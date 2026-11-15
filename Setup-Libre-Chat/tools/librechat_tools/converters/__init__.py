"""Content transformation engines: tables, syntax highlighting, diagrams, and HTML-to-GFM."""
from .syntax_highlighter import detect_code_language, normalize_markdown_code_blocks
from .table_converter import convert_html_table
from .diagram_detector import is_mermaid_content, svg_to_data_uri
from .html_to_md import html_to_markdown

__all__ = [
    "detect_code_language",
    "normalize_markdown_code_blocks",
    "convert_html_table",
    "is_mermaid_content",
    "svg_to_data_uri",
    "html_to_markdown",
]

