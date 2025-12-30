# Zeroconf Installation

This document describes how zeroconf (Python mDNS/Bonjour library) is installed on the Raspberry Pi.

## Overview

Zeroconf is an optional dependency that enables mDNS/Bonjour service discovery. It's pre-compiled on one Pi and then distributed to others to avoid the 15+ minute compilation time on Raspberry Pi Zero hardware.

## Installation Methods

### 1. Automated Installation (deploy.sh)

The `deploy.sh` script automatically installs zeroconf if a pre-built package is available in `retrieved-packages/`:

```bash
./scripts/deploy.sh
```

### 2. Manual Installation (install-zeroconf.sh)

For standalone installation:

```bash
# Install to user site-packages (recommended)
./scripts/install-zeroconf.sh --user

# Install to system site-packages (requires sudo)
./scripts/install-zeroconf.sh --system
```

## Key Implementation Details

### Dependencies

Zeroconf requires the following dependency:
- **ifaddr** (>=0.1.7) - Network interface address detection

Both installation scripts automatically install this dependency before extracting zeroconf.

### PEP 668 Compliance

Newer versions of Raspberry Pi OS (Bookworm and later) enforce PEP 668, which prevents pip from modifying system Python packages. The installation scripts handle this by:

1. **User installations**: Using both `--user` and `--break-system-packages` flags
2. **System installations**: Using `--break-system-packages` with `sudo`

Example:
```bash
pip3 install --user --break-system-packages ifaddr
```

### Installation Process

1. **Check for existing installation** - Verifies if zeroconf is already installed
2. **Install dependencies** - Ensures ifaddr is available
3. **Upload archive** - Transfers the pre-built package to the Pi
4. **Create directory** - Ensures target site-packages directory exists
5. **Extract package** - Extracts zeroconf and its metadata to site-packages
6. **Verify installation** - Tests that zeroconf can be imported successfully

### Target Directory

By default, packages are installed to the **user site-packages** directory:
- Path: `/home/pi/.local/lib/python3.11/site-packages/`
- No sudo required
- Safer and more isolated

## Creating a Pre-built Package

To create a pre-built zeroconf package from a Pi that has it installed:

```bash
./scripts/retrieve-zeroconf.sh
```

This creates an archive in `retrieved-packages/` containing:
- `zeroconf/` - The package directory with compiled extensions
- `zeroconf-X.Y.Z.dist-info/` - Package metadata

The archive is named: `zeroconf-{version}-python{py_version}-{arch}.tar.gz`

Example: `zeroconf-0.148.0-python3.11-armv6l.tar.gz`

## Troubleshooting

### Import Error: No module named 'ifaddr'

**Cause**: The ifaddr dependency is missing.

**Solution**: Install ifaddr manually:
```bash
ssh pi@raspberrypi.local
pip3 install --user --break-system-packages ifaddr
```

### Installation Verification Failed

**Cause**: Package was extracted but cannot be imported.

**Solution**: Check Python's sys.path includes the installation directory:
```bash
python3 -c "import sys; print('\n'.join(sys.path))"
```

Ensure `/home/pi/.local/lib/python3.11/site-packages` is listed.

### PEP 668 Error

**Cause**: Older pip flags used on newer Raspberry Pi OS.

**Solution**: Use both `--user` and `--break-system-packages`:
```bash
pip3 install --user --break-system-packages <package>
```

## Architecture Notes

- **armv6l**: Raspberry Pi Zero, Zero W, Zero 2 W
- **armv7l**: Raspberry Pi 2, 3, 4 (32-bit OS)
- **aarch64**: Raspberry Pi 3, 4 (64-bit OS)

Pre-built packages are architecture-specific and must match the target Pi's architecture.

## Related Scripts

- `scripts/install-zeroconf.sh` - Standalone installation script
- `scripts/retrieve-zeroconf.sh` - Create pre-built package from existing installation
- `scripts/deploy.sh` - Full deployment including zeroconf installation







