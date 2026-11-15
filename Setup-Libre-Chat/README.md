# Setup-Libre-Chat: 100% Localhost Isolated, Privacy-Focused AI Web Interface

A turnkey, self-hosted, and zero-telemetry deployment of [LibreChat](https://github.com/LibreChat-AI/LibreChat) for Debian, MX Linux, antiX, and Ubuntu. Pre-configured to connect directly to the local `llama.cpp` inference server ([Setup-LLAMA-CPP](../Setup-LLAMA-CPP/README.md)) running on your own machine.

---

## Why LibreChat on Localhost?

Modern cloud AI web interfaces (ChatGPT, Claude, Gemini Web) transmit all prompts, conversation history, and code snippets to remote corporate servers, logging metadata and utilizing data for model training.

**Setup-Libre-Chat provides the exact same modern, rich web interface entirely offline:**
- **Zero Cloud Transmission:** All conversations, message histories, and user credentials stay strictly inside your physical machine.
- **Absolute 0 Telemetry:** All analytics, balance checks, and phone-home telemetry are disabled at the environment and configuration levels.
- **Strict Localhost Isolation:** Binds strictly to `127.0.0.1:3080`. No ports are exposed to your local network (LAN) or public internet (WAN).
- **Turnkey Local LLM Integration:** Comes pre-configured via `librechat.yaml` to stream responses directly from your local `llama-server` (`http://127.0.0.1:8080/v1`).
- **Cryptographically Hardened:** Auto-generates 256-bit AES credential encryption keys (`CREDS_KEY`, `CREDS_IV`) and JWT secrets, securing `.env` with `0600` permissions.

---

## Architectural Deployment Options

| Feature | Docker Compose Mode (Recommended) | Native Node.js + Local MongoDB |
|---|---|---|
| **Prerequisites** | Docker & Docker Compose (from `Setup-Dev-Tools`) | Node.js v20+ & MongoDB |
| **Database Setup** | **100% Automatic** (Isolated internal container network `librechat_net`) | Manual or system service (`mongod`) |
| **System Overhead** | Minimal container overhead (~150MB RAM) | Zero container overhead (~80MB RAM) |
| **Upgrade Mechanism** | `docker compose pull` | `git pull && npm run reinstall` |
| **Target Machines** | Modern workstations & laptops | Lightweight systems (antiX / MX Linux) |

---

## Pre-Configured Endpoints (`librechat.yaml`)

LibreChat dynamically fetches available models from the local servers configured in `librechat.yaml`:

### 1. Local `llama.cpp` Server (Debian Dev Suite Module #1)
- **Base URL:** `http://127.0.0.1:8080/v1`
- **Authentication:** `not-needed-offline`
- **Supported Models:** Any model actively loaded by `run-llama-server` (e.g., Llama 3.2 3B, NVIDIA Nemotron-3 4B, Qwen 2.5 7B, Mistral 7B).
- **Features:** Full conversation history, system prompt customization, streaming tokens, temperature and parameter control.

### 2. Local Ollama Server (Optional)
- **Base URL:** `http://127.0.0.1:11434/v1`
- **Models:** Automatically queries all models pulled via `ollama list`.

### 3. Multiple Accounts / Work & Personal Profiles (Optional)
You can configure multiple separate accounts (e.g. personal vs. work API keys) in `librechat.yaml` without needing to log out. Simply define separate custom endpoints with distinct names:
```yaml
endpoints:
  custom:
    - name: "ChatGPT (Personal)"
      apiKey: "sk-proj-PERSONAL_KEY"
      baseURL: "https://api.openai.com/v1"
      models:
        default: ["gpt-4o", "gpt-4o-mini"]
    - name: "ChatGPT (Work)"
      apiKey: "sk-proj-WORK_KEY"
      baseURL: "https://api.openai.com/v1"
      models:
        default: ["gpt-4o", "gpt-4o-mini"]
```
In the web interface, switch profiles instantly using the model dropdown menu or assign them to custom **Agents** / **Presets**.

---

## Security & Privacy Audit

| Security Domain | Configuration | Guarantee |
|---|---|---|
| **Network Exposure** | `HOST=127.0.0.1`, `PORT=3080` | Zero exposure outside `127.0.0.1`. Inaccessible to Wi-Fi/LAN peers. |
| **Telemetry & Tracking** | `TELEMETRY=false`, `DISABLE_TELEMETRY=true` | Zero analytics pings sent to third parties or LibreChat servers. |
| **Balance Phone-Home** | `CHECK_BALANCE=false` | Prevents outbound pinging of cloud billing APIs. |
| **Data Encryption** | `CREDS_KEY` (64 hex) & `CREDS_IV` (32 hex) | AES-256-CBC encryption for local database credential storage. |
| **Access Control** | `ALLOW_SOCIAL_LOGIN=false`, `ALLOW_REGISTRATION=true` | Local email/password authentication only. No OAuth tracking. |
| **File Permissions** | `chmod 600 .env` | Only the running user can view configuration tokens. |

> [!TIP]
> **Single-User Lock:** After you create your first admin account in the web interface, set `ALLOW_REGISTRATION=false` in `.env` to prevent any other local user on your machine from registering new accounts.

---

## Quick Start Commands

### 1. Diagnostic Check
Check if LibreChat, MongoDB, and local `llama.cpp` are currently running:

```bash
cd Setup-Libre-Chat
./setup-librechat.sh --status
```

### 2. Turnkey Setup
Automatically detects Docker or Node.js, generates keys, and boots services:

```bash
./setup-librechat.sh --install
```

### 3. Dedicated Docker Mode (Turnkey & Isolated)
Spins up LibreChat and MongoDB containers together:

```bash
./setup-librechat.sh --docker
```

### 4. Background Server Management
```bash
# Start LibreChat
./setup-librechat.sh --start

# Stop LibreChat
./setup-librechat.sh --stop

# Tail live server logs
./setup-librechat.sh --logs

# Install desktop application launcher and CLI symlink (~/.local/bin/librechat-localhost)
./setup-librechat.sh --install-desktop
```

### 5. Clean Uninstallation
To cleanly stop running services and remove desktop shortcuts:

```bash
cd Setup-Libre-Chat
./setup-librechat.sh --uninstall
```

The uninstaller:
1. Gracefully stops running Docker containers (`librechat_app`, `librechat_mongodb`) or any background Node.js server processes.
2. Removes the desktop application launcher (`~/.local/share/applications/librechat.desktop`) and CLI symlink (`~/.local/bin/librechat-localhost`).
3. Preserves your local conversation database and uploaded files by default.

**To completely purge all data and configuration files:**
```bash
rm -rf librechat-data mongo_data LibreChat .env
```

---

## CLI Parameter Reference

| Parameter | Short Flag | Description |
|---|---|---|
| `--install` | `-i` | Turnkey installation: auto-detects Docker/Node.js, generates keys, and launches LibreChat |
| `--docker` | | Dedicated Docker Compose deployment (runs LibreChat + isolated MongoDB container) |
| `--native` | `--local` | Native deployment using host Node.js runtime and host MongoDB instance |
| `--start` | | Starts LibreChat and MongoDB services in the background and opens browser |
| `--stop` | | Gracefully stops running background containers or native server processes |
| `--status` | `-s` | Displays real-time operational dashboard for LibreChat, MongoDB, and local LLM |
| `--autostart [on\|off]` | | Toggles between Auto-Start on boot and On-Demand mode (`--autostart off` or `--autostart on`) |
| `--logs` | | Streams live logs from Docker Compose or the native background process |
| `--install-desktop` | | Installs desktop application menu launcher and CLI symlink (`librechat-localhost`) |
| `--uninstall` | | Cleanly terminates background services and removes desktop shortcuts |
| `--help` | `-h` | Displays usage manual and parameter reference |

---

## End-to-End Workflow: Chatting with Local AI

1. **Start the local `llama.cpp` inference server:**
   ```bash
   run-llama-server
   ```
   *(Running in terminal or systemd service on `http://127.0.0.1:8080`)*

2. **Start LibreChat:**
   ```bash
   librechat-localhost --start
   ```

3. **Open Browser:**
   Navigate to `http://127.0.0.1:3080`
   - Create your local admin user account on the first screen.
   - Select **"Local llama.cpp (100% Offline)"** from the top model dropdown.
   - Chat privately with full markdown formatting, LaTeX formulas, code syntax highlighting, and branching conversations!

---

## Importing Conversations (ChatGPT, Gemini, Claude)

LibreChat allows migrating your complete chat history from third-party services:

### 1. From ChatGPT
1. In ChatGPT, navigate to **Settings** $\rightarrow$ **Data Controls** $\rightarrow$ **Export Data**.
2. Download and unzip the archive to obtain `conversations.json`.
3. In LibreChat ([http://127.0.0.1:3080](http://127.0.0.1:3080)), click your profile icon (bottom-left) $\rightarrow$ **Settings** $\rightarrow$ **General** (or Data & Privacy) $\rightarrow$ **Import Conversations**.
4. Upload `conversations.json`. LibreChat parses and displays your full conversation archive instantly.

### 2. From Google Gemini (`tools/gemini-to-librechat.py`)
Google exports Gemini chats via **Google Takeout** (`My Activity` $\rightarrow$ `Gemini Apps`) as either `MyActivity.json` or `MyActivity.html`. LibreChat does not read raw Takeout activity streams out-of-the-box, but our converter maps them directly into LibreChat's native format:

```bash
cd Setup-Libre-Chat

# Convert Google Takeout JSON or HTML to LibreChat format
python3 tools/gemini-to-librechat.py -i ~/Downloads/Takeout/ -o conversations_gemini.json -f "Gemini"

# Or convert a specific file
python3 tools/gemini-to-librechat.py -i MyActivity.json -o conversations_gemini.json
```

**How to Import:**
1. Open LibreChat ([http://127.0.0.1:3080](http://127.0.0.1:3080)).
2. Go to **Settings** $\rightarrow$ **Data & Privacy** (or General) $\rightarrow$ click **Import**.
3. Select `conversations_gemini.json`. All your Gemini chats will appear in your sidebar!
4. *(Optional)* Organize them into a sidebar folder:
   ```bash
   python3 tools/batch-folder-organizer.py --folder "Gemini" --match "\[Gemini\]"
   ```

### 3. Auto-Folder, Search & Batch Tagging (`tools/batch-folder-organizer.py`)
To organize and search across thousands of imported chats without extra search engines or RAM overhead:

* **Global Search Across Messages (Instant Bookmark Filter):**
  Searches all conversation titles and message texts across your entire archive, tagging matches so you can filter them in LibreChat:
  ```bash
  # Search globally across all chats and messages
  python3 tools/batch-folder-organizer.py --search "quantum"

  # Search only within a specific project folder
  python3 tools/batch-folder-organizer.py --search "python" --in-folder "Work"

  # Clear all temporary search bookmarks when finished
  python3 tools/batch-folder-organizer.py --clear-search
  ```

* **Before Importing:** Add a folder label to `conversations.json`:
  ```bash
  python3 tools/batch-folder-organizer.py --file ~/Downloads/conversations.json --folder "Work"
  ```
  Upload the generated `conversations_Work.json` in LibreChat. All chats will appear neatly prefixed with `[Work] Title`!

* **After Importing (Direct MongoDB):** Organize chats into sidebar folders:
  ```bash
  # Check status (conversations, folders, tags)
  python3 tools/batch-folder-organizer.py --list

  # Put all untagged chats into a sidebar folder
  python3 tools/batch-folder-organizer.py --folder "Personal" --all-untagged

  # Put chats matching keywords into a folder
  python3 tools/batch-folder-organizer.py --folder "Work" --match "python|project|docker" --prefix-title

  # Permanently delete all chats in a folder (and remove folder from sidebar):
  python3 tools/batch-folder-organizer.py --delete-folder "TempFolder"

  # Permanently delete all chats in a folder but keep the empty folder shell:
  python3 tools/batch-folder-organizer.py --delete-chats "TempFolder" --keep-folder
  ```

### 4. Restore ChatGPT Attached Images (`tools/fix-chatgpt-images.py`)
ChatGPT data exports store image attachments as separate files (`file-*` or `file_*`) and reference them in `conversations.json` as `image_asset_pointer` objects. LibreChat's native importer renders these as raw JSON code blocks. This utility extracts the images and converts them into clickable 88px icon thumbnails:
```bash
cd Setup-Libre-Chat

# Check image status & missing assets:
python3 tools/fix-chatgpt-images.py --status

# Extract images from ChatGPT export .zip and auto-link:
python3 tools/fix-chatgpt-images.py --from-zip ~/Downloads/chatgpt_export.zip

# Or copy from an extracted folder and auto-link:
python3 tools/fix-chatgpt-images.py --from-dir ~/Downloads/chatgpt_extracted/

# Scan MongoDB and link images already present in images folder:
python3 tools/fix-chatgpt-images.py --link-db

# Clean up raw JSON blocks to neat Markdown placeholders:
python3 tools/fix-chatgpt-images.py --clean-placeholders
```

### 5. Native Full-Text In-App Search (`tools/toggle-meilisearch.sh`)
If you want LibreChat's native search bar (top of sidebar, `Ctrl+K`) with live fuzzy full-text indexing:
```bash
cd Setup-Libre-Chat

# Enable MeiliSearch & native search bar
./tools/toggle-meilisearch.sh --enable

# Check running status & RAM consumption
./tools/toggle-meilisearch.sh --status

# Disable MeiliSearch anytime to free RAM (~200MB)
./tools/toggle-meilisearch.sh --disable
```
- Strictly binds to `127.0.0.1:7700`.
- Zero telemetry (`MEILI_NO_ANALYTICS=true`).
- Auto-generates cryptographically secure master key.

### 5. Backups & Full Database Portability
All local user data, settings, and chat logs are stored inside your canonical data directory:
```bash
~/.local/share/dev-setups/librechat/mongo_data/
```
Backing up this directory secures your complete offline conversational history.

---

## Troubleshooting

### `MongoDB is NOT responding or running`
- **If using Docker Compose:** Run `./setup-librechat.sh --docker` which spins up the official MongoDB container bound strictly to `127.0.0.1:27017` with zero external network exposure.
- **If using Native Node.js:** Start the local MongoDB service on your host:
  ```bash
  sudo systemctl start mongod || sudo service mongodb start
  ```

### Local llama.cpp model not showing in dropdown
- Verify `llama-server` is actively running: `curl http://127.0.0.1:8080/v1/models`
- In LibreChat, click the model dropdown and select **"Fetch Models"** or refresh the browser page.
