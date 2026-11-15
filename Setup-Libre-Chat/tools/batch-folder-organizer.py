#!/usr/bin/env python3
"""
================================================================================
LibreChat Batch Folder & Tag Organizer
Part of the Debian Dev Suite (Zero Telemetry, 100% Localhost Isolated)
================================================================================

PURPOSE:
  Organizes imported conversations into labeled sidebar project folders and
  bookmark tags in LibreChat, and provides fast global or project-scoped message search.

MODULAR ARCHITECTURE:
  Powered by `librechat_tools`:
  - librechat_tools.storage.mongo_client     -> Direct MongoDB queries, folder creator, search
  - librechat_tools.cli.folder_organizer_cli -> CLI interface & export pre-processing

HOW TO USE:
  python3 batch-folder-organizer.py --list
  python3 batch-folder-organizer.py --search "quantum"
  python3 batch-folder-organizer.py --clear-search
  python3 batch-folder-organizer.py --folder "Personal" --all-untagged
  python3 batch-folder-organizer.py --folder "Work" --match "python|react|docker"
  python3 batch-folder-organizer.py --delete-folder "Gemini" --yes
================================================================================
"""

import sys
from pathlib import Path

# Ensure tools directory is in sys.path
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

# Backward-compatible API re-exports
from librechat_tools.storage.mongo_client import (
    run_mongo_eval, query_mongodb, list_database_summary,
    organize_conversations_into_folder, remove_folder_from_database,
    delete_folder_chats, search_and_bookmark, clear_search_bookmarks
)
from librechat_tools.cli.folder_organizer_cli import process_export_file, main

__all__ = [
    "run_mongo_eval",
    "query_mongodb",
    "list_database_summary",
    "organize_conversations_into_folder",
    "remove_folder_from_database",
    "delete_folder_chats",
    "search_and_bookmark",
    "clear_search_bookmarks",
    "process_export_file",
    "main",
]

if __name__ == "__main__":
    main()
