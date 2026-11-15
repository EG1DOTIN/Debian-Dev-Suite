# How-To-Use Guide: Developer Runtimes (uv, fnm, C/C++)

A comprehensive guide to managing **Python**, **Node.js**, and **C/C++** environments using modern, high-speed, 0-telemetry runtimes.

---

## Table of Contents

- [1. Python Development with `uv`](#1-python-development-with-uv)
  - [Why `uv` Replaces pip, venv, and poetry](#why-uv-replaces-pip-venv-and-poetry)
  - [Project Creation & Virtual Environments](#project-creation--virtual-environments)
  - [Managing Dependencies](#managing-dependencies)
  - [Running Code in Isolated Environments](#running-code-in-isolated-environments)
  - [Managing Multiple Python Versions](#managing-multiple-python-versions)
  - [Running Standalone CLI Tools](#running-standalone-cli-tools)
- [2. Node.js Development with `fnm`](#2-nodejs-development-with-fnm)
  - [Why `fnm` Replaces `nvm`](#why-fnm-replaces-nvm)
  - [Installing & Managing Node Versions](#installing--managing-node-versions)
  - [Automatic Directory-Based Switching](#automatic-directory-based-switching)
- [3. C/C++ Systems Development](#3-cc-systems-development)
  - [Compiling C and C++ Programs](#compiling-c-and-c-programs)
  - [Debugging with GDB](#debugging-with-gdb)
  - [Memory Leak Detection with Valgrind](#memory-leak-detection-with-valgrind)

---

## 1. Python Development with `uv`

**`uv`** is an ultra-fast Python package and project manager built by Astral in Rust. It replaces `pip`, `pip-tools`, `virtualenv`, and `poetry` with a single binary that is **10 to 100 times faster**.

### Why `uv` Replaces pip, venv, and poetry
- **Instant Package Installs:** Caches wheels globally using hardlinks; installing packages takes milliseconds instead of minutes.
- **Self-Contained Python Downloads:** Installs isolated Python versions (e.g. 3.10, 3.11, 3.12) automatically without needing external PPAs.
- **Zero Telemetry:** Strict privacy; no analytics sent over the network.

---

### Project Creation & Virtual Environments

```bash
# Create a new Python project directory
uv init my-project
cd my-project

# Notice the clean structure:
#   pyproject.toml
#   main.py
#   README.md
#   .python-version
```

---

### Managing Dependencies

```bash
# Add packages (creates lockfile and installs in virtualenv instantly)
uv add requests httpx

# Add development-only dependencies
uv add --dev pytest ruff

# Remove a package
uv remove requests
```

---

### Running Code in Isolated Environments

`uv` runs commands within the project's virtual environment automatically:

```bash
# Run your main script
uv run main.py

# Run tests or linters
uv run pytest
uv run ruff check .

# Start an interactive Python shell with packages available
uv run python
```

---

### Managing Multiple Python Versions

No need to compile Python from source or touch system packages:

```bash
# Install specific Python versions
uv python install 3.11
uv python install 3.12

# List installed versions
uv python list

# Pin current project to Python 3.11
uv python pin 3.11
```

---

### Running Standalone CLI Tools

Run CLI utilities without installing them into your global system Python:

```bash
# Run Ruff linter once without permanent installation
uvx ruff check .

# Install a global CLI tool permanently into an isolated environment
uv tool install ruff
uv tool install black
```

---

## 2. Node.js Development with `fnm`

**`fnm` (Fast Node Manager)** is built in Rust to manage multiple Node.js versions.

### Why `fnm` Replaces `nvm`
- **Zero Shell Delay:** `nvm` can add 300ms–800ms of lag every time you open a terminal tab. `fnm` initializes in **under 10ms**.
- **Fully Cross-Platform & 0 Telemetry:** Simple, single-binary architecture without background telemetry.

---

### Installing & Managing Node Versions

```bash
# Install the latest Long Term Support (LTS) release of Node.js
fnm install --lts

# Install a specific version
fnm install 20
fnm install 22

# List installed versions
fnm list

# Switch to a version for current terminal
fnm use 20

# Set a default version across all new shells
fnm default 20
```

Verify your active Node.js and NPM versions:
```bash
node -v
npm -v
```

---

### Automatic Directory-Based Switching

If your project contains a `.nvmrc` or `.node-version` file specifying `20.10.0`, `fnm` automatically switches to that version the moment you `cd` into that directory!

```bash
cd my-node-project
# fnm automatically outputs: Using Node v20.10.0
```

---

## 3. C/C++ Systems Development

The suite installs `build-essential`, `gdb`, `valgrind`, and `cmake` for native low-level programming.

### Compiling C and C++ Programs

#### C Compilation:
```bash
# Compile with all warnings enabled and debugging symbols
gcc -Wall -Wextra -g main.c -o app

# Run binary
./app
```

#### Modern C++ Compilation:
```bash
# Compile with modern C++20 standard and optimizations
g++ -std=c++20 -O2 -Wall -Wextra main.cpp -o app

# Run binary
./app
```

---

### Debugging with GDB

```bash
# Start debugger
gdb ./app

# Inside GDB:
(gdb) break main      # Set breakpoint at main function
(gdb) run             # Run program
(gdb) next            # Step over next line
(gdb) step            # Step into function
(gdb) print variable  # Print variable value
(gdb) backtrace       # View stack trace on crash
(gdb) quit            # Exit GDB
```

---

### Memory Leak Detection with Valgrind

`valgrind` is an essential tool to ensure your C/C++ code has no memory leaks or invalid memory accesses:

```bash
valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes ./app
```

Expected clean output:
```text
All heap blocks were freed -- no leaks are possible
ERROR SUMMARY: 0 errors from 0 contexts
```
