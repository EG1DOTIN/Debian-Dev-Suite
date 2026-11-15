#!/usr/bin/env python3
"""
Brightness & Color Controller for Debian & Linux Systems
Part of the Debian Dev Suite 

Ultra-lightweight, 100% open-source, standalone display brightness and night light controller.
- 0 Telemetry / 100% Localhost & Offline Execution
- Dual Engine: Hardware PWM Backlight (brightnessctl/sysfs) + Universal Software Gamma (xrandr)
- Multi-Monitor Support: Per-display independent or synchronized adjustments
- Blue Light Filter / Night Light Warmth Slider (3000K–6500K color temperature)
- Secure Input Sanitization & Blackout-Lockout Prevention (clamped safe bounds)
- System Tray Icon with Scroll-Wheel Brightness Adjustment
- CLI Interface for Keyboard Shortcut Bindings & Persistent Session Restore
"""

import sys
import os
import re
import json
import subprocess
import glob
import argparse
from typing import Dict, List, Tuple, Optional

# Ensure safe XDG_RUNTIME_DIR for PySide6 / Qt in minimal/SysVinit environments
if "XDG_RUNTIME_DIR" not in os.environ or not os.path.exists(os.environ["XDG_RUNTIME_DIR"]):
    _temp_runtime = f"/tmp/runtime-{os.getuid()}"
    try:
        os.makedirs(_temp_runtime, mode=0o700, exist_ok=True)
        os.environ["XDG_RUNTIME_DIR"] = _temp_runtime
    except Exception:
        pass

CONFIG_DIR = os.path.expanduser("~/.config/brightness-controller")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")

# Safety constraints (prevent screen blackouts or invalid X11 gamma)
MIN_SOFTWARE_BRIGHTNESS = 0.10  # 10% minimum to prevent pitch-black lockouts
MAX_SOFTWARE_BRIGHTNESS = 1.50  # 150% maximum
MIN_HW_BACKLIGHT = 1            # 1% minimum
MAX_HW_BACKLIGHT = 100
MIN_GAMMA = 0.10
MAX_GAMMA = 2.00

NAME_REGEX = re.compile(r"^[A-Za-z0-9_\-]+$")


class DisplayManager:
    """Manages display detection and xrandr brightness / gamma operations."""

    @staticmethod
    def get_connected_displays() -> List[Dict]:
        """Queries xrandr for connected outputs and their current brightness/gamma."""
        displays = []
        try:
            res = subprocess.run(
                ["xrandr", "--verbose"],
                capture_output=True,
                text=True,
                check=False
            )
            if res.returncode != 0:
                return displays

            current_disp = None
            for line in res.stdout.splitlines():
                # Matches: "eDP-1 connected primary 1920x1080..." or "HDMI-1 connected (normal..."
                m = re.match(r"^([A-Za-z0-9_\-]+)\s+connected(?:\s+(primary))?", line)
                if m:
                    name = m.group(1)
                    if NAME_REGEX.match(name):
                        is_primary = bool(m.group(2))
                        current_disp = {
                            "name": name,
                            "primary": is_primary,
                            "brightness": 1.0,
                            "gamma": [1.0, 1.0, 1.0],
                            "warmth": 0
                        }
                        displays.append(current_disp)
                elif current_disp and "Brightness:" in line:
                    try:
                        b_val = float(line.split(":")[1].strip())
                        current_disp["brightness"] = max(MIN_SOFTWARE_BRIGHTNESS, min(MAX_SOFTWARE_BRIGHTNESS, b_val))
                    except ValueError:
                        pass
                elif current_disp and "Gamma:" in line:
                    try:
                        g_parts = line.split(":")[1].strip().split(":")
                        if len(g_parts) == 3:
                            current_disp["gamma"] = [
                                max(MIN_GAMMA, min(MAX_GAMMA, float(g_parts[0]))),
                                max(MIN_GAMMA, min(MAX_GAMMA, float(g_parts[1]))),
                                max(MIN_GAMMA, min(MAX_GAMMA, float(g_parts[2])))
                            ]
                    except (ValueError, IndexError):
                        pass
        except Exception:
            pass

        # Fallback if xrandr verbose output was empty or failed to parse
        if not displays:
            try:
                res = subprocess.run(["xrandr", "--current"], capture_output=True, text=True, check=False)
                for line in res.stdout.splitlines():
                    m = re.match(r"^([A-Za-z0-9_\-]+)\s+connected(?:\s+(primary))?", line)
                    if m and NAME_REGEX.match(m.group(1)):
                        displays.append({
                            "name": m.group(1),
                            "primary": bool(m.group(2)),
                            "brightness": 1.0,
                            "gamma": [1.0, 1.0, 1.0],
                            "warmth": 0
                        })
            except Exception:
                pass

        return displays

    @staticmethod
    def apply_display_settings(display: str, brightness: float, gamma: Tuple[float, float, float]) -> bool:
        """Safely applies brightness and gamma to a specific display using xrandr and syncs MX Linux."""
        if not NAME_REGEX.match(display):
            return False

        b_safe = max(MIN_SOFTWARE_BRIGHTNESS, min(MAX_SOFTWARE_BRIGHTNESS, float(brightness)))
        g_r = max(MIN_GAMMA, min(MAX_GAMMA, float(gamma[0])))
        g_g = max(MIN_GAMMA, min(MAX_GAMMA, float(gamma[1])))
        g_b = max(MIN_GAMMA, min(MAX_GAMMA, float(gamma[2])))

        gamma_str = f"{g_r:.3f}:{g_g:.3f}:{g_b:.3f}"
        bright_str = f"{b_safe:.2f}"

        # If gamma is neutral daylight (1.0:1.0:1.0), omit --gamma to avoid NVIDIA Prime / X11 driver glitch
        if abs(g_r - 1.0) < 0.005 and abs(g_g - 1.0) < 0.005 and abs(g_b - 1.0) < 0.005:
            cmd = ["xrandr", "--output", display, "--brightness", bright_str]
        else:
            cmd = ["xrandr", "--output", display, "--brightness", bright_str, "--gamma", gamma_str]

        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=False)
            success = (res.returncode == 0)
            if success:
                # Synchronize with MX Linux's MX-Tweak software brightness system if directory or parent exists
                mx_tweak_dir = os.path.expanduser("~/.config/MX-Linux/MX-Tweak/brightness")
                if os.path.exists(os.path.dirname(mx_tweak_dir)):
                    try:
                        os.makedirs(mx_tweak_dir, exist_ok=True)
                        mx_file = os.path.join(mx_tweak_dir, display)
                        with open(mx_file, "w") as f:
                            f.write(f"xrandr --output {display} --brightness {bright_str} --gamma {gamma_str}\n")
                    except Exception:
                        pass
            return success
        except Exception:
            return False


class HardwareBacklightManager:
    """Manages laptop hardware backlight via brightnessctl or /sys/class/backlight."""

    @staticmethod
    def get_backlight_devices() -> List[Dict]:
        """Discovers all available kernel backlight devices."""
        devices = []
        for path in glob.glob("/sys/class/backlight/*"):
            dev_name = os.path.basename(path)
            if not NAME_REGEX.match(dev_name):
                continue
            max_p = os.path.join(path, "max_brightness")
            cur_p = os.path.join(path, "brightness")
            if os.path.exists(max_p) and os.path.exists(cur_p):
                try:
                    with open(max_p, "r") as f:
                        max_val = int(f.read().strip())
                    with open(cur_p, "r") as f:
                        cur_val = int(f.read().strip())
                    pct = round((cur_val / max_val) * 100) if max_val > 0 else 100
                    writable = os.access(cur_p, os.W_OK)
                    devices.append({
                        "device": dev_name,
                        "path": path,
                        "current": cur_val,
                        "max": max_val,
                        "percent": max(1, min(100, pct)),
                        "writable": writable
                    })
                except Exception:
                    pass
        return devices

    @staticmethod
    def is_writable() -> bool:
        """Tests whether hardware backlight can be modified rootlessly."""
        devs = HardwareBacklightManager.get_backlight_devices()
        if not devs:
            return False
        # Direct sysfs test
        if any(d.get("writable") for d in devs):
            return True
        # Check if brightnessctl is SUID root
        which_res = subprocess.run(["which", "brightnessctl"], capture_output=True, text=True, check=False)
        if which_res.returncode == 0:
            bctl_path = which_res.stdout.strip()
            if os.path.exists(bctl_path) and (os.stat(bctl_path).st_mode & 0o4000):
                return True
        return False

    @staticmethod
    def set_backlight_percent(percent: int, device: Optional[str] = None, allow_pkexec: bool = False) -> bool:
        """Sets hardware backlight brightness percent (1-100%)."""
        pct = max(MIN_HW_BACKLIGHT, min(MAX_HW_BACKLIGHT, int(percent)))
        # Priority 1: Use brightnessctl if installed (handles udev/SUID/setgid permissions)
        if subprocess.run(["which", "brightnessctl"], capture_output=True).returncode == 0:
            cmd = ["brightnessctl", "set", f"{pct}%"]
            if device and NAME_REGEX.match(device):
                cmd.extend(["-d", device])
            res = subprocess.run(cmd, capture_output=True, text=True, check=False)
            if res.returncode == 0:
                return True

        # Priority 2: Direct sysfs write if writable
        devs = HardwareBacklightManager.get_backlight_devices()
        target_devs = [d for d in devs if (device is None or d["device"] == device)]
        for dev in target_devs:
            if dev.get("writable"):
                try:
                    target_val = int(round((pct / 100.0) * dev["max"]))
                    target_val = max(1, min(dev["max"], target_val))
                    with open(os.path.join(dev["path"], "brightness"), "w") as f:
                        f.write(f"{target_val}\n")
                    return True
                except Exception:
                    pass

        # Priority 3: pkexec brightnessctl (if allowed/requested)
        if allow_pkexec and subprocess.run(["which", "pkexec"], capture_output=True).returncode == 0:
            if subprocess.run(["which", "brightnessctl"], capture_output=True).returncode == 0:
                cmd = ["pkexec", "brightnessctl", "set", f"{pct}%"]
                if device and NAME_REGEX.match(device):
                    cmd.extend(["-d", device])
                res = subprocess.run(cmd, capture_output=True, text=True, check=False)
                if res.returncode == 0:
                    return True

        return False


class WarmthEngine:
    """Calculates RGB gamma multipliers for night light warmth (3000K-6500K)."""

    @staticmethod
    def warmth_to_rgb(warmth_pct: int) -> Tuple[float, float, float]:
        """
        Converts warmth percentage (0-100%) to RGB gamma multipliers.
        0%   = 6500K (Daylight / Neutral): 1.0, 1.0, 1.0
        50%  = ~4500K (Gentle Evening):    1.0, 0.88, 0.70
        100% = ~3000K (Candle / Night):    1.0, 0.74, 0.42
        """
        w = max(0, min(100, warmth_pct)) / 100.0
        r = 1.0
        g = round(1.0 - (0.26 * w), 3)
        b = round(1.0 - (0.58 * w), 3)
        return (r, g, b)


class ProfileManager:
    """Handles loading and saving user brightness profiles."""

    @staticmethod
    def save_profile(data: Dict) -> bool:
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            # Write atomically with 0600 permissions
            temp_path = CONFIG_FILE + ".tmp"
            with open(temp_path, "w") as f:
                json.dump(data, f, indent=2)
            os.chmod(temp_path, 0o600)
            os.replace(temp_path, CONFIG_FILE)
            return True
        except Exception:
            return False

    @staticmethod
    def load_profile() -> Optional[Dict]:
        if not os.path.exists(CONFIG_FILE):
            return None
        try:
            with open(CONFIG_FILE, "r") as f:
                return json.load(f)
        except Exception:
            return None


PRESETS = {
    "day": {"name": "Daylight ☀️", "software_pct": 100, "hw_pct": 100, "warmth": 0, "desc": "100% Brightness • Pure Daylight (6500K)"},
    "office": {"name": "Office 💻", "software_pct": 80, "hw_pct": 80, "warmth": 15, "desc": "80% Brightness • Balanced Work Focus"},
    "evening": {"name": "Evening 🌆", "software_pct": 55, "hw_pct": 55, "warmth": 45, "desc": "55% Brightness • Relaxing Gentle Warmth"},
    "night": {"name": "Night 🌙", "software_pct": 35, "hw_pct": 35, "warmth": 75, "desc": "35% Brightness • High Blue Light Filter"},
    "ultradim": {"name": "Ultra-Dim 🕶️", "software_pct": 15, "hw_pct": 10, "warmth": 85, "desc": "15% Software Dimming • Pitch-Dark Room Reading"}
}


# ==============================================================================
# ==============================================================================
# PySide6 (Qt6 - Official LGPLv3) GUI Engine
# ==============================================================================

def launch_gui():
    """Initializes and runs the GUI using PySide6 (Qt6 - Official LGPLv3)."""
    try:
        import PySide6.QtWidgets as QtWidgets
        import PySide6.QtCore as QtCore
        import PySide6.QtGui as QtGui
        backend_info = "PySide6 (Qt6 - Official LGPLv3)"
    except ImportError:
        # Check if project root .venv has PySide6 available
        repo_venv = Path(__file__).resolve().parent.parent / ".venv" / "bin" / "python3"
        if repo_venv.is_file() and os.access(repo_venv, os.X_OK) and sys.executable != str(repo_venv):
            os.execv(str(repo_venv), [str(repo_venv)] + sys.argv)
        print("[-] Error: PySide6 is required for the GUI.")
        print("    Install PySide6: sudo apt install python3-pyside6.qtwidgets")
        print("    Or run: ./setup-brightness.sh --install")
        print("    You can still use the CLI interface: brightness-control --help")
        sys.exit(1)

    QApplication = QtWidgets.QApplication
    QMainWindow = QtWidgets.QMainWindow
    QWidget = QtWidgets.QWidget
    QVBoxLayout = QtWidgets.QVBoxLayout
    QHBoxLayout = QtWidgets.QHBoxLayout
    QLabel = QtWidgets.QLabel
    QSlider = QtWidgets.QSlider
    QPushButton = QtWidgets.QPushButton
    QTabWidget = QtWidgets.QTabWidget
    QCheckBox = QtWidgets.QCheckBox
    QSystemTrayIcon = QtWidgets.QSystemTrayIcon
    QMenu = QtWidgets.QMenu
    QMessageBox = QtWidgets.QMessageBox
    QGroupBox = QtWidgets.QGroupBox

    Qt = QtCore.Qt
    QIcon = QtGui.QIcon
    QAction = QtGui.QAction
    QtHorizontal = getattr(getattr(Qt, "Orientation", None), "Horizontal", getattr(Qt, "Horizontal", None))
    QtAlignCenter = getattr(getattr(Qt, "AlignmentFlag", None), "AlignCenter", getattr(Qt, "AlignCenter", None))

    app = QApplication(sys.argv)
    app.setApplicationName("Brightness & Color Controller")
    app.setQuitOnLastWindowClosed(False)

    # Dark Theme Stylesheet matching Debian Dev Suite aesthetics
    DARK_STYLE = """
    QMainWindow, QWidget {
        background-color: #181825;
        color: #cdd6f4;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        font-size: 13px;
    }
    QTabWidget::pane {
        border: 1px solid #313244;
        border-radius: 8px;
        background-color: #1e1e2e;
        padding: 10px;
    }
    QTabBar::tab {
        background: #181825;
        color: #a6adc8;
        padding: 8px 18px;
        margin-right: 4px;
        border-top-left-radius: 6px;
        border-top-right-radius: 6px;
        border: 1px solid #313244;
        border-bottom: none;
        font-weight: 600;
    }
    QTabBar::tab:selected {
        background: #1e1e2e;
        color: #89dceb;
        border-bottom: 2px solid #89b4fa;
    }
    QGroupBox {
        border: 1px solid #313244;
        border-radius: 8px;
        margin-top: 18px;
        font-weight: bold;
        color: #89b4fa;
        padding: 12px;
    }
    QGroupBox::title {
        subcontrol-origin: margin;
        subcontrol-position: top left;
        left: 12px;
        padding: 0 5px;
    }
    QSlider::groove:horizontal {
        border: none;
        height: 8px;
        background: #313244;
        border-radius: 4px;
    }
    QSlider::sub-page:horizontal {
        background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #89b4fa, stop:1 #89dceb);
        border-radius: 4px;
    }
    QSlider::handle:horizontal {
        background: #cdd6f4;
        border: 2px solid #89b4fa;
        width: 18px;
        margin-top: -5px;
        margin-bottom: -5px;
        border-radius: 9px;
    }
    QSlider::handle:horizontal:hover {
        background: #ffffff;
        border-color: #89dceb;
    }
    QPushButton {
        background-color: #313244;
        color: #cdd6f4;
        border: 1px solid #45475a;
        border-radius: 6px;
        padding: 7px 14px;
        font-weight: 600;
    }
    QPushButton:hover {
        background-color: #45475a;
        border-color: #89b4fa;
        color: #ffffff;
    }
    QPushButton:pressed {
        background-color: #1e1e2e;
    }
    QPushButton.preset-btn {
        background-color: #24273a;
        border: 1px solid #363a4f;
        padding: 8px 10px;
        font-size: 12px;
    }
    QPushButton.preset-btn:hover {
        background-color: #363a4f;
        border-color: #fab387;
        color: #fab387;
    }
    QPushButton.primary-btn {
        background-color: #89b4fa;
        color: #11111b;
        border: none;
    }
    QPushButton.primary-btn:hover {
        background-color: #b4befe;
    }
    QCheckBox {
        spacing: 8px;
        color: #cdd6f4;
        font-weight: 500;
    }
    QCheckBox::indicator {
        width: 18px;
        height: 18px;
        border-radius: 4px;
        border: 1px solid #45475a;
        background: #313244;
    }
    QCheckBox::indicator:checked {
        background: #89b4fa;
        border-color: #89b4fa;
    }
    QLabel.badge {
        background-color: #313244;
        color: #89dceb;
        border-radius: 4px;
        padding: 2px 8px;
        font-family: monospace;
        font-weight: bold;
    }
    QMenu {
        background-color: #1e1e2e;
        color: #cdd6f4;
        border: 1px solid #45475a;
        padding: 4px;
    }
    QMenu::item:selected {
        background-color: #313244;
        color: #89dceb;
    }
    """
    app.setStyleSheet(DARK_STYLE)

    class MainWindow(QMainWindow):
        def __init__(self):
            super().__init__()
            self.setWindowTitle("Brightness & Color Controller")
            self.setMinimumSize(540, 620)
            self.resize(580, 660)

            # Look for icon
            icon_paths = [
                "/usr/local/share/icons/hicolor/scalable/apps/brightness-controller.svg",
                os.path.join(os.path.dirname(__file__), "brightness-controller.svg"),
                os.path.expanduser("~/.local/share/icons/brightness-controller.svg")
            ]
            for ip in icon_paths:
                if os.path.exists(ip):
                    self.setWindowIcon(QIcon(ip))
                    break

            self.displays = DisplayManager.get_connected_displays()
            self.hw_devices = HardwareBacklightManager.get_backlight_devices()
            self.display_widgets = {}

            # Central Widget
            central = QWidget(self)
            self.setCentralWidget(central)
            main_layout = QVBoxLayout(central)
            main_layout.setContentsMargins(16, 16, 16, 16)
            main_layout.setSpacing(14)

            # Top Header Bar
            header_layout = QHBoxLayout()
            title_label = QLabel("✨ Display Brightness & Night Light")
            title_label.setStyleSheet("font-size: 16px; font-weight: bold; color: #89dceb;")
            header_layout.addWidget(title_label)
            header_layout.addStretch()

            self.link_checkbox = QCheckBox("Sync All Displays")
            self.link_checkbox.setToolTip("Apply brightness and color changes across all connected monitors simultaneously")
            self.link_checkbox.setChecked(True)
            header_layout.addWidget(self.link_checkbox)
            main_layout.addLayout(header_layout)

            # Hardware Backlight Permission Banner for antiX / MX Linux
            self.perm_banner = None
            if self.hw_devices and not HardwareBacklightManager.is_writable():
                self.perm_banner = QGroupBox("⚠️ Hardware Backlight Permissions Required (antiX / MX Linux)")
                self.perm_banner.setStyleSheet("QGroupBox { border: 1px solid #f38ba8; color: #f38ba8; font-weight: bold; background-color: #261b24; padding: 10px; border-radius: 8px; }")
                banner_layout = QHBoxLayout(self.perm_banner)
                banner_text = QLabel("Panel brightness file is currently read-only. Fix rootless permissions to enable physical hardware slider.")
                banner_text.setStyleSheet("color: #f5c2e7; font-size: 11px;")
                banner_layout.addWidget(banner_text)
                banner_layout.addStretch()
                fix_btn = QPushButton("🛠️ Fix Permissions")
                fix_btn.setStyleSheet("background-color: #f38ba8; color: #11111b; font-weight: bold; padding: 5px 12px; border-radius: 4px;")
                fix_btn.clicked.connect(self.fix_permissions_action)
                banner_layout.addWidget(fix_btn)
                main_layout.addWidget(self.perm_banner)

            # Presets Bar
            preset_group = QGroupBox("⚡ Quick Presets")
            preset_layout = QHBoxLayout(preset_group)
            preset_layout.setSpacing(8)

            for key, preset in PRESETS.items():
                btn = QPushButton(preset["name"])
                btn.setProperty("class", "preset-btn")
                btn.setToolTip(preset["desc"])
                btn.clicked.connect(lambda checked, k=key: self.apply_preset(k))
                preset_layout.addWidget(btn)
            main_layout.addWidget(preset_group)

            # Tabs for Displays (or single view)
            self.tabs = QTabWidget()
            if not self.displays:
                no_disp_label = QLabel("No connected X11 displays detected.\n(Ensure DISPLAY environment variable is valid)")
                no_disp_label.setAlignment(QtAlignCenter)
                self.tabs.addTab(no_disp_label, "Default")
            else:
                for disp in self.displays:
                    tab_content = self.create_display_tab(disp)
                    tab_title = f"{disp['name']}" + (" (Primary)" if disp["primary"] else "")
                    self.tabs.addTab(tab_content, tab_title)
            main_layout.addWidget(self.tabs)

            # Bottom Controls Bar
            bottom_bar = QHBoxLayout()

            save_btn = QPushButton("💾 Save Default Profile")
            save_btn.setToolTip("Saves current settings to ~/.config/brightness-controller/config.json for auto-restore")
            save_btn.clicked.connect(self.save_current_profile)
            bottom_bar.addWidget(save_btn)

            reset_btn = QPushButton("🔄 Reset 100%")
            reset_btn.setToolTip("Resets display to full 100% brightness and neutral 6500K color")
            reset_btn.clicked.connect(lambda: self.apply_preset("day"))
            bottom_bar.addWidget(reset_btn)

            bottom_bar.addStretch()

            tray_btn = QPushButton("📥 Minimize to Tray")
            tray_btn.clicked.connect(self.hide)
            bottom_bar.addWidget(tray_btn)

            main_layout.addLayout(bottom_bar)

            # System Tray Setup
            self.setup_tray()

            # Load saved profile if available
            saved = ProfileManager.load_profile()
            if saved and "displays" in saved:
                self.apply_saved_dict(saved)

        def create_display_tab(self, disp: Dict) -> QWidget:
            tab = QWidget()
            layout = QVBoxLayout(tab)
            layout.setSpacing(14)
            name = disp["name"]

            widgets = {}

            # 1. Hardware Backlight Slider (if hardware backlight is available)
            if self.hw_devices:
                hw_box = QGroupBox("🔆 Hardware Backlight (Laptop Panel PWM)")
                hw_box_layout = QVBoxLayout(hw_box)

                hw_row = QHBoxLayout()
                hw_label = QLabel("Backlight Level:")
                hw_val_label = QLabel(f"{self.hw_devices[0]['percent']}%")
                hw_val_label.setProperty("class", "badge")
                hw_row.addWidget(hw_label)
                hw_row.addStretch()
                hw_row.addWidget(hw_val_label)
                hw_box_layout.addLayout(hw_row)

                hw_slider = QSlider(QtHorizontal)
                hw_slider.setRange(MIN_HW_BACKLIGHT, MAX_HW_BACKLIGHT)
                hw_slider.setValue(self.hw_devices[0]["percent"])
                hw_slider.valueChanged.connect(lambda val, l=hw_val_label: self.on_hw_slider_changed(val, l))
                hw_box_layout.addWidget(hw_slider)

                hw_note = QLabel("Controls physical LED panel illumination (saves laptop battery).")
                hw_note.setStyleSheet("color: #6c7086; font-size: 11px;")
                hw_box_layout.addWidget(hw_note)

                layout.addWidget(hw_box)
                widgets["hw_slider"] = hw_slider
                widgets["hw_label"] = hw_val_label

            # 2. Universal Software Brightness Slider
            soft_box = QGroupBox("💡 Software Brightness (Universal Gamma Dimming)")
            soft_box_layout = QVBoxLayout(soft_box)

            soft_row = QHBoxLayout()
            soft_label = QLabel("Brightness:")
            cur_pct = int(round(disp["brightness"] * 100))
            soft_val_label = QLabel(f"{cur_pct}%")
            soft_val_label.setProperty("class", "badge")
            soft_row.addWidget(soft_label)
            soft_row.addStretch()
            soft_row.addWidget(soft_val_label)
            soft_box_layout.addLayout(soft_row)

            soft_slider = QSlider(QtHorizontal)
            soft_slider.setRange(int(MIN_SOFTWARE_BRIGHTNESS * 100), int(MAX_SOFTWARE_BRIGHTNESS * 100))
            soft_slider.setValue(cur_pct)
            soft_slider.valueChanged.connect(lambda val, d=name, l=soft_val_label: self.on_software_slider_changed(val, d, l))
            soft_box_layout.addWidget(soft_slider)

            soft_note = QLabel("Compatible with all internal & external monitors (HDMI, DP, VGA).")
            soft_note.setStyleSheet("color: #6c7086; font-size: 11px;")
            soft_box_layout.addWidget(soft_note)

            layout.addWidget(soft_box)
            widgets["soft_slider"] = soft_slider
            widgets["soft_label"] = soft_val_label

            # 3. Night Light / Warmth Slider
            warmth_box = QGroupBox("🌙 Night Light / Eye Care Warmth")
            warmth_box_layout = QVBoxLayout(warmth_box)

            warmth_row = QHBoxLayout()
            warmth_label = QLabel("Color Warmth:")
            warmth_val_label = QLabel("0% (Daylight 6500K)")
            warmth_val_label.setProperty("class", "badge")
            warmth_row.addWidget(warmth_label)
            warmth_row.addStretch()
            warmth_row.addWidget(warmth_val_label)
            warmth_box_layout.addLayout(warmth_row)

            warmth_slider = QSlider(QtHorizontal)
            warmth_slider.setRange(0, 100)
            warmth_slider.setValue(disp.get("warmth", 0))
            warmth_slider.valueChanged.connect(lambda val, d=name, l=warmth_val_label: self.on_warmth_slider_changed(val, d, l))
            warmth_box_layout.addWidget(warmth_slider)

            warmth_note = QLabel("Filters harsh blue light to reduce ocular strain and fatigue.")
            warmth_note.setStyleSheet("color: #6c7086; font-size: 11px;")
            warmth_box_layout.addWidget(warmth_note)

            layout.addWidget(warmth_box)
            widgets["warmth_slider"] = warmth_slider
            widgets["warmth_label"] = warmth_val_label

            # 4. Collapsible Advanced RGB Calibration
            adv_box = QGroupBox("🎨 Fine RGB Calibration")
            adv_layout = QVBoxLayout(adv_box)

            # Red Slider
            r_row = QHBoxLayout()
            r_row.addWidget(QLabel("Red Channel:"))
            r_val_label = QLabel(f"{disp['gamma'][0]:.2f}")
            r_val_label.setProperty("class", "badge")
            r_row.addStretch()
            r_row.addWidget(r_val_label)
            adv_layout.addLayout(r_row)

            r_slider = QSlider(QtHorizontal)
            r_slider.setRange(50, 150)
            r_slider.setValue(int(disp['gamma'][0] * 100))
            r_slider.valueChanged.connect(lambda val, d=name, l=r_val_label, ch=0: self.on_rgb_slider_changed(val, d, l, ch))
            adv_layout.addWidget(r_slider)

            # Green Slider
            g_row = QHBoxLayout()
            g_row.addWidget(QLabel("Green Channel:"))
            g_val_label = QLabel(f"{disp['gamma'][1]:.2f}")
            g_val_label.setProperty("class", "badge")
            g_row.addStretch()
            g_row.addWidget(g_val_label)
            adv_layout.addLayout(g_row)

            g_slider = QSlider(QtHorizontal)
            g_slider.setRange(50, 150)
            g_slider.setValue(int(disp['gamma'][1] * 100))
            g_slider.valueChanged.connect(lambda val, d=name, l=g_val_label, ch=1: self.on_rgb_slider_changed(val, d, l, ch))
            adv_layout.addWidget(g_slider)

            # Blue Slider
            b_row = QHBoxLayout()
            b_row.addWidget(QLabel("Blue Channel:"))
            b_val_label = QLabel(f"{disp['gamma'][2]:.2f}")
            b_val_label.setProperty("class", "badge")
            b_row.addStretch()
            b_row.addWidget(b_val_label)
            adv_layout.addLayout(b_row)

            b_slider = QSlider(QtHorizontal)
            b_slider.setRange(50, 150)
            b_slider.setValue(int(disp['gamma'][2] * 100))
            b_slider.valueChanged.connect(lambda val, d=name, l=b_val_label, ch=2: self.on_rgb_slider_changed(val, d, l, ch))
            adv_layout.addWidget(b_slider)

            widgets["r_slider"] = r_slider
            widgets["g_slider"] = g_slider
            widgets["b_slider"] = b_slider
            widgets["r_label"] = r_val_label
            widgets["g_label"] = g_val_label
            widgets["b_label"] = b_val_label

            layout.addWidget(adv_box)

            layout.addStretch()
            self.display_widgets[name] = widgets
            return tab

        def fix_permissions_action(self):
            user_name = os.environ.get("USER") or os.environ.get("LOGNAME") or os.path.basename(os.path.expanduser("~"))
            cmd = (
                'pkexec bash -c "'
                'chmod 0666 /sys/class/backlight/*/brightness 2>/dev/null; '
                'chmod 0666 /sys/class/leds/*kbd_backlight*/brightness 2>/dev/null; '
                'chmod u+s /usr/bin/brightnessctl 2>/dev/null; '
                'echo \\"ACTION==\\\\\\"add|change\\\\\\", SUBSYSTEM==\\\\\\"backlight\\\\\\", RUN+=\\\\\\"/bin/chmod 0666 /sys/class/backlight/%k/brightness\\\\\\"\\" > /etc/udev/rules.d/90-backlight.rules; '
                'echo \\"ACTION==\\\\\\"add|change\\\\\\", SUBSYSTEM==\\\\\\"leds\\\\\\", KERNEL==\\\\\\"*kbd_backlight*\\\\\\", RUN+=\\\\\\"/bin/chmod 0666 /sys/class/leds/%k/brightness\\\\\\"\\" >> /etc/udev/rules.d/90-backlight.rules; '
                'udevadm control --reload-rules 2>/dev/null; '
                'udevadm trigger --subsystem-match=backlight 2>/dev/null; '
                f'usermod -a -G video {user_name} 2>/dev/null || true'
                '"'
            )
            try:
                res = subprocess.run(cmd, shell=True)
                if res.returncode == 0:
                    QMessageBox.information(self, "Permissions Granted", "Rootless hardware backlight access has been successfully configured!\nThe hardware slider now directly controls physical panel brightness.")
                    if self.perm_banner:
                        self.perm_banner.hide()
                    self.hw_devices = HardwareBacklightManager.get_backlight_devices()
                else:
                    QMessageBox.warning(self, "Permission Update Incomplete", "Root authorization was cancelled or failed.\nYou can also run in terminal:\nsudo ./setup-brightness.sh --fix-permissions")
            except Exception as e:
                QMessageBox.warning(self, "Error", f"Failed to execute permission update: {e}")

        def on_hw_slider_changed(self, val: int, label: QLabel):
            label.setText(f"{val}%")
            success = HardwareBacklightManager.set_backlight_percent(val)
            if not success:
                # If hardware backlight write failed (e.g. antiX/MX rootless permissions),
                # seamlessly fallback to universal software dimming so the screen STILL adjusts!
                b_val = max(MIN_SOFTWARE_BRIGHTNESS, min(1.0, val / 100.0))
                for d in self.displays:
                    d["brightness"] = b_val
                    DisplayManager.apply_display_settings(d["name"], b_val, d["gamma"])
                    if d["name"] in self.display_widgets:
                        w = self.display_widgets[d["name"]]
                        if "soft_slider" in w:
                            w["soft_slider"].blockSignals(True)
                            w["soft_slider"].setValue(val)
                            w["soft_label"].setText(f"{val}%")
                            w["soft_slider"].blockSignals(False)

            if self.link_checkbox.isChecked():
                for d_name, w in self.display_widgets.items():
                    if "hw_slider" in w and w["hw_slider"] != self.sender():
                        w["hw_slider"].blockSignals(True)
                        w["hw_slider"].setValue(val)
                        w["hw_label"].setText(f"{val}%")
                        w["hw_slider"].blockSignals(False)
            self.update_tray_tooltip()

        def on_software_slider_changed(self, val: int, disp_name: str, label: QLabel):
            pct = val
            label.setText(f"{pct}%")
            b_val = pct / 100.0

            target_displays = self.displays if self.link_checkbox.isChecked() else [d for d in self.displays if d["name"] == disp_name]

            for d in target_displays:
                d["brightness"] = b_val
                DisplayManager.apply_display_settings(d["name"], b_val, d["gamma"])

                # Sync UI sliders if linked
                if self.link_checkbox.isChecked() and d["name"] in self.display_widgets:
                    w = self.display_widgets[d["name"]]
                    if w["soft_slider"] != self.sender():
                        w["soft_slider"].blockSignals(True)
                        w["soft_slider"].setValue(val)
                        w["soft_label"].setText(f"{pct}%")
                        w["soft_slider"].blockSignals(False)

            self.update_tray_tooltip()

        def on_warmth_slider_changed(self, val: int, disp_name: str, label: QLabel):
            if val == 0:
                label.setText("0% (Daylight 6500K)")
            elif val < 40:
                label.setText(f"{val}% (Gentle ~5500K)")
            elif val < 70:
                label.setText(f"{val}% (Warm ~4500K)")
            else:
                label.setText(f"{val}% (Amber ~3200K)")

            r_mult, g_mult, b_mult = WarmthEngine.warmth_to_rgb(val)

            target_displays = self.displays if self.link_checkbox.isChecked() else [d for d in self.displays if d["name"] == disp_name]

            for d in target_displays:
                d["warmth"] = val
                d["gamma"] = [r_mult, g_mult, b_mult]
                DisplayManager.apply_display_settings(d["name"], d["brightness"], d["gamma"])

                if d["name"] in self.display_widgets:
                    w = self.display_widgets[d["name"]]
                    # Update RGB sliders to reflect calculated values
                    w["r_slider"].blockSignals(True)
                    w["g_slider"].blockSignals(True)
                    w["b_slider"].blockSignals(True)
                    w["r_slider"].setValue(int(r_mult * 100))
                    w["g_slider"].setValue(int(g_mult * 100))
                    w["b_slider"].setValue(int(b_mult * 100))
                    w["r_label"].setText(f"{r_mult:.2f}")
                    w["g_label"].setText(f"{g_mult:.2f}")
                    w["b_label"].setText(f"{b_mult:.2f}")
                    w["r_slider"].blockSignals(False)
                    w["g_slider"].blockSignals(False)
                    w["b_slider"].blockSignals(False)

                    if self.link_checkbox.isChecked() and w["warmth_slider"] != self.sender():
                        w["warmth_slider"].blockSignals(True)
                        w["warmth_slider"].setValue(val)
                        w["warmth_label"].setText(label.text())
                        w["warmth_slider"].blockSignals(False)

        def on_rgb_slider_changed(self, val: int, disp_name: str, label: QLabel, channel: int):
            label.setText(f"{val / 100.0:.2f}")
            target_displays = self.displays if self.link_checkbox.isChecked() else [d for d in self.displays if d["name"] == disp_name]

            for d in target_displays:
                d["gamma"][channel] = val / 100.0
                DisplayManager.apply_display_settings(d["name"], d["brightness"], d["gamma"])

        def apply_preset(self, preset_key: str):
            if preset_key not in PRESETS:
                return
            p = PRESETS[preset_key]
            soft_pct = p["software_pct"]
            hw_pct = p["hw_pct"]
            warmth = p["warmth"]

            # Set hardware backlight
            if self.hw_devices:
                HardwareBacklightManager.set_backlight_percent(hw_pct)

            # Set software brightness & warmth across all displays
            r_mult, g_mult, b_mult = WarmthEngine.warmth_to_rgb(warmth)
            for d in self.displays:
                d["brightness"] = soft_pct / 100.0
                d["warmth"] = warmth
                d["gamma"] = [r_mult, g_mult, b_mult]
                DisplayManager.apply_display_settings(d["name"], d["brightness"], d["gamma"])

            # Sync GUI widgets
            for name, w in self.display_widgets.items():
                if "hw_slider" in w:
                    w["hw_slider"].blockSignals(True)
                    w["hw_slider"].setValue(hw_pct)
                    w["hw_label"].setText(f"{hw_pct}%")
                    w["hw_slider"].blockSignals(False)

                w["soft_slider"].blockSignals(True)
                w["soft_slider"].setValue(soft_pct)
                w["soft_label"].setText(f"{soft_pct}%")
                w["soft_slider"].blockSignals(False)

                w["warmth_slider"].blockSignals(True)
                w["warmth_slider"].setValue(warmth)
                if warmth == 0:
                    w["warmth_label"].setText("0% (Daylight 6500K)")
                else:
                    w["warmth_label"].setText(f"{warmth}%")
                w["warmth_slider"].blockSignals(False)

                w["r_slider"].blockSignals(True)
                w["g_slider"].blockSignals(True)
                w["b_slider"].blockSignals(True)
                w["r_slider"].setValue(int(r_mult * 100))
                w["g_slider"].setValue(int(g_mult * 100))
                w["b_slider"].setValue(int(b_mult * 100))
                w["r_label"].setText(f"{r_mult:.2f}")
                w["g_label"].setText(f"{g_mult:.2f}")
                w["b_label"].setText(f"{b_mult:.2f}")
                w["r_slider"].blockSignals(False)
                w["g_slider"].blockSignals(False)
                w["b_slider"].blockSignals(False)

            self.update_tray_tooltip()

        def save_current_profile(self):
            profile = {
                "link_displays": self.link_checkbox.isChecked(),
                "displays": {}
            }
            if self.hw_devices:
                profile["hw_backlight"] = self.display_widgets[self.displays[0]["name"]]["hw_slider"].value() if self.displays and self.displays[0]["name"] in self.display_widgets and "hw_slider" in self.display_widgets[self.displays[0]["name"]] else 100

            for d in self.displays:
                profile["displays"][d["name"]] = {
                    "brightness": d["brightness"],
                    "warmth": d.get("warmth", 0),
                    "gamma": d["gamma"]
                }

            if ProfileManager.save_profile(profile):
                QMessageBox.information(self, "Profile Saved", f"Display configuration successfully saved to:\n{CONFIG_FILE}\n\nSettings will auto-restore on boot/login.")
            else:
                QMessageBox.warning(self, "Save Error", "Failed to save configuration profile.")

        def apply_saved_dict(self, data: Dict):
            if "hw_backlight" in data and self.hw_devices:
                HardwareBacklightManager.set_backlight_percent(data["hw_backlight"])

            disp_map = data.get("displays", {})
            for d in self.displays:
                if d["name"] in disp_map:
                    cfg = disp_map[d["name"]]
                    b = cfg.get("brightness", 1.0)
                    w = cfg.get("warmth", 0)
                    g = cfg.get("gamma", [1.0, 1.0, 1.0])
                    d["brightness"] = b
                    d["warmth"] = w
                    d["gamma"] = g
                    DisplayManager.apply_display_settings(d["name"], b, g)

                    if d["name"] in self.display_widgets:
                        dw = self.display_widgets[d["name"]]
                        dw["soft_slider"].setValue(int(round(b * 100)))
                        dw["warmth_slider"].setValue(w)

        def setup_tray(self):
            if not QSystemTrayIcon.isSystemTrayAvailable():
                return

            self.tray_icon = QSystemTrayIcon(self)
            # Find icon or use window icon
            self.tray_icon.setIcon(self.windowIcon())

            tray_menu = QMenu()

            open_act = QAction("Open Controller", self)
            open_act.triggered.connect(self.show_and_raise)
            tray_menu.addAction(open_act)

            tray_menu.addSeparator()

            for key, preset in PRESETS.items():
                act = QAction(preset["name"], self)
                act.triggered.connect(lambda checked, k=key: self.apply_preset(k))
                tray_menu.addAction(act)

            tray_menu.addSeparator()

            save_act = QAction("Save Default Profile", self)
            save_act.triggered.connect(self.save_current_profile)
            tray_menu.addAction(save_act)

            quit_act = QAction("Quit Controller", self)
            quit_act.triggered.connect(app.quit)
            tray_menu.addAction(quit_act)

            self.tray_icon.setContextMenu(tray_menu)
            self.tray_icon.activated.connect(self.on_tray_activated)
            self.tray_icon.show()
            self.update_tray_tooltip()

        def update_tray_tooltip(self):
            if hasattr(self, "tray_icon"):
                b_pct = int(round(self.displays[0]["brightness"] * 100)) if self.displays else 100
                self.tray_icon.setToolTip(f"Brightness: {b_pct}%\nClick to open • Scroll wheel to adjust")

        def show_and_raise(self):
            self.show()
            self.raise_()
            self.activateWindow()

        def on_tray_activated(self, reason):
            if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick):
                if self.isVisible():
                    self.hide()
                else:
                    self.show_and_raise()

        def changeEvent(self, event):
            super().changeEvent(event)

        def closeEvent(self, event):
            if hasattr(self, "tray_icon") and self.tray_icon.isVisible():
                self.hide()
                event.ignore()
            else:
                event.accept()

    win = MainWindow()
    win.show()
    exec_func = getattr(app, "exec", getattr(app, "exec_", sys.exit))
    sys.exit(exec_func())


# ==============================================================================
# CLI Implementation
# ==============================================================================

def run_cli(args):
    """Executes non-GUI command-line brightness operations."""
    displays = DisplayManager.get_connected_displays()
    hw_devices = HardwareBacklightManager.get_backlight_devices()

    # Silently restore configuration (for system startup / autostart)
    if args.restore:
        cfg = ProfileManager.load_profile()
        if not cfg:
            sys.exit(0)

        if "hw_backlight" in cfg and hw_devices:
            HardwareBacklightManager.set_backlight_percent(cfg["hw_backlight"])

        disp_cfgs = cfg.get("displays", {})
        for d in displays:
            if d["name"] in disp_cfgs:
                c = disp_cfgs[d["name"]]
                b = c.get("brightness", 1.0)
                g = c.get("gamma", [1.0, 1.0, 1.0])
                DisplayManager.apply_display_settings(d["name"], b, g)
        sys.exit(0)

    # List displays & backlights
    if args.list:
        print("Connected X11 Displays:")
        if not displays:
            print("  (None detected or DISPLAY not available)")
        for d in displays:
            p_str = " [Primary]" if d["primary"] else ""
            b_pct = round(d["brightness"] * 100)
            print(f"  • {d['name']}{p_str}: Brightness={b_pct}% | Gamma={d['gamma'][0]:.2f}:{d['gamma'][1]:.2f}:{d['gamma'][2]:.2f}")

        print("\nHardware Backlight Controllers:")
        if not hw_devices:
            print("  (No /sys/class/backlight device detected; use software brightness)")
        for hw in hw_devices:
            w_str = "Writable" if hw.get("writable") else "Read-Only (Run ./setup-brightness.sh --install to enable)"
            print(f"  • {hw['device']}: {hw['percent']}% ({hw['current']}/{hw['max']}) [{w_str}]")
        return

    # Print status JSON
    if args.status:
        data = {
            "displays": displays,
            "hardware_backlights": hw_devices
        }
        print(json.dumps(data, indent=2))
        return

    # Apply Preset
    if args.preset:
        p_name = args.preset.lower()
        if p_name not in PRESETS:
            print(f"[-] Error: Unknown preset '{args.preset}'. Choose from: {', '.join(PRESETS.keys())}")
            sys.exit(1)
        p = PRESETS[p_name]
        soft_pct = p["software_pct"]
        hw_pct = p["hw_pct"]
        warmth = p["warmth"]

        if hw_devices:
            HardwareBacklightManager.set_backlight_percent(hw_pct)

        r_mult, g_mult, b_mult = WarmthEngine.warmth_to_rgb(warmth)
        target_displays = [d for d in displays if (not args.display or d["name"] == args.display)]
        for d in target_displays:
            DisplayManager.apply_display_settings(d["name"], soft_pct / 100.0, (r_mult, g_mult, b_mult))
        print(f"[✓] Applied preset '{p['name']}' ({p['desc']})")
        return

    # Adjust Software Brightness (set, inc, dec)
    target_displays = [d for d in displays if (not args.display or d["name"] == args.display)]
    if not target_displays:
        print("[-] Error: No matching display connected.")
        sys.exit(1)

    modified = False

    if args.set is not None:
        val = max(10, min(150, args.set)) / 100.0
        for d in target_displays:
            DisplayManager.apply_display_settings(d["name"], val, d["gamma"])
            print(f"[✓] Set {d['name']} software brightness to {int(round(val * 100))}%")
        modified = True

    if args.inc is not None:
        delta = args.inc / 100.0
        for d in target_displays:
            new_val = max(MIN_SOFTWARE_BRIGHTNESS, min(MAX_SOFTWARE_BRIGHTNESS, d["brightness"] + delta))
            DisplayManager.apply_display_settings(d["name"], new_val, d["gamma"])
            print(f"[✓] Increased {d['name']} brightness: {int(round(new_val * 100))}%")
        modified = True

    if args.dec is not None:
        delta = args.dec / 100.0
        for d in target_displays:
            new_val = max(MIN_SOFTWARE_BRIGHTNESS, min(MAX_SOFTWARE_BRIGHTNESS, d["brightness"] - delta))
            DisplayManager.apply_display_settings(d["name"], new_val, d["gamma"])
            print(f"[✓] Decreased {d['name']} brightness: {int(round(new_val * 100))}%")
        modified = True

    # Adjust Hardware Backlight
    if args.hw_set is not None:
        HardwareBacklightManager.set_backlight_percent(args.hw_set)
        print(f"[✓] Set hardware backlight to {args.hw_set}%")
        modified = True

    if args.hw_inc is not None:
        if hw_devices:
            cur = hw_devices[0]["percent"]
            HardwareBacklightManager.set_backlight_percent(cur + args.hw_inc)
            print(f"[✓] Increased hardware backlight to {min(100, cur + args.hw_inc)}%")
        modified = True

    if args.hw_dec is not None:
        if hw_devices:
            cur = hw_devices[0]["percent"]
            HardwareBacklightManager.set_backlight_percent(cur - args.hw_dec)
            print(f"[✓] Decreased hardware backlight to {max(1, cur - args.hw_dec)}%")
        modified = True

    # Adjust Warmth
    if args.warmth is not None:
        w_val = max(0, min(100, args.warmth))
        r, g, b = WarmthEngine.warmth_to_rgb(w_val)
        for d in target_displays:
            DisplayManager.apply_display_settings(d["name"], d["brightness"], (r, g, b))
            print(f"[✓] Set {d['name']} warmth to {w_val}% (RGB Gamma: {r}:{g}:{b})")
        modified = True

    if not modified:
        print("[!] No action specified. Use --gui, --list, --help, or --set <percent>.")


def main():
    parser = argparse.ArgumentParser(
        description="Standalone, secure, lightweight GUI & CLI display brightness controller.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("--gui", "-g", action="store_true", help="Launch the graphical user interface")
    parser.add_argument("--list", "-l", action="store_true", help="List detected displays and hardware backlights")
    parser.add_argument("--status", action="store_true", help="Output status in JSON format")
    parser.add_argument("--set", type=int, metavar="PCT", help="Set software brightness (10-150%%)")
    parser.add_argument("--inc", type=int, metavar="PCT", help="Increase software brightness by PCT%%")
    parser.add_argument("--dec", type=int, metavar="PCT", help="Decrease software brightness by PCT%%")
    parser.add_argument("--hw-set", type=int, metavar="PCT", help="Set hardware backlight percentage (1-100%%)")
    parser.add_argument("--hw-inc", type=int, metavar="PCT", help="Increase hardware backlight by PCT%%")
    parser.add_argument("--hw-dec", type=int, metavar="PCT", help="Decrease hardware backlight by PCT%%")
    parser.add_argument("--warmth", type=int, metavar="PCT", help="Set night light warmth (0-100%%)")
    parser.add_argument("--preset", type=str, metavar="NAME", help="Apply quick preset: day, office, evening, night, ultradim")
    parser.add_argument("--display", type=str, metavar="NAME", help="Target specific display name (e.g. eDP-1, HDMI-1)")
    parser.add_argument("--restore", action="store_true", help="Silently restore saved settings on system startup")
    parser.add_argument("--version", "-v", action="version", version="Brightness Controller v1.0.0 (100%% Open-Source, 0 Telemetry)")

    args = parser.parse_args()

    # Default to GUI if no command-line flags provided and DISPLAY is available
    if len(sys.argv) == 1:
        if "DISPLAY" in os.environ and os.environ["DISPLAY"]:
            launch_gui()
        else:
            parser.print_help()
            sys.exit(0)

    if args.gui:
        launch_gui()
    else:
        run_cli(args)


if __name__ == "__main__":
    main()
