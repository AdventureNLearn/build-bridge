# Build Bridge step 7 (Windows): fill the task template and register "Build Bridge Launch" for this user.
# v1.0.1 fix: the template stores the placeholder XML-escaped (&lt;USER_HOME&gt;), so a plain text replace of
# <USER_HOME> missed it and the task ran with a literal placeholder path. This script fills both forms from
# $env:USERPROFILE, and FAILS (exit 1) if any placeholder is left before registering or in the registered task.
# Also fails if the installed bin\bb-launch.ps1 still has $ProjectDir = "<PROJECT_DIR>". No admin rights. [UNTESTED on a PC]
param([string]$ProjectDir = "")
$ErrorActionPreference = "Stop"
$TaskName = "Build Bridge Launch"
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$bin = Join-Path $BBRoot "bin"
$tpl = Join-Path $PSScriptRoot "build-bridge-launch.task.xml"
$out = Join-Path $bin "build-bridge-launch.task.xml"
$launch = Join-Path $bin "bb-launch.ps1"
$ph = '(<|&lt;)[A-Z][A-Z0-9]*_[A-Z0-9_]*(>|&gt;)'
function Fail([string]$m) { Write-Output ("TASK-INSTALL-FAIL: " + $m); exit 1 }
if (-not (Test-Path -LiteralPath $tpl)) { Fail "task template not found next to this script" }
if (-not (Test-Path -LiteralPath $launch)) { Fail "copy bb-launch.ps1 into the bin folder first" }
# bb-launch.ps1: fill <PROJECT_DIR> if -ProjectDir was given, then make sure the assignment line has no placeholder.
$lt = [System.IO.File]::ReadAllText($launch)
if ($ProjectDir) {
    if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) { Fail "-ProjectDir is not an existing folder" }
    $lt = $lt.Replace('$ProjectDir = "<PROJECT_DIR>"', ('$ProjectDir = "' + $ProjectDir.Replace('"', '') + '"'))
    [System.IO.File]::WriteAllText($launch, $lt, (New-Object System.Text.UTF8Encoding $false))
}
foreach ($l in ($lt -split "`n")) { if ($l -match '^\s*\$ProjectDir\s*=' -and $l -match '<[A-Z_]+>') { Fail "bb-launch.ps1 still has a placeholder in its `$ProjectDir line; rerun with -ProjectDir" } }
# Fill the template: both the raw and the XML-escaped form. The value is XML-escaped.
$homeDir = $env:USERPROFILE
if (-not $homeDir) { Fail "USERPROFILE is not set" }
$homeXml = [System.Security.SecurityElement]::Escape($homeDir)
$x = [System.IO.File]::ReadAllText($tpl)
$x = $x.Replace("&lt;USER_HOME&gt;", $homeXml).Replace("<USER_HOME>", $homeXml)
if ($BBRoot -ne (Join-Path $env:USERPROFILE ".buildbridge")) { $x = $x.Replace([System.Security.SecurityElement]::Escape((Join-Path $homeDir ".buildbridge")), [System.Security.SecurityElement]::Escape($BBRoot)) }
$left = @([regex]::Matches($x, $ph) | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($left.Count -gt 0) { Fail ("placeholder left in the task XML before registering: " + ($left -join ", ") + ". Nothing registered.") }
[System.IO.File]::WriteAllText($out, $x, [System.Text.Encoding]::Unicode)
$o = @(& schtasks.exe /Create /TN $TaskName /XML $out /F 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) { Fail ("schtasks /Create failed (exit " + $LASTEXITCODE + "): " + ($o -join " ; ")) }
# Check the REGISTERED task, not just the file.
$q = (@(& schtasks.exe /Query /TN $TaskName /XML 2>&1 | ForEach-Object { "$_" })) -join "`n"
if ($LASTEXITCODE -ne 0) { Fail "schtasks /Query could not read the registered task" }
$left = @([regex]::Matches($q, $ph) | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($left.Count -gt 0) { Fail ("placeholder left in the REGISTERED task: " + ($left -join ", ") + ". Remove it with: schtasks /Delete /TN `"$TaskName`" /F") }
$want = [System.Security.SecurityElement]::Escape($launch)
if ($q.IndexOf($want, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail ("the registered task action does not point at bin\bb-launch.ps1. Remove it with: schtasks /Delete /TN `"$TaskName`" /F") }
if ($q -notmatch '<Triggers\s*/>') { Fail ("the registered task has triggers. Remove it with: schtasks /Delete /TN `"$TaskName`" /F") }
Write-Output "TASK-INSTALL-OK no placeholders, action points at bin\bb-launch.ps1, no triggers"
exit 0
