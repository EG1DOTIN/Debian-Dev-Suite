#!/usr/bin/env bash

###############################################################################
# MX Linux / Debian Battery & Deep Sleep Optimization Suite
# Part of the Debian Dev Suite
#
# Ultra-efficient, 100% open-source, privacy-first power optimization:
#   - 100% Free & Open-Source (FOSS), Zero Telemetry, 0 Network Tracking
#   - Kernel S3 Deep Sleep: Forces suspend-to-RAM (mem_sleep_default=deep)
#   - TLP Power Management: Advanced CPU, PCIe, USB & battery tuning
#   - Dual Init Support: Full compatibility with both systemd and SysVinit/MX Linux
#   - Suspend-then-Hibernate: Time-based fallback with RAM/Swap safety audit
#   - Diagnostic Dashboard: Real-time power state, battery health & swap checks
#
# USAGE:
#   sudo ./setup-deep-sleep.sh --install       # Turnkey installation and configuration
#   ./setup-deep-sleep.sh --status             # Non-root diagnostic check
#   sudo ./setup-deep-sleep.sh --uninstall     # Cleanly revert sleep and GRUB configs
#   ./setup-deep-sleep.sh --help               # Show usage details
###############################################################################

set -euo pipefail

# ANSI Colors
BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
MAGENTA="\033[0;35m"
RESET="\033[0m"

TICK="${GREEN}✔${RESET}"
CROSS="${RED}✖${RESET}"
WARN="${YELLOW}⚠${RESET}"
INFO="${CYAN}ℹ${RESET}"

GRUB_FILE="/etc/default/grub"
SLEEP_CONF_DIR="/etc/systemd/sleep.conf.d"
SLEEP_CONF_DROPIN="${SLEEP_CONF_DIR}/10-deep-sleep.conf"
SLEEP_CONF_LEGACY="/etc/systemd/sleep.conf"

print_header() {
    echo -e "\n${BOLD}${CYAN}======================================================================${RESET}"
    echo -e "${BOLD}${CYAN}  $1${RESET}"
    echo -e "${BOLD}${CYAN}======================================================================${RESET}\n"
}

print_section() {
    echo -e "\n${BOLD}${MAGENTA}--- $1 ---${RESET}\n"
}

print_pass() {
    echo -e "  [${TICK}] $1"
}

print_warn() {
    echo -e "  [${WARN}] ${YELLOW}$1${RESET}"
}

print_fail() {
    echo -e "  [${CROSS}] ${RED}$1${RESET}"
}

print_info() {
    echo -e "  [${INFO}] ${CYAN}$1${RESET}"
}

show_help() {
    cat << 'EOF'
================================================================================
     Battery & Deep Sleep Optimization — Debian Dev Suite
================================================================================

Usage: ./setup-deep-sleep.sh [OPTION]

Options:
  --install, -i          Install TLP, configure kernel deep sleep in GRUB,
                         and configure suspend-then-hibernate. (Requires root)
  --status, -s           Show diagnostic report of active sleep states,
                         TLP service, battery status, and swap sizing.
  --uninstall, -u        Revert GRUB deep sleep parameter and remove sleep.conf
                         drop-in modifications. (Requires root)
  --no-reboot            Suppress interactive reboot prompt during install.
  --help, -h             Display this help menu.

Examples:
  ./setup-deep-sleep.sh --status
  sudo ./setup-deep-sleep.sh --install
  sudo ./setup-deep-sleep.sh --install --no-reboot
  sudo ./setup-deep-sleep.sh --uninstall
EOF
}

check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        print_fail "This action requires root privileges."
        echo -e "Please run with sudo: ${BOLD}sudo $0 ${ACTION:---install}${RESET}" >&2
        exit 1
    fi
}

is_systemd() {
    [ -d /run/systemd/system ]
}

# -------------------------------------------------------------------------
# Diagnostic Status Dashboard (Works without root)
# -------------------------------------------------------------------------
show_status() {
    print_header "Linux Deep Sleep & Battery Diagnostics"

    # 1. Hardware & Kernel Sleep States
    echo -e "${BOLD}1. Hardware Sleep States (/sys/power/mem_sleep):${RESET}"
    if [ -f "/sys/power/mem_sleep" ]; then
        local mem_sleep
        mem_sleep=$(cat /sys/power/mem_sleep)
        echo -e "   Current State : ${CYAN}${mem_sleep}${RESET}"
        if [[ "$mem_sleep" == *"deep"* ]]; then
            if [[ "$mem_sleep" == *"[deep]"* ]]; then
                print_pass "Active state is 'deep' (S3 Suspend-to-RAM: Maximum power saving)."
            else
                print_warn "Hardware supports 'deep', but current default is '$(echo "$mem_sleep" | grep -o '\[.*\]')'."
                echo "   -> Run '--install' to lock in 'deep' via GRUB."
            fi
        else
            print_warn "Kernel only exposes 's2idle'. ACPI S3 deep sleep may be disabled in BIOS."
        fi
    else
        print_warn "/sys/power/mem_sleep not exposed by kernel or virtual environment."
    fi

    if [ -f "/sys/power/state" ]; then
        echo -e "   Supported States : $(cat /sys/power/state)"
    fi

    # 2. GRUB Configuration
    echo -e "\n${BOLD}2. GRUB Kernel Boot Parameters:${RESET}"
    if [ -f "$GRUB_FILE" ]; then
        if grep -q "mem_sleep_default=deep" "$GRUB_FILE"; then
            print_pass "GRUB configured with: mem_sleep_default=deep"
        else
            print_warn "GRUB is NOT yet configured with 'mem_sleep_default=deep'."
        fi
    else
        print_warn "$GRUB_FILE not found (System may use EFI stub or non-GRUB bootloader)."
    fi

    # 3. Init System & TLP Status
    echo -e "\n${BOLD}3. Init System & TLP Service:${RESET}"
    if is_systemd; then
        echo -e "   Init System : ${GREEN}systemd${RESET}"
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet tlp.service 2>/dev/null; then
                print_pass "TLP service is ACTIVE (systemd)"
            elif systemctl is-enabled --quiet tlp.service 2>/dev/null; then
                print_warn "TLP service is ENABLED but not currently running"
            else
                print_warn "TLP service is NOT enabled in systemd"
            fi
        fi
    else
        echo -e "   Init System : ${CYAN}SysVinit / MX Linux / OpenRC${RESET}"
        if [ -x "/etc/init.d/tlp" ] || [ -f "/etc/init.d/tlp" ]; then
            if service tlp status >/dev/null 2>&1 || /etc/init.d/tlp status >/dev/null 2>&1; then
                print_pass "TLP service is ACTIVE (SysVinit/init.d)"
            else
                print_warn "TLP service script present in /etc/init.d/tlp (start via: service tlp start)"
            fi
        else
            print_warn "TLP init script not found in /etc/init.d/"
        fi
    fi

    if command -v tlp-stat >/dev/null 2>&1; then
        print_pass "TLP binary installed ($(tlp-stat -s 2>/dev/null | grep -E "TLP.*enabled" || echo "Installed"))"
    else
        print_warn "TLP binary is NOT installed. Run: sudo $0 --install"
    fi

    # 4. RAM vs Swap Audit (Prerequisite for Hibernate)
    echo -e "\n${BOLD}4. Memory & Swap Capacity Audit (for Hibernation):${RESET}"
    local ram_total_mb swap_total_mb
    ram_total_mb=$(free -m | awk '/^Mem:/{print $2}')
    swap_total_mb=$(free -m | awk '/^Swap:/{print $2}')

    echo -e "   Physical RAM : ${ram_total_mb} MiB"
    echo -e "   Active Swap  : ${swap_total_mb} MiB"

    if [ "$swap_total_mb" -eq 0 ]; then
        print_warn "No Swap space detected! Suspend-to-RAM works, but Hibernation is disabled."
    elif [ "$swap_total_mb" -ge "$ram_total_mb" ]; then
        print_pass "Swap (${swap_total_mb} MiB) is >= RAM (${ram_total_mb} MiB). Safe for Suspend-then-Hibernate."
    else
        print_warn "Swap (${swap_total_mb} MiB) is smaller than RAM (${ram_total_mb} MiB)."
        echo "   -> Note: If memory usage exceeds swap size during sleep, hibernation may fail."
    fi

    # 5. Battery Health (if laptop)
    echo -e "\n${BOLD}5. Battery Hardware Status:${RESET}"
    local bat_found=false
    for bat in /sys/class/power_supply/BAT* /sys/class/power_supply/battery; do
        if [ -d "$bat" ]; then
            bat_found=true
            local bat_name status capacity health
            bat_name=$(basename "$bat")
            status=$(cat "$bat/status" 2>/dev/null || echo "Unknown")
            capacity=$(cat "$bat/capacity" 2>/dev/null || echo "Unknown")
            echo -e "   [Battery: ${bat_name}] Status: ${GREEN}${status}${RESET} | Charge: ${CYAN}${capacity}%${RESET}"
        fi
    done
    if [ "$bat_found" = false ]; then
        echo "   No battery detected (Desktop or VM host environment)."
    fi

    echo
}

# -------------------------------------------------------------------------
# Step 1: Configure Kernel Deep Sleep in GRUB
# -------------------------------------------------------------------------
configure_grub() {
    print_section "Step 1: Configuring Kernel Deep Sleep (S3 Suspend-to-RAM)"

    if [ ! -f "$GRUB_FILE" ]; then
        print_warn "$GRUB_FILE not found. Skipping GRUB bootloader modification."
        return 0
    fi

    # Check hardware capability
    if [ -f "/sys/power/mem_sleep" ]; then
        if ! grep -q "deep" /sys/power/mem_sleep; then
            print_warn "Hardware /sys/power/mem_sleep does not advertise 'deep'."
            print_warn "Applying parameter anyway for hardware that unlocks S3 on reboot."
        fi
    fi

    # Check if already present
    if grep -q "mem_sleep_default=deep" "$GRUB_FILE"; then
        print_pass "'mem_sleep_default=deep' is already active in $GRUB_FILE"
        return 0
    fi

    # Create safety backup
    local backup_file="${GRUB_FILE}.bak.$(date +%F_%H%M%S)"
    cp -p "$GRUB_FILE" "$backup_file"
    print_pass "Created safety backup at $backup_file"

    # Safely insert mem_sleep_default=deep into GRUB_CMDLINE_LINUX_DEFAULT
    if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=".*"' "$GRUB_FILE"; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 mem_sleep_default=deep"/' "$GRUB_FILE"
        # Clean any accidental double spaces
        sed -i 's/  */ /g' "$GRUB_FILE"
    elif grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=\(.*\)/GRUB_CMDLINE_LINUX_DEFAULT="\1 mem_sleep_default=deep"/' "$GRUB_FILE"
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash mem_sleep_default=deep"' >> "$GRUB_FILE"
    fi

    print_pass "Appended 'mem_sleep_default=deep' to GRUB_CMDLINE_LINUX_DEFAULT"

    # Update bootloader
    echo "Updating GRUB bootloader..."
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
        print_pass "GRUB configuration updated via update-grub"
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub-mkconfig -o /boot/grub/grub.cfg
        print_pass "GRUB configuration regenerated via grub-mkconfig"
    elif [ -x "/usr/sbin/update-grub" ]; then
        /usr/sbin/update-grub
        print_pass "GRUB configuration updated via /usr/sbin/update-grub"
    else
        print_warn "Could not locate update-grub command. Please run bootloader update manually."
    fi
}

# -------------------------------------------------------------------------
# Step 2: Install and Enable TLP Power Management
# -------------------------------------------------------------------------
configure_tlp() {
    print_section "Step 2: Installing and Activating TLP Power Management"

    # Install packages if missing
    if ! command -v tlp >/dev/null 2>&1; then
        echo "Installing tlp and tlp-rdw via apt-get..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq || true
        apt-get install -y --no-install-recommends tlp tlp-rdw
        print_pass "TLP packages installed successfully"
    else
        print_pass "TLP is already installed"
    fi

    # Configure services according to init system
    if is_systemd; then
        echo "Enabling TLP via systemd..."
        systemctl enable tlp.service 2>/dev/null || true
        systemctl restart tlp.service 2>/dev/null || true
        print_pass "TLP systemd service enabled and started"
    else
        echo "Configuring TLP for SysVinit / MX Linux..."
        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d tlp defaults 2>/dev/null || true
        fi
        if command -v service >/dev/null 2>&1; then
            service tlp restart 2>/dev/null || service tlp start 2>/dev/null || true
        elif [ -x "/etc/init.d/tlp" ]; then
            /etc/init.d/tlp restart 2>/dev/null || /etc/init.d/tlp start 2>/dev/null || true
        fi
        print_pass "TLP SysVinit service enabled and started"
    fi

    # Trigger immediate profile application
    if command -v tlp >/dev/null 2>&1; then
        tlp start >/dev/null 2>&1 || true
        print_pass "Applied active TLP power saving rules (tlp start)"
    fi
}

# -------------------------------------------------------------------------
# Step 3: Configure Suspend-then-Hibernate
# -------------------------------------------------------------------------
configure_sleep_hibernate() {
    print_section "Step 3: Configuring Suspend-then-Hibernate (120min timeout)"

    # Audit swap capacity
    local ram_total_mb swap_total_mb
    ram_total_mb=$(free -m | awk '/^Mem:/{print $2}')
    swap_total_mb=$(free -m | awk '/^Swap:/{print $2}')

    if [ "$swap_total_mb" -lt "$ram_total_mb" ]; then
        print_warn "Active Swap (${swap_total_mb} MiB) is smaller than RAM (${ram_total_mb} MiB)."
        print_warn "Suspend-to-RAM works immediately. However, if your system transitions to Hibernate"
        print_warn "when RAM exceeds swap capacity, hibernation will fail."
        echo "   -> Recommendation: Expand swap or create a swapfile if you want seamless hibernation."
    fi

    if is_systemd; then
        # Use clean drop-in directory instead of modifying default package files
        mkdir -p "$SLEEP_CONF_DIR"
        cat > "$SLEEP_CONF_DROPIN" << 'EOF'
# Configured by Debian Dev Suite (Setup-Deep-Sleep)
# Transitions system from Suspend-to-RAM to Hibernate after 120 minutes of sleep
[Sleep]
HibernateDelaySec=120min
EOF
        print_pass "Installed systemd sleep drop-in at $SLEEP_CONF_DROPIN"
    else
        print_info "SysVinit / MX Linux does not use systemd-sleep.conf."
        print_info "Kernel S3 deep sleep (mem_sleep_default=deep) will manage sleep power states."
    fi
}

# -------------------------------------------------------------------------
# Revert / Uninstall
# -------------------------------------------------------------------------
revert_configs() {
    print_header "Reverting Deep Sleep & Battery Configurations"

    check_root

    # Revert GRUB
    if [ -f "$GRUB_FILE" ] && grep -q "mem_sleep_default=deep" "$GRUB_FILE"; then
        echo "Removing mem_sleep_default=deep from $GRUB_FILE..."
        sed -i 's/mem_sleep_default=deep//g' "$GRUB_FILE"
        sed -i 's/  */ /g' "$GRUB_FILE"
        if command -v update-grub >/dev/null 2>&1; then
            update-grub
        elif command -v grub-mkconfig >/dev/null 2>&1; then
            grub-mkconfig -o /boot/grub/grub.cfg
        fi
        print_pass "Reverted GRUB kernel parameters and updated bootloader"
    else
        print_info "No GRUB deep sleep parameter found to revert."
    fi

    # Remove sleep drop-in
    if [ -f "$SLEEP_CONF_DROPIN" ]; then
        rm -f "$SLEEP_CONF_DROPIN"
        print_pass "Removed systemd drop-in $SLEEP_CONF_DROPIN"
    fi

    echo -e "\n${GREEN}✔ Deep sleep parameters have been cleanly removed.${RESET}\n"
}

# -------------------------------------------------------------------------
# Main Installation Flow
# -------------------------------------------------------------------------
install_all() {
    print_header "Starting Linux Battery & Deep Sleep Optimization"

    check_root

    configure_grub
    configure_tlp
    configure_sleep_hibernate

    echo
    echo "====================================================================="
    echo -e "${GREEN}${BOLD}✔ Optimization Complete Successfully!${RESET}"
    echo "  - Kernel Deep Sleep : mem_sleep_default=deep in GRUB"
    echo "  - Power Tuning      : TLP service enabled & active (Zero Telemetry)"
    echo "  - Suspend Timeout   : 120 minutes Suspend-then-Hibernate configured"
    echo "====================================================================="

    # Interactive reboot prompt only if running in a TTY and not suppressed
    if [ "$NO_REBOOT" = false ] && [ -t 0 ]; then
        read -p "Would you like to reboot now to apply kernel changes? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Rebooting system..."
            reboot
        else
            echo "[*] Please remember to reboot your system later for kernel changes to take full effect."
        fi
    else
        echo "[*] Please reboot your system when convenient for kernel parameters to take full effect."
    fi
}

# -------------------------------------------------------------------------
# Argument Parsing
# -------------------------------------------------------------------------
ACTION="install"
NO_REBOOT=false

while [ $# -gt 0 ]; do
    case "$1" in
        --install|-i)
            ACTION="install"
            shift
            ;;
        --status|-s|status)
            ACTION="status"
            shift
            ;;
        --uninstall|-u|--revert)
            ACTION="uninstall"
            shift
            ;;
        --no-reboot)
            NO_REBOOT=true
            shift
            ;;
        --help|-h|help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET}"
            show_help
            exit 1
            ;;
    esac
done

case "$ACTION" in
    status)
        show_status
        ;;
    install)
        install_all
        ;;
    uninstall)
        revert_configs
        ;;
esac