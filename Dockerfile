FROM ghcr.io/linuxserver/baseimage-kasmvnc:ubuntunoble

ARG OPENCODE_VERSION=v1.14.30
ARG TARGETARCH=amd64
ARG OPENCODE_DEB_URL=https://github.com/anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-desktop-linux-${TARGETARCH}.deb

# Install OpenCode Desktop dependencies and common development tools
RUN \
  echo "**** install runtime dependencies ****" && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    git \
    git-lfs \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    libgtk-3-0t64 \
    libwebkit2gtk-4.1-0 \
    libnss3 \
    libxss1 \
    libasound2t64 \
    libxtst6 \
    libxrandr2 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libcairo2 \
    libatspi2.0-0t64 \
    libdrm2 \
    libgbm1 \
    libxkbcommon0 \
    libx11-xcb1 \
    libxcb-dri3-0 \
    libxcb-xfixes0 \
    libglib2.0-0t64 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgcc-s1 \
    libstdc++6 \
    xdg-utils \
    xterm \
    pcmanfm \
    htop \
    nano \
    vim \
    jq \
    unzip \
    libva2 \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libegl1 \
    libglx-mesa0 \
    libgles2 \
    python3-xdg \
    && \
  echo "**** ensure X11 Unix socket directory exists ****" && \
  mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix && \
  echo "**** install OpenCode Desktop ****" && \
  wget -q "${OPENCODE_DEB_URL}" -O /tmp/opencode-desktop.deb && \
  (dpkg -i /tmp/opencode-desktop.deb || true) && \
  apt-get install -f -y --no-install-recommends && \
  test -x /usr/bin/OpenCode || { echo "ERROR: OpenCode binary not found after install"; exit 1; } && \
  rm -f /tmp/opencode-desktop.deb && \
  echo "**** add abc user to video/render groups for GPU access ****" && \
  { usermod -aG video abc 2>/dev/null || true; } && \
  { usermod -aG render abc 2>/dev/null || true; } && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/tmp/*

# Ensure X11 Unix socket directory persists (re-created here because /tmp
# is cleared above).  KasmVNC runs as non-root and cannot create this
# directory itself, which breaks local X clients such as openbox.
RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Copy custom init scripts and defaults
COPY root/ /

# Ensure init script is executable
RUN chmod +x /custom-cont-init.d/*.sh

# Copy custom branding assets (favicon.ico, icon.png) into the Kclient web root.
# These replace the default KasmVNC Client icons in the browser tab and PWA manifest.
# Place files in root/defaults/branding/ before building; missing files are ignored.
RUN \
  cp -f /defaults/branding/favicon.ico /kclient/public/favicon.ico 2>/dev/null || true && \
  cp -f /defaults/branding/icon.png /kclient/public/icon.png 2>/dev/null || true

# Expose KasmVNC web port
EXPOSE 3000
