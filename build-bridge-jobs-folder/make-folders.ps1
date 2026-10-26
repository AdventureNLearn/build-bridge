# Build Bridge step 2 (Windows). Creates the jobs folder. Safe to rerun.
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
# Test mode: the before-scan must already be saved (scan.ps1 -Save 1), or the rollback drill has nothing to compare with.
if ($env:BB_TEST -eq "1" -and -not (Test-Path -LiteralPath (Join-Path ($BBRoot + "-scans") "scan-1.txt"))) { Write-Output ("TEST-REFUSED: no before-scan at " + (Join-Path ($BBRoot + "-scans") "scan-1.txt") + ". Run scan.ps1 -Save 1 first."); exit 4 }
$ErrorActionPreference = "Stop"
$bb = $BBRoot
foreach ($s in @("", "outbox", "inbox", "done", "rejected", "bin", "state", "logs", "keys-public")) {
    $p = if ($s) { Join-Path $bb $s } else { $bb }
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}
(Get-Item -LiteralPath $bb -Force).Attributes = (Get-Item -LiteralPath $bb -Force).Attributes -bor [System.IO.FileAttributes]::Hidden
$missing = @("outbox", "inbox", "done", "rejected") | Where-Object { -not (Test-Path -LiteralPath (Join-Path $bb $_)) }
if ($missing) { Write-Output ("FOLDERS-FAILED " + ($missing -join ",")); exit 1 }
Write-Output "FOLDERS-OK"
