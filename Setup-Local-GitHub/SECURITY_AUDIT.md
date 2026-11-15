# Security & Privacy Audit: Localhost Forgejo Hardening

This document provides a formal security assessment, threat model, and verification benchmark for the localhost Forgejo deployment implemented via `forgejo-localhost.sh` and `docker-compose.yml`.

---

## 1. Security Objectives & Threat Model

### Security Objectives
1. **Absolute Network Isolation**: The service must only be accessible from the local host (`127.0.0.1`). Any device connected to the same Wi-Fi, Ethernet switch, or VPN must receive a TCP RST / Connection Refused.
2. **Zero Telemetry & Egress**: The application must never emit outbound network connections to third-party services (CDNs, Gravatar, analytics, package registries, external mail servers, or update checkers).
3. **Defense-in-Depth Against Web Exploits**: Even if an attacker can manipulate browser interactions (e.g., via DNS rebinding or cross-origin requests), the forge must defend itself via strict CORS, CSRF, and SameSite cookie policies.
4. **Local Multi-User Isolation**: On shared Linux workstations, no non-root user other than the owner should be capable of reading repositories, database records, session files, or secrets.

---

## 2. Threat Vector Analysis & Countermeasures

| Threat Vector | Attack Scenario | Implemented Mitigation | Verification Check |
| :--- | :--- | :--- | :--- |
| **LAN Port Scan** | An unauthorized device on the local network scans subnet ports to detect internal services. | `HTTP_ADDR = 127.0.0.1`<br>`SSH_LISTEN_HOST = 127.0.0.1` | `ss -tulpn` shows `127.0.0.1`, never `0.0.0.0` or `*`. |
| **Installer Hijack** | An attacker accesses a newly started instance before the admin configures it, setting themselves as superuser. | `INSTALL_LOCK = true` is populated before the server process starts. | Forgejo web wizard route `/` redirects straight to `/user/login`. |
| **Open Registration Abuse** | Unauthorized parties create accounts on the instance. | `DISABLE_REGISTRATION = true`<br>`ENABLE_OPENID_SIGNUP = false` | The "Register" button and route `/user/sign_up` return 404 or redirect. |
| **Unauthenticated Snooping** | Attackers or local tools crawl the `/explore` or public repo endpoints. | `REQUIRE_SIGNIN_VIEW = true` | Unauthenticated requests to `/`, `/explore`, or `/<user>/<repo>` require HTTP Basic Auth or redirect to `/user/login`. |
| **Avatar / Gravatar Tracking** | Forgejo transmits MD5 email hashes to `gravatar.com`, leaking user identity and IP address to Automattic/third parties. | `DISABLE_GRAVATAR = true`<br>`ENABLE_FEDERATED_AVATAR = false` | Zero HTTP requests made to external avatar domains. |
| **Third-Party CDN Leakage** | Web assets (fonts, icons, JavaScript) are loaded from external CDNs (Google Fonts, unpkg, cdnjs). | `OFFLINE_MODE = true` | All static assets load from embedded Forgejo binary (`/assets/...`). |
| **Local File Snooping** | Another local user with a shell account on the machine reads `app.ini` to steal `SECRET_KEY` or read `forgejo.db`. | `umask 077`<br>`chmod 600` on files<br>`chmod 700` on directories | `stat -c "%a" custom/conf/app.ini` returns `600`. |
| **DNS Rebinding** | A malicious website tricks the user's browser into resolving `attacker.com` to `127.0.0.1` to issue authenticated requests. | `REVERSE_PROXY_LIMIT = 0`<br>`COOKIE_SAME_SITE = strict`<br>`DOMAIN = 127.0.0.1` | Host header validation and strict SameSite cookies reject cross-site forged requests. |
| **SSRF via Webhooks** | A repository webhook is configured to hit `169.254.169.254` or internal LAN infrastructure. | `ALLOWED_HOST_LIST = loopback` | Outbound webhook requests to external or LAN subnets are blocked by Forgejo's HTTP client. |

---

## 3. Configuration Security Directives

### `[server]` Section
```ini
PROTOCOL               = http
HTTP_ADDR              = 127.0.0.1      # Binds exclusively to loopback interface
HTTP_PORT              = 3000
DOMAIN                 = 127.0.0.1
ROOT_URL               = http://127.0.0.1:3000/
OFFLINE_MODE           = true           # Blocks external CDN downloads and fonts
DISABLE_SSH            = false
START_SSH_SERVER       = true
SSH_PORT               = 2222
SSH_LISTEN_HOST        = 127.0.0.1      # Binds SSH daemon strictly to loopback
SSH_DOMAIN             = 127.0.0.1
```
* **Rationale**: Binding exclusively to `127.0.0.1` guarantees that the network packet filter drops incoming SYN packets on non-loopback interfaces. `OFFLINE_MODE` enforces air-gapped web asset serving.

### `[service]` Section
```ini
DISABLE_REGISTRATION             = true   # Disables user registration
REQUIRE_SIGNIN_VIEW              = true   # Requires login to view any content
ENABLE_NOTIFY_MAIL               = false  # Disables outbound emails
ENABLE_CAPTCHA                   = false  # Disables external captcha services
DEFAULT_KEEP_EMAIL_PRIVATE       = true   # Hides email addresses by default
SHOW_USER_EMAIL                  = false  # Suppresses email display in UI
ALLOW_ONLY_EXTERNAL_REGISTRATION = false
```
* **Rationale**: Prevents accidental public exposure or data leaks. Any request without a valid session cookie or API token is redirected to the login page.

### `[picture]` Section
```ini
DISABLE_GRAVATAR        = true   # Prevents email hash transmission
ENABLE_FEDERATED_AVATAR = false  # Disables Libravatar queries
```
* **Rationale**: Gravatar transmits MD5(email) to third-party servers. Disabling this eliminates third-party tracking.

### `[security]` Section
```ini
INSTALL_LOCK                  = true   # Locks the web installer wizard
SECRET_KEY                    = <32-byte-hex>
INTERNAL_TOKEN                = <32-byte-hex>
REVERSE_PROXY_LIMIT           = 0
REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.1
PASSWORD_COMPLEXITY           = lower,upper,digit,spec
MIN_PASSWORD_LENGTH           = 12
COOKIE_SAME_SITE              = strict
```
* **Rationale**: `INSTALL_LOCK` closes the setup attack window. High-entropy keys generated via `openssl rand -hex 32` protect session signing. `COOKIE_SAME_SITE = strict` mitigates CSRF attacks.

---

## 4. Verification & Audit Playbook

Run these commands on the host to verify your setup:

### Test 1: Verify Socket Listeners
```bash
ss -tulpn | grep -E ':(3000|2222)'
```
* **Pass Criteria**: Both listeners must show `127.0.0.1:3000` and `127.0.0.1:2222`.
* **Fail Criteria**: Showing `0.0.0.0:3000` or `*:3000` or `:::3000`.

### Test 2: Verify LAN Rejection
```bash
# Get your LAN IP (e.g., 192.168.1.X)
LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
curl -m 2 "http://${LAN_IP}:3000"
```
* **Pass Criteria**: `curl: (7) Failed to connect ... Connection refused`.
* **Fail Criteria**: HTTP 200, 302, or 403 received.

### Test 3: Verify File System Permissions
```bash
stat -c "%a %n" ~/.local/share/dev-setups/forgejo/custom/conf/app.ini
stat -c "%a %n" ~/.local/share/dev-setups/forgejo/data
# If credentials.txt has not yet been deleted:
[ -f ~/.local/share/dev-setups/forgejo/credentials.txt ] && stat -c "%a %n" ~/.local/share/dev-setups/forgejo/credentials.txt
```
* **Pass Criteria**:
  * `app.ini`: `600`
  * `data/`: `700`
  * `credentials.txt` (if present): `600`

> [!TIP]
> **Credential Storage & Password Manager Best Practice**:
> * Forgejo stores salted password hashes (Argon2 / bcrypt) in `data/forgejo.db`. It does not read `credentials.txt` at runtime.
> * To minimize plaintext credential footprint on disk, move the generated credentials to an encrypted password manager (e.g. **KeePassXC**, Bitwarden) and delete `credentials.txt` (`rm ~/.local/share/dev-setups/forgejo/credentials.txt`).
> * The service continues to operate normally with zero dependency on the text file.

### Test 4: Verify Anonymous Access is Blocked
```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/explore/repos
```
* **Pass Criteria**: Returns `302` (Redirect to `/user/login`) or `401`/`403`.
* **Fail Criteria**: Returns `200 OK`.

### Test 5: Verify Registration Endpoint is Inactive
```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/user/sign_up
```
* **Pass Criteria**: Returns `404 Not Found` or `302 Redirect` to `/user/login`.
* **Fail Criteria**: Returns `200 OK`.

---

## 5. Security Checklist Summary

- [x] Web server bound strictly to loopback (`127.0.0.1:3000`)
- [x] SSH server bound strictly to loopback (`127.0.0.1:2222`)
- [x] External CDNs and font loading disabled (`OFFLINE_MODE = true`)
- [x] Gravatar and Libravatar lookups disabled
- [x] Web installer permanently locked (`INSTALL_LOCK = true`)
- [x] Public registration hard-disabled (`DISABLE_REGISTRATION = true`)
- [x] Anonymous repository browsing disabled (`REQUIRE_SIGNIN_VIEW = true`)
- [x] Embedded SQLite3 database with zero exposed network ports
- [x] Strict file permissions (`chmod 600` for configs, `chmod 700` for directories)
- [x] Cryptographically random 256-bit secrets for JWT, internal tokens, and session keys
- [x] Strict SameSite cookies enabled
- [x] Push-to-create enabled for frictionless authenticated developer workflow
