# High-Performance llama.cpp Setup for Debian & MX Linux (4GB–8GB+ RAM & GPUs)

A production-grade, highly optimized local LLM environment powered by **llama.cpp** for **Debian, MX Linux, Ubuntu, Linux Mint, antiX, and Devuan**.

Tailored for modern workstations and laptops equipped with **4 GB to 8 GB+ RAM**, multi-core CPUs (AVX2 / AVX-512), and hardware accelerators including **NVIDIA CUDA**, universal **Vulkan** (NVIDIA, AMD Radeon, Intel Arc / Iris Xe), and **OpenBLAS**.

---

## Table of Contents

- [Overview & Architecture](#overview--architecture)
- [Hardware & Acceleration Matrix](#hardware--acceleration-matrix)
  - [Debian & MX Linux NVIDIA Integration](#debian--mx-linux-nvidia-integration)
  - [Vulkan: The Universal GPU Acceleration Path](#vulkan-the-universal-gpu-acceleration-path)
  - [OpenBLAS & Native CPU Vectorization](#openblas--native-cpu-vectorization)
- [RAM & Model Sizing Guide](#ram--model-sizing-guide)
  - [4GB RAM / 2–4GB VRAM Tier](#4gb-ram--24gb-vram-tier)
  - [8GB+ RAM / 6–8GB+ VRAM Tier](#8gb-ram--68gb-vram-tier)
- [Quick Start: Automated Setup](#quick-start-automated-setup)
  - [Interactive Installation](#interactive-installation)
  - [Script Options & Flags](#script-options--flags)
- [Model Management: Download, Link, or Skip](#model-management-download-link-or-skip)
- [Daily Usage](#daily-usage)
  - [1. Interactive Terminal Chat (`run-llama-cli`)](#1-interactive-terminal-chat-run-llama-cli)
  - [2. Browser Web UI & OpenAI-Compatible REST Server (`run-llama-server`)](#2-browser-web-ui--openai-compatible-rest-server-run-llama-server)
  - [3. Direct CLI One-Shot Invocations](#3-direct-cli-one-shot-invocations)
- [OpenAI-Compatible REST API](#openai-compatible-rest-api)
- [Performance Tuning Cheat Sheet](#performance-tuning-cheat-sheet)
- [Status Inspection & Diagnostics](#status-inspection--diagnostics)
- [Uninstallation](#uninstallation)
- [Troubleshooting & FAQ](#troubleshooting--faq)

---

## Overview & Architecture

```text
  🪶 Ultra-Lightweight (Native C/C++)  •  🔓 100% Open-Source (FOSS)  •  🛡️ Secure Local Sandbox  •  🔒 Privacy-Focused (0 Telemetry)
```

Unlike resource-heavy desktop AI wrappers (e.g., Electron-based runners that consume 1 GB+ of RAM before a model even loads), **llama.cpp** is written in pure C/C++ with zero runtime bloat.

This setup provides:
- **100% Local, Private & Zero Telemetry:** Absolute zero telemetry, analytics, or phone-home tracking. Prompts, weights, and inference tokens never leave your physical machine. Runs completely offline.
- **Maximum Hardware Efficiency:** Compiles directly against your processor's vector instruction sets (`AVX2`, `AVX-512`, `FMA`) and graphics card accelerators (`CUDA`, `Vulkan`).
- **Parallel Multi-Core Build:** Uses all available CPU threads (`nproc`) to compile in seconds rather than stalling on single threads.
- **Modern GGUF Quantization:** Runs 1.5B to 8B state-of-the-art models (Llama 3.2, Llama 3.1, Qwen 2.5, DeepSeek R1 Distill) comfortably inside 4GB to 8GB of RAM.
- **Built-in Web Interface & OpenAI REST API:** Includes `llama-server`, an integrated local web interface with chat history, model parameters, and an OpenAI-compatible `/v1/chat/completions` HTTP endpoint.
- **Zero Lock-In & Respect for Existing Models:** Prompts you whether you want to download a new model, link an existing `.gguf` file already on your disk, or skip model downloading entirely.

---

## Hardware & Acceleration Matrix

| Backend | Flag | Best Suited For | Key Dependencies |
|---|---|---|---|
| **NVIDIA CUDA** | `--backend cuda` | Systems with dedicated NVIDIA GeForce / RTX / Quadro GPUs | `nvidia-smi` driver, `nvidia-cuda-toolkit` (`nvcc`) |
| **Vulkan (Universal)** | `--backend vulkan` | NVIDIA, AMD Radeon, Intel Arc / Iris Xe, or lightweight setups | `libvulkan-dev`, `libvulkan1`, `vulkan-tools` |
| **OpenBLAS CPU** | `--backend openblas` | Multi-core CPUs without dedicated GPUs | `libopenblas-dev` |
| **Native CPU** | `--backend cpu` | Pure CPU with AVX2 / AVX-512 vectorization | `build-essential`, `cmake` |

---

### Debian & MX Linux NVIDIA Integration

**MX Linux** is renowned for its lightweight footprint (XFCE / Fluxbox) combined with Debian stability. MX Linux features a dedicated **MX Nvidia Driver Installer** (`ddm-mx`) in the MX Tools suite that installs proprietary NVIDIA drivers seamlessly.

When using this setup on Debian or MX Linux:
1. **If NVIDIA drivers are installed (`nvidia-smi` works):**
   - **Option A (Full CUDA):** If you want CUDA compilation (`-DGGML_CUDA=ON`), the script checks for `nvcc`. If missing, it can automatically install `nvidia-cuda-toolkit` via `apt`.
   - **Option B (Vulkan on NVIDIA — Highly Recommended):** NVIDIA's Linux proprietary drivers provide complete native Vulkan support out of the box. Compiling with `-DGGML_VULKAN=ON` offloads computation to your NVIDIA GPU **without** needing to download the large 2GB+ `nvidia-cuda-toolkit` package!
2. **If NVIDIA drivers are not yet installed:**
   - On MX Linux, run `MX Tools` -> `Nvidia Driver Installer` (or `sudo ddm-mx -i nvidia`).
   - On standard Debian, install `nvidia-driver` from the `non-free` / `non-free-firmware` repository.

---

### Vulkan: The Universal GPU Acceleration Path

Vulkan is the cross-platform standard for 3D graphics and compute. In `llama.cpp`:
- Works on **NVIDIA**, **AMD Radeon**, and **Intel Arc / Iris Xe** GPUs.
- Requires only small development packages (`libvulkan-dev`, `glslc`), keeping system bloat minimal.
- Offloads transformer layers to VRAM using the `-ngl` (number of GPU layers) parameter.

---

### OpenBLAS & Native CPU Vectorization

For systems without a dedicated GPU, `llama.cpp` leverages CPU vector math:
- **AVX2 + FMA:** 256-bit wide vector instructions present on nearly all Intel Core (4th Gen+) and AMD Ryzen CPUs.
- **AVX-512:** 512-bit wide instructions on Intel 11th Gen+ / Xeon and AMD Ryzen 7000/9000 series.
- **OpenBLAS:** High-performance BLAS library accelerating matrix multiplications across all CPU cores.

---

## RAM & Model Sizing Guide

Modern GGUF models quantized with **Q4_K_M** (4-bit medium quantization) offer near-lossless output quality while drastically reducing RAM and VRAM requirements:

### 4GB RAM / 2–4GB VRAM Tier

| Model Name | Parameter Size | File Size (Q4_K_M) | Working RAM/VRAM | Strengths |
|---|---|---|---|---|
| **Qwen2.5-1.5B-Instruct** | 1.5 Billion | ~1.0 GB | ~1.6 GB | Ultra-fast, responsive, lightweight reasoning |
| **Llama-3.2-3B-Instruct** | 3.2 Billion | ~2.0 GB | ~2.8 GB | Superb general chat, writing, summarization |
| **Qwen2.5-3B-Instruct** | 3.1 Billion | ~2.2 GB | ~3.0 GB | Exceptional multilingual & coding capabilities |

### 8GB+ RAM / 6–8GB+ VRAM Tier

| Model Name | Parameter Size | File Size (Q4_K_M) | Working RAM/VRAM | Strengths |
|---|---|---|---|---|
| **Llama-3.1-8B-Instruct** | 8.0 Billion | ~4.9 GB | ~6.5 GB | Industry standard 8B model, top-tier versatility |
| **Qwen2.5-7B-Instruct** | 7.6 Billion | ~4.7 GB | ~6.2 GB | SOTA performance in coding, math, structured data |
| **DeepSeek-R1-Distill-Qwen-7B** | 7.6 Billion | ~4.7 GB | ~6.2 GB | Chain-of-thought advanced reasoning & step-by-step logic |

> [!TIP]
> On an 8GB RAM machine, running a **3B model** allows you to expand the context window up to 8,192 or 16,384 tokens with blisteringly fast response speeds!

---

## Quick Start: Automated Setup

### Interactive Installation

Run the setup script with `--install`:

```bash
cd Setup-LLAMA-CPP
chmod +x setup-LLAMA.CPP.sh
./setup-LLAMA.CPP.sh --install
```

The script will automatically:
1. Detect your CPU instructions (`AVX2`, `AVX-512`) and available GPU (`nvidia-smi`, Vulkan).
2. Recommend the optimal acceleration backend (`CUDA`, `Vulkan`, `OpenBLAS`, or `CPU`).
3. Install required build dependencies via `apt`.
4. Clone or update `llama.cpp` at `~/llama.cpp`.
5. Compile binaries in parallel using `cmake --build build -j$(nproc)`.
6. Ask whether you want to **download a model**, **use an existing .gguf file**, or **skip**.
7. Create executable convenience launchers in `~/llama-bin/`:
   - `run-llama-cli` (Interactive CLI chat)
   - `run-llama-server` (Web interface & OpenAI REST API)

---

### Script Options & Flags

```bash
# Display help and available options
./setup-LLAMA.CPP.sh --help

# Check installation, active backend compilation, and detected models
./setup-LLAMA.CPP.sh --status

# Force a specific acceleration backend (non-interactive)
./setup-LLAMA.CPP.sh --install --backend cuda
./setup-LLAMA.CPP.sh --install --backend vulkan
./setup-LLAMA.CPP.sh --install --backend openblas
./setup-LLAMA.CPP.sh --install --backend cpu

# Specify an existing model path during install
./setup-LLAMA.CPP.sh --install --model /path/to/my-model.gguf

# Interactive uninstallation
./setup-LLAMA.CPP.sh --uninstall
```

---

## Model Management: Download, Link, or Skip

When running `./setup-LLAMA.CPP.sh --install`, the installer prompts:

```text
==> Model Setup (GGUF Format)
You can download a curated model, link an existing local .gguf file you already have, or skip for now.

  [1] Download a Curated Model (Curated for 4GB / 8GB RAM & GPUs)
  [2] Specify an Existing Local GGUF File (Already downloaded)
  [3] Skip Model Setup for Now
```

- **If you select `[1]`**: The installer presents a menu tailored to your RAM size (1.5B, 3B, 7B, 8B) and downloads directly from HuggingFace with a progress bar.
- **If you select `[2]`**: You can enter the path to any `.gguf` file already stored on your system (e.g., `~/Downloads/model.gguf` or `/media/storage/models/my-model.gguf`).
- **If you select `[3]`**: Setup completes immediately. You can place your `.gguf` files into `~/models/` at any time later.

---

## Daily Usage

The setup creates dedicated launchers in `~/llama-bin` and adds them to your `$PATH`.

### 1. Interactive Terminal Chat (`run-llama-cli`)

Start an interactive conversation in your terminal:

```bash
run-llama-cli
```

Features:
- Maintains multi-turn conversation memory.
- Uses all CPU cores (`nproc`) and offloads layers to GPU (`-ngl 99`).
- Type your prompt and press <kbd>Enter</kbd>. Press <kbd>Ctrl+C</kbd> to exit.

To specify a different model on the fly:
```bash
MODEL="$HOME/models/another-model.gguf" run-llama-cli
```

---

### 2. Browser Web UI & OpenAI-Compatible REST Server (`run-llama-server`)

Start the local server daemon:

```bash
run-llama-server
```

Then open your web browser to:
```text
http://127.0.0.1:8080
```

**Web UI Features:**
- Clean, modern, responsive chat interface.
- Markdown rendering, code syntax highlighting, and copy-code buttons.
- Adjustable system prompts, temperature, context length, and generation settings.
- Session export and import.

To run on a custom port or bind to your local network:
```bash
HOST="0.0.0.0" PORT="9000" run-llama-server
```

---

### 3. Direct CLI One-Shot Invocations

You can also run quick queries directly without conversation mode:

```bash
~/llama.cpp/build/bin/llama-cli \
  -m ~/models/llama-3.2-3b-instruct-q4_k_m.gguf \
  -t $(nproc) \
  -ngl 99 \
  -c 4096 \
  -p "Write a clean bash function to check internet connectivity."
```

Or pipe files into prompts:
```bash
cat script.py | ~/llama.cpp/build/bin/llama-cli \
  -m ~/models/llama-3.2-3b-instruct-q4_k_m.gguf \
  -t $(nproc) \
  -ngl 99 \
  -p "Review this Python code for bugs and efficiency issues:"
```

---

## OpenAI-Compatible REST API

When `run-llama-server` is running, it exposes a fully compatible OpenAI API endpoint at `http://127.0.0.1:8080/v1`.

### Example: Calling with cURL

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer no-key" \
  -d '{
    "model": "local",
    "messages": [
      {"role": "system", "content": "You are a concise, helpful programming assistant."},
      {"role": "user", "content": "What is the difference between hard and soft links in Linux?"}
    ],
    "temperature": 0.7
  }'
```

### Example: Calling with Python `openai` Package

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8080/v1",
    api_key="no-key"
)

response = client.chat.completions.create(
    model="local-model",
    messages=[
        {"role": "user", "content": "Explain Docker containers in two sentences."}
    ]
)

print(response.choices[0].message.content)
```

---

## Performance Tuning Cheat Sheet

| Parameter | Recommended Value | Impact & Description |
|---|---|---|
| `-t, --threads` | `$(nproc)` | Matches logical CPU cores for maximum processing speed. |
| `-ngl, --n-gpu-layers` | `99` (GPU) or `0` (CPU) | Number of transformer layers offloaded to GPU VRAM. `99` offloads all layers. |
| `-c, --ctx-size` | `4096` | Context window size in tokens (RAM usage scales with context). |
| `-b, --batch-size` | `512` | Batch size for prompt evaluation. Lower to `256` if RAM is constrained. |
| `--temp` | `0.7` | Temperature (0.0 = deterministic/coding; 0.8+ = creative writing). |
| `--top-p` | `0.9` | Nucleus sampling probability threshold. |
| `--repeat-penalty` | `1.1` | Discourages the model from repeating words/phrases. |

---

## Status Inspection & Diagnostics

Check your setup status at any time:

```bash
./setup-LLAMA.CPP.sh --status
```

Output includes:
- System OS and hardware specifications (RAM, CPU cores, AVX support).
- Detected GPU hardware and CUDA/Vulkan capabilities.
- Binary build verification and linked acceleration libraries (`libcuda`, `libvulkan`, or `libopenblas`).
- Catalog of all downloaded `.gguf` models in `~/models/`.

---

## Uninstallation

To completely or selectively remove llama.cpp:

```bash
./setup-LLAMA.CPP.sh --uninstall
```

The uninstaller asks before each removal action:
- Prompts whether to remove the `~/llama.cpp` source & build tree.
- Prompts whether to remove `~/llama-bin` convenience scripts.
- Prompts whether to remove or preserve downloaded model files in `~/models/`.
- Prompts whether to remove build packages via `apt`.

---

## Troubleshooting & FAQ

### 1. `CUDA error: no kernel image is available for execution`
- **Cause:** The CUDA architecture compiled by CMake doesn't match your GPU's compute capability.
- **Fix:** Specify your GPU compute architecture explicitly during cmake (e.g. `CUDA_ARCHITECTURES=75` for GTX 16xx/RTX 20xx, `86` for RTX 30xx, `89` for RTX 40xx), or simply use the **Vulkan** backend (`./setup-LLAMA.CPP.sh --install --backend vulkan`), which eliminates compute architecture discrepancies.

### 2. Out of Memory (OOM) / Process Killed
- **Cause:** The model + context size exceeds available physical RAM + VRAM.
- **Fix:**
  - Reduce the context size: `-c 2048`.
  - If using GPU, offload fewer layers to VRAM (e.g., `-ngl 20` instead of `-ngl 99`).
  - Switch to a 3B or 1.5B model if using a 4GB RAM system.

### 3. Missing `nvcc` on Debian / MX Linux
- **Fix:** If you have the NVIDIA display driver installed but lack `nvcc`, either install `sudo apt install nvidia-cuda-toolkit` or select the **Vulkan** backend, which runs on the existing NVIDIA driver without needing the full CUDA toolkit.
