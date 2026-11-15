"""
Auto-detection router for input chat export files.
Part of the Debian Dev Suite.
"""

import os
import json
from pathlib import Path
from typing import List, Dict, Any, Optional

from .gemini_html import parse_takeout_html
from .gemini_json import parse_takeout_json
from .ai_studio import parse_ai_studio_json
from .generic_json import parse_generic_chat_json
from .markdown_chat import parse_markdown_chat


def detect_and_parse(file_path: str, images_dest_dir: Optional[Path] = None) -> List[Dict[str, Any]]:
    """Auto-detects file format and parses into standardized conversation structure."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    ext = os.path.splitext(file_path)[1].lower()
    base_dir = os.path.dirname(os.path.abspath(file_path))

    if ext == ".html":
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        return parse_takeout_html(content, base_dir=base_dir, images_dest_dir=images_dest_dir)

    if ext in (".md", ".txt"):
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
        return parse_markdown_chat(content)

    if ext == ".json":
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            data = json.load(f)

        # 1. Check if Google Takeout MyActivity.json
        if isinstance(data, list) and len(data) > 0 and isinstance(data[0], dict):
            first = data[0]
            if first.get("header") == "Gemini Apps" or "Gemini Apps" in first.get("products", []) or "titleUrl" in first:
                return parse_takeout_json(data)

        # 2. Check if AI Studio format
        if (isinstance(data, dict) and "contents" in data) or (isinstance(data, list) and len(data) > 0 and isinstance(data[0], dict) and "contents" in data[0]):
            return parse_ai_studio_json(data)

        # 3. Check if generic chat format
        return parse_generic_chat_json(data)

    raise ValueError(f"Unsupported file format: {ext}")

