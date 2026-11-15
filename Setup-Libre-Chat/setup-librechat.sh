#!/usr/bin/env bash

###############################################################################
# LibreChat Localhost Setup & Manager
# Part of the Debian Dev Suite
#
# Ultra-private, 100% offline-ready AI chat interface:
#   - 100% Free & Open-Source (FOSS), Zero Telemetry, 0 Cloud Tracking
#   - Dual Mode: Turnkey Docker Compose (isolated) OR Native Node.js + MongoDB
#   - Strict Localhost Binding: Bound to 127.0.0.1:3080 (Zero LAN/WAN exposure)
#   - Pre-Configured Local AI: Connects to local llama.cpp server (127.0.0.1:8080)
#   - Cryptographic Hardening: 256-bit AES CREDS_KEY, CREDS_IV & JWT secrets
#   - Desktop & Background Management: start, stop, status, logs & desktop entry
#
# USAGE:
#   ./setup-librechat.sh --install       # Interactive turnkey installation
#   ./setup-librechat.sh --docker        # Turnkey install via Docker Compose
#   ./setup-librechat.sh --native        # Turnkey install via Native Node.js
#   ./setup-librechat.sh --start         # Start LibreChat server in background
#   ./setup-librechat.sh --stop          # Stop running LibreChat server
#   ./setup-librechat.sh --status        # Check server and MongoDB health
#   ./setup-librechat.sh --logs          # Stream runtime logs
#   ./setup-librechat.sh --help          # Show options and examples
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"
CANONICAL_DATA_DIR="$TARGET_HOME/.local/share/dev-setups/librechat"
DATA_DIR="${LIBRECHAT_DATA_DIR:-$CANONICAL_DATA_DIR}"

PID_FILE="${DATA_DIR}/librechat_local_server.pid"
ENV_FILE="${DATA_DIR}/.env"
COMPOSE_FILE="${DATA_DIR}/docker-compose.yml"
CONFIG_YAML="${DATA_DIR}/librechat.yaml"
APP_DIR="${DATA_DIR}/LibreChat"
DEFAULT_PORT=3080
PORT="${DEFAULT_PORT}"

# --- Seamless Legacy Data Migration ---
migrate_legacy_data() {
    if [[ "$DATA_DIR" == "$CANONICAL_DATA_DIR" ]]; then
        mkdir -p "$CANONICAL_DATA_DIR"
        local migrated=false

        if [[ -d "${SCRIPT_DIR}/librechat-data" ]]; then
            print_info "Migrating legacy librechat-data from repo to $CANONICAL_DATA_DIR..."
            mv "${SCRIPT_DIR}/librechat-data" "${CANONICAL_DATA_DIR}/"
            migrated=true
        fi
        if [[ -d "${SCRIPT_DIR}/mongo_data" ]]; then
            print_info "Migrating legacy mongo_data from repo to $CANONICAL_DATA_DIR..."
            mv "${SCRIPT_DIR}/mongo_data" "${CANONICAL_DATA_DIR}/"
            migrated=true
        fi
        if [[ -d "${SCRIPT_DIR}/LibreChat" ]]; then
            print_info "Migrating legacy LibreChat source clone from repo to $CANONICAL_DATA_DIR..."
            mv "${SCRIPT_DIR}/LibreChat" "${CANONICAL_DATA_DIR}/"
            migrated=true
        fi
        if [[ -f "${SCRIPT_DIR}/.env" ]]; then
            print_info "Migrating legacy .env from repo to $CANONICAL_DATA_DIR..."
            mv "${SCRIPT_DIR}/.env" "${CANONICAL_DATA_DIR}/"
            migrated=true
        fi

        if [[ "$migrated" == "true" ]]; then
            print_pass "LibreChat data migrated successfully to $CANONICAL_DATA_DIR."
        fi
    fi
}

ensure_data_dir() {
    migrate_legacy_data
    mkdir -p "${DATA_DIR}" "${DATA_DIR}/librechat-data/images" "${DATA_DIR}/librechat-data/logs" "${DATA_DIR}/mongo_data"
    if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
        cp -f "${SCRIPT_DIR}/docker-compose.yml" "$COMPOSE_FILE"
    fi
    if [[ -f "${SCRIPT_DIR}/index.html" ]]; then
        cp -f "${SCRIPT_DIR}/index.html" "${DATA_DIR}/index.html"
    fi
    if [[ -f "$CONFIG_YAML" ]] && grep -q "host.docker.internal" "$CONFIG_YAML" 2>/dev/null; then
        print_info "Updating librechat.yaml to unified localhost configuration..."
        cp -f "${SCRIPT_DIR}/librechat.yaml" "$CONFIG_YAML"
    elif [[ ! -f "$CONFIG_YAML" && -f "${SCRIPT_DIR}/librechat.yaml" ]]; then
        cp -f "${SCRIPT_DIR}/librechat.yaml" "$CONFIG_YAML"
    fi
}

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

print_header() {
    echo -e "\n${BOLD}${CYAN}======================================================================${RESET}"
    echo -e "${BOLD}${CYAN}  $1${RESET}"
    echo -e "${BOLD}${CYAN}======================================================================${RESET}\n"
}

print_pass() { echo -e "  [${TICK}] $1"; }
print_warn() { echo -e "  [${WARN}] ${YELLOW}$1${RESET}"; }
print_fail() { echo -e "  [${CROSS}] ${RED}$1${RESET}"; }
print_info() { echo -e "  [${INFO}] ${CYAN}$1${RESET}"; }

show_help() {
    cat << 'EOF'
================================================================================
          LibreChat Localhost Manager — Debian Dev Suite
================================================================================

Usage: ./setup-librechat.sh [COMMAND]

Commands:
  --install, -i        Auto-detect prerequisites and perform turnkey setup
  --docker             Deploy LibreChat + MongoDB via Docker Compose
  --native             Deploy LibreChat via Native Node.js + MongoDB
  --start              Start LibreChat server in background
  --stop               Stop running background LibreChat server
  --status             Display operational status of LibreChat & MongoDB
  --autostart [on|off] Switch between Auto-Start on boot and On-Demand mode
  --logs               View live server logs
  --install-desktop    Install desktop application launcher and CLI symlink
  --uninstall          Cleanly stop services and optionally remove app files
  --help, -h           Show this help manual

Examples:
  ./setup-librechat.sh --install
  ./setup-librechat.sh --status
  ./setup-librechat.sh --start
  ./setup-librechat.sh --stop
  ./setup-librechat.sh --autostart off    # On-demand only (will not boot on startup)
  ./setup-librechat.sh --autostart on     # Auto-start on system boot
  ./setup-librechat.sh --autostart status # Check current mode
EOF
}

# -------------------------------------------------------------------------
# Cryptographic Key Generation
# -------------------------------------------------------------------------
generate_hex_secret() {
    local bytes="$1"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "$bytes"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import secrets; print(secrets.token_hex($bytes))"
    elif command -v node >/dev/null 2>&1; then
        node -e "console.log(require('crypto').randomBytes($bytes).toString('hex'))"
    else
        # Pure bash fallback using urandom
        od -vN "$bytes" -An -tx1 /dev/urandom | tr -d ' \n'
    fi
}

generate_secure_env() {
    print_info "Generating cryptographically secure offline .env configuration..."

    if [ -f "$ENV_FILE" ]; then
        print_pass "Existing .env detected at $ENV_FILE"
        return 0
    fi

    local jwt_secret jwt_refresh creds_key creds_iv
    jwt_secret="$(generate_hex_secret 32)"
    jwt_refresh="$(generate_hex_secret 32)"
    creds_key="$(generate_hex_secret 32)"
    creds_iv="$(generate_hex_secret 16)"

    cat > "$ENV_FILE" << EOF
# ==============================================================================
# LibreChat Local Offline Configuration
# Generated by Debian Dev Suite (100% Localhost Isolated, Zero Telemetry)
# ==============================================================================

# Network & Host Binding (Strict Localhost)
HOST=127.0.0.1
PORT=${PORT}

# Database Connection
# If using Docker Compose: mongodb://librechat_mongodb:27017/LibreChat
# If using Native Host:   mongodb://127.0.0.1:27017/LibreChat
MONGO_URI=mongodb://127.0.0.1:27017/LibreChat

# Cryptographic Authentication Secrets
JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh}

# AES-256-CBC Credential Encryption Keys (Mandatory for security)
CREDS_KEY=${creds_key}
CREDS_IV=${creds_iv}

# Strict Privacy & Zero-Telemetry Settings
TELEMETRY=false
DISABLE_TELEMETRY=true
CHECK_BALANCE=false

# User Registration & Access Controls
ALLOW_REGISTRATION=true
ALLOW_EMAIL_LOGIN=true
ALLOW_SOCIAL_LOGIN=false
ALLOW_PASSWORD_RESET=false

# Custom Configuration File
CONFIG_PATH=${CONFIG_YAML}
EOF

    chmod 600 "$ENV_FILE"
    print_pass "Generated $ENV_FILE with 256-bit random secrets (Permissions: 600)"
}

# -------------------------------------------------------------------------
# Prerequisite Verification
# -------------------------------------------------------------------------
has_docker_engine() {
    command -v docker >/dev/null 2>&1
}

has_docker_compose() {
    docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1
}

has_docker() {
    has_docker_engine && has_docker_compose
}

run_compose() {
    ensure_data_dir
    if docker compose version >/dev/null 2>&1; then
        (cd "$DATA_DIR" && docker compose -f "$COMPOSE_FILE" "$@")
    else
        (cd "$DATA_DIR" && docker-compose -f "$COMPOSE_FILE" "$@")
    fi
}

ensure_image_styling() {
    # Check if librechat_app container is running and ensure staticCache headers are active
    if docker ps --filter "name=librechat_app" --filter "status=running" 2>/dev/null | grep -q librechat_app; then
        docker exec librechat_app node -e '
        const fs = require("fs");
        const file = "/app/api/server/utils/staticCache.js";
        if (fs.existsSync(file)) {
            let content = fs.readFileSync(file, "utf8");
            if (!content.includes("Content-Disposition")) {
                content = content.replace(
                    "const fileName = filePath ? path.basename(filePath) : \x27\x27;",
                    "const fileName = filePath ? path.basename(filePath) : \x27\x27;\n    res.setHeader(\x27Content-Disposition\x27, `inline; filename=\"${fileName}\"`);"
                );
                fs.writeFileSync(file, content);
            }
        }
        ' 2>/dev/null || true
    fi
}

has_node() {
    command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1
}

has_mongo() {
    command -v mongod >/dev/null 2>&1 || (command -v ss >/dev/null 2>&1 && ss -tulpn 2>/dev/null | grep -q ":27017\b") || (command -v netstat >/dev/null 2>&1 && netstat -tulpn 2>/dev/null | grep -q ":27017\b")
}

is_port_listening() {
    local p="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn 2>/dev/null | grep -q ":${p}\b"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulpn 2>/dev/null | grep -q ":${p}\b"
    elif command -v curl >/dev/null 2>&1; then
        curl -s -m 1 "http://127.0.0.1:${p}" >/dev/null 2>&1 || [ $? -eq 52 ]
    else
        return 1
    fi
}

open_in_browser() {
    local url="http://127.0.0.1:${PORT}"
    print_info "Opening browser at: ${url}"

    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        return 0
    fi

    if command -v x-www-browser >/dev/null 2>&1; then
        x-www-browser "${url}" >/dev/null 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "${url}" >/dev/null 2>&1 &
    elif command -v firefox >/dev/null 2>&1; then
        firefox "${url}" >/dev/null 2>&1 &
    elif command -v chromium >/dev/null 2>&1; then
        chromium "${url}" >/dev/null 2>&1 &
    fi
}

# -------------------------------------------------------------------------
# Status Dashboard
# -------------------------------------------------------------------------
show_status() {
    migrate_legacy_data
    print_header "LibreChat Localhost Status Dashboard"

    # 1. LibreChat Web Interface
    if is_port_listening "$PORT"; then
        print_pass "LibreChat is ACTIVE & LISTENING on http://127.0.0.1:${PORT}"
    else
        print_warn "LibreChat is NOT listening on port ${PORT}"
    fi

    # 2. MongoDB Database
    if is_port_listening 27017; then
        print_pass "MongoDB is ACTIVE on 127.0.0.1:27017 (Native Host)"
    elif has_docker && docker ps --filter "name=librechat_mongodb" --filter "status=running" 2>/dev/null | grep -q librechat_mongodb; then
        print_pass "MongoDB container (librechat_mongodb) is ACTIVE (Isolated Container Network)"
    else
        print_warn "MongoDB is NOT responding / running"
        if has_docker; then
            echo "   -> In Docker mode, MongoDB starts automatically with './setup-librechat.sh --docker' (or 'docker compose up -d')"
        elif has_docker_engine; then
            echo "   -> In Docker mode, install docker-compose ('sudo apt install -y docker-compose') then run './setup-librechat.sh --docker'"
        else
            echo "   -> In Native mode, start MongoDB via: sudo systemctl start mongod (or 'service mongodb start')"
        fi
    fi

    # 3. Local llama.cpp Integration
    if is_port_listening 8080; then
        print_pass "Local llama-server is ACTIVE on http://127.0.0.1:8080 (Ready for offline chat)"
    else
        print_info "Local llama-server is idle on port 8080. Start via: run-llama-server"
    fi

    # 4. Deployment Mode Check
    echo
    echo -e "${BOLD}Detected Prerequisites:${RESET}"
    if has_docker_engine; then
        local docker_ver
        docker_ver="$(docker --version 2>/dev/null | head -n1)"
        if has_docker_compose; then
            local compose_ver
            if docker compose version >/dev/null 2>&1; then
                compose_ver="$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null | head -n1)"
            else
                compose_ver="$(docker-compose --version 2>/dev/null | head -n1)"
            fi
            print_pass "Docker & Docker Compose: Available (${docker_ver}, ${compose_ver})"
        else
            print_warn "Docker Engine: Available (${docker_ver}), but Docker Compose is NOT installed"
            echo -e "   -> ${CYAN}Install Docker Compose via:${RESET} sudo apt install -y docker-compose"
        fi
    else
        print_info "Docker: Not found (Install via Setup-Dev-Tools if desired)"
    fi

    if has_node; then
        local node_ver
        node_ver=$(node -v 2>/dev/null || echo "Unknown")
        print_pass "Node.js (${node_ver}) & npm: Available"
    else
        print_info "Node.js: Not found"
    fi

    echo
}

# -------------------------------------------------------------------------
# Docker Mode Installation & Launch
# -------------------------------------------------------------------------
install_docker_mode() {
    print_header "Deploying LibreChat via Docker Compose (Turnkey Isolated Mode)"

    if ! has_docker_engine; then
        print_fail "Docker Engine is not installed on this system."
        echo "You can install Docker cleanly via Debian Dev Suite:"
        echo "  cd ../Setup-Dev-Tools && ./setup-dev-tools.sh --docker"
        exit 1
    fi

    if ! has_docker_compose; then
        print_fail "Docker Engine is installed, but Docker Compose (docker compose / docker-compose) was not found."
        echo "Docker Compose is required to run the LibreChat and MongoDB container stack."
        echo "You can install Docker Compose via:"
        echo "  sudo apt install -y docker-compose"
        exit 1
    fi

    if ! docker ps >/dev/null 2>&1; then
        print_fail "Cannot connect to Docker daemon."
        echo "Please ensure the Docker service is running and your user has permission:"
        echo "  sudo systemctl start docker (or 'sudo service docker start')"
        echo "  sudo usermod -aG docker \"$USER\" && newgrp docker"
        exit 1
    fi

    ensure_data_dir
    generate_secure_env

    # Ensure MONGO_URI in .env is configured for unified localhost networking
    if [ -f "$ENV_FILE" ]; then
        sed -i 's|^MONGO_URI=.*|MONGO_URI=mongodb://127.0.0.1:27017/LibreChat|g' "$ENV_FILE"
    fi

    echo "Starting Docker containers in background..."
    run_compose up -d
    ensure_image_styling

    echo
    print_pass "LibreChat and MongoDB containers are initializing!"
    echo "Access URL: http://127.0.0.1:${PORT}"
    open_in_browser
}

# -------------------------------------------------------------------------
# Native Node Mode Installation & Launch
# -------------------------------------------------------------------------
install_native_mode() {
    print_header "Deploying LibreChat via Native Node.js"

    if ! has_node; then
        print_fail "Node.js (v20+) and npm are required for native mode."
        echo "Install Node.js via Setup-Dev-Tools: cd ../Setup-Dev-Tools && ./setup-dev-tools.sh --install"
        exit 1
    fi

    generate_secure_env

    # Clone LibreChat if not present
    if [ ! -d "$APP_DIR" ]; then
        print_info "Cloning LibreChat repository (shallow clone)..."
        git clone --depth 1 https://github.com/LibreChat-AI/LibreChat.git "$APP_DIR"
    else
        print_pass "LibreChat source repository already present at $APP_DIR"
    fi

    # Link configuration
    cp -f "$ENV_FILE" "${APP_DIR}/.env"
    cp -f "$CONFIG_YAML" "${APP_DIR}/librechat.yaml"

    # Install dependencies
    print_info "Installing Node.js dependencies (this may take 2-3 minutes)..."
    (cd "$APP_DIR" && npm run reinstall || npm install)

    print_pass "Dependencies installed successfully!"

    # Verify MongoDB
    if ! is_port_listening 27017; then
        print_warn "MongoDB is not yet running on localhost:27017."
        echo "Please ensure MongoDB is active before launching the backend:"
        echo "  sudo systemctl start mongod || sudo service mongodb start"
    fi

    start_native_server
}

# -------------------------------------------------------------------------
# Start / Stop / Logs Services
# -------------------------------------------------------------------------
start_native_server() {
    if is_port_listening "$PORT"; then
        print_pass "LibreChat is already running on http://127.0.0.1:${PORT}"
        open_in_browser
        return 0
    fi

    if [ ! -d "$APP_DIR" ]; then
        print_fail "LibreChat source directory not found. Run: ./setup-librechat.sh --install"
        exit 1
    fi

    # Verify MongoDB is running
    if ! is_port_listening 27017; then
        print_fail "MongoDB is NOT running on localhost:27017."
        echo "Native LibreChat requires an active MongoDB database server."
        echo "Start native MongoDB: sudo systemctl start mongod (or 'sudo service mongodb start')"
        echo "Alternatively, use turnkey Docker mode (recommended): ./setup-librechat.sh --docker"
        exit 1
    fi

    # Check if compiled packages exist in LibreChat workspace
    if [ ! -f "${APP_DIR}/packages/api/dist/credentials.cjs" ] && [ ! -f "${APP_DIR}/node_modules/@librechat/api/dist/credentials.cjs" ]; then
        print_info "Building required LibreChat workspace packages (npm run build:api)..."
        (cd "$APP_DIR" && npm run build:api 2>/dev/null || npm run build 2>/dev/null || true)
        if [ ! -f "${APP_DIR}/packages/api/dist/credentials.cjs" ] && [ ! -f "${APP_DIR}/node_modules/@librechat/api/dist/credentials.cjs" ]; then
            print_fail "LibreChat workspace packages are not compiled (@librechat/api/dist/credentials.cjs missing)."
            echo "Recommendation: Use turnkey Docker mode which includes pre-compiled packages & MongoDB:"
            echo "  ./setup-librechat.sh --docker"
            exit 1
        fi
    fi

    print_info "Starting LibreChat native server in background..."
    nohup npm --prefix "$APP_DIR" run backend > /tmp/librechat.log 2>&1 &
    local s_pid=$!
    echo "$s_pid" > "$PID_FILE"

    sleep 2
    if kill -0 "$s_pid" 2>/dev/null; then
        print_pass "LibreChat server started (PID: ${s_pid})"
        echo "URL: http://127.0.0.1:${PORT}"
        open_in_browser
    else
        print_fail "Server failed to start. Last log lines:"
        tail -n 20 /tmp/librechat.log || true
        exit 1
    fi
}

start_service() {
    ensure_data_dir

    # 1. If LibreChat is already listening, just open browser and exit
    if is_port_listening "$PORT"; then
        print_pass "LibreChat is already running on http://127.0.0.1:${PORT}"
        open_in_browser
        return 0
    fi

    # 2. Prefer Docker Compose when Docker is available (Turnkey, pre-built, runs MongoDB container)
    if has_docker && ([ -f "$COMPOSE_FILE" ] || [ -f "${SCRIPT_DIR}/docker-compose.yml" ]); then
        print_info "Starting LibreChat & MongoDB stack via Docker Compose..."
        generate_secure_env
        if [ -f "$ENV_FILE" ]; then
            sed -i 's|^MONGO_URI=.*|MONGO_URI=mongodb://127.0.0.1:27017/LibreChat|g' "$ENV_FILE"
        fi
        run_compose up -d
        ensure_image_styling
        echo
        print_pass "LibreChat & MongoDB containers are starting in background!"
        echo "Access URL: http://127.0.0.1:${PORT}"
        open_in_browser
    # 3. Native mode fallback if LibreChat repository cloned
    elif [ -d "$APP_DIR" ]; then
        start_native_server
    # 4. Fallback to turnkey Docker setup
    elif has_docker; then
        install_docker_mode
    # 5. Fallback to native Node setup
    elif has_node; then
        install_native_mode
    else
        print_fail "Neither Docker nor Node.js environment detected. Run: ./setup-librechat.sh --help"
        exit 1
    fi
}

stop_service() {
    print_info "Stopping LibreChat services..."
    local stopped=false

    # 1. Check Docker
    if has_docker && [ -f "$COMPOSE_FILE" ]; then
        run_compose stop 2>/dev/null && stopped=true || true
    fi

    # 2. Check Native PID
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            stopped=true
        fi
        rm -f "$PID_FILE"
    fi

    # 3. Match any leftover LibreChat node process
    local pids
    pids=$(pgrep -f "node.*librechat" 2>/dev/null || echo "")
    if [ -n "$pids" ]; then
        kill $pids 2>/dev/null || true
        stopped=true
    fi

    if [ "$stopped" = true ]; then
        print_pass "LibreChat services stopped successfully."
    else
        print_info "No active LibreChat instance was running."
    fi
}

view_logs() {
    if has_docker && (docker ps -a 2>/dev/null | grep -q "librechat_app"); then
        run_compose logs -f --tail=100
    elif [ -f "/tmp/librechat.log" ]; then
        tail -f -n 100 /tmp/librechat.log
    else
        print_warn "No log files found."
    fi
}

install_desktop_launcher() {
    print_info "Installing desktop menu launcher and local CLI command..."
    local bin_dir="${HOME}/.local/bin"
    local apps_dir="${HOME}/.local/share/applications"

    mkdir -p "${bin_dir}" "${apps_dir}"

    # CLI Launcher Link
    ln -sf "${SCRIPT_DIR}/setup-librechat.sh" "${bin_dir}/librechat-localhost"
    print_pass "Installed CLI launcher: ${bin_dir}/librechat-localhost"

    # Desktop entry
    local desktop_file="${apps_dir}/librechat.desktop"
    cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=LibreChat (Localhost)
GenericName=Local AI Web Interface
Comment=100% Offline AI Chat Interface connecting to local llama.cpp
Exec=${bin_dir}/librechat-localhost --start
Icon=chat
Terminal=false
Categories=Network;Chat;Development;
Keywords=ai;chat;llm;llama;offline;librechat;
StartupNotify=true
EOF

    chmod +x "$desktop_file"
    print_pass "Installed desktop entry at $desktop_file"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
    fi
}

# -------------------------------------------------------------------------
# Autostart Mode Manager (On-Demand vs Auto-Start)
# -------------------------------------------------------------------------
manage_autostart() {
    local action="${1:-status}"
    local compose_candidates=("$COMPOSE_FILE" "${SCRIPT_DIR}/docker-compose.yml")

    case "$action" in
        disable|off|on-demand|--disable|--off|no)
            print_info "Configuring LibreChat stack for On-Demand mode (disabling autostart on boot)..."
            for cfile in "${compose_candidates[@]}"; do
                if [ -f "$cfile" ]; then
                    sed -i -E 's/restart:\s*(unless-stopped|always)/restart: "no"/g' "$cfile"
                fi
            done
            if has_docker_engine; then
                for c in librechat_app librechat_mongodb librechat_meilisearch; do
                    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
                        docker update --restart=no "$c" >/dev/null 2>&1 || true
                    fi
                done
            fi
            print_pass "Autostart is now DISABLED (On-Demand mode)."
            echo -e "   -> Docker will ${BOLD}NOT${RESET} auto-start LibreChat, MongoDB, or MeiliSearch on system boot."
            echo -e "   -> Start manually anytime via: ${CYAN}./setup-librechat.sh --start${RESET}"
            echo -e "   -> Stop manually anytime via:  ${CYAN}./setup-librechat.sh --stop${RESET}"
            ;;
        enable|on|auto|--enable|--on|yes|unless-stopped)
            print_info "Configuring LibreChat stack for Auto-Start mode (starts on system boot)..."
            for cfile in "${compose_candidates[@]}"; do
                if [ -f "$cfile" ]; then
                    sed -i -E 's/restart:\s*"no"/restart: unless-stopped/g' "$cfile"
                    sed -i -E 's/restart:\s*no/restart: unless-stopped/g' "$cfile"
                fi
            done
            if has_docker_engine; then
                for c in librechat_app librechat_mongodb librechat_meilisearch; do
                    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
                        docker update --restart=unless-stopped "$c" >/dev/null 2>&1 || true
                    fi
                done
            fi
            print_pass "Autostart is now ENABLED (Auto mode)."
            echo -e "   -> Docker will automatically start LibreChat & MongoDB stack on system boot."
            ;;
        status|--status)
            local current_policy="unknown"
            if [ -f "$COMPOSE_FILE" ]; then
                if grep -q -E 'restart:\s*("no"|no)' "$COMPOSE_FILE"; then
                    current_policy="no"
                elif grep -q -E 'restart:\s*(unless-stopped|always)' "$COMPOSE_FILE"; then
                    current_policy="unless-stopped"
                fi
            fi
            if [ "$current_policy" = "unknown" ] && has_docker_engine; then
                local live_pol
                live_pol="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' librechat_app 2>/dev/null || echo "")"
                if [ -n "$live_pol" ]; then
                    current_policy="$live_pol"
                fi
            fi

            echo
            echo -e "${BOLD}LibreChat Autostart Mode:${RESET}"
            if [ "$current_policy" = "no" ]; then
                echo -e "  Status : ${YELLOW}On-Demand (Autostart disabled, manual start only)${RESET}"
                echo -e "  Toggle : Run './setup-librechat.sh --autostart on' to switch to auto-start"
            elif [ "$current_policy" = "unless-stopped" ] || [ "$current_policy" = "always" ]; then
                echo -e "  Status : ${GREEN}Auto-Start (Restarts automatically on system boot via Docker)${RESET}"
                echo -e "  Toggle : Run './setup-librechat.sh --autostart off' to switch to on-demand"
            else
                echo -e "  Status : ${YELLOW}Not configured or running native Node.js${RESET}"
            fi
            echo
            ;;
        *)
            print_fail "Unknown autostart option: '$action'"
            echo "Usage: ./setup-librechat.sh --autostart [on|off|status]   (or: enable|disable)"
            exit 1
            ;;
    esac
}

# -------------------------------------------------------------------------
# Interactive Turnkey Installation
# -------------------------------------------------------------------------
turnkey_install() {
    print_header "Starting Turnkey Setup for LibreChat"

    echo "LibreChat provides a ChatGPT-style web UI for local and cloud models."
    echo "Debian Dev Suite configures it strictly on 127.0.0.1 with ZERO telemetry."
    echo

    if has_docker; then
        print_info "Docker & Docker Compose environment detected. Docker Compose is the recommended turnkey method."
        install_docker_mode
    elif has_docker_engine; then
        print_warn "Docker Engine is installed, but Docker Compose is missing."
        echo "LibreChat requires Docker Compose to run in container mode."
        echo "To install Docker Compose: sudo apt install -y docker-compose"
        echo
        if has_node; then
            print_info "Falling back to Native Node.js $(node -v) installation..."
            install_native_mode
        else
            print_fail "Neither Docker Compose nor Node.js is ready."
            exit 1
        fi
    elif has_node; then
        print_info "Node.js $(node -v) environment detected."
        install_native_mode
    else
        print_fail "Neither Docker nor Node.js (v20+) is installed."
        echo "To install Docker and development runtimes:"
        echo "  cd ../Setup-Dev-Tools && ./setup-dev-tools.sh --install"
        exit 1
    fi

    install_desktop_launcher
}

# -------------------------------------------------------------------------
# Command Dispatch
# -------------------------------------------------------------------------
ACTION="install"
AUTOSTART_ARG="status"

if [ $# -gt 0 ]; then
    case "$1" in
        --install|-i|install)
            ACTION="install"
            ;;
        --docker|docker)
            ACTION="docker"
            ;;
        --native|--local|native)
            ACTION="native"
            ;;
        --start|start)
            ACTION="start"
            ;;
        --stop|stop)
            ACTION="stop"
            ;;
        --status|-s|status)
            ACTION="status"
            ;;
        --autostart|autostart)
            ACTION="autostart"
            AUTOSTART_ARG="${2:-status}"
            ;;
        --on-demand|on-demand)
            ACTION="autostart"
            AUTOSTART_ARG="off"
            ;;
        --auto|auto)
            ACTION="autostart"
            AUTOSTART_ARG="on"
            ;;
        --logs|logs)
            ACTION="logs"
            ;;
        --install-desktop|desktop)
            ACTION="desktop"
            ;;
        --uninstall|uninstall)
            ACTION="uninstall"
            ;;
        --help|-h|help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown command: $1${RESET}"
            show_help
            exit 1
            ;;
    esac
fi

case "$ACTION" in
    install)
        turnkey_install
        ;;
    docker)
        install_docker_mode
        install_desktop_launcher
        ;;
    native)
        install_native_mode
        install_desktop_launcher
        ;;
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    status)
        show_status
        ;;
    autostart)
        manage_autostart "$AUTOSTART_ARG"
        ;;
    logs)
        view_logs
        ;;
    desktop)
        install_desktop_launcher
        ;;
    uninstall)
        stop_service
        print_info "To completely remove all data, run: rm -rf ${DATA_DIR}"
        ;;
esac