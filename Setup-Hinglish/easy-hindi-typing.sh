#!/usr/bin/env bash
# ==============================================================================
# Easy Hindi Typing — Localhost Launcher
# Part of Debian Dev Suite (100% Offline, Privacy-Focused)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"
CANONICAL_APP_DIR="$TARGET_HOME/.local/share/dev-setups/easy-hindi-typing"

if [[ -d "$CANONICAL_APP_DIR" && -f "$CANONICAL_APP_DIR/server.py" ]]; then
    APP_DIR="$CANONICAL_APP_DIR"
else
    APP_DIR="${SCRIPT_DIR}/easy-hindi-typing"
fi
SERVER_PY="${APP_DIR}/server.py"
PID_FILE="/tmp/easy_hindi_typing_server.pid"
DEFAULT_PORT=8765
PORT="${DEFAULT_PORT}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

is_server_running() {
    if [ -f "${PID_FILE}" ]; then
        local pid
        pid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            return 0
        fi
    fi
    # Check if port is listening
    if command -v ss >/dev/null 2>&1; then
        if ss -tulpn 2>/dev/null | grep -q ":${PORT}\b"; then
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tulpn 2>/dev/null | grep -q ":${PORT}\b"; then
            return 0
        fi
    fi
    return 1
}

open_url_in_browser() {
    local url="http://127.0.0.1:${PORT}"
    log_info "Opening browser at: ${url}"

    if command -v x-www-browser >/dev/null 2>&1; then
        x-www-browser "${url}" >/dev/null 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "${url}" >/dev/null 2>&1 &
    elif command -v firefox >/dev/null 2>&1; then
        firefox "${url}" >/dev/null 2>&1 &
    elif command -v chromium >/dev/null 2>&1; then
        chromium "${url}" >/dev/null 2>&1 &
    elif command -v google-chrome >/dev/null 2>&1; then
        google-chrome "${url}" >/dev/null 2>&1 &
    else
        log_warn "Could not detect default GUI browser. Please open ${url} manually."
    fi
}

start_server() {
    if is_server_running; then
        log_ok "Easy Hindi Typing server is already running on port ${PORT}."
        open_url_in_browser
        return 0
    fi

    log_info "Starting Easy Hindi Typing localhost server on 127.0.0.1:${PORT}..."
    nohup python3 "${SERVER_PY}" --port "${PORT}" --no-browser > /tmp/easy_hindi_typing.log 2>&1 &
    local server_pid=$!
    disown "${server_pid}" 2>/dev/null || true
    echo "${server_pid}" > "${PID_FILE}"

    # Wait briefly for socket readiness
    sleep 0.8
    if is_server_running; then
        log_ok "Easy Hindi Typing server is active (PID: ${server_pid})."
        open_url_in_browser
    else
        log_err "Failed to start server. Log output:"
        cat /tmp/easy_hindi_typing.log
        exit 1
    fi
}

stop_server() {
    local stopped=false
    if [ -f "${PID_FILE}" ]; then
        local pid
        pid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            kill "${pid}" 2>/dev/null || true
            stopped=true
            log_ok "Easy Hindi Typing server stopped (PID: ${pid})."
        fi
        rm -f "${PID_FILE}"
    fi

    # Try killing by port/process match if needed
    local found_pids
    found_pids=$(pgrep -f "easy-hindi-typing.*server.py" 2>/dev/null || true)
    if [ -n "${found_pids}" ]; then
        kill ${found_pids} 2>/dev/null || true
        stopped=true
        log_ok "Easy Hindi Typing server stopped (PID: ${found_pids})."
    fi

    # Ensure port 8765 is freed if fuser is available
    if command -v fuser >/dev/null 2>&1; then
        fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
    fi

    if [ "$stopped" = true ]; then
        return 0
    else
        log_info "No running Easy Hindi Typing server found."
    fi
}

check_status() {
    if is_server_running; then
        log_ok "Easy Hindi Typing server is RUNNING on http://127.0.0.1:${PORT}"
    else
        log_info "Easy Hindi Typing server is NOT running."
    fi
}

install_desktop_entry() {
    log_info "Installing desktop menu entry and local CLI launcher..."
    local bin_dir="${HOME}/.local/bin"
    local apps_dir="${HOME}/.local/share/applications"
    local icons_dir="${HOME}/.local/share/icons/hicolor/scalable/apps"
    local icons_fallback="${HOME}/.local/share/icons"

    mkdir -p "${bin_dir}" "${apps_dir}" "${icons_dir}" "${icons_fallback}" "${CANONICAL_APP_DIR}"

    # Sync app files to standalone user directory
    cp -rf "${SCRIPT_DIR}/easy-hindi-typing/"* "${CANONICAL_APP_DIR}/"
    cp -f "${SCRIPT_DIR}/easy-hindi-typing.sh" "${CANONICAL_APP_DIR}/easy-hindi-typing.sh"
    chmod +x "${CANONICAL_APP_DIR}/easy-hindi-typing.sh"

    # Install binary symlink
    ln -sf "${CANONICAL_APP_DIR}/easy-hindi-typing.sh" "${bin_dir}/easy-hindi-typing"
    log_ok "Launcher link installed at: ${bin_dir}/easy-hindi-typing"

    # Install icon
    if [ -f "${CANONICAL_APP_DIR}/icon.svg" ]; then
        cp -f "${CANONICAL_APP_DIR}/icon.svg" "${icons_dir}/easy-hindi-typing.svg" 2>/dev/null || true
        cp -f "${CANONICAL_APP_DIR}/icon.svg" "${icons_fallback}/easy-hindi-typing.svg" 2>/dev/null || true
        log_ok "Icon installed to scalable icon themes"
    fi

    local desktop_path="${apps_dir}/easy-hindi-typing.desktop"
    cat > "${desktop_path}" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Easy Hindi Typing
GenericName=Hinglish to Hindi Offline Typing
Comment=100% Offline Hinglish to Hindi Typing App with Word Suggestions
Exec=${bin_dir}/easy-hindi-typing
Icon=easy-hindi-typing
Terminal=false
Categories=Utility;TextEditor;Office;
Keywords=hindi;hinglish;typing;devanagari;transliteration;
StartupNotify=true
EOF

    chmod +x "${desktop_path}"
    log_ok "Desktop entry installed at: ${desktop_path}"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${apps_dir}" >/dev/null 2>&1 || true
    fi
}

uninstall_desktop_entry() {
    log_info "Uninstalling Easy Hindi Typing desktop launcher and shortcuts..."
    local bin_dir="${HOME}/.local/bin"
    local apps_dir="${HOME}/.local/share/applications"
    local icons_dir="${HOME}/.local/share/icons/hicolor/scalable/apps"
    local icons_fallback="${HOME}/.local/share/icons"

    stop_server

    rm -f "${bin_dir}/easy-hindi-typing"
    rm -f "${apps_dir}/easy-hindi-typing.desktop"
    rm -f "${icons_dir}/easy-hindi-typing.svg"
    rm -f "${icons_fallback}/easy-hindi-typing.svg"
    rm -f "${PID_FILE}"
    rm -rf "${CANONICAL_APP_DIR}"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${apps_dir}" >/dev/null 2>&1 || true
    fi
    log_ok "Desktop launcher and shortcuts removed successfully."
}

# Main Command Dispatch
case "${1:-start}" in
    start|"")
        start_server
        ;;
    foreground|run)
        python3 "${SERVER_PY}" --port "${PORT}"
        ;;
    stop)
        stop_server
        ;;
    restart)
        stop_server
        sleep 0.5
        start_server
        ;;
    status)
        check_status
        ;;
    --install-desktop|install-desktop)
        install_desktop_entry
        ;;
    --uninstall-desktop|uninstall|--uninstall)
        uninstall_desktop_entry
        ;;
    --help|-h|help)
        echo "Usage: $0 [start|foreground|stop|restart|status|--install-desktop|--uninstall]"
        echo ""
        echo "Commands:"
        echo "  start              Start server in background and open default browser (default)"
        echo "  foreground         Run server in foreground with live console logs"
        echo "  stop               Stop running background server"
        echo "  restart            Restart server"
        echo "  status             Check if server is active"
        echo "  --install-desktop  Install desktop menu launcher"
        echo "  --uninstall        Stop server and remove desktop shortcuts and launcher"
        echo "  --help, -h         Show this help manual"
        ;;
    *)
        log_err "Unknown command: $1. Run with --help for usage."
        exit 1
        ;;
esac
