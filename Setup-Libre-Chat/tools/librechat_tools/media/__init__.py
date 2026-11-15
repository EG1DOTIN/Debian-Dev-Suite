"""Media handling: image data URI encoding, magic bytes detection, and ChatGPT asset linking."""
from .image_encoder import file_to_data_uri, guess_image_extension
from .asset_linker import find_matching_file, extract_images_from_zip, extract_images_from_dir

__all__ = [
    "file_to_data_uri",
    "guess_image_extension",
    "find_matching_file",
    "extract_images_from_zip",
    "extract_images_from_dir",
]

