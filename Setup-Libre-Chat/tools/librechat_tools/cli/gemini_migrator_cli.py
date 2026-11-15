"""
CLI interface for Gemini to LibreChat data migration.
Part of the Debian Dev Suite.
"""

import os
import sys
import glob
import json
import argparse
from pathlib import Path

from ..common.colors import (
    BOLD, RESET, print_header, print_pass, print_info, print_warn, print_fail
)
from ..common.paths import get_librechat_images_dir
from ..parsers.router import detect_and_parse
from ..storage.json_exporter import to_chatgpt_format, to_claude_format


def main(args_list=None):
    parser = argparse.ArgumentParser(
        description="Map and convert Gemini exports (Takeout JSON, HTML, AI Studio) into LibreChat importable JSON.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Convert Google Takeout JSON
  python3 gemini-to-librechat.py -i MyActivity.json -o conversations_gemini.json

  # Convert Google Takeout HTML
  python3 gemini-to-librechat.py -i MyActivity.html -o conversations_gemini.json

  # Auto-scan Google Takeout folder and tag with folder prefix
  python3 gemini-to-librechat.py -i ~/Downloads/Takeout/ -f "Gemini" -o conversations_gemini.json
        """
    )

    parser.add_argument("-i", "--input", required=True, help="Input Gemini export file (MyActivity.json, MyActivity.html, etc.) or Takeout directory")
    parser.add_argument("-o", "--output", default="conversations_gemini.json", help="Output JSON file for LibreChat (default: conversations_gemini.json)")
    parser.add_argument("-f", "--folder", default="Gemini", help="Prefix conversation titles with folder label (e.g. '[Gemini] Title', default: 'Gemini')")
    parser.add_argument("-m", "--model", default="Gemini", help="Model name label for messages (default: 'Gemini')")
    parser.add_argument("--format", choices=["chatgpt", "claude"], default="chatgpt", help="Target import format (default: 'chatgpt')")
    parser.add_argument("--images-dir", type=Path, default=get_librechat_images_dir(), help=f"Directory to copy extracted images into (default: {get_librechat_images_dir()})")

    args = parser.parse_args(args_list)

    print_header("Gemini to LibreChat Converter")

    input_path = os.path.expanduser(args.input)
    if not os.path.exists(input_path):
        print_fail(f"Input path does not exist: {input_path}")
        sys.exit(1)

    files_to_process = []
    if os.path.isdir(input_path):
        print_info(f"Scanning directory: {input_path}")
        json_matches = glob.glob(os.path.join(input_path, "**", "*MyActivity*.json"), recursive=True)
        html_matches = glob.glob(os.path.join(input_path, "**", "*MyActivity*.html"), recursive=True)
        other_json = glob.glob(os.path.join(input_path, "**", "*.json"), recursive=True)

        if json_matches:
            files_to_process.extend(json_matches)
        elif html_matches:
            files_to_process.extend(html_matches)
        elif other_json:
            files_to_process.extend(other_json)
        else:
            print_fail("No compatible Gemini export files found in directory.")
            sys.exit(1)
    else:
        files_to_process.append(input_path)

    all_conversations = []
    for fpath in files_to_process:
        print_info(f"Parsing: {fpath}")
        try:
            convs = detect_and_parse(fpath, images_dest_dir=args.images_dir)
            print_pass(f"Extracted {len(convs)} conversation thread(s) from {os.path.basename(fpath)}")
            all_conversations.extend(convs)
        except Exception as e:
            print_warn(f"Failed to parse {fpath}: {e}")

    if not all_conversations:
        print_fail("No conversations were found in the provided file(s).")
        sys.exit(1)

    total_messages = sum(len(c.get("messages", [])) for c in all_conversations)
    print_pass(f"Total conversations collected: {len(all_conversations)}")
    print_pass(f"Total messages collected: {total_messages}")

    print_info(f"Formatting data into LibreChat '{args.format}' schema...")
    folder_prefix = args.folder.strip() if args.folder else None

    if args.format == "chatgpt":
        result_data = to_chatgpt_format(all_conversations, folder_prefix=folder_prefix, model_name=args.model)
    else:
        result_data = to_claude_format(all_conversations, folder_prefix=folder_prefix)

    output_path = os.path.abspath(os.path.expanduser(args.output))
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result_data, f, indent=2, ensure_ascii=False)

    file_size_kb = os.path.getsize(output_path) / 1024

    print()
    print_pass(f"Successfully generated LibreChat import file: {output_path}")
    print_info(f"Output file size: {file_size_kb:.1f} KB ({len(result_data)} conversations ready)")
    print()
    print(f"{BOLD}NEXT STEPS (Importing into LibreChat):{RESET}")
    print(f"  1. Open LibreChat: {BOLD}http://127.0.0.1:3080{RESET}")
    print("  2. Click your profile icon (bottom-left) -> Settings -> Data & Privacy (or General)")
    print("  3. Click 'Import' next to 'Import conversations from a JSON file'")
    print(f"  4. Select this file: {BOLD}{output_path}{RESET}")
    print("  5. Your complete Gemini conversations will appear immediately in your sidebar!")
    if folder_prefix:
        print(f"  6. (Optional) Run: {BOLD}python3 batch-folder-organizer.py --folder \"{folder_prefix}\" --match \"\\[{folder_prefix}\\]\"{RESET}")
        print("     to group them into a dedicated sidebar project folder.")
    print()


if __name__ == "__main__":
    main()

