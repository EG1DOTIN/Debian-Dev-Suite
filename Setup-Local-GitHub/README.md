# Localhost Git Forge (Forgejo)

A production-ready, completely private, and strictly hardened **GitHub alternative running entirely on `localhost` (127.0.0.1)** using **Forgejo** (the community-governed, lightweight fork of Gitea).

Zero cloud dependency. Zero telemetry. Zero exposure to your local network (LAN) or the internet.

---

## Highlights

* 🔒 **Strict 127.0.0.1 Binding**: Both HTTP (`127.0.0.1:3000`) and SSH (`127.0.0.1:2222`) bind exclusively to loopback. External devices on your Wi-Fi/LAN cannot reach or scan your forge.
* 🛡 **Air-Gapped Privacy**: `OFFLINE_MODE = true`, Gravatar disabled, Libravatar disabled, Google Captcha disabled, and external CDNs blocked. Zero telemetry phone-home.
* 📦 **Zero-Config Push-to-Create**: Just configure your Git remote and run `git push -u origin main`. Forgejo automatically provisions the repository without opening a browser.
* 🗄 **Embedded SQLite with WAL**: High performance and concurrent read/write transactions without running an external database daemon or exposing database ports.
* 🔑 **Hardened Authentication**: Public registration is disabled, sign-in is required to view any page, and the web installer wizard is permanently locked against takeover.
* ⚡ **Turnkey Lifecycle CLI**: Single standalone script (`forgejo-localhost.sh`) provides automated installation, start/stop/status, security auditing, backups, restores, user creation, and repository creation.
* 🐳 **Dual Deployment**: Native standalone binary (preferred, minimal overhead) or rootless Docker Compose mode.

---

## Quick Start (One Command)

To install, harden, and launch your private localhost GitHub in under 30 seconds:

```bash
./forgejo-localhost.sh install
```

The script will:
1. Detect your system CPU architecture (`amd64`, `arm64`, etc.).
2. Download the official Forgejo binary and verify cryptographic integrity.
3. Generate cryptographically strong random secrets (`SECRET_KEY`, `INTERNAL_TOKEN`, `JWT_SECRET`).
4. Generate a hardened, private `app.ini` configuration.
5. Bootstrap the SQLite WAL database and create the primary administrator account.
6. Start the daemon process (or configure a systemd user service with `--systemd`).
7. Run an automated 12-point security audit to confirm zero external exposure.
8. Output your credentials to terminal and save them securely to `~/.local/share/dev-setups/forgejo/credentials.txt` (`chmod 600`).

> [!NOTE]
> **Data Location & User-Space Decoupling**:
> * **Canonical Installation Path**: Runtime binaries, Git repositories, and SQLite databases are stored in `~/.local/share/dev-setups/forgejo/` to keep the Git repository clean.
> * **Custom Target with `--dir`**: If you want the data folder stored in a separate directory (e.g. on a USB drive or encrypted partition), simply pass `--dir <path>`.
> * **No Root / Sudo Required**: Forgejo runs 100% in user space without requiring system superuser (`root`/`sudo`) permissions.

---

## Web Dashboard & Access

Once started:
* **Web UI**: [http://127.0.0.1:3000/](http://127.0.0.1:3000/)
* **Built-in SSH Server**: `ssh://git@127.0.0.1:2222/`
* **Credentials**: Stored in `~/.local/share/dev-setups/forgejo/credentials.txt` (or run `./forgejo-localhost.sh credentials`)

> [!TIP]
> **Password Manager Best Practice & Deleting `credentials.txt`**:
> * **Forgejo does NOT use `credentials.txt` at runtime**: Forgejo validates logins using salted cryptographic hashes (Argon2 / bcrypt) stored in its SQLite database (`data/forgejo.db`). It never reads `credentials.txt` after initialization.
> * **Save in a Password Manager**: We strongly recommend saving your admin username and password into a password manager (e.g., **KeePassXC**, Bitwarden) or memorizing them.
> * **Safe to Delete**: Once saved in your password manager, you can safely delete the file:
>   ```bash
>   rm ~/.local/share/dev-setups/forgejo/credentials.txt
>   ```
> * The management script recognizes existing databases and will **never** overwrite or re-initialize your account if `credentials.txt` is removed.

---

## Command Reference

The `forgejo-localhost.sh` utility is an all-in-one management tool:

```bash
# Start, stop, and restart (On-Demand usage)
./forgejo-localhost.sh start
./forgejo-localhost.sh stop
./forgejo-localhost.sh restart

# Check running status, PID, port bindings, and API health
./forgejo-localhost.sh status

# Toggle between Auto-Start on boot and On-Demand mode
./forgejo-localhost.sh autostart off       # Switch to On-Demand (will NOT start on boot)
./forgejo-localhost.sh autostart on        # Switch to Auto-Start on login/boot
./forgejo-localhost.sh autostart status    # View current autostart mode

# Run automated security and network isolation audit
./forgejo-localhost.sh audit

# Tail live application logs
./forgejo-localhost.sh logs

# Create an additional user account
./forgejo-localhost.sh create-user --username alice --email alice@localhost

# Create a private repository directly from the command line
./forgejo-localhost.sh create-repo --name my-project --owner forgejo-admin

# Create a full compressed backup (database, git repos, configs)
./forgejo-localhost.sh backup

# Restore from a backup archive
./forgejo-localhost.sh restore --file /path/to/backup.tar.gz

# Clean uninstallation (removes service and deletes local files)
./forgejo-localhost.sh uninstall
```

### Installation Options & Customization

```bash
# Custom HTTP and SSH ports:
./forgejo-localhost.sh install --port 8080 --ssh-port 2200

# Install with systemd user unit (auto-starts on user login):
./forgejo-localhost.sh install --systemd

# Custom data directory:
./forgejo-localhost.sh install --dir ./custom-data

# Custom admin credentials:
./forgejo-localhost.sh install --admin-user myadmin --admin-pass "SuperSecret123!"

# Docker Compose mode:
./forgejo-localhost.sh install --mode docker
```

---

## Working with Local Repositories

### Method 1: Push-to-Create (Fastest)

Forgejo is configured with `ENABLE_PUSH_CREATE_USER = true`. You don't even need to open the browser to create a repository!

```bash
cd /path/to/my-local-code
git init -b main
git add .
git commit -m "Initial commit"

# Set remote (HTTP)
git remote add origin http://127.0.0.1:3000/forgejo-admin/my-local-code.git

# Push — Forgejo will automatically create the private repository!
git push -u origin main
```

### Method 2: Local SSH (Recommended)

1. Add your public SSH key (`~/.ssh/id_ed25519.pub`) into Forgejo:
   * Open [http://127.0.0.1:3000/user/settings/keys](http://127.0.0.1:3000/user/settings/keys)
   * Click **Add Key** and paste your public key.
2. Configure `~/.ssh/config` for clean URLs:
   ```ssh-config
   Host localhost-forge
       HostName 127.0.0.1
       Port 2222
       User git
       IdentityFile ~/.ssh/id_ed25519
   ```
3. Clone or push using SSH:
   ```bash
   git clone ssh://git@127.0.0.1:2222/forgejo-admin/my-project.git
   # Or with the SSH host alias:
   git clone localhost-forge:forgejo-admin/my-project.git
   ```

---

## The 7 Pillars of Localhost Hardening

| Security Layer | Implementation in this Setup | Benefit |
| :--- | :--- | :--- |
| **1. Loopback Binding** | `HTTP_ADDR = 127.0.0.1`<br>`SSH_LISTEN_HOST = 127.0.0.1` | No network interfaces besides `lo` accept packets. LAN neighbors cannot connect. |
| **2. Zero Telemetry** | `OFFLINE_MODE = true`<br>`DISABLE_GRAVATAR = true`<br>`ENABLE_FEDERATED_AVATAR = false` | Prevents IP leakage, CDN asset tracking, and avatar lookups. 100% self-contained. |
| **3. Access Lockdown** | `DISABLE_REGISTRATION = true`<br>`REQUIRE_SIGNIN_VIEW = true` | Zero public registration. Unauthenticated requests receive 403/login redirect. |
| **4. Installer Guard** | `INSTALL_LOCK = true` | Prevents web wizard hijacking or re-configuration. |
| **5. Crypto Entropy** | Secrets generated via `openssl rand -hex 32` | Prevents session forgery and cookie tampering. |
| **6. Least Privilege** | `umask 077`<br>`chmod 600` on configs, `chmod 700` on data | Prevents other local system users from reading keys or database files. |
| **7. Embedded Storage** | SQLite3 with Write-Ahead Logging (`WAL`) | Zero exposed database ports, zero DB service dependencies. |

---

## Verification & Auditing

You can verify the security posture of your local forge at any time by running:

```bash
./forgejo-localhost.sh audit
```

Or manually via standard Linux utilities:

```bash
# Verify sockets are listening ONLY on 127.0.0.1 (not 0.0.0.0 or :::)
ss -tulpn | grep -E ':(3000|2222)'

# Verify file permissions
ls -ld ./forgejo-data/custom/conf/app.ini
# Output must show -rw------- (600)
```

---

## USB / Portable Drive Installation

Yes, you can carry and run your entire private GitHub instance directly from a **USB flash drive or portable SSD**:

* **Self-Contained Storage**: All state—including SQLite databases (`forgejo.db`), bare Git repositories, user accounts, and configuration—is kept entirely inside `./forgejo-data`.
* **Zero Host Installation**: You do not need to install services onto the host system. Simply copy the project folder to your USB drive and run `./forgejo-localhost.sh start`.
* **Important Safety Rule (Clean Eject)**: Always run `./forgejo-localhost.sh stop` before unmounting or pulling out the USB drive. SQLite uses Write-Ahead Logging (`WAL`), and stopping the service ensures all memory buffers and commits are flushed to the drive cleanly.
* **Filesystem Selection**:
  * **Linux Only**: Format the USB drive as `ext4` to preserve POSIX file permissions (`chmod 600`, `chmod 700`, executable bits).
  * **Cross-Platform (Linux + Windows)**: Format as `exFAT` or `NTFS`. On Linux, ensure the drive is mounted with execution permissions (`mount -o exec ...`).

---

## Cross-OS Portability (Linux, Windows, macOS)

The **data, databases, and Git repositories are 100% portable across all operating systems**, while the executable engine is OS-specific:

* **Portable Data Layer**: The database (`forgejo.db`), `app.ini`, and Git bare repositories are binary-compatible across Linux, Windows, and macOS. You can move the USB drive between any computer.
* **Running on Windows**:
  * **Option A (WSL2 - Recommended)**: Plug the USB drive into Windows, open your WSL terminal, navigate to the mount point (`/mnt/d/...`), and run `./forgejo-localhost.sh start`.
  * **Option B (Native Windows Binary)**: Download the official `forgejo-*-windows-amd64.exe` onto the USB drive. You can launch it directly pointing to the existing data directory:
    ```cmd
    forgejo.exe web --config forgejo-data\custom\conf\app.ini --work-path forgejo-data
    ```
* **Running on macOS**:
  * Run the native macOS arm64/amd64 Forgejo binary or run via `docker compose up -d`.

---

## CI/CD Pipelines (GitHub Actions Compatibility)

Forgejo includes **built-in support for GitHub Actions workflows** (called **Forgejo Actions**):

* **Identical Syntax**: Supports standard `.github/workflows/*.yaml` (or `.forgejo/workflows/*.yaml`) workflow definitions (`on: [push, pull_request]`, `jobs:`, `steps:`, matrices, container actions).
* **Local Execution Engine**: Forgejo uses **`act_runner`** (a lightweight runner daemon based on `nektos/act`) to execute workflow jobs in local Docker containers or directly on the host.
* **Default Status (Disabled for Privacy & Lean Footprint)**:
  * In this hardened localhost setup, `[actions] ENABLED = false` is configured by default to maintain zero telemetry and zero background runner overhead.
* **Enabling Pipelines**:
  1. In `forgejo-data/custom/conf/app.ini`, change `[actions]` to `ENABLED = true`.
  2. Download the single-binary `forgejo-runner` / `act_runner`.
  3. Register the runner against `http://127.0.0.1:3000` using a registration token generated in **Site Administration -> Actions -> Runners**.
  4. Commits pushed to your localhost repositories will trigger local pipeline runs with full logs and status checks in the Web UI.

---

## Uninstallation

To cleanly and completely remove Forgejo:

```bash
cd Setup-Local-GitHub
./forgejo-localhost.sh uninstall
```

### What the Uninstaller Does:
1. Stops the running Forgejo process or Docker containers.
2. Disables and removes systemd user service units (`~/.config/systemd/user/forgejo.service`).
3. Prompts before deleting local repository data and configuration files (`./forgejo-data`).
4. Ensures no orphaned background processes or network ports remain active.

---

## CLI Command Reference

| Command / Option | Description |
|---|---|
| `./forgejo-localhost.sh install` | Automated installation, SQLite WAL configuration, admin creation & startup |
| `./forgejo-localhost.sh install --port <port>` | Run web interface on a custom port (default: `3000`, bound to `127.0.0.1`) |
| `./forgejo-localhost.sh install --ssh-port <port>` | Run built-in SSH Git server on custom port (default: `2222`, bound to `127.0.0.1`) |
| `./forgejo-localhost.sh install --systemd` | Configure and enable persistent systemd user service |
| `./forgejo-localhost.sh install --mode docker` | Run via hardened Docker Compose instead of standalone binary |
| `./forgejo-localhost.sh status` | Check service state, port bindings, and memory usage |
| `./forgejo-localhost.sh audit` | Run cryptographic permissions and network isolation security audit |
| `./forgejo-localhost.sh start` | Start the Forgejo service |
| `./forgejo-localhost.sh stop` | Gracefully flush SQLite WAL buffers and stop service |
| `./forgejo-localhost.sh restart` | Restart the local Forgejo instance |
| `./forgejo-localhost.sh logs` | View live application logs |
| `./forgejo-localhost.sh create-repo --name <name> --owner <owner>` | Create a repository directly from terminal CLI |
| `./forgejo-localhost.sh backup` | Atomic compressed backup of database, repos, and app.ini |
| `./forgejo-localhost.sh restore --file <path>` | Restore entire instance from a backup tarball |
| `./forgejo-localhost.sh uninstall` | Completely and safely remove service, unit files, and data |
| `./forgejo-localhost.sh --help` | Display CLI help with all available flags |

---

## Detailed Documentation

* 📖 **[Comprehensive Step-by-Step Guide](FORGEJO_LOCALHOST_SETUP.md)**: In-depth setup, architecture, GitHub repository migration, SSH key configuration, and troubleshooting.
* 🔒 **[Security Audit & Threat Model](SECURITY_AUDIT.md)**: Complete threat model, attack vector analysis, and security verification checklist.
* ⚙ **[Annotated Configuration Template](config/app.ini.template)**: Fully commented reference `app.ini`.
* 🐳 **[Docker Compose Configuration](docker-compose.yml)**: Hardened container setup.
