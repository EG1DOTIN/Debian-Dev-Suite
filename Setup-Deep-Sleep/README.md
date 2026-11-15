# Setup-Deep-Sleep: Linux Deep Sleep & Battery Optimization

A turnkey, privacy-focused, and zero-telemetry power optimization module for Debian, MX Linux, antiX, and Ubuntu systems.

---

## The Problem: Overnight Battery Drain in Linux

Modern laptops often default to **S0ix** (also marketed by Microsoft and Intel as *Modern Standby* or *s2idle*). In this state:
- The CPU and SoC never enter deep C-states.
- The system remains in a shallow low-power sleep where PCIe rails and controllers remain partially energized.
- A laptop closed overnight can lose **10% to 25% battery** by morning, running warm inside a laptop bag.

By switching the kernel to true **S3 Suspend-to-RAM (`deep`)**, the operating system powers down the CPU cores, bus controllers, and peripherals, refreshing only the volatile system RAM. Battery drain drops to **~1% to 2% over an 8-hour sleep**.

---

## Core Capabilities & Technical Architecture

### 1. Kernel S3 Deep Sleep (`mem_sleep_default=deep`)
- **Inspection:** Reads `/sys/power/mem_sleep` to determine ACPI hardware support (`[s2idle] deep` vs `s2idle [deep]`).
- **Persistence:** Injects `mem_sleep_default=deep` into `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` and rebuilds the bootloader configuration (`update-grub` / `grub-mkconfig`).

### 2. TLP Power Management & Advanced Hardware Tuning
- **Automated Deployment:** Installs and configures `tlp` and `tlp-rdw` from official distribution repositories.
- **Dynamic Optimization:** Manages CPU governor frequencies, Intel/AMD energy performance policies, PCIe Active State Power Management (ASPM), SATA link power management, and USB autosuspend.
- **100% Offline & 0 Telemetry:** TLP is fully open-source (GPL-3.0), contains zero analytics, makes zero external network requests, and runs entirely locally.

### 3. Dual Init System Architecture (systemd & SysVinit / MX Linux)
- **systemd Support:** Deploys a clean drop-in configuration to `/etc/systemd/sleep.conf.d/10-deep-sleep.conf` (avoiding destructive edits to default package configuration files).
- **SysVinit / MX Linux / antiX Support:** Detects non-systemd environments automatically, activating `/etc/init.d/tlp` services and leveraging kernel ACPI deep sleep transitions.

### 4. Suspend-then-Hibernate with Memory/Swap Safety Audit
- Configures `HibernateDelaySec=120min`: The machine sleeps lightly in RAM for 2 hours, then automatically transfers RAM to swap and powers off completely for zero battery loss during extended travel.
- **Safety Audit:** Automatically validates active swap capacity against physical RAM before enabling hibernation transitions.

---

## Memory & Swap Compatibility Matrix for Hibernation

Hibernation (*Suspend-to-Disk*) requires writing active RAM into swap space.

| Total RAM | Recommended Swap for Hibernate | Safe for S3 Deep Sleep? | Safe for Hibernation? |
|---|---|---|---|
| **4 GB** | $\ge 4\text{ GB}$ (preferably 6 GB) | **Yes** (Instant) | **Yes** if Swap $\ge$ 4 GB |
| **8 GB** | $\ge 8\text{ GB}$ (preferably 10 GB) | **Yes** (Instant) | **Yes** if Swap $\ge$ 8 GB |
| **16 GB** | $\ge 16\text{ GB}$ (preferably 20 GB) | **Yes** (Instant) | **Yes** if Swap $\ge$ 16 GB |

> [!NOTE]
> Even if your swap partition is smaller than total RAM, **S3 Suspend-to-RAM (`deep`) functions completely safely**. The script will simply alert you that full disk hibernation requires an expanded swap file.

---

## Quick Start Commands

### 1. Run Non-Root Diagnostic Check
Check your hardware's current sleep capabilities, GRUB status, and battery health without needing sudo:

```bash
cd Setup-Deep-Sleep
./setup-deep-sleep.sh --status
```

### 2. Install & Apply Optimizations
Enforces kernel deep sleep, starts TLP, and sets up sleep drop-ins:

```bash
sudo ./setup-deep-sleep.sh --install
```

To run unattended or in automation without an interactive reboot prompt:
```bash
sudo ./setup-deep-sleep.sh --install --no-reboot
```

### 3. Cleanly Uninstall / Revert
Removes the `mem_sleep_default=deep` kernel parameter and drops the systemd sleep configuration:

```bash
sudo ./setup-deep-sleep.sh --uninstall
```

---

## Verification & Diagnostic Commands

Run these standard Linux commands at any time to verify power management:

```bash
# Verify active kernel sleep state (should display 's2idle [deep]')
cat /sys/power/mem_sleep

# Check TLP service and system power profiles
tlp-stat -s

# Check battery health and discharge rate in watts
tlp-stat -b

# Verify GRUB kernel command line in the running kernel
cat /proc/cmdline | grep mem_sleep
```

---

## Troubleshooting

### `cat /sys/power/mem_sleep` only shows `[s2idle]` (No `deep`)
Certain newer laptop UEFI/BIOS firmware defaults to "Modern Standby" or "Windows 10/11 Network Standby".
- Enter your laptop's **BIOS/UEFI setup** (F2, F10, or Del during boot).
- Look for **Sleep Mode**, **Power Management**, or **ACPI OS Selection**.
- Change the setting from **"Modern Standby / S0ix"** to **"Linux / S3 / Legacy Sleep"**.
- Save and reboot. The `deep` state will now appear in `/sys/power/mem_sleep`.
