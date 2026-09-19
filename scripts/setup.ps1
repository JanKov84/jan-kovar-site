# Run from PowerShell: ./scripts/setup.ps1
# Installs portable, pinned tools and project dependencies inside this checkout.
$ErrorActionPreference = 'Stop'
$siteRoot = Split-Path $PSScriptRoot -Parent
$toolsRoot = Join-Path $siteRoot '.tools'
$downloadsRoot = Join-Path $toolsRoot 'downloads'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitOperatingSystem) {
    throw 'This setup script requires 64-bit Windows.'
}

$nodeCommand = Get-Command node -CommandType Application -ErrorAction SilentlyContinue
$gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
$tarCommand = Get-Command tar -CommandType Application -ErrorAction SilentlyContinue
if (-not $nodeCommand) { throw 'Make Node.js 24 available on PATH, then rerun setup. A portable installation is sufficient.' }
if (-not $gitCommand) { throw 'Git must be installed and available on PATH.' }
if (-not $tarCommand) { throw 'Windows tar.exe must be available on PATH to extract pnpm.' }
$nodeVersion = & $nodeCommand.Source --version
if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v24\.') {
    throw "Node.js 24 is required; the current version is '$nodeVersion'."
}

function Test-ArchiveChecksum {
    param([string] $Archive, [string] $Algorithm, [string] $Expected, [switch] $Base64)
    if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) { return $false }
    $hasher = [Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    $stream = [IO.File]::OpenRead($Archive)
    try {
        $digest = $hasher.ComputeHash($stream)
        if ($Base64) { $actual = [Convert]::ToBase64String($digest) }
        else { $actual = [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant() }
        return $actual -ceq $Expected
    }
    finally {
        $stream.Dispose()
        $hasher.Dispose()
    }
}

function Get-VerifiedArchive {
    param([string] $Url, [string] $FileName, [string] $Algorithm, [string] $Expected, [switch] $Base64)
    $archive = Join-Path $downloadsRoot $FileName
    if (-not (Test-ArchiveChecksum $archive $Algorithm $Expected -Base64:$Base64)) {
        Write-Host "Downloading $FileName..."
        Invoke-WebRequest -Uri $Url -OutFile $archive -UseBasicParsing
    }
    if (-not (Test-ArchiveChecksum $archive $Algorithm $Expected -Base64:$Base64)) {
        throw "Checksum verification failed for '$archive'. Nothing from this archive was extracted."
    }
    return $archive
}

function Test-HugoVersion {
    param([string] $Executable)
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return $false }
    $version = & $Executable version
    return $LASTEXITCODE -eq 0 -and $version -match '^hugo v0\.162\.0(?:[-+][^ ]*)?\+extended(?: |\+)' -and $version -match 'windows/amd64'
}

function Test-GoVersion {
    param([string] $Executable)
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return $false }
    $version = & $Executable version
    return $LASTEXITCODE -eq 0 -and $version -eq 'go version go1.27.1 windows/amd64'
}

function Test-PnpmVersion {
    param([string] $Cli)
    if (-not (Test-Path -LiteralPath $Cli -PathType Leaf)) { return $false }
    $version = & $nodeCommand.Source $Cli --version
    return $LASTEXITCODE -eq 0 -and $version -eq '10.14.0'
}

New-Item -ItemType Directory -Path $downloadsRoot -Force | Out-Null
$hugoRoot = Join-Path $toolsRoot 'hugo'
$hugoExecutable = Join-Path $hugoRoot 'hugo.exe'
if (-not (Test-HugoVersion $hugoExecutable)) {
    $archive = Get-VerifiedArchive `
        -Url 'https://github.com/gohugoio/hugo/releases/download/v0.162.0/hugo_extended_0.162.0_windows-amd64.zip' `
        -FileName 'hugo_extended_0.162.0_windows-amd64.zip' -Algorithm 'SHA256' `
        -Expected '93d4198aba296e6ac7b3213ad24371524d7a32d249eb5110b086f94510372285'
    New-Item -ItemType Directory -Path $hugoRoot -Force | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $hugoRoot -Force
    if (-not (Test-HugoVersion $hugoExecutable)) { throw 'Hugo Extended 0.162.0 could not be verified after extraction.' }
}

$goExecutable = Join-Path $toolsRoot 'go/bin/go.exe'
if (-not (Test-GoVersion $goExecutable)) {
    $archive = Get-VerifiedArchive `
        -Url 'https://go.dev/dl/go1.27.1.windows-amd64.zip' `
        -FileName 'go1.27.1.windows-amd64.zip' -Algorithm 'SHA256' `
        -Expected 'a3911b5e0e1b1053f25ed0675f4c1c6aad1e2bfcf253df2b9be4caabd2edd95d'
    # The official archive already contains its top-level go directory.
    Expand-Archive -LiteralPath $archive -DestinationPath $toolsRoot -Force
    if (-not (Test-GoVersion $goExecutable)) { throw 'Go 1.27.1 could not be verified after extraction.' }
}

$pnpmRoot = Join-Path $toolsRoot 'pnpm'
$pnpmCli = Join-Path $pnpmRoot 'bin/pnpm.cjs'
if (-not (Test-PnpmVersion $pnpmCli)) {
    $archive = Get-VerifiedArchive `
        -Url 'https://registry.npmjs.org/pnpm/-/pnpm-10.14.0.tgz' `
        -FileName 'pnpm-10.14.0.tgz' -Algorithm 'SHA512' -Base64 `
        -Expected 'rSenlkG0nD5IGhaoBbqnGBegS74Go40X5g4urug/ahRsamiBJfV5LkjdW6MOfaUqXNpMOZK5zPMz+c4iOvhHSA=='
    New-Item -ItemType Directory -Path $pnpmRoot -Force | Out-Null
    & $tarCommand.Source -xzf $archive -C $pnpmRoot --strip-components=1
    if ($LASTEXITCODE -ne 0) { throw 'pnpm archive extraction failed.' }
    if (-not (Test-PnpmVersion $pnpmCli)) { throw 'pnpm 10.14.0 could not be verified after extraction.' }
}

# Append a process-only Git setting, preserving any existing numbered settings.
$gitConfigCountText = [Environment]::GetEnvironmentVariable('GIT_CONFIG_COUNT', 'Process')
$gitConfigCount = 0
if ($null -ne $gitConfigCountText -and $gitConfigCountText -ne '') {
    if (-not [int]::TryParse($gitConfigCountText, [ref] $gitConfigCount) -or $gitConfigCount -lt 0 -or $gitConfigCount -eq [int]::MaxValue) {
        throw 'GIT_CONFIG_COUNT must be a nonnegative integer smaller than Int32.MaxValue.'
    }
}
$gitConfigKey = "GIT_CONFIG_KEY_$gitConfigCount"
$gitConfigValue = "GIT_CONFIG_VALUE_$gitConfigCount"
$environmentNames = @('NODE_USE_SYSTEM_CA', 'GOPATH', 'GOMODCACHE', 'GOCACHE', 'GIT_CONFIG_COUNT', $gitConfigKey, $gitConfigValue)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

Push-Location -LiteralPath $siteRoot
try {
    [Environment]::SetEnvironmentVariable('NODE_USE_SYSTEM_CA', '1', 'Process')
    [Environment]::SetEnvironmentVariable('GOPATH', (Join-Path $siteRoot '.cache/go'), 'Process')
    [Environment]::SetEnvironmentVariable('GOMODCACHE', (Join-Path $siteRoot '.cache/go/pkg/mod'), 'Process')
    [Environment]::SetEnvironmentVariable('GOCACHE', (Join-Path $siteRoot '.cache/go-build'), 'Process')
    [Environment]::SetEnvironmentVariable($gitConfigKey, 'http.sslBackend', 'Process')
    [Environment]::SetEnvironmentVariable($gitConfigValue, 'schannel', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT', [string] ($gitConfigCount + 1), 'Process')

    Write-Host 'Installing locked JavaScript dependencies...'
    & $nodeCommand.Source $pnpmCli install --frozen-lockfile --store-dir .cache/pnpm-store
    if ($LASTEXITCODE -ne 0) { throw 'pnpm dependency installation failed.' }

    # Run Go directly: Hugo does not preserve every environment setting for it.
    Write-Host 'Downloading pinned Hugo modules...'
    & $goExecutable mod download all
    if ($LASTEXITCODE -ne 0) { throw 'Go module download failed.' }
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
    Pop-Location
}

Write-Host 'Local setup is ready. Preview with ./scripts/pnpm.ps1 dev'
