# Universal Internet Time Synchronization for Debian-based Systems

A lightweight, robust, and 100% open-source time synchronization solution for **Debian, antiX, Ubuntu, Linux Mint, MX Linux, Devuan, Raspberry Pi OS**, and any other Debian-based distribution.

Designed specifically to eliminate the notorious **"Year 2008 Clock Reset"** problem caused by dead/dying motherboard RTC/CMOS batteries, while remaining completely distribution-agnostic, prioritizing built-in system tools, and supporting **offline manual date/time recovery**.

---

## Table of Contents

- [What is this and Why is it needed?](#what-is-this-and-why-is-it-needed)
  - [The Hardware Root Cause (Year 2008 Reset)](#the-hardware-root-cause-year-2008-reset)
  - [The "Catch-22" Breakdown: Why Year 2008 Breaks Linux](#the-catch-22-breakdown-why-year-2008-breaks-linux)
  - [Who Should Use This?](#who-should-use-this)
- [How It Works (Multi-Stage Synchronization Hierarchy)](#how-it-works-multi-stage-synchronization-hierarchy)
- [Core Principles: Inbuilt, Open-Source & Lightweight First](#core-principles-inbuilt-open-source--lightweight-first)
- [Prerequisites](#prerequisites)
- [Quick Start: Global Commands Installation](#quick-start-global-commands-installation)
- [Usage Guide](#usage-guide)
  - [1. Automatic Sync Over Internet](#1-automatic-sync-over-internet)
  - [2. Manual Date & Time Setting (Offline Mode)](#2-manual-date--time-setting-offline-mode)
  - [3. Check Status and Diagnostics](#3-check-status-and-diagnostics)
  - [4. Help & Command Reference](#4-help--command-reference)
- [Setting Up Automatic Boot Synchronization](#setting-up-automatic-boot-synchronization)
  - [Method A: SysV Init Service (antiX / Devuan)](#method-a-sysv-init-service-antix--devuan)
  - [Method B: Desktop Session Startup (antiX Linux)](#method-b-desktop-session-startup-antix-linux)
  - [Method C: Network Connect Hook (`if-up.d`)](#method-c-network-connect-hook-if-upd)
  - [Method D: Cron `@reboot`](#method-d-cron-reboot)
- [Preventing Future Resets with `fake-hwclock`](#preventing-future-resets-with-fake-hwclock)
- [Troubleshooting & Logs](#troubleshooting--logs)

---

## What is this and Why is it needed?

### The Hardware Root Cause (Year 2008 Reset)
Computers have an onboard Real-Time Clock (RTC) chip powered by a small coin-cell battery (usually a CR2032 or soldered laptop battery). When this battery dies, is disconnected, or loses charge while the system is powered down:
- The motherboard's hardware clock loses its memory and resets to its factory BIOS/chipset manufacture date (frequently **year 2008** on Core 2 / Pentium / older machines).
- Every time Linux boots, the kernel initializes system time from the hardware clock, starting the system at year 2008.

### The "Catch-22" Breakdown: Why Year 2008 Breaks Linux
When modern Linux boots into year 2008, multiple critical internet systems break simultaneously:

1. **SSL/TLS Certificates Fail Validation:**
   Modern HTTPS certificates are valid for dates in 2024–2026. A system set to 2008 interprets these certificates as *"not yet valid (from the future)"* and immediately rejects secure connections.
2. **APT Package Manager Completely Breaks:**
   Running `sudo apt update` or `sudo apt install` fails with errors such as:
   ```text
   E: Release file for http://deb.debian.org/... is not valid yet (invalid for another 6000 days)
   Certificate verification failed: The certificate is not yet valid
   ```
   **This creates a vicious Catch-22:** You cannot install new time-sync software (like `chrony`) because APT refuses to work until your clock is already fixed!
3. **DNSSEC Resolution Fails:**
   Resolvers that validate DNSSEC drop DNS lookups because cryptographic signatures are outside the valid time window.
4. **NTP Daemons Fail or Freeze:**
   Standard NTP clients often reject or ignore time adjustments greater than 1000 seconds (16 minutes) to prevent malicious time tampering, leaving the clock frozen in 2008.

### Who Should Use This?
- **Any Debian-based machine** (laptop, desktop, or single-board computer) where the hardware clock resets upon reboot or power loss.
- **Dual-boot systems** where Windows and Linux conflict over UTC vs Local RTC settings.
- **Offline / Portable rigs** that need automated time recovery or simple manual time setting without terminal struggle.

---

## How It Works (Multi-Stage Synchronization Hierarchy)

`sync-time.sh` solves the problem systematically through a multi-stage pipeline:

```
[System Boot (Clock = 2008)]
               │
               ▼
    [Smart Network Detection]
    (Retries non-destructively; handles delayed Wi-Fi / DHCP)
               │
       ┌───────┴───────┐
       ▼               ▼
[Network Online]   [Offline / Network Fails]
       │               │
       ▼               ▼
[Stage 1: HTTP Date Bootstrap]  --> [Interactive / CLI Manual Override]
(Queries plain HTTP 'Date:' header)  (Prompt: Enter date & time manually)
       │                                     │
       ▼                                     │
[Stage 2: Precision NTP Synchronization]     │
(systemd-timesyncd / BusyBox ntpd / Chrony)  │
       │                                     │
       └───────────────┬─────────────────────┘
                       │
                       ▼
    [Stage 3: Hardware Clock & fake-hwclock Persistence]
    (Writes time to RTC via hwclock and /etc/fake-hwclock.data)
                       │
                       ▼
    [Stage 4: Verification & Logging]
    (Confirms year >= 2024; logs to /var/log/time-sync.log)
```

1. **Smart Network Wait:** Checks DNS, ping, and HTTP connectivity with non-blocking retries.
2. **Offline Fallback:** If internet is disconnected or sync fails, interactively prompts the user to set the date and time manually.
3. **HTTP Date Fast Bootstrap:** Queries standard plain HTTP response headers from reliable servers (`deb.debian.org`, `connectivitycheck.gstatic.com`, `cloudflare.com`, `google.com`) to bypass SSL certificate lockouts.
4. **Inbuilt Tool Prioritization:** Precision sync using existing native tools (`systemd-timesyncd`, `busybox ntpd`, `chrony`, `ntpdate`).
5. **Hardware & Snapshot Persistence:** Saves the time using `hwclock --systohc --utc` and `fake-hwclock save` so subsequent boots start at the last saved time rather than 2008.

---

## Core Principles: Inbuilt, Open-Source & Lightweight First

- **100% Free and Open Source (FOSS):** Zero proprietary blobs, closed-source dependencies, or third-party telemetry.
- **Inbuilt Tools First:** Prioritizes existing system tools before recommending extra packages.
- **Offline Resilient:** Allows direct manual time configuration with instant persistence to hardware and fake-hwclock.
- **Minimal Resource Footprint:** Pure POSIX `/bin/sh` shell script. Consumes negligible memory.

---

## Prerequisites

The script requires only basic utilities present on virtually every Debian-based installation:
- `curl` or `wget` (for HTTP date bootstrap)
- `date` and standard core utilities
- Root privileges (`sudo`) to set system and hardware clocks

---

## Quick Start: Global Commands Installation

To install `sync-time` and `time-sync` as global commands in `/usr/local/bin`:

```bash
cd Setup-Sync-Time
sudo ./sync-time.sh --install
```

Once installed, you can simply type `sudo sync-time` or `sudo time-sync` from **any directory in any terminal**!

To remove the commands at any time:
```bash
sudo sync-time --uninstall
```

---

## Usage Guide

### 1. Automatic Sync Over Internet

To automatically detect network, bootstrap HTTP date, and synchronize via NTP:

```bash
sudo sync-time
```
*(Or `sudo time-sync`)*

### 2. Manual Date & Time Setting (Offline Mode)

If your computer is offline, has no Wi-Fi, or network sync failed, you can set the time manually. This updates the system clock, RTC hardware clock, and `fake-hwclock` simultaneously.

#### Option A: Interactive Wizard
```bash
sudo sync-time --manual
```
You will be prompted to enter the date and time (with sensible defaults pre-filled):
```text
Enter Date [YYYY-MM-DD] (default: 2026-09-20): 2026-09-20
Enter Time [HH:MM:SS] (default: 16:30:00): 16:30:00
```

#### Option B: Direct Command Line Flag
```bash
# Full Date and Time:
sudo sync-time --set "2026-09-20 16:30:00"

# Date only:
sudo sync-time --set "2026-09-20"
```

### 3. Check Status and Diagnostics
To view your current system time, hardware clock (RTC), installed sync tools, and recent log entries:
```bash
sudo sync-time --status
```

### 4. Help & Command Reference
```bash
sync-time --help
```

| Option | Description |
|---|---|
| `(no args)` | Synchronize system time immediately over internet. |
| `--sync` | Explicit synchronization trigger. |
| `--manual`, `-m` | Interactively set date and time manually. |
| `--set "DATE"` | Directly set date/time string and persist to hardware clock. |
| `--install`, `-i` | Create system-wide symlinks `/usr/local/bin/sync-time` and `time-sync`. |
| `--uninstall`, `-u` | Remove `/usr/local/bin/sync-time`, `time-sync`, and init services. |
| `--status`, `-s` | Show clock diagnostics, tool status, and recent log entries. |
| `--help`, `-h` | Display usage and examples. |

---

## Setting Up Automatic Boot Synchronization

### Method A: Automatic Prompt during Installation
When you run `sudo ./sync-time.sh --install`, the installer will automatically offer to register `/etc/init.d/time-sync` for boot startup.

### Method B: Manual SysV Init Service (antiX / Devuan)
```bash
sudo cp sync-time.sh /etc/init.d/time-sync
sudo chmod +x /etc/init.d/time-sync
sudo update-rc.d time-sync defaults
```

### Method C: Desktop Session Startup (antiX Linux)
On antiX Linux, you can run the script in the background when logging into the desktop:
1. Open `~/.desktop-session/startup` in a text editor:
   ```bash
   nano ~/.desktop-session/startup
   ```
2. Add the following line:
   ```bash
   sudo sync-time &
   ```

### Method D: Network Connect Hook (`if-up.d`)
To ensure time synchronizes the moment Wi-Fi or Ethernet connects:
1. Create `/etc/network/if-up.d/time-sync`:
   ```bash
   sudo tee /etc/network/if-up.d/time-sync <<'EOF'
   #!/bin/sh
   if [ "$IFACE" != "lo" ]; then
       /usr/local/bin/sync-time >/dev/null 2>&1 &
   fi
   EOF
   sudo chmod +x /etc/network/if-up.d/time-sync
   ```

---

## Preventing Future Resets with `fake-hwclock`

On computers where the CMOS coin-cell battery is dead, power loss causes the hardware clock to reset to 2008 before the OS boots.

The Debian utility **`fake-hwclock`** saves the current time at shutdown and restores it at boot before network services start, preventing the clock from falling back to 2008.

```bash
# Once time is synced and APT is working:
sudo apt update
sudo apt install -y fake-hwclock
```

`sync-time.sh` automatically detects and updates `fake-hwclock` on every manual or automatic sync.

---

## Troubleshooting & Logs

### View Synchronization Log
The script logs all operations with timestamps to `/var/log/time-sync.log`:
```bash
cat /var/log/time-sync.log
```

### Common Scenarios

| Symptom | Cause | Solution |
|---|---|---|
| `command not found: sync-time` | Global symlinks not created | Run `sudo ./sync-time.sh --install` in the `Setup-Sync-Time` folder. |
| `Network unreachable & clock in 2008` | No internet connection | Run `sudo sync-time --manual` to set the date manually so APT/Git works. |
| `APT update fails: Release file not valid yet` | System clock is still in year 2008 | Run `sudo sync-time` or `sudo sync-time --manual`. |
| `hwclock write failed` | Hardware RTC is missing or locked by BIOS | Safe to ignore. System clock is still synced in RAM, and `fake-hwclock` handles persistence. |
| Time is correct in UTC but wrong local hour | System timezone is not configured | Run `sudo dpkg-reconfigure tzdata` to select your local timezone. |
