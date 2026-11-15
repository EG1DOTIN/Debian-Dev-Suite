"""
CLI interface for LibreChat Batch Folder & Tag Organizer.
Part of the Debian Dev Suite.
"""

import sys
import json
import argparse
from typing import Optional
from pathlib import Path

from ..common.colors import (
    BOLD, RESET, print_header, print_pass, print_info, print_warn, print_fail
)
from ..storage.mongo_client import (
    list_database_summary, organize_conversations_into_folder,
    remove_folder_from_database, delete_folder_chats, get_folder_stats,
    search_and_bookmark, clear_search_bookmarks
)


def process_export_file(file_path: str, folder_name: str, output_path: Optional[str] = None) -> None:
    """Pre-prefixes conversation titles in a raw conversations.json file before import."""
    input_p = Path(file_path).expanduser().resolve()
    if not input_p.is_file():
        print_fail(f"File not found: {input_p}")
        sys.exit(1)

    print_info(f"Reading file: {input_p}")
    with open(input_p, "r", encoding="utf-8") as f:
        data = json.load(f)

    prefix = f"[{folder_name}] "
    count = 0

    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and "title" in item:
                orig = item["title"] or "Untitled"
                if not orig.startswith(prefix):
                    item["title"] = f"{prefix}{orig}"
                    count += 1
            elif isinstance(item, dict) and "name" in item:
                orig = item["name"] or "Untitled"
                if not orig.startswith(prefix):
                    item["name"] = f"{prefix}{orig}"
                    count += 1

    if output_path:
        out_path = Path(output_path).expanduser().resolve()
    else:
        out_name = f"{input_p.stem}_{folder_name}{input_p.suffix}"
        out_path = input_p.parent / out_name

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print_pass(f"Tagged {count} conversation(s) with prefix: '{prefix}'")
    print_pass(f"Saved ready-to-import file: {out_path}")


def main(args_list=None):
    parser = argparse.ArgumentParser(
        description="LibreChat Batch Folder, Tag & Search Organizer (Debian Dev Suite).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Mode 1: Search and temporary bookmarking (Fast Offline Search)
  python3 batch-folder-organizer.py --search "quantum"
  python3 batch-folder-organizer.py --search "python" --in-folder "Work"
  python3 batch-folder-organizer.py --search "docker" --bookmark "Docker-Chats"
  python3 batch-folder-organizer.py --clear-search

  # Mode 2: Pre-process export file before import
  python3 batch-folder-organizer.py --file conversations.json --folder "Work"

  # Mode 3: Direct MongoDB organization
  python3 batch-folder-organizer.py --list
  python3 batch-folder-organizer.py --folder "Personal" --all-untagged
  python3 batch-folder-organizer.py --folder "Work" --match "coding|python|client" --prefix-title
  python3 batch-folder-organizer.py --remove-folder "Work"

  # Destructive Deletion:
  python3 batch-folder-organizer.py --delete-folder "OldArchive" --yes
  python3 batch-folder-organizer.py --delete-chats "GEMINI-BYHOBBY" --keep-folder -y
        """
    )

    # Search & Temporary Bookmark Mode
    search_group = parser.add_argument_group("Search & Temporary Bookmark Tagging")
    search_group.add_argument("-s", "--search", type=str, help="Search keyword/topic across messages and titles")
    search_group.add_argument("--in-folder", type=str, help="Restrict search to a specific project folder (optional)")
    search_group.add_argument("--bookmark", type=str, help="Custom bookmark tag name for search results (default: '🔍 <query>')")
    search_group.add_argument("--clear-search", nargs="?", const="", default=None, help="Clear temporary search bookmarks from LibreChat (or specify tag)")

    # Pre-Import Mode
    file_group = parser.add_argument_group("Pre-Import File Preparation")
    file_group.add_argument("-f", "--file", type=str, help="Path to ChatGPT or Claude conversations.json file before importing")
    file_group.add_argument("-o", "--output", type=str, help="Custom output JSON path (pre-import mode only)")

    # Post-Import MongoDB Mode
    db_group = parser.add_argument_group("Post-Import Database Organization & Management")
    db_group.add_argument("-l", "--list", action="store_true", help="List current folders, bookmark tags, unassigned chats, and stats")
    db_group.add_argument("-F", "--folder", "--tag", dest="folder", type=str, help="Folder/Tag name to create or apply (creates Sidebar Project Folder + Tag)")
    db_group.add_argument("-u", "--all-untagged", action="store_true", help="Apply to all currently unassigned/untagged chats")
    db_group.add_argument("-m", "--match", type=str, help="Regex keyword pattern to match conversation titles")
    db_group.add_argument("-p", "--prefix-title", action="store_true", help="Also add [Folder] prefix to conversation titles in database")
    db_group.add_argument("--remove-folder", "--untag", dest="remove_folder", type=str, help="Remove folder shell (unassigns its chats back to root)")
    db_group.add_argument("--delete-folder", type=str, help="PERMANENTLY delete a folder AND all its conversations/messages")
    db_group.add_argument("--delete-chats", type=str, help="PERMANENTLY delete all chats in a folder but keep the empty folder shell")
    db_group.add_argument("--keep-folder", action="store_true", help="Keep the folder shell when deleting chats")
    db_group.add_argument("-y", "--yes", action="store_true", help="Skip confirmation prompt for destructive operations")

    args = parser.parse_args(args_list)

    if not any([args.list, args.search, args.clear_search is not None, args.file, args.folder, args.remove_folder, args.delete_folder, args.delete_chats]):
        list_database_summary()
        return

    if args.list:
        list_database_summary()
        return

    if args.search:
        scope_desc = f"inside project folder '{args.in_folder}'" if args.in_folder else "globally across ALL chats & messages"
        print_header(f"Searching Messages for: '{args.search}'")
        print_info(f"Searching for '{args.search}' {scope_desc}...")
        res = search_and_bookmark(args.search, folder_scope=args.in_folder, tag_name=args.bookmark)
        matched = res.get("matched", 0)
        modified = res.get("modified", 0)
        tag = res.get("tagName", args.bookmark or f"🔍 {args.search}")
        sample = res.get("sample", [])

        if matched == 0:
            print_warn(f"No conversations found matching '{args.search}'.")
            return

        print_pass(f"Found {BOLD}{matched}{RESET} matching conversation(s)!")
        if modified > 0:
            print_pass(f"Created temporary Bookmark Tag: {BOLD}{tag}{RESET} (tagged {modified} conversation(s))")
        else:
            print_pass(f"Active Bookmark Tag: {BOLD}{tag}{RESET} (all {matched} conversation(s) already tagged)")
        print()

        if sample:
            print_info("Top Matching Conversations:")
            for title in sample:
                print(f"    • {title}")
            if matched > len(sample):
                print(f"    ... and {matched - len(sample)} more")
            print()

        print_header("HOW TO VIEW IN LIBRECHAT")
        print("  1. Open LibreChat: http://127.0.0.1:3080")
        print("  2. In the top navbar or chat header, click the Bookmark icon (🏷️ / 🔖).")
        print(f"  3. Click '{tag}' to instantly filter and view all {matched} chats!")
        print()
        print("  -> When done, remove this search tag by running:")
        print("     python3 batch-folder-organizer.py --clear-search")
        return

    if args.clear_search is not None:
        tag_to_clear = args.clear_search.strip() if (isinstance(args.clear_search, str) and args.clear_search.strip()) else None
        target_desc = f"'{tag_to_clear}'" if tag_to_clear else "all temporary search bookmarks (starting with 🔍)"
        print_header(f"Clearing Search Bookmarks: {target_desc}")
        cleared_count, tags_cleared = clear_search_bookmarks(specific_tag=tag_to_clear)
        if cleared_count == 0:
            print_info("No temporary search bookmark tags found to clear.")
        else:
            print_pass(f"Cleared {len(tags_cleared)} search tag(s): {', '.join(tags_cleared)}")
            print_pass(f"Cleaned up {cleared_count} conversation record(s).")
        return

    if args.file:
        if not args.folder:
            print_fail("--folder is required when using --file.")
            sys.exit(1)
        process_export_file(args.file, args.folder, output_path=args.output)
        return

    if args.remove_folder:
        print_header(f"Removing Folder Shell: {args.remove_folder}")
        ok = remove_folder_from_database(args.remove_folder)
        if ok:
            print_pass(f"Removed folder '{args.remove_folder}'. Associated chats returned to unassigned list.")
        else:
            print_warn(f"Folder '{args.remove_folder}' not found.")
        return

    if args.delete_folder or args.delete_chats:
        target = args.delete_folder or args.delete_chats
        keep_shell = args.keep_folder or bool(args.delete_chats)
        action_desc = "delete all chats in folder and keep shell" if keep_shell else "PERMANENTLY DELETE folder AND all its chats"

        print_header(f"DESTRUCTIVE ACTION: {target}")

        conv_count, msg_count = get_folder_stats(target)
        if conv_count == 0:
            print_warn(f"No conversations or messages found matching folder/tag: '{target}'.")
            return

        print_info(f"Target Scope: Found {conv_count:,} conversation(s) and {msg_count:,} message(s) in '{target}'.")
        print_warn(f"You are about to {action_desc}: '{target}'")

        if not args.yes:
            try:
                confirm = input("  Are you sure you want to proceed? (yes/N): ").strip().lower()
            except (KeyboardInterrupt, EOFError):
                print()
                print_info("Operation cancelled.")
                return
            if confirm not in ("yes", "y"):
                print_info("Operation cancelled.")
                return

        del_convs, del_msgs = delete_folder_chats(target, keep_folder_shell=keep_shell)
        print_pass(f"Purged {del_convs:,} conversation(s) and {del_msgs:,} message(s) from database.")
        if keep_shell:
            print_info(f"Empty folder shell '{target}' has been preserved in LibreChat sidebar.")
        else:
            print_pass(f"Folder shell '{target}' completely removed from database.")
        return

    if args.folder:
        if not (args.all_untagged or args.match):
            print_fail("Please specify either --all-untagged or --match <regex> to select conversations.")
            sys.exit(1)
        print_header(f"Organizing Conversations into Folder: '{args.folder}'")
        count = organize_conversations_into_folder(
            args.folder,
            match_pattern=args.match,
            all_untagged=args.all_untagged,
            prefix_title=args.prefix_title
        )
        print_pass(f"Assigned {count} conversation(s) to folder '{args.folder}'.")


if __name__ == "__main__":
    main()

