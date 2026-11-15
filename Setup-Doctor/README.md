# System Doctor & Suite Diagnostic Tool (`Setup-Doctor`)

A 1-click diagnostic health-check engine that audits your system's hardware, CPU vector instructions, RAM/swap capacity, GPU acceleration backends, CMOS battery/RTC clock status, and the installation readiness of all **Debian-Dev-Suite** modules.

---

## Quick Start

You can run the doctor directly from the repository root or from within this folder:

```bash
# From repository root:
chmod +x doctor.sh
./doctor.sh

# Or from this folder:
cd Setup-Doctor
chmod +x doctor.sh
./doctor.sh
```

---

## What It Checks

| Audit Area | What Is Inspected | Why It Matters |
|---|---|---|
| **OS & Init System** | Distribution name, Linux Kernel version, architecture (`x86_64`, `arm64`), and init system (`systemd` vs `SysVinit`). | Ensures compatibility for background daemons (Docker, `llama-server.service`). |
| **System Clock & RTC** | Evaluates the system time against the current era. | **Detects Year 2008 CMOS battery resets** that break SSL certificates and APT package updates. |
| **CPU Vector Math** | Checks for `AVX-512`, `AVX2`, `AVX`, `FMA`, and `SSE4.2` instruction sets. | Determines whether you should run modern `Setup-LLAMA-CPP` or legacy-safe `Setup-LLAMA-CPP-LEGACY`. |
| **RAM & Swap Space** | Total physical RAM, available RAM, and swap partition/file size. | Verifies whether your system can compile LLMs without running out of memory (OOM). |
| **GPU & Acceleration** | Checks for NVIDIA drivers (`nvidia-smi`), CUDA toolkit (`nvcc`), and Vulkan API loader. | Verifies whether GPU acceleration can be offloaded via CUDA or lightweight Vulkan. |
| **Module Audit** | Scans all suite modules (`Setup-LLAMA-CPP`, `Setup-Dev-Tools`, `Setup-Tmux`, `Setup-GDrive`, `Setup-Geany`, `Setup-MD-Viewer`, `Setup-Sync-Time`, `Setup-Config-Sync`, `Setup-Local-GitHub`, `Setup-Virtual-Box`, `Setup-Hinglish`, `Setup-Brightness`, `Setup-Deep-Sleep`, `Setup-Libre-Chat`, `Setup-GUI-Manager`, `Setup-Detailed-Conkey`). | Summarizes which developer tools are ready to use and which can still be installed. |

---

## Example Output

```text
==================================================================
  Debian Dev Suite — Master Diagnostic Health Check
==================================================================

=== 1. Operating System & Environment ===
  [✔] Distribution : MX Linux 23.2 Libretto
  [✔] Kernel & Arch : 6.1.0-18-amd64 (x86_64)
  [✔] Init System : systemd (Standard modern Linux services)

=== 2. System Clock & RTC Health ===
  [✔] Clock Health : Accurate (2026-09-21 14:15:00 IST)

=== 3. Processor & Memory ===
  [✔] Processor : Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz (8 cores)
  [✔] Vector Instructions : AVX2 AVX SSE4.2
  [✔] Physical RAM : 8.0 GB (7924 MB) — High capacity (Great for 7B/8B LLMs)
  [✔] Swap Space : 4096 MB active

=== 4. GPU & Acceleration Backends ===
  [✔] NVIDIA Driver : GeForce MX150 (2048 MiB via nvidia-smi)
  [✔] Vulkan API : Vulkan runtime / loader available

=== 5. Debian-Dev-Suite Modules Verification ===
  [✔] Setup-LLAMA-CPP : Installed at ~/llama.cpp (2 .gguf models in ~/models)
  [✔] Setup-Dev-Tools : 11/11 tools active (CLI tools, Git, Runtimes, AI Copilot)
  [✔] Setup-Tmux : Installed with ~/.tmux.conf configured
  [✔] Setup-GDrive : Active & mounted at ~/GoogleDrive
  [✔] Setup-Geany : Installed (12 dark themes detected)
  [✔] Setup-MD-Viewer : Active (Pandoc + Surf WebKitGTK)
  [✔] Setup-Sync-Time : Global sync-time utility installed
  [✔] Setup-Config-Sync : Active (2 local backup archives found)

=== Summary Report ===
  Total Audited Items : 14
  Passed / Optimal    : 14
  Warnings            : 0
  Failures            : 0

Excellent! Your Debian development environment is in top condition.
```
