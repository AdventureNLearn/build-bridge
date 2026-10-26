# Build Bridge step 6 undo (Windows). Same rule whether AGENTS.md existed before install (a buildbridge-backup file)
# or Build Bridge created it (a buildbridge-none marker):
# 1. Check the markers first: exactly one BEGIN line and one END line, in that order, unchanged. Otherwise STOP,
#    change nothing and delete nothing (AGENTS.md, the backup or marker and the folder stay as they were).
# 2. Save the current AGENTS.md aside as AGENTS.md.before-bb-remove-<stamp>.
# 3. Remove only the lines from the BEGIN marker through the END marker (inclusive); every other byte (line endings,
#    encoding) is kept. If Build Bridge created the file and it is empty (only blank lines or spaces are left), delete AGENTS.md.
# 4. Delete the install-time backup or marker. The pre-install backup is never copied over AGENTS.md.
# -CheckOnly: run only the step 1 checks, change nothing, print CHECK-OK (exit 0) or STOP: <why> (exit 3).
#   bb-rollback.ps1 runs this first, before it stops or moves anything.
param([Parameter(Mandatory = $true)][string]$ProjectDir, [switch]$CheckOnly)
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
$ag = Join-Path $ProjectDir "AGENTS.md"
$b = Get-ChildItem -LiteralPath $ProjectDir -Filter "AGENTS.md.buildbridge-*" -File | Sort-Object Name -Descending | Select-Object -First 1
if (-not $b) { Write-Output "NOTHING-TO-UNDO"; exit 0 }
$created = ($b.Name -like "*buildbridge-none-*")
# Empty = only blank lines or spaces are left: only space (U+0020), CR and LF count; a tab or any other character keeps the file. This one line is the whole definition; for 0 bytes use: $s.Length -eq 0
function Test-BBEmpty([string]$s) { return (($s -replace '[ \r\n]','').Length -eq 0) }
function Stop-BB([string]$why) {
    Write-Output ("STOP: " + $why + " Nothing was changed or deleted: AGENTS.md, " + $b.Name + " and the folder are as they were. Remove the Build Bridge section by hand, or fix the markers and run this again.")
    exit 3
}
if (-not (Test-Path -LiteralPath $ag -PathType Leaf)) { Stop-BB "AGENTS.md is missing, so there is no Build Bridge section to remove." }
$bytes = [System.IO.File]::ReadAllBytes($ag)
# Pick the encoding from the BOM; no BOM means UTF-8. The text must round-trip to the same bytes, or we stop.
$pre = 0
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $enc = New-Object System.Text.UTF8Encoding $false, $true; $pre = 3 }
elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $enc = New-Object System.Text.UnicodeEncoding $false, $false, $true; $pre = 2 }
elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $enc = New-Object System.Text.UnicodeEncoding $true, $false, $true; $pre = 2 }
else { $enc = New-Object System.Text.UTF8Encoding $false, $true }
try { $text = $enc.GetString($bytes, $pre, $bytes.Length - $pre) } catch { Stop-BB "AGENTS.md is not valid text in its own encoding." }
$back = $enc.GetBytes($text)
if ($back.Length -ne ($bytes.Length - $pre)) { Stop-BB "AGENTS.md would not keep its exact bytes." }
for ($i = 0; $i -lt $back.Length; $i++) { if ($back[$i] -ne $bytes[$i + $pre]) { Stop-BB "AGENTS.md would not keep its exact bytes." } }
# Split into lines, each keeping its own line ending.
$lines = [regex]::Split($text, '(?<=\n)')
$beginM = "<!-- BEGIN BUILD BRIDGE -->"; $endM = "<!-- END BUILD BRIDGE -->"
$bi = @(); $ei = @(); $odd = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    $t = $lines[$i].TrimEnd("`r", "`n")
    if ($t -ceq $beginM) { $bi += $i } elseif ($t -ceq $endM) { $ei += $i }
    elseif ($t -match '(?i)(BEGIN|END)\s*BUILD\s*BRIDGE') { $odd++ }
}
if ($odd -gt 0) { Stop-BB "a Build Bridge marker line was changed (it no longer matches '$beginM' or '$endM' exactly)." }
if (@($bi).Count -ne 1) { Stop-BB ("expected exactly one '" + $beginM + "' line, found " + @($bi).Count + ".") }
if (@($ei).Count -ne 1) { Stop-BB ("expected exactly one '" + $endM + "' line, found " + @($ei).Count + ".") }
if ($ei[0] -le $bi[0]) { Stop-BB "the END marker comes before the BEGIN marker." }
if ($CheckOnly) { Write-Output ("CHECK-OK AGENTS.md has exactly one Build Bridge section; nothing was changed. (" + $b.Name + ")"); exit 0 }
# All checks passed. Only now is anything changed.
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$aside = $ag + ".before-bb-remove-" + $stamp
if (Test-Path -LiteralPath $aside) { Stop-BB ("the save-aside name " + $aside + " already exists.") }
Copy-Item -LiteralPath $ag -Destination $aside
Write-Output ("SAVED-ASIDE " + $aside)
$sb = New-Object System.Text.StringBuilder
for ($i = 0; $i -lt $lines.Count; $i++) { if ($i -lt $bi[0] -or $i -gt $ei[0]) { [void]$sb.Append($lines[$i]) } }
$outBody = $enc.GetBytes($sb.ToString())
$out = New-Object byte[] ($pre + $outBody.Length)
for ($i = 0; $i -lt $pre; $i++) { $out[$i] = $bytes[$i] }
[Array]::Copy($outBody, 0, $out, $pre, $outBody.Length)
$rest = $sb.ToString()
if ($created -and (Test-BBEmpty $rest)) {
    # Build Bridge created AGENTS.md and it is empty (only blank lines or spaces left): delete it (its copy was saved above).
    Remove-Item -LiteralPath $ag
    Write-Output "AGENTS-MD-DELETED (Build Bridge created it and only blank lines or spaces were left)"
} else {
    $tmp = $ag + ".bb-remove-tmp-" + $stamp
    [System.IO.File]::WriteAllBytes($tmp, $out)
    Move-Item -LiteralPath $tmp -Destination $ag -Force
    Write-Output "RULE-REMOVED (only the Build Bridge section; every other line kept)"
}
# Only after a successful removal: delete the install-time backup or marker.
Remove-Item -LiteralPath $b.FullName
Write-Output ("INSTALL-COPY-DELETED " + $b.Name)
