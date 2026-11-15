# Secure VirtualBox Installation & Hardening Automation

This repository provides an automated, security-hardened installation script for **Oracle VirtualBox with GUI**, implementing cryptographic package verification, attack surface minimization, and the principle of least privilege.

---

## Key Security Pillars

### 1. Cryptographic Package Verification (SHA256)
- **Official Source**: Downloads directly from Oracle's official HTTPS distribution server (`https://download.virtualbox.org/virtualbox/`).
- **Integrity Validation**: Automatically fetches official `SHA256SUMS` and computes the local cryptographic hash (`sha256sum`) of the package before execution.
- **Fail-Safe Abort**: If a checksum mismatch is detected (indicative of corruption, mirror spoofing, or a Man-in-the-Middle attack), the script alerts the administrator, deletes the unverified file immediately, and aborts before running any code.

### 2. Attack Surface Minimization
- **Exclusion of Oracle Extension Pack by Default**:
  - The proprietary Extension Pack introduces closed-source binary drivers running with host-level privileges.
  - Specifically omits the **VRDP (VirtualBox Remote Desktop Protocol)** server—historically a frequent source of remote code execution (RCE) and authentication bypass vulnerabilities—as well as proprietary USB 2.0/3.0 host controllers and webcam passthrough.
  - Can optionally be enabled with `--with-extpack` only when strictly required.
- **Service Disablement & Masking**:
  - Automatically stops, disables, and masks unnecessary host network services:
    - `vboxweb-service` (`vboxwebsrv`): Disables the SOAP management daemon listening on TCP port `18083`.
    - `vboxballoonctrl-service`: Disables memory ballooning automation.
    - `vboxautostart-service`: Disables VM autostart at system boot.
  - Only `vboxdrv.service` remains enabled for the essential hypervisor driver.
- **Minimal Dependencies**:
  - Uses `--no-install-recommends` and `--no-install-suggests` to avoid pulling unnecessary packages and daemons.

### 3. Principle of Least Privilege (Non-Root Execution)
- **Designated Regular User**:
  - VirtualBox GUI and guest VMs should **never** be executed as `root`. Running VMs as root allows hypervisor breakout (VM escape) vulnerabilities to grant immediate full-host takeover.
  - The script identifies or accepts the designated non-root user (e.g., `$SUDO_USER`) and adds them to the `vboxusers` group.
- **Device Node Hardening (`/dev/vboxdrv*`)**:
  - Configures `/etc/udev/rules.d/60-vboxdrv.rules` to enforce `OWNER="root"`, `GROUP="vboxusers"`, `MODE="0660"`.
  - World/others have **no access** (`0000`).
- **SUID Binary Hardening**:
  - Hardens VirtualBox helper binaries in `/usr/lib/virtualbox/` (`VBoxHeadless`, `VBoxNetDHCP`, `VBoxNetNAT`, `VBoxNetAdpCtl`, `VirtualBoxVM`).
  - Sets permissions to `4750` (`rwsr-x---`) owned by `root:vboxusers`, preventing non-`vboxusers` system accounts from invoking them.
- **User Storage & Configuration Isolation**:
  - Restricts permissions on `~/.config/VirtualBox` and `~/VirtualBox VMs` to `0700` (`rwx------`).
  - Protects VM disk images, RAM dumps, and configuration metadata from inspection by other unprivileged local users.
- **Root Execution Guard**:
  - Installs `/etc/profile.d/virtualbox-security.sh` to warn against launching the GUI with `UID 0`.

### 4. Full GUI Support
- Automatically verifies and configures desktop integration (`/usr/share/applications/virtualbox.desktop`).
- Validates Qt5/Qt6 core, GUI, OpenGL, and X11/Wayland runtime dependencies.

---

## Usage

### Quick Start
Make the script executable and run with `sudo`:

```bash
sudo ./setup_virtualbox_secure.sh
```

### Command Line Options

| Option | Description | Default |
|---|---|---|
| `-u, --user <USERNAME>` | Target non-root user to configure | `$SUDO_USER` or current user |
| `-v, --version <VERSION>` | VirtualBox version (e.g., `7.1.6`, `7.0.20`, `latest`) | `7.1.6` |
| `-m, --method <deb\|run>` | Installation package type | `auto` |
| `-p, --package-file <PATH>` | Use a local pre-downloaded package file | *(download from web)* |
| `-c, --checksum-file <PATH>` | Use a local `SHA256SUMS` file | *(download from web)* |
| `--with-extpack` | Include the Oracle Extension Pack (with SHA256 verification) | `false` |
| `--harden-only` | Apply security & permission controls to an existing installation | `false` |
| `--verify-only` | Download & verify SHA256 only without installing | `false` |
| `--uninstall` | Completely remove VirtualBox, services, kernel drivers, udev rules, hardening scripts, and desktop entries | `false` |
| `--purge` | Used with `--uninstall` to also permanently delete user VM disks (`~/VirtualBox VMs`) and configurations (`~/.config/VirtualBox`) | `false` |
| `--dry-run` | Simulate actions without applying changes to the system | `false` |
| `-h, --help` | Show help menu | - |

---

## Examples

### 1. Standard Secure Installation
Installs VirtualBox 7.1.6 with full GUI, minimal attack surface, and configures for user `$USER`:
```bash
sudo ./setup_virtualbox_secure.sh --user $USER --version 7.1.6
```

### 2. Security Hardening on an Existing Installation
If VirtualBox is already installed on your system and you want to apply least-privilege permissions, mask `vboxweb-service`, and restrict device access:
```bash
sudo ./setup_virtualbox_secure.sh --harden-only --user $USER
```

### 3. Verification of Local Package (Air-Gapped / Pre-downloaded)
Verify a pre-downloaded installer against the official checksum list before running:
```bash
sudo ./setup_virtualbox_secure.sh --package-file ./VirtualBox-7.1.6-167084-Linux_amd64.run --checksum-file ./SHA256SUMS
```

### 4. Complete Uninstallation
Completely remove all VirtualBox components, stopped services, kernel modules, hardening configs, and udev rules (while preserving your VM disks and configs):
```bash
sudo ./setup_virtualbox_secure.sh --uninstall
```

To also purge all VM disks and user configurations:
```bash
sudo ./setup_virtualbox_secure.sh --uninstall --purge --user $USER
```

### 5. Dry-Run Simulation
Simulate the entire process without making changes:
```bash
sudo ./setup_virtualbox_secure.sh --dry-run --user $USER
```

---

## Post-Installation Activation

After running the script, activate your new group membership:
```bash
# Option A: In the current terminal session:
newgrp vboxusers

# Option B: Log out of your desktop session and log back in.
```

Launch the VirtualBox GUI as your regular user:
```bash
VirtualBox &
```
