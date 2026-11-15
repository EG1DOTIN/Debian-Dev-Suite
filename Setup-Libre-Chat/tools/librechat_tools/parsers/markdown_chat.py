"""
Parser for plaintext and Markdown dialogue transcripts.
Part of the Debian Dev Suite.
"""

import re
from datetime import datetime
from typing import List, Dict, Any

from ..converters.syntax_highlighter import normalize_markdown_code_blocks


def parse_markdown_chat(text: str) -> List[Dict[str, Any]]:
    """Parses plaintext / markdown conversation transcripts."""
    lines = text.splitlines()
    conversations = []
    messages = []
    title = "Gemini Markdown Chat"
    now = datetime.now().timestamp()

    current_role = None
    current_lines = []

    role_pattern = re.compile(r'^(?:[\*#\s]*)(User|Human|Gemini|Model|Assistant)(?:[\*#\s]*):\s*(.*)$', re.IGNORECASE)

    for line in lines:
        match = role_pattern.match(line)
        if match:
            # Flush previous message
            if current_role and current_lines:
                msg_text = "\n".join(current_lines).strip()
                if msg_text:
                    messages.append({
                        "role": current_role,
                        "text": normalize_markdown_code_blocks(msg_text),
                        "time_epoch": now + len(messages)
                    })
                current_lines = []

            role_str = match.group(1).lower()
            current_role = "user" if role_str in ("user", "human") else "assistant"
            first_line = match.group(2).strip()
            if first_line:
                current_lines.append(first_line)
        else:
            if current_role:
                current_lines.append(line)

    if current_role and current_lines:
        msg_text = "\n".join(current_lines).strip()
        if msg_text:
            messages.append({
                "role": current_role,
                "text": normalize_markdown_code_blocks(msg_text),
                "time_epoch": now + len(messages)
            })

    if messages:
        conversations.append({
            "title": title,
            "create_time": now,
            "messages": messages
        })

    return conversations

