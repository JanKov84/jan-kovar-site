param([Parameter(ValueFromRemainingArguments = $true)][string[]] $PnpmArgs)
$ErrorActionPreference = 'Stop'
$siteRoot = Split-Path $PSScriptRoot -Parent
$pnpmCli = Join-Path $siteRoot '.tools/pnpm/bin/pnpm.cjs'
if (-not (Test-Path -LiteralPath $pnpmCli)) { throw 'Run scripts/setup.ps1 first.' }
$nodeCommand = Get-Command node -CommandType Application -ErrorAction SilentlyContinue
if (-not $nodeCommand) { throw 'Node.js 24 must be available on PATH. A portable installation is sufficient.' }

# Use the Windows trusted certificate store without changing TLS verification.
$previousSystemCA = [Environment]::GetEnvironmentVariable('NODE_USE_SYSTEM_CA', 'Process')
$pnpmExitCode = 1
Push-Location -LiteralPath $siteRoot
try {
    [Environment]::SetEnvironmentVariable('NODE_USE_SYSTEM_CA', '1', 'Process')
    & $nodeCommand.Source $pnpmCli @PnpmArgs
    $pnpmExitCode = $LASTEXITCODE
}
finally {
    [Environment]::SetEnvironmentVariable('NODE_USE_SYSTEM_CA', $previousSystemCA, 'Process')
    Pop-Location
}
exit $pnpmExitCode
