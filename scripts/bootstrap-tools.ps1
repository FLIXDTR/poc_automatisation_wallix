[CmdletBinding()]
param(
    [string]$WslDistro = "Ubuntu",
    [switch]$SkipTerraform,
    [switch]$SkipWslSetup,
    [switch]$SkipAnsibleInstall
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Test-CommandAvailable {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Add-ToProcessPathIfMissing {
    param([string]$PathToAdd)
    if (-not (Test-Path -LiteralPath $PathToAdd)) {
        return
    }

    $current = $env:Path -split ';'
    if (-not ($current | Where-Object { $_ -eq $PathToAdd })) {
        $env:Path = "$PathToAdd;$env:Path"
    }
}

function Install-WithWinget {
    param([string]$PackageId)

    if (-not (Test-CommandAvailable -Name "winget")) {
        throw "winget is required to install $PackageId automatically."
    }

    & winget install --id $PackageId -e --accept-package-agreements --accept-source-agreements
}

function Ensure-Terraform {
    if (Test-CommandAvailable -Name "terraform") {
        return
    }

    Write-Step "Installing Terraform with winget"
    Install-WithWinget -PackageId "Hashicorp.Terraform"

    Add-ToProcessPathIfMissing -PathToAdd "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe"

    if (-not (Test-CommandAvailable -Name "terraform")) {
        throw "Terraform installation completed but terraform is still not reachable in PATH."
    }
}

function Ensure-WslCore {
    if (-not (Test-CommandAvailable -Name "wsl")) {
        Write-Step "Installing WSL runtime"
        Install-WithWinget -PackageId "Microsoft.WSL"
    }

    Write-Step "Ensuring WSL optional features are enabled"
    & wsl --install --no-distribution | Out-Host
}

function Get-WslDistributions {
    $output = & wsl --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    return @($output | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Ensure-WslDistro {
    param([string]$Distro)

    $installed = Get-WslDistributions
    if ($installed -contains $Distro) {
        return
    }

    $wingetMap = @{
        "Ubuntu"        = "Canonical.Ubuntu.2404"
        "Ubuntu-24.04"  = "Canonical.Ubuntu.2404"
        "Ubuntu-22.04"  = "Canonical.Ubuntu.2204"
        "Ubuntu-20.04"  = "Canonical.Ubuntu.2004"
    }

    if ($wingetMap.ContainsKey($Distro)) {
        Write-Step "Installing WSL distro $Distro"
        Install-WithWinget -PackageId $wingetMap[$Distro]
        return
    }

    Write-Step "Installing WSL distro $Distro via wsl.exe"
    & wsl --install $Distro | Out-Host
}

function Test-WslDistroReady {
    param([string]$Distro)
    & wsl -d $Distro -- bash -lc "echo ready" | Out-Host
    return $LASTEXITCODE -eq 0
}

function Invoke-WslCommand {
    param(
        [string]$Distro,
        [string]$Command
    )

    & wsl -d $Distro -- bash -lc $Command
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed: $Command"
    }
}

function Ensure-AnsibleInWsl {
    param([string]$Distro)

    Write-Step "Installing/validating Ansible in WSL distro $Distro"
    Invoke-WslCommand -Distro $Distro -Command "if ! command -v ansible-playbook >/dev/null 2>&1; then sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible; fi"
    Invoke-WslCommand -Distro $Distro -Command "ansible-playbook --version"
}

if (-not $SkipTerraform) {
    Ensure-Terraform
    Write-Step "Terraform is available"
    & terraform version | Out-Host
}

if (-not $SkipWslSetup) {
    Ensure-WslCore
    Ensure-WslDistro -Distro $WslDistro

    if (-not (Test-WslDistroReady -Distro $WslDistro)) {
        throw "WSL distro '$WslDistro' is not ready yet. Reboot Windows, ensure virtualization is enabled in BIOS, then rerun."
    }

    if (-not $SkipAnsibleInstall) {
        Ensure-AnsibleInWsl -Distro $WslDistro
    }
}

Write-Step "Tool bootstrap completed."
