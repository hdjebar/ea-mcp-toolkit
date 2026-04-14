#!/bin/bash
#===============================================================================
# 01-setup-vmware-fusion.sh
# Downloads VMware Fusion prerequisites, the tiny11 Windows ISO, and the
# Sparx EA trial MSI.  Run on your Mac host before 02-create-win11-vm.sh.
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
VM_DIR="$HOME/Virtual Machines.localized"
LOG_FILE="$SCRIPT_DIR/setup.log"

# Minimum supported Fusion version
FUSION_MIN_MAJOR=13
FUSION_MIN_MINOR=5

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# Credentials — override in .env, never commit real values here
: "${WIN_USER:=architect}"
: "${WIN_PASS:=Sparx2026!}"   # change before use

#===============================================================================
# tiny11 ISO catalogue
# Source: https://archive.org/details/tiny11_25H2  (uploader: NTDEV/Microsoft)
# Use standard tiny11 — NOT core — EA requires .NET, COM, and Windows Update
#===============================================================================
TINY11_BASE_URL="https://archive.org/download/tiny11_25H2"

TINY11_ARM64_FILE="tiny11_25H2_Oct25_arm64.iso"
TINY11_ARM64_URL="${TINY11_BASE_URL}/${TINY11_ARM64_FILE}"
TINY11_ARM64_SHA256=""   # NTDEV has not published an arm64 hash; verify manually

TINY11_X64_FILE="tiny11_25H2_Nov25.iso"
TINY11_X64_URL="${TINY11_BASE_URL}/${TINY11_X64_FILE}"
TINY11_X64_SHA256="92484F2B7F707E42383294402A9EABBADEAA5EDE80AC633390AE7F3537E36275"
# SHA256 published by NTDEV at https://archive.org/details/tiny11_25H2 for Oct25 baseline.
# Verify the Nov25 hash on that page before trusting — NTDEV may update in-place.

#===============================================================================
# Sparx EA MSI catalogue
#
# Trial (no authentication required):
#   Sparx exposes a stable public URL for the latest trial MSI.
#   EA 16+ ships separate x86 and x64 installers; the x64 variant is preferred
#   for tiny11 on 64-bit Windows 11.
#
# Licensed (authentication required):
#   The registered-user area (https://sparxsystems.com/registered/ea_down.html)
#   is behind a login wall that does not expose a scriptable endpoint.
#   To use your licensed MSI: place easetupfull.msi in ./iso/ before running,
#   or set EA_REG_USER and EA_REG_PASS in .env to suppress the trial download
#   and be shown the manual download URL with your credentials.
#===============================================================================
EA_BASE_URL="https://www.sparxsystems.com/bin"
EA_TRIAL_X64_URL="${EA_BASE_URL}/easetup_x64.msi"   # EA 16+ 64-bit trial
EA_TRIAL_URL="${EA_BASE_URL}/easetup.msi"            # EA universal trial fallback
EA_TRIAL_DEST="$SCRIPT_DIR/iso/easetup.msi"
EA_LICENSED_DEST="$SCRIPT_DIR/iso/easetupfull.msi"

#===============================================================================
# STEP 0: Load .env
#===============================================================================
if [ -f "$SCRIPT_DIR/.env" ]; then
    log "Loading .env"
    set -a; source "$SCRIPT_DIR/.env"; set +a  # shellcheck source=/dev/null
fi

# Optional licensed-user credentials (set in .env to skip trial download)
: "${EA_REG_USER:=}"
: "${EA_REG_PASS:=}"

#===============================================================================
# STEP 1: Prerequisites
#===============================================================================
log "=== Step 1: Checking prerequisites ==="

SW_VER=$(sw_vers -productVersion)
log "macOS version: $SW_VER"

ARCH=$(uname -m)
log "Architecture: $ARCH"

if [[ "$ARCH" == "arm64" ]]; then
    log "✅ Apple Silicon — will use tiny11 ARM64"
    WIN_ARCH="arm64"
    TINY11_FILE="$TINY11_ARM64_FILE"
    TINY11_URL="$TINY11_ARM64_URL"
    TINY11_SHA256="$TINY11_ARM64_SHA256"
else
    log "✅ Intel Mac — will use tiny11 x64"
    WIN_ARCH="amd64"
    TINY11_FILE="$TINY11_X64_FILE"
    TINY11_URL="$TINY11_X64_URL"
    TINY11_SHA256="$TINY11_X64_SHA256"
fi

ISO_DEST="$SCRIPT_DIR/iso/$TINY11_FILE"

if ! command -v brew &>/dev/null; then
    log "⚠️  Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

#===============================================================================
# STEP 2: VMware Fusion version check
#===============================================================================
log "=== Step 2: Checking VMware Fusion ==="

if [ -d "/Applications/VMware Fusion.app" ]; then
    RAW_VER=$(defaults read "/Applications/VMware Fusion.app/Contents/Info" \
              CFBundleShortVersionString 2>/dev/null || echo "0.0")
    MAJOR=$(echo "$RAW_VER" | cut -d. -f1)
    MINOR=$(echo "$RAW_VER" | cut -d. -f2)
    log "VMware Fusion version: $RAW_VER"

    if (( MAJOR < FUSION_MIN_MAJOR )) || \
       (( MAJOR == FUSION_MIN_MAJOR && MINOR < FUSION_MIN_MINOR )); then
        log "❌ Fusion $RAW_VER is below the required minimum $FUSION_MIN_MAJOR.$FUSION_MIN_MINOR"
        log "   Update from: https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Fusion"
        open "https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Fusion" 2>/dev/null || true
        exit 1
    fi
    log "✅ VMware Fusion $RAW_VER — OK"
else
    log "⚠️  VMware Fusion not found."
    log "╔══════════════════════════════════════════════════════════════╗"
    log "║  Fusion Pro is FREE for personal use.                      ║"
    log "║  1. Register at: https://profile.broadcom.com              ║"
    log "║  2. Download and install the .dmg                          ║"
    log "║  3. Re-run this script                                     ║"
    log "╚══════════════════════════════════════════════════════════════╝"
    open "https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Fusion" 2>/dev/null || true
    exit 1
fi

#===============================================================================
# STEP 3: Verify vmrun
#===============================================================================
log "=== Step 3: Verifying vmrun CLI ==="

if [ -f "$VMRUN" ]; then
    log "✅ vmrun found"
    if [ ! -L /usr/local/bin/vmrun ]; then
        sudo ln -sf "$VMRUN" /usr/local/bin/vmrun 2>/dev/null || true
    fi
else
    log "❌ vmrun not found. Fusion may not be installed correctly."
    exit 1
fi

#===============================================================================
# STEP 4: Directory structure
#===============================================================================
log "=== Step 4: Creating directory structure ==="

mkdir -p "$VM_DIR" "$SCRIPT_DIR/iso" "$SCRIPT_DIR/drivers"
log "✅ Directories ready"

#===============================================================================
# STEP 5: Download tiny11 ISO
#
# tiny11 25H2 — minimal Windows 11 by NTDEV.  Removes ~20 store apps
# (Edge, OneDrive, Xbox, Clipchamp…), bypasses Microsoft Account, keeps
# .NET + COM + Windows Update intact (all required by EA MSI and MCP bridge).
#
# Official source: https://archive.org/details/tiny11_25H2 (uploader: NTDEV)
#===============================================================================
log "=== Step 5: tiny11 ISO ==="

_download() {
    local url="$1" dest="$2"
    if command -v aria2c &>/dev/null; then
        aria2c --file-allocation=none --continue=true \
               --max-connection-per-server=4 --split=4 --min-split-size=100M \
               --dir="$(dirname "$dest")" --out="$(basename "$dest")" "$url"
    elif command -v curl &>/dev/null; then
        curl -L --continue-at - --output "$dest" "$url"
    elif command -v wget &>/dev/null; then
        wget -c -O "$dest" "$url"
    else
        log "❌ No download tool found. Install one: brew install aria2"
        exit 1
    fi
}

if [ -f "$ISO_DEST" ]; then
    log "✅ ISO already present: $ISO_DEST"
else
    log "Downloading $TINY11_FILE (~5 GB)…"
    log "  from: $TINY11_URL"
    _download "$TINY11_URL" "$ISO_DEST"
    [ -f "$ISO_DEST" ] || { log "❌ Download failed."; exit 1; }
    log "✅ ISO downloaded"
fi

#===============================================================================
# STEP 6: Verify ISO integrity
#===============================================================================
log "=== Step 6: Verifying ISO ==="

ACTUAL_SIZE=$(stat -f%z "$ISO_DEST" 2>/dev/null || stat -c%s "$ISO_DEST")
log "ISO size: $((ACTUAL_SIZE / 1024 / 1024)) MB"

if (( ACTUAL_SIZE < 2000000000 )); then
    log "❌ ISO < 2 GB — likely truncated. Deleting and re-run to retry."
    rm -f "$ISO_DEST"; exit 1
fi

if [ -n "$TINY11_SHA256" ]; then
    log "Checking SHA-256…"
    ACTUAL_SHA=$(shasum -a 256 "$ISO_DEST" | awk '{print toupper($1)}')
    if [ "$ACTUAL_SHA" = "$TINY11_SHA256" ]; then
        log "✅ SHA-256 matches"
    else
        log "⚠️  SHA-256 mismatch — verify at https://archive.org/details/tiny11_25H2"
        log "   Expected : $TINY11_SHA256"
        log "   Got      : $ACTUAL_SHA"
    fi
else
    log "ℹ️  No reference SHA-256 for this build — verify at https://archive.org/details/tiny11_25H2"
fi

#===============================================================================
# STEP 7: Sparx EA MSI
#
# Priority order:
#   1. ./iso/easetupfull.msi  — licensed MSI placed here manually
#   2. ./iso/easetup.msi      — trial already downloaded in a previous run
#   3. Auto-download trial    — unless EA_REG_USER/EA_REG_PASS set in .env
#===============================================================================
log "=== Step 7: Sparx EA MSI ==="

if [ -f "$EA_LICENSED_DEST" ]; then
    log "✅ Licensed MSI found: $EA_LICENSED_DEST — skipping download"

elif [ -f "$EA_TRIAL_DEST" ]; then
    log "✅ Trial MSI already present: $EA_TRIAL_DEST"

elif [ -n "$EA_REG_USER" ] && [ -n "$EA_REG_PASS" ]; then
    # Registered-user area does not expose a scriptable download endpoint.
    # Print the URL and credentials so the user can fetch the licensed MSI.
    log ""
    log "╔══════════════════════════════════════════════════════════════════╗"
    log "║  Licensed MSI — manual download required                       ║"
    log "║                                                                ║"
    log "║  1. Open: https://sparxsystems.com/registered/ea_down.html     ║"
    log "║  2. Log in with:  EA_REG_USER / EA_REG_PASS  (from .env)       ║"
    log "║  3. Download easetupfull.msi and place it at:                  ║"
    log "║       $EA_LICENSED_DEST"
    log "║  4. Re-run this script (step 7 will skip the trial download)    ║"
    log "╚══════════════════════════════════════════════════════════════════╝"
    open "https://sparxsystems.com/registered/ea_down.html" 2>/dev/null || true

else
    # Auto-download the public trial MSI — no authentication required.
    # Try the x64-specific installer first (EA 16+); fall back to the
    # universal easetup.msi if the x64 URL returns an error.
    log "Downloading Sparx EA trial MSI…"

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --head "$EA_TRIAL_X64_URL")
    if [ "$HTTP_CODE" = "200" ]; then
        log "  Using x64 installer: $EA_TRIAL_X64_URL"
        _download "$EA_TRIAL_X64_URL" "$EA_TRIAL_DEST"
    else
        log "  x64 installer not available (HTTP $HTTP_CODE) — falling back to universal"
        log "  Using: $EA_TRIAL_URL"
        _download "$EA_TRIAL_URL" "$EA_TRIAL_DEST"
    fi

    # Sanity check — MSI should be at least 50 MB
    if [ -f "$EA_TRIAL_DEST" ]; then
        EA_SIZE=$(stat -f%z "$EA_TRIAL_DEST" 2>/dev/null || stat -c%s "$EA_TRIAL_DEST")
        if (( EA_SIZE < 50000000 )); then
            log "❌ EA MSI is suspiciously small ($((EA_SIZE/1024/1024)) MB) — download may have failed."
            rm -f "$EA_TRIAL_DEST"
            log "   Try downloading manually: $EA_TRIAL_URL"
            log "   Place the file at: $EA_TRIAL_DEST"
        else
            log "✅ EA trial MSI downloaded ($((EA_SIZE/1024/1024)) MB)"
            log "   30-day trial — all editions selectable on first launch."
            log "   To use a licensed copy instead, place easetupfull.msi at:"
            log "   $EA_LICENSED_DEST and re-run; this step will skip."
        fi
    else
        log "❌ EA MSI download failed. Download manually from:"
        log "   https://sparxsystems.com/products/ea/trial/request.html"
        log "   Place the file at: $EA_TRIAL_DEST"
    fi
fi

#===============================================================================
# DONE
#===============================================================================
log ""
log "=== Prerequisites complete ==="
log "ISO : $ISO_DEST"
log "MSI : ${EA_LICENSED_DEST:-$EA_TRIAL_DEST}"
log "Next: run ./02-create-win11-vm.sh"
