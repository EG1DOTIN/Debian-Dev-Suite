# Ergonomic Terminal Multiplexer (`Setup-Tmux`)

A production-grade, highly aesthetic **tmux** configuration designed for developers on **Debian, MX Linux, antiX, and Ubuntu**.

Provides persistent terminal sessions, mouse-controlled split panes, intuitive hotkeys, and an ultra-clean status bar—enabling seamless side-by-side workflows for local AI models, editors, and terminal tools in just **~3 MB of RAM**.

```text
  🪶 Ultra-Lightweight (~3MB RAM)  •  🔓 100% Open-Source (FOSS)  •  🛡️ Secure Local Sandbox  •  🔒 Privacy-Focused (0 Telemetry)
```

---

## Quick Start

```bash
cd Setup-Tmux
chmod +x setup-tmux.sh
./setup-tmux.sh --install
```

After installation:
1. Run `source ~/.bashrc`
2. Type `tm` to launch or resume your tmux session!

---

## Key Features & Ergonomics

| Feature | How It Works |
|---|---|
| **Full Mouse Support** | Click any pane to switch focus, drag pane borders to resize, and use your mouse wheel to scroll back through thousands of lines of terminal output. |
| **Intuitive Window Splits** | <kbd>Ctrl+B</kbd> then <kbd>\|</kbd> splits vertically.<br><kbd>Ctrl+B</kbd> then <kbd>-</kbd> splits horizontally. |
| **Dual Prefix Keys** | Supports both standard <kbd>Ctrl+B</kbd> and convenient <kbd>Ctrl+A</kbd>. |
| **Vim Pane Navigation** | Move between panes using <kbd>Ctrl+B</kbd> followed by <kbd>h</kbd>, <kbd>j</kbd>, <kbd>k</kbd>, <kbd>l</kbd>. |
| **1-Based Indexing** | Windows and panes start counting at `1` instead of `0` for easy keyboard reaching. |
| **Clean Dark Status Bar** | Aesthetic, minimal status bar showing the active session, window titles, and clock. |
| **Safe Backup on Install** | Automatically saves any preexisting `~/.tmux.conf` as `~/.tmux.conf.bak`. |

---

## Daily Usage Cheat Sheet

For a detailed visual guide and multi-window developer layouts, see [USAGE-TMUX.md](USAGE-TMUX.md).

```bash
# Start a new session or attach to the existing one:
tm

# Inside tmux:
Ctrl+B then |      # Split screen vertically (side-by-side)
Ctrl+B then -      # Split screen horizontally (top-and-bottom)
Ctrl+B then c      # Create new window tab
Ctrl+B then 1-9    # Switch to window number 1-9
Ctrl+B then z      # Zoom current pane to full screen (press again to restore)
Ctrl+B then d      # Detach from session (keeps programs running in background!)
```

---

## Status Inspection

Check your tmux setup status at any time:

```bash
./setup-tmux.sh --status
```

---

## Uninstallation

To cleanly remove the configuration:

```bash
./setup-tmux.sh --uninstall
```
Removes `~/.tmux.conf`, restores any previous backup (`~/.tmux.conf.bak`), and cleans up the `tm` alias from `~/.bashrc`.

---

## Command Reference

| Flag / Parameter | Mode | Description |
|---|---|---|
| `./setup-tmux.sh --install` | User / Sudo | Installs tmux package (if missing) and links optimized `~/.tmux.conf` |
| `./setup-tmux.sh --status` | Rootless | Checks whether tmux binary and configuration file are active |
| `./setup-tmux.sh --uninstall` | Rootless | Reverts `~/.tmux.conf`, restores backups, and uninstalls shell alias |
| `./setup-tmux.sh --help` | Rootless | Displays help menu with all options |
