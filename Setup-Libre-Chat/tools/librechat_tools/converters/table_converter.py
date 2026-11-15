"""
HTML Table to GitHub-Flavored Markdown (GFM) Converter.
Part of the Debian Dev Suite.
"""

import re
import html


def convert_html_table(table_str: str) -> str:
    """
    Converts an HTML <table> element into a GitHub Flavored Markdown (GFM) table.
    Preserves column alignment (left, center, right), headers (<th>),
    in-cell typography (bold, italic, code, links, del, sup, sub, mark, kbd),
    and properly escapes pipe characters.
    """
    rows = re.findall(r"<tr[^>]*>([\s\S]*?)</tr>", table_str, re.IGNORECASE)
    if not rows:
        return ""

    caption_m = re.search(r"<caption[^>]*>([\s\S]*?)</caption>", table_str, re.IGNORECASE)
    caption_text = ""
    if caption_m:
        caption_text = re.sub(r"<[^>]+>", "", caption_m.group(1)).strip()
        caption_text = html.unescape(caption_text)

    parsed_rows = []
    has_th = False

    for r in rows:
        cells = re.findall(r"<(th|td)([^>]*)>([\s\S]*?)</\1>", r, re.IGNORECASE)
        if not cells:
            continue
        row_data = []
        for tag, attrs, content in cells:
            if tag.lower() == "th":
                has_th = True
            align = "left"
            align_m = re.search(r'align=[\'"](left|center|right)[\'"]', attrs, re.IGNORECASE)
            if not align_m:
                align_m = re.search(r'text-align:\s*(left|center|right)', attrs, re.IGNORECASE)
            if align_m:
                align = align_m.group(1).lower()

            c_text = re.sub(r"<br\s*/?>", "<br>", content, flags=re.IGNORECASE)
            c_text = re.sub(r"<a\s+[^>]*href=[\"'](.*?)[\"'][^>]*>(.*?)</a>", r"[\2](\1)", c_text, flags=re.IGNORECASE)
            c_text = re.sub(r"<(?:strong|b)>(.*?)</(?:strong|b)>", r"**\1**", c_text, flags=re.IGNORECASE)
            c_text = re.sub(r"<(?:em|i)>(.*?)</(?:em|i)>", r"*\1*", c_text, flags=re.IGNORECASE)
            c_text = re.sub(r"<code>(.*?)</code>", r"`\1`", c_text, flags=re.IGNORECASE)
            c_text = re.sub(r"<(?:del|s|strike)>(.*?)</(?:del|s|strike)>", r"~~\1~~", c_text, flags=re.IGNORECASE)
            c_text = re.sub(r"<sub>(.*?)</sub>", r"~\1~", c_text, flags=re.IGNORECASE)
            c_text = re.sub(r"<sup>(.*?)</sup>", r"^\1^", c_text, flags=re.IGNORECASE)
            c_text = re.sub(r"<mark>(.*?)</mark>", r"==\1==", c_text, flags=re.IGNORECASE)
            c_text = re.sub(r"<kbd>(.*?)</kbd>", r"<kbd>\1</kbd>", c_text, flags=re.IGNORECASE)
            c_text = re.sub(r"<[^>]+>", "", c_text)
            c_text = html.unescape(c_text).strip()
            c_text = re.sub(r"\r?\n+", " ", c_text)
            c_text = c_text.replace("|", "\\|")
            row_data.append((c_text, align))
        if row_data:
            parsed_rows.append(row_data)

    if not parsed_rows:
        return ""

    num_cols = max(len(r) for r in parsed_rows)
    col_aligns = ["left"] * num_cols
    for r in parsed_rows:
        for idx, (val, al) in enumerate(r):
            if al != "left" and idx < num_cols:
                col_aligns[idx] = al

    lines = []
    if caption_text:
        lines.append(f"**Table: {caption_text}**\n")

    header_row = [r[0] for r in parsed_rows[0]]
    while len(header_row) < num_cols:
        header_row.append("")
    lines.append("| " + " | ".join(header_row) + " |")

    sep_cols = []
    for al in col_aligns:
        if al == "center":
            sep_cols.append(":---:")
        elif al == "right":
            sep_cols.append("---:")
        else:
            sep_cols.append(":---")
    lines.append("| " + " | ".join(sep_cols) + " |")

    data_rows = parsed_rows[1:] if (has_th or len(parsed_rows) > 1) else []
    for r in data_rows:
        row_vals = [c[0] for c in r]
        while len(row_vals) < num_cols:
            row_vals.append("")
        lines.append("| " + " | ".join(row_vals) + " |")

    return "\n\n" + "\n".join(lines) + "\n\n"

