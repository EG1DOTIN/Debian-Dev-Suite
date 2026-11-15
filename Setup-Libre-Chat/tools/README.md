# LibreChat Utility Tools & Helper Scripts

This directory contains standalone, lightweight automation tools for managing, organizing, migrating, and optimizing your local [LibreChat](../README.md) deployment.

All tools follow the **Debian Dev Suite** core standards:
- **100% Localhost Isolated** (`127.0.0.1`)
- **Absolute 0 Telemetry**
- **Zero External Dependencies** (Uses Python standard library & standard bash)
- **Non-Root Friendly**

---

## Tool Overview

| Tool | Type | Purpose | Primary Command |
|---|---|---|---|
| [`gemini-to-librechat.py`](gemini-to-librechat.py) | Python CLI | Convert Google Gemini exports (JSON/HTML) to LibreChat | `python3 gemini-to-librechat.py -i MyActivity.json` |
| [`fix-chatgpt-images.py`](fix-chatgpt-images.py) | Python CLI | Restore & link attached images from ChatGPT data exports | `python3 fix-chatgpt-images.py --status` |
| [`batch-folder-organizer.py`](batch-folder-organizer.py) | Python CLI | Auto-folder organizer & 0-RAM offline message search | `python3 batch-folder-organizer.py --list` |
| [`toggle-meilisearch.sh`](toggle-meilisearch.sh) | Bash CLI | Turn native in-app search (Ctrl+K) on/off on demand | `./toggle-meilisearch.sh --status` |
| [`librechat_tools/`](librechat_tools/) | Python Package | Modular engine powering conversion, parsing, and storage | Internal architecture |

---

## Modular Architecture (`librechat_tools/`)

All Python utilities are powered by the modular `librechat_tools` package adhering to the Single Responsibility Principle (SRP):

```text
tools/
├── librechat_tools/
│   ├── common/              # Terminal colors, date parsers, Takeout format detector
│   │   ├── colors.py
│   │   └── datetime_parser.py
│   ├── converters/          # Content transformation engines
│   │   ├── syntax_highlighter.py
│   │   ├── table_converter.py
│   │   ├── diagram_detector.py
│   │   └── html_to_md.py
│   ├── media/               # Image encoder, magic bytes sniffer, asset linker
│   │   ├── image_encoder.py
│   │   └── asset_linker.py
│   ├── parsers/             # Specialized export format parsers & auto-router
│   │   ├── gemini_json.py
│   │   ├── gemini_html.py
│   │   ├── ai_studio.py
│   │   ├── generic_json.py
│   │   ├── markdown_chat.py
│   │   └── router.py
│   ├── storage/             # JSON schema builders & MongoDB driver
│   │   ├── json_exporter.py
│   │   └── mongo_client.py
│   └── cli/                 # Independent CLI command handlers
│       ├── gemini_migrator_cli.py
│       ├── chatgpt_images_cli.py
│       └── folder_organizer_cli.py
├── gemini-to-librechat.py    # Lightweight entrypoint (re-exports API)
├── fix-chatgpt-images.py     # Lightweight entrypoint
└── batch-folder-organizer.py # Lightweight entrypoint
```

---

### 1. `batch-folder-organizer.py`
High-performance MongoDB organizer and instant message search tool.

* **List status & project folders:**
  ```bash
  python3 batch-folder-organizer.py --list
  ```

* **Instant Offline Message Search (0 MB extra RAM):**
  Searches across all 17,000+ messages and tags matches with a temporary bookmark (`🔍 <query>`) so you can filter them in the LibreChat UI:
  ```bash
  python3 batch-folder-organizer.py --search "quantum"
  python3 batch-folder-organizer.py --clear-search
  ```

* **Batch Assign Chats to Folders:**
  ```bash
  # Move all untagged conversations into a sidebar project folder
  python3 batch-folder-organizer.py --folder "Personal" --all-untagged

  # Move conversations matching keywords into a project folder
  python3 batch-folder-organizer.py --folder "Work" --match "python|project|docker" --prefix-title
  ```

* **Permanent Folder & Chat Deletion (Destructive):**
  Permanently purges all conversation records and individual messages inside a specific folder:
  ```bash
  # 1. Delete all chats in a folder AND remove the folder from sidebar:
  python3 batch-folder-organizer.py --delete-folder "FolderName"

  # 2. Delete all chats in a folder but KEEP the empty folder shell:
  python3 batch-folder-organizer.py --delete-chats "FolderName" --keep-folder

  # 3. Skip interactive confirmation prompt:
  python3 batch-folder-organizer.py --delete-folder "FolderName" --yes
  ```

* **Full CLI Parameters Reference (`batch-folder-organizer.py`):**
  | Parameter | Aliases | Description |
  |---|---|---|
  | `--list` | `-l` | List all sidebar project folders, bookmark tags, unassigned chats, and recent activity |
  | `--search <query>` | `-s` | Instant regex search across messages, tagging matches with bookmark |
  | `--in-folder <name>` | | Scope search to a specific project folder |
  | `--bookmark <tag>` | | Custom bookmark tag label for search results (default: `🔍 <query>`) |
  | `--clear-search [tag]` | | Remove all temporary `🔍` search bookmarks from MongoDB (or clear a specific tag) |
  | `--folder <name>` | `-F`, `--tag` | Target sidebar project folder name |
  | `--all-untagged` | `-u` | Apply folder assignment to all untagged/unassigned chats |
  | `--match <regex>` | `-m` | Regex keyword pattern to match conversation titles |
  | `--prefix-title` | `-p` | Prepend `[Folder]` label to conversation titles in database |
  | `--file <path>` | `-f` | Pre-process an export JSON file before importing |
  | `--output <path>` | `-o` | Custom output path for prepared JSON (used with `--file`) |
  | `--remove-folder <name>` | `--untag` | Remove a folder shell (unassigns its chats back to root) |
  | `--delete-folder <name>` | | Permanently purge a folder AND all its conversations/messages |
  | `--delete-chats <name>` | | Permanently purge all chats in a folder but keep the empty shell |
  | `--keep-folder` | | Flag used with `--delete-chats` to preserve the folder shell |
  | `-y`, `--yes` | | Skip interactive confirmation prompts for destructive actions |

---

### 2. `gemini-to-librechat.py`
Parses and reconstructs chat threads from Google Takeout (`MyActivity.json` or `MyActivity.html`), Google AI Studio, or browser extensions, mapping them into standard LibreChat-importable JSON.

* **Advanced Rich HTML & Diagram Engine:**
  - **Tables (`<table>`)**: Converts HTML tables into clean GitHub Flavored Markdown (GFM) tables (`| ... |`) with column alignment (`:---:`, `:---`, `---:`), `<th>` headers, and pipe escaping.
  - **Diagrams (Mermaid)**: Detects flowcharts, sequence diagrams, class diagrams, state diagrams, ER diagrams, mindmaps, and timelines, wrapping them into native ```` ```mermaid ```` code blocks.
  - **Vector Graphics (`<svg>`)**: Automatically encodes inline SVG diagrams into clickable Base64 data URIs.
  - **Alerts & Callouts**: Converts `<div class="callout ...">` and alert boxes into GitHub Markdown alerts (`> [!NOTE]`, `> [!WARNING]`, `> [!TIP]`, `> [!IMPORTANT]`, `> [!CAUTION]`).
  - **Lists**: Supports ordered lists (`<ol start="N">`), task checkboxes (`* [x] `, `* [ ] `), and definition lists (`<dl>`, `<dt>`, `<dd>`).
  - **Collapsible Details**: Formats `<details><summary>` blocks into clean collapsible markdown.
  - **Math & Typography**: Preserves LaTeX `<math>` equations, `<kbd>` keyboard badges, `==mark==` highlights, `~~strikethrough~~`, subscripts, and superscripts.

* **Convert Takeout Archive:**
  ```bash
  python3 gemini-to-librechat.py -i ~/Downloads/Takeout/ -o conversations_gemini.json -f "Gemini"
  ```

* **Convert Specific File:**
  ```bash
  python3 gemini-to-librechat.py -i MyActivity.json -o conversations_gemini.json
  python3 gemini-to-librechat.py -i MyActivity.html -o conversations_gemini.json
  ```

* **Full CLI Parameters Reference (`gemini-to-librechat.py`):**
  | Parameter | Default | Description |
  |---|---|---|
  | `-i`, `--input <path>` | *(required)* | Input Gemini export file (`MyActivity.json`, `MyActivity.html`, AI Studio JSON) or Takeout directory |
  | `-o`, `--output <file>` | `conversations_gemini.json` | Output JSON file for LibreChat |
  | `-f`, `--folder <name>` | `Gemini` | Prefix conversation titles with folder label (e.g. `[Gemini] Title`) |
  | `-m`, `--model <name>` | `Gemini` | Model name label assigned to assistant messages |
  | `--format {chatgpt,claude}` | `chatgpt` | Target import schema format recognized by LibreChat |
  | `--images-dir <path>` | *(auto)* | LibreChat static images directory (defaults to `librechat-data/images`) |

---

### 3. `fix-chatgpt-images.py`
Restores and renders attached images from ChatGPT and Google Gemini exports in LibreChat.

OpenAI exports images as separate files (`file-*` or `file_*`), referencing them in `conversations.json` as `image_asset_pointer` objects. Google Gemini exports often contain raw Base64 data URIs or local image filenames. This tool extracts/copies the images into LibreChat's static images folder (`librechat-data/images/`) and links MongoDB messages with clickable, lightweight Markdown thumbnails served via `/images/`.

* **Audit Image Status & Missing Assets:**
  ```bash
  python3 fix-chatgpt-images.py --status
  ```

* **Extract & Auto-Link Images from ChatGPT `.zip` Export:**
  ```bash
  python3 fix-chatgpt-images.py --from-zip ~/Downloads/chatgpt_export.zip
  ```

* **Copy & Auto-Link Images from Extracted Folder:**
  ```bash
  python3 fix-chatgpt-images.py --from-dir ~/Downloads/chatgpt_extracted/
  ```

* **Scan MongoDB & Link Images Placed Manually in Images Directory:**
  ```bash
  python3 fix-chatgpt-images.py --link-db
  ```

* **Clean Up Unresolved Raw JSON Blocks into Elegant Markdown Placeholders:**
  ```bash
  python3 fix-chatgpt-images.py --clean-placeholders
  ```

* **Pre-process `conversations.json` Before Importing into LibreChat:**
  ```bash
  python3 fix-chatgpt-images.py --prepare-file conversations.json -o conversations_ready.json
  ```

* **Full CLI Parameters Reference (`fix-chatgpt-images.py`):**
  | Parameter | Aliases | Description |
  |---|---|---|
  | `--status` | | Display status audit of disk images and MongoDB pointer blocks |
  | `--link-db` | `--scan-mongo` | Scan MongoDB and link image files on disk to chat messages |
  | `--from-zip` | | Extract images from a ChatGPT export `.zip` and link them in MongoDB |
  | `--from-dir` | | Copy images from an unzipped ChatGPT export folder and link them in MongoDB |
  | `--clean-placeholders`| `--clean-missing`| Convert unresolved JSON pointer blocks into clean Markdown notes |
  | `--prepare-file` | `--prepare` | Pre-process ChatGPT `conversations.json` before importing into LibreChat |
  | `-o`, `--output` | | Output path for prepared JSON (used with `--prepare-file`) |
  | `--images-dir` | | Custom LibreChat images directory (defaults to `librechat-data/images`) |
  | `--dry-run` | | Preview actions without modifying database or files |
  | `-y`, `--yes` | | Skip interactive confirmation prompts |

---

### 4. `toggle-meilisearch.sh`
Manages the native full-text search daemon (MeiliSearch) for LibreChat.

* **Enable native search bar (`Ctrl+K`):**
  ```bash
  ./toggle-meilisearch.sh --enable
  ```

* **Check status & RAM consumption:**
  ```bash
  ./toggle-meilisearch.sh --status
  ```

* **Disable to free ~200MB RAM:**
  ```bash
  ./toggle-meilisearch.sh --disable
  ```

