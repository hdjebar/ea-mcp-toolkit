#!/bin/bash
#===============================================================================
# install-mcp-servers.sh
# Installs both EA MCP servers on macOS:
#   1. SSH Bridge to Sparx EA MCP in Windows VM (requires VM running)
#   2. SQLite Model Analyzer (runs natively, no VM needed)
#
# Also configures Claude Desktop and/or Claude Code.
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.ea-mcp"
CLAUDE_CONFIG_DIR="$HOME/Library/Application Support/Claude"
CLAUDE_CONFIG="$CLAUDE_CONFIG_DIR/claude_desktop_config.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  EA MCP Server Installer for macOS                      ║"
echo "║  Bridge (SSH→VM) + SQLite Analyzer (native)             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

#===============================================================================
# Step 1: Check prerequisites
#===============================================================================
echo "--- Checking prerequisites ---"

# Python 3
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version)
    log "Python: $PY_VER"
else
    err "Python 3 not found. Install via: brew install python3"
    exit 1
fi

# uv (preferred) or pip
if command -v uv &>/dev/null; then
    UV_VER=$(uv --version)
    log "uv: $UV_VER"
    PKG_MGR="uv"
elif command -v pip3 &>/dev/null; then
    log "pip3 found (uv recommended: brew install uv)"
    PKG_MGR="pip"
else
    err "Neither uv nor pip3 found. Install uv: brew install uv"
    exit 1
fi

# SSH
if command -v ssh &>/dev/null; then
    log "SSH client available"
else
    err "SSH not found."
    exit 1
fi

# Check for Claude Desktop
if [ -d "/Applications/Claude.app" ]; then
    log "Claude Desktop installed"
    HAS_CLAUDE_DESKTOP=true
else
    warn "Claude Desktop not found (will configure for Claude Code only)"
    HAS_CLAUDE_DESKTOP=false
fi

# Check for Claude Code
if command -v claude &>/dev/null; then
    log "Claude Code CLI available"
    HAS_CLAUDE_CODE=true
else
    warn "Claude Code CLI not found (npm install -g @anthropic-ai/claude-code)"
    HAS_CLAUDE_CODE=false
fi

echo ""

#===============================================================================
# Step 2: Install MCP Python package
#===============================================================================
echo "--- Installing MCP SDK ---"

if [ "$PKG_MGR" = "uv" ]; then
    # uv manages its own environments; just verify it can resolve mcp
    log "uv will manage MCP dependencies per-server (no global install needed)"
else
    pip3 install "mcp[cli]" --break-system-packages 2>/dev/null || \
    pip3 install "mcp[cli]" || {
        err "Failed to install MCP SDK"
        exit 1
    }
    log "MCP SDK installed"
fi

#===============================================================================
# Step 3: Copy server files
#===============================================================================
echo ""
echo "--- Installing server files ---"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/bridge-ea-mcp.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/ea-sqlite-mcp.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/bridge-ea-mcp.py"
chmod +x "$INSTALL_DIR/ea-sqlite-mcp.py"

log "Servers installed to: $INSTALL_DIR"

#===============================================================================
# Step 4: Detect VM IP (if available)
#===============================================================================
echo ""
echo "--- Detecting Windows VM ---"

VM_IP=""
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"

if [ -f "$VMRUN" ]; then
    # Try to get IP from running VM
    RUNNING=$("$VMRUN" list 2>/dev/null | grep -i "Windows11-EA" || true)
    if [ -n "$RUNNING" ]; then
        VMX=$(echo "$RUNNING" | head -1)
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
    echo "    Enter VM IP manually (or press Enter to skip SSH bridge):"
    read -r -p "    VM IP: " VM_IP
fi

#===============================================================================
# Step 5: Set up SSH key auth (if VM available)
#===============================================================================
if [ -n "$VM_IP" ]; then
    echo ""
    echo "--- Setting up SSH key authentication ---"

    SSH_KEY="$HOME/.ssh/ea_vm_ed25519"
    if [ ! -f "$SSH_KEY" ]; then
        log "Generating dedicated SSH key for EA VM..."
        ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "ea-mcp-bridge"
        log "Key created: $SSH_KEY"

        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║  IMPORTANT: Copy the SSH key to your Windows VM         ║"
        echo "║                                                         ║"
        echo "║  Option A (from Mac terminal):                          ║"
        echo "║    ssh-copy-id -i $SSH_KEY architect@$VM_IP"
        echo "║                                                         ║"
        echo "║  Option B (manually in Windows):                        ║"
        echo "║    1. Copy this public key:                             ║"
        echo "║       $(cat "${SSH_KEY}.pub")"
        echo "║    2. In Windows, append to:                            ║"
        echo "║       C:\\Users\\architect\\.ssh\\authorized_keys        ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        read -r -p "Press Enter after copying the key (or 's' to skip): " SKIP_KEY
    else
        log "SSH key already exists: $SSH_KEY"
    fi

    # Test SSH connection
    echo "Testing SSH connection to $VM_IP..."
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes \
        "architect@$VM_IP" "echo SSH_OK" 2>/dev/null | grep -q "SSH_OK"; then
        log "SSH connection successful"
        SSH_WORKS=true
    else
        warn "SSH connection failed. Bridge will use password auth (less reliable)."
        warn "Enable OpenSSH Server in Windows: Settings > Optional Features > OpenSSH Server"
        SSH_WORKS=false
    fi
fi

#===============================================================================
# Step 6: Configure Claude Desktop
#===============================================================================
if [ "$HAS_CLAUDE_DESKTOP" = true ]; then
    echo ""
    echo "--- Configuring Claude Desktop ---"

    mkdir -p "$CLAUDE_CONFIG_DIR"

    # Build the config
    BRIDGE_PY="$INSTALL_DIR/bridge-ea-mcp.py"
    SQLITE_PY="$INSTALL_DIR/ea-sqlite-mcp.py"

    # Start building JSON
    SERVERS=""

    # SQLite server (always available)
    if [ "$PKG_MGR" = "uv" ]; then
        SQLITE_CMD="uv"
        SQLITE_ARGS='["run", "--with", "mcp[cli]", "python", "'$SQLITE_PY'"]'
    else
        SQLITE_CMD="python3"
        SQLITE_ARGS='["'$SQLITE_PY'"]'
    fi

    SERVERS="\"EA Model Analyzer\": {
      \"command\": \"$SQLITE_CMD\",
      \"args\": $SQLITE_ARGS
    }"

    # SSH Bridge (if VM available)
    if [ -n "$VM_IP" ]; then
        SSH_KEY_ESCAPED=${SSH_KEY//\//\\/}
        BRIDGE_ENV="{
        \"EA_VM_HOST\": \"$VM_IP\",
        \"EA_VM_USER\": \"architect\""

        if [ -f "$SSH_KEY" ]; then
            BRIDGE_ENV="$BRIDGE_ENV,
        \"EA_VM_KEY\": \"$SSH_KEY\""
        fi
        BRIDGE_ENV="$BRIDGE_ENV
      }"

        SERVERS="$SERVERS,
    \"Sparx EA (VM)\": {
      \"command\": \"python3\",
      \"args\": [\"$BRIDGE_PY\"],
      \"env\": $BRIDGE_ENV
    }"
    fi

    # Merge with existing config or create new
    if [ -f "$CLAUDE_CONFIG" ]; then
        log "Backing up existing Claude config..."
        cp "$CLAUDE_CONFIG" "$CLAUDE_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    fi

    cat > "$CLAUDE_CONFIG" << JSONEOF
{
  "mcpServers": {
    $SERVERS
  }
}
JSONEOF

    log "Claude Desktop configured: $CLAUDE_CONFIG"
    warn "Restart Claude Desktop to load the new MCP servers."
fi

#===============================================================================
# Step 7: Configure Claude Code
#===============================================================================
if [ "$HAS_CLAUDE_CODE" = true ]; then
    echo ""
    echo "--- Configuring Claude Code ---"

    # SQLite server
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

    # SSH Bridge
    if [ -n "$VM_IP" ]; then
        BRIDGE_ENV_FLAGS=""
        if [ -f "$SSH_KEY" ]; then
            BRIDGE_ENV_FLAGS="--env EA_VM_HOST=$VM_IP --env EA_VM_USER=architect --env EA_VM_KEY=$SSH_KEY"
        else
            BRIDGE_ENV_FLAGS="--env EA_VM_HOST=$VM_IP --env EA_VM_USER=architect"
        fi

        claude mcp add --transport stdio "Sparx EA (VM)" \
            $BRIDGE_ENV_FLAGS \
            -- python3 "$INSTALL_DIR/bridge-ea-mcp.py" 2>/dev/null && \
            log "Claude Code: Sparx EA (VM) bridge added" || \
            warn "Could not add Sparx EA bridge to Claude Code"
    fi
fi

#===============================================================================
# Step 8: Enable OpenSSH on Windows VM (reminder)
#===============================================================================
if [ -n "$VM_IP" ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  WINDOWS VM SETUP (run inside the VM once):             ║"
    echo "║                                                         ║"
    echo "║  1. Enable OpenSSH Server (Admin PowerShell):           ║"
    echo "║     Add-WindowsCapability -Online \\"
    echo "║       -Name OpenSSH.Server~~~~0.0.1.0                   ║"
    echo "║     Start-Service sshd                                  ║"
    echo "║     Set-Service -Name sshd -StartupType Automatic       ║"
    echo "║                                                         ║"
    echo "║  2. Download EA MCP Server:                             ║"
    echo "║     https://www.sparxsystems.jp/en/MCP/                 ║"
    echo "║     Install the .msi for your EA version (x64/x86)     ║"
    echo "║                                                         ║"
    echo "║  3. Ensure EA is running with a model open              ║"
    echo "║     when using the SSH bridge                           ║"
    echo "╚══════════════════════════════════════════════════════════╝"
fi

#===============================================================================
# Summary
#===============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅ Installation Complete                               ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                         ║"
echo "║  Installed servers:                                     ║"
echo "║    📁 $INSTALL_DIR/"
echo "║    • ea-sqlite-mcp.py  (native macOS, always available) ║"
if [ -n "$VM_IP" ]; then
echo "║    • bridge-ea-mcp.py  (SSH bridge to VM at $VM_IP)     ║"
fi
echo "║                                                         ║"
echo "║  Usage:                                                 ║"
echo "║    Claude: 'Analyze the model at ~/models/arch.qea'     ║"
echo "║    Claude: 'Show me all ArchiMate business processes'    ║"
echo "║    Claude: 'Trace dependencies from CRM System'         ║"
echo "║    Claude: 'Validate the ArchiMate relationships'       ║"
if [ -n "$VM_IP" ]; then
echo "║    Claude: 'Create a new Application Component in EA'   ║"
echo "║    Claude: 'Get the current diagram from EA'            ║"
fi
echo "║                                                         ║"
echo "║  Logs: ~/bridge-ea-mcp.log                             ║"
echo "╚══════════════════════════════════════════════════════════╝"
