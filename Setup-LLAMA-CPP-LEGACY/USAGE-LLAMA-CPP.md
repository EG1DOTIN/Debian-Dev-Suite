# llama.cpp Usage Guide — Command Examples & Tips

This guide covers how to use llama.cpp **after installation**. For installation instructions, see [README.md](README.md).

All examples assume:
- llama.cpp is installed at `~/llama.cpp`
- Models are stored in `~/models/`
- You are using 2 CPU threads (`-t 2`)

---

## Setting Up the Model Path

Set a variable so you don't have to type the full path every time:

```bash
MODEL="$HOME/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
LLAMA="$HOME/llama.cpp/build/bin/llama-cli"
```

To make these permanent, add them to your `~/.bashrc`:

```bash
echo 'export MODEL="$HOME/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"' >> ~/.bashrc
echo 'export LLAMA="$HOME/llama.cpp/build/bin/llama-cli"' >> ~/.bashrc
source ~/.bashrc
```

Now you can use `$LLAMA` and `$MODEL` in all commands below.

---

## Command Reference

### Common Flags

| Flag | Meaning | Recommended Value |
|---|---|---|
| `-m` | Path to GGUF model file | `$MODEL` |
| `-t` | Number of CPU threads | `2` (match your CPU cores) |
| `-c` | Context size (tokens) | `256`–`512` |
| `-b` | Batch size | `8`–`16` (lower = less RAM) |
| `-n` | Maximum output tokens | `64`–`128` |
| `-p` | Prompt text | Your question |
| `-cnv` | Enable conversation mode | *(no value needed)* |
| `--no-conversation` | Disable conversation mode | *(no value needed)* |
| `-f` | Read prompt from a file | Path to text file |
| `--temp` | Temperature (creativity) | `0.0`–`1.0` |
| `--top-k` | Top-K sampling | `40` (default) |
| `--top-p` | Top-P (nucleus) sampling | `0.9` (default) |
| `--repeat-penalty` | Penalize repeated words | `1.1` (default) |

---

## One-Shot Questions

Ask a single question and exit:

```bash
$LLAMA \
  -m "$MODEL" \
  -t 2 \
  -c 512 \
  -b 16 \
  -n 128 \
  --no-conversation \
  -p "Explain in simple words what Linux is."
```

### More one-shot examples:

**Summarize something:**
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  -p "Summarize in 3 bullet points: Linux is a free and open source operating system kernel created by Linus Torvalds in 1991. It powers servers, desktops, phones (Android), and embedded devices worldwide."
```

**Get a Linux command:**
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 64 --no-conversation \
  -p "Give me the Linux command to find all .txt files larger than 1MB in the home directory."
```

**Simple translation:**
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 64 --no-conversation \
  -p "Translate to French: Hello, how are you today?"
```

**Text classification:**
```bash
$LLAMA -m "$MODEL" -t 2 -c 256 -b 16 -n 32 --no-conversation \
  -p "Classify the sentiment as positive, negative, or neutral: I really enjoyed the movie but the ending was disappointing."
```

**Simple math / logic:**
```bash
$LLAMA -m "$MODEL" -t 2 -c 256 -b 16 -n 64 --no-conversation \
  -p "What is 15% of 240? Show the calculation step by step."
```

**Write a short poem:**
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  -p "Write a 4-line poem about the ocean."
```

**Explain a concept:**
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  -p "Explain what an IP address is to a 10-year-old."
```

---

## Interactive Chat Mode

Start a back-and-forth conversation:

```bash
$LLAMA \
  -m "$MODEL" \
  -t 2 \
  -c 512 \
  -b 16 \
  -n 128 \
  -cnv
```

Type your question and press Enter. The model will respond, then wait for your next input.

If `-cnv` is not supported by your llama.cpp version, omit it:

```bash
$LLAMA \
  -m "$MODEL" \
  -t 2 \
  -c 512 \
  -b 16 \
  -n 128
```

To exit, press `Ctrl+C`.

---

## Reading Prompts from a File

For longer prompts, save them to a file and pass it with `-f`:

Create a prompt file:
```bash
echo "List 5 useful Linux terminal commands for beginners. For each command, give a one-line description and an example." > ~/prompt.txt
```

Run it:
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 256 --no-conversation \
  -f ~/prompt.txt
```

This is useful when prompts are too long to type on one line.

---

## Controlling Output Quality

### Lower temperature = more focused, predictable answers:
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  --temp 0.2 \
  -p "What is the capital of France?"
```

### Higher temperature = more creative, varied answers:
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  --temp 0.9 \
  -p "Write a creative short story about a robot learning to cook."
```

### Deterministic output (temperature 0):
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  --temp 0 \
  -p "Convert 100 Celsius to Fahrenheit. Show the formula."
```

### Reduce repetition:
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  --repeat-penalty 1.3 \
  -p "Describe the benefits of open source software."
```

---

## Local Browser Server

Start a web-based chat UI accessible from your browser:

```bash
~/llama.cpp/build/bin/llama-server \
  -m "$MODEL" \
  -t 2 \
  -c 1024 \
  --host 127.0.0.1 \
  --port 8080
```

Then open in a browser:
```text
http://127.0.0.1:8080
```

Stop the server with `Ctrl+C`.

> **Note:** The CLI uses slightly less memory and starts faster than the browser interface, but the browser UI is more convenient for longer sessions.

### Server on a different port:
```bash
~/llama.cpp/build/bin/llama-server \
  -m "$MODEL" \
  -t 2 \
  -c 512 \
  --host 127.0.0.1 \
  --port 3000
```

---

## Benchmarking CPU Threads

Find out whether 1 or 2 threads is faster on your CPU:

**Test with 1 thread:**
```bash
time $LLAMA -m "$MODEL" -t 1 -c 512 -b 16 -n 32 --no-conversation \
  -p "Write one short sentence about Linux."
```

**Test with 2 threads:**
```bash
time $LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 32 --no-conversation \
  -p "Write one short sentence about Linux."
```

Compare the `real` time values. Use whichever is faster. On older dual-core processors, 2 threads is generally optimal.

---

## Low-Memory Mode

If the normal commands use too much memory or the system becomes unresponsive:

### Minimal settings:
```bash
$LLAMA -m "$MODEL" -t 2 -c 256 -b 8 -n 64 \
  -p "Give a short answer: what is Linux?"
```

### Ultra-low settings (last resort):
```bash
$LLAMA -m "$MODEL" -t 1 -c 128 -b 4 -n 32 \
  -p "What is Linux?"
```

### What each reduction does:

| Setting | Effect |
|---|---|
| Lower `-c` (256 → 128) | Less memory for context, shorter memory of conversation |
| Lower `-b` (16 → 8 → 4) | Slower prompt processing, less peak RAM |
| Lower `-n` (128 → 64 → 32) | Shorter answers |
| Lower `-t` (2 → 1) | Uses one core, may reduce memory contention |

---

## Monitoring Memory Usage

Open a **second terminal** and run:

```bash
watch -n 1 free -h
```

Important values:
- `used`: currently used memory
- `available`: memory still available
- `Swap used`: how much swap is being used

For detailed CPU and memory per process:
```bash
top
```

### If the computer becomes unresponsive:

1. Press `Ctrl+C` in the llama.cpp terminal
2. Close other applications
3. Use a smaller model
4. Lower the context size: `-c 256` or `-c 128`

---

## Finding Your Model Files

List all downloaded models:

```bash
find ~/models -type f -name "*.gguf"
```

Check file sizes:
```bash
ls -lh ~/models/*.gguf
```

Use the exact filename shown by those commands after `-m`.

---

## Creating a Launch Script

Save time with a reusable launch script:

```bash
nano ~/run-small-llm.sh
```

Paste this content:

```bash
#!/usr/bin/env bash

MODEL="$HOME/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
LLAMA="$HOME/llama.cpp/build/bin/llama-cli"

if [ ! -f "$MODEL" ]; then
    echo "Model not found:"
    echo "$MODEL"
    echo
    echo "Place a GGUF model at that path or edit this script."
    exit 1
fi

if [ ! -x "$LLAMA" ]; then
    echo "llama-cli was not found:"
    echo "$LLAMA"
    exit 1
fi

exec "$LLAMA" \
    -m "$MODEL" \
    -c 512 \
    -b 16 \
    -t 2 \
    -n 128 \
    -cnv
```

Save (`Ctrl+O`, Enter, `Ctrl+X`) and make it executable:

```bash
chmod +x ~/run-small-llm.sh
```

Run it:
```bash
~/run-small-llm.sh
```

---

## Useful Command Patterns

### Pipe output to a file:
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  -p "Write 5 Linux tips for beginners." > ~/output.txt
```

### Time any command:
```bash
time $LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 64 --no-conversation \
  -p "What is a kernel?"
```

### Suppress log output (cleaner output):
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  --log-disable \
  -p "What is a kernel?"
```

### Use a system prompt (instruction prefix):
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation \
  -p "You are a helpful Linux tutor. Explain what the chmod command does and give 3 examples."
```

---

## Quick Reference Card

### Standard settings (recommended start):
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128
```

### If the computer becomes slow:
```bash
$LLAMA -m "$MODEL" -t 2 -c 256 -b 8 -n 64
```

### One-shot question (no chat):
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 --no-conversation -p "Your question here"
```

### Interactive chat:
```bash
$LLAMA -m "$MODEL" -t 2 -c 512 -b 16 -n 128 -cnv
```

### Browser UI:
```bash
~/llama.cpp/build/bin/llama-server -m "$MODEL" -t 2 -c 1024 --host 127.0.0.1 --port 8080
```
