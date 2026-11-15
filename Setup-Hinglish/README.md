# Hinglish to Hindi Typing (Linux / Debian & Ubuntu)

> **100% Offline • Zero Telemetry • Real-Time Transliteration • Zero Shortcut Conflicts**  
> Type phonetically in English (Hinglish) and get instant Hindi text (e.g. `namaste` $\rightarrow$ **नमस्ते**).

---

## 1. Quick Installation

Make the script executable and run it as your **normal user**:

```bash
chmod +x hinglish-to-hindi-typing.sh
./hinglish-to-hindi-typing.sh
```

> [!NOTE]
> **Do not run with `sudo ./hinglish-to-hindi-typing.sh`!**  
> Running with `sudo` will target `/root` instead of your desktop profile. The script automatically requests `sudo` only when installing required system packages.

---

## 2. How to Use (Choose Your Preferred Workflow)

### Method 1: Easy Hindi Typing Localhost App (Like easyhindityping.com — Recommended for All Window Managers!)
If you run **antiX, Fluxbox, MX Linux, or any lightweight desktop** where X11 floating candidate windows might not appear, or if you want the exact convenience of [easyhindityping.com](https://www.easyhindityping.com/) **100% offline with zero internet**:

1. Launch Easy Hindi Typing:
   ```bash
   ./easy-hindi-typing.sh
   # or
   ./hinglish-to-hindi-typing.sh --web
   ```
2. Your browser opens to `http://127.0.0.1:8765` (100% private localhost, 0 external traffic).
3. Type in Hinglish (e.g. `namaste` or `aap kaise hain`):
   - Multiple candidate suggestions pop up right underneath your cursor!
   - Press **`Space`** or **`Enter`** to pick the top candidate.
   - Press **`1`** through **`9`** to pick any candidate instantly.
   - Use **`↓` / `↑`** arrow keys to browse suggestions, or **`Esc`** to keep English.
4. Click **Copy** to clipboard or **Download .txt** to save your text!
5. Includes quick Hindi symbols (`।`, `॥`, `ॐ`, `₹`), font size controls, word counters, dark/light themes, and an on-screen virtual keyboard.

---

### Method 2: Dedicated App Launchers (FeatherPad & LibreOffice)
If you want system-level Hindi typing **in specific software** without pressing any keyboard shortcuts:

1. Open **"FeatherPad (Hindi Notepad)"** directly from your Application Menu.
2. Type immediately in Hindi (`namaste` $\rightarrow$ **नमस्ते**)!
3. Or launch directly from your terminal:
   ```bash
   ./hinglish-to-hindi-typing.sh --launch featherpad
   # or
   ./hinglish-to-hindi-typing.sh --launch libreoffice
   ```
   *Your VS Code, terminals, and web browsers remain completely untouched in standard English.*

---

### Method 3: Per-Window Isolation (Global Desktop Toggle)
If you prefer switching keyboards dynamically across applications:

1. Focus any text field in FeatherPad, LibreOffice, or your browser.
2. Press **`Super + Space`** (Windows Key + Space) to toggle between English and Hindi.
3. **Per-Window Isolation is Enabled**:
   - Hindi is isolated **only to the window you toggled**!
   - When you click into **VS Code or your Terminal**, the keyboard **automatically stays in English**.
   - When you click back into FeatherPad, it remains in Hindi.
4. **Zero IntelliSense Conflict**:
   - **`Ctrl + Space` is never hijacked** and remains 100% dedicated to VS Code / IDE auto-complete.

---

## 3. Multiple Word Suggestions & Predictive Typing

When typing in phonetic Hinglish, an interactive candidate popup window appears next to your cursor:

```text
namaste ──┐
          ├─ 1. नमस्ते  (Top choice)
          ├─ 2. नमस्कार
          └─ 3. नमस्कर
```

### Candidate Selection Keys:
- **`Space` or `Enter`**: Commits the 1st (top) suggested candidate.
- **Numbers `1` – `9`**: Instantly commits candidate 1 through 9.
- **`Down` / `Up` / `Tab`**: Navigate and highlight through the candidate list.
- **`Escape`**: Dismisses the suggestions popup and commits raw input.

### Dual Typing Modes:
You can switch between predictive suggestion mode and direct 1-to-1 transliteration at any time:
```bash
./hinglish-to-hindi-typing.sh --suggestions    # Predictive mode with word suggestions (tb:hi:itrans)
./hinglish-to-hindi-typing.sh --direct         # Direct 1-to-1 transliteration without popup (m17n:hi:itrans)
```

---

## 4. Phonetic Typing Cheatsheet

### Common Phrases & Everyday Words
| Type (Hinglish) | Output (Hindi) | Meaning |
| :--- | :--- | :--- |
| `namaste` | **नमस्ते** | Hello / Greetings |
| `kya haal hai` | **क्या हाल है** | How are you? |
| `aap kaise ho` | **आप कैसे हो** | How are you? (Polite) |
| `mera bharat mahan` | **मेरा भारत महान** | My India is great |
| `dhanyavaad` | **धन्यवाद** | Thank you |
| `shubhkaamnaayein` | **शुभकामनाएं** | Best wishes |
| `main theek hoon` | **मैं ठीक हूँ** | I am fine |
| `OM` or `AUM` | **ॐ** | Sacred Om |

### Vowels & Matras (स्वर और मात्राएँ)
- `a` = **अ**, `aa` / `A` = **आ**, `i` = **इ**, `ii` / `ee` / `I` = **ई**, `u` = **उ**, `uu` / `oo` / `U` = **ऊ**
- `e` = **ए**, `ai` = **ऐ**, `o` = **ओ**, `au` = **औ**, `R^i` = **ऋ**

### Consonants (व्यंजन)
- `ka` = **क**, `kha` = **ख**, `ga` = **ग**, `gha` = **घ**
- `cha` = **च**, `chha` = **छ**, `ja` = **ज**, `jha` = **झ**
- `Ta` = **ट**, `Tha` = **ठ**, `Da` = **ड**, `Dha` = **ढ**, `Na` = **ण** (Capital T, D, N)
- `ta` = **त**, `tha` = **थ**, `da` = **द**, `dha` = **ध**, `na` = **न** (Small t, d, n)
- `pa` = **प**, `pha` / `fa` = **फ**, `ba` = **ब**, `bha` = **भ**, `ma` = **म**
- `ya` = **य**, `ra` = **र**, `la` = **ल**, `va` / `wa` = **व**
- `sha` = **श**, `Sha` = **ष**, `sa` = **स**, `ha` = **ह**
- `ksha` = **क्ष**, `tra` = **त्र**, `gya` = **ज्ञ**, `shra` = **श्र**

### Half Letters, Halant & Marks (आधा अक्षर)
- Skip the vowel or type a period (`.`) for halant:
  - `k` = **क्**
  - `sh` = **श्**
  - `namaste` (`na` + `ma` + `s` + `te`) $\rightarrow$ **नमस्ते**
  - `dilli` (`di` + `l` + `li`) $\rightarrow$ **दिल्ली**
- Anusvara (बिंदी `ं`): `M` or `n.` (e.g. `shAMti` $\rightarrow$ **शांति**)
- Chandrabindu (`ँ`): `.N` or `~M` (e.g. `A.Nkh` $\rightarrow$ **आँख**)
- Nukta consonants: `za` = **ज़**, `fa` = **फ़**, `kHa` = **ख़**, `gHa` = **ग़**

---

## 5. 100% Privacy & Security Guarantee

Unlike cloud-based tools (Google Input Tools, web extensions) that transmit keystrokes over the internet:

- **0 Bytes Network Traffic**: Powered by the local GNU `libm17n` library (`hi-itrans.mim`) and local Hunspell dictionary (`hi_IN`). Works 100% offline in airplane mode.
- **Zero Keylogging**: Transformations and candidate predictions are performed strictly in memory (RAM). Keystrokes are never logged to disk.
- **Zero Telemetry**: No tracking, analytics, or external API calls.
- **Safe Dotfile Management**: All configuration changes create timestamped `.bak` backups and use isolated tags (`# >>> HINGLISH_IBUS_CONFIG_START >>>`).

Verify offline security at any time:
```bash
sudo ss -tulpn | grep -E "ibus|m17n"   # Returns empty (no listening or outbound ports)
```

---

## 6. Script Commands & Management

| Command | Action |
| :--- | :--- |
| `./hinglish-to-hindi-typing.sh --web` | Launch Easy Hindi Typing offline localhost app (`127.0.0.1:8765`) |
| `./easy-hindi-typing.sh start` | Start Easy Hindi Typing background server and open default browser |
| `./easy-hindi-typing.sh stop` | Stop Easy Hindi Typing background server |
| `./easy-hindi-typing.sh status` | Check if Easy Hindi Typing server is active |
| `./hinglish-to-hindi-typing.sh autostart off` | Switch to On-Demand (disable IBus autostart on desktop login) |
| `./hinglish-to-hindi-typing.sh autostart on` | Switch to Auto-Start (enable IBus autostart on desktop login) |
| `./hinglish-to-hindi-typing.sh autostart status` | View current autostart mode |
| `./easy-hindi-typing.sh --install-desktop` | Install Easy Hindi Typing application menu shortcut |
| `./easy-hindi-typing.sh --uninstall` | Cleanly terminate server and remove application menu shortcut |
| `./hinglish-to-hindi-typing.sh` | Full setup with predictive suggestions, per-window isolation & app launchers |
| `./hinglish-to-hindi-typing.sh --suggestions` | Switch active engine to **Predictive Suggestions** (`tb:hi:itrans` with popup) |
| `./hinglish-to-hindi-typing.sh --direct` | Switch active engine to **Direct Transliteration** (`m17n:hi:itrans` without popup) |
| `./hinglish-to-hindi-typing.sh --app-only` | Setup **only** FeatherPad/LibreOffice launchers (leaves OS dotfiles untouched) |
| `./hinglish-to-hindi-typing.sh --launch [app]` | Launch FeatherPad or LibreOffice directly in Hindi mode |
| `./hinglish-to-hindi-typing.sh --check` | Audit package status, daemon, environment, and privacy |
| `./hinglish-to-hindi-typing.sh --test` | Display phonetic cheatsheet & selection key tips in terminal |
| `./hinglish-to-hindi-typing.sh --uninstall` | Cleanly revert all IBus/m17n configurations, remove dotfiles and launchers |
| `./hinglish-to-hindi-typing.sh --help` | Display options help menu |

---

### Clean Uninstallation Guide

To remove or revert Hindi typing components:

1. **Revert System-Wide IBus & Typing Configurations:**
   ```bash
   cd Setup-Hinglish
   ./hinglish-to-hindi-typing.sh --uninstall
   ```
   *Restores your original `.bashrc`, `.xprofile`, and IBus dconf keys from `.bak` backups and removes all desktop shortcuts.*

2. **Remove Easy Hindi Typing Web App & Launcher:**
   ```bash
   ./easy-hindi-typing.sh --uninstall
   ```
   *Stops the local web server and removes `~/.local/share/applications/easy-hindi-typing.desktop` and `~/.local/bin/easy-hindi-typing`.*

---

## 7. Troubleshooting

1. **Hotkey (`Super + Space`) does not switch:**  
   In GNOME (Ubuntu/Debian), open **Settings $\rightarrow$ Keyboard $\rightarrow$ Keyboard Shortcuts $\rightarrow$ Switch to next input source** and verify it is set to `Super + Space`.
2. **VS Code autocomplete conflict:**  
   `Ctrl + Space` is completely unbound from IBus, so IntelliSense will never be hijacked.
3. **Typing works in terminal but not in Chrome / VS Code:**  
   Environment variables in `~/.config/environment.d/ibus.conf` take effect across the entire desktop session upon login. Simply **log out and log back in** (or reboot).
4. **Characters or emojis display as boxes `[?]`:**  
   The script installs `fonts-lohit-deva` and `fonts-noto-color-emoji` automatically. Refresh your font cache with:
   ```bash
   fc-cache -f -v
   ```
