# Build Bridge launcher (Windows). Opens ONE Build session for <PROJECT_DIR> in a Windows Terminal
# tab, unless one is already running. Does not approve tools or bypass permissions.
# From the proven reference pattern: one quoted argument string for wt.exe.
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Continue"
$ProjectDir = "<PROJECT_DIR>"
# Process matching is scoped to THIS user's session and owner, and to the full installed path,
# so another user's (or another install's) Build Bridge processes are never counted or stopped.
$script:BBBin = Join-Path $BBRoot "bin"
$script:BBSession = (Get-Process -Id $PID).SessionId
$script:BBMe = $env:USERNAME
function Test-BBMine($p) {
    if ($p.SessionId -ne $script:BBSession) { return $false }
    $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue
    return ($o -and $o.User -eq $script:BBMe)
}
function Get-BBProcs([string]$Script) {
    # Output is unrolled; callers MUST collect with @(Get-BBProcs ...) before .Count (one match would be a scalar).
    $full = Join-Path $script:BBBin $Script
    @(Get-CimInstance Win32_Process -Filter "SessionId=$($script:BBSession)" -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($full, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and (Test-BBMine $_) })
}
function Get-BBBuild([string]$Dir) {
    @(Get-CimInstance Win32_Process -Filter "Name='grok.exe' AND SessionId=$($script:BBSession)" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -like "*--cwd*" -and $_.CommandLine.IndexOf($Dir, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and (Test-BBMine $_) })
}
$running = @(Get-BBBuild $ProjectDir)
if (@($running).Count -gt 0) { Write-Output "ALREADY-RUNNING. Nothing opened."; exit 0 }
$grok = Join-Path $env:USERPROFILE ".grok\bin\grok.exe"
if (-not (Test-Path -LiteralPath $grok)) { $c = Get-Command grok -ErrorAction SilentlyContinue; if ($c) { $grok = $c.Source } else { Write-Output "Grok Build not found. Nothing opened."; exit 1 } }
$wt = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"
if (-not (Test-Path -LiteralPath $wt)) { $c = Get-Command wt.exe -ErrorAction SilentlyContinue; if ($c) { $wt = $c.Source } else { $wt = $null } }
if (-not $wt) { Write-Output "Windows Terminal was not found. Nothing opened."; exit 1 }
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$tabHost = Join-Path $BBRoot "bin\bb-build-tab.ps1"
$wtArgs = "new-tab --title `"Grok Build`" --startingDirectory `"$ProjectDir`" -- `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$tabHost`" -ProjectDir `"$ProjectDir`" -Grok `"$grok`""
Start-Process -FilePath $wt -ArgumentList $wtArgs
Write-Output "LAUNCHED"
