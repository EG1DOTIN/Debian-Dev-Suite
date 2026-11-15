# How-To-Use Guide: Git Workflow & LazyGit TUI

A comprehensive guide to managing Git repositories at light speed using **LazyGit** and optimized Git defaults—without touching heavy desktop Git GUIs.

---

## Table of Contents

- [Launching LazyGit](#launching-lazygit)
- [The 5 Main Panels](#the-5-main-panels)
- [Essential Keyboard Shortcuts](#essential-keyboard-shortcuts)
- [Step-by-Step Daily Workflows](#step-by-step-daily-workflows)
  - [1. Staging Files & Partial Hunks](#1-staging-files--partial-hunks)
  - [2. Writing Commits](#2-writing-commits)
  - [3. Pushing & Pulling](#3-pushing--pulling)
  - [4. Creating & Switching Branches](#4-creating--switching-branches)
  - [5. Interactive Rebasing & Squashing](#5-interactive-rebasing--squashing)
  - [6. Visual Merge Conflict Resolution](#6-visual-merge-conflict-resolution)
  - [7. Stashing Changes](#7-stashing-changes)
- [Optimized CLI Git Aliases](#optimized-cli-git-aliases)

---

## Launching LazyGit

In any Git repository, launch LazyGit via either command:

```bash
lazygit
# or use the quick alias:
lg
```

Press <kbd>?</kbd> at any time inside LazyGit to view contextual help for the current panel.

---

## The 5 Main Panels

LazyGit is divided into focused panels with number shortcuts:

```text
┌───────────────┬──────────────────────────────────────────┐
│ [1] Files     │ [Main View]                              │
│ [2] Branches  │ Shows colored diffs, commit logs,        │
│ [3] Commits   │ file content, and merge conflict views   │
│ [4] Stash     │                                          │
└───────────────┴──────────────────────────────────────────┘
```

- <kbd>1</kbd> : Jump to **Files** panel (working tree changes).
- <kbd>2</kbd> : Jump to **Branches** panel (local & remote branches, tags).
- <kbd>3</kbd> : Jump to **Commits** panel (commit history of current branch).
- <kbd>4</kbd> : Jump to **Stash** panel (stashed changes).
- <kbd>Tab</kbd> / <kbd>]</kbd> : Cycle forward through panels.
- <kbd>Shift+Tab</kbd> / <kbd>[</kbd> : Cycle backward through panels.
- <kbd>Esc</kbd> / <kbd>q</kbd> : Exit panel or quit LazyGit.

---

## Essential Keyboard Shortcuts

| Key | Action |
|---|---|
| <kbd>Space</kbd> | Stage / Unstage selected file or line |
| <kbd>a</kbd> | Stage / Unstage ALL files |
| <kbd>c</kbd> | Commit staged changes (opens prompt) |
| <kbd>C</kbd> | Commit using standard Git commit editor |
| <kbd>A</kbd> | Amend previous commit |
| <kbd>P</kbd> | Push to remote (<kbd>Shift+P</kbd>) |
| <kbd>p</kbd> | Pull from remote |
| <kbd>d</kbd> | Discard changes / delete branch / drop commit |
| <kbd>Enter</kbd> | Focus into detail view (e.g. view hunks inside a file) |
| <kbd>z</kbd> | Undo last Git action |
| <kbd>Z</kbd> | Redo last undone Git action |

---

## Step-by-Step Daily Workflows

### 1. Staging Files & Partial Hunks

#### Staging Entire Files:
1. In the **Files** panel (<kbd>1</kbd>), navigate up/down with <kbd>↑</kbd> / <kbd>↓</kbd> or <kbd>k</kbd> / <kbd>j</kbd>.
2. Press <kbd>Space</kbd> to stage or unstage a file.

#### Staging Specific Lines or Hunks (Partial Commit):
1. Highlight a modified file and press <kbd>Enter</kbd> to enter the diff view.
2. Navigate between hunks with <kbd>[</kbd> / <kbd>]</kbd> or line-by-line with <kbd>k</kbd> / <kbd>j</kbd>.
3. Press <kbd>Space</kbd> on a single line or select a range with <kbd>v</kbd> + <kbd>Space</kbd> to stage only those lines!
4. Press <kbd>Esc</kbd> to return to the Files panel.

---

### 2. Writing Commits

1. Once changes are staged, press <kbd>c</kbd>.
2. Type your commit message in the popup window and press <kbd>Enter</kbd>.
3. To add a multiline description, press <kbd>Enter</kbd> to confirm title, then type the extended message.

---

### 3. Pushing & Pulling

- Press <kbd>Shift+P</kbd> (<kbd>P</kbd>) to push commits to the remote repository.
- Press <kbd>p</kbd> to pull latest changes from the upstream branch.

---

### 4. Creating & Switching Branches

1. Switch to the **Branches** panel (<kbd>2</kbd>).
2. Press <kbd>n</kbd> to create a new branch. Type the name and press <kbd>Enter</kbd>.
3. To switch to an existing branch, highlight it and press <kbd>Space</kbd>.
4. To merge a branch into your current branch, highlight it and press <kbd>M</kbd>.

---

### 5. Interactive Rebasing & Squashing

1. Switch to the **Commits** panel (<kbd>3</kbd>).
2. Highlight a past commit you want to edit or squash into:
   - Press <kbd>s</kbd> : Squash into the commit below it.
   - Press <kbd>r</kbd> : Reword (edit) the commit message.
   - Press <kbd>e</kbd> : Edit commit contents.
   - Press <kbd>d</kbd> : Drop (delete) this commit.

---

### 6. Visual Merge Conflict Resolution

When a merge or rebase encounters a conflict:
1. The conflicted file appears highlighted in red in the **Files** panel.
2. Press <kbd>Enter</kbd> to enter the interactive conflict resolver.
3. LazyGit displays `Your changes (ours)`, `Their changes`, and the common ancestor.
4. Press <kbd>b</kbd> to accept both, <kbd>Space</kbd> on individual sections to pick them, or edit manually.
5. Press <kbd>Esc</kbd> once resolved.

---

### 7. Stashing Changes

- In the **Files** panel, press <kbd>s</kbd> to stash all working changes with a descriptive message.
- To view stashes, switch to the **Stash** panel (<kbd>4</kbd>).
- Press <kbd>Space</kbd> to apply a stash, or <kbd>g</kbd> to pop it.

---

## Optimized CLI Git Aliases

The installer configures standard terminal Git aliases in `~/.gitconfig`:

| Command | Equivalent | What It Does |
|---|---|---|
| `git st` | `git status -s` | Compact, colored two-column status |
| `git lg` | `git log --oneline --graph --decorate -n 15` | Visual graph log of recent commits |
| `git br` | `git branch` | List local branches |
| `git ci` | `git commit` | Fast commit |
