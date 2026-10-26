# Build Bridge read-only scan (Windows). Reads only. Prints no secrets.
# -Save 1: also saves the report as the before-scan <root>-scans\scan-1.txt (refuses to overwrite one).
# -Save 2: saves <root>-scans\scan-2.txt (the after-rollback scan) and compares it with scan-1: SCAN-MATCH / SCAN-DIFF.
# <root>-scans sits NEXT TO <root> (and <root>-keys), so the rollback, which moves <root> and <root>-keys aside, never moves it.
param([string]$ProjectDir = "", [ValidateSet("", "1", "2")][string]$Save = "")
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
# Shared helpers (name check, deny-list, session check) live in bb-common.ps1: installed next to this script,
# or in build-bridge-signing in the package layout.
$bbc = Join-Path $PSScriptRoot "bb-common.ps1"
if (-not (Test-Path -LiteralPath $bbc)) { $bbc = [System.IO.Path]::Combine($PSScriptRoot, "..", "build-bridge-signing", "bb-common.ps1") }
. $bbc
$ErrorActionPreference = "Continue"
if ($Save) {
    $scans = $BBRoot + "-scans"; $s1 = Join-Path $scans "scan-1.txt"; $s2 = Join-Path $scans "scan-2.txt"
    if ($Save -eq "1" -and (Test-Path -LiteralPath $s1)) { "SCAN-1-EXISTS $s1 (kept; nothing overwritten)"; exit 1 }
    if ($Save -eq "2" -and -not (Test-Path -LiteralPath $s1)) { "SCAN-1-MISSING $s1 (nothing to compare with)"; exit 1 }
    $lines = @(& $PSCommandPath -ProjectDir $ProjectDir 2>$null)
    if (@($lines | Where-Object { $_ -eq "SCAN-COMPLETE" }).Count -eq 0) { $lines; "SCAN-INCOMPLETE (nothing saved)"; exit 1 }
    New-Item -ItemType Directory -Force -Path $scans | Out-Null
    $out = if ($Save -eq "1") { $s1 } else { $s2 }
    [System.IO.File]::WriteAllLines($out, [string[]]$lines, (New-Object System.Text.UTF8Encoding $false))
    $lines; "SCAN-SAVED $out"
    if ($Save -eq "1") { exit 0 }
    # Same rules as compare-scan.ps1: both scans must name the same project (project= line), and "info: " lines are not compared.
    $a = @(Get-Content -LiteralPath $s1); $b = @(Get-Content -LiteralPath $s2)
    $pa = @($a | Where-Object { $_ -like "project=*" }); $pb = @($b | Where-Object { $_ -like "project=*" })
    if (@($pa).Count -ne 1 -or @($pb).Count -ne 1 -or $pa[0] -cne $pb[0]) { "SCAN-PROJECT-MISMATCH scan-1 " + ($pa -join ",") + " / scan-2 " + ($pb -join ","); exit 2 }
    $d = @(Compare-Object -ReferenceObject @($a | Where-Object { $_ -notlike "info: *" }) -DifferenceObject @($b | Where-Object { $_ -notlike "info: *" }) -SyncWindow 0)
    if (@($d).Count -eq 0) { "SCAN-MATCH"; exit 0 }
    "SCAN-DIFF"; $d | ForEach-Object { "{0} {1}" -f $_.SideIndicator, $_.InputObject }; exit 1
}
$home_ = $env:USERPROFILE
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
function Say([string]$k, $v) { Write-Output ("{0}: {1}" -f $k, $v) }
# project= : a hash of the project's full path (no user name in the log). Both scans must carry the same one.
$projFull = if ($ProjectDir) { [System.IO.Path]::GetFullPath($ProjectDir).TrimEnd('\', '/').ToLowerInvariant() } else { "" }
$sha = [System.Security.Cryptography.SHA256]::Create()
"project=" + (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($projFull)) | ForEach-Object { $_.ToString("x2") }) -join "")
$sha.Dispose()

Say "os" ([System.Environment]::OSVersion.VersionString)
Say "powershell" $PSVersionTable.PSVersion.ToString()
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object System.Security.Principal.WindowsPrincipal $id).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
Say "elevated-now" $admin

$wt = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"
if (-not (Test-Path -LiteralPath $wt)) { $c = Get-Command wt.exe -ErrorAction SilentlyContinue; if ($c) { $wt = $c.Source } else { $wt = $null } }
Say "windows-terminal" ([bool]$wt)

$grok = Join-Path $home_ ".grok\bin\grok.exe"
if (-not (Test-Path -LiteralPath $grok)) { $c = Get-Command grok -ErrorAction SilentlyContinue; if ($c) { $grok = $c.Source } else { $grok = $null } }
Say "grok-installed" ([bool]$grok)
if ($grok) { try { Say "grok-version" ((& $grok --version 2>$null) -join " ") } catch { Say "grok-version" "unknown" } }

# Counted (compared) = bridge-launched Builds only: a grok.exe with an ancestor whose command line runs a script from
# <root>\bin (the launcher tab host bb-build-tab.ps1 or a pickup run; both also set BB_LAUNCHED). In test mode <root> is the
# test BB_HOME, so only test-tagged runs count. The person's own Builds are "info: " lines, which the compare skips.
$script:BBAll = @{}
foreach ($q in @(Get-CimInstance Win32_Process -Filter "SessionId=$($script:BBSession)" -ErrorAction SilentlyContinue)) { $script:BBAll[[int]$q.ProcessId] = $q }
function Test-BBLaunched($p) {
    $c = $p
    for ($i = 0; $i -lt 12; $i++) {
        $par = $script:BBAll[[int]$c.ParentProcessId]
        if (-not $par) { return $false }
        if ($par.CreationDate -and $c.CreationDate -and $par.CreationDate -gt $c.CreationDate) { return $false }   # stale parent id
        if ($par.CommandLine -and $par.CommandLine.IndexOf($script:BBBin, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        $c = $par
    }
    return $false
}
$builds = @(Get-CimInstance Win32_Process -Filter "Name='grok.exe' AND SessionId=$($script:BBSession)" -ErrorAction SilentlyContinue | Where-Object { Test-BBMine $_ })
$bridgeBuilds = @($builds | Where-Object { Test-BBLaunched $_ })
Say "bridge-grok-processes" @($bridgeBuilds).Count
Say "info: own-grok-processes" (@($builds).Count - @($bridgeBuilds).Count)
if ($ProjectDir) {
  $mine = @(Get-BBBuild $ProjectDir)
  $mineBridge = @($mine | Where-Object { Test-BBLaunched $_ })
  Say "bridge-build-running-for-project" (@($mineBridge).Count -gt 0)
  Say "info: own-build-running-for-project" ((@($mine).Count - @($mineBridge).Count) -gt 0)
  Say "project-exists" (Test-Path -LiteralPath $ProjectDir)
  $ag = Join-Path $ProjectDir "AGENTS.md"
  Say "agents-md-exists" (Test-Path -LiteralPath $ag)
  if (Test-Path -LiteralPath $ag) { Say "agents-md-has-bb-block" ([bool](Select-String -LiteralPath $ag -SimpleMatch "BEGIN BUILD BRIDGE" -Quiet)) }
}

Say "folder .buildbridge" (Test-Path -LiteralPath $BBRoot)
Say "folder .buildbridge-keys" (Test-Path -LiteralPath $BBKeysRoot)
$bb = $BBRoot
if (Test-Path -LiteralPath $bb) {
  foreach ($s in @("outbox","inbox","done","rejected")) {
    $p = Join-Path $bb $s
    $n = if (Test-Path -LiteralPath $p) { @(Get-ChildItem -LiteralPath $p -File).Count } else { "missing" }
    Say ("files " + $s) $n
  }
}

$tn = Get-BBTaskName
if ($null -eq $tn) { Say "task-name" "REFUSED (test mode needs BB_TASK_NAME)"; $task = $null } else { Say "task-name" $tn; $task = schtasks /Query /TN $tn 2>$null }
Say "task-build-bridge-launch" ([bool]$task)
$w = @(foreach ($n in @("bb-watch-outbox.ps1", "bb-watch-inbox.ps1", "bb-listen.ps1", "bb-pickup.ps1")) { Get-BBProcs $n })
Say "bb-watchers-running" @($w).Count
$runKeys = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
Say "sign-in-entries-mentioning-buildbridge" ([bool]($runKeys.PSObject.Properties | Where-Object { "$($_.Value)" -like "*buildbridge*" }))
Write-Output "SCAN-COMPLETE"
