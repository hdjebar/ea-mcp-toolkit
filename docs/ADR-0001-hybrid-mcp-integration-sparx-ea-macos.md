# ADR-0001: Adopt Hybrid MCP Integration for Sparx EA on macOS — SSH Bridge plus Native SQLite Analyzer

## Status
Accepted (2025-04-14)

## TOGAF Context
- **ADM Phase**: D — Technology Architecture
- **Architecture Domain**: Technology / Application (cross-cutting — tooling infrastructure for the EA practice itself)

## ArchiMate Linkage
| Element | Type | Layer | Role in this Decision |
|---------|------|-------|----------------------|
| Claude Desktop (macOS) | ApplicationComponent | Application | Primary MCP client — orchestrates both servers |
| Claude Code CLI (macOS) | ApplicationComponent | Application | Alternative MCP client for terminal-based EA work |
| SSH Bridge Proxy | ApplicationComponent | Application | New — local STDIO process forwarding MCP traffic over SSH |
| EA SQLite Analyzer | ApplicationComponent | Application | New — native Python MCP server reading .qea files directly |
| Sparx EA MCP Server (MCP3.exe) | ApplicationComponent | Application | Existing — Sparx Japan COM-based MCP server on Windows |
| Sparx Enterprise Architect | ApplicationComponent | Application | Existing — target EA tool, Windows-only, COM automation |
| Windows 11 ARM VM (VMware Fusion) | Node | Technology | Hosting environment for EA and its MCP server |
| macOS Host (Apple Silicon) | Node | Technology | Developer workstation running Claude clients |
| .qea Model Repository | DataObject | Application | SQLite-based EA model file — read by both paths |
| OpenSSH Tunnel | CommunicationNetwork | Technology | Transport layer between Mac and VM for MCP JSON-RPC |

## Compliance Linkage
| Obligation | Standard / Regulation | Article | Impact |
|-----------|----------------------|---------|--------|
| Tooling interoperability | TOGAF 10 | §44.3 (Technology Standards) | Satisfies — establishes standards for EA tool integration |
| Model integrity (read-only default) | ISO 27001 | A.8.3 (Information access restriction) | Satisfies — SQLite server enforces read-only; bridge requires explicit -enableEdit |
| Intellectual property protection | EU AI Act | Art. 53.1(c) (GPAI copyright) | N/A — local tool integration, no third-party model training |

## Context and Problem Statement

The enterprise architecture practice uses Sparx Enterprise Architect as its primary modeling tool, but the team works on macOS (Apple Silicon). EA is a Windows-only application with a COM-based automation API. Sparx Japan provides an official MCP server (MCP3.exe) that enables Claude to interact with EA models via the Model Context Protocol, but this server requires a running EA instance on Windows and communicates exclusively via Windows STDIO.

The architectural problem is: **how do we connect Claude Desktop and Claude Code running natively on macOS to Sparx EA’s MCP capabilities when the MCP server can only run on Windows?**

Constraints include: Apple Silicon Macs cannot run Windows natively (no Boot Camp); the Sparx MCP server requires COM interop with a live EA process; .qea model files are SQLite databases that can be read cross-platform; the MCP protocol uses JSON-RPC over STDIO (local process piping) or Streamable HTTP (remote); and model write operations must go through the EA COM API to avoid database corruption.

**Triggers**: Need to use Claude AI assistants for ArchiMate modeling, impact analysis, model validation, and documentation generation while working on macOS hardware.

## Decision Drivers

- **Cross-platform developer experience** — architects work on macOS and should not need to switch to a Windows desktop for every Claude interaction
- **Full EA capability access** — creating elements, updating diagrams, and querying live models must remain possible when needed
- **Offline/lightweight analysis** — common tasks (model statistics, dependency tracing, validation) should not require booting a Windows VM
- **Data integrity** — write operations must go through the official COM API; direct SQLite writes corrupt GUIDs and cascading updates
- **Low operational complexity** — the solution should be maintainable by an architecture team, not require DevOps infrastructure
- **Minimal latency** — MCP tool calls should complete in seconds, not minutes

## Considered Options

- **Option A**: Hybrid — SSH bridge for live EA + native SQLite analyzer for offline analysis
- **Option B**: Single server — run Claude Desktop inside the Windows VM exclusively
- **Option C**: Single server — expose Sparx MCP as a remote HTTP/SSE server on the VM
- **Option D**: Status quo — no MCP integration; manual export/import workflow

## Decision Outcome

**Chosen option**: **Option A — Hybrid (SSH Bridge + SQLite Analyzer)**

**Rationale**: This option uniquely provides both always-available offline analysis (no VM boot required) and full live EA interaction (when the VM is running) from the macOS native environment. The SSH bridge reuses the production-ready Sparx Japan MCP server via standard STDIO piping, avoiding the need to build or maintain a custom COM server. The SQLite analyzer handles the 80% case (read-only queries, validation, statistics, impact tracing) with zero infrastructure dependency. This combination scores highest on cross-platform DX and offline capability while maintaining full write capability through the established COM path.

### Consequences

**Positive:**
- Architects stay in their macOS environment with native Claude Desktop / Claude Code
- Model analysis available instantly without VM boot (SQLite path: ~0ms startup)
- Full CRUD operations available when VM is running (bridge path: ~2s SSH handshake then real-time)
- No custom Windows development required — reuses official MCP3.exe as-is
- Both servers register independently in Claude; Claude selects the appropriate one based on the task
- .qea files on shared folders are accessible to both paths simultaneously

**Negative (accepted trade-offs):**
- Two MCP servers to maintain instead of one
- SSH key management between Mac and VM required (mitigated: install script automates key generation)
- OpenSSH Server must be enabled in Windows VM (mitigated: one-time setup, automated in post-install script)
- Write operations require VM running + EA open with model loaded (inherent to the COM API)

**Risks (residual):**
- SSH connection drops during a write operation could leave EA in an inconsistent state — mitigated by MCP3.exe having no delete operations and EA’s own transaction handling
- SQLite server could report stale data if the model is being actively edited in EA — mitigated by SQLite WAL mode allowing concurrent reads during writes
- VMware Fusion networking changes (NAT IP reassignment) could break the bridge — mitigated by auto-detection via vmrun in the bridge startup

### Confirmation

This decision is confirmed when:
1. `claude mcp list` on macOS shows both “EA Model Analyzer” and “Sparx EA (VM)” servers
2. Claude can execute `model_statistics` on a .qea file without the VM running
3. Claude can execute `get_current_diagram` through the bridge with the VM running and EA open
4. Round-trip latency for a bridge tool call is under 5 seconds
5. The install script completes without errors on a clean macOS Sequoia + Apple Silicon machine

## Pros and Cons of the Options

### Option A — Hybrid (SSH Bridge + SQLite Analyzer) ✅ Chosen

- ✅ Works on macOS natively for both Claude Desktop and Claude Code
- ✅ Offline analysis always available (no VM dependency for reads)
- ✅ Full live CRUD when VM is running (reuses official MCP3.exe)
- ✅ No custom Windows code — bridge is a thin SSH pipe
- ✅ Both paths read the same .qea files for consistency
- ✅ SQLite server validates ArchiMate metamodel (not available in MCP3.exe)
- ❌ Two servers to install and configure
- ❌ SSH key setup required between Mac and VM
- ❌ Bridge adds ~2s latency for SSH handshake on first call

### Option B — Claude Desktop Inside Windows VM

- ✅ Simplest setup — everything runs locally in Windows
- ✅ Zero bridging or networking complexity
- ❌ Forces architect to work inside the VM for all Claude interactions
- ❌ VM must be running for any AI-assisted architecture work
- ❌ No offline analysis capability

### Option C — Remote HTTP/SSE MCP Server on VM

- ✅ Single server, platform-independent client access
- ❌ Requires building a custom HTTP wrapper around MCP3.exe (STDIO-only binary)
- ❌ Auth, CORS, TLS configuration complexity
- ❌ No offline analysis when VM is down

### Option D — Status Quo (No MCP)

- ✅ No setup or maintenance burden
- ❌ No AI-assisted modeling, validation, or impact analysis
- ❌ Manual XMI/CSV export-import for every Claude interaction

## Related Decisions

| ADR | Relationship | Notes |
|-----|-------------|-------|
| (future) ADR-0002: VM platform selection | Depends on | This ADR assumes VMware Fusion; would need revision if switching to Parallels or UTM |
| (future) ADR-0003: EA model repository strategy | Extends | SQLite (.qea) vs. DBMS-hosted repository affects which path is available |
| (future) ADR-0004: Claude skill for ArchiMate validation | Depends on | Validation rules in the SQLite MCP server should align with the Claude skill’s ArchiMate reference |

## Review Trigger

This decision should be re-evaluated if:
- Sparx Systems releases a cross-platform MCP server
- Sparx Systems releases a native macOS version of Enterprise Architect
- MCP protocol adds native remote-over-SSH transport
- The team migrates from VMware Fusion to a different virtualization platform
- The team adopts a DBMS-hosted EA repository instead of .qea files

**Scheduled review date**: April 2027 (or next EA major version upgrade)

## Architecture View

```
┌─────────────────────────────────────────────────────────────────┐
│  macOS Host (Apple Silicon)                                     │
│                                                                 │
│  ┌─────────────────────┐         ┌────────────────────────┐  │
│  │ Claude Desktop       │         │ Claude Code CLI          │  │
│  │ (MCP Client)         │         │ (MCP Client)             │  │
│  └──┬─────────┬────────┘         └──┬─────────┬────────────┘  │
│     │          │                     │          │               │
│  STDIO        STDIO                STDIO        STDIO            │
│     │          │                     │          │               │
│     ▼          ▼                     ▼          ▼               │
│  ┌──────────┐ ┌───────────────┐  (same two servers)           │
│  │ EA SQLite│ │ SSH Bridge     │                               │
│  │ Analyzer │ │ Proxy          │                               │
│  │ (Python) │ │ (Python)       │                               │
│  └──┬──────┘ └──┬─────────────┘                               │
│     │            │ SSH (port 22)                                │
│     │            ▼                                              │
│     │  ┌─────────────────────────────────────────┐             │
│     │  │ Windows 11 ARM VM (VMware Fusion)        │             │
│     │  │                                          │             │
│     │  │  OpenSSH ──▶ MCP3.exe ──COM──▶ Sparx EA │             │
│     │  │  Server       (STDIO)           (running)│             │
│     │  └─────────────────────────────────────────┘             │
│     ▼                                                           │
│  ┌──────────┐                                                   │
│  │ .qea file│  (SQLite — on shared folder or local)            │
│  └──────────┘                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Component Inventory

| Component | Location | Language | Lines | Dependencies | Maintainer |
|-----------|----------|----------|-------|--------------|------------|
| ea-sqlite-mcp.py | ~/.ea-mcp/ | Python 3.10+ | ~900 | mcp[cli], sqlite3 (stdlib) | Architecture team |
| bridge-ea-mcp.py | ~/.ea-mcp/ | Python 3.10+ | ~210 | ssh (system), subprocess (stdlib) | Architecture team |
| install-mcp-servers.sh | repo/mcp-servers/ | Bash | ~360 | uv or pip, ssh-keygen, python3 | Architecture team |
| MCP3.exe | EA\MCP_Server\ | .NET 9.0 | N/A (binary) | EA COM, .NET Runtime | Sparx Systems Japan |
| autounattend.xml | repo/vm-setup/shared/ | XML | ~150 | Windows Setup | Architecture team |
| vm.sh | repo/vm-setup/ | Bash | ~80 | vmrun (VMware Fusion) | Architecture team |

## More Information

- Sparx Japan MCP Server: https://www.sparxsystems.jp/en/MCP/
- MCP Protocol specification: https://modelcontextprotocol.io/
- EA database schema: “Inside Enterprise Architect” by Thomas Kilian (leanpub.com/InsideEA)
- ArchiMate 3.2 Specification: The Open Group (opengroup.org)
- MADR v4.0.0 template: https://adr.github.io/madr/
