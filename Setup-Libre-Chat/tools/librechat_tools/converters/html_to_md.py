"""
HTML to GitHub-Flavored Markdown (GFM) Transformation Pipeline.
Part of the Debian Dev Suite.
"""

import re
import os
import html
from pathlib import Path
from typing import Optional

from .table_converter import convert_html_table
from .syntax_highlighter import detect_code_language, normalize_markdown_code_blocks
from .diagram_detector import format_mermaid_block, svg_to_data_uri


def html_to_markdown(
    html_text: str,
    base_dir: Optional[str] = None,
    images_dest_dir: Optional[Path] = None
) -> str:
    """
    Converts HTML formatted responses from Google Takeout to clean GitHub-flavored Markdown.
    Supports tables (GFM format), diagrams (Mermaid, SVG), code blocks, math formulas,
    callouts / alerts, blockquotes, ordered/task lists, definition lists, collapsible details,
    typography, and local/remote images.
    """
    if not html_text:
        return ""
    s = str(html_text)

    # Late import to prevent circular dependency
    from ..media.image_encoder import file_to_data_uri
    from ..media.asset_linker import copy_takeout_image, save_base64_data_to_file

    code_blocks = []
    inline_codes = []
    table_blocks = []
    svg_blocks = []
    details_blocks = []
    math_blocks = []
    kbd_blocks = []

    # 1. Mermaid diagram blocks (<div class="mermaid">, <pre class="mermaid">)
    def mermaid_div_sub(m):
        block = format_mermaid_block(m.group(1))
        idx = len(code_blocks)
        code_blocks.append(block)
        return f"\n\n__PRE_BLOCK_{idx}__\n\n"

    s = re.sub(
        r'<(?:div|pre)[^>]*class=[\'"][^\'"]*mermaid[^\'"]*[\'"][^>]*>([\s\S]*?)</(?:div|pre)>',
        mermaid_div_sub,
        s,
        flags=re.IGNORECASE,
    )

    # 2. Preformatted code blocks (<pre>)
    def save_pre(m):
        full = m.group(0)
        pre_attr_m = re.match(r"<pre([^>]*)>", full, re.IGNORECASE)
        pre_attr = pre_attr_m.group(1) if pre_attr_m else ""

        code_m = re.search(r"<code([^>]*)>(.*?)</code>", full, re.DOTALL | re.IGNORECASE)
        if code_m:
            code_attr = code_m.group(1)
            raw_code = code_m.group(2)
        else:
            code_attr = ""
            raw_code = re.sub(r"^<pre[^>]*>", "", full, flags=re.IGNORECASE)
            raw_code = re.sub(r"</pre>$", "", raw_code, flags=re.IGNORECASE)

        code = html.unescape(raw_code)
        code = re.sub(r"</?code[^>]*>", "", code)

        combined_attrs = f"{pre_attr} {code_attr}"
        lang_match = re.search(
            r'(?:class=[\"\'].*?\b(?:language|lang)-([a-zA-Z0-9_+-]+)\b|class=[\"\'].*?\b(mermaid)\b|data-language=[\"\']([a-zA-Z0-9_+-]+)[\"\']|data-lang=[\"\']([a-zA-Z0-9_+-]+)[\"\'])',
            combined_attrs,
            re.IGNORECASE,
        )
        explicit_lang = (
            (lang_match.group(1) or lang_match.group(2) or lang_match.group(3) or lang_match.group(4)).lower()
            if lang_match
            else None
        )

        if "```" in code:
            block = f"\n\n{normalize_markdown_code_blocks(code.strip())}\n\n"
        else:
            lang = explicit_lang or detect_code_language(code)
            block = f"\n```{lang}\n{code.strip()}\n```\n"

        idx = len(code_blocks)
        code_blocks.append(block)
        return f"\n\n__PRE_BLOCK_{idx}__\n\n"

    s = re.sub(r"<pre[^>]*>.*?</pre>", save_pre, s, flags=re.DOTALL | re.IGNORECASE)

    # 3. SVG vector graphics (<svg>)
    def save_svg(m):
        alt, data_uri = svg_to_data_uri(m.group(0))
        idx = len(svg_blocks)
        if images_dest_dir:
            dest_file = save_base64_data_to_file(data_uri, images_dest_dir, preferred_filename="diagram.svg")
            if dest_file:
                svg_blocks.append(f"\n\n[![{alt}](/images/{dest_file})](/images/{dest_file})\n\n")
                return f"__SVG_BLOCK_{idx}__"
        svg_blocks.append(f"\n\n[![{alt}]({data_uri})]({data_uri})\n\n")
        return f"__SVG_BLOCK_{idx}__"

    s = re.sub(r"<svg[^>]*>[\s\S]*?</svg>", save_svg, s, flags=re.IGNORECASE)

    # 4. Collapsible sections (<details>)
    def save_details(m):
        full = m.group(0).strip()
        summary_m = re.search(r"<summary[^>]*>([\s\S]*?)</summary>", full, re.IGNORECASE)
        summary_text = summary_m.group(1).strip() if summary_m else "Details"
        summary_text = re.sub(r"<[^>]+>", "", summary_text)

        body = re.sub(r"^<details[^>]*>[\s\S]*?</summary>", "", full, flags=re.IGNORECASE)
        body = re.sub(r"</details>$", "", body, flags=re.IGNORECASE).strip()
        clean_body = re.sub(r"<[^>]+>", "", body)

        clean_details = f"<details>\n<summary>{summary_text}</summary>\n\n{clean_body}\n</details>"
        idx = len(details_blocks)
        details_blocks.append(f"\n\n{clean_details}\n\n")
        return f"__DETAILS_BLOCK_{idx}__"

    s = re.sub(r"<details[^>]*>[\s\S]*?</details>", save_details, s, flags=re.IGNORECASE)

    # 5. Math blocks (<math>)
    def save_math(m):
        raw = m.group(0).strip()
        alt_m = re.search(r'alttext=[\'"]([^\'"]+)[\'"]', raw, re.IGNORECASE)
        if alt_m:
            tex = alt_m.group(1).strip()
            content = f"\n\n$${tex}$$\n\n" if "\n" in tex else f" ${tex}$ "
        else:
            tex = re.sub(r"<[^>]+>", "", raw).strip()
            content = f" ${tex}$ "
        idx = len(math_blocks)
        math_blocks.append(content)
        return f"__MATH_BLOCK_{idx}__"

    s = re.sub(r"<math[^>]*>[\s\S]*?</math>", save_math, s, flags=re.IGNORECASE)

    # 6. HTML Tables (<table>)
    def save_table(m):
        tbl_md = convert_html_table(m.group(0))
        idx = len(table_blocks)
        table_blocks.append(tbl_md)
        return f"\n\n__TABLE_BLOCK_{idx}__\n\n"

    s = re.sub(r"<table[^>]*>[\s\S]*?</table>", save_table, s, flags=re.IGNORECASE)

    # 7. Inline code (<code>)
    def save_inline_code(m):
        code_content = html.unescape(m.group(1))
        idx = len(inline_codes)
        inline_codes.append(f"`{code_content}`")
        return f"__INLINE_CODE_{idx}__"

    s = re.sub(r"<code[^>]*>(.*?)</code>", save_inline_code, s, flags=re.DOTALL | re.IGNORECASE)

    # 8. GitHub Alerts & Callout divs
    def callout_repl(m):
        cls = (m.group(1) or "").lower()
        content = m.group(2).strip()
        tag = "NOTE"
        if "warn" in cls:
            tag = "WARNING"
        elif "tip" in cls or "success" in cls:
            tag = "TIP"
        elif "important" in cls:
            tag = "IMPORTANT"
        elif "caution" in cls or "danger" in cls or "error" in cls:
            tag = "CAUTION"
        inner_lines = [re.sub(r"<[^>]+>", "", l).strip() for l in content.split("\n") if l.strip()]
        return f"\n\n> [!{tag}]\n" + "\n".join(f"> {l}" for l in inner_lines) + "\n\n"

    s = re.sub(
        r'<div[^>]*class=[\'"][^\'"]*(?:callout|alert|admonition)[-_]?([a-zA-Z0-9_-]*)[^\'"]*[\'"][^>]*>([\s\S]*?)</div>',
        callout_repl,
        s,
        flags=re.IGNORECASE,
    )

    # 9. Blockquotes (<blockquote>)
    def bq_repl(m):
        content = m.group(1).strip()
        inner_lines = [re.sub(r"<[^>]+>", "", l).strip() for l in content.split("\n") if l.strip()]
        return "\n\n" + "\n".join(f"> {l}" for l in inner_lines) + "\n\n"

    s = re.sub(r"<blockquote[^>]*>([\s\S]*?)</blockquote>", bq_repl, s, flags=re.IGNORECASE)

    # 10. Lists: Ordered (<ol>) & Unordered (<ul>) with task list support
    def ol_repl(m):
        items = re.findall(r"<li[^>]*>([\s\S]*?)</li>", m.group(1), re.IGNORECASE)
        start_m = re.search(r'start=[\'"](\d+)[\'"]', m.group(0), re.IGNORECASE)
        start_num = int(start_m.group(1)) if start_m else 1
        res = []
        for i, it in enumerate(items):
            it_clean = re.sub(r"<br\s*/?>", " ", it, flags=re.IGNORECASE)
            it_clean = re.sub(r"<[^>]+>", "", it_clean).strip()
            res.append(f"{start_num + i}. {it_clean}")
        return "\n\n" + "\n".join(res) + "\n\n"

    def ul_repl(m):
        items = re.findall(r"<li[^>]*>([\s\S]*?)</li>", m.group(1), re.IGNORECASE)
        res = []
        for it in items:
            checked = bool(re.search(r'<input[^>]*type=[\'"]checkbox[\'"][^>]*checked', it, re.IGNORECASE))
            has_box = bool(re.search(r'<input[^>]*type=[\'"]checkbox[\'"]', it, re.IGNORECASE))
            it_clean = re.sub(r"<input[^>]*>", "", it)
            it_clean = re.sub(r"<br\s*/?>", " ", it_clean, flags=re.IGNORECASE)
            it_clean = re.sub(r"<[^>]+>", "", it_clean).strip()
            if checked:
                res.append(f"* [x] {it_clean}")
            elif has_box:
                res.append(f"* [ ] {it_clean}")
            else:
                res.append(f"* {it_clean}")
        return "\n\n" + "\n".join(res) + "\n\n"

    # Multi-pass for nested lists
    for _ in range(3):
        s = re.sub(r"<ol[^>]*>([\s\S]*?)</ol>", ol_repl, s, flags=re.IGNORECASE)
        s = re.sub(r"<ul[^>]*>([\s\S]*?)</ul>", ul_repl, s, flags=re.IGNORECASE)

    # 11. Definition Lists (<dl>, <dt>, <dd>)
    s = re.sub(r"<dt[^>]*>(.*?)</dt>", lambda m: f"\n\n**{re.sub(r'<[^>]+>', '', m.group(1)).strip()}**:\n", s, flags=re.IGNORECASE)
    s = re.sub(r"<dd[^>]*>(.*?)</dd>", lambda m: f"> {re.sub(r'<[^>]+>', '', m.group(1)).strip()}\n", s, flags=re.IGNORECASE)

    # 12. Images (<img>)
    def img_sub(m):
        src = m.group(1).strip()
        alt = m.group(2).strip() if len(m.groups()) > 1 and m.group(2) else "Attached Image"
        dest_file = None
        if base_dir and not src.startswith(("http://", "https://", "data:")):
            local_path = Path(base_dir) / src
            if local_path.is_file() and images_dest_dir:
                dest_file = copy_takeout_image(local_path, images_dest_dir)
            elif local_path.is_file() and not images_dest_dir:
                data_uri = file_to_data_uri(str(local_path))
                if data_uri:
                    return f"\n\n[![{alt}]({data_uri})]({data_uri})\n\n"
        elif src.startswith("data:image/") and images_dest_dir:
            dest_file = save_base64_data_to_file(src, images_dest_dir, preferred_filename=alt)

        if dest_file:
            img_url = f"/images/{dest_file}"
            return f"\n\n[![{alt}]({img_url})]({img_url})\n\n"

        img_url = src if src.startswith(("/images/", "http://", "https://", "data:")) else f"/images/{src}"
        return f"\n\n[![{alt}]({img_url})]({img_url})\n\n"

    s = re.sub(r"<img\s+[^>]*src=[\"\'](.*?)[\"\'][^>]*alt=[\"\'](.*?)[\"\'][^>]*>", img_sub, s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<img\s+[^>]*src=[\"\'](.*?)[\"\'][^>]*>", img_sub, s, flags=re.DOTALL | re.IGNORECASE)

    # 13. Links (<a>)
    s = re.sub(r"<a\s+[^>]*href=[\"\'](.*?)[\"\'][^>]*>(.*?)</a>", lambda m: f"[{m.group(2).strip()}]({m.group(1).strip()})", s, flags=re.DOTALL | re.IGNORECASE)

    # 14. Headings (<h1> to <h6>)
    s = re.sub(r"<h([1-6])[^>]*>(.*?)</h\1>", lambda m: f"\n\n{'#' * int(m.group(1))} {m.group(2).strip()}\n\n", s, flags=re.DOTALL | re.IGNORECASE)

    # 15. Typography & Formatting
    s = re.sub(r"<(?:strong|b)>(.*?)</(?:strong|b)>", r"**\1**", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<(?:em|i)>(.*?)</(?:em|i)>", r"*\1*", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<(?:del|s|strike)>(.*?)</(?:del|s|strike)>", r"~~\1~~", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<sub>(.*?)</sub>", r"~\1~", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<sup>(.*?)</sup>", r"^\1^", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<mark>(.*?)</mark>", r"==\1==", s, flags=re.DOTALL | re.IGNORECASE)

    def save_kbd(m):
        inner = re.sub(r"<[^>]+>", "", m.group(1)).strip()
        idx = len(kbd_blocks)
        kbd_blocks.append(f"<kbd>{inner}</kbd>")
        return f"__KBD_BLOCK_{idx}__"

    s = re.sub(r"<kbd[^>]*>(.*?)</kbd>", save_kbd, s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<abbr\s+[^>]*title=[\"\'](.*?)[\"\'][^>]*>(.*?)</abbr>", r"\2 (\1)", s, flags=re.DOTALL | re.IGNORECASE)

    # 16. Horizontal Rules, Paragraphs, Line Breaks
    s = re.sub(r"<hr\s*/?>", "\n---\n", s, flags=re.IGNORECASE)
    s = re.sub(r"<p[^>]*>(.*?)</p>", lambda m: f"\n\n{m.group(1).strip()}\n\n", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.IGNORECASE)

    # 17. Clean residual HTML tags and unescape entities
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)

    # 18. Restore protected blocks
    for i, t in enumerate(table_blocks):
        s = s.replace(f"__TABLE_BLOCK_{i}__", t)
    for i, svg in enumerate(svg_blocks):
        s = s.replace(f"__SVG_BLOCK_{i}__", svg)
    for i, d in enumerate(details_blocks):
        s = s.replace(f"__DETAILS_BLOCK_{i}__", d)
    for i, m in enumerate(math_blocks):
        s = s.replace(f"__MATH_BLOCK_{i}__", m)
    for i, k in enumerate(kbd_blocks):
        s = s.replace(f"__KBD_BLOCK_{i}__", k)
    for i, b in enumerate(code_blocks):
        s = s.replace(f"__PRE_BLOCK_{i}__", b)
    for i, c in enumerate(inline_codes):
        s = s.replace(f"__INLINE_CODE_{i}__", c)

    # 19. Clean up excess whitespace & normalize code blocks
    s = re.sub(r"\n{3,}", "\n\n", s)
    s = normalize_markdown_code_blocks(s)
    return s.strip()

