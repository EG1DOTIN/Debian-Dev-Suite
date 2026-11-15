#!/bin/sh

###############################################################################
# Universal Geany IDE & Developer Setup for Debian-based Systems
# (Debian, antiX, Ubuntu, Linux Mint, MX Linux, Devuan, etc.)
#
# Smart management script for Geany IDE and curated developer plugins:
#   - 100% Free & Open-Source (FOSS)
#   - Zero telemetry, privacy-focused, local-first
#   - Ultra-lightweight (consumes ~15-30MB RAM vs VSCode ~800MB)
#   - Curated developer plugins for Markdown, Project Organizer, Python, C/C++, Web
#   - Open-source color schemes (Dracula, Monokai, Solarized, Gruvbox, Nord)
#   - Lightweight AI Copilot (local-first via llama.cpp / Ollama / OpenAI API)
#
# USAGE:
#   ./setup-geany.sh --install       # Install Geany, developer plugins, themes & Copilot
#   ./setup-geany.sh --uninstall     # Clean uninstallation with dependency prompt
#   ./setup-geany.sh --update        # Update Geany packages, themes & Copilot scripts
#   ./setup-geany.sh --status        # Show installed version, active plugins & Copilot status
#   ./setup-geany.sh --help          # Show usage options and examples
###############################################################################

set -u

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
[ -z "$TARGET_HOME" ] && TARGET_HOME="$HOME"
GEANY_CONFIG_DIR="$TARGET_HOME/.config/geany"
PLUGINS_DIR="$GEANY_CONFIG_DIR/plugins"
COLORSCHEMES_DIR="$GEANY_CONFIG_DIR/colorschemes"
GEANYLUA_DIR="$PLUGINS_DIR/geanylua"
COPILOT_CONF="$GEANY_CONFIG_DIR/geany-copilot.conf"

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:$PATH
export PATH

###############################################################################
# Help / Usage
###############################################################################

show_help()
{
    echo "Universal Geany IDE & Developer Setup for Debian-based Systems"
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  --install, -i      Install Geany, developer plugins, themes, and AI Copilot"
    echo "  --uninstall, -u    Remove custom configs, themes, and optionally uninstall packages"
    echo "  --update           Update Geany packages, themes, and AI Copilot scripts"
    echo "  --status, -s       Show Geany version, installed plugins, and Copilot configuration"
    echo "  --help, -h         Display this help message"
    echo
    echo "Examples:"
    echo "  $0 --install       # Install full developer setup"
    echo "  $0 --status        # View status of Geany and plugins"
    echo "  $0 --uninstall     # Clean uninstallation"
    echo
}

###############################################################################
# Pre-checks: System Clock & Root
###############################################################################

check_system_clock()
{
    CURRENT_YEAR=$(date +%Y 2>/dev/null || echo 0)
    if [ "$CURRENT_YEAR" -lt 2024 ]; then
        echo "WARNING: Your system clock is set to year $CURRENT_YEAR!"
        echo "APT package downloads and HTTPS requests will FAIL with SSL certificate"
        echo "errors until your clock is corrected."
        echo
        echo "Please synchronize your time first by running:"
        echo "    sudo ../Setup-Sync-Time/sync-time.sh"
        echo
        printf "Do you want to continue anyway? [y/N]: "
        read -r CONTINUE_CHOICE
        case "$CONTINUE_CHOICE" in
            [yY]|[yY][eE][sS])
                echo "Continuing..."
                ;;
            *)
                echo "Exiting. Please synchronize your system time first."
                exit 1
                ;;
        esac
    fi
}

###############################################################################
# Curated Developer Package List
###############################################################################

# Curated developer plugins:
# - geany                     : Core fast GTK3 IDE
# - geany-plugins-common      : Shared plugin data
# - geany-plugin-markdown     : Markdown preview and viewer
# - geany-plugin-projectorganizer : Open folder as project / tree sidebar
# - geany-plugin-treebrowser  : Alternative filesystem tree view
# - geany-plugin-autoclose    : Auto-close brackets/quotes (Python, C, Web)
# - geany-plugin-git-changebar: Git diff in gutter
# - geany-plugin-codenav      : Fast code navigation to definitions
# - geany-plugin-lineoperations: Sort, unique, trim whitespace
# - geany-plugin-lipsum       : Lorem ipsum placeholder generator
# - geany-plugin-spellcheck   : Spellchecking
# - geany-plugin-lsp          : Language Server Protocol client (Python, C, JS)
# - geany-plugin-lua          : GeanyLua scripting (powers lightweight Copilot)
# - curl                      : HTTP client for AI Copilot queries
DEVELOPER_PACKAGES="geany geany-plugins-common geany-plugin-markdown geany-plugin-projectorganizer geany-plugin-treebrowser geany-plugin-autoclose geany-plugin-git-changebar geany-plugin-codenav geany-plugin-lineoperations geany-plugin-lipsum geany-plugin-spellcheck geany-plugin-lsp geany-plugin-lua curl"

###############################################################################
# Installation: Geany Packages
###############################################################################

install_packages()
{
    echo "--------------------------------------------------"
    echo "1. Checking and Installing Geany & Plugins"
    echo "--------------------------------------------------"

    MISSING_PKGS=""
    for PKG in $DEVELOPER_PACKAGES; do
        if ! dpkg -s "$PKG" >/dev/null 2>&1; then
            MISSING_PKGS="$MISSING_PKGS $PKG"
        fi
    done

    if [ -n "$MISSING_PKGS" ]; then
        echo "The following packages need to be installed:"
        echo " $MISSING_PKGS"
        echo
        echo "Updating package lists..."
        if ! sudo apt update; then
            echo "WARNING: 'sudo apt update' reported non-zero status."
        fi

        echo "Installing developer packages..."
        # Try installing specific curated list
        if sudo apt install -y $MISSING_PKGS; then
            echo "  [OK] Developer packages installed successfully."
        else
            echo "Notice: Some individual plugin packages were unavailable. Trying metapackage 'geany-plugins'..."
            sudo apt install -y geany geany-plugins curl || {
                echo "ERROR: Failed to install Geany packages."
                exit 1
            }
            echo "  [OK] Geany and geany-plugins installed."
        fi
    else
        echo "  [OK] Geany and all developer plugins are already installed."
    fi
}

###############################################################################
# Installation: Popular Open-Source Color Themes
###############################################################################

install_themes()
{
    echo
    echo "--------------------------------------------------"
    echo "2. Installing Open-Source Color Schemes"
    echo "--------------------------------------------------"

    mkdir -p "$COLORSCHEMES_DIR"

    # 1. Dracula Theme
    if [ ! -f "$COLORSCHEMES_DIR/dracula.conf" ]; then
        cat > "$COLORSCHEMES_DIR/dracula.conf" <<'EOF'
# Dracula Theme for Geany
# Based on the official Dracula Color Palette (MIT License)
[theme_info]
name=Dracula
description=A dark theme for Geany using the Dracula palette
version=1.0
author=Dracula Theme
compat=1.22;

[named_styles]
default=#f8f8f2;#282a36;false;false
whitespace=#6272a4;#282a36;false;false
comment=#6272a4;;false;true
comment_line=#6272a4;;false;true
comment_doc=#6272a4;;false;true
number=#bd93f9;;false;false
word=#ff79c6;;true;false
word2=#8be9fd;;false;false
string=#f1fa8c;;false;false
character=#f1fa8c;;false;false
operator=#ff79c6;;false;false
identifier=#f8f8f2;;false;false
preprocessor=#ff79c6;;false;false
current_line=;#44475a;true;false
selection=;#44475a;false;true
error=#ff5555;;true;false
EOF
        echo "  [OK] Installed Dracula theme."
    fi

    # 2. Monokai Theme
    if [ ! -f "$COLORSCHEMES_DIR/monokai.conf" ]; then
        cat > "$COLORSCHEMES_DIR/monokai.conf" <<'EOF'
# Monokai Theme for Geany
[theme_info]
name=Monokai
description=Monokai color scheme
version=1.0
author=Wimer Hazenberg
compat=1.22;

[named_styles]
default=#f8f8f2;#272822;false;false
whitespace=#75715e;#272822;false;false
comment=#75715e;;false;true
comment_line=#75715e;;false;true
comment_doc=#75715e;;false;true
number=#ae81ff;;false;false
word=#f92672;;true;false
word2=#66d9ef;;false;false
string=#e6db74;;false;false
character=#e6db74;;false;false
operator=#f92672;;false;false
identifier=#f8f8f2;;false;false
preprocessor=#a6e22e;;false;false
current_line=;#3e3d32;true;false
selection=;#49483e;false;true
error=#f92672;#1e0010;true;false
EOF
        echo "  [OK] Installed Monokai theme."
    fi

    # 3. Solarized Dark Theme
    if [ ! -f "$COLORSCHEMES_DIR/solarized-dark.conf" ]; then
        cat > "$COLORSCHEMES_DIR/solarized-dark.conf" <<'EOF'
# Solarized Dark Theme for Geany
[theme_info]
name=Solarized Dark
description=Precision color scheme for machines and people
version=1.0
author=Ethan Schoonover
compat=1.22;

[named_styles]
default=#839496;#002b36;false;false
whitespace=#586e75;#002b36;false;false
comment=#586e75;;false;true
comment_line=#586e75;;false;true
comment_doc=#586e75;;false;true
number=#2aa198;;false;false
word=#859900;;true;false
word2=#268bd2;;false;false
string=#2aa198;;false;false
character=#2aa198;;false;false
operator=#859900;;false;false
identifier=#839496;;false;false
preprocessor=#cb4b16;;false;false
current_line=;#073642;true;false
selection=;#073642;false;true
error=#dc322f;;true;false
EOF
        echo "  [OK] Installed Solarized Dark theme."
    fi

    # 4. Gruvbox Theme
    if [ ! -f "$COLORSCHEMES_DIR/gruvbox.conf" ]; then
        cat > "$COLORSCHEMES_DIR/gruvbox.conf" <<'EOF'
# Gruvbox Dark Theme for Geany
[theme_info]
name=Gruvbox Dark
description=Retro groove color scheme for Geany
version=1.0
author=morhetz
compat=1.22;

[named_styles]
default=#ebdbb2;#282828;false;false
whitespace=#928374;#282828;false;false
comment=#928374;;false;true
comment_line=#928374;;false;true
comment_doc=#928374;;false;true
number=#d3869b;;false;false
word=#fb4934;;true;false
word2=#83a598;;false;false
string=#b8bb26;;false;false
character=#b8bb26;;false;false
operator=#fe8019;;false;false
identifier=#ebdbb2;;false;false
preprocessor=#8ec07c;;false;false
current_line=;#3c3836;true;false
selection=;#504945;false;true
error=#fb4934;;true;false
EOF
        echo "  [OK] Installed Gruvbox theme."
    fi

    # 5. Nord Theme
    if [ ! -f "$COLORSCHEMES_DIR/nord.conf" ]; then
        cat > "$COLORSCHEMES_DIR/nord.conf" <<'EOF'
# Nord Theme for Geany
[theme_info]
name=Nord
description=An arctic, north-bluish clean color theme
version=1.0
author=Arctic Ice Studio
compat=1.22;

[named_styles]
default=#d8dee9;#2e3440;false;false
whitespace=#4c566a;#2e3440;false;false
comment=#616e88;;false;true
comment_line=#616e88;;false;true
comment_doc=#616e88;;false;true
number=#b48ead;;false;false
word=#81a1c1;;true;false
word2=#88c0d0;;false;false
string=#a3be8c;;false;false
character=#a3be8c;;false;false
operator=#81a1c1;;false;false
identifier=#d8dee9;;false;false
preprocessor=#5e81ac;;false;false
current_line=;#3b4252;true;false
selection=;#434c5e;false;true
error=#bf616a;;true;false
EOF
        echo "  [OK] Installed Nord theme."
    fi

    echo "  [OK] Open-source color schemes ready in $COLORSCHEMES_DIR."
}

###############################################################################
# Installation: Lightweight AI Copilot (GeanyLua + cURL)
###############################################################################

install_copilot()
{
    echo
    echo "--------------------------------------------------"
    echo "3. Setting Up Lightweight Geany AI Copilot"
    echo "--------------------------------------------------"
    echo "Uses native GeanyLua + curl (100% open-source, local-first, zero telemetry)."

    mkdir -p "$GEANYLUA_DIR"

    # Default Copilot Configuration
    if [ ! -f "$COPILOT_CONF" ]; then
        cat > "$COPILOT_CONF" <<'EOF'
# Geany Copilot Configuration
# Local-first, privacy-focused, zero telemetry

# AI Backend API URL (OpenAI-compatible)
# Default: Local llama.cpp server (http://localhost:8080/v1)
# Alternative for Ollama: http://localhost:11434/v1
# Alternative for Cloud: https://api.deepseek.com/v1 (or groq/openrouter)
API_URL=http://localhost:8080/v1/chat/completions

# Model name (matches your loaded model or Ollama model)
MODEL=default

# API Key (leave empty for local localhost models; required for cloud endpoints)
API_KEY=

# Request timeout in seconds
TIMEOUT=30

# Temperature (0.0 to 1.0; low value = more deterministic code)
TEMPERATURE=0.2
EOF
        echo "  [OK] Created default configuration ($COPILOT_CONF)."
    else
        echo "  [OK] Configuration exists ($COPILOT_CONF)."
    fi

    # 1. Copilot Code Generation / Completion Script
    cat > "$GEANYLUA_DIR/copilot.lua" <<'EOF'
-- Geany AI Copilot - Code Generation & Completion
-- 100% Free, Open-Source, Lightweight, Local-First
-- Sends selection or current line to local/remote LLM and inserts response.

local function read_config()
    local conf_path = os.getenv("HOME") .. "/.config/geany/geany-copilot.conf"
    local cfg = {
        api_url = "http://localhost:8080/v1/chat/completions",
        model = "default",
        api_key = "",
        timeout = "30",
        temperature = "0.2"
    }

    local f = io.open(conf_path, "r")
    if f then
        for line in f:lines() do
            local key, val = line:match("^([%w_]+)=(.*)$")
            if key and val then
                val = val:gsub("^%s*(.-)%s*$", "%1") -- trim
                if key == "API_URL" and val ~= "" then cfg.api_url = val end
                if key == "MODEL" and val ~= "" then cfg.model = val end
                if key == "API_KEY" then cfg.api_key = val end
                if key == "TIMEOUT" and val ~= "" then cfg.timeout = val end
                if key == "TEMPERATURE" and val ~= "" then cfg.temperature = val end
            end
        end
        f:close()
    end
    return cfg
end

local function escape_json(str)
    str = str:gsub('\\', '\\\\')
    str = str:gsub('"', '\\"')
    str = str:gsub('\n', '\\n')
    str = str:gsub('\r', '\\r')
    str = str:gsub('\t', '\\t')
    return str
end

local cfg = read_config()

-- Get selected code or prompt
local prompt = geany.selection()
local is_selection = true

if not prompt or prompt == "" then
    -- Fall back to current line
    local cur_line = geany.lines(geany.line())
    if cur_line and cur_line:match("%S") then
        prompt = cur_line
        is_selection = false
    end
end

if not prompt or prompt == "" then
    geany.message("AI Copilot: Please select some code/prompt or place caret on a line.")
    return
end

geany.status("AI Copilot: Querying " .. cfg.api_url .. " ...")

-- Build JSON payload
local auth_header = ""
if cfg.api_key and cfg.api_key ~= "" then
    auth_header = "-H \"Authorization: Bearer " .. cfg.api_key .. "\" "
end

local json_payload = string.format(
    '{"model":"%s","messages":[{"role":"system","content":"You are a helpful programming copilot. Provide clean, correct code. Respond ONLY with code or concise code explanations, no unnecessary filler."},{"role":"user","content":"%s"}],"temperature":%s}',
    cfg.model, escape_json(prompt), cfg.temperature
)

local tmp_in = os.tmpname()
local f_in = io.open(tmp_in, "w")
f_in:write(json_payload)
f_in:close()

local curl_cmd = string.format(
    'curl -s -m %s %s -H "Content-Type: application/json" -d @%s "%s"',
    cfg.timeout, auth_header, tmp_in, cfg.api_url
)

local handle = io.popen(curl_cmd)
local response = handle:read("*a")
handle:close()
os.remove(tmp_in)

if not response or response == "" then
    geany.status("AI Copilot: No response received (is local model server running?).")
    geany.message("AI Copilot Error: Failed to connect to " .. cfg.api_url)
    return
end

-- Extract content from response
-- Handles standard OpenAI-compatible JSON structure: "content":"..."
local content = response:match('"content"%s*:%s*"(.-)"[%s,}][^%]]*')

if content then
    -- Unescape JSON string
    content = content:gsub('\\n', '\n')
    content = content:gsub('\\r', '\r')
    content = content:gsub('\\t', '\t')
    content = content:gsub('\\"', '"')
    content = content:gsub('\\\\', '\\')

    if is_selection then
        -- Append after selection
        geany.selection(prompt .. "\n\n" .. content)
    else
        geany.selection("\n" .. content)
    end
    geany.status("AI Copilot: Completed successfully.")
else
    -- Check for API error message
    local err_msg = response:match('"message"%s*:%s*"(.-)"')
    if err_msg then
        geany.status("AI Copilot Error: " .. err_msg)
        geany.message("AI Copilot API Error: " .. err_msg)
    else
        geany.status("AI Copilot: Received raw response.")
        geany.message("AI Copilot Response: " .. response)
    end
end
EOF

    # 2. Copilot Explain / Refactor Script
    cat > "$GEANYLUA_DIR/copilot-explain.lua" <<'EOF'
-- Geany AI Copilot - Code Explainer
-- Sends selected code to LLM and outputs explanation into Geany Messages tab.

local function read_config()
    local conf_path = os.getenv("HOME") .. "/.config/geany/geany-copilot.conf"
    local cfg = {
        api_url = "http://localhost:8080/v1/chat/completions",
        model = "default",
        api_key = "",
        timeout = "30"
    }

    local f = io.open(conf_path, "r")
    if f then
        for line in f:lines() do
            local key, val = line:match("^([%w_]+)=(.*)$")
            if key and val then
                val = val:gsub("^%s*(.-)%s*$", "%1")
                if key == "API_URL" and val ~= "" then cfg.api_url = val end
                if key == "MODEL" and val ~= "" then cfg.model = val end
                if key == "API_KEY" then cfg.api_key = val end
                if key == "TIMEOUT" and val ~= "" then cfg.timeout = val end
            end
        end
        f:close()
    end
    return cfg
end

local function escape_json(str)
    str = str:gsub('\\', '\\\\')
    str = str:gsub('"', '\\"')
    str = str:gsub('\n', '\\n')
    str = str:gsub('\r', '\\r')
    str = str:gsub('\t', '\\t')
    return str
end

local code = geany.selection()
if not code or code == "" then
    geany.message("AI Explainer: Please select the code you want explained.")
    return
end

local cfg = read_config()
geany.status("AI Explainer: Analyzing code...")

local auth_header = ""
if cfg.api_key and cfg.api_key ~= "" then
    auth_header = "-H \"Authorization: Bearer " .. cfg.api_key .. "\" "
end

local json_payload = string.format(
    '{"model":"%s","messages":[{"role":"system","content":"You are a code reviewer. Explain clearly and concisely what this code does, identifying any bugs or performance issues."},{"role":"user","content":"%s"}],"temperature":0.1}',
    cfg.model, escape_json(code)
)

local tmp_in = os.tmpname()
local f_in = io.open(tmp_in, "w")
f_in:write(json_payload)
f_in:close()

local curl_cmd = string.format(
    'curl -s -m %s %s -H "Content-Type: application/json" -d @%s "%s"',
    cfg.timeout, auth_header, tmp_in, cfg.api_url
)

local handle = io.popen(curl_cmd)
local response = handle:read("*a")
handle:close()
os.remove(tmp_in)

local content = response:match('"content"%s*:%s*"(.-)"[%s,}][^%]]*')
if content then
    content = content:gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\t', '\t'):gsub('\\"', '"'):gsub('\\\\', '\\')
    geany.message("=== AI Code Explanation ===\n" .. content .. "\n===========================")
    geany.status("AI Explainer: Explanation printed to Messages tab.")
else
    geany.message("AI Explainer Error: " .. (response or "No response"))
    geany.status("AI Explainer: Error occurred.")
end
EOF

    chmod +x "$GEANYLUA_DIR/copilot.lua"
    chmod +x "$GEANYLUA_DIR/copilot-explain.lua"

    echo "  [OK] AI Copilot scripts installed in $GEANYLUA_DIR."
    echo "       - copilot.lua         (Code generation / completion)"
    echo "       - copilot-explain.lua (Code explanation & review in Messages tab)"
}

###############################################################################
# Installation: Recommended Developer Preferences
###############################################################################

configure_developer_preferences()
{
    echo
    echo "--------------------------------------------------"
    echo "4. Setting Recommended Developer Preferences"
    echo "--------------------------------------------------"

    mkdir -p "$GEANY_CONFIG_DIR"

    # If geany.conf does not exist, initialize a clean default with developer settings
    if [ ! -f "$GEANY_CONFIG_DIR/geany.conf" ]; then
        cat > "$GEANY_CONFIG_DIR/geany.conf" <<'EOF'
[geany]
# Developer Defaults
pref_main_load_session=true
pref_editor_tab_width=4
pref_editor_use_spaces=true
pref_editor_strip_trailing_spaces=true
pref_editor_ensure_convert_line_endings=true
pref_editor_line_numbers=true
pref_editor_show_white_spaces=false
pref_editor_auto_close_xml_tags=true
pref_editor_complete_snippets=true
pref_editor_auto_complete_symbols=true
pref_editor_line_wrapping=true
sidebar_page=2
sidebar_visible=true
msgwin_visible=true
color_scheme=dracula.conf
EOF
        echo "  [OK] Initialized geany.conf with developer defaults (spaces, strip whitespace, Dracula theme)."
    else
        echo "  [OK] Preserved existing geany.conf (custom user preferences maintained)."
    fi
}

###############################################################################
# Status & Diagnostics
###############################################################################

show_status()
{
    echo "=================================================="
    echo "          Geany IDE Environment Status           "
    echo "=================================================="

    printf "Geany Installed      : "
    if command -v geany >/dev/null 2>&1; then
        VERSION=$(geany --version 2>/dev/null | head -n 1 || echo "Installed")
        echo "Yes ($VERSION)"
    else
        echo "No"
    fi

    echo
    echo "Installed Developer Plugins:"
    for PKG in geany-plugin-markdown geany-plugin-projectorganizer geany-plugin-treebrowser geany-plugin-autoclose geany-plugin-git-changebar geany-plugin-lsp geany-plugin-codenav geany-plugin-lua; do
        printf "  - %-30s: " "$PKG"
        if dpkg -s "$PKG" >/dev/null 2>&1; then
            echo "Installed"
        else
            echo "Not installed"
        fi
    done

    echo
    echo "Installed Color Themes in $COLORSCHEMES_DIR:"
    if [ -d "$COLORSCHEMES_DIR" ]; then
        THEMES=$(ls "$COLORSCHEMES_DIR" 2>/dev/null | tr '\n' ' ')
        echo "  ${THEMES:-(None)}"
    else
        echo "  (None)"
    fi

    echo
    echo "AI Copilot Status:"
    if [ -f "$GEANYLUA_DIR/copilot.lua" ]; then
        echo "  - Script: Installed ($GEANYLUA_DIR/copilot.lua)"
    else
        echo "  - Script: Not installed"
    fi

    if [ -f "$COPILOT_CONF" ]; then
        echo "  - Config: $COPILOT_CONF"
        API_URL=$(grep '^API_URL=' "$COPILOT_CONF" | cut -d'=' -f2-)
        MODEL=$(grep '^MODEL=' "$COPILOT_CONF" | cut -d'=' -f2-)
        echo "    Endpoint : ${API_URL:-http://localhost:8080/v1/chat/completions}"
        echo "    Model    : ${MODEL:-default}"

        # Test local endpoint connectivity
        printf "    Backend Connectivity: "
        BASE_URL=$(echo "$API_URL" | sed -e 's#/chat/completions##' -e 's#/v1##')
        if curl -s --max-time 1 "$BASE_URL" >/dev/null 2>&1 || curl -s --max-time 1 "$API_URL" >/dev/null 2>&1; then
            echo "ONLINE and reachable!"
        else
            echo "Offline (Start your local llama-server / Ollama when ready)"
        fi
    fi
    echo "=================================================="
}

###############################################################################
# Update Routine
###############################################################################

update_geany()
{
    check_system_clock

    echo "=================================================="
    echo "            Updating Geany & Plugins              "
    echo "=================================================="

    echo "Updating system package repositories..."
    sudo apt update || true

    echo "Upgrading Geany and installed plugins..."
    sudo apt install --only-upgrade -y geany geany-plugins $DEVELOPER_PACKAGES 2>/dev/null || true

    echo "Re-verifying color schemes..."
    install_themes

    echo "Re-verifying AI Copilot scripts..."
    install_copilot

    echo
    echo "=================================================="
    echo "         Update Completed Successfully!           "
    echo "=================================================="
    show_status
}

###############################################################################
# Uninstallation Routine
###############################################################################

uninstall_geany()
{
    echo "=================================================="
    echo "           Geany Setup Uninstallation             "
    echo "=================================================="

    # Check if Geany is running
    if pgrep -x "geany" >/dev/null 2>&1; then
        echo "Notice: Geany is currently running. Please save your work and close it."
        printf "Press ENTER once Geany is closed..."
        read -r _
    fi

    # 1. Remove Copilot scripts
    if [ -d "$GEANYLUA_DIR" ]; then
        rm -f "$GEANYLUA_DIR/copilot.lua" "$GEANYLUA_DIR/copilot-explain.lua"
        echo "  [OK] Removed AI Copilot Lua scripts."
    fi

    # 2. Remove Copilot config
    if [ -f "$COPILOT_CONF" ]; then
        rm -f "$COPILOT_CONF"
        echo "  [OK] Removed Copilot configuration."
    fi

    # 3. Ask about custom color schemes
    if [ -d "$COLORSCHEMES_DIR" ]; then
        printf "Do you want to remove installed custom color schemes ($COLORSCHEMES_DIR)? [y/N]: "
        read -r REMOVE_THEMES
        case "$REMOVE_THEMES" in
            [yY]|[yY][eE][sS])
                rm -rf "$COLORSCHEMES_DIR"
                echo "  [OK] Removed color schemes."
                ;;
            *)
                echo "  Kept color schemes."
                ;;
        esac
    fi

    # 4. Ask about user configurations
    if [ -d "$GEANY_CONFIG_DIR" ]; then
        printf "Do you want to delete your personal Geany configuration folder (~/.config/geany)? [y/N]: "
        read -r REMOVE_CONFIG
        case "$REMOVE_CONFIG" in
            [yY]|[yY][eE][sS])
                rm -rf "$GEANY_CONFIG_DIR"
                echo "  [OK] Deleted ~/.config/geany."
                ;;
            *)
                echo "  Kept ~/.config/geany."
                ;;
        esac
    fi

    # 5. Interactive Dependency Removal Prompt
    echo
    echo "--------------------------------------------------"
    printf "Do you want to uninstall system packages (geany, geany-plugins)? [y/N]: "
    read -r REMOVE_PACKAGES
    case "$REMOVE_PACKAGES" in
        [yY]|[yY][eE][sS])
            echo "Removing Geany and plugin packages via apt..."
            sudo apt remove --purge -y geany geany-plugins geany-plugin-* 2>/dev/null || true
            sudo apt autoremove -y 2>/dev/null || true
            echo "  [OK] System packages uninstalled."
            ;;
        *)
            echo "  Kept Geany system packages installed for other uses."
            ;;
    esac
    echo "--------------------------------------------------"

    echo
    echo "=================================================="
    echo "         Uninstallation Completed Cleanly         "
    echo "=================================================="
}

###############################################################################
# Main Entrypoint
###############################################################################

case "${1:-}" in
    --install|-i)
        check_system_clock
        install_packages
        install_themes
        install_copilot
        configure_developer_preferences
        echo
        echo "=================================================="
        echo "         Installation Finished Successfully!      "
        echo "=================================================="
        echo
        echo "Start Geany from your application menu or run:"
        echo "    geany &"
        echo
        echo "To use AI Copilot in Geany:"
        echo "    1. Open Tools -> Plugin Manager -> Enable 'GeanyLua'"
        echo "    2. Select code and choose Tools -> Lua Scripts -> copilot.lua"
        echo "       (or configure a custom shortcut in Edit -> Preferences -> Keybindings)"
        echo
        echo "To change Color Scheme:"
        echo "    View -> Change Color Scheme -> select Dracula, Monokai, etc."
        echo "=================================================="
        ;;

    --uninstall|-u)
        uninstall_geany
        ;;

    --update)
        update_geany
        ;;

    --status|-s)
        show_status
        ;;

    --help|-h)
        show_help
        ;;

    "")
        echo "No option specified."
        echo
        show_help
        exit 1
        ;;

    *)
        echo "Unknown option: $1"
        echo
        show_help
        exit 1
        ;;
esac
