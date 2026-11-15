# Setup-Brightness: Standalone GUI Brightness & Color Controller

> **100% Free & Open-Source (FOSS) • Zero Telemetry • Dual Hardware/Software Engine • Blackout-Proof**  
> Ultra-lightweight, standalone display brightness and night light (blue light filter) controller designed for Debian, antiX, MX Linux, Ubuntu, Linux Mint, Devuan, and all X11 Linux systems.

```text
  🪶 ~15–20MB Idle RAM  •  🔒 0 Telemetry (100% Localhost)  •  🛡️ Blackout Lockout Protection  •  ⚡ Instant 1-Click Presets
```

---

## 1. Why Setup-Brightness?

Most Linux desktop environments either lack integrated external monitor brightness controls, bundle heavy background daemons, or lack blue light warmth filtering:

- **Laptop backlights** (`/sys/class/backlight`) only dim the built-in laptop panel and cannot dim external HDMI/DisplayPort/DVI monitors.
- **DDC/CI tools** require specific monitor hardware support, I2C kernel modules, and often fail over HDMI adapters or budget displays.
- **Standard night light tools** (like Redshift or GNOME Night Light) often conflict with display managers or require internet access for geolocation.
- **Heavy GUI tools** often consume 100MB–400MB of RAM or depend on deprecated Python 2 / PPA dependencies.

`Setup-Brightness` solves this with a **zero-telemetry, standalone dual-engine architecture powered by PySide6 (official LGPLv3 Qt6)**:
1. **Official LGPLv3 Qt6 Engine (PySide6):** Built with **PySide6** (Qt for Python, officially maintained by The Qt Company under the permissive LGPLv3 license) for modern, native Linux desktop integration.
2. **Hardware PWM Engine:** Controls physical laptop LED backlights via `brightnessctl` or `/sys/class/backlight` to reduce physical power consumption and preserve battery.
3. **Universal Software Gamma Engine:** Directly calibrates the X11 RandR engine (`xrandr`), enabling fluid brightness adjustments (from 10% to 150%) and color temperature warming (3000K–6500K) across **any connected display** (laptop screens, desktop monitors, HDMI, DisplayPort, VGA).

---

## 2. Quick Installation & Launch

Run the installer as your **normal user** from the repository directory:

```bash
cd Setup-Brightness
chmod +x setup-brightness.sh
./setup-brightness.sh --install
```

> [!NOTE]
> **Do not run `./setup-brightness.sh --install` as `sudo`!**  
> Running as a standard user ensures desktop shortcuts and autostart profiles are configured in your personal user profile. The script automatically requests `sudo` only when deploying global udev rules or installing missing system packages.

### Launching the Controller

- **Application Menu:** Search for **"Brightness & Color Controller"** under *Accessories* or *Settings*.
- **Terminal GUI:** Run `brightness-controller --gui` (or `./setup-brightness.sh --gui`).
- **Terminal CLI:** Use `brightness-control` for instant adjustments or keyboard shortcuts.

### antiX & MX Linux Compatibility Guide (Hardware Permissions & MX-Tweak)

antiX and MX Linux operate on lightweight **SysVinit / OpenRC** (without `systemd-logind`), which means the Linux kernel initializes `/sys/class/backlight` as read-only (`root:root 0644`):

1. **Automatic In-App Fix**:
   - If hardware backlight write permission is restricted, an alert banner appears at the top of the GUI:
     `[ ⚠️ Hardware Backlight Permissions Required (antiX / MX Linux) ] [ 🛠️ Fix Permissions ]`
   - Clicking **"Fix Permissions"** prompts for password once and immediately unlocks rootless hardware slider control!
2. **One-Command Terminal Fix**:
   ```bash
   sudo ./setup-brightness.sh --fix-permissions
   ```
   This configures `/etc/udev/rules.d/90-backlight.rules`, grants SUID on `/usr/bin/brightnessctl`, adds user to the `video` group, and hooks persistence in `/etc/init.d/brightness`.
3. **Seamless Fallback**:
   - Even if permissions have not been configured yet, dragging the hardware backlight slider gracefully falls back to universal software dimming—ensuring your screen brightness **always dims and brightens reliably**!
4. **MX Linux MX-Tweak Synchronization**:
   - In MX Linux, settings automatically sync to `~/.config/MX-Linux/MX-Tweak/brightness/<display>`, ensuring MX Linux's native `/usr/bin/restore-software-brightness` service stays in complete harmony across reboots!

---

## 3. Core Features

### 🖥️ Multi-Monitor Support with Synchronized Linking
- Auto-detects all active displays (`eDP-1`, `HDMI-1`, `DP-1`, etc.).
- Switch between displays using dedicated tabs, or check **"Sync All Displays"** to control all screens simultaneously with a single slider.

### 💡 Dual Brightness Controls
- **Universal Software Dimming (10%–150%):** Works on all displays. Lets you dim your display lower than hardware minimums for late-night work in dark rooms, or boost contrast up to 150%.
- **Physical Hardware Backlight (1%–100%):** Controls laptop screen LED backlight to maximize battery runtime.

### 🌙 Night Light / Blue Light Eye Care (Warmth Slider)
- Gradual color temperature adjustment from **Daylight (6500K)** to **Cozy Amber (3000K)**.
- Uses Planckian color mathematics to selectively attenuate harsh blue spectrum light, preventing ocular strain and circadian rhythm disruption without third-party cloud geolocation.

### 🎨 Fine-Grained RGB Channel Calibration
- Collapsible drawer with individual **Red, Green, and Blue** gamma sliders (0.50 to 1.50) for color calibration, accessibility, or monitor matching.

### ⚡ 1-Click Quick Presets
| Preset | Software Brightness | Hardware Backlight | Warmth | Best For |
| :--- | :---: | :---: | :---: | :--- |
| **☀️ Daylight** | `100%` | `100%` | `0% (6500K)` | Bright sunlight & daylight hours |
| **💻 Office** | `80%` | `80%` | `15% (~5800K)` | Balanced focus during office work |
| **🌆 Evening** | `55%` | `55%` | `45% (~4800K)` | Sunset & dimly lit rooms |
| **🌙 Night** | `35%` | `35%` | `75% (~3600K)` | Late-night coding & reading |
| **🕶️ Ultra-Dim** | `15%` | `10%` | `85% (~3200K)` | Pitch-dark bedrooms & OLED mode |

### 📥 System Tray Integration
- Sits unobtrusively in your desktop notification tray.
- **Scroll-Wheel Dimming:** Scroll your mouse wheel directly over the tray icon to increase or decrease brightness in 5% increments!
- Right-click menu allows instant 1-click preset switching.

### 💾 Persistent Auto-Restore on Login
- Click **"Save Default Profile"** to store your preferred settings in `~/.config/brightness-controller/config.json`.
- Automatically re-applies your saved profile when you log into your desktop environment.

---

## 4. CLI Quick Reference (Keyboard Shortcuts)

The `brightness-control` CLI companion allows you to integrate brightness and warmth controls into window managers, hotkeys, or scripts:

```bash
# Relative brightness adjustments (ideal for Fn key bindings)
brightness-control --inc 10            # Increase software brightness by 10%
brightness-control --dec 10            # Decrease software brightness by 10%

# Direct brightness values
brightness-control --set 75            # Set software brightness to 75%
brightness-control --hw-set 50         # Set laptop hardware backlight to 50%

# Night light and warmth
brightness-control --warmth 60         # Set blue light filter warmth to 60%
brightness-control --preset night      # Apply Night preset
brightness-control --preset day        # Reset to Daylight preset

# Diagnostics and session restore
brightness-control --list              # List connected displays & backlight devices
brightness-control --status            # Export full status as JSON
brightness-control --restore           # Silently restore saved settings on login
```

---

## 5. Keyboard Shortcut Configuration Guide

Bind brightness keys in your desktop environment or window manager:

### XFCE
1. Go to **Settings** $\rightarrow$ **Keyboard** $\rightarrow$ **Application Shortcuts**.
2. Click **Add**:
   - Command: `brightness-control --inc 10` $\rightarrow$ Press <kbd>XF86MonBrightnessUp</kbd> (or <kbd>Super</kbd> + <kbd>F12</kbd>).
   - Command: `brightness-control --dec 10` $\rightarrow$ Press <kbd>XF86MonBrightnessDown</kbd> (or <kbd>Super</kbd> + <kbd>F11</kbd>).
   - Command: `brightness-control --preset night` $\rightarrow$ Press <kbd>Super</kbd> + <kbd>N</kbd>.

### i3 / Sway
Add to `~/.config/i3/config` or `~/.config/sway/config`:
```i3config
# Brightness controls
bindsym XF86MonBrightnessUp exec --no-startup-id brightness-control --inc 10
bindsym XF86MonBrightnessDown exec --no-startup-id brightness-control --dec 10
bindsym $mod+Shift+n exec --no-startup-id brightness-control --preset night
bindsym $mod+Shift+d exec --no-startup-id brightness-control --preset day
```

### Openbox / antiX / Fluxbox
Add to `~/.config/openbox/rc.xml` inside `<keyboard>`:
```xml
<keybind key="XF86MonBrightnessUp">
  <action name="Execute"><command>brightness-control --inc 10</command></action>
</keybind>
<keybind key="XF86MonBrightnessDown">
  <action name="Execute"><command>brightness-control --dec 10</command></action>
</keybind>
```

---

## 6. Security & Privacy Audit

| Metric | Verification & Hardening |
| :--- | :--- |
| **Telemetry & Analytics** | **0 Telemetry.** 0 bytes of network traffic; strictly audited against external network modules. Works 100% air-gapped. |
| **Blackout Lockout Protection** | Software brightness is clamped to $\ge 10\%$ (`0.10`). Users can never accidentally turn their screen completely black and get locked out. |
| **Input Sanitization** | Display identifiers are strictly verified using `^[A-Za-z0-9_\-]+$`. Prevents shell interpolation and command injection. |
| **Least Privilege Runtime** | Normal GUI and CLI executions run as standard unprivileged users without requiring `sudo`. |
| **Safe File Permissions** | Profiles in `~/.config/brightness-controller/config.json` are written with restrictive `0600` permissions. |

---

## 7. Diagnostics & Testing

Run the built-in diagnostic and test suite anytime:

```bash
# Check hardware backlights, displays, and tool versions
./setup-brightness.sh --status

# Run automated security and unit tests
./setup-brightness.sh --test
```

### Uninstallation

To cleanly remove launchers and desktop entries:

```bash
./setup-brightness.sh --uninstall
```

---

## 8. License & Open Source

Licensed under the **MIT License**. 100% Free and Open Source.
