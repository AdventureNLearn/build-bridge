# Build Bridge OFF (Windows): stop both watchers, the listener, the Build session for
# <PROJECT_DIR>, and the tab host, so the Windows Terminal tab closes. Touches nothing else.
# Tab fix: the launcher runs Build inside bb-build-tab.ps1, which always exits 0. Under the
# Windows Terminal default closeOnExit ("automatic"/"graceful"), a tab whose process exits 0 closes.
# Before, Build was the tab's own process and a forced stop exited non-zero, so the tab stayed open.
param([string]$ProjectDir = "<PROJECT_DIR>")
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Continue"
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
# Stop each matched pid; a pid that already exited is skipped quietly (no Stop-Process error).
function Stop-List($list) {
    $stopped = @()
    foreach ($p in @($list)) {
        if ($null -eq $p) { continue }
        $id = [int]$p.ProcessId
        $alive = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($null -ne $alive) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
        $stopped += $id
    }
    $stopped   # unrolled on purpose; callers collect with @()
}
$w = @(foreach ($n in @("bb-watch-outbox.ps1", "bb-watch-inbox.ps1", "bb-listen.ps1", "bb-pickup.ps1")) { Stop-List @(Get-BBProcs $n) })
# End Build: its process exits, then the tab host sees it gone and exits 0.
$g = @(Stop-List @(Get-BBBuild $ProjectDir))
Start-Sleep -Seconds 3
# Fallback: if the tab host is still alive, stop it gently. Windows Terminal may then show
# "process exited"; say so, and the person closes that one tab by hand.
$h = @(Get-BBProcs "bb-build-tab.ps1")
$hostLeft = @($h).Count -gt 0
if ($hostLeft) { [void](Stop-List $h) }
Write-Output ("stopped watchers/listener: {0}; build: {1}; tab-host-forced: {2}" -f @($w).Count, @($g).Count, $hostLeft)
& (Join-Path $BBRoot "bin\bb-status.ps1") -ProjectDir $ProjectDir
