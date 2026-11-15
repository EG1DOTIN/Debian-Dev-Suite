# How-To-Use Guide: Modern CLI PowerTools

A practical guide to supercharging your everyday terminal workflow using **ripgrep**, **fzf**, **bat**, **eza**, and **zoxide**.

---

## Table of Contents

- [Overview & Quick Aliases](#overview--quick-aliases)
- [1. `ripgrep` (`rg`): 10x Faster Search](#1-ripgrep-rg-10x-faster-search)
- [2. `fzf`: Interactive Fuzzy Finding](#2-fzf-interactive-fuzzy-finding)
- [3. `bat`: Syntax Highlighted Cat](#3-bat-syntax-highlighted-cat)
- [4. `eza`: Modern Visual Directory Listings](#4-eza-modern-visual-directory-listings)
- [5. `zoxide` (`z`): Smart Directory Jumping](#5-zoxide-z-smart-directory-jumping)
- [Power Combos (Piping Tools Together)](#power-combos-piping-tools-together)

---

## Overview & Quick Aliases

After running `source ~/.bashrc`, the following aliases are active:

| Alias | Command | What It Does |
|---|---|---|
| `ls` | `eza --icons --group-directories-first` | Clean modern directory listing with icons |
| `ll` | `eza -lh --icons --group-directories-first --git` | Detailed long listing with Git change status |
| `la` | `eza -lah --icons --group-directories-first --git` | Detailed listing including hidden dotfiles |
| `tree` | `eza --tree --icons` | Interactive tree hierarchy view |
| `bat` | `bat` (or `batcat`) | Syntax highlighted viewer with Git indicators |
| `cd` | `z` (zoxide) | Smart frecency directory jump |
| `grep` | `rg` (ripgrep) | Ultra-fast regex search |

---

## 1. `ripgrep` (`rg`): 10x Faster Search

`ripgrep` recursively searches directories for a regex pattern while respecting your `.gitignore` by default.

### Common Commands:
```bash
# Basic search for a word across all files
rg "connect_database"

# Case-insensitive search
rg -i "error_handler"

# Search only in specific file types (e.g. Python files only)
rg -t py "def process_data"

# Search in specific file types (e.g. Rust or C files)
rg -t c "malloc"

# Search including hidden files and ignored files
rg -u "SECRET_KEY"

# Show filenames only that match
rg -l "TODO"

# Replace string across files (preview with rg)
rg "old_function"
```

---

## 2. `fzf`: Interactive Fuzzy Finding

`fzf` is an interactive filter that lets you fuzzy search through lists in real time.

### Keyboard Shortcuts:
- <kbd>Ctrl+T</kbd> : Fuzzy search for files in current directory and paste the selected file path onto your command line.
- <kbd>Ctrl+R</kbd> : Fuzzy search your entire bash command history.
- <kbd>Alt+C</kbd> : Fuzzy search directory tree and `cd` directly into the selected folder.

### Common Usage:
```bash
# Open any file in your editor interactively
geany $(fzf)

# Preview files before opening (with bat syntax highlighting)
fzf --preview 'bat --color=always {}'

# Interactively find and kill a process
kill -9 $(ps aux | fzf | awk '{print $2}')
```

---

## 3. `bat`: Syntax Highlighted Cat

`bat` replaces `cat` with colored output, line numbers, and Git change status markers (added, modified, deleted lines).

### Common Commands:
```bash
# View file with syntax highlighting
bat main.py

# View multiple files side by side or sequentially
bat config.json README.md

# Show non-printable characters (tabs, newlines)
bat -A script.sh

# Plain output without line numbers (for copying)
bat -p snippet.txt

# Pipe logs into bat with syntax highlighting
curl -s https://api.github.com | bat -l json
```

---

## 4. `eza`: Modern Visual Directory Listings

`eza` is an ultra-fast Rust alternative to `ls`.

### Common Commands:
```bash
# Standard clean listing with icons
ll

# Tree view up to 2 levels deep
tree -L 2

# Sort by file size
eza -lh --sort=size

# Sort by modification date (newest first)
eza -lh --sort=modified --reverse

# View Git repository status of every file
eza -lh --git
```

---

## 5. `zoxide` (`z`): Smart Directory Jumping

`zoxide` remembers the directories you visit most frequently and lets you jump to them from anywhere using partial names.

### Common Commands:
```bash
# Navigate around your filesystem as usual
cd ~/projects/web-application
cd /var/log/nginx

# Now jump from anywhere using partial words!
z web            # Jumps directly to ~/projects/web-application
z nginx          # Jumps directly to /var/log/nginx
z dev            # Jumps to Debian-Dev-Suite

# Interactive directory selection with fzf
zi
```

---

## Power Combos (Piping Tools Together)

### 1. Fuzzy Search + Syntax Highlight Preview + Open in Editor
```bash
# Interactively search files with a live syntax preview, then open in Geany
geany $(fzf --preview 'bat --color=always --style=numbers --line-range :100 {}')
```

### 2. Search for Code and Open at the Exact Line
```bash
# Search for pattern with ripgrep, select with fzf, and view with bat
rg --line-number "function_name" | fzf --delimiter : --preview 'bat --color=always {1} --highlight-line {2}'
```
