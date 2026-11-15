"""
MongoDB Driver & Query Interface for LibreChat.
Communicates with `librechat_mongodb` container using `mongosh`.
Part of the Debian Dev Suite (100% Localhost Isolated).
"""

import os
import re
import json
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from ..common.colors import (
    BOLD, RESET, print_pass, print_info, print_warn, print_fail, print_header
)
from ..media.asset_linker import find_matching_file, save_base64_data_to_file, normalize_and_index_images
from ..media.image_encoder import guess_image_extension

# Defaults
MONGO_CONTAINER = "librechat_mongodb"
MONGO_DB = "LibreChat"

JSON_BLOCK_PATTERN = re.compile(r"```(?:json)?\s*\{[\s\S]*?\"image_asset_pointer\"[\s\S]*?\}\s*```")
CLEAN_PLACEHOLDER_PATTERN = re.compile(r"> 📷 \*\*Attached Image:\*\* `(file-[a-zA-Z0-9]+|file_[a-zA-Z0-9]+)`[^\n]*\n?")
ASSET_ID_PATTERN = re.compile(r"\"asset_pointer\":\s*\"(?:file-service://|sediment://)?([^\"#]+)")
BASE64_MD_PATTERN = re.compile(
    r"\[!\[(.*?)\]\((data:image/[a-zA-Z0-9+.-]+;base64,[A-Za-z0-9+/=]{20,})\)\]\((?:data:image/[a-zA-Z0-9+.-]+;base64,[A-Za-z0-9+/=]{20,}|[^\)]+)\)|!\[(.*?)\]\((data:image/[a-zA-Z0-9+.-]+;base64,[A-Za-z0-9+/=]{20,})\)"
)


def run_mongo_eval(js_code: str) -> Tuple[bool, str]:
    """Execute a JavaScript command in MongoDB via docker exec mongosh."""
    cmd = [
        "docker", "exec", MONGO_CONTAINER,
        "mongosh", "--quiet", MONGO_DB,
        "--eval", js_code
    ]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        return True, res.stdout.strip()
    except subprocess.CalledProcessError as e:
        return False, e.stderr.strip()
    except Exception as e:
        return False, str(e)


def query_mongodb(js_script: str) -> Optional[Any]:
    """Execute a JavaScript query against MongoDB and parse JSON output."""
    cmd = [
        "docker", "exec", MONGO_CONTAINER,
        "mongosh", "--quiet", MONGO_DB,
        "--eval", js_script
    ]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        out = proc.stdout.strip()
        if not out:
            return None
        return json.loads(out)
    except Exception:
        return None


def get_all_target_messages() -> List[Dict[str, Any]]:
    """Fetch all messages from MongoDB that contain unresolved image asset pointers."""
    js = """
    (function() {
        var cursor = db.messages.find(
            { text: { $regex: 'image_asset_pointer' } },
            { messageId: 1, conversationId: 1, text: 1 }
        );
        return JSON.stringify(cursor.toArray());
    })()
    """
    res = query_mongodb(js)
    return res if isinstance(res, list) else []


def get_resolved_messages() -> List[Dict[str, Any]]:
    """Fetch all messages that contain linked Markdown image thumbnails."""
    js = r"""
    (function() {
        var cursor = db.messages.find(
            { text: { $regex: /\[!\[.*?\]\(\/images\// } },
            { messageId: 1, conversationId: 1, text: 1 }
        );
        return JSON.stringify(cursor.toArray());
    })()
    """
    res = query_mongodb(js)
    return res if isinstance(res, list) else []


def get_all_base64_messages() -> List[Dict[str, Any]]:
    """Fetch all messages from MongoDB that contain embedded Base64 image data URIs."""
    js = """
    (function() {
        var cursor = db.messages.find(
            { text: { $regex: 'data:image/[a-zA-Z0-9+.-]+;base64,[A-Za-z0-9+/=]{20,}' } },
            { messageId: 1, conversationId: 1, text: 1 }
        );
        return JSON.stringify(cursor.toArray());
    })()
    """
    res = query_mongodb(js)
    return res if isinstance(res, list) else []


def sanitize_mongodb_base64_images(images_dir: Path, dry_run: bool = False) -> Tuple[int, int]:
    """
    Scans MongoDB messages for embedded Base64 data URIs (e.g. from Gemini exports),
    extracts or matches them to files on disk in images_dir, and rewrites the messages
    into clean, lightweight Markdown links pointing to /images/<filename>.
    Deduplicates identical images referenced multiple times in the same turn.
    Returns: (updated_messages_count, images_extracted_count)
    """
    messages = get_all_base64_messages()
    if not messages:
        return 0, 0

    files_on_disk = [f for f in os.listdir(images_dir) if not f.startswith(".")] if images_dir.is_dir() else []
    updated_count = 0
    images_extracted = 0

    for msg in messages:
        msg_id = msg.get("messageId")
        orig_text = msg.get("text", "")
        if not msg_id or not orig_text:
            continue

        matches = list(BASE64_MD_PATTERN.finditer(orig_text))
        if not matches:
            continue

        seen_stems = set()
        new_text = orig_text

        # Process replacements from end to start to preserve slice offsets
        for match in reversed(matches):
            alt = match.group(1) or match.group(3) or "Attached Image"
            b64_uri = match.group(2) or match.group(4)
            clean_alt = alt.replace("Attached Image:", "").strip()
            stem = Path(clean_alt).stem.split("-")[0]

            if stem in seen_stems:
                new_text = new_text[:match.start()] + "" + new_text[match.end():]
            else:
                seen_stems.add(stem)
                disk_matches = [f for f in files_on_disk if f.startswith(stem) or stem in f]
                if disk_matches:
                    matched_file = disk_matches[0]
                else:
                    saved_file = save_base64_data_to_file(b64_uri, images_dir, preferred_filename=clean_alt)
                    matched_file = saved_file or f"{stem}.png"
                    files_on_disk.append(matched_file)
                    images_extracted += 1

                replacement = f"\n\n[![Attached Image: {matched_file}](/images/{matched_file})](/images/{matched_file})\n\n"
                new_text = new_text[:match.start()] + replacement + new_text[match.end():]

        new_text = re.sub(r"\n{3,}", "\n\n", new_text).strip()

        if new_text != orig_text:
            if not dry_run:
                js_update = f"""
                db.messages.updateOne(
                    {{ messageId: {json.dumps(msg_id)} }},
                    {{ $set: {{ text: {json.dumps(new_text)} }} }}
                );
                """
                success, _ = run_mongo_eval(js_update)
                if success:
                    updated_count += 1
            else:
                updated_count += 1

    return updated_count, images_extracted


def link_mongodb_messages(images_dir: Path, clean_placeholders: bool = False, clean_missing: bool = False, dry_run: bool = False) -> Tuple[int, int, List[str]]:
    """
    Scans MongoDB messages for raw `image_asset_pointer` blocks and embedded Base64
    images (e.g. from Gemini exports), matches them with files on disk in images_dir,
    and rewrites them into clickable Markdown image thumbnails.
    """
    if dry_run and images_dir.is_dir():
        simulated_files = set()
        for root, _, files in os.walk(images_dir):
            for f in files:
                if f.startswith("."):
                    continue
                fpath = Path(root) / f
                simulated_files.add(f)
                try:
                    with open(fpath, "rb") as fp:
                        header = fp.read(16)
                    ext = guess_image_extension(header)
                    if ext and (fpath.suffix.lower() == ".dat" or not fpath.suffix):
                        target_name = f"{fpath.stem}{ext}" if fpath.suffix else f"{fpath.name}{ext}"
                        simulated_files.add(target_name)
                except Exception:
                    pass
        files_on_disk = list(simulated_files)
    else:
        if images_dir.is_dir():
            renamed, hardlinked = normalize_and_index_images(images_dir)
            if renamed > 0 or hardlinked > 0:
                print_info(f"Auto-normalized {renamed} file extension(s) and indexed {hardlinked} subfolder image(s).")
        files_on_disk = [f for f in os.listdir(images_dir) if not f.startswith(".")] if images_dir.is_dir() else []
    updated_count = 0
    cleaned_count = 0
    missing_assets: List[str] = []
    should_clean = clean_placeholders or clean_missing

    # 1. Resolve raw ChatGPT image asset pointers
    messages = get_all_target_messages()
    for msg in messages:
        msg_id = msg.get("messageId")
        orig_text = msg.get("text", "")
        if not msg_id or not orig_text:
            continue

        new_text = orig_text
        modified = False

        for match in JSON_BLOCK_PATTERN.finditer(orig_text):
            block = match.group(0)
            asset_m = ASSET_ID_PATTERN.search(block)
            if not asset_m:
                continue

            asset_id = asset_m.group(1).strip()
            matched_file = find_matching_file(asset_id, files_on_disk)

            if matched_file:
                thumb_md = f"\n\n[![Attached Image: {matched_file}](/images/{matched_file})](/images/{matched_file})\n\n"
                new_text = new_text.replace(block, thumb_md)
                modified = True
            else:
                missing_assets.append(asset_id)
                if should_clean:
                    note_md = f"\n> 📷 **Attached Image:** `{asset_id}` *(File missing from archive)*\n"
                    new_text = new_text.replace(block, note_md)
                    modified = True
                    cleaned_count += 1

        if modified and new_text != orig_text:
            if not dry_run:
                js_update = f"""
                db.messages.updateOne(
                    {{ messageId: {json.dumps(msg_id)} }},
                    {{ $set: {{ text: {json.dumps(new_text)} }} }}
                );
                """
                success, _ = run_mongo_eval(js_update)
                if success:
                    updated_count += 1
            else:
                updated_count += 1

    # 2. Resolve Gemini Base64 embedded images
    b64_updated, b64_extracted = sanitize_mongodb_base64_images(images_dir, dry_run=dry_run)
    updated_count += b64_updated

    return updated_count, cleaned_count, missing_assets


def list_database_summary() -> None:
    """Prints a detailed summary of LibreChat database, folders, tags, unassigned chats, and recent activity."""
    js = """
    (function() {
        var total = db.conversations.countDocuments();
        var totalMsgs = db.messages.countDocuments();

        var unassigned = db.conversations.countDocuments({
            $or: [
                { chatProjectId: null },
                { chatProjectId: { $exists: false } },
                { chatProjectId: "" },
                { project: null },
                { project: { $exists: false } },
                { project: "" }
            ]
        });

        var untagged = db.conversations.countDocuments({
            $or: [
                { tags: { $exists: false } },
                { tags: null },
                { tags: [] }
            ]
        });

        var chatProjects = db.chatprojects ? db.chatprojects.find().toArray() : [];
        var legacyProjects = db.projects ? db.projects.find().toArray() : [];
        var allProjects = chatProjects.concat(legacyProjects);

        var seen = {};
        var folders = [];
        for (var i = 0; i < allProjects.length; i++) {
            var p = allProjects[i];
            if (!p || seen[p.name]) continue;
            seen[p.name] = true;
            var pId = p._id.toString();
            var count = db.conversations.countDocuments({
                $or: [
                    { chatProjectId: pId },
                    { chatProjectId: p._id },
                    { project: pId }
                ]
            });
            var lastDt = "n/a";
            if (p.lastConversationAt) {
                try {
                    lastDt = (typeof p.lastConversationAt === "string") ?
                             p.lastConversationAt.substring(0, 10) :
                             p.lastConversationAt.toISOString().substring(0, 10);
                } catch(e) {
                    lastDt = String(p.lastConversationAt).substring(0, 10);
                }
            }
            folders.push({ name: p.name, count: count, id: pId, lastActive: lastDt });
        }

        var tagsWithCount = [];
        if (db.conversationtags) {
            try {
                db.conversationtags.updateMany(
                    { user: { $type: "objectId" } },
                    [{ $set: { user: { $toString: "$user" } } }]
                );
            } catch(e) {}
            var convTags = db.conversationtags.find().sort({ count: -1 }).toArray();
            for (var j = 0; j < convTags.length; j++) {
                tagsWithCount.push({ tag: convTags[j].tag, count: convTags[j].count });
            }
        }
        if (tagsWithCount.length === 0) {
            var rawTags = db.conversations.distinct('tags');
            for (var k = 0; k < rawTags.length; k++) {
                var t = rawTags[k];
                if (!t) continue;
                var tCount = db.conversations.countDocuments({ tags: t });
                tagsWithCount.push({ tag: t, count: tCount });
            }
        }

        var sample = db.conversations.find({}, { title: 1, tags: 1, chatProjectId: 1, project: 1 })
            .sort({ updatedAt: -1, _id: -1 })
            .limit(6)
            .toArray();

        return JSON.stringify({
            total: total,
            totalMsgs: totalMsgs,
            unassigned: unassigned,
            untagged: untagged,
            folders: folders,
            tags: tagsWithCount,
            sample: sample
        });
    })()
    """
    res = query_mongodb(js)
    if not res:
        print_fail("Failed to retrieve database summary. Is MongoDB running?")
        return

    print_header("LibreChat Local Conversations & Folder Status")
    print_info(f"Total Conversations in Database : {BOLD}{res.get('total', 0):,}{RESET}")
    print_info(f"Total Individual Messages       : {BOLD}{res.get('totalMsgs', 0):,}{RESET}")
    print_info(f"Root / Unassigned to Folders     : {BOLD}{res.get('unassigned', 0):,}{RESET}")
    print_info(f"Untagged Conversations          : {BOLD}{res.get('untagged', 0):,}{RESET}")

    folders = res.get("folders", [])
    print()
    print_info(f"Sidebar Project Folders ({len(folders)} total):")
    if folders:
        for f in folders:
            last_dt = f.get("lastActive", "n/a")
            print(f"    📁 {BOLD}{f['name']}{RESET} ({f['count']} chats, last active: {last_dt})")
    else:
        print("    (No sidebar project folders found)")

    tags = res.get("tags", [])
    print()
    print_info(f"Bookmark Tags ({len(tags)} total):")
    if tags:
        for t in tags:
            tag_name = t.get("tag", "") if isinstance(t, dict) else str(t)
            tag_count = f" ({t.get('count')} chats)" if isinstance(t, dict) and "count" in t else ""
            print(f"    🏷️  {tag_name}{tag_count}")
    else:
        print("    (No bookmark tags found)")

    sample = res.get("sample", [])
    if sample:
        print()
        print_info("Recent Conversations:")
        for s in sample:
            has_folder = bool(s.get("chatProjectId") or s.get("project"))
            p_str = "[in folder]" if has_folder else "[unassigned]"
            t_list = s.get("tags") or []
            t_str = f" [tag: {', '.join(t_list)}]" if t_list else ""
            title = s.get("title", "Untitled")
            print(f"    - {title} {p_str}{t_str}")
    print()


def get_folder_stats(folder_name: str) -> Tuple[int, int]:
    """Returns (conversation_count, message_count) for a given folder name or bookmark tag."""
    title_regex = json.dumps(r"^\[\s*" + re.escape(folder_name) + r"\s*\]")
    js = f"""
    (function() {{
        var name = {json.dumps(folder_name)};
        var cp = (db.chatprojects ? db.chatprojects.findOne({{ name: name }}) : null) ||
                 (db.projects ? db.projects.findOne({{ name: name }}) : null);
        var cpId = cp ? cp._id.toString() : null;
        var cpObjId = cp ? cp._id : null;

        var filter = {{
            $or: [
                cpId ? {{ chatProjectId: cpId }} : null,
                cpObjId ? {{ chatProjectId: cpObjId }} : null,
                cpId ? {{ project: cpId }} : null,
                {{ tags: name }},
                {{ title: {{ $regex: {title_regex}, $options: 'i' }} }}
            ].filter(Boolean)
        }};

        var convs = db.conversations.find(filter, {{ conversationId: 1 }}).toArray();
        var cIds = convs.map(function(c) {{ return c.conversationId; }});
        var msgCount = db.messages.countDocuments({{ conversationId: {{ $in: cIds }} }});
        return JSON.stringify({{ convCount: convs.length, msgCount: msgCount }});
    }})()
    """
    res = query_mongodb(js)
    if isinstance(res, dict):
        return res.get("convCount", 0), res.get("msgCount", 0)
    return 0, 0


def organize_conversations_into_folder(folder_name: str, match_pattern: Optional[str] = None, all_untagged: bool = False, prefix_title: bool = False) -> int:
    """Assigns conversations matching pattern or all untagged chats into a sidebar folder."""
    js_ensure_folder = f"""
    (function() {{
        var name = {json.dumps(folder_name)};
        var cp = (db.chatprojects ? db.chatprojects.findOne({{ name: name }}) : null) ||
                 (db.projects ? db.projects.findOne({{ name: name }}) : null);
        if (cp) return cp._id.toString();

        var u = db.users.findOne();
        var uId = u ? u._id : null;
        var now = new Date();

        if (db.chatprojects) {{
            var res = db.chatprojects.insertOne({{
                name: name,
                description: "",
                user: uId,
                conversationCount: 0,
                lastConversationAt: null,
                lastConversationId: null,
                createdAt: now,
                updatedAt: now,
                __v: 0
            }});
            return res.insertedId.toString();
        }} else if (db.projects) {{
            var res2 = db.projects.insertOne({{
                name: name,
                user: uId,
                createdAt: now,
                updatedAt: now
            }});
            return res2.insertedId.toString();
        }}
        return "";
    }})()
    """
    success, p_id = run_mongo_eval(js_ensure_folder)
    if not success or not p_id:
        print_fail(f"Could not create/find project folder: {folder_name}")
        return 0

    p_id_clean = p_id.strip('"').strip("'")

    conditions = []
    if all_untagged:
        conditions.append("""{
            $or: [
                { chatProjectId: { $exists: false } },
                { chatProjectId: null },
                { chatProjectId: '' },
                { project: { $exists: false } },
                { project: null },
                { project: '' },
                { tags: { $exists: false } },
                { tags: null },
                { tags: [] }
            ]
        }""")
    if match_pattern:
        conditions.append(f"{{ title: {{ $regex: {json.dumps(match_pattern)}, $options: 'i' }} }}")

    if not conditions:
        print_warn("Neither --all-untagged nor --match pattern specified.")
        return 0

    if len(conditions) > 1:
        query_filter = f"{{ $and: [{', '.join(conditions)}] }}"
    else:
        query_filter = conditions[0]

    prefix_js = ""
    if prefix_title:
        escaped_prefix = f"[{folder_name}] "
        prefix_js = f"""
        var convsToPrefix = db.conversations.find(filter).toArray();
        convsToPrefix.forEach(function(c) {{
            var currentTitle = c.title || 'Untitled';
            if (!currentTitle.startsWith({json.dumps(escaped_prefix)})) {{
                db.conversations.updateOne(
                    {{ conversationId: c.conversationId }},
                    {{ $set: {{ title: {json.dumps(escaped_prefix)} + currentTitle }} }}
                );
            }}
        }});
        """

    js_update = f"""
    (function() {{
        var filter = {query_filter};
        var pId = {json.dumps(p_id_clean)};
        var name = {json.dumps(folder_name)};

        var update = {{
            $set: {{
                chatProjectId: pId,
                project: pId
            }},
            $addToSet: {{
                tags: name
            }}
        }};
        var res = db.conversations.updateMany(filter, update);

        {prefix_js}

        // Update project conversationCount
        var totalInFolder = db.conversations.countDocuments({{
            $or: [{{ chatProjectId: pId }}, {{ project: pId }}]
        }});

        if (db.chatprojects) {{
            try {{
                db.chatprojects.updateOne(
                    {{ _id: ObjectId(pId) }},
                    {{ $set: {{ conversationCount: totalInFolder, updatedAt: new Date() }} }}
                );
            }} catch(e) {{
                db.chatprojects.updateOne(
                    {{ name: name }},
                    {{ $set: {{ conversationCount: totalInFolder, updatedAt: new Date() }} }}
                );
            }}
        }}

        // Update conversationtags collection for UI bookmark chip
        if (db.conversationtags) {{
            try {{
                db.conversationtags.updateMany(
                    {{ user: {{ $type: "objectId" }} }},
                    [{{ $set: {{ user: {{ $toString: "$user" }} }} }}]
                );
            }} catch(e) {{}}
            var u = db.users.findOne();
            var uId = u && u._id ? u._id.toString() : null;
            if (uId) {{
                db.conversationtags.updateOne(
                    {{ tag: name, user: uId }},
                    {{ $set: {{ tag: name, user: uId, count: totalInFolder, position: 0, updatedAt: new Date() }} }},
                    {{ upsert: true }}
                );
            }}
        }}

        return res.modifiedCount;
    }})()
    """
    ok, count_str = run_mongo_eval(js_update)
    count = int(count_str) if ok and count_str.isdigit() else 0
    return count


def remove_folder_from_database(folder_name: str) -> bool:
    """Removes a folder shell from database and unassigns all associated chats."""
    js = f"""
    (function() {{
        var name = {json.dumps(folder_name)};
        var cp = (db.chatprojects ? db.chatprojects.findOne({{ name: name }}) : null) ||
                 (db.projects ? db.projects.findOne({{ name: name }}) : null);
        if (!cp) return false;
        var pId = cp._id.toString();

        db.conversations.updateMany(
            {{
                $or: [
                    {{ chatProjectId: pId }},
                    {{ chatProjectId: cp._id }},
                    {{ project: pId }}
                ]
            }},
            {{
                $unset: {{
                    chatProjectId: "",
                    project: ""
                }}
            }}
        );

        if (db.chatprojects) db.chatprojects.deleteMany({{ name: name }});
        if (db.projects) db.projects.deleteMany({{ name: name }});
        return true;
    }})()
    """
    ok, res = run_mongo_eval(js)
    return ok and "true" in res.lower()


def delete_folder_chats(folder_name: str, keep_folder_shell: bool = False) -> Tuple[int, int]:
    """Permanently deletes all conversation records and messages in a given folder."""
    title_regex = json.dumps(r"^\[\s*" + re.escape(folder_name) + r"\s*\]")
    js = f"""
    (function() {{
        var name = {json.dumps(folder_name)};
        var keepShell = {json.dumps(keep_folder_shell)};

        var cp = (db.chatprojects ? db.chatprojects.findOne({{ name: name }}) : null) ||
                 (db.projects ? db.projects.findOne({{ name: name }}) : null);
        var cpId = cp ? cp._id.toString() : null;
        var cpObjId = cp ? cp._id : null;

        var filter = {{
            $or: [
                cpId ? {{ chatProjectId: cpId }} : null,
                cpObjId ? {{ chatProjectId: cpObjId }} : null,
                cpId ? {{ project: cpId }} : null,
                {{ tags: name }},
                {{ title: {{ $regex: {title_regex}, $options: 'i' }} }}
            ].filter(Boolean)
        }};

        var convs = db.conversations.find(filter, {{ conversationId: 1 }}).toArray();
        var cIds = convs.map(function(c) {{ return c.conversationId; }});
        var msgRes = {{ deletedCount: 0 }};
        var convRes = {{ deletedCount: 0 }};

        if (cIds.length > 0) {{
            msgRes = db.messages.deleteMany({{ conversationId: {{ $in: cIds }} }});
            convRes = db.conversations.deleteMany({{ conversationId: {{ $in: cIds }} }});
        }}

        // Clean up bookmark tags across database
        db.conversations.updateMany({{}}, {{ $pull: {{ tags: name }} }});
        if (db.conversationtags) {{
            db.conversationtags.deleteMany({{ tag: name }});
        }}

        if (keepShell) {{
            // Reset counters on folder shell
            if (db.chatprojects) {{
                db.chatprojects.updateMany(
                    {{ name: name }},
                    {{ $set: {{ conversationCount: 0, lastConversationAt: null, lastConversationId: null, updatedAt: new Date() }} }}
                );
            }}
            if (db.projects) {{
                db.projects.updateMany(
                    {{ name: name }},
                    {{ $set: {{ conversationCount: 0, updatedAt: new Date() }} }}
                );
            }}
        }} else {{
            // Permanently remove folder shell
            if (db.chatprojects) db.chatprojects.deleteMany({{ name: name }});
            if (db.projects) db.projects.deleteMany({{ name: name }});
        }}

        return JSON.stringify({{ deletedConvs: convRes.deletedCount, deletedMsgs: msgRes.deletedCount }});
    }})()
    """
    res = query_mongodb(js)
    if isinstance(res, dict):
        return res.get("deletedConvs", 0), res.get("deletedMsgs", 0)
    return 0, 0


def search_and_bookmark(query: str, folder_scope: Optional[str] = None, tag_name: Optional[str] = None) -> Dict[str, Any]:
    """Performs instant offline regex message search and tags matching conversations with a bookmark."""
    tag = tag_name or f"🔍 {query}"
    try:
        re.compile(query)
        regex_query = query
    except re.error:
        regex_query = re.escape(query)

    scope_cond = ""
    if folder_scope:
        scope_title_regex = json.dumps(r"^\[\s*" + re.escape(folder_scope) + r"\s*\]")
        scope_cond = f"""
        var scopeName = {json.dumps(folder_scope)};
        var cp = (db.chatprojects ? db.chatprojects.findOne({{ name: scopeName }}) : null) ||
                 (db.projects ? db.projects.findOne({{ name: scopeName }}) : null);
        var cpId = cp ? cp._id.toString() : null;
        var cpObjId = cp ? cp._id : null;
        scopeOr = [
            cpId ? {{ chatProjectId: cpId }} : null,
            cpObjId ? {{ chatProjectId: cpObjId }} : null,
            cpId ? {{ project: cpId }} : null,
            {{ tags: scopeName }},
            {{ title: {{ $regex: {scope_title_regex}, $options: 'i' }} }}
        ].filter(Boolean);
        """

    js = f"""
    (function() {{
        // Normalize any legacy ObjectId users to String in conversationtags
        if (db.conversationtags) {{
            try {{
                db.conversationtags.updateMany(
                    {{ user: {{ $type: "objectId" }} }},
                    [{{ $set: {{ user: {{ $toString: "$user" }} }} }}]
                );
            }} catch(e) {{}}
        }}

        var convFilter = {{}};
        var scopeOr = null;
        {scope_cond}

        var msgCursor = db.messages.find({{ text: {{ $regex: {json.dumps(regex_query)}, $options: 'i' }} }}, {{ conversationId: 1 }});
        var cIdMap = {{}};
        msgCursor.forEach(function(m) {{ if (m.conversationId) cIdMap[m.conversationId] = true; }});
        var cIds = Object.keys(cIdMap);

        var matchOr = [
            {{ conversationId: {{ $in: cIds }} }},
            {{ title: {{ $regex: {json.dumps(regex_query)}, $options: 'i' }} }}
        ];

        if (scopeOr && scopeOr.length > 0) {{
            convFilter.$and = [
                {{ $or: scopeOr }},
                {{ $or: matchOr }}
            ];
        }} else {{
            convFilter.$or = matchOr;
        }}

        var sample = db.conversations.find(convFilter, {{ title: 1, user: 1 }})
            .sort({{ updatedAt: -1, _id: -1 }})
            .limit(8)
            .toArray();

        var res = db.conversations.updateMany(convFilter, {{ $addToSet: {{ tags: {json.dumps(tag)} }} }});
        var totalMatched = (typeof res.matchedCount === "number") ? res.matchedCount : db.conversations.countDocuments(convFilter);
        var modifiedCount = (typeof res.modifiedCount === "number") ? res.modifiedCount : 0;

        // Update conversationtags for UI chip (ensuring user is String so LibreChat UI can query it)
        if (db.conversationtags && totalMatched > 0) {{
            var totalWithTag = db.conversations.countDocuments({{ tags: {json.dumps(tag)} }});
            var u = db.users.findOne();
            var uId = (sample.length > 0 && sample[0].user) ? String(sample[0].user) : (u && u._id ? u._id.toString() : null);
            if (uId) {{
                db.conversationtags.updateOne(
                    {{ tag: {json.dumps(tag)}, user: uId }},
                    {{ $set: {{ tag: {json.dumps(tag)}, user: uId, count: totalWithTag, position: 0, updatedAt: new Date() }} }},
                    {{ upsert: true }}
                );
            }}
        }}

        return JSON.stringify({{
            matched: totalMatched,
            modified: modifiedCount,
            tagName: {json.dumps(tag)},
            sample: sample.map(function(s) {{ return s.title || "Untitled"; }})
        }});
    }})()
    """
    res = query_mongodb(js)
    if isinstance(res, dict):
        return res
    return {"matched": 0, "modified": 0, "tagName": tag, "sample": []}


def clear_search_bookmarks(specific_tag: Optional[str] = None) -> Tuple[int, List[str]]:
    """Removes search bookmark tags from MongoDB (all starting with '🔍' / 'temp-', or a specific tag)."""
    spec_tag_json = json.dumps(specific_tag.strip()) if specific_tag else "null"
    js = f"""
    (function() {{
        var specific = {spec_tag_json};
        var tagFilter = specific ? {{ tag: specific }} : {{ tag: /^🔍|^temp-/ }};

        var tagsToRemove = [];
        if (db.conversationtags) {{
            var convTags = db.conversationtags.find(tagFilter).toArray();
            tagsToRemove = convTags.map(function(t) {{ return t.tag; }});
        }}

        if (specific && tagsToRemove.length === 0) {{
            tagsToRemove = [specific];
        }}

        if (tagsToRemove.length === 0) {{
            var rawTags = db.conversations.distinct('tags');
            tagsToRemove = rawTags.filter(function(t) {{ return t && (t.startsWith('🔍') || t.startsWith('temp-')); }});
        }}

        if (tagsToRemove.length === 0) {{
            return JSON.stringify({{ cleared: 0, tags: [] }});
        }}

        var res = db.conversations.updateMany(
            {{ tags: {{ $in: tagsToRemove }} }},
            {{ $pull: {{ tags: {{ $in: tagsToRemove }} }} }}
        );
        if (db.conversationtags) {{
            db.conversationtags.deleteMany({{ tag: {{ $in: tagsToRemove }} }});
        }}

        return JSON.stringify({{ cleared: res.modifiedCount, tags: tagsToRemove }});
    }})()
    """
    res = query_mongodb(js)
    if isinstance(res, dict):
        return res.get("cleared", 0), res.get("tags", [])
    return 0, []
