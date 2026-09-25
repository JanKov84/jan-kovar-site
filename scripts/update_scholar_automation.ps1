Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$updaterPath = Join-Path $PSScriptRoot 'update_scholar_local.R'
$scholarPath = 'data/citations/scholar.json'

function Stop-WithCode {
    param(
        [Parameter(Mandatory = $true)][int]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    [Console]::Error.WriteLine("ERROR {0}: {1}" -f $Code, $Message)
    exit $Code
}

function Get-GitOutput {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    try {
        $lines = @(& git -C $repoRoot @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
        return [pscustomobject]@{ ExitCode = $code; Lines = $lines }
    }
    catch {
        return [pscustomobject]@{ ExitCode = 127; Lines = @($_.Exception.Message) }
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    Stop-WithCode 12 "Could not locate the Git repository from script path '$PSScriptRoot'."
}

$branchResult = Get-GitOutput -Arguments @('branch', '--show-current')
if ($branchResult.ExitCode -ne 0) {
    Stop-WithCode 12 "Could not determine the current Git branch. $($branchResult.Lines -join ' ')"
}
$branch = ($branchResult.Lines -join '').Trim()
if ($branch -ne 'main') {
    Stop-WithCode 10 "Expected branch 'main'; found '$branch'. No update was run."
}

$statusResult = Get-GitOutput -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
if ($statusResult.ExitCode -ne 0) {
    Stop-WithCode 12 "Could not inspect Git status. $($statusResult.Lines -join ' ')"
}
$initialChanges = @($statusResult.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($initialChanges.Count -gt 0) {
    Stop-WithCode 11 "Working tree is not clean. No update was run. Git status: $($initialChanges -join ' | ')"
}

Write-Output "Scholar automation repository: $repoRoot"
Write-Output 'Branch and working tree preflight passed.'

$rscriptPath = $null
$rscriptCommand = Get-Command Rscript.exe -ErrorAction SilentlyContinue
if ($null -ne $rscriptCommand) {
    $commandPath = $rscriptCommand.Source
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        $commandPath = $rscriptCommand.Path
    }
    if (-not [string]::IsNullOrWhiteSpace($commandPath) -and
        (Test-Path -LiteralPath $commandPath -PathType Leaf)) {
        $rscriptPath = $commandPath
    }
}

if ($null -eq $rscriptPath) {
    $installRoot = Join-Path $env:ProgramFiles 'R'
    $rCandidates = @(
        Get-ChildItem -LiteralPath $installRoot -Directory -Filter 'R-*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                $versionText = $_.Name.Substring(2)
                $version = $null
                $candidate = Join-Path $_.FullName 'bin\x64\Rscript.exe'
                if ([version]::TryParse($versionText, [ref]$version) -and
                    (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                    [pscustomobject]@{ Version = $version; Path = $candidate }
                }
            }
    )
    if ($rCandidates.Count -gt 0) {
        $rscriptPath = ($rCandidates | Sort-Object Version -Descending | Select-Object -First 1).Path
    }
}

if ($null -eq $rscriptPath) {
    Stop-WithCode 13 'Rscript.exe was not found on PATH or under C:\Program Files\R\R-*\bin\x64.'
}
Write-Output "Using Rscript: $rscriptPath"

Write-Output 'Synchronizing with origin/main using fast-forward only.'
$pullResult = Get-GitOutput -Arguments @('pull', '--ff-only', 'origin', 'main')
$pullResult.Lines | ForEach-Object { Write-Output $_ }
if ($pullResult.ExitCode -ne 0) {
    Stop-WithCode 20 'git pull --ff-only origin main failed. No Scholar update was run.'
}

if (-not (Test-Path -LiteralPath $updaterPath -PathType Leaf)) {
    Stop-WithCode 21 "Scholar updater was not found at '$updaterPath'."
}

Write-Output 'Running the local Scholar updater.'
Push-Location $repoRoot
try {
    & $rscriptPath $updaterPath
    $rscriptExitCode = $LASTEXITCODE
}
catch {
    Pop-Location
    Stop-WithCode 30 "Could not run the Scholar updater: $($_.Exception.Message)"
}
Pop-Location
if ($rscriptExitCode -ne 0) {
    Stop-WithCode 30 "Scholar updater failed with exit code $rscriptExitCode. No files were staged or committed."
}

$updatedStatus = Get-GitOutput -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
if ($updatedStatus.ExitCode -ne 0) {
    Stop-WithCode 31 "Could not inspect Git status after the Scholar update. $($updatedStatus.Lines -join ' ')"
}
$changedLines = @($updatedStatus.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$changedPaths = @(
    $changedLines | ForEach-Object {
        if ($_.Length -ge 4) { $_.Substring(3).Trim('"') }
        else { $_ }
    }
)
$unexpectedPaths = @($changedPaths | Where-Object { $_ -ne $scholarPath })
if ($unexpectedPaths.Count -gt 0) {
    Stop-WithCode 32 "Unexpected files changed; nothing was staged or committed: $($unexpectedPaths -join ', ')"
}

if ($changedPaths.Count -eq 0) {
    Write-Output 'Scholar metrics unchanged; nothing to commit.'
    exit 0
}

Write-Output 'Staging only data/citations/scholar.json.'
$stageResult = Get-GitOutput -Arguments @('add', '--', $scholarPath)
$stageResult.Lines | ForEach-Object { Write-Output $_ }
if ($stageResult.ExitCode -ne 0) {
    Stop-WithCode 40 'Could not stage data/citations/scholar.json.'
}

$stagedResult = Get-GitOutput -Arguments @('diff', '--cached', '--name-only')
if ($stagedResult.ExitCode -ne 0 -or
    $stagedResult.Lines.Count -ne 1 -or
    $stagedResult.Lines[0].Trim() -ne $scholarPath) {
    Stop-WithCode 41 'Staged file verification failed; refusing to commit.'
}

Write-Output 'Committing Scholar metrics.'
$commitResult = Get-GitOutput -Arguments @('commit', '-m', 'chore(citations): update Scholar metrics')
$commitResult.Lines | ForEach-Object { Write-Output $_ }
if ($commitResult.ExitCode -ne 0) {
    Stop-WithCode 42 'Could not commit the Scholar metrics update.'
}

Write-Output 'Pushing the Scholar metrics commit to origin/main.'
$pushResult = Get-GitOutput -Arguments @('push', 'origin', 'main')
$pushResult.Lines | ForEach-Object { Write-Output $_ }
if ($pushResult.ExitCode -ne 0) {
    Stop-WithCode 43 'Could not push the Scholar metrics commit to origin/main.'
}

Write-Output 'Scholar metrics commit pushed successfully.'
exit 0
