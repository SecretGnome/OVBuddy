# SSH Password Authentication Fix

## Problem

After setting up a Raspberry Pi Zero W using the `setup-sd-card.sh` script, the Pi boots successfully and is reachable via `ovbuddy.local`, but SSH password authentication fails with "Permission denied".

## Root Cause

The issue is with how the password hash is generated in the `setup-sd-card.sh` script. The script creates a `firstrun.sh` that runs on the Pi's first boot to configure the user account. The password hash generation has two potential issues:

1. **Hash Format Incompatibility**: Python's `crypt` module on macOS may generate password hashes in a format that's not fully compatible with Raspberry Pi OS's password system.

2. **Hash Method Mismatch**: Raspberry Pi OS Bookworm uses yescrypt for password hashing by default, but the script was using SHA-512, which may not work correctly with the `chpasswd -e` command in all cases.

## Solution

The fix uses OpenSSL to generate the password hash, which is more reliable and compatible:

```bash
# Use openssl passwd -6 to generate SHA-512 hash
PASSWORD_HASH=$(openssl passwd -6 "$USER_PASSWORD")
```

This ensures:
- The hash is in the correct format for Linux systems
- It's compatible with both `userconf` and `chpasswd -e` methods
- It works consistently across macOS and Linux development machines

## Changes Made

### 1. Updated `scripts/setup-sd-card.sh`

Modified the password hash generation (lines ~315-336) to:
- First try using `openssl passwd -6` (most reliable)
- Fall back to Python's `crypt` module if OpenSSL is not available
- Properly handle errors in both cases

### 2. Created `scripts/test-ssh.sh`

A diagnostic script that helps troubleshoot SSH connection issues:
- Tests network connectivity
- Verifies mDNS resolution
- Checks if SSH port is accessible
- Tests both key-based and password authentication
- Provides detailed error messages and troubleshooting tips

## How to Use

### If You Haven't Set Up the SD Card Yet

1. Update your `setup.env` file with the correct credentials:
   ```bash
   WIFI_SSID="your-wifi-name"
   WIFI_PASSWORD="your-wifi-password"
   WIFI_COUNTRY="CH"
   HOSTNAME="ovbuddy"
   USERNAME="pi"
   USER_PASSWORD="your-secure-password"
   ```

2. Run the setup script:
   ```bash
   cd scripts
   ./setup-sd-card.sh
   ```

3. After the Pi boots (wait 2-3 minutes for first boot + auto-reboot), test SSH:
   ```bash
   ./test-ssh.sh
   ```

### If You Already Set Up the SD Card

You have two options:

#### Option A: Recreate the SD Card (Recommended)

1. Run `./setup-sd-card.sh` again with the updated script
2. This ensures the password hash is generated correctly

#### Option B: Manual Password Reset

If you have a monitor and keyboard:

1. Connect monitor and keyboard to the Pi
2. Log in at the console (username from setup.env)
3. Change the password:
   ```bash
   passwd
   ```
4. Enter your desired password twice
5. Test SSH connection from your Mac

#### Option C: SSH Key Setup

If you can access the Pi through other means:

1. Generate an SSH key on your Mac (if you don't have one):
   ```bash
   ssh-keygen -t ed25519
   ```

2. Copy the key to the Pi:
   ```bash
   ssh-copy-id pi@ovbuddy.local
   ```

3. Update `.env` to use key-based auth (remove PI_PASSWORD line)

## Testing SSH Connection

Use the test script to diagnose connection issues:

```bash
cd scripts
./test-ssh.sh
```

The script will:
1. Test network connectivity (ping)
2. Verify mDNS resolution (ovbuddy.local)
3. Check if SSH port 22 is accessible
4. Test SSH key authentication
5. Test SSH password authentication

## Deployment After Fix

Once SSH is working, you can deploy OVBuddy:

```bash
cd scripts
./deploy.sh
```

The deploy script will:
- Copy all necessary files to the Pi
- Install Python dependencies
- Configure systemd services
- Set up passwordless sudo
- Enable SPI for the e-ink display

## Prevention

To avoid this issue in the future:

1. Always use the latest version of `setup-sd-card.sh`
2. Ensure OpenSSL is installed on your development machine
3. Test SSH connection immediately after first boot
4. Keep a backup of your `setup.env` file

## Related Files

- `scripts/setup-sd-card.sh` - SD card setup script (updated)
- `scripts/test-ssh.sh` - SSH connection test script (new)
- `scripts/deploy.sh` - Deployment script
- `setup.env` - Configuration file with credentials

## Technical Details

### Password Hash Formats

- **SHA-512** (`$6$`): Widely supported, used by the fix
- **yescrypt** (`$y$`): Newer, used by modern Raspberry Pi OS
- **SHA-256** (`$5$`): Older, less secure

The fix uses SHA-512 which is compatible with all Raspberry Pi OS versions.

### firstrun.sh Execution

The `firstrun.sh` script runs during the first boot via systemd:

1. Kernel command line includes `systemd.run=/boot/firstrun.sh`
2. Script runs before normal boot process
3. Sets hostname, creates user, configures WiFi, enables SSH
4. Removes itself and reboots the system
5. After reboot, system is fully configured

### userconf vs chpasswd

The script supports two methods:

1. **userconf** (newer): `/usr/lib/userconf-pi/userconf`
   - Preferred method on Bookworm and later
   - Handles password hashing automatically

2. **chpasswd -e** (older): Traditional method
   - Requires pre-hashed password
   - Used as fallback for older systems

## Troubleshooting

### "Permission denied" after entering password

- Password hash was not generated correctly
- Solution: Recreate SD card with updated script

### "Host key verification failed"

- SSH host key has changed (Pi was re-imaged)
- Solution: Remove old key: `ssh-keygen -R ovbuddy.local`

### "Connection refused"

- SSH service is not running
- Solution: Check if Pi finished first boot (wait 3-5 minutes)

### "No route to host"

- Pi is not on the network
- Solution: Check WiFi credentials in setup.env

### Pi boots but not accessible via ovbuddy.local

- mDNS not working properly
- Solution: Use IP address instead, or check avahi-daemon on Pi

## See Also

- [DEPLOYMENT_FIX.md](DEPLOYMENT_FIX.md) - Deployment troubleshooting
- [QUICK_FIX_GUIDE.md](QUICK_FIX_GUIDE.md) - Quick fixes for common issues
- [PASSWORDLESS_SUDO_FIX.md](PASSWORDLESS_SUDO_FIX.md) - Sudo configuration

