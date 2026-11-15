#!/usr/bin/env bash
#
# setup-manager.sh — CLI Manager & Launcher for Debian Dev Suite Manager GUI
# Part of the Debian Dev Suite
#
# Features:
#   - Rootless GUI launch: ./setup-manager.sh or debian-dev-manager
#   - Desktop integration: installs .desktop shortcut, scalable icon & global CLI symlink
#   - Automated dependency audit: checks Python3, PySide6 (Qt6), Display server
#   - Clean uninstallation: safely reverts shortcuts and system symlinks
#
# Usage:
#   ./setup-manager.sh                   # Launch GUI Manager
#   ./setup-manager.sh --status          # Non-root health and dependency check
#   sudo ./setup-manager.sh --install    # Install system menu shortcuts and global command
#   sudo ./setup-manager.sh --uninstall  # Remove shortcuts and symlinks
#   ./setup-manager.sh --help            # Show usage
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"
VENV_DIR="${REPO_ROOT}/.venv"
VENV_PYTHON="${VENV_DIR}/bin/python3"

BOLD=$'\033[1m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
RESET=$'\033[0m'

log_info()    { echo -e "  [${CYAN}ℹ${RESET}] ${BOLD}$1${RESET} : $2"; }
log_ok()      { echo -e "  [${GREEN}✔${RESET}] ${BOLD}$1${RESET} : $2"; }
log_warn()    { echo -e "  [${YELLOW}⚠${RESET}] ${YELLOW}${BOLD}$1${RESET} : $2"; }
log_err()     { echo -e "  [${RED}✖${RESET}] ${RED}${BOLD}$1${RESET} : $2"; }

show_help() {
    cat << EOF
${BOLD}Debian Dev Suite GUI Manager — Command Line Interface${RESET}

${BOLD}Usage:${RESET}
  $0 [OPTION]

${BOLD}Options:${RESET}
  (no arguments), --launch, -l   Launch Debian Dev Suite Manager GUI (auto-initializes .venv)
  --status, -s                   Check GUI dependencies, Python bindings & desktop integration
  --create-venv, --venv          Explicitly create or refresh isolated Python virtual environment (.venv)
  --install, -i                  Install system desktop shortcut, icon & /usr/local/bin/debian-dev-manager
  --uninstall, -u                Remove desktop shortcuts, icon & global symlinks
  --help, -h                     Display this help message

${BOLD}Examples:${RESET}
  ./setup-manager.sh                     # Open the GUI Control Center (auto-prepares .venv)
  ./setup-manager.sh --status            # Check dependencies without root
  ./setup-manager.sh --create-venv       # Prepare isolated .venv with PySide6 rootlessly
  sudo ./setup-manager.sh --install      # Add to application menu for all users
  sudo ./setup-manager.sh --uninstall    # Remove desktop integration cleanly
EOF
}

ensure_venv() {
    # If the venv exists and PySide6 runs cleanly, return immediately
    if [ -x "$VENV_PYTHON" ] && "$VENV_PYTHON" -c "import PySide6.QtWidgets" >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${BOLD}${CYAN}Setting up shared Python virtual environment (.venv) at repository root...${RESET}"

    # Create .venv if it doesn't exist
    if [ ! -x "$VENV_PYTHON" ]; then
        echo -e "  [${CYAN}ℹ${RESET}] Initializing virtualenv in: ${BOLD}${VENV_DIR}${RESET}"
        # Use --system-site-packages so if python3-pyside6 is present on system, it links with 0s overhead
        if python3 -m venv --system-site-packages "$VENV_DIR" 2>/dev/null; then
            echo -e "  [${GREEN}✔${RESET}] Virtualenv created successfully."
        elif python3 -m venv "$VENV_DIR" 2>/dev/null; then
            echo -e "  [${GREEN}✔${RESET}] Clean virtualenv created successfully."
        else
            echo -e "${RED}ERROR: Failed to create virtual environment. Please install python3-venv (sudo apt install python3-venv).${RESET}" >&2
            exit 1
        fi
    fi

    # Verify PySide6 is working inside the venv; if not, install it into .venv
    if ! "$VENV_PYTHON" -c "import PySide6.QtWidgets" >/dev/null 2>&1; then
        echo -e "  [${CYAN}ℹ${RESET}] Installing PySide6 into isolated .venv (no root required)..."
        if command -v uv >/dev/null 2>&1; then
            uv pip install --python "$VENV_PYTHON" PySide6
        elif [ -x "${TARGET_HOME}/.local/bin/uv" ]; then
            "${TARGET_HOME}/.local/bin/uv" pip install --python "$VENV_PYTHON" PySide6
        elif [ -x "$VENV_DIR/bin/pip" ]; then
            "$VENV_DIR/bin/pip" install --upgrade pip >/dev/null 2>&1 || true
            "$VENV_DIR/bin/pip" install PySide6
        else
            echo -e "  [${YELLOW}⚠${RESET}] Bootstrapping pip into .venv via ensurepip..."
            "$VENV_PYTHON" -m ensurepip --default-pip >/dev/null 2>&1 || true
            if [ -x "$VENV_DIR/bin/pip" ]; then
                "$VENV_DIR/bin/pip" install PySide6
            else
                echo -e "${RED}ERROR: Neither pip nor uv is available to install PySide6 into .venv.${RESET}" >&2
                exit 1
            fi
        fi
    fi

    # Fix ownership if running under sudo
    if [ -n "${SUDO_USER:-}" ] && [ "$EUID" -eq 0 ]; then
        chown -R "$TARGET_USER:$TARGET_USER" "$VENV_DIR" 2>/dev/null || true
    fi

    if "$VENV_PYTHON" -c "import PySide6.QtWidgets" >/dev/null 2>&1; then
        echo -e "  [${GREEN}✔${RESET}] ${BOLD}PySide6 active in isolated virtual environment!${RESET}"
    else
        echo -e "${RED}${BOLD}✖ Failed to verify PySide6 in .venv.${RESET}" >&2
        exit 1
    fi
}

check_status() {
    echo -e "${BOLD}${CYAN}==================================================================${RESET}"
    echo -e "${BOLD}     Debian Dev Suite GUI Manager — Diagnostic Health Check       ${RESET}"
    echo -e "${BOLD}${CYAN}==================================================================${RESET}"
    echo

    # 1. Python 3
    if command -v python3 >/dev/null 2>&1; then
        PY_VER=$(python3 --version 2>&1 | awk '{print $2}')
        log_ok "Python Interpreter" "Python 3 ($PY_VER) available"
    else
        log_err "Python Interpreter" "python3 is not installed"
    fi

    # 2. Isolated Virtual Environment (.venv)
    if [ -x "$VENV_PYTHON" ] && "$VENV_PYTHON" -c "import PySide6.QtWidgets" >/dev/null 2>&1; then
        VENV_PY_VER=$("$VENV_PYTHON" --version 2>&1 | awk '{print $2}')
        log_ok "Virtual Environment" "Active isolated .venv ($VENV_PY_VER) at ${VENV_DIR}"
    elif [ -d "$VENV_DIR" ]; then
        log_warn "Virtual Environment" ".venv exists at ${VENV_DIR} but PySide6 is not ready (run: $0 --create-venv)"
    else
        log_info "Virtual Environment" "Not initialized yet (run: $0 --create-venv, or auto-created on launch)"
    fi

    # 3. PySide6 (Official Qt6 for Python)
    if [ -x "$VENV_PYTHON" ] && "$VENV_PYTHON" -c "import PySide6.QtWidgets" 2>/dev/null; then
        PYSIDE_VER=$("$VENV_PYTHON" -c "import PySide6; print(PySide6.__version__)" 2>/dev/null || echo "active")
        log_ok "GUI Toolkit" "PySide6 (Qt6 - Official LGPLv3, v$PYSIDE_VER) ready in .venv"
    elif python3 -c "import PySide6.QtWidgets" 2>/dev/null; then
        PYSIDE_VER=$(python3 -c "import PySide6; print(PySide6.__version__)" 2>/dev/null || echo "active")
        log_ok "GUI Toolkit" "PySide6 (Qt6 - Official LGPLv3, v$PYSIDE_VER) available in system Python"
    else
        log_warn "GUI Toolkit" "PySide6 not yet installed (will auto-install into .venv on launch)"
    fi

    # 4. Display Server
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        log_ok "Display Server" "Active display session (${DISPLAY:-${WAYLAND_DISPLAY:-unknown}})"
    else
        log_warn "Display Server" "No graphical display detected ($DISPLAY empty). GUI requires X11 or Wayland."
    fi

    # 5. Desktop Entry & Icon
    if [ -f "/usr/share/applications/debian-dev-manager.desktop" ] || [ -f "${TARGET_HOME}/.local/share/applications/debian-dev-manager.desktop" ]; then
        log_ok "Desktop Shortcut" "Installed in system application menu"
    else
        log_info "Desktop Shortcut" "Not installed (run: sudo $0 --install)"
    fi

    # 6. Global Command Symlink
    if [ -x "/usr/local/bin/debian-dev-manager" ] || [ -x "${TARGET_HOME}/.local/bin/debian-dev-manager" ]; then
        log_ok "Global Command" "Active ('debian-dev-manager' executable from any shell)"
    else
        log_info "Global Command" "Not installed in /usr/local/bin"
    fi

    # 7. Privilege Escalator (pkexec / sudo)
    if command -v pkexec >/dev/null 2>&1; then
        log_ok "Privilege Escalation" "pkexec available for native graphical root prompts"
    elif command -v sudo >/dev/null 2>&1; then
        log_info "Privilege Escalation" "sudo available"
    else
        log_warn "Privilege Escalation" "Neither pkexec nor sudo found"
    fi

    echo
    echo -e "${BOLD}${CYAN}==================================================================${RESET}"
}

do_install() {
    echo -e "${BOLD}${CYAN}Installing Debian Dev Suite Manager Desktop Integration...${RESET}"

    # Ensure isolated venv is prepared
    ensure_venv

    if [ "$EUID" -eq 0 ]; then
        # System-wide installation (requires root)
        echo "Installing system-wide (/usr/local/bin and /usr/share/applications)..."
        mkdir -p /usr/share/icons/hicolor/scalable/apps
        cp -f "${SCRIPT_DIR}/debian-dev-suite.svg" /usr/share/icons/hicolor/scalable/apps/debian-dev-suite.svg 2>/dev/null || cp -f "${SCRIPT_DIR}/debian-dev-manager.svg" /usr/share/icons/hicolor/scalable/apps/debian-dev-suite.svg
        cp -f "${SCRIPT_DIR}/debian-dev-suite.svg" /usr/share/icons/hicolor/scalable/apps/debian-dev-manager.svg 2>/dev/null || true
        chmod 644 /usr/share/icons/hicolor/scalable/apps/debian-dev-*.svg 2>/dev/null || true

        mkdir -p /usr/share/applications
        sed "s|Exec=debian-dev-manager|Exec=/usr/local/bin/debian-dev-manager|g" "${SCRIPT_DIR}/debian-dev-manager.desktop" > /usr/share/applications/debian-dev-manager.desktop
        chmod 644 /usr/share/applications/debian-dev-manager.desktop

        cat << 'WRAPPER' > /usr/local/bin/debian-dev-manager
#!/usr/bin/env bash
APP_SH="REAL_APP_SH"
if [ -x "$APP_SH" ]; then
    exec "$APP_SH" "$@"
else
    echo "ERROR: Could not locate setup-manager.sh at $APP_SH" >&2
    exit 1
fi
WRAPPER
        sed -i "s|REAL_APP_SH|${SCRIPT_DIR}/setup-manager.sh|g" /usr/local/bin/debian-dev-manager
        chmod 755 /usr/local/bin/debian-dev-manager

        if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database /usr/share/applications >/dev/null 2>&1 || true; fi
        if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true; fi
    else
        # 100% Rootless User-Space Installation (~/.local/bin and ~/.local/share/applications)
        echo "Installing in user-space (0 root privileges required)..."
        local user_icon_dir="${TARGET_HOME}/.local/share/icons/hicolor/scalable/apps"
        local user_app_dir="${TARGET_HOME}/.local/share/applications"
        local user_bin_dir="${TARGET_HOME}/.local/bin"

        mkdir -p "$user_icon_dir" "$user_app_dir" "$user_bin_dir"
        cp -f "${SCRIPT_DIR}/debian-dev-suite.svg" "${user_icon_dir}/debian-dev-suite.svg" 2>/dev/null || cp -f "${SCRIPT_DIR}/debian-dev-manager.svg" "${user_icon_dir}/debian-dev-suite.svg"
        cp -f "${SCRIPT_DIR}/debian-dev-suite.svg" "${user_icon_dir}/debian-dev-manager.svg" 2>/dev/null || true
        chmod 644 "${user_icon_dir}"/debian-dev-*.svg 2>/dev/null || true

        sed "s|Exec=debian-dev-manager|Exec=${user_bin_dir}/debian-dev-manager|g" "${SCRIPT_DIR}/debian-dev-manager.desktop" > "${user_app_dir}/debian-dev-manager.desktop"
        chmod 644 "${user_app_dir}/debian-dev-manager.desktop"

        cat << 'WRAPPER' > "${user_bin_dir}/debian-dev-manager"
#!/usr/bin/env bash
APP_SH="REAL_APP_SH"
if [ -x "$APP_SH" ]; then
    exec "$APP_SH" "$@"
else
    echo "ERROR: Could not locate setup-manager.sh at $APP_SH" >&2
    exit 1
fi
WRAPPER
        sed -i "s|REAL_APP_SH|${SCRIPT_DIR}/setup-manager.sh|g" "${user_bin_dir}/debian-dev-manager"
        chmod 755 "${user_bin_dir}/debian-dev-manager"

        if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "${user_app_dir}" >/dev/null 2>&1 || true; fi
    fi

    echo -e "${GREEN}${BOLD}✔ Successfully installed Debian Dev Suite Manager!${RESET}"
    echo "  - Desktop application menu: 'Debian Dev Suite Manager'"
    echo "  - Command:                  'debian-dev-manager'"
}

do_uninstall() {
    echo -e "${YELLOW}Removing Debian Dev Suite Manager integration...${RESET}"

    rm -f /usr/share/applications/debian-dev-manager.desktop
    rm -f "${TARGET_HOME}/.local/share/applications/debian-dev-manager.desktop"
    rm -f /usr/share/icons/hicolor/scalable/apps/debian-dev-manager.svg /usr/share/icons/hicolor/scalable/apps/debian-dev-suite.svg
    rm -f "${TARGET_HOME}/.local/share/icons/hicolor/scalable/apps/debian-dev-manager.svg" "${TARGET_HOME}/.local/share/icons/hicolor/scalable/apps/debian-dev-suite.svg"
    rm -f /usr/local/bin/debian-dev-manager
    rm -f "${TARGET_HOME}/.local/bin/debian-dev-manager"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi

    echo -e "${GREEN}${BOLD}✔ Uninstallation complete. Removed desktop shortcuts and symlinks.${RESET}"
}

do_launch() {
    ensure_venv
    chmod +x "${SCRIPT_DIR}/setup-manager.py"
    exec "$VENV_PYTHON" "${SCRIPT_DIR}/setup-manager.py" "$@"
}

case "${1:-}" in
    --status|-s|status)
        check_status
        ;;
    --create-venv|--venv|venv)
        ensure_venv
        ;;
    --install|-i|install)
        do_install
        ;;
    --uninstall|-u|uninstall)
        do_uninstall
        ;;
    --help|-h|help)
        show_help
        ;;
    --launch|-l|launch|"")
        do_launch "$@"
        ;;
    *)
        echo -e "${RED}Unknown option: $1${RESET}"
        show_help
        exit 1
        ;;
esac
