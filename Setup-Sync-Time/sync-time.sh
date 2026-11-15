#!/bin/sh

###############################################################################
# Universal Internet Time Synchronization for Debian-based Linux Systems
# (Debian, antiX, Ubuntu, Linux Mint, MX Linux, Devuan, Raspberry Pi OS, etc.)
#
# Solves clock rollback issues (e.g. system resetting to year 2008 on boot
# due to depleted/dead motherboard RTC/CMOS battery) using a multi-stage,
# 100% open-source, secure, privacy-focused, and lightweight hierarchy:
#
#   1. Smart Network Wait (handles slow boot Wi-Fi/DHCP without freezing boot)
#   2. HTTP Date Fast Bootstrap (bypasses SSL/TLS/DNSSEC 2008 lockout)
#   3. Built-in NTP Precision Sync (systemd-timesyncd, busybox ntpd, chrony, ntpdate)
#   4. Hardware Clock & fake-hwclock Persistence (prevents 2008 rollback on reboot)
#   5. Offline Manual Override (set manual date/time if internet fails or offline)
#   6. Verification (confirms year >= 2024)
#
# USAGE
# -----
#   sudo sync-time                     # Sync time immediately over internet
#   sudo sync-time --manual            # Interactively set date and time manually
#   sudo sync-time --set "YYYY-MM-DD"  # Set manual date/time via CLI
#   sudo sync-time --install           # Install system commands into /usr/local/bin
#   sudo sync-time --uninstall         # Remove commands and services
#   sudo sync-time --status            # Show current time, RTC & recent logs
#   sync-time --help                   # Show usage instructions
###############################################################################

### BEGIN INIT INFO
# Provides:          time-sync
# Required-Start:    $remote_fs $network
# Required-Stop:
# Should-Start:      $network $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Synchronize system time over the Internet
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export PATH

LOGFILE="/var/log/time-sync.log"

# Multi-pool NTP servers (standard open-source / public infrastructure)
NTP_SERVERS="pool.ntp.org time.cloudflare.com time.google.com 0.debian.pool.ntp.org"

# HTTP Date bootstrap endpoints (using plain HTTP to avoid 2008 SSL certificate failures)
HTTP_DATE_URLS="http://deb.debian.org http://connectivitycheck.gstatic.com http://cloudflare.com http://www.google.com"

# Network retry settings (default: up to 30 attempts, 3 seconds apart = 90s max)
MAX_NETWORK_TRIES=30
WAIT_SECONDS=3
MIN_VALID_YEAR=2024

###############################################################################
# Helper Functions
###############################################################################

log_message()
{
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)
    echo "$TIMESTAMP - $1" >> "$LOGFILE" 2>/dev/null || true
}

log_and_echo()
{
    echo "$1"
    log_message "$1"
}

check_root()
{
    if [ "$(id -u 2>/dev/null || true)" != "0" ]; then
        echo "ERROR: This operation must be run as root (use sudo)."
        echo "Example: sudo $0"
        exit 1
    fi
}

get_current_year()
{
    date +%Y 2>/dev/null || echo 0
}

###############################################################################
# Network Detection (Smart & Resilient)
###############################################################################

is_network_online()
{
    # 1. Try DNS resolution of a known domain
    if command -v getent >/dev/null 2>&1; then
        if getent hosts deb.debian.org >/dev/null 2>&1 || getent hosts pool.ntp.org >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 2. Try pinging reliable public IPs (bypasses DNS/DNSSEC issues when clock is in 2008)
    if command -v ping >/dev/null 2>&1; then
        # 1.1.1.1 (Cloudflare) or 8.8.8.8 (Google)
        if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 3. Try lightweight HTTP connection
    if command -v curl >/dev/null 2>&1; then
        if curl -s --head --connect-timeout 2 http://deb.debian.org >/dev/null 2>&1; then
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --spider --timeout=2 http://deb.debian.org >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

wait_for_network()
{
    log_and_echo "Checking for active Internet connection..."

    ATTEMPT=1
    while [ "$ATTEMPT" -le "$MAX_NETWORK_TRIES" ]; do
        if is_network_online; then
            log_and_echo "Network connection is active and reachable."
            return 0
        fi

        if [ "$ATTEMPT" -eq 1 ] || [ $((ATTEMPT % 5)) -eq 0 ]; then
            log_and_echo "Waiting for network (attempt $ATTEMPT of $MAX_NETWORK_TRIES)..."
        fi

        sleep "$WAIT_SECONDS"
        ATTEMPT=$((ATTEMPT + 1))
    done

    log_and_echo "WARNING: Network connection was not established within $((MAX_NETWORK_TRIES * WAIT_SECONDS)) seconds."
    return 1
}

###############################################################################
# Step 1: HTTP Date Bootstrap (Fixes Year 2008 SSL/APT/DNSSEC Trap)
###############################################################################

bootstrap_http_time()
{
    YEAR=$(get_current_year)
    if [ "$YEAR" -ge "$MIN_VALID_YEAR" ]; then
        # Clock is already within reasonable current era
        return 0
    fi

    log_and_echo "Clock is set to year $YEAR (likely dead RTC battery). Performing HTTP date bootstrap..."

    HTTP_DATE=""

    # Try curl first
    if command -v curl >/dev/null 2>&1; then
        for URL in $HTTP_DATE_URLS; do
            # Use plain HTTP and max-time 4s. Plain HTTP does not validate SSL certificates!
            HEADER_DATE=$(curl -sI --connect-timeout 3 --max-time 5 "$URL" 2>/dev/null | grep -i '^date:' | head -n 1 | sed -e 's/^[Dd]ate:[[:space:]]*//' -e 's/\r//g')
            if [ -n "$HEADER_DATE" ]; then
                HTTP_DATE="$HEADER_DATE"
                log_message "Fetched HTTP date from $URL: $HTTP_DATE"
                break
            fi
        done
    fi

    # Fallback to wget
    if [ -z "$HTTP_DATE" ] && command -v wget >/dev/null 2>&1; then
        for URL in $HTTP_DATE_URLS; do
            HEADER_DATE=$(wget -S --spider --timeout=4 "$URL" 2>&1 | grep -i '^[[:space:]]*date:' | head -n 1 | sed -e 's/^[[:space:]]*[Dd]ate:[[:space:]]*//' -e 's/\r//g')
            if [ -n "$HEADER_DATE" ]; then
                HTTP_DATE="$HEADER_DATE"
                log_message "Fetched HTTP date via wget from $URL: $HTTP_DATE"
                break
            fi
        done
    fi

    if [ -n "$HTTP_DATE" ]; then
        # Apply date (UTC)
        if date -u -s "$HTTP_DATE" >/dev/null 2>&1; then
            NEW_YEAR=$(get_current_year)
            log_and_echo "Successfully bootstrapped system clock from $YEAR to $(date '+%Y-%m-%d %H:%M:%S %Z')."
            return 0
        else
            log_message "Failed to apply date with 'date -u -s'."
        fi
    fi

    log_and_echo "Notice: HTTP date bootstrap could not reach servers or parse date header."
    return 1
}

###############################################################################
# Step 2: High-Precision Synchronization (Prioritizes Inbuilt Tools)
###############################################################################

sync_via_systemd()
{
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        log_and_echo "Using built-in systemd-timesyncd..."
        systemctl restart systemd-timesyncd >/dev/null 2>&1 || true
        sleep 2
        if command -v timedatectl >/dev/null 2>&1; then
            timedatectl set-ntp true >/dev/null 2>&1 || true
        fi
        return 0
    fi
    return 1
}

sync_via_chrony()
{
    if command -v chronyc >/dev/null 2>&1; then
        log_and_echo "Using chrony for time synchronization..."

        # Ensure service is running (SysV init or systemd)
        if command -v service >/dev/null 2>&1; then
            service chrony start >/dev/null 2>&1 || true
        elif command -v systemctl >/dev/null 2>&1; then
            systemctl start chrony >/dev/null 2>&1 || true
        fi

        # Send burst requests to quickly poll NTP sources
        chronyc burst 4/4 >> "$LOGFILE" 2>&1 || true
        sleep 2

        # Step time immediately if offset is large
        if chronyc makestep >> "$LOGFILE" 2>&1; then
            log_message "chronyc makestep executed."
            return 0
        fi
    fi
    return 1
}

sync_via_busybox()
{
    if command -v busybox >/dev/null 2>&1 && busybox ntpd --help >/dev/null 2>&1; then
        log_and_echo "Using built-in BusyBox ntpd..."
        for SERVER in $NTP_SERVERS; do
            # -n: run in foreground, -q: quit after setting time, -p: server
            if busybox ntpd -n -q -p "$SERVER" >> "$LOGFILE" 2>&1; then
                log_message "BusyBox ntpd synced with $SERVER"
                return 0
            fi
        done
    fi
    return 1
}

sync_via_ntpdate()
{
    if command -v ntpdate >/dev/null 2>&1; then
        log_and_echo "Using ntpdate..."
        for SERVER in $NTP_SERVERS; do
            # -u uses unprivileged port to bypass firewalls
            # -b forces stepping instead of slewing
            if ntpdate -u -b "$SERVER" >> "$LOGFILE" 2>&1; then
                log_message "ntpdate synced with $SERVER"
                return 0
            fi
        done
    elif command -v sntp >/dev/null 2>&1; then
        log_and_echo "Using sntp..."
        for SERVER in $NTP_SERVERS; do
            if sntp -sS "$SERVER" >> "$LOGFILE" 2>&1; then
                log_message "sntp synced with $SERVER"
                return 0
            fi
        done
    fi
    return 1
}

synchronize_time()
{
    log_message "Starting time synchronization sequence."

    # Priority 1: Built-in systemd-timesyncd (Debian/Ubuntu default)
    if sync_via_systemd; then
        YEAR=$(get_current_year)
        if [ "$YEAR" -ge "$MIN_VALID_YEAR" ]; then
            return 0
        fi
    fi

    # Priority 2: Built-in BusyBox ntpd (antiX/lightweight default)
    if sync_via_busybox; then
        YEAR=$(get_current_year)
        if [ "$YEAR" -ge "$MIN_VALID_YEAR" ]; then
            return 0
        fi
    fi

    # Priority 3: Installed Chrony
    if sync_via_chrony; then
        YEAR=$(get_current_year)
        if [ "$YEAR" -ge "$MIN_VALID_YEAR" ]; then
            return 0
        fi
    fi

    # Priority 4: ntpdate / sntp
    if sync_via_ntpdate; then
        YEAR=$(get_current_year)
        if [ "$YEAR" -ge "$MIN_VALID_YEAR" ]; then
            return 0
        fi
    fi

    # Priority 5: Fallback to HTTP Date bootstrap (works everywhere with curl/wget)
    log_and_echo "Trying HTTP date synchronization fallback..."
    if bootstrap_http_time; then
        return 0
    fi

    return 1
}

###############################################################################
# Step 3: Hardware Clock & Persistence
###############################################################################

persist_time()
{
    # 1. Update Hardware Clock (RTC) if supported
    if command -v hwclock >/dev/null 2>&1; then
        if hwclock --systohc --utc 2>/dev/null || hwclock -w 2>/dev/null; then
            log_message "Hardware clock updated (hwclock --systohc --utc)."
        else
            log_message "Notice: hwclock write failed (hardware RTC may be disabled or inaccessible)."
        fi
    fi

    # 2. Update fake-hwclock if installed (crucial for dead RTC batteries)
    if command -v fake-hwclock >/dev/null 2>&1; then
        if fake-hwclock save 2>/dev/null; then
            log_message "Saved current time to fake-hwclock (/etc/fake-hwclock.data)."
        fi
    fi
}

###############################################################################
# Step 4: Manual Date & Time Setting (Offline or Override)
###############################################################################

set_manual_time()
{
    check_root
    MANUAL_VAL="$1"

    if [ -z "$MANUAL_VAL" ]; then
        echo "ERROR: Missing date/time specification."
        echo "Example: sudo $0 --set \"2026-09-20 16:30:00\""
        return 1
    fi

    log_and_echo "Setting manual system time to: $MANUAL_VAL"

    if date -s "$MANUAL_VAL" >/dev/null 2>&1; then
        persist_time
        log_and_echo "SUCCESS: System time manually set to $(date '+%Y-%m-%d %H:%M:%S %Z')."
        log_and_echo "Saved to Hardware Clock (RTC) and fake-hwclock."
        return 0
    else
        log_and_echo "ERROR: Failed to apply manual time: '$MANUAL_VAL'"
        echo "Please use a format like: \"YYYY-MM-DD HH:MM:SS\" (e.g. \"2026-09-20 16:30:00\")"
        return 1
    fi
}

set_manual_time_interactive()
{
    check_root

    echo
    echo "=================================================="
    echo "            Manual Date & Time Setup              "
    echo "=================================================="
    echo "Set system time manually when offline or if network"
    echo "synchronization is unavailable."
    echo

    DEFAULT_DATE=$(date '+%Y-%m-%d' 2>/dev/null || echo "2026-09-20")
    CUR_YEAR=$(get_current_year)
    if [ "$CUR_YEAR" -lt "$MIN_VALID_YEAR" ]; then
        DEFAULT_DATE="2026-09-20"
    fi

    printf "Enter Date [YYYY-MM-DD] (default: %s): " "$DEFAULT_DATE"
    read -r INPUT_DATE
    [ -z "$INPUT_DATE" ] && INPUT_DATE="$DEFAULT_DATE"

    DEFAULT_TIME=$(date '+%H:%M:%S' 2>/dev/null || echo "12:00:00")
    printf "Enter Time [HH:MM:SS] (default: %s): " "$DEFAULT_TIME"
    read -r INPUT_TIME
    [ -z "$INPUT_TIME" ] && INPUT_TIME="$DEFAULT_TIME"

    COMBINED="$INPUT_DATE $INPUT_TIME"
    set_manual_time "$COMBINED"
}

###############################################################################
# Step 5: System-Wide Commands Installation (/usr/local/bin)
###############################################################################

install_shortcuts()
{
    check_root

    SCRIPT_PATH="$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")"

    echo "[+] Installing system-wide time-sync commands into /usr/local/bin..."
    mkdir -p /usr/local/bin

    ln -sf "$SCRIPT_PATH" /usr/local/bin/sync-time
    ln -sf "$SCRIPT_PATH" /usr/local/bin/time-sync
    chmod +x /usr/local/bin/sync-time /usr/local/bin/time-sync "$SCRIPT_PATH"

    echo "  [OK] Created /usr/local/bin/sync-time"
    echo "  [OK] Created /usr/local/bin/time-sync"

    # Also register init.d service if requested or if SysV init is detected
    if [ -d /etc/init.d ] && [ ! -f /etc/init.d/time-sync ]; then
        if [ -t 0 ]; then
            echo
            printf "Would you like to install automatic boot sync service into /etc/init.d? [y/N]: "
            read -r BOOT_CHOICE
            case "$BOOT_CHOICE" in
                [yY]|[yY][eE][sS])
                    cp "$SCRIPT_PATH" /etc/init.d/time-sync
                    chmod +x /etc/init.d/time-sync
                    if command -v update-rc.d >/dev/null 2>&1; then
                        update-rc.d time-sync defaults 2>/dev/null || true
                        echo "  [OK] Registered SysV init service: /etc/init.d/time-sync"
                    fi
                    ;;
            esac
        fi
    fi

    echo
    echo "=================================================="
    echo "       Time Sync Commands Installed!              "
    echo "=================================================="
    echo "You can now run time synchronization from any terminal:"
    echo "  sudo sync-time                          # Auto sync over internet"
    echo "  sudo sync-time --manual                 # Interactive manual time setup"
    echo "  sudo sync-time --set \"YYYY-MM-DD HH:MM:SS\""
    echo "  sudo sync-time --status                 # Check current time & diagnostics"
    echo "  (Or shortcut alias: sudo time-sync)"
    echo "=================================================="
}

uninstall_shortcuts()
{
    check_root

    echo "[+] Uninstalling time-sync commands..."
    rm -f /usr/local/bin/sync-time
    rm -f /usr/local/bin/time-sync

    if [ -f /etc/init.d/time-sync ]; then
        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d -f time-sync remove 2>/dev/null || true
        fi
        rm -f /etc/init.d/time-sync
        echo "  [OK] Removed /etc/init.d/time-sync"
    fi

    echo "  [OK] Removed /usr/local/bin/sync-time and /usr/local/bin/time-sync"
    echo "=================================================="
    echo "       Time Sync Uninstalled Cleanly              "
    echo "=================================================="
}

###############################################################################
# Main Synchronization Pipeline
###############################################################################

run_sync_pipeline()
{
    check_root

    log_and_echo "=================================================="
    log_and_echo "Time Synchronization Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"

    # 1. First check if network is available
    if ! wait_for_network; then
        log_and_echo "ERROR: Cannot synchronize time because network is unreachable."
        log_and_echo "Check your Internet connection (Wi-Fi or Ethernet) and try again."

        if [ -t 0 ]; then
            echo
            printf "Network is unreachable. Would you like to set the date and time manually? [y/N]: "
            read -r MANUAL_CHOICE
            case "$MANUAL_CHOICE" in
                [yY]|[yY][eE][sS])
                    set_manual_time_interactive
                    return $?
                    ;;
            esac
        fi
        return 1
    fi

    # 2. Check for 2008 or older clock and perform bootstrap first
    CURRENT_YEAR=$(get_current_year)
    if [ "$CURRENT_YEAR" -lt "$MIN_VALID_YEAR" ]; then
        bootstrap_http_time
    fi

    # 3. Synchronize using prioritized tools
    if synchronize_time; then
        # 4. Save to hardware clock and fake-hwclock
        persist_time

        FINAL_YEAR=$(get_current_year)
        if [ "$FINAL_YEAR" -ge "$MIN_VALID_YEAR" ]; then
            log_and_echo "SUCCESS: Time synchronized successfully."
            log_and_echo "Current System Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            log_and_echo "=================================================="
            return 0
        fi
    fi

    log_and_echo "ERROR: Automatic time synchronization failed. Year is still $(get_current_year)."
    log_and_echo "=================================================="

    if [ -t 0 ]; then
        echo
        printf "Automatic sync failed. Would you like to set the date and time manually? [y/N]: "
        read -r MANUAL_CHOICE
        case "$MANUAL_CHOICE" in
            [yY]|[yY][eE][sS])
                set_manual_time_interactive
                return $?
                ;;
        esac
    fi

    return 1
}

###############################################################################
# Status & Diagnostics
###############################################################################

show_status()
{
    echo "=================================================="
    echo "         Time Synchronization Diagnostics         "
    echo "=================================================="
    echo "Current System Time : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Current Year        : $(get_current_year)"

    if command -v hwclock >/dev/null 2>&1; then
        HW_TIME=$(hwclock -r 2>/dev/null || echo "Unavailable/Error")
        echo "Hardware Clock (RTC): $HW_TIME"
    fi

    if [ -f /etc/fake-hwclock.data ]; then
        echo "fake-hwclock Data   : $(cat /etc/fake-hwclock.data 2>/dev/null)"
    fi

    echo
    echo "System Commands in /usr/local/bin:"
    printf "  - sync-time         : "
    if [ -x /usr/local/bin/sync-time ]; then
        echo "Installed in /usr/local/bin"
    else
        echo "Not installed (Run: sudo $0 --install)"
    fi

    printf "  - time-sync         : "
    if [ -x /usr/local/bin/time-sync ]; then
        echo "Installed in /usr/local/bin"
    else
        echo "Not installed (Run: sudo $0 --install)"
    fi

    echo
    echo "Installed Time Tools:"
    printf "  - systemd-timesyncd : "
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        echo "Active"
    else
        echo "Not active"
    fi

    printf "  - chrony            : "
    if command -v chronyc >/dev/null 2>&1; then
        echo "Installed ($(chronyc -v 2>/dev/null | head -n 1 || echo 'chrony'))"
    else
        echo "Not installed"
    fi

    printf "  - busybox ntpd      : "
    if command -v busybox >/dev/null 2>&1 && busybox ntpd --help >/dev/null 2>&1; then
        echo "Installed (Built-in)"
    else
        echo "Not installed"
    fi

    printf "  - ntpdate           : "
    if command -v ntpdate >/dev/null 2>&1; then
        echo "Installed"
    else
        echo "Not installed"
    fi

    printf "  - fake-hwclock      : "
    if command -v fake-hwclock >/dev/null 2>&1; then
        echo "Installed"
    else
        echo "Not installed (Recommended for dead RTC batteries)"
    fi

    echo
    echo "Recent Synchronization Log (/var/log/time-sync.log):"
    echo "--------------------------------------------------"
    if [ -f "$LOGFILE" ]; then
        tail -n 15 "$LOGFILE"
    else
        echo "(No log file created yet)"
    fi
    echo "--------------------------------------------------"
}

show_help()
{
    echo "Universal Internet Time Synchronization for Debian-based Systems"
    echo
    echo "Usage: sudo $0 [OPTION]"
    echo
    echo "Options:"
    echo "  (no arguments)         Synchronize system time immediately over internet"
    echo "  --sync, start          Synchronize system time immediately (explicit flag)"
    echo "  --manual, -m           Interactively set date and time manually (offline mode)"
    echo "  --set \"DATE STRING\"    Set date and time manually via CLI and persist to RTC"
    echo "  --install, -i          Install 'sync-time' and 'time-sync' into /usr/local/bin"
    echo "  --uninstall, -u        Remove global symlinks and services"
    echo "  --status, -s           Show current time status, installed tools & recent logs"
    echo "  --restart, restart     Restart time synchronization"
    echo "  --stop, stop           No-op (oneshot synchronization task)"
    echo "  --help, -h             Show this help message"
    echo
    echo "Examples:"
    echo "  sudo $0 --install                           # Install global 'sync-time' and 'time-sync' commands"
    echo "  sudo sync-time                              # Sync time over internet from any terminal"
    echo "  sudo sync-time --manual                     # Set date/time manually if offline or no internet"
    echo "  sudo sync-time --set \"2026-09-20 16:30:00\"      # Direct manual date/time setting"
    echo "  sudo sync-time --status                     # View clock status, RTC, and logs"
    echo
}

###############################################################################
# Main Entrypoint
###############################################################################

case "${1:-}" in
    --sync|start|"")
        run_sync_pipeline
        exit $?
        ;;

    --manual|-m)
        set_manual_time_interactive
        exit $?
        ;;

    --set)
        if [ -z "${2:-}" ]; then
            echo "ERROR: --set requires a date/time argument."
            echo "Example: sudo $0 --set \"2026-09-20 16:30:00\""
            exit 1
        fi
        set_manual_time "$2"
        exit $?
        ;;

    --install|-i)
        install_shortcuts
        exit $?
        ;;

    --uninstall|-u)
        uninstall_shortcuts
        exit $?
        ;;

    --status|status|-s)
        show_status
        exit 0
        ;;

    --restart|restart)
        run_sync_pipeline
        exit $?
        ;;

    --stop|stop)
        echo "time-sync performs a one-time synchronization; nothing to stop."
        exit 0
        ;;

    --help|-h)
        show_help
        exit 0
        ;;

    *)
        echo "Invalid option: $1"
        echo
        show_help
        exit 1
        ;;
esac
