#!/usr/bin/env bash
#
# manager.sh — Root Launcher for Debian Dev Suite Manager GUI
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/Setup-GUI-Manager/setup-manager.sh" "$@"
