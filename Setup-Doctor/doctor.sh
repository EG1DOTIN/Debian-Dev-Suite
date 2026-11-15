#!/usr/bin/env bash
#
# doctor.sh — System Diagnostic & Debian-Dev-Suite Health Audit
#
# Audits:
#   1. OS, Kernel & Init System (systemd vs SysVinit)
#   2. Hardware Capabilities: CPU Cores, Vector Instructions (AVX, AVX2, AVX-512)
#   3. Memory: Total RAM, Free RAM, Active Swap Partition
#   4. GPU Accelerators: NVIDIA drivers, CUDA nvcc, Vulkan loader, Intel/AMD
#   5. Motherboard CMOS & RTC Clock Status (detects Year 2008 battery reset bug)
#   6. Full Debian-Dev-Suite Module Verification (all suite modules)
#
# Usage:
#   ./doctor.sh
#   ./doctor.sh --help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_VERSION="$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null || cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "1.0.0")"

# Dynamic User & Target Home Lookup (Zero hardcoding, dual-root/user safe)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"

# ---------------------------------------------------------------------------
# Terminal Colors & Styling
# ---------------------------------------------------------------------------
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

TOTAL_CHECKS=0
PASSED_CHECKS=0
WARNING_CHECKS=0
FAILED_CHECKS=0

check_result() {
    local status="$1"
    local title="$2"
    local details="$3"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    case "$status" in
        PASS)
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            echo -e "  [${TICK}] ${BOLD}$title${RESET} : $details"
            ;;
        WARN)
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            echo -e "  [${WARN}] ${YELLOW}${BOLD}$title${RESET} : $details"
            ;;
        FAIL)
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            echo -e "  [${CROSS}] ${RED}${BOLD}$title${RESET} : $details"
            ;;
        INFO)
            echo -e "  [${INFO}] ${CYAN}${BOLD}$title${RESET} : $details"
            ;;
    esac
}

print_section() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${RESET}"
}

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo -e "${BOLD}${MAGENTA}Debian Dev Suite — Master Diagnostic Health Check${RESET}"
    echo
    echo -e "${BOLD}Usage:${RESET}"
    echo "  ./doctor.sh [OPTION]"
    echo
    echo -e "${BOLD}Options:${RESET}"
    echo "  (no arguments)       Run full master diagnostic audit of OS, hardware & modules"
    echo "  --help, -h           Display this help manual"
    echo
    echo -e "${BOLD}Description:${RESET}"
    echo "  Read-only hardware, GPU, memory, clock, and suite module verification."
    echo "  Requires 0 root privileges and makes zero system modifications."
    exit 0
fi

# ---------------------------------------------------------------------------
# Diagnostic Header
# ---------------------------------------------------------------------------
echo -e "${BOLD}${MAGENTA}"
echo "=================================================================="
echo "  Debian Dev Suite (v${SUITE_VERSION}) — Master Diagnostic Health Check"
echo "=================================================================="
echo -e "${RESET}"

# ---------------------------------------------------------------------------
# 1. Operating System & Init System
# ---------------------------------------------------------------------------
print_section "1. Operating System & Environment"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="${PRETTY_NAME:-$NAME}"
    check_result "PASS" "Distribution" "$OS_NAME"
else
    check_result "WARN" "Distribution" "Generic Linux (/etc/os-release not found)"
fi

KERNEL_VER=$(uname -r)
ARCH=$(uname -m)
check_result "PASS" "Kernel & Arch" "$KERNEL_VER ($ARCH)"

# Init System Detection
if pidof systemd >/dev/null 2>&1 || [ -d /run/systemd/system ]; then
    check_result "PASS" "Init System" "systemd (Standard modern Linux services)"
elif [ -f /etc/init.d/rc ] || [ -d /etc/init.d ]; then
    check_result "PASS" "Init System" "SysVinit / OpenRC (antiX / MX Linux lightweight mode)"
else
    check_result "WARN" "Init System" "Unknown init daemon"
fi

# ---------------------------------------------------------------------------
# 2. Clock & CMOS Battery Health (Year 2008 Check)
# ---------------------------------------------------------------------------
print_section "2. System Clock & RTC Health"

CURRENT_YEAR=$(date +%Y)
CURRENT_DATE=$(date "+%Y-%m-%d %H:%M:%S %Z")

if [ "$CURRENT_YEAR" -lt 2024 ]; then
    check_result "FAIL" "Clock Health" "CLOCK RESET DETECTED! Year is $CURRENT_YEAR ($CURRENT_DATE). CMOS battery is dead or RTC lost power. Run: sudo Setup-Sync-Time/sync-time.sh"
else
    check_result "PASS" "Clock Health" "Accurate ($CURRENT_DATE)"
fi

# ---------------------------------------------------------------------------
# 3. Hardware Inspection (CPU, Vector Instructions, RAM, Swap)
# ---------------------------------------------------------------------------
print_section "3. Processor & Memory"

CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//' || echo "x86_64 CPU")
CPU_CORES=$(nproc 2>/dev/null || echo 1)
check_result "PASS" "Processor" "$CPU_MODEL ($CPU_CORES cores)"

# Vector & Cryptographic Extensions
CPU_FLAGS=$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null || true)
VECTOR_EXTS=""
if echo "$CPU_FLAGS" | grep -qw "avx512f"; then VECTOR_EXTS="$VECTOR_EXTS AVX-512"; fi
if echo "$CPU_FLAGS" | grep -qw "avx2"; then VECTOR_EXTS="$VECTOR_EXTS AVX2"; fi
if echo "$CPU_FLAGS" | grep -qw "avx"; then VECTOR_EXTS="$VECTOR_EXTS AVX"; fi
if echo "$CPU_FLAGS" | grep -qw "sse4_2"; then VECTOR_EXTS="$VECTOR_EXTS SSE4.2"; fi
if echo "$CPU_FLAGS" | grep -qw "aes"; then VECTOR_EXTS="$VECTOR_EXTS AES-NI"; fi
if echo "$CPU_FLAGS" | grep -qw "pclmulqdq" || echo "$CPU_FLAGS" | grep -qw "pclmul"; then VECTOR_EXTS="$VECTOR_EXTS PCLMUL"; fi

if [ -n "$VECTOR_EXTS" ]; then
    check_result "PASS" "Vector Instructions" "$VECTOR_EXTS"
else
    check_result "WARN" "Vector Instructions" "Legacy CPU (SSE2/SSSE3 only). Lacks AVX/SSE4.2 (Use Setup-LLAMA-CPP-LEGACY for local AI)."
fi

# RAM & Swap
TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 0)
TOTAL_RAM_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_RAM_MB / 1024}")
SWAP_MB=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}' || echo 0)

if [ "$TOTAL_RAM_MB" -ge 7000 ]; then
    check_result "PASS" "Physical RAM" "${TOTAL_RAM_GB} GB (${TOTAL_RAM_MB} MB) — High capacity (Great for 7B/8B LLMs)"
elif [ "$TOTAL_RAM_MB" -ge 3500 ]; then
    check_result "PASS" "Physical RAM" "${TOTAL_RAM_GB} GB (${TOTAL_RAM_MB} MB) — Standard capacity (Ideal for 1.5B–3B LLMs)"
else
    check_result "WARN" "Physical RAM" "${TOTAL_RAM_GB} GB (${TOTAL_RAM_MB} MB) — Low-memory PC (Use Setup-LLAMA-CPP-LEGACY with 0.5B model)"
fi

if [ "$SWAP_MB" -gt 512 ]; then
    check_result "PASS" "Swap Space" "${SWAP_MB} MB active"
else
    check_result "WARN" "Swap Space" "${SWAP_MB} MB — Low or no swap detected. Compilation or large models may trigger OOM."
fi

# ---------------------------------------------------------------------------
# 4. Graphics & Hardware Acceleration
# ---------------------------------------------------------------------------
print_section "4. GPU & Acceleration Backends"

HAS_NVIDIA=false
if command -v nvidia-smi >/dev/null 2>&1; then
    HAS_NVIDIA=true
    NVIDIA_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "NVIDIA GPU")
    NVIDIA_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -n1 || echo "Unknown VRAM")
    check_result "PASS" "NVIDIA Driver" "$NVIDIA_NAME ($NVIDIA_VRAM via nvidia-smi)"
elif lspci 2>/dev/null | grep -i "vga\|3d" | grep -iq "nvidia"; then
    check_result "WARN" "NVIDIA Hardware" "NVIDIA GPU detected, but proprietary driver/nvidia-smi is NOT loaded. Run MX Nvidia Driver Installer or install nvidia-driver."
else
    check_result "INFO" "NVIDIA GPU" "No NVIDIA GPU detected"
fi

if command -v nvcc >/dev/null 2>&1; then
    NVCC_VER=$(nvcc --version 2>/dev/null | grep -o 'release [0-9.]*' | cut -d' ' -f2 || echo "Available")
    check_result "PASS" "CUDA Toolkit" "nvcc compiler present (v$NVCC_VER)"
else
    check_result "INFO" "CUDA Toolkit" "nvcc not installed (Optional: Vulkan can be used without full CUDA toolkit)"
fi

if command -v vulkaninfo >/dev/null 2>&1 || dpkg -s libvulkan1 >/dev/null 2>&1; then
    check_result "PASS" "Vulkan API" "Vulkan runtime / loader available"
else
    check_result "INFO" "Vulkan API" "Vulkan packages not detected (apt install libvulkan1 libvulkan-dev)"
fi

# ---------------------------------------------------------------------------
# 5. Debian Dev Suite Modules Audit
# ---------------------------------------------------------------------------
print_section "5. Debian-Dev-Suite Modules Verification"

# 1. Setup-LLAMA-CPP
if [ -x "$TARGET_HOME/llama.cpp/build/bin/llama-cli" ]; then
    MODEL_COUNT=$(find "$TARGET_HOME/models" -maxdepth 2 -type f -name "*.gguf" 2>/dev/null | wc -l || echo 0)
    check_result "PASS" "Setup-LLAMA-CPP" "Installed at ~/llama.cpp ($MODEL_COUNT .gguf models in ~/models)"
else
    check_result "INFO" "Setup-LLAMA-CPP" "Not installed (cd Setup-LLAMA-CPP or Setup-LLAMA-CPP-LEGACY && ./setup-LLAMA.CPP.sh --install)"
fi

# 2. Setup-Dev-Tools
DEV_TOOLS_INSTALLED=0
for tool in rg fzf eza zoxide lazygit uv fnm docker lazydocker ai; do
    if command -v "$tool" >/dev/null 2>&1 || [ -x "$TARGET_HOME/.local/bin/$tool" ]; then
        DEV_TOOLS_INSTALLED=$((DEV_TOOLS_INSTALLED + 1))
    fi
done
# Check bat / batcat (Debian packages bat as batcat)
if command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1 || [ -x "$TARGET_HOME/.local/bin/bat" ]; then
    DEV_TOOLS_INSTALLED=$((DEV_TOOLS_INSTALLED + 1))
fi

if [ "$DEV_TOOLS_INSTALLED" -ge 8 ]; then
    check_result "PASS" "Setup-Dev-Tools" "$DEV_TOOLS_INSTALLED/11 tools active (CLI tools, Git, Runtimes, AI Copilot)"
elif [ "$DEV_TOOLS_INSTALLED" -gt 0 ]; then
    check_result "WARN" "Setup-Dev-Tools" "Partially installed ($DEV_TOOLS_INSTALLED/11 tools active)"
else
    check_result "INFO" "Setup-Dev-Tools" "Not installed (cd Setup-Dev-Tools && ./setup-dev-tools.sh --install)"
fi

# 3. Setup-Tmux
if command -v tmux >/dev/null 2>&1 && [ -f "$TARGET_HOME/.tmux.conf" ]; then
    check_result "PASS" "Setup-Tmux" "Installed with ~/.tmux.conf configured"
elif command -v tmux >/dev/null 2>&1; then
    check_result "WARN" "Setup-Tmux" "tmux installed, but ~/.tmux.conf not configured"
else
    check_result "INFO" "Setup-Tmux" "Not installed (cd Setup-Tmux && ./setup-tmux.sh --install)"
fi

# 4. Setup-GDrive
if command -v rclone >/dev/null 2>&1; then
    if mountpoint -q "$TARGET_HOME/GoogleDrive" 2>/dev/null; then
        check_result "PASS" "Setup-GDrive" "Active & mounted at ~/GoogleDrive"
    else
        check_result "WARN" "Setup-GDrive" "Rclone installed, but ~/GoogleDrive is not currently mounted"
    fi
else
    check_result "INFO" "Setup-GDrive" "Not installed (cd Setup-GDrive && ./setup-GoogleDrive.sh --install)"
fi

# 5. Setup-Geany
if command -v geany >/dev/null 2>&1; then
    THEME_COUNT=$(find "$TARGET_HOME/.config/geany/colorschemes" -type f 2>/dev/null | wc -l || echo 0)
    check_result "PASS" "Setup-Geany" "Installed ($THEME_COUNT dark themes detected)"
else
    check_result "INFO" "Setup-Geany" "Not installed (cd Setup-Geany && ./setup-geany.sh --install)"
fi

# 6. Setup-MD-Viewer
if command -v md-viewer >/dev/null 2>&1 || [ -x "$TARGET_HOME/.local/bin/md-viewer" ]; then
    check_result "PASS" "Setup-MD-Viewer" "Active (Pandoc + Surf WebKitGTK)"
else
    check_result "INFO" "Setup-MD-Viewer" "Not installed (cd Setup-MD-Viewer && ./setup-md-viewer.sh --install)"
fi

# 7. Setup-Sync-Time
if command -v sync-time >/dev/null 2>&1 || [ -x "/usr/local/bin/sync-time" ]; then
    check_result "PASS" "Setup-Sync-Time" "Global sync-time utility installed"
else
    check_result "INFO" "Setup-Sync-Time" "Available in Setup-Sync-Time/sync-time.sh"
fi

# 8. Setup-Config-Sync
if [ -d "$TARGET_HOME/Debian-Dev-Backups" ] || [ -d "$TARGET_HOME/GoogleDrive/Debian-Dev-Backups" ]; then
    LOCAL_BACKUPS=$(find "$TARGET_HOME/Debian-Dev-Backups" -type f 2>/dev/null | wc -l || echo 0)
    check_result "PASS" "Setup-Config-Sync" "Active ($LOCAL_BACKUPS local backup archives found)"
else
    check_result "INFO" "Setup-Config-Sync" "Available in Setup-Config-Sync/backup-dev-configs.sh"
fi

# 9. Setup-Local-GitHub
if curl -s -f -o /dev/null "http://127.0.0.1:3000/" 2>/dev/null; then
    check_result "PASS" "Setup-Local-GitHub" "Active & running on http://127.0.0.1:3000"
elif [ -d "$TARGET_HOME/.local/share/dev-setups/forgejo" ] || [ -d "$TARGET_HOME/forgejo-data" ] || [ -d "$SCRIPT_DIR/../Setup-Local-GitHub/forgejo-data" ]; then
    check_result "INFO" "Setup-Local-GitHub" "Configured & ready (currently stopped, start via: ./Setup-Local-GitHub/forgejo-localhost.sh start)"
else
    check_result "INFO" "Setup-Local-GitHub" "Available in Setup-Local-GitHub/forgejo-localhost.sh"
fi

# 10. Setup-Virtual-Box
if command -v VirtualBox >/dev/null 2>&1 || command -v virtualbox >/dev/null 2>&1; then
    VBOX_VER=$(VBoxManage --version 2>/dev/null | grep -E '^[0-9]' | cut -d'r' -f1 | head -n1 || echo "installed")
    [ -n "$VBOX_VER" ] || VBOX_VER="installed"
    check_result "PASS" "Setup-Virtual-Box" "VirtualBox ($VBOX_VER) installed with GUI"
else
    check_result "INFO" "Setup-Virtual-Box" "Available in Setup-Virtual-Box/setup_virtualbox_secure.sh"
fi

# 11. Setup-Hinglish
EASY_HINDI_SCRIPT="$SCRIPT_DIR/../Setup-Hinglish/easy-hindi-typing.sh"
if [ -f "/usr/share/m17n/hi-itrans.mim" ] && command -v ibus >/dev/null 2>&1; then
    check_result "PASS" "Setup-Hinglish" "Active (IBus + GNU m17n table + Easy Hindi Typing localhost app)"
elif [ -f "$TARGET_HOME/.local/bin/hinglish-launch" ] || [ -f "$TARGET_HOME/.local/bin/hinglish-pad" ] || [ -x "$EASY_HINDI_SCRIPT" ]; then
    check_result "PASS" "Setup-Hinglish" "Configured (Easy Hindi Typing localhost app + dedicated launchers)"
else
    check_result "INFO" "Setup-Hinglish" "Available in Setup-Hinglish/hinglish-to-hindi-typing.sh"
fi

# 12. Setup-Brightness
if command -v brightness-controller >/dev/null 2>&1 || [ -x "$TARGET_HOME/.local/bin/brightness-controller" ] || [ -x "$SCRIPT_DIR/../Setup-Brightness/brightness-controller" ] || [ -x "$SCRIPT_DIR/../Setup-Brightness/brightness-controller.py" ]; then
    check_result "PASS" "Setup-Brightness" "Active (Standalone GUI/CLI + X11 RandR + Hardware Backlight)"
else
    check_result "INFO" "Setup-Brightness" "Available in Setup-Brightness/setup-brightness.sh"
fi

# 13. Setup-Deep-Sleep
if ([ -f "/sys/power/mem_sleep" ] && grep -q "\[deep\]" "/sys/power/mem_sleep") || ([ -f "/etc/default/grub" ] && grep -q "mem_sleep_default=deep" "/etc/default/grub"); then
    check_result "PASS" "Setup-Deep-Sleep" "Active (Kernel S3 deep sleep + TLP battery management)"
elif command -v tlp >/dev/null 2>&1; then
    check_result "PASS" "Setup-Deep-Sleep" "TLP battery management active (S3 sleep available via setup-deep-sleep.sh)"
else
    check_result "INFO" "Setup-Deep-Sleep" "Available in Setup-Deep-Sleep/setup-deep-sleep.sh"
fi

# 14. Setup-Libre-Chat
if curl -s -m 1 "http://127.0.0.1:3080" >/dev/null 2>&1 || (command -v ss >/dev/null 2>&1 && ss -tulpn 2>/dev/null | grep -q ":3080\b"); then
    check_result "PASS" "Setup-Libre-Chat" "Active & running on http://127.0.0.1:3080 (0 Telemetry, Local AI)"
elif command -v docker >/dev/null 2>&1 && docker ps --filter "name=librechat_app" --filter "status=running" 2>/dev/null | grep -q librechat_app; then
    check_result "PASS" "Setup-Libre-Chat" "Containers active (Initializing / Ready on http://127.0.0.1:3080)"
elif [ -d "$TARGET_HOME/.local/share/dev-setups/librechat" ] || [ -f "$SCRIPT_DIR/../Setup-Libre-Chat/.env" ] || [ -d "$SCRIPT_DIR/../Setup-Libre-Chat/LibreChat" ] || [ -f "$SCRIPT_DIR/../Setup-Libre-Chat/docker-compose.yml" ]; then
    check_result "INFO" "Setup-Libre-Chat" "Configured & ready (currently stopped, start via: ./Setup-Libre-Chat/setup-librechat.sh --start)"
else
    check_result "INFO" "Setup-Libre-Chat" "Available in Setup-Libre-Chat/setup-librechat.sh"
fi

# 15. Setup-GUI-Manager
GUI_MGR_DIR="$SCRIPT_DIR/../Setup-GUI-Manager"
if [ -x "/usr/local/bin/debian-dev-manager" ] || [ -f "/usr/share/applications/debian-dev-manager.desktop" ]; then
    check_result "PASS" "Setup-GUI-Manager" "Installed with Desktop Integration (debian-dev-manager)"
elif [ -x "$SCRIPT_DIR/../.venv/bin/python3" ] && "$SCRIPT_DIR/../.venv/bin/python3" -c "import PySide6.QtWidgets" 2>/dev/null; then
    check_result "PASS" "Setup-GUI-Manager" "Ready (Shared root .venv with PySide6 Qt6 active, launch via ./manager.sh)"
elif [ -x "$GUI_MGR_DIR/.venv/bin/python3" ] && "$GUI_MGR_DIR/.venv/bin/python3" -c "import PySide6.QtWidgets" 2>/dev/null; then
    check_result "PASS" "Setup-GUI-Manager" "Ready (Isolated .venv with PySide6 Qt6 active, launch via ./manager.sh)"
elif python3 -c "import PySide6.QtWidgets" 2>/dev/null; then
    check_result "PASS" "Setup-GUI-Manager" "Ready (PySide6 Qt6 active, launch via ./manager.sh)"
elif [ -f "$GUI_MGR_DIR/setup-manager.py" ]; then
    check_result "INFO" "Setup-GUI-Manager" "Ready (Auto-initializes root .venv on first launch: ./manager.sh)"
else
    check_result "INFO" "Setup-GUI-Manager" "Available in Setup-GUI-Manager/setup-manager.sh"
fi

# 16. Setup-Detailed-Conkey
CONKY_DIR="$SCRIPT_DIR/../Setup-Detailed-Conkey"
if pgrep -x conky >/dev/null 2>&1 || pidof conky >/dev/null 2>&1; then
    check_result "PASS" "Setup-Detailed-Conkey" "Active & Running (Obsidian Dark Glass System Monitor)"
elif [ -f "$TARGET_HOME/.config/autostart/conky.desktop" ] || [ -f "$TARGET_HOME/.config/conky/conky.conf" ]; then
    check_result "PASS" "Setup-Detailed-Conkey" "Configured with Autostart (~/.config/conky/conky.conf)"
elif [ -x "$CONKY_DIR/Setup-Detailed-Conky.sh" ]; then
    check_result "INFO" "Setup-Detailed-Conkey" "Available in Setup-Detailed-Conkey/Setup-Detailed-Conky.sh"
fi

# ---------------------------------------------------------------------------
# Summary Dashboard
# ---------------------------------------------------------------------------
print_section "Summary Report"

echo -e "  Total Audited Items : ${BOLD}$TOTAL_CHECKS${RESET}"
echo -e "  Passed / Optimal    : ${GREEN}${BOLD}$PASSED_CHECKS${RESET}"
echo -e "  Warnings            : ${YELLOW}${BOLD}$WARNING_CHECKS${RESET}"
echo -e "  Failures            : ${RED}${BOLD}$FAILED_CHECKS${RESET}"
echo

if [ "$FAILED_CHECKS" -gt 0 ]; then
    echo -e "${RED}${BOLD}Action Required:${RESET} Critical issues detected (such as clock desync). Please review items marked with [✖]."
elif [ "$WARNING_CHECKS" -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}System Ready with Warnings:${RESET} Core items are functional. Review items marked with [⚠] for optimal performance."
else
    echo -e "${GREEN}${BOLD}Excellent!${RESET} Your Debian development environment is in top condition."
fi
echo
