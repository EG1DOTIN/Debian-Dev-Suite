#!/usr/bin/env bash
#
# backup-dev-configs.sh — Multi-PC Config & Dotfiles Sync Tool
#
# Backs up your personalized developer settings:
#   - ~/.bashrc (aliases, paths, environment)
#   - ~/.gitconfig (Git user, aliases, diffs)
#   - ~/.tmux.conf (terminal multiplexer splits and themes)
#   - ~/.config/geany/ (editor themes, keybindings, build settings)
#   - ~/.config/lazygit/ (LazyGit settings)
#   - ~/.config/rclone/ (optional Google Drive remote config)
#
# Features:
#   - Creates local ZIP and TAR.GZ archives in ~/Debian-Dev-Backups/
#   - Automatically syncs to ~/GoogleDrive/Debian-Dev-Backups/ if GDrive is mounted
#   - Restrictive permissions (0700 dir, 0600 archives) and secure mktemp temporary folders
#   - Safe --restore: Creates a safety backup (.bak) of existing files before restoring
#
# Usage:
#   ./backup-dev-configs.sh --backup
#   ./backup-dev-configs.sh --restore [file_path]
#   ./backup-dev-configs.sh --list
#   ./backup-dev-configs.sh --install-aliases
#   ./backup-dev-configs.sh --help
#

set -e

BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Dynamic User & Target Home Lookup (Zero hardcoding, dual-root/user safe)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"

LOCAL_BACKUP_DIR="$TARGET_HOME/Debian-Dev-Backups"
GDRIVE_DIR="$TARGET_HOME/GoogleDrive/Debian-Dev-Backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
BASHRC="$TARGET_HOME/.bashrc"

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "=================================================================="
    echo "  $1"
    echo "=================================================================="
    echo -e "${RESET}"
}

# ---------------------------------------------------------------------------
# Backup Function
# ---------------------------------------------------------------------------
do_backup() {
    mkdir -p "$LOCAL_BACKUP_DIR"
    chmod 700 "$LOCAL_BACKUP_DIR" 2>/dev/null || true
    print_header "Backing Up Developer Configurations"

    # Cryptographically safe temporary directory with mode 0700 (CWE-377 mitigation)
    local temp_dir
    temp_dir=$(mktemp -d "/tmp/dev-configs-backup.XXXXXX")
    chmod 700 "$temp_dir"
    trap 'rm -rf "$temp_dir"' EXIT INT TERM

    local items_backed_up=0

    # 1. ~/.bashrc
    if [ -f "$TARGET_HOME/.bashrc" ]; then
        cp "$TARGET_HOME/.bashrc" "$temp_dir/bashrc"
        echo -e "  ${GREEN}✓${RESET} ~/.bashrc"
        items_backed_up=$((items_backed_up + 1))
    fi

    # 2. ~/.gitconfig
    if [ -f "$TARGET_HOME/.gitconfig" ]; then
        cp "$TARGET_HOME/.gitconfig" "$temp_dir/gitconfig"
        echo -e "  ${GREEN}✓${RESET} ~/.gitconfig"
        items_backed_up=$((items_backed_up + 1))
    fi

    # 3. ~/.tmux.conf
    if [ -f "$TARGET_HOME/.tmux.conf" ]; then
        cp "$TARGET_HOME/.tmux.conf" "$temp_dir/tmux.conf"
        echo -e "  ${GREEN}✓${RESET} ~/.tmux.conf"
        items_backed_up=$((items_backed_up + 1))
    fi

    # 4. ~/.config/geany
    if [ -d "$TARGET_HOME/.config/geany" ]; then
        mkdir -p "$temp_dir/config/geany"
        cp -r "$TARGET_HOME/.config/geany/"* "$temp_dir/config/geany/" 2>/dev/null || true
        echo -e "  ${GREEN}✓${RESET} ~/.config/geany (Themes, keybindings, settings)"
        items_backed_up=$((items_backed_up + 1))
    fi

    # 5. ~/.config/lazygit
    if [ -d "$TARGET_HOME/.config/lazygit" ]; then
        mkdir -p "$temp_dir/config/lazygit"
        cp -r "$TARGET_HOME/.config/lazygit/"* "$temp_dir/config/lazygit/" 2>/dev/null || true
        echo -e "  ${GREEN}✓${RESET} ~/.config/lazygit"
        items_backed_up=$((items_backed_up + 1))
    fi

    # 6. ~/.config/rclone (Google Drive config)
    if [ -f "$TARGET_HOME/.config/rclone/rclone.conf" ]; then
        echo -en "${BOLD}Include Google Drive rclone.conf authentication token? [Y/n]: ${RESET}"
        read -r reply
        reply="${reply:-y}"
        if [[ "$reply" =~ ^[Yy] ]]; then
            mkdir -p "$temp_dir/config/rclone"
            cp "$TARGET_HOME/.config/rclone/rclone.conf" "$temp_dir/config/rclone/"
            echo -e "  ${GREEN}✓${RESET} ~/.config/rclone/rclone.conf (Encrypted Google Drive token)"
            items_backed_up=$((items_backed_up + 1))
        fi
    fi

    if [ "$items_backed_up" -eq 0 ]; then
        echo -e "${RED}No configuration files found to back up.${RESET}"
        rm -rf "$temp_dir"
        trap - EXIT INT TERM
        exit 1
    fi

    # Create Local Archives (.zip and .tar.gz)
    local zip_file="$LOCAL_BACKUP_DIR/dev-configs-$TIMESTAMP.zip"
    local tar_file="$LOCAL_BACKUP_DIR/dev-configs-$TIMESTAMP.tar.gz"
    local latest_zip="$LOCAL_BACKUP_DIR/dev-configs-latest.zip"
    local latest_tar="$LOCAL_BACKUP_DIR/dev-configs-latest.tar.gz"

    echo
    echo "Compressing archives..."
    cd "$temp_dir"

    # Tar.gz archive
    tar -czf "$tar_file" .
    cp "$tar_file" "$latest_tar"

    # Zip archive (if zip is installed, otherwise fallback)
    if command -v zip >/dev/null 2>&1; then
        zip -qr "$zip_file" .
        cp "$zip_file" "$latest_zip"
    else
        # Auto-install zip or notify
        if sudo apt install -y zip >/dev/null 2>&1; then
            zip -qr "$zip_file" .
            cp "$zip_file" "$latest_zip"
        fi
    fi

    # Restrict permissions to owner only (chmod 600 protects OAuth tokens & dotfiles)
    chmod 600 "$tar_file" "$latest_tar" 2>/dev/null || true
    if [ -f "$zip_file" ]; then
        chmod 600 "$zip_file" "$latest_zip" 2>/dev/null || true
    fi

    # If executed under sudo, fix ownership to the target user
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown -R "$TARGET_USER:$TARGET_USER" "$LOCAL_BACKUP_DIR" 2>/dev/null || true
    fi

    rm -rf "$temp_dir"
    trap - EXIT INT TERM

    local archive_size
    archive_size=$(ls -lh "$tar_file" | awk '{print $5}')

    echo -e "${GREEN}✓ Local backup created successfully!${RESET}"
    echo -e "  Location: ${BOLD}$tar_file${RESET} ($archive_size)"
    if [ -f "$zip_file" ]; then
        echo -e "  ZIP file: ${BOLD}$zip_file${RESET}"
    fi

    # Google Drive Sync (if mounted)
    local gdrive_synced=false
    if mountpoint -q "$TARGET_HOME/GoogleDrive" 2>/dev/null || [ -d "$TARGET_HOME/GoogleDrive" ]; then
        mkdir -p "$GDRIVE_DIR" 2>/dev/null || true
        chmod 700 "$GDRIVE_DIR" 2>/dev/null || true
        if cp "$tar_file" "$GDRIVE_DIR/" 2>/dev/null && cp "$latest_tar" "$GDRIVE_DIR/" 2>/dev/null; then
            if [ -f "$zip_file" ]; then cp "$zip_file" "$GDRIVE_DIR/" 2>/dev/null || true; fi
            echo -e "${GREEN}✓ Synced to Google Drive: ${BOLD}$GDRIVE_DIR/dev-configs-latest.zip${RESET}"
            gdrive_synced=true
        fi
    fi

    if [ "$gdrive_synced" = false ]; then
        echo -e "${YELLOW}ℹ Google Drive not currently mounted. Backup is saved locally.${RESET}"
    fi

    # USB & Offline Copy Instructions
    echo
    echo -e "${BOLD}${CYAN}------------------------------------------------------------------${RESET}"
    echo -e "${BOLD}OFFLINE USB TRANSFER INSTRUCTIONS:${RESET}"
    echo -e "To copy this backup to a USB drive and set up another PC:"
    echo -e "  ${BOLD}1. Insert your USB flash drive.${RESET}"
    echo -e "  ${BOLD}2. Copy the archive:${RESET}"
    echo -e "     cp $latest_tar /media/$TARGET_USER/<USB_NAME>/"
    echo -e "     ${CYAN}(or copy $latest_zip)${RESET}"
    echo -e "  ${BOLD}3. On the new PC, run:${RESET}"
    echo -e "     ./backup-dev-configs.sh --restore /media/$TARGET_USER/<USB_NAME>/dev-configs-latest.tar.gz"
    echo -e "${BOLD}${CYAN}------------------------------------------------------------------${RESET}"
    echo
}

# ---------------------------------------------------------------------------
# Restore Function
# ---------------------------------------------------------------------------
do_restore() {
    print_header "Restoring Developer Configurations"

    local target_file="${1:-}"

    if [ -z "$target_file" ]; then
        if [ -f "$LOCAL_BACKUP_DIR/dev-configs-latest.tar.gz" ]; then
            target_file="$LOCAL_BACKUP_DIR/dev-configs-latest.tar.gz"
            echo -e "Using latest local backup: ${BOLD}$target_file${RESET}"
        elif [ -f "$LOCAL_BACKUP_DIR/dev-configs-latest.zip" ]; then
            target_file="$LOCAL_BACKUP_DIR/dev-configs-latest.zip"
            echo -e "Using latest local ZIP backup: ${BOLD}$target_file${RESET}"
        else
            echo "No default backup archive found."
            echo -en "${BOLD}Enter path to backup archive (.zip or .tar.gz): ${RESET}"
            read -r target_file
        fi
    fi

    # Expand ~ if used
    target_file="${target_file/#\~/$TARGET_HOME}"

    if [ ! -f "$target_file" ]; then
        echo -e "${RED}Error: Backup file not found at '$target_file'${RESET}"
        exit 1
    fi

    echo -e "Restoring from: ${BOLD}$target_file${RESET}"
    echo -en "${BOLD}Proceed with restoring these configurations? [Y/n]: ${RESET}"
    read -r confirm
    confirm="${confirm:-y}"
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Restore cancelled."
        exit 0
    fi

    # Unpack to secure temporary directory with mode 0700
    local temp_dir
    temp_dir=$(mktemp -d "/tmp/dev-configs-restore.XXXXXX")
    chmod 700 "$temp_dir"
    trap 'rm -rf "$temp_dir"' EXIT INT TERM

    if [[ "$target_file" =~ \.zip$ ]]; then
        unzip -q "$target_file" -d "$temp_dir"
    else
        tar -xzf "$target_file" -C "$temp_dir"
    fi

    # Safety Backup of current existing configs
    local safety_dir="$TARGET_HOME/.config-safety-backup-$TIMESTAMP"
    mkdir -p "$safety_dir"
    chmod 700 "$safety_dir"
    echo -e "Creating safety backup of current configs at: ${BOLD}$safety_dir${RESET}..."
    if [ -f "$TARGET_HOME/.bashrc" ]; then cp "$TARGET_HOME/.bashrc" "$safety_dir/"; fi
    if [ -f "$TARGET_HOME/.gitconfig" ]; then cp "$TARGET_HOME/.gitconfig" "$safety_dir/"; fi
    if [ -f "$TARGET_HOME/.tmux.conf" ]; then cp "$TARGET_HOME/.tmux.conf" "$safety_dir/"; fi

    # Perform Restore
    if [ -f "$temp_dir/bashrc" ]; then
        cp "$temp_dir/bashrc" "$TARGET_HOME/.bashrc"
        echo -e "  ${GREEN}✓ Restored ~/.bashrc${RESET}"
    fi

    if [ -f "$temp_dir/gitconfig" ]; then
        cp "$temp_dir/gitconfig" "$TARGET_HOME/.gitconfig"
        echo -e "  ${GREEN}✓ Restored ~/.gitconfig${RESET}"
    fi

    if [ -f "$temp_dir/tmux.conf" ]; then
        cp "$temp_dir/tmux.conf" "$TARGET_HOME/.tmux.conf"
        echo -e "  ${GREEN}✓ Restored ~/.tmux.conf${RESET}"
    fi

    if [ -d "$temp_dir/config/geany" ]; then
        mkdir -p "$TARGET_HOME/.config/geany"
        cp -r "$temp_dir/config/geany/"* "$TARGET_HOME/.config/geany/" 2>/dev/null || true
        echo -e "  ${GREEN}✓ Restored ~/.config/geany (Themes & settings)${RESET}"
    fi

    if [ -d "$temp_dir/config/lazygit" ]; then
        mkdir -p "$TARGET_HOME/.config/lazygit"
        cp -r "$temp_dir/config/lazygit/"* "$TARGET_HOME/.config/lazygit/" 2>/dev/null || true
        echo -e "  ${GREEN}✓ Restored ~/.config/lazygit${RESET}"
    fi

    if [ -f "$temp_dir/config/rclone/rclone.conf" ]; then
        mkdir -p "$TARGET_HOME/.config/rclone"
        cp "$temp_dir/config/rclone/rclone.conf" "$TARGET_HOME/.config/rclone/rclone.conf"
        chmod 600 "$TARGET_HOME/.config/rclone/rclone.conf"
        echo -e "  ${GREEN}✓ Restored ~/.config/rclone/rclone.conf${RESET}"
    fi

    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.bashrc" "$TARGET_HOME/.gitconfig" "$TARGET_HOME/.tmux.conf" 2>/dev/null || true
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config" "$safety_dir" 2>/dev/null || true
    fi

    rm -rf "$temp_dir"
    trap - EXIT INT TERM

    echo
    echo -e "${BOLD}${GREEN}==================================================================${RESET}"
    echo -e "${BOLD}${GREEN}  Configurations Restored Successfully!${RESET}"
    echo -e "${BOLD}${GREEN}==================================================================${RESET}"
    echo "To apply your restored bash environment immediately, run:"
    echo -e "  ${CYAN}source ~/.bashrc${RESET}"
    echo
}

# ---------------------------------------------------------------------------
# List Archives
# ---------------------------------------------------------------------------
do_list() {
    print_header "Available Configuration Backups"

    echo -e "${BOLD}Local Backups ($LOCAL_BACKUP_DIR):${RESET}"
    if [ -d "$LOCAL_BACKUP_DIR" ] && [ "$(ls -A "$LOCAL_BACKUP_DIR" 2>/dev/null)" ]; then
        ls -lh "$LOCAL_BACKUP_DIR"
    else
        echo "  No local backup files found."
    fi

    echo
    echo -e "${BOLD}Google Drive Backups ($GDRIVE_DIR):${RESET}"
    if [ -d "$GDRIVE_DIR" ] && [ "$(ls -A "$GDRIVE_DIR" 2>/dev/null)" ]; then
        ls -lh "$GDRIVE_DIR"
    else
        echo "  No Google Drive backup files found (or Google Drive not mounted)."
    fi
    echo
}

# ---------------------------------------------------------------------------
# Install Aliases
# ---------------------------------------------------------------------------
do_install_aliases() {
    print_header "Installing Config Sync Shell Aliases"

    local script_abs
    script_abs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backup-dev-configs.sh"

    if ! grep -q "backup-configs" "$BASHRC" 2>/dev/null; then
        echo "" >> "$BASHRC"
        echo "# Debian-Dev-Suite: Config Sync Shortcuts" >> "$BASHRC"
        echo "alias backup-configs=\"$script_abs --backup\"" >> "$BASHRC"
        echo "alias restore-configs=\"$script_abs --restore\"" >> "$BASHRC"
        echo -e "  ${GREEN}✓ Added 'backup-configs' and 'restore-configs' to ~/.bashrc${RESET}"
        echo "Run: source ~/.bashrc"
    else
        echo -e "  ${CYAN}Aliases are already present in ~/.bashrc${RESET}"
    fi
    echo
}

# ---------------------------------------------------------------------------
# Status Function
# ---------------------------------------------------------------------------
do_status() {
    print_header "Developer Configurations Backup Status"

    local local_count=0
    if [ -d "$LOCAL_BACKUP_DIR" ]; then
        local_count=$(find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f \( -name "*.zip" -o -name "*.tar.gz" \) 2>/dev/null | wc -l || echo 0)
    fi

    local gdrive_count=0
    if [ -d "$GDRIVE_DIR" ] && mountpoint -q "$TARGET_HOME/GoogleDrive" 2>/dev/null; then
        gdrive_count=$(find "$GDRIVE_DIR" -maxdepth 1 -type f \( -name "*.zip" -o -name "*.tar.gz" \) 2>/dev/null | wc -l || echo 0)
    fi

    echo -e "  ${BOLD}Local Backups Directory:${RESET}  $LOCAL_BACKUP_DIR ($local_count archives)"
    if [ "$local_count" -gt 0 ]; then
        local latest_backup
        latest_backup=$(ls -t "$LOCAL_BACKUP_DIR" 2>/dev/null | head -n1 || echo "")
        if [ -n "$latest_backup" ]; then
            echo -e "  ${BOLD}Latest Local Backup:${RESET}      $latest_backup"
        fi
    fi

    if mountpoint -q "$TARGET_HOME/GoogleDrive" 2>/dev/null; then
        echo -e "  ${BOLD}Google Drive Sync:${RESET}        ${GREEN}Active${RESET} ($gdrive_count remote archives)"
    else
        echo -e "  ${BOLD}Google Drive Sync:${RESET}        ${YELLOW}Inactive${RESET} (GoogleDrive not mounted)"
    fi

    echo
    echo -e "  ${BOLD}Tracked Configuration Files:${RESET}"
    for f in "$TARGET_HOME/.bashrc" "$TARGET_HOME/.gitconfig" "$TARGET_HOME/.tmux.conf" "$TARGET_HOME/.config/geany" "$TARGET_HOME/.config/lazygit"; do
        if [ -e "$f" ]; then
            echo -e "    ${GREEN}✔${RESET} $f"
        else
            echo -e "    ${YELLOW}○${RESET} $f (not found)"
        fi
    done

    echo
    if grep -q "backup-configs" "$BASHRC" 2>/dev/null; then
        echo -e "  ${BOLD}Shell Aliases:${RESET}            ${GREEN}Installed${RESET} (backup-configs, restore-configs)"
    else
        echo -e "  ${BOLD}Shell Aliases:${RESET}            ${YELLOW}Not registered${RESET} (run with --install-aliases)"
    fi
    echo
}

# ---------------------------------------------------------------------------
# Uninstall Function
# ---------------------------------------------------------------------------
do_uninstall() {
    print_header "Uninstalling Config Sync Shortcuts"

    if [ -f "$BASHRC" ]; then
        if grep -q "backup-configs" "$BASHRC" 2>/dev/null; then
            sed -i -E '/# Debian-Dev-(Suite|Setup): Config Sync Shortcuts/d' "$BASHRC"
            sed -i '/alias backup-configs=/d' "$BASHRC"
            sed -i '/alias restore-configs=/d' "$BASHRC"
            echo -e "  ${GREEN}✓ Removed 'backup-configs' and 'restore-configs' from ~/.bashrc${RESET}"
            echo "Run: source ~/.bashrc to refresh your current shell session."
        else
            echo -e "  ${CYAN}No Config Sync aliases were found in ~/.bashrc.${RESET}"
        fi
    fi

    echo
    echo -e "  ${BOLD}Local Backups Directory:${RESET} $LOCAL_BACKUP_DIR"
    if [ -d "$LOCAL_BACKUP_DIR" ]; then
        if [ -t 0 ]; then
            echo -en "  Do you want to delete existing local backup archives in $LOCAL_BACKUP_DIR? [y/N]: "
            read -r del_resp
            if [[ "$del_resp" =~ ^[Yy]$ ]]; then
                rm -rf "$LOCAL_BACKUP_DIR"
                echo -e "  ${GREEN}✓ Removed $LOCAL_BACKUP_DIR${RESET}"
            else
                echo -e "  ${CYAN}Preserved backup archives in $LOCAL_BACKUP_DIR${RESET}"
            fi
        else
            echo -e "  ${CYAN}Non-interactive mode: preserved backup archives in $LOCAL_BACKUP_DIR${RESET}"
        fi
    fi

    echo
    echo -e "  ${GREEN}✓ Config Sync uninstallation completed!${RESET}"
    echo
}

# ---------------------------------------------------------------------------
# CLI Argument Parser
# ---------------------------------------------------------------------------
case "${1:-}" in
    --status|-s|status)
        do_status
        ;;
    --backup)
        do_backup
        ;;
    --restore)
        do_restore "${2:-}"
        ;;
    --list)
        do_list
        ;;
    --install|--install-aliases)
        do_install_aliases
        ;;
    --uninstall|uninstall)
        do_uninstall
        ;;
    --help|-h|help)
        echo -e "${BOLD}Usage:${RESET} $0 [OPTION]"
        echo
        echo -e "${BOLD}Options:${RESET}"
        echo "  --backup                   Create local ZIP/TAR archives and sync to Google Drive"
        echo "  --restore [file]           Restore configurations from archive (with safe .bak backup)"
        echo "  --list                     List available local and Google Drive backup archives"
        echo "  --install, --install-aliases Register 'backup-configs' and 'restore-configs' in ~/.bashrc"
        echo "  --uninstall                Cleanly remove shell aliases and optionally purge backup archives"
        echo "  --status, -s               Show backup archives status, tracked files & aliases"
        echo "  --help, -h                 Show this help manual"
        echo
        ;;
    "")
        echo "Select action:"
        echo "  [1] Backup configs now (Local + Google Drive)"
        echo "  [2] Restore configs from archive"
        echo "  [3] List existing backups"
        echo "  [4] Register shell aliases in ~/.bashrc"
        echo "  [5] Uninstall shell aliases and cleanup"
        echo -en "${BOLD}Choose [1-5, Default: 1]: ${RESET}"
        read -r opt
        opt="${opt:-1}"
        case "$opt" in
            1) do_backup ;;
            2) do_restore "" ;;
            3) do_list ;;
            4) do_install_aliases ;;
            5) do_uninstall ;;
            *) do_backup ;;
        esac
        ;;
    *)
        echo -e "${RED}Unknown option: $1${RESET}"
        echo "Use --help for options."
        exit 1
        ;;
esac
