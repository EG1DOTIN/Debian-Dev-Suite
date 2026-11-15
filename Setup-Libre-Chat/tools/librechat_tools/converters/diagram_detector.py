"""
Diagram and Vector Graphics Detector (Mermaid & SVG).
Part of the Debian Dev Suite.
"""

import re
import html
import base64
from typing import Tuple

from .syntax_highlighter import MERMAID_KEYWORDS


def is_mermaid_content(text: str) -> bool:
    """Checks if text content starts with a recognized Mermaid diagram syntax keyword."""
    clean = text.strip()
    if not clean:
        return False
    lines = [l.strip() for l in clean.split("\n") if l.strip()]
    if lines and any(lines[0].startswith(kw) for kw in MERMAID_KEYWORDS):
        return True
    return False


def format_mermaid_block(raw_content: str) -> str:
    """Wraps raw diagram content in a native ```mermaid code block."""
    content = html.unescape(raw_content).strip()
    return f"\n\n```mermaid\n{content}\n```\n\n"


def svg_to_data_uri(svg_code: str) -> Tuple[str, str]:
    """
    Encodes an SVG XML element into a self-contained Base64 data URI and extracts title/alt.
    Returns: (alt_text, data_uri)
    """
    clean_svg = svg_code.strip()
    title_m = re.search(r"<title[^>]*>([^<]+)</title>", clean_svg, re.IGNORECASE)
    alt = title_m.group(1).strip() if title_m else "Vector Diagram"
    b64 = base64.b64encode(clean_svg.encode("utf-8")).decode("ascii")
    data_uri = f"data:image/svg+xml;base64,{b64}"
    return alt, data_uri

