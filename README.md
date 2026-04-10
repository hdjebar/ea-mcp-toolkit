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

- **Enterprise Architecture skill** — covers ArchiMate 3.2, BPMN 2.0, TOGAF, UML, C4, and 50+ EA frameworks. When combined with this toolkit, Claude can produce diagrams, ADRs, ATAM evaluations, and impact analyses directly from live EA model data.

- **Custom Sparx EA MCP** — this toolkit provides a working foundation to build a **fully customised MCP server tailored to a specific Sparx EA repository or organisational context**, enabling natural language exploration and integration of EA models via any LLM:
  - Query the repository in plain language: *"Which BPMN processes reference the ConnectionRequest business object?"* or *"Show all application components with no assigned owner"*
  - Navigate the model without knowing the EA UI: browse packages, diagrams, elements and relationships by describing what you are looking for
  - Validate governance rules conversationally: *"Are all ArchiMate relationships typed correctly?"*, *"Flag BPMN processes missing a lane assignment"*
  - Generate architecture artefacts on demand: ADRs, impact analysis, traceability matrices, directly from model data
  - Integrate EA with external systems via natural language orchestration: trigger EA queries from CI/CD pipelines, wikis, or ticketing tools through an LLM intermediary
  - Adapt the MCP tool definitions to domain-specific vocabularies (e.g. IEC 61968 for energy distribution, BIAN for banking, HL7/FHIR for healthcare) so the LLM speaks the organisation's language, not generic EA terminology

## Two MCP Servers

| Server | Runs on | Needs VM? | Read | Write | Best for |
|--------|---------|-----------|------|-------|----------|
| **EA Model Analyzer** | macOS (native) | No | ✅ | ❌ | Offline analysis, validation, statistics, impact tracing |
| **Sparx EA Bridge** | macOS → SSH → VM | Yes | ✅ | ✅ | Live CRUD, diagram export, element creation |

The SQLite analyzer handles the common case (read-only queries, validation, reporting) with zero startup time. The SSH bridge provides full EA interaction through the official Sparx Japan MCP server when you need write operations.

## Requirements

- macOS 13+ (Apple Silicon or Intel)
- Python 3.10+
- [uv](https://github.com/astral-sh/uv) (recommended) or pip
- VMware Fusion 13.5+ (free for personal use) — only for write access
- Sparx EA license — only for write access

## Documentation

- **[ADR-0001: Hybrid MCP Integration](docs/ADR-0001-hybrid-mcp-integration-sparx-ea-macos.md)** — Full architecture decision record with rationale, trade-offs, and component inventory
- **[VM Setup Guide](vm-setup/README.md)** — Scripted Windows 11 + EA installation
- **[MCP Servers Guide](mcp-servers/README.md)** — Server configuration and usage

## Related

- [SparxEA](https://github.com/hdjebar/SparxEA) — PowerShell/Python automation via the EA Interop API. Complements this repo: SparxEA writes and populates the repository; ea-mcp-toolkit reads, queries and validates it via SQLite and MCP.

## License

MIT
