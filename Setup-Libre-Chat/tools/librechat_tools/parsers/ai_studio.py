"""
Parser for Google AI Studio / MakerSuite chat export formats.
Part of the Debian Dev Suite.
"""

from datetime import datetime
from typing import List, Dict, Any

from ..converters.syntax_highlighter import normalize_markdown_code_blocks


def parse_ai_studio_json(data: Any) -> List[Dict[str, Any]]:
    """Parses Google AI Studio / MakerSuite prompt and chat JSON exports."""
    conversations = []
    items = data if isinstance(data, list) else [data]

    for item in items:
        if not isinstance(item, dict):
            continue

        title = item.get("prompt", {}).get("text", "") if isinstance(item.get("prompt"), dict) else item.get("name", "AI Studio Prompt")
        if not title:
            title = "AI Studio Chat"
        title = title[:60].strip()

        messages = []
        now = datetime.now().timestamp()

        # Format A: item['contents'] -> list of turn objects
        contents = item.get("contents", [])
        for idx, turn in enumerate(contents):
            if not isinstance(turn, dict):
                continue
            role_raw = turn.get("role", "").lower()
            role = "user" if role_raw in ("user", "human") else "assistant"
            parts = turn.get("parts", [])
            text_parts = []
            for p in parts:
                if isinstance(p, dict) and "text" in p:
                    text_parts.append(p["text"])
                elif isinstance(p, str):
                    text_parts.append(p)
            text = "\n\n".join(text_parts).strip()
            if text:
                messages.append({
                    "role": role,
                    "text": normalize_markdown_code_blocks(text),
                    "time_epoch": now + idx
                })

        if messages:
            conversations.append({
                "title": title,
                "create_time": now,
                "messages": messages
            })

    return conversations

