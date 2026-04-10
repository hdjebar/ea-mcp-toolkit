# ea-mcp-toolkit

Hybrid MCP integration for **Sparx Enterprise Architect** on **macOS** — combining a Windows VM (VMware Fusion) with native cross-platform model analysis.

> Use Claude Desktop or Claude Code on your Mac to query, validate, and create ArchiMate/UML/BPMN models in Sparx EA — without leaving macOS.

## Architecture

```
┌─ macOS (Apple Silicon / Intel) ───────────────────────────────┐
│                                                                │
│  Claude Desktop / Claude Code                                  │
│       │ STDIO            │ STDIO                               │
│       ▼                  ▼                                     │
│  ┌──────────────┐  ┌──────────────────┐                       │
│  │ EA SQLite    │  │ SSH Bridge Proxy  │                       │
│  │ Analyzer     │  │                  │──── SSH ────┐          │
│  │ (native)     │  └──────────────────┘             │          │
│  └──────┬───────┘                                   ▼          │
│         │                              ┌────────────────────┐  │
│         ▼                              │ Windows 11 ARM VM  │  │
│    .qea file ◄─────────────────────────│ Sparx EA + MCP3.exe│  │
│    (SQLite)     shared folder          └────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

## What's Included

| Directory | Contents |
|-----------|----------|
| [`mcp-servers/`](mcp-servers/) | Two MCP servers + one-command installer |
| [`vm-setup/`](vm-setup/) | Scripted VMware Fusion + Windows 11 + EA installation |
| [`docs/`](docs/) | Architecture Decision Record (MADR v4.0.0) |

## Quick Start

### 1. Set up the Windows VM (if you need write access to EA)

```bash
cd vm-setup
chmod +x *.sh
./01-setup-vmware-fusion.sh   # Check prerequisites
./02-create-win11-vm.sh       # Create VM with autounattend
# Boot the VM, let Windows install unattended
./03-post-install.sh          # Install EA, configure MCP, create snapshot
```

### 2. Install the MCP servers on macOS

```bash
cd mcp-servers
chmod +x install-mcp-servers.sh
./install-mcp-servers.sh
```

This auto-configures Claude Desktop and/or Claude Code with both servers.

### 3. Use with Claude

```
You: "Analyze the model at ~/models/architecture.qea"
You: "Show all ArchiMate application components and their dependencies"
You: "Trace the impact of retiring the Legacy CRM — 3 hops"
You: "Validate all ArchiMate relationships in the model"
You: "Create a Business Process called 'Order Fulfillment' in EA"
```

## Claude Skills

This toolkit is designed to work alongside **Claude custom skills** — domain-specific instructions that extend Claude's behaviour when interacting with EA models via MCP.

- **Enterprise Architecture skill** — covers ArchiMate 3.2, BPMN 2.0, TOGAF, UML, C4, and 50+ EA frameworks. When combined with this