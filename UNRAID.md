# Unraid Deployment Guide

This guide covers deploying **OpenCode Desktop Docker** on [Unraid](https://unraid.net/) via the Community Applications (CA) plugin or a custom template.

---

## Prerequisites

- Unraid 6.10+ with the **Community Applications** plugin installed
- (Optional) Intel or AMD integrated GPU on your Unraid server for DRI3 acceleration
- (Optional) The **User Scripts** plugin if you want to automate updates

---

## Option 1: Add Template Directly (Fastest)

If you don't want to wait for CA store approval, you can add the template directly in a few clicks.

1. Go to the **Docker** tab in Unraid.
2. Click **Add Container**.
3. At the bottom of the page, switch to **Template** mode.
4. In the **Template URL** field, paste:
   ```
   https://raw.githubusercontent.com/djurcola/opencode-docker/main/unraid/opencode-desktop.xml
   ```
5. Click **Load Template**.
6. Review the settings (see [Configuration](#configuration) below).
7. Click **Apply**.

The container will download and start automatically.

---

## Option 2: Submit to Community Applications (CA) App Store

To make this template discoverable by all Unraid users through the CA app store:

1. Ensure your `unraid/opencode-desktop.xml` template is committed and pushed to your GitHub repository.
2. Post in the **Unraid Community Applications Template Requests** forum thread:
   - [https://forums.unraid.net/topic/87126-ca-application-policies-notes/](https://forums.unraid.net/topic/87126-ca-application-policies-notes/)
3. Provide:
   - Template name: `opencode-desktop`
   - Template URL: `https://raw.githubusercontent.com/djurcola/opencode-docker/main/unraid/opencode-desktop.xml`
   - Support thread: Your GitHub Issues page
   - Brief description of what the container does

A moderator will review and add it to the CA store, usually within a few days.

---

## Configuration

When you add the container, the following fields are exposed in the Unraid UI:

### Required / Recommended

| Name | Default | Description |
|------|---------|-------------|
| **Appdata** | `/mnt/user/appdata/opencode-desktop` | Persistent storage for OpenCode config, auth, cache, plugins, and desktop settings. Maps to `/config` inside the container. |
| **Workspace** | `/mnt/user/opencode-projects` | Your code projects. Create subfolders here (e.g. `project-a`, `project-b`). Maps to `/workspace` inside the container. |
| **Web UI** | `3000` | The port to access the KasmVNC web interface. Change if port 3000 is already in use. |
| **Timezone** | `Etc/UTC` | Your local timezone (e.g. `Europe/London`, `America/New_York`). |
| **Password** | *(blank)* | Optional password for the KasmVNC web UI. Leave blank for no authentication. |

### Advanced Settings

| Name | Default | Description |
|------|---------|-------------|
| **PUID** | `99` | User ID. Unraid default is 99 (nobody). Change only if you know what you're doing. |
| **PGID** | `100` | Group ID. Unraid default is 100 (users). Change only if you know what you're doing. |
| **Docker Socket** | `/var/run/docker.sock` | Optional. Allows OpenCode to run Docker commands on your Unraid host. Disable if you don't need it. |
| **Extra Packages** | *(blank)* | Space-separated APT packages installed at container startup. Example: `golang-go ruby rustc cargo postgresql-client`. No need to rebuild the image. |
| **GPU** | *(blank)* | Optional Intel/AMD GPU device for DRI3 acceleration. Set to `/dev/dri` if your server has an iGPU. Leave blank otherwise. |

---

## Accessing the Desktop

Once the container is running:

1. Go to the **Docker** tab in Unraid.
2. Click the container icon or WebUI link for `opencode-desktop`.
3. Alternatively, open your browser and navigate to:
   ```
   http://<unraid-ip>:3000
   ```
4. If you set a password, enter it when prompted.
5. You will see the Ubuntu desktop with OpenCode Desktop already running.

---

## Managing Projects

1. Inside the OpenCode Desktop container, open the **File Manager** (PCManFM) or a terminal.
2. Navigate to `/workspace`.
3. Create a new folder for your project (e.g. `my-new-project`).
4. Open a terminal in that folder and run:
   ```bash
   opencode-cli
   /init
   ```
5. Repeat for each project.

All projects live in your host's `/mnt/user/opencode-projects` directory, so they persist even if the container is removed.

---

## Updating

### Update the container image

When a new OpenCode Desktop version is released, the GitHub Actions workflow automatically builds and pushes a new image.

To update on Unraid:

1. Go to the **Docker** tab.
2. Find `opencode-desktop`.
3. Click the container name, then click **Check for Updates** (or click the **Force Update** button).
4. Unraid will pull `ghcr.io/djurcola/opencode-desktop-docker:latest` and recreate the container.

Your config and projects are safe because they live in the mapped `/mnt/user/appdata` and `/mnt/user/opencode-projects` paths.

### Update notifications

Consider installing the **CA Auto Update** plugin from Community Applications. You can configure it to automatically update selected containers (including this one) when new images are available.

---

## Troubleshooting

### Black screen after login
- Check the container logs via Unraid: **Docker** tab → click the container icon → **Logs**.
- Ensure your server has enough free RAM (the desktop + Electron app need at least 2-4 GB).
- Try rebuilding with `--no-cache` if you modified the Dockerfile locally.

### Permission denied on workspace
- Ensure the **Appdata** and **Workspace** directories on your Unraid array/cache are writable by the nobody user (UID 99 / GID 100):
  ```bash
  chown -R 99:100 /mnt/user/appdata/opencode-desktop
  chown -R 99:100 /mnt/user/opencode-projects
  ```

### Cannot access Web UI
- Make sure port 3000 (or your custom port) is not already in use by another container or Unraid service.
- Check that the container is running and check the logs for errors.

### Plugins not persisting
- Make sure the **Appdata** path is correctly mapped and the container has read/write access.
- Plugins are stored in `/config/.config/opencode/plugins/` and cached in `/config/.cache/opencode/`.

---

## Reverse Proxy (Optional)

If you run [SWAG](https://github.com/linuxserver/docker-swag) or [Nginx Proxy Manager](https://github.com/NginxProxyManager/nginx-proxy-manager) on Unraid, you can put a reverse proxy in front of OpenCode Desktop.

### Important notes
- **WebSockets required:** KasmVNC uses WebSockets. Ensure your proxy forwards `Upgrade` and `Connection` headers.
- **Subdomain recommended:** KasmVNC does not natively support subpaths (e.g. `/opencode/`). Use a subdomain like `opencode.yourdomain.com`.
- **Authentication:** You can rely on KasmVNC's built-in password or offload auth to your reverse proxy / Authelia.

---

## Support

For bugs, feature requests, or help with this container:
- [Open an issue on GitHub](https://github.com/djurcola/opencode-docker/issues)

For OpenCode-specific questions:
- [OpenCode Documentation](https://opencode.ai/docs)
- [OpenCode Discord](https://opencode.ai/discord)
