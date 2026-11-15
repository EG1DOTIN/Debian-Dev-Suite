# llama.cpp Usage Guide — Daily Workflows, Tips & System Integration

This guide provides practical examples, shell integration tips, and production setups for **llama.cpp** on modern Debian-based systems.

For installation instructions, see [README.md](README.md).

---

## Table of Contents

- [Environment & Path Setup](#environment--path-setup)
- [Interactive Conversation Mode](#interactive-conversation-mode)
- [Running the Local Web UI](#running-the-local-web-ui)
- [Single-Shot Terminal Invocations](#single-shot-terminal-invocations)
- [Resource & Hardware Sizing Guide (RAM & VRAM)](#resource--hardware-sizing-guide-ram--vram)
  - [Understanding the Out-of-Memory (cudaMalloc) Error](#understanding-the-out-of-memory-cudamalloc-error)
  - [Model Size vs. Memory Compatibility Matrix](#model-size-vs-memory-compatibility-matrix)
  - [Profile 1: 2GB VRAM GPU (GeForce MX250 / MX150 / GTX 1050 2GB)](#profile-1-2gb-vram-gpu-geforce-mx250--mx150--gtx-1050-2gb)
  - [Profile 2: 4GB–6GB VRAM GPU (GTX 1650 / RTX 3050)](#profile-2-4gb6gb-vram-gpu-gtx-1650--rtx-3050)
  - [Profile 3: 8GB+ VRAM GPU (RTX 3060 / 4060+)](#profile-3-8gb-vram-gpu-rtx-3060--4060)
  - [Profile 4: CPU-Only & Low RAM Mode (4GB–8GB System RAM)](#profile-4-cpu-only--low-ram-mode-4gb8gb-system-ram)
  - [Dynamic Launcher Overrides (GPU_LAYERS & CONTEXT)](#dynamic-launcher-overrides-gpu_layers--context)
  - [Real-Time Resource Monitoring Commands](#real-time-resource-monitoring-commands)
- [Systemd Background Service (Always-On AI Server)](#systemd-background-service-always-on-ai-server)
- [Integrating with Editors & IDEs](#integrating-with-editors--ides)
  - [Geany Code Editor Integration](#geany-code-editor-integration)
- [OpenAI-Compatible Client Integrations](#openai-compatible-client-integrations)
  - [Python Scripting](#python-scripting)
  - [Curl API Examples](#curl-api-examples)
- [Advanced Flag Customizations](#advanced-flag-customizations)

---

## Environment & Path Setup

The installation script adds `~/llama-bin` to your `PATH`. Ensure it is active in your current shell:

```bash
source ~/.bashrc
```

You can verify that the launchers are available globally:

```bash
which run-llama-cli
which run-llama-server
```

> [!TIP]
> To update or regenerate the launcher scripts at any time **without recompiling** `llama.cpp`:
> ```bash
> ./setup-LLAMA.CPP.sh --update-launchers
> ```

To define a default model for all sessions, set the `MODEL` environment variable in your `~/.bashrc`:

```bash
echo 'export MODEL="$HOME/models/llama-3.2-3b-instruct-q4_k_m.gguf"' >> ~/.bashrc
source ~/.bashrc
```

---

## Interactive Conversation Mode

Launch a multi-turn chat directly in your terminal:

```bash
run-llama-cli
```

### In-Session Commands
- **Send Message:** Type your text and press <kbd>Enter</kbd>.
- **Multiline Input:** End a line with `\` and press <kbd>Enter</kbd> to continue typing on the next line.
- **Interrupt Output:** Press <kbd>Ctrl+C</kbd> once to stop text generation while keeping the chat alive.
- **Exit Session:** Press <kbd>Ctrl+C</kbd> twice or type `/exit`.

### Custom System Prompt
You can customize the model's persona using the `--system-prompt` flag:

```bash
run-llama-cli -p "You are an expert Linux system administrator. Answer with precise bash commands."
```

---

## Running the Local Web UI

Launch `llama-server` to access the responsive browser interface:

```bash
run-llama-server
```

Open your browser to:
```text
http://127.0.0.1:8080
```

### Key Web UI Capabilities
1. **Model Controls:** Adjust temperature, top-p, top-k, and max tokens using interactive sliders in the sidebar.
2. **Chat Sessions:** Save, export, and rename multiple chat conversations stored in your browser's local storage.
3. **Markdown & Code:** Automatic syntax highlighting with single-click code copy buttons.
4. **Context Monitor:** Real-time visual indicator showing how much of the context window is utilized.

---

## Single-Shot Terminal Invocations

Single-shot mode is ideal for scripting, quick lookups, and piping commands.

### Quick Question
```bash
~/llama.cpp/build/bin/llama-cli \
  -m "$MODEL" \
  -t $(nproc) \
  -ngl 99 \
  -c 4096 \
  -p "Explain the difference between symlinks and hardlinks in Linux in 3 bullet points."
```

### Piping Logs or Code for Analysis
```bash
# Analyze kernel dmesg errors
dmesg | tail -n 50 | ~/llama.cpp/build/bin/llama-cli \
  -m "$MODEL" \
  -t $(nproc) \
  -ngl 99 \
  -p "Analyze these kernel log entries and point out any critical hardware errors:"

# Review a Python script
cat main.py | ~/llama.cpp/build/bin/llama-cli \
  -m "$MODEL" \
  -t $(nproc) \
  -ngl 99 \
  -p "Find potential security vulnerabilities and performance bottlenecks in this Python script:"
```

---

## Resource & Hardware Sizing Guide (RAM & VRAM)

When running local models with `llama.cpp`, memory allocation is divided between:
1. **Model Weights:** Loaded into GPU VRAM (via `-ngl` layers) and/or System RAM.
2. **Context Window (KV Cache):** Allocated per token. At `-c 4096`, modern models consume several hundred megabytes of memory.
3. **Compute Runtime Overhead:** CUDA driver and BLAS runtime overhead (~200MB–400MB).

---

### Understanding the Out-of-Memory (cudaMalloc) Error

If you see an error like:
```text
ggml_backend_cuda_buffer_type_alloc_buffer: allocating 2428.65 MiB on device 0: cudaMalloc failed: out of memory
llama_model_load: error loading model: unable to allocate CUDA0 buffer
```
- **Cause:** You ran with `GPU Layers : 99` (`-ngl 99`), commanding `llama.cpp` to put all model layers into GPU memory.
- **Why it failed:** The model buffer (`2,428.65 MiB`) exceeded your GPU's physical VRAM capacity (e.g. 2,048 MiB on an NVIDIA GeForce MX250).
- **The Solution:** Use **hybrid offloading** (`-ngl 12`–`16`), lower the context (`-c 2048`), or run on CPU (`-ngl 0`).

---

### Model Size vs. Memory Compatibility Matrix

| Model Parameter Size | Quantization | Model File Size | 2GB VRAM GPU (MX250 / GTX 1050) | 4GB–6GB VRAM GPU (GTX 1650) | 8GB+ VRAM GPU (RTX 3060+) | CPU-Only (System RAM) |
|---|---|---|---|---|---|---|
| **0.5B – 1.5B** (SmolLM, Qwen 1.5B, Llama 1B) | Q4_K_M | 0.3 GB – 1.2 GB | **Full GPU** (`-ngl 99`) | **Full GPU** (`-ngl 99`) | **Full GPU** (`-ngl 99`) | 4GB+ RAM (`-ngl 0`) |
| **3B – 4B** (Nemotron 4B, Llama 3.2 3B, Phi 3) | Q4_K_M | 2.0 GB – 2.5 GB | **Hybrid** (`-ngl 12–16`) | **Full GPU** (`-ngl 99`) | **Full GPU** (`-ngl 99`) | 8GB+ RAM (`-ngl 0`) |
| **7B – 8B** (Llama 3.1 8B, Qwen 7B, Mistral 7B) | Q4_K_M | 4.5 GB – 5.5 GB | **Hybrid** (`-ngl 6–10`) | **Hybrid** (`-ngl 18–24`) | **Full GPU** (`-ngl 99`) | 12GB+ RAM (`-ngl 0`) |
| **14B** (Qwen 2.5 14B) | Q4_K_M | ~9.0 GB | CPU-Only (`-ngl 0`) | CPU-Only (`-ngl 0`) | **Hybrid** (`-ngl 18–24`) | 16GB–32GB RAM |

---

### Profile 1: 2GB VRAM GPU (GeForce MX250 / MX150 / GTX 1050 2GB)

For a 2GB VRAM card, allocate layers conservatively so total GPU memory usage stays under ~1.6 GB–1.8 GB.

#### 1. Running 3B–4B Models (Nemotron-3 Nano 4B, Llama-3.2-3B, Phi-3 Mini)
Offload 12 to 16 layers to the GPU, and keep context at 2048:

```bash
# Direct CLI invocation:
~/llama.cpp/build/bin/llama-cli \
  -m "$HOME/models/NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf" \
  -t $(nproc) \
  -ngl 14 \
  -c 2048

# Direct Server / Web UI invocation:
~/llama.cpp/build/bin/llama-server \
  -m "$HOME/models/NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf" \
  --host 127.0.0.1 --port 8080 \
  -t $(nproc) \
  -ngl 14 \
  -c 2048

# Or using the launcher scripts with environment overrides:
GPU_LAYERS=14 CONTEXT=2048 MODEL="$HOME/models/NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf" run-llama-cli
GPU_LAYERS=14 CONTEXT=2048 MODEL="$HOME/models/NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf" run-llama-server
```

#### 2. Running 7B–8B Models on 2GB VRAM + 8GB/16GB System RAM
Offload 6 to 10 layers to GPU for a slight acceleration boost, letting system RAM handle the bulk:
```bash
GPU_LAYERS=8 CONTEXT=2048 run-llama-cli
```

---

### Profile 2: 4GB–6GB VRAM GPU (GTX 1650 / RTX 3050)

- **1B to 4B Models:** Full GPU acceleration (`-ngl 99`, `-c 4096`).
- **7B to 8B Models:** Hybrid offload with 20–28 layers:

```bash
# 7B-8B model hybrid offloading:
GPU_LAYERS=24 CONTEXT=2048 run-llama-cli
GPU_LAYERS=24 CONTEXT=2048 run-llama-server
```

---

### Profile 3: 8GB+ VRAM GPU (RTX 3060 / 4060+)

Models up to 8B parameters fit entirely into GPU VRAM with full 8k+ context:

```bash
GPU_LAYERS=99 CONTEXT=8192 run-llama-cli
GPU_LAYERS=99 CONTEXT=8192 run-llama-server
```

---

### Profile 4: CPU-Only & Low RAM Mode (4GB–8GB System RAM)

If your GPU VRAM is completely unavailable, or you want to run a model larger than your VRAM without GPU memory errors:

```bash
# 1. Pure CPU CLI Chat (Zero VRAM allocated)
~/llama.cpp/build/bin/llama-cli \
  -m "$MODEL" \
  -t $(nproc) \
  -ngl 0 \
  -c 2048 \
  -b 256

# 2. Pure CPU Local Server
~/llama.cpp/build/bin/llama-server \
  -m "$MODEL" \
  --host 127.0.0.1 --port 8080 \
  -t $(nproc) \
  -ngl 0 \
  -c 2048

# 3. Using Launchers in CPU Mode
GPU_LAYERS=0 CONTEXT=2048 run-llama-cli
GPU_LAYERS=0 CONTEXT=2048 run-llama-server
```

> [!TIP]
> **Low-RAM System Optimization:** If your system has 4GB RAM, reduce context to `-c 1024` or `-c 512` and set batch size to `-b 128` to minimize memory spikes during prompt processing.

---

### Dynamic Launcher Overrides (GPU_LAYERS & CONTEXT)

The convenience launchers (`run-llama-cli` and `run-llama-server`) accept standard environment variables without needing to edit scripts:

| Variable | Default | Purpose | Example |
|---|---|---|---|
| `MODEL` | First `.gguf` in `~/models` | Path to target GGUF model | `MODEL="/path/to/model.gguf"` |
| `GPU_LAYERS` | Hardware-detected (`14` on 2GB GPU, `99` on 4GB+ GPU, `0` on CPU) | Number of layers to offload to GPU | `GPU_LAYERS=16` or `GPU_LAYERS=0` |
| `CONTEXT` | `4096` | Context window token size | `CONTEXT=2048` or `CONTEXT=1024` |
| `THREADS` | `$(nproc)` | CPU worker threads | `THREADS=4` |
| `HOST` | `127.0.0.1` | Server binding address (`run-llama-server`) | `HOST=0.0.0.0` |
| `PORT` | `8080` | Server port (`run-llama-server`) | `PORT=5000` |

#### Combined Example:
```bash
MODEL="$HOME/models/NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf" \
GPU_LAYERS=14 \
CONTEXT=2048 \
run-llama-cli
```

---

### Real-Time Resource Monitoring Commands

Keep a second terminal open while running models to track memory consumption:

```bash
# Monitor GPU VRAM, utilization & temperature in real time (every 1 second)
watch -n 1 nvidia-smi
# OR
nvidia-smi -l 1

# Monitor System RAM and Swap usage in real time
watch -n 1 free -h

# Interactive CPU threads, memory, and per-process usage
htop
```

---

## Systemd Background Service (Always-On AI Server)

If you want `llama-server` to start automatically when your computer boots:

### 1. Create a Systemd Service File
```bash
sudo nano /etc/systemd/system/llama-server.service
```

Paste the following configuration (replace `<username>` with your Linux username):

```ini
[Unit]
Description=llama.cpp Local AI Server & OpenAI REST API
After=network.target

[Service]
Type=simple
User=<username>
WorkingDirectory=/home/<username>
Environment="MODEL=/home/<username>/models/llama-3.2-3b-instruct-q4_k_m.gguf"
ExecStart=/home/<username>/llama.cpp/build/bin/llama-server \
    -m /home/<username>/models/llama-3.2-3b-instruct-q4_k_m.gguf \
    --host 127.0.0.1 \
    --port 8080 \
    -t 4 \
    -ngl 99 \
    -c 4096
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

### 2. Enable & Start the Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now llama-server.service
```

### 3. Check Status & Logs
```bash
sudo systemctl status llama-server.service
journalctl -u llama-server.service -f
```

---

## Integrating with Editors & IDEs

### Geany Code Editor Integration

In **Geany** (installed via `Setup-Geany`):
1. Go to **Build** -> **Set Build Commands**.
2. Under **Execute Commands**, add:
   - **Command Name:** `Ask LLM`
   - **Command:** `bash -c 'cat "%f" | ~/llama.cpp/build/bin/llama-cli -m "$MODEL" -t $(nproc) -ngl 99 -p "Review this file for bugs:"'`
3. Now press your configured hotkey to pipe the open file directly into your local LLM!

---

## OpenAI-Compatible Client Integrations

### Python Scripting

```python
#!/usr/bin/env python3
import os
from openai import OpenAI

# Initialize client pointing to local llama-server
client = OpenAI(
    base_url="http://127.0.0.1:8080/v1",
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="local-model",
    messages=[
        {"role": "system", "content": "You are a concise software engineering mentor."},
        {"role": "user", "content": "Explain memory management in modern C++."}
    ],
    temperature=0.3,
    max_tokens=256
)

print(response.choices[0].message.content)
```

### Curl API Examples

#### Chat Completion:
```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "Provide a 1-liner bash command to find files larger than 100MB."}
    ],
    "temperature": 0.2
  }' | grep -o '"content":"[^"]*"' | sed 's/"content":"//;s/"$//'
```

#### List Available Models:
```bash
curl -s http://127.0.0.1:8080/v1/models | jq .
```

---

## Advanced Flag Customizations

| Task | Recommended Flags |
|---|---|
| **Low RAM Mode (4GB System)** | `-c 2048 -b 256` |
| **High Context Coding (8GB+ System)** | `-c 8192 -b 512` |
| **Deterministic Code Generation** | `--temp 0.1 --top-p 0.95` |
| **Creative Brainstorming / Writing** | `--temp 0.8 --top-p 0.9 --presence-penalty 0.1` |
| **Partial GPU Offloading (2GB VRAM card)** | `-ngl 15` (adjust upwards until VRAM is ~90% full) |
| **Full GPU Offloading (4GB–8GB VRAM card)** | `-ngl 99` |
