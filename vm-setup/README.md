# Automated Sparx EA + Windows 11 on VMware Fusion (macOS)

## Overview

This script set automates setting up **Sparx Enterprise Architect** on a **macOS** machine via **VMware Fusion** with **Windows 11** — including silent EA installation and **MCP Server configuration** for Claude AI integration.

## Architecture

```
┌──────────────────────────────────────────────────┐
│  macOS Host                                       │
│                                                   │
│  ┌─────────────────────┐   ┌──────────────────┐  │
│  │  VMware Fusion       │   │ Python SQLite    │  │
│  │  ┌─────────────────┐│   │ MCP Server       │  │
│  │  │ Windows 11 ARM  ││   │ (reads .qea      │  │
│  │  │                 ││   │  files natively)  │  │
│  │  │  Sparx EA 17.x  ││   └──────────────────┘  │
│  │  │  MCP Server     ││                         │
│  │  │  (COM → Claude) ││   Shared Folder: Z:\     │
│  │  └─────────────────┘│   ← ~/setup-ea-vm/shared │
│  └─────────────────────┘                         │
└──────────────────────────────────────────────────┘
```

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| macOS 13+ (Ventura or later) | Apple Silicon or Intel |
| VMware Fusion Pro 13.5+ | Free for personal use |
| 16 GB RAM minimum | 8 GB for VM + 8 GB for macOS |
| 100 GB free disk space | 80 GB VM disk + ISOs |
| Sparx EA license or trial | `.msi` installer file |

## Quick Start

### Step 1: Check prerequisites and install VMware Fusion

```bash
chmod +x *.sh
./01-setup-vmware-fusion.sh
```

This checks your environment, ensures VMware Fusion is installed, and creates the directory structure.

### Step 2: Create the Windows 11 VM

```bash
./02-create-win11-vm.sh
```

This script:
- Creates a `.vmx` configuration file for a Windows 11 VM
- Generates an `autounattend.xml` for fully unattended Windows installation
- Creates PowerShell scripts for silent EA installation
- Builds an autounattend ISO for the VM
- Configures a shared folder between Mac and Windows

**Before starting the VM**, you need to:

1. **Set the Windows ISO path** — Edit the `.vmx` file or use Fusion's GUI:
   - For Apple Silicon: Fusion can download Windows 11 ARM automatically
   - For Intel: Download from microsoft.com/software-download/windows11

2. **Place the EA installer** in `./shared/installers/`:
   ```bash
   cp ~/Downloads/easetupfull.msi ./shared/installers/
   ```

3. **Start the VM**:
   ```bash
   # Via GUI (recommended for first boot):
   open "$HOME/Virtual Machines.localized/Windows11-EA.vmwarevm"
   
   # Or via command line:
   vmrun start "$HOME/Virtual Machines.localized/Windows11-EA.vmwarevm/Windows11-EA.vmx"
   ```

### Step 3: Post-install configuration

After Windows boots and VMware Tools are running:

```bash
./03-post-install.sh
```

This copies installers, runs EA silent install, configures the MCP server, enables RDP, and creates a snapshot.

### Step 4: Daily use

```bash
./vm.sh start          # Start the VM
./vm.sh ea             # Launch Enterprise Architect
./vm.sh ea model.qea   # Open a specific model
./vm.sh rdp            # Connect via Remote Desktop
./vm.sh stop           # Graceful shutdown
```

## What Gets Installed (Automatically)

| Component | Method | Details |
|-----------|--------|---------|
| Windows 11 | `autounattend.xml` | Local account, no Microsoft login, telemetry minimized |
| VMware Tools | PowerShell script | Drivers, shared folders, clipboard sync |
| Sparx EA | `msiexec /qn` | Silent MSI install with EULA accepted |
| MCP Server | PowerShell config | Claude Desktop config pre-configured |
| Remote Desktop | Registry + Firewall | For accessing VM from Mac |

## Credentials

| Item | Value |
|------|-------|
| Windows user | `architect` |
| Windows password | `Sparx2026!` |
| Computer name | `EA-WORKSTATION` |

*Change these in `02-create-win11-vm.sh` before running.*

## VM Configuration

| Setting | Value |
|---------|-------|
| RAM | 8 GB |
| CPUs | 4 cores |
| Disk | 80 GB |
| Network | NAT |
| Display | 256 MB VRAM |
| Shared folder | `./shared` → `Z:\` |

## Shared Folder Structure

```
shared/
├── installers/          # EA .msi files
│   └── easetupfull.msi
├── licenses/            # EA key.dat file
│   └── key.dat
├── models/              # .qea model files (accessible from both Mac and Windows)
├── scripts/             # Additional automation scripts
└── autounattend.xml     # Generated Windows answer file
```

## Troubleshooting

### "vmrun: command not found"
```bash
sudo ln -sf "/Applications/VMware Fusion.app/Contents/Library/vmrun" /usr/local/bin/vmrun
```

### Windows stuck on "Let's connect you to a network"
Press `Shift+F10` to open command prompt, then:
```cmd
OOBE\BYPASSNRO
```
The VM will restart and offer "I don't have internet" option.

### EA installer not found by automated script
Copy manually into the running VM:
```bash
./vm.sh run "mkdir C:\Temp"
vmrun -gu architect -gp "Sparx2026!" copyFileFromHostToGuest \
  "$HOME/Virtual Machines.localized/Windows11-EA.vmwarevm/Windows11-EA.vmx" \
  ./shared/installers/easetupfull.msi "C:\Temp\easetupfull.msi"
./vm.sh run "msiexec /i C:\Temp\easetupfull.msi /qn /norestart"
```

### MCP Server not connecting
1. Ensure EA is running with a model open
2. Check Claude Desktop config exists: `%APPDATA%\Claude\claude_desktop_config.json`
3. Verify MCP3.exe path in the config matches your EA installation

### Apple Silicon: "This VM requires hardware that is not available"
Ensure you're using a Windows 11 ARM ISO, not x64. VMware Fusion 13.6.1+ can auto-download the correct ARM version.
