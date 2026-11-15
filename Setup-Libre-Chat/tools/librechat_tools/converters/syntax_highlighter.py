"""
Syntax Highlighting & Language Inference for Markdown Code Blocks.
Part of the Debian Dev Suite.
"""

import re
import json

# Mermaid diagram keywords
MERMAID_KEYWORDS = (
    "graph ", "graph\n", "graph\r\n", "flowchart ", "flowchart\n", "flowchart\r\n",
    "sequenceDiagram", "classDiagram", "stateDiagram", "erDiagram",
    "gantt", "pie ", "pie\n", "pie\r\n", "gitGraph", "journey", "mindmap",
    "timeline", "zenuml", "sankey-beta", "xychart-beta", "quadrantChart",
    "architecture-beta", "packet-beta", "kanban", "block-beta"
)

# Language normalization aliases
LANG_MAP = {
    "mermaid": "mermaid",
    "diagram": "mermaid",
    "chart": "mermaid",
    "js": "javascript",
    "ts": "typescript",
    "jsx": "jsx",
    "tsx": "tsx",
    "react": "jsx",
    "py": "python",
    "py3": "python",
    "c++": "cpp",
    "cpp": "cpp",
    "c": "c",
    "h": "c",
    "hpp": "cpp",
    "cs": "csharp",
    "c#": "csharp",
    "sh": "bash",
    "shell": "bash",
    "zsh": "bash",
    "bash": "bash",
    "html": "html",
    "htm": "html",
    "xml": "xml",
    "svg": "xml",
    "css": "css",
    "scss": "scss",
    "sass": "sass",
    "md": "markdown",
    "markdown": "markdown",
    "yml": "yaml",
    "yaml": "yaml",
    "json": "json",
    "sql": "sql",
    "docker": "dockerfile",
    "dockerfile": "dockerfile",
    "txt": "text",
    "text": "text",
    "plaintext": "text",
}


def detect_code_language(code: str) -> str:
    """
    Infers the programming language of a code block to prevent highlight.js
    from erroneously guessing 'vbnet', 'less', or other obscure grammars.
    Supports mermaid diagrams, html, python, cpp, javascript, jsx, tsx, css,
    markdown, bash, json, yaml, sql, dockerfile, ini, and defaults cleanly to 'text'.
    """
    code_strip = code.strip()
    if not code_strip:
        return "text"

    # 0. Mermaid Diagrams
    first_non_empty = [l.strip() for l in code_strip.split("\n") if l.strip()]
    if first_non_empty and any(first_non_empty[0].startswith(kw) for kw in MERMAID_KEYWORDS):
        return "mermaid"

    # 1. JSON
    if (code_strip.startswith("{") and code_strip.endswith("}")) or (code_strip.startswith("[") and code_strip.endswith("]")):
        try:
            json.loads(code_strip)
            return "json"
        except Exception:
            pass

    # 2. YAML
    if re.search(r"^---\s*$", code_strip, re.MULTILINE):
        return "yaml"
    yaml_lines = [l for l in code_strip.split("\n") if l.strip() and not l.strip().startswith("#")]
    if len(yaml_lines) >= 2 and all(re.match(r"^\s*(?:-\s+|\w[\w\.\-]*:\s*)", l) for l in yaml_lines[:6]):
        if any(":" in l for l in yaml_lines):
            return "yaml"

    # 3. Dockerfile
    if re.search(r"^(?:FROM|WORKDIR|COPY|ADD|RUN|CMD|ENTRYPOINT|EXPOSE|ENV|ARG)\s+", code_strip, re.MULTILINE):
        return "dockerfile"

    # 4. Markdown (Tables, Headings with links/lists, task lists)
    if re.search(r"\|(?:\s*[-:]+\s*\|)+", code_strip):
        return "markdown"
    if re.search(r"^#{1,6}\s+\S+", code_strip, re.MULTILINE) and (
        re.search(r"\[.+?\]\(.+?\)", code_strip) or
        re.search(r"^\s*[-*]\s+\S+", code_strip, re.MULTILINE) or
        re.search(r"^\s*\d+\.\s+\S+", code_strip, re.MULTILINE)
    ):
        return "markdown"

    # 5. React / JSX / TSX (MUST evaluate before HTML and generic JS)
    react_patterns = [
        r"\bimport\s+React\b",
        r"\bfrom\s+[\"']react(?:-[a-z]+)?[\"']",
        r"\bReact\.(?:FC|Component|PureComponent|ReactNode|memo)\b",
        r"\buse(?:State|Effect|Context|Reducer|Callback|Memo|Ref|Id|Navigate|Location)\s*\(",
        r"<\w+\s+[^>]*className=[\"']",
        r"<\w+\s+[^>]*onClick=\{",
        r"<\w+\s+[^>]*onChange=\{",
        r"=>\s*\(?\s*<\w+",
        r"return\s*\(?\s*<\w+",
    ]
    if any(re.search(pat, code_strip) for pat in react_patterns):
        if re.search(r":\s*React\.(?:FC|ReactNode)|interface\s+\w+\s*\{|<[A-Z]\w+>\s*\(", code_strip):
            return "tsx"
        return "jsx"

    # 6. HTML / XML / SVG
    html_pattern = r"<(?:!DOCTYPE|html|head|body|div|span|p|a|button|input|textarea|select|table|thead|tbody|tr|td|th|ul|ol|li|h[1-6]|form|header|footer|nav|section|article|main|script|style|svg)\b[^>]*>"
    if re.search(html_pattern, code_strip, re.IGNORECASE) and ("</" in code_strip or "/>" in code_strip):
        return "html"
    if code_strip.startswith("<?xml") or code_strip.startswith("<svg"):
        return "xml"

    # 7. CSS / SCSS
    if re.search(r"(?:[.#]?[\w\-]+|\*|body|html|div|span|p|a|ul|li|h[1-6])\s*\{[^}]*\}", code_strip) and re.search(
        r"\b(?:color|background(?:-color)?|margin(?:-[a-z]+)?|padding(?:-[a-z]+)?|font(?:-[a-z]+)?|display|flex(?:-[a-z]+)?|grid(?:-[a-z]+)?|border(?:-[a-z]+)?|width|height|position|top|left|right|bottom|opacity|transform|transition|box-shadow|z-index|line-height|text-align)\s*:",
        code_strip
    ):
        return "css"
    if re.search(r"@(?:media|keyframes|import)\b", code_strip):
        return "css"

    # 8. TypeScript
    ts_patterns = [
        r"\binterface\s+\w+(?:\s+extends\s+\w+)?\s*\{",
        r"\btype\s+[A-Z]\w*\s*=",
        r":\s*(?:string|number|boolean|any|void|unknown|never)(?:\[\])?\s*[=;,\)]",
        r"\bas\s+const\b",
    ]
    if any(re.search(pat, code_strip) for pat in ts_patterns):
        return "typescript"

    # 9. C / C++ / Arduino
    cpp_patterns = [
        r"#include\s+[<\"].+[>\"]",
        r"#define\s+\w+",
        r"\b(?:Serial\.(?:print|println|begin|available|read)|LittleFS|WiFi|WebServer)\b",
        r"\b(?:void|int|bool|float|double|char)\s+(?:setup|loop)\s*\(",
        r"\b(?:void|int|bool|float|double|char)\s+\w+::\w+\s*\(",
        r"\b(?:uint8_t|uint16_t|uint32_t|int16_t|int32_t|size_t)\b",
        r"\b(?:nullptr|std::|va_list|va_start|va_end|sprintf|printf|malloc|free)\b",
        r"\b(?:cout\s*<<|cin\s*>>|endl\b)",
        r"\b(?:vector|map|unordered_map|pair|set)<",
        r"\busing\s+namespace\s+std\b",
        r"\b(?:public|private|protected)\s*:",
        r"\bclass\s+\w+\s*\{[^\}]*\b(?:public|private|protected)\s*:",
        r"\bAppLogger\b",
    ]
    if any(re.search(pat, code_strip) for pat in cpp_patterns):
        return "cpp"

    # 10. Python
    py_patterns = [
        r"\bdef\s+\w+\s*\(.*?\):",
        r"\bclass\s+\w+(?:\(.*?\))?:",
        r"\bfrom\s+\w+\s+import\s+",
        r"\bimport\s+(?:sys|os|re|json|datetime|math|numpy|pandas|tensorflow|torch|requests|fastapi|flask|django)\b",
        r"\bif\s+__name__\s*==\s*[\"']__main__[\"']:",
        r"\bprint\s*\(.*?\)",
        r"\b(?:elif|except|finally)\s*.*?:",
        r"\b(?:pd\.|np\.|plt\.)\w+",
        r"\bself\.\w+",
        r"\b(?:True|False|None)\b",
        r"\[.+?\s+for\s+\w+\s+in\s+.+?\]",
        r"\b(?:range|enumerate|len)\s*\(",
    ]
    if any(re.search(pat, code_strip, re.MULTILINE) for pat in py_patterns):
        return "python"

    # 11. JavaScript / Google Apps Script
    js_patterns = [
        r"\bfunction\s+\w*\s*\(",
        r"\b(?:const|let|var)\s+\w+\s*=",
        r"\bconsole\.(?:log|error|warn|info)\b",
        r"\b(?:document\.|window\.|localStorage\.)",
        r"\b(?:Utilities\.|SpreadsheetApp\.|ContentService\.|Charts\.|PropertiesService\.)",
        r"=>\s*\{?",
        r"\b(?:export\s+default|export\s+const|import\s+.*?from\s+[\"'])",
        r"\btypeof\s+\w+",
    ]
    if any(re.search(pat, code_strip) for pat in js_patterns):
        return "javascript"

    # 12. SQL
    sql_patterns = [
        r"\b(?:SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|CREATE\s+TABLE|ALTER\s+TABLE|DROP\s+TABLE)\b",
    ]
    if any(re.search(pat, code_strip, re.IGNORECASE) for pat in sql_patterns):
        return "sql"

    # 13. Bash / Shell
    first_line = code_strip.split("\n")[0].strip()
    if re.match(r"^(?:pip\d?|npm|npx|yarn|pnpm|git|docker|sudo|apt|apt-get|brew|curl|wget|chmod|chown|mkdir|cd|cat|ls|rm|echo|systemctl|service|grep|find|sed|awk)\s+", first_line) or first_line.startswith(("$ ", "#!", "> ")):
        return "bash"

    # 14. INI / Config
    if re.match(r"^\[[\w:\-\.]+\]", first_line) and "=" in code_strip:
        return "ini"

    # Safe default: 'text' explicitly disables highlight.js auto-detection of 'vbnet' or 'less'
    return "text"


def normalize_markdown_code_blocks(text: str) -> str:
    """
    Scans markdown text for code fences (```) and ensures every block has a valid,
    clean language tag (e.g. python, cpp, javascript, jsx, tsx, html, css, bash,
    json, yaml, sql, markdown, text).
    Maps common language aliases and resolves blank code blocks or erroneous highlight.js auto-guesses.
    """
    if not text or "```" not in text:
        return text

    def replacer(m):
        raw_lang = m.group(1).strip().lower()
        code_body = m.group(2)

        if raw_lang in LANG_MAP:
            target_lang = LANG_MAP[raw_lang]
        elif raw_lang in ("vbnet", "vb", "less", "apache"):
            detected = detect_code_language(code_body)
            target_lang = detected if detected != "text" else raw_lang
        elif raw_lang:
            target_lang = raw_lang
        else:
            target_lang = detect_code_language(code_body)

        return f"```{target_lang}\n{code_body}```"

    return re.sub(r"```([a-zA-Z0-9_+-]*)[ \t]*\n([\s\S]*?)```", replacer, text)

