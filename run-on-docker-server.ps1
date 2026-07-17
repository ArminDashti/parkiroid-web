<#
.SYNOPSIS
    Build locally and deploy the dogan-webui UI stack to a remote Docker host over SSH.

.DESCRIPTION
    Builds images on the local Docker daemon, transfers them to the remote host,
    syncs compose files, and starts the stack without a remote build.
    --ssh-string is required (SSH config alias only).

.EXAMPLE
    .\run-on-docker-server.ps1 --ssh-string=myserver

.EXAMPLE
    .\run-on-docker-server.ps1 --ssh-string=myserver --delete-volume=yes

.EXAMPLE
    .\run-on-docker-server.ps1 --ssh-string=myserver --domain=parkiroid.example.com --internal-port=80
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
    [Alias('reverse-proxy')]
    [string]$ReverseProxy,
    [Alias('domain')]
    [string]$DomainName,
    [Alias('public-port')]
    [string]$PublicPort,
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
$Script:LocalDeployDir = Join-Path $PSScriptRoot '.deploy'
$Script:DefaultApiBaseUrl = 'http://localhost:8080/dogan/api/v1'
$Script:ContainerName = 'dogan-webui'
$Script:SafePortMin = 30000
$Script:SafePortMax = 32767
$Script:DeploySyncFiles = @(
    'docker-compose.yml',
    'Dockerfile',
    'nginx.conf',
    '.dockerignore',
    '.docker/stack.manifest.json'
)

function Show-Help {
    Write-Host @"
run-on-docker-server.ps1 — deploy $Script:ContainerName on a remote Docker host over SSH

USAGE:
  .\run-on-docker-server.ps1 --ssh-string=<alias> [flags]

FLAGS:
  --ssh-string=<alias>       SSH config alias (required; default: null → validation error)
  --delete-image=<no|yes>    Remove built images during teardown (default: null → no)
  --delete-volume=<no|yes>   Remove volumes before recreate (default: null → no)
  --internal-port=<port>     Container port for domain routing, or host publish when reverse-proxy=none
                             (default: null → 80 for sslh domain routing, or random 30000–32767 when publishing)
  --volume-dir=<path>        Bind-mount data directory (default: null → /cloud-admin/docker-volumes/<CONTAINER-NAME>)
  --volume-name=<name>       Named Docker volume (default: null → <CONTAINER-NAME>-volume)
  --network-name=<name>      Docker network (default: null → from manifest or <CONTAINER-NAME>-network)
  --reverse-proxy=<sslh|none> Reverse-proxy mode (default: null → sslh)
  --domain=<hostname>        Map hostname via remote sslh/nginx (optional)
  --public-port=<port>       Public HTTPS port for sslh/nginx (default: null → 443)
  --api-base-url=<url>       VITE_API_BASE_URL baked at build time (default: null → .env or $Script:DefaultApiBaseUrl)
  --help                     Show this help

EXAMPLES:
  .\run-on-docker-server.ps1 --ssh-string=myserver
  .\run-on-docker-server.ps1 --ssh-string=myserver --delete-volume=yes
  .\run-on-docker-server.ps1 --ssh-string=myserver --domain=parkiroid.example.com --internal-port=80

NOTES:
  - Use SSH config alias only; do not include "ssh" in --ssh-string.
  - Images are built locally, transferred, and loaded remotely (no remote build).
  - Null defaults resolve as described in FLAGS.
  - Truthy values for yes/no flags: yes, true, 1, y, on.
  - Default published host port (reverse-proxy=none) is random from 30000–32767 if not specified.
  - Default --volume-dir is always /cloud-admin/docker-volumes/<CONTAINER-NAME> and is created on the remote host.
  - Remote compose install path is /cloud-admin/docker/<CONTAINER-NAME> (not /opt/docker).
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
    Write-Progress -Activity 'dogan-webui remote Docker' -Status $Message -PercentComplete $percent
    Write-Host ("[{0}/{1}] {2}" -f $Step, $Total, $Message) -ForegroundColor Yellow
}

function Resolve-SshTarget {
    param([string]$SshString)
    if ([string]::IsNullOrWhiteSpace($SshString)) {
        throw '--ssh-string is required. Pass an SSH config alias (e.g. --ssh-string=myserver).'
    }
    $alias = $SshString.Trim()
    if ($alias -match '^(?i)ssh(\s|$)') {
        throw 'Invalid --ssh-string value. Pass only the SSH config alias. Do not include "ssh".'
    }
    if ($alias -in @('localhost', 'local', '127.0.0.1')) {
        throw 'Use .\run-on-docker-local.ps1 for local Docker deploys.'
    }
    return [pscustomobject]@{ IsLocal = $false; SshAlias = $alias }
}

function Invoke-RemoteCommand {
    param([pscustomobject]$Target, [string]$Command, [string]$WorkingDirectory = $null)
    $remoteCommand = if ($WorkingDirectory) { "cd '$WorkingDirectory' && $Command" } else { $Command }
    $escapedCommand = $remoteCommand -replace "'", "'\''"
    $output = & ssh $Target.SshAlias "bash -lc '$escapedCommand'" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Remote command failed (exit $LASTEXITCODE): $remoteCommand" }
    return $output.Trim()
}

function Invoke-RemoteShell {
    param([pscustomobject]$Target, [string]$Command, [string]$WorkingDirectory = $null)
    $remoteCommand = if ($WorkingDirectory) { "cd '$WorkingDirectory' && $Command" } else { $Command }
    $escapedCommand = $remoteCommand -replace "'", "'\''"
    & ssh $Target.SshAlias "bash -lc '$escapedCommand'"
    if ($LASTEXITCODE -ne 0) { throw "Remote command failed (exit $LASTEXITCODE): $remoteCommand" }
}

function Copy-FileToRemote {
    param([pscustomobject]$Target, [string]$LocalPath, [string]$RemotePath)
    & scp -o StrictHostKeyChecking=accept-new $LocalPath "$($Target.SshAlias):$RemotePath"
    if ($LASTEXITCODE -ne 0) { throw "Failed to copy '$LocalPath' to remote." }
}

function Sync-DeployFilesToRemote {
    param([pscustomobject]$Target, [string]$LocalRoot, [string]$RemotePath)
    $normalized = ($RemotePath -replace '\\', '/').TrimEnd('/')
    # Use ssh double-quoted remote cmd so $(whoami) expands; Invoke-RemoteShell uses bash -lc '...' which would not.
    & ssh $Target.SshAlias "sudo mkdir -p '$normalized' '$normalized/.docker' && sudo chown -R `$(whoami):`$(whoami) '$normalized'"
    if ($LASTEXITCODE -ne 0) {
        throw "Remote command failed (exit $LASTEXITCODE): sudo mkdir/chown '$normalized' (need passwordless sudo under /cloud-admin)"
    }
    foreach ($relativePath in $Script:DeploySyncFiles) {
        $localPath = Join-Path $LocalRoot $relativePath
        if (-not (Test-Path $localPath)) { throw "Missing deploy file: $relativePath" }
        $remoteTarget = if ($relativePath -like '.docker/*') { "$normalized/$relativePath" } else { "$normalized/" }
        Copy-FileToRemote -Target $Target -LocalPath $localPath -RemotePath $remoteTarget
    }
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

function Get-StackImageTag {
    param([string]$ProjectRoot)
    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.webImageTag) { return [string]$manifest.webImageTag }
    if ($manifest -and $manifest.imageTag) { return [string]$manifest.imageTag }
    return 'dogan-webui:latest'
}

function Get-ImageArchiveName {
    param([string]$StackName)
    return ($StackName -replace '[^a-zA-Z0-9._-]', '-') + '-images.tar'
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

function Resolve-NetworkName {
    param([string]$ProjectRoot, [string]$Override, [string]$ContainerName)
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }
    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.dockerNetwork) { return [string]$manifest.dockerNetwork }
    return "t3-net"
}

function Resolve-VolumeDir {
    param([string]$Override, [string]$ContainerName)
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }
    return "/cloud-admin/docker-volumes/$ContainerName"
}

function Ensure-RemoteVolumeDir {
    param([pscustomobject]$Target, [string]$Path)
    $normalized = ($Path -replace '\\', '/').TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw 'Volume directory path is empty.'
    }
    Invoke-RemoteShell -Target $Target -Command "sudo mkdir -p '$normalized' && sudo chmod 755 '$normalized'"
    Write-Host "Remote volume dir ready: $normalized" -ForegroundColor Green
}

function Resolve-VolumeName {
    param([string]$Override, [string]$ContainerName)
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }
    return "$ContainerName-vol"
}

function Test-PortNumber {
    param([string]$Value, [string]$ParameterName)
    if ($Value -notmatch '^\d+$') {
        throw "Invalid $ParameterName value '$Value'. Use a numeric port between 1 and 65535."
    }
    $port = [int]$Value
    if ($port -lt 1 -or $port -gt 65535) {
        throw "Invalid $ParameterName value '$Value'. Use a port between 1 and 65535."
    }
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

function Test-ReverseProxyMode {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'sslh' }
    $normalized = $Value.Trim().ToLowerInvariant()
    if ($normalized -in @('sslh', 'none', 'direct', 'off')) { return $normalized }
    throw "Invalid --reverse-proxy value '$Value'. Allowed: sslh, none."
}

function Export-LocalDockerImages {
    param([string[]]$ImageTags, [string]$ArchivePath)
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
    param([pscustomobject]$Target, [string[]]$ImageTags, [string]$RemotePath, [string]$StackName)
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

function Get-SslhRuntimeInfo {
    param([pscustomobject]$Target)
    $inspectJson = Invoke-RemoteCommand -Target $Target -Command "docker inspect sslh --format '{{json .}}' 2>/dev/null || true"
    if ([string]::IsNullOrWhiteSpace($inspectJson)) {
        throw 'sslh container not found on remote host. Start sslh before using --reverse-proxy=sslh with --domain.'
    }
    $inspect = $inspectJson | ConvertFrom-Json
    $configMount = $inspect.Mounts | Where-Object { $_.Destination -eq '/etc/sslh' } | Select-Object -First 1
    if (-not $configMount) { throw 'Could not locate sslh config mount at /etc/sslh.' }
    $networkName = ($inspect.NetworkSettings.Networks.PSObject.Properties | Select-Object -First 1).Name
    if ([string]::IsNullOrWhiteSpace($networkName)) { throw 'Could not determine sslh Docker network.' }
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
        [string]$WebImageTag = 'dogan-webui:latest',
        [string]$VolumeDir = '/cloud-admin/docker-volumes/dogan-webui'
    )

    $safeDomain = $DomainName.Trim().ToLowerInvariant()
    $configPath = ($SslhInfo.ConfigPath -replace '\\', '/')
    $tlsDir = (($VolumeDir -replace '\\', '/').TrimEnd('/')) + '/tls'
    $sslhEntry = "  { name: `"tls`"; host: `"$TlsContainerName`"; port: `"443`"; sni_hostnames: [ `"$safeDomain`" ]; },"
    $remoteScriptPath = '/tmp/dogan-webui-sslh-domain-map.sh'
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
TLS_DIR='$tlsDir'
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
        [string]$WebImageTag = 'dogan-webui:latest',
        [string]$VolumeDir = '/cloud-admin/docker-volumes/dogan-webui'
    )

    $safeDomain = $DomainName.Trim().ToLowerInvariant()
    if ($safeDomain -notmatch '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$') {
        throw "Invalid --domain value '$DomainName'."
    }
    Test-PortNumber -Value $ContainerPort -ParameterName '--internal-port'
    Test-PortNumber -Value $HttpsPort -ParameterName '--public-port'

    if ($ReverseProxyMode -eq 'sslh') {
        $sslhInfo = Get-SslhRuntimeInfo -Target $Target
        $tlsContainerName = "${WebContainerName}-tls"
        Set-SslhDomainMapping -Target $Target -DomainName $safeDomain -TlsContainerName $tlsContainerName -WebContainerPort $ContainerPort -WebContainerName $WebContainerName -StackNetworkName $StackNetworkName -SslhInfo $sslhInfo -WebImageTag $WebImageTag -VolumeDir $VolumeDir
        return
    }

    $configFileName = "$safeDomain.conf"
    $availablePath = "/etc/nginx/sites-available/$configFileName"
    $enabledPath = "/etc/nginx/sites-enabled/$configFileName"
    $nginxConfig = @"
server {
    listen 80;
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

function Test-DockerComposeFile {
    param([string]$ProjectRoot)
    foreach ($relative in @($Script:ComposeFile, 'Dockerfile', 'nginx.conf')) {
        if (-not (Test-Path (Join-Path $ProjectRoot $relative))) {
            throw "Missing $relative in the repo root."
        }
    }
}

function Ensure-DockerNetwork {
    param([pscustomobject]$Target, [string]$NetworkName, [string]$WorkingDirectory)
    $createCommand = "docker network inspect '$NetworkName' >/dev/null 2>&1 || docker network create '$NetworkName'"
    try {
        Invoke-RemoteShell -Target $Target -Command $createCommand -WorkingDirectory $WorkingDirectory
    }
    catch {
        throw "Failed to ensure Docker network '$NetworkName': $($_.Exception.Message)"
    }
}

function Get-RemoteWorkDir {
    param([string]$ProjectRoot)
    $stackName = 'dogan-webui'
    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.remoteWorkDir) { return ([string]$manifest.remoteWorkDir).TrimEnd('/') }
    if ($manifest -and $manifest.stackName) { $stackName = [string]$manifest.stackName }
    return "/cloud-admin/docker/$stackName"
}

function Get-RemoteComposeEnvironmentPrefix {
    param(
        [string]$NetworkName,
        [string]$ApiBaseUrl,
        [bool]$PublishHostPorts,
        [string]$PublishPort,
        [string]$VolumeDir
    )
    $safeVolumeDir = ($VolumeDir -replace '\\', '/').TrimEnd('/')
    $prefix = "DOCKER_NETWORK='$NetworkName' VITE_API_BASE_URL='$ApiBaseUrl' VOLUME_DIR='$safeVolumeDir' "
    if ($PublishHostPorts) {
        $prefix += "WEB_PUBLISH_PORT='$PublishPort' "
    }
    else {
        $prefix += "WEB_PUBLISH_PORT='' "
    }
    return $prefix
}

function Invoke-ComposeStack {
    param(
        [pscustomobject]$Target,
        [string]$WorkingDirectory,
        [bool]$RemoveVolumes,
        [bool]$RemoveImages,
        [string]$NetworkName,
        [string]$ApiBaseUrl,
        [bool]$PublishHostPorts,
        [string]$PublishPort,
        [string]$VolumeDir
    )

    $downFlag = if ($RemoveVolumes) { ' -v' } else { '' }
    $rmiFlag = if ($RemoveImages) { ' --rmi local' } else { '' }
    $composeDown = "docker compose -p dogan-webui -f $Script:ComposeFile down$rmiFlag$downFlag"
    $composeUp = "docker compose -p dogan-webui -f $Script:ComposeFile up -d"

    try {
        Invoke-RemoteShell -Target $Target -Command $composeDown -WorkingDirectory $WorkingDirectory
    }
    catch {
        Write-Host "Compose down skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    $envPrefix = Get-RemoteComposeEnvironmentPrefix -NetworkName $NetworkName -ApiBaseUrl $ApiBaseUrl -PublishHostPorts:$PublishHostPorts -PublishPort $PublishPort -VolumeDir $VolumeDir
    Invoke-RemoteShell -Target $Target -Command "${envPrefix}$composeUp" -WorkingDirectory $WorkingDirectory
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
    $target = Resolve-SshTarget -SshString $sshStringValue

    $deleteImageRaw = if ($cliArgs.ContainsKey('delete_image')) { [string]$cliArgs['delete_image'] } elseif (-not [string]::IsNullOrWhiteSpace($DeleteImage)) { $DeleteImage } else { $null }
    $deleteVolumeRaw = if ($cliArgs.ContainsKey('delete_volume')) { [string]$cliArgs['delete_volume'] } elseif (-not [string]::IsNullOrWhiteSpace($DeleteVolume)) { $DeleteVolume } else { $null }
    $removeImages = Test-Truthy -Value $deleteImageRaw
    $removeVolumes = Test-Truthy -Value $deleteVolumeRaw

    $reverseProxyRaw = if ($cliArgs['reverse_proxy']) { [string]$cliArgs['reverse_proxy'] } elseif (-not [string]::IsNullOrWhiteSpace($ReverseProxy)) { $ReverseProxy } else { $null }
    $reverseProxyMode = Test-ReverseProxyMode -Value $reverseProxyRaw
    $publishHostPorts = $reverseProxyMode -in @('none', 'direct', 'off')

    $domainValue = if ($cliArgs['domain']) { [string]$cliArgs['domain'] } elseif (-not [string]::IsNullOrWhiteSpace($DomainName)) { $DomainName } else { $null }
    $domainValue = Normalize-CliParameterValue -Name 'domain' -Value $domainValue

    $publicPortRaw = if ($cliArgs['public_port']) { [string]$cliArgs['public_port'] } elseif (-not [string]::IsNullOrWhiteSpace($PublicPort)) { $PublicPort } else { $null }
    $publicPortValue = if (-not [string]::IsNullOrWhiteSpace($publicPortRaw)) { $publicPortRaw } else { '443' }
    Test-PortNumber -Value $publicPortValue -ParameterName '--public-port'

    $portRaw = if ($cliArgs['internal_port']) { [string]$cliArgs['internal_port'] } elseif (-not [string]::IsNullOrWhiteSpace($InternalPort)) { $InternalPort } else { $null }
    if ($publishHostPorts) {
        $internalPortValue = if (-not [string]::IsNullOrWhiteSpace($portRaw)) { $portRaw } else { [string](Get-RandomFreePort) }
        Test-PortNumber -Value $internalPortValue -ParameterName '--internal-port'
        $containerRoutePort = '80'
        $publishPort = $internalPortValue
    }
    else {
        $internalPortValue = if (-not [string]::IsNullOrWhiteSpace($portRaw)) { $portRaw } else { '80' }
        Test-PortNumber -Value $internalPortValue -ParameterName '--internal-port'
        $containerRoutePort = $internalPortValue
        $publishPort = ''
    }

    $volumeDirRaw = if ($cliArgs['volume_dir']) { [string]$cliArgs['volume_dir'] } elseif (-not [string]::IsNullOrWhiteSpace($VolumeDir)) { $VolumeDir } else { $null }
    $volumeNameRaw = if ($cliArgs['volume_name']) { [string]$cliArgs['volume_name'] } elseif (-not [string]::IsNullOrWhiteSpace($VolumeName)) { $VolumeName } else { $null }
    $networkRaw = if ($cliArgs['network_name']) { [string]$cliArgs['network_name'] } elseif (-not [string]::IsNullOrWhiteSpace($NetworkName)) { $NetworkName } else { $null }
    $resolvedVolumeDir = Resolve-VolumeDir -Override $volumeDirRaw -ContainerName $containerName
    $resolvedVolumeName = Resolve-VolumeName -Override $volumeNameRaw -ContainerName $containerName
    $resolvedNetwork = Resolve-NetworkName -ProjectRoot $ProjectRoot -Override $networkRaw -ContainerName $containerName

    $apiOverride = if ($cliArgs['api_base_url']) { [string]$cliArgs['api_base_url'] } elseif (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) { $ApiBaseUrl } else { $null }
    $resolvedApi = Resolve-ApiBaseUrl -ProjectRoot $ProjectRoot -OverrideValue $apiOverride

    $workDir = Get-RemoteWorkDir -ProjectRoot $ProjectRoot
    $imageTag = Get-StackImageTag -ProjectRoot $ProjectRoot
    $stackManifest = Get-StackManifest -ProjectRoot $ProjectRoot
    $stackName = if ($stackManifest -and $stackManifest.stackName) { [string]$stackManifest.stackName } else { 'dogan-webui' }
    $webContainerName = $containerName

    $totalSteps = if ([string]::IsNullOrWhiteSpace($domainValue)) { 8 } else { 9 }
    $proxyLabel = if ($publishHostPorts) { "host port $publishPort" } else { 'sslh (docker network only)' }

    Write-Host ("Target: ssh {0} | network: {1} | api: {2} | domain: {3} | proxy: {4} | volumes: {5} | images: {6}" -f `
        $target.SshAlias, $resolvedNetwork, $resolvedApi, `
        $(if ($domainValue) { $domainValue } else { 'none' }), $proxyLabel, `
        $(if ($removeVolumes) { 'delete' } else { 'keep' }), `
        $(if ($removeImages) { 'delete' } else { 'keep' })) -ForegroundColor Cyan

    Write-RunStep -Step 1 -Total $totalSteps -Message 'Checking Docker files and local CLI'
    Test-DockerComposeFile -ProjectRoot $ProjectRoot
    & docker version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker CLI is not available or not running locally.' }

    Write-RunStep -Step 2 -Total $totalSteps -Message 'Building web image locally'
    $createImageScript = Join-Path $ProjectRoot 'create-image.ps1'
    if (Test-Path $createImageScript) {
        & $createImageScript --api-base-url=$resolvedApi
        if ($LASTEXITCODE -ne 0) { throw 'create-image.ps1 failed.' }
    }
    else {
        Push-Location $ProjectRoot
        try {
            $env:VITE_API_BASE_URL = $resolvedApi
            & docker compose -p dogan-webui -f $Script:ComposeFile build
            if ($LASTEXITCODE -ne 0) { throw "docker compose build failed (exit $LASTEXITCODE)" }
        }
        finally { Pop-Location }
    }

    Write-RunStep -Step 3 -Total $totalSteps -Message "Syncing compose files to ssh $($target.SshAlias)"
    Sync-DeployFilesToRemote -Target $target -LocalRoot $ProjectRoot -RemotePath $workDir

    Write-RunStep -Step 4 -Total $totalSteps -Message 'Transferring images to remote host'
    Transfer-DockerImagesToRemote -Target $target -ImageTags @($imageTag) -RemotePath $workDir -StackName $stackName

    Write-RunStep -Step 5 -Total $totalSteps -Message 'Checking remote Docker'
    Invoke-RemoteShell -Target $target -Command 'docker version'

    Write-RunStep -Step 6 -Total $totalSteps -Message "Ensuring volume dir '$resolvedVolumeDir'"
    Ensure-RemoteVolumeDir -Target $target -Path $resolvedVolumeDir

    Write-RunStep -Step 7 -Total $totalSteps -Message "Ensuring Docker network '$resolvedNetwork'"
    Ensure-DockerNetwork -Target $target -NetworkName $resolvedNetwork -WorkingDirectory $workDir

    Write-RunStep -Step 8 -Total $totalSteps -Message $(if ($removeVolumes) { 'Recreating stack (volumes removed)' } else { 'Recreating stack (keeping volumes)' })
    Invoke-ComposeStack -Target $target -WorkingDirectory $workDir -RemoveVolumes:$removeVolumes -RemoveImages:$removeImages -NetworkName $resolvedNetwork -ApiBaseUrl $resolvedApi -PublishHostPorts:$publishHostPorts -PublishPort $publishPort -VolumeDir $resolvedVolumeDir

    if (-not [string]::IsNullOrWhiteSpace($domainValue)) {
        Write-RunStep -Step 9 -Total $totalSteps -Message "Mapping domain '$domainValue' to $webContainerName"
        Set-DomainReverseProxyMapping -Target $target -DomainName $domainValue -WebContainerName $webContainerName -ContainerPort $containerRoutePort -HttpsPort $publicPortValue -ReverseProxyMode $reverseProxyMode -StackNetworkName $resolvedNetwork -WebImageTag $imageTag -VolumeDir $resolvedVolumeDir
    }

    Write-Progress -Activity 'dogan-webui remote Docker' -Completed -Status 'Done'
    Write-Host ''
    Write-Host "Stack is running on remote host at $workDir (network: $resolvedNetwork)." -ForegroundColor Green
    Write-Host ("Images were built locally and deployed to {0} without a remote build." -f $target.SshAlias) -ForegroundColor Green
    Write-Host "  API (build-time): $resolvedApi" -ForegroundColor Green
    Write-Host "  Volume dir:       $resolvedVolumeDir" -ForegroundColor Green
    Write-Host "  Volume name:      $resolvedVolumeName" -ForegroundColor Green
    if ($publishHostPorts) {
        Write-Host "  Host port:        $publishPort" -ForegroundColor Green
    }
    if (-not [string]::IsNullOrWhiteSpace($domainValue)) {
        Write-Host "  URL:              https://${domainValue}/" -ForegroundColor Green
    }
}
catch {
    Write-Progress -Activity 'dogan-webui remote Docker' -Completed -Status 'Failed'
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Show-Help
    exit 1
}
