# Google Drive Setup & Mount for Debian-based Systems

A lightweight, robust, and 100% open-source solution to mount Google Drive as a local folder on **Debian, antiX, Ubuntu, Linux Mint, MX Linux, Devuan**, and any other Debian-based distribution.

Powered by **Rclone** and **FUSE (Filesystem in Userspace)**, this allows you to access and stream your Google Drive files directly inside your file manager or terminal without downloading your entire drive or running bloated proprietary software.

---

## Table of Contents

- [What, Why, and How](#what-why-and-how)
  - [What is this?](#what-is-this)
  - [Why Rclone + FUSE?](#why-rclone--fuse)
  - [How does it work?](#how-does-it-work)
- [Prerequisites (Important Note on System Clock)](#prerequisites-important-note-on-system-clock)
- [Pre-Run Walkthrough: What to Expect During `rclone config`](#pre-run-walkthrough-what-to-expect-during-rclone-config)
  - [Step-by-Step Prompt Answers](#step-by-step-prompt-answers)
  - [Desktop Browser vs Headless / SSH Authentication](#desktop-browser-vs-headless--ssh-authentication)
  - [Optional: Custom Google OAuth Client ID](#optional-custom-google-oauth-client-id)
- [Installation Guide (`--install`)](#installation-guide---install)
  - [1. Run the Installer](#1-run-the-installer)
  - [2. What the Installer Does](#2-what-the-installer-does)
- [Daily Usage](#daily-usage)
  - [Mounting Google Drive](#mounting-google-drive)
  - [Accessing Your Files](#accessing-your-files)
  - [Unmounting Google Drive](#unmounting-google-drive)
- [Uninstallation Guide (`--uninstall`)](#uninstallation-guide---uninstall)
  - [Dependency Removal Option](#dependency-removal-option)
- [Configuring Autostart on Login (Optional)](#configuring-autostart-on-login-optional)
  - [antiX Linux (`~/.desktop-session/startup`)](#antix-linux-desktop-sessionstartup)
  - [Standard Desktop / XFCE / GNOME (`~/.config/autostart`)](#standard-desktop--xfce--gnome-configautostart)
- [Troubleshooting & FAQs](#troubleshooting--faqs)

---

## What, Why, and How

### What is this?
This tool configures your system so that your Google Drive appears as a regular local folder at:
```text
/home/<your-username>/GoogleDrive
```
You can view, edit, copy, paste, create, and delete files using your favorite file manager (Thunar, PCManFM, ROX-Filer, Nautilus) or standard terminal commands (`ls`, `cp`, `mv`, `cat`).

The helper management scripts are cleanly placed in:
```text
/home/<your-username>/GoogleDrive-Bin
```

### Why Rclone + FUSE?
- **100% Free and Open-Source (FOSS):** No closed-source binaries, no third-party telemetry, and no account tracking.
- **On-Demand Streaming (Full VFS Caching):** Unlike traditional sync clients that copy every gigabyte of your cloud storage onto your hard drive, Rclone streams files on-demand. When you open a PDF or image, only that file is fetched into a local disk cache. This saves vast amounts of disk space.
- **High-Performance Uploads & Deletions:** Uses 64MB chunk sizes (`--drive-chunk-size 64M`) for 3–5x faster uploads, bypasses trash (`--drive-use-trash=false`) for instant deletions, and caches directory listings (`--dir-cache-time 1000h`) so your file manager never freezes when browsing folders.
- **Ultra-Lightweight Resource Footprint:** Official desktop cloud clients often consume 300 MB–800 MB of RAM using heavy Electron frameworks. Rclone is written in Go and typically uses only **20 MB–50 MB of RAM**, making it ideal for resource-constrained systems (e.g., 2 GB–3 GB RAM) as well as high-performance workstations.
- **Fast and Resilient:** Operates as a background daemon with directory caching and automatic asynchronous writeback.

### How does it work?
1. **Rclone** communicates securely with Google Drive via Google's official REST API over HTTPS.
2. **FUSE (Filesystem in Userspace)** translates standard Linux filesystem calls (`open`, `read`, `write`, `unlink`) into Rclone cloud API requests.
3. Two simple helper scripts are created in `~/GoogleDrive-Bin`:
   - `mount-gdrive` : Starts the background daemon and mounts the filesystem with verification, performance flags, and logging.
   - `unmount-gdrive` : Safely flushes writes and unmounts the folder with lazy unmount fallback.

---

## Prerequisites (Important Note on System Clock)

> [!IMPORTANT]
> **Your system time MUST be accurate before configuring or mounting Google Drive!**
> Google's OAuth2 authentication servers validate timestamps on login tokens. If your computer's clock is set to **year 2008** (common on systems with dead CMOS batteries), Google will reject your authentication request with SSL/TLS certificate errors.
>
> If your system clock resets to 2008, run the time synchronizer first:
> ```bash
> sudo ../Setup-Sync-Time/sync-time.sh
> ```

---

## Pre-Run Walkthrough: What to Expect During `rclone config`

When you run `setup-GoogleDrive.sh --install`, it will launch `rclone config` to link your Google account. Here is exactly what will appear and what you should type:

### Step-by-Step Prompt Answers

| Prompt | What to Type / Press | Explanation |
|---|---|---|
| `e/n/d/r/c/s/q>` | **`n`** | Creates a **n**ew remote |
| `name>` | **`gdrive`** | The name identifier for your remote |
| `Type of storage to configure>` | **`drive`** | Selects Google Drive (or type the corresponding number) |
| `client_id>` | *Press ENTER* | Leave blank to use Rclone's default client (or enter custom ID) |
| `client_secret>` | *Press ENTER* | Leave blank (or enter custom secret) |
| `scope>` | **`1`** | Grants full access to files and folders |
| `service_account_file>` | *Press ENTER* | Leave blank |
| `Edit advanced config?>` | **`n`** | Default options are optimal |
| `Use auto config?>` | **`y`** (Desktop) or **`n`** (SSH/Headless) | See section below |
| `Keep this "gdrive" remote?>` | **`y`** | Confirms saving the configuration |
| `e/n/d/r/c/s/q>` | **`q`** | **Q**uits configuration |

### Desktop Browser vs Headless / SSH Authentication

When `rclone` asks `Use auto config?`:
- **If you are on Desktop Linux with a web browser (Firefox, Chromium, etc.):**
  - Type **`y`** and press ENTER.
  - A browser window will automatically open with Google's login page.
  - Sign in to your Google Account and click **"Allow"**.
  - Your browser will say *"Success!"* and you can return to the terminal.
- **If you are connected via SSH or running without a web browser:**
  - Type **`n`** and press ENTER.
  - Rclone will display a verification URL.
  - Copy that URL into a browser on any other phone or PC, log in, and copy the authorization code.
  - Paste the code back into the terminal prompt.

### Optional: Custom Google OAuth Client ID
Rclone's default client ID is shared by millions of users, which occasionally leads to low Google API rate limits or a warning saying *"Google hasn't verified this app"* (where you have to click *Advanced -> Go to rclone (unsafe)*).
If you prefer your own personal API quota, you can create a free OAuth Client ID in the [Google Cloud Console](https://console.cloud.google.com/) and enter your custom `client_id` and `client_secret` when prompted.

---

## Installation Guide (`--install`)

### 1. Run the Installer
In your terminal, navigate to the `Setup-GDrive` directory and run:
```bash
cd Setup-GDrive
chmod +x setup-GoogleDrive.sh
./setup-GoogleDrive.sh --install
```

### 2. What the Installer Does
1. **Clock Pre-Check:** Verifies that your clock is not in year 2008.
2. **Package Verification:** Checks if `rclone` and `fuse3` (or `fuse`) are already installed. If missing, installs them via `apt`.
3. **Directory Creation:** Creates `~/GoogleDrive` (mount directory), `~/GoogleDrive-Bin` (dedicated scripts folder), and `~/.cache/rclone` (log directory).
4. **Account Link:** Launches `rclone config` and verifies that the `gdrive:` remote was configured.
5. **Generates Helper Commands in `~/GoogleDrive-Bin`:**
   - Creates `~/GoogleDrive-Bin/mount-gdrive` with verified background daemon mounting.
   - Creates `~/GoogleDrive-Bin/unmount-gdrive` with graceful and lazy unmount fallbacks.
6. **PATH Configuration:** Ensures `~/GoogleDrive-Bin` is added to your `$PATH` via `~/.bashrc`.
7. **System Shortcuts:** Optionally offers to create system-wide `/usr/local/bin` shortcuts.
8. **Autostart:** Optionally configures automatic mounting upon desktop login.

---

## Daily Usage

### Mounting Google Drive
Whenever you want to access your cloud files, run:
```bash
mount-gdrive
```
*(Or via direct path: `~/GoogleDrive-Bin/mount-gdrive`)*

**What happens:**
- Rclone starts in the background as a daemon (`--daemon`).
- Full read/write local disk caching is enabled (`--vfs-cache-mode full`).
- Upload chunk sizes are boosted to 64MB (`--drive-chunk-size 64M`) for 3–5x faster uploads.
- Direct deletions are enabled (`--drive-use-trash=false`) so file and folder deletions are instant.
- Directory listings are cached for 1000 hours (`--dir-cache-time 1000h`), keeping folder browsing instant without freezing file managers.
- Live cloud polling (`--poll-interval 1m`) syncs changes made from other devices every minute.
- Verifies that the mount succeeded and displays a confirmation.

### Optimized Performance Flags Breakdown

The mount script uses heavily tuned flags designed for responsive daily workflow:

| Flag | Value | Purpose & Performance Impact |
|---|---|---|
| `--vfs-cache-mode` | `full` | Complete local disk caching for both reads and writes. Text editors, IDEs, and office tools open and save files instantly to local cache while Rclone handles uploading in the background. |
| `--drive-chunk-size` | `64M` | Increases upload stream chunk size from the default 8MB to 64MB. Drastically cuts down HTTP API roundtrips, speeding up file uploads by **3x to 5x**. |
| `--drive-use-trash` | `false` | Bypasses Google Drive Trash. Files are deleted permanently and immediately, eliminating the slow metadata updates that cause file managers to hang during deletions. |
| `--dir-cache-time` | `1000h` | Caches the remote directory hierarchy for 1000 hours so that opening folders in Thunar, PCManFM, or terminal is near-instant. |
| `--poll-interval` | `1m` | Pairs with directory cache: actively asks Google Drive for changes every minute so local directory listings stay in sync with cloud modifications without constantly refetching the entire tree. |
| `--vfs-cache-max-age` | `24h` | Retains active cached files locally for 24 hours, avoiding repeated re-downloads of files you are currently working on. |
| `--vfs-cache-max-size` | `10G` | Caps total local cache size at 10 GB to prevent your hard drive from filling up. |
| `--buffer-size` | `16M` | Allocates a 16MB memory buffer per active file stream, ensuring smooth reads while maintaining a minimal RAM footprint (~20–40 MB). |

### Accessing Your Files in PCManFM / File Manager
- Open **PCManFM** (or your file manager).
- Look at the left sidebar under **Bookmarks / Places**: you will see **`GoogleDrive`** ready to click!
- You can browse, drag and drop, open, edit, and save files normally.
- In terminal:
  ```bash
  cd ~/GoogleDrive
  ls -la
  ```

### Option 1: Virtual Live Mount (Browsing like local disk)
Best when you want Google Drive to act like an external hard drive or USB thumb drive:
- **Mount:** `mount-gdrive` (or `~/GoogleDrive-Bin/mount-gdrive`)
- **Unmount:** `unmount-gdrive` (or `~/GoogleDrive-Bin/unmount-gdrive`)

**What happens on mount:**
- Rclone starts in the background as a daemon (`--daemon`).
- Full read/write local disk caching is enabled (`--vfs-cache-mode full`).
- Upload chunk sizes are boosted to 64MB (`--drive-chunk-size 64M`) for 3–5x faster uploads.
- Direct deletions are enabled (`--drive-use-trash=false`) so deletions are instant.
- Directory listings are cached for 1000 hours (`--dir-cache-time 1000h`), keeping folder browsing instant without freezing file managers.
- Live cloud polling (`--poll-interval 1m`) syncs changes made from other devices every minute.

### Option 2: Direct Fast Sync (Zero FUSE Overhead, Maximum Transfer Speed)
Best when you want maximum speed without keeping a background virtual mount running:
- **Upload local folder to Google Drive:**
  ```bash
  gdrive-push
  ```
  *(Runs `rclone copy ~/GoogleDrive gdrive:` with 4 parallel transfers, 64MB chunks, and a live progress bar).*
- **Download Google Drive to local folder:**
  ```bash
  gdrive-pull
  ```
  *(Downloads your cloud files to `~/GoogleDrive` at full multi-threaded connection speed).*

> [!TIP]
> **Why Option 2 (Direct Sync) is Lightning Fast:**
> Virtual FUSE mounts translate every filesystem call over kernel pipes. Direct sync transfers files directly over multi-threaded HTTPS streams, completely bypassing filesystem overhead. If you just want to backup files or grab documents quickly, `gdrive-push` and `gdrive-pull` are the fastest method.

### Unmounting Google Drive
When you are done with the live mount or before disconnecting:
```bash
unmount-gdrive
```
**What happens:**
- Flushes any pending cached uploads to Google Drive.
- Unmounts cleanly using `fusermount3` / `fusermount`.
- If an application has an open file, it automatically falls back to a lazy unmount (`-uz`) to prevent terminal freezing.

---

## Uninstallation Guide (`--uninstall`)

If you want to remove the Google Drive setup:
```bash
cd Setup-GDrive
./setup-GoogleDrive.sh --uninstall
```

### What the Uninstaller Does:
1. Safely unmounts `~/GoogleDrive` if currently mounted.
2. Removes autostart entries (`~/.desktop-session/startup` and `~/.config/autostart`).
3. Removes system shortcuts in `/usr/local/bin`.
4. Removes scripts inside `~/GoogleDrive-Bin` and cleans up the folder.
5. Removes `GoogleDrive-Bin` from `~/.bashrc` PATH.
6. Prompts whether to remove the local mount folder (`~/GoogleDrive`).
7. Prompts whether to remove Rclone credentials (`rclone.conf`).
8. **Dependency Removal Option:** Prompts:
   ```text
   Do you want to uninstall system packages (rclone, fuse3/fuse)? [y/N]:
   ```
   - If **`y`**: Removes `rclone` and `fuse` via `apt purge` and cleans unused packages.
   - If **`N`**: Leaves `rclone` and `fuse` installed for other tools.

---

## Configuring Autostart on Login (Optional)

If you chose not to enable autostart during the installation script, you can easily enable it manually:

### antiX Linux (`~/.desktop-session/startup`)
Open `~/.desktop-session/startup` in a text editor (e.g. `nano ~/.desktop-session/startup`) and add this line near the bottom:
```bash
$HOME/GoogleDrive-Bin/mount-gdrive &
```
Save and exit. Google Drive will now mount automatically every time you log into antiX.

### Standard Desktop / XFCE / GNOME (`~/.config/autostart`)
Create an autostart desktop entry:
```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/mount-gdrive.desktop <<EOF
[Desktop Entry]
Type=Application
Exec=sh -c '"$HOME/GoogleDrive-Bin/mount-gdrive"'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Mount Google Drive
Comment=Mount Google Drive folder on desktop login
EOF
```

---

## Troubleshooting & FAQs

### 1. "Failed to mount Google Drive"
Check the Rclone mount log file:
```bash
cat ~/.cache/rclone/gdrive-mount.log
```
- **Error: `directory not found` or `remote not found`:** Check configured remotes using `rclone listremotes`. If your remote is named something other than `gdrive:`, re-run `setup-GoogleDrive.sh --install` or edit `~/GoogleDrive-Bin/mount-gdrive` to match the name.
- **Error: `token expired` or `oauth error`:** Your login session expired. Re-authenticate by running `rclone config reconnect gdrive:`.
- **Error: `SSL/TLS certificate verification failed`:** Your system clock has reset to year 2008. Run `sudo ../Setup-Sync-Time/sync-time.sh`.

### 2. "Device or resource busy" during unmount
This occurs when a terminal window or file manager tab is currently inside `~/GoogleDrive`, or an editor has an open file.
- Navigate out of the folder (`cd ~`) and close any open documents.
- Run `unmount-gdrive` again. The updated script will automatically apply a lazy unmount (`fusermount3 -uz`) if needed.

### 3. "command not found: mount-gdrive"
If `mount-gdrive` is not recognized:
- Run `source ~/.bashrc` or open a new terminal window.
- Alternatively, run it using the full path: `~/GoogleDrive-Bin/mount-gdrive`.

### 4. How much disk space does Rclone use for cache?
By default, Rclone only caches files you are actively modifying or reading in `~/.cache/rclone/vfs`. Once files are uploaded, old cache entries are automatically purged. You can clear the cache at any time when unmounted:
```bash
rm -rf ~/.cache/rclone/vfs
```
