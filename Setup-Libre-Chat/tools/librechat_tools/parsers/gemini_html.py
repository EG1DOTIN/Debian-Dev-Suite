"""
Parser for Google Takeout Gemini Activity HTML (MyActivity.html).
Part of the Debian Dev Suite.
"""

import os
import re
import html
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional

from ..common.colors import print_info
from ..common.datetime_parser import parse_iso_or_text_time, describe_date_format, DATE_PATTERN
from ..common.paths import get_librechat_images_dir
from ..converters.html_to_md import html_to_markdown
from ..converters.syntax_highlighter import normalize_markdown_code_blocks
from ..media.image_encoder import file_to_data_uri
from ..media.asset_linker import copy_takeout_image, save_base64_data_to_file


def parse_takeout_html(
    html_str: str,
    base_dir: Optional[str] = None,
    images_dest_dir: Optional[Path] = None
) -> List[Dict[str, Any]]:
    """
    Parses Google Takeout MyActivity.html into distinct conversations.
    Accurately extracts thread IDs, prompt turns, timestamps, and converts response HTML to Markdown.
    Employs universal date detection, resilient response boundary parsing, and static image linking.
    """
    if images_dest_dir is None:
        images_dest_dir = get_librechat_images_dir()

    cards = re.split(r'<div class=[\'"]outer-cell', html_str)[1:]
    threads = {}
    detected_format_reported = False

    for card in cards:
        # Extract thread ID from Details section
        url_match = re.search(r"gemini\.google\.com/app/(?:c/)?([a-zA-Z0-9_-]+)", card)
        conv_id = url_match.group(1) if url_match else None

        # Extract primary content cell
        m = re.search(r"content-cell[^>]*mdl-typography--body-1[\'\"][^>]*>(.*?)<br\s*/?>\s*</div>", card, re.DOTALL)
        if not m:
            continue

        raw_body = m.group(1)
        lines = re.split(r"<br\s*/?>", raw_body)
        if not lines:
            continue

        prompt_line = lines[0].replace("\xa0", " ").strip()
        # Skip Google account telemetry events
        if any(prompt_line.startswith(prefix) for prefix in (
            "Cleared previous", "Gave feedback", "Answered survey", "Created Gemini Canvas"
        )):
            continue

        # Locate timestamp line using universal detection
        date_idx = None
        time_epoch = datetime.now().timestamp()

        # 1. Primary check: DATE_PATTERN
        for idx, l in enumerate(lines[1:], start=1):
            clean_l = l.replace("\xa0", " ").strip()
            if clean_l.startswith(("<p", "<pre", "<ul", "<ol", "<div", "<h", "<table", "<blockquote")):
                break
            d_match = DATE_PATTERN.search(clean_l)
            if d_match:
                date_idx = idx
                time_str = d_match.group(1)
                time_epoch = parse_iso_or_text_time(time_str)
                if not detected_format_reported:
                    detected_format_reported = True
                    print_info(f"Auto-detected Takeout date format: {describe_date_format(time_str)} (sample: '{time_str}')")
                break

        # 2. Secondary check: Structural date line
        if date_idx is None:
            for idx, l in enumerate(lines[1:], start=1):
                clean_l = l.replace("\xa0", " ").strip()
                if clean_l.startswith(("<p", "<pre", "<ul", "<ol", "<div", "<h", "<table", "<blockquote")):
                    break
                if clean_l.startswith(("Attached", "- <a", "<img", "Uploaded")):
                    continue
                if re.search(r"\b(?:19|20)\d{2}\b", clean_l) and re.search(r"\b\d{1,2}:\d{2}\b", clean_l) and len(clean_l) < 120:
                    date_idx = idx
                    time_epoch = parse_iso_or_text_time(clean_l)
                    if not detected_format_reported:
                        detected_format_reported = True
                        print_info(f"Auto-detected Takeout date format: {describe_date_format(clean_l)} (sample: '{clean_l}')")
                    break

        linked_image_stems = set()

        # Extract prompt lines up to date_idx
        if date_idx is not None and date_idx > 0:
            prompt_parts = []
            for pl in lines[:date_idx]:
                clean_pl = pl.replace("\xa0", " ").strip()
                if not clean_pl:
                    continue

                def link_sub(match):
                    href = match.group(1).strip()
                    name = match.group(2).strip()
                    ext = os.path.splitext(href)[1].lower()
                    if ext in (".png", ".jpg", ".jpeg", ".webp", ".gif"):
                        stem = Path(href).stem.split("-")[0]
                        linked_image_stems.add(stem)

                        dest_file = None
                        if base_dir and not href.startswith(("http://", "https://", "data:")):
                            local_img = Path(base_dir) / href
                            if local_img.is_file() and images_dest_dir:
                                dest_file = copy_takeout_image(local_img, images_dest_dir)
                            elif local_img.is_file() and not images_dest_dir:
                                data_uri = file_to_data_uri(str(local_img))
                                if data_uri:
                                    return f"\n\n[![Attached Image: {name}]({data_uri})]({data_uri})\n\n"
                        elif href.startswith("data:image/") and images_dest_dir:
                            dest_file = save_base64_data_to_file(href, images_dest_dir, preferred_filename=name)

                        if dest_file:
                            img_url = f"/images/{dest_file}"
                            return f"\n\n[![Attached Image: {dest_file}]({img_url})]({img_url})\n\n"

                        img_url = href if href.startswith(("/images/", "http://", "https://", "data:")) else f"/images/{href}"
                        return f"\n\n[![Attached Image: {name}]({img_url})]({img_url})\n\n"
                    return f"[{name}]({href})"

                clean_pl = re.sub(r'<a\s+[^>]*href=[\"\'](.*?)[\"\'][^>]*>(.*?)</a>', link_sub, clean_pl, flags=re.IGNORECASE)
                clean_pl = re.sub(r'<[^>]+>', '', clean_pl)
                clean_pl = html.unescape(clean_pl)
                prompt_parts.append(clean_pl)
            full_prompt = "\n".join(prompt_parts)
        else:
            full_prompt = prompt_line

        prompt_text = re.sub(r'^(?:Prompted\s+|Asked\s+Gemini:\s*|Asked\s+Gemini\s+|Asked:\s*)', '', full_prompt, flags=re.IGNORECASE)
        prompt_text = prompt_text.strip(' "\'“”‘’')

        # Also check if card has an image preview thumbnail in the right-hand cell
        img_preview_match = re.search(r'<img\s+[^>]*src=[\"\'](.*?)[\"\'][^>]*class=[\"\']image-preview[\"\']', card, re.IGNORECASE)
        if img_preview_match:
            img_src = img_preview_match.group(1).strip()
            src_stem = Path(img_src).stem.split("-")[0]
            if src_stem not in linked_image_stems and img_src not in prompt_text and f"![{img_src}]" not in prompt_text:
                linked_image_stems.add(src_stem)
                dest_file = None
                if base_dir and not img_src.startswith(("http://", "https://", "data:")):
                    local_img = Path(base_dir) / img_src
                    if local_img.is_file() and images_dest_dir:
                        dest_file = copy_takeout_image(local_img, images_dest_dir)
                    elif local_img.is_file() and not images_dest_dir:
                        data_uri = file_to_data_uri(str(local_img))
                        if data_uri:
                            prompt_text += f"\n\n[![Attached Image: {img_src}]({data_uri})]({data_uri})"
                            dest_file = "data_uri"
                elif img_src.startswith("data:image/") and images_dest_dir:
                    dest_file = save_base64_data_to_file(img_src, images_dest_dir, preferred_filename=img_src)

                if dest_file != "data_uri":
                    if dest_file:
                        img_url = f"/images/{dest_file}"
                        prompt_text += f"\n\n[![Attached Image: {dest_file}]({img_url})]({img_url})"
                    else:
                        img_url = img_src if img_src.startswith(("/images/", "http://", "https://", "data:")) else f"/images/{img_src}"
                        prompt_text += f"\n\n[![Attached Image: {img_src}]({img_url})]({img_url})"

        # 3. Resilient Response Boundary
        if date_idx is not None and date_idx + 1 < len(lines):
            response_html = "<br>".join(lines[date_idx + 1:])
        else:
            resp_idx = None
            for idx, l in enumerate(lines[1:], start=1):
                if l.strip().startswith(("<p", "<pre", "<ul", "<ol", "<div", "<h", "<table", "<blockquote")):
                    resp_idx = idx
                    break
            if resp_idx is not None:
                response_html = "<br>".join(lines[resp_idx:])
            else:
                response_html = ""

        response_md = html_to_markdown(response_html, base_dir=base_dir, images_dest_dir=images_dest_dir)

        if not prompt_text and not response_md:
            continue

        if not conv_id:
            dt = datetime.fromtimestamp(time_epoch)
            conv_id = f"chat_{dt.strftime('%Y%m%d_%H%M%S')}"

        if conv_id not in threads:
            threads[conv_id] = []

        threads[conv_id].append({
            "prompt": prompt_text,
            "response": response_md,
            "time_epoch": time_epoch
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

