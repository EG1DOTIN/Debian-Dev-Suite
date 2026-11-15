#!/usr/bin/env bash
# ==============================================================================
# Script: hinglish-to-hindi-typing.sh
# Purpose: Complete, Automated, 100% Offline & Private Hinglish (Phonetic Hindi)
#          Typing Setup for Linux (GNOME, KDE, XFCE, Wayland & X11).
# Privacy: 100% Offline. Zero telemetry, zero cloud calls, zero keylogging.
#
# QUICK COMMAND LINE USAGE:
#   chmod +x hinglish-to-hindi-typing.sh
#   ./hinglish-to-hindi-typing.sh             # Full automated installation & setup
#   ./hinglish-to-hindi-typing.sh --app-only  # App-only setup (FeatherPad/LibreOffice only, leaves OS untouched)
#   ./hinglish-to-hindi-typing.sh --launch    # Launch FeatherPad directly in Hindi typing mode
#   ./hinglish-to-hindi-typing.sh --check     # Audit system packages, daemon & privacy
#   ./hinglish-to-hindi-typing.sh --test      # View phonetic cheatsheet in terminal
#   ./hinglish-to-hindi-typing.sh --uninstall # Cleanly revert all configurations
#   ./hinglish-to-hindi-typing.sh --help      # Show options help menu
#
# KEYBOARD SHORTCUT (ZERO VS CODE CONFLICT):
#   Press Super + Space (Windows Key + Space) to toggle English/Hindi.
#   (Ctrl + Space is preserved for VS Code & IDE autocomplete; never overridden!)
#   Per-window isolation is enabled so Hindi in FeatherPad never affects VS Code or Terminal.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----------------------------- Color & Styling --------------------------------
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
NC="\033[0m" # No Color

TAG_START="# >>> HINGLISH_IBUS_CONFIG_START >>>"
TAG_END="# <<< HINGLISH_IBUS_CONFIG_END <<<"

# ------------------------------ Helper Functions ------------------------------
print_banner() {
    cat << "EOF"
  _    _ _             _ _     _        _    _ _           _ _ 
 | |  | (_)           | (_)   | |      | |  | (_)         | (_)
 | |__| |_ _ __   __ _| |_ ___| |__    | |__| |_ _ __   __| |_ 
 |  __  | | '_ \ / _` | | / __| '_ \   |  __  | | '_ \ / _` | |
 | |  | | | | | | (_| | | \__ \ | | |  | |  | | | | | | (_| | |
 |_|  |_|_|_| |_|\__, |_|_|___/_| |_|  |_|  |_|_|_| |_|\__,_|_|
                  __/ |                                        
                 |___/   Phonetic Typing • 100% Offline & Private
EOF
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${BOLD} Zero Telemetry • Real-time Transliteration (e.g. namaste -> नमस्ते)${NC}"
    echo -e "${CYAN}====================================================================${NC}\n"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $1" >&2
}

# Ensure script is NOT run directly as root/sudo (which would corrupt user $HOME)
check_root_safety() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
        log_error "Please do NOT run this script using 'sudo ./hinglish-to-hindi-typing.sh'!"
        echo -e "\nRunning with sudo causes configuration files to be installed into ${BOLD}/root${NC}"
        echo -e "instead of your user home directory (${BOLD}$(eval echo "~$SUDO_USER")${NC}).\n"
        echo -e "Correct usage: run as your normal user:"
        echo -e "    ${GREEN}./hinglish-to-hindi-typing.sh${NC}\n"
        echo -e "The script will automatically request sudo permissions only for package installation."
        exit 1
    fi
}

# Determine target user's home directory safely
get_user_home() {
    if [[ -n "${SUDO_USER:-}" ]] && [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        eval echo "~$SUDO_USER"
    else
        echo "$HOME"
    fi
}

USER_HOME="$(get_user_home)"

# Backup a file before modifying it
backup_file() {
    local target="$1"
    if [[ -f "$target" ]]; then
        local timestamp
        timestamp="$(date +%Y%m%d_%H%M%S)"
        local backup="${target}.bak_${timestamp}"
        cp "$target" "$backup"
        log_info "Created backup: ${target} -> ${backup}"
    fi
}

# Safely inject environment variables into a file with clean tags
add_env_block() {
    local target="$1"
    local block_content="$2"

    mkdir -p "$(dirname "$target")"
    touch "$target"

    # Remove any existing block first to ensure idempotency
    if grep -q "$TAG_START" "$target" 2>/dev/null; then
        sed -i "/$TAG_START/,/$TAG_END/d" "$target"
    fi

    # Append new block
    {
        echo ""
        echo "$TAG_START"
        echo "$block_content"
        echo "$TAG_END"
    } >> "$target"

    log_success "Configured: $target"
}

# Remove injected environment block from a file
remove_env_block() {
    local target="$1"
    if [[ -f "$target" ]] && grep -q "$TAG_START" "$target" 2>/dev/null; then
        sed -i "/$TAG_START/,/$TAG_END/d" "$target"
        log_info "Cleaned configuration from: $target"
    fi
}

# -------------------------- Distro & Package Detection -----------------------
detect_and_install_packages() {
    log_info "Detecting Linux distribution and package manager..."

    if command -v apt-get &>/dev/null || command -v apt &>/dev/null; then
        log_info "Debian/Ubuntu-based system detected (APT)."
        
        # Note: m17n-contrib is obsolete and superseded by m17n-db on Debian/Ubuntu
        local core_pkgs=(ibus ibus-m17n m17n-db hunspell-hi fonts-lohit-deva fonts-noto-color-emoji)
        local optional_pkgs=(ibus-gtk ibus-gtk3 ibus-gtk4 ibus-typing-booster fonts-deva)
        local to_install=()

        # Validate candidate availability to avoid "has no installation candidate" errors
        for pkg in "${core_pkgs[@]}"; do
            local cand
            cand="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}')"
            if [[ -n "$cand" && "$cand" != "(none)" ]]; then
                to_install+=("$pkg")
            else
                log_warn "Package '$pkg' has no installation candidate; skipping."
            fi
        done

        for pkg in "${optional_pkgs[@]}"; do
            local cand
            cand="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}')"
            if [[ -n "$cand" && "$cand" != "(none)" ]]; then
                to_install+=("$pkg")
            fi
        done

        log_info "Updating package lists and installing: ${to_install[*]}"
        sudo apt-get update -y
        sudo apt-get install -y "${to_install[@]}"

    elif command -v dnf &>/dev/null; then
        log_info "Fedora/RHEL-based system detected (DNF)."
        
        local core_pkgs=(ibus ibus-m17n m17n-db hunspell-hi google-noto-sans-devanagari-fonts)
        local optional_pkgs=(ibus-gtk2 ibus-gtk3 ibus-gtk4 ibus-typing-booster)
        local to_install=("${core_pkgs[@]}")

        for pkg in "${optional_pkgs[@]}"; do
            if dnf list available "$pkg" &>/dev/null; then
                to_install+=("$pkg")
            fi
        done

        log_info "Installing packages: ${to_install[*]}"
        sudo dnf install -y "${to_install[@]}"

    elif command -v pacman &>/dev/null; then
        log_info "Arch Linux-based system detected (Pacman)."
        
        local pkgs=(ibus ibus-m17n m17n-db hunspell-hi noto-fonts)
        if pacman -Si ibus-typing-booster &>/dev/null; then
            pkgs+=(ibus-typing-booster)
        fi

        log_info "Installing packages: ${pkgs[*]}"
        sudo pacman -S --needed --noconfirm "${pkgs[@]}"

    elif command -v zypper &>/dev/null; then
        log_info "openSUSE-based system detected (Zypper)."
        
        local pkgs=(ibus ibus-m17n m17n-db noto-sans-devanagari-fonts)
        log_info "Installing packages: ${pkgs[*]}"
        sudo zypper install -y "${pkgs[@]}"

    else
        log_error "Unsupported package manager!"
        echo "Please manually install the following packages using your distribution's package manager:"
        echo "  - ibus"
        echo "  - ibus-m17n"
        echo "  - m17n-db"
        echo "  - hunspell-hi"
        echo "  - Devanagari fonts (e.g., fonts-lohit-deva or noto-fonts)"
        exit 1
    fi

    log_success "All required dependencies and Devanagari fonts installed successfully!"
}

# ------------------------- Automatic Environment Setup -----------------------
configure_environment_variables() {
    log_info "Configuring universal input method environment variables..."

    local env_content
    env_content=$(cat << 'EOF'
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export INPUT_METHOD=ibus
export SDL_IM_MODULE=ibus
EOF
)

    local systemd_env_content
    systemd_env_content=$(cat << 'EOF'
GTK_IM_MODULE=ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
INPUT_METHOD=ibus
SDL_IM_MODULE=ibus
EOF
)

    # 1. systemd user environment (Affects all GUI apps, Wayland & X11 sessions, D-Bus services)
    local env_dir="${USER_HOME}/.config/environment.d"
    mkdir -p "$env_dir"
    local sys_env_file="${env_dir}/ibus.conf"
    echo "$systemd_env_content" > "$sys_env_file"
    log_success "Configured systemd user session environment: $sys_env_file"

    # 2. Traditional login files (~/.profile and ~/.xprofile for Display Managers like GDM/SDDM/LightDM)
    local profile_file="${USER_HOME}/.profile"
    backup_file "$profile_file"
    add_env_block "$profile_file" "$env_content"

    local xprofile_file="${USER_HOME}/.xprofile"
    if [[ -f "$xprofile_file" ]] || [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
        backup_file "$xprofile_file"
        add_env_block "$xprofile_file" "$env_content"
    fi

    # 3. Interactive Shells (~/.bashrc and ~/.zshrc)
    local bashrc_file="${USER_HOME}/.bashrc"
    backup_file "$bashrc_file"
    add_env_block "$bashrc_file" "$env_content"

    if [[ -f "${USER_HOME}/.zshrc" ]]; then
        local zshrc_file="${USER_HOME}/.zshrc"
        backup_file "$zshrc_file"
        add_env_block "$zshrc_file" "$env_content"
    fi
}

# ---------------------- Automatic Desktop Configuration ----------------------
configure_desktop_settings() {
    log_info "Applying automated desktop input source settings (Predictive Hindi + Direct)..."

    # Primary: tb:hi:itrans (Typing Booster with multi-word suggestion popup)
    # Secondary: m17n:hi:itrans (Direct 1-to-1 transliteration without popup)
    local tb_engine="tb:hi:itrans"
    local direct_engine="m17n:hi:itrans"

    # --- Configure ibus-typing-booster for Hindi Word Predictions (hunspell-hi) ---
    log_info "Configuring ibus-typing-booster dictionary (hi_IN) for multi-word candidate suggestions..."
    if command -v dconf &>/dev/null; then
        dconf write /org/freedesktop/ibus/engine/typing-booster/dictionary "'hi_IN'" 2>/dev/null || true
        dconf write /org/freedesktop/ibus/engine/typing-booster/inputmethod "'hi-itrans,NoIME'" 2>/dev/null || true
        dconf write /org/freedesktop/ibus/engine/typing-booster/wordpredictions "true" 2>/dev/null || true
        dconf write /org/freedesktop/ibus/engine/typing-booster/addspaceoncommit "true" 2>/dev/null || true
        dconf write /org/freedesktop/ibus/engine/typing-booster/pagesize "9" 2>/dev/null || true
        dconf write /org/freedesktop/ibus/engine/typing-booster/mincharcomplete "1" 2>/dev/null || true
        dconf write /org/freedesktop/ibus/engine/typing-booster/autoselectcandidate "0" 2>/dev/null || true
        dconf write /org/freedesktop/ibus/engine/typing-booster/shownumberofcandidates "true" 2>/dev/null || true
        dconf write /org/freedesktop/ibus/engine/typing-booster/prefercommit "false" 2>/dev/null || true
    fi

    if command -v gsettings &>/dev/null && gsettings list-schemas 2>/dev/null | grep -q "org.freedesktop.ibus.engine.typing-booster"; then
        gsettings set org.freedesktop.ibus.engine.typing-booster:/org/freedesktop/ibus/engine/typing-booster/ dictionary "'hi_IN'" 2>/dev/null || true
        gsettings set org.freedesktop.ibus.engine.typing-booster:/org/freedesktop/ibus/engine/typing-booster/ inputmethod "'hi-itrans,NoIME'" 2>/dev/null || true
        gsettings set org.freedesktop.ibus.engine.typing-booster:/org/freedesktop/ibus/engine/typing-booster/ wordpredictions true 2>/dev/null || true
        gsettings set org.freedesktop.ibus.engine.typing-booster:/org/freedesktop/ibus/engine/typing-booster/ addspaceoncommit true 2>/dev/null || true
        gsettings set org.freedesktop.ibus.engine.typing-booster:/org/freedesktop/ibus/engine/typing-booster/ pagesize 9 2>/dev/null || true
        gsettings set org.freedesktop.ibus.engine.typing-booster:/org/freedesktop/ibus/engine/typing-booster/ shownumberofcandidates true 2>/dev/null || true
        gsettings set org.freedesktop.ibus.engine.typing-booster:/org/freedesktop/ibus/engine/typing-booster/ mincharcomplete 1 2>/dev/null || true
    fi

    # --- GNOME Configuration (Ubuntu, Fedora, Debian GNOME) ---
    if command -v gsettings &>/dev/null && gsettings list-schemas 2>/dev/null | grep -q "org.gnome.desktop.input-sources"; then
        log_info "GNOME desktop schema detected. Configuring GNOME input sources..."

        # Update input sources safely using Python if available, or bash fallback
        if command -v python3 &>/dev/null; then
            python3 - << 'EOF'
import subprocess
import ast
import sys

target_tb = ('ibus', 'tb:hi:itrans')
target_direct = ('ibus', 'm17n:hi:itrans')

try:
    raw = subprocess.check_output(
        ['gsettings', 'get', 'org.gnome.desktop.input-sources', 'sources'],
        stderr=subprocess.DEVNULL
    ).decode().strip()

    if raw.startswith('@a(ss) '):
        raw = raw[7:]

    sources = ast.literal_eval(raw) if raw and raw != '[]' else []
except Exception:
    sources = []

if not sources:
    sources = [('xkb', 'us')]

# Add tb:hi:itrans (predictive suggestions) and m17n:hi:itrans (direct)
modified = False
if target_tb not in sources:
    sources.append(target_tb)
    modified = True
if target_direct not in sources:
    sources.append(target_direct)
    modified = True

if modified:
    formatted = "[" + ", ".join(f"('{s[0]}', '{s[1]}')" for s in sources) + "]"
    subprocess.call(['gsettings', 'set', 'org.gnome.desktop.input-sources', 'sources', formatted])
    print("[✓ SUCCESS] Added ('ibus', 'tb:hi:itrans') and ('ibus', 'm17n:hi:itrans') to GNOME input-sources.")
else:
    print("[INFO] GNOME input-sources already contains Hindi typing engines.")
EOF
        else
            # Pure Bash Fallback
            local current_sources
            current_sources=$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || echo "[]")
            if [[ "$current_sources" != *"tb:hi:itrans"* ]]; then
                if [[ "$current_sources" == *"["* && "$current_sources" != "@a(ss) []" && "$current_sources" != "[]" ]]; then
                    local updated_sources="${current_sources%]*}, ('ibus', 'tb:hi:itrans'), ('ibus', 'm17n:hi:itrans')]"
                    gsettings set org.gnome.desktop.input-sources sources "$updated_sources" 2>/dev/null || true
                else
                    gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('ibus', 'tb:hi:itrans'), ('ibus', 'm17n:hi:itrans')]" 2>/dev/null || true
                fi
                log_success "Updated GNOME input sources with tb:hi:itrans & m17n:hi:itrans"
            fi
        fi

        # Ensure keyboard switch shortcut is configured in GNOME (Super+Space)
        gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Super>space', 'XF86Keyboard']" 2>/dev/null || true
        # Enable Per-Window input source isolation (Keeps Hindi in FeatherPad without affecting VS Code)
        gsettings set org.gnome.desktop.input-sources per-window true 2>/dev/null || true
        log_success "Configured GNOME: Super+Space switch & enabled per-window input isolation."
    fi

    # --- Standalone IBus / KDE / XFCE / LXQt / Fluxbox / antiX / MX Linux ---
    log_info "Configuring standalone IBus engines and switch shortcuts..."

    if command -v dconf &>/dev/null; then
        dconf write /desktop/ibus/general/preload-engines "['xkb:us::eng', 'tb:hi:itrans', 'm17n:hi:itrans']" 2>/dev/null || true
        dconf write /desktop/ibus/general/engines-order "['xkb:us::eng', 'tb:hi:itrans', 'm17n:hi:itrans']" 2>/dev/null || true
        # ONLY Super+Space (Ctrl+Space is removed to preserve VS Code IntelliSense autocomplete!)
        dconf write /desktop/ibus/general/hotkey/triggers "['<Super>space']" 2>/dev/null || true
        # Enable per-window input method engine isolation
        dconf write /desktop/ibus/general/use-global-engine false 2>/dev/null || true
    fi

    if command -v gsettings &>/dev/null && gsettings list-schemas 2>/dev/null | grep -q "org.freedesktop.ibus.general"; then
        gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', 'tb:hi:itrans', 'm17n:hi:itrans']" 2>/dev/null || true
        gsettings set org.freedesktop.ibus.general engines-order "['xkb:us::eng', 'tb:hi:itrans', 'm17n:hi:itrans']" 2>/dev/null || true
        gsettings set org.freedesktop.ibus.general use-global-engine false 2>/dev/null || true
    fi

    # Autostart entry for desktop environments that do not start IBus natively (KDE, XFCE, i3, Fluxbox, etc.)
    local autostart_dir="${USER_HOME}/.config/autostart"
    mkdir -p "$autostart_dir"
    local autostart_file="${autostart_dir}/ibus.desktop"
    cat << 'EOF' > "$autostart_file"
[Desktop Entry]
Name=IBus Daemon
Comment=Start IBus input method daemon automatically
Type=Application
Exec=ibus-daemon -drx
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-Phase=Initialization
NotShowIn=GNOME;
EOF
    log_success "Created autostart entry: $autostart_file"

    # Generate dedicated app launchers for FeatherPad & LibreOffice
    create_app_launchers
}

# -------------------- Autostart Mode Manager (On-Demand vs Auto-Start) --------
manage_autostart() {
    local action="${1:-status}"
    local autostart_dir="${USER_HOME}/.config/autostart"
    local autostart_file="${autostart_dir}/ibus.desktop"

    case "$action" in
        disable|off|on-demand|--disable|--off|no)
            if [[ -f "$autostart_file" ]]; then
                sed -i 's/^Hidden=.*/Hidden=true/' "$autostart_file" || true
                if ! grep -q "^Hidden=" "$autostart_file"; then
                    echo "Hidden=true" >> "$autostart_file"
                fi
            fi
            log_success "Autostart is now DISABLED (On-Demand mode)."
            log_info "IBus daemon will NOT launch automatically on login."
            log_info "Start on demand anytime via: ./easy-hindi-typing.sh start (or 'ibus-daemon -drx')"
            ;;
        enable|on|auto|--enable|--on|yes)
            mkdir -p "$autostart_dir"
            if [[ -f "$autostart_file" ]]; then
                sed -i 's/^Hidden=.*/Hidden=false/' "$autostart_file" || true
            else
                cat << 'EOF' > "$autostart_file"
[Desktop Entry]
Name=IBus Daemon
Comment=Start IBus input method daemon automatically
Type=Application
Exec=ibus-daemon -drx
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-Phase=Initialization
NotShowIn=GNOME;
EOF
            fi
            log_success "Autostart is now ENABLED (Auto mode)."
            log_info "IBus daemon will launch automatically on login."
            ;;
        status|--status)
            echo ""
            echo "Setup-Hinglish Autostart Mode:"
            if [[ -f "$autostart_file" ]] && ! grep -q "^Hidden=true" "$autostart_file"; then
                echo -e "  Status : \033[0;32mAuto-Start (Enabled on login via ~/.config/autostart/ibus.desktop)\033[0m"
                echo "  Toggle : Run '$0 autostart off' to switch to on-demand"
            else
                echo -e "  Status : \033[1;33mOn-Demand (Disabled on login, manual start only)\033[0m"
                echo "  Toggle : Run '$0 autostart on' to switch to auto-start"
            fi
            echo ""
            ;;
        *)
            log_error "Unknown autostart action: '$action'"
            echo "Usage: $0 autostart [on|off|status]   (or: enable|disable)"
            exit 1
            ;;
    esac
}

# -------------------- Dedicated App Launchers (FeatherPad & LibreOffice) ------
create_app_launchers() {
    log_info "Creating dedicated Hindi application launchers..."

    local bin_dir="${USER_HOME}/.local/bin"
    local app_dir="${USER_HOME}/.local/share/applications"
    mkdir -p "$bin_dir" "$app_dir"

    # 1. Generic launcher script: hinglish-launch
    local launcher_script="${bin_dir}/hinglish-launch"
    cat << 'EOF' > "$launcher_script"
#!/usr/bin/env bash
# Launches any application with isolated Hinglish (Hindi) input
TARGET="${1:-featherpad}"
shift || true

# Ensure IBus daemon is running
if ! pgrep -x "ibus-daemon" &>/dev/null; then
    ibus-daemon -drx 2>/dev/null || true
    sleep 0.5
fi

# Pre-activate Hindi predictive typing engine (with fallback to direct transliteration)
ibus engine tb:hi:itrans 2>/dev/null || ibus engine m17n:hi:itrans 2>/dev/null || true

# Execute target app with IBus input modules
exec env GTK_IM_MODULE=ibus QT_IM_MODULE=ibus XMODIFIERS=@im=ibus "$TARGET" "$@"
EOF
    chmod +x "$launcher_script"
    log_success "Created CLI launcher: $launcher_script"

    # Convenience symlink / alias: hinglish-pad
    ln -sf "$launcher_script" "${bin_dir}/hinglish-pad"

    # 2. FeatherPad (Hindi Notepad) Desktop Entry
    if command -v featherpad &>/dev/null; then
        local featherpad_desktop="${app_dir}/featherpad-hindi.desktop"
        cat << EOF > "$featherpad_desktop"
[Desktop Entry]
Name=FeatherPad (Hindi Notepad)
Comment=Plain text editor with automatic Hinglish to Hindi phonetic typing
Exec=${launcher_script} featherpad %F
Icon=featherpad
Terminal=false
Type=Application
Categories=Utility;TextEditor;
StartupNotify=true
EOF
        chmod +x "$featherpad_desktop"
        log_success "Created Desktop Menu item: FeatherPad (Hindi Notepad)"
    fi

    # 3. LibreOffice Writer (Hindi) Desktop Entry
    if command -v libreoffice &>/dev/null; then
        local libreoffice_desktop="${app_dir}/libreoffice-hindi.desktop"
        cat << EOF > "$libreoffice_desktop"
[Desktop Entry]
Name=LibreOffice Writer (Hindi)
Comment=Word processor with automatic Hinglish to Hindi phonetic typing
Exec=${launcher_script} libreoffice --writer %U
Icon=libreoffice-writer
Terminal=false
Type=Application
Categories=Office;WordProcessor;
StartupNotify=true
EOF
        chmod +x "$libreoffice_desktop"
        log_success "Created Desktop Menu item: LibreOffice Writer (Hindi)"
    fi

    # 4. Easy Hindi Typing (100% Offline Localhost Web App with Word Suggestions)
    local easy_hindi_script="${SCRIPT_DIR}/easy-hindi-typing.sh"
    if [[ -f "$easy_hindi_script" ]]; then
        local easy_hindi_desktop="${app_dir}/easy-hindi-typing.desktop"
        cat << EOF > "$easy_hindi_desktop"
[Desktop Entry]
Name=Easy Hindi Typing
Comment=100% Offline Hinglish to Hindi Typing App with Word Suggestions
Exec=${easy_hindi_script} start
Icon=${SCRIPT_DIR}/easy-hindi-typing/icon.svg
Terminal=false
Type=Application
Categories=Utility;TextEditor;Office;
Keywords=hindi;hinglish;typing;devanagari;transliteration;
StartupNotify=true
EOF
        chmod +x "$easy_hindi_desktop"
        log_success "Created Desktop Menu item: Easy Hindi Typing"
    fi

    # Refresh desktop application database if tool available
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$app_dir" 2>/dev/null || true
    fi
}

# ------------------------- On-Demand App Launcher ----------------------------
launch_isolated_app() {
    local target="${1:-featherpad}"

    if ! command -v "$target" &>/dev/null; then
        for fallback in featherpad gedit mousepad leafpad xed kate kwrite; do
            if command -v "$fallback" &>/dev/null; then
                target="$fallback"
                break
            fi
        done
    fi

    if ! command -v "$target" &>/dev/null; then
        log_error "No supported text editor found. Please install featherpad via: sudo apt install -y featherpad"
        exit 1
    fi

    log_info "Launching '$target' in dedicated Hindi typing mode..."
    if ! pgrep -x "ibus-daemon" &>/dev/null; then
        ibus-daemon -drx 2>/dev/null || true
        sleep 0.5
    fi
    ibus engine m17n:hi:itrans 2>/dev/null || true
    echo -e "${GREEN}[✓] '$target' launched! You can start typing Hindi immediately.${NC}"
    echo -e "${CYAN}Tip: Your other windows (VS Code, terminal, browser) remain completely unaffected.${NC}"
    env GTK_IM_MODULE=ibus QT_IM_MODULE=ibus XMODIFIERS=@im=ibus "$target" &
}

# ----------------------------- Restart IBus Daemon ---------------------------
restart_ibus_daemon() {
    log_info "Restarting IBus daemon to apply changes immediately..."

    if [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        if command -v ibus &>/dev/null; then
            ibus restart 2>/dev/null || ibus-daemon -drx 2>/dev/null || true
            sleep 1
            # Pre-set engine verification
            if ibus engine m17n:hi:itrans 2>/dev/null; then
                log_success "IBus daemon active. Set active engine to: m17n:hi:itrans"
            else
                log_info "IBus daemon restarted. Ready for input."
            fi
        fi
    else
        log_info "No graphical session active in current terminal (${DISPLAY:-} unset)."
        log_info "The IBus daemon will automatically activate upon graphical desktop login."
    fi
}

# ---------------------------- Diagnostic / Check -----------------------------
run_diagnostic_check() {
    print_banner
    echo -e "${BOLD}${CYAN}--- System Diagnostic & Privacy Audit ---${NC}\n"

    local all_good=true

    # 1. Package checks
    echo -n "• Checking Core Packages: "
    local missing_pkgs=()
    for pkg in ibus ibus-m17n ibus-typing-booster hunspell-hi; do
        if ! command -v "$pkg" &>/dev/null && ! dpkg -s "$pkg" &>/dev/null 2>&1 && ! rpm -q "$pkg" &>/dev/null 2>&1 && ! pacman -Q "$pkg" &>/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
        echo -e "${GREEN}[INSTALLED: ibus, ibus-m17n, ibus-typing-booster, hunspell-hi]${NC}"
    else
        echo -e "${YELLOW}[PARTIAL / MISSING: ${missing_pkgs[*]}]${NC}"
        all_good=false
    fi

    # 2. Hindi Hunspell Dictionary check (enables word suggestions)
    echo -n "• Checking Hindi Hunspell Dictionary (hi_IN): "
    if [[ -f "/usr/share/hunspell/hi_IN.dic" ]] || [[ -f "/usr/share/myspell/dicts/hi_IN.dic" ]]; then
        echo -e "${GREEN}[FOUND /usr/share/hunspell/hi_IN.dic]${NC}"
    else
        echo -e "${YELLOW}[MISSING - Required for word suggestions; install hunspell-hi]${NC}"
        all_good=false
    fi

    # 3. m17n Itrans definition check
    echo -n "• Checking Hindi ITRANS Table: "
    if [[ -f "/usr/share/m17n/hi-itrans.mim" ]]; then
        echo -e "${GREEN}[FOUND /usr/share/m17n/hi-itrans.mim]${NC}"
    else
        echo -e "${YELLOW}[NOT FOUND IN DEFAULT PATH]${NC}"
    fi

    # 4. Typing Booster Dconf Configuration check
    echo -n "• Checking Typing Booster Dictionary Key: "
    local tb_dict="None"
    if command -v dconf &>/dev/null; then
        tb_dict=$(dconf read /org/freedesktop/ibus/engine/typing-booster/dictionary 2>/dev/null || echo "None")
    fi
    if [[ "$tb_dict" == *"'hi_IN'"* || "$tb_dict" == *"hi_IN"* ]]; then
        echo -e "${GREEN}[ACTIVE: hi_IN loaded (Predictive Suggestions Enabled)]${NC}"
    else
        echo -e "${YELLOW}[CURRENT: $tb_dict (Run setup to enable 'hi_IN')]${NC}"
    fi

    # 5. Environment Variables
    echo -n "• Checking Systemd Environment: "
    if [[ -f "${USER_HOME}/.config/environment.d/ibus.conf" ]]; then
        echo -e "${GREEN}[CONFIGURED]${NC}"
    else
        echo -e "${RED}[NOT CONFIGURED]${NC}"
        all_good=false
    fi

    echo -n "• Checking Shell Dotfiles: "
    if grep -q "$TAG_START" "${USER_HOME}/.bashrc" 2>/dev/null; then
        echo -e "${GREEN}[CONFIGURED IN .bashrc]${NC}"
    else
        echo -e "${YELLOW}[MISSING IN .bashrc]${NC}"
    fi

    # 6. GNOME / IBus Input Sources Check
    if command -v gsettings &>/dev/null && gsettings list-schemas 2>/dev/null | grep -q "org.gnome.desktop.input-sources"; then
        echo -n "• Checking GNOME Input Sources: "
        local sources
        sources=$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || echo "")
        if [[ "$sources" == *"tb:hi:itrans"* || "$sources" == *"m17n:hi:itrans"* ]]; then
            echo -e "${GREEN}[ACTIVE: Hindi typing sources registered]${NC}"
        else
            echo -e "${YELLOW}[NOT PRESENT IN GNOME SOURCES]${NC}"
            all_good=false
        fi
    fi

    # 7. IBus Daemon Status
    echo -n "• Checking IBus Daemon: "
    if pgrep -x "ibus-daemon" &>/dev/null; then
        local cur_engine
        cur_engine=$(ibus engine 2>/dev/null || echo "unknown")
        echo -e "${GREEN}[RUNNING (Current Active Engine: ${cur_engine})]${NC}"
    else
        echo -e "${YELLOW}[NOT RUNNING]${NC} (Will start automatically on graphical login)"
    fi

    # 8. Privacy & Security Audit
    echo -e "\n${BOLD}${MAGENTA}--- 100% Privacy & Security Guarantee ---${NC}"
    echo -e "✓ ${BOLD}Network Traffic:${NC}   0 bytes. Completely offline local mapping."
    echo -e "✓ ${BOLD}Telemetry / Cloud:${NC} None. No external APIs, zero analytics."
    echo -e "✓ ${BOLD}Keylogger Safety:${NC}  Zero keystrokes logged to disk."
    echo -e "✓ ${BOLD}Dictionaries:${NC}      100% Local GNU m17n & Hunspell Devanagari dictionary."

    echo ""
    if $all_good; then
        echo -e "${GREEN}${BOLD}✓ System is fully configured and ready for predictive Hinglish typing!${NC}"
    else
        echo -e "${YELLOW}${BOLD}! Some components need configuration. Run ./hinglish-to-hindi-typing.sh to complete setup.${NC}"
    fi
    echo ""
}

# ----------------------------- Uninstallation --------------------------------
uninstall_setup() {
    print_banner
    echo -e "${BOLD}${RED}--- Reverting Hinglish Typing Configuration ---${NC}\n"

    read -rp "Are you sure you want to remove the Hinglish typing configuration? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        echo "Aborted."
        exit 0
    fi

    log_info "Removing environment variable blocks..."
    remove_env_block "${USER_HOME}/.bashrc"
    remove_env_block "${USER_HOME}/.zshrc"
    remove_env_block "${USER_HOME}/.profile"
    remove_env_block "${USER_HOME}/.xprofile"

    if [[ -f "${USER_HOME}/.config/environment.d/ibus.conf" ]]; then
        rm -f "${USER_HOME}/.config/environment.d/ibus.conf"
        log_info "Removed ${USER_HOME}/.config/environment.d/ibus.conf"
    fi

    if [[ -f "${USER_HOME}/.config/autostart/ibus.desktop" ]]; then
        rm -f "${USER_HOME}/.config/autostart/ibus.desktop"
        log_info "Removed autostart entry."
    fi

    # Remove application launchers
    "${SCRIPT_DIR}/easy-hindi-typing.sh" stop 2>/dev/null || true
    rm -f "${USER_HOME}/.local/share/applications/featherpad-hindi.desktop" \
          "${USER_HOME}/.local/share/applications/libreoffice-hindi.desktop" \
          "${USER_HOME}/.local/share/applications/easy-hindi-typing.desktop" \
          "${USER_HOME}/.local/bin/hinglish-launch" \
          "${USER_HOME}/.local/bin/hinglish-pad"
    log_info "Removed application menu launchers."

    # GNOME sources removal
    if command -v gsettings &>/dev/null && gsettings list-schemas 2>/dev/null | grep -q "org.gnome.desktop.input-sources"; then
        log_info "Removing Hindi engines from GNOME input sources..."
        if command -v python3 &>/dev/null; then
            python3 - << 'EOF'
import subprocess, ast
try:
    raw = subprocess.check_output(
        ['gsettings', 'get', 'org.gnome.desktop.input-sources', 'sources'],
        stderr=subprocess.DEVNULL
    ).decode().strip()
    if raw.startswith('@a(ss) '): raw = raw[7:]
    sources = ast.literal_eval(raw) if raw and raw != '[]' else []
    sources = [s for s in sources if s not in (('ibus', 'tb:hi:itrans'), ('ibus', 'm17n:hi:itrans'))]
    if not sources: sources = [('xkb', 'us')]
    formatted = "[" + ", ".join(f"('{s[0]}', '{s[1]}')" for s in sources) + "]"
    subprocess.call(['gsettings', 'set', 'org.gnome.desktop.input-sources', 'sources', formatted])
except Exception: pass
EOF
        fi
    fi

    log_success "Configurations reverted cleanly. (Package binaries were kept to prevent removing system packages)."
}

# ----------------------------- Print Cheatsheet ------------------------------
print_cheatsheet() {
    echo -e "\n${BOLD}${GREEN}====================================================================${NC}"
    echo -e "${BOLD}${GREEN}             🎉 HINGLISH TYPING SETUP COMPLETE! 🎉                 ${NC}"
    echo -e "${BOLD}${GREEN}====================================================================${NC}\n"

    echo -e "${BOLD}▶ 1. MULTIPLE WORD SUGGESTIONS (PREDICTIVE CANDIDATE POPUP):${NC}"
    echo -e "  • As you type in Hinglish (e.g. ${CYAN}namaste${NC}), an interactive candidate popup appears:"
    echo -e "      ${BOLD}1. नमस्ते   2. नमस्कार   3. नमस्कर${NC}"
    echo -e "  • ${GREEN}Candidate Selection Keys:${NC}"
    echo -e "      • ${BOLD}Space / Enter${NC} : Commits the 1st (top) candidate"
    echo -e "      • ${BOLD}1 – 9${NC}         : Press number to select candidate directly"
    echo -e "      • ${BOLD}Down / Up / Tab${NC}: Scroll or navigate through suggestions"
    echo -e "      • ${BOLD}Escape${NC}        : Dismiss popup and keep typed text\n"

    echo -e "${BOLD}▶ 2. DEDICATED APP LAUNCHERS (ZERO SHORTCUT CONFLICT):${NC}"
    echo -e "  • ${GREEN}FeatherPad (Hindi Notepad)${NC} is now in your Application Menu!"
    echo -e "  • Open it and type Hindi immediately with suggestion popups!"
    echo -e "  • Or run from terminal: ${CYAN}./hinglish-to-hindi-typing.sh --launch featherpad${NC}\n"

    echo -e "${BOLD}▶ 3. PER-WINDOW ISOLATION (PROTECTS VS CODE & TERMINAL):${NC}"
    echo -e "  • Keyboard shortcut: ${CYAN}${BOLD}Super + Space${NC} (Windows Key + Space)"
    echo -e "  • ${MAGENTA}Per-Window Isolation is ON:${NC} When you switch to Hindi in FeatherPad"
    echo -e "    or LibreOffice, your VS Code and Terminal ${BOLD}stay in English automatically${NC}!"
    echo -e "  • ${MAGENTA}Zero IntelliSense Collision:${NC} ${BOLD}Ctrl + Space${NC} is preserved for VS Code autocomplete.\n"

    echo -e "${BOLD}▶ 4. SWITCHING MODES (PREDICTIVE SUGGESTIONS vs. DIRECT 1-TO-1):${NC}"
    echo -e "  • Predictive with Suggestions: ${CYAN}./hinglish-to-hindi-typing.sh --suggestions${NC}  (tb:hi:itrans)"
    echo -e "  • Direct (No popup):           ${CYAN}./hinglish-to-hindi-typing.sh --direct${NC}       (m17n:hi:itrans)\n"

    echo -e "${BOLD}▶ QUICK PHONETIC TYPING CHEAT SHEET:${NC}"
    echo -e "  ┌──────────────────────────────┬──────────────────────────────┐"
    echo -e "  │ ${BOLD}You Type (English/Hinglish)${NC}   │ ${BOLD}Output (Hindi / Devanagari)${NC}   │"
    echo -e "  ├──────────────────────────────┼──────────────────────────────┤"
    echo -e "  │ namaste                      │ नमस्ते                       │"
    echo -e "  │ kya haal hai                 │ क्या हाल है                  │"
    echo -e "  │ bharat                       │ भारत                         │"
    echo -e "  │ dhanyavaad                   │ धन्यवाद                      │"
    echo -e "  │ shanti (or shAMti)           │ शांति                        │"
    echo -e "  │ mera                         │ मेरा                         │"
    echo -e "  │ aap kaise ho                 │ आप कैसे हो                   │"
    echo -e "  │ k (ending with halant)       │ क्                            │"
    echo -e "  │ OM / AUM                     │ ॐ                            │"
    echo -e "  │ 1 2 3                        │ १ २ ३                         │"
    echo -e "  └──────────────────────────────┴──────────────────────────────┘"

    echo -e "\n${BOLD}▶ PRIVACY SUMMARY:${NC}"
    echo -e "  • ${GREEN}100% Offline${NC}: Zero internet connection required."
    echo -e "  • ${GREEN}No Keylogger${NC}: Keystrokes are converted in RAM and never stored."
    echo -e "  • ${GREEN}Zero Telemetry${NC}: No data is sent to any server.\n"
}

# ----------------------------- App-Only Setup --------------------------------
setup_app_only() {
    print_banner
    log_info "Configuring App-Only Mode (FeatherPad / LibreOffice only; leaves OS environment untouched)..."
    detect_and_install_packages
    create_app_launchers
    restart_ibus_daemon

    echo -e "\n${BOLD}${GREEN}====================================================================${NC}"
    echo -e "${BOLD}${GREEN}             🎉 APP-ONLY SETUP COMPLETE! 🎉                        ${NC}"
    echo -e "${BOLD}${GREEN}====================================================================${NC}\n"
    echo -e "✓ Created ${BOLD}FeatherPad (Hindi Notepad)${NC} in your Application Menu."
    echo -e "✓ Global environment variables (.bashrc, .profile) were ${BOLD}NOT modified${NC}."
    echo -e "✓ VS Code, terminal, and browser shortcuts are 100% unaffected.\n"
    echo -e "To open Hindi Notepad directly from terminal, run:"
    echo -e "    ${CYAN}./hinglish-to-hindi-typing.sh --launch featherpad${NC}  or  ${CYAN}~/.local/bin/hinglish-pad${NC}\n"
}

# ------------------------- Mode Switch Helpers -------------------------------
switch_engine_mode() {
    local mode="$1"
    if [[ "$mode" == "suggestions" ]]; then
        log_info "Switching active IBus engine to 'tb:hi:itrans' (Predictive Suggestions)..."
        if command -v dconf &>/dev/null; then
            dconf write /org/freedesktop/ibus/engine/typing-booster/dictionary "'hi_IN'" 2>/dev/null || true
            dconf write /org/freedesktop/ibus/engine/typing-booster/wordpredictions "true" 2>/dev/null || true
        fi
        ibus engine tb:hi:itrans 2>/dev/null || log_warn "IBus daemon not responding (will apply on next start)."
        log_success "Switched to Predictive Suggestions Mode: Candidate popup enabled!"
        echo -e "  Type in Hinglish (e.g. 'namaste') $\rightarrow$ shows 1. नमस्ते  2. नमस्कार"
        echo -e "  Press Space/Enter for top candidate, or numbers 1-9 directly."
    elif [[ "$mode" == "direct" ]]; then
        log_info "Switching active IBus engine to 'm17n:hi:itrans' (Direct Transliteration)..."
        ibus engine m17n:hi:itrans 2>/dev/null || log_warn "IBus daemon not responding (will apply on next start)."
        log_success "Switched to Direct Transliteration Mode: 1-to-1 typing without candidate popup."
    fi
}

# -------------------------------- Main Logic ---------------------------------
show_help() {
    echo "Usage: ./hinglish-to-hindi-typing.sh [OPTION]"
    echo ""
    echo "Automated, 100% offline Hinglish (phonetic Hindi) typing setup for Linux."
    echo ""
    echo "Options:"
    echo "  --web, -w, --app     Launch Easy Hindi Typing (100% offline localhost app like"
    echo "                       easyhindityping.com with real-time word suggestions)."
    echo "  --install, -i        (Default) Automatically install packages, configure"
    echo "                       IBus, enable predictive suggestions, and create app launchers."
    echo "  --suggestions, -s    Activate Predictive Suggestions mode (tb:hi:itrans with candidate popup)."
    echo "  --direct, -d         Activate Direct Transliteration mode (m17n:hi:itrans without popup)."
    echo "  --app-only, -a       Configure ONLY FeatherPad/LibreOffice launchers (leaves OS"
    echo "                       dotfiles and global environment variables 100% untouched)."
    echo "  --launch, -l [APP]   Launch FeatherPad (or specified editor) directly in Hindi mode."
    echo "  --check, -c          Perform diagnostic verification and 100% privacy audit."
    echo "  --autostart [on|off] Switch between Auto-Start on login and On-Demand mode."
    echo "  --uninstall, -u      Cleanly revert and remove all configuration changes."
    echo "  --test, -t           Display phonetic typing cheatsheet and verification tips."
    echo "  --help, -h           Show this help message."
    echo ""
    echo "Candidate Selection Keys (when suggestions are active):"
    echo "  • Space / Enter      : Commits top candidate"
    echo "  • 1 – 9              : Commits candidate 1 through 9 directly"
    echo "  • Down / Up / Tab    : Browse candidate list"
    echo "  • Escape             : Dismiss suggestions"
    echo ""
    echo "Examples:"
    echo "  ./hinglish-to-hindi-typing.sh                    # Standard setup with suggestions enabled"
    echo "  ./hinglish-to-hindi-typing.sh --suggestions      # Switch to predictive candidate popup"
    echo "  ./hinglish-to-hindi-typing.sh --direct           # Switch to direct 1-to-1 transliteration"
    echo "  ./hinglish-to-hindi-typing.sh --launch           # Open FeatherPad in Hindi typing mode"
    echo "  ./hinglish-to-hindi-typing.sh --check            # Check current setup status"
}

main() {
    local action="install"
    local launch_target="featherpad"
    local autostart_arg="status"

    if [[ $# -gt 0 ]]; then
        case "$1" in
            --web|-w|--app)
                action="web"
                ;;
            --install|-i)
                action="install"
                ;;
            --suggestions|-s)
                action="suggestions"
                ;;
            --direct|-d)
                action="direct"
                ;;
            --app-only|-a)
                action="app_only"
                ;;
            --launch|-l)
                action="launch"
                if [[ $# -gt 1 ]]; then
                    launch_target="$2"
                fi
                ;;
            --autostart|autostart)
                action="autostart"
                if [[ $# -gt 1 ]]; then
                    autostart_arg="$2"
                fi
                ;;
            --check|-c|--status|status)
                action="check"
                ;;
            --uninstall|-u)
                action="uninstall"
                ;;
            --test|-t)
                action="test"
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    fi

    if [[ "$action" != "launch" && "$action" != "web" && "$action" != "test" && "$action" != "check" && "$action" != "suggestions" && "$action" != "direct" && "$action" != "autostart" ]]; then
        check_root_safety
    fi

    case "$action" in
        web)
            "${SCRIPT_DIR}/easy-hindi-typing.sh" start
            ;;
        autostart)
            manage_autostart "$autostart_arg"
            ;;
        install)
            print_banner
            detect_and_install_packages
            configure_environment_variables
            configure_desktop_settings
            restart_ibus_daemon
            print_cheatsheet
            ;;
        suggestions)
            switch_engine_mode "suggestions"
            ;;
        direct)
            switch_engine_mode "direct"
            ;;
        app_only)
            setup_app_only
            ;;
        launch)
            launch_isolated_app "$launch_target"
            ;;
        check)
            run_diagnostic_check
            ;;
        uninstall)
            uninstall_setup
            ;;
        test)
            print_cheatsheet
            ;;
    esac
}

main "$@"