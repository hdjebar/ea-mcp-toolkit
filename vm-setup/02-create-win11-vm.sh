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

# CD/DVD - Windows ISO (update path after download)
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.fileName = ""
sata0:0.deviceType = "cdrom-image"
sata0:0.startConnected = "TRUE"

# Second CD/DVD - for autounattend ISO
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
vtpm.present = "TRUE"
managedvm.autoAddVTPM = "software"

# Shared folders (for transferring EA installer and files)
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

# Tools auto-install
tools.syncTime = "TRUE"
tools.upgrade.policy = "upgradeAtPowerCycle"

# Encryption for TPM
encryption.keySafe = "vmware:key/list/(pair/(phrase/$VM_NAME/pass2key=PBKDF2-HMAC-SHA-1:cipher=AES-256:rounds=10000))"
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

# Copy EA installer to shared folder if it exists
for msi in "$SCRIPT_DIR/iso/easetupfull.msi" "$SCRIPT_DIR/iso/easetup.msi"; do
    if [ -f "$msi" ]; then
        cp "$msi" "$SCRIPT_DIR/shared/installers/"
        log "✅ Copied EA installer to shared folder"
        break
    fi
done

log "✅ Shared folder structure created at: $SCRIPT_DIR/shared/"

#===============================================================================
# STEP 5: Generate autounattend.xml
#===============================================================================
log "=== Step 5: Generating autounattend.xml ==="

# Determine processor architecture for autounattend
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
            <!-- EFI System Partition -->
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Size>260</Size>
              <Type>EFI</Type>
            </CreatePartition>
            <!-- MSR Partition -->
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Size>16</Size>
              <Type>MSR</Type>
            </CreatePartition>
            <!-- Windows Partition (uses remaining space) -->
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
          <!-- Index 1 = Windows 11 Home, typically use for ARM -->
          <!-- Adjust if your ISO has different indices -->
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
  <!-- PASS 4: specialize — Computer name & network                 -->
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

    <!-- Disable Windows Defender for better VM performance (optional) -->
    <component name="Microsoft-Windows-Security-SPP-UX"
               processorArchitecture="PROC_ARCH_PLACEHOLDER"
               publicKeyToken="31bf3856ad364e35"
               language="neutral" versionScope="nonSxS">
      <SkipAutoActivation>true</SkipAutoActivation>
    </component>
  </settings>

  <!-- ============================================================ -->
  <!-- PASS 7: oobeSystem — User account & OOBE skip                -->
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

      <!-- First logon commands: Install VMware Tools, then EA -->
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

# Replace placeholders with actual values
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

# Create directory structure for the ISO
AUTOUNATTEND_DIR="$SCRIPT_DIR/shared/autounattend-iso-content"
mkdir -p "$AUTOUNATTEND_DIR/\$OEM\$/\$\$/Setup/Scripts"

cp "$SCRIPT_DIR/shared/autounattend.xml" "$AUTOUNATTEND_DIR/autounattend.xml"

# Copy setup scripts to $OEM$ folder (they'll be copied to C:\Windows\Setup\Scripts\)
# We'll also create a setup-scripts directory at C:\ root
mkdir -p "$AUTOUNATTEND_DIR/\$OEM\$/\$1/setup-scripts"

# Generate the PowerShell scripts
cat > "$AUTOUNATTEND_DIR/\$OEM\$/\$1/setup-scripts/01-install-vmtools.ps1" << 'PS1EOF'
#===============================================================================
# 01-install-vmtools.ps1
# Installs VMware Tools from the mounted CD/DVD drive
#===============================================================================
$ErrorActionPreference = "SilentlyContinue"
$logFile = "C:\setup-scripts\vmtools-install.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $msg" | Tee-Object -FilePath $logFile -Append
}

Log "=== VMware Tools Installation ==="

# Find VMware Tools installer on CD/DVD drives
$vmToolsSetup = $null
foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[D-Z]:\\$' })) {
    $setupPath = Join-Path $drive.Root "setup64.exe"
    $setupPath32 = Join-Path $drive.Root "setup.exe"
    if (Test-Path $setupPath) {
        $vmToolsSetup = $setupPath
        break
    } elseif (Test-Path $setupPath32) {
        $vmToolsSetup = $setupPath32
        break
    }
}

if ($vmToolsSetup) {
    Log "Found VMware Tools at: $vmToolsSetup"
    Log "Starting silent installation..."
    $proc = Start-Process -FilePath $vmToolsSetup -ArgumentList "/S /v/qn REBOOT=R" -Wait -PassThru
    Log "VMware Tools install exit code: $($proc.ExitCode)"
} else {
    Log "VMware Tools not found on any drive. Will need manual installation."
    Log "Go to: Virtual Machine menu > Install VMware Tools"
}

Log "=== VMware Tools installation complete ==="
PS1EOF

cat > "$AUTOUNATTEND_DIR/\$OEM\$/\$1/setup-scripts/02-install-sparx-ea.ps1" << 'PS1EOF'
#===============================================================================
# 02-install-sparx-ea.ps1
# Silent install of Sparx Enterprise Architect
# Looks for MSI in shared folder (Z:\) or C:\setup-scripts\
#===============================================================================
$ErrorActionPreference = "SilentlyContinue"
$logFile = "C:\setup-scripts\ea-install.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $msg" | Tee-Object -FilePath $logFile -Append
}

Log "=== Sparx EA Installation ==="

# Wait for network (VMware shared folders need VMware Tools + network)
Log "Waiting for shared folder access..."
$maxWait = 120  # seconds
$waited = 0
while (-not (Test-Path "Z:\installers") -and $waited -lt $maxWait) {
    Start-Sleep -Seconds 5
    $waited += 5
    # Try to map the shared folder
    net use Z: "\\vmware-host\Shared Folders\MacShare" 2>$null
}

# Search for EA installer in multiple locations
$searchPaths = @(
    "Z:\installers\easetupfull.msi",
    "Z:\installers\easetup.msi",
    "C:\setup-scripts\easetupfull.msi",
    "C:\setup-scripts\easetup.msi",
    "C:\Users\Public\Downloads\easetupfull.msi",
    "C:\Users\Public\Downloads\easetup.msi"
)

$eaMsi = $null
foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        $eaMsi = $path
        Log "Found EA installer at: $eaMsi"
        break
    }
}

if (-not $eaMsi) {
    Log "⚠️ EA installer not found. Searched locations:"
    foreach ($path in $searchPaths) {
        Log "  - $path"
    }
    Log ""
    Log "Manual install required. Download from:"
    Log "  https://sparxsystems.com/products/ea/downloads.html"
    Log ""
    Log "Then run: msiexec /i <path-to-msi> /qn /norestart"
    exit 0
}

# Run silent install
Log "Starting silent EA installation..."
$msiArgs = @(
    "/i"
    "`"$eaMsi`""
    "/qn"              # Quiet, no UI
    "/norestart"       # Don't auto-reboot
    "ACCEPT=YES"       # Accept EULA
    "COMPANYNAME=`"Enterprise Architecture`""
    "USERNAME=`"Architect`""
    "/l*v `"C:\setup-scripts\ea-msi-install.log`""  # Verbose log
)

$proc = Start-Process -FilePath "msiexec.exe" -ArgumentList ($msiArgs -join " ") -Wait -PassThru
Log "EA install exit code: $($proc.ExitCode)"

# Verify installation
$eaExe = "C:\Program Files (x86)\Sparx Systems\EA\EA.exe"
$eaExe64 = "C:\Program Files\Sparx Systems\EA\EA.exe"

if (Test-Path $eaExe) {
    Log "✅ EA installed successfully at: $eaExe"
} elseif (Test-Path $eaExe64) {
    Log "✅ EA installed successfully at: $eaExe64"
} else {
    Log "⚠️ EA executable not found after installation. Check MSI log."
}

# Copy license key if provided
$keyFile = "Z:\licenses\key.dat"
if (Test-Path $keyFile) {
    $eaAppData = "$env:APPDATA\Sparx Systems\EA"
    if (-not (Test-Path $eaAppData)) {
        New-Item -ItemType Directory -Path $eaAppData -Force
    }
    Copy-Item $keyFile "$eaAppData\key.dat" -Force
    Log "✅ License key deployed"
}

Log "=== Sparx EA installation complete ==="
PS1EOF

cat > "$AUTOUNATTEND_DIR/\$OEM\$/\$1/setup-scripts/03-configure-ea-mcp.ps1" << 'PS1EOF'
#===============================================================================
# 03-configure-ea-mcp.ps1
# Downloads and configures the Sparx Japan MCP Server for Claude integration
#===============================================================================
$ErrorActionPreference = "SilentlyContinue"
$logFile = "C:\setup-scripts\mcp-setup.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $msg" | Tee-Object -FilePath $logFile -Append
}

Log "=== MCP Server Configuration ==="

# Check if EA is installed
$eaDir = $null
foreach ($dir in @(
    "C:\Program Files (x86)\Sparx Systems\EA",
    "C:\Program Files\Sparx Systems\EA"
)) {
    if (Test-Path $dir) {
        $eaDir = $dir
        break
    }
}

if (-not $eaDir) {
    Log "⚠️ EA not found. Skipping MCP server setup."
    exit 0
}

Log "EA found at: $eaDir"

# Check if MCP server is bundled with EA 17+
$mcpDir = "$eaDir\MCP_Server"
if (Test-Path "$mcpDir\MCP3.exe") {
    Log "✅ MCP Server already bundled with EA"
} else {
    Log "MCP Server not bundled. Download from:"
    Log "  https://www.sparxsystems.jp/en/MCP/"
    Log ""
    Log "After downloading, extract to: $eaDir\MCP_Server\"
    
    # Try downloading from Sparx Japan
    $mcpUrl = "https://www.sparxsystems.jp/en/MCP/"
    Log "Opening MCP download page..."
    # Note: actual download link may require manual action
}

# Create Claude Desktop configuration
$claudeConfigDir = "$env:APPDATA\Claude"
if (-not (Test-Path $claudeConfigDir)) {
    New-Item -ItemType Directory -Path $claudeConfigDir -Force
}

$mcpExePath = "$mcpDir\MCP3.exe" -replace '\\', '\\\\'

$claudeConfig = @"
{
  "mcpServers": {
    "Enterprise Architect": {
      "command": "$mcpExePath",
      "args": ["-enableEdit"]
    }
  }
}
"@

$configFile = "$claudeConfigDir\claude_desktop_config.json"

if (Test-Path $configFile) {
    Log "Claude Desktop config already exists. Backing up..."
    Copy-Item $configFile "$configFile.bak" -Force
}

$claudeConfig | Out-File -FilePath $configFile -Encoding UTF8
Log "✅ Claude Desktop MCP config created at: $configFile"

# Create a convenience batch file to launch EA with MCP
$batchContent = @"
@echo off
echo Starting Enterprise Architect with MCP Server...
echo.
echo MCP Server will be available for Claude Desktop, VS Code, etc.
echo.
start "" "$eaDir\EA.exe"
echo.
echo EA launched. MCP Server is active when connected via Claude Desktop.
pause
"@

$batchContent | Out-File -FilePath "C:\Users\Public\Desktop\Launch-EA-MCP.bat" -Encoding ASCII
Log "✅ Desktop shortcut created"

# Enable Windows Remote Desktop (optional, for accessing from Mac)
Log "Enabling Remote Desktop..."
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" 2>$null
Log "✅ Remote Desktop enabled"

# Configure Windows Firewall for shared folder access
Log "Configuring firewall..."
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" 2>$null
Log "✅ File sharing firewall rules enabled"

# Summary
Log ""
Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  Setup Complete!                                            ║"
Log "║                                                             ║"
Log "║  Enterprise Architect: $eaDir"
Log "║  MCP Config: $configFile"
Log "║  Remote Desktop: Enabled                                    ║"
Log "║                                                             ║"
Log "║  To use with Claude:                                        ║"
Log "║  1. Launch EA and open a model                              ║"
Log "║  2. Open Claude Desktop (or VS Code with Copilot Chat)      ║"
Log "║  3. The MCP server connects automatically                   ║"
Log "║                                                             ║"
Log "║  Shared folder: Z:\  (mapped to Mac ~/setup-ea-vm/shared)  ║"
Log "║  Place .qea models in Z:\models\ for easy access            ║"
Log "╚══════════════════════════════════════════════════════════════╝"

Log "=== MCP Server configuration complete ==="
PS1EOF

# Build ISO from the autounattend directory
AUTOUNATTEND_ISO="$SCRIPT_DIR/iso/autounattend.iso"

if command -v hdiutil &>/dev/null; then
    # macOS: use hdiutil to create ISO
    hdiutil makehybrid -o "$AUTOUNATTEND_ISO" \
        "$AUTOUNATTEND_DIR" \
        -iso -joliet \
        -default-volume-name "OEMDRV" 2>/dev/null || {
        # Fallback: try mkisofs if available
        if command -v mkisofs &>/dev/null; then
            mkisofs -o "$AUTOUNATTEND_ISO" \
                -V "OEMDRV" -J -r \
                "$AUTOUNATTEND_DIR"
        else
            log "⚠️  Could not create ISO. Install cdrtools: brew install cdrtools"
            log "    Or manually mount the autounattend folder contents."
        fi
    }
    
    if [ -f "$AUTOUNATTEND_ISO" ]; then
        log "✅ Autounattend ISO created: $AUTOUNATTEND_ISO"
        # Update VMX to point to the autounattend ISO
        sed -i.bak "s|sata0:1.fileName = \"\"|sata0:1.fileName = \"$AUTOUNATTEND_ISO\"|" "$VMX_FILE"
        rm -f "$VMX_FILE.bak"
    fi
else
    log "⚠️  hdiutil not available. ISO creation skipped."
fi

#===============================================================================
# STEP 7: Print instructions
#===============================================================================
log ""
log "╔══════════════════════════════════════════════════════════════════╗"
log "║  VM CREATED: $VM_NAME                                         ║"
log "╠══════════════════════════════════════════════════════════════════╣"
log "║                                                                ║"
log "║  VMX file: $VMX_FILE"
log "║  Disk: ${VM_DISK_GB}GB | RAM: $((VM_RAM_MB/1024))GB | CPUs: $VM_CPUS"
log "║  User: $WIN_USER / $WIN_PASS"
log "║                                                                ║"
log "║  NEXT STEPS:                                                   ║"
log "║                                                                ║"
log "║  1. Set the Windows ISO path in the VMX file:                  ║"
log "║     Edit: sata0:0.fileName = \"<path-to-Win11.iso>\"          ║"
log "║                                                                ║"
log "║  2. OR use Fusion's built-in Windows download:                 ║"
log "║     Open VMware Fusion > File > New > Get Windows              ║"
log "║                                                                ║"
log "║  3. Start the VM:                                              ║"
log "║     vmrun start \"$VMX_FILE\"                                  ║"
log "║                                                                ║"
log "║  4. After Windows installs, run 03-post-install.sh             ║"
log "║                                                                ║"
log "║  Windows will auto-configure with:                             ║"
log "║  - Local account (no Microsoft account required)               ║"
log "║  - VMware Tools installation                                   ║"
log "║  - Sparx EA silent installation                                ║"
log "║  - MCP Server configuration for Claude                         ║"
log "║  - Remote Desktop enabled                                      ║"
log "╚══════════════════════════════════════════════════════════════════╝"

log ""
log "=== VM creation complete. Run ./03-post-install.sh after Windows boots ==="
