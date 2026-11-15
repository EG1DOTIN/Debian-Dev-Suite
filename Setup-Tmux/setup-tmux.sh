#!/usr/bin/env bash
#
# setup-tmux.sh
#
# Configures an ergonomic, high-performance tmux environment for Debian/MX Linux
# Features:
#   - Full mouse support (click panes, resize borders, scroll history)
#   - Intuitive split hotkeys: | and -
#   - Vim navigation (h, j, k, l)
#   - Clean aesthetic dark status bar
#   - Quick shell alias: 'tm'
#
# Usage:
#   ./setup-tmux.sh --install
#   ./setup-tmux.sh --uninstall
#   ./setup-tmux.sh --status
#   ./setup-tmux.sh --help
#

set -e

# Security Guardrail: Prevent running directly as pure root
if [ "$EUID" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    echo -e "\033[0;31m✖ [SECURITY ERROR] Do not run this script directly as root!\033[0m"
    echo "  Tmux configurations belong in your regular user's home (~/.tmux.conf)."
    echo "  Please run: ./setup-tmux.sh"
    exit 1
fi

BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Dynamic User & Target Home Lookup (Zero hardcoding, dual-root/user safe)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"

TARGET_CONF="$TARGET_HOME/.tmux.conf"
BASHRC="$TARGET_HOME/.bashrc"
ALIAS_LINE="alias tm=\"tmux attach 2>/dev/null || tmux new\""

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "=================================================================="
    echo "  $1"
    echo "=================================================================="
    echo -e "${RESET}"
}

do_install() {
    print_header "Setup Tmux — Ergonomic Terminal Multiplexer"

    echo "1. Checking tmux installation..."
    if ! command -v tmux >/dev/null 2>&1; then
        echo "Root privileges required to install tmux package via APT..."
        sudo apt update -y && sudo apt install -y tmux
        echo "  [OK] tmux installed."
    else
        echo "  [OK] tmux is already installed (0 root commands needed)."
    fi

    echo "2. Deploying ~/.tmux.conf..."
    if [ -f "$TARGET_CONF" ]; then
        echo -e "  ${YELLOW}Existing ~/.tmux.conf detected. Creating backup at $TARGET_HOME/.tmux.conf.bak...${RESET}"
        cp "$TARGET_CONF" "$TARGET_HOME/.tmux.conf.bak"
    fi

    cp "$SCRIPT_DIR/tmux.conf" "$TARGET_CONF"
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown "$TARGET_USER:$TARGET_USER" "$TARGET_CONF" 2>/dev/null || true
        if [ -f "$TARGET_HOME/.tmux.conf.bak" ]; then
            chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.tmux.conf.bak" 2>/dev/null || true
        fi
    fi
    echo -e "  ${GREEN}✓ Deployed ~/.tmux.conf${RESET}"

    echo "3. Configuring shell alias 'tm'..."
    if ! grep -q "alias tm=" "$BASHRC" 2>/dev/null; then
        echo "$ALIAS_LINE" >> "$BASHRC"
        if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            chown "$TARGET_USER:$TARGET_USER" "$BASHRC" 2>/dev/null || true
        fi
        echo -e "  ${GREEN}✓ Added 'tm' alias to ~/.bashrc (attaches or starts tmux)${RESET}"
    fi

    echo
    echo -e "${BOLD}${GREEN}==================================================================${RESET}"
    echo -e "${BOLD}${GREEN}  Tmux Configuration Complete!${RESET}"
    echo -e "${BOLD}${GREEN}==================================================================${RESET}"
    echo
    echo "Quick start:"
    echo "  1. Reload your shell: source ~/.bashrc"
    echo "  2. Launch tmux with: tm"
    echo
    echo "Key shortcuts inside tmux:"
    echo "  - Split vertically   : Ctrl+B then | (or Ctrl+A then |)"
    echo "  - Split horizontally : Ctrl+B then - (or Ctrl+A then -)"
    echo "  - Switch panes       : Click with mouse OR Ctrl+B then h/j/k/l"
    echo "  - Resize panes       : Drag with mouse"
    echo "  - Scroll history     : Use mouse scroll wheel"
    echo
}

do_status() {
    print_header "Tmux Status"
    echo -n "  tmux installed : "
    if command -v tmux >/dev/null 2>&1; then
        echo -e "${GREEN}$(which tmux) (v$(tmux -V | cut -d' ' -f2))${RESET}"
    else
        echo -e "${RED}Not installed${RESET}"
    fi

    echo -n "  ~/.tmux.conf   : "
    if [ -f "$TARGET_CONF" ]; then
        echo -e "${GREEN}Configured ($(wc -l < "$TARGET_CONF") lines)${RESET}"
    else
        echo -e "${RED}Missing${RESET}"
    fi

    echo -n "  'tm' alias     : "
    if grep -q "alias tm=" "$BASHRC" 2>/dev/null; then
        echo -e "${GREEN}Configured in ~/.bashrc${RESET}"
    else
        echo -e "${YELLOW}Not configured${RESET}"
    fi
    echo
}

do_uninstall() {
    print_header "Tmux — UNINSTALL"
    if [ -f "$TARGET_CONF" ]; then
        rm -f "$TARGET_CONF"
        echo -e "  ${GREEN}✓ Removed ~/.tmux.conf${RESET}"
        if [ -f "$TARGET_HOME/.tmux.conf.bak" ]; then
            mv "$TARGET_HOME/.tmux.conf.bak" "$TARGET_CONF"
            echo -e "  ${GREEN}✓ Restored previous ~/.tmux.conf from backup${RESET}"
        fi
    fi

    if grep -q "alias tm=" "$BASHRC" 2>/dev/null; then
        sed -i '/alias tm=/d' "$BASHRC"
        echo -e "  ${GREEN}✓ Removed 'tm' alias from ~/.bashrc${RESET}"
    fi

    echo "Uninstallation complete."
}

case "${1:-}" in
    --install)   do_install ;;
    --uninstall) do_uninstall ;;
    --status)    do_status ;;
    --help|-h)
        echo "Usage: $0 [--install | --uninstall | --status | --help]"
        ;;
    *)
        do_install
        ;;
esac
