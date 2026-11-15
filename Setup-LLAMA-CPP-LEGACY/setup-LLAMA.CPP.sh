#!/usr/bin/env bash
#
# setup-LLAMA.CPP.sh
#
# Install or uninstall llama.cpp on legacy / low-spec systems
# (Older 64-bit dual-core CPUs without AVX/SSE4.2, sub-4GB RAM, lightweight Linux).
#
# Usage:
#   ./setup-LLAMA.CPP.sh --install
#   ./setup-LLAMA.CPP.sh --uninstall
#

set -e

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
LLAMA_DIR="$HOME/llama.cpp"
MODELS_DIR="$HOME/models"
SWAPFILE="/swapfile"
MODEL_FILE="$MODELS_DIR/qwen2.5-0.5b-instruct-q4_k_m.gguf"
MODEL_URL="https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"

DEPENDENCIES=(git cmake build-essential curl ca-certificates)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
print_separator() {
    echo
    echo "== $1 =="
}

confirm_prompt() {
    # Usage: confirm_prompt "Question?" [default: y/n]
    local question="$1"
    local default="${2:-n}"
    local reply

    if [ "$default" = "y" ]; then
        read -r -p "$question [Y/n]: " reply
        reply="${reply:-y}"
    else
        read -r -p "$question [y/N]: " reply
        reply="${reply:-n}"
    fi

    case "$reply" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Usage / Help
# ---------------------------------------------------------------------------
show_usage() {
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  --install      Install llama.cpp, dependencies, swap, and download a model"
    echo "  --uninstall    Remove llama.cpp, models, and optionally dependencies/swap"
    echo "  --help, -h     Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --install"
    echo "  $0 --uninstall"
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
do_install() {
    echo
    echo "========================================"
    echo "  llama.cpp — INSTALL (Legacy Hardware)"
    echo "  Target: Older CPUs without AVX/SSE4.2 & Low-RAM Systems"
    echo "========================================"

    # --- OS Detection ---
    print_separator "Checking operating system"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "Detected: ${PRETTY_NAME:-unknown}"
    else
        echo "Cannot identify the operating system."
        exit 1
    fi

    # --- Dependencies ---
    print_separator "Updating package lists"
    sudo apt update

    print_separator "Installing dependencies"
    sudo apt install -y "${DEPENDENCIES[@]}"

    # --- Swap ---
    print_separator "Checking swap space"
    SWAP_SIZE=$(free -m | awk '/^Swap:/ {print $2}')
    if [ "$SWAP_SIZE" -eq 0 ]; then
        echo "Notice: No active swap detected on this system."
        if confirm_prompt "Older systems (<4GB RAM) need swap for compiling. Create a 2GB swapfile (requires sudo)?" "y"; then
            echo "Creating a 2 GB swap file..."
            sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=2048 status=progress
            sudo chmod 600 "$SWAPFILE"
            sudo mkswap "$SWAPFILE"
            sudo swapon "$SWAPFILE"
            if ! grep -q "$SWAPFILE" /etc/fstab; then
                echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
            fi
            echo "Swap created and enabled successfully."
        else
            echo "Skipped swap creation. Proceeding without swap."
        fi
    else
        echo "Swap space already active (${SWAP_SIZE} MB)."
    fi

    # --- Clone / Update ---
    print_separator "Downloading llama.cpp"
    cd "$HOME"

    if [ -d "$LLAMA_DIR" ]; then
        echo "llama.cpp already exists; updating it..."
        cd "$LLAMA_DIR"
        git pull
    else
        git clone https://github.com/ggml-org/llama.cpp.git
        cd "$LLAMA_DIR"
    fi

    # --- Configure ---
    print_separator "Configuring llama.cpp for CPU-only use (legacy CPU safe flags)"
    cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
        -DCMAKE_C_FLAGS="-march=x86-64 -mtune=generic -mno-sse4.1 -mno-sse4.2 -mno-popcnt" \
        -DCMAKE_CXX_FLAGS="-march=x86-64 -mtune=generic -mno-sse4.1 -mno-sse4.2 -mno-popcnt" \
        -DGGML_NATIVE=OFF \
        -DGGML_SSE42=OFF \
        -DGGML_AVX=OFF \
        -DGGML_AVX2=OFF \
        -DGGML_AVX512=OFF \
        -DGGML_FMA=OFF \
        -DGGML_F16C=OFF \
        -DGGML_BMI2=OFF \
        -DGGML_LLAMAFILE=OFF

    # --- Build ---
    print_separator "Compiling llama.cpp (single-threaded to save RAM)"
    echo "This may take a while on a low-memory computer."
    cmake --build build --config Release --clean-first -j1

    # --- Verify ---
    print_separator "Verifying build flags"
    if [ -f "$LLAMA_DIR/build/compile_commands.json" ]; then
        if grep -q -- '-msse4.2' "$LLAMA_DIR/build/compile_commands.json" 2>/dev/null; then
            echo "WARNING: SSE4.2 was enabled in the build. This will crash on older CPUs lacking SSE4.2."
            echo "Check your cmake flags and rebuild."
        elif grep -q -- '-march=native' "$LLAMA_DIR/build/compile_commands.json" 2>/dev/null; then
            echo "WARNING: -march=native was used. This may enable unsupported instructions."
        else
            echo "Build flags look correct (no SSE4.2 or -march=native detected)."
        fi
    else
        echo "compile_commands.json not found; skipping flag verification."
    fi

    # --- Models ---
    print_separator "Creating model directory"
    mkdir -p "$MODELS_DIR"

    print_separator "Downloading a small model"
    if [ -f "$MODEL_FILE" ]; then
        echo "Model already exists: $MODEL_FILE"
    else
        echo "Downloading Qwen2.5-0.5B-Instruct Q4_K_M..."
        echo "This may take several minutes on a slow connection."
        curl -L -o "$MODEL_FILE" "$MODEL_URL"
        if [ -f "$MODEL_FILE" ]; then
            echo "Model downloaded successfully."
        else
            echo "WARNING: Model download failed. You can download it manually later."
            echo "URL: $MODEL_URL"
            echo "Save to: $MODEL_FILE"
        fi
    fi

    # --- Done ---
    print_separator "Testing installation"
    if [ -x "$LLAMA_DIR/build/bin/llama-cli" ]; then
        echo
        echo "==========================================="
        echo "  Installation completed successfully!"
        echo "==========================================="
        echo
        echo "To test, run:"
        echo "  $LLAMA_DIR/build/bin/llama-cli --help"
        echo
        echo "To run the model:"
        echo "  $LLAMA_DIR/build/bin/llama-cli \\"
        echo "    -m $MODEL_FILE \\"
        echo "    -c 512 -b 16 -t 2 -n 128 \\"
        echo "    -p \"Explain Linux in simple words.\""
    else
        echo "Compilation finished, but llama-cli was not found."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
do_uninstall() {
    echo
    echo "========================================"
    echo "  llama.cpp — UNINSTALL"
    echo "========================================"
    echo

    local removed_something=false

    # --- llama.cpp directory ---
    if [ -d "$LLAMA_DIR" ]; then
        echo "Found llama.cpp at: $LLAMA_DIR"
        if confirm_prompt "Remove the llama.cpp directory ($LLAMA_DIR)?" "y"; then
            rm -rf "$LLAMA_DIR"
            echo "Removed: $LLAMA_DIR"
            removed_something=true
        else
            echo "Skipped."
        fi
    else
        echo "llama.cpp directory not found at $LLAMA_DIR (already removed or never installed)."
    fi
    echo

    # --- Model files ---
    if [ -d "$MODELS_DIR" ]; then
        local model_count
        model_count=$(find "$MODELS_DIR" -type f -name "*.gguf" 2>/dev/null | wc -l)
        echo "Found models directory at: $MODELS_DIR ($model_count .gguf file(s))"

        if [ "$model_count" -gt 0 ]; then
            echo "Model files found:"
            find "$MODELS_DIR" -type f -name "*.gguf" -exec ls -lh {} \;
            echo
        fi

        if confirm_prompt "Remove the models directory and all model files ($MODELS_DIR)?" "n"; then
            rm -rf "$MODELS_DIR"
            echo "Removed: $MODELS_DIR"
            removed_something=true
        else
            echo "Skipped. Your models are still at $MODELS_DIR"
        fi
    else
        echo "Models directory not found at $MODELS_DIR."
    fi
    echo

    # --- Launch script ---
    if [ -f "$HOME/run-small-llm.sh" ]; then
        echo "Found launch script: $HOME/run-small-llm.sh"
        if confirm_prompt "Remove the launch script?" "y"; then
            rm -f "$HOME/run-small-llm.sh"
            echo "Removed: $HOME/run-small-llm.sh"
            removed_something=true
        else
            echo "Skipped."
        fi
    fi
    echo

    # --- Swap file ---
    if [ -f "$SWAPFILE" ]; then
        echo "Found swap file: $SWAPFILE"
        SWAP_ACTIVE=$(swapon --show=NAME --noheadings 2>/dev/null | grep -c "$SWAPFILE" || true)

        if confirm_prompt "Remove the swap file ($SWAPFILE)?" "n"; then
            if [ "$SWAP_ACTIVE" -gt 0 ]; then
                echo "Disabling swap..."
                sudo swapoff "$SWAPFILE"
            fi
            sudo rm -f "$SWAPFILE"
            # Remove fstab entry
            if grep -q "$SWAPFILE" /etc/fstab 2>/dev/null; then
                echo "Removing swap entry from /etc/fstab..."
                sudo sed -i "\|$SWAPFILE|d" /etc/fstab
            fi
            echo "Removed: $SWAPFILE"
            removed_something=true
        else
            echo "Skipped. Swap file kept."
        fi
    else
        echo "No swap file found at $SWAPFILE."
    fi
    echo

    # --- Dependencies ---
    echo "The following packages were installed as dependencies:"
    echo "  ${DEPENDENCIES[*]}"
    echo
    echo "WARNING: Other programs on your system may also use these packages."
    echo "         Only remove them if you are sure nothing else needs them."
    echo

    if confirm_prompt "Remove these dependency packages?" "n"; then
        echo "Removing packages..."
        sudo apt remove -y "${DEPENDENCIES[@]}"
        echo
        if confirm_prompt "Also run 'apt autoremove' to clean up unused packages?" "y"; then
            sudo apt autoremove -y
        fi
        echo "Dependencies removed."
        removed_something=true
    else
        echo "Skipped. Dependencies kept."
    fi

    # --- Summary ---
    echo
    echo "========================================"
    if [ "$removed_something" = true ]; then
        echo "  Uninstall complete."
    else
        echo "  Nothing was removed."
    fi
    echo "========================================"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "${1:-}" in
    --install)
        do_install
        ;;
    --uninstall)
        do_uninstall
        ;;
    --help|-h)
        show_usage
        ;;
    "")
        echo "Error: No option specified."
        echo
        show_usage
        exit 1
        ;;
    *)
        echo "Error: Unknown option '$1'"
        echo
        show_usage
        exit 1
        ;;
esac
