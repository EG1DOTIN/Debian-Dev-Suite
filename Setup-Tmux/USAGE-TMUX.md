# tmux Usage Guide — Layouts, Shortcuts & Developer Workflows

A practical guide to multi-tasking like a pro in the terminal using **tmux**.

---

## Table of Contents

- [Core Concepts (Sessions, Windows, Panes)](#core-concepts-sessions-windows-panes)
- [Essential Shortcuts Table](#essential-shortcuts-table)
- [Recommended Multi-Pane Developer Layouts](#recommended-multi-pane-developer-layouts)
  - [Layout 1: The Local AI Development Studio](#layout-1-the-local-ai-development-studio)
  - [Layout 2: The Git & Docker Ops Dashboard](#layout-2-the-git--docker-ops-dashboard)
- [Detaching & Re-attaching (Persistent Background Sessions)](#detaching--re-attaching-persistent-background-sessions)
- [Scrolling & Copying Text](#scrolling--copying-text)

---

## Core Concepts (Sessions, Windows, Panes)

1. **Session:** A workspace that persists even if you close your terminal or disconnect. You can detach and re-attach anytime.
2. **Window:** A tab inside a session (like browser tabs), visible in the bottom status bar (`1: bash`, `2: geany`).
3. **Pane:** A split screen inside a window. You can split one window into 2, 3, or 4 simultaneous terminal screens.

---

## Essential Shortcuts Table

> **Note:** The "Prefix" key is <kbd>Ctrl+B</kbd> (or <kbd>Ctrl+A</kbd>). Press Prefix, release, then press the shortcut key.

| Category | Shortcut | Action |
|---|---|---|
| **Splitting Panes** | <kbd>Prefix</kbd> + <kbd>\|</kbd> | Split pane vertically (side-by-side) |
| | <kbd>Prefix</kbd> + <kbd>-</kbd> | Split pane horizontally (stacked) |
| | <kbd>Prefix</kbd> + <kbd>x</kbd> | Close current pane |
| | <kbd>Prefix</kbd> + <kbd>z</kbd> | Toggle zoom on current pane (maximize/restore) |
| **Pane Navigation** | **Click with Mouse** | Instantly focus clicked pane |
| | <kbd>Prefix</kbd> + <kbd>h</kbd> | Move to left pane |
| | <kbd>Prefix</kbd> + <kbd>j</kbd> | Move to pane below |
| | <kbd>Prefix</kbd> + <kbd>k</kbd> | Move to pane above |
| | <kbd>Prefix</kbd> + <kbd>l</kbd> | Move to right pane |
| **Resizing Panes** | **Drag with Mouse** | Click and drag any pane border |
| | <kbd>Prefix</kbd> + <kbd>Alt+Arrow</kbd> | Nudge pane size |
| **Windows (Tabs)** | <kbd>Prefix</kbd> + <kbd>c</kbd> | Create new window |
| | <kbd>Prefix</kbd> + <kbd>1–9</kbd> | Switch to window 1 through 9 |
| | <kbd>Prefix</kbd> + <kbd>n</kbd> / <kbd>p</kbd> | Next / Previous window |
| | <kbd>Prefix</kbd> + <kbd>,</kbd> | Rename current window |
| **Sessions** | <kbd>Prefix</kbd> + <kbd>d</kbd> | **Detach from session** (leaves all programs running!) |

---

## Recommended Multi-Pane Developer Layouts

### Layout 1: The Local AI Development Studio

Run your local LLM, interactive coding editor, and AI terminal assistant in one screen:

```text
┌──────────────────────────────┬──────────────────────────────┐
│ Pane 1 (Left - 50% width)    │ Pane 2 (Top Right - 25%)     │
│                              │ run-llama-server             │
│ Editor or Code File          │ (Shows local LLM server logs)│
│ e.g. nano main.py or bash    ├──────────────────────────────┤
│                              │ Pane 3 (Bottom Right - 25%)  │
│                              │ ai "Explain this function"   │
└──────────────────────────────┴──────────────────────────────┘
```

**How to create this layout:**
1. Open tmux: `tm`
2. Split vertically: <kbd>Ctrl+B</kbd> then <kbd>|</kbd>
3. In the right pane, split horizontally: <kbd>Ctrl+B</kbd> then <kbd>-</kbd>
4. In Top Right pane: run `run-llama-server`
5. In Bottom Right pane: use your `ai` copilot command!

---

### Layout 2: The Git & Docker Ops Dashboard

Monitor containers and manage Git changes simultaneously:

```text
┌──────────────────────────────┬──────────────────────────────┐
│ Pane 1 (Left - 50%)          │ Pane 2 (Right - 50%)         │
│                              │                              │
│ lazygit                      │ lazydocker                   │
│ (Visual Git staging & diffs) │ (Visual container monitoring)│
│                              │                              │
└──────────────────────────────┴──────────────────────────────┘
```

**How to create this layout:**
1. Split vertically: <kbd>Ctrl+B</kbd> then <kbd>|</kbd>
2. In left pane, run: `lg`
3. In right pane, run: `lz`

---

## Detaching & Re-attaching (Persistent Background Sessions)

One of tmux's greatest features is that your programs **never close** if you disconnect or close the terminal window:

1. To detach and leave programs running:
   - Press <kbd>Ctrl+B</kbd> then <kbd>d</kbd>.
   - Tmux outputs: `[detached (from session 0)]`.
2. Later, reopen your terminal and type:
   ```bash
   tm
   ```
   You are instantly back right where you left off, with all your split panes and running programs intact!

---

## Scrolling & Copying Text

- **Mouse Scrolling:** Simply place your cursor over any pane and scroll your mouse wheel up. A copy indicator appears in the top right.
- **Copying Text:** Click and drag your mouse to highlight text; text is copied automatically. Press <kbd>q</kbd> to exit scroll mode.
