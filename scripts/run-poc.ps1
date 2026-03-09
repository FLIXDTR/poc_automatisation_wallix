[CmdletBinding()]
param(
    [string]$SecretsFile = "",
    [string]$TerraformDir = "",
    [string]$AnsibleDir = "",
    [string]$Mode = "vsphere",
    [string]$LocalBastionHost = "",
    [string]$WslDistro = "Ubuntu",
    [switch]$AutoApprove,
    [switch]$SkipToolBootstrap,
    [switch]$ForceLocalBootstrap
)

$ErrorActionPreference = "Stop"
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$defaultSecretsFile = Join-Path $scriptRoot "..\.secrets.env"
$localSecretsFile = Join-Path $scriptRoot "..\secrets_local.env"

if (-not $SecretsFile) {
    $envSecretsFile = [Environment]::GetEnvironmentVariable("POC_ENV_FILE", "Process")
    if ($envSecretsFile -and $envSecretsFile.Trim()) {
        $SecretsFile = $envSecretsFile.Trim()
    }
    elseif (Test-Path -LiteralPath $localSecretsFile) {
        $SecretsFile = $localSecretsFile
    }
    else {
        $SecretsFile = $defaultSecretsFile
    }
}
if (-not $TerraformDir) {
    $TerraformDir = Join-Path $scriptRoot "..\terraform"
}
if (-not $AnsibleDir) {
    $AnsibleDir = Join-Path $scriptRoot "..\ansible"
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Test-CommandAvailable {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-TerraformCommand {
    $command = Get-Command terraform -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidate = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe\terraform.exe"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    throw "Terraform not found. Run scripts/bootstrap-tools.ps1 first."
}

function Ensure-SecretsFile {
    param(
        [string]$Path,
        [string]$TemplatePath
    )

    if (Test-Path -LiteralPath $Path) {
        return
    }

    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        throw "Missing secrets file ($Path) and template ($TemplatePath)."
    }

    Copy-Item -LiteralPath $TemplatePath -Destination $Path -Force
    throw "Created $Path from template. Update values (required secrets/settings), then rerun."
}

function Resolve-ExecutionMode {
    param([string]$RequestedMode)

    $normalized = $RequestedMode.Trim().ToLower()
    if (-not $normalized) {
        $normalized = "vsphere"
    }

    if ($normalized -notin @("vsphere", "local")) {
        throw "Invalid mode '$RequestedMode'. Allowed values: vsphere, local."
    }

    return $normalized
}

function Try-ExtractHostFromUrl {
    param([string]$Url)

    if (-not $Url) {
        return ""
    }

    try {
        $uri = [System.Uri]$Url
        return $uri.Host
    }
    catch {
        return ""
    }
}

function Resolve-LocalBastionHost {
    param([string]$ProvidedHost)

    if ($ProvidedHost.Trim()) {
        return $ProvidedHost.Trim()
    }

    $fromEnv = [Environment]::GetEnvironmentVariable("LOCAL_BASTION_HOST", "Process")
    if ($fromEnv -and $fromEnv.Trim()) {
        return $fromEnv.Trim()
    }

    $apiUrl = [Environment]::GetEnvironmentVariable("WALLIX_API_URL", "Process")
    $fromUrl = Try-ExtractHostFromUrl -Url $apiUrl
    if ($fromUrl) {
        return $fromUrl
    }

    return ""
}

function Assert-ConfiguredSecrets {
    param(
        [string]$Path,
        [string]$ExecutionMode,
        [string]$ResolvedLocalHost
    )

    $placeholderValues = @(
        "",
        "CHANGE_ME",
        "CHANGE_ME_TOO",
        "CHANGE_ME_2",
        "CHANGE_ME_3",
        "CHANGE_ME_TOO",
        "vcenter.example.local",
        "Datacenter",
        "Cluster",
        "Datastore",
        "VM Network",
        "Resources",
        "local-bastion.example.local"
    )

    $required = @(
        "WALLIX_API_USER",
        "WALLIX_API_PASSWORD",
        "WALLIX_ADMIN_NEW_PASSWORD"
    )

    if ($ExecutionMode -eq "vsphere") {
        $required += @(
            "TF_VAR_vsphere_server",
            "TF_VAR_vsphere_user",
            "TF_VAR_vsphere_password",
            "TF_VAR_datacenter",
            "TF_VAR_cluster",
            "TF_VAR_datastore",
            "TF_VAR_network",
            "TF_VAR_resource_pool",
            "TF_VAR_vm_name"
        )
    }
    elseif (-not $ResolvedLocalHost) {
        $required += "LOCAL_BASTION_HOST"
    }

    $missing = @()
    foreach ($key in $required) {
        $value = [Environment]::GetEnvironmentVariable($key, "Process")
        if ($null -eq $value) {
            $missing += $key
            continue
        }

        if ($placeholderValues -contains $value.Trim()) {
            $missing += $key
        }
    }

    if ($missing.Count -gt 0) {
        $list = ($missing | Sort-Object -Unique) -join ", "
        throw "Unconfigured values in ${Path}: $list"
    }
}

function Test-NativeAnsibleReady {
    if (-not (Test-CommandAvailable -Name "ansible-playbook")) {
        return $false
    }

    if (-not (Test-CommandAvailable -Name "ansible-galaxy")) {
        return $false
    }

    try {
        & ansible-playbook --version *> $null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Escape-BashSingleQuoted {
    param([string]$Value)
    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace("'", "'""'""'")
}

function Invoke-WslBash {
    param(
        [string]$Distro,
        [string]$Command,
        [hashtable]$EnvironmentVars = @{}
    )

    $exports = @()
    foreach ($entry in $EnvironmentVars.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            continue
        }

        $escaped = Escape-BashSingleQuoted -Value ([string]$entry.Value)
        $exports += "export $($entry.Key)='$escaped'"
    }

    $fullCommand = if ($exports.Count -gt 0) {
        ($exports -join "; ") + "; " + $Command
    }
    else {
        $Command
    }

    & wsl -d $Distro -- bash -lc $fullCommand
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed: $fullCommand"
    }
}

function Convert-ToWslPath {
    param([string]$WindowsPath)

    $resolved = (Resolve-Path -LiteralPath $WindowsPath).Path
    $drive = $resolved.Substring(0, 1).ToLower()
    $tail = $resolved.Substring(2).Replace('\', '/')
    return "/mnt/$drive$tail"
}

function Import-DotEnv {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Secrets file not found: $Path (copy .secrets.env.example to .secrets.env)"
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) {
            return
        }

        $parts = $line.Split("=", 2)
        if ($parts.Count -ne 2) {
            return
        }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim("'").Trim('"')
        [Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

if (-not (Test-CommandAvailable -Name "python")) {
    throw "Python 3 is required."
}

$SecretsTemplate = Join-Path $scriptRoot "..\.secrets.env.example"
Ensure-SecretsFile -Path $SecretsFile -TemplatePath $SecretsTemplate
Import-DotEnv -Path $SecretsFile

if (-not $PSBoundParameters.ContainsKey("Mode")) {
    $modeFromEnv = [Environment]::GetEnvironmentVariable("POC_MODE", "Process")
    if ($modeFromEnv) {
        $Mode = $modeFromEnv
    }
}
if (-not $PSBoundParameters.ContainsKey("WslDistro")) {
    $distroFromEnv = [Environment]::GetEnvironmentVariable("WSL_DISTRO", "Process")
    if ($distroFromEnv) {
        $WslDistro = $distroFromEnv
    }
}
if (-not $PSBoundParameters.ContainsKey("LocalBastionHost")) {
    $localHostFromEnv = [Environment]::GetEnvironmentVariable("LOCAL_BASTION_HOST", "Process")
    if ($localHostFromEnv) {
        $LocalBastionHost = $localHostFromEnv
    }
}

$ExecutionMode = Resolve-ExecutionMode -RequestedMode $Mode
$ResolvedLocalHost = Resolve-LocalBastionHost -ProvidedHost $LocalBastionHost

Assert-ConfiguredSecrets -Path $SecretsFile -ExecutionMode $ExecutionMode -ResolvedLocalHost $ResolvedLocalHost

if (-not $SkipToolBootstrap) {
    if ($ExecutionMode -eq "local" -and -not $ForceLocalBootstrap) {
        Write-Step "Local mode: skipping automatic bootstrap to avoid changing host virtualization settings"
    }
    elseif ($ExecutionMode -eq "local" -and $ForceLocalBootstrap) {
        Write-Step "Bootstrapping local tools (forced in local mode)"
        & (Join-Path $scriptRoot "bootstrap-tools.ps1") -WslDistro $WslDistro -SkipTerraform
    }
    else {
        Write-Step "Bootstrapping local tools"
        & (Join-Path $scriptRoot "bootstrap-tools.ps1") -WslDistro $WslDistro
    }
}

$AnsibleDirResolved = (Resolve-Path -LiteralPath $AnsibleDir).Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot "..")).Path
$InventoryPath = Join-Path $AnsibleDirResolved "inventory\generated\hosts.yml"

$ansibleEnv = @{
    WALLIX_VALIDATE_CERTS     = [Environment]::GetEnvironmentVariable("WALLIX_VALIDATE_CERTS", "Process")
    WALLIX_API_URL            = [Environment]::GetEnvironmentVariable("WALLIX_API_URL", "Process")
    WALLIX_API_USER           = [Environment]::GetEnvironmentVariable("WALLIX_API_USER", "Process")
    WALLIX_API_PASSWORD       = [Environment]::GetEnvironmentVariable("WALLIX_API_PASSWORD", "Process")
    WALLIX_ADMIN_NEW_PASSWORD = [Environment]::GetEnvironmentVariable("WALLIX_ADMIN_NEW_PASSWORD", "Process")
}

$BastionUrlForSmoke = ""

if ($ExecutionMode -eq "vsphere") {
    $TerraformCommand = Get-TerraformCommand
    $TerraformDirResolved = (Resolve-Path -LiteralPath $TerraformDir).Path

    Write-Step "Terraform init/validate/plan/apply"
    Push-Location $TerraformDirResolved
    try {
        & $TerraformCommand init
        & $TerraformCommand fmt -check
        & $TerraformCommand validate
        & $TerraformCommand plan -out=tfplan

        if ($AutoApprove) {
            & $TerraformCommand apply -auto-approve tfplan
        }
        else {
            & $TerraformCommand apply tfplan
        }
    }
    finally {
        Pop-Location
    }

    Write-Step "Generate dynamic Ansible inventory from Terraform outputs"
    python (Join-Path $RepoRoot "scripts\generate_inventory.py") `
        --terraform-dir $TerraformDirResolved `
        --output $InventoryPath
}
else {
    Write-Step "Local mode: skip Terraform and use existing Bastion host"

    $apiUrl = [Environment]::GetEnvironmentVariable("WALLIX_API_URL", "Process")
    if (-not $apiUrl) {
        $apiUrl = "https://$ResolvedLocalHost"
    }

    $BastionUrlForSmoke = $apiUrl

    python (Join-Path $RepoRoot "scripts\generate_inventory.py") `
        --output $InventoryPath `
        --bastion-host $ResolvedLocalHost `
        --api-url $apiUrl
}

$useNativeAnsible = Test-NativeAnsibleReady
$useWslAnsible = $false
$useLocalApiFallback = $false
if (-not $useNativeAnsible) {
    $wslReady = $false
    if (Test-CommandAvailable -Name "wsl") {
        & wsl -d $WslDistro -- bash -lc "echo ready" *> $null
        if ($LASTEXITCODE -eq 0) {
            $wslReady = $true
        }
    }

    if ($wslReady) {
        $useWslAnsible = $true
    }
    elseif ($ExecutionMode -eq "local") {
        Write-Step "Ansible/WSL unavailable in local mode, switching to direct API fallback"
        $useLocalApiFallback = $true
    }
    else {
        throw "Ansible is not available and WSL distro '$WslDistro' is not ready. Install Ansible or fix WSL."
    }
}

if ($useNativeAnsible) {
    Write-Step "Using native Ansible runtime"
    Push-Location $AnsibleDirResolved
    try {
        & ansible-galaxy collection install -r requirements.yml

        Write-Step "Run Ansible bootstrap"
        & ansible-playbook -i $InventoryPath playbooks/bootstrap.yml

        Write-Step "Run Ansible configure"
        & ansible-playbook -i $InventoryPath playbooks/configure.yml

        $assetsEnabled = [Environment]::GetEnvironmentVariable("WALLIX_ASSETS_ENABLED", "Process")
        if ($assetsEnabled -and $assetsEnabled.Trim().ToLower() -eq "true") {
            Write-Step "Run Ansible assets (devices/groups/authorizations)"
            & ansible-playbook -i $InventoryPath playbooks/assets.yml
        }
    }
    finally {
        Pop-Location
    }
}
elseif ($useWslAnsible) {
    Write-Step "Using Ansible runtime from WSL distro $WslDistro"
    $ansibleDirWsl = Convert-ToWslPath -WindowsPath $AnsibleDirResolved
    $inventoryWsl = Convert-ToWslPath -WindowsPath $InventoryPath

    Invoke-WslBash -Distro $WslDistro -Command "if ! command -v ansible-playbook >/dev/null 2>&1; then sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible; fi"
    Invoke-WslBash -Distro $WslDistro -Command "cd '$ansibleDirWsl' && ansible-galaxy collection install -r requirements.yml"
    Invoke-WslBash -Distro $WslDistro -EnvironmentVars $ansibleEnv -Command "cd '$ansibleDirWsl' && ansible-playbook -i '$inventoryWsl' playbooks/bootstrap.yml"
    Invoke-WslBash -Distro $WslDistro -EnvironmentVars $ansibleEnv -Command "cd '$ansibleDirWsl' && ansible-playbook -i '$inventoryWsl' playbooks/configure.yml"

    $assetsEnabled = [Environment]::GetEnvironmentVariable("WALLIX_ASSETS_ENABLED", "Process")
    if ($assetsEnabled -and $assetsEnabled.Trim().ToLower() -eq "true") {
        Invoke-WslBash -Distro $WslDistro -EnvironmentVars $ansibleEnv -Command "cd '$ansibleDirWsl' && ansible-playbook -i '$inventoryWsl' playbooks/assets.yml"
    }
}
elseif ($useLocalApiFallback) {
    Write-Step "Using direct local API fallback (no WSL/Ansible)"
    python (Join-Path $RepoRoot "scripts\local_configure_wallix.py") --bastion-url $BastionUrlForSmoke
}

Write-Step "Run smoke tests"
if ($ExecutionMode -eq "vsphere") {
    $TerraformDirResolved = (Resolve-Path -LiteralPath $TerraformDir).Path
    python (Join-Path $RepoRoot "scripts\smoke_test.py") --terraform-dir $TerraformDirResolved
}
else {
    python (Join-Path $RepoRoot "scripts\smoke_test.py") --bastion-url $BastionUrlForSmoke
}

Write-Host "PoC completed successfully."
