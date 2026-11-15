# How-To-Use Guide: Lightweight Containers & LazyDocker

A guide to running Docker and Podman containers efficiently on Debian and MX Linux using **native Linux cgroups** and the **LazyDocker TUI**—eliminating the multi-gigabyte memory footprint of Docker Desktop.

---

## Table of Contents

- [Why Native Linux Containers Beat Docker Desktop](#why-native-linux-containers-beat-docker-desktop)
- [Running Docker Without Sudo](#running-docker-without-sudo)
- [Managing the Container Service (SysVinit vs Systemd)](#managing-the-container-service-sysvinit-vs-systemd)
- [Essential Docker CLI Commands](#essential-docker-cli-commands)
- [LazyDocker: Visual Terminal Container Management](#lazydocker-visual-terminal-container-management)
  - [Opening LazyDocker](#opening-lazydocker)
  - [Main Panels](#main-panels)
  - [Key Shortcuts](#key-shortcuts)
- [Pruning Unused Containers & Images](#pruning-unused-containers--images)

---

## Why Native Linux Containers Beat Docker Desktop

On Windows and macOS, Docker requires a virtual machine running a Linux kernel. "Docker Desktop" wraps this VM in a heavy Electron graphical interface, consuming **2 GB to 3.5 GB of RAM** just idling in the background.

On **Linux (Debian, MX Linux, antiX)**, containers run natively using the host Linux kernel's built-in namespaces and control groups (`cgroups`).

- **Idle RAM:** **~30 MB to 50 MB** (98% memory reduction!).
- **Startup:** Instantaneous; no virtual machine to boot up.
- **Disk I/O:** Direct bare-metal disk speeds without VM filesystem translation layer lag.

---

## Running Docker Without Sudo

The installer automatically configures non-root access by adding your user to the `docker` group.

Verify non-root access:
```bash
docker ps
```

> [!NOTE]
> If you just ran the installer, reload your user group in your current shell:
> ```bash
> newgrp docker
> ```
> Or log out and log back into your desktop session.

---

## Managing the Container Service (SysVinit vs Systemd)

MX Linux and antiX offer flexible init systems. Here is how to control the background Docker service on both:

### Systemd Systems (Standard Debian & MX Linux with systemd):
```bash
# Check if Docker is running
sudo systemctl status docker

# Start Docker daemon
sudo systemctl start docker

# Stop Docker daemon (saves RAM when not in use!)
sudo systemctl stop docker

# Prevent Docker from starting automatically on boot
sudo systemctl disable docker
```

### SysVinit Systems (Default antiX & MX Linux SysVinit mode):
```bash
# Check service status
sudo service docker status

# Start Docker daemon
sudo service docker start

# Stop Docker daemon
sudo service docker stop
```

---

## Essential Docker CLI Commands

```bash
# Run a lightweight Alpine Linux test container interactively
docker run --rm -it alpine sh

# Run an Nginx web server on port 8080
docker run -d --name web -p 8080:80 nginx:alpine

# List active containers
docker ps

# List all containers (including stopped)
docker ps -a

# View container logs
docker logs -f web

# Open a shell inside a running container
docker exec -it web sh

# Stop and remove container
docker stop web
docker rm web
```

---

## LazyDocker: Visual Terminal Container Management

**`lazydocker`** is a lightning-fast terminal UI written in Go that lets you inspect, monitor, and manage your containers and images with single keystrokes.

### Opening LazyDocker

Run either command in your terminal:
```bash
lazydocker
# or use the quick alias:
lz
```

```text
┌─────────────────┬──────────────────────────────────────────┐
│ [1] Containers  │ [Main Panel]                             │
│ [2] Services    │ Real-time ASCII CPU & Memory graphs,     │
│ [3] Images      │ live streaming container logs,           │
│ [4] Volumes     │ and environment variable inspections     │
└─────────────────┴──────────────────────────────────────────┘
```

---

### Main Panels

- <kbd>1</kbd> : Jump to **Containers** panel.
- <kbd>2</kbd> : Jump to **Services** panel (Docker Compose).
- <kbd>3</kbd> : Jump to **Images** panel.
- <kbd>4</kbd> : Jump to **Volumes** panel.
- <kbd>[</kbd> / <kbd>]</kbd> : Cycle between sub-tabs (Logs, Stats, Config, Top).

---

### Key Shortcuts

| Key | Action |
|---|---|
| <kbd>Enter</kbd> | Focus container logs |
| <kbd>s</kbd> | Stop selected container |
| <kbd>r</kbd> | Restart selected container |
| <kbd>d</kbd> | Remove (delete) container or image |
| <kbd>e</kbd> | Execute an interactive shell (`sh`/`bash`) inside the container |
| <kbd>m</kbd> | View logs in full screen |
| <kbd>q</kbd> | Quit LazyDocker |

---

## Pruning Unused Containers & Images

Reclaim gigabytes of disk space safely:

### Interactively in LazyDocker:
In the **Images** panel (<kbd>3</kbd>), press <kbd>d</kbd> on any unused image to delete it, or press <kbd>D</kbd> to prune all dangling images.

### Via Command Line:
```bash
# Remove stopped containers, unused networks, and dangling images
docker system prune -f

# Include unused volumes (use caution)
docker system prune --volumes
```
