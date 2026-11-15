"""
ChatGPT Image Asset Extractor & Linker.
Resolves `image_asset_pointer` and extracts files from archives into LibreChat's images directory.
Part of the Debian Dev Suite.
"""

import os
import shutil
import zipfile
import hashlib
from pathlib import Path
from typing import List, Optional, Tuple

from .image_encoder import guess_image_extension, data_uri_to_bytes


def find_matching_file(asset_id: str, files_on_disk: List[str]) -> Optional[str]:
    """Find a matching file in images directory for the given asset ID."""
    clean_id = asset_id.strip()
    if not clean_id:
        return None

    # 1. Exact match on filename, basename, or stem
    for f in files_on_disk:
        base = Path(f).name
        stem = Path(base).stem
        if f == clean_id or base == clean_id or stem == clean_id:
            return f

    # 2. Filename or basename starts with asset ID (e.g., file-XXXX.png, file-XXXX-sanitized.jpg)
    for f in files_on_disk:
        base = Path(f).name
        if f.startswith(clean_id) or base.startswith(clean_id):
            return f

    # 3. Asset ID contained in filename or path
    for f in files_on_disk:
        if clean_id in f:
            return f

    return None


def normalize_and_index_images(images_dir: Path) -> Tuple[int, int]:
    """
    Scans images_dir recursively to:
    1. Detect real image extensions via magic bytes for .dat or extensionless files.
    2. Hardlink/copy files from subdirectories (e.g. dalle-generations, user-*) to images root.
    Returns: (renamed_count, hardlinked_count)
    """
    if not images_dir.is_dir():
        return 0, 0

    renamed_count = 0
    hardlinked_count = 0

    # Pass 1: Fix extensions (.dat and extensionless files)
    for root, _, files in os.walk(images_dir):
        for f in files:
            if f.startswith("."):
                continue
            fpath = Path(root) / f
            try:
                with open(fpath, "rb") as fp:
                    header = fp.read(16)
                ext = guess_image_extension(header)
                if ext and (fpath.suffix.lower() == ".dat" or not fpath.suffix):
                    target_name = f"{fpath.stem}{ext}" if fpath.suffix else f"{fpath.name}{ext}"
                    target_p = fpath.with_name(target_name)
                    if not target_p.exists():
                        fpath.rename(target_p)
                        renamed_count += 1
            except Exception:
                pass

    # Pass 2: Hardlink subfolder image files to root images_dir
    subdirs = [d for d in images_dir.iterdir() if d.is_dir() and not d.name.startswith(".")]
    for d in subdirs:
        for f in d.iterdir():
            if f.is_file() and not f.name.startswith("."):
                root_target = images_dir / f.name
                if not root_target.exists():
                    try:
                        os.link(f, root_target)
                        hardlinked_count += 1
                    except Exception:
                        try:
                            shutil.copy2(f, root_target)
                            hardlinked_count += 1
                        except Exception:
                            pass

    return renamed_count, hardlinked_count


def extract_images_from_zip(zip_path: Path, dest_dir: Path, dry_run: bool = False) -> int:
    """Extract all image and asset files from a ChatGPT export zip."""
    if not zip_path.is_file():
        print(f"  [✘] Error: Zip file not found at: {zip_path}")
        return 0

    dest_dir.mkdir(parents=True, exist_ok=True)
    extracted_count = 0

    print(f"  [ℹ] Inspecting archive: {zip_path}")
    with zipfile.ZipFile(zip_path, "r") as z:
        for info in z.infolist():
            if info.is_dir():
                continue

            filename = Path(info.filename).name
            lower = filename.lower()

            is_image_asset = (
                filename.startswith("file-") or
                filename.startswith("file_") or
                lower.endswith((".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"))
            )

            if not is_image_asset:
                continue

            dest_file = dest_dir / filename
            if not dry_run:
                with z.open(info) as src:
                    data = src.read()
                if "." not in filename and len(data) >= 16:
                    ext = guess_image_extension(data[:16])
                    if ext:
                        dest_file = dest_dir / f"{filename}{ext}"
                with open(dest_file, "wb") as f_out:
                    f_out.write(data)
                extracted_count += 1
            else:
                extracted_count += 1

    return extracted_count


def extract_images_from_dir(source_dir: Path, dest_dir: Path, dry_run: bool = False) -> int:
    """Copy all image and asset files from an unzipped ChatGPT export folder."""
    if not source_dir.is_dir():
        print(f"  [✘] Error: Source folder not found at: {source_dir}")
        return 0

    dest_dir.mkdir(parents=True, exist_ok=True)
    copied_count = 0

    print(f"  [ℹ] Scanning directory: {source_dir}")
    for root, _, files in os.walk(source_dir):
        for f in files:
            lower = f.lower()
            is_image_asset = (
                f.startswith("file-") or
                f.startswith("file_") or
                lower.endswith((".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"))
            )
            if not is_image_asset:
                continue

            src_file = Path(root) / f
            dest_file = dest_dir / f

            # Detect missing extensions
            if "." not in f:
                try:
                    with open(src_file, "rb") as header_f:
                        header = header_f.read(16)
                    ext = guess_image_extension(header)
                    if ext:
                        dest_file = dest_dir / f"{f}{ext}"
                except Exception:
                    pass

            if not dry_run:
                shutil.copy2(src_file, dest_file)
            copied_count += 1

    return copied_count


def save_base64_data_to_file(
    data_uri: str,
    dest_dir: Path,
    preferred_filename: Optional[str] = None
) -> Optional[str]:
    """
    Saves a base64 data URI to an image file in dest_dir.
    If a file with preferred_filename already exists, reuses it.
    Returns the relative filename (e.g. 'image_02eb44-dbe6d86c216469f4.jpg') or None on error.
    """
    raw_bytes, ext = data_uri_to_bytes(data_uri)
    if not raw_bytes:
        return None

    dest_dir.mkdir(parents=True, exist_ok=True)
    content_hash = hashlib.sha256(raw_bytes).hexdigest()[:16]

    if preferred_filename:
        clean_pref = Path(preferred_filename).name
        target = dest_dir / clean_pref
        if target.is_file():
            return clean_pref
        pref_stem = Path(clean_pref).stem.split("-")[0]
        try:
            for f in os.listdir(dest_dir):
                if f.startswith(pref_stem) and f.endswith(ext):
                    return f
        except Exception:
            pass
        filename = clean_pref if "." in clean_pref else f"{clean_pref}{ext}"
    else:
        filename = f"gemini_img_{content_hash}{ext}"

    dest_file = dest_dir / filename
    if not dest_file.exists():
        with open(dest_file, "wb") as f_out:
            f_out.write(raw_bytes)
    return filename


def copy_takeout_image(
    src_path: Path,
    dest_dir: Path,
    preferred_name: Optional[str] = None
) -> Optional[str]:
    """
    Copies a local Takeout image to dest_dir, avoiding re-copying if identical.
    Returns the relative filename in dest_dir.
    """
    if not src_path.is_file():
        return None

    dest_dir.mkdir(parents=True, exist_ok=True)
    filename = preferred_name or src_path.name

    stem = src_path.stem.split("-")[0]
    try:
        for existing in os.listdir(dest_dir):
            if existing == filename or existing.startswith(stem):
                return existing
    except Exception:
        pass

    dest_file = dest_dir / filename
    if not dest_file.exists():
        shutil.copy2(src_path, dest_file)
    return filename


