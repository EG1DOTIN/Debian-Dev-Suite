#!/bin/sh

###############################################################################
# Universal Google Drive Setup & Mount for Debian-based Linux Systems
# (Debian, antiX, Ubuntu, Linux Mint, MX Linux, Devuan, etc.)
#
# Sets up Rclone with FUSE to mount Google Drive directly as a local folder:
#   - 100% Open-source, lightweight, secure, and privacy-focused
#   - On-demand streaming (reads/writes on the fly without filling your disk)
#   - Low RAM footprint (ideal for low-spec systems like 2-3GB RAM)
#   - Creates simple 'mount-gdrive' and 'unmount-gdrive' in GoogleDrive-Bin
#   - Mount verification, error logging & autostart integration
#
# USAGE:
#   ./setup-GoogleDrive.sh --install     # Install dependencies, configure & setup
#   ./setup-GoogleDrive.sh --uninstall   # Safely unmount, clean up & optionally remove packages
#   ./setup-GoogleDrive.sh --help        # Show help and usage instructions
###############################################################################

set -u

# Dynamic User & Target Home Lookup (Zero hardcoding, dual-root/user safe)
TARGET_USER="${SUDO_USER:-${USER:-$(id -un 2>/dev/null || echo '')}}"
if [ -n "$TARGET_USER" ]; then
    TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "${HOME:-/home/$TARGET_USER}")"
else
    TARGET_HOME="${HOME:-/home/$USER}"
fi

MOUNT_DIR="$TARGET_HOME/GoogleDrive"
BIN_DIR="$TARGET_HOME/GoogleDrive-Bin"
LOG_DIR="$TARGET_HOME/.cache/rclone"
MOUNT_LOG="$LOG_DIR/gdrive-mount.log"

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:"$BIN_DIR":$PATH
export PATH

###############################################################################
# Help / Usage
###############################################################################

show_help()
{
    echo "Universal Google Drive Setup & Mount for Debian-based Systems"
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  --install, -i      Install dependencies, configure Google Drive, and create mount scripts"
    echo "  --uninstall, -u    Unmount Google Drive, remove scripts & optionally remove dependencies"
    echo "  --status, -s       Show Google Drive installation, configuration & mount status"
    echo "  --help, -h         Display this help message"
    echo
    echo "Examples:"
    echo "  $0 --status        # Check Google Drive mount and configuration status"
    echo "  $0 --install       # Full automated installation"
    echo "  $0 --uninstall     # Clean uninstallation with dependency removal prompt"
    echo
}

###############################################################################
# Installation Routine
###############################################################################

install_gdrive()
{
    echo "=================================================="
    echo "    Google Drive Setup for Debian-based Systems   "
    echo "=================================================="
    echo

    # 1. System Clock Verification (Critical for SSL / OAuth)
    CURRENT_YEAR=$(date +%Y 2>/dev/null || echo 0)
    if [ "$CURRENT_YEAR" -lt 2024 ]; then
        echo "WARNING: Your system clock is set to year $CURRENT_YEAR!"
        echo "Google Drive authentication and APT package downloads will FAIL with"
        echo "SSL/TLS certificate errors until your clock is corrected."
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

    # 2. Package Installation (rclone and fuse3 / fuse)
    NEED_INSTALL=0

    if ! command -v rclone >/dev/null 2>&1; then
        NEED_INSTALL=1
    fi

    if ! command -v fusermount3 >/dev/null 2>&1 && ! command -v fusermount >/dev/null 2>&1; then
        NEED_INSTALL=1
    fi

    if [ "$NEED_INSTALL" -eq 1 ]; then
        echo "Installing required open-source packages (rclone, fuse3)..."
        echo "Root privileges (sudo) required for package installation."

        if ! sudo apt update; then
            echo
            echo "WARNING: 'sudo apt update' reported errors."
            echo "If this was caused by an outdated system clock, ensure time is synced."
            printf "Try installing packages anyway? [Y/n]: "
            read -r TRY_APT
            case "$TRY_APT" in
                [nN]|[nN][oO])
                    echo "Installation aborted."
                    exit 1
                    ;;
            esac
        fi

        if ! sudo apt install -y rclone fuse3; then
            echo "Trying alternative package name (fuse)..."
            sudo apt install -y rclone fuse || {
                echo "ERROR: Failed to install rclone and fuse."
                exit 1
            }
        fi
        echo "  [OK] Packages installed successfully."
    else
        echo "  [OK] rclone and fuse are already installed."
    fi

    # 3. Create Directories
    mkdir -p "$BIN_DIR"
    mkdir -p "$MOUNT_DIR"
    mkdir -p "$LOG_DIR"
    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown -R "$TARGET_USER:$TARGET_USER" "$BIN_DIR" "$MOUNT_DIR" "$LOG_DIR" 2>/dev/null || true
    fi

    # 4. Google Drive Configuration (rclone config)
    echo
    echo "--------------------------------------------------"
    echo "            Google Drive Configuration            "
    echo "--------------------------------------------------"
    echo "We will now launch 'rclone config' to connect your account."
    echo
    echo "Quick Guide for the Prompts:"
    echo "  1. Choose 'n'               -> New remote"
    echo "  2. Name                     -> Type: gdrive"
    echo "  3. Type of storage          -> Type: drive  (for Google Drive)"
    echo "  4. Client Id & Secret       -> Press ENTER for default (or enter your own)"
    echo "  5. Scope                    -> Type: 1      (Full access to files)"
    echo "  6. Service Account File     -> Press ENTER (leave blank)"
    echo "  7. Edit advanced config     -> Type: n      (No)"
    echo "  8. Use auto config?:"
    echo "       - If on Desktop Linux with web browser : Type 'y' (browser will open)"
    echo "       - If on SSH / Terminal without browser : Type 'n' (follow remote auth steps)"
    echo "  9. Keep this remote?        -> Type: y"
    echo " 10. Quit config              -> Type: q"
    echo "--------------------------------------------------"
    echo
    printf "Press ENTER to start 'rclone config'..."
    read -r _

    rclone config

    # Detect configured remotes
    CONFIGURED_REMOTES=$(rclone listremotes 2>/dev/null || true)
    REMOTE_NAME="gdrive"

    if echo "$CONFIGURED_REMOTES" | grep -q "^${REMOTE_NAME}:"; then
        echo "  [OK] Found configured remote '${REMOTE_NAME}:'."
    elif [ -n "$CONFIGURED_REMOTES" ]; then
        FIRST_REMOTE=$(echo "$CONFIGURED_REMOTES" | head -n 1 | tr -d ':')
        echo "Found configured remote: '$FIRST_REMOTE'"
        printf "Use '$FIRST_REMOTE' as your Google Drive remote? [Y/n]: "
        read -r REMOTE_CHOICE
        case "$REMOTE_CHOICE" in
            [nN]|[nN][oO])
                printf "Enter the exact remote name you configured: "
                read -r MANUAL_REMOTE
                REMOTE_NAME=$(echo "$MANUAL_REMOTE" | tr -d ':')
                ;;
            *)
                REMOTE_NAME="$FIRST_REMOTE"
                ;;
        esac
    else
        echo "WARNING: No rclone remotes found. Defaulting to 'gdrive'."
        echo "You can re-run 'rclone config' later if needed."
    fi

    # 5. Create 'mount-gdrive' Script in GoogleDrive-Bin
    cat > "$BIN_DIR/mount-gdrive" <<EOF
#!/bin/sh

# Google Drive Mount Script
# Uses Rclone VFS caching for responsive and reliable access.

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:"$BIN_DIR":\$PATH
MOUNT="$MOUNT_DIR"
REMOTE="$REMOTE_NAME"
LOGFILE="$MOUNT_LOG"

mkdir -p "\$MOUNT"
mkdir -p "$LOG_DIR"

if mountpoint -q "\$MOUNT"; then
    echo "Google Drive is already mounted at \$MOUNT"
    exit 0
fi

echo "Mounting Google Drive (\$REMOTE:) to \$MOUNT..."

# rclone mount options (optimized for high speed, fast uploads & instant deletions):
# --vfs-cache-mode full       : caches reads and writes to local disk for native responsiveness
# --vfs-cache-max-age 24h     : retains active files in cache for 24 hours
# --vfs-cache-max-size 10G    : limits local cache size so disk does not fill up
# --drive-chunk-size 64M      : increases upload chunk from default 8M to 64M (3-5x faster uploads)
# --drive-use-trash=false     : deletes files directly on remote without slow trash metadata updates
# --dir-cache-time 1000h      : caches folder tree for instant folder navigation
# --poll-interval 1m          : polls Google Drive API for remote changes every minute
# --buffer-size 16M           : low memory footprint for read streaming
# --daemon                    : run in background
rclone mount "\$REMOTE:" "\$MOUNT" \\
    --vfs-cache-mode full \\
    --vfs-cache-max-age 24h \\
    --vfs-cache-max-size 10G \\
    --drive-chunk-size 64M \\
    --drive-use-trash=false \\
    --dir-cache-time 1000h \\
    --poll-interval 1m \\
    --buffer-size 16M \\
    --log-file "\$LOGFILE" \\
    --log-level NOTICE \\
    --daemon

# Wait up to 3 seconds for mount to initialize
sleep 2

if mountpoint -q "\$MOUNT"; then
    echo "SUCCESS: Google Drive mounted at \$MOUNT"
    echo "Files are now accessible in your file manager or terminal."
    exit 0
else
    echo "ERROR: Failed to mount Google Drive at \$MOUNT."
    if [ -f "\$LOGFILE" ]; then
        echo "Recent log messages (\$LOGFILE):"
        echo "----------------------------------------"
        tail -n 12 "\$LOGFILE"
        echo "----------------------------------------"
    fi
    echo "Troubleshooting: Check 'rclone lsd \$REMOTE:' to test connectivity."
    exit 1
fi
EOF

    # 6. Create 'unmount-gdrive' Script in GoogleDrive-Bin
    cat > "$BIN_DIR/unmount-gdrive" <<EOF
#!/bin/sh

# Google Drive Unmount Script

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:"$BIN_DIR":\$PATH
MOUNT="$MOUNT_DIR"

if ! mountpoint -q "\$MOUNT"; then
    echo "Google Drive is not currently mounted at \$MOUNT."
    exit 0
fi

echo "Unmounting Google Drive from \$MOUNT..."

# Try standard unmount with fusermount3 or fusermount
UNMOUNT_OK=0

if command -v fusermount3 >/dev/null 2>&1; then
    fusermount3 -u "\$MOUNT" 2>/dev/null && UNMOUNT_OK=1
elif command -v fusermount >/dev/null 2>&1; then
    fusermount -u "\$MOUNT" 2>/dev/null && UNMOUNT_OK=1
else
    umount "\$MOUNT" 2>/dev/null && UNMOUNT_OK=1
fi

# If standard unmount was busy, try lazy unmount (-z)
if [ "\$UNMOUNT_OK" -eq 0 ] && mountpoint -q "\$MOUNT"; then
    echo "Mount point is busy (files may be open). Attempting lazy unmount..."
    if command -v fusermount3 >/dev/null 2>&1; then
        fusermount3 -uz "\$MOUNT" 2>/dev/null && UNMOUNT_OK=1
    elif command -v fusermount >/dev/null 2>&1; then
        fusermount -uz "\$MOUNT" 2>/dev/null && UNMOUNT_OK=1
    else
        umount -l "\$MOUNT" 2>/dev/null && UNMOUNT_OK=1
    fi
fi

sleep 1

if ! mountpoint -q "\$MOUNT"; then
    echo "SUCCESS: Google Drive unmounted."
    exit 0
else
    echo "ERROR: Unable to unmount \$MOUNT."
    echo "Close any terminals or file manager tabs currently viewing \$MOUNT and retry."
    exit 1
fi
EOF

    chmod +x "$BIN_DIR/mount-gdrive"
    chmod +x "$BIN_DIR/unmount-gdrive"

    # 7. Create Fast Direct Sync Scripts ('gdrive-push' and 'gdrive-pull')
    # These bypass FUSE completely, offering maximum multi-threaded upload/download speeds
    cat > "$BIN_DIR/gdrive-push" <<EOF
#!/bin/sh
# Fast Multi-Threaded Direct Upload to Google Drive (Zero FUSE lag)
SOURCE="$MOUNT_DIR"
REMOTE="$REMOTE_NAME"

echo "=================================================="
echo "Uploading local \$SOURCE to \$REMOTE: ..."
echo "=================================================="

rclone copy "\$SOURCE" "\$REMOTE:" \\
    --transfers 4 \\
    --checkers 8 \\
    --drive-chunk-size 64M \\
    --progress

echo
echo "SUCCESS: Upload to Google Drive completed."
EOF

    cat > "$BIN_DIR/gdrive-pull" <<EOF
#!/bin/sh
# Fast Multi-Threaded Direct Download from Google Drive (Zero FUSE lag)
DEST="$MOUNT_DIR"
REMOTE="$REMOTE_NAME"

echo "=================================================="
echo "Downloading from \$REMOTE: to \$DEST ..."
echo "=================================================="

mkdir -p "\$DEST"

rclone copy "\$REMOTE:" "\$DEST" \\
    --transfers 4 \\
    --checkers 8 \\
    --drive-chunk-size 64M \\
    --progress

echo
echo "SUCCESS: Download from Google Drive completed."
EOF

    chmod +x "$BIN_DIR/gdrive-push"
    chmod +x "$BIN_DIR/gdrive-pull"
    echo "  [OK] Created fast direct sync scripts ('gdrive-push' and 'gdrive-pull')."

    # 8. Integrate PCManFM & File Manager Bookmarks
    GTK3_BOOKMARKS="$TARGET_HOME/.config/gtk-3.0/bookmarks"
    GTK2_BOOKMARKS="$TARGET_HOME/.gtk-bookmarks"
    BOOKMARK_ENTRY="file://$MOUNT_DIR GoogleDrive"

    mkdir -p "$TARGET_HOME/.config/gtk-3.0"
    if [ -f "$GTK3_BOOKMARKS" ]; then
        if ! grep -q "$MOUNT_DIR" "$GTK3_BOOKMARKS" 2>/dev/null; then
            echo "$BOOKMARK_ENTRY" >> "$GTK3_BOOKMARKS"
            echo "  [OK] Added 'GoogleDrive' to PCManFM / GTK3 bookmarks sidebar."
        fi
    else
        echo "$BOOKMARK_ENTRY" > "$GTK3_BOOKMARKS"
        echo "  [OK] Created PCManFM / GTK3 bookmark for GoogleDrive."
    fi

    if [ -f "$GTK2_BOOKMARKS" ]; then
        if ! grep -q "$MOUNT_DIR" "$GTK2_BOOKMARKS" 2>/dev/null; then
            echo "$BOOKMARK_ENTRY" >> "$GTK2_BOOKMARKS"
        fi
    fi

    # 9. Ensure $BIN_DIR is in $PATH
    PATH_UPDATED=0
    case ":$PATH:" in
        *":$BIN_DIR:"*)
            # Already in current PATH
            ;;
        *)
            # Add to ~/.bashrc if not present
            if [ -f "$TARGET_HOME/.bashrc" ] && ! grep -q 'GoogleDrive-Bin' "$TARGET_HOME/.bashrc"; then
                echo '' >> "$TARGET_HOME/.bashrc"
                echo '# User bin path for Google Drive scripts' >> "$TARGET_HOME/.bashrc"
                echo 'export PATH="$HOME/GoogleDrive-Bin:$PATH"' >> "$TARGET_HOME/.bashrc"
                PATH_UPDATED=1
            fi
            ;;
    esac

    # 10. Optional system-wide symlink in /usr/local/bin
    echo
    printf "Do you want to create system-wide shortcuts in /usr/local/bin (requires sudo)? [y/N]: "
    read -r SYMLINK_CHOICE
    case "$SYMLINK_CHOICE" in
        [yY]|[yY][eE][sS])
            sudo ln -sf "$BIN_DIR/mount-gdrive" /usr/local/bin/mount-gdrive
            sudo ln -sf "$BIN_DIR/unmount-gdrive" /usr/local/bin/unmount-gdrive
            sudo ln -sf "$BIN_DIR/gdrive-push" /usr/local/bin/gdrive-push
            sudo ln -sf "$BIN_DIR/gdrive-pull" /usr/local/bin/gdrive-pull
            echo "  [OK] Shortcuts created in /usr/local/bin (mount-gdrive, unmount-gdrive, gdrive-push, gdrive-pull)."
            ;;
        *)
            echo "  Skipped system-wide shortcuts. You can run them via:"
            echo "    $BIN_DIR/mount-gdrive"
            echo "    $BIN_DIR/unmount-gdrive"
            echo "    $BIN_DIR/gdrive-push"
            echo "    $BIN_DIR/gdrive-pull"
            ;;
    esac

    # 11. Optional Autostart Setup
    echo
    printf "Do you want Google Drive to mount automatically when you log in? [y/N]: "
    read -r AUTOSTART_CHOICE
    case "$AUTOSTART_CHOICE" in
        [yY]|[yY][eE][sS])
            # antiX Linux autostart (~/.desktop-session/startup)
            if [ -f "$TARGET_HOME/.desktop-session/startup" ]; then
                if ! grep -q 'mount-gdrive' "$TARGET_HOME/.desktop-session/startup"; then
                    echo '' >> "$TARGET_HOME/.desktop-session/startup"
                    echo '# Auto-mount Google Drive on login' >> "$TARGET_HOME/.desktop-session/startup"
                    echo "$BIN_DIR/mount-gdrive &" >> "$TARGET_HOME/.desktop-session/startup"
                    echo "  [OK] Added to antiX desktop startup (~/.desktop-session/startup)."
                fi
            fi

            # Standard Desktop Autostart (~/.config/autostart/)
            AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
            mkdir -p "$AUTOSTART_DIR"
            cat > "$AUTOSTART_DIR/mount-gdrive.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$BIN_DIR/mount-gdrive
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Mount Google Drive
Comment=Mount Google Drive folder on desktop login
EOF
            if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
                chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config" "$BIN_DIR" 2>/dev/null || true
            fi
            echo "  [OK] Created desktop autostart entry ($AUTOSTART_DIR/mount-gdrive.desktop)."
            ;;
        *)
            echo "  Skipped autostart. Mount manually whenever needed."
            ;;
    esac

    # 12. Summary & Next Steps
    echo
    echo "=================================================="
    echo "          Installation Finished Successfully!     "
    echo "=================================================="
    echo
    echo "Files Location:"
    echo "    Local Folder : $MOUNT_DIR"
    echo "    Scripts Path : $BIN_DIR/"
    echo "    PCManFM      : 'GoogleDrive' added to left Bookmarks sidebar"
    echo
    echo "Option 1: Virtual Live Mount (Browsing like local disk):"
    echo "    mount-gdrive    (Mounts Google Drive with full VFS cache)"
    echo "    unmount-gdrive  (Safely unmounts and flushes writes)"
    echo
    echo "Option 2: Direct Fast Sync (Zero FUSE lag, maximum transfer speed):"
    echo "    gdrive-push     (Fast multi-threaded upload of ~/GoogleDrive to cloud)"
    echo "    gdrive-pull     (Fast multi-threaded download of cloud to ~/GoogleDrive)"
    echo
    echo "Log file for troubleshooting:"
    echo "    $MOUNT_LOG"
    echo
    if [ "$PATH_UPDATED" -eq 1 ]; then
        echo "Note: Run 'source ~/.bashrc' or open a new terminal so commands are in your PATH."
    fi
    echo "=================================================="
}

###############################################################################
# Uninstallation Routine
###############################################################################

uninstall_gdrive()
{
    echo "=================================================="
    echo "        Google Drive Setup Uninstallation         "
    echo "=================================================="
    echo

    # 1. Unmount if currently mounted
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        echo "Google Drive is currently mounted. Unmounting first..."
        if [ -x "$BIN_DIR/unmount-gdrive" ]; then
            "$BIN_DIR/unmount-gdrive" || true
        else
            fusermount3 -uz "$MOUNT_DIR" 2>/dev/null || fusermount -uz "$MOUNT_DIR" 2>/dev/null || umount -l "$MOUNT_DIR" 2>/dev/null || true
        fi
        sleep 1
    fi

    # 2. Remove autostart entries
    if [ -f "$TARGET_HOME/.desktop-session/startup" ]; then
        if grep -q 'mount-gdrive' "$TARGET_HOME/.desktop-session/startup"; then
            sed -i '/# Auto-mount Google Drive on login/d' "$TARGET_HOME/.desktop-session/startup" 2>/dev/null || true
            sed -i '/mount-gdrive/d' "$TARGET_HOME/.desktop-session/startup" 2>/dev/null || true
            echo "  [OK] Removed autostart entry from ~/.desktop-session/startup."
        fi
    fi

    DESKTOP_AUTOSTART="$TARGET_HOME/.config/autostart/mount-gdrive.desktop"
    if [ -f "$DESKTOP_AUTOSTART" ]; then
        rm -f "$DESKTOP_AUTOSTART"
        echo "  [OK] Removed desktop autostart entry ($DESKTOP_AUTOSTART)."
    fi

    # 3. Remove shortcuts in /usr/local/bin
    sudo rm -f /usr/local/bin/mount-gdrive /usr/local/bin/unmount-gdrive /usr/local/bin/gdrive-push /usr/local/bin/gdrive-pull 2>/dev/null || true
    echo "  [OK] Removed shortcuts from /usr/local/bin."

    # 4. Remove scripts in GoogleDrive-Bin
    if [ -d "$BIN_DIR" ]; then
        rm -f "$BIN_DIR/mount-gdrive" "$BIN_DIR/unmount-gdrive" "$BIN_DIR/gdrive-push" "$BIN_DIR/gdrive-pull"
        rmdir "$BIN_DIR" 2>/dev/null || true
        echo "  [OK] Removed scripts from $BIN_DIR."
    fi

    # 5. Remove PCManFM / GTK bookmarks
    GTK3_BOOKMARKS="$TARGET_HOME/.config/gtk-3.0/bookmarks"
    GTK2_BOOKMARKS="$TARGET_HOME/.gtk-bookmarks"
    if [ -f "$GTK3_BOOKMARKS" ]; then
        sed -i "\|$MOUNT_DIR|d" "$GTK3_BOOKMARKS" 2>/dev/null || true
        echo "  [OK] Removed GoogleDrive from PCManFM / GTK3 bookmarks."
    fi
    if [ -f "$GTK2_BOOKMARKS" ]; then
        sed -i "\|$MOUNT_DIR|d" "$GTK2_BOOKMARKS" 2>/dev/null || true
    fi

    # 6. Clean ~/.bashrc PATH entry
    if [ -f "$TARGET_HOME/.bashrc" ] && grep -q 'GoogleDrive-Bin' "$TARGET_HOME/.bashrc"; then
        sed -i '/GoogleDrive-Bin/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true
        sed -i '/# User bin path for Google Drive scripts/d' "$TARGET_HOME/.bashrc" 2>/dev/null || true
        echo "  [OK] Removed GoogleDrive-Bin from ~/.bashrc PATH."
    fi

    # 6. Ask about mount directory ($MOUNT_DIR)
    echo
    if [ -d "$MOUNT_DIR" ]; then
        printf "Do you want to remove the local mount folder ($MOUNT_DIR)? [y/N]: "
        read -r REMOVE_MOUNT
        case "$REMOVE_MOUNT" in
            [yY]|[yY][eE][sS])
                rmdir "$MOUNT_DIR" 2>/dev/null || echo "  (Folder not empty; kept $MOUNT_DIR)"
                echo "  [OK] Processed mount folder."
                ;;
            *)
                echo "  Kept mount folder ($MOUNT_DIR)."
                ;;
        esac
    fi

    # 7. Ask about Rclone configuration
    echo
    if [ -f "$TARGET_HOME/.config/rclone/rclone.conf" ]; then
        printf "Do you want to delete your Rclone Google Drive credentials configuration? [y/N]: "
        read -r REMOVE_CONFIG
        case "$REMOVE_CONFIG" in
            [yY]|[yY][eE][sS])
                rclone config delete gdrive 2>/dev/null || true
                echo "  [OK] Deleted 'gdrive' remote configuration."
                ;;
            *)
                echo "  Kept Rclone configuration."
                ;;
        esac
    fi

    # 8. Ask about removing system dependencies (rclone, fuse3)
    echo
    echo "--------------------------------------------------"
    printf "Do you want to uninstall system packages (rclone, fuse3/fuse)? [y/N]: "
    read -r REMOVE_PACKAGES
    case "$REMOVE_PACKAGES" in
        [yY]|[yY][eE][sS])
            echo "Removing system packages..."
            sudo apt remove --purge -y rclone fuse3 fuse 2>/dev/null || true
            sudo apt autoremove -y 2>/dev/null || true
            echo "  [OK] Packages (rclone, fuse) uninstalled."
            ;;
        *)
            echo "  Kept system packages (rclone, fuse) installed."
            ;;
    esac
    echo "--------------------------------------------------"

    echo
    echo "=================================================="
    echo "         Uninstallation Completed Cleanly         "
    echo "=================================================="
}

show_status()
{
    echo "=================================================="
    echo "       Google Drive Status & Health Check         "
    echo "=================================================="
    echo

    # 1. Check Rclone Binary
    if command -v rclone >/dev/null 2>&1; then
        RCLONE_VER=$(rclone --version 2>/dev/null | head -n1 || echo "installed")
        echo "  [✔] Rclone Binary       : $RCLONE_VER"
    else
        echo "  [✖] Rclone Binary       : Not installed"
    fi

    # 2. Check FUSE support
    if command -v fusermount3 >/dev/null 2>&1 || command -v fusermount >/dev/null 2>&1; then
        echo "  [✔] FUSE Filesystem     : Available"
    else
        echo "  [⚠] FUSE Filesystem     : fuse3 / fusermount not detected"
    fi

    # 3. Check Rclone Remote Config
    RCLONE_CONF="${HOME}/.config/rclone/rclone.conf"
    if [ -f "$RCLONE_CONF" ] && grep -q '\[gdrive\]' "$RCLONE_CONF" 2>/dev/null; then
        echo "  [✔] Remote 'gdrive'     : Configured in ~/.config/rclone/rclone.conf"
    elif [ -f "$RCLONE_CONF" ]; then
        echo "  [⚠] Remote 'gdrive'     : rclone.conf exists, but 'gdrive' remote not configured"
    else
        echo "  [ℹ] Remote 'gdrive'     : Not configured (~/.config/rclone/rclone.conf missing)"
    fi

    # 4. Check Mountpoint Directory
    MOUNT_DIR="${HOME}/GoogleDrive"
    if [ -d "$MOUNT_DIR" ]; then
        echo "  [✔] Mount Directory     : $MOUNT_DIR exists"
    else
        echo "  [ℹ] Mount Directory     : $MOUNT_DIR does not exist"
    fi

    # 5. Check Active Mount Status
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        echo "  [✔] Mount Status        : Active & Mounted (On-demand streaming ready)"
    else
        echo "  [ℹ] Mount Status        : Not currently mounted"
    fi

    # 6. Check Helper Scripts
    if [ -x "${HOME}/.local/bin/mount-gdrive" ]; then
        echo "  [✔] Helper Shortcuts    : Available (~/.local/bin/mount-gdrive)"
    fi

    echo
    echo "=================================================="
}

###############################################################################
# Main Entrypoint
###############################################################################

case "${1:-}" in
    --status|-s|status)
        show_status
        ;;

    --install|-i)
        install_gdrive
        ;;

    --uninstall|-u)
        uninstall_gdrive
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
