#!/bin/bash
#===============================================================================
# install-mcp-servers.sh
# Installs both EA MCP servers on macOS:
#   1. SSH Bridge  — tunnels to Sparx EA MCP in Windows VM (requires VM running)
#   2. SQLite Analyzer — reads .qea files natively on macOS (no VM needed)
#
# Also configures Claude Desktop and/or Claude Code.
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.ea-mcp"
CLAUDE_CONFIG_DIR="$HOME/Library/Application Support/Claude"
CLAUDE_CONFIG="$CLAUDE_CONFIG_DIR/claude_desktop_config.json"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  EA MCP Server Installer for macOS                      ║"
echo "║  Bridge (SSH→VM) + SQLite Analyzer (native)             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

#===============================================================================
# Step 1: Prerequisites
#===============================================================================
echo "--- Checking prerequisites ---"

if command -v python3 &>/dev/null; then
    log "Python: $(python3 --version)"
else
    err "Python 3 not found. Install via: brew install python3"
    exit 1
fi

if command -v uv &>/dev/null; then
    log "uv: $(uv --version)"
    PKG_MGR="uv"
elif command -v pip3 &>/dev/null; then
    log "pip3 found (uv recommended: brew install uv)"
    PKG_MGR="pip"
else
    err "Neither uv nor pip3 found. Install uv: brew install uv"
    exit 1
fi

if command -v ssh &>/dev/null; then
    log "SSH client available"
else
    err "SSH not found."
    exit 1
fi

if [ -d "/Applications/Claude.app" ]; then
    log "Claude Desktop installed"
    HAS_CLAUDE_DESKTOP=true
else
    warn "Claude Desktop not found (will configure Claude Code only)"
    HAS_CLAUDE_DESKTOP=false
fi

if command -v claude &>/dev/null; then
    log "Claude Code CLI available"
    HAS_CLAUDE_CODE=true
else
    warn "Claude Code CLI not found (npm install -g @anthropic-ai/claude-code)"
    HAS_CLAUDE_CODE=false
fi

echo ""

#===============================================================================
# Step 2: Install MCP SDK
#===============================================================================
echo "--- Installing MCP SDK ---"

if [ "$PKG_MGR" = "uv" ]; then
    log "uv manages MCP dependencies per-server (no global install needed)"
else
    pip3 install "mcp[cli]" --break-system-packages 2>/dev/null || \
    pip3 install "mcp[cli]" || { err "Failed to install MCP SDK"; exit 1; }
    log "MCP SDK installed"
fi

#===============================================================================
# Step 3: Copy server files
#===============================================================================
echo ""
echo "--- Installing server files ---"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/bridge-ea-mcp.py"  "$INSTALL_DIR/"
cp "$SCRIPT_DIR/ea-sqlite-mcp.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/bridge-ea-mcp.py"
chmod +x "$INSTALL_DIR/ea-sqlite-mcp.py"
log "Servers installed to: $INSTALL_DIR"

#===============================================================================
# Step 4: Detect VM IP
#===============================================================================
echo ""
echo "--- Detecting Windows VM ---"

VM_IP=""
SSH_KEY="$HOME/.ssh/ea_vm_ed25519"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"

if [ -f "$VMRUN" ]; then
    RUNNING=$("$VMRUN" list 2>/dev/null | grep -i "Windows11-EA" || true)
    if [ -n "$RUNNING" ]; then
        VMX=$(echo "$RUNNING" | head -1)
        # getGuestIPAddress does not require guest credentials
        VM_IP=$("$VMRUN" getGuestIPAddress "$VMX" 2>/dev/null || true)
        if [ -n "$VM_IP" ] && [ "$VM_IP" != "unknown" ]; then
            log "Windows VM detected at: $VM_IP"
        else
            VM_IP=""
        fi
    fi
fi

if [ -z "$VM_IP" ]; then
    warn "Windows VM not running or not detected."
    read -r -p "    Enter VM IP (or press Enter to skip SSH bridge): " VM_IP
fi

if [ -z "$VM_IP" ]; then
    warn "No VM IP provided — SSH bridge will not be configured."
    warn "Re-run this script when the VM is running, or set EA_VM_HOST in"
    warn "your environment before starting Claude Desktop / Claude Code."
fi

#===============================================================================
# Step 5: SSH key setup (if VM available)
#===============================================================================
if [ -n "$VM_IP" ]; then
    echo ""
    echo "--- Setting up SSH key authentication ---"

    if [ ! -f "$SSH_KEY" ]; then
        log "Generating dedicated SSH key for EA VM..."
        ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "ea-mcp-bridge"
        log "Key created: $SSH_KEY"

        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║  Copy the SSH public key to your Windows VM:            ║"
        echo "║                                                         ║"
        echo "║  Option A (from Mac terminal):                          ║"
        echo "║    ssh-copy-id -i $SSH_KEY architect@$VM_IP"
        echo "║                                                         ║"
        echo "║  Option B (manually in Windows):                        ║"
        echo "║    Append the key below to:                             ║"
        echo "║    C:\\Users\\architect\\.ssh\\authorized_keys           ║"
        echo "║                                                         ║"
        echo "║  $(cat "${SSH_KEY}.pub")"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        read -r -p "Press Enter after copying the key (or 's' to skip): " SKIP_KEY
    else
        log "SSH key already exists: $SSH_KEY"
    fi

    echo "Testing SSH connection to $VM_IP..."
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes \
        "architect@$VM_IP" "echo SSH_OK" 2>/dev/null | grep -q "SSH_OK"; then
        log "SSH connection successful"
        SSH_WORKS=true
    else
        warn "SSH connection failed. Bridge will fall back to ssh-agent."
        warn "Enable OpenSSH Server in Windows: Settings > Optional Features > OpenSSH Server"
        SSH_WORKS=false
    fi
fi

#===============================================================================
# Step 6: Configure Claude Desktop
# JSON is generated by Python to correctly handle paths with spaces/quotes.
#===============================================================================
if [ "$HAS_CLAUDE_DESKTOP" = true ]; then
    echo ""
    echo "--- Configuring Claude Desktop ---"

    mkdir -p "$CLAUDE_CONFIG_DIR"

    if [ -f "$CLAUDE_CONFIG" ]; then
        log "Backing up existing Claude config..."
        cp "$CLAUDE_CONFIG" "$CLAUDE_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # Build config JSON via Python so path special-chars are handled correctly.
    EA_SQLITE_PY="$INSTALL_DIR/ea-sqlite-mcp.py" \
    EA_BRIDGE_PY="$INSTALL_DIR/bridge-ea-mcp.py" \
    EA_VM_IP="$VM_IP" \
    EA_SSH_KEY="$SSH_KEY" \
    EA_PKG_MGR="$PKG_MGR" \
    python3 << 'PYEOF' > "$CLAUDE_CONFIG"
import json, os

sqlite_py = os.environ["EA_SQLITE_PY"]
bridge_py = os.environ["EA_BRIDGE_PY"]
vm_ip     = os.environ.get("EA_VM_IP", "")
ssh_key   = os.environ.get("EA_SSH_KEY", "")
pkg_mgr   = os.environ.get("EA_PKG_MGR", "uv")

servers = {}

if pkg_mgr == "uv":
    servers["EA Model Analyzer"] = {
        "command": "uv",
        "args": ["run", "--with", "mcp[cli]", "python", sqlite_py],
    }
else:
    servers["EA Model Analyzer"] = {
        "command": "python3",
        "args": [sqlite_py],
    }

if vm_ip:
    env = {"EA_VM_HOST": vm_ip, "EA_VM_USER": "architect"}
    if ssh_key:
        env["EA_VM_KEY"] = ssh_key
    servers["Sparx EA (VM)"] = {
        "command": "python3",
        "args": [bridge_py],
        "env": env,
    }

print(json.dumps({"mcpServers": servers}, indent=2))
PYEOF

    log "Claude Desktop configured: $CLAUDE_CONFIG"
    warn "Restart Claude Desktop to load the new MCP servers."
fi

#===============================================================================
# Step 7: Configure Claude Code
#===============================================================================
if [ "$HAS_CLAUDE_CODE" = true ]; then
    echo ""
    echo "--- Configuring Claude Code ---"

    if [ "$PKG_MGR" = "uv" ]; then
        claude mcp add --transport stdio "EA Model Analyzer" \
            -- uv run --with "mcp[cli]" python "$INSTALL_DIR/ea-sqlite-mcp.py" 2>/dev/null && \
            log "Claude Code: EA Model Analyzer added" || \
            warn "Could not add EA Model Analyzer to Claude Code"
    else
        claude mcp add --transport stdio "EA Model Analyzer" \
            -- python3 "$INSTALL_DIR/ea-sqlite-mcp.py" 2>/dev/null && \
            log "Claude Code: EA Model Analyzer added" || \
            warn "Could not add EA Model Analyzer to Claude Code"
    fi

    if [ -n "$VM_IP" ]; then
        # Build the --env flags as a proper array to handle paths with spaces
        bridge_flags=(
            "--env" "EA_VM_HOST=$VM_IP"
            "--env" "EA_VM_USER=architect"
        )
        if [ -f "$SSH_KEY" ]; then
            bridge_flags+=("--env" "EA_VM_KEY=$SSH_KEY")
        fi

        claude mcp add --transport stdio "Sparx EA (VM)" \
            "${bridge_flags[@]}" \
            -- python3 "$INSTALL_DIR/bridge-ea-mcp.py" 2>/dev/null && \
            log "Claude Code: Sparx EA (VM) bridge added" || \
            warn "Could not add Sparx EA bridge to Claude Code"
    fi
fi

#===============================================================================
# Step 8: Windows VM setup reminder
#===============================================================================
if [ -n "$VM_IP" ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  WINDOWS VM SETUP (run inside the VM once):             ║"
    echo "║                                                         ║"
    echo "║  1. Enable OpenSSH Server (Admin PowerShell):           ║"
    echo "║     Add-WindowsCapability -Online \\"                   "
    echo "║       -Name OpenSSH.Server~~~~0.0.1.0                   ║"
    echo "║     Start-Service sshd                                  ║"
    echo "║     Set-Service -Name sshd -StartupType Automatic       ║"
    echo "║                                                         ║"
    echo "║  2. Download EA MCP Server:                             ║"
    echo "║     https://www.sparxsystems.jp/en/MCP/                 ║"
    echo "║     Install the .msi for your EA version (x64/x86)     ║"
    echo "║                                                         ║"
    echo "║  3. Open EA with a model before using the SSH bridge    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
fi

#===============================================================================
# Summary
#===============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅ Installation Complete                               ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Installed:                                             ║"
echo "║    $INSTALL_DIR/"
echo "║    • ea-sqlite-mcp.py  (native, always available)       ║"
if [ -n "$VM_IP" ]; then
echo "║    • bridge-ea-mcp.py  (SSH bridge → VM at $VM_IP)      ║"
fi
echo "║                                                         ║"
echo "║  Try with Claude:                                       ║"
echo "║    'Analyze ~/models/architecture.qea'                  ║"
echo "║    'Show all ArchiMate business processes'               ║"
echo "║    'Trace dependencies from the CRM System'             ║"
if [ -n "$VM_IP" ]; then
echo "║    'Create a new Application Component in EA'           ║"
fi
echo "║                                                         ║"
echo "║  Logs: ~/bridge-ea-mcp.log                             ║"
echo "╚══════════════════════════════════════════════════════════╝"
