"""
Image encoding, MIME type detection, and Base64 data URI generation.
Part of the Debian Dev Suite.
"""

import os
import re
import base64
from typing import Optional, Tuple


def guess_image_extension(header_bytes: bytes) -> str:
    """Detect image file extension from magic bytes."""
    if header_bytes.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    elif header_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    elif header_bytes.startswith(b"GIF87a") or header_bytes.startswith(b"GIF89a"):
        return ".gif"
    elif header_bytes.startswith(b"RIFF") and b"WEBP" in header_bytes[:12]:
        return ".webp"
    return ""


def file_to_data_uri(file_path: str) -> Optional[str]:
    """Encodes a local image file into a self-contained Base64 Data URI."""
    if not os.path.exists(file_path):
        return None
    ext = os.path.splitext(file_path)[1].lower()
    mime_types = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
        ".gif": "image/gif",
        ".svg": "image/svg+xml",
    }
    mime = mime_types.get(ext, "image/png")
    try:
        with open(file_path, "rb") as f:
            data = f.read()
        b64 = base64.b64encode(data).decode("ascii")
        return f"data:{mime};base64,{b64}"
    except Exception:
        return None


def data_uri_to_bytes(data_uri: str) -> Tuple[Optional[bytes], str]:
    """
    Decodes a Base64 data URI (e.g. data:image/png;base64,...) into raw bytes and detected file extension.
    Returns: (raw_bytes, extension_with_dot)
    """
    m = re.match(r"^data:(image/[a-zA-Z0-9+.-]+);base64,(.+)$", data_uri.strip(), re.DOTALL)
    if not m:
        return None, ""
    mime = m.group(1).lower()
    b64_str = m.group(2).strip()
    try:
        raw_bytes = base64.b64decode(b64_str)
    except Exception:
        return None, ""

    ext = guess_image_extension(raw_bytes[:16])
    if not ext:
        mime_map = {
            "image/jpeg": ".jpg",
            "image/jpg": ".jpg",
            "image/png": ".png",
            "image/webp": ".webp",
            "image/gif": ".gif",
            "image/svg+xml": ".svg",
        }
        ext = mime_map.get(mime, ".png")
    return raw_bytes, ext


