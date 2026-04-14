#!/bin/bash
#===============================================================================
# 01-setup-vmware-fusion.sh
# Downloads VMware Fusion prerequisites, the tiny11 Windows ISO, and the
# Sparx EA MSI.  Run on your Mac host before 02-create-win11-vm.sh.
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
VM_DIR="$HOME/Virtual Machines.localized"
LOG_FILE="$SCRIPT_DIR/setup.log"

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
# Three editions are available; set EA_EDITION in .env to select:
#
#   EA_EDITION=trial   (default)
#     Full EA — 30-day trial, no auth required.
#     MCP3.exe COM bridge works. All editions selectable on first launch.
#     URL: https://www.sparxsystems.com/bin/easetup_x64.msi
#
#   EA_EDITION=lite
#     EA Lite (Viewer) — permanently free, read-only, no auth required.
#     Intended for distributing models to stakeholders / non-modellers.
#     MCP3.exe COM bridge does NOT work with Lite (no automation API).
#     The SQLite Analyzer MCP server on macOS is unaffected and still works.
#     URL: https://www.sparxsystems.com/bin/ealite_x64.msi
#
#   EA_EDITION=licensed
#     Full licensed EA — requires Sparx registered-user credentials.
#     Place easetupfull.msi in ./iso/ manually, or set EA_REG_USER +
#     EA_REG_PASS in .env to be shown the registered download page.
#     URL: https://sparxsystems.com/registered/ea_down.html (login required)
#===============================================================================
EA_BASE_URL="https://www.sparxsystems.com/bin"

EA_TRIAL_X64_URL="${EA_BASE_URL}/easetup_x64.msi"
EA_TRIAL_URL="${EA_BASE_URL}/easetup.msi"          # universal fallback
EA_TRIAL_DEST="$SCRIPT_DIR/iso/easetup.msi"

EA_LITE_URL="${EA_BASE_URL}/ealite_x64.msi"
EA_LITE_DEST="$SCRIPT_DIR/iso/ealite_x64.msi"

EA_LICENSED_DEST="$SCRIPT_DIR/iso/easetupfull.msi"

#===============================================================================
# STEP 0: Load .env
#===============================================================================
if [ -f "$SCRIPT_DIR/.env" ]; then
    log "Loading .env"
    set -a; source "$SCRIPT_DIR/.env"; set +a  # shellcheck source=/dev/null
fi

: "${EA_EDITION:=trial}"   # trial | lite | licensed
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
# Controlled by EA_EDITION (set in .env or environment):
#   trial    — full EA, 30-day, no auth (default)
#   lite     — EA Lite (Viewer), permanently free, read-only, no auth
#   licensed — full licensed EA; place easetupfull.msi manually or set creds
#
# MCP capability summary:
#   Edition   | SQLite Analyzer MCP | Sparx EA Bridge MCP (MCP3.exe)
#   --------- | ------------------- | ------------------------------
#   Lite      | ✅ full              | ❌ no COM automation API
#   Trial     | ✅ full              | ✅ full (30-day window)
#   Licensed  | ✅ full              | ✅ full (permanent)
#===============================================================================
log "=== Step 7: Sparx EA MSI (edition: $EA_EDITION) ==="

_check_msi_size() {
    local dest="$1" label="$2"
    if [ -f "$dest" ]; then
        local sz
        sz=$(stat -f%z "$dest" 2>/dev/null || stat -c%s "$dest")
        if (( sz < 50000000 )); then
            log "❌ $label MSI is too small ($((sz/1024/1024)) MB) — likely a failed download."
            rm -f "$dest"
            return 1
        fi
        log "✅ $label MSI downloaded ($((sz/1024/1024)) MB)"
        return 0
    fi
    log "❌ $label MSI not found after download."
    return 1
}

case "$EA_EDITION" in

  lite)
    if [ -f "$EA_LITE_DEST" ]; then
        log "✅ EA Lite already present: $EA_LITE_DEST"
    else
        log "Downloading EA Lite (Viewer) — free, read-only, no auth required…"
        log "  from: $EA_LITE_URL"
        _download "$EA_LITE_URL" "$EA_LITE_DEST"
        _check_msi_size "$EA_LITE_DEST" "EA Lite" || {
            log "   Manual download: $EA_LITE_URL"
            log "   Place at: $EA_LITE_DEST"
        }
    fi
    log ""
    log "ℹ️  EA Lite is a read-only viewer — no model editing."
    log "   MCP3.exe COM bridge is NOT supported with Lite."
    log "   The SQLite Analyzer MCP server on macOS is fully supported."
    log "   Set EA_EDITION=trial in .env to get full MCP write capability."
    ;;

  licensed)
    if [ -f "$EA_LICENSED_DEST" ]; then
        log "✅ Licensed MSI found: $EA_LICENSED_DEST"
    else
        log ""
        log "╔══════════════════════════════════════════════════════════════════╗"
        log "║  Licensed MSI — manual download required                       ║"
        log "║                                                                ║"
        log "║  The Sparx registered-user area has no scriptable endpoint.    ║"
        log "║                                                                ║"
        log "║  1. Open: https://sparxsystems.com/registered/ea_down.html     ║"
        if [ -n "$EA_REG_USER" ]; then
        log "║  2. Log in with EA_REG_USER / EA_REG_PASS from .env            ║"
        else
        log "║  2. Log in with your Sparx registered-user credentials         ║"
        fi
        log "║  3. Download easetupfull.msi (x64) and place it at:            ║"
        log "║       $EA_LICENSED_DEST"
        log "║  4. Re-run this script — step 7 will detect it and skip        ║"
        log "╚══════════════════════════════════════════════════════════════════╝"
        open "https://sparxsystems.com/registered/ea_down.html" 2>/dev/null || true
    fi
    ;;

  trial|*)
    if [ -f "$EA_LICENSED_DEST" ]; then
        log "✅ Licensed MSI found: $EA_LICENSED_DEST — using it (overrides trial)"
    elif [ -f "$EA_TRIAL_DEST" ]; then
        log "✅ Trial MSI already present: $EA_TRIAL_DEST"
    else
        log "Downloading EA trial MSI — no auth required…"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --head "$EA_TRIAL_X64_URL")
        if [ "$HTTP_CODE" = "200" ]; then
            log "  Using x64 installer: $EA_TRIAL_X64_URL"
            _download "$EA_TRIAL_X64_URL" "$EA_TRIAL_DEST"
        else
            log "  x64 URL returned HTTP $HTTP_CODE — falling back to universal"
            _download "$EA_TRIAL_URL" "$EA_TRIAL_DEST"
        fi
        _check_msi_size "$EA_TRIAL_DEST" "EA trial" || {
            log "   Manual download: https://sparxsystems.com/products/ea/trial/request.html"
            log "   Place at: $EA_TRIAL_DEST"
        }
        log "   30-day trial — all editions selectable on first launch."
        log "   MCP3.exe COM bridge fully supported."
    fi
    ;;
esac

#===============================================================================
# DONE
#===============================================================================
log ""
log "=== Prerequisites complete ==="
log "ISO     : $ISO_DEST"
log "Edition : $EA_EDITION"
log "Next    : run ./02-create-win11-vm.sh"
