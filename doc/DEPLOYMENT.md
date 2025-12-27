# Deployment

OVBuddy is deployed by copying `dist/` to the Pi and installing/refreshing systemd services.

## Prerequisites

- A booted Pi reachable over SSH
- `sshpass` on your workstation (required by `scripts/deploy.sh` for password auth)

## Create `.env` (required)

`scripts/deploy.sh` reads a `.env` file (project root).

```bash
cat > .env <<'EOF'
PI_HOST=ovbuddy.local
PI_USER=pi
PI_PASSWORD=your_password
EOF
```

Notes:
- `PI_HOST` can be an IP (recommended if `.local` isn’t resolving yet).
- `setup.env` is used by the SD-card script; it is **not** used by `deploy.sh`.

## Run deployment

```bash
cd scripts
./deploy.sh
```

What it does (high level):
- copies files to `/home/${PI_USER}/ovbuddy`
- installs Python/system dependencies
- installs/refreshes sudoers rules used by the web UI
- installs/refreshes Bonjour/mDNS fixes (Avahi)
- installs/refreshes systemd services (`ovbuddy`, `ovbuddy-web`, `ovbuddy-wifi`)

## Flags

- `-main`: deploy only `ovbuddy.py` (and web UI assets) for faster iteration
- `-reboot`: reboot after deploy and verify services come back
- `--skip-deploy`: skip file copy, but still run dependency/setup steps

Examples:

```bash
cd scripts
./deploy.sh -main
./deploy.sh -reboot
./deploy.sh --skip-deploy
```





