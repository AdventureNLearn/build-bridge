# Build Bridge step 2 undo (Windows). Moves the folder aside; deletes nothing.
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
$bb = $BBRoot
if (-not (Test-Path -LiteralPath $bb)) { Write-Output "NOTHING-TO-UNDO"; exit 0 }
$dest = $bb + "-removed-" + (Get-Date -Format "yyyyMMdd-HHmmss")
Move-Item -LiteralPath $bb -Destination $dest
Write-Output ("MOVED-TO " + $dest)
