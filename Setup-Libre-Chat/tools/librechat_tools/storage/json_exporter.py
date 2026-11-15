"""
Exporters formatting conversations into LibreChat Web UI compatible JSON schemas.
Supports ChatGPT (conversations.json) and Claude format.
Part of the Debian Dev Suite.
"""

import uuid
from datetime import datetime
from typing import List, Dict, Any, Optional


def to_chatgpt_format(conversations: List[Dict[str, Any]], folder_prefix: Optional[str] = None, model_name: str = "Gemini") -> List[Dict[str, Any]]:
    """
    Builds the standard ChatGPT `conversations.json` structure natively recognized
    by LibreChat's file importer.
    """
    output_convs = []

    for conv in conversations:
        title = conv.get("title", "Imported Gemini Chat")
        if folder_prefix:
            prefix = f"[{folder_prefix}] "
            if not title.startswith(prefix):
                title = f"{prefix}{title}"

        create_time = conv.get("create_time", datetime.now().timestamp())
        messages = conv.get("messages", [])
        if not messages:
            continue

        root_id = str(uuid.uuid4())
        mapping = {
            root_id: {
                "id": root_id,
                "message": None,
                "parent": None,
                "children": []
            }
        }

        parent_id = root_id
        curr_time = create_time

        for msg in messages:
            m_id = str(uuid.uuid4())
            role = msg["role"]
            text = msg["text"]
            m_time = msg.get("time_epoch", curr_time)
            curr_time = m_time + 1

            # Connect parent to this child
            mapping[parent_id]["children"].append(m_id)

            node = {
                "id": m_id,
                "message": {
                    "id": m_id,
                    "author": {
                        "role": role,
                        "name": None,
                        "metadata": {}
                    },
                    "create_time": m_time,
                    "content": {
                        "content_type": "text",
                        "parts": [text]
                    },
                    "status": "finished_successfully",
                    "end_turn": True,
                    "weight": 1.0,
                    "metadata": {
                        "model_slug": model_name if role == "assistant" else None
                    }
                },
                "parent": parent_id,
                "children": []
            }
            mapping[m_id] = node
            parent_id = m_id

        output_convs.append({
            "title": title,
            "create_time": create_time,
            "mapping": mapping,
            "current_node": parent_id
        })

    return output_convs


def to_claude_format(conversations: List[Dict[str, Any]], folder_prefix: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Builds the Claude export structure natively recognized by LibreChat's file importer.
    """
    output_convs = []

    for conv in conversations:
        title = conv.get("title", "Imported Gemini Chat")
        if folder_prefix:
            prefix = f"[{folder_prefix}] "
            if not title.startswith(prefix):
                title = f"{prefix}{title}"

        create_time = conv.get("create_time", datetime.now().timestamp())
        dt = datetime.fromtimestamp(create_time)
        created_at_iso = dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")

        messages = conv.get("messages", [])
        chat_messages = []

        for msg in messages:
            role = msg["role"]
            sender = "human" if role == "user" else "assistant"
            m_epoch = msg.get("time_epoch", create_time)
            m_iso = datetime.fromtimestamp(m_epoch).strftime("%Y-%m-%dT%H:%M:%S.000Z")

            chat_messages.append({
                "uuid": str(uuid.uuid4()),
                "text": msg["text"],
                "sender": sender,
                "created_at": m_iso
            })

        output_convs.append({
            "uuid": str(uuid.uuid4()),
            "name": title,
            "created_at": created_at_iso,
            "chat_messages": chat_messages
        })

    return output_convs

