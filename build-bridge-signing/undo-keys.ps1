# Build Bridge step 3 undo (Windows). Moves keys aside; deletes nothing.
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\bb-common.ps1"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (Test-Path -LiteralPath $script:BBKeys) { Move-Item -LiteralPath $script:BBKeys -Destination ($script:BBKeys + "-removed-" + $stamp) }
$pub = Join-Path $script:BBHome "keys-public\signing-public.xml"
if (Test-Path -LiteralPath $pub) { Move-Item -LiteralPath $pub -Destination ($pub + ".removed-" + $stamp) }
Write-Output "KEYS-MOVED-ASIDE"
