# Build Bridge ON (Windows): start both watchers hidden; optionally start Build too.
# From the proven reference pattern. A second start is harmless (each watcher holds a mutex).
param([switch]$WithBuild, [switch]$AllowUnsigned)
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
# Test mode: the before-scan must already be saved (scan.ps1 -Save 1), or the rollback drill has nothing to compare with.
if ($env:BB_TEST -eq "1" -and -not (Test-Path -LiteralPath (Join-Path ($BBRoot + "-scans") "scan-1.txt"))) { Write-Output ("TEST-REFUSED: no before-scan at " + (Join-Path ($BBRoot + "-scans") "scan-1.txt") + ". Run scan.ps1 -Save 1 first."); exit 4 }
# Shared helpers (name check, deny-list, session check) live in bb-common.ps1: installed next to this script,
# or in build-bridge-signing in the package layout.
$bbc = Join-Path $PSScriptRoot "bb-common.ps1"
if (-not (Test-Path -LiteralPath $bbc)) { $bbc = [System.IO.Path]::Combine($PSScriptRoot, "..", "build-bridge-signing", "bb-common.ps1") }
. $bbc
$ErrorActionPreference = "Continue"
$bin = Join-Path $BBRoot "bin"
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
foreach ($name in @("bb-watch-outbox.ps1", "bb-watch-inbox.ps1")) {
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ('"' + (Join-Path $bin $name) + '"'))
    if ($AllowUnsigned -and $name -eq "bb-watch-outbox.ps1") { $a += "-AllowUnsigned" }
    Start-Process -FilePath $ps -ArgumentList $a -WindowStyle Hidden
}
if ($WithBuild) {
    $tn = Get-BBTaskName
    if ($null -eq $tn) { Write-Output "WITH-BUILD REFUSED: test mode needs BB_TASK_NAME set to a TEST task name (contains 'test', never the live name)" }
    else {
        & schtasks.exe /Run /TN $tn | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Output ("WITH-BUILD started task: " + $tn) } else { Write-Output ("WITH-BUILD FAILED task: " + $tn + " exit " + $LASTEXITCODE) }
    }
}
Start-Sleep -Seconds 3
& (Join-Path $bin "bb-status.ps1")
