#!/usr/bin/env bash
#
# doctor.sh — Root Launcher for Debian Dev Suite Health Check
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/Setup-Doctor/doctor.sh" "$@"
