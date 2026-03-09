[CmdletBinding()]
param(
    [string]$VmRoot = "D:\VMware",
    [string]$VmName = "wallix-control",
    [int]$DiskSizeGb = 40,
    [int]$Cpu = 2,
    [int]$MemoryMb = 4096,
    [string]$UbuntuSeries = "22.04",
    [string]$UbuntuIsoDir = "",
    [string]$UbuntuIsoPath = "",
    [string]$ShareHostPath = "",
    [string]$ShareName = "WallixRepo",
    [switch]$StartVm
)

$ErrorActionPreference = "Stop"
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-Step([string]$Message) {
    Write-Host "==> $Message"
}

function Get-VMwareToolPath([string]$ExeName) {
    $candidates = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\$ExeName",
        "C:\Program Files\VMware\VMware Workstation\$ExeName"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw "VMware Workstation tool not found: $ExeName (checked standard install paths)."
}

function Resolve-UbuntuIsoUrl([string]$Series) {
    $indexUrl = "https://releases.ubuntu.com/$Series/"
    Write-Step "Discovering latest Ubuntu Server ISO from $indexUrl"

    $html = (Invoke-WebRequest -UseBasicParsing -Uri $indexUrl -TimeoutSec 60).Content
    $pattern = "ubuntu-(\d{2})\.(\d{2})(?:\.(\d+))?-live-server-amd64\.iso"
    $matches = [regex]::Matches($html, $pattern)
    if ($matches.Count -eq 0) {
        throw "Cannot find any live-server-amd64 ISO on $indexUrl"
    }

    $items = foreach ($match in $matches) {
        $major = [int]$match.Groups[1].Value
        $minor = [int]$match.Groups[2].Value
        $patch = if ($match.Groups[3].Success) { [int]$match.Groups[3].Value } else { 0 }
        [PSCustomObject]@{
            Major    = $major
            Minor    = $minor
            Patch    = $patch
            FileName = $match.Value
        }
    }

    $best = $items | Sort-Object Major, Minor, Patch -Descending | Select-Object -First 1
    return "$indexUrl$($best.FileName)"
}

function Ensure-FileDownloaded([string]$Url, [string]$DestPath) {
    if (Test-Path -LiteralPath $DestPath) {
        $existing = Get-Item -LiteralPath $DestPath
        if ($existing.Length -gt 104857600) { # > 100MB
            Write-Step "Ubuntu ISO already exists: $DestPath"
            return
        }

        Write-Step "Ubuntu ISO exists but looks incomplete (${($existing.Length)} bytes), re-downloading"
        Remove-Item -LiteralPath $DestPath -Force
    }

    $parent = Split-Path -Parent $DestPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-Step "Downloading Ubuntu ISO (this can take a while)"
    Write-Host "     $Url"
    Write-Host "  -> $DestPath"
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Start-BitsTransfer -Source $Url -Destination $DestPath
    }
    else {
        Invoke-WebRequest -Uri $Url -OutFile $DestPath -TimeoutSec 0
    }
}

function Wait-FileReadable([string]$Path, [int]$TimeoutSec = 120) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read
            )
            $stream.Close()
            return
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    throw "ISO is still locked/unreadable after ${TimeoutSec}s: $Path"
}

if (-not $UbuntuIsoDir) {
    $UbuntuIsoDir = Join-Path $VmRoot "_isos"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot "..")).Path
if (-not $ShareHostPath) {
    $ShareHostPath = $repoRoot
}

$vmDir = Join-Path $VmRoot $VmName
$vmxPath = Join-Path $vmDir "$VmName.vmx"
$vmdkPath = Join-Path $vmDir "$VmName-disk1.vmdk"

$vmrun = Get-VMwareToolPath -ExeName "vmrun.exe"
$vdiskmanager = Get-VMwareToolPath -ExeName "vmware-vdiskmanager.exe"

if (-not (Test-Path -LiteralPath $VmRoot)) {
    throw "VM root does not exist: $VmRoot"
}

if (-not (Test-Path -LiteralPath $vmDir)) {
    Write-Step "Creating VM directory: $vmDir"
    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
}

if (-not $UbuntuIsoPath) {
    $ubuntuIsoUrl = Resolve-UbuntuIsoUrl -Series $UbuntuSeries
    $isoFileName = Split-Path -Leaf $ubuntuIsoUrl
    $UbuntuIsoPath = Join-Path $UbuntuIsoDir $isoFileName
    Ensure-FileDownloaded -Url $ubuntuIsoUrl -DestPath $UbuntuIsoPath
}
else {
    if (-not (Test-Path -LiteralPath $UbuntuIsoPath)) {
        throw "Ubuntu ISO path not found: $UbuntuIsoPath"
    }
    Write-Step "Using provided Ubuntu ISO: $UbuntuIsoPath"
}

if (-not (Test-Path -LiteralPath $vmdkPath)) {
    Write-Step "Creating virtual disk (${DiskSizeGb}GB): $vmdkPath"
    & $vdiskmanager -c -s "${DiskSizeGb}GB" -a lsilogic -t 0 $vmdkPath | Out-Host
}
else {
    Write-Step "Virtual disk already exists: $vmdkPath"
}

if (-not (Test-Path -LiteralPath $vmxPath)) {
    Write-Step "Writing VMX: $vmxPath"

    $shareHostPathEscaped = $ShareHostPath.Replace("\", "\\")
    $vmx = @(
        '.encoding = "UTF-8"'
        'config.version = "8"'
        'virtualHW.version = "19"'
        "displayName = `"$VmName`""
        'guestOS = "ubuntu-64"'
        "nvram = `"$VmName.nvram`""
        ''
        "numvcpus = `"$Cpu`""
        "memsize = `"$MemoryMb`""
        'cpuid.numSMT = "1"'
        ''
        'pciBridge0.present = "TRUE"'
        'pciBridge4.present = "TRUE"'
        'pciBridge4.virtualDev = "pcieRootPort"'
        'pciBridge4.functions = "8"'
        'pciBridge5.present = "TRUE"'
        'pciBridge5.virtualDev = "pcieRootPort"'
        'pciBridge5.functions = "8"'
        'pciBridge6.present = "TRUE"'
        'pciBridge6.virtualDev = "pcieRootPort"'
        'pciBridge6.functions = "8"'
        'pciBridge7.present = "TRUE"'
        'pciBridge7.virtualDev = "pcieRootPort"'
        'pciBridge7.functions = "8"'
        ''
        'scsi0.present = "TRUE"'
        'scsi0.virtualDev = "lsilogic"'
        'scsi0:0.present = "TRUE"'
        'scsi0:0.deviceType = "disk"'
        "scsi0:0.fileName = `"$([IO.Path]::GetFileName($vmdkPath))`""
        'scsi0:0.mode = "persistent"'
        ''
        'sata0.present = "TRUE"'
        'sata0:1.present = "TRUE"'
        'sata0:1.deviceType = "cdrom-image"'
        "sata0:1.fileName = `"$UbuntuIsoPath`""
        'sata0:1.startConnected = "TRUE"'
        ''
        'ethernet0.present = "TRUE"'
        'ethernet0.virtualDev = "vmxnet3"'
        'ethernet0.connectionType = "nat"'
        'ethernet0.addressType = "generated"'
        'ethernet0.startConnected = "TRUE"'
        ''
        'ethernet1.present = "TRUE"'
        'ethernet1.virtualDev = "vmxnet3"'
        'ethernet1.connectionType = "bridged"'
        'ethernet1.addressType = "generated"'
        'ethernet1.startConnected = "TRUE"'
        ''
        'usb.present = "TRUE"'
        'mks.enable3d = "true"'
        'tools.syncTime = "false"'
        ''
        '# Share this repo into the runner VM (requires open-vm-tools in guest)'
        'isolation.tools.hgfs.disable = "FALSE"'
        'sharedFolder0.present = "TRUE"'
        'sharedFolder0.enabled = "TRUE"'
        'sharedFolder0.readAccess = "TRUE"'
        'sharedFolder0.writeAccess = "TRUE"'
        "sharedFolder0.hostPath = `"$shareHostPathEscaped`""
        "sharedFolder0.guestName = `"$ShareName`""
        ''
        '# Runner VM does not need nested virtualization'
        'vhv.enable = "FALSE"'
    )

    Set-Content -LiteralPath $vmxPath -Value ($vmx -join "`r`n") -Encoding UTF8
}
else {
    Write-Step "VMX already exists: $vmxPath"
}

Write-Step "Runner VM created"
Write-Host "VMX: $vmxPath"

if ($StartVm) {
    Write-Step "Waiting for Ubuntu ISO to be readable (avoid transient lock right after download)"
    Wait-FileReadable -Path $UbuntuIsoPath -TimeoutSec 180

    Write-Step "Starting VM in VMware Workstation"
    & $vmrun -T ws start $vmxPath | Out-Host
    Write-Host ""
    Write-Host "Next (manual, 5 minutes):"
    Write-Host "1) In Ubuntu installer, enable 'Install OpenSSH server'."
    Write-Host "2) Create user 'runner' (or any) + remember password."
    Write-Host "3) After first boot: run scripts/runner/bootstrap-runner.sh inside the VM."
    Write-Host "4) Repo should be available under /mnt/hgfs/$ShareName (after bootstrap mounts it)."
}
