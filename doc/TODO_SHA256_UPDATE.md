# TODO: Update SHA256 Checksum

## Action Required

The `setup-sd-card.sh` script currently has a placeholder SHA256 checksum for the Raspberry Pi OS Bullseye image.

**File:** `scripts/setup-sd-card.sh`  
**Line:** ~182

```bash
IMAGE_SHA256="451396b8d5f3c8c38e8d2e4f8d8c7e1b8e8a1c8e8e8e8e8e8e8e8e8e8e8e8e8e"  # TODO: Get actual SHA256
```

## How to Fix

### Option 1: Download and Calculate (Recommended)

```bash
# Download the image
curl -L -o test.img.xz "https://downloads.raspberrypi.com/raspios_oldstable_lite_armhf/images/raspios_oldstable_lite_armhf-2024-10-22/2024-10-22-raspios-bullseye-armhf-lite.img.xz"

# Calculate SHA256
shasum -a 256 test.img.xz

# Or on Linux
sha256sum test.img.xz

# Update the script with the actual hash
```

### Option 2: Get from Official Source

Check the Raspberry Pi downloads page for the official SHA256:
https://www.raspberrypi.com/software/operating-systems/

Look for:
- **Raspberry Pi OS Lite (Legacy)**
- **32-bit**
- **Debian Bullseye**
- **Release: 2024-10-22** (or latest available)

### Option 3: Disable Checksum Verification (Not Recommended)

If you can't get the SHA256, you could disable verification:

```bash
# In setup-sd-card.sh, comment out the checksum verification
# But this is NOT recommended for security reasons
```

## Why This Matters

- **Security**: Verifies the downloaded image hasn't been tampered with
- **Integrity**: Ensures the download completed successfully
- **Reliability**: Prevents using corrupted images

## Current Status

⚠️ **The script will currently fail checksum verification**

The placeholder SHA256 won't match the actual image, so the script will abort with:
```
Error: SHA256 checksum mismatch!
Expected: 451396b8d5f3c8c38e8d2e4f8d8c7e1b8e8a1c8e8e8e8e8e8e8e8e8e8e8e8e
Got:      [actual hash]
```

## Temporary Workaround

Until the correct SHA256 is added, you can:

1. **Skip verification** by commenting out lines ~210-217 in `setup-sd-card.sh`
2. **Use the manual GUI method** (option 2 in the script)
3. **Download and calculate the hash** as shown above

## Priority

🔴 **HIGH** - Script won't work without this fix

## Related Files

- `scripts/setup-sd-card.sh` - Needs SHA256 update
- `doc/SETUP_SD_CARD_FIXES.md` - Documents all fixes


