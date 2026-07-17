<#
.SYNOPSIS
    Build and run the dogan-webui UI stack on the local Docker daemon.

.DESCRIPTION
    Uses the repo-root Dockerfile, docker-compose.yml, and nginx.conf.
    Builds (or rebuilds) the web image, ensures the Docker network, then starts Compose.
    Parameter defaults are null and resolve at runtime per prepare-for-docker contract.

.EXAMPLE
    .\run-on-docker-local.ps1

.EXAMPLE
    .\run-on-docker-local.ps1 --delete-volume=yes

.EXAMPLE
    .\run-on-docker-local.ps1 --internal-port=30042
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Alias('ssh-string')]
    [string]$SshString,
    [Alias('delete-image')]
    [string]$DeleteImage,
    [Alias('delete-volume')]
    [string]$DeleteVolume,
    [Alias('internal-port')]
    [string]$InternalPort,
    [Alias('volume-dir')]
    [string]$VolumeDir,
    [Alias('volume-name')]
    [string]$VolumeName,
    [Alias('network-name')]
    [string]$NetworkName,
    [Alias('api-base-url')]
    [string]$ApiBaseUrl,
    [Alias('h')]
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:ComposeFile = 'docker-compose.yml'
$Script:DefaultApiBaseUrl = 'http://localhost:8080/dogan/api/v1'
$Script:ContainerName = 'dogan-webui'
$Script:SafePortMin = 30000
$Script:SafePortMax = 32767

function Show-Help {
    Write-Host @"
run-on-docker-local.ps1 — deploy $Script:ContainerName on local Docker

USAGE:
  .\run-on-docker-local.ps1 [flags]

FLAGS:
  --ssh-string=<alias>       SSH alias; null → local daemon (default: null)
  --delete-image=<no|yes>    Remove built images during teardown (default: null → no)
  --delete-volume=<no|yes>   Remove volumes before recreate (default: null → no)
  --internal-port=<port>     Host port mapped to the container (default: null → random 30000–32767)
  --volume-dir=<path>        Bind-mount data directory (default: null → <USER-PROFILE-NAME>/docker/<CONTAINER-NAME>)
  --volume-name=<name>       Named Docker volume (default: null → <CONTAINER-NAME>-volume)
  --network-name=<name>      Docker network (default: null → from manifest or <CONTAINER-NAME>-network)
  --api-base-url=<url>       VITE_API_BASE_URL baked at build time (default: null → .env or $Script:DefaultApiBaseUrl)
  --help                     Show this help

EXAMPLES:
  .\run-on-docker-local.ps1
  .\run-on-docker-local.ps1 --delete-volume=yes
  .\run-on-docker-local.ps1 --internal-port=30042

NOTES:
  - Use SSH config alias only; do not include "ssh" in --ssh-string.
  - For local deploy, omit --ssh-string (or leave null). Non-null values are rejected here — use run-on-docker-server.ps1.
  - Null defaults resolve as described in FLAGS.
  - Truthy values for yes/no flags: yes, true, 1, y, on.
  - Default internal port is picked randomly from 30000–32767 if not specified.
"@ -ForegroundColor Cyan
}

function Remove-SurroundingQuotes {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $Value = $Value.Trim()
    if (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or ($Value.StartsWith("'") -and $Value.EndsWith("'"))) {
        return $Value.Substring(1, $Value.Length - 2).Trim()
    }
    return $Value
}

function Normalize-CliParameterValue {
    param([string]$Name, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $Value = Remove-SurroundingQuotes -Value $Value.Trim()
    if ($Value -match '^--?(?<param>[\w-]+)(?:=(?<rest>.*))?$') {
        $paramKey = ($Matches['param'] -replace '-', '_').ToLowerInvariant()
        $nameKey = ($Name -replace '-', '_').ToLowerInvariant()
        if ($paramKey -eq $nameKey) {
            if ($null -ne $Matches['rest'] -and $Matches['rest'] -ne '') {
                return Remove-SurroundingQuotes -Value $Matches['rest']
            }
            return $null
        }
    }
    return $Value
}

function Merge-CliArguments {
    param([hashtable]$BoundParameters, [string[]]$RemainingArguments)

    if ($null -eq $RemainingArguments) { $RemainingArguments = @() }
    else { $RemainingArguments = @($RemainingArguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }

    $merged = @{}
    foreach ($key in $BoundParameters.Keys) {
        $normalizedKey = ([regex]::Replace($key, '([a-z0-9])([A-Z])', '$1_$2')).ToLowerInvariant()
        if ($normalizedKey -in @('remainingarguments', 'help')) { continue }
        if ($null -eq $BoundParameters[$key] -or $BoundParameters[$key] -eq '') { continue }
        $normalizedValue = Normalize-CliParameterValue -Name $normalizedKey -Value ([string]$BoundParameters[$key])
        if ($null -ne $normalizedValue -and $normalizedValue -ne '') {
            $merged[$normalizedKey] = $normalizedValue
        }
    }

    $index = 0
    while ($index -lt $RemainingArguments.Count) {
        $argument = $RemainingArguments[$index]
        if ($argument -match '^--?(?<name>[\w-]+)(?:=(?<value>.*))?$') {
            $normalizedKey = ($Matches['name'] -replace '-', '_').ToLowerInvariant()
            if ($normalizedKey -in @('help', 'h')) {
                $merged['help'] = $true
                $index++
                continue
            }
            if ($null -ne $Matches['value'] -and $Matches['value'] -ne '') {
                $merged[$normalizedKey] = Remove-SurroundingQuotes -Value $Matches['value']
                $index++
            }
            elseif (($index + 1) -lt $RemainingArguments.Count -and $RemainingArguments[$index + 1] -notmatch '^-') {
                $merged[$normalizedKey] = Remove-SurroundingQuotes -Value $RemainingArguments[$index + 1]
                $index += 2
            }
            else {
                $merged[$normalizedKey] = $true
                $index++
            }
        }
        elseif ($argument -match '^(-h|-help|--help|-\?|/\?)$') {
            $merged['help'] = $true
            $index++
        }
        else {
            throw "Unknown argument: '$argument'. Run with --help."
        }
    }
    return $merged
}

function Test-Truthy {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    switch ($Value.ToLowerInvariant()) {
        { $_ -in @('yes', 'true', '1', 'y', 'on') } { return $true }
        default { return $false }
    }
}

function Write-RunStep {
    param([int]$Step, [int]$Total, [string]$Message)
    $percent = [math]::Round(($Step / $Total) * 100)
    Write-Progress -Activity 'dogan-webui local Docker' -Status $Message -PercentComplete $percent
    Write-Host ("[{0}/{1}] {2}" -f $Step, $Total, $Message) -ForegroundColor Yellow
}

function Get-StackManifest {
    param([string]$ProjectRoot)
    $manifestPath = Join-Path $ProjectRoot '.docker/stack.manifest.json'
    if (-not (Test-Path $manifestPath)) { return $null }
    return Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
}

function Resolve-ContainerName {
    param([string]$ProjectRoot)
    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.containerName) { return [string]$manifest.containerName }
    if ($manifest -and $manifest.webContainerName) { return [string]$manifest.webContainerName }
    if ($manifest -and $manifest.stackName) { return [string]$manifest.stackName }
    return $Script:ContainerName
}

function Resolve-NetworkName {
    param([string]$ProjectRoot, [string]$Override, [string]$ContainerName)
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }
    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.dockerNetwork) { return [string]$manifest.dockerNetwork }
    return "$ContainerName-network"
}

function Resolve-VolumeDir {
    param([string]$Override, [string]$ContainerName)
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }
    $userProfilePath = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { (Get-Location).Path }
    return (Join-Path $userProfilePath "docker/$ContainerName")
}

function Resolve-VolumeName {
    param([string]$Override, [string]$ContainerName)
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }
    return "$ContainerName-volume"
}

function Test-PortInUse {
    param([int]$Port)
    try {
        $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        return ($null -ne $listeners -and @($listeners).Count -gt 0)
    }
    catch {
        $netstat = & netstat -ano 2>$null | Select-String -Pattern ":$Port\s"
        return ($null -ne $netstat)
    }
}

function Get-RandomFreePort {
    $rng = [System.Random]::new()
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        $candidate = $rng.Next($Script:SafePortMin, $Script:SafePortMax + 1)
        if (-not (Test-PortInUse -Port $candidate)) { return $candidate }
    }
    throw "Could not find a free port in $Script:SafePortMin–$Script:SafePortMax."
}

function Resolve-InternalPort {
    param([string]$Override)
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        if ($Override -notmatch '^\d+$') {
            throw "Invalid --internal-port value '$Override'. Use a numeric port."
        }
        $port = [int]$Override
        if ($port -lt 1 -or $port -gt 65535) {
            throw "Invalid --internal-port value '$Override'. Use a port between 1 and 65535."
        }
        return $port
    }
    return (Get-RandomFreePort)
}

function Resolve-ApiBaseUrl {
    param([string]$ProjectRoot, [string]$OverrideValue)
    if (-not [string]::IsNullOrWhiteSpace($OverrideValue)) {
        return $OverrideValue.Trim().TrimEnd('/')
    }
    $envPath = Join-Path $ProjectRoot '.env'
    if (Test-Path $envPath) {
        foreach ($line in Get-Content -Path $envPath) {
            if ($line -match '^\s*VITE_API_BASE_URL\s*=\s*(.+?)\s*$') {
                $value = Remove-SurroundingQuotes -Value $Matches[1]
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return $value.Trim().TrimEnd('/')
                }
            }
        }
    }
    return $Script:DefaultApiBaseUrl
}

function Test-DockerComposeFile {
    param([string]$ProjectRoot)
    foreach ($relative in @($Script:ComposeFile, 'Dockerfile', 'nginx.conf')) {
        if (-not (Test-Path (Join-Path $ProjectRoot $relative))) {
            throw "Missing $relative in the repo root."
        }
    }
}

function Ensure-DockerNetwork {
    param([string]$NetworkName)
    $existingNetworks = docker network ls --format '{{.Name}}'
    if ($LASTEXITCODE -ne 0) { throw 'Failed to list Docker networks. Is Docker running?' }
    if ($existingNetworks -notcontains $NetworkName) {
        docker network create $NetworkName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to create Docker network '$NetworkName'." }
    }
}

function Ensure-VolumeDir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

try {
    $cliArgs = Merge-CliArguments -BoundParameters $PSBoundParameters -RemainingArguments $RemainingArguments
    if ($Help -or $cliArgs['help'] -or ($RemainingArguments -match '^(--help|-h|/\?)$')) {
        Show-Help
        exit 0
    }

    $ProjectRoot = $PSScriptRoot
    $containerName = Resolve-ContainerName -ProjectRoot $ProjectRoot

    $sshStringValue = if ($cliArgs['ssh_string']) { [string]$cliArgs['ssh_string'] } elseif (-not [string]::IsNullOrWhiteSpace($SshString)) { $SshString } else { $null }
    $sshStringValue = Normalize-CliParameterValue -Name 'ssh_string' -Value $sshStringValue
    if (-not [string]::IsNullOrWhiteSpace($sshStringValue) -and $sshStringValue -notin @('localhost', 'local', '127.0.0.1')) {
        throw "This script is for local Docker only. Use .\run-on-docker-server.ps1 --ssh-string=$sshStringValue"
    }

    $deleteImageRaw = if ($cliArgs.ContainsKey('delete_image')) { [string]$cliArgs['delete_image'] } elseif (-not [string]::IsNullOrWhiteSpace($DeleteImage)) { $DeleteImage } else { $null }
    $deleteVolumeRaw = if ($cliArgs.ContainsKey('delete_volume')) { [string]$cliArgs['delete_volume'] } elseif (-not [string]::IsNullOrWhiteSpace($DeleteVolume)) { $DeleteVolume } else { $null }
    $removeImages = Test-Truthy -Value $deleteImageRaw
    $removeVolumes = Test-Truthy -Value $deleteVolumeRaw

    $portRaw = if ($cliArgs['internal_port']) { [string]$cliArgs['internal_port'] } elseif (-not [string]::IsNullOrWhiteSpace($InternalPort)) { $InternalPort } else { $null }
    $hostPort = Resolve-InternalPort -Override $portRaw

    $volumeDirRaw = if ($cliArgs['volume_dir']) { [string]$cliArgs['volume_dir'] } elseif (-not [string]::IsNullOrWhiteSpace($VolumeDir)) { $VolumeDir } else { $null }
    $volumeNameRaw = if ($cliArgs['volume_name']) { [string]$cliArgs['volume_name'] } elseif (-not [string]::IsNullOrWhiteSpace($VolumeName)) { $VolumeName } else { $null }
    $networkRaw = if ($cliArgs['network_name']) { [string]$cliArgs['network_name'] } elseif (-not [string]::IsNullOrWhiteSpace($NetworkName)) { $NetworkName } else { $null }
    $resolvedVolumeDir = Resolve-VolumeDir -Override $volumeDirRaw -ContainerName $containerName
    $resolvedVolumeName = Resolve-VolumeName -Override $volumeNameRaw -ContainerName $containerName
    $resolvedNetwork = Resolve-NetworkName -ProjectRoot $ProjectRoot -Override $networkRaw -ContainerName $containerName

    $apiOverride = if ($cliArgs['api_base_url']) { [string]$cliArgs['api_base_url'] } elseif (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) { $ApiBaseUrl } else { $null }
    $resolvedApi = Resolve-ApiBaseUrl -ProjectRoot $ProjectRoot -OverrideValue $apiOverride

    $totalSteps = 5
    Write-Host ("Target: localhost | network: {0} | port: {1} | api: {2} | volumes: {3} | images: {4}" -f `
        $resolvedNetwork, $hostPort, $resolvedApi, `
        $(if ($removeVolumes) { 'delete' } else { 'keep' }), `
        $(if ($removeImages) { 'delete' } else { 'keep' })) -ForegroundColor Cyan

    Write-RunStep -Step 1 -Total $totalSteps -Message 'Checking Docker files and CLI'
    Test-DockerComposeFile -ProjectRoot $ProjectRoot
    & docker version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker CLI is not available or not running.' }

    Write-RunStep -Step 2 -Total $totalSteps -Message 'Building web image'
    $createImageScript = Join-Path $ProjectRoot 'create-image.ps1'
    if (Test-Path $createImageScript) {
        & $createImageScript --api-base-url=$resolvedApi
        if ($LASTEXITCODE -ne 0) { throw 'create-image.ps1 failed.' }
    }
    else {
        Push-Location $ProjectRoot
        try {
            $env:VITE_API_BASE_URL = $resolvedApi
            & docker compose -f $Script:ComposeFile build
            if ($LASTEXITCODE -ne 0) { throw "docker compose build failed (exit $LASTEXITCODE)" }
        }
        finally { Pop-Location }
    }

    Write-RunStep -Step 3 -Total $totalSteps -Message "Ensuring network '$resolvedNetwork' and volume dir"
    Ensure-DockerNetwork -NetworkName $resolvedNetwork
    Ensure-VolumeDir -Path $resolvedVolumeDir

    Write-RunStep -Step 4 -Total $totalSteps -Message $(if ($removeVolumes) { 'Recreating stack (volumes removed)' } else { 'Recreating stack (keeping volumes)' })
    Push-Location $ProjectRoot
    try {
        $env:DOCKER_NETWORK = $resolvedNetwork
        $env:VITE_API_BASE_URL = $resolvedApi
        $env:WEB_PUBLISH_PORT = [string]$hostPort
        $env:VOLUME_DIR = $resolvedVolumeDir

        $downFlag = if ($removeVolumes) { ' -v' } else { '' }
        $rmiFlag = if ($removeImages) { ' --rmi local' } else { '' }
        $composeDown = "docker compose -f $Script:ComposeFile down$rmiFlag$downFlag"
        Invoke-Expression $composeDown | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Compose down skipped or partial (stack may not exist yet).' -ForegroundColor DarkYellow
        }

        & docker compose -f $Script:ComposeFile up -d
        if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }
    }
    finally { Pop-Location }

    Write-RunStep -Step 5 -Total $totalSteps -Message 'Done'
    Write-Progress -Activity 'dogan-webui local Docker' -Completed -Status 'Done'
    Write-Host ''
    Write-Host 'Stack is running on localhost.' -ForegroundColor Green
    Write-Host "  Web UI:          http://localhost:$hostPort" -ForegroundColor Green
    Write-Host "  API (build-time): $resolvedApi" -ForegroundColor Green
    Write-Host "  Network:         $resolvedNetwork" -ForegroundColor Green
    Write-Host "  Volume dir:      $resolvedVolumeDir" -ForegroundColor Green
    Write-Host "  Volume name:     $resolvedVolumeName" -ForegroundColor Green
}
catch {
    Write-Progress -Activity 'dogan-webui local Docker' -Completed -Status 'Failed'
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Show-Help
    exit 1
}
