# Universal Markdown Viewer for Debian & antiX Linux

An ultra-lightweight, local-first, distraction-free Markdown viewer powered by **Pandoc** and the **Surf (WebKitGTK)** browser engine.

Designed specifically for Debian, antiX, MX Linux, Ubuntu, and lightweight Linux setups, this viewer delivers crisp full-window GitHub-style Markdown rendering, syntax-highlighted code blocks, high-contrast pinned copy buttons, persistent Dark/Light modes, hardware crash immunity, and seamless desktop integration under the name **MD-Viewer (Surf)**—without the heavy 800MB RAM overhead of Electron-based viewers.

---

## Table of Contents

- [Highlights & Features](#highlights--features)
- [Why Surf + Pandoc?](#why-surf--pandoc)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage Guide](#usage-guide)
  - [Terminal Usage](#terminal-usage)
  - [File Manager Integration (SpaceFM, zzzFM, PCManFM)](#file-manager-integration-spacefm-zzzfm-pcmanfm)
  - [Using an Alternative Browser](#using-an-alternative-browser)
  - [CLI Management Options](#cli-management-options)
- [Interactive Features & Controls](#interactive-features--controls)
  - [Guaranteed Full Window Width](#guaranteed-full-window-width)
  - [Dual-Mode Clipboard Engine](#dual-mode-clipboard-engine)
  - [Dark / Light Theme Toggle](#dark--light-theme-toggle)
  - [Keyboard Shortcuts](#keyboard-shortcuts)
- [Hardware & Sandbox Crash Immunity](#hardware--sandbox-crash-immunity)
- [Technical Architecture](#technical-architecture)
- [Uninstallation with Dependency Removal](#uninstallation-with-dependency-removal)
- [Troubleshooting](#troubleshooting)

---

## Highlights & Features

| Feature | Description |
|---|---|
| **Guaranteed Full Window Viewing** | Content expands across 100% of the window with Pandoc's default 36em constraint eliminated, plus a readable-width toggle (<kbd>W</kbd>). |
| **Crash Immunity** | Bypasses WebKitGTK bubblewrap sandboxing and GPU compositing issues to prevent `g_spawn_sync() / waitpid() ECHILD` crashes and segmentation faults on older GPUs. |
| **Automatic Browser Fallback** | If Surf encounters an unrecoverable engine crash, it gracefully falls back to your system browser (`xdg-open`, Firefox, Chromium, Dillo). |
| **True GitHub Styling** | Clean, readable 16px base font with GitHub Dark and Clean Light themes. |
| **Pinned High-Contrast Copy** | Dedicated copy button pinned to each code block header with SVG icons and instant visual feedback. |
| **Dual-Mode Clipboard** | Works asynchronously via `navigator.clipboard` with an automatic fallback to `execCommand` for local `file://` WebKitGTK sandboxes. |
| **Offline-Ready** | Embedded, self-contained CSS styles that render completely without an internet connection. |
| **Mermaid Diagram Support** | Automatically renders Mermaid flowcharts, sequence diagrams, and architecture maps. |
| **Relative Asset Resolution** | Auto-resolves relative image paths (`./images/diagram.png`) regardless of where the command was invoked. |
| **Ultra-Low Memory Footprint** | Consumes ~30–50MB RAM during preview (vs ~800MB+ for VSCode/Electron). |
| **antiX / Debian Integration** | "Open with MD-Viewer (Surf)" context menu action for SpaceFM, zzzFM, and PCManFM file managers. |
| **Smart Uninstaller** | Clean removal with an interactive prompt to uninstall system packages (`pandoc`, `surf`). |
| **Zero Telemetry** | 100% Free & Open-Source (FOSS), privacy-first, local-first execution. |

---

## Why Surf + Pandoc?

Many modern Markdown previewers (like Obsidian, VSCode, or Electron-based tools) consume 500MB to 1GB of RAM and depend on continuous background processes. 

On resource-constrained hardware (e.g., dual-core laptops with 2GB–4GB RAM running antiX or Debian):
1. **Pandoc** converts GitHub Flavored Markdown (`gfm`) directly into clean, semantically correct HTML with syntax highlighting in milliseconds.
2. **Surf** utilizes the system's native WebKitGTK engine to render the preview instantly with virtually zero idle overhead.
3. Once you close the viewer window, the temporary preview files in `/tmp` are immediately and completely purged from memory and disk.

---

## Prerequisites

The viewer requires only standard Debian packages:
- `pandoc` (Markdown parsing engine)
- `surf` (WebKitGTK minimalist web browser)
- `python3` (for HTML injection)

The installer (`./setup-md-viewer.sh --install`) automatically checks and installs any missing packages via `apt`.

---

## Installation

Run the setup script from within the repository:

```bash
cd Setup-MD-Viewer
chmod +x setup-md-viewer.sh
./setup-md-viewer.sh --install
```

### What this sets up:
1. Installs `pandoc` and `surf` if not already installed.
2. Creates the launcher at `/usr/local/bin/pandoc-md-viewer`.
3. Creates the convenient alias `/usr/local/bin/md-viewer`.
4. Registers `MD-Viewer (Surf)` in `/usr/local/share/applications/pandoc-md-viewer.desktop` and `~/.local/share/applications/` with system MIME types (`text/markdown`, `text/x-markdown`).
5. Adds right-click **"Open with MD-Viewer (Surf)"** actions to antiX file managers (**SpaceFM**, **zzzFM**, and **PCManFM**).

---

## Usage Guide

### Terminal Usage

Once installed, you can view any Markdown file from any directory:

```bash
# Using the short alias:
md-viewer README.md

# Or using the full binary name:
pandoc-md-viewer /path/to/notes.md
```

You can also pass a Markdown file directly to the setup script:
```bash
./setup-md-viewer.sh README.md
```

### File Manager Integration (SpaceFM, zzzFM, PCManFM)

1. Open **SpaceFM**, **zzzFM**, or **PCManFM**.
2. Right-click any `.md` or `.markdown` file.
3. Select **Open with MD-Viewer (Surf)** (or find `MD-Viewer (Surf)` in the *Open With...* list).

### Using an Alternative Browser

If you want to view a document in another browser (e.g. Firefox or Dillo) instead of Surf:
```bash
MD_VIEWER_BROWSER=firefox-esr md-viewer README.md
```

### CLI Management Options

The management script supports standard flags:

```bash
./setup-md-viewer.sh --help          # Show options and quick reference
./setup-md-viewer.sh --status        # Check dependencies, binaries, and associations
./setup-md-viewer.sh --install       # Install or refresh viewer components
./setup-md-viewer.sh --uninstall     # Cleanly remove launcher binaries and shortcuts
```

---

## Interactive Features & Controls

### Guaranteed Full Window Width

By default, Pandoc generates standalone documents with an artificial `max-width: 36em` (~576px) constraint, which causes markdown files to render in only half of your screen. 

This viewer completely strips the 36em constraint and configures HTML, body, and container styles to use **100% of your window width**.

If you ever want a narrow centered column, click the **↔ Width** button on the top navigation bar or press <kbd>W</kbd>. Your choice is saved in local storage.

### Dual-Mode Clipboard Engine

Copying code from local HTML files (`file:///tmp/...`) in WebKitGTK browsers frequently fails because modern browsers restrict `navigator.clipboard` to secure contexts (`https://` or `localhost`).

This viewer implements an automatic **dual-mode clipboard engine**:
1. It attempts `navigator.clipboard.writeText()` first.
2. If blocked or running in an unprivileged `file://` context, it silently falls back to an off-screen `document.execCommand('copy')` routine.
3. The button transitions to green with a checkmark and **"Copied!"** label for 2 seconds.
4. The button is pinned to the top-right header of the code container, ensuring it **never overlaps the code** and **never scrolls away** when code scrolls horizontally.

### Dark / Light Theme Toggle

- Click the **🌓 Theme** button in the top navigation bar, or press <kbd>T</kbd> on your keyboard.
- Switches between **GitHub Dark** (`#0d1117`) and **Clean Light** (`#ffffff`).
- Your preference is saved in local storage and persists across previews.

### Keyboard Shortcuts

Click the <kbd>?</kbd> button in the top right to view the shortcut cheat sheet:

| Shortcut | Action |
|---|---|
| <kbd>Ctrl</kbd> + <kbd>G</kbd> or <kbd>Ctrl</kbd> + <kbd>/</kbd> | Find / Search text in document |
| <kbd>W</kbd> | Toggle Full Width / Readable Boxed Width |
| <kbd>T</kbd> | Toggle Dark / Light theme |
| <kbd>Ctrl</kbd> + <kbd>+</kbd> | Zoom in (increase font size) |
| <kbd>Ctrl</kbd> + <kbd>-</kbd> | Zoom out (decrease font size) |
| <kbd>Ctrl</kbd> + <kbd>0</kbd> | Reset zoom to default |
| <kbd>Ctrl</kbd> + <kbd>R</kbd> | Reload Markdown document |
| <kbd>Ctrl</kbd> + <kbd>Q</kbd> | Close viewer |
| <kbd>?</kbd> | Open / Close shortcut help modal |

---

## Hardware & Sandbox Crash Immunity

On Debian/antiX systems—especially machines with older Intel GPUs (GMA 4500, GL40, Ironlake) or non-systemd kernels—WebKitGTK can crash with:
```text
In call to g_spawn_sync(), wait status of a child process was requested but ECHILD was received by waitpid().
web process terminated, crashed. Segmentation fault.
```

The launcher script applies automatic environment workarounds before starting WebKitGTK:
1. `WEBKIT_FORCE_SANDBOX=0` & `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`: Disables the bubblewrap sandbox that fails with `g_spawn_sync / ECHILD` when unprivileged user namespaces are disabled in the kernel.
2. `WEBKIT_DISABLE_COMPOSITING_MODE=1` & `WEBKIT_DISABLE_DMABUF_RENDERER=1`: Disables hardware-accelerated OpenGL compositing, avoiding GPU crashes on older Mesa/Intel drivers.
3. **Automatic Fallback**: If Surf still exits abnormally, the launcher automatically re-opens the document in your system browser (`xdg-open` or Firefox).

---

## Technical Architecture

```
[User opens Markdown file (terminal or right-click 'MD-Viewer (Surf)')]
                                  │
                                  ▼
                [Resolve Real Path & Working Directory]
                                  │
                                  ▼
                [Create Secure Temp Folder in /tmp]
                (Registered with EXIT, INT, TERM, HUP trap)
                                  │
                                  ▼
      [Pandoc Engine (GFM + Smart + BreezeDark + -V maxwidth=100%)]
            (Embeds CSS styles, resolves relative images via --resource-path)
                                  │
                                  ▼
                [Python Post-Processor Injection]
        (Removes 36em constraint, injects full-width navbar, clipboard, zoom & theme)
                                  │
                                  ▼
        [Apply WebKitGTK Sandbox & Compositing Workarounds]
                                  │
                                  ▼
            [Surf WebKit Launch (with fallback to xdg-open)]
                                  │
                                  ▼
                [Window Closed / Process Exit]
                (Trap triggers: /tmp directory cleanly deleted)
```

---

## Uninstallation with Dependency Removal

To remove the viewer and all registered shortcuts:

```bash
cd Setup-MD-Viewer
sudo ./setup-md-viewer.sh --uninstall
```

During uninstallation, the script will interactively ask:
```text
Do you want to uninstall system packages (pandoc, surf)? [y/N]:
```
* If you enter **`y`** or **`yes`**, it will purge `pandoc` and `surf` via `apt` and run `autoremove`.
* If you enter **`n`** or press **ENTER**, it will keep `pandoc` and `surf` installed so other tools on your system can still use them.

---

## Troubleshooting

### Text appears too small or too large
- Use the **A+** and **A-** buttons on the top navigation bar.
- Or use the native Surf zoom shortcuts: <kbd>Ctrl</kbd> + <kbd>+</kbd> and <kbd>Ctrl</kbd> + <kbd>-</kbd>.

### Want narrow / centered column instead of full width
- Click the **↔ Width** button on the navbar or press <kbd>W</kbd>.

### Local images are missing or broken
- Ensure your markdown links use relative paths relative to the document location (e.g. `![diagram](./images/flow.png)`).
- The viewer automatically passes `--resource-path` set to the directory containing the markdown file.
