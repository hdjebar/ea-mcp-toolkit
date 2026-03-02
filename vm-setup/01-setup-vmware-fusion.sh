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

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

#===============================================================================
# STEP 1: Check prerequisites
#===============================================================================
log "=== Step 1: Checking prerequisites ==="

# Check macOS version
SW_VER=$(sw_vers -productVersion)
log "macOS version: $SW_VER"

# Check architecture (Apple Silicon vs Intel)
ARCH=$(uname -m)
log "Architecture: $ARCH"

if [[ "$ARCH" == "arm64" ]]; then
    log "✅ Apple Silicon detected — will use Windows 11 ARM"
    WIN_ARCH="arm64"
else
    log "✅ Intel Mac detected — will use Windows 11 x64"
    WIN_ARCH="amd64"
fi

# Check for Homebrew
if ! command -v brew &>/dev/null; then
    log "⚠️  Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

#===============================================================================
# STEP 2: Check if VMware Fusion is installed
#===============================================================================
log "=== Step 2: Checking VMware Fusion installation ==="

if [ -d "/Applications/VMware Fusion.app" ]; then
    FUSION_VER=$("/Applications/VMware Fusion.app/Contents/Library/vmware-vmx" --version 2>/dev/null | head -1 || echo "unknown")
    log "✅ VMware Fusion already installed: $FUSION_VER"
else
    log "⚠️  VMware Fusion not found."
    log ""
    log "╔══════════════════════════════════════════════════════════════╗"
    log "║  VMware Fusion Pro is FREE for personal use.               ║"
    log "║  You need to download it manually from Broadcom:           ║"
    log "║                                                            ║"
    log "║  1. Register at: https://profile.broadcom.com              ║"
    log "║  2. Download from VMware Fusion download page              ║"
    log "║  3. Install the .dmg file                                  ║"
    log "║  4. Re-run this script                                     ║"
    log "╚══════════════════════════════════════════════════════════════╝"
    log ""
    
    # Try opening the download page
    open "https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware+Fusion" 2>/dev/null || true
    
    exit 1
fi

#===============================================================================
# STEP 3: Verify vmrun is available
#===============================================================================
log "=== Step 3: Verifying vmrun CLI tool ==="

if [ -f "$VMRUN" ]; then
    log "✅ vmrun found at: $VMRUN"
    # Create symlink for convenience
    if [ ! -L /usr/local/bin/vmrun ]; then
        log "Creating vmrun symlink in /usr/local/bin..."
        sudo ln -sf "$VMRUN" /usr/local/bin/vmrun 2>/dev/null || true
    fi
else
    log "❌ vmrun not found. VMware Fusion may not be installed correctly."
    exit 1
fi

#===============================================================================
# STEP 4: Create VM directory structure
#===============================================================================
log "=== Step 4: Creating directory structure ==="

mkdir -p "$VM_DIR"
mkdir -p "$SCRIPT_DIR/iso"
mkdir -p "$SCRIPT_DIR/drivers"

log "✅ VM directory: $VM_DIR"
log "✅ ISO directory: $SCRIPT_DIR/iso"

#===============================================================================
# STEP 5: Download Windows 11 ARM ISO (Apple Silicon) or guide for Intel
#===============================================================================
log "=== Step 5: Windows 11 ISO ==="

if [[ "$WIN_ARCH" == "arm64" ]]; then
    # Check if Fusion can download Windows automatically
    log ""
    log "╔══════════════════════════════════════════════════════════════╗"
    log "║  For Apple Silicon Macs, VMware Fusion 13.6.1+ can         ║"
    log "║  download Windows 11 ARM automatically during VM creation. ║"
    log "║                                                            ║"
    log "║  Option A (Recommended): Let Fusion download it            ║"
    log "║    → Run script 02 which creates the VM with auto-download ║"
    log "║                                                            ║"
    log "║  Option B: Manual ISO download                             ║"
    log "║    → The ISO will be at:                                   ║"
    log "║      ~/Virtual Machines.localized/VMWIsoImages/            ║"
    log "║    → Or use the 24H2_esd2iso tool from GitHub              ║"
    log "╚══════════════════════════════════════════════════════════════╝"
else
    log "Download Windows 11 x64 ISO from:"
    log "  https://www.microsoft.com/software-download/windows11"
    log "Place the ISO at: $SCRIPT_DIR/iso/Win11.iso"
fi

#===============================================================================
# STEP 6: Download Sparx EA installer
#===============================================================================
log "=== Step 6: Sparx EA Installer ==="

EA_MSI="$SCRIPT_DIR/iso/easetupfull.msi"
EA_TRIAL_MSI="$SCRIPT_DIR/iso/easetup.msi"

if [ -f "$EA_MSI" ] || [ -f "$EA_TRIAL_MSI" ]; then
    log "✅ Sparx EA installer found"
else
    log ""
    log "╔══════════════════════════════════════════════════════════════╗"
    log "║  Download the Sparx EA installer:                          ║"
    log "║                                                            ║"
    log "║  Trial:  https://sparxsystems.com/products/ea/downloads.html║"
    log "║  Licensed: Registered Users Area (login required)          ║"
    log "║                                                            ║"
    log "║  Place the .msi file at:                                   ║"
    log "║    $SCRIPT_DIR/iso/easetupfull.msi                         ║"
    log "║  or:                                                       ║"
    log "║    $SCRIPT_DIR/iso/easetup.msi  (trial)                    ║"
    log "╚══════════════════════════════════════════════════════════════╝"
    
    open "https://sparxsystems.com/products/ea/downloads.html" 2>/dev/null || true
fi

log ""
log "=== Prerequisites check complete ==="
log "Next step: Run ./02-create-win11-vm.sh"
