#!/bin/bash
#===============================================================================
# 03-post-install.sh
# Runs from Mac host AFTER Windows has booted and VMware Tools are installed
# Uses vmrun to execute commands inside the guest VM
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
VM_DIR="$HOME/Virtual Machines.localized"
VM_NAME="Windows11-EA"
VMX_FILE="$VM_DIR/${VM_NAME}.vmwarevm/${VM_NAME}.vmx"
LOG_FILE="$SCRIPT_DIR/setup.log"

# Must match credentials from 02-create-win11-vm.sh
WIN_USER="architect"
WIN_PASS="Sparx2026!"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

#===============================================================================
# Helper: Run command in guest
#===============================================================================
run_in_guest() {
    "$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" \
        runProgramInGuest "$VMX_FILE" -noWait -activeWindow "$@"
}

run_in_guest_wait() {
    "$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" \
        runProgramInGuest "$VMX_FILE" -interactive "$@"
}

run_script_in_guest() {
    "$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" \
        runScriptInGuest "$VMX_FILE" -interactive "" "$@"
}

copy_to_guest() {
    "$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" \
        copyFileFromHostToGuest "$VMX_FILE" "$1" "$2"
}

#===============================================================================
# STEP 1: Verify VM is running and Tools are available
#===============================================================================
log "=== Post-Install Configuration ==="
log "=== Step 1: Checking VM status ==="

if ! "$VMRUN" list | grep -q "$VM_NAME"; then
    log "VM not running. Starting..."
    "$VMRUN" start "$VMX_FILE" 2>/dev/null || "$VMRUN" start "$VMX_FILE" nogui
    log "Waiting 60s for Windows to boot..."
    sleep 60
fi

# Wait for VMware Tools
log "Waiting for VMware Tools to become available..."
MAX_WAIT=300
WAITED=0
while ! "$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" listProcessesInGuest "$VMX_FILE" &>/dev/null; do
    sleep 10
    WAITED=$((WAITED + 10))
    if [ $WAITED -ge $MAX_WAIT ]; then
        log "❌ Timeout waiting for VMware Tools. Is Windows fully booted?"
        log "   Try: vmrun -gu $WIN_USER -gp $WIN_PASS listProcessesInGuest \"$VMX_FILE\""
        exit 1
    fi
    log "  Waiting... (${WAITED}s / ${MAX_WAIT}s)"
done
log "✅ VMware Tools responding"

#===============================================================================
# STEP 2: Copy installers to guest if autounattend didn't handle it
#===============================================================================
log "=== Step 2: Ensuring installers are on the guest ==="

# Create setup directory in guest
run_script_in_guest "cmd.exe /c mkdir C:\\setup-scripts 2>nul" || true

# Copy EA installer
for msi in "$SCRIPT_DIR/shared/installers/easetupfull.msi" "$SCRIPT_DIR/shared/installers/easetup.msi"; do
    if [ -f "$msi" ]; then
        log "Copying EA installer to guest..."
        copy_to_guest "$msi" "C:\\setup-scripts\\$(basename "$msi")"
        log "✅ EA installer copied"
        break
    fi
done

# Copy PowerShell scripts
for ps1 in "$SCRIPT_DIR/shared/autounattend-iso-content/\$OEM\$/\$1/setup-scripts/"*.ps1; do
    if [ -f "$ps1" ]; then
        BASENAME=$(basename "$ps1")
        log "Copying $BASENAME to guest..."
        copy_to_guest "$ps1" "C:\\setup-scripts\\$BASENAME"
    fi
done

#===============================================================================
# STEP 3: Run EA installation if not already done
#===============================================================================
log "=== Step 3: Checking/Running EA installation ==="

# Check if EA is already installed
EA_CHECK=$("$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" \
    runScriptInGuest "$VMX_FILE" -interactive "" \
    "cmd.exe /c if exist \"C:\\Program Files (x86)\\Sparx Systems\\EA\\EA.exe\" (echo FOUND) else (echo NOTFOUND)" \
    2>&1 || echo "NOTFOUND")

if echo "$EA_CHECK" | grep -q "FOUND"; then
    log "✅ Sparx EA already installed"
else
    log "Running EA silent installation..."
    run_in_guest_wait "cmd.exe" "/c powershell -ExecutionPolicy Bypass -File C:\\setup-scripts\\02-install-sparx-ea.ps1"
    log "✅ EA installation script executed"
fi

#===============================================================================
# STEP 4: Configure MCP Server
#===============================================================================
log "=== Step 4: Configuring MCP Server ==="

run_in_guest_wait "cmd.exe" "/c powershell -ExecutionPolicy Bypass -File C:\\setup-scripts\\03-configure-ea-mcp.ps1"
log "✅ MCP Server configured"

#===============================================================================
# STEP 5: Enable RDP from Mac
#===============================================================================
log "=== Step 5: Enabling RDP access from Mac ==="

# Get VM's IP address
VM_IP=$("$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" \
    getGuestIPAddress "$VMX_FILE" 2>/dev/null || echo "unknown")

log "VM IP address: $VM_IP"

if [[ "$VM_IP" != "unknown" ]]; then
    log ""
    log "Connect via Remote Desktop:"
    log "  IP: $VM_IP"
    log "  User: $WIN_USER"
    log "  Pass: $WIN_PASS"
    log ""
    log "Or use: open rdp://$WIN_USER@$VM_IP"
fi

#===============================================================================
# STEP 6: Create snapshot
#===============================================================================
log "=== Step 6: Creating snapshot ==="

"$VMRUN" snapshot "$VMX_FILE" "EA-Installed-Clean" || log "⚠️  Snapshot creation failed"
log "✅ Snapshot 'EA-Installed-Clean' created"

#===============================================================================
# STEP 7: Create Mac helper scripts
#===============================================================================
log "=== Step 7: Creating Mac helper scripts ==="

# VM management script
cat > "$SCRIPT_DIR/vm.sh" << 'VMHELPER'
#!/bin/bash
#===============================================================================
# vm.sh — Quick VM management from Mac terminal
# Usage: ./vm.sh [start|stop|suspend|status|rdp|snapshot|restore]
#===============================================================================

VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
VMX="$HOME/Virtual Machines.localized/Windows11-EA.vmwarevm/Windows11-EA.vmx"
WIN_USER="architect"
WIN_PASS="Sparx2026!"

case "${1:-status}" in
    start)
        echo "Starting Windows 11 EA VM..."
        "$VMRUN" start "$VMX" ${2:-} # pass 'nogui' as $2 for headless
        ;;
    stop)
        echo "Shutting down VM gracefully..."
        "$VMRUN" stop "$VMX" soft
        ;;
    suspend)
        echo "Suspending VM..."
        "$VMRUN" suspend "$VMX" soft
        ;;
    status)
        echo "Running VMs:"
        "$VMRUN" list
        echo ""
        IP=$("$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" getGuestIPAddress "$VMX" 2>/dev/null || echo "N/A")
        echo "EA VM IP: $IP"
        ;;
    rdp)
        IP=$("$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" getGuestIPAddress "$VMX" 2>/dev/null)
        if [ -n "$IP" ] && [ "$IP" != "unknown" ]; then
            echo "Opening RDP to $IP..."
            open "rdp://$WIN_USER@$IP"
        else
            echo "VM not running or IP not available. Start with: ./vm.sh start"
        fi
        ;;
    ip)
        "$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" getGuestIPAddress "$VMX" 2>/dev/null
        ;;
    snapshot)
        NAME="${2:-$(date +%Y%m%d-%H%M%S)}"
        echo "Creating snapshot: $NAME"
        "$VMRUN" snapshot "$VMX" "$NAME"
        ;;
    restore)
        NAME="${2:-EA-Installed-Clean}"
        echo "Restoring snapshot: $NAME"
        "$VMRUN" revertToSnapshot "$VMX" "$NAME"
        ;;
    run)
        shift
        "$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" \
            runScriptInGuest "$VMX" -interactive "" "cmd.exe /c $*"
        ;;
    ps1)
        shift
        "$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" \
            runScriptInGuest "$VMX" -interactive "" \
            "powershell.exe -ExecutionPolicy Bypass -Command $*"
        ;;
    ea)
        echo "Launching Enterprise Architect..."
        "$VMRUN" -gu "$WIN_USER" -gp "$WIN_PASS" \
            runProgramInGuest "$VMX" -noWait -activeWindow \
            "C:\Program Files (x86)\Sparx Systems\EA\EA.exe" "${2:-}"
        ;;
    *)
        echo "Usage: $0 {start|stop|suspend|status|rdp|ip|snapshot|restore|run|ps1|ea}"
        echo ""
        echo "  start [nogui]   - Start VM (optionally headless)"
        echo "  stop            - Graceful shutdown"
        echo "  suspend         - Suspend to disk"
        echo "  status          - Show running VMs and IP"
        echo "  rdp             - Open Remote Desktop to VM"
        echo "  ip              - Show VM IP address"
        echo "  snapshot [name] - Create named snapshot"
        echo "  restore [name]  - Restore snapshot (default: EA-Installed-Clean)"
        echo "  run <cmd>       - Run a command in the guest"
        echo "  ps1 <cmd>       - Run PowerShell in the guest"
        echo "  ea [file.qea]   - Launch EA (optionally with a model file)"
        ;;
esac
VMHELPER

chmod +x "$SCRIPT_DIR/vm.sh"
log "✅ VM helper script created: $SCRIPT_DIR/vm.sh"

#===============================================================================
# DONE
#===============================================================================
log ""
log "╔══════════════════════════════════════════════════════════════════╗"
log "║  ✅ SETUP COMPLETE!                                            ║"
log "╠══════════════════════════════════════════════════════════════════╣"
log "║                                                                ║"
log "║  Quick commands (from Mac terminal):                           ║"
log "║                                                                ║"
log "║  ./vm.sh start          Start the Windows VM                   ║"
log "║  ./vm.sh stop           Graceful shutdown                      ║"
log "║  ./vm.sh ea             Launch Enterprise Architect             ║"
log "║  ./vm.sh ea model.qea   Open a specific model                  ║"
log "║  ./vm.sh rdp            Open Remote Desktop                    ║"
log "║  ./vm.sh status         Show VM status and IP                  ║"
log "║  ./vm.sh snapshot name  Create a snapshot                      ║"
log "║  ./vm.sh restore name   Restore a snapshot                     ║"
log "║  ./vm.sh run <cmd>      Run command in Windows                 ║"
log "║  ./vm.sh ps1 <cmd>      Run PowerShell in Windows              ║"
log "║                                                                ║"
log "║  Shared folder: ~/setup-ea-vm/shared → Z:\ in Windows         ║"
log "║  Place .qea models in shared/models/ for cross-access          ║"
log "║                                                                ║"
log "║  For Claude + MCP integration:                                 ║"
log "║  1. Install Claude Desktop in Windows VM                       ║"
log "║  2. MCP config is pre-configured at:                           ║"
log "║     %APPDATA%\Claude\claude_desktop_config.json                ║"
log "║  3. Open EA → Open model → Claude can now query it             ║"
log "╚══════════════════════════════════════════════════════════════════╝"
