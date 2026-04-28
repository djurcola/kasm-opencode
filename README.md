# OpenCode Desktop Docker

Run the [OpenCode](https://opencode.ai) Desktop application inside a browser-accessible Linux desktop container, built on [LinuxServer.io's KasmVNC base image](https://github.com/linuxserver/docker-baseimage-kasmvnc).

This provides a full desktop environment streamed to your browser, allowing you to use the OpenCode Desktop app (and CLI) from any device on your network without needing a dedicated VM.

---

## Features

- **Browser-based desktop** - Access OpenCode Desktop via any modern web browser at `http://docker-host:3000`
- **Persistent storage** - All OpenCode settings, authentication, plugins, and cache survive container restarts
- **Project workspace** - Map a host directory to `/workspace` and organise projects in subfolders
- **LinuxServer conventions** - Uses `PUID`/`PGID`, `TZ`, `/config` volume, and s6-overlay for easy maintenance
- **Optional GPU acceleration** - Pass through Intel/AMD iGPU for smoother desktop rendering
- **Optional Docker access** - Mount host Docker socket to let OpenCode run Docker commands
- **Runtime package installation** - Install additional dev tools on startup via the `EXTRA_PACKAGES` environment variable

---

## Prerequisites

- A Linux Docker host with Docker Engine and Docker Compose (v2) installed
- (Optional) Intel or AMD integrated GPU for DRI3 acceleration
- (Optional) A reverse proxy if you want external/SSL access
- (Optional) Unraid server with Community Applications plugin

---

## Quick Start

1. **Clone or copy this repository** to your Docker host.

2. **Create the data and projects directories** on your host:
   ```bash
   mkdir -p opencode-data opencode-projects
   ```

3. **Build and start the container**:
   ```bash
   docker compose up -d --build
   ```

4. **Open your browser** and navigate to:
   ```
   http://<docker-host-ip>:3000
   ```

   If you set a `PASSWORD`, you will be prompted for it. You will then see the Ubuntu desktop with OpenCode Desktop already running.

5. **Create project folders** inside `/workspace` (e.g., `/workspace/my-project`) and initialise OpenCode inside each one:
   ```bash
   cd /workspace/my-project
   opencode-cli
   /init
   ```

---

## Unraid

An official Unraid template is included for easy deployment via the Community Applications plugin.

- **Template file:** [`unraid/opencode-desktop.xml`](unraid/opencode-desktop.xml)
- **Full guide:** See [`UNRAID.md`](UNRAID.md) for step-by-step instructions, screenshots, and troubleshooting.

Quick steps for Unraid users:
1. Go to **Docker > Add Container** in Unraid.
2. Set **Template URL** to:
   ```
   https://raw.githubusercontent.com/djurcola/opencode-docker/main/unraid/opencode-desktop.xml
   ```
3. Click **Load Template**, adjust paths and ports, then **Apply**.

---

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PUID` | No | `1000` | User ID to run as inside the container |
| `PGID` | No | `1000` | Group ID to run as inside the container |
| `TZ` | No | `Etc/UTC` | Timezone (e.g. `Europe/London`) |
| `PASSWORD` | No | *(none)* | Password for the KasmVNC web UI |
| `EXTRA_PACKAGES` | No | *(none)* | Space-separated list of APT packages to install at container startup |

> **Tip:** You can copy `.env.example` to `.env`, edit the values, and add `env_file: - .env` to your `docker-compose.yml` if you prefer.

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `OPENCODE_VERSION` | `v1.14.28` | OpenCode Desktop GitHub release tag to install |
| `TARGETARCH` | `amd64` | Target architecture (`amd64` or `arm64`) |

To update OpenCode Desktop, change `OPENCODE_VERSION` in `docker-compose.yml` and run:
```bash
docker compose up -d --build
```

### Volumes

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `./opencode-data` | `/config` | Persistent OpenCode config, auth, cache, plugins, themes, and desktop settings |
| `./opencode-projects` | `/workspace` | Your code projects |
| `/var/run/docker.sock` | `/var/run/docker.sock` | *(Optional)* Host Docker socket for OpenCode Docker tools |

### Ports

| Host | Container | Purpose |
|------|-----------|---------|
| `3000` | `3000` | KasmVNC web interface |

---

## Installing Extra Development Tools

You can install additional packages without rebuilding the image by using the `EXTRA_PACKAGES` environment variable.

### docker-compose.yml example
```yaml
environment:
  - EXTRA_PACKAGES="golang-go ruby rustc cargo postgresql-client redis-tools"
```

### At runtime (one-off)
```bash
docker exec -it opencode-desktop bash
apt-get update && apt-get install -y <package-name>
```

> **Note:** Packages installed via `EXTRA_PACKAGES` are re-installed every time the container starts. Packages installed manually inside the running container will be lost when the container is recreated.

---

## Automated Builds with GitHub Actions

This repository includes a GitHub Actions workflow (`.github/workflows/build.yml`) that can automatically build and push multi-architecture Docker images to the **GitHub Container Registry (ghcr.io)**.

### What the workflow does

- **Checks for new OpenCode releases** every day at 06:00 UTC
- **Compares** the latest release with the version pinned in `Dockerfile`
- **Auto-updates** `Dockerfile` and commits the change when a new version is found
- **Builds** multi-arch images for `linux/amd64` and `linux/arm64`
- **Pushes** tagged images:
  - `ghcr.io/YOUR_USERNAME/opencode-desktop-docker:latest`
  - `ghcr.io/YOUR_USERNAME/opencode-desktop-docker:v1.x.x`
  - `ghcr.io/YOUR_USERNAME/opencode-desktop-docker:amd64-v1.x.x`
  - `ghcr.io/YOUR_USERNAME/opencode-desktop-docker:arm64-v1.x.x`

### Setup

1. Push this repository to GitHub.
2. Go to **Settings > Actions > General** and ensure **Workflow permissions** includes **Read and write permissions** (needed to push packages).
3. The workflow will run automatically on schedule. You can also trigger it manually from the **Actions** tab.

### Using the pre-built image

Instead of building locally, you can use the published image:

```yaml
services:
  opencode-desktop:
    image: ghcr.io/YOUR_USERNAME/opencode-desktop-docker:latest
    # Remove or comment out the 'build:' block
```

> **Important:** Replace `YOUR_USERNAME` with your actual GitHub username or organisation name.

### Manual triggers

You can manually trigger a build with a specific version from the GitHub Actions tab using **workflow_dispatch**. This is useful if you want to build an older version or force a rebuild.

---

## Updating

### Option 1: Use pre-built images (recommended with GitHub Actions)

If you have set up the GitHub Actions workflow, simply pull the latest image:
```bash
docker compose pull
docker compose up -d
```

### Option 2: Build locally

1. Check the [OpenCode releases page](https://github.com/anomalyco/opencode/releases) for the latest version.
2. Update the `OPENCODE_VERSION` build argument in `docker-compose.yml`.
3. Rebuild and restart:
   ```bash
   docker compose up -d --build
   ```

### Update the base image

LinuxServer regularly updates their base images. To pull the latest base image and rebuild:
```bash
docker compose pull
docker compose up -d --build
```

### Automated update notifications

Consider running [Diun](https://crazymax.dev/diun/) (Docker Image Update Notifier) to get notified when new images are available on ghcr.io.

---

## Reverse Proxy

You can place a reverse proxy in front of KasmVNC. The container exposes plain HTTP on port `3000`.

### Nginx example
```nginx
server {
    listen 443 ssl;
    server_name opencode.yourdomain.com;

    location / {
        proxy_pass http://opencode-desktop:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Important notes
- **WebSockets:** KasmVNC requires WebSocket support. Ensure your proxy forwards the `Upgrade` and `Connection` headers.
- **Path-based proxying:** KasmVNC does not natively support subpaths (e.g. `/opencode/`). Use a subdomain instead.
- **Authentication:** KasmVNC provides basic HTTP auth via the `PASSWORD` variable. For stronger security, offload authentication to your reverse proxy or Authelia/Authentik.

---

## GPU Acceleration

To enable DRI3 GPU acceleration for smoother desktop performance, pass your Intel or AMD render device into the container:

```yaml
devices:
  - /dev/dri:/dev/dri
```

> **NVIDIA:** KasmVNC DRI3 does **not** support the proprietary NVIDIA driver. It works with Intel (`i965`, `i915`) and AMD (`amdgpu`, `radeon`) open-source drivers only.

---

## CPU-Only / Low-Resource Mode

If your host does **not** have a compatible GPU (or you choose not to pass one through), KasmVNC and WebKitGTK will fall back to software rendering, which can consume a lot of CPU. You can enable automatic low-resource optimisations:

1. **Remove or comment out** the `/dev/dri` device mapping in `docker-compose.yml`.
2. **Uncomment** the following environment variables in `docker-compose.yml`:
   ```yaml
   environment:
     - DISABLE_DRI=true
     - WEBKIT_DISABLE_COMPOSITING_MODE=1
   ```

When `DISABLE_DRI=true` is set, the container automatically writes a CPU-optimised `kasmvnc.yaml` that:

- Caps the screen-capture frame rate to **24 fps** (matching official Kasm defaults)
- Lowers JPEG quality to **4–7** (more compression = less CPU)
- Requires **>60%** of the screen to change for **10 seconds** before entering “video mode”
- Prevents the browser client from overriding these server settings

`WEBKIT_DISABLE_COMPOSITING_MODE=1` stops OpenCode Desktop’s WebKitGTK engine from wasting CPU cycles trying to GPU-composite web content inside a software-only container.

**Trade-offs:** The desktop will feel slightly less “smooth” than a GPU-accelerated session. For writing code in OpenCode, the difference is usually negligible.

---

## Persistence & File Locations

Because the container uses LinuxServer's `/config` convention, all OpenCode data lives inside the mounted `./opencode-data` directory on your host.

| Inside container | On host (if mapped to `./opencode-data`) | Contents |
|------------------|------------------------------------------|----------|
| `/config/.config/opencode/` | `./opencode-data/.config/opencode/` | Global config (`opencode.json`, `tui.json`), plugins, agents, commands, themes |
| `/config/.local/share/opencode/` | `./opencode-data/.local/share/opencode/` | Auth tokens, logs, sessions |
| `/config/.cache/opencode/` | `./opencode-data/.cache/opencode/` | Provider package cache, `node_modules` for npm plugins |
| `/workspace/` | `./opencode-projects/` | Your code projects |

**Project-level OpenCode files** (e.g. `.opencode/plugins/`, `AGENTS.md`) should be committed to your individual project repositories inside `/workspace`.

---

## Docker-in-Docker vs. Docker Socket Passthrough

By default, the `docker-compose.yml` mounts the **host Docker socket** (`/var/run/docker.sock`) as read-only. This allows OpenCode to run Docker commands on the **host** Docker daemon. This is the recommended approach.

If you need true Docker-in-Docker isolation, you can run the container with `--privileged` and mount a dedicated volume for `/var/lib/docker`. See the [LinuxServer KasmVNC documentation](https://github.com/linuxserver/docker-baseimage-kasmvnc?tab=readme-ov-file#docker-in-docker-dind) for details.

---

## Troubleshooting

### OpenCode Desktop does not start
Check the container logs:
```bash
docker logs -f opencode-desktop
```

If you see sandbox-related errors, the `--no-sandbox` flag is already applied in the autostart script. You can also try running OpenCode manually inside the container:
```bash
docker exec -it opencode-desktop bash
/usr/bin/OpenCode --no-sandbox
```

### Permission denied on workspace files
Ensure the directories on your host are owned by the same user you specify with `PUID`/`PGID`:
```bash
sudo chown -R 1000:1000 ./opencode-data ./opencode-projects
```

### KasmVNC shows a black screen
This usually means OpenCode Desktop crashed or the autostart script failed. Check the logs and ensure all Electron dependencies are present. Rebuilding the image with `--no-cache` can help:
```bash
docker compose build --no-cache
docker compose up -d
```

### Plugins not persisting
Plugins installed via npm are cached in `/config/.cache/opencode/node_modules/`. If this directory is not inside your persistent volume, they will be lost on restart. Ensure your `./opencode-data` volume is correctly mapped.

---

## License

This wrapper is provided as-is for personal use. OpenCode itself is licensed under the MIT License.
