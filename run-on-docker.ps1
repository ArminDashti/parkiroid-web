<#
.SYNOPSIS
    Build and run the parkiroid-web UI stack with Docker Compose locally or over SSH.

.DESCRIPTION
    Uses the repo-root Dockerfile, docker-compose.yml, and nginx.conf.
    Builds the web image, then starts the stack. When --ssh-string is omitted,
    the local Docker daemon is used. When --ssh-string is set, images are built locally,
    exported, transferred to the remote host, loaded there, and compose is started without
    a remote build. When --delete-volume=yes, existing compose volumes are removed before
    the stack is recreated.

.PARAMETER SshString
    SSH config alias for remote Docker (e.g. example). The script prepends "ssh"
    when connecting; do not include "ssh" in the value. When omitted, localhost Docker is used.

.PARAMETER DeleteImage
    Whether to remove built images during stack teardown. Default: no.

.PARAMETER DeleteVolume
    Whether to remove data volumes before starting. Default: no.

.PARAMETER ReverseProxy
    Reverse-proxy mode. Default: sslh (no host port publishing on remote deploy).

.PARAMETER DomainName
    Public hostname to route to the web container through nginx on the remote host.

.PARAMETER InternalPort
    Container port used for domain routing. Default: 80 (web service).

.PARAMETER PublicPort
    Public HTTPS port for sslh/nginx. Default: 443.

.PARAMETER ApiBaseUrl
    VITE_API_BASE_URL build arg baked into the frontend. Default: from .env or
    http://localhost:8080/dogan/api/v1.

.EXAMPLE
    .\run-on-docker.ps1

.EXAMPLE
    .\run-on-docker.ps1 --delete-volume=yes

.EXAMPLE
    .\run-on-docker.ps1 --api-base-url=http://api.example.com/dogan/api/v1

.EXAMPLE
    .\run-on-docker.ps1 --ssh-string=example --domain=parkiroid.example.com --internal-port=80

.EXAMPLE
    .\run-on-docker.ps1 --ssh-string=example --delete-image=no --delete-volume=no
#>
[CmdletBinding()]
param(
    [Alias('ssh-string')]
    [string]$SshString,
    [Alias('delete-image')]
    [string]$DeleteImage = 'no',
    [Alias('delete-volume')]
    [string]$DeleteVolume = 'no',
    [Alias('reverse-proxy')]
    [string]$ReverseProxy = 'sslh',
    [Alias('domain')]
    [string]$DomainName,
    [Alias('internal-port')]
    [string]$InternalPort,
    [Alias('public-port')]
    [string]$PublicPort = '443',
    [Alias('api-base-url')]
    [string]$ApiBaseUrl,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:ComposeFile = 'docker-compose.yml'
$Script:LocalDeployDir = Join-Path $PSScriptRoot '.deploy'
$Script:DefaultApiBaseUrl = 'http://localhost:8080/dogan/api/v1'
$Script:DeploySyncFiles = @(
    'docker-compose.yml',
    'Dockerfile',
    'nginx.conf',
    '.dockerignore',
    '.docker/stack.manifest.json'
)

function Show-RunOnDockerHelp {
    Write-Host @'
parkiroid-web Docker run - build web image and start the Compose stack

Usage:
  .\run-on-docker.ps1 [--ssh-string=<alias>] [--delete-image=<no|yes>] [--delete-volume=<no|yes>]
                      [--reverse-proxy=<sslh|none>] [--domain=<hostname>] [--internal-port=<port>]
                      [--public-port=<port>] [--api-base-url=<url>] [--help]

Arguments:
  --ssh-string=<alias>        SSH config alias for remote Docker (e.g. example)
                              The script prepends "ssh" when connecting; do not include "ssh"
                              in the value. Builds images locally, transfers them to the server,
                              then starts compose remotely. When omitted, localhost Docker is used.
  --delete-image=<no|yes>     Remove built images during stack teardown (default: no)
  --delete-volume=<no|yes>    Remove named volumes before starting (default: no)
  --reverse-proxy=<sslh|none> Reverse-proxy mode (default: sslh)
                              sslh: no host port publishing on remote deploy (use Docker network)
                              none: publish host ports (8082 web on local)
  --domain=<hostname>         Map this hostname to the web container via remote nginx
                              Requires --ssh-string. Creates an nginx site and reloads nginx.
  --internal-port=<port>      Container port for domain routing (default: 80)
  --public-port=<port>        Public HTTPS port for sslh/nginx (default: 443)
  --api-base-url=<url>        VITE_API_BASE_URL baked into the frontend at build time
                              (default: from .env or http://localhost:8080/dogan/api/v1)
  --help, -h                  Show this help message and exit

Examples:
  .\run-on-docker.ps1
  .\run-on-docker.ps1 --help
  .\run-on-docker.ps1 --delete-volume=yes
  .\run-on-docker.ps1 --api-base-url=http://api.example.com/dogan/api/v1
  .\run-on-docker.ps1 --ssh-string=example --delete-image=no --delete-volume=no
  .\run-on-docker.ps1 --ssh-string=example --domain=parkiroid.example.com --internal-port=80
  .\run-on-docker.ps1 --ssh-string=example --reverse-proxy=sslh --domain=parkiroid.example.com --public-port=443

Remote deploy (--ssh-string): builds images locally, exports them, uploads to the
server, loads them there, and starts compose without a remote build.

Requires docker-compose.yml and Dockerfile in the repo root.
Local: Web UI http://localhost:8082
Remote with --domain: https://<domain> (routed to web container on Docker network)
'@ -ForegroundColor Cyan
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
    param(
        [string]$Name,
        [string]$Value
    )

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

    if ($null -eq $RemainingArguments) {
        $RemainingArguments = @()
    }
    else {
        $RemainingArguments = @($RemainingArguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

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

    switch ($Value.ToLowerInvariant()) {
        { $_ -in @('yes', 'true', '1', 'y', 'on') } { return $true }
        default { return $false }
    }
}

function Write-RunStep {
    param(
        [int]$Step,
        [int]$Total,
        [string]$Message
    )

    $percent = [math]::Round(($Step / $Total) * 100)
    Write-Progress -Activity 'parkiroid-web Docker run' -Status $Message -PercentComplete $percent
    Write-Host ("[{0}/{1}] {2}" -f $Step, $Total, $Message) -ForegroundColor Yellow
}

function Resolve-SshTarget {
    param([string]$SshString)

    if ([string]::IsNullOrWhiteSpace($SshString)) {
        return [pscustomobject]@{
            IsLocal  = $true
            SshAlias = $null
        }
    }

    $alias = $SshString.Trim()

    if ($alias -match '^(?i)ssh(\s|$)') {
        throw 'Invalid --ssh-string value. Pass only the SSH config alias (e.g. --ssh-string=example). Do not include "ssh".'
    }

    if ([string]::IsNullOrWhiteSpace($alias)) {
        throw 'Invalid --ssh-string value. Example: --ssh-string=example'
    }

    return [pscustomobject]@{
        IsLocal  = $false
        SshAlias = $alias
    }
}

function Invoke-RemoteCommand {
    param(
        [pscustomobject]$Target,
        [string]$Command,
        [string]$WorkingDirectory = $null
    )

    $remoteCommand = if ($WorkingDirectory) { "cd '$WorkingDirectory' && $Command" } else { $Command }

    if ($Target.IsLocal) {
        if ($WorkingDirectory) {
            Push-Location $WorkingDirectory
            try { return (Invoke-Expression $Command 2>&1 | Out-String).Trim() }
            finally { Pop-Location }
        }
        return (Invoke-Expression $Command 2>&1 | Out-String).Trim()
    }

    $escapedCommand = $remoteCommand -replace "'", "'\''"
    $output = & ssh $Target.SshAlias "bash -lc '$escapedCommand'" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Remote command failed (exit $LASTEXITCODE): $remoteCommand" }
    return $output.Trim()
}

function Invoke-RemoteShell {
    param(
        [pscustomobject]$Target,
        [string]$Command,
        [string]$WorkingDirectory = $null
    )

    $remoteCommand = if ($WorkingDirectory) { "cd '$WorkingDirectory' && $Command" } else { $Command }

    if ($Target.IsLocal) {
        if ($WorkingDirectory) {
            Push-Location $WorkingDirectory
            try { Invoke-Expression $Command | Out-Null }
            finally { Pop-Location }
        }
        else {
            Invoke-Expression $Command | Out-Null
        }
        if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): $Command" }
        return
    }

    $escapedCommand = $remoteCommand -replace "'", "'\''"
    & ssh $Target.SshAlias "bash -lc '$escapedCommand'"
    if ($LASTEXITCODE -ne 0) { throw "Remote command failed (exit $LASTEXITCODE): $remoteCommand" }
}

function Test-DockerCliAvailable {
    param([pscustomobject]$Target = $null)

    if ($null -eq $Target -or $Target.IsLocal) {
        & docker version | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Docker CLI is not available or not running.' }
        return
    }

    Invoke-RemoteShell -Target $Target -Command 'docker version'
}

function Copy-FileToRemote {
    param(
        [pscustomobject]$Target,
        [string]$LocalPath,
        [string]$RemotePath
    )

    & scp -o StrictHostKeyChecking=accept-new $LocalPath "$($Target.SshAlias):$RemotePath"
    if ($LASTEXITCODE -ne 0) { throw "Failed to copy '$LocalPath' to remote." }
}

function Sync-DeployFilesToRemote {
    param(
        [pscustomobject]$Target,
        [string]$LocalRoot,
        [string]$RemotePath
    )

    Invoke-RemoteShell -Target $Target -Command "mkdir -p '$RemotePath' '$RemotePath/.docker'"

    foreach ($relativePath in $Script:DeploySyncFiles) {
        $localPath = Join-Path $LocalRoot $relativePath
        if (-not (Test-Path $localPath)) {
            throw "Missing deploy file: $relativePath"
        }

        $remoteTarget = if ($relativePath -like '.docker/*') {
            "$RemotePath/$relativePath"
        }
        else {
            "$RemotePath/"
        }

        Copy-FileToRemote -Target $Target -LocalPath $localPath -RemotePath $remoteTarget
    }
}

function Get-StackManifest {
    param([string]$ProjectRoot)

    $manifestPath = Join-Path $ProjectRoot '.docker/stack.manifest.json'
    if (-not (Test-Path $manifestPath)) { return $null }
    return Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
}

function Get-StackImageTag {
    param([string]$ProjectRoot)

    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.webImageTag) {
        return [string]$manifest.webImageTag
    }
    if ($manifest -and $manifest.imageTag) {
        return [string]$manifest.imageTag
    }
    return 'parkiroid-web:latest'
}

function Get-ImageArchiveName {
    param([string]$StackName)

    return ($StackName -replace '[^a-zA-Z0-9._-]', '-') + '-images.tar'
}

function Resolve-ApiBaseUrl {
    param(
        [string]$ProjectRoot,
        [string]$OverrideValue
    )

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

function Build-LocalDockerImages {
    param(
        [string]$ProjectRoot,
        [string]$ApiBaseUrl
    )

    Push-Location $ProjectRoot
    try {
        $env:VITE_API_BASE_URL = $ApiBaseUrl
        & docker compose -f $Script:ComposeFile build
        if ($LASTEXITCODE -ne 0) { throw "docker compose build failed (exit $LASTEXITCODE)" }
    }
    finally {
        Pop-Location
    }
}

function Export-LocalDockerImages {
    param(
        [string[]]$ImageTags,
        [string]$ArchivePath
    )

    $parentDirectory = Split-Path -Parent $ArchivePath
    if (-not (Test-Path -LiteralPath $parentDirectory)) {
        New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force
    }

    & docker save -o $ArchivePath @ImageTags
    if ($LASTEXITCODE -ne 0) { throw "docker save failed (exit $LASTEXITCODE)" }
}

function Transfer-DockerImagesToRemote {
    param(
        [pscustomobject]$Target,
        [string[]]$ImageTags,
        [string]$RemotePath,
        [string]$StackName
    )

    $archiveName = Get-ImageArchiveName -StackName $StackName
    $localArchive = Join-Path $Script:LocalDeployDir $archiveName
    $remoteArchive = "$RemotePath/$archiveName"

    try {
        Export-LocalDockerImages -ImageTags $ImageTags -ArchivePath $localArchive

        $tarSizeMb = [math]::Round((Get-Item $localArchive).Length / 1MB, 1)
        Write-Host "Transferring images ($tarSizeMb MB) to remote host..." -ForegroundColor Cyan
        Copy-FileToRemote -Target $Target -LocalPath $localArchive -RemotePath $remoteArchive

        Write-Host 'Loading images on remote host...' -ForegroundColor Cyan
        Invoke-RemoteShell -Target $Target -Command "docker load -i '$remoteArchive' && rm -f '$remoteArchive'"
        Write-Host 'Images loaded on remote host.' -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $localArchive) {
            Remove-Item -LiteralPath $localArchive -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-PortNumber {
    param(
        [string]$Value,
        [string]$ParameterName
    )

    if ($Value -notmatch '^\d+$') {
        throw "Invalid $ParameterName value '$Value'. Use a numeric port between 1 and 65535."
    }

    $port = [int]$Value
    if ($port -lt 1 -or $port -gt 65535) {
        throw "Invalid $ParameterName value '$Value'. Use a port between 1 and 65535."
    }
}

function Test-ReverseProxyMode {
    param([string]$Value)

    $normalized = $Value.Trim().ToLowerInvariant()
    if ($normalized -in @('sslh', 'none', 'direct', 'off')) { return $normalized }
    throw "Invalid --reverse-proxy value '$Value'. Allowed: sslh, none."
}

function Get-SslhRuntimeInfo {
    param([pscustomobject]$Target)

    $inspectJson = Invoke-RemoteCommand -Target $Target -Command "docker inspect sslh --format '{{json .}}' 2>/dev/null || true"
    if ([string]::IsNullOrWhiteSpace($inspectJson)) {
        throw 'sslh container not found on remote host. Start sslh before using --reverse-proxy=sslh with --domain.'
    }

    $inspect = $inspectJson | ConvertFrom-Json
    $configMount = $inspect.Mounts | Where-Object { $_.Destination -eq '/etc/sslh' } | Select-Object -First 1
    if (-not $configMount) {
        throw 'Could not locate sslh config mount at /etc/sslh.'
    }

    $networkName = ($inspect.NetworkSettings.Networks.PSObject.Properties | Select-Object -First 1).Name
    if ([string]::IsNullOrWhiteSpace($networkName)) {
        throw 'Could not determine sslh Docker network.'
    }

    return [pscustomobject]@{
        ContainerName = [string]$inspect.Name.TrimStart('/')
        ConfigPath    = Join-Path $configMount.Source 'sslh.cfg'
        NetworkName   = [string]$networkName
    }
}

function Set-SslhDomainMapping {
    param(
        [pscustomobject]$Target,
        [string]$DomainName,
        [string]$TlsContainerName,
        [string]$WebContainerPort,
        [string]$WebContainerName,
        [string]$StackNetworkName,
        [pscustomobject]$SslhInfo,
        [string]$WebImageTag = 'parkiroid-web:latest'
    )

    $safeDomain = $DomainName.Trim().ToLowerInvariant()
    $configPath = ($SslhInfo.ConfigPath -replace '\\', '/')
    $sslhEntry = "  { name: `"tls`"; host: `"$TlsContainerName`"; port: `"443`"; sni_hostnames: [ `"$safeDomain`" ]; },"

    $remoteScriptPath = '/tmp/parkiroid-web-sslh-domain-map.sh'
    $localScriptPath = Join-Path $Script:LocalDeployDir 'sslh-domain-map.sh'
    $parentDirectory = Split-Path -Parent $localScriptPath
    if (-not (Test-Path -LiteralPath $parentDirectory)) {
        New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
    }

    $bashScript = @"
#!/bin/bash
set -euo pipefail

TLS_HOST='$TlsContainerName'
WEB='$WebContainerName'
WEB_PORT='$WebContainerPort'
STACK_NET='$StackNetworkName'
SSLH_NET='$($SslhInfo.NetworkName)'
TLS_DIR='/cloud-admin/docker-volumes/parkiroid-web/tls'
CFG='$configPath'
DOMAIN='$safeDomain'
SSLH_ENTRY='$sslhEntry'

docker network connect "`$SSLH_NET" "`$WEB" 2>/dev/null || true

sudo mkdir -p "`$TLS_DIR"
if [ ! -f "`$TLS_DIR/cert.pem" ]; then
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "`$TLS_DIR/key.pem" -out "`$TLS_DIR/cert.pem" \
    -subj "/CN=`$DOMAIN"
fi

sudo tee "`$TLS_DIR/default.conf" >/dev/null <<'NGINXEOF'
server {
    listen 443 ssl;
    server_name $safeDomain;
    ssl_certificate /etc/nginx/certs/cert.pem;
    ssl_certificate_key /etc/nginx/certs/key.pem;
    location / {
        proxy_pass http://${WebContainerName}:${WebContainerPort};
        proxy_http_version 1.1;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
NGINXEOF

docker rm -f "`$TLS_HOST" 2>/dev/null || true
docker run -d --name "`$TLS_HOST" --network "`$SSLH_NET" \
  -v "`$TLS_DIR/cert.pem:/etc/nginx/certs/cert.pem:ro" \
  -v "`$TLS_DIR/key.pem:/etc/nginx/certs/key.pem:ro" \
  -v "`$TLS_DIR/default.conf:/etc/nginx/conf.d/default.conf:ro" \
  $WebImageTag
docker network connect "`$STACK_NET" "`$TLS_HOST" 2>/dev/null || true

sudo python3 - <<'PY'
from pathlib import Path
import re

cfg_path = Path('$configPath')
domain = '$safeDomain'
entry = '$sslhEntry'
text = cfg_path.read_text()
if domain in text:
    pattern = r'  \{ name: "tls"; host: "[^"]+"; port: "[^"]+"; sni_hostnames: \[ "' + re.escape(domain) + r'" \]; \},?\n?'
    text = re.sub(pattern, entry + '\n', text)
else:
    text = text.replace('protocols:\n(\n', 'protocols:\n(\n' + entry + '\n', 1)
cfg_path.write_text(text)
PY

docker restart '$($SslhInfo.ContainerName)'
"@

    [System.IO.File]::WriteAllText($localScriptPath, ($bashScript -replace "`r`n", "`n"))

    Write-Host "Mapping domain '$safeDomain' via sslh -> ${TlsContainerName}:443 -> ${WebContainerName}..." -ForegroundColor Cyan
    Copy-FileToRemote -Target $Target -LocalPath $localScriptPath -RemotePath $remoteScriptPath
    Invoke-RemoteShell -Target $Target -Command "chmod +x '$remoteScriptPath' && bash '$remoteScriptPath' && rm -f '$remoteScriptPath'"
    Write-Host "sslh domain mapping configured for https://${safeDomain}/" -ForegroundColor Green
}

function Set-DomainReverseProxyMapping {
    param(
        [pscustomobject]$Target,
        [string]$DomainName,
        [string]$WebContainerName,
        [string]$ContainerPort,
        [string]$HttpsPort,
        [string]$ReverseProxyMode,
        [string]$StackNetworkName,
        [string]$WebImageTag = 'parkiroid-web:latest'
    )

    if ($Target.IsLocal) {
        throw '--domain requires --ssh-string for remote reverse-proxy configuration.'
    }

    $safeDomain = $DomainName.Trim().ToLowerInvariant()
    if ($safeDomain -notmatch '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$') {
        throw "Invalid --domain value '$DomainName'."
    }

    Test-PortNumber -Value $ContainerPort -ParameterName '--internal-port'
    Test-PortNumber -Value $HttpsPort -ParameterName '--public-port'

    if ($ReverseProxyMode -eq 'sslh') {
        $sslhInfo = Get-SslhRuntimeInfo -Target $Target
        $tlsContainerName = "${WebContainerName}-tls"
        Set-SslhDomainMapping -Target $Target -DomainName $safeDomain -TlsContainerName $tlsContainerName -WebContainerPort $ContainerPort -WebContainerName $WebContainerName -StackNetworkName $StackNetworkName -SslhInfo $sslhInfo -WebImageTag $WebImageTag
        return
    }

    $configFileName = "$safeDomain.conf"
    $availablePath = "/etc/nginx/sites-available/$configFileName"
    $enabledPath = "/etc/nginx/sites-enabled/$configFileName"
    $listenDirective = 'listen 80;'

    $nginxConfig = @"
server {
    $listenDirective
    server_name $safeDomain;
    location / {
        resolver 127.0.0.11 valid=30s ipv6=off;
        set `$upstream $WebContainerName`:$ContainerPort;
        proxy_pass http://`$upstream;
        proxy_http_version 1.1;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
"@

    $encodedConfig = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($nginxConfig))
    $installCommand = @"
set -e
tmp='$(Split-Path -Leaf $availablePath).tmp'
echo '$encodedConfig' | base64 -d | sudo tee "/tmp/`$tmp" >/dev/null
sudo mv "/tmp/`$tmp" '$availablePath'
sudo ln -sf '$availablePath' '$enabledPath'
if command -v nginx >/dev/null 2>&1; then
  sudo nginx -t
  sudo systemctl reload nginx || sudo service nginx reload
fi
"@

    Write-Host "Mapping domain '$safeDomain' -> ${WebContainerName}:${ContainerPort} (public port $HttpsPort)..." -ForegroundColor Cyan
    Invoke-RemoteShell -Target $Target -Command $installCommand
    Write-Host "Domain mapping configured for https://${safeDomain}/" -ForegroundColor Green
}

function Get-DockerManifestDefaults {
    param([string]$ProjectRoot)

    $defaults = @{
        WebContainerName = 'parkiroid-web'
        WebInternalPort  = '80'
        DockerNetwork    = 'parkiroid-net'
        ContainerName    = 'parkiroid-web'
        WebPublishPort   = '8082'
    }

    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if (-not $manifest) { return $defaults }

    if ($manifest.PSObject.Properties.Match('containerName').Count -gt 0 -and $manifest.containerName) {
        $defaults.ContainerName = [string]$manifest.containerName
    }
    if ($manifest.PSObject.Properties.Match('webContainerName').Count -gt 0 -and $manifest.webContainerName) {
        $defaults.WebContainerName = [string]$manifest.webContainerName
    }
    if ($manifest.PSObject.Properties.Match('webInternalPort').Count -gt 0 -and $manifest.webInternalPort) {
        $defaults.WebInternalPort = [string]$manifest.webInternalPort
    }
    if ($manifest.PSObject.Properties.Match('dockerNetwork').Count -gt 0 -and $manifest.dockerNetwork) {
        $defaults.DockerNetwork = [string]$manifest.dockerNetwork
    }
    if ($manifest.PSObject.Properties.Match('webPublishPort').Count -gt 0 -and $manifest.webPublishPort) {
        $defaults.WebPublishPort = [string]$manifest.webPublishPort
    }

    return $defaults
}

function Set-ComposeEnvironment {
    param(
        [string]$NetworkName,
        [string]$ApiBaseUrl,
        [bool]$PublishHostPorts = $true
    )

    $env:DOCKER_NETWORK = $NetworkName
    $env:VITE_API_BASE_URL = $ApiBaseUrl

    if ($PublishHostPorts) {
        Remove-Item Env:WEB_PUBLISH_PORT -ErrorAction SilentlyContinue
    }
    else {
        $env:WEB_PUBLISH_PORT = ''
    }
}

function Get-RemoteComposeEnvironmentPrefix {
    param(
        [string]$NetworkName,
        [string]$ApiBaseUrl,
        [bool]$PublishHostPorts = $false
    )

    $prefix = "DOCKER_NETWORK='$NetworkName' VITE_API_BASE_URL='$ApiBaseUrl' "
    if (-not $PublishHostPorts) {
        $prefix += "WEB_PUBLISH_PORT='' "
    }
    return $prefix
}

function Get-RemoteWorkDir {
    param(
        [string]$ProjectRoot,
        [pscustomobject]$Target = $null
    )

    $stackName = 'parkiroid-web'
    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.stackName) {
        $stackName = [string]$manifest.stackName
    }

    if ($null -ne $Target -and -not $Target.IsLocal) {
        return "/opt/docker/$stackName"
    }

    return $ProjectRoot
}

function Test-DockerComposeFile {
    param([string]$ProjectRoot)

    $composePath = Join-Path $ProjectRoot $Script:ComposeFile
    if (-not (Test-Path $composePath)) {
        throw "Missing $Script:ComposeFile in the repo root."
    }

    $dockerfilePath = Join-Path $ProjectRoot 'Dockerfile'
    if (-not (Test-Path $dockerfilePath)) {
        throw 'Missing Dockerfile in the repo root.'
    }

    $nginxPath = Join-Path $ProjectRoot 'nginx.conf'
    if (-not (Test-Path $nginxPath)) {
        throw 'Missing nginx.conf in the repo root.'
    }
}

function Ensure-DockerNetwork {
    param(
        [pscustomobject]$Target,
        [string]$NetworkName,
        [string]$WorkingDirectory
    )

    if ($Target.IsLocal) {
        $existingNetworks = docker network ls --format '{{.Name}}'
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to list Docker networks. Is Docker running?'
        }
        if ($existingNetworks -notcontains $NetworkName) {
            docker network create $NetworkName | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create Docker network '$NetworkName'."
            }
        }
        return
    }

    $createCommand = "docker network inspect '$NetworkName' >/dev/null 2>&1 || docker network create '$NetworkName'"
    try {
        Invoke-RemoteShell -Target $Target -Command $createCommand -WorkingDirectory $WorkingDirectory
    }
    catch {
        throw "Failed to ensure Docker network '$NetworkName': $($_.Exception.Message)"
    }
}

function Invoke-ComposeStack {
    param(
        [pscustomobject]$Target,
        [string]$WorkingDirectory,
        [bool]$RemoveVolumes,
        [bool]$RemoveImages,
        [bool]$Build,
        [string]$NetworkName,
        [string]$ApiBaseUrl,
        [bool]$PublishHostPorts
    )

    $downFlag = if ($RemoveVolumes) { ' -v' } else { '' }
    $rmiFlag = if ($RemoveImages) { ' --rmi local' } else { '' }
    $composeDown = "docker compose -f $Script:ComposeFile down$rmiFlag$downFlag"
    $buildFlag = if ($Build) { ' --build' } else { '' }
    $composeUp = "docker compose -f $Script:ComposeFile up -d$buildFlag"

    if ($Target.IsLocal) {
        Push-Location $WorkingDirectory
        try {
            Set-ComposeEnvironment -NetworkName $NetworkName -ApiBaseUrl $ApiBaseUrl -PublishHostPorts:$PublishHostPorts
            Invoke-Expression $composeDown | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'Compose down skipped or partial (stack may not exist yet).' -ForegroundColor DarkYellow
            }
            Invoke-Expression $composeUp | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }
        }
        finally {
            Pop-Location
        }
        return
    }

    try {
        Invoke-RemoteShell -Target $Target -Command $composeDown -WorkingDirectory $WorkingDirectory
    }
    catch {
        Write-Host "Compose down skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    $envPrefix = Get-RemoteComposeEnvironmentPrefix -NetworkName $NetworkName -ApiBaseUrl $ApiBaseUrl -PublishHostPorts:$PublishHostPorts
    Invoke-RemoteShell -Target $Target -Command "${envPrefix}$composeUp" -WorkingDirectory $WorkingDirectory
}

if ($Help) {
    Show-RunOnDockerHelp
    Get-Help $PSCommandPath -Full
    exit 0
}

$cliArgs = Merge-CliArguments -BoundParameters $PSBoundParameters -RemainingArguments $RemainingArguments
if ($cliArgs['help']) {
    Show-RunOnDockerHelp
    Get-Help $PSCommandPath -Full
    exit 0
}

$sshStringValue = if ($cliArgs['ssh_string']) { [string]$cliArgs['ssh_string'] } else { [string]$SshString }
$sshStringValue = Normalize-CliParameterValue -Name 'ssh_string' -Value $sshStringValue
$deleteImageValue = if ($cliArgs['delete_image']) { [string]$cliArgs['delete_image'] } else { [string]$DeleteImage }
$deleteImageValue = Normalize-CliParameterValue -Name 'delete_image' -Value $deleteImageValue
$deleteVolumeValue = if ($cliArgs['delete_volume']) { [string]$cliArgs['delete_volume'] } else { [string]$DeleteVolume }
$deleteVolumeValue = Normalize-CliParameterValue -Name 'delete_volume' -Value $deleteVolumeValue
$reverseProxyValue = if ($cliArgs['reverse_proxy']) { [string]$cliArgs['reverse_proxy'] } else { [string]$ReverseProxy }
$reverseProxyValue = Normalize-CliParameterValue -Name 'reverse_proxy' -Value $reverseProxyValue
$domainValue = if ($cliArgs['domain']) { [string]$cliArgs['domain'] } else { [string]$DomainName }
$domainValue = Normalize-CliParameterValue -Name 'domain' -Value $domainValue
$publicPortValue = if ($cliArgs['public_port']) { [string]$cliArgs['public_port'] } else { [string]$PublicPort }
$publicPortValue = Normalize-CliParameterValue -Name 'public_port' -Value $publicPortValue
$apiBaseUrlValue = if ($cliArgs['api_base_url']) { [string]$cliArgs['api_base_url'] } elseif (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) { [string]$ApiBaseUrl } else { $null }
$apiBaseUrlValue = Normalize-CliParameterValue -Name 'api_base_url' -Value $apiBaseUrlValue
$removeVolumes = Test-Truthy -Value $deleteVolumeValue
$removeImages = Test-Truthy -Value $deleteImageValue
$reverseProxyMode = Test-ReverseProxyMode -Value $reverseProxyValue

$ProjectRoot = $PSScriptRoot
$manifestDefaults = Get-DockerManifestDefaults -ProjectRoot $ProjectRoot
$internalPortValue = if ($cliArgs['internal_port']) { [string]$cliArgs['internal_port'] } elseif (-not [string]::IsNullOrWhiteSpace($InternalPort)) { [string]$InternalPort } else { $manifestDefaults.WebInternalPort }
$internalPortValue = Normalize-CliParameterValue -Name 'internal_port' -Value $internalPortValue
$resolvedApiBaseUrl = Resolve-ApiBaseUrl -ProjectRoot $ProjectRoot -OverrideValue $apiBaseUrlValue

Test-PortNumber -Value $internalPortValue -ParameterName '--internal-port'
Test-PortNumber -Value $publicPortValue -ParameterName '--public-port'

$target = Resolve-SshTarget -SshString $sshStringValue
if (-not [string]::IsNullOrWhiteSpace($domainValue) -and $target.IsLocal) {
    throw '--domain requires --ssh-string for remote nginx configuration.'
}

$networkValue = $manifestDefaults.DockerNetwork
$webContainerName = $manifestDefaults.WebContainerName
$webPublishPort = $manifestDefaults.WebPublishPort
$publishHostPorts = $target.IsLocal -or ($reverseProxyMode -in @('none', 'direct', 'off'))
$workDir = Get-RemoteWorkDir -ProjectRoot $ProjectRoot -Target $target
$imageTag = Get-StackImageTag -ProjectRoot $ProjectRoot
$stackManifest = Get-StackManifest -ProjectRoot $ProjectRoot
$stackName = if ($stackManifest -and $stackManifest.stackName) { [string]$stackManifest.stackName } else { 'parkiroid-web' }

$targetLabel = if ($target.IsLocal) { 'localhost' } else { "ssh $($target.SshAlias)" }
$volumeAction = if ($removeVolumes) { 'removing volumes' } else { 'keeping volumes' }
$imageAction = if ($removeImages) { 'removing images' } else { 'keeping images' }
$proxyLabel = if ($publishHostPorts) { 'host ports' } else { 'sslh (docker network only)' }
$domainLabel = if ([string]::IsNullOrWhiteSpace($domainValue)) { 'none' } else { $domainValue }
$totalSteps = if ($target.IsLocal) {
    4
}
else {
    if ([string]::IsNullOrWhiteSpace($domainValue)) { 7 } else { 8 }
}

try {
    $deployMode = if ($target.IsLocal) { 'local Docker' } else { 'local build + image transfer' }
    Write-Host ("Target: {0} ({1}) | network: {2} | api: {3} | domain: {4} | proxy: {5} | {6} | {7}" -f `
        $targetLabel, $deployMode, $networkValue, $resolvedApiBaseUrl, `
        $domainLabel, $proxyLabel, $volumeAction, $imageAction) -ForegroundColor Cyan

    Write-RunStep -Step 1 -Total $totalSteps -Message 'Checking Docker files'
    Test-DockerComposeFile -ProjectRoot $ProjectRoot
    Test-DockerCliAvailable -Target $target

    Write-RunStep -Step 2 -Total $totalSteps -Message 'Building web image'
    Build-LocalDockerImages -ProjectRoot $ProjectRoot -ApiBaseUrl $resolvedApiBaseUrl

    if ($target.IsLocal) {
        Write-RunStep -Step 3 -Total $totalSteps -Message "Ensuring Docker network '$networkValue'"
        Ensure-DockerNetwork -Target $target -NetworkName $networkValue -WorkingDirectory $workDir

        Write-RunStep -Step 4 -Total $totalSteps -Message $(if ($removeVolumes) { 'Recreating stack (volumes removed)' } else { 'Recreating stack (keeping volumes)' })
        Invoke-ComposeStack -Target $target -WorkingDirectory $workDir -RemoveVolumes:$removeVolumes -RemoveImages:$removeImages -Build:$false -NetworkName $networkValue -ApiBaseUrl $resolvedApiBaseUrl -PublishHostPorts:$publishHostPorts
    }
    else {
        Write-RunStep -Step 3 -Total $totalSteps -Message "Syncing compose files to $targetLabel"
        Sync-DeployFilesToRemote -Target $target -LocalRoot $ProjectRoot -RemotePath $workDir

        Write-RunStep -Step 4 -Total $totalSteps -Message 'Transferring images to remote host'
        Transfer-DockerImagesToRemote -Target $target -ImageTags @($imageTag) -RemotePath $workDir -StackName $stackName

        Write-RunStep -Step 5 -Total $totalSteps -Message 'Checking remote Docker'
        Test-DockerCliAvailable -Target $target

        Write-RunStep -Step 6 -Total $totalSteps -Message "Ensuring Docker network '$networkValue'"
        Ensure-DockerNetwork -Target $target -NetworkName $networkValue -WorkingDirectory $workDir

        Write-RunStep -Step 7 -Total $totalSteps -Message $(if ($removeVolumes) { 'Recreating stack (volumes removed)' } else { 'Recreating stack (keeping volumes)' })
        Invoke-ComposeStack -Target $target -WorkingDirectory $workDir -RemoveVolumes:$removeVolumes -RemoveImages:$removeImages -Build:$false -NetworkName $networkValue -ApiBaseUrl $resolvedApiBaseUrl -PublishHostPorts:$publishHostPorts

        if (-not [string]::IsNullOrWhiteSpace($domainValue)) {
            Write-RunStep -Step 8 -Total $totalSteps -Message "Mapping domain '$domainValue' to $webContainerName"
            Set-DomainReverseProxyMapping -Target $target -DomainName $domainValue -WebContainerName $webContainerName -ContainerPort $internalPortValue -HttpsPort $publicPortValue -ReverseProxyMode $reverseProxyMode -StackNetworkName $networkValue -WebImageTag $imageTag
        }
    }

    Write-Progress -Activity 'parkiroid-web Docker run' -Completed -Status 'Done'
    Write-Host ''

    if ($target.IsLocal) {
        Write-Host 'Stack is running on localhost.' -ForegroundColor Green
        Write-Host "  Web UI: http://localhost:$webPublishPort" -ForegroundColor Green
        Write-Host "  API (build-time): $resolvedApiBaseUrl" -ForegroundColor Green
    }
    else {
        Write-Host "Stack is running on remote host at $workDir (network: $networkValue)." -ForegroundColor Green
        Write-Host ("Images were built locally and deployed to {0} without a remote build." -f $target.SshAlias) -ForegroundColor Green
        Write-Host "  API (build-time): $resolvedApiBaseUrl" -ForegroundColor Green
        if (-not [string]::IsNullOrWhiteSpace($domainValue)) {
            Write-Host "  URL:  https://${domainValue}/" -ForegroundColor Green
        }
    }
}
catch {
    Write-Progress -Activity 'parkiroid-web Docker run' -Completed -Status 'Failed'
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Show-RunOnDockerHelp
    exit 1
}
