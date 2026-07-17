<#
.SYNOPSIS
    Build the parkiroid-web Docker image from the repo Dockerfile.

.DESCRIPTION
    Project-agnostic image build. Resolves image name/tag from .docker/stack.manifest.json
    or package.json when flags are omitted. Supports --help / -h / /?.

.EXAMPLE
    .\create-image.ps1

.EXAMPLE
    .\create-image.ps1 --tag=1.2.3

.EXAMPLE
    .\create-image.ps1 --image-name=parkiroid-web --tag=latest --api-base-url=http://api.example.com/dogan/api/v1
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Alias('image-name')]
    [string]$ImageName,
    [Alias('tag')]
    [string]$ImageTag,
    [Alias('dockerfile')]
    [string]$DockerfilePath,
    [Alias('context')]
    [string]$BuildContext,
    [Alias('api-base-url')]
    [string]$ApiBaseUrl,
    [Alias('h')]
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:DefaultApiBaseUrl = 'http://localhost:8080/dogan/api/v1'
$Script:ContainerName = 'parkiroid-web'

function Show-Help {
    Write-Host @"
create-image.ps1 — build $Script:ContainerName Docker image

USAGE:
  .\create-image.ps1 [flags]

FLAGS:
  --image-name=<name>        Image repository name (default: null → from manifest / $Script:ContainerName)
  --tag=<tag>                Image tag (default: null → from package.json version or latest)
  --dockerfile=<path>        Dockerfile path (default: null → ./Dockerfile)
  --context=<path>           Build context directory (default: null → script directory)
  --api-base-url=<url>       VITE_API_BASE_URL build arg (default: null → .env or $Script:DefaultApiBaseUrl)
  --help, -h, /?             Show this help

EXAMPLES:
  .\create-image.ps1
  .\create-image.ps1 --tag=1.0.0
  .\create-image.ps1 --image-name=parkiroid-web --tag=latest --api-base-url=http://api.example.com/dogan/api/v1

NOTES:
  - Null defaults resolve as described in FLAGS.
  - Requires Docker CLI and a Dockerfile in the build context.
  - Run scripts call this when a rebuild is needed.
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

function Get-StackManifest {
    param([string]$ProjectRoot)
    $manifestPath = Join-Path $ProjectRoot '.docker/stack.manifest.json'
    if (-not (Test-Path $manifestPath)) { return $null }
    return Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
}

function Resolve-ImageName {
    param([string]$ProjectRoot, [string]$Override)
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }

    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.webImageTag) {
        $parts = ([string]$manifest.webImageTag).Split(':', 2)
        if ($parts.Count -ge 1 -and $parts[0]) { return $parts[0] }
    }
    if ($manifest -and $manifest.stackName) { return [string]$manifest.stackName }
    if ($manifest -and $manifest.containerName) { return [string]$manifest.containerName }
    return $Script:ContainerName
}

function Resolve-ImageTag {
    param([string]$ProjectRoot, [string]$Override)
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return $Override.Trim() }

    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.webImageTag) {
        $parts = ([string]$manifest.webImageTag).Split(':', 2)
        if ($parts.Count -eq 2 -and $parts[1]) { return $parts[1] }
    }

    $packageJson = Join-Path $ProjectRoot 'package.json'
    if (Test-Path $packageJson) {
        $pkg = Get-Content -Path $packageJson -Raw | ConvertFrom-Json
        if ($pkg.version) { return [string]$pkg.version }
    }
    return 'latest'
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

try {
    $cliArgs = Merge-CliArguments -BoundParameters $PSBoundParameters -RemainingArguments $RemainingArguments
    if ($Help -or $cliArgs['help'] -or ($RemainingArguments -match '^(--help|-h|/\?)$')) {
        Show-Help
        exit 0
    }

    $ProjectRoot = $PSScriptRoot
    $resolvedName = Resolve-ImageName -ProjectRoot $ProjectRoot -Override $(if ($cliArgs['image_name']) { [string]$cliArgs['image_name'] } else { $ImageName })
    $tagOverride = if ($cliArgs['tag']) { [string]$cliArgs['tag'] } elseif ($cliArgs['image_tag']) { [string]$cliArgs['image_tag'] } elseif (-not [string]::IsNullOrWhiteSpace($ImageTag)) { $ImageTag } else { $null }
    $resolvedTag = Resolve-ImageTag -ProjectRoot $ProjectRoot -Override $tagOverride
    $resolvedDockerfile = if ($cliArgs['dockerfile']) { [string]$cliArgs['dockerfile'] } elseif ($cliArgs['dockerfile_path']) { [string]$cliArgs['dockerfile_path'] } elseif (-not [string]::IsNullOrWhiteSpace($DockerfilePath)) { $DockerfilePath } else { 'Dockerfile' }
    $resolvedContext = if ($cliArgs['context']) { [string]$cliArgs['context'] } elseif ($cliArgs['build_context']) { [string]$cliArgs['build_context'] } elseif (-not [string]::IsNullOrWhiteSpace($BuildContext)) { $BuildContext } else { $ProjectRoot }
    $apiOverride = if ($cliArgs['api_base_url']) { [string]$cliArgs['api_base_url'] } elseif (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) { $ApiBaseUrl } else { $null }
    $resolvedApi = Resolve-ApiBaseUrl -ProjectRoot $ProjectRoot -OverrideValue $apiOverride
    $fullImage = "${resolvedName}:${resolvedTag}"

    $dockerfilePath = if ([System.IO.Path]::IsPathRooted($resolvedDockerfile)) {
        $resolvedDockerfile
    }
    else {
        Join-Path $resolvedContext $resolvedDockerfile
    }
    if (-not (Test-Path $dockerfilePath)) {
        throw "Missing Dockerfile at '$dockerfilePath'."
    }

    Write-Host "[1/2] Checking Docker CLI..." -ForegroundColor Yellow
    & docker version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker CLI is not available or not running.' }

    Write-Host "[2/2] Building $fullImage (VITE_API_BASE_URL=$resolvedApi)..." -ForegroundColor Yellow
    & docker build `
        --build-arg "VITE_API_BASE_URL=$resolvedApi" `
        -f $dockerfilePath `
        -t $fullImage `
        $resolvedContext
    if ($LASTEXITCODE -ne 0) { throw "docker build failed (exit $LASTEXITCODE)" }

    # Also tag as :latest when building a version tag so compose defaults keep working
    $latestTag = "${resolvedName}:latest"
    if ($resolvedTag -ne 'latest') {
        & docker tag $fullImage $latestTag
        if ($LASTEXITCODE -ne 0) { throw "docker tag failed (exit $LASTEXITCODE)" }
    }

    Write-Host ''
    Write-Host "Done: $fullImage" -ForegroundColor Green
    if ($resolvedTag -ne 'latest') {
        Write-Host "Also tagged: $latestTag" -ForegroundColor Green
    }
}
catch {
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Show-Help
    exit 1
}
