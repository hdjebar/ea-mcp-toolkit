#!/bin/bash
#===============================================================================
# 02-create-win11-vm.sh
# Creates a Windows 11 ARM/x64 VM in VMware Fusion via command line
# Generates .vmx config and autounattend.xml for unattended installation
# Run on your Mac host
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
VM_DIR="$HOME/Virtual Machines.localized"
VM_NAME="Windows11-EA"
VMX_DIR="$VM_DIR/${VM_NAME}.vmwarevm"
VMX_FILE="$VMX_DIR/${VM_NAME}.vmx"
LOG_FILE="$SCRIPT_DIR/setup.log"

# VM Configuration — adjust as needed
VM_RAM_MB=8192          # 8 GB RAM (min 4096 for Win11)
VM_CPUS=4               # 4 CPU cores
VM_DISK_GB=80           # 80 GB disk (EA needs ~2GB, models can grow)
VM_DISK_SIZE=$((VM_DISK_GB * 1024))  # Convert to MB

# Windows credentials for autounattend
WIN_USER="architect"
WIN_PASS="Sparx2026!"
WIN_HOSTNAME="EA-WORKSTATION"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
ARCH=$(uname -m)

#===============================================================================
# STEP 1: Check for VMware Fusion
#===============================================================================
log "=== Creating Windows 11 VM ==="

if [ ! -f "$VMRUN" ]; then
    log "❌ VMware Fusion not installed. Run 01-setup-vmware-fusion.sh first."
    exit 1
fi

#===============================================================================
# STEP 2: Create VM directory and virtual disk
#===============================================================================
log "=== Step 1: Creating VM directory ==="

if [ -d "$VMX_DIR" ]; then
    log "⚠️  VM directory already exists: $VMX_DIR"
    read -p "Delete and recreate? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$VMX_DIR"
    else
        log "Aborting."
        exit 0
    fi
fi

mkdir -p "$VMX_DIR"

# Create virtual disk
log "=== Step 2: Creating ${VM_DISK_GB}GB virtual disk ==="
VDISK_TOOL="/Applications/VMware Fusion.app/Contents/Library/vmware-vdiskmanager"

if [ -f "$VDISK_TOOL" ]; then
    "$VDISK_TOOL" -c -s "${VM_DISK_GB}GB" -a lsilogic -t 0 "$VMX_DIR/${VM_NAME}.vmdk"
    log "✅ Virtual disk created"
else
    log "⚠️  vdiskmanager not found, disk will be created by Fusion on first boot"
fi

#===============================================================================
# STEP 3: Generate .vmx configuration file
#===============================================================================
log "=== Step 3: Generating VMX configuration ==="

if [[ "$ARCH" == "arm64" ]]; then
    GUEST_OS="arm-windows11-64"
    HW_VERSION="20"
    FIRMWARE="efi"
else
    GUEST_OS="windows11-64"
    HW_VERSION="20"
    FIRMWARE="efi"
fi

cat > "$VMX_FILE" << VMXEOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "$HW_VERSION"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
displayName = "$VM_NAME"
guestOS = "$GUEST_OS"
firmware = "$FIRMWARE"
uefi.secureBoot.enabled = "TRUE"

# Memory & CPU
memsize = "$VM_RAM_MB"
numvcpus = "$VM_CPUS"

# Virtual disk
scsi0.virtualDev = "lsisas1068"
scsi0.present = "TRUE"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "${VM_NAME}.vmdk"

# CD/DVD - Windows ISO (patched by 01-setup-vmware-fusion.sh)
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.fileName = ""
sata0:0.deviceType = "cdrom-image"
sata0:0.startConnected = "TRUE"

# Second CD/DVD - autounattend ISO
sata0:1.present = "TRUE"
sata0:1.fileName = ""
sata0:1.deviceType = "cdrom-image"
sata0:1.startConnected = "TRUE"

# Network - NAT
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "vmxnet3"
ethernet0.addressType = "generated"
ethernet0.wakeOnPcktRcv = "FALSE"

# USB
usb.present = "TRUE"
usb_xhci.present = "TRUE"

# Sound
sound.present = "TRUE"
sound.virtualDev = "hdaudio"
sound.autodetect = "TRUE"

# Display
svga.vramSize = "268435456"
svga.graphicsMemoryKB = "262144"

# vTPM (required for Windows 11)
# NOTE: do NOT add encryption.keySafe here — Fusion generates it on first boot
vtpm.present = "TRUE"
managedvm.autoAddVTPM = "software"

# Shared folders
sharedFolder0.present = "TRUE"
sharedFolder0.enabled = "TRUE"
sharedFolder0.readAccess = "TRUE"
sharedFolder0.writeAccess = "TRUE"
sharedFolder0.hostPath = "$SCRIPT_DIR/shared"
sharedFolder0.guestName = "MacShare"
sharedFolder0.expiration = "never"
sharedFolder.maxNum = "1"
isolation.tools.hgfs.disable = "FALSE"

# Power management
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"

# Tools
tools.syncTime = "TRUE"
tools.upgrade.policy = "upgradeAtPowerCycle"
VMXEOF

log "✅ VMX configuration created at: $VMX_FILE"

#===============================================================================
# STEP 4: Create shared folder structure
#===============================================================================
log "=== Step 4: Creating shared folders ==="

mkdir -p "$SCRIPT_DIR/shared/installers"
mkdir -p "$SCRIPT_DIR/shared/scripts"
mkdir -p "$SCRIPT_DIR/shared/licenses"
mkdir -p "$SCRIPT_DIR/shared/models"

# Copy EA installer to shared folder — all three editions in priority order.
# 02-install-sparx-ea.ps1 will detect which one is present and act accordingly.
for msi in \
    "$SCRIPT_DIR/iso/easetupfull.msi" \
    "$SCRIPT_DIR/iso/easetup.msi" \
    "$SCRIPT_DIR/iso/ealite_x64.msi"; do
    if [ -f "$msi" ]; then
        cp "$msi" "$SCRIPT_DIR/shared/installers/"
        log "✅ Copied $(basename "$msi") to shared folder"
        break
    fi
done

log "✅ Shared folder structure created at: $SCRIPT_DIR/shared/"

#===============================================================================
# STEP 5: Generate autounattend.xml
#===============================================================================
log "=== Step 5: Generating autounattend.xml ==="

if [[ "$ARCH" == "arm64" ]]; then
    PROC_ARCH="arm64"
else
    PROC_ARCH="amd64"
fi

cat > "$SCRIPT_DIR/shared/autounattend.xml" << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend"
          xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

  <!-- ============================================================ -->
  <!-- PASS 1: windowsPE — Disk partitioning & image selection      -->
  <!-- ============================================================ -->
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE"
               processorArchitecture="PROC_ARCH_PLACEHOLDER"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <SetupUILanguage>
        <UILanguage>en-US</UILanguage>
      </SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>

    <component name="Microsoft-Windows-Setup"
               processorArchitecture="PROC_ARCH_PLACEHOLDER"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">

      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Size>260</Size>
              <Type>EFI</Type>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Size>16</Size>
              <Type>MSR</Type>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>3</Order>
              <Extend>true</Extend>
              <Type>Primary</Type>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Format>FAT32</Format>
              <Label>System</Label>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>3</Order>
              <PartitionID>3</PartitionID>
              <Format>NTFS</Format>
              <Label>Windows</Label>
              <Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>

      <ImageInstall>
        <OSImage>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>3</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>

      <UserData>
        <AcceptEula>true</AcceptEula>
        <FullName>WIN_USER_PLACEHOLDER</FullName>
        <Organization>Enterprise Architecture</Organization>
      </UserData>

      <UseConfigurationSet>true</UseConfigurationSet>
    </component>
  </settings>

  <!-- ============================================================ -->
  <!-- PASS 4: specialize                                           -->
  <!-- ============================================================ -->
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="PROC_ARCH_PLACEHOLDER"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <ComputerName>WIN_HOSTNAME_PLACEHOLDER</ComputerName>
      <TimeZone>Romance Standard Time</TimeZone>
      <RegisteredOwner>WIN_USER_PLACEHOLDER</RegisteredOwner>
      <RegisteredOrganization>Enterprise Architecture</RegisteredOrganization>
    </component>

    <component name="Microsoft-Windows-Security-SPP-UX"
               processorArchitecture="PROC_ARCH_PLACEHOLDER"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <SkipAutoActivation>true</SkipAutoActivation>
    </component>
  </settings>

  <!-- ============================================================ -->
  <!-- PASS 7: oobeSystem — User account & OOBE skip               -->
  <!-- ============================================================ -->
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="PROC_ARCH_PLACEHOLDER"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>

    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="PROC_ARCH_PLACEHOLDER"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">

      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
        <SkipUserOOBE>true</SkipUserOOBE>
        <SkipMachineOOBE>true</SkipMachineOOBE>
      </OOBE>

      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>WIN_USER_PLACEHOLDER</Name>
            <Group>Administrators</Group>
            <Password>
              <Value>WIN_PASS_PLACEHOLDER</Value>
              <PlainText>true</PlainText>
            </Password>
            <DisplayName>WIN_USER_PLACEHOLDER</DisplayName>
            <Description>EA Architect Account</Description>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>

      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>WIN_USER_PLACEHOLDER</Username>
        <Password>
          <Value>WIN_PASS_PLACEHOLDER</Value>
          <PlainText>true</PlainText>
        </Password>
        <LogonCount>3</LogonCount>
      </AutoLogon>

      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>cmd.exe /c powershell -ExecutionPolicy Bypass -File C:\setup-scripts\01-install-vmtools.ps1</CommandLine>
          <Description>Install VMware Tools</Description>
          <RequiresUserInput>false</RequiresUserInput>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <CommandLine>cmd.exe /c powershell -ExecutionPolicy Bypass -File C:\setup-scripts\02-install-sparx-ea.ps1</CommandLine>
          <Description>Install Sparx EA</Description>
          <RequiresUserInput>false</RequiresUserInput>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>3</Order>
          <CommandLine>cmd.exe /c powershell -ExecutionPolicy Bypass -File C:\setup-scripts\03-configure-ea-mcp.ps1</CommandLine>
          <Description>Configure EA MCP Server</Description>
          <RequiresUserInput>false</RequiresUserInput>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
XMLEOF

sed -i.bak "s/PROC_ARCH_PLACEHOLDER/$PROC_ARCH/g" "$SCRIPT_DIR/shared/autounattend.xml"
sed -i.bak "s/WIN_USER_PLACEHOLDER/$WIN_USER/g" "$SCRIPT_DIR/shared/autounattend.xml"
sed -i.bak "s/WIN_PASS_PLACEHOLDER/$WIN_PASS/g" "$SCRIPT_DIR/shared/autounattend.xml"
sed -i.bak "s/WIN_HOSTNAME_PLACEHOLDER/$WIN_HOSTNAME/g" "$SCRIPT_DIR/shared/autounattend.xml"
rm -f "$SCRIPT_DIR/shared/autounattend.xml.bak"

log "✅ autounattend.xml generated"

#===============================================================================
# STEP 6: Create the autounattend ISO
#===============================================================================
log "=== Step 6: Creating autounattend ISO ==="

AUTOUNATTEND_DIR="$SCRIPT_DIR/shared/autounattend-iso-content"
mkdir -p "$AUTOUNATTEND_DIR/\$OEM\$/\$\$/Setup/Scripts"
cp "$SCRIPT_DIR/shared/autounattend.xml" "$AUTOUNATTEND_DIR/autounattend.xml"
mkdir -p "$AUTOUNATTEND_DIR/\$OEM\$/\$1/setup-scripts"

# ---------------------------------------------------------------------------
# 01-install-vmtools.ps1
# ---------------------------------------------------------------------------
cat > "$AUTOUNATTEND_DIR/\$OEM\$/\$1/setup-scripts/01-install-vmtools.ps1" << 'PS1EOF'
#===============================================================================
# 01-install-vmtools.ps1
# Installs VMware Tools from the mounted CD/DVD drive
#===============================================================================
$ErrorActionPreference = "Stop"
$logFile = "C:\setup-scripts\vmtools-install.log"
function Log($msg) { $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; "$ts - $msg" | Tee-Object -FilePath $logFile -Append }

Log "=== VMware Tools Installation ==="

$vmToolsSetup = $null
foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[D-Z]:\\$' })) {
    $p64 = Join-Path $drive.Root "setup64.exe"
    $p32 = Join-Path $drive.Root "setup.exe"
    if (Test-Path $p64) { $vmToolsSetup = $p64; break }
    elseif (Test-Path $p32) { $vmToolsSetup = $p32; break }
}

if ($vmToolsSetup) {
    Log "Found VMware Tools at: $vmToolsSetup"
    $proc = Start-Process -FilePath $vmToolsSetup -ArgumentList "/S /v/qn REBOOT=R" -Wait -PassThru
    Log "VMware Tools exit code: $($proc.ExitCode)"
} else {
    Log "VMware Tools not found. Use Virtual Machine menu > Install VMware Tools."
}
Log "=== VMware Tools installation complete ==="
PS1EOF

# ---------------------------------------------------------------------------
# 02-install-sparx-ea.ps1
#
# Detects which MSI was placed in the shared folder (licensed > trial > lite)
# and installs silently.  Writes EA_EDITION=lite|full to
# C:\setup-scripts\ea-edition.txt so that 03-configure-ea-mcp.ps1 can decide
# whether to attempt the MCP3 COM bridge setup.
# ---------------------------------------------------------------------------
cat > "$AUTOUNATTEND_DIR/\$OEM\$/\$1/setup-scripts/02-install-sparx-ea.ps1" << 'PS1EOF'
#===============================================================================
# 02-install-sparx-ea.ps1
# Silent install of Sparx Enterprise Architect (licensed / trial / lite)
#===============================================================================
$ErrorActionPreference = "SilentlyContinue"
$logFile = "C:\setup-scripts\ea-install.log"
function Log($msg) { $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; "$ts - $msg" | Tee-Object -FilePath $logFile -Append }

Log "=== Sparx EA Installation ==="

# Wait for VMware shared folder to become available
Log "Waiting for shared folder (Z:\)..."
$waited = 0
while (-not (Test-Path "Z:\installers") -and $waited -lt 120) {
    Start-Sleep -Seconds 5; $waited += 5
    net use Z: "\\vmware-host\Shared Folders\MacShare" 2>$null
}

# Priority order: licensed > trial > lite
# EA Lite is a permanently free, read-only viewer — no COM automation API.
# MCP3.exe (Sparx EA Bridge) requires a full edition (trial or licensed).
$candidates = [ordered]@{
    "full"    = @(
        "Z:\installers\easetupfull.msi",
        "C:\setup-scripts\easetupfull.msi"
    )
    "full"    = @(
        "Z:\installers\easetup.msi",
        "C:\setup-scripts\easetup.msi",
        "C:\Users\Public\Downloads\easetup.msi"
    )
    "lite"    = @(
        "Z:\installers\ealite_x64.msi",
        "C:\setup-scripts\ealite_x64.msi",
        "C:\Users\Public\Downloads\ealite_x64.msi"
    )
}

$eaMsi    = $null
$eaEdition = "unknown"

foreach ($edition in $candidates.Keys) {
    foreach ($path in $candidates[$edition]) {
        if (Test-Path $path) {
            $eaMsi     = $path
            $eaEdition = $edition
            Log "Found $edition MSI at: $eaMsi"
            break
        }
    }
    if ($eaMsi) { break }
}

if (-not $eaMsi) {
    Log "No EA MSI found. Searched:"
    foreach ($edition in $candidates.Keys) {
        foreach ($path in $candidates[$edition]) { Log "  - $path" }
    }
    Log "Run 01-setup-vmware-fusion.sh on the Mac to download an MSI, then re-run this script."
    exit 0
}

# Silent install
Log "Installing $eaEdition edition silently..."
$proc = Start-Process msiexec.exe -ArgumentList (
    "/i `"$eaMsi`" /qn /norestart ACCEPT=YES " +
    "COMPANYNAME=`"Enterprise Architecture`" USERNAME=`"Architect`" " +
    "/l*v `"C:\setup-scripts\ea-msi-install.log`""
) -Wait -PassThru
Log "msiexec exit code: $($proc.ExitCode)"

# Verify
$eaExe = @(
    "C:\Program Files (x86)\Sparx Systems\EA\EA.exe",
    "C:\Program Files (x86)\Sparx Systems\EA Trial\EA.exe",
    "C:\Program Files\Sparx Systems\EA\EA.exe",
    "C:\Program Files\Sparx Systems\EA Lite\EA.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($eaExe) {
    Log "✅ EA installed at: $eaExe"
} else {
    Log "⚠️  EA.exe not found after install. Check C:\setup-scripts\ea-msi-install.log"
}

# Write edition marker for 03-configure-ea-mcp.ps1
"EA_EDITION=$eaEdition" | Out-File "C:\setup-scripts\ea-edition.txt" -Encoding ASCII
Log "Edition marker written: EA_EDITION=$eaEdition"

# Deploy license key if provided
$keyFile = "Z:\licenses\key.dat"
if (Test-Path $keyFile) {
    $eaAppData = "$env:APPDATA\Sparx Systems\EA"
    New-Item -ItemType Directory -Path $eaAppData -Force -ErrorAction SilentlyContinue | Out-Null
    Copy-Item $keyFile "$eaAppData\key.dat" -Force
    Log "✅ License key deployed"
}

Log "=== Sparx EA installation complete ==="
PS1EOF

# ---------------------------------------------------------------------------
# 03-configure-ea-mcp.ps1
#
# Reads EA_EDITION from the marker file written by step 02.
# For full editions: configures MCP3.exe COM bridge for Claude Desktop.
# For lite edition:  skips MCP3 setup (no COM API), logs a clear explanation.
# Both: enables RDP and creates a desktop shortcut.
# ---------------------------------------------------------------------------
cat > "$AUTOUNATTEND_DIR/\$OEM\$/\$1/setup-scripts/03-configure-ea-mcp.ps1" << 'PS1EOF'
#===============================================================================
# 03-configure-ea-mcp.ps1
# Configures the Sparx EA MCP server for Claude Desktop (full editions only)
#===============================================================================
$ErrorActionPreference = "SilentlyContinue"
$logFile = "C:\setup-scripts\mcp-setup.log"
function Log($msg) { $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; "$ts - $msg" | Tee-Object -FilePath $logFile -Append }

Log "=== MCP Server Configuration ==="

# Read edition written by 02-install-sparx-ea.ps1
$eaEdition = "full"   # default if marker missing
$markerFile = "C:\setup-scripts\ea-edition.txt"
if (Test-Path $markerFile) {
    $line = Get-Content $markerFile -Raw
    if ($line -match "EA_EDITION=(.+)") { $eaEdition = $Matches[1].Trim() }
}
Log "EA edition: $eaEdition"

# Locate EA install directory (covers full and lite paths)
$eaDir = @(
    "C:\Program Files (x86)\Sparx Systems\EA",
    "C:\Program Files (x86)\Sparx Systems\EA Trial",
    "C:\Program Files\Sparx Systems\EA",
    "C:\Program Files\Sparx Systems\EA Lite"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $eaDir) {
    Log "⚠️  No EA installation found. Skipping MCP setup."
    exit 0
}
Log "EA directory: $eaDir"

# Enable RDP and file sharing regardless of edition
Log "Enabling Remote Desktop..."
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
    -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue
Log "✅ Remote Desktop enabled"

if ($eaEdition -eq "lite") {
    # EA Lite has no COM automation API — MCP3.exe will not work.
    # The SQLite Analyzer MCP server on macOS reads .qea files directly
    # and is fully functional regardless of this VM's EA edition.
    Log ""
    Log "╔══════════════════════════════════════════════════════════════════╗"
    Log "║  EA Lite (Viewer) detected — MCP3 COM bridge not available     ║"
    Log "║                                                                ║"
    Log "║  EA Lite is a read-only viewer with no COM automation API.     ║"
    Log "║  The Sparx EA Bridge MCP server (MCP3.exe) requires a full     ║"
    Log "║  edition (trial or licensed) to function.                      ║"
    Log "║                                                                ║"
    Log "║  What still works:                                             ║"
    Log "║  ✅ EA Lite — browse and view any .qea model in Windows        ║"
    Log "║  ✅ SQLite Analyzer MCP (macOS) — read-only Claude queries     ║"
    Log "║                                                                ║"
    Log "║  To enable full read+write MCP access, re-run setup with:     ║"
    Log "║    EA_EDITION=trial  in your .env on the Mac host              ║"
    Log "╚══════════════════════════════════════════════════════════════════╝"

    # Create a desktop note explaining the limitation
    $noteContent = @"
EA Lite is installed (read-only viewer).

The MCP3.exe COM bridge is NOT available with EA Lite.
To enable full Claude MCP write access, reinstall with the trial or licensed edition.

The SQLite Analyzer MCP server on your Mac (no VM needed) is fully functional
and supports all read-only Claude queries against any .qea model file.

Download the EA trial: https://sparxsystems.com/products/ea/trial/request.html
"@
    $noteContent | Out-File "C:\Users\Public\Desktop\EA-Lite-MCP-Note.txt" -Encoding UTF8
    Log "✅ Limitation note written to desktop"
    exit 0
}

# ---- Full edition (trial or licensed) ----

$mcpDir = "$eaDir\MCP_Server"
if (Test-Path "$mcpDir\MCP3.exe") {
    Log "✅ MCP3.exe bundled with EA at: $mcpDir"
} else {
    Log "MCP3.exe not bundled with this EA version."
    Log "Download from: https://www.sparxsystems.jp/en/MCP/"
    Log "Extract to: $eaDir\MCP_Server\"
}

# Build Claude Desktop config using ConvertTo-Json (avoids backslash escaping bugs)
$claudeConfigDir = "$env:APPDATA\Claude"
New-Item -ItemType Directory -Path $claudeConfigDir -Force -ErrorAction SilentlyContinue | Out-Null

$configObj = @{
    mcpServers = @{
        "Enterprise Architect" = @{
            command = "$mcpDir\MCP3.exe"
            # -enableEdit grants write access to the model.
            # Remove this argument for read-only MCP access.
            args = @("-enableEdit")
        }
    }
}

$configFile = "$claudeConfigDir\claude_desktop_config.json"
if (Test-Path $configFile) {
    Copy-Item $configFile "$configFile.bak" -Force
    Log "Existing config backed up to: $configFile.bak"
}

$configObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $configFile -Encoding UTF8
Log "✅ Claude Desktop MCP config written: $configFile"

# Desktop launcher
@"
@echo off
echo Starting Enterprise Architect with MCP Server...
start "" "$eaDir\EA.exe"
echo EA launched. MCP Server connects automatically via Claude Desktop.
pause
"@ | Out-File "C:\Users\Public\Desktop\Launch-EA-MCP.bat" -Encoding ASCII
Log "✅ Desktop launcher created"

Log ""
Log "╔══════════════════════════════════════════════════════════════════╗"
Log "║  ✅ Setup complete ($eaEdition edition)                        ║"
Log "║                                                                ║"
Log "║  EA directory : $eaDir"
Log "║  MCP config   : $configFile"
Log "║  RDP          : enabled"
Log "║                                                                ║"
Log "║  To use with Claude:                                           ║"
Log "║  1. Launch EA via the desktop shortcut and open a model        ║"
Log "║  2. Open Claude Desktop on Windows                             ║"
Log "║  3. The MCP server connects automatically                      ║"
Log "║                                                                ║"
Log "║  Models in Z:\models\ are accessible from both Mac and VM      ║"
Log "╚══════════════════════════════════════════════════════════════════╝"
Log "=== MCP configuration complete ==="
PS1EOF

#===============================================================================
# Build autounattend ISO
#===============================================================================
AUTOUNATTEND_ISO="$SCRIPT_DIR/iso/autounattend.iso"

if command -v hdiutil &>/dev/null; then
    hdiutil makehybrid -o "$AUTOUNATTEND_ISO" \
        "$AUTOUNATTEND_DIR" -iso -joliet \
        -default-volume-name "OEMDRV" 2>/dev/null || {
        if command -v mkisofs &>/dev/null; then
            mkisofs -o "$AUTOUNATTEND_ISO" -V "OEMDRV" -J -r "$AUTOUNATTEND_DIR"
        else
            log "⚠️  Could not create ISO. Install cdrtools: brew install cdrtools"
        fi
    }

    if [ -f "$AUTOUNATTEND_ISO" ]; then
        log "✅ Autounattend ISO: $AUTOUNATTEND_ISO"
        sed -i.bak "s|sata0:1.fileName = \"\"|sata0:1.fileName = \"$AUTOUNATTEND_ISO\"|" "$VMX_FILE"
        rm -f "$VMX_FILE.bak"
    else
        log "❌ Autounattend ISO creation failed — Windows setup will run interactively."
        exit 1
    fi
else
    log "⚠️  hdiutil not available. ISO creation skipped."
fi

# Patch the tiny11 ISO path if it was downloaded by script 01
TINY11_ISO=$(ls "$SCRIPT_DIR/iso/tiny11_"*.iso 2>/dev/null | head -1 || true)
if [ -n "$TINY11_ISO" ]; then
    sed -i.bak "s|sata0:0.fileName = \"\"|sata0:0.fileName = \"$TINY11_ISO\"|" "$VMX_FILE"
    rm -f "$VMX_FILE.bak"
    log "✅ VMX patched with ISO: $TINY11_ISO"
else
    log "⚠️  No tiny11 ISO found in ./iso/. Edit sata0:0.fileName in the VMX manually."
fi

#===============================================================================
# STEP 7: Print instructions
#===============================================================================
log ""
log "╔══════════════════════════════════════════════════════════════════╗"
log "║  VM CREATED: $VM_NAME                                         ║"
log "╠══════════════════════════════════════════════════════════════════╣"
log "║  VMX    : $VMX_FILE"
log "║  Disk   : ${VM_DISK_GB} GB | RAM: $((VM_RAM_MB/1024)) GB | CPUs: $VM_CPUS"
log "║  User   : $WIN_USER / $WIN_PASS"
log "╠══════════════════════════════════════════════════════════════════╣"
log "║  1. Start the VM:                                              ║"
log "║     vmrun start \"$VMX_FILE\"                                  ║"
log "║  2. Windows installs unattended (~10–20 min)                   ║"
log "║  3. Run: ./03-post-install.sh                                  ║"
log "╚══════════════════════════════════════════════════════════════════╝"
log ""
log "=== VM creation complete ==="
