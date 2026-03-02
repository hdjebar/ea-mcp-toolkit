# EA MCP Servers for macOS

Hybrid MCP integration for Sparx Enterprise Architect on macOS — combining an SSH bridge to the Windows VM with a native SQLite model analyzer.

See [ADR-0001](ADR-0001-hybrid-mcp-integration-sparx-ea-macos.md) for the full architecture decision record.

## Quick Install

```bash
chmod +x install-mcp-servers.sh
./install-mcp-servers.sh
```

The installer detects your environment (Claude Desktop, Claude Code, VM status) and configures everything automatically.

## Servers

### EA Model Analyzer (native macOS)

Reads `.qea` files directly via SQLite. No VM, no EA installation required.

| Tool | Description |
|------|-------------|
| `list_elements` | Search elements by type, stereotype, name, package |
| `get_element_detail` | Full element with attributes, tags, connections, diagrams |
| `trace_dependencies` | Multi-hop dependency/impact chain traversal |
| `model_statistics` | Element counts, layer distribution, coverage metrics |
| `validate_archimate` | Check relationships against ArchiMate 3.2 metamodel |
| `list_packages` | Package hierarchy with element counts |
| `list_diagrams` | Diagram inventory with types and element counts |
| `query_sql` | Raw read-only SQL for advanced queries |

**Example prompts:**
- "Analyze the model at ~/models/architecture.qea"
- "Show all ArchiMate business processes and their serving relationships"
- "Trace the impact of changing the CRM System — 3 hops deep"
- "Validate all ArchiMate relationships in the model"

### Sparx EA Bridge (SSH to Windows VM)

Tunnels MCP traffic to the Sparx Japan MCP3.exe running in the Windows VM. Exposes all 30+ tools from the official server including live diagram access and element creation.

**Requires:** VM running, EA open with model loaded, OpenSSH Server enabled.

**Example prompts:**
- "Get the current diagram from EA"
- "Create an Application Component called 'Payment Gateway'"
- "Find all elements named 'Customer' in the EA model"

## Manual Configuration

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "EA Model Analyzer": {
      "command": "uv",
      "args": ["run", "--with", "mcp[cli]", "python", "~/.ea-mcp/ea-sqlite-mcp.py"]
    },
    "Sparx EA (VM)": {
      "command": "python3",
      "args": ["~/.ea-mcp/bridge-ea-mcp.py"],
      "env": {
        "EA_VM_HOST": "192.168.75.128",
        "EA_VM_USER": "architect",
        "EA_VM_KEY": "~/.ssh/ea_vm_ed25519"
      }
    }
  }
}
```

### Claude Code

```bash
claude mcp add --transport stdio "EA Model Analyzer" \
  -- uv run --with "mcp[cli]" python ~/.ea-mcp/ea-sqlite-mcp.py

claude mcp add --transport stdio "Sparx EA (VM)" \
  --env EA_VM_HOST=192.168.75.128 \
  --env EA_VM_USER=architect \
  --env EA_VM_KEY=~/.ssh/ea_vm_ed25519 \
  -- python3 ~/.ea-mcp/bridge-ea-mcp.py
```

## Windows VM Prerequisites

Run once in an elevated PowerShell inside the VM:

```powershell
# Enable OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# Install Sparx Japan MCP Server
# Download from: https://www.sparxsystems.jp/en/MCP/
# 64-bit: MCP_EA_x64.msi  |  32-bit: MCP_EA_x86.msi
```

## File Structure

```
mcp-servers/
├── ea-sqlite-mcp.py                              # Native SQLite MCP server
├── bridge-ea-mcp.py                               # SSH bridge proxy
├── install-mcp-servers.sh                         # One-command installer
├── ADR-0001-hybrid-mcp-integration-sparx-ea-macos.md  # Architecture decision
└── README.md                                      # This file
```
