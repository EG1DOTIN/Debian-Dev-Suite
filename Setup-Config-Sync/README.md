# Developer Config & Dotfiles Sync (`Setup-Config-Sync`)

A lightweight, 100% private backup and synchronization engine that archives your personal developer settings—including **`.bashrc`**, **`.gitconfig`**, **Geany dark themes**, **LazyGit**, and **tmux** configurations.

Designed to eliminate the tedious hours spent re-configuring editors, shortcuts, and aliases when switching between PCs (e.g. antiX laptop to MX Linux workstation) or recovering from a fresh OS install.

```text
  💾 Local ZIP & TAR.GZ  •  🔌 Offline USB Transfer  •  ☁️ Optional Google Drive Sync  •  🛡️ Safe .bak Restores
```

---

## Table of Contents

- [What It Backs Up](#what-it-backs-up)
- [Local PC & Offline USB Workflow](#local-pc--offline-usb-workflow)
- [Automatic Google Drive Cloud Sync](#automatic-google-drive-cloud-sync)
- [Quick Start](#quick-start)
  - [1. Create a Backup](#1-create-a-backup)
  - [2. Restore on Another PC](#2-restore-on-another-pc)
  - [3. Register Quick Terminal Shortcuts](#3-register-quick-terminal-shortcuts)
  - [4. Clean Uninstallation](#4-clean-uninstallation)
- [CLI Parameter Reference](#cli-parameter-reference)
- [Safety & Privacy Protections](#safety--privacy-protections)

---

## What It Backs Up

| File / Folder | What It Contains |
|---|---|
| `~/.bashrc` | Custom aliases (`lg`, `ll`, `tm`, `ai`), environment variables, and shell functions. |
| `~/.gitconfig` | Git user identity, default branch (`main`), and custom Git log/status aliases. |
| `~/.tmux.conf` | Mouse scrolling, window split keys (`\|`, `-`), and dark aesthetic status bar. |
| `~/.config/geany/` | Custom dark color schemes (Monokai, Bespin), syntax styling, and compiler build hotkeys. |
| `~/.config/lazygit/` | Custom LazyGit keybindings and UI themes. |
| `~/.config/rclone/` | *(Optional prompt)* Encrypted Google Drive connection tokens. |

---

## Local PC & Offline USB Workflow

Whenever you run a backup, the tool **always creates a local ZIP and TAR.GZ archive** on your machine at:
```text
/home/<user>/Debian-Dev-Backups/dev-configs-latest.zip
```

### Transferring to Another PC via USB Flash Drive:

1. **On your primary PC:** Run `./backup-dev-configs.sh --backup`
2. **Copy to your USB drive:**
   ```bash
   cp ~/Debian-Dev-Backups/dev-configs-latest.zip /media/$USER/<USB_NAME>/
   ```
3. **On your secondary PC:** Plug in the USB and restore:
   ```bash
   ./backup-dev-configs.sh --restore /media/$USER/<USB_NAME>/dev-configs-latest.zip
   ```
   *(Or copy the file to the other PC and run `--restore`).*

Your editor themes, Git aliases, and terminal configurations are instantly applied!

---

## Automatic Google Drive Cloud Sync

If you have **`Setup-GDrive`** mounted at `~/GoogleDrive`:
- The script automatically copies the newly created archive into:
  ```text
  ~/GoogleDrive/Debian-Dev-Backups/dev-configs-latest.zip
  ```
- On any other PC connected to your Google Drive, running `--restore` automatically detects the cloud archive without needing any file paths or USB sticks!

---

## Quick Start

### 1. Create a Backup
```bash
cd Setup-Config-Sync
chmod +x backup-dev-configs.sh
./backup-dev-configs.sh --backup
```

---

### 2. Restore on Another PC
```bash
cd Setup-Config-Sync
./backup-dev-configs.sh --restore
```
*(If no file argument is passed, it automatically searches for the latest backup in Google Drive or your local backup folder).*

---

### 3. Register Quick Terminal Shortcuts
Add `backup-configs` and `restore-configs` commands to your `~/.bashrc`:

```bash
./backup-dev-configs.sh --install-aliases
source ~/.bashrc
```

Now you can back up from anywhere in your terminal simply by typing:
```bash
backup-configs
```

---

### 4. Clean Uninstallation
To remove the shell aliases and optionally purge local backup files:

```bash
cd Setup-Config-Sync
./backup-dev-configs.sh --uninstall
```

The uninstallation process:
1. Safely strips `backup-configs` and `restore-configs` alias lines from your `~/.bashrc`.
2. Interactively prompts whether you wish to delete or preserve your local backup archives in `~/Debian-Dev-Backups/`.
3. Leaves all your active dotfiles (`~/.bashrc`, `~/.gitconfig`, `~/.tmux.conf`, `~/.config/geany`) 100% untouched.

---

## CLI Parameter Reference

| Parameter | Short Flag | Description |
|---|---|---|
| `--backup` | | Creates local ZIP and TAR.GZ archives in `~/Debian-Dev-Backups/` and auto-syncs to Google Drive if mounted |
| `--restore [file]` | | Restores configurations from a specified archive or auto-detects the latest local/cloud backup |
| `--list` | | Lists all available local and Google Drive backup archives with dates and sizes |
| `--install-aliases`, `--install` | | Registers `backup-configs` and `restore-configs` shortcuts in `~/.bashrc` |
| `--uninstall` | | Cleanly removes shell aliases from `~/.bashrc` and optionally cleans backup directories |
| `--status` | `-s` | Displays diagnostic summary of local archives, Google Drive mount status, and tracked dotfiles |
| `--help` | `-h` | Shows usage manual and all available options |

---

## Safety & Privacy Protections

1. **Non-Destructive Restores:** Before replacing any configuration on your target machine, the script automatically creates a timestamped safety backup in `~/.config-safety-backup-<timestamp>/`. Your existing settings are never lost.
2. **100% Private (0 Cloud Leaks):** Unlike public GitHub dotfile repositories that risk leaking sensitive tokens, your backup stays strictly on your local PC, offline USB, or your private Google Drive account.
3. **Hardened Permissions & Safe Temporary Folders:** Temporary staging directories are created using `mktemp -d` with strict `0700` permissions and cleanup traps (mitigating CWE-377). Local backup folders and generated archives are locked to modes `0700` and `0600`, preventing unprivileged local users from inspecting sensitive dotfiles or OAuth tokens.
4. **Strict Restored File Permissions:** Restored sensitive files (like `rclone.conf`) are automatically locked down with secure `chmod 600` permissions.
