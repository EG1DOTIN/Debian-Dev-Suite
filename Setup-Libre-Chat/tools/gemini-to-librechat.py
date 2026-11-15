#!/usr/bin/env python3
"""
================================================================================
Gemini to LibreChat Data Mapper & Converter
Part of the Debian Dev Suite (Zero Telemetry, 100% Localhost Isolated)
================================================================================

PURPOSE:
  Converts Google Gemini exports (Takeout JSON, Takeout HTML, AI Studio, etc.)
  into LibreChat-compatible import files (ChatGPT conversations.json or Claude format).

MODULAR ARCHITECTURE:
  This script is a lightweight entry point powered by the `librechat_tools` package:
  - librechat_tools.common.datetime_parser  -> Universal date & Takeout format detection
  - librechat_tools.converters.html_to_md   -> HTML to GFM table, Mermaid & SVG converter
  - librechat_tools.parsers.router          -> Multi-format parser & auto-detector
  - librechat_tools.storage.json_exporter   -> Target schema builder
  - librechat_tools.cli.gemini_migrator_cli -> CLI application logic

HOW TO USE:
  python3 gemini-to-librechat.py -i MyActivity.json -o conversations_gemini.json
  python3 gemini-to-librechat.py -i MyActivity.html -o conversations_gemini.json
  python3 gemini-to-librechat.py -i ~/Downloads/Takeout/ -f "Gemini" -o conversations_gemini.json
================================================================================
"""

import sys
from pathlib import Path

# Ensure tools directory is in sys.path
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

# Backward-compatible API re-exports
from librechat_tools.common.datetime_parser import (
    parse_iso_or_text_time, describe_date_format, DATE_PATTERN, MONTH_MAP
)
from librechat_tools.converters.syntax_highlighter import (
    detect_code_language, normalize_markdown_code_blocks
)
from librechat_tools.converters.table_converter import convert_html_table
from librechat_tools.converters.diagram_detector import (
    is_mermaid_content, format_mermaid_block, svg_to_data_uri
)
from librechat_tools.converters.html_to_md import html_to_markdown
from librechat_tools.media.image_encoder import file_to_data_uri, guess_image_extension
from librechat_tools.parsers.gemini_json import parse_takeout_json
from librechat_tools.parsers.gemini_html import parse_takeout_html
from librechat_tools.parsers.ai_studio import parse_ai_studio_json
from librechat_tools.parsers.generic_json import parse_generic_chat_json
from librechat_tools.parsers.markdown_chat import parse_markdown_chat
from librechat_tools.parsers.router import detect_and_parse
from librechat_tools.storage.json_exporter import to_chatgpt_format, to_claude_format
from librechat_tools.cli.gemini_migrator_cli import main

__all__ = [
    "parse_iso_or_text_time",
    "describe_date_format",
    "DATE_PATTERN",
    "MONTH_MAP",
    "detect_code_language",
    "normalize_markdown_code_blocks",
    "convert_html_table",
    "is_mermaid_content",
    "format_mermaid_block",
    "svg_to_data_uri",
    "html_to_markdown",
    "file_to_data_uri",
    "guess_image_extension",
    "parse_takeout_json",
    "parse_takeout_html",
    "parse_ai_studio_json",
    "parse_generic_chat_json",
    "parse_markdown_chat",
    "detect_and_parse",
    "to_chatgpt_format",
    "to_claude_format",
    "main",
]

if __name__ == "__main__":
    main()
