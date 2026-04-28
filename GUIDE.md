# Converting Desktop Apps to Browser-Based KasmVNC Containers

A comprehensive guide for packaging any desktop application (Electron, GTK, Qt, etc.) to run inside a LinuxServer KasmVNC container and be accessed via a web browser. This document captures every architectural decision, pitfall, and fix discovered while converting OpenCode Desktop.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Before You Start — Checklist](#2-before-you-start--checklist)
3. [Step-by-Step Conversion Guide](#3-step-by-step-conversion-guide)
4. [The Dockerfile — Reusable Patterns](#4-the-dockerfile--reusable-patterns)
5. [Runtime Configuration](#5-runtime-configuration)
6. [GitHub Actions CI/CD](#6-github-actions-cicd)
7. [Troubleshooting Encyclopedia](#7-troubleshooting-encyclopedia)
8. [Environment Variable Reference](#8-environment-variable-reference)
9. [Quick Command Reference](#9-quick-command-reference)
10. [Case Study: OpenCode Desktop](#10-case-study-opencode-desktop)

---

## 1. Architecture Overview

### Why KasmVNC + LinuxServer base image?

| Concern | How KasmVNC solves it |
|---------|----------------------|
| No native client needed | Runs entirely in the browser via WebSocket + HTML5 canvas |
| GPU acceleration optional | `-hw3d` flag for DRI3; falls back to CPU rendering seamlessly |
| Audio forwarding | Built-in PulseAudio → WebRTC audio streaming |
| Clipboard | Browser Clipboard API integration (with HTTPS or localhost) |
| Single sign-on | Basic auth, PAM, or LDAP via nginx reverse proxy |
| Container-native | Designed to run as non-root inside Docker/Podman |

### How the pieces fit together

```
Host Browser ──► nginx (port 3000) ──► KasmVNC WebSocket (port 6901)
                                              │
                                              ▼
                                        Xvnc X Server (:1)
                                              │
                                              ▼
                                        Openbox Window Manager
                                              │
                                              ▼
                                        Your Desktop App
```

### The LinuxServer service lifecycle (s6-overlay)

Understanding this is critical for debugging startup issues:

1. **init-os-end** → OS-level setup (users, permissions)
2. **init-kasmvnc** → Up trigger (no-op marker)
3. **init-kasmvnc-config** → Copies `/defaults/autostart` to `/config/.config/openbox/autostart` (only if missing!)
4. **init-video** → Detects `/dev/dri` devices and sets group permissions
5. **init-kasmvnc-end** → End-of-init marker
6. **init-config** → Runs `/custom-cont-init.d/*.sh` scripts (your custom setup)
7. **svc-pulseaudio** → Starts PulseAudio daemon
8. **svc-kasmvnc** → Starts `Xvnc :1` (runs as `abc` user)
9. **svc-kclient** → KasmVNC web client relay
10. **svc-nginx** → Starts nginx on port 3000
11. **svc-de** → Starts `/defaults/startwm.sh` → `/usr/bin/openbox-session` (runs as `abc`)

**Key insight:** `svc-de` depends on `svc-nginx`, which depends on `svc-kclient`, which depends on `svc-kasmvnc`. The X server must be up before Openbox starts.

---

## 2. Before You Start — Checklist

When converting a new app, gather this information first:

- [ ] **App type**: Electron, GTK, Qt, Java (Swing/AWT), generic X11?
- [ ] **Binary name and path**: e.g., `/usr/bin/OpenCode`, `/usr/bin/code`
- [ ] **Distribution format**: `.deb`, `.AppImage`, tarball, or build from source?
- [ ] **Runtime dependencies**: graphics libraries, audio, WebKit, etc.
- [ ] **Sandboxing requirements**: Does it need `--no-sandbox` in Docker?
- [ ] **GPU acceleration**: DRI3/OpenGL required, or CPU-only acceptable?
- [ ] **Config directory**: Where does it store settings? (usually `~/.config/<app>`)
- [ ] **Target base image**: `ubuntunoble`, `debianbookworm`, `alpine320`, etc.
- [ ] **Architecture**: `amd64` only, or `amd64` + `arm64`?

### Desktop app type quick-reference

| App Type | Typical flags in Docker | Common deps |
|----------|------------------------|-------------|
| Electron | `--no-sandbox --disable-gpu` | `libgtk-3-0`, `libnss3`, `libasound2`, `libxss1` |
| GTK/WebKit | None | `libwebkit2gtk-*`, `libgtk-3-0`, `libjavascriptcoregtk-*` |
| Qt | `-platform xcb` | `libqt5gui5`, `libqt5network5`, `libqt5widgets5` |
| Java/Swing | None | `default-jre`, `libxext6`, `libxrender1`, `libxtst6` |
| Generic X11 | None | `libx11-6`, `libxext6` |

---

## 3. Step-by-Step Conversion Guide

### Step 1: Choose your base image

```dockerfile
FROM ghcr.io/linuxserver/baseimage-kasmvnc:ubuntunoble
```

Available variants: `ubuntunoble`, `debianbookworm`, `alpine320`, `fedora41`, etc. Ubuntu Noble is recommended for the widest package compatibility.

### Step 2: Identify and install dependencies

Always start with a minimal set, test, and add missing libraries incrementally.

**Minimal starter set for Electron/GTK apps:**
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl ca-certificates \
    libgtk-3-0t64 \
    libnss3 \
    libxss1 \
    libasound2t64 \
    libxtst6 \
    libxrandr2 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libpango-1.0-0 \
    libcairo2 \
    libatspi2.0-0t64 \
    libdrm2 \
    libgbm1 \
    libxkbcommon0 \
    libglib2.0-0t64 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgcc-s1 \
    libstdc++6 \
    xdg-utils
```

**How to find missing libraries:**
```bash
# Inside the container after install
ldd /usr/bin/YourApp | grep "not found"

# Or run the app and check stderr for missing .so files
```

### Step 3: Install the application

**From a .deb file:**
```dockerfile
ARG APP_VERSION=1.0.0
ARG APP_DEB_URL=https://example.com/releases/${APP_VERSION}/app.deb

RUN wget -q "${APP_DEB_URL}" -O /tmp/app.deb && \
    (dpkg -i /tmp/app.deb || true) && \
    apt-get install -f -y --no-install-recommends && \
    test -x /usr/bin/YourApp || { echo "ERROR: Binary not found"; exit 1; } && \
    rm -f /tmp/app.deb
```

**From an AppImage:**
```dockerfile
RUN wget -q "https://example.com/app.AppImage" -O /usr/bin/YourApp && \
    chmod +x /usr/bin/YourApp
```

**Build from source:**
```dockerfile
RUN git clone https://github.com/example/app.git /tmp/app && \
    cd /tmp/app && \
    make && make install && \
    rm -rf /tmp/app
```

### Step 4: Handle the X11 socket directory

**This is non-negotiable.** Add this as a separate RUN layer:

```dockerfile
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
```

And add this to your init script (`/custom-cont-init.d/10-setup.sh`):
```bash
#!/bin/bash
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
```

### Step 5: Create the autostart file

This launches your app when Openbox starts. Place it at `/root/defaults/autostart`:

```bash
#!/bin/bash

# Ensure DISPLAY is set
export DISPLAY=${DISPLAY:-:1}

# Wait for X server socket (prevents race conditions)
for i in $(seq 1 30); do
    if [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]; then
        break
    fi
    sleep 0.5
done

# Launch your app with Docker-specific flags
/usr/bin/YourApp --no-sandbox &
```

### Step 6: Create the init script

Place at `/root/custom-cont-init.d/10-setup.sh`:

```bash
#!/bin/bash

# Ensure X11 socket directory exists
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Ensure app config directory exists
mkdir -p /config/.config/yourapp

# Create default config if missing
if [ ! -f /config/.config/yourapp/settings.json ]; then
    cat > /config/.config/yourapp/settings.json << 'EOF'
{ "autoupdate": false }
EOF
fi

# Ensure workspace directory
mkdir -p /workspace

# Fix ownership (abc user is mapped via PUID/PGID)
chown -R abc:abc /config/.config/yourapp /workspace 2>/dev/null || true

# CPU-only optimizations (optional)
if [ "${DISABLE_DRI}" = "true" ]; then
    mkdir -p /config/.vnc
    cat > /config/.vnc/kasmvnc.yaml << 'EOF'
runtime_configuration:
  allow_client_to_override_kasm_server_settings: false
encoding:
  max_frame_rate: 24
  rect_encoding_mode:
    min_quality: 4
    max_quality: 7
  video_encoding_mode:
    enter_video_encoding_mode:
      time_threshold: 10
      area_threshold: 60%
EOF
    chown -R abc:abc /config/.vnc
fi
```

### Step 7: Assemble the Dockerfile

```dockerfile
FROM ghcr.io/linuxserver/baseimage-kasmvnc:ubuntunoble

ARG APP_VERSION=1.0.0
ARG TARGETARCH=amd64

# Install dependencies and app
RUN apt-get update && apt-get install -y --no-install-recommends \
    [your dependencies here] \
    && \
    wget -q "https://example.com/app-${APP_VERSION}.deb" -O /tmp/app.deb && \
    (dpkg -i /tmp/app.deb || true) && \
    apt-get install -f -y --no-install-recommends && \
    test -x /usr/bin/YourApp || { echo "ERROR: Binary not found"; exit 1; } && \
    rm -f /tmp/app.deb && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

# Persist X11 socket directory
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Copy custom files
COPY root/ /

# Make init scripts executable
RUN chmod +x /custom-cont-init.d/*.sh

EXPOSE 3000
```

### Step 8: Test locally before pushing to CI

```bash
docker compose build --no-cache
docker compose up -d
docker compose exec opencode-desktop ls -la /usr/bin/YourApp
docker compose exec opencode-desktop ls -la /tmp/.X11-unix/
docker compose logs -f
```

---

## 4. The Dockerfile — Reusable Patterns

### Pattern 1: The `/tmp/.X11-unix` Directory

**Why it matters:** Xvnc creates its Unix socket at `/tmp/.X11-unix/X1`. If the directory doesn't exist and Xvnc can't create it (running as non-root), no local X clients can connect.

**Anti-pattern (broken):**
```dockerfile
RUN mkdir -p /tmp/.X11-unix && \
    [do other stuff] && \
    rm -rf /tmp/*  # <-- Deletes the directory you just created
```

**Correct pattern:**
```dockerfile
RUN [install stuff] && \
    rm -rf /tmp/* /var/lib/apt/lists/*

RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
```

**Runtime safety net (in init script):**
```bash
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
```

### Pattern 2: Safe Shell Exit Handling

**Anti-pattern (broken — `|| true` swallows failures):**
```dockerfile
RUN test -x /usr/bin/App || { echo "ERROR"; exit 1; } && \
    usermod -aG video abc 2>/dev/null || true && \
    echo "This always runs even if test failed!"
```

**Correct pattern (braces isolate `|| true`):**
```dockerfile
RUN test -x /usr/bin/App || { echo "ERROR"; exit 1; } && \
    { usermod -aG video abc 2>/dev/null || true; } && \
    { usermod -aG render abc 2>/dev/null || true; } && \
    echo "Only runs if test passed"
```

### Pattern 3: Ubuntu Package Name Compatibility

Package names change between Ubuntu releases. Always verify on the target version.

| Package | 22.04 (Jammy) | 24.04 (Noble) |
|---------|---------------|---------------|
| EGL library | `libegl1-mesa` | `libegl1` |
| GLES library | `libgles2-mesa` | `libgles2` |
| GTK3 | `libgtk-3-0` | `libgtk-3-0t64` |
| WebKit | `libwebkit2gtk-4.0-37` | `libwebkit2gtk-4.1-0` |
| ASound | `libasound2` | `libasound2t64` |

**How to find the correct name:**
```bash
docker run --rm ghcr.io/linuxserver/baseimage-kasmvnc:ubuntunoble \
    apt-cache search libegl | grep "^libegl"
```

### Pattern 4: Binary Verification

Always verify critical binaries exist after installation. This catches silent `.deb` failures.

```dockerfile
RUN wget -q "${URL}" -O /tmp/pkg.deb && \
    (dpkg -i /tmp/pkg.deb || true) && \
    apt-get install -f -y && \
    test -x /usr/bin/YourApp || { echo "ERROR: Binary missing"; exit 1; } && \
    rm -f /tmp/pkg.deb
```

### Pattern 5: Electron-Specific Docker Flags

Electron apps inside Docker need `--no-sandbox` because they can't use Chromium's setuid sandbox when not running as root:

```bash
/usr/bin/YourApp --no-sandbox &
```

Additional flags for stubborn Electron apps:
```bash
/usr/bin/YourApp --no-sandbox --disable-gpu --disable-dev-shm-usage &
```

### Pattern 6: Waiting for the X Server

Openbox's autostart runs immediately when Openbox starts, but the X server socket may not be ready yet.

```bash
export DISPLAY=${DISPLAY:-:1}
for i in $(seq 1 30); do
    [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ] && break
    sleep 0.5
done
/usr/bin/YourApp --no-sandbox &
```

---

## 5. Runtime Configuration

### docker-compose.yml template

```yaml
services:
  your-app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: your-app
    environment:
      # User mapping
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC

      # Prevent CPU spin-wait in image encoding libs
      - GOMP_SPINCOUNT=0
      - OMP_WAIT_POLICY=PASSIVE

      # Optional: basic auth password
      - PASSWORD=yourpassword

      # Optional: disable GPU probing for CPU-only hosts
      - DISABLE_DRI=true

      # Optional: extra packages to install at startup
      - EXTRA_PACKAGES=
    volumes:
      # Persistent config, auth, cache
      - ./app-data:/config

      # Your projects/workspace
      - ./projects:/workspace

      # Optional: Docker socket passthrough
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "3000:3000"
    shm_size: 512m      # Critical for WebKitGTK
    devices:
      # Optional: GPU passthrough
      - /dev/dri:/dev/dri
    restart: unless-stopped
```

### Key environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `PUID` | `1000` | Maps container `abc` user to host UID |
| `PGID` | `1000` | Maps container `abc` group to host GID |
| `TZ` | `Etc/UTC` | Container timezone |
| `PASSWORD` | *(none)* | Enables basic auth on port 3000 |
| `DISABLE_DRI` | *(unset)* | Set to `true` for CPU-only mode |
| `NO_DECOR` | *(unset)* | Removes window borders |
| `NO_FULL` | *(unset)* | Prevents Openbox auto-maximizing windows |
| `EXTRA_PACKAGES` | *(none)* | Space-separated apt packages to install at startup |

### Persistent data structure

```
./app-data/
├── .config/
│   ├── openbox/
│   │   ├── autostart      # Copied once from /defaults/autostart
│   │   └── menu.xml       # Openbox right-click menu
│   └── yourapp/           # Application-specific config
├── .vnc/
│   └── kasmvnc.yaml       # KasmVNC settings (encoding, framerate)
├── .local/
│   └── share/
│       └── yourapp/       # App data, databases, cache
└── ssl/
    ├── cert.pem           # Self-signed cert (auto-generated)
    └── cert.key
```

**Important:** `/defaults/autostart` is only copied to `/config/.config/openbox/autostart` on **first run**. If you modify it, delete the cached copy:
```bash
rm -f ./app-data/.config/openbox/autostart
```

---

## 6. GitHub Actions CI/CD

### Workflow design principles

1. **Multi-arch support** from day one (`linux/amd64` + `linux/arm64`)
2. **Version tracking** — auto-detect upstream releases
3. **Clean builds** during active development (`no-cache: true`)
4. **Cache re-enable** once stable for faster builds

### Recommended workflow structure

```yaml
name: Build and Push Docker Image

on:
  workflow_dispatch:
    inputs:
      app_version:
        description: 'App version to build'
        required: false
        default: ''
        type: string
  push:
    branches: [main]
    paths:
      - 'Dockerfile'
      - 'root/**'
      - '.github/workflows/build.yml'
  schedule:
    - cron: '0 6 * * *'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  check-release:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.get-version.outputs.version }}
      build_needed: ${{ steps.check.outputs.build_needed }}
    steps:
      - uses: actions/checkout@v4
      - id: current
        run: |
          CURRENT=$(grep 'ARG APP_VERSION=' Dockerfile | head -1 | sed 's/.*=//')
          echo "version=$CURRENT" >> $GITHUB_OUTPUT
      - id: latest
        run: |
          if [ -n "${{ github.event.inputs.app_version }}" ]; then
            LATEST="${{ github.event.inputs.app_version }}"
          else
            LATEST=$(curl -s https://api.github.com/repos/OWNER/REPO/releases/latest | jq -r '.tag_name')
          fi
          echo "version=$LATEST" >> $GITHUB_OUTPUT
      - id: check
        run: |
          if [ "${{ steps.current.outputs.version }}" != "${{ steps.latest.outputs.version }}" ] || \
             [ "${{ github.event_name }}" = "push" ] || \
             [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            echo "build_needed=true" >> $GITHUB_OUTPUT
          else
            echo "build_needed=false" >> $GITHUB_OUTPUT
          fi
      - id: get-version
        run: echo "version=${{ steps.latest.outputs.version }}" >> $GITHUB_OUTPUT

  build-and-push:
    needs: check-release
    if: needs.check-release.outputs.build_needed == 'true'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    strategy:
      fail-fast: false
      matrix:
        include:
          - platform: linux/amd64
            targetarch: amd64
          - platform: linux/arm64
            targetarch: arm64
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          platforms: ${{ matrix.platform }}
          push: true
          no-cache: true   # Remove once stable; re-add cache-from/cache-to
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ matrix.targetarch }}-${{ needs.check-release.outputs.version }}
          build-args: |
            APP_VERSION=${{ needs.check-release.outputs.version }}
            TARGETARCH=${{ matrix.targetarch }}

  create-manifest:
    needs: [check-release, build-and-push]
    if: always() && needs.build-and-push.result == 'success'
    runs-on: ubuntu-latest
    steps:
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/setup-buildx-action@v3
      - run: |
          VERSION="${{ needs.check-release.outputs.version }}"
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}"
          docker buildx imagetools create \
            -t "$IMAGE:latest" \
            -t "$IMAGE:$VERSION" \
            "$IMAGE:amd64-$VERSION" \
            "$IMAGE:arm64-$VERSION"
```

### Clearing stale artifacts

**GitHub Actions cache:**
```bash
gh cache delete --all -R owner/repo
```

**GHCR images:**
```bash
# List versions
gh api /users/OWNER/packages/container/REPO/versions \
  --jq '.[] | {id, tags: .metadata.container.tags}'

# Delete version by ID
gh api -X DELETE /users/OWNER/packages/container/REPO/versions/12345678
```

**Web UI:** `https://github.com/OWNER/REPO/pkgs/container/REPO`

---

## 7. Troubleshooting Encyclopedia

### Black screen / no desktop

**Symptoms:** Browser connects but screen is black; no Openbox; error about display.

**Causes & fixes:**

| Root cause | Diagnostic | Fix |
|------------|-----------|-----|
| Missing `/tmp/.X11-unix` | `ls /tmp/.X11-unix` → "No such file" | Add persistent `RUN` layer + runtime init script |
| Stale cached autostart | File doesn't have `DISPLAY` export | `rm -f ./data/.config/openbox/autostart` |
| Race condition | App starts before X socket ready | Add socket wait loop in autostart |
| OpenCode binary missing | `ls /usr/bin/OpenCode` → missing | Fix package names or `.deb` install step |
| Wrong `DISPLAY` | `echo $DISPLAY` → empty | Add `export DISPLAY=${DISPLAY:-:1}` |

### App binary missing after build

**Symptoms:** Container starts but autostart reports `/usr/bin/App: not found`.

**Causes:**
1. Package names wrong → `apt-get install` failed silently
2. `.deb` download failed → `wget` exited 0 but file is empty/error HTML
3. `dpkg -i` failed → `.deb` has unmet dependencies that `apt-get install -f` couldn't resolve

**Fix:** Add `test -x /usr/bin/App` verification after install. Check build logs for `E: Unable to locate package` or `dpkg: error`.

### "Database is locked" (SQLite)

**Symptoms:** App launches but shows "cannot reach local server"; logs show `SQLiteError: database is locked`.

**Cause:** Previous container crash left stale WAL/SHM files.

**Fix:**
```bash
docker compose down
rm -f ./data/.local/share/app/*.db-*
docker compose up -d
```

### Clipboard not working

**Symptoms:** Can't copy-paste between host and remote app.

**Cause:** Browser Clipboard API blocked on non-localhost HTTP origins.

**Fixes:**
1. Access via `http://localhost:3000` (using SSH port forwarding)
2. Use HTTPS (reverse proxy with valid cert)
3. Use the KasmVNC clipboard overlay (manual paste buffer)

### High CPU usage

**Symptoms:** Fan spins up; container uses 100%+ CPU.

**Causes & fixes:**

| Cause | Fix |
|-------|-----|
| Missing `shm_size` | Set `shm_size: 512m` in compose |
| WebKit software compositing | Set `WEBKIT_DISABLE_COMPOSITING_MODE=1` |
| KasmVNC probing for GPU | Set `DISABLE_DRI=true` |
| Image encoding spin-wait | Set `GOMP_SPINCOUNT=0` and `OMP_WAIT_POLICY=PASSIVE` |

### Build succeeds but image is broken

**Symptoms:** CI shows green checkmark, but running container has missing files.

**Cause:** `|| true` in Dockerfile swallowed an `exit 1`.

**Fix:** Wrap `|| true` in braces: `{ cmd || true; }`

---

## 8. Environment Variable Reference

### LinuxServer KasmVNC base image

| Variable | Description |
|----------|-------------|
| `DISPLAY` | X display (default `:1`) |
| `HOME` | User home (default `/config`) |
| `PUID` | User ID to map `abc` to |
| `PGID` | Group ID to map `abc` to |
| `TZ` | Timezone |
| `PASSWORD` | Basic auth password |
| `HASHED_PASSWORD` | Pre-hashed basic auth password |
| `DISABLE_DRI` | Set to `true` to disable GPU probing |
| `DRINODE` | Override DRI render node path |
| `NO_DECOR` | Remove Openbox window decorations |
| `NO_FULL` | Don't auto-maximize windows |
| `CUSTOM_PORT` | Override web port (default 3000) |
| `CUSTOM_HTTPS_PORT` | Override HTTPS port (default 3001) |
| `SUBFOLDER` | Serve under a subpath |
| `EXTRA_PACKAGES` | Space-separated apt packages to install at startup |

### Common Electron/GTK app variables

| Variable | Effect |
|----------|--------|
| `WEBKIT_DISABLE_COMPOSITING_MODE=1` | Disables GPU compositing in WebKitGTK |
| `ELECTRON_ENABLE_LOGGING=1` | Enables Electron internal logging |
| `GTK_THEME=Adwaita:dark` | Forces dark GTK theme |

---

## 9. Quick Command Reference

```bash
# Fresh local build
docker compose down
docker compose build --no-cache
docker compose up -d

# Verify binary exists
docker compose exec app ls -la /usr/bin/YourApp

# Check X11 socket
docker compose exec app ls -la /tmp/.X11-unix/

# View logs
docker compose logs -f app

# Enter container shell
docker compose exec app bash

# Reset cached autostart
docker compose down
rm -f ./data/.config/openbox/autostart
docker compose up -d

# Clear stale SQLite locks
docker compose down
rm -f ./data/.local/share/app/*.db-*
docker compose up -d

# Check missing libraries
docker compose exec app ldd /usr/bin/YourApp | grep "not found"

# Force pull latest GHCR image
docker compose pull
docker compose up -d

# Build specific platform locally
docker buildx build --platform linux/amd64 --no-cache -t test-build .
```

---

## 10. Case Study: OpenCode Desktop

This project converted [OpenCode Desktop](https://github.com/anomalyco/opencode) (an Electron app) to run in KasmVNC.

### What OpenCode needs

- Electron runtime (Chromium-based)
- GTK3 + WebKit2GTK (for native dialogs)
- Audio (libasound)
- No sandbox (runs as non-root in Docker)

### Dependencies installed

```dockerfile
libgtk-3-0t64 libwebkit2gtk-4.1-0 libnss3 libxss1 libasound2t64 \
libxtst6 libxrandr2 libxcomposite1 libxdamage1 libxfixes3 \
libpango-1.0-0 libpangocairo-1.0-0 libcairo2 libatspi2.0-0t64 \
libdrm2 libgbm1 libxkbcommon0 libx11-xcb1 libxcb-dri3-0 \
libxcb-xfixes0 libglib2.0-0t64 libdbus-1-3 libexpat1 \
libfontconfig1 libgcc-s1 libstdc++6 xdg-utils xterm pcmanfm \
htop nano vim jq unzip libva2 mesa-va-drivers mesa-vulkan-drivers \
libegl1 libglx-mesa0 libgles2 python3-xdg
```

### Bugs discovered and fixed

1. **Missing `/tmp/.X11-unix`** → Black screen. Fixed by persistent RUN layer + runtime init.
2. **Wrong Mesa package names** (`libegl1-mesa` vs `libegl1`) → OpenCode binary never installed.
3. **Shell precedence trap** (`|| true` swallowing `exit 1`) → Broken images pushed as "successful".
4. **Stale SQLite WAL files** → "Cannot reach local server" error on restart.
5. **Race condition in autostart** → Added socket wait loop.

### Files in this project

```
.
├── Dockerfile
├── docker-compose.yml
├── .github/workflows/build.yml
├── root/
│   ├── custom-cont-init.d/50-config.sh
│   └── defaults/
│       ├── autostart
│       └── menu.xml
└── GUIDE.md
```

---

*This guide is designed to be self-contained. For any new desktop app conversion, start at [Section 2: Before You Start](#2-before-you-start--checklist) and work through [Section 3: Step-by-Step Conversion Guide](#3-step-by-step-conversion-guide). When something breaks, consult [Section 7: Troubleshooting Encyclopedia](#7-troubleshooting-encyclopedia).*
