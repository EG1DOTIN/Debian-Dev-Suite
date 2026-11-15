# llama.cpp Setup for Legacy & Low-Spec Computers (Sub-4GB RAM & Vintage CPUs)

Complete setup guide for running llama.cpp on older, legacy, or resource-constrained computers (such as vintage 64-bit dual-core processors with 2 GB–4 GB RAM running lightweight Debian-based distributions like antiX, MX Linux, or minimal Debian).

## Quick Start

Use the setup script for automated install or uninstall:

```bash
# Install everything (dependencies, swap, llama.cpp, model)
./setup-LLAMA.CPP.sh --install

# Uninstall (interactive — asks what to remove)
./setup-LLAMA.CPP.sh --uninstall

# Show help
./setup-LLAMA.CPP.sh --help
```

The sections below document each step manually if you prefer to do it yourself.

---

## Target System Architecture

This configuration is engineered for legacy computers that lack modern CPU vector acceleration instruction sets and have limited physical RAM:

- **Target CPU Profile:** Vintage 64-bit dual-core / quad-core processors (e.g., Intel Core 2 Duo, Pentium Dual-Core, older Celeron, or AMD Athlon 64 X2).
- **Target Memory Profile:** 2 GB to 4 GB physical RAM (with automated swap space).
- **GPU Acceleration:** None (Pure CPU-only inference).
- **Recommended OS:** Lightweight Debian-derived distributions (antiX, MX Linux, Debian with XFCE/LXQt, or Devuan).

### CPU Vector Instruction Sets

| Instruction Set Category | Status | Notes |
|---|---|---|
| **Supported** | `SSE`, `SSE2`, `SSSE3` | Supported on nearly all 64-bit x86 CPUs |
| **Unsupported** | `SSE4.1`, `SSE4.2`, `AVX`, `AVX2`, `FMA`, `F16C`, `BMI/BMI2` | Must be explicitly disabled during compilation |

> [!IMPORTANT]
> Upstream `llama.cpp` attempts to enable SSE4.2 or native instruction sets by default. On legacy CPUs without SSE4.2, this causes immediate `Illegal Instruction (core dumped)` crashes. This configuration explicitly disables modern instruction sets to guarantee crash-proof execution.

### Reference Hardware Benchmark
As a real-world test benchmark, this build was verified on:
- **Processor:** Intel Pentium Dual-Core T4300 @ 2.10GHz (2 cores, 2 threads)
- **Memory:** 3 GB RAM
- **Operating System:** antiX Linux (Debian-based)
- **Model:** Qwen2.5-0.5B-Instruct (Q4_K_M, ~398 MB)
- **Throughput:** ~1.5 to 2.5 tokens per second

---

## 1. Install Dependencies

```bash
sudo apt update
sudo apt install -y git cmake build-essential curl ca-certificates
```

Verify installation:

```bash
git --version
cmake --version
```

OpenSSL is optional. If HTTPS support is wanted:

```bash
sudo apt install libssl-dev
```

The local HTTP server works without OpenSSL.

---

## 2. Create Swap Space

With limited physical memory (sub-4GB RAM), swap prevents out-of-memory crashes during compilation and inference.

Check whether swap is already enabled:

```bash
free -h
```

Look at the `Swap` row. If it shows `0B`, create a 2 GB swap file:

```bash
sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

Confirm it is active:

```bash
free -h
```

To enable swap automatically at every boot:

```bash
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

> **Note:** Swap is much slower than RAM. Avoid running many other programs while using llama.cpp.

---

## 3. Download llama.cpp

Download the source code:

```bash
cd ~
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
```

If the directory already exists, update it instead:

```bash
cd ~/llama.cpp
git pull
```

---

## 4. Compile llama.cpp

Remove any previous build:

```bash
cd ~/llama.cpp
rm -rf build
```

Configure llama.cpp with CPU instructions safe for legacy processors:

```bash
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
```

Build using one job to reduce memory usage:

```bash
cmake --build build --config Release --clean-first -j1
```

> **Warning:** Compilation may take a long time on this hardware. Do not open a browser or other heavy applications during the build.

---

## 5. Verify the Build

Check that the main executable exists:

```bash
ls -lh ~/llama.cpp/build/bin/llama-cli
```

Check that SSE4.2 was **not** enabled:

```bash
grep -oE -- '-m[^ "]+' ~/llama.cpp/build/compile_commands.json | sort -u
```

The output should contain:
```text
-mno-sse4.2
```

It should **not** contain:
```text
-msse4.2
-msse4.1
-march=native
```

Test the executable:

```bash
~/llama.cpp/build/bin/llama-cli --help
```

If the help text appears, llama.cpp is installed correctly.

---

## 6. Download a Model

Create a model directory:

```bash
mkdir -p ~/models
```

### Recommended Models for 3GB RAM

| Model | Parameters | Quantization | Notes |
|---|---|---|---|
| SmolLM2 360M Instruct | 360M | Q4_K_M | **Best starting point** |
| Qwen2.5 0.5B Instruct | 500M | Q4_K_M | Good alternative |
| TinyLlama 1.1B Chat | 1.1B | Q4_K_M | May be too slow or use too much memory |

Use a model file **smaller than approximately 1 GB**. The model must be in **GGUF** format. Do not use `.safetensors`, `.bin`, or other formats directly.

Place the downloaded `.gguf` file in `~/models/`.

Example expected path:
```text
~/models/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

### Recommended Settings

```text
Model:        360M–500M parameters
Quantization: Q4_K_M
Context:      256–512
Batch size:   8–16
Threads:      2
Output:       64–128 tokens
Swap:         1–2 GB
```

---

## 7. Quick Test

Run a quick test to make sure everything works:

```bash
~/llama.cpp/build/bin/llama-cli \
  -m ~/models/qwen2.5-0.5b-instruct-q4_k_m.gguf \
  -c 512 \
  -b 16 \
  -t 2 \
  -n 64 \
  -p "What is Linux?"
```

If you see generated text, the setup is complete. For detailed usage examples and more commands, see the companion guide: **USAGE-LLAMA-CPP.md**.

---

## 8. Performance Expectations

On older legacy CPUs without AVX or SSE4.2 instructions, with the **0.5B Q4_K_M** model, expect around **1 to 2.5 tokens per second** (e.g., benchmarked on a vintage dual-core CPU).

### This setup can handle:
- Short questions and simple explanations
- Basic Linux commands
- Small text transformations
- Very simple programming examples
- Demonstrating local AI functionality
- Learning how LLM inference works

### This setup will struggle with:
- Real-time or fast conversations
- Long conversations or large documents
- Complex coding assistance
- Large context windows (>512)
- Models above 1B parameters
- Multiple programs running simultaneously

Generation may be slow. Do not run a web browser with many tabs, a desktop application, and llama.cpp at the same time.

---

## 9. Troubleshooting

### `Illegal Instruction` crash

The crucial flag is `-DGGML_SSE42=OFF`. If you see this error, recompile with all the disable flags from Section 4.

### `cmake: command not found`

```bash
sudo apt update && sudo apt install cmake
```

### `g++: command not found`

```bash
sudo apt install build-essential
```

### `git: command not found`

```bash
sudo apt install git
```

### `Killed` during compilation

The system ran out of memory. Make sure swap is enabled:

```bash
free -h
```

Then compile with one job:

```bash
cmake --build build --config Release -j1
```

### `Killed` while loading the model

Use a smaller model or lower the context:

```bash
-c 256 -b 8
```

### The model is extremely slow

This is expected on an old Pentium processor. Try:

```bash
-t 2 -c 256 -b 8
```

Also close browsers and other applications.

### The model file cannot be opened

Check the path:

```bash
ls -lh ~/models
```

Then use the exact filename after `-m`.

### Check your CPU architecture

```bash
uname -m
```

It should report: `x86_64`

---

## 10. Uninstall

To uninstall llama.cpp, models, swap, and optionally the dependencies:

```bash
./setup-LLAMA.CPP.sh --uninstall
```

The script will interactively ask about each component:
- llama.cpp directory (`~/llama.cpp`)
- Downloaded models (`~/models`)
- Launch script (`~/run-small-llm.sh`)
- Swap file (`/swapfile`)
- Dependencies (`git`, `cmake`, `build-essential`, `curl`, `ca-certificates`)

Destructive actions default to **No** so you won't accidentally remove things.

### Manual cleanup (alternative)

Remove llama.cpp:
```bash
rm -rf ~/llama.cpp
```

Remove models:
```bash
rm -f ~/models/*.gguf
```

Remove swap:
```bash
sudo swapoff /swapfile
sudo rm /swapfile
```

Remove swap entry from `/etc/fstab`:
```bash
sudo sed -i '\|/swapfile|d' /etc/fstab
```

Remove dependencies (only if nothing else needs them):
```bash
sudo apt remove -y git cmake build-essential curl ca-certificates
sudo apt autoremove -y
```
