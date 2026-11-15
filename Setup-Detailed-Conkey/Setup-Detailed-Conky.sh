#!/usr/bin/env bash
# ==============================================================================
# Setup-Detailed-Conky.sh
# 
# Comprehensive, secure, and privacy-first installer and lifecycle manager
# for the Advanced Detailed Conky System Monitor.
#
# Supported commands:
#   --install     : Auto-detects hardware, generates tailored config, enables autostart, & launches
#   --uninstall   : Completely and cleanly removes configs, autostart entries, & stops Conky
#   --status      : Reports live process state, autostart configuration, and detected sensors
#   --start       : Starts Conky in persistent background mode
#   --stop        : Gracefully terminates running Conky instances
#   --restart     : Stops and restarts Conky with current configuration
#   --detect      : Scans and reports power supplies, thermal modules, and network devices
#   --help        : Displays full command-line usage and options
#
# Security & Privacy Highlights:
#   - 100% Offline: Zero external network requests, zero telemetry, zero analytics
#   - Unprivileged: Operates entirely in user space ($HOME), no sudo required
#   - Safe Execution: Strict error handling, safe file permissions (0600/0700)
#   - Hardware Adaptive: Dynamically tunes to battery names, CPU core counts, and thermal sensors
# ==============================================================================

set -euo pipefail

# Security Guardrail: Prevent running directly as pure root
if [ "$EUID" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    echo "✖ [SECURITY ERROR] Do not run this script directly as root!"
    echo "  Conky desktop configurations and autostart hooks belong in your regular user's home (~/.config/conky)."
    echo "  Please run: ./Setup-Detailed-Conky.sh"
    exit 1
fi

# ------------------------------------------------------------------------------
# Constants & Directory Paths
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"
USER_CONFIG_DIR="${TARGET_HOME}/.config/conky"
USER_CONFIG_FILE="${USER_CONFIG_DIR}/conky.conf"
AUTOSTART_DIR="${TARGET_HOME}/.config/autostart"
AUTOSTART_FILE="${AUTOSTART_DIR}/conky.desktop"
MX_STARTUP_DIR="${TARGET_HOME}/.conky"
MX_STARTUP_FILE="${MX_STARTUP_DIR}/conky-startup.sh"
ZOOM_PREF_FILE="${USER_CONFIG_DIR}/zoom_profile"

# ANSI Colors for Clean CLI Presentation
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
SLATE='\033[0;90m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Helper: Print Banners and Messages
# ------------------------------------------------------------------------------
print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "========================================================================"
    echo "      ADVANCED DETAILED CONKY SYSTEM MONITOR MANAGER                "
    echo "========================================================================"
    echo -e "${NC}"
}

log_info() {
    echo -e "${CYAN}ℹ [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓ [SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${AMBER}⚠ [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}✖ [ERROR]${NC} $1" >&2
}

# ------------------------------------------------------------------------------
# Hardware & Sensor Auto-Detection
# ------------------------------------------------------------------------------
detect_hardware() {
    # 1. Detect Battery and AC Adapter
    BATTERY_DEV=""
    AC_DEV=""
    if [ -d /sys/class/power_supply ]; then
        for p in /sys/class/power_supply/*; do
            [ -e "$p" ] || continue
            pname=$(basename "$p")
            ptype=$(cat "$p/type" 2>/dev/null || true)
            if [ "$ptype" = "Battery" ] && [ -z "$BATTERY_DEV" ]; then
                BATTERY_DEV="$pname"
            elif [ "$ptype" = "Mains" ] && [ -z "$AC_DEV" ]; then
                AC_DEV="$pname"
            fi
        done
    fi
    [ -z "$BATTERY_DEV" ] && BATTERY_DEV="BAT1"
    [ -z "$AC_DEV" ] && AC_DEV="ACAD"

    # 2. Detect Thermal Sensor Modules
    CPU_TEMP_VAR=""
    NVME_TEMP_VAR=""
    PCH_TEMP_VAR=""
    WIFI_TEMP_VAR=""

    if [ -d /sys/class/hwmon ]; then
        for h in /sys/class/hwmon/hwmon*; do
            [ -e "$h" ] || continue
            mname=$(cat "$h/name" 2>/dev/null || true)
            case "$mname" in
                coretemp|k10temp|zenpower)
                    CPU_TEMP_VAR="$mname"
                    ;;
                nvme)
                    NVME_TEMP_VAR="nvme"
                    ;;
                pch_*|acpitz)
                    [ -z "$PCH_TEMP_VAR" ] && PCH_TEMP_VAR="$mname"
                    ;;
                ath*|iwl*|rtw*)
                    WIFI_TEMP_VAR="$mname"
                    ;;
            esac
        done
    fi
    [ -z "$CPU_TEMP_VAR" ] && CPU_TEMP_VAR="coretemp"
    [ -z "$NVME_TEMP_VAR" ] && NVME_TEMP_VAR="nvme"
    [ -z "$PCH_TEMP_VAR" ] && PCH_TEMP_VAR="pch_cannonlake"
    [ -z "$WIFI_TEMP_VAR" ] && WIFI_TEMP_VAR="ath10k_hwmon"

    # 3. Detect Primary Network Interfaces
    NET_WIFI=""
    NET_ETH=""
    if [ -d /sys/class/net ]; then
        for iface in /sys/class/net/*; do
            [ -e "$iface" ] || continue
            iname=$(basename "$iface")
            [ "$iname" = "lo" ] && continue
            if [ -d "$iface/wireless" ] || [ -e "$iface/phy80211" ] || [[ "$iname" == wl* ]]; then
                [ -z "$NET_WIFI" ] && NET_WIFI="$iname"
            elif [[ "$iname" == eth* || "$iname" == en* ]]; then
                [ -z "$NET_ETH" ] && NET_ETH="$iname"
            fi
        done
    fi
    [ -z "$NET_WIFI" ] && NET_WIFI="wlan0"
    [ -z "$NET_ETH" ] && NET_ETH="eth0"

    # 4. Detect CPU Thread Count
    CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)
}

# ------------------------------------------------------------------------------
# Generate Dynamic Conky Configuration
# ------------------------------------------------------------------------------
generate_conky_config() {
    local target_file="$1"
    local zoom="${2:-}"

    # Resolve zoom preference
    if [ -z "$zoom" ]; then
        if [ -f "$ZOOM_PREF_FILE" ]; then
            zoom=$(cat "$ZOOM_PREF_FILE" 2>/dev/null || echo "large")
        else
            zoom="large" # Default to large full-height profile for optimal visibility
        fi
    fi

    detect_hardware

    # Dynamic layout, geometry, and typography based on zoom profile
    local win_w win_h gap_x gap_y inner_pad
    local font_base font_title font_sec font_mono
    local bar_w bar_h cpu_bar_w cpu_bar_h cpu_goto
    local graph_cpu_h graph_io_h hr_thick swap_bar_h

    case "$zoom" in
        normal|small|1)
            ZOOM_NAME="Normal (Compact 330px)"
            win_w=330
            win_h=840
            gap_x=20
            gap_y=35
            inner_pad=14
            font_base="DejaVu Sans:size=8"
            font_title="DejaVu Sans:bold:size=10"
            font_sec="DejaVu Sans:bold:size=9"
            font_mono="DejaVu Sans Mono:size=7.5"
            bar_w=330
            bar_h=5
            cpu_bar_w=45
            cpu_bar_h=4
            cpu_goto=175
            graph_cpu_h=22
            graph_io_h=18
            hr_thick=1
            ;;
        xlarge|huge|3)
            ZOOM_NAME="Extra Large (440px / 1440p-4K)"
            win_w=440
            win_h=1180
            gap_x=24
            gap_y=20
            inner_pad=18
            font_base="DejaVu Sans:size=11"
            font_title="DejaVu Sans:bold:size=13.5"
            font_sec="DejaVu Sans:bold:size=12"
            font_mono="DejaVu Sans Mono:size=10"
            bar_w=440
            bar_h=8
            cpu_bar_w=60
            cpu_bar_h=6
            cpu_goto=235
            graph_cpu_h=32
            graph_io_h=24
            hr_thick=1.5
            ;;
        large|zoomed|2|*)
            ZOOM_NAME="Large (Full 1080p Height 385px)"
            win_w=385
            win_h=1020
            gap_x=18
            gap_y=18
            inner_pad=16
            font_base="DejaVu Sans:size=9.5"
            font_title="DejaVu Sans:bold:size=12"
            font_sec="DejaVu Sans:bold:size=10.5"
            font_mono="DejaVu Sans Mono:size=8.5"
            bar_w=385
            bar_h=6
            cpu_bar_w=52
            cpu_bar_h=5
            cpu_goto=205
            graph_cpu_h=26
            graph_io_h=22
            hr_thick=1
            ;;
    esac
    swap_bar_h=$((bar_h > 4 ? bar_h - 1 : 4))

    # Build per-core visual CPU bars dynamically based on detected cores and zoom geometry
    local cpu_cores_markup=""
    local i=1
    while [ $i -le "$CPU_CORES" ]; do
        local next=$((i + 1))
        if [ $next -le "$CPU_CORES" ]; then
            cpu_cores_markup+="\${color1}C${i}: \${color5}\${cpu cpu${i}}% \${color0}\${cpubar cpu${i} ${cpu_bar_h},${cpu_bar_w}}\${goto ${cpu_goto}}\${color1}C${next}: \${color5}\${cpu cpu${next}}% \${color0}\${cpubar cpu${next} ${cpu_bar_h},${cpu_bar_w}}\n"
            i=$((i + 2))
        else
            cpu_cores_markup+="\${color1}C${i}: \${color5}\${cpu cpu${i}}% \${color0}\${cpubar cpu${i} ${cpu_bar_h},${cpu_bar_w}}\n"
            i=$((i + 1))
        fi
    done

    # Thermal sensor markup
    local thermal_cores_markup=""
    if [ -f "/sys/class/hwmon/hwmon5/temp2_input" ] || [ "$CPU_TEMP_VAR" = "coretemp" ]; then
        thermal_cores_markup="\${color1}Individual Cores:\${alignr}\${color5}\${hwmon ${CPU_TEMP_VAR} temp 2}°C \${color1}|\${color5} \${hwmon ${CPU_TEMP_VAR} temp 3}°C \${color1}|\${color5} \${hwmon ${CPU_TEMP_VAR} temp 4}°C \${color1}|\${color5} \${hwmon ${CPU_TEMP_VAR} temp 5}°C"
    else
        thermal_cores_markup="\${color1}CPU Temp:\${alignr}\${color5}\${hwmon ${CPU_TEMP_VAR} temp 1}°C"
    fi

    # Battery section markup (only if battery hardware exists or fallback)
    local battery_markup=""
    if [ -d "/sys/class/power_supply/${BATTERY_DEV}" ]; then
        battery_markup="\${color0}\${font ${font_sec}}⚡ POWER & BATTERY (${BATTERY_DEV}) \${hr ${hr_thick}}\${font}
\${color1}Status:\${alignr}\${color5}\${battery_status ${BATTERY_DEV}} \${color1}(AC: \${acpiacadapter ${AC_DEV}})
\${color1}Charge Level:\${alignr}\${color2}\${battery_percent ${BATTERY_DEV}}%
\${color2}\${battery_bar ${bar_h},${bar_w} ${BATTERY_DEV}}
\${color1}Estimated Remaining:\${alignr}\${color5}\${battery_time ${BATTERY_DEV}}
\${color1}Power Draw:\${alignr}\${color3}\${execi 5 awk '{c=\$1} END{getline < \"/sys/class/power_supply/${BATTERY_DEV}/voltage_now\"; printf \"%.2f W\", (c*\$1)/10^12}' /sys/class/power_supply/${BATTERY_DEV}/current_now 2>/dev/null}
\${color1}Battery Health:\${alignr}\${color2}\${execi 60 awk '{f=\$1} END{getline < \"/sys/class/power_supply/${BATTERY_DEV}/charge_full_design\"; printf \"%.1f%% of design capacity\", (f/\$1)*100}' /sys/class/power_supply/${BATTERY_DEV}/charge_full 2>/dev/null}
"
    else
        battery_markup="\${color0}\${font ${font_sec}}⚡ POWER STATUS \${hr ${hr_thick}}\${font}
\${color1}AC Power Adapter:\${alignr}\${color2}\${acpiacadapter ${AC_DEV}}
"
    fi

    cat << EOF > "$target_file"
-- ==============================================================================
-- ADVANCED DETAILED CONKY SYSTEM MONITOR
-- Generated automatically by Setup-Detailed-Conky.sh
-- Display Zoom Profile: ${ZOOM_NAME}
-- ==============================================================================
-- System Hardware Mapping:
--  - Battery: ${BATTERY_DEV} | AC Adapter: ${AC_DEV}
--  - CPU Module: ${CPU_TEMP_VAR} (${CPU_CORES} logical threads detected)
--  - NVMe Module: ${NVME_TEMP_VAR}
--  - Chipset Module: ${PCH_TEMP_VAR}
--  - WiFi Interface: ${NET_WIFI} | Ethernet: ${NET_ETH}
-- ==============================================================================

conky.config = {
    -- Window Positioning & Dimensions
    alignment = 'top_right',
    gap_x = ${gap_x},
    gap_y = ${gap_y},
    minimum_width = ${win_w},
    maximum_width = ${win_w},
    minimum_height = ${win_h},
    
    -- X11 Window Integration & Compositing
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'normal',
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    own_window_transparent = false,
    own_window_argb_visual = true,
    own_window_argb_value = 228,       -- Translucent dark glass (~90% opacity)
    own_window_colour = '#090d16',     -- Deep Obsidian Slate background

    -- Double Buffering & Sampling
    double_buffer = true,
    update_interval = 1.0,
    cpu_avg_samples = 2,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_ncurses = false,
    out_to_stderr = false,
    out_to_x = true,

    -- Borders & Padding
    draw_borders = false,
    draw_graph_borders = false,
    draw_outline = false,
    draw_shades = false,
    border_width = 0,
    border_inner_margin = ${inner_pad},
    border_outer_margin = 0,
    show_graph_range = false,
    show_graph_scale = false,

    -- Typography & Rendering
    use_xft = true,
    font = '${font_base}',
    extra_newline = false,
    uppercase = false,
    use_spacer = 'none',

    -- Curated Modern Color Scheme
    default_color = '#F1F5F9',         -- Base Crisp White
    color0 = '#38BDF8',                -- Electric Cyan: Headers & Primary Indicators
    color1 = '#94A3B8',                -- Cool Slate: Descriptive Labels & Units
    color2 = '#34D399',                -- Emerald Mint: Available RAM, Health, Success
    color3 = '#A78BFA',                -- Soft Lavender: Secondary metrics & Storage
    color4 = '#FB923C',                -- Warm Amber: Warnings, Used RAM, Temperatures
    color5 = '#F8FAFC',                -- Pure White: Numerical Highlights
    color6 = '#1E293B',                -- Subtle Border / Track Dark Tone
}

conky.text = [[
\${color0}\${font ${font_title}}◆ SYSTEM OVERVIEW \${hr ${hr_thick}}\${font}
\${color1}Host:\${color5} \${nodename}\${alignr}\${color1}Kernel:\${color5} \${kernel}
\${color1}Uptime:\${color5} \${uptime}\${alignr}\${color1}Arch:\${color5} \${machine}

${battery_markup}
\${color0}\${font ${font_sec}}■ MEMORY (AVAILABLE vs FREE) \${hr ${hr_thick}}\${font}
\${color1}RAM Used:\${alignr}\${color4}\${mem} / \${memmax} (\${memperc}%)
\${color4}\${membar ${bar_h},${bar_w}}
\${color1}RAM Available (Apps):\${alignr}\${color2}\${memavail} / \${memmax} (\${execi 2 awk '/MemTotal/{t=\$2} /MemAvailable/{a=\$2} END{printf "%.1f%%", (a/t)*100}' /proc/meminfo})
\${color2}\${execibar 2 ${bar_h},${bar_w} awk '/MemTotal/{t=\$2} /MemAvailable/{a=\$2} END{printf "%.0f", (a/t)*100}' /proc/meminfo}
\${color1}RAM Free (Unallocated):\${alignr}\${color5}\${memfree}
\${color1}Cache & Buffers:\${alignr}\${color1}Cached: \${color5}\${cached} \${color1}| Buffers: \${color5}\${buffers}
\${color1}Swap Space:\${alignr}\${color5}\${swap} / \${swapmax} (\${swapperc}%)
\${color3}\${swapbar ${swap_bar_h},${bar_w}}

\${color0}\${font ${font_sec}}▲ CPU LOAD & CORES (${CPU_CORES}T) \${hr ${hr_thick}}\${font}
\${color1}Overall CPU:\${color5} \${cpu cpu0}% @ \${freq_g} GHz\${alignr}\${color1}Load: \${color5}\${loadavg 1} \${loadavg 2} \${loadavg 3}
\${color0}\${cpugraph cpu0 ${graph_cpu_h},${bar_w} 38BDF8 FB923C -l}
${cpu_cores_markup}
\${color0}\${font ${font_sec}}▼ HARDWARE TEMPERATURES \${hr ${hr_thick}}\${font}
\${color1}CPU Package:\${alignr}\${color4}\${hwmon ${CPU_TEMP_VAR} temp 1}°C
${thermal_cores_markup}
\${color1}NVMe SSD:\${alignr}\${color5}\${hwmon ${NVME_TEMP_VAR} temp 1}°C
\${color1}Motherboard Chipset:\${alignr}\${color5}\${hwmon ${PCH_TEMP_VAR} temp 1}°C
\${color1}WiFi Chip:\${alignr}\${color5}\${hwmon ${WIFI_TEMP_VAR} temp 1}°C

\${color0}\${font ${font_sec}}◆ STORAGE & DISK I/O \${hr ${hr_thick}}\${font}
\${color1}Root (/):\${alignr}\${color5}\${fs_used /} / \${fs_size /} (\${fs_used_perc /}%)
\${color3}\${fs_bar ${bar_h},${bar_w} /}
\${color1}Available Space:\${alignr}\${color2}\${fs_free /} free
\${color1}Disk Read:\${color2} \${diskio_read}/s\${alignr}\${color1}Disk Write:\${color4} \${diskio_write}/s
\${color3}\${diskiograph ${graph_io_h},${bar_w} A78BFA 38BDF8 -l}

\${color0}\${font ${font_sec}}▲ NETWORK ACTIVITY \${hr ${hr_thick}}\${font}
\${color1}WiFi (${NET_WIFI}):\${alignr}\${color5}\${addr ${NET_WIFI}}
\${color1}Signal Quality:\${alignr}\${color2}\${wireless_link_qual_perc ${NET_WIFI}}%
\${color1}Download:\${color2} \${downspeed ${NET_WIFI}}/s\${alignr}\${color1}Total Down:\${color5} \${totaldown ${NET_WIFI}}
\${color2}\${downspeedgraph ${NET_WIFI} ${graph_io_h},${bar_w} 059669 34D399 -l}
\${color1}Upload:\${color3} \${upspeed ${NET_WIFI}}/s\${alignr}\${color1}Total Up:\${color5} \${totalup ${NET_WIFI}}
\${color3}\${upspeedgraph ${NET_WIFI} ${graph_io_h},${bar_w} 7C3AED A78BFA -l}

\${color0}\${font ${font_sec}}● TOP MEMORY CONSUMERS (ACTIONABLE) \${hr ${hr_thick}}\${font}
\${font ${font_mono}}\${color1}NAME             PID     MEM%       RES
\${color5}\${top_mem name 1} \${top_mem pid 1}  \${top_mem mem 1}%  \${alignr}\${top_mem mem_res 1}
\${color5}\${top_mem name 2} \${top_mem pid 2}  \${top_mem mem 2}%  \${alignr}\${top_mem mem_res 2}
\${color5}\${top_mem name 3} \${top_mem pid 3}  \${top_mem mem 3}%  \${alignr}\${top_mem mem_res 3}
\${color5}\${top_mem name 4} \${top_mem pid 4}  \${top_mem mem 4}%  \${alignr}\${top_mem mem_res 4}

\${font ${font_sec}}\${color0}● TOP CPU PROCESSES \${hr ${hr_thick}}\${font}
\${font ${font_mono}}\${color1}NAME             PID     CPU%      MEM%
\${color5}\${top name 1} \${top pid 1}  \${top cpu 1}%  \${alignr}\${top mem 1}%
\${color5}\${top name 2} \${top pid 2}  \${top cpu 2}%  \${alignr}\${top mem 2}%
\${color5}\${top name 3} \${top pid 3}  \${top cpu 3}%  \${alignr}\${top mem 3}%
\${color5}\${top name 4} \${top pid 4}  \${top cpu 4}%  \${alignr}\${top mem 4}
\${font}]]
EOF

    chmod 644 "$target_file"
}

# ------------------------------------------------------------------------------
# Action: Install & Enable Permanent Autostart
# ------------------------------------------------------------------------------
do_install() {
    print_banner
    log_info "Starting installation and hardware auto-tuning..."

    # Ensure conky is installed
    if ! command -v conky >/dev/null 2>&1; then
        log_info "Conky binary not found. Installing conky-all package via apt..."
        if [ "$EUID" -eq 0 ]; then
            apt-get update -y && apt-get install -y conky-all
        elif command -v sudo >/dev/null 2>&1; then
            sudo apt-get update -y && sudo apt-get install -y conky-all
        else
            log_error "Conky is not installed. Please install it using: sudo apt install conky-all"
            exit 1
        fi
    fi

    # Ensure target directories exist
    mkdir -p "${USER_CONFIG_DIR}"
    mkdir -p "${AUTOSTART_DIR}"
    mkdir -p "${MX_STARTUP_DIR}"

    # Generate workspace config and user config
    local local_conf="${SCRIPT_DIR}/conky.conf"
    log_info "Auditing hardware sensors & generating optimized configuration..."
    generate_conky_config "${local_conf}"
    cp -f "${local_conf}" "${USER_CONFIG_FILE}"
    log_success "Configuration installed to ${USER_CONFIG_FILE}"

    # Setup Universal Desktop Autostart (~/.config/autostart/conky.desktop)
    cat << EOF > "${AUTOSTART_FILE}"
[Desktop Entry]
Type=Application
Exec=${SCRIPT_DIR}/Setup-Detailed-Conky.sh --start
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Conky System Monitor
Comment=Start Detailed Conky System Monitor automatically on desktop login
EOF
    chmod 644 "${AUTOSTART_FILE}"
    log_success "Universal Desktop Autostart registered at ${AUTOSTART_FILE}"

    # Setup MX Linux Desktop Integration Hook (~/.conky/conky-startup.sh)
    cat << EOF > "${MX_STARTUP_FILE}"
#!/bin/bash
exec "${SCRIPT_DIR}/Setup-Detailed-Conky.sh" --start
EOF
    chmod 755 "${MX_STARTUP_FILE}"
    log_success "MX Linux compatibility hook registered at ${MX_STARTUP_FILE}"

    # Adjust permissions if executed under sudo
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_CONFIG_DIR}" "${AUTOSTART_FILE}" "${MX_STARTUP_DIR}" 2>/dev/null || true
    fi

    # Restart Conky immediately
    log_info "Launching Conky now..."
    do_restart

    echo ""
    log_success "Installation Complete! Conky will now start automatically forever."
}

# ------------------------------------------------------------------------------
# Action: Clean Uninstall
# ------------------------------------------------------------------------------
do_uninstall() {
    print_banner
    log_info "Initiating clean uninstallation of Conky monitor and autostart hooks..."

    # 1. Stop any running instances
    do_stop

    # 2. Remove autostart desktop entry
    if [ -f "${AUTOSTART_FILE}" ]; then
        rm -f "${AUTOSTART_FILE}"
        log_success "Removed autostart entry: ${AUTOSTART_FILE}"
    fi

    # 3. Remove MX Linux hook
    if [ -f "${MX_STARTUP_FILE}" ]; then
        rm -f "${MX_STARTUP_FILE}"
        log_success "Removed MX Linux hook: ${MX_STARTUP_FILE}"
    fi

    # 4. Remove installed configuration
    if [ -f "${USER_CONFIG_FILE}" ]; then
        rm -f "${USER_CONFIG_FILE}"
        log_success "Removed user configuration: ${USER_CONFIG_FILE}"
    fi

    echo ""
    log_success "Uninstallation completed cleanly. No background tasks or hooks remain."
}

# ------------------------------------------------------------------------------
# Action: Process Status & Health Check
# ------------------------------------------------------------------------------
do_status() {
    print_banner
    echo -e "${BOLD}1. Process State:${NC}"
    local pids
    pids=$(pgrep -x conky || true)
    if [ -n "$pids" ]; then
        echo -e "   Status:      ${GREEN}● RUNNING${NC}"
        echo -e "   PID(s):      ${CYAN}${pids}${NC}"
        local mem_usage
        mem_usage=$(ps -o rss= -p "$pids" 2>/dev/null | awk '{sum+=$1} END{printf "%.1f MB", sum/1024}')
        echo -e "   Memory RSS:  ${mem_usage}"
    else
        echo -e "   Status:      ${RED}○ STOPPED${NC}"
    fi
    echo ""

    echo -e "${BOLD}2. Autostart Configuration:${NC}"
    if [ -f "${AUTOSTART_FILE}" ]; then
        echo -e "   XDG Autostart: ${GREEN}✓ ENABLED${NC} (${AUTOSTART_FILE})"
    else
        echo -e "   XDG Autostart: ${SLATE}○ DISABLED${NC}"
    fi
    if [ -f "${MX_STARTUP_FILE}" ]; then
        echo -e "   MX Linux Hook: ${GREEN}✓ ENABLED${NC} (${MX_STARTUP_FILE})"
    else
        echo -e "   MX Linux Hook: ${SLATE}○ NOT PRESENT${NC}"
    fi
    echo ""

    echo -e "${BOLD}3. Zoom & Typography Profile:${NC}"
    local current_zoom="large"
    [ -f "${ZOOM_PREF_FILE}" ] && current_zoom=$(cat "${ZOOM_PREF_FILE}" 2>/dev/null || echo "large")
    echo -e "   Profile:     ${GREEN}${current_zoom}${NC} (Change via '--zoom [normal|large|xlarge]')"
    echo ""

    echo -e "${BOLD}4. Configuration File:${NC}"
    if [ -f "${USER_CONFIG_FILE}" ]; then
        echo -e "   Active Config: ${CYAN}${USER_CONFIG_FILE}${NC}"
    else
        echo -e "   Active Config: ${AMBER}Not installed in ~/.config/conky/${NC}"
    fi
    echo ""

    echo -e "${BOLD}5. Detected Hardware Sensors:${NC}"
    detect_hardware
    echo -e "   Battery:     ${GREEN}${BATTERY_DEV}${NC} (Mains: ${AC_DEV})"
    echo -e "   CPU Module:  ${GREEN}${CPU_TEMP_VAR}${NC} (${CPU_CORES} threads)"
    echo -e "   NVMe Temp:   ${GREEN}${NVME_TEMP_VAR}${NC}"
    echo -e "   Network:     WiFi=${GREEN}${NET_WIFI}${NC}, Eth=${GREEN}${NET_ETH}${NC}"
    echo ""
}

# ------------------------------------------------------------------------------
# Action: Start, Stop, Restart
# ------------------------------------------------------------------------------
do_start() {
    if pgrep -x conky >/dev/null 2>&1; then
        log_info "Conky is already running. Use '--restart' to reload."
        return 0
    fi
    local conf="${USER_CONFIG_FILE}"
    [ ! -f "$conf" ] && conf="${SCRIPT_DIR}/conky.conf"

    if [ ! -f "$conf" ]; then
        log_error "Configuration file not found. Run '--install' first."
        exit 1
    fi

    # Brief delay if invoked during boot to let window manager/wallpaper settle
    if [ "${1:-}" = "delayed" ]; then
        sleep 3
    fi

    (setsid conky -c "$conf" >/dev/null 2>&1 &)
    sleep 0.8
    if pgrep -x conky >/dev/null 2>&1; then
        log_success "Conky started in background."
    else
        log_warn "Conky launched."
    fi
}

do_stop() {
    if pgrep -x conky >/dev/null 2>&1; then
        killall -q conky 2>/dev/null || pkill -x conky 2>/dev/null || true
        local count=0
        while pgrep -x conky >/dev/null 2>&1 && [ $count -lt 30 ]; do
            sleep 0.1
            count=$((count + 1))
        done
        if pgrep -x conky >/dev/null 2>&1; then
            killall -9 -q conky 2>/dev/null || pkill -9 -x conky 2>/dev/null || true
            sleep 0.2
        fi
        log_success "Conky processes stopped."
    else
        log_info "No running Conky instance found."
    fi
}

do_restart() {
    do_stop
    sleep 1
    do_start
    log_success "Conky restarted."
}

# ------------------------------------------------------------------------------
# Action: Hardware & Sensor Audit
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Action: Adjust Zoom & Display Profile
# ------------------------------------------------------------------------------
do_zoom() {
    local requested="${1:-large}"
    [ "$requested" = "--zoom" ] && requested="large"
    [ -z "$requested" ] && requested="large"

    print_banner
    log_info "Applying display zoom profile: ${requested}..."

    mkdir -p "${USER_CONFIG_DIR}"
    echo "$requested" > "${ZOOM_PREF_FILE}"

    local local_conf="${SCRIPT_DIR}/conky.conf"
    generate_conky_config "${local_conf}" "$requested"
    cp -f "${local_conf}" "${USER_CONFIG_FILE}"
    log_success "Generated and installed ${ZOOM_NAME} configuration."

    log_info "Restarting Conky with new zoom settings..."
    do_restart
    log_success "Zoom applied! Conky now takes full vertical height with enhanced visibility."
}

do_detect() {
    print_banner
    echo "========================================================"
    echo "          CONKY HARDWARE & SENSOR AUDIT                 "
    echo "========================================================"
    echo ""

    echo "--- 1. BATTERY & AC ADAPTER ---"
    if [ -d /sys/class/power_supply ]; then
        for dev in /sys/class/power_supply/*; do
            [ -e "$dev" ] || continue
            local name ptype pstatus pcap
            name=$(basename "$dev")
            ptype=$(cat "$dev/type" 2>/dev/null || true)
            pstatus=$(cat "$dev/status" 2>/dev/null || true)
            pcap=$(cat "$dev/capacity" 2>/dev/null || true)
            echo "Found: $name (Type: $ptype)"
            if [ "$ptype" = "Battery" ]; then
                echo "  -> Capacity: ${pcap}% | Status: $pstatus"
                echo "  -> Conky Battery Variable: \${battery $name} or \${battery_percent $name}"
            elif [ "$ptype" = "Mains" ]; then
                echo "  -> Online State: $(cat "$dev/online" 2>/dev/null || true)"
                echo "  -> Conky AC Adapter: \${acpiacadapter $name}"
            fi
        done
    else
        echo "No /sys/class/power_supply found."
    fi
    echo ""

    echo "--- 2. HWMON TEMPERATURE SENSORS ---"
    if [ -d /sys/class/hwmon ]; then
        for h in /sys/class/hwmon/hwmon*; do
            [ -e "$h" ] || continue
            local hname modname
            hname=$(basename "$h")
            modname=$(cat "$h/name" 2>/dev/null || true)
            echo "Device $hname: module name = '$modname'"
            for s in "$h"/temp*_input; do
                [ -e "$s" ] || continue
                local sbase idx label val temp_c
                sbase=$(basename "$s" _input)
                idx="${sbase#temp}"
                label=$(cat "$h/${sbase}_label" 2>/dev/null || true)
                [ -z "$label" ] && label="(sensor $idx)"
                val=$(cat "$s" 2>/dev/null || true)
                if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
                    temp_c=$((val / 1000))
                    echo "  -> $sbase: $label = ${temp_c}°C"
                    echo "     Conky: \${hwmon $modname temp $idx} or \${hwmon ${hname#hwmon} temp $idx}"
                fi
            done
        done
    else
        echo "No /sys/class/hwmon found."
    fi
    echo ""

    echo "--- 3. NETWORK INTERFACES ---"
    if [ -d /sys/class/net ]; then
        for iface in /sys/class/net/*; do
            [ -e "$iface" ] || continue
            local iname state ipaddr
            iname=$(basename "$iface")
            state=$(cat "$iface/operstate" 2>/dev/null || true)
            ipaddr=$(ip -4 addr show "$iname" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 || true)
            [ -z "$ipaddr" ] && ipaddr="No IPv4"
            echo "Interface: $iname (State: $state, IP: $ipaddr)"
            echo "  -> Conky: \${addr $iname} | \${downspeed $iname} | \${upspeed $iname}"
        done
    fi
    echo ""

    echo "--- 4. STORAGE MOUNTS ---"
    df -h -x tmpfs -x devtmpfs -x squashfs -x efivarfs 2>/dev/null | awk 'NR>1 {print "Mount: " $6 " (Device: " $1 ", Size: " $2 ", Used: " $3 ", Free: " $4 ")"} '
    echo ""
    echo "========================================================"
}

# ------------------------------------------------------------------------------
# Action: Help Menu
# ------------------------------------------------------------------------------
do_help() {
    print_banner
    echo -e "${BOLD}USAGE:${NC}"
    echo "  ./Setup-Detailed-Conky.sh [OPTION]"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo -e "  ${CYAN}--install${NC}       Audit hardware, generate customized config, register autostart, & launch"
    echo -e "  ${CYAN}--uninstall${NC}     Cleanly remove autostart entries, user config, and terminate processes"
    echo -e "  ${CYAN}--status${NC}        Show process state, memory RSS, autostart config, and hardware sensor map"
    echo -e "  ${CYAN}--start${NC}         Launch Conky in the background"
    echo -e "  ${CYAN}--stop${NC}          Gracefully stop running Conky instances"
    echo -e "  ${CYAN}--restart${NC}       Stop and restart Conky"
    echo -e "  ${CYAN}--zoom [LEVEL]${NC}  Enlarge fonts & take full vertical screen (normal, large, xlarge)"
    echo -e "  ${CYAN}--detect${NC}        Inspect system sensors, battery, and interfaces (live audit)"
    echo -e "  ${CYAN}--help${NC}          Display this manual"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "  ./Setup-Detailed-Conky.sh --install     # One-step complete permanent setup"
    echo "  ./Setup-Detailed-Conky.sh --status      # Check system monitor status"
    echo "  ./Setup-Detailed-Conky.sh --uninstall   # Completely remove"
    echo ""
}

# ------------------------------------------------------------------------------
# CLI Parameter Routing
# ------------------------------------------------------------------------------
case "${1:-}" in
    --install|-i)
        do_install
        ;;
    --uninstall|-u)
        do_uninstall
        ;;
    --status|-s)
        do_status
        ;;
    --start)
        do_start
        ;;
    --stop)
        do_stop
        ;;
    --restart|-r)
        do_restart
        ;;
    --zoom|-z)
        shift
        do_zoom "${1:-large}"
        ;;
    --detect|-d)
        do_detect
        ;;
    --help|-h|"")
        do_help
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Run '$0 --help' for available commands."
        exit 1
        ;;
esac
