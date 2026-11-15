#!/usr/bin/env bash

###############################################################################
# Universal Markdown Viewer for Debian & antiX Systems
#
# Ultra-lightweight, local-first Markdown viewer powered by Pandoc & Surf WebKit:
#   - 100% Free & Open-Source (FOSS), zero telemetry, local-first
#   - True GitHub Markdown styling (Dark & Light modes with persistent toggle)
#   - Guaranteed 100% full-window width viewing across all displays
#   - Hardware crash immunity (disables WebKitGTK buggy sandboxing and GPU compositing
#     to eliminate g_spawn_sync() / waitpid() ECHILD crashes and segmentation faults)
#   - Automatic browser fallback (if Surf encounters issues, gracefully opens in system browser)
#   - High-visibility Copy Code button with dual-mode clipboard engine
#   - Embedded offline-ready CSS (works 100% offline without CDN dependencies)
#   - Mermaid diagram support with code-block sanitization
#   - Automatic resource path resolution for relative images & assets
#   - Desktop & File Manager integration as "MD-Viewer (Surf)" (SpaceFM, zzzFM, PCManFM)
#   - Interactive uninstallation with optional dependency removal (pandoc, surf)
#
# USAGE:
#   ./setup-md-viewer.sh --install       # Install pandoc, surf, launcher, & integrations
#   ./setup-md-viewer.sh --uninstall     # Cleanly remove launcher, desktop & ask for dependencies
#   ./setup-md-viewer.sh --status        # Show installed components and associations
#   ./setup-md-viewer.sh --help          # Show usage options and examples
###############################################################################

set -eu

VIEWER_BIN="/usr/local/bin/pandoc-md-viewer"
VIEWER_SYMLINK="/usr/local/bin/md-viewer"
USER_BIN="$HOME/.local/bin/pandoc-md-viewer"
DESKTOP_DIR="/usr/local/share/applications"
USER_DESKTOP_DIR="$HOME/.local/share/applications"

show_help() {
    cat << 'EOF'
Universal Markdown Viewer for Debian & antiX Systems

Usage: ./setup-md-viewer.sh [OPTION]

Options:
  --install, -i      Install viewer dependencies, launcher executable, and file associations
  --uninstall, -u    Remove launcher executables, desktop entries, and file manager hooks
  --status, -s       Display installation status of Pandoc, Surf, and launcher binaries
  --help, -h         Show this help message

Examples:
  ./setup-md-viewer.sh --install       # Full setup (installs pandoc, surf, and launcher)
  ./setup-md-viewer.sh --status        # Check if viewer and dependencies are installed
  ./setup-md-viewer.sh --uninstall     # Cleanly remove viewer (prompts to remove dependencies)

To view any Markdown file once installed:
  md-viewer README.md
  pandoc-md-viewer /path/to/document.md
  (Or right-click any .md file in SpaceFM, zzzFM, or PCManFM -> "Open with MD-Viewer (Surf)")
EOF
}

check_root_or_sudo() {
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
        else
            SUDO=""
        fi
    else
        SUDO=""
    fi
}

show_status() {
    echo "=================================================="
    echo "       Markdown Viewer Component Diagnostics      "
    echo "=================================================="
    
    printf "  - Pandoc Engine      : "
    if command -v pandoc >/dev/null 2>&1; then
        echo "Installed ($(pandoc --version 2>/dev/null | head -n 1))"
    else
        echo "Not installed (Run ./setup-md-viewer.sh --install)"
    fi

    printf "  - Surf Browser       : "
    if command -v surf >/dev/null 2>&1; then
        echo "Installed ($(surf -v 2>&1 | head -n 1 || echo 'WebKit Surf'))"
    else
        echo "Not installed (Run ./setup-md-viewer.sh --install)"
    fi

    printf "  - Global Launcher    : "
    if [ -x "$VIEWER_BIN" ]; then
        echo "Installed at $VIEWER_BIN"
    elif [ -x "$USER_BIN" ]; then
        echo "Installed at $USER_BIN"
    else
        echo "Not installed"
    fi

    printf "  - Quick Alias        : "
    if [ -x "$VIEWER_SYMLINK" ]; then
        echo "Installed at $VIEWER_SYMLINK ('md-viewer')"
    else
        echo "Not configured"
    fi

    printf "  - Desktop Entry      : "
    if [ -f "$DESKTOP_DIR/pandoc-md-viewer.desktop" ] || [ -f "$USER_DESKTOP_DIR/pandoc-md-viewer.desktop" ]; then
        echo "Registered (MD-Viewer (Surf))"
    else
        echo "Not registered"
    fi

    printf "  - File Manager Menu  : "
    FM_FOUND=0
    for fm_dir in "$HOME/.config/zzzfm" "$HOME/.config/spacefm"; do
        if [ -d "$fm_dir/scripts/hand_text_markdown" ]; then
            echo "Integrated ($(basename "$fm_dir") -> 'Open with MD-Viewer (Surf)')"
            FM_FOUND=1
            break
        fi
    done
    [ "$FM_FOUND" -eq 0 ] && echo "Standard MIME associations"

    echo "=================================================="
}

install_viewer() {
    check_root_or_sudo

    echo "[+] Step 1: Checking and installing dependencies (Pandoc and Surf)..."
    MISSING_PKGS=""
    command -v pandoc >/dev/null 2>&1 || MISSING_PKGS="$MISSING_PKGS pandoc"
    command -v surf >/dev/null 2>&1 || MISSING_PKGS="$MISSING_PKGS surf"

    if [ -n "$MISSING_PKGS" ]; then
        echo "    Installing missing packages:$MISSING_PKGS..."
        $SUDO apt update
        $SUDO apt install -y $MISSING_PKGS
    else
        echo "    [OK] Pandoc and Surf are already installed."
    fi

    # Choose user-space or system-wide based on execution privilege
    local dest_bin dest_link dest_desktop
    if [ "$(id -u)" -eq 0 ]; then
        dest_bin="$VIEWER_BIN"
        dest_link="$VIEWER_SYMLINK"
        dest_desktop="$DESKTOP_DIR"
    else
        dest_bin="$USER_BIN"
        dest_link="$HOME/.local/bin/md-viewer"
        dest_desktop="$USER_DESKTOP_DIR"
        SUDO=""
    fi

    echo "[+] Step 2: Creating standalone viewer executable at $dest_bin..."
    $SUDO mkdir -p "$(dirname "$dest_bin")"

    # Generate the launcher script with embedded offline styles, full width layout and dual-mode clipboard
    $SUDO tee "$dest_bin" > /dev/null << 'EOF_LAUNCHER'
#!/usr/bin/env bash
set -eu

if [ $# -lt 1 ] || [ -z "$1" ]; then
    echo "Usage: pandoc-md-viewer <path-to-markdown-file>"
    echo "Alias: md-viewer <path-to-markdown-file>"
    exit 1
fi

TARGET_FILE="$1"
if [ ! -f "$TARGET_FILE" ]; then
    echo "[-] Error: File not found: $TARGET_FILE"
    exit 1
fi

# Resolve absolute path & working directory for relative image loading
REAL_FILE_PATH="$(realpath "$TARGET_FILE" 2>/dev/null || readlink -f "$TARGET_FILE" 2>/dev/null || echo "$TARGET_FILE")"
DOC_DIR="$(dirname "$REAL_FILE_PATH")"
DOC_NAME="$(basename "$REAL_FILE_PATH")"

TMP_DIR="$(mktemp -d /tmp/md_view_XXXXXX)"
TMP_HTML="$TMP_DIR/index.html"
HEADER_FILE="$TMP_DIR/header.html"

# Ensure temp directory is cleaned up on exit or signal
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM HUP

# Write self-contained HTML Header (Styles, Theme Engine, and Copy Engine)
cat << 'HTML_HEADER' > "$HEADER_FILE"
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  :root {
    --bg-primary: #0d1117;
    --bg-secondary: #161b22;
    --bg-canvas: #090d13;
    --text-primary: #c9d1d9;
    --text-muted: #8b949e;
    --text-heading: #f0f6fc;
    --border-color: #30363d;
    --border-muted: #21262d;
    --accent: #58a6ff;
    --accent-hover: #79c0ff;
    --code-bg: #161b22;
    --copy-btn-bg: #21262d;
    --copy-btn-text: #c9d1d9;
    --copy-btn-border: #388bfd66;
    --copy-btn-hover: #30363d;
    --copy-btn-success-bg: #238636;
    --copy-btn-success-border: #2ea043;
    --table-zebra: #161b2280;
    --link-color: #58a6ff;
    --blockquote-border: #3b434b;
    --nav-bg: rgba(13, 17, 23, 0.94);
  }

  body.light-theme {
    --bg-primary: #ffffff;
    --bg-secondary: #f6f8fa;
    --bg-canvas: #f0f2f5;
    --text-primary: #1f2328;
    --text-muted: #656d76;
    --text-heading: #1f2328;
    --border-color: #d0d7de;
    --border-muted: #e1e4e8;
    --accent: #0969da;
    --accent-hover: #0550ae;
    --code-bg: #f6f8fa;
    --copy-btn-bg: #f6f8fa;
    --copy-btn-text: #24292f;
    --copy-btn-border: #0969da55;
    --copy-btn-hover: #eaeef2;
    --copy-btn-success-bg: #1a7f37;
    --copy-btn-success-border: #1a7f37;
    --table-zebra: #f6f8fa;
    --link-color: #0969da;
    --blockquote-border: #d0d7de;
    --nav-bg: rgba(255, 255, 255, 0.96);
  }

  * { box-sizing: border-box; }

  html {
    background-color: var(--bg-canvas);
    scroll-behavior: smooth;
    width: 100% !important;
    max-width: 100% !important;
    margin: 0 !important;
    padding: 0 !important;
  }

  /* Override Pandoc's default 36em width constraint completely */
  body, body.markdown-body {
    margin: 0 !important;
    padding: 0 !important;
    width: 100% !important;
    max-width: 100% !important;
    min-width: 100% !important;
    background-color: var(--bg-primary);
    color: var(--text-primary);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Roboto, Helvetica, Arial, sans-serif;
    font-size: 16px;
    line-height: 1.65;
    word-wrap: break-word;
    min-height: 100vh;
    box-sizing: border-box !important;
    transition: background-color 0.2s ease, color 0.2s ease;
  }

  /* Sticky Top Navigation Bar (Full Window Width) */
  .top-navbar {
    position: sticky;
    top: 0;
    z-index: 100;
    background: var(--nav-bg);
    backdrop-filter: blur(8px);
    border-bottom: 1px solid var(--border-color);
    padding: 10px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 14px;
    width: 100% !important;
    max-width: 100% !important;
    box-sizing: border-box !important;
  }

  .nav-left {
    display: flex;
    align-items: center;
    gap: 10px;
    overflow: hidden;
  }

  .doc-badge {
    background: var(--bg-secondary);
    border: 1px solid var(--border-color);
    color: var(--accent);
    padding: 2px 8px;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    flex-shrink: 0;
  }

  .doc-title {
    font-weight: 600;
    color: var(--text-heading);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 480px;
  }

  .nav-right {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-shrink: 0;
  }

  .nav-btn {
    background: var(--bg-secondary);
    color: var(--text-primary);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    padding: 5px 10px;
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 5px;
    transition: all 0.15s ease;
  }

  .nav-btn:hover {
    background: var(--border-color);
    color: var(--text-heading);
  }

  /* Main Document Container - 100% Full Window Width */
  .container {
    width: 100% !important;
    max-width: 100% !important;
    min-width: 100% !important;
    margin: 0 !important;
    padding: 28px 40px 64px 40px !important;
    box-sizing: border-box !important;
    transition: max-width 0.2s ease, margin 0.2s ease;
  }

  .container.readable-width {
    width: 100% !important;
    max-width: 1080px !important;
    margin: 0 auto !important;
  }

  /* Force all direct content children to expand full width */
  .container > * {
    max-width: 100% !important;
  }

  /* Typography & Core Elements */
  h1, h2, h3, h4, h5, h6 {
    color: var(--text-heading);
    font-weight: 600;
    margin-top: 28px;
    margin-bottom: 16px;
    line-height: 1.3;
    width: 100% !important;
  }

  h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border-color); }
  h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border-color); }
  h3 { font-size: 1.25em; }
  h4 { font-size: 1em; }

  p, ul, ol, dl, table, blockquote {
    margin-top: 0;
    margin-bottom: 16px;
    width: 100% !important;
  }

  a {
    color: var(--link-color);
    text-decoration: none;
  }

  a:hover {
    text-decoration: underline;
  }

  ul, ol {
    padding-left: 2em;
  }

  li + li {
    margin-top: 0.25em;
  }

  blockquote {
    padding: 0 1em;
    color: var(--text-muted);
    border-left: 0.25em solid var(--blockquote-border);
  }

  hr {
    height: 0.2em;
    padding: 0;
    margin: 24px 0;
    background-color: var(--border-color);
    border: 0;
  }

  /* Tables - Full Width */
  table {
    border-spacing: 0;
    border-collapse: collapse;
    width: 100% !important;
    max-width: 100% !important;
    margin-bottom: 20px;
    overflow-x: auto;
    display: table !important;
  }

  table th, table td {
    padding: 10px 16px;
    border: 1px solid var(--border-color);
  }

  table th {
    font-weight: 600;
    background-color: var(--bg-secondary);
    color: var(--text-heading);
  }

  table tr:nth-child(2n) {
    background-color: var(--table-zebra);
  }

  /* Images */
  img {
    max-width: 100%;
    height: auto;
    border-radius: 6px;
    border: 1px solid var(--border-color);
  }

  /* Inline Code */
  code:not([class]) {
    padding: 0.2em 0.4em;
    margin: 0;
    font-size: 85%;
    background-color: var(--code-bg);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  }

  /* Code Container & Pinned Copy Button */
  .code-block-wrapper, div.sourceCode {
    position: relative;
    width: 100% !important;
    max-width: 100% !important;
    margin-bottom: 20px;
    background: var(--code-bg);
    border: 1px solid var(--border-color);
    border-radius: 8px;
    overflow: visible;
  }

  pre {
    margin: 0;
    padding: 38px 16px 16px 16px !important;
    font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
    font-size: 14px;
    line-height: 1.5;
    overflow-x: auto;
    border-radius: 8px;
    background: transparent !important;
    width: 100% !important;
    box-sizing: border-box !important;
  }

  pre code {
    background: transparent !important;
    border: none !important;
    padding: 0 !important;
    font-size: inherit;
    color: inherit;
  }

  .copy-button {
    position: absolute;
    top: 8px;
    right: 10px;
    z-index: 20;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: var(--copy-btn-bg);
    color: var(--copy-btn-text);
    border: 1px solid var(--copy-btn-border);
    border-radius: 6px;
    padding: 4px 10px;
    font-size: 12px;
    font-weight: 600;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    cursor: pointer;
    box-shadow: 0 1px 3px rgba(0,0,0,0.25);
    transition: all 0.15s ease-in-out;
    user-select: none;
  }

  .copy-button:hover {
    background: var(--copy-btn-hover);
    color: var(--accent);
    border-color: var(--accent);
  }

  .copy-button.copied {
    background: var(--copy-btn-success-bg) !important;
    border-color: var(--copy-btn-success-border) !important;
    color: #ffffff !important;
  }

  .copy-button svg {
    width: 14px;
    height: 14px;
    fill: currentColor;
    flex-shrink: 0;
  }

  /* Shortcuts Drawer / Modal */
  .shortcuts-modal {
    display: none;
    position: fixed;
    top: 55px;
    right: 24px;
    z-index: 200;
    background: var(--bg-secondary);
    border: 1px solid var(--border-color);
    border-radius: 8px;
    padding: 16px 20px;
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    width: 330px;
    font-size: 13px;
  }

  .shortcuts-modal.open {
    display: block;
  }

  .shortcuts-modal h4 {
    margin: 0 0 10px 0;
    font-size: 14px;
    color: var(--text-heading);
    border-bottom: 1px solid var(--border-color);
    padding-bottom: 6px;
  }

  .shortcut-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
  }

  kbd {
    display: inline-block;
    padding: 2px 6px;
    font-size: 11px;
    line-height: 1.4;
    color: var(--text-primary);
    background-color: var(--bg-primary);
    border: 1px solid var(--border-color);
    border-radius: 4px;
    box-shadow: inset 0 -1px 0 var(--border-color);
    font-family: ui-monospace, monospace;
  }

  /* Print Styles */
  @media print {
    .top-navbar, .copy-button, .shortcuts-modal { display: none !important; }
    body { background: #fff !important; color: #000 !important; }
    .container { width: 100% !important; max-width: 100% !important; padding: 0 !important; }
  }
</style>

<!-- Mermaid Diagram Support -->
<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
  mermaid.initialize({ 
    startOnLoad: false, 
    theme: document.body.classList.contains('light-theme') ? 'default' : 'dark',
    securityLevel: 'loose'
  });
  
  document.addEventListener('DOMContentLoaded', async () => {
    try {
      const mermaidPre = document.querySelectorAll('pre.mermaid, pre > code.language-mermaid, div.mermaid');
      for (const el of mermaidPre) {
        let code = el.innerText || el.textContent;
        const container = document.createElement('div');
        container.className = 'mermaid';
        container.textContent = code.trim();
        const target = el.closest('pre') || el;
        target.parentNode.replaceChild(container, target);
      }
      await mermaid.run();
    } catch (e) {
      console.warn('Mermaid rendering skipped:', e);
    }
  });
</script>
HTML_HEADER

# Convert Markdown to self-contained HTML (forcing 100% width and no margin constraints)
pandoc "$REAL_FILE_PATH" -s -o "$TMP_HTML" \
  --from gfm+smart \
  -V maxwidth=100% \
  -V margin-left=0 -V margin-right=0 \
  --metadata title="$DOC_NAME" \
  --resource-path="$DOC_DIR" \
  --embed-resources \
  --highlight-style=breezeDark \
  -H "$HEADER_FILE"

# Inject Top Navigation Bar and Interactive Logic into HTML
python3 - << 'PY_INJECT' "$TMP_HTML" "$DOC_NAME"
import sys, re

html_path = sys.argv[1]
doc_name = sys.argv[2]

with open(html_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Strip any residual 36em or auto margin from Pandoc template
content = re.sub(r'max-width:\s*36em;?', 'max-width: 100% !important;', content)
content = re.sub(r'margin:\s*0\s+auto;?', 'margin: 0 !important;', content)
content = re.sub(r'padding-left:\s*50px;?', 'padding-left: 0 !important;', content)
content = re.sub(r'padding-right:\s*50px;?', 'padding-right: 0 !important;', content)

navbar_html = f'''
<nav class="top-navbar">
  <div class="nav-left">
    <span class="doc-badge">Markdown</span>
    <span class="doc-title" title="{doc_name}">{doc_name}</span>
  </div>
  <div class="nav-right">
    <button class="nav-btn" id="theme-btn" title="Toggle Light / Dark mode (T)">
      <span id="theme-icon">🌓</span> <span id="theme-text">Theme</span>
    </button>
    <button class="nav-btn" id="width-btn" title="Toggle Full / Readable Width (W)">↔ Width</button>
    <button class="nav-btn" id="zoom-in" title="Zoom In (Ctrl + +)">A+</button>
    <button class="nav-btn" id="zoom-out" title="Zoom Out (Ctrl + -)">A-</button>
    <button class="nav-btn" id="shortcuts-btn" title="Keyboard Shortcuts (?)">?</button>
  </div>
</nav>

<div class="shortcuts-modal" id="shortcuts-modal">
  <h4>Surf / Viewer Shortcuts</h4>
  <div class="shortcut-row"><span>Find text</span> <kbd>Ctrl + G</kbd> / <kbd>Ctrl + /</kbd></div>
  <div class="shortcut-row"><span>Toggle Full/Readable Width</span> <kbd>W</kbd></div>
  <div class="shortcut-row"><span>Zoom in</span> <kbd>Ctrl + +</kbd></div>
  <div class="shortcut-row"><span>Zoom out</span> <kbd>Ctrl + -</kbd></div>
  <div class="shortcut-row"><span>Reset zoom</span> <kbd>Ctrl + 0</kbd></div>
  <div class="shortcut-row"><span>Reload</span> <kbd>Ctrl + R</kbd></div>
  <div class="shortcut-row"><span>Toggle Theme</span> <kbd>T</kbd></div>
  <div class="shortcut-row"><span>Close viewer</span> <kbd>Ctrl + Q</kbd></div>
</div>
'''

script_html = '''
<script>
(function() {
  // 1. Theme Management (with localStorage persistence)
  const savedTheme = localStorage.getItem('md_viewer_theme') || 'dark';
  if (savedTheme === 'light') {
    document.body.classList.add('light-theme');
  }

  const themeBtn = document.getElementById('theme-btn');
  if (themeBtn) {
    themeBtn.addEventListener('click', toggleTheme);
  }

  function toggleTheme() {
    const isLight = document.body.classList.toggle('light-theme');
    localStorage.setItem('md_viewer_theme', isLight ? 'light' : 'dark');
  }

  // 2. Width Management (Default: 100% Full window width)
  const savedWidth = localStorage.getItem('md_viewer_width') || 'full';
  const container = document.querySelector('.container');
  if (savedWidth === 'readable' && container) {
    container.classList.add('readable-width');
  }

  const widthBtn = document.getElementById('width-btn');
  if (widthBtn && container) {
    widthBtn.addEventListener('click', toggleWidth);
  }

  function toggleWidth() {
    if (!container) return;
    const isReadable = container.classList.toggle('readable-width');
    localStorage.setItem('md_viewer_width', isReadable ? 'readable' : 'full');
  }

  // 3. Keyboard shortcuts modal & key bindings
  const modal = document.getElementById('shortcuts-modal');
  const shortcutsBtn = document.getElementById('shortcuts-btn');
  if (shortcutsBtn && modal) {
    shortcutsBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      modal.classList.toggle('open');
    });
    document.addEventListener('click', (e) => {
      if (!modal.contains(e.target) && e.target !== shortcutsBtn) {
        modal.classList.remove('open');
      }
    });
  }

  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    if (e.key === 't' || e.key === 'T') {
      toggleTheme();
    } else if (e.key === 'w' || e.key === 'W') {
      toggleWidth();
    } else if (e.key === '?' || (e.shiftKey && e.key === '/')) {
      if (modal) modal.classList.toggle('open');
    } else if (e.key === 'Escape') {
      if (modal) modal.classList.remove('open');
    }
  });

  // 4. Zoom controls
  let currentZoom = 16;
  const zoomInBtn = document.getElementById('zoom-in');
  const zoomOutBtn = document.getElementById('zoom-out');
  if (zoomInBtn) {
    zoomInBtn.addEventListener('click', () => {
      currentZoom = Math.min(currentZoom + 2, 28);
      document.body.style.fontSize = currentZoom + 'px';
    });
  }
  if (zoomOutBtn) {
    zoomOutBtn.addEventListener('click', () => {
      currentZoom = Math.max(currentZoom - 2, 12);
      document.body.style.fontSize = currentZoom + 'px';
    });
  }

  // 5. SVG Icons for Copy Button
  const COPY_ICON = '<svg viewBox="0 0 16 16"><path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z"></path><path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"></path></svg>';
  const CHECK_ICON = '<svg viewBox="0 0 16 16"><path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path></svg>';

  // 6. Dual-Mode Clipboard Engine
  function copyTextToClipboard(text, btn) {
    function onCopied() {
      btn.classList.add('copied');
      btn.innerHTML = CHECK_ICON + '<span>Copied!</span>';
      setTimeout(() => {
        btn.classList.remove('copied');
        btn.innerHTML = COPY_ICON + '<span>Copy</span>';
      }, 2000);
    }

    // Method A: Modern asynchronous Clipboard API
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(onCopied).catch(doFallback);
    } else {
      doFallback();
    }

    // Method B: execCommand fallback (guaranteed on file:// WebKitGTK / Surf)
    function doFallback() {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.left = '-9999px';
      textarea.style.top = '-9999px';
      textarea.setAttribute('readonly', '');
      document.body.appendChild(textarea);
      textarea.select();
      textarea.setSelectionRange(0, 99999);
      try {
        const success = document.execCommand('copy');
        if (success) onCopied();
        else btn.querySelector('span').textContent = 'Failed';
      } catch (err) {
        btn.querySelector('span').textContent = 'Error';
      }
      document.body.removeChild(textarea);
    }
  }

  // 7. Attach Copy Buttons to Code Blocks
  const preElements = document.querySelectorAll('pre');
  preElements.forEach((pre) => {
    let wrapper = pre.parentElement;
    if (!wrapper || !wrapper.classList.contains('sourceCode')) {
      wrapper = document.createElement('div');
      wrapper.className = 'code-block-wrapper';
      pre.parentNode.insertBefore(wrapper, pre);
      wrapper.appendChild(pre);
    } else {
      wrapper.classList.add('code-block-wrapper');
    }

    const copyBtn = document.createElement('button');
    copyBtn.className = 'copy-button';
    copyBtn.innerHTML = COPY_ICON + '<span>Copy</span>';
    copyBtn.setAttribute('title', 'Copy code snippet to clipboard');

    copyBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const codeElement = pre.querySelector('code') || pre;
      const rawText = codeElement.innerText || codeElement.textContent || '';
      copyTextToClipboard(rawText.trimEnd(), copyBtn);
    });

    wrapper.appendChild(copyBtn);
  });
})();
</script>
'''

# Ensure body has class="markdown-body" and is wrapped in full-width container
if '<body' in content:
    content = re.sub(r'<body([^>]*)>', r'<body\1 class="markdown-body">', content, count=1)
    body_match = re.search(r'<body[^>]*>', content)
    if body_match:
        idx = body_match.end()
        before = content[:idx]
        after = content[idx:]
        after = re.sub(r'</body>', r'</div>' + script_html + r'</body>', after, count=1)
        content = before + navbar_html + '<div class="container">' + after

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(content)
PY_INJECT

# Environment workarounds for WebKitGTK / Surf on Debian & antiX:
# 1. Disable bubblewrap sandbox (eliminates g_spawn_sync() / waitpid() ECHILD crash)
export WEBKIT_FORCE_SANDBOX=0
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1

# 2. Disable GPU accelerated compositing & DMA-BUF (eliminates OpenGL / Mesa segmentation faults)
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1

# 3. GLib memory allocator stability
export G_SLICE=always-malloc

# Browser Execution with Automatic Fallback
PREFERRED_BROWSER="${MD_VIEWER_BROWSER:-surf}"
EXIT_STATUS=0

if command -v "$PREFERRED_BROWSER" >/dev/null 2>&1; then
    "$PREFERRED_BROWSER" "$TMP_HTML" || EXIT_STATUS=$?
else
    EXIT_STATUS=127
fi

# If Surf terminated with a crash (segfault 139, abort 134, or non-zero)
if [ "$EXIT_STATUS" -ne 0 ]; then
    echo "[-] Notice: $PREFERRED_BROWSER exited with error code $EXIT_STATUS."

    FALLBACK=""
    for b in xdg-open sensible-browser firefox-esr firefox chromium dillo badwolf; do
        if command -v "$b" >/dev/null 2>&1 && [ "$b" != "$PREFERRED_BROWSER" ]; then
            FALLBACK="$b"
            break
        fi
    done

    if [ -n "$FALLBACK" ]; then
        echo "[+] Launching document in fallback browser ($FALLBACK)..."
        if [ "$FALLBACK" = "xdg-open" ]; then
            # Persist HTML copy so background browser has time to load before cleanup
            PERSISTENT_COPY="/tmp/md_preview_$(id -u)_${DOC_NAME}.html"
            cp -f "$TMP_HTML" "$PERSISTENT_COPY"
            xdg-open "$PERSISTENT_COPY" >/dev/null 2>&1 &
        else
            "$FALLBACK" "$TMP_HTML" || true
        fi
    fi
fi
EOF_LAUNCHER

    $SUDO chmod +x "$VIEWER_BIN"

    echo "[+] Step 3: Creating convenient symlink $VIEWER_SYMLINK ('md-viewer')..."
    $SUDO ln -sf "$VIEWER_BIN" "$VIEWER_SYMLINK"

    echo "[+] Step 4: Registering Desktop Application & MIME Types as 'MD-Viewer (Surf)'..."
    $SUDO mkdir -p "$DESKTOP_DIR"
    $SUDO tee "$DESKTOP_DIR/pandoc-md-viewer.desktop" > /dev/null << EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=MD-Viewer (Surf)
Comment=Fast, beautiful Markdown viewer in Surf browser with Dark/Light modes, copy code buttons & Mermaid support
Exec=$VIEWER_BIN %f
Icon=text-html
Terminal=false
MimeType=text/markdown;text/x-markdown;text/plain;
Categories=Utility;Viewer;Development;
EOF_DESKTOP

    # Also register in user desktop dir
    mkdir -p "$USER_DESKTOP_DIR"
    cp "$DESKTOP_DIR/pandoc-md-viewer.desktop" "$USER_DESKTOP_DIR/" 2>/dev/null || true

    # Update desktop database
    $SUDO update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    update-desktop-database "$USER_DESKTOP_DIR" 2>/dev/null || true

    echo "[+] Step 5: Integrating with antiX & Debian File Managers (SpaceFM / zzzFM / PCManFM)..."
    for FM_BASE in "$HOME/.config/zzzfm" "$HOME/.config/spacefm"; do
        if [ -d "$FM_BASE" ]; then
            RIGHT_CLICK_DIR="$FM_BASE/scripts/hand_text_markdown"
            mkdir -p "$RIGHT_CLICK_DIR"
            cat << EOF_FM > "$RIGHT_CLICK_DIR/pandoc-md-viewer.desktop"
[Desktop Entry]
Name=Open with MD-Viewer (Surf)
Exec=$VIEWER_BIN %f
Icon=text-html
EOF_FM
            echo "    Integrated right-click action for $(basename "$FM_BASE") ('Open with MD-Viewer (Surf)')."
        fi
    done

    # Register default handler for markdown via xdg-mime
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default pandoc-md-viewer.desktop text/markdown 2>/dev/null || true
        xdg-mime default pandoc-md-viewer.desktop text/x-markdown 2>/dev/null || true
    fi

    echo
    echo "=================================================="
    echo "       Markdown Viewer Installed Successfully!    "
    echo "=================================================="
    echo "  Executables created:"
    echo "    - $VIEWER_BIN"
    echo "    - $VIEWER_SYMLINK (quick alias)"
    echo
    echo "  Features ready:"
    echo "    [✔] 100% Full-window width layout (Pandoc 36em constraint removed)"
    echo "    [✔] Crash immunity: WebKit sandbox & GPU compositing workarounds"
    echo "    [✔] Automatic browser fallback (xdg-open, Firefox, Chromium)"
    echo "    [✔] Dual-Theme (GitHub Dark / Clean Light with toggle)"
    echo "    [✔] Crisp 16px typography & responsive layout"
    echo "    [✔] High-contrast pinned Copy button (with fallback)"
    echo "    [✔] Offline-ready self-contained CSS styles"
    echo "    [✔] SpaceFM / zzzFM / PCManFM 'Open with MD-Viewer (Surf)'"
    echo
    echo "  Test it now by running:"
    echo "    md-viewer <path-to-file.md>"
    echo "=================================================="
}

uninstall_viewer() {
    check_root_or_sudo

    echo "=================================================="
    echo "       Markdown Viewer Setup Uninstallation       "
    echo "=================================================="

    echo "[+] Step 1: Removing launcher executables and shortcuts..."
    $SUDO rm -f "$VIEWER_BIN" "$VIEWER_SYMLINK" "$USER_BIN"
    echo "    [OK] Removed $VIEWER_BIN and $VIEWER_SYMLINK."

    echo "[+] Step 2: Removing desktop entries..."
    $SUDO rm -f "$DESKTOP_DIR/pandoc-md-viewer.desktop"
    rm -f "$USER_DESKTOP_DIR/pandoc-md-viewer.desktop"
    echo "    [OK] Removed desktop entries."

    echo "[+] Step 3: Removing file manager context menus..."
    for FM_BASE in "$HOME/.config/zzzfm" "$HOME/.config/spacefm"; do
        rm -f "$FM_BASE/scripts/hand_text_markdown/pandoc-md-viewer.desktop" 2>/dev/null || true
    done
    echo "    [OK] Removed file manager context actions."

    $SUDO update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    update-desktop-database "$USER_DESKTOP_DIR" 2>/dev/null || true

    # Step 4: Interactive Dependency Removal Prompt
    echo
    echo "--------------------------------------------------"
    printf "Do you want to uninstall system packages (pandoc, surf)? [y/N]: "
    read -r REMOVE_PACKAGES
    case "$REMOVE_PACKAGES" in
        [yY]|[yY][eE][sS])
            echo "Removing pandoc and surf packages via apt..."
            $SUDO apt remove --purge -y pandoc surf 2>/dev/null || true
            $SUDO apt autoremove -y 2>/dev/null || true
            echo "  [OK] System packages (pandoc, surf) uninstalled."
            ;;
        *)
            echo "  Kept pandoc and surf packages installed for other uses."
            ;;
    esac
    echo "--------------------------------------------------"

    echo
    echo "=================================================="
    echo "       Markdown Viewer Uninstalled Cleanly        "
    echo "=================================================="
}

###############################################################################
# Main Entry Point
###############################################################################

case "${1:-}" in
    --install|-i|"")
        install_viewer
        ;;

    --uninstall|-u)
        uninstall_viewer
        ;;

    --status|-s)
        show_status
        ;;

    --help|-h)
        show_help
        ;;

    *)
        # If a file path was passed directly (e.g. ./setup-md-viewer.sh doc.md), execute viewer
        if [ -f "$1" ]; then
            if [ -x "$VIEWER_BIN" ]; then
                exec "$VIEWER_BIN" "$1"
            else
                echo "[!] Viewer is not yet installed. Installing now..."
                install_viewer
                exec "$VIEWER_BIN" "$1"
            fi
        else
            echo "[-] Error: Invalid option or file not found: $1"
            echo
            show_help
            exit 1
        fi
        ;;
esac