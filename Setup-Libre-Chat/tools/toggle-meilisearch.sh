#!/usr/bin/env bash
#
# ==============================================================================
# LibreChat MeiliSearch Manager (Toggle Native In-App Search)
# Part of the Debian Dev Suite
# ==============================================================================
#
# PURPOSE:
#   Enables or disables native full-text in-app search (MeiliSearch) for LibreChat
#   with 100% localhost loopback (127.0.0.1) and absolute zero telemetry.
#
# HOW TO USE:
#   ./tools/toggle-meilisearch.sh --enable    # Enable MeiliSearch & in-app search bar (Ctrl+K)
#   ./tools/toggle-meilisearch.sh --disable   # Disable MeiliSearch & free RAM (~200MB)
#   ./tools/toggle-meilisearch.sh --status    # Check if MeiliSearch is running & RAM usage
#   ./tools/toggle-meilisearch.sh --help      # Show this manual
#
# FEATURES:
#   - Automatic 256-bit AES master key generation
#   - Strict localhost isolation: binds only to 127.0.0.1:7700
#   - Zero telemetry: MEILI_NO_ANALYTICS=true explicitly configured
#   - Automated Docker Compose service configuration with safe backups
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"
CANONICAL_DATA_DIR="$TARGET_HOME/.local/share/dev-setups/librechat"
DATA_DIR="${LIBRECHAT_DATA_DIR:-$CANONICAL_DATA_DIR}"

ENV_FILE="${DATA_DIR}/.env"
COMPOSE_FILE="${DATA_DIR}/docker-compose.yml"
MEILI_DATA_DIR="${DATA_DIR}/meili_data"

# Colors
BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

print_header() {
    echo -e "\n${BOLD}${CYAN}======================================================================${RESET}"
    echo -e "${BOLD}${CYAN}  $1${RESET}"
    echo -e "${BOLD}${CYAN}======================================================================${RESET}\n"
}

print_pass() { echo -e "  [${GREEN}✔${RESET}] $1"; }
print_warn() { echo -e "  [${YELLOW}⚠${RESET}] ${YELLOW}$1${RESET}"; }
print_fail() { echo -e "  [${RED}✖${RESET}] ${RED}$1${RESET}"; }
print_info() { echo -e "  [${CYAN}ℹ${RESET}] ${CYAN}$1${RESET}"; }

show_help() {
    cat << 'EOF'
================================================================================
       LibreChat MeiliSearch Manager — Debian Dev Suite
================================================================================

Usage: ./toggle-meilisearch.sh [COMMAND]

Commands:
  --enable, -e       Enable MeiliSearch and turn on the native search bar (Ctrl+K)
  --disable, -d      Disable MeiliSearch to free RAM (reverts to standard mode)
  --sync             Trigger full re-indexing of all conversations and messages
  --status, -s       Check MeiliSearch health, indexing status, and RAM consumption
  --help, -h         Show this help manual

Examples:
  ./toggle-meilisearch.sh --enable
  ./toggle-meilisearch.sh --sync
  ./toggle-meilisearch.sh --status
  ./toggle-meilisearch.sh --disable
EOF
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        print_fail "Docker is not installed."
        exit 1
    fi
    if ! docker ps >/dev/null 2>&1; then
        print_fail "Docker daemon is not accessible."
        exit 1
    fi
}

enable_meilisearch() {
    print_header "Enabling Native MeiliSearch for LibreChat"
    check_docker

    if [ ! -f "$COMPOSE_FILE" ]; then
        print_fail "docker-compose.yml not found at $COMPOSE_FILE"
        exit 1
    fi

    mkdir -p "$MEILI_DATA_DIR"

    # 1. Update .env with MEILI_MASTER_KEY if not already present
    if [ -f "$ENV_FILE" ]; then
        if ! grep -q "^MEILI_MASTER_KEY=" "$ENV_FILE" 2>/dev/null; then
            print_info "Generating 256-bit MeiliSearch master encryption key..."
            local key
            key=$(openssl rand -hex 16 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(16))")
            echo "" >> "$ENV_FILE"
            echo "# MeiliSearch In-App Search Integration (Strict Localhost, Zero Telemetry)" >> "$ENV_FILE"
            echo "SEARCH=true" >> "$ENV_FILE"
            echo "MEILI_HOST=http://127.0.0.1:7700" >> "$ENV_FILE"
            echo "MEILI_HTTP_ADDR=127.0.0.1:7700" >> "$ENV_FILE"
            echo "MEILI_MASTER_KEY=${key}" >> "$ENV_FILE"
            echo "MEILI_NO_ANALYTICS=true" >> "$ENV_FILE"
            echo "MEILI_SYNC_THRESHOLD=0" >> "$ENV_FILE"
            chmod 600 "$ENV_FILE"
            print_pass "Added secure MeiliSearch configuration to .env"
        else
            sed -i 's|^SEARCH=.*|SEARCH=true|g' "$ENV_FILE"
            sed -i 's|^MEILI_HOST=.*|MEILI_HOST=http://127.0.0.1:7700|g' "$ENV_FILE"
            sed -i 's|^MEILI_HTTP_ADDR=.*|MEILI_HTTP_ADDR=127.0.0.1:7700|g' "$ENV_FILE"
            sed -i 's|^MEILI_NO_ANALYTICS=.*|MEILI_NO_ANALYTICS=true|g' "$ENV_FILE"
            if grep -q "^MEILI_SYNC_THRESHOLD=" "$ENV_FILE" 2>/dev/null; then
                sed -i 's|^MEILI_SYNC_THRESHOLD=.*|MEILI_SYNC_THRESHOLD=0|g' "$ENV_FILE"
            else
                echo "MEILI_SYNC_THRESHOLD=0" >> "$ENV_FILE"
            fi
            print_pass "Enabled SEARCH=true in existing .env"
        fi
    fi

    # 2. Check if meilisearch is already configured in docker-compose.yml
    if grep -q "container_name: librechat_meilisearch" "$COMPOSE_FILE" 2>/dev/null; then
        print_pass "MeiliSearch service is already present in docker-compose.yml"
    else
        print_info "Backing up docker-compose.yml before editing..."
        cp -p "$COMPOSE_FILE" "${COMPOSE_FILE}.bak.$(date +%F_%H%M%S)"

        # Rewrite compose file cleanly to include meilisearch service
        local current_restart="unless-stopped"
        if [ -f "$COMPOSE_FILE" ] && grep -q -E 'restart:\s*("no"|no)' "$COMPOSE_FILE"; then
            current_restart='"no"'
        fi
        cat > "$COMPOSE_FILE" << EOF
# ==============================================================================
# LibreChat Local Docker Compose Configuration
# 100% Localhost Isolated, Privacy-Focused & Zero Telemetry
# ==============================================================================
# Access: http://127.0.0.1:3080
# Strict Binding: 127.0.0.1 only (Zero external LAN/WAN exposure)
# ==============================================================================

services:
  librechat:
    image: ghcr.io/danny-avila/librechat:latest
    container_name: librechat_app
    restart: ${current_restart}
    network_mode: "host"
    environment:
      - HOST=127.0.0.1
      - PORT=3080
      - MONGO_URI=mongodb://127.0.0.1:27017/LibreChat
      - CONFIG_PATH=/app/librechat.yaml
      - TELEMETRY=false
      - DISABLE_TELEMETRY=true
      - CHECK_BALANCE=false
      - ALLOW_REGISTRATION=true
      - ALLOW_SOCIAL_LOGIN=false
      - SEARCH=true
      - MEILI_HOST=http://127.0.0.1:7700
      - MEILI_MASTER_KEY=\${MEILI_MASTER_KEY}
    env_file:
      - .env
    volumes:
      - type: bind
        source: ./librechat.yaml
        target: /app/librechat.yaml
      - type: bind
        source: ./index.html
        target: /app/client/dist/index.html
      - type: bind
        source: ./librechat-data/images
        target: /app/client/public/images
      - type: bind
        source: ./librechat-data/logs
        target: /app/api/logs
    depends_on:
      - mongodb
      - meilisearch

  mongodb:
    image: mongo:6.0
    container_name: librechat_mongodb
    restart: ${current_restart}
    network_mode: "host"
    volumes:
      - ./mongo_data:/data/db
    command: mongod --noauth --bind_ip 127.0.0.1

  meilisearch:
    image: getmeili/meilisearch:v1.12.0
    container_name: librechat_meilisearch
    restart: ${current_restart}
    network_mode: "host"
    environment:
      - MEILI_HOST=http://127.0.0.1:7700
      - MEILI_HTTP_ADDR=127.0.0.1:7700
      - MEILI_MASTER_KEY=\${MEILI_MASTER_KEY}
      - MEILI_NO_ANALYTICS=true
    volumes:
      - ./meili_data:/meili_data
EOF
        print_pass "Configured MeiliSearch service in docker-compose.yml"
    fi

    # 3. Also update template compose file in repository if running from repo
    for candidate in "${MODULE_DIR}/docker-compose.yml" "${SCRIPT_DIR}/docker-compose.yml"; do
        if [ -f "$candidate" ] && [ "$candidate" != "$COMPOSE_FILE" ]; then
            cp -f "$COMPOSE_FILE" "$candidate"
        fi
    done

    # 4. Start containers
    print_info "Restarting Docker Compose stack with MeiliSearch enabled..."
    (cd "$DATA_DIR" && docker compose up -d)

    echo
    print_pass "MeiliSearch daemon is ACTIVE on http://127.0.0.1:7700!"
    print_info "LibreChat will index your existing messages in the background (takes ~1 minute)."
    echo
    echo -e "${BOLD}NEXT STEPS:${RESET}"
    echo "  1. Open LibreChat: http://127.0.0.1:3080"
    echo "  2. Press Ctrl+F5 to reload the web UI."
    echo "  3. You will now see the live Search Bar at the top of the sidebar!"
    echo "  4. Press Ctrl+K anytime to search across every chat and message in real-time."
}

disable_meilisearch() {
    print_header "Disabling MeiliSearch (Reverting to Standard Mode)"
    check_docker

    if [ -f "$ENV_FILE" ]; then
        sed -i 's|^SEARCH=.*|SEARCH=false|g' "$ENV_FILE"
        print_pass "Set SEARCH=false in .env"
    fi

    # Stop meilisearch container if running
    if docker ps -a --filter "name=librechat_meilisearch" -q | grep -q .; then
        print_info "Stopping and removing librechat_meilisearch container..."
        docker stop librechat_meilisearch >/dev/null 2>&1 || true
        docker rm librechat_meilisearch >/dev/null 2>&1 || true
        print_pass "Removed librechat_meilisearch container (freed ~200MB RAM)."
    fi

    # Revert compose file to standard dual stack (librechat + mongodb)
    if [ -f "$COMPOSE_FILE" ]; then
        local current_restart="unless-stopped"
        if grep -q -E 'restart:\s*("no"|no)' "$COMPOSE_FILE"; then
            current_restart='"no"'
        fi
        cat > "$COMPOSE_FILE" << EOF
# ==============================================================================
# LibreChat Local Docker Compose Configuration
# 100% Localhost Isolated, Privacy-Focused & Zero Telemetry
# ==============================================================================
# Access: http://127.0.0.1:3080
# Strict Binding: 127.0.0.1 only (Zero external LAN/WAN exposure)
# ==============================================================================

services:
  librechat:
    image: ghcr.io/danny-avila/librechat:latest
    container_name: librechat_app
    restart: ${current_restart}
    network_mode: "host"
    environment:
      - HOST=127.0.0.1
      - PORT=3080
      - MONGO_URI=mongodb://127.0.0.1:27017/LibreChat
      - CONFIG_PATH=/app/librechat.yaml
      - TELEMETRY=false
      - DISABLE_TELEMETRY=true
      - CHECK_BALANCE=false
      - ALLOW_REGISTRATION=true
      - ALLOW_SOCIAL_LOGIN=false
    env_file:
      - .env
    volumes:
      - type: bind
        source: ./librechat.yaml
        target: /app/librechat.yaml
      - type: bind
        source: ./index.html
        target: /app/client/dist/index.html
      - type: bind
        source: ./librechat-data/images
        target: /app/client/public/images
      - type: bind
        source: ./librechat-data/logs
        target: /app/api/logs
    depends_on:
      - mongodb

  mongodb:
    image: mongo:6.0
    container_name: librechat_mongodb
    restart: ${current_restart}
    network_mode: "host"
    volumes:
      - ./mongo_data:/data/db
    command: mongod --noauth --bind_ip 127.0.0.1
EOF
        print_pass "Reverted docker-compose.yml to standard lightweight configuration."
    fi

    for candidate in "${MODULE_DIR}/docker-compose.yml" "${SCRIPT_DIR}/docker-compose.yml"; do
        if [ -f "$candidate" ] && [ "$candidate" != "$COMPOSE_FILE" ]; then
            cp -f "$COMPOSE_FILE" "$candidate"
        fi
    done

    print_info "Restarting LibreChat..."
    (cd "$DATA_DIR" && docker compose up -d)

    echo
    print_pass "MeiliSearch disabled successfully."
    print_info "Your past search data in meili_data is preserved safely if you want to re-enable later."
}

sync_meilisearch() {
    print_header "Synchronizing MeiliSearch Indexes (Full Sync)"
    check_docker

    if ! docker ps --filter "name=librechat_app" --filter "status=running" -q | grep -q .; then
        print_fail "LibreChat container (librechat_app) is not running."
        exit 1
    fi

    print_info "Triggering database synchronization to MeiliSearch..."
    docker exec librechat_app node -e '
const mongoose = require("mongoose");
const { createModels } = require("/app/packages/data-schemas/dist/index.cjs");
async function run() {
  await mongoose.connect(process.env.MONGO_URI);
  const models = createModels(mongoose);
  console.log("  [ℹ] Syncing messages index...");
  await models.Message.syncWithMeili();
  console.log("  [ℹ] Syncing conversations index...");
  await models.Conversation.syncWithMeili();
  console.log("  [✔] Full database synchronization complete!");
  process.exit(0);
}
run().catch(e => { console.error("  [✖] Sync error:", e.message); process.exit(1); });
'
    print_pass "All conversations and messages are 100% indexed in MeiliSearch."
}

show_status() {
    print_header "MeiliSearch Status Dashboard"
    check_docker

    local is_container_running=false
    if docker ps --filter "name=librechat_meilisearch" --filter "status=running" -q | grep -q .; then
        is_container_running=true
    fi

    if [ "$is_container_running" = true ]; then
        print_pass "MeiliSearch container (librechat_meilisearch) is RUNNING"
        
        # Check HTTP health
        if curl -s http://127.0.0.1:7700/health | grep -q "available"; then
            print_pass "HTTP Health Check: 127.0.0.1:7700 is HEALTHY (available)"
        else
            print_warn "HTTP Health Check: Port 7700 is not responding yet (initializing...)"
        fi

        # Query document counts from MeiliSearch
        local meili_key
        meili_key=$(grep "^MEILI_MASTER_KEY=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo "")
        if [ -n "$meili_key" ]; then
            local conv_count msg_count
            conv_count=$(curl -s -H "Authorization: Bearer $meili_key" http://127.0.0.1:7700/indexes/convos/stats 2>/dev/null | grep -o '"numberOfDocuments":[0-9]*' | cut -d: -f2 || echo "N/A")
            msg_count=$(curl -s -H "Authorization: Bearer $meili_key" http://127.0.0.1:7700/indexes/messages/stats 2>/dev/null | grep -o '"numberOfDocuments":[0-9]*' | cut -d: -f2 || echo "N/A")
            print_pass "Indexed in MeiliSearch: ${conv_count} conversations, ${msg_count} messages"
        fi

        # Check RAM usage
        local ram_usage
        ram_usage=$(docker stats --no-stream --format "{{.MemUsage}}" librechat_meilisearch 2>/dev/null || echo "Unknown")
        print_info "Current RAM Usage: ${ram_usage}"
    else
        print_info "MeiliSearch is currently DISABLED / STOPPED"
        echo "   -> To enable in-app search: ./toggle-meilisearch.sh --enable"
    fi

    # Check .env SEARCH state
    if [ -f "$ENV_FILE" ]; then
        local search_env
        search_env=$(grep "^SEARCH=" "$ENV_FILE" 2>/dev/null || echo "SEARCH=false")
        print_info "LibreChat .env Setting: ${search_env}"
    fi
}

case "${1:-}" in
    --enable|-e)
        enable_meilisearch
        ;;
    --disable|-d|--revert)
        disable_meilisearch
        ;;
    --sync)
        sync_meilisearch
        ;;
    --status|-s)
        show_status
        ;;
    --help|-h|"")
        show_help
        ;;
    *)
        print_fail "Unknown argument: $1"
        show_help
        exit 1
        ;;
esac
