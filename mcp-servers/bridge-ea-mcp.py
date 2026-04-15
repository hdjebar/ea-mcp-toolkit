#!/usr/bin/env python3
"""
bridge-ea-mcp.py — macOS-side STDIO proxy to Sparx EA MCP Server via SSH

Runs locally on macOS as a standard STDIO MCP server.
Transparently tunnels all MCP JSON-RPC messages over SSH to the
Windows VM where MCP3.exe and EA are running.

Usage:
  python3 bridge-ea-mcp.py

Environment variables:
  EA_VM_HOST     - Windows VM IP or hostname (required, or auto-detected via vmrun)
  EA_VM_USER     - Windows VM username (default: architect)
  EA_VM_PORT     - SSH port (default: 22)
  EA_VM_KEY      - Path to SSH private key (optional, uses ssh-agent if unset)
  EA_MCP_PATH    - Path to MCP3.exe on Windows (auto-detected from known install paths)
  EA_MCP_EDIT    - Set to "1" to enable -enableEdit flag (default: 1)

Claude Desktop config (~/.../Claude/claude_desktop_config.json):
  {
    "mcpServers": {
      "Sparx EA (VM)": {
        "command": "python3",
        "args": ["/path/to/bridge-ea-mcp.py"],
        "env": {
          "EA_VM_HOST": "192.168.75.128",
          "EA_VM_USER": "architect",
          "EA_VM_KEY":  "~/.ssh/ea_vm_ed25519"
        }
      }
    }
  }
"""

import os
import sys
import shlex
import signal
import subprocess
import shutil
import time
import logging

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

VM_HOST     = os.environ.get("EA_VM_HOST", "")
VM_USER     = os.environ.get("EA_VM_USER", "architect")
VM_PORT     = os.environ.get("EA_VM_PORT", "22")
VM_KEY      = os.environ.get("EA_VM_KEY", "")
ENABLE_EDIT = os.environ.get("EA_MCP_EDIT", "1") == "1"

_MCP_PATH_ENV = os.environ.get("EA_MCP_PATH", "")
MCP_CANDIDATE_PATHS = [
    p for p in [
        _MCP_PATH_ENV,
        r"C:\Program Files\Sparx Systems\EA\MCP_Server\MCP3.exe",
        r"C:\Program Files (x86)\Sparx Systems\EA\MCP_Server\MCP3.exe",
    ] if p
]

# Reconnect settings
MAX_RETRIES  = 3
RETRY_DELAYS = [2, 4, 8]   # seconds between attempts

LOG_FILE = os.path.expanduser("~/bridge-ea-mcp.log")

# ---------------------------------------------------------------------------
# Logging (file only — stdout/stdin are the MCP STDIO transport)
# ---------------------------------------------------------------------------

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("bridge-ea-mcp")


def resolve_vm_host() -> str:
    """Return the VM IP, auto-detecting via vmrun if EA_VM_HOST is not set."""
    if VM_HOST:
        return VM_HOST

    vm_sh = os.path.expanduser("~/setup-ea-vm/vm.sh")
    if os.path.isfile(vm_sh):
        try:
            result = subprocess.run(
                [vm_sh, "ip"], capture_output=True, text=True, timeout=10
            )
            ip = result.stdout.strip()
            if ip and ip not in ("unknown", ""):
                log.info(f"Auto-detected VM IP via vm.sh: {ip}")
                return ip
        except Exception as exc:
            log.warning(f"vm.sh ip failed: {exc}")

    vmrun = "/Applications/VMware Fusion.app/Contents/Library/vmrun"
    vmx   = os.path.expanduser(
        "~/Virtual Machines.localized/Windows11-EA.vmwarevm/Windows11-EA.vmx"
    )
    if os.path.isfile(vmrun) and os.path.isfile(vmx):
        try:
            result = subprocess.run(
                [vmrun, "getGuestIPAddress", vmx],
                capture_output=True, text=True, timeout=10,
            )
            ip = result.stdout.strip()
            if ip and "Error" not in ip:
                log.info(f"Auto-detected VM IP via vmrun: {ip}")
                return ip
        except Exception:
            pass

    log.error("Cannot determine VM IP. Set EA_VM_HOST in your environment.")
    sys.exit(1)


def find_mcp_path() -> str:
    """Return the configured MCP3.exe path (first candidate or the default)."""
    return MCP_CANDIDATE_PATHS[0] if MCP_CANDIDATE_PATHS else \
        r"C:\Program Files\Sparx Systems\EA\MCP_Server\MCP3.exe"


def verify_mcp_exists(host: str, mcp_path: str) -> bool:
    """Run a quick SSH command to check that MCP3.exe exists on the remote VM.

    Returns True if the file is found (or if the check itself fails and we
    cannot be sure — the caller should proceed and let the real SSH command
    surface the error).  Returns False only when we can positively confirm
    the file is absent.
    """
    ssh = shutil.which("ssh")
    if not ssh:
        return True  # can’t verify, assume OK

    cmd = [
        ssh, "-T",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ConnectTimeout=10",
        "-o", "BatchMode=yes",
        "-p", VM_PORT,
    ]
    if VM_KEY:
        cmd.extend(["-i", VM_KEY])
    cmd.append(f"{VM_USER}@{host}")
    # Windows cmd.exe: echo FOUND if MCP3.exe exists, NOTFOUND otherwise
    cmd.append(f'if exist "{mcp_path}" (echo FOUND) else (echo NOTFOUND)')

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        if "NOTFOUND" in result.stdout:
            log.error(
                f"MCP3.exe not found at remote path: {mcp_path}\n"
                f"  Download from: https://www.sparxsystems.jp/en/MCP/\n"
                f"  Override path: set EA_MCP_PATH env var"
            )
            return False
        if "FOUND" in result.stdout:
            log.info(f"MCP3.exe confirmed at: {mcp_path}")
            return True
        # Ambiguous result (SSH not yet ready, wrong shell, etc.) — proceed
        log.debug(f"MCP3.exe check inconclusive: stdout={result.stdout!r}")
        return True
    except subprocess.TimeoutExpired:
        log.warning("MCP3.exe existence check timed out — proceeding anyway")
        return True
    except Exception as exc:
        log.warning(f"MCP3.exe existence check failed: {exc} — proceeding anyway")
        return True


def build_ssh_command(host: str) -> list[str]:
    """Build the SSH argv list that launches MCP3.exe on the Windows VM."""
    ssh = shutil.which("ssh")
    if not ssh:
        log.error("ssh binary not found on PATH")
        sys.exit(1)

    mcp_path = find_mcp_path()
    quoted_path = shlex.quote(mcp_path)
    mcp_args   = "-enableEdit" if ENABLE_EDIT else ""
    remote_cmd = f"{quoted_path} {mcp_args}".strip()

    cmd = [
        ssh,
        "-T",
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


def main() -> None:
    """Launch SSH tunnel and pipe STDIO bidirectionally, with automatic retry."""
    host = resolve_vm_host()

    # Verify MCP3.exe exists on the VM before starting the real tunnel.
    # This produces a clear error message instead of a cryptic SSH exit code.
    mcp_path = find_mcp_path()
    if not verify_mcp_exists(host, mcp_path):
        log.warning(
            "MCP3.exe not found — bridge will attempt to start anyway. "
            "Set EA_MCP_PATH if the binary is in a non-standard location."
        )

    cmd = build_ssh_command(host)

    for attempt in range(MAX_RETRIES):
        log.info(
            f"Starting SSH bridge to {VM_USER}@{host} "
            f"(attempt {attempt + 1}/{MAX_RETRIES})"
        )
        log.debug(f"Command: {' '.join(cmd)}")

        try:
            proc = subprocess.Popen(
                cmd,
                stdin=sys.stdin.buffer,
                stdout=sys.stdout.buffer,
                stderr=subprocess.PIPE,
            )

            def handle_signal(signum, frame):
                log.info(f"Received signal {signum}, terminating")
                proc.terminate()
                sys.exit(0)

            signal.signal(signal.SIGTERM, handle_signal)
            signal.signal(signal.SIGINT,  handle_signal)

            exit_code = proc.wait()
            stderr_out = proc.stderr.read().decode("utf-8", errors="replace")
            if stderr_out:
                log.warning(f"SSH stderr: {stderr_out}")

            if exit_code == 0:
                log.info("SSH bridge exited cleanly.")
                sys.exit(0)

            log.warning(f"SSH bridge exited with code {exit_code}")

        except FileNotFoundError:
            log.error("ssh binary not found")
            sys.exit(1)
        except Exception as exc:
            log.error(f"Bridge error: {exc}")

        if attempt < MAX_RETRIES - 1:
            delay = RETRY_DELAYS[attempt]
            log.info(f"Retrying in {delay}s (attempt {attempt + 2}/{MAX_RETRIES})...")
            time.sleep(delay)
            host = resolve_vm_host()
            cmd  = build_ssh_command(host)

    log.error(f"SSH bridge failed after {MAX_RETRIES} attempts. Exiting.")
    sys.exit(1)


if __name__ == "__main__":
    main()
