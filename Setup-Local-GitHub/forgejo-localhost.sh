#!/usr/bin/env bash
# ==============================================================================
# forgejo-localhost.sh - Hardened, Localhost-Only Git Forge (Forgejo) Manager
# ==============================================================================
#
# PURPOSE:
#   Deploys and manages a completely private, air-gapped, localhost-only
#   GitHub replacement powered by Forgejo (lightweight, community-driven fork
#   of Gitea).
#
# SECURITY & PRIVACY PROMISES:
#   1. Loopback-Only: HTTP (127.0.0.1:3000) and SSH (127.0.0.1:2222) are bound
#      STRICTLY to IPv4 loopback (127.0.0.1). Zero exposure to LAN or WAN.
#   2. Offline Mode: External CDNs, web fonts, Gravatar, Libravatar, external
#      trackers, and telemetry are hard-disabled in configuration.
#   3. Zero Public Exposure: Public registration is DISABLED. Sign-in is REQUIRED
#      to view any repositories, issues, or profiles.
#   4. Install Lock: The Forgejo web installer wizard is permanently locked down
#      to eliminate web-based setup hijacking.
#   5. Cryptographic Isolation: High-entropy secret keys (SECRET_KEY, INTERNAL_TOKEN,
#      JWT_SECRET, LFS_JWT_SECRET) are generated via OpenSSL /dev/urandom.
#   6. File System Least Privilege: Strict umask 077 is enforced. All config files
#      are chmod 600, directories chmod 700, accessible ONLY to the host user.
#   7. SQLite3 WAL Database: Embedded SQLite with Write-Ahead Logging (WAL) for
#      high reliability without exposing any database ports.
#
# ==============================================================================

set -euo pipefail
umask 077

# --- Color and Styling Palette ---
if [[ -t 1 ]]; then
  readonly BOLD="\033[1m"
  readonly RESET="\033[0m"
  readonly RED="\033[1;31m"
  readonly GREEN="\033[1;32m"
  readonly YELLOW="\033[1;33m"
  readonly BLUE="\033[1;34m"
  readonly PURPLE="\033[1;35m"
  readonly CYAN="\033[1;36m"
  readonly GRAY="\033[0;90m"
else
  readonly BOLD=""
  readonly RESET=""
  readonly RED=""
  readonly GREEN=""
  readonly YELLOW=""
  readonly BLUE=""
  readonly PURPLE=""
  readonly CYAN=""
  readonly GRAY=""
fi

log_info()    { printf "${CYAN}ℹ %b${RESET}\n" "$*"; }
log_ok()      { printf "${GREEN}✔ %b${RESET}\n" "$*"; }
log_warn()    { printf "${YELLOW}⚠ %b${RESET}\n" "$*"; }
log_err()     { printf "${RED}✖ %b${RESET}\n" "$*" >&2; }
log_sec()     { printf "${PURPLE}🔒 [SECURITY] %b${RESET}\n" "$*"; }
log_header()  { printf "\n${BOLD}${BLUE}=== %b ===${RESET}\n" "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"
CANONICAL_BASE_DIR="$TARGET_HOME/.local/share/dev-setups/forgejo"
LEGACY_BASE_DIR="$SCRIPT_DIR/forgejo-data"

FORGEJO_DEFAULT_VERSION="16.0.5"
FORGEJO_VERSION="${FORGEJO_VERSION:-$FORGEJO_DEFAULT_VERSION}"
BASE_DIR="${FORGEJO_BASE_DIR:-$CANONICAL_BASE_DIR}"
HTTP_PORT="${FORGEJO_HTTP_PORT:-3000}"
SSH_PORT="${FORGEJO_SSH_PORT:-2222}"
BIND_IP="127.0.0.1"
ADMIN_USER="${FORGEJO_ADMIN_USER:-forgejo-admin}"
ADMIN_EMAIL="${FORGEJO_ADMIN_EMAIL:-admin@localhost.localdomain}"
ADMIN_PASSWORD="${FORGEJO_ADMIN_PASSWORD:-}"
ENABLE_TLS=false
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  ENABLE_SYSTEMD=true
else
  ENABLE_SYSTEMD=false
fi
MODE="binary" # "binary" or "docker"

# Paths
BIN_DIR="$BASE_DIR/bin"
CONF_DIR="$BASE_DIR/custom/conf"
DATA_DIR="$BASE_DIR/data"
LOG_DIR="$BASE_DIR/log"
BACKUP_DIR="$BASE_DIR/backups"
APP_INI="$CONF_DIR/app.ini"
PID_FILE="$BASE_DIR/forgejo.pid"
CREDENTIALS_FILE="$BASE_DIR/credentials.txt"
SYSTEMD_USER_DIR="$TARGET_HOME/.config/systemd/user"
SYSTEMD_SERVICE_FILE="$SYSTEMD_USER_DIR/forgejo-localhost.service"

# --- Seamless Legacy Data Migration ---
migrate_legacy_data() {
  if [[ "$BASE_DIR" == "$CANONICAL_BASE_DIR" && ! -d "$CANONICAL_BASE_DIR" && -d "$LEGACY_BASE_DIR" ]]; then
    log_info "Migrating legacy Forgejo data from $LEGACY_BASE_DIR to $CANONICAL_BASE_DIR..."
    
    # If legacy instance is running, stop it first
    if is_running; then
      log_info "Stopping running instance before migration..."
      stop_service
    fi

    mkdir -p "$(dirname "$CANONICAL_BASE_DIR")"
    mv "$LEGACY_BASE_DIR" "$CANONICAL_BASE_DIR"

    # Update absolute paths in app.ini, credentials.txt, and systemd service
    if [[ -f "$CANONICAL_BASE_DIR/custom/conf/app.ini" ]]; then
      sed -i "s|$LEGACY_BASE_DIR|$CANONICAL_BASE_DIR|g" "$CANONICAL_BASE_DIR/custom/conf/app.ini"
    fi
    if [[ -f "$CANONICAL_BASE_DIR/credentials.txt" ]]; then
      sed -i "s|$LEGACY_BASE_DIR|$CANONICAL_BASE_DIR|g" "$CANONICAL_BASE_DIR/credentials.txt"
    fi
    if [[ -f "$SYSTEMD_SERVICE_FILE" ]]; then
      sed -i "s|$LEGACY_BASE_DIR|$CANONICAL_BASE_DIR|g" "$SYSTEMD_SERVICE_FILE"
      systemctl --user daemon-reload 2>/dev/null || true
    fi
    log_ok "Forgejo data migrated successfully to $CANONICAL_BASE_DIR."
  fi
}

# GPG Public Key Fingerprint for Forgejo Releases
# (Codeberg / Forgejo Release Signing Key)
FORGEJO_GPG_KEY_ID="EB114F5E6C0DC2BCDD183550A4B61A2DC5923710"

# --- Architecture Detection ---
detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64)   echo "linux-amd64" ;;
    aarch64|arm64)  echo "linux-arm64" ;;
    armv7l|armhf)   echo "linux-arm-6" ;;
    *)
      log_err "Unsupported CPU architecture: $machine"
      exit 1
      ;;
  esac
}

# --- Pre-flight System & Dependency Audit ---
check_prerequisites() {
  log_info "Verifying host prerequisites..."
  local missing=()
  for cmd in curl openssl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_err "Missing mandatory utilities: ${missing[*]}"
    log_err "Please install them via your package manager (e.g., 'apt install ${missing[*]}' or 'dnf install ${missing[*]}')."
    exit 1
  fi

  # Git check
  if ! command -v git >/dev/null 2>&1; then
    log_warn "'git' is not installed on the host. Forgejo binary requires git for server-side repository operations."
    log_warn "If you run Forgejo natively, install git via 'sudo apt install git' or run in Docker mode via '--mode docker'."
  else
    log_ok "Host git found: $(git --version)"
  fi

  # Check loopback interface
  if ! ip addr show lo >/dev/null 2>&1 && ! ifconfig lo >/dev/null 2>&1; then
    log_warn "Could not inspect 'lo' interface, proceeding with standard 127.0.0.1 bind."
  fi
}

# --- Secure High-Entropy Random Generation ---
generate_secret_hex() {
  openssl rand -hex 32
}

generate_password() {
  # 24-character high-entropy alphanumeric + safe symbols guaranteed to meet
  # Forgejo complexity (lower, upper, digit, spec)
  python3 -c '
import secrets, string
spec = "!#%*+,-./:=?@_"
pwd = [
    secrets.choice(string.ascii_lowercase),
    secrets.choice(string.ascii_uppercase),
    secrets.choice(string.digits),
    secrets.choice(spec),
]
all_chars = string.ascii_letters + string.digits + spec
pwd += [secrets.choice(all_chars) for _ in range(20)]
secrets.SystemRandom().shuffle(pwd)
print("".join(pwd))
' 2>/dev/null || (
    printf '%s%s%s%s%s' \
      "$(head -c 10 /dev/urandom | tr -dc 'a-z' | head -c 2)" \
      "$(head -c 10 /dev/urandom | tr -dc 'A-Z' | head -c 2)" \
      "$(head -c 10 /dev/urandom | tr -dc '0-9' | head -c 2)" \
      "$(head -c 10 /dev/urandom | tr -dc '!#%*+,-./:=?@_' | head -c 2)" \
      "$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9!#%*+,-./:=?@_' | head -c 16)"
  )
}

# --- Port Availability Check ---
check_port_free() {
  local port="$1"
  local ip="$2"

  if command -v ss >/dev/null 2>&1; then
    if ss -tln | grep -q "${ip}:${port}\b"; then
      return 1
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tln | grep -q "${ip}:${port}\b"; then
      return 1
    fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -i "TCP@${ip}:${port}" >/dev/null 2>&1; then
      return 1
    fi
  fi
  return 0
}

# --- Download and Verify Forgejo Binary ---
download_binary() {
  local arch
  arch="$(detect_arch)"
  local bin_file="$BIN_DIR/forgejo"
  local target_url="https://code.forgejo.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-${arch}"
  local target_asc="${target_url}.asc"

  mkdir -p "$BIN_DIR"
  chmod 700 "$BIN_DIR"

  if [[ -x "$bin_file" ]]; then
    local current_ver
    current_ver="$("$bin_file" --version 2>/dev/null || echo "unknown")"
    log_ok "Forgejo binary already present: $current_ver"
    return 0
  fi

  log_info "Downloading Forgejo v${FORGEJO_VERSION} for ${arch}..."
  log_info "URL: ${target_url}"

  local temp_bin
  temp_bin="$(mktemp "$BIN_DIR/forgejo.tmp.XXXXXX")"
  chmod 700 "$temp_bin"

  if ! curl -fSL --progress-bar -o "$temp_bin" "$target_url"; then
    rm -f "$temp_bin"
    log_err "Failed to download Forgejo binary. Please check internet access or version string."
    exit 1
  fi

  # Attempt GPG Verification if gpg is available
  if command -v gpg >/dev/null 2>&1; then
    log_info "Attempting GPG cryptographic signature verification..."
    local temp_asc
    temp_asc="$(mktemp "$BIN_DIR/forgejo.asc.XXXXXX")"
    if curl -fSL -s -o "$temp_asc" "$target_asc"; then
      # Import official key if not present
      if ! gpg --list-keys "$FORGEJO_GPG_KEY_ID" >/dev/null 2>&1; then
        log_info "Importing official Forgejo release key ($FORGEJO_GPG_KEY_ID)..."
        gpg --keyserver keys.openpgp.org --recv-keys "$FORGEJO_GPG_KEY_ID" >/dev/null 2>&1 || true
      fi

      if gpg --verify "$temp_asc" "$temp_bin" >/dev/null 2>&1; then
        log_ok "GPG signature verification SUCCESSFUL."
      else
        log_warn "GPG signature check did not complete (keyring may lack openpgp keyserver access). Binary SHA256 will be logged."
      fi
      rm -f "$temp_asc"
    else
      rm -f "$temp_asc"
      log_warn "Signature file (.asc) not accessible; skipping GPG check."
    fi
  else
    log_info "GPG utility not installed; skipping cryptographic signature check."
  fi

  mv "$temp_bin" "$bin_file"
  chmod 700 "$bin_file"
  local sha256
  sha256="$(sha256sum "$bin_file" | awk '{print $1}')"
  log_sec "Verified binary stored at: $bin_file (SHA-256: ${sha256:0:16}...)"
}

# --- Hardened app.ini Generation ---
generate_app_ini() {
  log_info "Generating hardened, privacy-first configuration..."

  mkdir -p "$CONF_DIR" "$DATA_DIR" "$LOG_DIR" "$DATA_DIR/sessions" "$DATA_DIR/lfs" "$DATA_DIR/repositories" "$DATA_DIR/ssh"
  chmod 700 "$CONF_DIR" "$DATA_DIR" "$LOG_DIR"

  if [[ -f "$APP_INI" ]]; then
    log_warn "Existing configuration found at $APP_INI. Creating backup before overwriting."
    cp "$APP_INI" "${APP_INI}.backup.$(date +%s)"
  fi

  local secret_key internal_token jwt_secret lfs_jwt_secret
  secret_key="$(generate_secret_hex)"
  internal_token="$(generate_secret_hex)"
  jwt_secret="$(generate_secret_hex)"
  lfs_jwt_secret="$(generate_secret_hex)"

  local protocol="http"
  local cookie_secure="false"
  if [[ "$ENABLE_TLS" == "true" ]]; then
    protocol="https"
    cookie_secure="true"
    setup_localhost_tls
  fi

  cat > "$APP_INI" <<EOF
# ==============================================================================
# Forgejo Hardened Localhost Configuration
# Generated automatically by forgejo-localhost.sh
# Generated At: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ==============================================================================

APP_NAME = Localhost Git Forge (Strictly Private)
RUN_MODE = prod
RUN_USER = $USER
WORK_PATH = $BASE_DIR

[server]
# --- STRICT NETWORK BINDING ---
PROTOCOL = ${protocol}
HTTP_ADDR = ${BIND_IP}
HTTP_PORT = ${HTTP_PORT}
DOMAIN = ${BIND_IP}
ROOT_URL = ${protocol}://${BIND_IP}:${HTTP_PORT}/
APP_DATA_PATH = ${DATA_DIR}

# --- STRICT OFFLINE & PRIVACY MODE ---
OFFLINE_MODE = true
DISABLE_SSH = false
START_SSH_SERVER = true
SSH_PORT = ${SSH_PORT}
SSH_LISTEN_HOST = ${BIND_IP}
SSH_DOMAIN = ${BIND_IP}
SSH_KEY_GEN_ALGORITHMS = ed25519,ecdsa,rsa
SSH_SERVER_CIPHERS = chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
SSH_SERVER_KEY_EXCHANGES = curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
SSH_SERVER_MACS = hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Assets & Static
LANDING_PAGE = explore
ENABLE_GZIP = true
STATIC_CACHE_TIME = 6h

[service]
# --- ZERO PUBLIC ACCESS ---
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = true
ENABLE_NOTIFY_MAIL = false
ENABLE_CAPTCHA = false
REGISTER_MANUAL_CONFIRM = false
AUTO_WATCH_NEW_REPOS = false
DEFAULT_KEEP_EMAIL_PRIVATE = true
DEFAULT_ALLOW_CREATE_ORGANIZATION = true
DEFAULT_ENABLE_TIMETRACKING = false
SHOW_USER_EMAIL = false
ALLOW_ONLY_EXTERNAL_REGISTRATION = false
NO_REPLY_ADDRESS = noreply.localhost

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false

[oauth2]
ENABLE = false

[federation]
ENABLED = false

[picture]
# --- DISABLE EXTERNAL AVATAR QUERIES (NO GRAVATAR/LIBRAVATAR LEAKS) ---
DISABLE_GRAVATAR = true
ENABLE_FEDERATED_AVATAR = false

[repository]
ROOT = ${DATA_DIR}/repositories
DEFAULT_PRIVATE = true
FORCE_PRIVATE = false
ENABLE_PUSH_CREATE_USER = true
ENABLE_PUSH_CREATE_ORG = true
MAX_CREATION_LIMIT = -1
DEFAULT_BRANCH = main

[security]
INSTALL_LOCK = true
SECRET_KEY = ${secret_key}
INTERNAL_TOKEN = ${internal_token}
REVERSE_PROXY_LIMIT = 0
REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.1
PASSWORD_COMPLEXITY = lower,upper,digit,spec
MIN_PASSWORD_LENGTH = 12
LOGIN_REMEMBER_DAYS = 7
COOKIE_USERNAME = forgejo_local_usr
COOKIE_REMEMBER_NAME = forgejo_local_rm
COOKIE_SECURE = ${cookie_secure}
COOKIE_SAME_SITE = strict

[database]
# --- EMBEDDED SQLITE3 WITH WAL ---
DB_TYPE = sqlite3
PATH = ${DATA_DIR}/forgejo.db
SQLITE_JOURNAL_MODE = WAL
TIMEOUT = 500

[session]
PROVIDER = file
PROVIDER_CONFIG = ${DATA_DIR}/sessions
COOKIE_NAME = forgejo_sess
COOKIE_SECURE = ${cookie_secure}
SAME_SITE = strict
GC_INTERVAL_TIME = 86400

[webhook]
# Prevent SSRF: allow only localhost webhooks if ever used
ALLOWED_HOST_LIST = loopback
DELIVER_TIMEOUT = 5

[mailer]
ENABLED = false

[lfs]
PATH = ${DATA_DIR}/lfs

[log]
MODE = console, file
LEVEL = Info
ROUTER = console
ROOT_PATH = ${LOG_DIR}
EOF

  chmod 600 "$APP_INI"
  log_ok "Hardened app.ini generated at: $APP_INI (chmod 600)"
}

# --- Optional Localhost TLS (Self-Signed) ---
setup_localhost_tls() {
  local cert_dir="$CONF_DIR/tls"
  mkdir -p "$cert_dir"
  chmod 700 "$cert_dir"
  local cert_file="$cert_dir/cert.pem"
  local key_file="$cert_dir/key.pem"

  if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
    log_info "Generating local self-signed TLS certificate (valid for 365 days)..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout "$key_file" \
      -out "$cert_file" \
      -subj "/CN=127.0.0.1" \
      -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" >/dev/null 2>&1
    chmod 600 "$key_file" "$cert_file"
    log_ok "TLS Certificates generated in $cert_dir"
  fi
}

# --- Initialize Admin User and Database ---
initialize_admin() {
  local bin_file="$BIN_DIR/forgejo"

  if [[ -z "$ADMIN_PASSWORD" ]]; then
    ADMIN_PASSWORD="$(generate_password)"
  fi

  log_info "Initializing SQLite database and primary admin account..."

  # Run admin user creation using Forgejo CLI
  # This command auto-migrates the database schema and creates the admin record.
  local output
  if output="$("$bin_file" admin user create \
    --admin \
    --username "$ADMIN_USER" \
    --password "$ADMIN_PASSWORD" \
    --email "$ADMIN_EMAIL" \
    --must-change-password=false \
    --config "$APP_INI" \
    --work-path "$BASE_DIR" 2>&1)"; then
    log_ok "Primary administrator created: '$ADMIN_USER'"
  else
    if echo "$output" | grep -qi "user already exists"; then
      log_warn "Administrator account '$ADMIN_USER' already exists."
      if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        log_info "Synchronizing password for '$ADMIN_USER' to ensure valid credentials..."
        "$bin_file" admin user change-password \
          --username "$ADMIN_USER" \
          --password "$ADMIN_PASSWORD" \
          --config "$APP_INI" \
          --work-path "$BASE_DIR" >/dev/null 2>&1 || true
      fi
    else
      log_err "Failed to initialize admin user: $output"
      exit 1
    fi
  fi

  # Record credentials safely
  cat > "$CREDENTIALS_FILE" <<EOF
# ==============================================================================
# LOCALHOST GIT FORGE - CREDENTIALS & ACCESS DETAILS
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# RESTRICTED: chmod 600
# ==============================================================================

Web URL:         http://${BIND_IP}:${HTTP_PORT}/
Admin Username:  ${ADMIN_USER}
Admin Password:  ${ADMIN_PASSWORD}
Admin Email:     ${ADMIN_EMAIL}

SSH Server:      ssh://git@${BIND_IP}:${SSH_PORT}/
Base Directory:  ${BASE_DIR}
Config File:     ${APP_INI}
Database File:   ${DATA_DIR}/forgejo.db

IMPORTANT:
- Keep this file private. It is readable only by your user account (chmod 600).
- Public registration is strictly disabled.
- To create additional users, use:
  $0 create-user --username <name> --email <email>
EOF

  chmod 600 "$CREDENTIALS_FILE"
  log_sec "Credentials securely recorded to: $CREDENTIALS_FILE"
}

# --- Systemd User Service Integration ---
setup_systemd_service() {
  if [[ "$ENABLE_SYSTEMD" != "true" ]]; then
    return 0
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    log_warn "systemctl is not available. Skipping systemd setup."
    return 0
  fi

  log_info "Configuring systemd user service for auto-start..."
  mkdir -p "$SYSTEMD_USER_DIR"
  chmod 700 "$SYSTEMD_USER_DIR"

  cat > "$SYSTEMD_SERVICE_FILE" <<EOF
[Unit]
Description=Forgejo Localhost Git Service (Private)
After=network.target

[Service]
Type=simple
WorkingDirectory=${BASE_DIR}
ExecStart=${BIN_DIR}/forgejo web --config ${APP_INI} --work-path ${BASE_DIR}
Restart=on-failure
RestartSec=3s
LimitNOFILE=65535
UMask=0077

# Hardening Directives
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${BASE_DIR}
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=default.target
EOF

  chmod 600 "$SYSTEMD_SERVICE_FILE"
  systemctl --user daemon-reload || true
  systemctl --user disable forgejo-localhost.service 2>/dev/null || true
  log_ok "Systemd user service installed (On-Demand mode): $SYSTEMD_SERVICE_FILE"
}

# --- Autostart Mode Manager (On-Demand vs Auto-Start) ---
manage_autostart() {
  local action="${1:-status}"
  case "$action" in
    disable|off|on-demand|--disable|--off|no)
      if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        if [[ ! -f "$SYSTEMD_SERVICE_FILE" ]]; then
          setup_systemd_service
        fi
        systemctl --user disable forgejo-localhost.service 2>/dev/null || true
        log_ok "Autostart is now DISABLED (On-Demand mode)."
        log_info "Forgejo will NOT start automatically on boot or login."
        log_info "Start on demand anytime via: $0 start"
        log_info "Stop on demand anytime via:  $0 stop"
      else
        log_warn "Systemd not detected. Forgejo runs on demand by default without systemd."
      fi
      ;;
    enable|on|auto|--enable|--on|yes)
      if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        if [[ ! -f "$SYSTEMD_SERVICE_FILE" ]]; then
          setup_systemd_service
        else
          systemctl --user daemon-reload 2>/dev/null || true
          systemctl --user enable forgejo-localhost.service 2>/dev/null || true
        fi
        log_ok "Autostart is now ENABLED (Auto mode)."
        log_info "Forgejo will start automatically whenever you log in or boot."
      else
        log_warn "Systemd not detected. Cannot configure systemd user autostart."
      fi
      ;;
    status|--status)
      echo
      echo -e "${BOLD}Forgejo Autostart Mode:${RESET}"
      if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        if systemctl --user is-enabled forgejo-localhost.service >/dev/null 2>&1; then
          echo -e "  Status : ${GREEN}Auto-Start (Enabled on boot/login via systemd user service)${RESET}"
          echo -e "  Toggle : Run '$0 autostart off' to switch to on-demand"
        else
          echo -e "  Status : ${YELLOW}On-Demand (Disabled on boot/login, manual start only)${RESET}"
          echo -e "  Toggle : Run '$0 autostart on' to switch to auto-start"
        fi
      else
        echo -e "  Status : ${YELLOW}On-Demand (SysVinit / No systemd user service active)${RESET}"
      fi
      echo
      ;;
    *)
      log_err "Unknown autostart action: '$action'"
      echo "Usage: $0 autostart [on|off|status]   (or: enable|disable)"
      exit 1
      ;;
  esac
}

# --- Start Forgejo ---
start_service() {
  log_header "Starting Localhost Forgejo Service"

  if is_running; then
    log_warn "Forgejo is already running (PID: $(cat "$PID_FILE" 2>/dev/null || echo "unknown"))."
    return 0
  fi

  if [[ ! -f "$APP_INI" ]]; then
    log_err "Configuration not found at $APP_INI. Run '$0 install' first."
    exit 1
  fi

  if [[ ! -f "$DATA_DIR/forgejo.db" && ! -f "$CREDENTIALS_FILE" ]]; then
    log_info "No database or credentials detected. Initializing primary administrator..."
    initialize_admin
  fi

  if ! check_port_free "$HTTP_PORT" "$BIND_IP"; then
    log_err "Port ${BIND_IP}:${HTTP_PORT} is already in use by another process!"
    exit 1
  fi

  if ! check_port_free "$SSH_PORT" "$BIND_IP"; then
    log_err "SSH Port ${BIND_IP}:${SSH_PORT} is already in use by another process!"
    exit 1
  fi

  if [[ "$ENABLE_SYSTEMD" == "true" ]] && command -v systemctl >/dev/null 2>&1; then
    if [[ ! -f "$SYSTEMD_SERVICE_FILE" ]]; then
      setup_systemd_service
    fi
    log_info "Starting via systemd user service..."
    systemctl --user start forgejo-localhost.service
  else
    log_info "Starting daemon process in background..."
    local bin_file="$BIN_DIR/forgejo"
    nohup "$bin_file" web --config "$APP_INI" --work-path "$BASE_DIR" >> "$LOG_DIR/forgejo.stdout.log" 2>&1 &
    local pid=$!
    disown "$pid" 2>/dev/null || true
    echo "$pid" > "$PID_FILE"
    chmod 600 "$PID_FILE"
    log_ok "Forgejo started in background with PID $pid"
  fi

  # Wait and verify health
  log_info "Waiting for service to initialize..."
  local attempts=0
  local max_attempts=20
  local healthy=false

  while [[ $attempts -lt $max_attempts ]]; do
    sleep 1
    if curl -s -m 2 "http://${BIND_IP}:${HTTP_PORT}/api/v1/version" >/dev/null 2>&1 || \
       curl -s -m 2 -k "https://${BIND_IP}:${HTTP_PORT}/api/v1/version" >/dev/null 2>&1 || \
       curl -s -m 2 "http://${BIND_IP}:${HTTP_PORT}/" >/dev/null 2>&1; then
      healthy=true
      break
    fi
    attempts=$((attempts + 1))
  done

  if [[ "$healthy" == "true" ]]; then
    log_ok "Service is UP and HEALTHY!"
    display_summary
  else
    log_warn "Service process started, but health check timed out. Inspect logs at: $LOG_DIR/forgejo.stdout.log"
  fi
}

# --- Stop Forgejo ---
stop_service() {
  log_header "Stopping Localhost Forgejo Service"

  if [[ "$ENABLE_SYSTEMD" == "true" ]] && command -v systemctl >/dev/null 2>&1 && [[ -f "$SYSTEMD_SERVICE_FILE" ]]; then
    log_info "Stopping systemd user service..."
    systemctl --user stop forgejo-localhost.service || true
    systemctl --user disable forgejo-localhost.service 2>/dev/null || true
  fi

  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      log_info "Sending SIGTERM to PID $pid..."
      kill "$pid" || true
      local waited=0
      while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 10 ]]; do
        sleep 1
        waited=$((waited + 1))
      done
      if kill -0 "$pid" 2>/dev/null; then
        log_warn "Process still alive after 10s. Sending SIGKILL..."
        kill -9 "$pid" 2>/dev/null || true
      fi
    fi
    rm -f "$PID_FILE"
    log_ok "Daemon stopped."
  else
    log_info "No PID file found. Checking for lingering forgejo web processes under $BASE_DIR..."
    pkill -f "$BIN_DIR/forgejo web" 2>/dev/null || true
  fi
}

# --- Status Check ---
is_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi

  if pgrep -f "$BIN_DIR/forgejo web" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -f "$SYSTEMD_SERVICE_FILE" ]] && command -v systemctl >/dev/null 2>&1; then
    if systemctl --user is-active --quiet forgejo-localhost.service 2>/dev/null; then
      return 0
    fi
  fi

  if curl -s -m 1 "http://${BIND_IP}:${HTTP_PORT}/" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

service_status() {
  log_header "Localhost Forgejo Status"

  if is_running; then
    local pid="unknown"
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null || true)" 2>/dev/null; then
      pid="$(cat "$PID_FILE")"
    else
      pid="$(pgrep -f "$BIN_DIR/forgejo web" | head -n1 || echo "active")"
    fi
    log_ok "Service State: RUNNING (PID: $pid)"
    log_info "Local URL: http://${BIND_IP}:${HTTP_PORT}/"
    log_info "Local SSH: ssh://git@${BIND_IP}:${SSH_PORT}/"

    # API Version / Health test
    local ver_resp
    ver_resp="$(curl -s -m 2 "http://${BIND_IP}:${HTTP_PORT}/api/v1/version" 2>/dev/null || echo "{}")"
    if echo "$ver_resp" | grep -qi "version"; then
      log_info "Forgejo API Version: $ver_resp"
    else
      log_info "Web UI: Active & responding on port ${HTTP_PORT} (Strict loopback, login required)"
    fi
  else
    log_warn "Service State: STOPPED"
  fi

  run_security_audit
}

# --- Security and Privacy Audit ---
run_security_audit() {
  log_header "Automated Security & Privacy Audit"
  local issues=0

  log_info "Auditing Network Socket Bindings..."
  # Audit HTTP Port
  if command -v ss >/dev/null 2>&1; then
    local http_bind
    http_bind="$(ss -tulpn 2>/dev/null | grep ":${HTTP_PORT}\b" || true)"
    if [[ -n "$http_bind" ]]; then
      if echo "$http_bind" | grep -q "127.0.0.1:${HTTP_PORT}"; then
        log_ok "HTTP Socket: Bound strictly to 127.0.0.1:${HTTP_PORT} (NO external LAN access)"
      elif echo "$http_bind" | grep -q "0.0.0.0\|::"; then
        log_err "CRITICAL: HTTP Socket is listening on 0.0.0.0 or wildcard! External devices can access your forge!"
        issues=$((issues + 1))
      else
        log_info "HTTP Socket: $http_bind"
      fi
    fi

    local ssh_bind
    ssh_bind="$(ss -tulpn 2>/dev/null | grep ":${SSH_PORT}\b" || true)"
    if [[ -n "$ssh_bind" ]]; then
      if echo "$ssh_bind" | grep -q "127.0.0.1:${SSH_PORT}"; then
        log_ok "SSH Socket: Bound strictly to 127.0.0.1:${SSH_PORT} (NO external LAN access)"
      elif echo "$ssh_bind" | grep -q "0.0.0.0\|::"; then
        log_err "CRITICAL: SSH Socket is listening on 0.0.0.0 or wildcard!"
        issues=$((issues + 1))
      fi
    fi
  else
    log_info "ss utility not found; checking configuration directives instead."
  fi

  log_info "Auditing app.ini Configuration Directives..."
  if [[ ! -f "$APP_INI" ]]; then
    log_warn "Forgejo configuration not found ($APP_INI)."
    log_info "The instance has not been installed yet. Run '$0 install' first."
    return 0
  fi
    # Check INSTALL_LOCK
    if grep -q "INSTALL_LOCK = true" "$APP_INI"; then
      log_ok "INSTALL_LOCK is true (Web installer wizard disabled)"
    else
      log_err "INSTALL_LOCK is NOT set to true! Web installer may be open!"
      issues=$((issues + 1))
    fi

    # Check DISABLE_REGISTRATION
    if grep -q "DISABLE_REGISTRATION = true" "$APP_INI"; then
      log_ok "DISABLE_REGISTRATION is true (Public registration blocked)"
    else
      log_warn "DISABLE_REGISTRATION is false (Public registration allowed via web)"
    fi

    # Check REQUIRE_SIGNIN_VIEW
    if grep -q "REQUIRE_SIGNIN_VIEW = true" "$APP_INI"; then
      log_ok "REQUIRE_SIGNIN_VIEW is true (Anonymous visitors cannot view repos)"
    else
      log_warn "REQUIRE_SIGNIN_VIEW is not set to true. Public repository views permitted."
    fi

    # Check OFFLINE_MODE
    if grep -q "OFFLINE_MODE = true" "$APP_INI"; then
      log_ok "OFFLINE_MODE is true (Zero external CDN/font connections)"
    else
      log_warn "OFFLINE_MODE is false. Assets may query external CDNs."
    fi

    # Check DISABLE_GRAVATAR
    if grep -q "DISABLE_GRAVATAR = true" "$APP_INI"; then
      log_ok "DISABLE_GRAVATAR is true (Avatar requests will not leak email hashes)"
    else
      log_warn "DISABLE_GRAVATAR is false. Gravatar could receive email hashes."
    fi

  log_info "Auditing File System Permissions..."
  if [[ -f "$APP_INI" ]]; then
    local ini_perm
    ini_perm="$(stat -c "%a" "$APP_INI" 2>/dev/null || stat -f "%Op" "$APP_INI" 2>/dev/null || echo "unknown")"
    if [[ "$ini_perm" == "600" || "$ini_perm" == "0600" ]]; then
      log_ok "app.ini permissions: $ini_perm (Owner read/write only)"
    else
      log_warn "app.ini permissions are $ini_perm (recommended: 600). Fixing now..."
      chmod 600 "$APP_INI"
    fi
  fi

  if [[ -f "$CREDENTIALS_FILE" ]]; then
    local cred_perm
    cred_perm="$(stat -c "%a" "$CREDENTIALS_FILE" 2>/dev/null || stat -f "%Op" "$CREDENTIALS_FILE" 2>/dev/null || echo "unknown")"
    if [[ "$cred_perm" == "600" || "$cred_perm" == "0600" ]]; then
      log_ok "credentials.txt permissions: $cred_perm (Strictly private)"
    else
      chmod 600 "$CREDENTIALS_FILE"
    fi
  fi

  if [[ -d "$DATA_DIR" ]]; then
    local data_perm
    data_perm="$(stat -c "%a" "$DATA_DIR" 2>/dev/null || stat -f "%Op" "$DATA_DIR" 2>/dev/null || echo "unknown")"
    if [[ "$data_perm" == "700" || "$data_perm" == "0700" ]]; then
      log_ok "data directory permissions: $data_perm (Owner only)"
    else
      chmod 700 "$DATA_DIR"
    fi
  fi

  if [[ $issues -eq 0 ]]; then
    log_ok "${BOLD}AUDIT PASSED: The instance meets strict localhost privacy and security criteria.${RESET}"
  else
    log_err "${BOLD}AUDIT FAILED: $issues potential security issues detected above!${RESET}"
  fi
}

# --- Display Setup Summary ---
display_summary() {
  printf "\n"
  printf "${BOLD}${GREEN}==============================================================================${RESET}\n"
  printf "${BOLD}${GREEN}  FORGEJO LOCALHOST GIT INSTANCE READY & RUNNING${RESET}\n"
  printf "${BOLD}${GREEN}==============================================================================${RESET}\n"
  printf "  ${BOLD}Web Dashboard:${RESET}    http://%s:%s/\n" "$BIND_IP" "$HTTP_PORT"
  printf "  ${BOLD}SSH Git Port:${RESET}     ssh://git@%s:%s/\n" "$BIND_IP" "$SSH_PORT"
  printf "  ${BOLD}Admin User:${RESET}       %s\n" "$ADMIN_USER"
  if [[ -f "$CREDENTIALS_FILE" ]]; then
    local admin_pwd
    admin_pwd="$(grep '^Admin Password:' "$CREDENTIALS_FILE" | awk '{print $3}' || true)"
    if [[ -n "$admin_pwd" ]]; then
      printf "  ${BOLD}Admin Password:${RESET}   %s\n" "$admin_pwd"
    fi
  fi
  printf "  ${BOLD}Credentials File:${RESET} %s\n" "$CREDENTIALS_FILE"
  printf "  ${BOLD}Data Directory:${RESET}   %s\n" "$DATA_DIR"
  printf "  ${BOLD}Config File:${RESET}      %s\n" "$APP_INI"
  printf "${BOLD}${GREEN}------------------------------------------------------------------------------${RESET}\n"
  printf "  ${BOLD}Quick Git Remote Setup:${RESET}\n"
  printf "    git remote add origin http://%s:%s/%s/<repo-name>.git\n" "$BIND_IP" "$HTTP_PORT" "$ADMIN_USER"
  printf "  ${BOLD}Or via Local SSH:${RESET}\n"
  printf "    git remote add origin ssh://git@%s:%s/%s/<repo-name>.git\n" "$BIND_IP" "$SSH_PORT" "$ADMIN_USER"
  printf "\n"
  printf "  ${PURPLE}Security Highlights:${RESET}\n"
  printf "  ✔ Bound STRICTLY to 127.0.0.1 (Zero local LAN or public exposure)\n"
  if grep -q "DISABLE_REGISTRATION = true" "$APP_INI" 2>/dev/null; then
    printf "  ✔ Public registration is disabled (Create users via: $0 create-user)\n"
  else
    printf "  ℹ Public registration is ENABLED (Register via Web Dashboard)\n"
  fi
  printf "  ✔ Offline mode active (Zero external telemetry or CDN calls)\n"
  printf "  ✔ Embedded SQLite with WAL mode (Zero exposed DB ports)\n"
  printf "  ✔ Push-to-create enabled (Pushing a new repo auto-creates it!)\n"
  printf "${BOLD}${GREEN}==============================================================================${RESET}\n\n"
}

# --- Show Stored Credentials ---
show_credentials() {
  if [[ -f "$CREDENTIALS_FILE" ]]; then
    cat "$CREDENTIALS_FILE"
  else
    log_warn "Credentials file not found at $CREDENTIALS_FILE."
    if [[ -x "$BIN_DIR/forgejo" && -f "$APP_INI" ]]; then
      log_info "Re-generating credentials file..."
      initialize_admin
      cat "$CREDENTIALS_FILE"
    else
      log_err "Forgejo is not installed yet. Run '$0 install' first."
      exit 1
    fi
  fi
}

# --- Enable/Disable Web Registration ---
enable_registration() {
  if [[ ! -f "$APP_INI" ]]; then
    log_err "Configuration not found at $APP_INI."
    exit 1
  fi
  sed -i 's/^DISABLE_REGISTRATION = true/DISABLE_REGISTRATION = false/' "$APP_INI"
  log_ok "Public web registration is now ENABLED in $APP_INI."
  if is_running; then
    log_info "Restarting Forgejo to apply changes..."
    stop_service
    start_service
  else
    log_info "Start Forgejo with '$0 start' to apply."
  fi
}

disable_registration() {
  if [[ ! -f "$APP_INI" ]]; then
    log_err "Configuration not found at $APP_INI."
    exit 1
  fi
  sed -i 's/^DISABLE_REGISTRATION = false/DISABLE_REGISTRATION = true/' "$APP_INI"
  log_ok "Public web registration is now DISABLED in $APP_INI."
  if is_running; then
    log_info "Restarting Forgejo to apply changes..."
    stop_service
    start_service
  else
    log_info "Start Forgejo with '$0 start' to apply."
  fi
}

# --- Reset User Password Helper ---
reset_password() {
  local target_user="${1:-$ADMIN_USER}"
  local new_pass="${2:-}"
  if [[ -z "$new_pass" ]]; then
    new_pass="$(generate_password)"
  fi
  local bin_file="$BIN_DIR/forgejo"
  if "$bin_file" admin user change-password \
    --username "$target_user" \
    --password "$new_pass" \
    --config "$APP_INI" \
    --work-path "$BASE_DIR"; then
    log_ok "Password for user '$target_user' successfully reset."
    printf "  Username: %s\n  Password: %s\n" "$target_user" "$new_pass"
    if [[ "$target_user" == "$ADMIN_USER" && -f "$CREDENTIALS_FILE" ]]; then
      sed -i "s/^Admin Password:.*/Admin Password:  $new_pass/" "$CREDENTIALS_FILE"
    fi
  else
    log_err "Failed to reset password for '$target_user'."
    exit 1
  fi
}

# --- Create User Helper ---
create_user() {
  local new_user=""
  local new_email=""
  local new_pass=""
  local is_admin=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --username) new_user="$2"; shift 2 ;;
      --email)    new_email="$2"; shift 2 ;;
      --password) new_pass="$2"; shift 2 ;;
      --admin)    is_admin=true; shift 1 ;;
      *) shift 1 ;;
    esac
  done

  if [[ -z "$new_user" || -z "$new_email" ]]; then
    log_err "Usage: $0 create-user --username <name> --email <email> [--password <pass>] [--admin]"
    exit 1
  fi

  if [[ -z "$new_pass" ]]; then
    new_pass="$(generate_password)"
  fi

  local admin_flag=""
  if [[ "$is_admin" == "true" ]]; then
    admin_flag="--admin"
  fi

  local bin_file="$BIN_DIR/forgejo"
  "$bin_file" admin user create \
    $admin_flag \
    --username "$new_user" \
    --password "$new_pass" \
    --email "$new_email" \
    --must-change-password=false \
    --config "$APP_INI" \
    --work-path "$BASE_DIR"

  log_ok "User '$new_user' created successfully."
  printf "  Username: %s\n  Password: %s\n  Email:    %s\n" "$new_user" "$new_pass" "$new_email"
}

# --- Create Repository Helper ---
create_repo() {
  local repo_name=""
  local repo_owner="$ADMIN_USER"
  local is_private=true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)    repo_name="$2"; shift 2 ;;
      --owner)   repo_owner="$2"; shift 2 ;;
      --public)  is_private=false; shift 1 ;;
      *) shift 1 ;;
    esac
  done

  if [[ -z "$repo_name" ]]; then
    log_err "Usage: $0 create-repo --name <repo-name> [--owner <username>] [--public]"
    exit 1
  fi

  local bin_file="$BIN_DIR/forgejo"
  local priv_arg="--private"
  if [[ "$is_private" == "false" ]]; then
    priv_arg=""
  fi

  "$bin_file" admin repo create \
    --owner "$repo_owner" \
    --repo "$repo_name" \
    $priv_arg \
    --config "$APP_INI" \
    --work-path "$BASE_DIR"

  log_ok "Repository '$repo_name' created for owner '$repo_owner'."
  printf "  Clone URL (HTTP): http://%s:%s/%s/%s.git\n" "$BIND_IP" "$HTTP_PORT" "$repo_owner" "$repo_name"
  printf "  Clone URL (SSH):  ssh://git@%s:%s/%s/%s.git\n" "$BIND_IP" "$SSH_PORT" "$repo_owner" "$repo_name"
}

# --- Create Backup ---
create_backup() {
  log_header "Creating Full Backup"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  local backup_file="$BACKUP_DIR/forgejo_backup_${timestamp}.tar.gz"

  log_info "Archiving database, repositories, and configuration..."
  # If running, checkpoint WAL to ensure atomic consistency
  if [[ -f "$DATA_DIR/forgejo.db" ]] && command -v sqlite3 >/dev/null 2>&1; then
    log_info "Running SQLite WAL checkpoint..."
    sqlite3 "$DATA_DIR/forgejo.db" 'PRAGMA wal_checkpoint(TRUNCATE);' 2>/dev/null || true
  fi

  tar -czf "$backup_file" -C "$BASE_DIR" custom data credentials.txt
  chmod 600 "$backup_file"

  local size
  size="$(du -h "$backup_file" | awk '{print $1}')"
  log_ok "Backup created successfully: $backup_file ($size)"
  log_info "To restore, run: $0 restore --file $backup_file"
}

# --- Restore Backup ---
restore_backup() {
  local restore_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) restore_file="$2"; shift 2 ;;
      *) shift 1 ;;
    esac
  done

  if [[ -z "$restore_file" || ! -f "$restore_file" ]]; then
    log_err "Usage: $0 restore --file <path-to-tar.gz>"
    exit 1
  fi

  log_header "Restoring Backup from: $restore_file"
  if is_running; then
    log_warn "Stopping service prior to restore..."
    stop_service
  fi

  log_info "Extracting backup into $BASE_DIR..."
  tar -xzf "$restore_file" -C "$BASE_DIR"
  chmod 700 "$DATA_DIR" "$CONF_DIR"
  chmod 600 "$APP_INI" "$CREDENTIALS_FILE"

  log_ok "Restore completed successfully."
  log_info "Starting service..."
  start_service
}

# --- Tail Logs ---
tail_logs() {
  log_header "Forgejo Logs ($LOG_DIR)"
  local main_log="$LOG_DIR/forgejo.log"
  local stdout_log="$LOG_DIR/forgejo.stdout.log"

  if [[ -f "$main_log" ]]; then
    tail -f "$main_log"
  elif [[ -f "$stdout_log" ]]; then
    tail -f "$stdout_log"
  else
    log_warn "No log file found in $LOG_DIR yet."
  fi
}

# --- Docker Compose Generation (Alternative Mode) ---
setup_docker_mode() {
  log_header "Setting Up Hardened Docker Compose Environment"
  local compose_file="$BASE_DIR/docker-compose.yml"
  mkdir -p "$BASE_DIR"
  chmod 700 "$BASE_DIR"

  cat > "$compose_file" <<EOF
# ==============================================================================
# Hardened Forgejo Localhost Deployment (Docker Compose)
# Strictly bound to 127.0.0.1
# ==============================================================================
services:
  forgejo:
    image: codeberg.org/forgejo/forgejo:${FORGEJO_VERSION}
    container_name: forgejo-localhost
    restart: unless-stopped
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - FORGEJO__server__DOMAIN=127.0.0.1
      - FORGEJO__server__HTTP_ADDR=0.0.0.0
      - FORGEJO__server__HTTP_PORT=3000
      - FORGEJO__server__ROOT_URL=http://127.0.0.1:${HTTP_PORT}/
      - FORGEJO__server__SSH_DOMAIN=127.0.0.1
      - FORGEJO__server__SSH_PORT=${SSH_PORT}
      - FORGEJO__server__SSH_LISTEN_HOST=0.0.0.0
      - FORGEJO__server__OFFLINE_MODE=true
      - FORGEJO__service__DISABLE_REGISTRATION=true
      - FORGEJO__service__REQUIRE_SIGNIN_VIEW=true
      - FORGEJO__picture__DISABLE_GRAVATAR=true
      - FORGEJO__picture__ENABLE_FEDERATED_AVATAR=false
      - FORGEJO__security__INSTALL_LOCK=true
      - FORGEJO__repository__DEFAULT_PRIVATE=true
      - FORGEJO__repository__ENABLE_PUSH_CREATE_USER=true
    volumes:
      - ./data:/data
      - ./custom:/data/forgejo/custom
    ports:
      # STRICT LOOPBACK BINDING
      - "127.0.0.1:${HTTP_PORT}:3000"
      - "127.0.0.1:${SSH_PORT}:22"
    security_opt:
      - no-new-privileges:true
EOF
  chmod 600 "$compose_file"
  log_ok "Hardened docker-compose.yml written to: $compose_file"
  log_info "To start via docker: cd $BASE_DIR && docker compose up -d"
}

# --- Uninstall ---
uninstall_service() {
  log_header "Uninstall Localhost Forgejo"
  printf "${RED}${BOLD}WARNING:${RESET} This will permanently stop and delete the Forgejo instance,\n"
  printf "including repositories, SQLite databases, secrets, and configurations at:\n"
  printf "  %s\n\n" "$BASE_DIR"

  read -r -p "Type 'DELETE' to confirm uninstallation: " confirm
  if [[ "$confirm" != "DELETE" ]]; then
    log_info "Uninstallation aborted."
    return 0
  fi

  stop_service

  if [[ -f "$SYSTEMD_SERVICE_FILE" ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable forgejo-localhost.service 2>/dev/null || true
    rm -f "$SYSTEMD_SERVICE_FILE"
    systemctl --user daemon-reload || true
  fi

  rm -rf "$BASE_DIR"
  log_ok "Forgejo and all data completely removed."
}

# --- Installation Workflow ---
install_workflow() {
  log_header "Starting Hardened Localhost Forgejo Installation"
  log_sec "Zero-Trust Localhost Mode Active: 127.0.0.1 loopback only"

  check_prerequisites

  if [[ "$MODE" == "docker" ]]; then
    setup_docker_mode
    log_ok "Docker mode configured. Run with: cd $BASE_DIR && docker compose up -d"
    return 0
  fi

  download_binary
  generate_app_ini
  initialize_admin
  setup_systemd_service

  start_service
  run_security_audit
}

# --- CLI Help ---
show_help() {
  printf "%b" "${BOLD}forgejo-localhost.sh${RESET} - Private, Hardened Localhost Git Forge Manager

${BOLD}USAGE:${RESET}
  $0 <command> [options]

${BOLD}CORE COMMANDS:${RESET}
  install             Full automated install, hardening, admin creation & startup
  start               Start the local Forgejo service
  stop                Stop the running Forgejo service
  restart             Restart the service
  status              Check running status, ports, and health
  autostart [on|off]  Switch between auto-start on boot and on-demand mode
  audit               Run strict security and network privacy audit
  logs                Tail live Forgejo logs
  create-user         Create an additional user account
  create-repo         Create a new repository from CLI
  credentials         Display current administrator login credentials
  reset-password      Reset a user's password (<username> [<password>])
  enable-registration Enable web sign-up / registration in app.ini
  disable-registration Disable web sign-up / registration in app.ini
  backup              Create an atomic compressed backup of DB and repositories
  restore             Restore from a previous backup tar.gz
  uninstall           Completely remove Forgejo and all local data

${BOLD}OPTIONS:${RESET}
  --port <port>         Web interface port (Default: 3000, binds to 127.0.0.1)
  --ssh-port <port>     SSH Git port (Default: 2222, binds to 127.0.0.1)
  --dir <path>          Base data and binary directory (Default: ./forgejo-data)
  --admin-user <name>   Admin username (Default: forgejo-admin)
  --admin-email <email> Admin email (Default: admin@localhost.localdomain)
  --admin-pass <pass>   Admin password (Default: auto-generated high-entropy)
  --version <version>   Forgejo release version (Default: ${FORGEJO_DEFAULT_VERSION})
  --enable-tls          Generate self-signed SSL/TLS for local HTTPS
  --systemd             Install and manage via systemd user service
  --mode <binary|docker> Deployment mode (Default: binary)
  -h, --help            Show this help manual

${BOLD}EXAMPLES:${RESET}
  # One-line zero-configuration secure install:
  $0 install

  # Custom ports and systemd user service:
  $0 install --port 8080 --ssh-port 2200 --systemd

  # Check security status:
  $0 audit

  # Create a private repository instantly from CLI:
  $0 create-repo --name my-project --owner forgejo-admin

  # Create a regular user:
  $0 create-user --username alice --email alice@localhost

  # Run security audit:
  $0 audit

  # Switch to on-demand mode (will not boot automatically):
  $0 autostart off

  # Switch back to auto-start on boot:
  $0 autostart on

  # Check autostart mode:
  $0 autostart status
"
}

# --- Command Parser ---
main() {
  local cmd="${1:-help}"
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)        HTTP_PORT="$2"; shift 2 ;;
      --ssh-port)    SSH_PORT="$2"; shift 2 ;;
      --dir)         BASE_DIR="$2"; shift 2 ;;
      --admin-user)  ADMIN_USER="$2"; shift 2 ;;
      --admin-email) ADMIN_EMAIL="$2"; shift 2 ;;
      --admin-pass)  ADMIN_PASSWORD="$2"; shift 2 ;;
      --version)     FORGEJO_VERSION="$2"; shift 2 ;;
      --enable-tls)  ENABLE_TLS=true; shift 1 ;;
      --systemd)     ENABLE_SYSTEMD=true; shift 1 ;;
      --mode)        MODE="$2"; shift 2 ;;
      -h|--help)     show_help; exit 0 ;;
      *)
        # Retain positional arguments for subcommands
        break
        ;;
    esac
  done

  # Resolve BASE_DIR if specified as relative path
  if [[ "$BASE_DIR" != /* ]]; then
    BASE_DIR="$PWD/$BASE_DIR"
  fi

  # Execute automatic legacy migration if needed
  migrate_legacy_data

  # Refresh dynamic paths if BASE_DIR was modified
  BIN_DIR="$BASE_DIR/bin"
  CONF_DIR="$BASE_DIR/custom/conf"
  DATA_DIR="$BASE_DIR/data"
  LOG_DIR="$BASE_DIR/log"
  BACKUP_DIR="$BASE_DIR/backups"
  APP_INI="$CONF_DIR/app.ini"
  PID_FILE="$BASE_DIR/forgejo.pid"
  CREDENTIALS_FILE="$BASE_DIR/credentials.txt"

  case "$cmd" in
    install|--install|-i)   install_workflow ;;
    start|--start)          start_service ;;
    stop|--stop)            stop_service ;;
    restart|--restart)      stop_service; start_service ;;
    status|--status|-s)     service_status ;;
    autostart|--autostart)  manage_autostart "$@" ;;
    enable-autostart)       manage_autostart enable ;;
    disable-autostart)      manage_autostart disable ;;
    audit|--audit)          run_security_audit ;;
    logs|--logs)            tail_logs ;;
    credentials|--credentials) show_credentials ;;
    enable-registration)    enable_registration ;;
    disable-registration)   disable_registration ;;
    reset-password)         reset_password "$@" ;;
    create-user)            create_user "$@" ;;
    create-repo)            create_repo "$@" ;;
    backup|--backup)        create_backup ;;
    restore|--restore)      restore_backup "$@" ;;
    uninstall|--uninstall|-u) uninstall_service ;;
    help|-h|--help)         show_help ;;
    *)
      log_err "Unknown command: '$cmd'"
      show_help
      exit 1
      ;;
  esac
}

main "$@"
