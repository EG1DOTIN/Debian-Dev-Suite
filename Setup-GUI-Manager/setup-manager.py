#!/usr/bin/env python3
"""
Debian Dev Suite Manager — Master Graphical Control Center & Module Orchestrator
Part of the Debian Dev Suite

Features:
  1. Live Module Status Audit (Installed, Partial, Available, Running)
  2. One-Click Individual Install, Reconfigure & Clean Uninstall
  3. Real-Time Interactive Terminal Console with ANSI Color Rendering & Stdin Input
  4. Non-Blocking Async Background Diagnostics & Execution
  5. Direct Launchers for GUIs, Web Dashboards (127.0.0.1), and CLI Tools
  6. Integrated Doctor Diagnostic Suite & Hardware Inspector
  7. 100% Offline-First, Zero Telemetry, Dual Init Compatible (systemd & SysVinit)
"""

import sys
import os
import re
import html
import shutil
import subprocess
import getpass
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any

# Ensure safe XDG_RUNTIME_DIR for Qt in minimal/SysVinit environments
if "XDG_RUNTIME_DIR" not in os.environ or not os.path.exists(os.environ["XDG_RUNTIME_DIR"]):
    _temp_runtime = f"/tmp/runtime-{os.getuid()}"
    try:
        os.makedirs(_temp_runtime, mode=0o700, exist_ok=True)
        os.environ["XDG_RUNTIME_DIR"] = _temp_runtime
    except Exception:
        pass

# Qt Import: PySide6 (Official Qt for Python, LGPLv3 by The Qt Company)
try:
    from PySide6 import QtCore, QtGui, QtWidgets
    from PySide6.QtCore import Qt, QProcess, QThread, Signal, QTimer, QSize
    from PySide6.QtGui import QIcon, QFont, QTextCursor, QColor
    from PySide6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QGridLayout, QLabel, QPushButton, QLineEdit, QSplitter,
        QTextEdit, QFrame, QScrollArea, QTabWidget, QDialog,
        QMessageBox, QCheckBox, QProgressBar, QSizePolicy,
        QProxyStyle, QStyle, QTableWidget, QTableWidgetItem,
        QHeaderView, QAbstractItemView
    )
except ImportError as e:
    print(f"ERROR: PySide6 is required to run Debian Dev Suite Manager ({e}).", file=sys.stderr)
    print("Please install PySide6 via apt:", file=sys.stderr)
    print("    sudo apt update && sudo apt install -y python3-pyside6.qtwidgets python3-pyside6.qtgui python3-pyside6.qtcore", file=sys.stderr)
    sys.exit(1)

# Dynamic Paths & Zero Hardcoding
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
CURRENT_USER = os.environ.get("SUDO_USER") or getpass.getuser()
try:
    import pwd
    USER_HOME = Path(pwd.getpwnam(CURRENT_USER).pw_dir)
except Exception:
    USER_HOME = Path(os.environ.get("HOME") or Path.home())

# Status Enums
STATUS_INSTALLED = "INSTALLED"
STATUS_STOPPED = "STOPPED"
STATUS_PARTIAL = "PARTIAL"
STATUS_NOT_INSTALLED = "NOT_INSTALLED"
STATUS_UNKNOWN = "UNKNOWN"

# Color Palette Constants
COLOR_BG = "#0f172a"          # Slate 900
COLOR_CARD = "#1e293b"        # Slate 800
COLOR_CARD_HOVER = "#24324a"  # Slate 750
COLOR_BORDER = "#334155"      # Slate 700
COLOR_ACCENT = "#0284c7"      # Sky 600
COLOR_ACCENT_HOVER = "#0369a1"# Sky 700
COLOR_CYAN = "#06b6d4"        # Cyan 500
COLOR_GREEN = "#10b981"       # Emerald 500
COLOR_YELLOW = "#f59e0b"      # Amber 500
COLOR_RED = "#f43f5e"         # Rose 500
COLOR_TEXT = "#f8fafc"        # Slate 50
COLOR_MUTED = "#94a3b8"       # Slate 400
COLOR_CONSOLE_BG = "#090d16"  # Deep Terminal Black


class ANSIColorConverter:
    """Translates ANSI escape sequences into clean HTML formatted text."""
    
    ANSI_MAP = {
        "30": "#64748b", "31": "#f43f5e", "32": "#34d399", "33": "#fbbf24",
        "34": "#60a5fa", "35": "#e879f9", "36": "#22d3ee", "37": "#f8fafc",
        "90": "#94a3b8", "91": "#fb7185", "92": "#4ade80", "93": "#fde047",
        "94": "#93c5fd", "95": "#f472b6", "96": "#67e8f9", "97": "#ffffff"
    }

    @classmethod
    def to_html(cls, text: str) -> str:
        # Escape raw HTML characters
        safe_text = html.escape(text)
        
        # Strip carriage return and control chars
        safe_text = safe_text.replace("\r\n", "\n").replace("\r", "")

        # Convert ANSI color sequences: \033[...m
        def replace_ansi(match):
            codes = match.group(1).split(";")
            styles = []
            for code in codes:
                code = code.strip()
                if code == "0":
                    return "</span>"
                elif code == "1":
                    styles.append("font-weight:bold")
                elif code in cls.ANSI_MAP:
                    styles.append(f"color:{cls.ANSI_MAP[code]}")
            if styles:
                return f"<span style=\"{';'.join(styles)}\">"
            return ""

        converted = re.sub(r"\033\[([0-9;]*)m", replace_ansi, safe_text)
        # Clean any remaining ANSI cursor codes
        converted = re.sub(r"\033\[[0-9;]*[a-zA-Z]", "", converted)
        return converted


class SystemInspector:
    """Collects real-time hardware, OS, and kernel specifications rootlessly."""

    @staticmethod
    def get_system_summary() -> Dict[str, str]:
        info = {
            "os": "Linux",
            "kernel": "Unknown",
            "arch": "x86_64",
            "init": "Unknown",
            "cpu": "CPU",
            "ram": "0 GB",
            "gpu": "None detected"
        }

        # 1. OS Release
        try:
            if os.path.exists("/etc/os-release"):
                with open("/etc/os-release", "r") as f:
                    for line in f:
                        if line.startswith("PRETTY_NAME="):
                            info["os"] = line.split("=", 1)[1].strip().strip('"')
                            break
        except Exception:
            pass

        # 2. Kernel & Arch
        try:
            info["kernel"] = subprocess.check_output(["uname", "-r"], text=True).strip()
            info["arch"] = subprocess.check_output(["uname", "-m"], text=True).strip()
        except Exception:
            pass

        # 3. Init System
        try:
            if os.path.exists("/run/systemd/system") or subprocess.run(["pidof", "systemd"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                info["init"] = "systemd"
            else:
                info["init"] = "SysVinit / antiX / MX mode"
        except Exception:
            info["init"] = "SysVinit / antiX"

        # 4. CPU & RAM
        try:
            if os.path.exists("/proc/cpuinfo"):
                with open("/proc/cpuinfo", "r") as f:
                    for line in f:
                        if "model name" in line:
                            info["cpu"] = line.split(":", 1)[1].strip()
                            break
            if os.path.exists("/proc/meminfo"):
                with open("/proc/meminfo", "r") as f:
                    for line in f:
                        if "MemTotal:" in line:
                            kb = int(line.split()[1])
                            info["ram"] = f"{kb / (1024 * 1024):.1f} GB"
                            break
        except Exception:
            pass

        # 5. GPU
        try:
            if shutil.which("nvidia-smi"):
                res = subprocess.check_output(
                    ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
                    text=True, stderr=subprocess.DEVNULL
                ).strip()
                if res:
                    info["gpu"] = res.splitlines()[0]
            elif shutil.which("lspci"):
                res = subprocess.check_output(["lspci"], text=True, stderr=subprocess.DEVNULL)
                for line in res.splitlines():
                    if re.search(r"vga|3d", line, re.I):
                        parts = line.split(":", 2)
                        info["gpu"] = parts[-1].strip()
                        break
        except Exception:
            pass

        return info


class ModuleDetector:
    """Fast, rootless, non-blocking individual status audit for all modules."""

    @staticmethod
    def check_dev_tools() -> Tuple[str, str]:
        tools = ["rg", "fzf", "eza", "zoxide", "lazygit", "uv", "fnm", "docker", "lazydocker", "ai"]
        count = 0
        for t in tools:
            if shutil.which(t) or (USER_HOME / ".local" / "bin" / t).is_file():
                count += 1
        # Check bat / batcat (Debian packages bat as batcat)
        if shutil.which("bat") or shutil.which("batcat") or (USER_HOME / ".local" / "bin" / "bat").is_file():
            count += 1

        if count >= 8:
            return STATUS_INSTALLED, f"{count}/11 active tools (CLI, Git, Runtimes, Copilot)"
        elif count > 0:
            return STATUS_PARTIAL, f"{count}/11 tools installed (partial setup)"
        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_tmux() -> Tuple[str, str]:
        has_bin = bool(shutil.which("tmux"))
        has_conf = (USER_HOME / ".tmux.conf").is_file()
        if has_bin and has_conf:
            return STATUS_INSTALLED, "Installed with ergonomic ~/.tmux.conf"
        elif has_bin:
            return STATUS_PARTIAL, "tmux installed, but ~/.tmux.conf missing"
        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_geany() -> Tuple[str, str]:
        if shutil.which("geany"):
            theme_dir = USER_HOME / ".config" / "geany" / "colorschemes"
            theme_count = len(list(theme_dir.glob("*.conf"))) if theme_dir.is_dir() else 0
            return STATUS_INSTALLED, f"Geany active with {theme_count} dark themes & Copilot config"
        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_md_viewer() -> Tuple[str, str]:
        if shutil.which("md-viewer") or (USER_HOME / ".local" / "bin" / "md-viewer").is_file():
            return STATUS_INSTALLED, "Active (Pandoc + Surf WebKit with dark/light themes)"
        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_config_sync() -> Tuple[str, str]:
        local_dir = USER_HOME / "Debian-Dev-Backups"
        gdrive_dir = USER_HOME / "GoogleDrive" / "Debian-Dev-Backups"
        local_count = len(list(local_dir.glob("*.zip"))) if local_dir.is_dir() else 0
        gdrive_count = len(list(gdrive_dir.glob("*.zip"))) if gdrive_dir.is_dir() else 0
        total = local_count + gdrive_count
        if total > 0 or local_dir.is_dir():
            return STATUS_INSTALLED, f"Active ({local_count} local, {gdrive_count} cloud backup archives)"
        return STATUS_NOT_INSTALLED, "Not configured (run backup now)"

    @staticmethod
    def check_forgejo() -> Tuple[str, str]:
        try:
            res = subprocess.run(
                ["curl", "-s", "-f", "-m", "1", "http://127.0.0.1:3000/"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            if res.returncode == 0:
                return STATUS_INSTALLED, "Running on http://127.0.0.1:3000 (Loopback Only)"
        except Exception:
            pass

        forgejo_canonical = USER_HOME / ".local" / "share" / "dev-setups" / "forgejo"
        forgejo_legacy = REPO_ROOT / "Setup-Local-GitHub" / "forgejo-data"
        if (forgejo_canonical / "bin" / "forgejo").is_file() or (forgejo_legacy / "bin" / "forgejo").is_file() or (USER_HOME / ".local" / "bin" / "forgejo").is_file():
            return STATUS_STOPPED, "Installed & configured, but currently stopped"
        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_llama_cpp() -> Tuple[str, str]:
        cli_bin = USER_HOME / "llama.cpp" / "build" / "bin" / "llama-cli"
        alt_bin = USER_HOME / ".local" / "share" / "dev-setups" / "llama-cpp" / "build" / "bin" / "llama-cli"
        if (cli_bin.is_file() and os.access(cli_bin, os.X_OK)) or (alt_bin.is_file() and os.access(alt_bin, os.X_OK)):
            models_dir = USER_HOME / "models"
            alt_models = USER_HOME / ".local" / "share" / "dev-setups" / "llama-cpp" / "models"
            model_count = len(list(models_dir.glob("*.gguf"))) if models_dir.is_dir() else (len(list(alt_models.glob("*.gguf"))) if alt_models.is_dir() else 0)
            return STATUS_INSTALLED, f"Installed ({model_count} .gguf models)"
        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_llama_cpp_legacy() -> Tuple[str, str]:
        legacy_bin = USER_HOME / "llama.cpp-legacy" / "build" / "bin" / "llama-cli"
        alt_bin = USER_HOME / "llama.cpp" / "llama-cli"
        canonical_legacy = USER_HOME / ".local" / "share" / "dev-setups" / "llama-cpp-legacy" / "build" / "bin" / "llama-cli"
        if (legacy_bin.is_file() and os.access(legacy_bin, os.X_OK)) or (alt_bin.is_file() and os.access(alt_bin, os.X_OK)) or (canonical_legacy.is_file() and os.access(canonical_legacy, os.X_OK)):
            return STATUS_INSTALLED, "Installed (legacy low-RAM CPU build)"
        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_librechat() -> Tuple[str, str]:
        try:
            res = subprocess.run(
                ["curl", "-s", "-m", "1", "http://127.0.0.1:3080"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            if res.returncode in (0, 52):
                return STATUS_INSTALLED, "Running on http://127.0.0.1:3080 (0 Telemetry)"
        except Exception:
            pass

        has_docker = bool(shutil.which("docker"))

        # Check if docker containers are running
        if has_docker:
            try:
                ps_res = subprocess.run(
                    ["docker", "ps", "--filter", "name=librechat_app", "--filter", "status=running", "--format", "{{.Names}}"],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
                )
                if "librechat_app" in ps_res.stdout:
                    return STATUS_INSTALLED, "Containers active (Initializing / Ready on :3080)"
            except Exception:
                pass

        # Check if configured/installed in canonical or legacy path
        chat_canonical = USER_HOME / ".local" / "share" / "dev-setups" / "librechat"
        chat_dir = chat_canonical / "LibreChat"
        env_file = chat_canonical / ".env"
        legacy_env = REPO_ROOT / "Setup-Libre-Chat" / ".env"
        legacy_dir = REPO_ROOT / "Setup-Libre-Chat" / "LibreChat"

        if has_docker:
            try:
                ps_res = subprocess.run(
                    ["docker", "ps", "-a", "--filter", "name=librechat", "--format", "{{.Names}}"],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
                )
                if "librechat" in ps_res.stdout:
                    return STATUS_STOPPED, "Docker containers ready (Stopped)"
            except Exception:
                pass

        if chat_canonical.is_dir() or chat_dir.is_dir() or env_file.is_file() or legacy_env.is_file() or legacy_dir.is_dir():
            return STATUS_STOPPED, "Configured & ready, but currently stopped"

        compose_file = REPO_ROOT / "Setup-Libre-Chat" / "docker-compose.yml"
        if has_docker and (compose_file.is_file() or (chat_canonical / "docker-compose.yml").is_file()):
            has_compose = bool(shutil.which("docker-compose"))
            if not has_compose:
                try:
                    c_res = subprocess.run(["docker", "compose", "version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    has_compose = (c_res.returncode == 0)
                except Exception:
                    pass
            if has_compose:
                return STATUS_STOPPED, "Docker stack ready, click to start"

        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_gdrive() -> Tuple[str, str]:
        has_rclone = bool(shutil.which("rclone"))
        mount_dir = USER_HOME / "GoogleDrive"
        is_mounted = False
        try:
            res = subprocess.run(["mountpoint", "-q", str(mount_dir)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            is_mounted = (res.returncode == 0)
        except Exception:
            pass

        if has_rclone and is_mounted:
            return STATUS_INSTALLED, "Active & Mounted at ~/GoogleDrive"
        elif has_rclone:
            return STATUS_PARTIAL, "Rclone installed, but ~/GoogleDrive unmounted"
        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_virtualbox() -> Tuple[str, str]:
        if shutil.which("VirtualBox") or shutil.which("virtualbox"):
            try:
                out = subprocess.check_output(["VBoxManage", "--version"], text=True, stderr=subprocess.DEVNULL).strip()
                ver = out.split("r")[0].strip() if out else "installed"
            except Exception:
                ver = "installed"
            return STATUS_INSTALLED, f"VirtualBox ({ver}) installed with hardened GUI"
        return STATUS_NOT_INSTALLED, "Not installed"

    @staticmethod
    def check_sync_time() -> Tuple[str, str]:
        if shutil.which("sync-time") or Path("/usr/local/bin/sync-time").is_file():
            return STATUS_INSTALLED, "Installed globally (/usr/local/bin/sync-time)"
        return STATUS_NOT_INSTALLED, "Available (Setup-Sync-Time/sync-time.sh)"

    @staticmethod
    def check_brightness() -> Tuple[str, str]:
        if shutil.which("brightness-controller") or (USER_HOME / ".local" / "bin" / "brightness-controller").is_file():
            return STATUS_INSTALLED, "Active (Standalone GUI + CLI + X11 RandR & Backlight)"
        script = REPO_ROOT / "Setup-Brightness" / "brightness-controller.py"
        if script.is_file() and os.access(script, os.X_OK):
            return STATUS_INSTALLED, "Ready in Setup-Brightness/brightness-controller.py"
        return STATUS_NOT_INSTALLED, "Available"

    @staticmethod
    def check_deep_sleep() -> Tuple[str, str]:
        is_deep = False
        try:
            if os.path.exists("/sys/power/mem_sleep"):
                with open("/sys/power/mem_sleep", "r") as f:
                    if "[deep]" in f.read():
                        is_deep = True
            if os.path.exists("/etc/default/grub"):
                with open("/etc/default/grub", "r") as f:
                    if "mem_sleep_default=deep" in f.read():
                        is_deep = True
        except Exception:
            pass

        has_tlp = bool(shutil.which("tlp"))
        if is_deep and has_tlp:
            return STATUS_INSTALLED, "Active (Kernel S3 deep sleep + TLP battery optimization)"
        elif is_deep or has_tlp:
            return STATUS_PARTIAL, "Partially configured (S3 or TLP active)"
        return STATUS_NOT_INSTALLED, "Available (Setup-Deep-Sleep/setup-deep-sleep.sh)"

    @staticmethod
    def check_hinglish() -> Tuple[str, str]:
        has_mim = Path("/usr/share/m17n/hi-itrans.mim").is_file()
        has_ibus = bool(shutil.which("ibus"))
        has_pad = (USER_HOME / ".local" / "bin" / "hinglish-launch").is_file() or (REPO_ROOT / "Setup-Hinglish" / "easy-hindi-typing.sh").is_file()

        # Check if the Easy Hindi Typing localhost server is running on 127.0.0.1:8765
        is_server_running = False
        try:
            import socket
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(0.3)
                if s.connect_ex(("127.0.0.1", 8765)) == 0:
                    is_server_running = True
        except Exception:
            pass

        if not is_server_running:
            pid_file = Path("/tmp/easy_hindi_typing_server.pid")
            if pid_file.is_file():
                try:
                    pid = int(pid_file.read_text().strip())
                    if pid > 0:
                        os.kill(pid, 0)
                        is_server_running = True
                except Exception:
                    pass

        if is_server_running:
            ibus_info = " (IBus system active)" if (has_mim and has_ibus) else ""
            return STATUS_INSTALLED, f"Running on http://127.0.0.1:8765{ibus_info}"

        if has_mim and has_ibus:
            return STATUS_STOPPED, "Installed & IBus active, web server stopped (Click Start to launch)"
        elif has_pad:
            return STATUS_STOPPED, "Notepad installed, web server stopped (Click Start to launch)"

        return STATUS_NOT_INSTALLED, "Available"

    @staticmethod
    def check_detailed_conky() -> Tuple[str, str]:
        try:
            res = subprocess.run(["pgrep", "-x", "conky"], capture_output=True, text=True)
            if res.returncode == 0 and res.stdout.strip():
                pids = " ".join(res.stdout.split())
                return STATUS_INSTALLED, f"Active & Running (PID: {pids})"
        except Exception:
            pass
        autostart = USER_HOME / ".config" / "autostart" / "conky.desktop"
        conf = USER_HOME / ".config" / "conky" / "conky.conf"
        if autostart.is_file() and conf.is_file():
            return STATUS_INSTALLED, "Configured with Autostart (~/.config/conky/conky.conf)"
        script = REPO_ROOT / "Setup-Detailed-Conkey" / "Setup-Detailed-Conky.sh"
        if script.is_file():
            return STATUS_NOT_INSTALLED, "Ready to Install (Setup-Detailed-Conkey/Setup-Detailed-Conky.sh)"
        return STATUS_NOT_INSTALLED, "Available"

    @staticmethod
    def check_doctor() -> Tuple[str, str]:
        return STATUS_INSTALLED, "Diagnostic & Health Audit Suite Ready"


# Complete Master Module Registry with Rich Metadata & Upstream Component Attribution
MODULES_CONFIG: List[Dict[str, Any]] = [
    {
        "id": "doctor",
        "title": "Setup-Doctor",
        "category": "System & Hardware",
        "icon": "🩺",
        "tagline": "Master Diagnostic & System Health Audit",
        "description": "Performs an exhaustive audit of Linux kernel, CPU flags (AVX/AVX2), RAM/swap headroom, GPU/CUDA hardware acceleration, motherboard RTC battery state, and all installed suite components.",
        "tags": ["doctor", "audit", "system", "health", "diagnostic", "hardware", "cpu", "gpu"],
        "script_rel": "doctor.sh",
        "doc_file": "Setup-Doctor/README.md",
        "install_path": "Integrated Diagnostic Suite (CLI: ./doctor.sh)",
        "status_cmd": ["./doctor.sh"],
        "install_cmd": None,
        "uninstall_cmd": None,
        "requires_root": False,
        "launch_type": "console",
        "launch_cmd": "./doctor.sh",
        "install_guide": "Integrated master diagnostic suite. No installation needed; execute rootlessly from CLI or GUI manager anytime.",
        "uninstall_guide": "Read-only inspection framework; makes zero system alterations and installs no background daemons.",
        "upstream_components": [
            {
                "name": "GNU coreutils & util-linux",
                "author": "Free Software Foundation & Karel Zak et al.",
                "license": "GPL-3.0+",
                "role": "Kernel procfs/sysfs inspection (lscpu, uname, free, lsblk)",
                "upstream_url": "https://www.kernel.org/pub/linux/utils/util-linux/"
            },
            {
                "name": "pciutils & dmidecode",
                "author": "Martin Mares & Alan Cox",
                "license": "GPL-2.0+",
                "role": "Motherboard DMI, BIOS, and PCI GPU hardware detection",
                "upstream_url": "https://github.com/pciutils/pciutils"
            },
            {
                "name": "lm-sensors",
                "author": "Frodo Looijaard et al.",
                "license": "GPL-2.0+",
                "role": "Hardware thermal sensor inspection and voltage monitoring",
                "upstream_url": "https://github.com/lm-sensors/lm-sensors"
            }
        ],
        "check_func": ModuleDetector.check_doctor
    },
    {
        "id": "dev-tools",
        "title": "Setup-Dev-Tools",
        "category": "Core Developer",
        "icon": "⚡",
        "tagline": "Modern CLI Tools, Runtimes & Docker Suite",
        "description": "Installs curated high-performance development utilities: ripgrep (rg), fzf, bat/batcat, eza (modern ls), zoxide (cd memory), lazygit, uv (fast Python runtime), fnm (Fast Node Manager), Docker engine, and AI Copilot CLI.",
        "tags": ["tools", "cli", "git", "lazygit", "docker", "uv", "fnm", "ripgrep", "fzf", "bat", "eza", "zoxide"],
        "script_rel": "Setup-Dev-Tools/setup-dev-tools.sh",
        "doc_file": "Setup-Dev-Tools/README.md",
        "install_path": "/usr/local/bin & ~/.local/bin",
        "status_cmd": ["./Setup-Dev-Tools/setup-dev-tools.sh", "--status"],
        "install_cmd": ["./Setup-Dev-Tools/setup-dev-tools.sh", "--install"],
        "uninstall_cmd": ["./Setup-Dev-Tools/setup-dev-tools.sh", "--uninstall"],
        "requires_root": True,
        "launch_type": "terminal",
        "launch_cmd": "lazygit",
        "install_guide": "Installs modern developer binaries via APT and official upstream archives. Configures aliases in ~/.bashrc.",
        "uninstall_guide": "Removes installed packages and cleans up configuration aliases from shell profiles.",
        "upstream_components": [
            {
                "name": "ripgrep (rg)",
                "author": "Andrew Gallant (BurntSushi)",
                "license": "MIT / Unlicense",
                "role": "Ultra-fast recursive line-oriented regex search engine",
                "upstream_url": "https://github.com/BurntSushi/ripgrep"
            },
            {
                "name": "fzf",
                "author": "Junegunn Choi",
                "license": "MIT License",
                "role": "Interactive command-line fuzzy finder for files and history",
                "upstream_url": "https://github.com/junegunn/fzf"
            },
            {
                "name": "bat / batcat",
                "author": "David Peter (sharkdp)",
                "license": "Apache-2.0 / MIT",
                "role": "Cat clone with syntax highlighting, line numbers, and Git integration",
                "upstream_url": "https://github.com/sharkdp/bat"
            },
            {
                "name": "eza",
                "author": "eza-community",
                "license": "MIT License",
                "role": "Modern, maintained replacement for ls with colors and file icons",
                "upstream_url": "https://github.com/eza-community/eza"
            },
            {
                "name": "zoxide",
                "author": "Ajeet D'Souza",
                "license": "MIT License",
                "role": "Smarter cd command remembering most frequently visited folders",
                "upstream_url": "https://github.com/ajeetdsouza/zoxide"
            },
            {
                "name": "lazygit",
                "author": "Jesse Duffield",
                "license": "MIT License",
                "role": "Terminal UI for git commands with staging, rebasing, and branches",
                "upstream_url": "https://github.com/jesseduffield/lazygit"
            },
            {
                "name": "uv",
                "author": "Astral Software (Charlie Marsh)",
                "license": "MIT / Apache-2.0",
                "role": "Extremely fast Python package installer and virtual environment manager",
                "upstream_url": "https://github.com/astral-sh/uv"
            },
            {
                "name": "fnm",
                "author": "Gal Schlezinger (Schniz)",
                "license": "GPL-3.0",
                "role": "Fast Node Manager built in Rust",
                "upstream_url": "https://github.com/Schniz/fnm"
            },
            {
                "name": "Docker & Docker Compose",
                "author": "Docker Inc. & Community",
                "license": "Apache-2.0",
                "role": "Containerization engine and multi-container orchestration runtime",
                "upstream_url": "https://github.com/docker"
            }
        ],
        "check_func": ModuleDetector.check_dev_tools
    },
    {
        "id": "tmux",
        "title": "Setup-Tmux",
        "category": "Core Developer",
        "icon": "🖥️",
        "tagline": "Ergonomic Multiplexer with Mouse & Intuitive Splits",
        "description": "Pre-configured tmux terminal multiplexer with full click-and-drag mouse resizing, intuitive vertical/horizontal split hotkeys (| and -), persistent sessions, and a clean dark status bar.",
        "tags": ["tmux", "terminal", "multiplexer", "mouse", "splits", "session"],
        "script_rel": "Setup-Tmux/setup-tmux.sh",
        "doc_file": "Setup-Tmux/README.md",
        "install_path": "~/.tmux.conf",
        "status_cmd": ["./Setup-Tmux/setup-tmux.sh", "--status"],
        "install_cmd": ["./Setup-Tmux/setup-tmux.sh", "--install"],
        "uninstall_cmd": ["./Setup-Tmux/setup-tmux.sh", "--uninstall"],
        "requires_root": False,
        "launch_type": "terminal",
        "launch_cmd": "tmux",
        "install_guide": "Installs tmux via APT, creates ~/.tmux.conf with mouse support, intuitive split bindings (| and -), and status styling.",
        "uninstall_guide": "Restores previous ~/.tmux.conf backup and cleans configuration files.",
        "upstream_components": [
            {
                "name": "tmux",
                "author": "Nicholas Marriott and contributors",
                "license": "ISC License",
                "role": "Terminal multiplexer enabling persistent sessions, window tabs, and pane splits",
                "upstream_url": "https://github.com/tmux/tmux"
            }
        ],
        "check_func": ModuleDetector.check_tmux
    },
    {
        "id": "geany",
        "title": "Setup-Geany",
        "category": "Core Developer",
        "icon": "📝",
        "tagline": "Lightweight Developer IDE with Dark Themes & AI Copilot",
        "description": "Instant-start native C/GTK programmer editor configured with 15+ modern dark themes, project manager plugins, Git status integration, and AI coding assistant sidecar integration.",
        "tags": ["geany", "editor", "ide", "themes", "code", "copilot", "lightweight"],
        "script_rel": "Setup-Geany/setup-geany.sh",
        "doc_file": "Setup-Geany/README.md",
        "install_path": "~/.config/geany/",
        "status_cmd": ["./Setup-Geany/setup-geany.sh", "--status"],
        "install_cmd": ["./Setup-Geany/setup-geany.sh", "--install"],
        "uninstall_cmd": ["./Setup-Geany/setup-geany.sh", "--uninstall"],
        "requires_root": True,
        "launch_type": "gui",
        "launch_cmd": "geany",
        "install_guide": "Installs Geany and plugins via APT, downloads and activates 15+ modern dark color schemes (Darcula, Monokai, Obsidian, Dracula).",
        "uninstall_guide": "Removes installed color schemes and restores original Geany configuration.",
        "upstream_components": [
            {
                "name": "Geany",
                "author": "Enrico Tröger, Nick Treleaven, Matthew Brush et al.",
                "license": "GPL-2.0+",
                "role": "Fast, lightweight GTK programmer editor and IDE",
                "upstream_url": "https://www.geany.org"
            },
            {
                "name": "Geany-Plugins",
                "author": "Geany Community",
                "license": "GPL-2.0+",
                "role": "Git integration, project management, spell checking",
                "upstream_url": "https://plugins.geany.org"
            },
            {
                "name": "Geany Themes",
                "author": "Geany Themes Project",
                "license": "Various Open Source",
                "role": "Modern curated dark syntax themes",
                "upstream_url": "https://github.com/geany/geany-themes"
            }
        ],
        "check_func": ModuleDetector.check_geany
    },
    {
        "id": "md-viewer",
        "title": "Setup-MD-Viewer",
        "category": "Core Developer",
        "icon": "📖",
        "tagline": "Zero-Telemetry GitHub-Style Markdown Viewer",
        "description": "Fast local Markdown viewer powered by Pandoc and lightweight Surf WebKitGTK engine. Includes authentic GitHub Dark and Light themes with persistent toggle, instant live preview, and system file association.",
        "tags": ["markdown", "md", "viewer", "pandoc", "surf", "github", "docs"],
        "script_rel": "Setup-MD-Viewer/setup-md-viewer.sh",
        "doc_file": "Setup-MD-Viewer/README.md",
        "install_path": "/usr/local/bin/md-viewer & /usr/bin/surf",
        "status_cmd": ["./Setup-MD-Viewer/setup-md-viewer.sh", "--status"],
        "install_cmd": ["./Setup-MD-Viewer/setup-md-viewer.sh", "--install"],
        "uninstall_cmd": ["./Setup-MD-Viewer/setup-md-viewer.sh", "--uninstall"],
        "requires_root": True,
        "launch_type": "gui",
        "launch_cmd": "md-viewer README.md",
        "install_guide": "Compiles/installs suckless Surf WebKitGTK browser, pandoc markdown compiler, GitHub dark/light styling, and installs 'md-viewer' binary in /usr/local/bin.",
        "uninstall_guide": "Removes /usr/local/bin/md-viewer, cached stylesheets, and desktop file associations.",
        "upstream_components": [
            {
                "name": "Pandoc",
                "author": "John MacFarlane",
                "license": "GPL-2.0+",
                "role": "Universal document markup converter",
                "upstream_url": "https://github.com/jgm/pandoc"
            },
            {
                "name": "Surf",
                "author": "suckless.org community",
                "license": "MIT / X Consortium",
                "role": "Minimalist WebKitGTK browser engine for zero-telemetry local rendering",
                "upstream_url": "https://surf.suckless.org"
            },
            {
                "name": "GitHub Markdown CSS",
                "author": "Sindre Sorhus",
                "license": "MIT License",
                "role": "Authentic GitHub Dark & Light CSS presentation",
                "upstream_url": "https://github.com/sindresorhus/github-markdown-css"
            },
            {
                "name": "Highlight.js",
                "author": "Egor Khmelev and contributors",
                "license": "BSD-3-Clause",
                "role": "Client-side syntax highlighting for code fences",
                "upstream_url": "https://highlightjs.org"
            }
        ],
        "check_func": ModuleDetector.check_md_viewer
    },
    {
        "id": "config-sync",
        "title": "Setup-Config-Sync",
        "category": "Core Developer",
        "icon": "🔄",
        "tagline": "Dotfiles & Developer Settings Backup / Restore",
        "description": "Automated synchronization tool that packages your ~/.bashrc, ~/.gitconfig, ~/.tmux.conf, Geany settings, and LazyGit configurations into timestamped ZIP/TAR archives with optional Google Drive backup.",
        "tags": ["backup", "sync", "dotfiles", "bashrc", "gitconfig", "configs"],
        "script_rel": "Setup-Config-Sync/backup-dev-configs.sh",
        "doc_file": "Setup-Config-Sync/README.md",
        "install_path": "~/Debian-Dev-Backups/ & ~/GoogleDrive/",
        "status_cmd": ["./Setup-Config-Sync/backup-dev-configs.sh", "--status"],
        "install_cmd": ["./Setup-Config-Sync/backup-dev-configs.sh", "--install-aliases"],
        "uninstall_cmd": ["./Setup-Config-Sync/backup-dev-configs.sh", "--uninstall"],
        "requires_root": False,
        "launch_type": "console",
        "launch_cmd": "./Setup-Config-Sync/backup-dev-configs.sh --backup",
        "install_guide": "Installs shell aliases ('backup-configs', 'restore-configs') in ~/.bashrc for 1-click archiving of configs.",
        "uninstall_guide": "Removes alias bindings from ~/.bashrc.",
        "upstream_components": [
            {
                "name": "tar & gzip",
                "author": "Free Software Foundation",
                "license": "GPL-3.0+",
                "role": "Timestamped archive creation and compression",
                "upstream_url": "https://www.gnu.org/software/tar/"
            },
            {
                "name": "Rclone (optional)",
                "author": "Nick Craig-Wood",
                "license": "MIT License",
                "role": "Optional automated cloud backup synchronization",
                "upstream_url": "https://rclone.org"
            }
        ],
        "check_func": ModuleDetector.check_config_sync
    },
    {
        "id": "forgejo",
        "title": "Setup-Local-GitHub",
        "category": "Core Developer",
        "icon": "🐙",
        "tagline": "Private, Hardened Localhost-Only Forgejo Git Server",
        "description": "Self-hosted GitHub alternative powered by Forgejo (Gitea fork). Strictly isolated to 127.0.0.1:3000 with zero external telemetry, SQLite WAL embedded database, and cryptographically verified isolation.",
        "tags": ["git", "forgejo", "gitea", "github", "server", "localhost", "private", "offline"],
        "script_rel": "Setup-Local-GitHub/forgejo-localhost.sh",
        "doc_file": "Setup-Local-GitHub/README.md",
        "install_path": "~/.local/share/dev-setups/forgejo/",
        "status_cmd": ["./Setup-Local-GitHub/forgejo-localhost.sh", "--status"],
        "install_cmd": ["./Setup-Local-GitHub/forgejo-localhost.sh", "install"],
        "uninstall_cmd": ["./Setup-Local-GitHub/forgejo-localhost.sh", "uninstall"],
        "start_cmd": ["./Setup-Local-GitHub/forgejo-localhost.sh", "start"],
        "stop_cmd": ["./Setup-Local-GitHub/forgejo-localhost.sh", "stop"],
        "requires_root": False,
        "launch_type": "browser",
        "launch_url": "http://127.0.0.1:3000",
        "install_guide": "Downloads standalone Forgejo binary, creates dedicated service user, sets up SQLite WAL database, creates systemd/sysvinit service bound strictly to 127.0.0.1:3000.",
        "uninstall_guide": "Stops service, removes daemon, and backs up Git repositories and SQLite database.",
        "upstream_components": [
            {
                "name": "Forgejo",
                "author": "Codeberg e.V. & Forgejo Contributors (Gitea fork)",
                "license": "MIT License",
                "role": "Self-hosted, lightweight Git server with full web UI, issues, PRs, and wiki",
                "upstream_url": "https://forgejo.org"
            },
            {
                "name": "SQLite 3",
                "author": "D. Richard Hipp and contributors",
                "license": "Public Domain",
                "role": "Zero-configuration embedded SQL database with WAL journaling",
                "upstream_url": "https://sqlite.org"
            }
        ],
        "check_func": ModuleDetector.check_forgejo
    },
    {
        "id": "llama-cpp",
        "title": "Setup-LLAMA-CPP (Modern)",
        "category": "AI & Machine Learning",
        "icon": "🦙",
        "tagline": "High-Performance Local LLM Runtime (AVX2/CUDA)",
        "description": "Compiled C/C++ engine for executing local large language models (GGUF format). Tailored for multi-core CPUs with AVX2/AVX-512 instructions, Vulkan acceleration, and optional NVIDIA CUDA offloading.",
        "tags": ["ai", "llama", "llm", "gguf", "cuda", "vulkan", "avx", "chat"],
        "script_rel": "Setup-LLAMA-CPP/setup-LLAMA.CPP.sh",
        "doc_file": "Setup-LLAMA-CPP/README.md",
        "install_path": "~/llama.cpp/ (Binaries: ~/llama-bin/ & Models: ~/models/)",
        "status_cmd": ["./Setup-LLAMA-CPP/setup-LLAMA.CPP.sh", "--status"],
        "install_cmd": ["./Setup-LLAMA-CPP/setup-LLAMA.CPP.sh", "--install"],
        "uninstall_cmd": ["./Setup-LLAMA-CPP/setup-LLAMA.CPP.sh", "--uninstall"],
        "requires_root": False,
        "launch_type": "browser",
        "launch_url": "http://127.0.0.1:8080",
        "start_cmd": ["bash", "-c", "run-llama-server &"],
        "install_guide": "Builds high-performance llama.cpp C/C++ engine tailored to host CPU flags (AVX2/AVX-512) and GPU drivers (Vulkan/CUDA). Creates 'run-llama-server' launcher bound to 127.0.0.1:8080.",
        "uninstall_guide": "Removes compiled binaries and launchers from ~/.local/bin.",
        "upstream_components": [
            {
                "name": "llama.cpp",
                "author": "Georgi Gerganov and contributors",
                "license": "MIT License",
                "role": "C/C++ inference engine for quantized GGUF Large Language Models",
                "upstream_url": "https://github.com/ggerganov/llama.cpp"
            },
            {
                "name": "Vulkan SDK / CUDA Toolkit",
                "author": "Khronos Group / NVIDIA",
                "license": "Apache-2.0 / NVIDIA EULA",
                "role": "Hardware GPU tensor acceleration and compute offloading",
                "upstream_url": "https://www.vulkan.org"
            }
        ],
        "check_func": ModuleDetector.check_llama_cpp
    },
    {
        "id": "llama-cpp-legacy",
        "title": "Setup-LLAMA-CPP-LEGACY (Low-RAM)",
        "category": "AI & Machine Learning",
        "icon": "💾",
        "tagline": "Tuned Local LLM Engine for Older CPUs & Sub-4GB PCs",
        "description": "Specialized build of llama.cpp configured for older 64-bit dual-core processors, systems without modern AVX vector instructions, and budget devices with tight memory constraints.",
        "tags": ["ai", "legacy", "low-ram", "llama", "sub-4gb", "lightweight"],
        "script_rel": "Setup-LLAMA-CPP-LEGACY/setup-LLAMA.CPP.sh",
        "doc_file": "Setup-LLAMA-CPP-LEGACY/README.md",
        "install_path": "~/llama.cpp/ (Binaries: ~/llama-bin/ & Models: ~/models/)",
        "status_cmd": ["./Setup-Doctor/doctor.sh"],
        "install_cmd": ["./Setup-LLAMA-CPP-LEGACY/setup-LLAMA.CPP.sh", "--install"],
        "uninstall_cmd": ["./Setup-LLAMA-CPP-LEGACY/setup-LLAMA.CPP.sh", "--uninstall"],
        "requires_root": False,
        "launch_type": "console",
        "launch_cmd": "./Setup-Doctor/doctor.sh",
        "install_guide": "Builds specialized lightweight llama.cpp engine with AVX disabled for older CPUs (Intel Core 2 Duo, Pentium) and systems with <= 4GB RAM.",
        "uninstall_guide": "Removes compiled legacy binaries and build artifacts.",
        "upstream_components": [
            {
                "name": "llama.cpp (CPU baseline)",
                "author": "Georgi Gerganov and contributors",
                "license": "MIT License",
                "role": "Lightweight CPU-only GGUF runtime with low memory footprint",
                "upstream_url": "https://github.com/ggerganov/llama.cpp"
            }
        ],
        "check_func": ModuleDetector.check_llama_cpp_legacy
    },
    {
        "id": "librechat",
        "title": "Setup-Libre-Chat",
        "category": "AI & Machine Learning",
        "icon": "💬",
        "tagline": "Private ChatGPT-Style Web UI for Local & Remote AI",
        "description": "Turnkey ChatGPT-equivalent user interface bound strictly to localhost loopback (127.0.0.1:3080). Connects seamlessly to your local llama-server, Ollama, or OpenAI APIs with zero third-party telemetry.",
        "tags": ["chat", "librechat", "ui", "ai", "llm", "web", "localhost", "private"],
        "script_rel": "Setup-Libre-Chat/setup-librechat.sh",
        "doc_file": "Setup-Libre-Chat/README.md",
        "install_path": "~/.local/share/dev-setups/librechat/",
        "status_cmd": ["./Setup-Libre-Chat/setup-librechat.sh", "--status"],
        "install_cmd": ["./Setup-Libre-Chat/setup-librechat.sh", "--install"],
        "uninstall_cmd": ["./Setup-Libre-Chat/setup-librechat.sh", "--uninstall"],
        "start_cmd": ["./Setup-Libre-Chat/setup-librechat.sh", "--start"],
        "stop_cmd": ["./Setup-Libre-Chat/setup-librechat.sh", "--stop"],
        "requires_root": False,
        "launch_type": "browser",
        "launch_url": "http://127.0.0.1:3080",
        "install_guide": "Clones LibreChat, configures offline-first librechat.yaml with local llama-server endpoints, generates cryptographically secure secrets via openssl, starts via Docker Compose or native Node.js bound strictly to 127.0.0.1:3080.",
        "uninstall_guide": "Stops containers/services, removes systemd/docker configs, backs up MongoDB data.",
        "upstream_components": [
            {
                "name": "LibreChat",
                "author": "Danny Avila (danny-avila)",
                "license": "MIT License",
                "role": "Full-featured ChatGPT-style web UI with multi-model support, artifact rendering, and presets",
                "upstream_url": "https://github.com/danny-avila/LibreChat"
            },
            {
                "name": "MongoDB Community Server",
                "author": "MongoDB, Inc. / Docker Community",
                "license": "SSPL / Open Community",
                "role": "NoSQL persistence database for conversation history and user profiles",
                "upstream_url": "https://www.mongodb.com"
            },
            {
                "name": "Node.js & npm",
                "author": "OpenJS Foundation",
                "license": "MIT License",
                "role": "Server-side JavaScript runtime engine",
                "upstream_url": "https://nodejs.org"
            },
            {
                "name": "Meilisearch (optional)",
                "author": "Meilisearch Inc.",
                "license": "MIT License",
                "role": "Ultra-fast local full-text search engine for chat histories",
                "upstream_url": "https://www.meilisearch.com"
            }
        ],
        "check_func": ModuleDetector.check_librechat
    },
    {
        "id": "gdrive",
        "title": "Setup-GDrive",
        "category": "Cloud & Productivity",
        "icon": "☁️",
        "tagline": "On-Demand Google Drive Streaming via Rclone FUSE",
        "description": "Integrates Google Drive directly into ~/GoogleDrive using Rclone on-demand FUSE streaming. Files stream instantly without eating up local drive space. 100% open-source and privacy-respecting.",
        "tags": ["gdrive", "google", "drive", "cloud", "rclone", "fuse", "storage"],
        "script_rel": "Setup-GDrive/setup-GoogleDrive.sh",
        "doc_file": "Setup-GDrive/README.md",
        "install_path": "~/.config/rclone/ & ~/GoogleDrive/",
        "status_cmd": ["./Setup-GDrive/setup-GoogleDrive.sh", "--status"],
        "install_cmd": ["./Setup-GDrive/setup-GoogleDrive.sh", "--install"],
        "uninstall_cmd": ["./Setup-GDrive/setup-GoogleDrive.sh", "--uninstall"],
        "requires_root": False,
        "launch_type": "gui",
        "launch_cmd": f"xdg-open '{USER_HOME}/GoogleDrive'",
        "install_guide": "Installs Rclone, guides through Google Drive OAuth token configuration, creates on-demand FUSE mount at ~/GoogleDrive with background systemd user service.",
        "uninstall_guide": "Unmounts ~/GoogleDrive, disables systemd user service, and removes rclone config.",
        "upstream_components": [
            {
                "name": "Rclone",
                "author": "Nick Craig-Wood",
                "license": "MIT License",
                "role": "Cloud storage sync tool and FUSE filesystem driver",
                "upstream_url": "https://rclone.org"
            },
            {
                "name": "FUSE 3",
                "author": "Miklos Szeredi",
                "license": "LGPL-2.1 / GPL-2.0",
                "role": "Userspace filesystem layer for on-demand file streaming",
                "upstream_url": "https://github.com/libfuse/libfuse"
            }
        ],
        "check_func": ModuleDetector.check_gdrive
    },
    {
        "id": "virtualbox",
        "title": "Setup-Virtual-Box",
        "category": "Cloud & Productivity",
        "icon": "📦",
        "tagline": "Cryptographically Verified, Hardened VirtualBox with GUI",
        "description": "Automated installation of Oracle VirtualBox with verified SHA256 cryptographic signatures. Minimizes attack surface by omitting unnecessary network daemons and enforcing least-privilege user access.",
        "tags": ["virtualbox", "vm", "virtualization", "vbox", "hardened", "sandbox"],
        "script_rel": "Setup-Virtual-Box/setup_virtualbox_secure.sh",
        "doc_file": "Setup-Virtual-Box/README.md",
        "install_path": "/usr/bin/virtualbox (System Packages)",
        "status_cmd": ["./Setup-Virtual-Box/setup_virtualbox_secure.sh", "--status"],
        "install_cmd": ["./Setup-Virtual-Box/setup_virtualbox_secure.sh", "--install"],
        "uninstall_cmd": ["./Setup-Virtual-Box/setup_virtualbox_secure.sh", "--uninstall"],
        "requires_root": True,
        "launch_type": "gui",
        "launch_cmd": "virtualbox",
        "install_guide": "Verifies Oracle Debian APT repository cryptographic keys, installs VirtualBox, builds kernel modules (vboxdrv), and securely adds current user to vboxusers group without root privileges.",
        "uninstall_guide": "Removes VirtualBox packages, kernel modules, and APT repository configuration.",
        "upstream_components": [
            {
                "name": "VirtualBox",
                "author": "Oracle Corporation (formerly Sun / Innotek)",
                "license": "GPL-2.0 (base) / PUEL",
                "role": "x86 and AMD64/Intel64 enterprise-class desktop virtualization software",
                "upstream_url": "https://www.virtualbox.org"
            },
            {
                "name": "DKMS",
                "author": "Dell / Linux Community",
                "license": "GPL-2.0+",
                "role": "Dynamic Kernel Module Support for automatic rebuild on kernel updates",
                "upstream_url": "https://github.com/dell/dkms"
            }
        ],
        "check_func": ModuleDetector.check_virtualbox
    },
    {
        "id": "sync-time",
        "title": "Setup-Sync-Time",
        "category": "System & Hardware",
        "icon": "⏰",
        "tagline": "Robust CMOS Battery Fix & Multi-Stage Time Sync",
        "description": "Solves Motherboard CMOS Year 2008 clock failure rollbacks caused by exhausted RTC batteries. Utilizes HTTPS HTTP-date headers and fallback NTP pools with persistent systemd/SysVinit boot hooks.",
        "tags": ["time", "clock", "rtc", "cmos", "ntp", "sync", "battery", "fix"],
        "script_rel": "Setup-Sync-Time/sync-time.sh",
        "doc_file": "Setup-Sync-Time/README.md",
        "install_path": "/usr/local/bin/sync-time",
        "status_cmd": ["./Setup-Sync-Time/sync-time.sh", "--status"],
        "install_cmd": ["./Setup-Sync-Time/sync-time.sh", "--install"],
        "uninstall_cmd": ["./Setup-Sync-Time/sync-time.sh", "--uninstall"],
        "requires_root": True,
        "launch_type": "console",
        "launch_cmd": "./Setup-Sync-Time/sync-time.sh --status",
        "install_guide": "Installs HTTPS HTTP-Date recovery script and timedatectl/chrony NTP fallback hooks. Sets up systemd/SysVinit boot service to prevent Year 2008 clock failure rollbacks on exhausted CMOS RTC batteries.",
        "uninstall_guide": "Disables and removes time synchronization service and boot scripts.",
        "upstream_components": [
            {
                "name": "curl",
                "author": "Daniel Stenberg and contributors",
                "license": "curl license (MIT-compatible)",
                "role": "Fetches authoritative HTTP Date headers over TLS 1.3 even when system clock is wrong",
                "upstream_url": "https://curl.se"
            },
            {
                "name": "systemd-timesyncd / chrony",
                "author": "Lennart Poettering / Richard Curnow et al.",
                "license": "GPL-2.0+",
                "role": "Network Time Protocol (NTP) system time synchronization daemons",
                "upstream_url": "https://chrony-project.org"
            }
        ],
        "check_func": ModuleDetector.check_sync_time
    },
    {
        "id": "brightness",
        "title": "Setup-Brightness",
        "category": "System & Hardware",
        "icon": "☀️",
        "tagline": "Hardware Backlight + Software Gamma & Night Light",
        "description": "Standalone GUI and CLI display controller supporting dual engines: Hardware PWM backlight (brightnessctl/sysfs) and X11 RandR gamma control. Features blue-light warmth filter and system tray icon.",
        "tags": ["brightness", "display", "gamma", "nightlight", "monitor", "backlight"],
        "script_rel": "Setup-Brightness/setup-brightness.sh",
        "doc_file": "Setup-Brightness/README.md",
        "install_path": "/usr/local/bin/brightness-controller (or Setup-Brightness/)",
        "status_cmd": ["./Setup-Brightness/setup-brightness.sh", "--status"],
        "install_cmd": ["./Setup-Brightness/setup-brightness.sh", "--install"],
        "uninstall_cmd": ["./Setup-Brightness/setup-brightness.sh", "--uninstall"],
        "requires_root": True,
        "launch_type": "gui",
        "launch_cmd": f"python3 '{REPO_ROOT}/Setup-Brightness/brightness-controller.py'",
        "install_guide": "Installs hardware backlight control (brightnessctl with udev rules for rootless access) and software gamma control (xrandr) with warm night-light filter GUI.",
        "uninstall_guide": "Removes desktop shortcuts, udev backlight permissions, and autostart tray files.",
        "upstream_components": [
            {
                "name": "brightnessctl",
                "author": "hummerdell / systemd community",
                "license": "MIT License",
                "role": "Direct hardware PWM backlight control via Linux sysfs interface",
                "upstream_url": "https://github.com/Hummer12007/brightnessctl"
            },
            {
                "name": "xrandr",
                "author": "Keith Packard / X.Org Foundation",
                "license": "MIT License",
                "role": "Software-level color temperature and gamma correction for X11",
                "upstream_url": "https://gitlab.freedesktop.org/xorg/app/xrandr"
            },
            {
                "name": "PySide6 (Qt for Python)",
                "author": "The Qt Company",
                "license": "LGPLv3",
                "role": "Native desktop GUI slider and system tray integration",
                "upstream_url": "https://www.qt.io/qt-for-python"
            }
        ],
        "check_func": ModuleDetector.check_brightness
    },
    {
        "id": "deep-sleep",
        "title": "Setup-Deep-Sleep",
        "category": "System & Hardware",
        "icon": "🌙",
        "tagline": "Kernel S3 Deep Sleep & TLP Battery Optimization",
        "description": "Eliminates modern laptop overnight battery drain by forcing Linux kernel S3 suspend-to-RAM (mem_sleep_default=deep). Pairs with TLP power management for optimal battery life.",
        "tags": ["sleep", "suspend", "battery", "power", "tlp", "s3", "drain"],
        "script_rel": "Setup-Deep-Sleep/setup-deep-sleep.sh",
        "doc_file": "Setup-Deep-Sleep/README.md",
        "install_path": "/etc/systemd/system/ & /etc/tlp.d/",
        "status_cmd": ["./Setup-Deep-Sleep/setup-deep-sleep.sh", "--status"],
        "install_cmd": ["./Setup-Deep-Sleep/setup-deep-sleep.sh", "--install"],
        "uninstall_cmd": ["./Setup-Deep-Sleep/setup-deep-sleep.sh", "--uninstall"],
        "requires_root": True,
        "launch_type": "console",
        "launch_cmd": "./Setup-Deep-Sleep/setup-deep-sleep.sh --status",
        "install_guide": "Configures Linux kernel S3 suspend-to-RAM (mem_sleep_default=deep in GRUB) and installs TLP power management to eliminate overnight laptop standby drain.",
        "uninstall_guide": "Reverts GRUB boot parameters and removes TLP configuration overrides.",
        "upstream_components": [
            {
                "name": "Linux ACPI / S3 Subsystem",
                "author": "Linux Kernel Development Community",
                "license": "GPL-2.0",
                "role": "Hardware power management state (suspend-to-RAM vs modern standby)",
                "upstream_url": "https://www.kernel.org"
            },
            {
                "name": "TLP",
                "author": "Thomas Koch (linrunner)",
                "license": "GPL-2.0+",
                "role": "Advanced Linux power management daemon for battery optimization",
                "upstream_url": "https://linrunner.de/tlp/"
            }
        ],
        "check_func": ModuleDetector.check_deep_sleep
    },
    {
        "id": "hinglish",
        "title": "Setup-Hinglish",
        "category": "Cloud & Productivity",
        "icon": "🇮🇳",
        "tagline": "100% Offline Phonetic Hinglish-to-Hindi Typing",
        "description": "Complete local phonetic typing system powered by IBus m17n table (e.g. typing 'namaste' produces 'नमस्ते'). Completely offline with zero keylogging, zero telemetry, and standalone notepad web app.",
        "tags": ["hindi", "hinglish", "typing", "keyboard", "ibus", "m17n", "language"],
        "script_rel": "Setup-Hinglish/hinglish-to-hindi-typing.sh",
        "doc_file": "Setup-Hinglish/README.md",
        "install_path": "/usr/share/m17n/ & ~/.local/share/dev-setups/easy-hindi-typing/",
        "status_cmd": ["./Setup-Hinglish/hinglish-to-hindi-typing.sh", "--status"],
        "install_cmd": ["./Setup-Hinglish/hinglish-to-hindi-typing.sh", "--install"],
        "uninstall_cmd": ["./Setup-Hinglish/hinglish-to-hindi-typing.sh", "--uninstall"],
        "start_cmd": ["bash", "./Setup-Hinglish/easy-hindi-typing.sh", "start"],
        "stop_cmd": ["bash", "./Setup-Hinglish/easy-hindi-typing.sh", "stop"],
        "requires_root": True,
        "launch_type": "browser",
        "launch_url": "http://127.0.0.1:45678",
        "install_guide": "Installs IBus and m17n Hindi phonetic typing table (hi-phonetic) for instant system-wide transliteration. Includes lightweight offline web notepad bound strictly to 127.0.0.1:45678.",
        "uninstall_guide": "Removes ibus engine configurations and stops offline notepad service.",
        "upstream_components": [
            {
                "name": "IBus",
                "author": "Peng Huang and IBus project",
                "license": "LGPL-2.1+",
                "role": "Intelligent Input Bus framework for multilingual Linux typing",
                "upstream_url": "https://github.com/ibus/ibus"
            },
            {
                "name": "m17n-lib & m17n-db",
                "author": "National Institute of Advanced Industrial Science and Technology (AIST)",
                "license": "LGPL-2.1+",
                "role": "Multilingualization text processing engine and phonetic transliteration maps",
                "upstream_url": "https://www.nongnu.org/m17n/"
            }
        ],
        "check_func": ModuleDetector.check_hinglish
    },
    {
        "id": "detailed-conkey",
        "title": "Setup-Detailed-Conkey",
        "category": "System & Hardware",
        "icon": "📊",
        "tagline": "Obsidian Dark Glass System Monitor & Diagnostics",
        "description": "Comprehensive, privacy-first desktop system monitor. Highlights RAM Available vs Free distinction, battery wattage & health diagnostics, multi-threaded CPU per-core load, module-named thermal sensors (coretemp, nvme), disk I/O, network activity, and actionable top process tables.",
        "tags": ["conky", "system monitor", "ram", "battery", "cpu", "thermals", "desktop", "sensors"],
        "script_rel": "Setup-Detailed-Conkey/Setup-Detailed-Conky.sh",
        "doc_file": "Setup-Detailed-Conkey/README.md",
        "install_path": "~/.config/conky/conky.conf & ~/.config/autostart/",
        "status_cmd": ["./Setup-Detailed-Conkey/Setup-Detailed-Conky.sh", "--status"],
        "install_cmd": ["./Setup-Detailed-Conkey/Setup-Detailed-Conky.sh", "--install"],
        "uninstall_cmd": ["./Setup-Detailed-Conkey/Setup-Detailed-Conky.sh", "--uninstall"],
        "requires_root": False,
        "launch_type": "gui",
        "launch_cmd": f"'{REPO_ROOT}/Setup-Detailed-Conkey/Setup-Detailed-Conky.sh' --restart",
        "install_guide": "Installs Conky and dependencies, configures obsidian dark glass theme with real-time RAM available vs free, per-core CPU load, battery diagnostics, and thermal sensors.",
        "uninstall_guide": "Stops Conky process and removes desktop autostart configuration.",
        "upstream_components": [
            {
                "name": "Conky",
                "author": "Brenden Matthews, Philip Kovacs, and Conky contributors",
                "license": "GPL-3.0+",
                "role": "Lightweight, highly configurable system monitor for X11 and Wayland",
                "upstream_url": "https://github.com/brndnmtthws/conky"
            },
            {
                "name": "Lua",
                "author": "PUC-Rio (Roberto Ierusalimschy, Waldemar Celes, Luiz Henrique de Figueiredo)",
                "license": "MIT License",
                "role": "Embedded scripting language for custom calculations and sensor formatting",
                "upstream_url": "https://www.lua.org"
            }
        ],
        "check_func": ModuleDetector.check_detailed_conky
    }
]


class CleanNoFocusProxyStyle(QProxyStyle):
    """Modern cross-platform style proxy that completely eliminates dotted focus marquees and button label selection boxes."""

    def drawPrimitive(self, element, option, painter, widget=None):
        if element == QStyle.PrimitiveElement.PE_FrameFocusRect:
            return
        super().drawPrimitive(element, option, painter, widget)


class ModernStyleSheet:
    """Ultra-premium modern dark theme QSS styling."""

    MAIN_STYLE = f"""
    QMainWindow {{
        background-color: {COLOR_BG};
    }}

    QWidget {{
        color: {COLOR_TEXT};
        font-family: 'Inter', 'Ubuntu', 'DejaVu Sans', 'Liberation Sans', -apple-system, sans-serif;
        font-size: 13px;
    }}

    /* Global Label Transparency: Ensures text labels inherit parent block background seamlessly */
    QLabel {{
        background: transparent;
        background-color: transparent;
    }}

    /* Scroll Area and Inner Viewports must be transparent to avoid box artifacts */
    QScrollArea {{
        background: transparent;
        background-color: transparent;
        border: none;
    }}
    QScrollArea > QWidget > QWidget {{
        background: transparent;
        background-color: transparent;
    }}

    /* Scrollbars */
    QScrollBar:vertical {{
        background: {COLOR_BG};
        width: 8px;
        margin: 0px;
    }}
    QScrollBar::handle:vertical {{
        background: {COLOR_BORDER};
        min-height: 24px;
        border-radius: 4px;
    }}
    QScrollBar::handle:vertical:hover {{
        background: {COLOR_MUTED};
    }}
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
        height: 0px;
    }}

    /* Search Box */
    QLineEdit {{
        background-color: {COLOR_CARD};
        border: 1px solid {COLOR_BORDER};
        border-radius: 8px;
        padding: 7px 12px;
        color: {COLOR_TEXT};
        font-size: 13px;
    }}
    QLineEdit:focus {{
        border: 1px solid {COLOR_ACCENT};
        background-color: {COLOR_CARD_HOVER};
    }}

    /* Buttons: outline none and subtle translucent fill prevents focus marquee / label selection artifacts */
    QPushButton {{
        outline: none;
        background-color: rgba(255, 255, 255, 0.06);
        border: 1px solid {COLOR_BORDER};
        border-radius: 6px;
        padding: 5px 12px;
        color: {COLOR_TEXT};
        font-weight: 500;
        font-size: 12px;
    }}
    QPushButton:focus, QPushButton::focus {{
        outline: none;
        border-color: {COLOR_BORDER};
    }}
    QPushButton:hover {{
        background-color: rgba(255, 255, 255, 0.12);
        border-color: {COLOR_ACCENT};
    }}
    QPushButton:pressed {{
        background-color: rgba(255, 255, 255, 0.18);
    }}

    QPushButton.primary {{
        outline: none;
        background-color: {COLOR_ACCENT};
        border: 1px solid {COLOR_ACCENT};
        color: #ffffff;
        font-weight: 600;
    }}
    QPushButton.primary:focus {{
        outline: none;
    }}
    QPushButton.primary:hover {{
        background-color: {COLOR_ACCENT_HOVER};
    }}

    QPushButton.danger {{
        outline: none;
        background-color: rgba(244, 63, 94, 0.12);
        border: 1px solid rgba(244, 63, 94, 0.35);
        color: #fb7185;
    }}
    QPushButton.danger:focus {{
        outline: none;
    }}
    QPushButton.danger:hover {{
        background-color: rgba(244, 63, 94, 0.25);
        border-color: {COLOR_RED};
        color: #ffffff;
    }}

    QPushButton.filter-active {{
        outline: none;
        background-color: {COLOR_ACCENT};
        border: 1px solid {COLOR_ACCENT};
        color: #ffffff;
        font-weight: bold;
    }}
    QPushButton.filter-active:focus {{
        outline: none;
    }}

    /* Splitter Handle */
    QSplitter::handle {{
        background-color: {COLOR_BORDER};
        height: 5px;
    }}
    QSplitter::handle:hover {{
        background-color: {COLOR_ACCENT};
    }}

    /* Text Terminal */
    QTextEdit {{
        background-color: {COLOR_CONSOLE_BG};
        border: 1px solid {COLOR_BORDER};
        border-radius: 8px;
        color: #e2e8f0;
        font-family: 'JetBrains Mono', 'DejaVu Sans Mono', 'Noto Sans Mono', 'Liberation Mono', monospace;
        font-size: 12px;
        line-height: 1.4;
        padding: 8px 10px;
    }}

    /* Dialog styling */
    QDialog {{
        background-color: {COLOR_BG};
        color: {COLOR_TEXT};
    }}

    /* Tabs */
    QTabWidget::pane {{
        border: 1px solid #334155;
        border-radius: 8px;
        background-color: #1e293b;
        top: -1px;
    }}
    QTabBar::tab {{
        background-color: #0f172a;
        color: #94a3b8;
        border: 1px solid #334155;
        border-bottom: none;
        border-top-left-radius: 6px;
        border-top-right-radius: 6px;
        padding: 8px 16px;
        margin-right: 4px;
        font-weight: 600;
        font-size: 12px;
    }}
    QTabBar::tab:selected {{
        background-color: #1e293b;
        color: #38bdf8;
        border-bottom: 2px solid #38bdf8;
    }}
    QTabBar::tab:hover:!selected {{
        background-color: #1e293b;
        color: #f8fafc;
    }}

    /* Table Widget */
    QTableWidget {{
        background-color: #0f172a;
        border: 1px solid #334155;
        border-radius: 8px;
        gridline-color: #1e293b;
        color: #f8fafc;
        selection-background-color: #0284c7;
        font-size: 12px;
    }}
    QHeaderView::section {{
        background-color: #1e293b;
        color: #cbd5e1;
        padding: 6px 10px;
        font-weight: 700;
        font-size: 12px;
        border: 1px solid #334155;
    }}
    """


# Monogram Developer Badges (100% Native Vector Colors - Zero Font Dependencies)
MODULE_BADGES: Dict[str, Tuple[str, str]] = {
    "doctor": ("DOC", "#38bdf8"),
    "dev-tools": ("DEV", "#f59e0b"),
    "tmux": ("TMX", "#10b981"),
    "geany": ("IDE", "#a855f7"),
    "md-viewer": ("MD", "#3b82f6"),
    "config-sync": ("CFG", "#6366f1"),
    "forgejo": ("GIT", "#f97316"),
    "llama-cpp": ("LLM", "#ec4899"),
    "llama-cpp-legacy": ("CPU", "#06b6d4"),
    "librechat": ("CHAT", "#10b981"),
    "gdrive": ("DRV", "#2563eb"),
    "virtualbox": ("VM", "#d97706"),
    "sync-time": ("RTC", "#0891b2"),
    "brightness": ("DISP", "#eab308"),
    "deep-sleep": ("PWR", "#6366f1"),
    "hinglish": ("TYP", "#ea580c"),
    "detailed-conkey": ("CNK", "#8b5cf6"),
}


class ModuleCardWidget(QFrame):
    """Modern card view component representing an individual module."""

    action_triggered = Signal(str, str)  # (module_id, action_type)

    def __init__(self, module: Dict[str, Any], parent=None):
        super().__init__(parent)
        self.module = module
        self.status = STATUS_UNKNOWN
        self.status_text = "Checking..."
        self.setObjectName("moduleCard")
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)
        self.setup_ui()

    def setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(18, 16, 18, 16)
        layout.setSpacing(8)

        # Header: Monogram Tech Badge + Title + Category + Status Pill
        top_row = QHBoxLayout()
        top_row.setSpacing(12)

        badge_code, badge_color = MODULE_BADGES.get(self.module["id"], ("APP", "#0284c7"))
        badge_lbl = QLabel(badge_code)
        badge_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        badge_lbl.setFixedSize(42, 42)
        badge_lbl.setStyleSheet(f"""
            background-color: {badge_color}22;
            color: {badge_color};
            border: 1.5px solid {badge_color}66;
            border-radius: 9px;
            font-size: 13px;
            font-weight: 900;
            font-family: 'JetBrains Mono', 'DejaVu Sans Mono', 'Liberation Mono', monospace;
        """)
        top_row.addWidget(badge_lbl)

        title_col = QVBoxLayout()
        title_col.setSpacing(2)

        self.title_lbl = QLabel(self.module["title"])
        self.title_lbl.setStyleSheet(f"font-size: 16px; font-weight: bold; color: {COLOR_TEXT}; background: transparent;")
        title_col.addWidget(self.title_lbl)

        self.category_lbl = QLabel(self.module["category"])
        self.category_lbl.setStyleSheet(f"font-size: 11px; color: {COLOR_MUTED}; text-transform: uppercase; font-weight: 700; letter-spacing: 0.8px; background: transparent;")
        title_col.addWidget(self.category_lbl)
        top_row.addLayout(title_col)

        top_row.addStretch()

        # Status Badge Pill
        self.status_badge = QLabel(" AUDITING ")
        self.status_badge.setStyleSheet(f"""
            background-color: #334155;
            color: #cbd5e1;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: bold;
        """)
        top_row.addWidget(self.status_badge)
        layout.addLayout(top_row)

        # Tagline
        self.tagline_lbl = QLabel(self.module["tagline"])
        self.tagline_lbl.setStyleSheet(f"font-size: 13px; color: {COLOR_CYAN}; font-weight: 600; background: transparent;")
        self.tagline_lbl.setWordWrap(True)
        layout.addWidget(self.tagline_lbl)

        # Description (spacious, legible 13.5px text, natural wrapping)
        self.desc_lbl = QLabel(self.module["description"])
        self.desc_lbl.setStyleSheet(f"font-size: 13.5px; color: #cbd5e1; line-height: 1.45; background: transparent;")
        self.desc_lbl.setWordWrap(True)
        layout.addWidget(self.desc_lbl)

        # Installation Path
        path_box = QHBoxLayout()
        path_box.setSpacing(6)
        path_icon = QLabel("📍")
        path_icon.setStyleSheet("font-size: 11px; background: transparent;")
        path_box.addWidget(path_icon)
        install_path_str = self.module.get("install_path", "System / User Config")
        self.path_lbl = QLabel(f"Path: {install_path_str}")
        self.path_lbl.setStyleSheet("font-size: 11.5px; color: #38bdf8; font-family: monospace; font-weight: 500; background: transparent;")
        self.path_lbl.setWordWrap(True)
        path_box.addWidget(self.path_lbl)
        path_box.addStretch()
        layout.addLayout(path_box)

        # Status text summary line
        self.status_detail_lbl = QLabel("• Status: Inspecting system...")
        self.status_detail_lbl.setStyleSheet("font-size: 12.5px; color: #94a3b8; font-style: italic; background: transparent;")
        self.status_detail_lbl.setWordWrap(True)
        layout.addWidget(self.status_detail_lbl)

        # Separator line
        sep = QFrame()
        sep.setFrameShape(QFrame.Shape.HLine)
        sep.setStyleSheet(f"background-color: {COLOR_BORDER}; max-height: 1px; margin-top: 4px; margin-bottom: 2px;")
        layout.addWidget(sep)

        # Action Buttons Row
        self.btn_row = QHBoxLayout()
        self.btn_row.setSpacing(8)

        # Check Status Button
        self.btn_status = QPushButton("🔍 Status")
        self.btn_status.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_status.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_status.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 255, 255, 0.07);
                border: 1px solid {COLOR_BORDER};
                color: {COLOR_TEXT};
                border-radius: 6px;
                padding: 6px 14px;
                font-size: 12.5px;
                font-weight: 500;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: rgba(255, 255, 255, 0.15);
                border-color: {COLOR_ACCENT};
            }}
        """)
        self.btn_status.clicked.connect(lambda: self.action_triggered.emit(self.module["id"], "status"))
        self.btn_row.addWidget(self.btn_status)

        # Install Button
        if self.module.get("install_cmd"):
            self.btn_install = QPushButton("⬇ Install")
            self.btn_install.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            self.btn_install.setCursor(Qt.CursorShape.PointingHandCursor)
            self.btn_install.setStyleSheet(f"""
                QPushButton {{
                    background-color: {COLOR_ACCENT};
                    border: 1px solid {COLOR_ACCENT};
                    color: white;
                    font-weight: bold;
                    border-radius: 6px;
                    padding: 6px 14px;
                    font-size: 12.5px;
                    outline: none;
                }}
                QPushButton:hover {{
                    background-color: {COLOR_ACCENT_HOVER};
                    border-color: {COLOR_ACCENT_HOVER};
                }}
            """)
            self.btn_install.clicked.connect(lambda: self.action_triggered.emit(self.module["id"], "install"))
            self.btn_row.addWidget(self.btn_install)
        else:
            self.btn_install = None

        # Launch / Open Button
        self.btn_launch = QPushButton("🚀 Open")
        self.btn_launch.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_launch.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_launch.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(6, 182, 212, 0.12);
                border: 1px solid {COLOR_CYAN};
                color: {COLOR_CYAN};
                border-radius: 6px;
                padding: 6px 14px;
                font-size: 12.5px;
                font-weight: 600;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: rgba(6, 182, 212, 0.25);
                color: #ffffff;
            }}
        """)
        self.btn_launch.clicked.connect(lambda: self.action_triggered.emit(self.module["id"], "launch"))
        self.btn_row.addWidget(self.btn_launch)

        # Stop Button (for background services)
        if self.module.get("stop_cmd"):
            self.btn_stop = QPushButton("⏹ Stop")
            self.btn_stop.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            self.btn_stop.setCursor(Qt.CursorShape.PointingHandCursor)
            self.btn_stop.setStyleSheet(f"""
                QPushButton {{
                    background-color: rgba(245, 158, 11, 0.12);
                    border: 1px solid rgba(245, 158, 11, 0.4);
                    color: {COLOR_YELLOW};
                    border-radius: 6px;
                    padding: 6px 14px;
                    font-size: 12.5px;
                    font-weight: 600;
                    outline: none;
                }}
                QPushButton:hover {{
                    background-color: rgba(245, 158, 11, 0.25);
                    color: #ffffff;
                }}
            """)
            self.btn_stop.clicked.connect(lambda: self.action_triggered.emit(self.module["id"], "stop"))
            self.btn_stop.setVisible(False)
            self.btn_row.addWidget(self.btn_stop)
        else:
            self.btn_stop = None

        # Uninstall Button
        if self.module.get("uninstall_cmd"):
            self.btn_uninstall = QPushButton("🗑 Uninstall")
            self.btn_uninstall.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            self.btn_uninstall.setCursor(Qt.CursorShape.PointingHandCursor)
            self.btn_uninstall.setStyleSheet(f"""
                QPushButton {{
                    background-color: rgba(244, 63, 94, 0.12);
                    border: 1px solid rgba(244, 63, 94, 0.35);
                    color: #fb7185;
                    border-radius: 6px;
                    padding: 6px 14px;
                    font-size: 12.5px;
                    outline: none;
                }}
                QPushButton:hover {{
                    background-color: rgba(244, 63, 94, 0.25);
                    border-color: {COLOR_RED};
                    color: #ffffff;
                }}
            """)
            self.btn_uninstall.clicked.connect(lambda: self.action_triggered.emit(self.module["id"], "uninstall"))
            self.btn_row.addWidget(self.btn_uninstall)
        else:
            self.btn_uninstall = None

        self.btn_row.addStretch()

        # Details Button
        self.btn_info = QPushButton("ℹ Details")
        self.btn_info.setToolTip("Complete Module Specifications, Commands & Attribution")
        self.btn_info.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_info.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_info.setStyleSheet(f"""
            QPushButton {{
                background-color: transparent;
                border: 1px solid {COLOR_BORDER};
                border-radius: 6px;
                padding: 6px 14px;
                color: {COLOR_MUTED};
                font-size: 12px;
                font-weight: 500;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: {COLOR_CARD_HOVER};
                border-color: {COLOR_CYAN};
                color: {COLOR_TEXT};
            }}
        """)
        self.btn_info.clicked.connect(lambda: self.action_triggered.emit(self.module["id"], "info"))
        self.btn_row.addWidget(self.btn_info)

        layout.addLayout(self.btn_row)

        for btn in self.findChildren(QPushButton):
            btn.setFocusPolicy(Qt.FocusPolicy.NoFocus)

        self.update_card_style()

    def update_status(self, status: str, detail_text: str):
        self.status = status
        self.status_text = detail_text
        self.status_detail_lbl.setText(f"• Current: {detail_text}")

        is_doctor = (self.module.get("id") == "doctor")

        if is_doctor or status == STATUS_INSTALLED:
            badge_text = " ✔ RUNNING " if self.module.get("stop_cmd") else " ✔ INSTALLED "
            if is_doctor:
                badge_text = " ✔ READY "
            self.status_badge.setText(badge_text)
            self.status_badge.setStyleSheet(f"""
                background-color: rgba(16, 185, 129, 0.2);
                color: {COLOR_GREEN};
                border: 1px solid {COLOR_GREEN};
                padding: 4px 10px;
                border-radius: 12px;
                font-size: 11px;
                font-weight: bold;
            """)
            if self.btn_install:
                self.btn_install.setText("⟳ Reinstall")
                self.btn_install.setStyleSheet(f"""
                    QPushButton {{
                        background-color: rgba(255, 255, 255, 0.06);
                        border: 1px solid {COLOR_BORDER};
                        color: {COLOR_TEXT};
                        border-radius: 6px;
                        padding: 6px 14px;
                        font-size: 12.5px;
                        outline: none;
                    }}
                    QPushButton:hover {{
                        background-color: rgba(255, 255, 255, 0.14);
                        border-color: {COLOR_ACCENT};
                    }}
                """)
            if self.btn_uninstall:
                self.btn_uninstall.setVisible(True)
            if self.btn_launch:
                self.btn_launch.setVisible(True)
                self.btn_launch.setText("🚀 Run Audit" if is_doctor else "🚀 Open")
            if self.btn_stop:
                self.btn_stop.setVisible(True)
        elif status == STATUS_STOPPED:
            self.status_badge.setText(" ⏸ STOPPED ")
            self.status_badge.setStyleSheet(f"""
                background-color: rgba(6, 182, 212, 0.15);
                color: {COLOR_CYAN};
                border: 1px solid {COLOR_CYAN};
                padding: 4px 10px;
                border-radius: 12px;
                font-size: 11px;
                font-weight: bold;
            """)
            if self.btn_install:
                self.btn_install.setText("⟳ Reinstall")
                self.btn_install.setStyleSheet(f"""
                    QPushButton {{
                        background-color: rgba(255, 255, 255, 0.06);
                        border: 1px solid {COLOR_BORDER};
                        color: {COLOR_TEXT};
                        border-radius: 6px;
                        padding: 6px 14px;
                        font-size: 12.5px;
                        outline: none;
                    }}
                    QPushButton:hover {{
                        background-color: rgba(255, 255, 255, 0.14);
                        border-color: {COLOR_ACCENT};
                    }}
                """)
            if self.btn_uninstall:
                self.btn_uninstall.setVisible(True)
            if self.btn_launch:
                self.btn_launch.setVisible(True)
                self.btn_launch.setText("▶ Start & Open")
            if self.btn_stop:
                self.btn_stop.setVisible(False)
        elif status == STATUS_PARTIAL:
            self.status_badge.setText(" ⚠ PARTIAL ")
            self.status_badge.setStyleSheet(f"""
                background-color: rgba(245, 158, 11, 0.2);
                color: {COLOR_YELLOW};
                border: 1px solid {COLOR_YELLOW};
                padding: 4px 10px;
                border-radius: 12px;
                font-size: 11px;
                font-weight: bold;
            """)
            if self.btn_install:
                self.btn_install.setText("⬇ Complete Install")
                self.btn_install.setStyleSheet(f"""
                    QPushButton {{
                        background-color: {COLOR_ACCENT};
                        border: 1px solid {COLOR_ACCENT};
                        color: white;
                        font-weight: bold;
                        border-radius: 6px;
                        padding: 6px 14px;
                        font-size: 12.5px;
                        outline: none;
                    }}
                    QPushButton:hover {{
                        background-color: {COLOR_ACCENT_HOVER};
                        border-color: {COLOR_ACCENT_HOVER};
                    }}
                """)
            if self.btn_uninstall:
                self.btn_uninstall.setVisible(True)
            if self.btn_launch:
                self.btn_launch.setVisible(True)
                self.btn_launch.setText("▶ Start & Open" if self.module.get("start_cmd") else "🚀 Open")
            if self.btn_stop:
                self.btn_stop.setVisible(False)
        else:
            self.status_badge.setText(" ○ AVAILABLE ")
            self.status_badge.setStyleSheet(f"""
                background-color: rgba(148, 163, 184, 0.15);
                color: {COLOR_MUTED};
                border: 1px solid {COLOR_BORDER};
                padding: 4px 10px;
                border-radius: 12px;
                font-size: 11px;
                font-weight: bold;
            """)
            if self.btn_install:
                self.btn_install.setText("⬇ Install")
                self.btn_install.setStyleSheet(f"""
                    QPushButton {{
                        background-color: {COLOR_ACCENT};
                        border: 1px solid {COLOR_ACCENT};
                        color: white;
                        font-weight: bold;
                        border-radius: 6px;
                        padding: 6px 14px;
                        font-size: 12.5px;
                        outline: none;
                    }}
                    QPushButton:hover {{
                        background-color: {COLOR_ACCENT_HOVER};
                        border-color: {COLOR_ACCENT_HOVER};
                    }}
                """)
            if self.btn_uninstall:
                self.btn_uninstall.setVisible(False)
            if self.btn_launch:
                # If module has no install command, it is directly runnable
                if not self.module.get("install_cmd"):
                    self.btn_launch.setVisible(True)
                    self.btn_launch.setText("🚀 Run Audit" if is_doctor else "🚀 Run")
                else:
                    self.btn_launch.setVisible(False)
            if self.btn_stop:
                self.btn_stop.setVisible(False)

        for btn in self.findChildren(QPushButton):
            btn.setFocusPolicy(Qt.FocusPolicy.NoFocus)

        self.update_card_style()

    def update_card_style(self):
        border_color = COLOR_BORDER
        if self.status == STATUS_INSTALLED:
            border_color = "#1e3a47"
        elif self.status == STATUS_STOPPED:
            border_color = "#1b3842"
        elif self.status == STATUS_PARTIAL:
            border_color = "#42321c"

        self.setStyleSheet(f"""
            QFrame#moduleCard {{
                background-color: {COLOR_CARD};
                border: 1px solid {border_color};
                border-radius: 10px;
            }}
            QFrame#moduleCard:hover {{
                border-color: {COLOR_ACCENT};
                background-color: {COLOR_CARD_HOVER};
            }}
        """)


class ModuleDetailsDialog(QDialog):
    """Comprehensive, user-friendly details modal displaying complete specifications,
    CLI commands (install/uninstall/status/start/stop), third-party components & upstream attribution,
    and direct quick actions."""

    action_requested = Signal(str, str)  # (module_id, action)

    def __init__(self, module: Dict[str, Any], status: str, status_text: str, parent=None):
        super().__init__(parent)
        self.module = module
        self.status = status
        self.status_text = status_text
        self.setWindowTitle(f"Module Details — {module['title']}")
        self.resize(780, 620)
        self.setMinimumSize(700, 520)
        self.setStyleSheet(ModernStyleSheet.MAIN_STYLE)
        self.setup_ui()

    def setup_ui(self):
        root_layout = QVBoxLayout(self)
        root_layout.setContentsMargins(22, 20, 22, 20)
        root_layout.setSpacing(14)

        # Header Bar
        header = QHBoxLayout()
        header.setSpacing(14)

        badge_code, badge_color = MODULE_BADGES.get(self.module["id"], ("APP", "#0284c7"))
        badge_lbl = QLabel(badge_code)
        badge_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        badge_lbl.setFixedSize(48, 48)
        badge_lbl.setStyleSheet(f"""
            background-color: {badge_color}22;
            color: {badge_color};
            border: 2px solid {badge_color}77;
            border-radius: 10px;
            font-size: 15px;
            font-weight: 900;
            font-family: 'JetBrains Mono', 'DejaVu Sans Mono', monospace;
        """)
        header.addWidget(badge_lbl)

        title_col = QVBoxLayout()
        title_col.setSpacing(3)
        title_lbl = QLabel(f"{self.module['icon']} {self.module['title']}")
        title_lbl.setStyleSheet(f"font-size: 18px; font-weight: bold; color: {COLOR_TEXT}; background: transparent;")
        title_col.addWidget(title_lbl)

        tagline_lbl = QLabel(self.module["tagline"])
        tagline_lbl.setStyleSheet(f"font-size: 13px; color: {COLOR_CYAN}; font-weight: 600; background: transparent;")
        title_col.addWidget(tagline_lbl)
        header.addLayout(title_col)

        header.addStretch()

        # Status Pill
        status_pill = QLabel(f" {self.status} ")
        if self.status == STATUS_INSTALLED:
            status_style = f"background-color: rgba(16, 185, 129, 0.2); color: {COLOR_GREEN}; border: 1px solid {COLOR_GREEN};"
        elif self.status == STATUS_STOPPED:
            status_style = f"background-color: rgba(6, 182, 212, 0.15); color: {COLOR_CYAN}; border: 1px solid {COLOR_CYAN};"
        elif self.status == STATUS_PARTIAL:
            status_style = f"background-color: rgba(245, 158, 11, 0.2); color: {COLOR_YELLOW}; border: 1px solid {COLOR_YELLOW};"
        else:
            status_style = f"background-color: rgba(148, 163, 184, 0.15); color: {COLOR_MUTED}; border: 1px solid {COLOR_BORDER};"

        status_pill.setStyleSheet(f"""
            {status_style}
            padding: 5px 12px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: bold;
        """)
        header.addWidget(status_pill)
        root_layout.addLayout(header)

        # Tab Widget
        tabs = QTabWidget()

        # TAB 1: Overview & Architecture
        tab_overview = QWidget()
        tab_ov_layout = QVBoxLayout(tab_overview)
        tab_ov_layout.setContentsMargins(14, 14, 14, 14)
        tab_ov_layout.setSpacing(12)

        desc_box = QTextEdit()
        desc_box.setReadOnly(True)
        script_full = str(REPO_ROOT / self.module['script_rel'])
        root_req_text = "Required (APT packages / System configs)" if self.module.get("requires_root") else "None (User-space execution / Rootless)"

        launch_info = "N/A"
        if self.module.get("launch_url"):
            launch_info = f"<a href='{self.module['launch_url']}' style='color:{COLOR_CYAN}; font-weight:bold;'>{self.module['launch_url']}</a>"
        elif self.module.get("launch_cmd"):
            launch_info = f"<code>{self.module['launch_cmd']}</code> ({self.module.get('launch_type', 'CLI')})"

        ov_html = f"""
        <div style="font-size: 13.5px; line-height: 1.5; color: #f1f5f9;">
        <h3 style="color: {COLOR_TEXT}; margin-top: 0;">Overview</h3>
        <p>{self.module['description']}</p>
        <hr style="border: 0; border-top: 1px solid #334155; margin: 12px 0;">
        <table cellpadding="4" style="width: 100%; font-size: 12.5px;">
            <tr><td style="color: #94a3b8; width: 170px;"><b>Category:</b></td><td style="color: {COLOR_CYAN}; font-weight: 600;">{self.module['category']}</td></tr>
            <tr><td style="color: #94a3b8;"><b>Current State:</b></td><td style="color: #f8fafc;">{self.status_text}</td></tr>
            <tr><td style="color: #94a3b8;"><b>Installation Path:</b></td><td style="color: #38bdf8; font-family: monospace; font-weight: 600;">{self.module.get('install_path', 'System / User Config')}</td></tr>
            <tr><td style="color: #94a3b8;"><b>Module Script Path:</b></td><td><code>{script_full}</code></td></tr>
            <tr><td style="color: #94a3b8;"><b>Root Privileges:</b></td><td style="color: {'#fb7185' if self.module.get('requires_root') else '#34d399'}; font-weight: 600;">{root_req_text}</td></tr>
            <tr><td style="color: #94a3b8;"><b>Application Access:</b></td><td>{launch_info}</td></tr>
            <tr><td style="color: #94a3b8;"><b>Network Binding:</b></td><td style="color: #34d399; font-weight: 600;">127.0.0.1 (Strict Localhost Loopback Only)</td></tr>
            <tr><td style="color: #94a3b8;"><b>Telemetry Status:</b></td><td style="color: #34d399; font-weight: 600;">Absolute 0 Telemetry / Offline-First (No tracking/analytics)</td></tr>
            <tr><td style="color: #94a3b8;"><b>Init System Support:</b></td><td style="color: #38bdf8;">Dual Compatible (systemd & SysVinit / antiX / MX Linux)</td></tr>
        </table>
        </div>
        """
        desc_box.setHtml(ov_html)
        tab_ov_layout.addWidget(desc_box)
        tabs.addTab(tab_overview, "📋 Overview & Architecture")

        # TAB 2: CLI Commands & Controls
        tab_cli = QWidget()
        tab_cli_layout = QVBoxLayout(tab_cli)
        tab_cli_layout.setContentsMargins(14, 14, 14, 14)
        tab_cli_layout.setSpacing(10)

        cli_box = QTextEdit()
        cli_box.setReadOnly(True)

        status_cmd_str = ' '.join(self.module.get('status_cmd') or ['N/A'])
        install_cmd_str = ' '.join(self.module.get('install_cmd') or ['N/A'])
        uninstall_cmd_str = ' '.join(self.module.get('uninstall_cmd') or ['N/A'])
        start_cmd_str = ' '.join(self.module.get('start_cmd') or ['N/A'])
        stop_cmd_str = ' '.join(self.module.get('stop_cmd') or ['N/A'])

        sudo_prefix = "sudo " if self.module.get("requires_root") else ""

        cli_html = f"""
        <div style="font-size: 13px; line-height: 1.45; color: #f1f5f9;">
        <h3 style="color: {COLOR_TEXT}; margin-top: 0;">Command-Line Interface & Automated Control</h3>
        <p style="color: #94a3b8;">Every module in Debian Dev Suite is fully usable and automatable directly from the terminal without the GUI.</p>
        
        <div style="margin-bottom: 12px;">
            <b style="color: {COLOR_CYAN}; font-size: 13px;">1. Status Audit (Rootless)</b><br>
            <span style="color: #94a3b8; font-size: 12px;">Checks real-time prerequisites, services, ports, and configuration integrity.</span><br>
            <pre style="background: #090d16; border: 1px solid #334155; padding: 6px 10px; border-radius: 6px; color: #38bdf8;">cd {REPO_ROOT} && {status_cmd_str}</pre>
        </div>

        <div style="margin-bottom: 12px;">
            <b style="color: {COLOR_GREEN}; font-size: 13px;">2. Installation & Configuration</b><br>
            <span style="color: #94a3b8; font-size: 12px;">{self.module.get('install_guide', 'Installs and configures the module.')}</span><br>
            <pre style="background: #090d16; border: 1px solid #334155; padding: 6px 10px; border-radius: 6px; color: #4ade80;">cd {REPO_ROOT} && {sudo_prefix}{install_cmd_str}</pre>
        </div>

        <div style="margin-bottom: 12px;">
            <b style="color: #fb7185; font-size: 13px;">3. Clean Revert / Uninstallation</b><br>
            <span style="color: #94a3b8; font-size: 12px;">{self.module.get('uninstall_guide', 'Reverts changes and removes installed packages.')}</span><br>
            <pre style="background: #090d16; border: 1px solid #334155; padding: 6px 10px; border-radius: 6px; color: #fb7185;">cd {REPO_ROOT} && {sudo_prefix}{uninstall_cmd_str}</pre>
        </div>
        """

        if self.module.get("start_cmd"):
            cli_html += f"""
            <div style="margin-bottom: 12px;">
                <b style="color: {COLOR_YELLOW}; font-size: 13px;">4. Service Daemon Control (Start / Stop)</b><br>
                <span style="color: #94a3b8; font-size: 12px;">Start background service:</span><br>
                <pre style="background: #090d16; border: 1px solid #334155; padding: 6px 10px; border-radius: 6px; color: #fbbf24;">cd {REPO_ROOT} && {start_cmd_str}</pre>
                <span style="color: #94a3b8; font-size: 12px;">Stop background service:</span><br>
                <pre style="background: #090d16; border: 1px solid #334155; padding: 6px 10px; border-radius: 6px; color: #fbbf24;">cd {REPO_ROOT} && {stop_cmd_str}</pre>
            </div>
            """

        cli_html += "</div>"
        cli_box.setHtml(cli_html)
        tab_cli_layout.addWidget(cli_box)
        tabs.addTab(tab_cli, "⚙️ How to Install / Control (CLI)")

        # TAB 3: Third-Party Components & Attribution (Rule #5)
        tab_thirdparty = QWidget()
        tab_tp_layout = QVBoxLayout(tab_thirdparty)
        tab_tp_layout.setContentsMargins(14, 14, 14, 14)
        tab_tp_layout.setSpacing(10)

        tp_banner = QLabel("""
            <div style="background-color: rgba(56, 189, 248, 0.08); border: 1px solid rgba(56, 189, 248, 0.25); border-radius: 6px; padding: 10px; font-size: 12px; color: #cbd5e1; line-height: 1.4;">
                <b style="color: #38bdf8;">Respect for Upstream Open Source & Third-Party Authors:</b><br>
                Debian Dev Suite is an <b>orchestration, automation, configuration, and integration framework</b>.<br>
                The third-party open-source components below are credited with their original authors and licenses.
            </div>
        """)
        tp_banner.setWordWrap(True)
        tab_tp_layout.addWidget(tp_banner)

        components = self.module.get("upstream_components", [])
        if components:
            table = QTableWidget()
            table.setColumnCount(4)
            table.setHorizontalHeaderLabels(["Component", "Upstream Author", "License", "Integration Role"])
            table.setRowCount(len(components))
            table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
            table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
            table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
            table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
            table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
            table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
            table.setAlternatingRowColors(True)
            table.verticalHeader().setVisible(False)

            for row_idx, comp in enumerate(components):
                item_name = QTableWidgetItem(comp.get("name", ""))
                item_author = QTableWidgetItem(comp.get("author", ""))
                item_license = QTableWidgetItem(comp.get("license", ""))
                item_role = QTableWidgetItem(comp.get("role", ""))

                item_name.setForeground(QtGui.QBrush(QtGui.QColor(COLOR_CYAN)))
                item_author.setForeground(QtGui.QBrush(QtGui.QColor(COLOR_TEXT)))
                item_license.setForeground(QtGui.QBrush(QtGui.QColor(COLOR_YELLOW)))
                item_role.setForeground(QtGui.QBrush(QtGui.QColor("#cbd5e1")))

                table.setItem(row_idx, 0, item_name)
                table.setItem(row_idx, 1, item_author)
                table.setItem(row_idx, 2, item_license)
                table.setItem(row_idx, 3, item_role)

            tab_tp_layout.addWidget(table)
        else:
            no_tp = QLabel("No external third-party daemons; 100% native Debian Linux utilities and shell automation.")
            no_tp.setStyleSheet(f"color: {COLOR_MUTED}; font-style: italic; padding: 20px;")
            tab_tp_layout.addWidget(no_tp)

        tabs.addTab(tab_thirdparty, "🧩 Third-Party Components & Attribution")

        # TAB 4: Documentation (README.md)
        tab_doc = QWidget()
        tab_doc_layout = QVBoxLayout(tab_doc)
        tab_doc_layout.setContentsMargins(14, 14, 14, 14)
        tab_doc_layout.setSpacing(10)

        doc_box = QTextEdit()
        doc_box.setReadOnly(True)

        doc_rel = self.module.get("doc_file")
        doc_content = ""
        if doc_rel:
            doc_file = REPO_ROOT / doc_rel
            if doc_file.is_file():
                try:
                    with open(doc_file, "r", encoding="utf-8", errors="replace") as f:
                        doc_content = f.read()
                except Exception as e:
                    doc_content = f"Error reading {doc_file}: {e}"

        if doc_content:
            try:
                doc_box.setMarkdown(doc_content)
            except Exception:
                doc_box.setPlainText(doc_content)
        else:
            doc_box.setPlainText(f"No specific README.md found for {self.module['title']}.\nRefer to root README.md.")

        tab_doc_layout.addWidget(doc_box)
        tabs.addTab(tab_doc, "📖 README Documentation")

        root_layout.addWidget(tabs)

        # Dialog Footer Buttons Row
        footer = QHBoxLayout()
        footer.setSpacing(10)

        # Quick Action: Open / Start
        btn_open = QPushButton("🚀 Open / Start Application")
        btn_open.setCursor(Qt.CursorShape.PointingHandCursor)
        btn_open.setStyleSheet(f"""
            QPushButton {{
                background-color: {COLOR_ACCENT};
                border: 1px solid {COLOR_ACCENT};
                color: white;
                font-weight: bold;
                border-radius: 6px;
                padding: 7px 16px;
                font-size: 12.5px;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: {COLOR_ACCENT_HOVER};
            }}
        """)
        btn_open.clicked.connect(self.on_open_clicked)
        footer.addWidget(btn_open)

        # Quick Action: Run Status Audit
        btn_run_status = QPushButton("🔍 Run Status Audit")
        btn_run_status.setCursor(Qt.CursorShape.PointingHandCursor)
        btn_run_status.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 255, 255, 0.08);
                border: 1px solid {COLOR_BORDER};
                color: {COLOR_TEXT};
                border-radius: 6px;
                padding: 7px 14px;
                font-size: 12.5px;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: rgba(255, 255, 255, 0.16);
                border-color: {COLOR_CYAN};
            }}
        """)
        btn_run_status.clicked.connect(self.on_status_clicked)
        footer.addWidget(btn_run_status)

        # Quick Action: Open README in MD-Viewer if available
        if doc_rel and (REPO_ROOT / doc_rel).is_file():
            btn_md = QPushButton("📖 Open in MD-Viewer")
            btn_md.setCursor(Qt.CursorShape.PointingHandCursor)
            btn_md.setStyleSheet(f"""
                QPushButton {{
                    background-color: transparent;
                    border: 1px solid {COLOR_BORDER};
                    color: {COLOR_MUTED};
                    border-radius: 6px;
                    padding: 7px 12px;
                    font-size: 12px;
                    outline: none;
                }}
                QPushButton:hover {{
                    background-color: {COLOR_CARD_HOVER};
                    color: {COLOR_TEXT};
                    border-color: {COLOR_ACCENT};
                }}
            """)
            btn_md.clicked.connect(self.on_view_readme_clicked)
            footer.addWidget(btn_md)

        footer.addStretch()

        close_btn = QPushButton("Close")
        close_btn.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        close_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        close_btn.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 255, 255, 0.06);
                border: 1px solid {COLOR_BORDER};
                color: {COLOR_TEXT};
                padding: 7px 20px;
                border-radius: 6px;
                font-size: 12.5px;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: rgba(255, 255, 255, 0.14);
            }}
        """)
        close_btn.clicked.connect(self.accept)
        footer.addWidget(close_btn)

        root_layout.addLayout(footer)

    def on_open_clicked(self):
        self.action_requested.emit(self.module["id"], "launch")
        self.accept()

    def on_status_clicked(self):
        self.action_requested.emit(self.module["id"], "status")
        self.accept()

    def on_view_readme_clicked(self):
        doc_rel = self.module.get("doc_file")
        if doc_rel:
            doc_file = str(REPO_ROOT / doc_rel)
            if shutil.which("md-viewer"):
                subprocess.Popen(["md-viewer", doc_file], cwd=str(REPO_ROOT))
            elif shutil.which("xdg-open"):
                subprocess.Popen(["xdg-open", doc_file], cwd=str(REPO_ROOT))


class MainWindow(QMainWindow):
    """Main Application Window for Debian Dev Suite Manager."""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Debian Dev Suite — Master GUI Manager")
        self.resize(1180, 820)
        self.setMinimumSize(920, 640)

        # Process & state management
        self.current_process: Optional[QProcess] = None
        self.active_module_id: Optional[str] = None
        self.auto_scroll_enabled = True
        self.splitter: Optional[QSplitter] = None
        self.console_collapsed = False
        self.last_console_size = 220
        self._current_col_count = 2

        # Module widgets map
        self.module_cards: Dict[str, ModuleCardWidget] = {}
        self.current_filter_category = "All"
        self.search_query = ""

        # Setup Icon
        icon_path = SCRIPT_DIR / "debian-dev-suite.svg"
        if not icon_path.is_file():
            icon_path = SCRIPT_DIR / "debian-dev-manager.svg"
        if icon_path.is_file():
            self.setWindowIcon(QIcon(str(icon_path)))

        self.setup_ui()
        self.apply_styles()

        # Trigger Initial Status Scan asynchronously after window displays
        QTimer.singleShot(200, self.refresh_all_statuses)

    def setup_ui(self):
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(12, 10, 12, 10)
        main_layout.setSpacing(10)

        # ---------------------------------------------------------------------
        # 1. Top Dashboard Header Bar (Streamlined & Space-Efficient)
        # ---------------------------------------------------------------------
        header_frame = QFrame()
        header_frame.setObjectName("headerFrame")
        header_frame.setStyleSheet(f"""
            QFrame#headerFrame {{
                background-color: {COLOR_CARD};
                border: 1px solid {COLOR_BORDER};
                border-radius: 9px;
            }}
        """)
        header_layout = QVBoxLayout(header_frame)
        header_layout.setContentsMargins(12, 8, 12, 8)
        header_layout.setSpacing(6)

        # Row 1: App Branding & Primary Master Controls
        top_row = QHBoxLayout()
        top_row.setSpacing(12)

        # Branding
        brand_layout = QHBoxLayout()
        brand_layout.setSpacing(10)
        app_logo_lbl = QLabel()
        icon_file = SCRIPT_DIR / "debian-dev-suite.svg"
        if not icon_file.is_file():
            icon_file = SCRIPT_DIR / "debian-dev-manager.svg"
        if icon_file.is_file():
            app_logo_lbl.setPixmap(QIcon(str(icon_file)).pixmap(30, 30))
            app_logo_lbl.setStyleSheet("background: transparent;")
        else:
            app_logo_lbl.setText("⚙")
            app_logo_lbl.setStyleSheet("font-size: 20px; color: #38bdf8; background: transparent;")
        brand_layout.addWidget(app_logo_lbl)

        title_col = QVBoxLayout()
        title_col.setSpacing(0)
        app_title = QLabel("Debian Dev Suite Manager")
        app_title.setStyleSheet(f"font-size: 16px; font-weight: 800; color: {COLOR_TEXT}; letter-spacing: -0.3px; background: transparent;")
        
        app_subtitle = QLabel("Master Control Center • Zero-Telemetry • 100% Offline-First Orchestrator")
        app_subtitle.setStyleSheet(f"font-size: 11px; color: {COLOR_CYAN}; font-weight: 500; background: transparent;")
        title_col.addWidget(app_title)
        title_col.addWidget(app_subtitle)
        brand_layout.addLayout(title_col)
        top_row.addLayout(brand_layout)

        top_row.addStretch()

        # Action Buttons on Top Right
        self.btn_run_doctor = QPushButton("✦ Run Doctor Audit")
        self.btn_run_doctor.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_run_doctor.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_run_doctor.setStyleSheet(f"""
            QPushButton {{
                background-color: #0284c7;
                color: #ffffff;
                font-weight: bold;
                font-size: 12px;
                padding: 6px 14px;
                border-radius: 6px;
                border: 1px solid #38bdf8;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: #0369a1;
                border-color: #7dd3fc;
            }}
            QPushButton:pressed {{
                background-color: #075985;
            }}
        """)
        self.btn_run_doctor.clicked.connect(self.run_doctor_audit)
        top_row.addWidget(self.btn_run_doctor)

        self.btn_refresh = QPushButton("⟳ Refresh All")
        self.btn_refresh.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_refresh.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_refresh.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 255, 255, 0.06);
                color: {COLOR_TEXT};
                font-size: 12px;
                padding: 6px 12px;
                border: 1px solid {COLOR_BORDER};
                border-radius: 6px;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: rgba(255, 255, 255, 0.12);
                border-color: {COLOR_ACCENT};
            }}
            QPushButton:pressed {{
                background-color: rgba(255, 255, 255, 0.18);
            }}
        """)
        self.btn_refresh.clicked.connect(self.refresh_all_statuses)
        top_row.addWidget(self.btn_refresh)

        self.btn_top_console = QPushButton("💻 Console ▼")
        self.btn_top_console.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_top_console.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_top_console.setToolTip("Toggle Live Execution Console Visibility")
        self.btn_top_console.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 255, 255, 0.06);
                color: {COLOR_MUTED};
                font-size: 12px;
                padding: 6px 12px;
                border: 1px solid {COLOR_BORDER};
                border-radius: 6px;
                outline: none;
            }}
            QPushButton:hover {{
                color: {COLOR_TEXT};
                background-color: rgba(255, 255, 255, 0.12);
                border-color: {COLOR_ACCENT};
            }}
            QPushButton:pressed {{
                background-color: rgba(255, 255, 255, 0.18);
            }}
        """)
        self.btn_top_console.clicked.connect(self.toggle_console)
        top_row.addWidget(self.btn_top_console)

        header_layout.addLayout(top_row)

        # Row 2: Unified Specs Ribbon & Metric Summary Badges
        specs_row = QHBoxLayout()
        specs_row.setSpacing(8)

        sys_info = SystemInspector.get_system_summary()
        os_clean = sys_info['os'].replace("GNU/Linux", "").replace("Linux", "").strip()
        cpu_clean = re.sub(r"\(R\)|\(TM\)|CPU|@.*", "", sys_info['cpu']).strip()
        cpu_clean = re.sub(r"\s+", " ", cpu_clean)
        gpu_clean = sys_info['gpu'].replace("NVIDIA GeForce", "NVIDIA").replace("Intel(R) UHD Graphics", "Intel UHD").strip()
        init_clean = sys_info['init'].split("/")[0].strip()

        specs_text = (
            f"<span style='color:{COLOR_CYAN}; font-weight:600;'>OS:</span> {os_clean} ({init_clean}) &nbsp;•&nbsp; "
            f"<span style='color:{COLOR_CYAN}; font-weight:600;'>CPU:</span> {cpu_clean} &nbsp;•&nbsp; "
            f"<span style='color:{COLOR_CYAN}; font-weight:600;'>RAM:</span> {sys_info['ram']} &nbsp;•&nbsp; "
            f"<span style='color:{COLOR_CYAN}; font-weight:600;'>GPU:</span> {gpu_clean}"
        )
        self.specs_label = QLabel(specs_text)
        self.specs_label.setStyleSheet(f"""
            font-size: 11px;
            color: #94a3b8;
            background-color: rgba(255, 255, 255, 0.04);
            padding: 4px 10px;
            border-radius: 6px;
            border: 1px solid rgba(255, 255, 255, 0.08);
        """)
        self.specs_label.setTextFormat(Qt.TextFormat.RichText)
        specs_row.addWidget(self.specs_label, stretch=1)

        # Metric Statistics Pills
        self.stat_total = QLabel("Total: 16")
        self.stat_total.setStyleSheet(f"font-size: 11px; font-weight: 600; color: {COLOR_TEXT}; background-color: rgba(255, 255, 255, 0.04); padding: 4px 8px; border-radius: 6px; border: 1px solid rgba(255, 255, 255, 0.08);")
        specs_row.addWidget(self.stat_total)

        self.stat_installed = QLabel("✔ 0 Installed")
        self.stat_installed.setStyleSheet(f"font-size: 11px; font-weight: bold; color: {COLOR_GREEN}; background-color: rgba(16, 185, 129, 0.15); padding: 4px 8px; border-radius: 6px; border: 1px solid rgba(16, 185, 129, 0.3);")
        specs_row.addWidget(self.stat_installed)

        self.stat_partial = QLabel("⚠ 0 Partial")
        self.stat_partial.setStyleSheet(f"font-size: 11px; font-weight: bold; color: {COLOR_YELLOW}; background-color: rgba(245, 158, 11, 0.15); padding: 4px 8px; border-radius: 6px; border: 1px solid rgba(245, 158, 11, 0.3);")
        specs_row.addWidget(self.stat_partial)

        self.stat_available = QLabel("○ 0 Available")
        self.stat_available.setStyleSheet(f"font-size: 11px; font-weight: 600; color: {COLOR_MUTED}; background-color: rgba(255, 255, 255, 0.04); padding: 4px 8px; border-radius: 6px; border: 1px solid rgba(255, 255, 255, 0.08);")
        specs_row.addWidget(self.stat_available)

        header_layout.addLayout(specs_row)
        main_layout.addWidget(header_frame)

        # ---------------------------------------------------------------------
        # 2. Filter & Search Controls Bar
        # ---------------------------------------------------------------------
        filter_row = QHBoxLayout()
        filter_row.setSpacing(8)

        # Search Bar
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("🔍 Filter setups by name, command, or keyword...")
        self.search_input.setClearButtonEnabled(True)
        self.search_input.textChanged.connect(self.on_search_changed)
        filter_row.addWidget(self.search_input, stretch=2)

        # Category Filter Tabs (Clean labels without Qt accelerator ampersand collisions!)
        self.filter_buttons: Dict[str, QPushButton] = {}
        for cat_key, display_label in [
            ("All", "All (16)"),
            ("Core Developer", "Core Dev (6)"),
            ("AI & Machine Learning", "AI / ML (3)"),
            ("System & Hardware", "System / Hardware (4)"),
            ("Cloud & Productivity", "Cloud / Productivity (3)")
        ]:
            btn = QPushButton(display_label)
            btn.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            btn.clicked.connect(lambda checked, k=cat_key: self.on_category_selected(k))
            if cat_key == "All":
                btn.setProperty("class", "filter-active")
                btn.setStyleSheet(f"background-color: {COLOR_ACCENT}; color: white; font-weight: bold; border-radius: 6px; padding: 6px 12px; border: 1px solid {COLOR_ACCENT}; outline: none;")
            else:
                btn.setStyleSheet(f"background-color: {COLOR_CARD}; color: {COLOR_TEXT}; border-radius: 6px; padding: 6px 12px; border: 1px solid {COLOR_BORDER}; outline: none;")
            filter_row.addWidget(btn)
            self.filter_buttons[cat_key] = btn

        main_layout.addLayout(filter_row)

        # ---------------------------------------------------------------------
        # 3. Splitter: Upper Card Grid + Lower Live Terminal Console
        # ---------------------------------------------------------------------
        self.splitter = QSplitter(Qt.Orientation.Vertical)
        self.splitter.setChildrenCollapsible(False)

        # Upper Area: Scrollable Module Cards Grid
        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setFrameShape(QFrame.Shape.NoFrame)
        self.scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

        self.grid_container = QWidget()
        self.grid_layout = QGridLayout(self.grid_container)
        self.grid_layout.setContentsMargins(6, 6, 6, 6)
        self.grid_layout.setSpacing(14)
        self.grid_layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        # Populate cards in a responsive layout (strictly max 2 columns)
        self._current_col_count = 2
        for idx, mod in enumerate(MODULES_CONFIG):
            card = ModuleCardWidget(mod)
            card.action_triggered.connect(self.handle_module_action)
            self.module_cards[mod["id"]] = card
            row = idx // self._current_col_count
            col = idx % self._current_col_count
            self.grid_layout.addWidget(card, row, col)

        self.scroll_area.setWidget(self.grid_container)
        self.splitter.addWidget(self.scroll_area)

        # Lower Area: Live Embedded Terminal Console
        self.console_widget = QWidget()
        console_layout = QVBoxLayout(self.console_widget)
        console_layout.setContentsMargins(0, 4, 0, 0)
        console_layout.setSpacing(6)

        # Terminal Header Bar
        console_header = QHBoxLayout()
        console_header.setSpacing(10)

        term_title = QLabel("💻 Live Execution Console")
        term_title.setStyleSheet(f"font-weight: bold; font-size: 13px; color: {COLOR_TEXT}; background: transparent;")
        console_header.addWidget(term_title)

        self.execution_status_lbl = QLabel("● Ready")
        self.execution_status_lbl.setStyleSheet(f"font-size: 11px; color: {COLOR_GREEN}; font-weight: 600; background: transparent;")
        console_header.addWidget(self.execution_status_lbl)

        console_header.addStretch()

        self.btn_stop = QPushButton("⏹ Stop")
        self.btn_stop.setEnabled(False)
        self.btn_stop.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_stop.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_stop.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(244, 63, 94, 0.15);
                border: 1px solid rgba(244, 63, 94, 0.4);
                color: #fb7185;
                padding: 4px 10px;
                font-size: 11px;
                border-radius: 5px;
                outline: none;
            }}
            QPushButton:enabled:hover {{
                background-color: rgba(244, 63, 94, 0.3);
                border-color: {COLOR_RED};
                color: white;
            }}
            QPushButton:disabled {{
                color: #64748b;
                border-color: #334155;
                background-color: transparent;
            }}
        """)
        self.btn_stop.clicked.connect(self.stop_current_process)
        console_header.addWidget(self.btn_stop)

        self.btn_clear_console = QPushButton("🧹 Clear")
        self.btn_clear_console.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_clear_console.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_clear_console.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 255, 255, 0.05);
                border: 1px solid {COLOR_BORDER};
                color: {COLOR_MUTED};
                padding: 4px 10px;
                font-size: 11px;
                border-radius: 5px;
                outline: none;
            }}
            QPushButton:hover {{
                color: {COLOR_TEXT};
                background-color: rgba(255, 255, 255, 0.1);
                border-color: {COLOR_ACCENT};
            }}
        """)
        self.btn_clear_console.clicked.connect(self.clear_console)
        console_header.addWidget(self.btn_clear_console)

        self.btn_copy_console = QPushButton("📋 Copy Log")
        self.btn_copy_console.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_copy_console.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_copy_console.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 255, 255, 0.05);
                border: 1px solid {COLOR_BORDER};
                color: {COLOR_MUTED};
                padding: 4px 10px;
                font-size: 11px;
                border-radius: 5px;
                outline: none;
            }}
            QPushButton:hover {{
                color: {COLOR_TEXT};
                background-color: rgba(255, 255, 255, 0.1);
                border-color: {COLOR_ACCENT};
            }}
        """)
        self.btn_copy_console.clicked.connect(self.copy_console_output)
        console_header.addWidget(self.btn_copy_console)

        self.btn_toggle_console = QPushButton("▼ Collapse Console")
        self.btn_toggle_console.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_toggle_console.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_toggle_console.setStyleSheet(f"""
            QPushButton {{
                background-color: rgba(255, 255, 255, 0.05);
                border: 1px solid {COLOR_BORDER};
                color: {COLOR_CYAN};
                padding: 4px 10px;
                font-size: 11px;
                border-radius: 5px;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: rgba(255, 255, 255, 0.1);
                border-color: {COLOR_CYAN};
            }}
        """)
        self.btn_toggle_console.clicked.connect(self.toggle_console)
        console_header.addWidget(self.btn_toggle_console)

        console_layout.addLayout(console_header)

        # Embedded Console Output Text
        self.console_output = QTextEdit()
        self.console_output.setReadOnly(True)
        self.console_output.setPlaceholderText("Live shell output (installations, uninstalls, status diagnostics) will stream here in real time...")
        console_layout.addWidget(self.console_output)

        # Terminal Input Row for interactive prompts (e.g. typing [y/N] or choices)
        input_row = QHBoxLayout()
        input_row.setSpacing(8)
        self.terminal_input = QLineEdit()
        self.terminal_input.setPlaceholderText("Type command or response to send to running script (stdin)...")
        self.terminal_input.returnPressed.connect(self.send_terminal_input)
        input_row.addWidget(self.terminal_input)

        self.btn_send_input = QPushButton("Send Input")
        self.btn_send_input.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.btn_send_input.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_send_input.setStyleSheet(f"""
            QPushButton {{
                background-color: {COLOR_ACCENT};
                border: 1px solid {COLOR_ACCENT};
                color: white;
                font-weight: 600;
                padding: 6px 14px;
                border-radius: 6px;
                outline: none;
            }}
            QPushButton:hover {{
                background-color: {COLOR_ACCENT_HOVER};
            }}
        """)
        self.btn_send_input.clicked.connect(self.send_terminal_input)
        input_row.addWidget(self.btn_send_input)
        console_layout.addLayout(input_row)

        self.splitter.addWidget(self.console_widget)

        # Give maximum vertical height to module cards by default (75% cards, 25% console)
        self.splitter.setSizes([600, 160])
        main_layout.addWidget(self.splitter)

        # Ensure all existing buttons have NoFocus policy to eliminate Qt focus marquees
        for btn in self.findChildren(QPushButton):
            btn.setFocusPolicy(Qt.FocusPolicy.NoFocus)

    def apply_styles(self):
        self.setStyleSheet(ModernStyleSheet.MAIN_STYLE)

    # -------------------------------------------------------------------------
    # Responsive Reflow & Console Toggling
    # -------------------------------------------------------------------------
    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.reflow_grid()

    def reflow_grid(self):
        """Dynamically adjusts column count: strictly maximum 2 columns for clear card visibility."""
        if not hasattr(self, "scroll_area") or not hasattr(self, "grid_layout"):
            return
        width = self.scroll_area.width()
        cols = 2 if width >= 620 else 1
        if hasattr(self, "_current_col_count") and self._current_col_count == cols:
            return
        self._current_col_count = cols
        self.relayout_cards()

    def relayout_cards(self):
        """Lays out visible cards in strict 2-column or 1-column grid without blank gaps."""
        if not hasattr(self, "grid_layout"):
            return
        cols = getattr(self, "_current_col_count", 2)
        visible_idx = 0
        for mod in MODULES_CONFIG:
            card = self.module_cards.get(mod["id"])
            if card:
                self.grid_layout.removeWidget(card)
                if not card.isHidden():
                    r = visible_idx // cols
                    c = visible_idx % cols
                    self.grid_layout.addWidget(card, r, c)
                    visible_idx += 1

    def toggle_console(self):
        """Smoothly toggles the console between collapsed and expanded states."""
        if not self.splitter:
            return
        sizes = self.splitter.sizes()
        if sizes[1] > 45:
            # Collapse console
            self.last_console_size = sizes[1]
            self.splitter.setSizes([sizes[0] + sizes[1] - 38, 38])
            self.btn_toggle_console.setText("▲ Expand Console")
            self.btn_top_console.setText("💻 Console ▲")
            self.console_collapsed = True
        else:
            # Expand console
            target = getattr(self, "last_console_size", 220)
            if target < 140:
                target = 220
            total = sizes[0] + sizes[1]
            self.splitter.setSizes([max(300, total - target), target])
            self.btn_toggle_console.setText("▼ Collapse Console")
            self.btn_top_console.setText("💻 Console ▼")
            self.console_collapsed = False

    def ensure_console_expanded(self):
        """Ensures the console is open so live command execution is visible."""
        if not self.splitter:
            return
        sizes = self.splitter.sizes()
        if sizes[1] < 120:
            target = 240
            total = sizes[0] + sizes[1]
            self.splitter.setSizes([max(300, total - target), target])
            self.btn_toggle_console.setText("▼ Collapse Console")
            self.btn_top_console.setText("💻 Console ▼")
            self.console_collapsed = False

    # -------------------------------------------------------------------------
    # Filtering & Searching
    # -------------------------------------------------------------------------
    def on_search_changed(self, text: str):
        self.search_query = text.strip().lower()
        self.apply_card_filters()

    def on_category_selected(self, category: str):
        self.current_filter_category = category
        for cat, btn in self.filter_buttons.items():
            if cat == category:
                btn.setStyleSheet(f"background-color: {COLOR_ACCENT}; color: white; font-weight: bold; border-radius: 6px; padding: 6px 12px; border: 1px solid {COLOR_ACCENT}; outline: none;")
            else:
                btn.setStyleSheet(f"background-color: {COLOR_CARD}; color: {COLOR_TEXT}; border-radius: 6px; padding: 6px 12px; border: 1px solid {COLOR_BORDER}; outline: none;")
        self.apply_card_filters()

    def apply_card_filters(self):
        for mod in MODULES_CONFIG:
            card = self.module_cards.get(mod["id"])
            if not card:
                continue

            # Category filter
            matches_cat = (self.current_filter_category == "All") or (mod["category"] == self.current_filter_category)

            # Search query filter
            matches_search = True
            if self.search_query:
                haystack = f"{mod['title']} {mod['tagline']} {mod['description']} {' '.join(mod['tags'])} {card.status_text}".lower()
                matches_search = self.search_query in haystack

            card.setVisible(matches_cat and matches_search)

        self.relayout_cards()

    # -------------------------------------------------------------------------
    # Status Audit Engine
    # -------------------------------------------------------------------------
    def refresh_all_statuses(self):
        """Scans status for all modules and updates metric pills."""
        installed_count = 0
        partial_count = 0
        available_count = 0

        for mod in MODULES_CONFIG:
            card = self.module_cards.get(mod["id"])
            if not card:
                continue

            check_fn = mod.get("check_func")
            if check_fn:
                status, detail = check_fn()
                card.update_status(status, detail)
                if status in (STATUS_INSTALLED, STATUS_STOPPED):
                    installed_count += 1
                elif status == STATUS_PARTIAL:
                    partial_count += 1
                else:
                    available_count += 1

        self.stat_total.setText(f"Total: {len(MODULES_CONFIG)}")
        self.stat_installed.setText(f"✔ {installed_count} Installed")
        self.stat_partial.setText(f"⚠ {partial_count} Partial")
        self.stat_available.setText(f"○ {available_count} Available")

    def refresh_single_status(self, module_id: str):
        card = self.module_cards.get(module_id)
        if not card:
            return
        mod = card.module
        check_fn = mod.get("check_func")
        if check_fn:
            status, detail = check_fn()
            card.update_status(status, detail)

        installed_count = sum(1 for c in self.module_cards.values() if c.status in (STATUS_INSTALLED, STATUS_STOPPED))
        partial_count = sum(1 for c in self.module_cards.values() if c.status == STATUS_PARTIAL)
        available_count = sum(1 for c in self.module_cards.values() if c.status not in (STATUS_INSTALLED, STATUS_STOPPED, STATUS_PARTIAL))
        self.stat_installed.setText(f"✔ {installed_count} Installed")
        self.stat_partial.setText(f"⚠ {partial_count} Partial")
        self.stat_available.setText(f"○ {available_count} Available")

    # -------------------------------------------------------------------------
    # Command Execution Engine (QProcess)
    # -------------------------------------------------------------------------
    def execute_shell_command(self, cmd_args: List[str], working_dir: Path, module_id: Optional[str] = None):
        """Executes a shell command asynchronously and streams live output to terminal console."""
        if self.current_process and self.current_process.state() == QProcess.ProcessState.Running:
            QMessageBox.warning(
                self,
                "Process Already Running",
                "Another task is currently running in the console. Please wait for it to complete or click 'Stop'."
            )
            return

        # Auto-expand console so the user sees live execution immediately
        self.ensure_console_expanded()

        self.active_module_id = module_id
        cmd_str = " ".join(cmd_args)

        self.append_console_html(f"<br><b style='color:{COLOR_CYAN}'>[EXEC]</b> <span style='color:{COLOR_TEXT}'>{html.escape(cmd_str)}</span><br>")
        self.execution_status_lbl.setText(f"Running: {cmd_args[0]}...")
        self.execution_status_lbl.setStyleSheet(f"color: {COLOR_YELLOW}; font-weight: bold; background: transparent;")
        self.btn_stop.setEnabled(True)

        proc = QProcess(self)
        proc.setWorkingDirectory(str(working_dir))
        
        # Merge environment variables to guarantee UTF-8 and path discovery
        env = QtCore.QProcessEnvironment.systemEnvironment()
        env.insert("PYTHONUNBUFFERED", "1")
        env.insert("FORCE_COLOR", "1")
        env.insert("TERM", "xterm-256color")
        proc.setProcessEnvironment(env)

        proc.readyReadStandardOutput.connect(self.on_process_stdout)
        proc.readyReadStandardError.connect(self.on_process_stderr)
        proc.finished.connect(self.on_process_finished)

        # Launch process
        program = cmd_args[0]
        args = cmd_args[1:]
        proc.start(program, args)
        self.current_process = proc

    def on_process_stdout(self):
        if not self.current_process:
            return
        data = bytes(self.current_process.readAllStandardOutput().data()).decode("utf-8", errors="replace")
        formatted = ANSIColorConverter.to_html(data)
        self.append_console_html(formatted)

    def on_process_stderr(self):
        if not self.current_process:
            return
        data = bytes(self.current_process.readAllStandardError().data()).decode("utf-8", errors="replace")
        formatted = ANSIColorConverter.to_html(data)
        self.append_console_html(formatted)

    def on_process_finished(self, exit_code: int, exit_status):
        self.btn_stop.setEnabled(False)
        if exit_code == 0:
            self.execution_status_lbl.setText("Completed Successfully (exit code 0)")
            self.execution_status_lbl.setStyleSheet(f"color: {COLOR_GREEN}; font-weight: bold; background: transparent;")
            self.append_console_html(f"<br><b style='color:{COLOR_GREEN}'>[SUCCESS] Process completed with code 0</b><br>")
        else:
            self.execution_status_lbl.setText(f"Terminated with Exit Code {exit_code}")
            self.execution_status_lbl.setStyleSheet(f"color: {COLOR_RED}; font-weight: bold; background: transparent;")
            self.append_console_html(f"<br><b style='color:{COLOR_RED}'>[ERROR] Process exited with status code {exit_code}</b><br>")

        # Automatically refresh the status of the affected module
        if self.active_module_id:
            self.refresh_single_status(self.active_module_id)
        else:
            self.refresh_all_statuses()

        self.current_process = None
        self.active_module_id = None

    def stop_current_process(self):
        if self.current_process and self.current_process.state() == QProcess.ProcessState.Running:
            reply = QMessageBox.question(
                self,
                "Terminate Process",
                "Are you sure you want to stop the currently executing process?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if reply == QMessageBox.StandardButton.Yes:
                self.current_process.terminate()
                QTimer.singleShot(1500, lambda: self.current_process.kill() if self.current_process else None)
                self.append_console_html(f"<br><b style='color:{COLOR_RED}'>[STOPPED] Terminate signal sent by user.</b><br>")

    def send_terminal_input(self):
        text = self.terminal_input.text()
        if not text:
            return
        if self.current_process and self.current_process.state() == QProcess.ProcessState.Running:
            self.current_process.write((text + "\n").encode("utf-8"))
            self.append_console_html(f"<span style='color:{COLOR_MUTED}'>&gt; {html.escape(text)}</span><br>")
            self.terminal_input.clear()
        else:
            QMessageBox.information(self, "No Active Process", "No process is currently awaiting input in the terminal.", QMessageBox.StandardButton.Ok)

    def append_console_html(self, html_content: str):
        cursor = self.console_output.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        cursor.insertHtml(html_content.replace("\n", "<br>"))
        if self.auto_scroll_enabled:
            self.console_output.moveCursor(QTextCursor.MoveOperation.End)

    def clear_console(self):
        self.console_output.clear()
        self.execution_status_lbl.setText("Ready")
        self.execution_status_lbl.setStyleSheet(f"color: {COLOR_MUTED}; background: transparent;")

    def copy_console_output(self):
        text = self.console_output.toPlainText()
        QApplication.clipboard().setText(text)
        QMessageBox.information(self, "Copied", "Console output copied to clipboard.", QMessageBox.StandardButton.Ok)

    # -------------------------------------------------------------------------
    # Action Handlers
    # -------------------------------------------------------------------------
    def handle_module_action(self, module_id: str, action: str):
        card = self.module_cards.get(module_id)
        if not card:
            return
        mod = card.module

        if action == "status":
            cmd = mod.get("status_cmd")
            if cmd:
                self.execute_shell_command(cmd, REPO_ROOT, module_id)
            else:
                self.refresh_single_status(module_id)

        elif action == "install":
            self.trigger_install(mod)

        elif action == "uninstall":
            self.trigger_uninstall(mod)

        elif action == "launch":
            self.trigger_launch(mod)

        elif action == "stop":
            self.trigger_stop(mod)

        elif action == "info":
            self.show_module_info_dialog(mod)

    def trigger_install(self, module: Dict[str, Any]):
        cmd = module.get("install_cmd")
        if not cmd:
            QMessageBox.information(self, "Info", f"No automated install command defined for {module['title']}.", QMessageBox.StandardButton.Ok)
            return

        # Check if root is required and user is not root
        if module.get("requires_root") and os.geteuid() != 0:
            if shutil.which("pkexec"):
                wrapped_cmd = ["pkexec", "bash", str(REPO_ROOT / module["script_rel"]), "--install"]
            else:
                wrapped_cmd = ["sudo"] + cmd
        else:
            wrapped_cmd = cmd

        reply = QMessageBox.question(
            self,
            f"Install {module['title']}",
            f"Do you want to proceed with installing <b>{module['title']}</b>?<br><br>"
            f"<code>{' '.join(wrapped_cmd)}</code>",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if reply == QMessageBox.StandardButton.Yes:
            self.execute_shell_command(wrapped_cmd, REPO_ROOT, module["id"])

    def trigger_uninstall(self, module: Dict[str, Any]):
        cmd = module.get("uninstall_cmd")
        if not cmd:
            QMessageBox.information(self, "Info", f"No uninstaller available for {module['title']}.", QMessageBox.StandardButton.Ok)
            return

        if module.get("requires_root") and os.geteuid() != 0:
            if shutil.which("pkexec"):
                wrapped_cmd = ["pkexec", "bash", str(REPO_ROOT / module["script_rel"]), "--uninstall"]
            else:
                wrapped_cmd = ["sudo"] + cmd
        else:
            wrapped_cmd = cmd

        reply = QMessageBox.warning(
            self,
            f"Uninstall {module['title']}",
            f"Are you sure you want to clean uninstall <b>{module['title']}</b>?<br><br>"
            f"Command: <code>{' '.join(wrapped_cmd)}</code>",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if reply == QMessageBox.StandardButton.Yes:
            self.execute_shell_command(wrapped_cmd, REPO_ROOT, module["id"])

    @staticmethod
    def find_terminal_emulator() -> Optional[str]:
        candidates = [
            "x-terminal-emulator",
            "xfce4-terminal",
            "gnome-terminal",
            "konsole",
            "mate-terminal",
            "alacritty",
            "kitty",
            "tilix",
            "urxvt",
            "lxterminal",
            "xterm",
        ]
        for term in candidates:
            if shutil.which(term):
                return term
        return None

    def trigger_launch(self, module: Dict[str, Any]):
        card = self.module_cards.get(module["id"])
        is_stopped = (card and card.status in (STATUS_STOPPED, STATUS_PARTIAL))
        start_cmd = module.get("start_cmd")
        launch_type = module.get("launch_type")
        launch_url = module.get("launch_url")
        launch_cmd = module.get("launch_cmd")

        # 1. If service is stopped and has a start command, start it via console
        if start_cmd and is_stopped:
            self.ensure_console_expanded()
            self.append_console_html(f"<b style='color:{COLOR_CYAN}'>[START]</b> Starting service for {module['title']}...<br>")
            self.execute_shell_command(start_cmd, REPO_ROOT, module["id"])
            if launch_type == "browser" and launch_url:
                def delayed_browser():
                    import webbrowser
                    webbrowser.open(launch_url)
                QTimer.singleShot(2500, delayed_browser)
            return

        # 2. Browser apps:
        if launch_type == "browser" and launch_url:
            import webbrowser
            webbrowser.open(launch_url)
            self.append_console_html(f"<b style='color:{COLOR_CYAN}'>[LAUNCH]</b> Opened web interface: <a href='{launch_url}' style='color:{COLOR_CYAN}'>{launch_url}</a><br>")
            return

        # 3. GUI apps:
        if launch_type == "gui" and launch_cmd:
            try:
                subprocess.Popen(launch_cmd, shell=True, cwd=str(REPO_ROOT))
                self.append_console_html(f"<b style='color:{COLOR_CYAN}'>[LAUNCH]</b> Launched GUI application: {launch_cmd}<br>")
                return
            except Exception as e:
                QMessageBox.critical(self, "Launch Error", f"Failed to launch GUI application: {e}")
                return

        # 4. Terminal apps:
        if launch_type == "terminal" and launch_cmd:
            term = self.find_terminal_emulator()
            if term:
                try:
                    if term in ("gnome-terminal", "mate-terminal"):
                        subprocess.Popen([term, "--", "bash", "-c", f"{launch_cmd}; exec bash"], cwd=str(REPO_ROOT))
                    elif term == "konsole":
                        subprocess.Popen([term, "-e", "bash", "-c", f"{launch_cmd}; exec bash"], cwd=str(REPO_ROOT))
                    elif term == "xfce4-terminal":
                        subprocess.Popen([term, "--hold", "-e", launch_cmd], cwd=str(REPO_ROOT))
                    else:
                        subprocess.Popen([term, "-e", f"bash -c '{launch_cmd}; exec bash'"], cwd=str(REPO_ROOT))
                    self.append_console_html(f"<b style='color:{COLOR_CYAN}'>[LAUNCH]</b> Spawned {launch_cmd} in terminal ({term})<br>")
                    return
                except Exception as e:
                    self.append_console_html(f"<b style='color:{COLOR_YELLOW}'>[WARN]</b> Terminal launch failed ({e}), running in embedded console...<br>")

            # Fallback to embedded console
            self.ensure_console_expanded()
            self.execute_shell_command(["bash", "-c", launch_cmd], REPO_ROOT, module["id"])
            return

        # 5. Console scripts (like doctor, sync-time, config-sync):
        if launch_type == "console" or (not launch_type and launch_cmd):
            self.ensure_console_expanded()
            cmd = ["bash", "-c", launch_cmd] if launch_cmd else module.get("status_cmd", ["echo", "Ready"])
            self.execute_shell_command(cmd, REPO_ROOT, module["id"])
            return

        # 6. Fallback: run status check in console
        status_cmd = module.get("status_cmd")
        if status_cmd:
            self.ensure_console_expanded()
            self.execute_shell_command(status_cmd, REPO_ROOT, module["id"])

    def trigger_stop(self, module: Dict[str, Any]):
        cmd = module.get("stop_cmd")
        if not cmd:
            return
        self.ensure_console_expanded()
        self.append_console_html(f"<b style='color:{COLOR_YELLOW}'>[STOP]</b> Stopping service for {module['title']}...<br>")
        self.execute_shell_command(cmd, REPO_ROOT, module["id"])

    def run_doctor_audit(self):
        """Runs the complete master doctor.sh diagnostic suite."""
        doctor_script = REPO_ROOT / "doctor.sh"
        if not doctor_script.is_file():
            doctor_script = REPO_ROOT / "Setup-Doctor" / "doctor.sh"
        self.ensure_console_expanded()
        self.execute_shell_command(["bash", str(doctor_script)], REPO_ROOT)

    def show_module_info_dialog(self, module: Dict[str, Any]):
        card = self.module_cards.get(module["id"])
        status = card.status if card else STATUS_UNKNOWN
        status_text = card.status_text if card else "Unknown"

        dialog = ModuleDetailsDialog(module, status, status_text, self)
        dialog.action_requested.connect(self.handle_module_action)
        dialog.exec()


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("Debian Dev Suite Manager")
    app.setStyle(CleanNoFocusProxyStyle("Fusion"))
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
