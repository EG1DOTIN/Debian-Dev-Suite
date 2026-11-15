# Comprehensive Step-by-Step Guide: Self-Hosting a Private GitHub on Localhost with Forgejo

This guide provides an end-to-end walkthrough for deploying a **strictly private, hardened, air-gapped GitHub alternative** on your local workstation using **Forgejo**.

Whether you are working on confidential code, intellectual property, security research, or simply want an offline Git forge with full Pull Requests, Issue tracking, Code Search, and a modern Web UI, this setup guarantees complete isolation from external networks and third parties.

---

## Table of Contents

1. [Architecture & Threat Model](#1-architecture--threat-model)
2. [Prerequisites & System Preparation](#2-prerequisites--system-preparation)
3. [Method A: Automated Turnkey Setup (Recommended)](#3-method-a-automated-turnkey-setup-recommended)
4. [Method B: Manual Step-by-Step Setup](#4-method-b-manual-step-by-step-setup)
5. [Hardened Configuration Breakdown (app.ini)](#5-hardened-configuration-breakdown-appini)
6. [Strict Network Isolation & Security Verification](#6-strict-network-isolation--security-verification)
7. [Git Workflows with Local Forgejo](#7-git-workflows-with-local-forgejo)
   - [Configuring Local SSH Keys](#configuring-local-ssh-keys)
   - [Push-to-Create Workflow](#push-to-create-workflow)
   - [Cloning and Working on Repositories](#cloning-and-working-on-repositories)
   - [Mirroring/Migrating Existing Repos from GitHub](#mirroringmigrating-existing-repos-from-github)
   - [Git Credential Storage](#git-credential-storage)
8. [Service Management & Autostart](#8-service-management--autostart)
9. [Backups, Restores & Disaster Recovery](#9-backups-restores--disaster-recovery)
10. [Upgrades & Maintenance](#10-upgrades--maintenance)
11. [USB / Portable Flash Drive Deployment](#11-usb--portable-flash-drive-deployment)
12. [Cross-OS Portability (Windows, Linux, macOS)](#12-cross-os-portability-windows-linux-macos)
13. [CI/CD Pipelines & GitHub Actions Compatibility](#13-cicd-pipelines--github-actions-compatibility)
14. [Troubleshooting & Common Questions](#14-troubleshooting--common-questions)

---

## 1. Architecture & Threat Model

### The Stack
* **Forge Core**: Forgejo binary (single Go static executable).
* **Database**: Embedded SQLite3 with Write-Ahead Logging (`WAL` mode). Zero database network sockets; stored as a local file.
* **Web Server**: Built-in Go HTTP server bound strictly to `127.0.0.1:3000`.
* **Git Transport**:
  * **HTTP**: `http://127.0.0.1:3000/`
  * **SSH**: Built-in Go SSH server bound strictly to `127.0.0.1:2222`.
* **State Directory**: `./forgejo-data/` (relative to project root, or custom directory) with `chmod 700`.

```
+-------------------------------------------------------------------------+
|                              LOCAL HOST ONLY                            |
|                                                                         |
|   +-----------------------+              +--------------------------+   |
|   |  Browser / Developer  |              |    Local Git CLI Client  |   |
|   +-----------+-----------+              +------------+-------------+   |
|               | (HTTP: 127.0.0.1:3000)                | (SSH: :2222)    |
|               |                                       |                 |
|               v                                       v                 |
|   +-----------------------------------------------------------------+   |
|   |                  FORGEJO APPLICATION SERVICE                    |   |
|   |                                                                 |   |
|   |  * OFFLINE_MODE = true         * INSTALL_LOCK = true            |   |
|   |  * DISABLE_REGISTRATION = true * DISABLE_GRAVATAR = true        |   |
|   |  * REQUIRE_SIGNIN_VIEW = true  * PUSH_CREATE_USER = true        |   |
|   +-------------------------------+---------------------------------+   |
|                                   |                                     |
|                                   v                                     |
|           +-----------------------------------------------+             |
|           |       EMBEDDED STORAGE (Local Filesystem)     |             |
|           |                                               |             |
|           |  * SQLite DB (forgejo.db with WAL mode)       |             |
|           |  * Bare Git Repositories (data/repositories/) |             |
|           |  * Encrypted Sessions & Secrets (chmod 600)   |             |
|           +-----------------------------------------------+             |
|                                                                         |
+-------------------------------------------------------------------------+
          X (NO PACKETS TO LAN, WI-FI, ROUTER, OR WAN)
```

### Threat Model & Defenses
1. **Network Eavesdropping / Port Scans on Local Wi-Fi**:
   * *Risk*: Other computers on your office/home network try to scan your ports or browse your code.
   * *Defense*: Services are bound exclusively to `127.0.0.1`. The Linux kernel routes loopback packets internally; no Ethernet or Wi-Fi network interface ever sees or transmits these packets.
2. **Third-Party CDN / Telemetry Tracking**:
   * *Risk*: Modern web software often queries Google Fonts, Gravatar, CDNs, or telemetry servers, leaking your IP and repository activity.
   * *Defense*: `OFFLINE_MODE = true` forces all assets to load from the binary. `DISABLE_GRAVATAR = true` suppresses all avatar hashing.
3. **Web Installer Hijacking**:
   * *Risk*: In unconfigured installations, an attacker who reaches the web port can run the initial wizard and take over the instance.
   * *Defense*: `INSTALL_LOCK = true` is set immediately before starting the service. The web installer is permanently disabled.
4. **Unauthorized Account Registration**:
   * *Risk*: Attackers or scripts register an account to view internal code.
   * *Defense*: `DISABLE_REGISTRATION = true` blocks all self-registration. New accounts can only be created via the local CLI or by an existing admin.
5. **Local Multi-User Snooping**:
   * *Risk*: Other local system users on a shared workstation inspect configuration files, secrets, or database tables.
   * *Defense*: All files are created under `umask 077` (`chmod 600` on files, `chmod 700` on directories). Only your Linux UID has read/write privileges.

---

## 2. Prerequisites & System Preparation

### Supported Operating Systems
* **Linux**: Debian, Ubuntu, Fedora, Arch, Alpine, CentOS/RHEL, Rocky, openSUSE.
* **WSL2** (Windows Subsystem for Linux): Ubuntu, Debian, etc.
* **macOS**: Supported natively or via rootless containers.

### Required Host Tools
Before proceeding, ensure basic command-line tools are available:
```bash
# Debian / Ubuntu:
sudo apt update && sudo apt install -y curl openssl git

# Fedora / RHEL:
sudo dnf install -y curl openssl git

# Arch Linux:
sudo pacman -S curl openssl git
```

*(Note: If you run in Docker mode, only Docker or Podman is needed).*

---

## 3. Method A: Automated Turnkey Setup (Recommended)

The standalone script `forgejo-localhost.sh` automates the entire installation, cryptographic secret generation, configuration, user setup, and verification.

### Step 1: Clone or Place the Script
Place `forgejo-localhost.sh` in your workspace and ensure it is executable:
```bash
chmod +x forgejo-localhost.sh
```

> [!TIP]
> **Path Independence**: You can place this directory anywhere on your filesystem (e.g., `/home/username/projects`, `/opt/forgejo`, or on a portable USB drive). The script dynamically detects its own directory via `$SCRIPT_DIR` and treats that location as the project root, creating `./forgejo-data` right beside the script. If you invoke it from another path or prefer a different data location, pass `--dir <path>`. No `root` (sudo) permissions are needed.

### Step 2: Run the Installer
```bash
./forgejo-localhost.sh install
```

#### What Happens Under the Hood:
1. Detects your CPU architecture (e.g. `linux-amd64` or `linux-arm64`).
2. Downloads official Forgejo binary (`v16.0.5`) from Codeberg/Forgejo mirrors.
3. Verifies GPG cryptographic signature if `gpg` is available.
4. Generates unique 256-bit cryptographic secrets via `openssl rand -hex 32`.
5. Writes the hardened `custom/conf/app.ini` with all security directives.
6. Boots the SQLite database and creates the primary `forgejo-admin` account with a secure 24-character password.
7. Starts the background daemon and verifies loopback responsiveness.
8. Runs the automated 12-point security audit.

### Step 3: Note Your Credentials & Store in a Password Manager
At the conclusion of the installation, your credentials are saved in:
```bash
cat ~/.local/share/dev-setups/forgejo/credentials.txt
# Or inspect via management script:
./forgejo-localhost.sh credentials
```
*(File permissions are strictly `chmod 600`, visible only to your user account).*

> [!TIP]
> **Password Manager Best Practice & Deleting `credentials.txt`**:
> * **Forgejo does not use `credentials.txt` at runtime**: Forgejo authenticates logins against salted cryptographic hashes (Argon2 / bcrypt) stored in its SQLite database (`data/forgejo.db`). It never reads `credentials.txt` after initialization.
> * **Move to Password Manager**: We strongly recommend saving your admin username and password into a password manager (e.g., **KeePassXC**, Bitwarden) or memorizing them.
> * **Safe to Delete**: Once saved in your password manager, you can safely delete the file:
>   ```bash
>   rm ~/.local/share/dev-setups/forgejo/credentials.txt
>   ```
> * The management script recognizes existing databases and will **never** overwrite or re-initialize your account if `credentials.txt` is removed.

### Step 4: Access the Dashboard
Open your web browser and navigate to:
```
http://127.0.0.1:3000/
```
Log in using your generated admin credentials.

---

## 4. Method B: Manual Step-by-Step Setup

If you prefer to configure everything manually without scripts, follow these exact steps:

### Step 1: Create Secure Directories
```bash
# In your project root folder:
mkdir -p ./forgejo-data/{bin,custom/conf,data,log}
chmod 700 ./forgejo-data
chmod 700 ./forgejo-data/*
cd ./forgejo-data
```

### Step 2: Download the Forgejo Binary
```bash
FORGEJO_VER="16.0.5"
ARCH="linux-amd64" # Or linux-arm64

curl -fSL -o bin/forgejo "https://code.forgejo.org/forgejo/forgejo/releases/download/v${FORGEJO_VER}/forgejo-${FORGEJO_VER}-${ARCH}"
chmod 700 bin/forgejo
```

### Step 3: Generate High-Entropy Cryptographic Secrets
```bash
SECRET_KEY=$(openssl rand -hex 32)
INTERNAL_TOKEN=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
LFS_JWT_SECRET=$(openssl rand -hex 32)
```

### Step 4: Write custom/conf/app.ini
Create `custom/conf/app.ini` (`chmod 600`):
```ini
APP_NAME = Localhost Git Forge (Strictly Private)
RUN_MODE = prod
RUN_USER = git
WORK_PATH = .

[server]
PROTOCOL = http
HTTP_ADDR = 127.0.0.1
HTTP_PORT = 3000
DOMAIN = 127.0.0.1
ROOT_URL = http://127.0.0.1:3000/
APP_DATA_PATH = data
OFFLINE_MODE = true
DISABLE_SSH = false
START_SSH_SERVER = true
SSH_PORT = 2222
SSH_LISTEN_HOST = 127.0.0.1
SSH_DOMAIN = 127.0.0.1
LANDING_PAGE = explore

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true
ENABLE_NOTIFY_MAIL = false
ENABLE_CAPTCHA = false
DEFAULT_KEEP_EMAIL_PRIVATE = true
SHOW_USER_EMAIL = false

[picture]
DISABLE_GRAVATAR = true
ENABLE_FEDERATED_AVATAR = false

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false

[repository]
ROOT = data/repositories
DEFAULT_PRIVATE = true
ENABLE_PUSH_CREATE_USER = true

[security]
INSTALL_LOCK = true
SECRET_KEY = REPLACE_WITH_GENERATED_SECRET_KEY
INTERNAL_TOKEN = REPLACE_WITH_GENERATED_INTERNAL_TOKEN
REVERSE_PROXY_LIMIT = 0
REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.1

[database]
DB_TYPE = sqlite3
PATH = data/forgejo.db
SQLITE_JOURNAL_MODE = WAL

[session]
PROVIDER = file
PROVIDER_CONFIG = data/sessions
COOKIE_SECURE = false
SAME_SITE = strict

[webhook]
ALLOWED_HOST_LIST = loopback

[log]
MODE = console, file
LEVEL = Info
ROOT_PATH = log
```
Set file permissions:
```bash
chmod 600 custom/conf/app.ini
```

### Step 5: Initialize Database & Create Admin
Run Forgejo CLI to create the admin user and populate the SQLite schema:
```bash
./bin/forgejo admin user create \
  --admin \
  --username admin \
  --password "ChooseAStrongPassword123!" \
  --email "admin@localhost.localdomain" \
  --must-change-password=false \
  --config custom/conf/app.ini \
  --work-path "$PWD"
```

### Step 6: Launch Forgejo
```bash
nohup ./bin/forgejo web --config custom/conf/app.ini --work-path "$PWD" > log/stdout.log 2>&1 &
echo $! > forgejo.pid
```

---

## 5. Hardened Configuration Breakdown (app.ini)

Let's examine the critical security directives and why they matter:

### 1. Network Boundary (`[server]`)
* `HTTP_ADDR = 127.0.0.1`: Binds the HTTP listener exclusively to IPv4 loopback. It is physically impossible for external machines on your subnet to establish a TCP handshake.
* `SSH_LISTEN_HOST = 127.0.0.1`: Ensures the internal SSH server is also loopback-only.
* `OFFLINE_MODE = true`: Prevents the frontend from making HTTP requests to external CDNs for JavaScript libraries, fonts, or CSS. All static files are loaded locally.

### 2. Zero Leakage & Identity Protection (`[picture]`, `[service]`)
* `DISABLE_GRAVATAR = true`: Gravatar sends an MD5 hash of user email addresses to external servers (`gravatar.com`), which can be used to track users or reverse-engineer email addresses. Disabling this keeps all avatars local.
* `ENABLE_FEDERATED_AVATAR = false`: Disables Libravatar lookups.
* `DEFAULT_KEEP_EMAIL_PRIVATE = true`: Automatically flags new user accounts to hide email addresses on commit views and profiles.

### 3. Attack Surface Reduction (`[service]`, `[openid]`, `[security]`)
* `DISABLE_REGISTRATION = true`: Prevents anonymous sign-ups. Only trusted users provisioned by you can access the instance.
* `REQUIRE_SIGNIN_VIEW = true`: Prevents search engine indexing, crawler snooping, and anonymous repository viewing. Without credentials, no content is visible.
* `INSTALL_LOCK = true`: Permanently locks the initial web configuration wizard. Even if someone could connect, they cannot re-run the installer.
* `ALLOWED_HOST_LIST = loopback` (`[webhook]`): Webhooks are restricted strictly to loopback addresses, completely neutralizing Server-Side Request Forgery (SSRF) vulnerabilities against your local network.

---

## 6. Strict Network Isolation & Security Verification

Never assume security—verify it. Run these commands to prove that your local forge is completely isolated.

### Verification 1: Inspect Listening Sockets
Run `ss` or `netstat` to view exact socket bindings:
```bash
ss -tulpn | grep -E ':(3000|2222)'
```
**Expected Output:**
```
tcp   LISTEN 0 4096 127.0.0.1:3000 0.0.0.0:* users:(("forgejo",pid=...,fd=...))
tcp   LISTEN 0 4096 127.0.0.1:2222 0.0.0.0:* users:(("forgejo",pid=...,fd=...))
```
Notice `127.0.0.1:3000` and `127.0.0.1:2222`. If you see `0.0.0.0` or `:::`, the service is exposed to the local network! In our hardened setup, it is strictly `127.0.0.1`.

### Verification 2: Test from External IP / LAN IP
Find your local LAN IP (e.g., `192.168.1.50` or `10.0.0.15`):
```bash
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1'
```
Now attempt to curl your LAN IP:
```bash
curl -m 2 http://YOUR_LAN_IP:3000/
```
**Expected Result:**
```
curl: (7) Failed to connect to YOUR_LAN_IP port 3000: Connection refused
```
The connection is refused at the kernel layer before any application logic runs.

### Verification 3: File Permissions Check
Verify that config files and secrets are unreadable by other local users:
```bash
ls -l ~/.local/share/dev-setups/forgejo/custom/conf/app.ini
[ -f ~/.local/share/dev-setups/forgejo/credentials.txt ] && ls -l ~/.local/share/dev-setups/forgejo/credentials.txt
```
**Expected Result:**
`-rw-------` (Permissions `600` — Owner read/write only).

*(Note: If you have already saved your credentials in KeePassXC or another password manager and deleted `credentials.txt`, only `app.ini` will be present).*

---

## 7. Git Workflows with Local Forgejo

### Configuring Local SSH Keys

Using SSH for Git operations is the most convenient method.

1. Generate a dedicated Ed25519 key pair (if you don't already have one):
   ```bash
   ssh-keygen -t ed25519 -C "local-forgejo" -f ~/.ssh/id_forgejo_local -N ""
   ```

2. Add your public key to Forgejo:
   * Log in to [http://127.0.0.1:3000/](http://127.0.0.1:3000/)
   * Go to **Settings** (`/user/settings`) -> **SSH / GPG Keys** -> **Add Key**
   * Paste the output of `cat ~/.ssh/id_forgejo_local.pub` and click **Add Key**.

3. Configure your `~/.ssh/config` file:
   ```ssh-config
   Host localhost-forge
       HostName 127.0.0.1
       Port 2222
       User git
       IdentityFile ~/.ssh/id_forgejo_local
       IdentitiesOnly yes
       StrictHostKeyChecking accept-new
   ```

### Push-to-Create Workflow

Because `ENABLE_PUSH_CREATE_USER = true` is active, you don't have to create repositories in the web UI first!

```bash
mkdir my-new-project
cd my-new-project
git init -b main

echo "# My Private Project" > README.md
git add README.md
git commit -m "feat: initial commit"

# Using SSH host alias:
git remote add origin localhost-forge:forgejo-admin/my-new-project.git

# Push to Forgejo:
git push -u origin main
```
Forgejo will automatically detect that the repository does not exist, provision a new private bare repository on disk, apply the commit, and return:
```
To localhost-forge:forgejo-admin/my-new-project.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

### Cloning and Working on Repositories

```bash
# Clone using SSH:
git clone localhost-forge:forgejo-admin/my-new-project.git

# Clone using HTTP:
git clone http://127.0.0.1:3000/forgejo-admin/my-new-project.git
```

### Mirroring/Migrating Existing Repos from GitHub

If you want to migrate existing repositories from GitHub to your private localhost forge:

```bash
# 1. Clone a mirror from GitHub
git clone --mirror https://github.com/username/my-existing-repo.git

# 2. Change into the bare repository
cd my-existing-repo.git

# 3. Create the target repo on localhost Forgejo via CLI helper
./forgejo-localhost.sh create-repo --name my-existing-repo --owner forgejo-admin

# 4. Push all branches, tags, and commits to local Forgejo
git push --mirror localhost-forge:forgejo-admin/my-existing-repo.git

# 5. Clean up temporary mirror
cd .. && rm -rf my-existing-repo.git
```

### Git Credential Storage

If using HTTP rather than SSH, you can avoid entering your password repeatedly by caching credentials locally:

```bash
git config --global credential.helper "cache --timeout=86400"
```
Or for persistent storage in your Linux desktop keyring:
```bash
git config --global credential.helper libsecret
```

---

## 8. Service Management & Autostart

### Managing the Daemon Process
Using the management script:
```bash
./forgejo-localhost.sh start
./forgejo-localhost.sh stop
./forgejo-localhost.sh restart
./forgejo-localhost.sh status
./forgejo-localhost.sh logs
```

### Managing via Systemd User Service
If installed with `--systemd` (or created at `~/.config/systemd/user/forgejo-localhost.service`):

```bash
# Start service:
systemctl --user start forgejo-localhost

# Stop service:
systemctl --user stop forgejo-localhost

# Check status:
systemctl --user status forgejo-localhost

# Enable auto-start on boot/login:
systemctl --user enable forgejo-localhost

# View live systemd journal logs:
journalctl --user-unit forgejo-localhost -f
```

To allow the user service to continue running even after you log out:
```bash
loginctl enable-linger $USER
```

---

## 9. Backups, Restores & Disaster Recovery

### Hot Backups (Zero Downtime)
Because Forgejo uses SQLite in Write-Ahead Logging (`WAL`) mode, creating a backup requires flushing pending transactions first.

The script automates this via:
```bash
./forgejo-localhost.sh backup
```

This performs:
1. `PRAGMA wal_checkpoint(TRUNCATE);` to ensure the `.db` file has all committed transactions.
2. Creates an archive containing:
   * `data/forgejo.db` (database schema, PRs, issues, user data)
   * `data/repositories/` (all bare Git repositories)
   * `custom/conf/app.ini` (server configurations & secrets)
   * `credentials.txt` (access records)
3. Saves to `./forgejo-data/backups/forgejo_backup_YYYYMMDD_HHMMSS.tar.gz` with `chmod 600`.

### Restoring from Backup
```bash
./forgejo-localhost.sh restore --file /path/to/forgejo_backup_20261010_120000.tar.gz
```

---

## 10. Upgrades & Maintenance

Upgrading Forgejo is as simple as replacing the single binary. Because the database schema auto-migrates forward on startup:

1. Stop the running service:
   ```bash
   ./forgejo-localhost.sh stop
   ```
2. Create a backup first:
   ```bash
   ./forgejo-localhost.sh backup
   ```
3. Download the new version binary:
   ```bash
   NEW_VER="16.0.6"
   ARCH="linux-amd64"
   curl -fSL -o ./forgejo-data/bin/forgejo \
     "https://code.forgejo.org/forgejo/forgejo/releases/download/v${NEW_VER}/forgejo-${NEW_VER}-${ARCH}"
   chmod 700 ./forgejo-data/bin/forgejo
   ```
4. Start the service:
   ```bash
   ./forgejo-localhost.sh start
   ```

---

## 11. USB / Portable Flash Drive Deployment

You can carry and run your entire private GitHub instance directly from a **USB flash drive or portable SSD**.

### Why It Works
1. **Self-Contained Data Engine**: All user records, issue trackers, pull requests, bare Git repositories, and configuration files reside strictly within `./forgejo-data`.
2. **Zero System Registry / Daemon Footprint**: The Forgejo binary runs in user space without requiring root privileges or system daemon registration.
3. **No Network Installation**: Once downloaded to the drive, it requires no internet connection to start and operate.

### Step-by-Step USB Setup
1. Format your USB drive:
   * **For pure Linux usage**: Format as `ext4`. This preserves native POSIX file permissions (`chmod 600` on credentials, `chmod 700` on data).
   * **For cross-platform usage (Linux & Windows)**: Format as `exFAT` or `NTFS`.
2. Copy this repository folder onto the USB drive.
3. Open a terminal on the mounted USB drive:
   ```bash
   cd /media/your-username/USB_DRIVE/forgejo-localhost
   ./forgejo-localhost.sh start
   ```
4. Access the forge at `http://127.0.0.1:3000/`.

### Critical Rule: Safe Unmounting (SQLite WAL Integrity)
Because Forgejo runs SQLite with Write-Ahead Logging (`WAL`), active database pages are cached in memory and in the `-wal` file.
> [!CAUTION]
> **Always run `./forgejo-localhost.sh stop` before unplugging or unmounting the USB drive!**
> Stopping the service gracefully flushes all commits and checkpoints the WAL file into `forgejo.db`. Pulling out a live USB drive while transactions are in progress can corrupt the SQLite database.

---

## 12. Cross-OS Portability (Windows, Linux, macOS)

The **data layer is 100% portable** across all operating systems, but the executable binary itself is platform-specific.

### Cross-OS Architecture
* **Portable across all OSes**: `data/forgejo.db` (SQLite file), `data/repositories/` (standard Git bare repos), `custom/conf/app.ini`, and `credentials.txt`.
* **Platform-specific**: The Forgejo executable binary.

### Running on Windows

#### Method 1: Windows Subsystem for Linux (WSL2) — Recommended
If you have WSL2 enabled on Windows:
1. Insert the USB drive (Windows typically mounts it at `D:` or `E:`).
2. Open your WSL2 terminal (Ubuntu/Debian).
3. Access the USB drive mount point:
   ```bash
   cd /mnt/d/path-to-forgejo
   ./forgejo-localhost.sh start
   ```
4. Open your browser in Windows at `http://127.0.0.1:3000/`.

#### Method 2: Native Windows Executable (`forgejo.exe`)
You can run Forgejo natively on Windows without WSL or Docker:
1. Download the official Windows 64-bit binary from Codeberg:
   `forgejo-16.0.5-windows-amd64.exe`
2. Place it on the USB drive next to `forgejo-localhost.sh` and rename it to `forgejo.exe`.
3. Create a simple Windows launcher script `start-forgejo-windows.bat`:
   ```bat
   @echo off
   echo Starting Forgejo on localhost:3000...
   forgejo.exe web --config forgejo-data\custom\conf\app.ini --work-path forgejo-data
   pause
   ```
4. Double-click `start-forgejo-windows.bat` on any Windows PC.

### Running on macOS
On macOS (Apple Silicon M1/M2/M3 or Intel):
1. Download the macOS binary: `forgejo-16.0.5-darwin-arm64` (or `darwin-amd64`).
2. Make it executable (`chmod +x forgejo`).
3. Run:
   ```bash
   ./forgejo web --config ./forgejo-data/custom/conf/app.ini --work-path ./forgejo-data
   ```

---

## 13. CI/CD Pipelines & GitHub Actions Compatibility

Forgejo includes a full-featured, built-in CI/CD pipeline engine called **Forgejo Actions**, which is **compatible with GitHub Actions**.

### Key Features
* **Identical YAML Syntax**: Workflows use `.github/workflows/*.yaml` or `.forgejo/workflows/*.yaml`.
* **Full Pipeline Constructs**: Supports `on: [push, pull_request]`, jobs, steps, environment variables, secrets, matrices, and container actions.
* **Local Web UI Feedback**: View real-time log streaming, job stages, commit status badges, and pull request check indicators directly in your localhost dashboard.

### How It Works Locally
1. **Forgejo Web Server**: Acts as the coordinator and API server (equivalent to `github.com`).
2. **`act_runner` Daemon**: A lightweight, standalone worker based on `nektos/act` that pulls jobs from Forgejo and executes them inside local Docker containers or directly on the host shell.

### Enabling Pipelines Step-by-Step

#### Step 1: Enable Actions in Configuration
In `forgejo-data/custom/conf/app.ini`, locate or add the `[actions]` section:
```ini
[actions]
ENABLED = true
```
Restart Forgejo to apply:
```bash
./forgejo-localhost.sh restart
```

#### Step 2: Obtain a Runner Registration Token
1. Open [http://127.0.0.1:3000/](http://127.0.0.1:3000/) and log in as your administrator.
2. Navigate to **Site Administration** (wrench icon in top right) -> **Actions** -> **Runners**.
3. Click **Create new Runner** and copy the displayed registration token.

#### Step 3: Download and Register `act_runner`
```bash
# 1. Download the official act_runner binary
curl -fSL -o act_runner https://code.forgejo.org/forgejo/runner/releases/download/v6.2.2/act_runner-6.2.2-linux-amd64
chmod +x act_runner

# 2. Register with your local Forgejo instance
./act_runner register \
  --instance http://127.0.0.1:3000 \
  --token <YOUR_REGISTRATION_TOKEN> \
  --no-interactive

# 3. Start the runner daemon
./act_runner daemon
```

#### Step 4: Add a GitHub Actions Workflow
In any repository, commit a workflow file at `.github/workflows/test.yaml`:
```yaml
name: Local CI Test
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      - name: Run local test suite
        run: |
          echo "Running tests on localhost forge!"
          date
```
Whenever you push commits to your repository, the runner will execute the job locally and report results directly in the Web UI!

---

## 14. Troubleshooting & Common Questions

### Issue: "Port 3000 is already in use"
* **Diagnosis**: Another local service (e.g. Grafana, React dev server, nodejs) is occupying port 3000.
* **Fix**: Run the installer with a custom port:
  ```bash
  ./forgejo-localhost.sh install --port 3333
  ```

### Issue: "fatal: Could not read from remote repository (SSH port 2222)"
* **Diagnosis**: SSH is attempting to connect on default port 22 instead of Forgejo's port 2222, or SSH key is not added to Forgejo.
* **Fix**: Ensure your remote URL includes the port explicitly:
  ```bash
  git remote set-url origin ssh://git@127.0.0.1:2222/username/reponame.git
  ```
  And verify your public key is added in **User Settings -> SSH / GPG Keys**.

### Issue: "Database is locked" in SQLite
* **Diagnosis**: Multiple concurrent processes accessed the SQLite file without WAL mode.
* **Fix**: WAL mode is enabled by default in our configuration (`SQLITE_JOURNAL_MODE = WAL`). Ensure no zombie Forgejo processes are running:
  ```bash
  killall forgejo
  ./forgejo-localhost.sh start
  ```

### Issue: Can I enable HTTPS locally?
* Yes! If your workflow requires HTTPS (e.g., testing webhooks with local certs), run:
  ```bash
  ./forgejo-localhost.sh install --enable-tls
  ```
  The script generates a 2048-bit self-signed certificate in `custom/conf/tls/` valid for `127.0.0.1` and `localhost`.
