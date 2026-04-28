# Web UI Branding

Place your custom branding assets in this folder to replace the default
KasmVNC web UI branding with OpenCode branding.

## Files

| File | Purpose | Recommended Size |
|------|---------|------------------|
| `favicon.ico` | Browser tab icon | Multi-size ICO (16×16, 32×32, 48×48, 128×128, 256×256) |
| `icon.png` | Apple touch icon & PWA manifest | 180×180 PNG |

## How to provide the icons

### Option 1: Build-time (baked into the image)
1. Save your `favicon.ico` and `icon.png` into this `root/defaults/branding/` folder.
2. Re-build the image (`docker compose build`).

### Option 2: Runtime (no rebuild required)
1. Create a `branding/` folder next to your `docker-compose.yml`.
2. Save your `favicon.ico` and `icon.png` there.
3. Mount it into the container by uncommenting the volume in `docker-compose.yml`:

```yaml
    volumes:
      - ./opencode-data:/config
      - ./opencode-projects:/workspace
      - ./branding:/config/branding   # <-- add this
```

The container init script will automatically copy any files found in
`/config/branding/` over the default KasmVNC assets on startup.

## Getting the OpenCode icon

The official OpenCode dark logo is available at:
https://opencode.ai/_build/assets/preview-opencode-logo-dark-ZBwNGoYp.png

You can convert it to the required formats using tools like:
- [favicon.io](https://favicon.io/) (PNG → ICO converter)
- ImageMagick: `convert logo.png -define icon:auto-resize=256,128,64,48,32,16 favicon.ico`
- Gimp / Photoshop

## Title

The browser page title is controlled by the `TITLE` environment variable in
`docker-compose.yml`. It is already set to **OpenCode** by default.
