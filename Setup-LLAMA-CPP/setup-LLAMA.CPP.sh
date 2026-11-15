#!/usr/bin/env bash
#
# setup-LLAMA.CPP.sh
#
# High-Performance llama.cpp Setup for Modern Debian-based Systems
# Target Hardware: 4GB–8GB+ RAM, Multi-Core CPUs, and GPU Acceleration
# Supported OS: Debian 11/12, MX Linux, Ubuntu, Linux Mint, antiX, Devuan
#
# Features:
#   - Auto-detects CPU vector instructions (AVX2, AVX-512, FMA)
#   - Auto-detects NVIDIA GPUs (CUDA), Vulkan-capable GPUs, and OpenBLAS CPU acceleration
#   - Native support for MX Linux with pre-installed NVIDIA drivers
#   - Parallel multi-threaded build using $(nproc)
#   - Flexible model selection (Curated 1.5B–8B models, use existing local GGUF, or skip)
#   - Generates quick helper launchers: run-llama-cli and run-llama-server (Web UI + API)
#   - Complete uninstaller with clean dependency cleanup
#
# Usage:
#   ./setup-LLAMA.CPP.sh --install
#   ./setup-LLAMA.CPP.sh --uninstall
#   ./setup-LLAMA.CPP.sh --status
#   ./setup-LLAMA.CPP.sh --help
#

set -e

# Security Guardrail: Prevent running directly as pure root
if [ "$EUID" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    echo "✖ [SECURITY ERROR] Do not run this script directly as root!"
    echo "  LLM models and binaries belong strictly in your regular user's home (~/llama.cpp and ~/llama-bin)."
    echo "  Please run: ./setup-LLAMA.CPP.sh"
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
# Dynamic User & Target Home Lookup (Zero hardcoding, dual-root/user safe)
# ---------------------------------------------------------------------------
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"

# ---------------------------------------------------------------------------
# Default Paths
# ---------------------------------------------------------------------------
LLAMA_DIR="$TARGET_HOME/llama.cpp"
MODELS_DIR="$TARGET_HOME/models"
BIN_DIR="$TARGET_HOME/llama-bin"

# Base dependencies for compilation
BASE_DEPENDENCIES=(git cmake build-essential curl ca-certificates pkg-config)

# ---------------------------------------------------------------------------
# Curated Model Catalog (Quantized GGUF Q4_K_M)
# ---------------------------------------------------------------------------
# 4GB RAM Tier
MODEL_1_NAME="Qwen2.5-1.5B-Instruct (Q4_K_M — ~1.0 GB) [Fast & Smart for 4GB RAM]"
MODEL_1_FILE="qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODEL_1_URL="https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf"

MODEL_2_NAME="Llama-3.2-3B-Instruct (Q4_K_M — ~2.0 GB) [Recommended for 4GB-8GB RAM]"
MODEL_2_FILE="llama-3.2-3b-instruct-q4_k_m.gguf"
MODEL_2_URL="https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"

MODEL_3_NAME="Qwen2.5-3B-Instruct (Q4_K_M — ~2.2 GB) [Strong General & Coding for 4GB-8GB]"
MODEL_3_FILE="qwen2.5-3b-instruct-q4_k_m.gguf"
MODEL_3_URL="https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf"

# 8GB+ RAM / GPU Tier
MODEL_4_NAME="Llama-3.1-8B-Instruct (Q4_K_M — ~4.9 GB) [Recommended for 8GB+ RAM / 6GB+ VRAM]"
MODEL_4_FILE="llama-3.1-8b-instruct-q4_k_m.gguf"
MODEL_4_URL="https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"

MODEL_5_NAME="Qwen2.5-7B-Instruct (Q4_K_M — ~4.7 GB) [Exceptional Reasoning for 8GB+ RAM]"
MODEL_5_FILE="qwen2.5-7b-instruct-q4_k_m.gguf"
MODEL_5_URL="https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf"

MODEL_6_NAME="DeepSeek-R1-Distill-Qwen-7B (Q4_K_M — ~4.7 GB) [Advanced Step-by-Step Reasoning]"
MODEL_6_FILE="deepseek-r1-distill-qwen-7b-q4_k_m.gguf"
MODEL_6_URL="https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf"

# ---------------------------------------------------------------------------
# UI & Helper Functions
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

# ---------------------------------------------------------------------------
# Hardware & Environment Inspection
# ---------------------------------------------------------------------------
detect_hardware() {
    print_section "Detecting System Hardware & Capabilities"

    # OS Identification
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="${PRETTY_NAME:-$NAME}"
    else
        OS_NAME="Generic Linux"
    fi
    echo -e "  Operating System : ${BOLD}$OS_NAME${RESET}"

    # RAM Detection
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    TOTAL_RAM_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_RAM_MB / 1024}")
    echo -e "  System Memory    : ${BOLD}${TOTAL_RAM_GB} GB (${TOTAL_RAM_MB} MB)${RESET}"

    # CPU Cores & Model
    CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//' || echo "x86_64 CPU")
    echo -e "  Processor        : ${BOLD}$CPU_MODEL${RESET} (${CPU_CORES} logical cores)"

    # CPU Vector Instruction Sets
    CPU_FLAGS=$(grep -m1 '^flags' /proc/cpuinfo || true)
    HAS_AVX2=false
    HAS_AVX512=false
    if echo "$CPU_FLAGS" | grep -qw "avx2"; then HAS_AVX2=true; fi
    if echo "$CPU_FLAGS" | grep -qw "avx512f"; then HAS_AVX512=true; fi

    echo -e "  CPU Acceleration : AVX2: $([ "$HAS_AVX2" = true ] && echo -e "${GREEN}Yes${RESET}" || echo "No"), AVX-512: $([ "$HAS_AVX512" = true ] && echo -e "${GREEN}Yes${RESET}" || echo "No")"

    # GPU Detection
    HAS_NVIDIA=false
    HAS_NVIDIA_SMI=false
    HAS_NVCC=false
    HAS_VULKAN=false

    if command -v nvidia-smi >/dev/null 2>&1; then
        HAS_NVIDIA_SMI=true
        HAS_NVIDIA=true
        NVIDIA_GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "NVIDIA GPU")
        NVIDIA_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo "Unknown")
        echo -e "  NVIDIA GPU       : ${GREEN}${BOLD}$NVIDIA_GPU_NAME${RESET} (${NVIDIA_VRAM_MB} MB VRAM via nvidia-smi)"
    elif lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -iq "nvidia"; then
        HAS_NVIDIA=true
        NVIDIA_GPU_NAME=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -i "nvidia" | cut -d: -f3 | sed 's/^[ \t]*//' | head -n1)
        echo -e "  NVIDIA Hardware  : ${BOLD}$NVIDIA_GPU_NAME${RESET} (Driver not yet loaded / proprietary driver needed)"
    fi

    if command -v nvcc >/dev/null 2>&1; then
        HAS_NVCC=true
        NVCC_VER=$(nvcc --version | grep "release" | sed 's/.*release //' | cut -d, -f1)
        echo -e "  CUDA Compiler    : ${GREEN}Found nvcc (CUDA $NVCC_VER)${RESET}"
    fi

    # Vulkan Detection (Works for NVIDIA, AMD, Intel Arc/Iris)
    if command -v vulkaninfo >/dev/null 2>&1 || dpkg -s libvulkan1 >/dev/null 2>&1 || dpkg -s libvulkan-dev >/dev/null 2>&1; then
        HAS_VULKAN=true
        echo -e "  Vulkan Support   : ${GREEN}Available / Compatible${RESET}"
    fi
}

# ---------------------------------------------------------------------------
# Backend Selection & Configuration
# ---------------------------------------------------------------------------
choose_backend() {
    local preselected="$1"

    if [ -n "$preselected" ]; then
        CHOSEN_BACKEND="$preselected"
        print_info "Using preselected backend: $CHOSEN_BACKEND"
        return
    fi

    print_section "Select Acceleration Backend"

    echo "llama.cpp can run using several hardware acceleration options:"
    echo

    local default_choice="4"
    if [ "$HAS_NVIDIA" = true ] && [ "$HAS_NVCC" = true ]; then
        echo -e "  ${BOLD}1)${RESET} ${GREEN}NVIDIA CUDA${RESET} [RECOMMENDED for your system: NVIDIA GPU + nvcc detected]"
        default_choice="1"
    elif [ "$HAS_NVIDIA" = true ] && [ "$HAS_NVIDIA_SMI" = true ]; then
        echo -e "  ${BOLD}1)${RESET} ${GREEN}NVIDIA CUDA${RESET} (NVIDIA driver detected; script will install nvidia-cuda-toolkit)"
        echo -e "  ${BOLD}2)${RESET} ${CYAN}Vulkan GPU Backend${RESET} [RECOMMENDED for lightweight setup; uses existing driver without 2GB CUDA toolkit]"
        default_choice="2"
    elif [ "$HAS_VULKAN" = true ]; then
        echo -e "  ${BOLD}1)${RESET} NVIDIA CUDA"
        echo -e "  ${BOLD}2)${RESET} ${CYAN}Vulkan GPU Backend${RESET} [RECOMMENDED: universal for NVIDIA, AMD Radeon, & Intel GPUs]"
        default_choice="2"
    else
        echo -e "  ${BOLD}1)${RESET} NVIDIA CUDA"
        echo -e "  ${BOLD}2)${RESET} Vulkan GPU Backend"
    fi

    echo -e "  ${BOLD}3)${RESET} CPU + OpenBLAS Acceleration (Optimized linear algebra for multi-core CPUs)"
    echo -e "  ${BOLD}4)${RESET} CPU Native AVX2/AVX-512 (Pure multi-threaded CPU without extra graphics packages)"
    echo

    echo -en "${BOLD}Select an option [1-4, Default: $default_choice]: ${RESET}"
    read -r backend_choice
    backend_choice="${backend_choice:-$default_choice}"

    case "$backend_choice" in
        1|cuda|CUDA)
            CHOSEN_BACKEND="cuda"
            ;;
        2|vulkan|VULKAN)
            CHOSEN_BACKEND="vulkan"
            ;;
        3|openblas|OPENBLAS|blas)
            CHOSEN_BACKEND="openblas"
            ;;
        4|cpu|CPU|native)
            CHOSEN_BACKEND="cpu"
            ;;
        *)
            print_warning "Invalid selection. Defaulting to: $default_choice"
            case "$default_choice" in
                1) CHOSEN_BACKEND="cuda" ;;
                2) CHOSEN_BACKEND="vulkan" ;;
                3) CHOSEN_BACKEND="openblas" ;;
                *) CHOSEN_BACKEND="cpu" ;;
            esac
            ;;
    esac

    print_info "Selected Backend: ${BOLD}$CHOSEN_BACKEND${RESET}"
}

# ---------------------------------------------------------------------------
# Dependencies Installation
# ---------------------------------------------------------------------------
install_dependencies() {
    print_section "Installing Dependencies for Backend: $CHOSEN_BACKEND"

    local PKGS=("${BASE_DEPENDENCIES[@]}")

    case "$CHOSEN_BACKEND" in
        cuda)
            if [ "$HAS_NVCC" = false ]; then
                print_info "Installing NVIDIA CUDA compiler toolkit (nvidia-cuda-toolkit)..."
                PKGS+=(nvidia-cuda-toolkit)
            else
                print_success "NVIDIA CUDA compiler (nvcc) already present."
            fi
            ;;
        vulkan)
            print_info "Adding Vulkan development packages..."
            PKGS+=(libvulkan-dev vulkan-tools glslc libvulkan1)
            ;;
        openblas)
            print_info "Adding OpenBLAS library..."
            PKGS+=(libopenblas-dev)
            ;;
        cpu)
            # Pure native CPU needs no extra graphics toolkits
            ;;
    esac

    local missing_pkgs=()
    for pkg in "${PKGS[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        print_info "Root privileges required to install build packages: ${missing_pkgs[*]}"
        sudo apt update -y
        sudo apt install -y "${missing_pkgs[@]}"
    else
        print_success "All build dependencies are already satisfied (0 root commands needed)."
    fi
    print_success "All build dependencies satisfied."
}

# ---------------------------------------------------------------------------
# Clone or Update llama.cpp
# ---------------------------------------------------------------------------
sync_llama_repo() {
    print_section "Fetching / Updating llama.cpp Repository"

    if [ -d "$LLAMA_DIR/.git" ]; then
        print_info "llama.cpp already exists at $LLAMA_DIR. Fetching updates..."
        cd "$LLAMA_DIR"
        git pull --ff-only || print_warning "git pull encountered local changes; proceeding with existing source."
    else
        print_info "Cloning llama.cpp from GitHub..."
        git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
        cd "$LLAMA_DIR"
    fi
}

# ---------------------------------------------------------------------------
# Configure & Compile llama.cpp
# ---------------------------------------------------------------------------
build_llama() {
    print_section "Configuring & Building llama.cpp (${CHOSEN_BACKEND} backend)"

    cd "$LLAMA_DIR"

    local CMAKE_FLAGS=(
        "-B" "build"
        "-DCMAKE_BUILD_TYPE=Release"
    )

    case "$CHOSEN_BACKEND" in
        cuda)
            CMAKE_FLAGS+=("-DGGML_CUDA=ON")
            ;;
        vulkan)
            CMAKE_FLAGS+=("-DGGML_VULKAN=ON")
            ;;
        openblas)
            CMAKE_FLAGS+=("-DGGML_BLAS=ON" "-DGGML_BLAS_VENDOR=OpenBLAS")
            ;;
        cpu)
            CMAKE_FLAGS+=("-DGGML_NATIVE=ON")
            ;;
    esac

    print_info "Running CMake configuration: cmake ${CMAKE_FLAGS[*]}"
    cmake "${CMAKE_FLAGS[@]}"

    local BUILD_THREADS="${CPU_CORES:-2}"
    print_info "Compiling with ${BUILD_THREADS} parallel threads (cmake --build build -j${BUILD_THREADS})..."
    cmake --build build --config Release -j"$BUILD_THREADS"

    if [ -x "$LLAMA_DIR/build/bin/llama-cli" ]; then
        print_success "Compilation successful! llama-cli & llama-server are ready."
    else
        print_error "Compilation finished, but llama-cli binary was not found."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Model Management: Download or Link Existing GGUF
# ---------------------------------------------------------------------------
manage_model() {
    local preselected_model="$1"

    print_section "Model Setup (GGUF Format)"
    mkdir -p "$MODELS_DIR"

    if [ -n "$preselected_model" ]; then
        print_info "Model specified via argument: $preselected_model"
        CURRENT_MODEL_FILE="$preselected_model"
        return
    fi

    echo "You can download a curated model, link an existing local .gguf file you already have, or skip for now."
    echo
    echo -e "  ${BOLD}[1] Download a Curated Model${RESET} (Curated for 4GB / 8GB RAM & GPUs)"
    echo -e "  ${BOLD}[2] Specify an Existing Local GGUF File${RESET} (Already downloaded)"
    echo -e "  ${BOLD}[3] Skip Model Setup for Now${RESET}"
    echo

    local default_choice="1"
    # Check if models already exist in ~/models
    local existing_count
    existing_count=$(find "$MODELS_DIR" -maxdepth 2 -type f -name "*.gguf" 2>/dev/null | wc -l)
    if [ "$existing_count" -gt 0 ]; then
        print_info "Found $existing_count existing .gguf file(s) in $MODELS_DIR."
        default_choice="2"
    fi

    echo -en "${BOLD}Choose model option [1-3, Default: $default_choice]: ${RESET}"
    read -r model_mode
    model_mode="${model_mode:-$default_choice}"

    case "$model_mode" in
        1)
            # Curated download menu
            echo
            echo -e "${BOLD}--- Curated GGUF Models (Quantized Q4_K_M) ---${RESET}"
            echo -e "  ${CYAN}[4GB RAM / 2-4GB VRAM Tier]${RESET}"
            echo -e "  ${BOLD}1)${RESET} $MODEL_1_NAME"
            echo -e "  ${BOLD}2)${RESET} $MODEL_2_NAME"
            echo -e "  ${BOLD}3)${RESET} $MODEL_3_NAME"
            echo
            echo -e "  ${CYAN}[8GB+ RAM / 6GB+ VRAM Tier]${RESET}"
            echo -e "  ${BOLD}4)${RESET} $MODEL_4_NAME"
            echo -e "  ${BOLD}5)${RESET} $MODEL_5_NAME"
            echo -e "  ${BOLD}6)${RESET} $MODEL_6_NAME"
            echo

            local rec_model="2"
            if [ "$TOTAL_RAM_MB" -ge 7000 ]; then
                rec_model="4"
            fi

            echo -en "${BOLD}Select model to download [1-6, Default: $rec_model]: ${RESET}"
            read -r selected_num
            selected_num="${selected_num:-$rec_model}"

            local dl_name dl_file dl_url
            case "$selected_num" in
                1) dl_name="$MODEL_1_NAME"; dl_file="$MODEL_1_FILE"; dl_url="$MODEL_1_URL" ;;
                2) dl_name="$MODEL_2_NAME"; dl_file="$MODEL_2_FILE"; dl_url="$MODEL_2_URL" ;;
                3) dl_name="$MODEL_3_NAME"; dl_file="$MODEL_3_FILE"; dl_url="$MODEL_3_URL" ;;
                4) dl_name="$MODEL_4_NAME"; dl_file="$MODEL_4_FILE"; dl_url="$MODEL_4_URL" ;;
                5) dl_name="$MODEL_5_NAME"; dl_file="$MODEL_5_FILE"; dl_url="$MODEL_5_URL" ;;
                6) dl_name="$MODEL_6_NAME"; dl_file="$MODEL_6_FILE"; dl_url="$MODEL_6_URL" ;;
                *) dl_name="$MODEL_2_NAME"; dl_file="$MODEL_2_FILE"; dl_url="$MODEL_2_URL" ;;
            esac

            local target_path="$MODELS_DIR/$dl_file"
            if [ -f "$target_path" ]; then
                print_success "Model file already exists: $target_path"
                CURRENT_MODEL_FILE="$target_path"
            else
                print_info "Downloading $dl_name..."
                print_info "Source: $dl_url"
                print_info "Destination: $target_path"
                curl -L --progress-bar -o "$target_path" "$dl_url"
                if [ -f "$target_path" ]; then
                    print_success "Download complete: $target_path"
                    CURRENT_MODEL_FILE="$target_path"
                else
                    print_warning "Download could not be completed. You can download manually later."
                fi
            fi
            ;;

        2)
            # Existing local model
            echo
            echo "Enter the full path to your existing .gguf file:"
            echo -en "${BOLD}File path: ${RESET}"
            read -r user_path

            # Expand ~ if used
            user_path="${user_path/#\~/$TARGET_HOME}"

            if [ -f "$user_path" ]; then
                print_success "Valid GGUF model located: $user_path"
                CURRENT_MODEL_FILE="$user_path"
            else
                print_warning "File not found at '$user_path'. Skipping model selection."
            fi
            ;;

        3)
            print_info "Skipping model configuration for now."
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Launcher Scripts Generation (~/llama-bin)
# ---------------------------------------------------------------------------
create_launchers() {
    print_section "Generating Convenience Launchers in $BIN_DIR"
    mkdir -p "$BIN_DIR"

    local model_path="${CURRENT_MODEL_FILE:-$MODELS_DIR/$MODEL_2_FILE}"
    local default_ngl="0"
    if [ "$CHOSEN_BACKEND" = "cuda" ] || [ "$CHOSEN_BACKEND" = "vulkan" ]; then
        if [ "$NVIDIA_VRAM_MB" != "Unknown" ] && [ "$NVIDIA_VRAM_MB" -le 2500 ] 2>/dev/null; then
            default_ngl="14"  # Safe default for 2GB VRAM GPUs (e.g. MX150/MX250/MX350/GTX 1050)
        else
            default_ngl="99"  # Offload all possible layers to GPU
        fi
    fi

    # 1. Interactive CLI Chat Launcher
    cat << 'EOF' > "$BIN_DIR/run-llama-cli"
#!/usr/bin/env bash
#
# Interactive llama.cpp CLI launcher
#

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"
LLAMA_DIR="$TARGET_HOME/llama.cpp"
MODELS_DIR="$TARGET_HOME/models"
BIN="$LLAMA_DIR/build/bin/llama-cli"

if [ ! -x "$BIN" ]; then
    echo "Error: llama-cli not found at $BIN. Please run setup-LLAMA.CPP.sh --install"
    exit 1
fi

# Auto-detect first available model if not set
MODEL="${MODEL:-}"
if [ -z "$MODEL" ]; then
    MODEL=$(find "$MODELS_DIR" -maxdepth 2 -type f -name "*.gguf" 2>/dev/null | head -n1)
fi

if [ -z "$MODEL" ] || [ ! -f "$MODEL" ]; then
    echo "No .gguf model found in $MODELS_DIR."
    echo "Usage: MODEL=/path/to/model.gguf $0 [options]"
    exit 1
fi

THREADS=$(nproc 2>/dev/null || echo 4)
GPU_LAYERS="${GPU_LAYERS:-NGL_PLACEHOLDER}"
CONTEXT="${CONTEXT:-4096}"

echo "=========================================================="
echo " Starting llama-cli in Interactive Conversation Mode"
echo " Model      : $MODEL"
echo " Threads    : $THREADS"
echo " GPU Layers : $GPU_LAYERS"
echo " Context    : $CONTEXT tokens"
echo " Tip        : Type your message and press Enter. Ctrl+C to exit."
echo "=========================================================="
echo

exec "$BIN" \
    -m "$MODEL" \
    -t "$THREADS" \
    -ngl "$GPU_LAYERS" \
    -c "$CONTEXT" \
    "$@"
EOF

    sed -i "s/NGL_PLACEHOLDER/$default_ngl/g" "$BIN_DIR/run-llama-cli"
    chmod +x "$BIN_DIR/run-llama-cli"
    print_success "Created: $BIN_DIR/run-llama-cli (Interactive Chat)"

    # 2. Local Web UI & OpenAI-compatible Server Launcher
    cat << 'EOF' > "$BIN_DIR/run-llama-server"
#!/usr/bin/env bash
#
# Local Web UI & OpenAI-compatible REST API Server launcher
#

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"
LLAMA_DIR="$TARGET_HOME/llama.cpp"
MODELS_DIR="$TARGET_HOME/models"
BIN="$LLAMA_DIR/build/bin/llama-server"

if [ ! -x "$BIN" ]; then
    echo "Error: llama-server not found at $BIN. Please run setup-LLAMA.CPP.sh --install"
    exit 1
fi

MODEL="${MODEL:-}"
if [ -z "$MODEL" ]; then
    MODEL=$(find "$MODELS_DIR" -maxdepth 2 -type f -name "*.gguf" 2>/dev/null | head -n1)
fi

if [ -z "$MODEL" ] || [ ! -f "$MODEL" ]; then
    echo "No .gguf model found in $MODELS_DIR."
    echo "Usage: MODEL=/path/to/model.gguf $0"
    exit 1
fi

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
THREADS=$(nproc 2>/dev/null || echo 4)
GPU_LAYERS="${GPU_LAYERS:-NGL_PLACEHOLDER}"
CONTEXT="${CONTEXT:-4096}"

echo "=========================================================="
echo " Starting llama-server"
echo " Web UI / API URL : http://${HOST}:${PORT}"
echo " Model            : $MODEL"
echo " Threads          : $THREADS"
echo " GPU Layers       : $GPU_LAYERS"
echo " Context Window   : $CONTEXT tokens"
echo " Endpoints        : /v1/chat/completions, /v1/models"
echo " Press Ctrl+C to stop the server"
echo "=========================================================="
echo

exec "$BIN" \
    -m "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    -t "$THREADS" \
    -ngl "$GPU_LAYERS" \
    -c "$CONTEXT" \
    "$@"
EOF

    sed -i "s/NGL_PLACEHOLDER/$default_ngl/g" "$BIN_DIR/run-llama-server"
    chmod +x "$BIN_DIR/run-llama-server"
    print_success "Created: $BIN_DIR/run-llama-server (Web UI & REST API)"

    # Suggest PATH addition in ~/.bashrc if not present
    if ! grep -q "$BIN_DIR" "$TARGET_HOME/.bashrc" 2>/dev/null; then
        echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$TARGET_HOME/.bashrc"
        print_info "Added $BIN_DIR to ~/.bashrc for easy global command execution."
    fi

    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown -R "$TARGET_USER:$TARGET_USER" "$BIN_DIR" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Action: Update Launchers Only (No Recompilation)
# ---------------------------------------------------------------------------
do_update_launchers() {
    print_header "Updating llama.cpp Convenience Launchers"

    detect_hardware

    # Auto-detect backend from existing CMake build configuration
    if [ -f "$LLAMA_DIR/build/CMakeCache.txt" ]; then
        if grep -q "GGML_CUDA:BOOL=ON" "$LLAMA_DIR/build/CMakeCache.txt" 2>/dev/null; then
            CHOSEN_BACKEND="cuda"
        elif grep -q "GGML_VULKAN:BOOL=ON" "$LLAMA_DIR/build/CMakeCache.txt" 2>/dev/null; then
            CHOSEN_BACKEND="vulkan"
        elif grep -q "GGML_BLAS:BOOL=ON" "$LLAMA_DIR/build/CMakeCache.txt" 2>/dev/null; then
            CHOSEN_BACKEND="openblas"
        else
            CHOSEN_BACKEND="cpu"
        fi
        print_info "Detected existing build backend: $CHOSEN_BACKEND"
    elif [ "$HAS_NVIDIA" = true ] && [ "$HAS_NVCC" = true ]; then
        CHOSEN_BACKEND="cuda"
    else
        CHOSEN_BACKEND="cpu"
    fi

    create_launchers
    echo
    print_success "Launchers updated successfully in $BIN_DIR without recompiling!"
    echo -e "You can now use ${CYAN}GPU_LAYERS=14${RESET} and ${CYAN}CONTEXT=2048${RESET} with run-llama-cli or run-llama-server."
}

# ---------------------------------------------------------------------------
# Action: Install
# ---------------------------------------------------------------------------
do_install() {
    print_header "llama.cpp Modern Installation (4GB–8GB+ RAM & GPUs)"

    detect_hardware
    choose_backend "${CLI_BACKEND:-}"
    install_dependencies
    sync_llama_repo
    build_llama
    manage_model "${CLI_MODEL:-}"
    create_launchers

    echo
    echo -e "${BOLD}${GREEN}==================================================================${RESET}"
    echo -e "${BOLD}${GREEN}  Installation & Configuration Complete!${RESET}"
    echo -e "${BOLD}${GREEN}==================================================================${RESET}"
    echo
    echo -e "Installed Location : ${BOLD}$LLAMA_DIR${RESET}"
    echo -e "Helper Launchers   : ${BOLD}$BIN_DIR${RESET}"
    echo
    echo -e "${BOLD}Quick Run Commands:${RESET}"
    echo -e "  1. Launch Interactive Chat (CLI):"
    echo -e "     ${CYAN}$BIN_DIR/run-llama-cli${RESET}"
    echo
    echo -e "  2. Launch Web UI & OpenAI API (Browser):"
    echo -e "     ${CYAN}$BIN_DIR/run-llama-server${RESET}"
    echo -e "     Then open in your browser: ${BOLD}http://127.0.0.1:8080${RESET}"
    echo
    echo -e "  3. Single-shot prompt:"
    echo -e "     ${CYAN}$LLAMA_DIR/build/bin/llama-cli -m <model.gguf> -p \"Explain quantum computing in 2 lines.\"${RESET}"
    echo
}

# ---------------------------------------------------------------------------
# Action: Status
# ---------------------------------------------------------------------------
do_status() {
    print_header "llama.cpp System & Build Status"

    detect_hardware
    echo
    print_section "Build Inspection"

    if [ -x "$LLAMA_DIR/build/bin/llama-cli" ]; then
        print_success "llama-cli executable found at $LLAMA_DIR/build/bin/llama-cli"
        if [ -x "$LLAMA_DIR/build/bin/llama-server" ]; then
            print_success "llama-server executable found at $LLAMA_DIR/build/bin/llama-server"
        fi

        # Check binary linked libraries for acceleration
        local ldd_out
        ldd_out=$(ldd "$LLAMA_DIR/build/bin/llama-cli" 2>/dev/null || true)
        echo
        echo -e "${BOLD}Detected Binary Linkage:${RESET}"
        if echo "$ldd_out" | grep -qi "cuda\|cudart\|cublas"; then
            print_success "Compiled with NVIDIA CUDA Acceleration!"
        elif echo "$ldd_out" | grep -qi "vulkan"; then
            print_success "Compiled with Vulkan GPU Acceleration!"
        elif echo "$ldd_out" | grep -qi "openblas"; then
            print_success "Compiled with OpenBLAS CPU Acceleration!"
        else
            print_info "Compiled with Standard / Native CPU Acceleration."
        fi
    else
        print_warning "llama.cpp is not yet compiled or installed at $LLAMA_DIR."
    fi

    echo
    print_section "Installed Models in $MODELS_DIR"
    if [ -d "$MODELS_DIR" ]; then
        local models
        models=$(find "$MODELS_DIR" -maxdepth 2 -type f -name "*.gguf" 2>/dev/null || true)
        if [ -n "$models" ]; then
            find "$MODELS_DIR" -maxdepth 2 -type f -name "*.gguf" -exec ls -lh {} \;
        else
            echo "  No .gguf model files found in $MODELS_DIR."
        fi
    else
        echo "  Directory $MODELS_DIR does not exist."
    fi
    echo
}

# ---------------------------------------------------------------------------
# Action: Uninstall
# ---------------------------------------------------------------------------
do_uninstall() {
    print_header "llama.cpp — UNINSTALLATION"

    local removed_something=false

    # 1. llama.cpp repository
    if [ -d "$LLAMA_DIR" ]; then
        echo -e "Found llama.cpp repository at: ${BOLD}$LLAMA_DIR${RESET}"
        if confirm_prompt "Remove $LLAMA_DIR?" "y"; then
            rm -rf "$LLAMA_DIR"
            print_success "Removed $LLAMA_DIR"
            removed_something=true
        else
            print_info "Kept $LLAMA_DIR."
        fi
    else
        print_info "Directory $LLAMA_DIR not found."
    fi

    # 2. Launchers in ~/llama-bin
    if [ -d "$BIN_DIR" ]; then
        echo
        echo -e "Found helper launchers in: ${BOLD}$BIN_DIR${RESET}"
        if confirm_prompt "Remove launcher directory $BIN_DIR?" "y"; then
            rm -rf "$BIN_DIR"
            print_success "Removed $BIN_DIR"
            removed_something=true
        fi
    fi

    # 3. Model files
    if [ -d "$MODELS_DIR" ]; then
        echo
        local model_count
        model_count=$(find "$MODELS_DIR" -type f -name "*.gguf" 2>/dev/null | wc -l)
        echo -e "Found models directory at: ${BOLD}$MODELS_DIR${RESET} ($model_count .gguf file(s))"
        if [ "$model_count" -gt 0 ]; then
            find "$MODELS_DIR" -type f -name "*.gguf" -exec ls -lh {} \;
        fi

        if confirm_prompt "Remove all models and delete $MODELS_DIR?" "n"; then
            rm -rf "$MODELS_DIR"
            print_success "Removed $MODELS_DIR"
            removed_something=true
        else
            print_info "Preserved models at $MODELS_DIR."
        fi
    fi

    # 4. Optional dependency packages
    echo
    echo "Build dependencies may have been installed (e.g., cmake, build-essential, nvidia-cuda-toolkit, libvulkan-dev)."
    if confirm_prompt "Would you like to review and remove dependency packages?" "n"; then
        echo "Enter packages to remove (separated by spaces), or press Enter to skip:"
        read -r custom_pkgs
        if [ -n "$custom_pkgs" ]; then
            sudo apt remove -y $custom_pkgs
            sudo apt autoremove -y
            print_success "Removed specified packages."
            removed_something=true
        fi
    fi

    echo
    echo "=================================================================="
    if [ "$removed_something" = true ]; then
        print_success "Uninstallation complete."
    else
        print_info "No changes made."
    fi
    echo "=================================================================="
}

# ---------------------------------------------------------------------------
# Action: Help / Usage
# ---------------------------------------------------------------------------
show_usage() {
    echo -e "${BOLD}Usage:${RESET} $0 [OPTION]"
    echo
    echo -e "${BOLD}Options:${RESET}"
    echo "  --install                  Install llama.cpp, dependencies, and configure launchers"
    echo "  --update-launchers         Regenerate ~/llama-bin launchers without recompiling"
    echo "  --backend <name>           Specify backend: cuda, vulkan, openblas, or cpu"
    echo "  --model <path>             Specify existing GGUF model path or name"
    echo "  --status                   Display system hardware, active build type, and models"
    echo "  --uninstall                Interactively remove llama.cpp, binaries, and models"
    echo "  --help, -h                 Display this help and exit"
    echo
    echo -e "${BOLD}Examples:${RESET}"
    echo "  $0 --install                           # Interactive installation with auto-detection"
    echo "  $0 --update-launchers                  # Update run-llama-cli / run-llama-server (no compile)"
    echo "  $0 --install --backend cuda            # Force NVIDIA CUDA backend"
    echo "  $0 --install --backend vulkan          # Force Vulkan GPU backend (universal)"
    echo "  $0 --status                            # Check current installation and build status"
    echo "  $0 --uninstall                         # Safe uninstallation"
    echo
}

# ---------------------------------------------------------------------------
# CLI Argument Parsing
# ---------------------------------------------------------------------------
ACTION=""
CLI_BACKEND=""
CLI_MODEL=""

while [ $# -gt 0 ]; do
    case "$1" in
        --install)
            ACTION="install"
            shift
            ;;
        --update-launchers|--launchers)
            ACTION="launchers"
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --backend)
            CLI_BACKEND="$2"
            shift 2
            ;;
        --model)
            CLI_MODEL="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

case "$ACTION" in
    install)
        do_install
        ;;
    launchers)
        do_update_launchers
        ;;
    uninstall)
        do_uninstall
        ;;
    status)
        do_status
        ;;
    "")
        show_usage
        exit 1
        ;;
esac
