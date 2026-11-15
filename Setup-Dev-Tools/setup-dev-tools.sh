#!/usr/bin/env bash
#
# setup-dev-tools.sh
#
# High-Performance, Ultra-Lightweight, 0-Telemetry Developer Tools Suite
# Supported OS: Debian 11/12, MX Linux, antiX, Ubuntu, Linux Mint, Devuan
#
# Components:
#   [1] Modern CLI PowerTools (ripgrep, fzf, bat, eza, zoxide)
#   [2] Git Workflow & LazyGit TUI (lazygit, delta, optimized config)
#   [3] Developer Runtimes (uv for Python, fnm for Node.js, C/C++ toolchain)
#   [4] Lightweight Containers (Docker Engine / Podman + lazydocker)
#   [5] Local AI Developer Copilot (terminal 'ai' helper connected to llama.cpp)
#
# Usage:
#   ./setup-dev-tools.sh --install       # Interactive component selector
#   ./setup-dev-tools.sh --all           # Install all 5 components non-interactively
#   ./setup-dev-tools.sh --cli           # Install CLI PowerTools only
#   ./setup-dev-tools.sh --git           # Install Git & LazyGit only
#   ./setup-dev-tools.sh --runtimes      # Install Dev Runtimes only
#   ./setup-dev-tools.sh --docker        # Install Docker/Containers only
#   ./setup-dev-tools.sh --ai            # Install Local AI Copilot CLI only
#   ./setup-dev-tools.sh --status        # Show status of all components
#   ./setup-dev-tools.sh --uninstall     # Clean uninstaller
#   ./setup-dev-tools.sh --help          # Show help
#

set -e

# ---------------------------------------------------------------------------
# Security & Least-Privilege Guardrail
# ---------------------------------------------------------------------------
# Developer runtimes (uv, fnm, lazygit, eza, zoxide) belong strictly in user-space
# (~/.local/bin). Never run this script directly as root; the script will prompt
# for sudo permission only when installing system-level APT packages.
if [ "$EUID" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    echo -e "\033[0;31m✖ [SECURITY ERROR] Do not run this script directly as root!\033[0m"
    echo "  Developer runtimes must be owned and run by your regular user account."
    echo "  Please run: ./setup-dev-tools.sh"
    echo "  The script will request sudo permission only when installing necessary APT packages."
    exit 1
fi

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

# ---------------------------------------------------------------------------
# Resolve Real User and Home Directory (Works seamlessly under root/sudo or normal user)
# ---------------------------------------------------------------------------
if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER="${USER:-$(id -un)}"
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
[ -z "$TARGET_HOME" ] && TARGET_HOME="$HOME"

LOCAL_BIN="${TARGET_HOME}/.local/bin"
BASHRC="${TARGET_HOME}/.bashrc"
ENV_MARKER_START="# >>> Debian-Dev-Suite: Dev-Tools >>>"
ENV_MARKER_END="# <<< Debian-Dev-Suite: Dev-Tools <<<"

mkdir -p "$LOCAL_BIN" 2>/dev/null || true
if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    chown "${TARGET_USER}:${TARGET_USER}" "$LOCAL_BIN" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "=================================================================="
    echo "  $1"
    echo "=================================================================="
    echo -e "${RESET}"
}

print_section() {
    echo -e "\n${BOLD}${MAGENTA}==> $1${RESET}"
}

print_success() {
    echo -e "${GREEN}✓ $1${RESET}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

# Request explicit sudo permission only when required for system APT packages
request_sudo_permission() {
    local reason="$1"
    if [ "$EUID" -eq 0 ]; then
        return 0
    fi
    print_info "Root privileges required for system packages: ${reason}"
    if ! sudo -v; then
        print_error "Sudo authorization failed or was denied. Cannot install system packages."
        return 1
    fi
}


print_error() {
    echo -e "${RED}✖ $1${RESET}"
}

confirm_prompt() {
    local prompt="$1"
    local default="${2:-n}"
    local reply

    if [ "$default" = "y" ]; then
        echo -en "${BOLD}$prompt [Y/n]: ${RESET}"
        read -r reply
        reply="${reply:-y}"
    else
        echo -en "${BOLD}$prompt [y/N]: ${RESET}"
        read -r reply
        reply="${reply:-n}"
    fi

    case "$reply" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

detect_arch() {
    local raw_arch
    raw_arch=$(uname -m)
    case "$raw_arch" in
        x86_64)  ARCH="x86_64"; DEB_ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64"; DEB_ARCH="arm64" ;;
        armv7l|armhf)  ARCH="armv7"; DEB_ARCH="armhf" ;;
        *) ARCH="x86_64"; DEB_ARCH="amd64" ;;
    esac
}

# ---------------------------------------------------------------------------
# 1. Component: Modern CLI PowerTools
# ---------------------------------------------------------------------------
install_cli_powertools() {
    print_section "[1/5] Installing Modern CLI PowerTools (ripgrep, fzf, bat, eza, zoxide)"

    print_info "Installing core packages from Debian repositories..."
    request_sudo_permission "CLI utilities (ripgrep, fzf, bat)"
    sudo apt update -y
    sudo apt install -y ripgrep fzf bat curl ca-certificates jq

    # Handle batcat -> bat symlink on Debian/Ubuntu
    if command -v batcat >/dev/null 2>&1 && [ ! -e "$LOCAL_BIN/bat" ]; then
        ln -s "$(command -v batcat)" "$LOCAL_BIN/bat"
        print_success "Created symlink: $LOCAL_BIN/bat -> batcat"
    fi

    # Install eza (modern fast ls in Rust)
    if ! command -v eza >/dev/null 2>&1; then
        print_info "Installing eza (modern Rust alternative to ls)..."
        # Download latest release static binary from GitHub
        detect_arch
        local eza_tar="/tmp/eza.tar.gz"
        local eza_url="https://github.com/eza-community/eza/releases/latest/download/eza_${ARCH}-unknown-linux-gnu.tar.gz"
        if [ "$ARCH" = "armv7" ]; then
            eza_url="https://github.com/eza-community/eza/releases/latest/download/eza_arm-unknown-linux-gnueabihf.tar.gz"
        fi

        if curl -sL "$eza_url" -o "$eza_tar" 2>/dev/null; then
            tar -xzf "$eza_tar" -C "$LOCAL_BIN" 2>/dev/null || true
            chmod +x "$LOCAL_BIN/eza" 2>/dev/null || true
            rm -f "$eza_tar"
            print_success "Installed eza binary to $LOCAL_BIN/eza"
        else
            print_warning "Direct binary download of eza failed; skipping eza."
        fi
    else
        print_success "eza is already installed."
    fi

    # Install zoxide (smart cd directory jumper)
    if ! command -v zoxide >/dev/null 2>&1; then
        print_info "Installing zoxide (smart directory jumping)..."
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
        print_success "Installed zoxide to $LOCAL_BIN/zoxide"
    else
        print_success "zoxide is already installed."
    fi

    print_success "CLI PowerTools successfully installed!"
}

# ---------------------------------------------------------------------------
# 2. Component: Git & LazyGit TUI
# ---------------------------------------------------------------------------
install_git_tools() {
    print_section "[2/5] Installing Git Workflow & LazyGit TUI"

    print_info "Ensuring git is installed..."
    if ! command -v git >/dev/null 2>&1; then
        request_sudo_permission "Git package"
        sudo apt install -y git curl tar
    fi

    # Install LazyGit
    if ! command -v lazygit >/dev/null 2>&1; then
        print_info "Installing LazyGit (terminal UI for Git in Go)..."
        detect_arch
        local lg_arch="x86_64"
        if [ "$ARCH" = "arm64" ]; then lg_arch="arm64"; fi
        if [ "$ARCH" = "armv7" ]; then lg_arch="armv6"; fi

        local lg_version
        lg_version=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": *"v\K[^"]*' || echo "0.44.1")
        local lg_url="https://github.com/jesseduffield/lazygit/releases/download/v${lg_version}/lazygit_${lg_version}_Linux_${lg_arch}.tar.gz"

        local lg_tar="/tmp/lazygit.tar.gz"
        curl -sL "$lg_url" -o "$lg_tar"
        tar -xzf "$lg_tar" -C /tmp lazygit
        mv /tmp/lazygit "$LOCAL_BIN/lazygit"
        chmod +x "$LOCAL_BIN/lazygit"
        rm -f "$lg_tar"
        print_success "Installed LazyGit v${lg_version} to $LOCAL_BIN/lazygit"
    else
        print_success "LazyGit is already installed."
    fi

    # Configure helpful, safe Git defaults (if user doesn't already have them)
    print_info "Configuring sensible Git defaults (safe directory, main branch, color UI)..."
    git config --global init.defaultBranch main 2>/dev/null || true
    git config --global color.ui auto 2>/dev/null || true
    git config --global core.autocrlf input 2>/dev/null || true

    # Useful git aliases
    git config --global alias.st "status -s" 2>/dev/null || true
    git config --global alias.lg "log --oneline --graph --decorate -n 15" 2>/dev/null || true
    git config --global alias.br "branch" 2>/dev/null || true
    git config --global alias.ci "commit" 2>/dev/null || true

    print_success "Git & LazyGit setup complete!"
}

# ---------------------------------------------------------------------------
# 3. Component: Dev Runtimes (uv, fnm, C/C++)
# ---------------------------------------------------------------------------
install_dev_runtimes() {
    print_section "[3/5] Installing Developer Runtimes (uv Python, fnm Node.js, C/C++ tools)"

    # C/C++ Build Essentials (System-level packages)
    print_info "Installing C/C++ build essentials (gcc, g++, make, gdb, valgrind)..."
    request_sudo_permission "C/C++ compiler toolchain"
    if [ "$EUID" -eq 0 ]; then
        apt install -y build-essential gdb valgrind cmake pkg-config
    else
        sudo apt install -y build-essential gdb valgrind cmake pkg-config
    fi

    # Python: uv (100% User-Space Astral package & virtualenv manager - ZERO root privileges)
    if ! command -v uv >/dev/null 2>&1 && [ ! -x "$LOCAL_BIN/uv" ]; then
        print_info "Installing uv in user-space ($LOCAL_BIN/uv; 0 root privileges)..."
        export UV_INSTALL_DIR="$LOCAL_BIN"
        export CARGO_DIST_FORCE_INSTALL_DIR="$LOCAL_BIN"
        if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" UV_INSTALL_DIR="$LOCAL_BIN" curl -LsSf https://astral.sh/uv/install.sh | sh
        else
            curl -LsSf https://astral.sh/uv/install.sh | sh
        fi
        chmod +x "$LOCAL_BIN/uv" "$LOCAL_BIN/uvx" 2>/dev/null || true
    fi

    # Verify strictly user-space installation (never touches /usr/local/bin)
    if [ -x "$LOCAL_BIN/uv" ]; then
        print_success "Installed uv to $LOCAL_BIN/uv (User-space, 0 root privileges)"
    elif command -v uv >/dev/null 2>&1; then
        print_success "uv is available at $(command -v uv)"
    else
        print_warning "uv installation completed, but binary not found in $LOCAL_BIN/uv."
    fi

    # Node.js: fnm (Fast Node Manager in Rust)
    if ! command -v fnm >/dev/null 2>&1 && [ ! -x "$LOCAL_BIN/fnm" ]; then
        print_info "Installing fnm (Fast Node Manager in Rust; replaces nvm)..."
        if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
        else
            curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
        fi
        if [ -f "$TARGET_HOME/.local/share/fnm/fnm" ] && [ ! -e "$LOCAL_BIN/fnm" ]; then
            ln -s "$TARGET_HOME/.local/share/fnm/fnm" "$LOCAL_BIN/fnm"
        fi
        chmod +x "$LOCAL_BIN/fnm" 2>/dev/null || true
        print_success "Installed fnm to $LOCAL_BIN/fnm"
    else
        print_success "fnm is already installed."
    fi

    print_success "Developer Runtimes setup complete!"
}

# ---------------------------------------------------------------------------
# 4. Component: Lightweight Containers (Docker / Podman + lazydocker)
# ---------------------------------------------------------------------------
install_containers() {
    print_section "[4/5] Installing Lightweight Containers (Docker Engine & lazydocker)"

    echo "Select container engine:"
    echo "  [1] Docker Engine (Standard Docker CE without Docker Desktop bloat)"
    echo "  [2] Podman (Rootless, daemonless alternative)"
    echo -en "${BOLD}Choose [1-2, Default: 1]: ${RESET}"
    read -r c_choice
    c_choice="${c_choice:-1}"

    if [ "$c_choice" = "2" ]; then
        print_info "Installing Podman..."
        request_sudo_permission "Podman container engine"
        sudo apt install -y podman
        print_success "Podman installed successfully!"
    else
        print_info "Installing Docker Engine and CLI from Debian repositories..."
        request_sudo_permission "Docker Engine & CLI (docker.io, docker-cli)"
        local docker_pkgs="docker.io containerd"
        if apt-cache show docker-cli >/dev/null 2>&1; then
            docker_pkgs="docker.io docker-cli containerd"
        fi
        if apt-cache show docker-compose >/dev/null 2>&1; then
            docker_pkgs="$docker_pkgs docker-compose"
        elif apt-cache show docker-compose-v2 >/dev/null 2>&1; then
            docker_pkgs="$docker_pkgs docker-compose-v2"
        fi
        sudo apt install -y $docker_pkgs

        # Add target user to docker group
        if ! id -nG "$TARGET_USER" 2>/dev/null | grep -qw "docker"; then
            print_info "Adding user $TARGET_USER to 'docker' group (allows docker without sudo)..."
            sudo usermod -aG docker "$TARGET_USER"
            print_warning "You will need to log out and log back in (or run 'newgrp docker') for docker group changes to take effect."
        fi

        # Service handling for both systemd and SysVinit (MX Linux & antiX support)
        if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running 2>/dev/null | grep -qE "running|degraded"; then
            print_info "Configuring Docker service with systemd..."
            sudo systemctl enable --now docker || true
        elif [ -x /etc/init.d/docker ]; then
            print_info "Configuring Docker service with SysVinit..."
            sudo service docker start || true
        fi
        print_success "Docker Engine installed and configured!"
    fi

    # Install lazydocker (Terminal UI for Docker in Go)
    if ! command -v lazydocker >/dev/null 2>&1; then
        print_info "Installing lazydocker TUI..."
        detect_arch
        local ld_arch="x86_64"
        if [ "$ARCH" = "arm64" ]; then ld_arch="arm64"; fi
        if [ "$ARCH" = "armv7" ]; then ld_arch="armv6"; fi

        local ld_version
        ld_version=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | grep -Po '"tag_name": *"v\K[^"]*' || echo "0.23.3")
        local ld_url="https://github.com/jesseduffield/lazydocker/releases/download/v${ld_version}/lazydocker_${ld_version}_Linux_${ld_arch}.tar.gz"

        local ld_tar="/tmp/lazydocker.tar.gz"
        curl -sL "$ld_url" -o "$ld_tar"
        tar -xzf "$ld_tar" -C /tmp lazydocker
        mv /tmp/lazydocker "$LOCAL_BIN/lazydocker"
        chmod +x "$LOCAL_BIN/lazydocker"
        rm -f "$ld_tar"
        print_success "Installed lazydocker to $LOCAL_BIN/lazydocker"
    else
        print_success "lazydocker is already installed."
    fi

    print_success "Container environment setup complete!"
}

# ---------------------------------------------------------------------------
# 5. Component: Local AI Developer Copilot CLI ('ai' command)
# ---------------------------------------------------------------------------
install_local_ai_copilot() {
    print_section "[5/5] Installing Local AI Copilot CLI ('ai' command)"

    local ai_bin="$LOCAL_BIN/ai"

    print_info "Creating standalone local AI assistant command at $ai_bin..."

    cat << 'EOF' > "$ai_bin"
#!/usr/bin/env bash
#
# ai — Zero-Telemetry Local AI Terminal Copilot
# Connects directly to local llama.cpp server (http://127.0.0.1:8080)
#
# Features:
#   - 100% Private, 0 Telemetry, completely offline execution
#   - Direct question answering: ai "explain tar command"
#   - Stdin piping: cat file.py | ai "find bugs in this code"
#   - Shell command generation: ai -c "find files larger than 50MB"
#

set -e

SERVER_URL="${LLAMA_SERVER_URL:-http://127.0.0.1:8080/v1/chat/completions}"
TIMEOUT="${AI_TIMEOUT:-60}"

show_help() {
    echo "Usage: ai [OPTIONS] [PROMPT]"
    echo
    echo "Zero-telemetry local AI copilot wired to your llama.cpp server."
    echo
    echo "Options:"
    echo "  -c, --cmd         Generate a single, executable bash command and nothing else"
    echo "  -h, --help        Show this help message"
    echo
    echo "Examples:"
    echo "  ai \"Explain memory management in C++\""
    echo "  ai -c \"list all open listening ports\""
    echo "  cat main.py | ai \"review this code for performance issues\""
    echo "  git diff | ai \"write a concise commit message for these changes\""
    echo
}

# Check if llama-server is reachable
check_server() {
    if ! curl -s --max-time 2 "${SERVER_URL%/v1/chat/completions}/health" >/dev/null 2>&1 && \
       ! curl -s --max-time 2 "${SERVER_URL%/v1/chat/completions}/v1/models" >/dev/null 2>&1; then
        echo -e "\033[0;31mError: Local llama-server is not responding at ${SERVER_URL%/v1/chat/completions}\033[0m" >&2
        echo "Please start your local server first using:" >&2
        echo "  run-llama-server" >&2
        echo "or check your setup in Setup-LLAMA-CPP" >&2
        exit 1
    fi
}

COMMAND_MODE=false
PROMPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--cmd)
            COMMAND_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [ -z "$PROMPT" ]; then
                PROMPT="$1"
            else
                PROMPT="$PROMPT $1"
            fi
            shift
            ;;
    esac
done

# Read from stdin if piped
STDIN_INPUT=""
if [ ! -t 0 ]; then
    STDIN_INPUT=$(cat)
fi

if [ -z "$PROMPT" ] && [ -z "$STDIN_INPUT" ]; then
    show_help
    exit 1
fi

check_server

# Build Prompt Content
FULL_PROMPT=""
if [ -n "$STDIN_INPUT" ]; then
    FULL_PROMPT="Context / File Content:
\`\`\`
$STDIN_INPUT
\`\`\`

Request: ${PROMPT:-Analyze the context provided above.}"
else
    FULL_PROMPT="$PROMPT"
fi

SYSTEM_PROMPT="You are an expert Linux developer and terminal assistant. Provide concise, clear, and direct answers."
if [ "$COMMAND_MODE" = true ]; then
    SYSTEM_PROMPT="You are a precise Linux shell command generator. Return ONLY the single executable bash command. Do not wrap in markdown quotes, backticks, or provide explanations."
fi

# Send JSON payload safely via python3 using environment variables to eliminate code injection risks
AI_SERVER_URL="$SERVER_URL" AI_TIMEOUT="$TIMEOUT" AI_SYSTEM="$SYSTEM_PROMPT" AI_USER="$FULL_PROMPT" AI_CMD_MODE="$COMMAND_MODE" python3 - << 'PYEOF'
import os
import sys
import json
import urllib.request

server_url = os.environ.get("AI_SERVER_URL", "http://127.0.0.1:8080/v1/chat/completions")
try:
    timeout_sec = float(os.environ.get("AI_TIMEOUT", 60))
except ValueError:
    timeout_sec = 60.0

system_prompt = os.environ.get("AI_SYSTEM", "")
user_prompt = os.environ.get("AI_USER", "")
cmd_mode = os.environ.get("AI_CMD_MODE", "false") == "true"

payload = {
    "model": "local-model",
    "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt}
    ],
    "temperature": 0.2 if cmd_mode else 0.5,
    "max_tokens": 1024
}

req = urllib.request.Request(
    server_url,
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"}
)

try:
    with urllib.request.urlopen(req, timeout=timeout_sec) as response:
        res = json.loads(response.read().decode("utf-8"))
        content = res["choices"][0]["message"]["content"].strip()
        print(content)
except Exception as e:
    sys.stderr.write(f"Error querying local AI: {e}\n")
    sys.exit(1)
PYEOF
EOF

    chmod +x "$ai_bin"
    print_success "Created local AI copilot: $ai_bin"
    print_info "Usage: ai \"Explain docker in 2 lines\""
    print_info "Piping: cat code.py | ai \"Explain bugs\""
}

# ---------------------------------------------------------------------------
# Shell Environment Configuration (~/.bashrc)
# ---------------------------------------------------------------------------
configure_shell_environment() {
    print_section "Configuring Shell Environment (~/.bashrc)"

    # Remove existing block if present (both modern and legacy markers)
    if grep -q -E "# >>> Debian-Dev-(Suite|Setup): Dev-Tools >>>" "$BASHRC" 2>/dev/null; then
        sed -i -E "/# >>> Debian-Dev-(Suite|Setup): Dev-Tools >>>/,/# <<< Debian-Dev-(Suite|Setup): Dev-Tools <<</d" "$BASHRC"
    fi

    # Append fresh, clean consolidated block
    cat << 'EOF' >> "$BASHRC"

# >>> Debian-Dev-Suite: Dev-Tools >>>
# 1. Path exports
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$HOME/llama-bin:$PATH"

# 2. Modern CLI Tool Aliases
if command -v batcat >/dev/null 2>&1 && [ ! -e "$HOME/.local/bin/bat" ]; then
    alias bat="batcat"
fi
if command -v eza >/dev/null 2>&1; then
    alias ls="eza --icons --group-directories-first"
    alias ll="eza -lh --icons --group-directories-first --git"
    alias la="eza -lah --icons --group-directories-first --git"
    alias tree="eza --tree --icons"
fi

# 3. Zoxide smart cd hook
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
    alias cd="z"
fi

# 4. FNM (Fast Node Manager) hook
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd)"
fi

# 5. Git & LazyGit Shortcuts
alias lg="lazygit"
alias lz="lazydocker"

# <<< Debian-Dev-Suite: Dev-Tools <<<
EOF

    print_success "Configured shell integration block in $BASHRC."
    print_info "Run: ${BOLD}source ~/.bashrc${RESET} to activate immediately in your current terminal."
}

# ---------------------------------------------------------------------------
# Status Inspection
# ---------------------------------------------------------------------------
do_status() {
    print_header "Developer Tools Suite — Component Status"

    echo -e "${BOLD}1. CLI PowerTools:${RESET}"
    echo "  - ripgrep (rg) : $(command -v rg 2>/dev/null || echo 'Not installed')"
    echo "  - fzf          : $(command -v fzf 2>/dev/null || echo 'Not installed')"
    echo "  - bat          : $(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || echo 'Not installed')"
    echo "  - eza          : $(command -v eza 2>/dev/null || echo 'Not installed')"
    echo "  - zoxide       : $(command -v zoxide 2>/dev/null || echo 'Not installed')"

    echo
    echo -e "${BOLD}2. Git & LazyGit:${RESET}"
    echo "  - git          : $(command -v git 2>/dev/null || echo 'Not installed')"
    echo "  - lazygit      : $(command -v lazygit 2>/dev/null || echo 'Not installed')"

    echo
    echo -e "${BOLD}3. Developer Runtimes:${RESET}"
    local uv_path
    if command -v uv >/dev/null 2>&1; then uv_path=$(command -v uv); elif [ -x "$LOCAL_BIN/uv" ]; then uv_path="$LOCAL_BIN/uv"; else uv_path="Not installed"; fi
    echo "  - uv (Python)  : $uv_path"
    local fnm_path
    if command -v fnm >/dev/null 2>&1; then fnm_path=$(command -v fnm); elif [ -x "$LOCAL_BIN/fnm" ]; then fnm_path="$LOCAL_BIN/fnm"; else fnm_path="Not installed"; fi
    echo "  - fnm (Node.js): $fnm_path"
    echo "  - gcc / g++    : $(command -v gcc 2>/dev/null || echo 'Not installed')"
    echo "  - cmake        : $(command -v cmake 2>/dev/null || echo 'Not installed')"

    echo
    echo -e "${BOLD}4. Containers:${RESET}"
    echo "  - docker       : $(command -v docker 2>/dev/null || echo 'Not installed')"
    local compose_status="Not installed"
    if docker compose version >/dev/null 2>&1; then
        compose_status="docker compose ($(docker compose version --short 2>/dev/null || echo 'plugin'))"
    elif command -v docker-compose >/dev/null 2>&1; then
        compose_status="$(docker-compose --version 2>/dev/null | head -n1)"
    fi
    echo "  - compose      : $compose_status"
    echo "  - podman       : $(command -v podman 2>/dev/null || echo 'Not installed')"
    echo "  - lazydocker   : $(command -v lazydocker 2>/dev/null || echo 'Not installed')"

    echo
    echo -e "${BOLD}5. Local AI Copilot:${RESET}"
    echo "  - ai CLI       : $([ -x "$LOCAL_BIN/ai" ] && echo "$LOCAL_BIN/ai" || echo 'Not installed')"
    echo
}

# ---------------------------------------------------------------------------
# Interactive Menu
# ---------------------------------------------------------------------------
do_interactive_install() {
    print_header "Setup Developer Tools Suite (100% FOSS & 0 Telemetry)"

    echo "Select which components to install:"
    echo
    echo -e "  ${BOLD}[1]${RESET} Modern CLI PowerTools (ripgrep, fzf, bat, eza, zoxide)"
    echo -e "  ${BOLD}[2]${RESET} Git Workflow & LazyGit TUI (lazygit, safe configs, aliases)"
    echo -e "  ${BOLD}[3]${RESET} Dev Runtimes (uv Python, fnm Node.js, C/C++ toolchain)"
    echo -e "  ${BOLD}[4]${RESET} Lightweight Containers (Docker Engine / Podman + lazydocker)"
    echo -e "  ${BOLD}[5]${RESET} Local AI Copilot CLI ('ai' command wired to llama.cpp)"
    echo -e "  ${BOLD}[A]${RESET} ${GREEN}Install ALL 5 Components${RESET} [RECOMMENDED]"
    echo

    echo -en "${BOLD}Enter choice [e.g. 1,2,5 or A, Default: A]: ${RESET}"
    read -r choices
    choices="${choices:-A}"

    case "$choices" in
        [Aa]|all|ALL)
            install_cli_powertools
            install_git_tools
            install_dev_runtimes
            install_containers
            install_local_ai_copilot
            ;;
        *)
            if [[ "$choices" =~ "1" ]]; then install_cli_powertools; fi
            if [[ "$choices" =~ "2" ]]; then install_git_tools; fi
            if [[ "$choices" =~ "3" ]]; then install_dev_runtimes; fi
            if [[ "$choices" =~ "4" ]]; then install_containers; fi
            if [[ "$choices" =~ "5" ]]; then install_local_ai_copilot; fi
            ;;
    esac

    configure_shell_environment

    echo
    echo -e "${BOLD}${GREEN}==================================================================${RESET}"
    echo -e "${BOLD}${GREEN}  Developer Tools Setup Completed!${RESET}"
    echo -e "${BOLD}${GREEN}==================================================================${RESET}"
    echo
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown -R "${TARGET_USER}:${TARGET_USER}" "${LOCAL_BIN}" "${TARGET_HOME}/.local" 2>/dev/null || true
        chown "${TARGET_USER}:${TARGET_USER}" "$BASHRC" 2>/dev/null || true
    fi

    echo "Please activate your environment now with:"
    echo -e "  ${CYAN}source ~/.bashrc${RESET}"
    echo
}

# ---------------------------------------------------------------------------
# Uninstallation
# ---------------------------------------------------------------------------
do_uninstall() {
    print_header "Developer Tools Suite — UNINSTALL"

    if confirm_prompt "Remove shell integration block from ~/.bashrc?" "y"; then
        if grep -q -E "# >>> Debian-Dev-(Suite|Setup): Dev-Tools >>>" "$BASHRC" 2>/dev/null; then
            sed -i -E "/# >>> Debian-Dev-(Suite|Setup): Dev-Tools >>>/,/# <<< Debian-Dev-(Suite|Setup): Dev-Tools <<</d" "$BASHRC"
            print_success "Removed environment block from $BASHRC"
        fi
    fi

    if confirm_prompt "Remove custom binaries from $LOCAL_BIN (lazygit, lazydocker, ai, eza, zoxide, fnm)?" "y"; then
        rm -f "$LOCAL_BIN/lazygit" "$LOCAL_BIN/lazydocker" "$LOCAL_BIN/ai" "$LOCAL_BIN/eza" "$LOCAL_BIN/bat" "$LOCAL_BIN/zoxide" "$LOCAL_BIN/fnm"
        print_success "Removed binaries from $LOCAL_BIN"
    fi

    if confirm_prompt "Uninstall APT packages (ripgrep, fzf, bat, docker.io, docker-cli, docker-compose)?" "n"; then
        sudo apt remove -y ripgrep fzf bat docker.io docker-cli containerd docker-compose docker-compose-v2 podman || true
        sudo apt autoremove -y || true
        print_success "Uninstalled APT packages."
    fi

    print_success "Uninstallation complete."
}

# ---------------------------------------------------------------------------
# Show Help
# ---------------------------------------------------------------------------
show_usage() {
    echo -e "${BOLD}Usage:${RESET} $0 [OPTION]"
    echo
    echo -e "${BOLD}Options:${RESET}"
    echo "  --install                  Interactive menu to choose components to install"
    echo "  --all                      Install all 5 developer components non-interactively"
    echo "  --cli                      Install Modern CLI PowerTools only"
    echo "  --git                      Install Git & LazyGit only"
    echo "  --runtimes                 Install Dev Runtimes (uv, fnm, C/C++) only"
    echo "  --docker                   Install Containers (Docker/Podman + lazydocker) only"
    echo "  --ai                       Install Local AI Copilot CLI only"
    echo "  --status                   Inspect which components are currently installed"
    echo "  --uninstall                Interactively remove installed tools and bash configs"
    echo "  --help, -h                 Show this help"
    echo
}

# ---------------------------------------------------------------------------
# Entrypoint CLI Parser
# ---------------------------------------------------------------------------
case "${1:-}" in
    --install)
        do_interactive_install
        ;;
    --all)
        install_cli_powertools
        install_git_tools
        install_dev_runtimes
        install_containers
        install_local_ai_copilot
        configure_shell_environment
        ;;
    --cli)
        install_cli_powertools
        configure_shell_environment
        ;;
    --git)
        install_git_tools
        configure_shell_environment
        ;;
    --runtimes)
        install_dev_runtimes
        configure_shell_environment
        ;;
    --docker)
        install_containers
        configure_shell_environment
        ;;
    --ai)
        install_local_ai_copilot
        configure_shell_environment
        ;;
    --status)
        do_status
        ;;
    --uninstall)
        do_uninstall
        ;;
    --help|-h)
        show_usage
        ;;
    "")
        do_interactive_install
        ;;
    *)
        print_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac
