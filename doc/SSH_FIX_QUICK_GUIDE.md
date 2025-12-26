# SSH Password Fix - Quick Reference

## Problem
✗ Can ping `ovbuddy.local` but can't SSH with password → "Permission denied"

## Quick Fix

### Option 1: Recreate SD Card (Recommended - 5 minutes)
```bash
cd scripts
./setup-sd-card.sh
```
Wait 3-5 minutes for first boot, then test:
```bash
./test-ssh.sh
```

### Option 2: Manual Password Reset (If you have monitor/keyboard)
1. Connect monitor and keyboard to Pi
2. Log in at console
3. Run: `passwd`
4. Enter new password twice

### Option 3: Use SSH Keys (Advanced)
```bash
ssh-keygen -t ed25519
ssh-copy-id pi@ovbuddy.local
```

## Diagnostic Command
```bash
cd scripts
./test-ssh.sh
```

This will test:
- ✓ Network connectivity
- ✓ mDNS resolution
- ✓ SSH port
- ✓ Authentication

## What Changed

**Before:** Python's `crypt` module (unreliable on macOS)
**After:** OpenSSL's `passwd -6` (reliable everywhere)

## Files Updated
- ✓ `scripts/setup-sd-card.sh` - Fixed password hash generation
- ✓ `scripts/test-ssh.sh` - New diagnostic tool
- ✓ `doc/SSH_PASSWORD_FIX.md` - Full documentation
- ✓ `README.md` - Added troubleshooting section

## After SSH Works

Deploy OVBuddy:
```bash
cd scripts
./deploy.sh
```

## Need Help?

1. Run diagnostic: `./scripts/test-ssh.sh`
2. Read full docs: `doc/SSH_PASSWORD_FIX.md`
3. Check README: Troubleshooting → "Can't SSH into Raspberry Pi"

## Common Issues

**"Connection refused"**
→ SSH not enabled or Pi still booting (wait 3-5 min)

**"No route to host"**
→ Pi not on network, check WiFi credentials in `setup.env`

**"Permission denied"**
→ Password hash issue, recreate SD card with updated script

**"Host key verification failed"**
→ Pi was re-imaged, remove old key: `ssh-keygen -R ovbuddy.local`

