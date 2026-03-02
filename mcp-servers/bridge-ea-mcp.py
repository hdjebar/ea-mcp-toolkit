#!/usr/bin/env python3
"""
bridge-ea-mcp.py — macOS-side STDIO proxy to Sparx EA MCP Server via SSH

Runs locally on macOS as a standard STDIO MCP server.
Transparently tunnels all MCP JSON-RPC messages over SSH to the
Windows VM where MCP3.exe and EA are running.

Usage:
  python3 bridge-ea-mcp.py

Environment variables:
  EA_VM_HOST     - Windows VM IP or hostname (default: from vm.sh ip)
  EA_VM_USER     - Windows VM username (default: architect)
  EA_VM_PORT     - SSH port (default: 22)
  EA_VM_KEY      - Path to SSH private key (optional, uses ssh-agent if unset)
  EA_MCP_PATH    - Path to MCP3.exe on Windows (auto-detected)
  EA_MCP_EDIT    - Set to "1" to enable -enableEdit flag (default: 1)

Claude Desktop config (~/Library/Application Support/Claude/claude_desktop_config.json):
  {
    "mcpServers": {
      "Sparx EA (VM)": {
        "command": "python3",
        "args": ["/path/to/bridge-ea-mcp.py"],
        "env": {
          "EA_VM_HOST": "192.168.75.128",
          "EA_VM_USER": "architect"
        }
      }
    }
  }

Claude Code:
  claude mcp add --transport stdio "Sparx EA (VM)" \
    -- python3 /path/to/bridge-ea-mcp.py
"""

import os
import sys
import signal
import subprocess
import shutil
import json
import logging

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

VM_HOST = os.environ.get("EA_VM_HOST", "")
VM_USER = os.environ.get("EA_VM_USER", "architect")
VM_PORT = os.environ.get("EA_VM_PORT", "22")
VM_KEY = os.environ.get("EA_VM_KEY", "")
ENABLE_EDIT = os.environ.get("EA_MCP_EDIT", "1") == "1"

# MCP3.exe search paths on Windows (tried in order)
MCP_PATHS = [
    os.environ.get("EA_MCP_PATH", ""),
    r"C:\Program Files\Sparx Systems\EA\MCP_Server\MCP3.exe",
    r"C:\Program Files (x86)\Sparx Systems\EA\MCP_Server\MCP3.exe",
]

LOG_FILE = os.path.expanduser("~/bridge-ea-mcp.log")

# ---------------------------------------------------------------------------
# Logging (to file only — stdout/stdin are the MCP transport)
# ---------------------------------------------------------------------------

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("bridge-ea-mcp")


def resolve_vm_host() -> str:
    """Try to auto-detect VM IP if not explicitly set."""
    if VM_HOST:
        return VM_HOST

    # Try the vm.sh helper from setup-ea-vm
    vm_sh = os.path.expanduser("~/setup-ea-vm/vm.sh")
    if os.path.isfile(vm_sh):
        try:
            result = subprocess.run(
                [vm_sh, "ip"], capture_output=True, text=True, timeout=10
            )
            ip = result.stdout.strip()
            if ip and ip != "unknown":
                log.info(f"Auto-detected VM IP from vm.sh: {ip}")
                return ip
        except Exception as e:
            log.warning(f"vm.sh ip failed: {e}")

    # Try vmrun directly
    vmrun = "/Applications/VMware Fusion.app/Contents/Library/vmrun"
    vmx_glob = os.path.expanduser(
        "~/Virtual Machines.localized/Windows11-EA.vmwarevm/Windows11-EA.vmx"
    )
    if os.path.isfile(vmrun) and os.path.isfile(vmx_glob):
        try:
            result = subprocess.run(
                [vmrun, "-gu", VM_USER, "-gp", "", "getGuestIPAddress", vmx_glob],
                capture_output=True,
                text=True,
                timeout=10,
            )
            ip = result.stdout.strip()
            if ip and "Error" not in ip:
                log.info(f"Auto-detected VM IP from vmrun: {ip}")
                return ip
        except Exception:
            pass

    log.error("Cannot determine VM IP. Set EA_VM_HOST environment variable.")
    sys.exit(1)


def find_mcp_path() -> str:
    """Return the first valid MCP3.exe path."""
    for path in MCP_PATHS:
        if path:
            return path
    return r"C:\Program Files\Sparx Systems\EA\MCP_Server\MCP3.exe"


def build_ssh_command(host: str) -> list[str]:
    """Build the SSH command that launches MCP3.exe on the Windows VM."""
    ssh = shutil.which("ssh")
    if not ssh:
        log.error("ssh not found on PATH")
        sys.exit(1)

    mcp_path = find_mcp_path()
    mcp_args = "-enableEdit" if ENABLE_EDIT else ""

    # Build the remote command
    # On Windows OpenSSH, the command is executed via cmd.exe
    remote_cmd = f'"{mcp_path}"'
    if mcp_args:
        remote_cmd += f" {mcp_args}"

    cmd = [
        ssh,
        "-T",  # No TTY allocation (pure pipe)
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ConnectTimeout=15",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        "-p", VM_PORT,
    ]

    if VM_KEY:
        cmd.extend(["-i", VM_KEY])

    cmd.append(f"{VM_USER}@{host}")
    cmd.append(remote_cmd)

    return cmd


def main():
    """Launch SSH tunnel and pipe STDIO bidirectionally."""
    host = resolve_vm_host()
    cmd = build_ssh_command(host)

    log.info(f"Starting SSH bridge to {VM_USER}@{host}")
    log.info(f"Command: {' '.join(cmd)}")

    try:
        proc = subprocess.Popen(
            cmd,
            stdin=sys.stdin.buffer,
            stdout=sys.stdout.buffer,
            stderr=subprocess.PIPE,
        )

        # Forward SIGTERM/SIGINT to child
        def handle_signal(signum, frame):
            log.info(f"Received signal {signum}, terminating SSH tunnel")
            proc.terminate()
            sys.exit(0)

        signal.signal(signal.SIGTERM, handle_signal)
        signal.signal(signal.SIGINT, handle_signal)

        # Wait for process to complete
        exit_code = proc.wait()

        # Log any stderr from SSH
        stderr_output = proc.stderr.read().decode("utf-8", errors="replace")
        if stderr_output:
            log.warning(f"SSH stderr: {stderr_output}")

        log.info(f"SSH bridge exited with code {exit_code}")
        sys.exit(exit_code)

    except FileNotFoundError:
        log.error("ssh binary not found")
        sys.exit(1)
    except Exception as e:
        log.error(f"Bridge error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
