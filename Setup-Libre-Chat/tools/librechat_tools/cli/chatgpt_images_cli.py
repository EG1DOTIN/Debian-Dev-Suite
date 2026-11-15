"""
CLI interface for ChatGPT Image Restorer & Linker.
Part of the Debian Dev Suite.
"""

import os
import json
import argparse
from pathlib import Path

from ..common.colors import (
    BOLD, RESET, print_header, print_pass, print_info, print_warn, print_fail
)
from ..common.paths import get_librechat_images_dir
from ..media.asset_linker import extract_images_from_zip, extract_images_from_dir, find_matching_file
from ..storage.mongo_client import (
    get_all_target_messages, get_resolved_messages, get_all_base64_messages,
    link_mongodb_messages, JSON_BLOCK_PATTERN, ASSET_ID_PATTERN, CLEAN_PLACEHOLDER_PATTERN
)

DEFAULT_IMAGES_DIR = get_librechat_images_dir()


def show_status(images_dir: Path) -> None:
    """Print status report on unresolved pointers and images on disk."""
    print_header("LibreChat Attached Image Status Audit")

    if images_dir.is_dir():
        all_files_on_disk = []
        for root, _, fnames in os.walk(images_dir):
            for fn in fnames:
                if not fn.startswith("."):
                    all_files_on_disk.append(fn)
        img_files = [f for f in all_files_on_disk if f.lower().endswith((".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg")) or f.startswith(("file-", "file_"))]
        print_pass(f"Images Directory: {images_dir}")
        print_info(f"Total Files on Disk: {len(all_files_on_disk):,} (Image Assets: {len(img_files):,})")
    else:
        print_warn(f"Images directory does not exist yet: {images_dir}")
        all_files_on_disk = []

    target_msgs = get_all_target_messages()
    resolved_msgs = get_resolved_messages()
    base64_msgs = get_all_base64_messages()

    print_pass(f"Messages with resolved Markdown images : {len(resolved_msgs):,}")
    print_info(f"Messages with raw JSON asset pointers : {len(target_msgs):,}")
    if base64_msgs:
        print_warn(f"Messages with raw Base64 data URIs   : {len(base64_msgs):,} (Needs linking to static /images/)")
    else:
        print_pass("Messages with raw Base64 data URIs   : 0 (All static /images/)")

    if target_msgs:
        missing_ids = set()
        resolvable_ids = set()
        for msg in target_msgs:
            text = msg.get("text", "")
            for match in JSON_BLOCK_PATTERN.finditer(text):
                m = ASSET_ID_PATTERN.search(match.group(0))
                if m:
                    aid = m.group(1).strip()
                    if find_matching_file(aid, all_files_on_disk):
                        resolvable_ids.add(aid)
                    else:
                        missing_ids.add(aid)
            for ph in CLEAN_PLACEHOLDER_PATTERN.finditer(text):
                aid = ph.group(1).strip()
                if not find_matching_file(aid, all_files_on_disk):
                    missing_ids.add(aid)

        print()
        print_warn(f"{len(target_msgs)} messages still have raw JSON pointer blocks!")
        if resolvable_ids:
            print_pass(f"Ready to Link: {len(resolvable_ids)} asset(s) found on disk (run 'python3 fix-chatgpt-images.py --link-db')")
        if missing_ids:
            print_info(f"Missing from Disk: {len(missing_ids)} unique asset(s) not found in images directory")
            print("      Sample missing asset IDs:")
            for mid in list(missing_ids)[:6]:
                print(f"       - {mid}")
            if len(missing_ids) > 6:
                print(f"       ... and {len(missing_ids) - 6} more.")

        print()
        print(f"{BOLD}RECOMMENDED NEXT STEPS:{RESET}")
        print(f"  1. Link images already placed in the images folder:")
        print(f"     {BOLD}python3 fix-chatgpt-images.py --link-db{RESET}")
        print(f"  2. Or extract images directly from an export ZIP:")
        print(f"     {BOLD}python3 fix-chatgpt-images.py --from-zip ~/Downloads/chatgpt_export.zip{RESET}")
        print(f"  3. Or convert missing assets into clean Markdown notes:")
        print(f"     {BOLD}python3 fix-chatgpt-images.py --clean-placeholders{RESET}")
    elif base64_msgs:
        print()
        print_warn(f"{len(base64_msgs)} Gemini message(s) contain raw embedded Base64 images instead of static files!")
        print(f"{BOLD}RECOMMENDED NEXT STEP:{RESET}")
        print(f"  Run '{BOLD}python3 fix-chatgpt-images.py --link-db{RESET}' to link them to static /images/")
    print()


def prepare_conversations_json(input_json: Path, output_json: Path, images_dir: Path) -> int:
    """Pre-processes raw ChatGPT conversations.json before importing to LibreChat."""
    if not input_json.is_file():
        print_fail(f"Input file not found: {input_json}")
        return 0

    print_info(f"Loading conversations from: {input_json}")
    with open(input_json, "r", encoding="utf-8") as f:
        data = json.load(f)

    files_on_disk = os.listdir(images_dir) if images_dir.is_dir() else []
    replaced_count = 0

    def patch_node(node):
        nonlocal replaced_count
        if not isinstance(node, dict):
            return
        msg = node.get("message")
        if isinstance(msg, dict):
            content = msg.get("content")
            if isinstance(content, dict):
                parts = content.get("parts")
                if isinstance(parts, list):
                    new_parts = []
                    for p in parts:
                        if isinstance(p, dict) and p.get("content_type") == "image_asset_pointer":
                            asset_pointer = p.get("asset_pointer", "")
                            asset_id = asset_pointer.replace("file-service://", "").replace("sediment://", "").strip()
                            matched = find_matching_file(asset_id, files_on_disk)
                            if matched:
                                thumb_md = f"\n\n[![Attached Image: {matched}](/images/{matched})](/images/{matched})\n\n"
                                new_parts.append(thumb_md)
                                replaced_count += 1
                            else:
                                new_parts.append(f"\n> 📷 **Attached Image:** `{asset_id}`\n")
                                replaced_count += 1
                        elif isinstance(p, str):
                            new_p = p
                            for match in JSON_BLOCK_PATTERN.finditer(p):
                                block = match.group(0)
                                asset_m = ASSET_ID_PATTERN.search(block)
                                if asset_m:
                                    asset_id = asset_m.group(1).strip()
                                    matched = find_matching_file(asset_id, files_on_disk)
                                    if matched:
                                        thumb_md = f"\n\n[![Attached Image: {matched}](/images/{matched})](/images/{matched})\n\n"
                                        new_p = new_p.replace(block, thumb_md)
                                        replaced_count += 1
                            new_parts.append(new_p)
                        else:
                            new_parts.append(p)
                    content["parts"] = new_parts

    items = data if isinstance(data, list) else [data]
    for item in items:
        if isinstance(item, dict) and "mapping" in item:
            mapping = item["mapping"]
            if isinstance(mapping, dict):
                for node_id, node in mapping.items():
                    patch_node(node)

    with open(output_json, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print_pass(f"Pre-processed JSON written to: {output_json} ({replaced_count} image pointer(s) converted)")
    return replaced_count


def main(args_list=None):
    parser = argparse.ArgumentParser(
        description="ChatGPT Image Restorer & Linker for LibreChat (Debian Dev Suite).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Command Examples:
  # 1. Audit status of images and messages:
  python3 fix-chatgpt-images.py --status

  # 2. Extract and link images directly from ChatGPT export .zip:
  python3 fix-chatgpt-images.py --from-zip ~/Downloads/chatgpt_export.zip

  # 3. Copy and link images from an unzipped folder:
  python3 fix-chatgpt-images.py --from-dir ~/Downloads/chatgpt_extracted/

  # 4. Scan MongoDB and link image files already in the images directory:
  python3 fix-chatgpt-images.py --link-db

  # 5. Clean up unresolved JSON asset blocks into clean Markdown notes:
  python3 fix-chatgpt-images.py --clean-placeholders

  # 6. Pre-process conversations.json before importing via LibreChat UI:
  python3 fix-chatgpt-images.py --prepare-file conversations.json -o conversations_fixed.json

  # 7. Preview actions without writing to database or disk:
  python3 fix-chatgpt-images.py --link-db --dry-run
        """
    )

    parser.add_argument("--status", action="store_true", help="Show audit dashboard of images and messages in MongoDB")
    parser.add_argument("--from-zip", type=Path, help="Extract images from a ChatGPT export .zip and link them in MongoDB")
    parser.add_argument("--from-dir", type=Path, help="Copy images from an unzipped ChatGPT export folder and link them in MongoDB")
    parser.add_argument("--link-db", "--scan-mongo", dest="link_db", action="store_true", help="Scan MongoDB and link image files on disk to chat messages")
    parser.add_argument("--clean-placeholders", "--clean-missing", dest="clean_placeholders", action="store_true", help="Convert unresolved JSON pointer blocks into clean Markdown notes")
    parser.add_argument("--prepare-file", "--prepare", dest="prepare_file", type=Path, help="Pre-process ChatGPT conversations.json before importing into LibreChat")
    parser.add_argument("-o", "--output", type=Path, help="Output path for prepared JSON (used with --prepare-file)")
    parser.add_argument("--images-dir", type=Path, default=DEFAULT_IMAGES_DIR, help=f"Custom LibreChat images directory (default: {DEFAULT_IMAGES_DIR})")
    parser.add_argument("--dry-run", action="store_true", help="Preview actions without modifying database or files")
    parser.add_argument("-y", "--yes", action="store_true", help="Skip interactive prompts")

    args = parser.parse_args(args_list)

    # Default action if no arguments provided
    if not any([args.status, args.from_zip, args.from_dir, args.link_db, args.clean_placeholders, args.prepare_file]):
        show_status(args.images_dir)
        return

    if args.status:
        show_status(args.images_dir)
        return

    # Mode 1: Pre-process export file before import
    if args.prepare_file:
        print_header("Pre-processing conversations.json")
        out_path = args.output or args.prepare_file.with_name(f"{args.prepare_file.stem}_with_images.json")
        prepare_conversations_json(args.prepare_file, out_path, args.images_dir)
        return

    # Mode 2: Extract from ZIP archive
    if args.from_zip:
        print_header("Extracting Images from Archive")
        count = extract_images_from_zip(args.from_zip, args.images_dir, dry_run=args.dry_run)
        print_pass(f"Extracted {count} asset(s) to: {args.images_dir}")
        print_info("Linking messages in MongoDB...")
        resolved, placeholders, missing = link_mongodb_messages(
            args.images_dir,
            clean_placeholders=args.clean_placeholders,
            dry_run=args.dry_run
        )
        print_pass(f"Done. Resolved {resolved} images in chat messages.")
        if placeholders:
            print_info(f"Cleaned {placeholders} placeholder(s) into Markdown notes.")
        if missing:
            print_warn(f"Assets still missing on disk: {len(set(missing))}")
        return

    # Mode 3: Copy from Directory
    if args.from_dir:
        print_header("Copying Images from Directory")
        count = extract_images_from_dir(args.from_dir, args.images_dir, dry_run=args.dry_run)
        print_pass(f"Copied {count} asset(s) to: {args.images_dir}")
        print_info("Linking messages in MongoDB...")
        resolved, placeholders, missing = link_mongodb_messages(
            args.images_dir,
            clean_placeholders=args.clean_placeholders,
            dry_run=args.dry_run
        )
        print_pass(f"Done. Resolved {resolved} images in chat messages.")
        if placeholders:
            print_info(f"Cleaned {placeholders} placeholder(s) into Markdown notes.")
        if missing:
            print_warn(f"Assets still missing on disk: {len(set(missing))}")
        return

    # Mode 4: Link DB / Clean Placeholders
    if args.link_db or args.clean_placeholders:
        print_header("Scanning MongoDB for Image Pointers")
        resolved, placeholders, missing = link_mongodb_messages(
            args.images_dir,
            clean_placeholders=args.clean_placeholders,
            dry_run=args.dry_run
        )
        print_pass("Database scan complete:")
        print(f"  - Resolved images: {resolved}")
        if args.clean_placeholders:
            print(f"  - Cleaned placeholders: {placeholders}")
        if missing:
            print_warn(f"Assets still missing on disk: {len(set(missing))}")
        return


if __name__ == "__main__":
    main()
