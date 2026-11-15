#!/usr/bin/env python3
"""
================================================================================
fix-chatgpt-images.py - ChatGPT Image Restorer & Linker for LibreChat
Part of the Debian Dev Suite (Zero Telemetry, 100% Localhost Isolated)
================================================================================

PURPOSE:
  Restores and renders attached images from ChatGPT exports in LibreChat.
  Extracts images from .zip archives or folders into LibreChat's images directory
  and links MongoDB messages with clickable Markdown thumbnails.

MODULAR ARCHITECTURE:
  Powered by `librechat_tools`:
  - librechat_tools.media.image_encoder   -> Magic byte sniffer & data URI generator
  - librechat_tools.media.asset_linker    -> Asset pointer resolution & zip/dir extraction
  - librechat_tools.storage.mongo_client  -> MongoDB message scanner & thumbnail rewriter
  - librechat_tools.cli.chatgpt_images_cli-> Interactive & batch CLI logic

HOW TO USE:
  python3 fix-chatgpt-images.py --status
  python3 fix-chatgpt-images.py --from-zip ~/Downloads/chatgpt_export.zip
  python3 fix-chatgpt-images.py --from-dir ~/Downloads/chatgpt_extracted/
  python3 fix-chatgpt-images.py --link-db
  python3 fix-chatgpt-images.py --clean-placeholders
  python3 fix-chatgpt-images.py --prepare-file conversations.json -o conversations_fixed.json
================================================================================
"""

import sys
from pathlib import Path

# Ensure tools directory is in sys.path
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

# Backward-compatible API re-exports
from librechat_tools.media.image_encoder import guess_image_extension, file_to_data_uri
from librechat_tools.media.asset_linker import (
    find_matching_file, extract_images_from_zip, extract_images_from_dir
)
from librechat_tools.storage.mongo_client import (
    query_mongodb, get_all_target_messages, get_resolved_messages, get_all_base64_messages,
    link_mongodb_messages, sanitize_mongodb_base64_images,
    JSON_BLOCK_PATTERN, ASSET_ID_PATTERN, CLEAN_PLACEHOLDER_PATTERN, BASE64_MD_PATTERN
)
from librechat_tools.cli.chatgpt_images_cli import show_status, prepare_conversations_json, main

__all__ = [
    "guess_image_extension",
    "file_to_data_uri",
    "find_matching_file",
    "extract_images_from_zip",
    "extract_images_from_dir",
    "query_mongodb",
    "get_all_target_messages",
    "get_resolved_messages",
    "get_all_base64_messages",
    "link_mongodb_messages",
    "sanitize_mongodb_base64_images",
    "JSON_BLOCK_PATTERN",
    "ASSET_ID_PATTERN",
    "CLEAN_PLACEHOLDER_PATTERN",
    "BASE64_MD_PATTERN",
    "show_status",
    "prepare_conversations_json",
    "main",
]

if __name__ == "__main__":
    main()
