"""
Parser for Google Takeout Gemini Activity JSON (MyActivity.json).
Part of the Debian Dev Suite.
"""

import re
import html
from datetime import datetime
from typing import List, Dict, Any

from ..common.datetime_parser import parse_iso_or_text_time
from ..converters.syntax_highlighter import normalize_markdown_code_blocks


def parse_takeout_json(data: Any) -> List[Dict[str, Any]]:
    """
    Parses Takeout/My Activity/Gemini Apps/MyActivity.json.
    Groups entries by conversation thread (titleUrl) and sorts chronologically.
    """
    if not isinstance(data, list):
        return []

    threads = {}

    for entry in data:
        if not isinstance(entry, dict):
            continue

        title = entry.get("title", "").strip()
        title_url = entry.get("titleUrl", "").strip()
        timestamp_str = entry.get("time", "")
        epoch_time = parse_iso_or_text_time(timestamp_str)

        conv_key = "standalone"
        if title_url:
            match = re.search(r"/app/(?:c/)?([a-zA-Z0-9_-]+)", title_url)
            if match:
                conv_key = match.group(1)
            else:
                conv_key = title_url
        else:
            dt = datetime.fromtimestamp(epoch_time)
            conv_key = f"date_{dt.strftime('%Y%m%d')}"

        prompt_text = ""
        details = entry.get("details", [])
        if isinstance(details, list):
            for d in details:
                if isinstance(d, dict):
                    name = d.get("name", "").lower()
                    if name in ("prompt", "query", "question"):
                        prompt_text = d.get("value", "").strip()
                        break

        if not prompt_text and title:
            cleaned = re.sub(r'^(?:Asked\s+Gemini:\s*|Asked\s+Gemini\s+|Asked:\s*|Prompted\s+)', '', title, flags=re.IGNORECASE)
            cleaned = html.unescape(cleaned.strip(' "\'“”‘’'))
            if cleaned and cleaned.lower() not in ("gemini apps", "used gemini apps"):
                prompt_text = cleaned

        response_text = ""
        if isinstance(details, list):
            for d in details:
                if isinstance(d, dict):
                    name = d.get("name", "").lower()
                    if name in ("response", "answer", "gemini response", "output"):
                        response_text = d.get("value", "").strip()
                        break

        if not response_text:
            subtitles = entry.get("subtitles", [])
            if isinstance(subtitles, list):
                sub_texts = []
                for s in subtitles:
                    if isinstance(s, dict):
                        name_val = s.get("name")
                        if isinstance(name_val, str) and name_val.strip():
                            sub_texts.append(name_val.strip())
                    elif isinstance(s, str) and s.strip():
                        sub_texts.append(s.strip())
                if sub_texts:
                    response_text = "\n\n".join(sub_texts)

        if not prompt_text and not response_text:
            continue

        if conv_key not in threads:
            threads[conv_key] = []

        threads[conv_key].append({
            "prompt": prompt_text,
            "response": response_text,
            "time_epoch": epoch_time
        })

    conversations = []
    for conv_id, turns in threads.items():
        turns.sort(key=lambda x: x["time_epoch"])
        first_turn = turns[0]
        title = first_turn["prompt"][:60] if first_turn["prompt"] else f"Gemini Chat ({conv_id})"

        messages = []
        for t in turns:
            if t["prompt"]:
                messages.append({
                    "role": "user",
                    "text": normalize_markdown_code_blocks(t["prompt"]),
                    "time_epoch": t["time_epoch"]
                })
            if t["response"]:
                messages.append({
                    "role": "assistant",
                    "text": normalize_markdown_code_blocks(t["response"]),
                    "time_epoch": t["time_epoch"] + 1
                })

        if messages:
            conversations.append({
                "title": title,
                "create_time": first_turn["time_epoch"],
                "messages": messages
            })

    conversations.sort(key=lambda x: x["create_time"], reverse=True)
    return conversations

