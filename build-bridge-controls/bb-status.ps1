# Build Bridge STATUS (Windows). Plain text, so Grok Bot can read it. Changes nothing.
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
function On([string]$name) { if (@(Get-BBProcs $name).Count -gt 0) { "on" } else { "off" } }
Write-Output ("outbox-watcher: " + (On "bb-watch-outbox.ps1"))
Write-Output ("reply-watcher: " + (On "bb-watch-inbox.ps1"))
Write-Output ("listener: " + (On "bb-listen.ps1"))
$b = @(Get-BBBuild $ProjectDir)
Write-Output ("build: " + $(if (@($b).Count -gt 0) { "on" } else { "off" }))
Write-Output ("autopickup: " + $(if (Test-Path -LiteralPath (Join-Path $BBRoot "state\autopickup.on")) { "on" } else { "off" }))
$bbc = Join-Path $PSScriptRoot "bb-common.ps1"
if (-not (Test-Path -LiteralPath $bbc)) { $bbc = [System.IO.Path]::Combine($PSScriptRoot, "..", "build-bridge-signing", "bb-common.ps1") }
. $bbc
Write-Output ("permission-auto: " + $(if (Test-BBAutoYes) { "on (YES recorded)" } else { "off" }))
Write-Output ("build-tab-host: " + (On "bb-build-tab.ps1"))
$bb = $BBRoot
foreach ($s in @("outbox", "inbox", "done", "rejected")) { Write-Output ("{0}: {1} files" -f $s, @(Get-ChildItem -LiteralPath (Join-Path $bb $s) -File -ErrorAction SilentlyContinue).Count) }
# Jobs waiting for a person: a needs-approval entry whose job is not in done\ yet.
$w = 0
foreach ($e in @(Get-ChildItem -LiteralPath (Join-Path $bb "inbox") -Filter "*.needs-approval" -File -ErrorAction SilentlyContinue)) {
    $i = $e.Name.Substring(0, $e.Name.Length - ".needs-approval".Length)
    if (Test-Path -LiteralPath (Join-Path $bb ("done\" + $i + ".job"))) { continue }
    $since = (@(Get-Content -LiteralPath $e.FullName) | Where-Object { $_ -like "returned: *" } | Select-Object -First 1)
    Write-Output ("waiting-for-approval: " + $i + " (since " + ([string]$since).Replace("returned: ", "") + ")"); $w++
}
if ($w -eq 0) { Write-Output "waiting-for-approval: none" }
