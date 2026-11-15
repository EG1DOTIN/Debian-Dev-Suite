# Config Sync Usage Guide — Multi-PC Sync & Offline USB Recovery

A step-by-step walkthrough for syncing your developer configurations across multiple computers.

---

## Table of Contents

- [Scenario 1: Offline USB Transfer (e.g. antiX Laptop to MX Linux PC)](#scenario-1-offline-usb-transfer-eg-antix-laptop-to-mx-linux-pc)
- [Scenario 2: Automatic Sync via Google Drive](#scenario-2-automatic-sync-via-google-drive)
- [Inspecting Backups](#inspecting-backups)
- [Reverting a Restore (Using the Safety Backup)](#reverting-a-restore-using-the-safety-backup)

---

## Scenario 1: Offline USB Transfer (e.g. antiX Laptop to MX Linux PC)

When working offline or moving settings between machines that aren't on the same network:

### Step 1: Create Backup on PC #1 (Source PC)
On your primary machine:
```bash
cd Setup-Config-Sync
./backup-dev-configs.sh --backup
```
The script will output:
```text
✔ Local backup created successfully!
  Location: ~/Debian-Dev-Backups/dev-configs-latest.zip
```

### Step 2: Copy to USB Flash Drive
Plug your USB stick into PC #1 and run:
```bash
cp ~/Debian-Dev-Backups/dev-configs-latest.zip /media/$USER/<USB_NAME>/
```

### Step 3: Restore on PC #2 (Target PC)
Plug the USB stick into PC #2 and run:
```bash
cd Setup-Config-Sync
./backup-dev-configs.sh --restore /media/$USER/<USB_NAME>/dev-configs-latest.zip
```
The script safely restores your `.bashrc`, `.gitconfig`, `.tmux.conf`, and Geany themes.

Reload your terminal:
```bash
source ~/.bashrc
```

---

## Scenario 2: Automatic Sync via Google Drive

If both machines have **`Setup-GDrive`** mounted at `~/GoogleDrive`:

### Step 1: Back up on PC #1
```bash
backup-configs
```
The archive is saved locally and automatically copied to `~/GoogleDrive/Debian-Dev-Backups/dev-configs-latest.zip`.

### Step 2: Restore on PC #2
On your second computer, simply run:
```bash
restore-configs
```
The script automatically detects the cloud archive in Google Drive, restores all settings, and prompts you to reload your terminal. **Done in 2 seconds!**

---

## Inspecting Backups

To see what archives are currently stored locally and in Google Drive:

```bash
./backup-dev-configs.sh --list
```

Sample output:
```text
==================================================================
  Available Configuration Backups
==================================================================
Local Backups (~/Debian-Dev-Backups):
-rw-r--r-- 1 <user> <group>  45K Sep 21 14:15 dev-configs-2026-09-21_141520.tar.gz
-rw-r--r-- 1 <user> <group>  48K Sep 21 14:15 dev-configs-2026-09-21_141520.zip
-rw-r--r-- 1 <user> <group>  48K Sep 21 14:15 dev-configs-latest.zip

Google Drive Backups (~/GoogleDrive/Debian-Dev-Backups):
-rw-r--r-- 1 <user> <group>  48K Sep 21 14:15 dev-configs-latest.zip
```

---

## Reverting a Restore (Using the Safety Backup)

Whenever you run `--restore`, a safety backup of your previous files is created in `~/.config-safety-backup-<timestamp>/`.

If you ever wish to undo a restore:
```bash
cp ~/.config-safety-backup-<timestamp>/bashrc ~/.bashrc
cp ~/.config-safety-backup-<timestamp>/gitconfig ~/.gitconfig
cp ~/.config-safety-backup-<timestamp>/tmux.conf ~/.tmux.conf
source ~/.bashrc
```
Your previous settings are restored immediately.
