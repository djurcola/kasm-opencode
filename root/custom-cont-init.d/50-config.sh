#!/bin/bash

# OpenCode Desktop Container Init Script
# Runs as root before services start

echo "**** OpenCode Desktop init started ****"

# Ensure the X11 Unix socket directory exists so local X clients (openbox)
# can connect to KasmVNC even when the container runs as a non-root user.
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Install extra packages if the EXTRA_PACKAGES environment variable is set
if [ -n "$EXTRA_PACKAGES" ]; then
    echo "**** Installing extra packages: $EXTRA_PACKAGES ****"
    apt-get update
    apt-get install -y --no-install-recommends $EXTRA_PACKAGES
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
fi

# Ensure OpenCode config directory exists
mkdir -p /config/.config/opencode

# Create a default global config if one does not already exist
if [ ! -f /config/.config/opencode/opencode.json ]; then
    echo "**** Creating default OpenCode global config ****"
    cat > /config/.config/opencode/opencode.json << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false
}
EOF
fi

# Ensure workspace directory exists
mkdir -p /workspace

# Fix ownership so the 'abc' user (mapped via PUID/PGID) can read/write everything
# LinuxServer base images handle most /config chowning automatically, but we
# touch the specific paths OpenCode uses to be safe.
chown -R abc:abc /config/.config/opencode /workspace 2>/dev/null || true

# Apply custom web UI branding from persistent /config/branding/ if present.
# This allows users to change icons at runtime without rebuilding the image.
if [ -d /config/branding ]; then
    if [ -f /config/branding/favicon.ico ]; then
        echo "**** Applying custom favicon from /config/branding/ ****"
        cp -f /config/branding/favicon.ico /kclient/public/favicon.ico
    fi
    if [ -f /config/branding/icon.png ]; then
        echo "**** Applying custom icon.png from /config/branding/ ****"
        cp -f /config/branding/icon.png /kclient/public/icon.png
    fi
fi

# When running CPU-only (no GPU), apply low-resource KasmVNC settings.
# These mirror the official Kasm Workspaces defaults which cap frame rate at
# 24 fps and prioritise bandwidth/CPU over visual fidelity.
if [ "${DISABLE_DRI}" = "true" ]; then
    echo "**** Applying CPU-only KasmVNC optimizations ****"
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

echo "**** OpenCode Desktop init finished ****"
