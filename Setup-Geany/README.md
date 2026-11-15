# Universal Geany IDE & Developer Setup for Debian-based Systems

A lightweight, robust, and 100% open-source development environment for **Debian, antiX, Ubuntu, Linux Mint, MX Linux, Devuan**, and any Debian-based distribution.

Configures the **Geany IDE** with a curated suite of developer plugins for **Python, C/C++, HTML, CSS, and JavaScript**, including live Markdown document viewing, project tree browsing, open-source color schemes, and an ultra-lightweight **AI Copilot** powered by local or remote LLMs.

---

## Table of Contents

- [What, Why, and How](#what-why-and-how)
  - [What is this?](#what-is-this)
  - [Why Geany? (The Lightweight Champion)](#why-geany-the-lightweight-champion)
  - [How does it work?](#how-does-it-work)
- [Component & Plugin Audit Matrix](#component--plugin-audit-matrix)
- [Prerequisites (System Clock & Repositories)](#prerequisites-system-clock--repositories)
- [Installation Guide (`--install`)](#installation-guide---install)
  - [1. Run the Installer](#1-run-the-installer)
  - [2. What the Installer Configures](#2-what-the-installer-configures)
- [Developer Workflow & Plugin Guide](#developer-workflow--plugin-guide)
  - [1. Markdown Document Viewer](#1-markdown-document-viewer)
  - [2. Project Management (Open Folder as Project)](#2-project-management-open-folder-as-project)
  - [3. Coding in Python, C/C++, HTML, CSS, and JavaScript](#3-coding-in-python-cc-html-css-and-javascript)
  - [4. Selecting Color Themes](#4-selecting-color-themes)
- [AI Copilot Setup & Usage Guide](#ai-copilot-setup--usage-guide)
  - [How It Works (Ultra-Lightweight & Zero-Telemetry)](#how-it-works-ultra-lightweight--zero-telemetry)
  - [How to Enable GeanyLua](#how-to-enable-geanylua)
  - [Using AI Copilot](#using-ai-copilot)
  - [Configuring the AI Backend (`geany-copilot.conf`)](#configuring-the-ai-backend-geany-copilotconf)
  - [Connecting to Local `llama.cpp` (This Repo's Server)](#connecting-to-local-llamacpp-this-repos-server)
  - [Connecting to Local Ollama](#connecting-to-local-ollama)
  - [Connecting to Remote OpenAI-Compatible APIs](#connecting-to-remote-openai-compatible-apis)
  - [Setting Up a Keyboard Shortcut](#setting-up-a-keyboard-shortcut)
- [Managing Your Setup](#managing-your-setup)
  - [Checking Status (`--status`)](#checking-status---status)
  - [Updating Packages & Scripts (`--update`)](#updating-packages--scripts---update)
  - [Uninstallation (`--uninstall`)](#uninstallation---uninstall)
- [Troubleshooting & FAQs](#troubleshooting--faqs)

---

## What, Why, and How

### What is this?
A smart, modular setup script (`setup-geany.sh`) that installs, configures, updates, and manages the Geany Integrated Development Environment along with a carefully audited set of developer plugins, color schemes, and an offline-first AI coding copilot.

### Why Geany? (The Lightweight Champion)
Modern code editors like Visual Studio Code or JetBrains IDEs are built on top of heavy runtimes (Electron / Chromium / Java). On older hardware or lightweight distributions:
- **VS Code:** Consumes **600 MB–1200 MB of RAM** at idle and takes 5–15 seconds to launch.
- **Geany:** Written in pure C and GTK3. It starts in **under 1 second** and consumes only **15 MB–35 MB of RAM**.

This makes Geany the ultimate IDE for developers on resource-constrained systems (e.g. 2 GB–3 GB RAM, Intel Pentium / Core 2 Duo) as well as modern power-users who want instant responsiveness without background bloat.

### How does it work?
1. Fetches official Debian-packaged binaries (`geany`, `geany-plugins`).
2. Configures sensible developer defaults (tab-to-spaces, strip trailing whitespace on save, line numbering).
3. Installs community-standard open-source dark themes (Dracula, Monokai, Solarized Dark, Gruvbox, Nord).
4. Deploys an ultra-lightweight, native Lua AI Copilot script that sends code prompts to any local or remote OpenAI-compatible HTTP server using standard `curl`.

---

## Component & Plugin Audit Matrix

Every component installed by this script has been strictly audited against four core pillars: **Open-Source**, **Lightweight**, **Security**, and **Privacy (Zero Telemetry)**:

| Component / Plugin | Key Features & Purpose | Open-Source & License | Lightweight Profile | Security Criteria | Privacy Focused |
|---|---|---|---|---|---|
| **Geany IDE Core** | Fast, tabbed code editor with syntax highlighting, symbol list, and terminal. | 100% FOSS (GPL-2.0-or-later) | **~15–30 MB RAM**; instant sub-second cold start. | Native Linux GTK3 binary from trusted Debian repos. No remote script execution. | **Zero Telemetry.** Never calls home or sends usage statistics. |
| **Markdown Preview** (`geany-plugin-markdown`) | Live document viewer and HTML preview for `.md` files directly inside Geany. | 100% FOSS (GPL-2.0-or-later) | **~1–2 MB RAM**; lightweight WebKit/cmark renderer. | Runs completely offline. No remote assets or tracking pixels. | **Zero Telemetry.** Renders markdown files strictly locally. |
| **Project Organizer** (`geany-plugin-projectorganizer`) | Opens folders as projects, sidebar tree view, project-wide symbol and file search. | 100% FOSS (GPL-2.0-or-later) | **~2 MB RAM**; background file indexing with negligible CPU. | Local filesystem inspection only. Respects file permissions. | **Zero Telemetry.** All indexing remains in local RAM/cache. |
| **Tree Browser** (`geany-plugin-treebrowser`) | Fast alternative directory tree view in the sidebar. | 100% FOSS (GPL-2.0-or-later) | **< 1 MB RAM**; on-demand directory expansion. | Standard POSIX directory listing (`opendir`/`readdir`). | **Zero Telemetry.** Purely local filesystem tool. |
| **Auto-Close** (`geany-plugin-autoclose`) | Auto-closes `()`, `{}`, `[]`, `""`, `''` for Python, C/C++, HTML, CSS, JS. | 100% FOSS (GPL-2.0-or-later) | **Zero overhead**; triggered on keypress hooks. | In-memory text buffer manipulation only. | **Zero Telemetry.** Completely offline editor utility. |
| **Git ChangeBar** (`geany-plugin-git-changebar`) | Displays real-time diff indicators (added, modified, deleted lines) in editor gutter. | 100% FOSS (GPL-2.0-or-later) | **< 2 MB RAM**; reads local `.git` index. | Read-only access to local git repository. Never pushes or pulls. | **Zero Telemetry.** Completely offline git inspection. |
| **LSP Client** (`geany-plugin-lsp`) | Language Server Protocol client for autocomplete, diagnostics, and definition lookup. | 100% FOSS (GPL-2.0-or-later) | **~5–10 MB RAM** (client only; connects to local language servers). | Connects to local UNIX sockets or stdio of installed language servers. | **Zero Telemetry.** No remote server communication unless configured by user. |
| **Code Navigation** (`geany-plugin-codenav`) | Fast navigation to function, class, and variable definitions. | 100% FOSS (GPL-2.0-or-later) | **< 1 MB RAM**; uses Geany's built-in tag manager. | In-memory tag search across open files. | **Zero Telemetry.** 100% local operation. |
| **Line Operations** (`geany-plugin-lineoperations`) | Sort lines alphabetically, remove duplicates, trim trailing spaces, join lines. | 100% FOSS (GPL-2.0-or-later) | **Zero overhead**; fast in-memory string buffer algorithms. | In-memory text transformation. | **Zero Telemetry.** 100% offline. |
| **Lipsum & Spellcheck** (`geany-plugin-lipsum`, `geany-plugin-spellcheck`) | Lorem ipsum placeholder text generator for web design and inline spellchecker. | 100% FOSS (GPL-2.0-or-later) | **< 2 MB RAM**; uses local Hunspell/Enchant dictionaries. | Offline dictionary lookup only. | **Zero Telemetry.** Never transmits typed text over the network. |
| **Geany Themes** | Dracula, Monokai, Solarized Dark, Gruvbox, and Nord color schemes. | 100% FOSS (MIT / GPL) | **Zero RAM/CPU overhead**; static `.conf` color definitions. | Static text configuration files. No executable code. | **Zero Telemetry.** Plain color styling. |
| **Geany AI Copilot** (`geanylua` + `curl`) | AI code generation, completion, and explanation from selected text or cursor position. | 100% FOSS (MIT / GPL) | **< 0.5 MB RAM**; pure Lua script executed on-demand via native GeanyLua. | Uses standard `curl`. Defaults to `localhost`. No background daemons. | **100% Private (Local-First).** Connects directly to `localhost` with zero external calls unless user supplies cloud API key. |

---

## Prerequisites (System Clock & Repositories)

> [!IMPORTANT]
> **Check your system clock before running the installer!**
> If your motherboard battery is depleted and your clock reset to **year 2008**, Debian's `apt update` will fail with SSL certificate errors.
>
> If your clock is inaccurate, run the time synchronizer first:
> ```bash
> sudo ../Setup-Sync-Time/sync-time.sh
> ```

---

## Installation Guide (`--install`)

### 1. Run the Installer
In your terminal, navigate to the `Setup-Geany` folder and run:
```bash
cd Setup-Geany
chmod +x setup-geany.sh
./setup-geany.sh --install
```

### 2. What the Installer Configures
1. **Clock Verification:** Verifies system year `>= 2024` to ensure secure repository downloads.
2. **Dependency & Plugin Installation:** Checks which packages are missing and installs Geany and curated plugins via `apt`.
3. **Open-Source Themes:** Installs Dracula, Monokai, Solarized Dark, Gruvbox, and Nord into `~/.config/geany/colorschemes/`.
4. **Lightweight AI Copilot:** Installs `copilot.lua` and `copilot-explain.lua` into `~/.config/geany/plugins/geanylua/` and creates the configuration file `~/.config/geany/geany-copilot.conf`.
5. **Developer Preferences:** Sets 4-space indentation, auto-conversion of tabs to spaces, line numbering, auto-closing of tags, and strips trailing whitespace on save.

---

## Developer Workflow & Plugin Guide

After running `--install`, launch Geany:
```bash
geany &
```
Go to **Tools → Plugin Manager** to ensure the desired plugins are checked:
- `Markdown`
- `Project Organizer`
- `Tree Browser`
- `Autoclose`
- `Git ChangeBar`
- `GeanyLua` *(Required for AI Copilot)*

### 1. Markdown Document Viewer
- Open any `.md` file in Geany.
- A new **Markdown** tab will appear in the Message/Sidebar window.
- Click the preview icon or view live rendered HTML in the sidebar.

### 2. Project Management (Open Folder as Project)
- **Open Project Folder:** Go to **Project → New**.
- Under **Base Path**, choose your working directory (e.g., `~/projects/my-app`).
- Geany's sidebar switches to **Project Organizer**, showing your entire directory tree, files, and symbol breakdown.
- Double-click any file to open it instantly.

### 3. Coding in Python, C/C++, HTML, CSS, and JavaScript
- **Auto-Close:** Typing `(`, `{`, `[`, `"`, `'` automatically inserts the closing character and places your cursor inside.
- **Git Gutter Indicators:** As you edit code in a git repository, green markers show added lines, orange shows modified lines, and red arrows show deleted lines.
- **Whitespace Cleanup:** Whenever you save (`Ctrl+S`), trailing whitespace is automatically stripped.

### 4. Selecting Color Themes
1. Open Geany.
2. Go to **View → Change Color Scheme...**
3. Select any of the installed open-source schemes:
   - **Dracula** *(Modern high-contrast dark theme)*
   - **Monokai** *(Classic developer favorite)*
   - **Solarized Dark** *(Low-contrast eye-strain reduction)*
   - **Gruvbox Dark** *(Retro warm tones)*
   - **Nord** *(Arctic bluish clean palette)*

---

## AI Copilot Setup & Usage Guide

### How It Works (Ultra-Lightweight & Zero-Telemetry)
Unlike heavy AI extensions that consume 200 MB of RAM running node/python daemons, this Copilot is built using **GeanyLua** and standard **curl**:
- Runs only when triggered by you.
- Reads your selected code or the current line.
- Sends an OpenAI-compatible JSON payload directly to your configured backend.
- Inserts the generated code at your cursor or displays explanations in Geany's **Messages** tab.
- **Zero background memory consumption.**

### How to Enable GeanyLua
1. In Geany, click **Tools → Plugin Manager**.
2. Scroll down and check the box for **GeanyLua**.
3. Click **OK**.

### Using AI Copilot

#### Action A: Code Generation / Completion (`copilot.lua`)
1. Type a prompt or select existing code. Examples:
   ```python
   # Write a python function to parse a CSV file and return a dictionary
   ```
   Or select an existing function you want refactored.
2. Go to **Tools → Lua Scripts → copilot.lua**.
3. Geany's status bar will display `AI Copilot: Querying...`.
4. In seconds, the generated code will be inserted directly into your document!

#### Action B: Code Explanation / Review (`copilot-explain.lua`)
1. Highlight any complex code snippet or function.
2. Go to **Tools → Lua Scripts → copilot-explain.lua**.
3. Look at the bottom **Messages** tab in Geany to read a clear, concise breakdown of what the code does, including potential bugs or optimizations.

### Configuring the AI Backend (`geany-copilot.conf`)
The configuration file is located at:
```text
~/.config/geany/geany-copilot.conf
```

Default configuration contents:
```ini
# Geany Copilot Configuration
# Local-first, privacy-focused, zero telemetry

# AI Backend API URL (OpenAI-compatible)
API_URL=http://localhost:8080/v1/chat/completions

# Model name
MODEL=default

# API Key (leave empty for local models)
API_KEY=

# Request timeout in seconds
TIMEOUT=30

# Temperature (0.0 to 1.0; low value = more deterministic code)
TEMPERATURE=0.2
```

### Connecting to Local `llama.cpp` (This Repo's Server)
If you are running the `llama.cpp` server from this repository (`Setup-LLAMA-CPP/`):
1. Start the server (for example, on port 8080):
   ```bash
   ./llama-server -m models/your-model.gguf --port 8080
   ```
2. The default `API_URL=http://localhost:8080/v1/chat/completions` connects to it immediately with zero configuration changes needed!

### Connecting to Local Ollama
If you use Ollama for local models:
1. Start Ollama (`ollama run qwen2.5-coder` or `ollama run deepseek-r1`).
2. Edit `~/.config/geany/geany-copilot.conf`:
   ```ini
   API_URL=http://localhost:11434/v1/chat/completions
   MODEL=qwen2.5-coder
   API_KEY=
   ```

### Connecting to Remote OpenAI-Compatible APIs
If you prefer using a cloud model (DeepSeek, Groq, OpenRouter, OpenAI):
1. Open `~/.config/geany/geany-copilot.conf`.
2. Update the URL, model, and API key:
   ```ini
   API_URL=https://api.deepseek.com/v1/chat/completions
   MODEL=deepseek-coder
   API_KEY=sk-your-actual-api-key-here
   ```

### Setting Up a Keyboard Shortcut
You can trigger Copilot instantly with a keypress (e.g. `Ctrl+Alt+C`):
1. In Geany, go to **Edit → Preferences**.
2. Click the **Keybindings** tab.
3. Scroll down to the **GeanyLua** section.
4. Locate `copilot.lua` and double-click to assign a shortcut (e.g. `Ctrl+Alt+C`).
5. Click **Apply** and **OK**.

---

## Managing Your Setup

### Checking Status (`--status`)
To inspect your Geany installation, active plugins, installed themes, and test connectivity to your AI backend:
```bash
./setup-geany.sh --status
```

### Updating Packages & Scripts (`--update`)
To upgrade Geany and all plugins via APT and refresh color schemes and Copilot scripts:
```bash
./setup-geany.sh --update
```

### Uninstallation (`--uninstall`)
To cleanly remove the setup:
```bash
./setup-geany.sh --uninstall
```
The uninstaller will:
1. Clean up custom Copilot scripts and configs.
2. Ask if you wish to remove custom color schemes.
3. Ask if you wish to delete personal configuration (`~/.config/geany`).
4. **Interactive Dependency Prompt:**
   ```text
   Do you want to uninstall system packages (geany, geany-plugins)? [y/N]:
   ```
   - If **`y`**: Purges `geany` and plugin packages via `apt`.
   - If **`N`**: Keeps Geany installed for other uses.

---

## Troubleshooting & FAQs

### 1. "AI Copilot: No response received"
- **Cause:** The AI backend is not running or the URL is incorrect.
- **Solution:** 
  - If using local `llama.cpp`, verify that `llama-server` is running on port 8080.
  - Test connectivity with `./setup-geany.sh --status`.
  - Check `~/.config/geany/geany-copilot.conf` to verify `API_URL`.

### 2. "Tools → Lua Scripts is missing in Geany"
- **Cause:** The `GeanyLua` plugin is installed but not enabled.
- **Solution:** Go to **Tools → Plugin Manager**, find **GeanyLua**, check its checkbox, and click **OK**.

### 3. Markdown preview is blank or shows raw text
- **Cause:** The Markdown plugin needs to be enabled in Plugin Manager.
- **Solution:** Check **Markdown** in **Tools → Plugin Manager**. Ensure your file is saved with a `.md` extension.

### 4. How do I change indentation from 4 spaces to 2 spaces for Web development?
- Go to **Document → Indentation → Width → 2**.
- You can also set filetype-specific indentation by editing `~/.config/geany/filedefs/filetypes.html`.
