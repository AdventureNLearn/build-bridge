# Build Bridge step 6 (Windows): back up AGENTS.md, then append the Build Bridge block.
param([Parameter(Mandatory = $true)][string]$ProjectDir)
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
$ag = Join-Path $ProjectDir "AGENTS.md"
$block = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "startup-rule-block.md")).Replace("<USER_HOME>\.buildbridge", $BBRoot).Replace("<USER_HOME>", $env:USERPROFILE)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$utf8 = New-Object System.Text.UTF8Encoding $false
if (Test-Path -LiteralPath $ag) {
    if (Select-String -LiteralPath $ag -SimpleMatch "BEGIN BUILD BRIDGE" -Quiet) { Write-Output "RULE-ALREADY-THERE (nothing changed)"; exit 0 }
    Copy-Item -LiteralPath $ag -Destination ($ag + ".buildbridge-backup-" + $stamp)
    $old = [System.IO.File]::ReadAllText($ag)
    [System.IO.File]::WriteAllText($ag, $old.TrimEnd() + "`r`n`r`n" + $block, $utf8)
} else {
    [System.IO.File]::WriteAllText(($ag + ".buildbridge-none-" + $stamp), "", $utf8)
    [System.IO.File]::WriteAllText($ag, $block, $utf8)
}
Write-Output "RULE-ADDED"
