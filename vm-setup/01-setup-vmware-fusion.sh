#!/bin/bash
#===============================================================================
# 01-setup-vmware-fusion.sh
# Downloads and installs VMware Fusion Pro on macOS (free for personal use)
# Run on your Mac host
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
VM_DIR="$HOME/Virtual Machines.localized"
LOG_FILE="$SCRIPT_DIR/setup.log"

# Minimum supported Fusion version (13.5)
FUSION_MIN_MAJOR=13
FUSION_MIN_MINOR=5

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# Centralise credentials — override before running, or export from a .env file
# NEVER commit real values here
: "${WIN_USER:=architect}"
: "${WIN_PASS:=Sparx2026!}"    # change before use

#===============================================================================
# tiny11 ISO catalogue
# Source: https://archive.org/details/tiny11_25H2  (uploader: NTDEV/Microsoft)
# Use standard tiny11 — NOT core — because EA requires .NET/COM/Windows Update
#===============================================================================
TINY11_BASE_URL="https://archive.org/download/tiny11_25H2"

# ARM64 (Apple Silicon) — Oct 2025 build
TINY11_ARM64_FILE="tiny11_25H2_Oct25_arm64.iso"
TINY11_ARM64_URL="${TINY11_BASE_URL}/${TINY11_ARM64_FILE}"
TINY11_ARM64_SHA256=""  # NTDEV has not published arm64 SHA256; verify manually after download

# x64 (Intel Mac) — Nov 2025 build (includes Nov 2025 security patch)
TINY11_X64_FILE="tiny11_25H2_Nov25.iso"
TINY11_X64_URL="${TINY11_BASE_URL}/${TINY11_X64_FILE}"
TINY11_X64_SHA256="92484F2B7F707E42383294402A9EABBADEAA5EDE80AC633390AE7F3537E36275"
# SHA256 source: https://archive.org/details/tiny11_25H2
# Verify Nov25 hash on the archive page before trusting — NTDEV may update in-place

#===============================================================================
# STEP 0: Load .env if present (keeps credentials out of source control)
#===============================================================================
if [ -f "$SCRIPT_DIR/.env" ]; then
    log "Loading credentials from .env"
    # shellcheck source=/dev/null
    set -a; source "$SCRIPT_DIR/.env"; set +a
fi

#===============================================================================
# STEP 1: Check prerequisites
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
# STEP 2: Check VMware Fusion installation and version
#===============================================================================
log "=== Step 2: Checking VMware Fusion ==="

if [ -d "/Applications/VMware Fusion.app" ]; then
    # Extract major.minor from the bundle version string
    RAW_VER=$(defaults read "/Applications/VMware Fusion.app/Contents/Info" \
              CFBundleShortVersionString 2>/dev/null || echo "0.0")
    MAJOR=$(echo "$RAW_VER" | cut -d. -f1)
    MINOR=$(echo "$RAW_VER" | cut -d. -f2)
    log "VMware Fusion version: $RAW_VER"

    if (( MAJOR < FUSION_MIN_MAJOR )) || \
       (( MAJOR == FUSION_MIN_MAJOR && MINOR < FUSION_MIN_MINOR )); then
        log "❌ VMware Fusion $RAW_VER is below the minimum required $FUSION_MIN_MAJOR.$FUSION_MIN_MINOR"
        log "   Update from: https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Fusion"
        open "https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Fusion" 2>/dev/null || true
        exit 1
    fi

    log "✅ VMware Fusion $RAW_VER — OK"
else
    log "⚠️  VMware Fusion not found."
    log ""
    log "╔══════════════════════════════════════════════════════════════╗"
    log "║  VMware Fusion Pro is FREE for personal use.               ║"
    log "║  1. Register at: https://profile.broadcom.com              ║"
    log "║  2. Download from the VMware Fusion download page          ║"
    log "║  3. Install the .dmg, then re-run this script              ║"
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
    log "❌ vmrun not found at expected path. Fusion may not be installed correctly."
    exit 1
fi

#===============================================================================
# STEP 4: Create directory structure
#===============================================================================
log "=== Step 4: Creating directory structure ==="

mkdir -p "$VM_DIR"
mkdir -p "$SCRIPT_DIR/iso"
mkdir -p "$SCRIPT_DIR/drivers"
log "✅ Directories created"

#===============================================================================
# STEP 5: Download tiny11 ISO
#
# tiny11 25H2 is a minimal Windows 11 build maintained by NTDEV.
# It removes ~20 store apps (Edge, OneDrive, Xbox, Clipchamp, etc.) and
# bypasses Microsoft Account requirement — ideal for a Sparx EA VM.
# Standard (not core) build keeps .NET, COM, and Windows Update intact,
# all of which are required by the EA MSI installer and MCP COM bridge.
#
# Official source: https://archive.org/details/tiny11_25H2 (uploader: NTDEV)
#===============================================================================
log "=== Step 5: tiny11 ISO ==="

if [ -f "$ISO_DEST" ]; then
    log "✅ ISO already present: $ISO_DEST"
else
    log "Downloading $TINY11_FILE from Internet Archive..."
    log "  URL : $TINY11_URL"
    log "  Dest: $ISO_DEST"
    log "  Size: ~5 GB — this will take a while on a slow connection"

    # Prefer aria2c (parallel chunks, resume) → curl (resume) → wget (resume)
    if command -v aria2c &>/dev/null; then
        aria2c \
            --file-allocation=none \
            --continue=true \
            --max-connection-per-server=4 \
            --split=4 \
            --min-split-size=100M \
            --dir="$SCRIPT_DIR/iso" \
            --out="$TINY11_FILE" \
            "$TINY11_URL"
    elif command -v curl &>/dev/null; then
        curl -L --continue-at - --output "$ISO_DEST" "$TINY11_URL"
    elif command -v wget &>/dev/null; then
        wget -c -O "$ISO_DEST" "$TINY11_URL"
    else
        log "❌ No download tool found (aria2c / curl / wget)."
        log "   Install one: brew install aria2"
        exit 1
    fi

    if [ ! -f "$ISO_DEST" ]; then
        log "❌ Download failed — file not found at $ISO_DEST"
        exit 1
    fi
    log "✅ Download complete"
fi

#===============================================================================
# STEP 6: Verify ISO integrity
#===============================================================================
log "=== Step 6: Verifying ISO ==="

ACTUAL_SIZE=$(stat -f%z "$ISO_DEST" 2>/dev/null || stat -c%s "$ISO_DEST")
log "ISO size: $((ACTUAL_SIZE / 1024 / 1024)) MB"

if (( ACTUAL_SIZE < 2000000000 )); then
    log "❌ ISO is suspiciously small (< 2 GB). Download may have been truncated."
    rm -f "$ISO_DEST"
    log "   Deleted partial file. Re-run to retry."
    exit 1
fi

if [ -n "$TINY11_SHA256" ]; then
    log "Checking SHA-256..."
    ACTUAL_SHA=$(shasum -a 256 "$ISO_DEST" | awk '{print toupper($1)}')
    if [ "$ACTUAL_SHA" = "$TINY11_SHA256" ]; then
        log "✅ SHA-256 matches"
    else
        log "⚠️  SHA-256 mismatch"
        log "   Expected : $TINY11_SHA256"
        log "   Got      : $ACTUAL_SHA"
        log "   Verify manually at: https://archive.org/details/tiny11_25H2"
        log "   Delete $ISO_DEST and re-run if the file is corrupt."
    fi
else
    log "ℹ️  No reference SHA-256 for this build — verify manually at:"
    log "   https://archive.org/details/tiny11_25H2"
fi

#===============================================================================
# STEP 7: Sparx EA installer
#===============================================================================
log "=== Step 7: Sparx EA installer ==="

EA_MSI="$SCRIPT_DIR/iso/easetupfull.msi"
EA_TRIAL_MSI="$SCRIPT_DIR/iso/easetup.msi"

if [ -f "$EA_MSI" ] || [ -f "$EA_TRIAL_MSI" ]; then
    log "✅ Sparx EA installer found"
else
    log ""
    log "╔══════════════════════════════════════════════════════════════╗"
    log "║  Download the Sparx EA installer and place it at:          ║"
    log "║    $SCRIPT_DIR/iso/easetupfull.msi       (licensed)        ║"
    log "║    $SCRIPT_DIR/iso/easetup.msi            (trial)          ║"
    log "║                                                            ║"
    log "║  Download: https://sparxsystems.com/products/ea/downloads  ║"
    log "╚══════════════════════════════════════════════════════════════╝"
    open "https://sparxsystems.com/products/ea/downloads.html" 2>/dev/null || true
fi

#===============================================================================
# DONE
#===============================================================================
log ""
log "=== Prerequisites complete ==="
log "ISO : $ISO_DEST"
log "Next: run ./02-create-win11-vm.sh"
