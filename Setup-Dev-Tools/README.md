# Developer Tools Suite for Debian & MX Linux

An **ultra-lightweight, 100% open-source, secure**, and **privacy-focused (0 telemetry)** developer productivity toolkit for **Debian, MX Linux, antiX, Ubuntu, Linux Mint, and Devuan**.

Provides a complete, modern terminal development environment—replacing sluggish GNU utilities, bloated desktop apps (Electron, Docker Desktop, VSCode Git extensions), and cloud-dependent assistants with blazing-fast native binaries and local tools.

```text
  🪶 Ultra-Lightweight (0–50MB RAM)  •  🔓 100% Open-Source (FOSS)  •  🛡️ Secure by Design  •  🔒 Privacy-Focused (0 Telemetry)
```

---

## Table of Contents

- [Core Pillars & Tool Audit Table](#core-pillars--tool-audit-table)
  - [Why These Tools Were Chosen](#why-these-tools-were-chosen)
- [Suite Components](#suite-components)
  - [1. Modern CLI PowerTools](#1-modern-cli-powertools)
  - [2. Git Workflow & LazyGit TUI](#2-git-workflow--lazygit-tui)
  - [3. Developer Runtimes](#3-developer-runtimes)
  - [4. Lightweight Containers](#4-lightweight-containers)
  - [5. Local AI Developer Copilot](#5-local-ai-developer-copilot)
- [Dedicated "How to Use" Guides](#dedicated-how-to-use-guides)
- [Quick Start: Installation](#quick-start-installation)
  - [Interactive Menu Installation](#interactive-menu-installation)
  - [Automated / Non-Interactive Flags](#automated--non-interactive-flags)
- [Status Inspection](#status-inspection)
- [MX Linux & antiX Service Handling](#mx-linux--antix-service-handling)
- [Uninstallation](#uninstallation)

---

## 🔒 Security Architecture: Principle of Least Privilege

- **Strictly User-Space Execution**: Developer runtimes (`uv`, `fnm`), Git tools (`lazygit`), and modern CLI binaries (`eza`, `zoxide`, `bat`, `ai`) are installed strictly in `$HOME/.local/bin/` with standard user ownership. They **never** touch `/usr/local/bin` and **never** execute with root privileges.
- **Minimized Root Activity**: `sudo` is requested **only** when system-level OS packages are strictly required (`apt install build-essential`, `docker.io`, `docker-cli`).
- **Explicit Permission**: The script notifies the user before requesting `sudo` authorization for APT packages.
- **Root Guard**: Running the installer directly as `root` is blocked to prevent polluting `/root` with developer tooling and dotfiles.

---

## Core Pillars & Tool Audit Table

Every tool in this suite is audited against our strict four non-negotiable principles:

| Component | Selected Tools | License & FOSS Status | RAM / Resource Footprint | Security & Privacy (0 Telemetry) | Why It Is Useful (Advantage over Bloatware) |
|---|---|---|---|---|---|
| **CLI PowerTools** | `ripgrep` (`rg`), `fzf`, `bat`, `eza`, `zoxide` | **100% Open Source**<br>(MIT / Apache 2.0 / EUPL) | **0 MB idle RAM.** Compiled native Rust & Go static binaries. | **Zero Telemetry.** Pure offline file search & navigation; zero network communication during usage. | **10x faster than traditional grep/find/cat.** Provides instant fuzzy finding, colorized file listings with Git statuses, and smart folder jumping (`z`). |
| **Git & LazyGit** | `lazygit`, clean diffs, sensible git config | **100% Open Source**<br>(MIT) | **~15 MB RAM** only while active. Instant startup. | **Zero Telemetry.** Reads local git repository status; no telemetry, tracking, or cloud account required. | **Replaces 600MB+ Electron Git GUIs** (GitKraken, VSCode Git). Stage hunks, resolve merge conflicts, and rebase interactively via fast keyboard shortcuts. |
| **Dev Runtimes** | **Python:** `uv`<br>**Node.js:** `fnm`<br>**C/C++:** `build-essential` | **100% Open Source**<br>(Apache 2.0 / GPLv3 / MIT) | Native Rust binaries. Replaces slow Python `pip`/`venv` and sluggish `nvm`. | **Zero Telemetry.** `uv` has explicit offline caching. `fnm` contains no telemetry or phone-home pings. | **`uv` is 10–100x faster than pip/virtualenv.** `fnm` starts 40x faster than `nvm` without adding lag to terminal startups. |
| **Containers** | Docker Engine (CE) / Rootless Podman + `lazydocker` | **100% Open Source**<br>(Apache 2.0 / MIT) | Native Linux daemon (~30-50MB RAM). **No 2GB Electron Docker Desktop.** | Isolated Linux cgroups & namespaces. Optional rootless daemon execution. | **Runs container workloads without freezing your system.** `lazydocker` provides a visual container/volume manager right in the terminal. |
| **Local AI Copilot** | Standalone `ai` terminal tool wired to `llama.cpp` | **100% Open Source**<br>(MIT / Local Bash) | **0 MB extra RAM.** Communicates with existing local `llama-server` on `127.0.0.1:8080`. | **Absolute 0 Telemetry.** 100% offline localhost execution. No code or prompts leave your machine; zero cloud API keys needed. | **Replaces proprietary AI subscriptions** (GitHub Copilot). Ask terminal questions, explain error logs, and generate shell commands using your local LLM. |

---

### Why These Tools Were Chosen

1. **Native Performance (Rust & Go):** Standard tools like `nvm` (Node Version Manager) are large shell scripts that slow down every single new terminal tab by 200–500ms. `fnm` and `uv` execute in under 10ms.
2. **Zero Electron Bloat:** Docker Desktop and graphical Git clients consume over 2 GB of RAM before opening a project. `lazygit` and `lazydocker` deliver equal or superior functionality in under 20 MB of RAM.
3. **Completely Local & Offline-First:** Many modern developer assistants require paid subscriptions and beam your code to external cloud providers. Our `ai` CLI tool queries your local `llama.cpp` instance running right on your CPU/GPU.

---

## Suite Components

### 1. Modern CLI PowerTools
- **`ripgrep` (`rg`):** Blazing-fast recursive regex search that respects `.gitignore` rules automatically.
- **`fzf`:** General-purpose fuzzy finder for files, processes, Git branches, and command history.
- **`bat`:** Syntax-highlighted file viewer with Git modification markers and line numbering.
- **`eza`:** Modern replacement for `ls` featuring file-type icons, Git status indicators, and tree viewing.
- **`zoxide`:** Smart directory jumper that learns your habits (`z project` immediately jumps to `~/deep/path/project`).

### 2. Git Workflow & LazyGit TUI
- **`lazygit`:** A lightning-fast, keyboard-driven terminal UI for Git. View branches, inspect diffs, stage individual lines/hunks, resolve conflicts, and stash with single keystrokes.
- **Safe Global Configurations:** Initializes default branch as `main`, sets sensible whitespace and color policies, and registers handy aliases (`git st`, `git lg`).

### 3. Developer Runtimes
- **`uv` (Python):** An extremely fast Python package and environment manager written in Rust. Installs packages and resolves dependencies up to 100x faster than standard `pip`.
- **`fnm` (Node.js):** Fast Node Manager built in Rust. Seamlessly install and switch between Node versions (`fnm use 20`) with instant shell startup.
- **C/C++ Build Essentials:** Installs GCC, G++, Make, GDB, Valgrind, and CMake for native systems development.

> [!TIP]
> **Environment Activation:**
> Binaries like `uv` and `fnm` reside in `~/.local/bin/`. On first installation, simply run `source ~/.bashrc` or open a new terminal window to activate the path in your current shell session.

### 4. Lightweight Containers
- **Docker Engine (CE) or Rootless Podman:** Clean Linux container runtimes without the proprietary bloat or RAM consumption of Docker Desktop.
- **`lazydocker`:** Complete terminal UI to inspect running containers, view real-time CPU/RAM stats, tail logs, prune images, and manage volumes.

### 5. Local AI Developer Copilot
- **`ai` CLI:** A custom, zero-telemetry command-line helper wired directly to your local `llama-server` (`http://127.0.0.1:8080`).
- Generates precise bash commands (`ai -c "extract audio from video"`), explains error logs via standard input piping (`cat build.log | ai "what broke?"`), and refactors code locally. Built with environment variable prompt isolation to eliminate code injection vulnerabilities when piping untrusted files or diffs.

---

## Dedicated "How to Use" Guides

For in-depth tutorials, practical keyboard shortcuts, and workflow examples, see the dedicated guides in the [`docs/`](docs/) directory:

- 📖 **[1. CLI PowerTools Guide](docs/1-CLI-POWERTOOLS.md)** — Searching, fuzzy finding, smart navigation, and aliases.
- 📖 **[2. Git & LazyGit Guide](docs/2-GIT-LAZYGIT.md)** — Interactive rebasing, staging hunks, conflict resolution, and keybindings.
- 📖 **[3. Developer Runtimes Guide](docs/3-DEV-RUNTIMES.md)** — Managing Python with `uv`, Node with `fnm`, and C/C++ compilation.
- 📖 **[4. Containers & LazyDocker Guide](docs/4-DOCKER-CONTAINERS.md)** — Docker without Desktop, non-root access, service management, and TUI shortcuts.
- 📖 **[5. Local AI Copilot Guide](docs/5-LOCAL-AI-COPILOT.md)** — Terminal queries, stdin log piping, shell command generation, and editor integration.

---

## Quick Start: Installation

### Interactive Menu Installation

Run the master setup script:

```bash
cd Setup-Dev-Tools
chmod +x setup-dev-tools.sh
./setup-dev-tools.sh --install
```

You will be presented with an interactive component selector:
```text
==================================================================
  Setup Developer Tools Suite (100% FOSS & 0 Telemetry)
==================================================================
Select which components to install:

  [1] Modern CLI PowerTools (ripgrep, fzf, bat, eza, zoxide)
  [2] Git Workflow & LazyGit TUI (lazygit, safe configs, aliases)
  [3] Dev Runtimes (uv Python, fnm Node.js, C/C++ toolchain)
  [4] Lightweight Containers (Docker Engine / Podman + lazydocker)
  [5] Local AI Copilot CLI ('ai' command wired to llama.cpp)
  [A] Install ALL 5 Components [RECOMMENDED]

Enter choice [e.g. 1,2,5 or A, Default: A]:
```

After installation completes, activate the new environment in your current terminal:
```bash
source ~/.bashrc
```

---

### Automated / Non-Interactive Flags

For scripted or headless installations:

```bash
# Install everything non-interactively
./setup-dev-tools.sh --all

# Install specific components only
./setup-dev-tools.sh --cli          # Only ripgrep, fzf, bat, eza, zoxide
./setup-dev-tools.sh --git          # Only Git & LazyGit
./setup-dev-tools.sh --runtimes     # Only uv, fnm, build-essential
./setup-dev-tools.sh --docker       # Only Docker/Podman & lazydocker
./setup-dev-tools.sh --ai           # Only Local AI Copilot 'ai' CLI
```

---

## Status Inspection

Check which components are installed on your system at any time:

```bash
./setup-dev-tools.sh --status
```

Example output:
```text
==================================================================
  Developer Tools Suite — Component Status
==================================================================
1. CLI PowerTools:
  - ripgrep (rg) : /usr/bin/rg
  - fzf          : /usr/bin/fzf
  - bat          : ~/.local/bin/bat
  - eza          : ~/.local/bin/eza
  - zoxide       : ~/.local/bin/zoxide

2. Git & LazyGit:
  - git          : /usr/bin/git
  - lazygit      : ~/.local/bin/lazygit

3. Developer Runtimes:
  - uv (Python)  : ~/.local/bin/uv
  - fnm (Node.js): ~/.local/bin/fnm
  - gcc / g++    : /usr/bin/gcc
  - cmake        : /usr/bin/cmake

4. Containers:
  - docker       : /usr/bin/docker
  - lazydocker   : ~/.local/bin/lazydocker

5. Local AI Copilot:
  - ai CLI       : ~/.local/bin/ai
```

---

## MX Linux & antiX Service Handling

- **SysVinit Systems (Default antiX / MX Linux SysVinit mode):**
  - Docker service can be started or checked with standard service commands:
    ```bash
    sudo service docker status
    sudo service docker start
    ```
- **Systemd Systems (Standard Debian / MX Linux systemd boot option):**
  - Docker service runs via `systemctl`:
    ```bash
    sudo systemctl status docker
    sudo systemctl start docker
    ```
- **Non-Root Docker Execution:**
  The installer automatically adds your user to the `docker` group, allowing you to run `docker ps` and `lazydocker` without typing `sudo`. If you just installed it, run `newgrp docker` or re-login.

---

## Uninstallation

To remove all or specific components cleanly:

```bash
./setup-dev-tools.sh --uninstall
```

The uninstaller prompts before each action:
1. Prompts whether to remove the shell environment block in `~/.bashrc`.
2. Prompts whether to remove custom binaries in `~/.local/bin`.
3. Prompts whether to remove APT packages.
