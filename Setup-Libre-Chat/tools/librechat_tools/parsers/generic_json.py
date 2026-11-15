"""
Parser for generic chat JSON files from browser extensions or community tools.
Part of the Debian Dev Suite.
"""

from typing import List, Dict, Any

from ..common.datetime_parser import parse_iso_or_text_time
from ..converters.syntax_highlighter import normalize_markdown_code_blocks


def parse_generic_chat_json(data: Any) -> List[Dict[str, Any]]:
    """Parses generic chat JSON files from browser extensions or community tools."""
    items = data if isinstance(data, list) else [data]
    conversations = []

    for item in items:
        if not isinstance(item, dict):
            continue

        msg_list = None
        for key in ("messages", "chat", "conversation", "history", "dialogue"):
            if key in item and isinstance(item[key], list):
                msg_list = item[key]
                break

        if not msg_list:
            continue

        title = item.get("title") or item.get("name") or "Imported Gemini Chat"
        create_time = parse_iso_or_text_time(item.get("create_time") or item.get("date") or item.get("created_at"))
        messages = []

        for idx, m in enumerate(msg_list):
            if not isinstance(m, dict):
                continue
            role_raw = str(m.get("role") or m.get("sender") or m.get("author") or m.get("speaker") or "").lower()
            role = "user" if role_raw in ("user", "human", "me") else "assistant"
            text = m.get("text") or m.get("content") or m.get("message") or ""
            if isinstance(text, list):
                text = "\n\n".join(str(p) for p in text)
            text = str(text).strip()

            m_time = parse_iso_or_text_time(m.get("time") or m.get("timestamp") or m.get("created_at"))
            if not m_time:
                m_time = create_time + idx

            if text:
                messages.append({
                    "role": role,
                    "text": normalize_markdown_code_blocks(text),
                    "time_epoch": m_time
                })

        if messages:
            conversations.append({
                "title": title,
                "create_time": create_time,
                "messages": messages
            })

    return conversations

