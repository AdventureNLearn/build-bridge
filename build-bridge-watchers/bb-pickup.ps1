# Build Bridge pickup (Windows). Runs a job when NO Build session is open, because an open, idle
# session cannot be woken by a background process (KNOWN ISSUE, see build-bridge-watchers SKILL.md).
# Usage: bb-pickup.ps1 -Enable | -Disable | -Status | -Run | -AllowAuto | -DisallowAuto | -CheckCmd "<command>"
#   -AllowAuto records the person's separate YES for Grok Build --permission-mode auto (auto SKIPS shell prompts).
#   -DisallowAuto removes that record, so auto is refused again. -CheckCmd only reports ALLOWED/REFUSED for a command.
#   -Run is called by the outbox watcher after a good job. It does nothing unless auto pickup is on.
# Mode: if $OneShot is set (not the placeholder), it runs one short Build run that exits by itself.
#   <BUILD_ONESHOT_CMD> is [UNKNOWN]: put the Build CLI's real one-shot/headless command here only after
#   checking Build's own docs, with {PROMPT_FILE} where the prompt file's path goes (the prompt itself is never in the command; it is also on stdin and in BB_PROMPT_FILE). Otherwise it falls back to the
#   proven launcher task, which opens one new tab with the starting prompt.
# Approval stall [UNTESTED live]: a one-shot run with no progress (no output growth, no new file in inbox\ or done\)
#   for BB_PICKUP_STALL seconds (default 300; the right length is [UNKNOWN] until a live test; must be < BB_PICKUP_MAX_RUN,
#   default 3600), or one that reaches BB_PICKUP_MAX_RUN, is stopped (only its own process tree, this user's session only).
#   Each still-pending job gets ONE inbox\<id>.needs-approval entry, and the person gets ONE wake ping. No retry, no
#   permission change. -ClearApproval <id> removes the entry once the person has dealt with it.
# Guards: auto pickup must be on; no Build session already open for <PROJECT_DIR>; one pickup at a time (mutex).
param([switch]$Enable, [switch]$Disable, [switch]$Status, [switch]$Run, [switch]$AllowAuto, [switch]$DisallowAuto, [string]$CheckCmd = "", [string]$ClearApproval = "")
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
$ProjectDir = "<PROJECT_DIR>"
$OneShot = "<BUILD_ONESHOT_CMD>"
$bb = $BBRoot
$flag = Join-Path $bb "state\autopickup.on"
$trace = Join-Path $bb "logs\pickup.log"
$utf8 = New-Object System.Text.UTF8Encoding $false
function Write-Trace([string]$m) { [System.IO.File]::AppendAllText($trace, ((Get-Date).ToString("o") + " " + $m + "`r`n"), $utf8) }
$autoYes = $script:BBAutoYes
# -AllowAuto is for the PERSON only, typed in their own terminal (like bb-set-webhook). A job, a Build session or a
# Build Bridge launched process can never record it: those are refused below.
if ($AllowAuto) {
    $why = Test-BBLaunchedSession
    if ($why) { "REFUSED allow-auto: this is a Build or Build Bridge launched session ($why). Run it yourself in your own terminal."; exit 5 }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or -not [Environment]::UserInteractive) { "REFUSED allow-auto: needs an interactive terminal. Run it yourself in your own terminal."; exit 5 }
    "Auto mode lets Grok Build run shell commands with NO prompt and NO approval from you, for Build Bridge pickup runs."
    $ans = Read-Host "Type I ALLOW AUTO to confirm (anything else cancels)"
    if ($ans -cne "I ALLOW AUTO") { "NOT-CONFIRMED (nothing recorded)"; exit 1 }
    $body = $script:BBAutoMark + "`r`ntime=" + (Get-Date).ToString("o") + "`r`ntext=the person typed the confirmation; --permission-mode auto skips shell prompts`r`n"
    if (-not (New-BBAutoKey)) { "REFUSED allow-auto: the keys folder is missing (do step 3 first), or the HMAC keys owner-only ACL could not be set or verified. Nothing recorded."; exit 5 }
    [System.IO.File]::WriteAllText($autoYes, $body, $utf8)
    [System.IO.File]::WriteAllText($script:BBAutoMac, (Get-BBHmacHex $script:BBAutoKey $autoYes))
    "PERMISSION-AUTO-YES-RECORDED"; exit 0
}
if ($DisallowAuto) { foreach ($f in @($autoYes, $script:BBAutoMac)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f } }; "PERMISSION-AUTO-OFF"; exit 0 }
if ($CheckCmd) { $r = Test-BBCmd $CheckCmd; $r; if ($r -eq "ALLOWED") { exit 0 } else { exit 3 } }
if ($ClearApproval) {
    # PERSON ONLY, after their YES. Build, a job or a launched session must never run it (refused below).
    # Checks: id is letters/digits/- only; the entry exists; it removes only inbox\<id>.needs-approval, nothing else.
    $why = Test-BBLaunchedSession
    if ($why) { "REFUSED clear-approval: this is a Build or Build Bridge launched session ($why). The person runs it in their own terminal."; exit 5 }
    if ($ClearApproval -notmatch '^[A-Za-z0-9-]+$') { "usage: -ClearApproval <job id> (letters, digits and - only)"; exit 1 }
    $e = Join-Path $bb ("inbox\" + $ClearApproval + ".needs-approval")
    if (-not (Test-Path -LiteralPath $e)) { "NO-ENTRY $ClearApproval (nothing removed)"; exit 1 }
    Remove-Item -LiteralPath $e; "APPROVAL-ENTRY-CLEARED $ClearApproval"; exit 0
}
if ($Enable) { [System.IO.File]::WriteAllText($flag, "on`r`n", $utf8); "AUTOPICKUP-ON"; exit 0 }
if ($Disable) { if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag }; "AUTOPICKUP-OFF"; exit 0 }
if ($Status) { if (Test-Path -LiteralPath $flag) { "autopickup: on" } else { "autopickup: off" }; if (Test-BBAutoYes) { "permission-auto: on (YES recorded)" } else { "permission-auto: off" }; exit 0 }
if (-not $Run) { "usage: -Enable | -Disable | -Status | -Run"; exit 1 }
if (-not (Test-Path -LiteralPath $flag)) { Write-Trace "SKIP autopickup-off"; exit 0 }
# Digits only and at most 6 digits BEFORE the [int] cast (so a huge value can't overflow), then 1..cap.
function Get-BBSec([string]$v, [int]$d, [int]$cap) {
    if (-not $v) { return $d }
    if ($v -notmatch '^[0-9]{1,6}$') { return -1 }
    $n = [int]$v; if ($n -lt 1 -or $n -gt $cap) { return -1 }; return $n
}
$maxRun = Get-BBSec $env:BB_PICKUP_MAX_RUN 3600 604800
$stall = Get-BBSec $env:BB_PICKUP_STALL 300 86400     # seconds without progress = approval stall; right length [UNKNOWN] until a live test
$poll = Get-BBSec $env:BB_PICKUP_POLL 5 86400
if ($maxRun -lt 1 -or $stall -lt 1 -or $poll -lt 1) { Write-Trace "REFUSED BB_PICKUP_MAX_RUN (1..604800) / BB_PICKUP_STALL (1..86400) / BB_PICKUP_POLL (1..86400) must be whole seconds in range"; "REFUSED BB_PICKUP_MAX_RUN / BB_PICKUP_STALL / BB_PICKUP_POLL out of range or not whole seconds"; exit 3 }
if ($stall -ge $maxRun) { Write-Trace "REFUSED BB_PICKUP_STALL ($stall) must be less than BB_PICKUP_MAX_RUN ($maxRun)"; "REFUSED BB_PICKUP_STALL must be less than BB_PICKUP_MAX_RUN"; exit 3 }
# Jobs still pending = outbox\<id>.job not yet in done\. A job with an open needs-approval entry waits for a person.
function Get-BBPending { @(Get-ChildItem -LiteralPath (Join-Path $bb "outbox") -Filter "*.job" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName } | Where-Object { -not (Test-Path -LiteralPath (Join-Path $bb ("done\" + $_ + ".job"))) }) }
$pAll = @(Get-BBPending)
$pNew = @($pAll | Where-Object { -not (Test-Path -LiteralPath (Join-Path $bb ("inbox\" + $_ + ".needs-approval"))) })
if (@($pAll).Count -gt 0 -and @($pNew).Count -eq 0) { Write-Trace "SKIP waiting-for-approval (every pending job needs a person; no retry)"; exit 0 }
$cfgPath = Join-Path $BBKeysRoot "webhook.json"
function Send-WakeOnce {   # the existing wake-only body; one attempt, no retry
    if (-not (Test-Path -LiteralPath $cfgPath)) { Write-Trace "WEBHOOK_NOT_SET"; return }
    try { $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json } catch { Write-Trace "WEBHOOK_NOT_SET"; return }
    $url = [string]$cfg.url; $key = [string]$cfg.key
    $name = if ($cfg.header) { [string]$cfg.header } else { "Authorization" }
    $value = if ($name -eq "Authorization") { "Bearer " + $key } else { $key }
    if (-not $url -or -not $key) { Write-Trace "WEBHOOK_NOT_SET"; return }
    $code = 0
    try {
        $r = Invoke-WebRequest -Uri $url -Method Post -Headers @{ $name = $value } -Body '{"event":"ACTION_REQUIRED","source":"buildbridge"}' -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 20
        $code = [int]$r.StatusCode
    } catch { if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch { $code = 0 } } }
    Write-Trace ("WEBHOOK " + $code + " (needs-approval)")
}
# ONE entry per still-pending job id (never a duplicate), then ONE ping if any entry is new.
function Write-BBNeedsApproval([string]$Why, [datetime]$Started) {
    $made = 0
    foreach ($i in @(Get-BBPending)) {
        $e = Join-Path $bb ("inbox\" + $i + ".needs-approval")
        if (Test-Path -LiteralPath $e) { continue }
        $body = "v: 3`nid: $i`nfrom: Build Bridge pickup`nstatus: needs-approval`npickup: " + $Started.ToString("o") + "`nreturned: " + (Get-Date).ToString("o") + "`n---`n" +
            "A hands-off pickup run for this job was stopped after $Why. Build was most likely waiting for an approval that nobody was there to give. Nothing was retried and the permission mode was not changed. The job is still waiting in outbox. To finish it, open Build yourself and approve, or give the separate auto YES (build-bridge-watchers step 4c). Then run: bb-pickup.ps1 -ClearApproval $i`nstop`n"
        [System.IO.File]::WriteAllText($e + ".tmp", $body.Replace("`n", "`r`n"), $utf8); Move-Item -LiteralPath ($e + ".tmp") -Destination $e
        $made++; Write-Trace "NEEDS-APPROVAL $i"
    }
    if ($made -gt 0) { Send-WakeOnce }
}
# This run's process tree only: Windows walks Win32_Process parents in this session for this user; other OSes
# (box tests only) use Process.Parent. Children are stopped before parents.
function Get-BBTree([int]$Id) {
    $kids = @()
    if ($IsWindows -eq $false) { $kids = @(Get-Process | Where-Object { $_.Parent -and $_.Parent.Id -eq $Id } | ForEach-Object { $_.Id }) }
    else {
        # Windows keeps a child's ParentProcessId after the parent dies, so a reused pid could look like a parent:
        # count a child only if it was created after the parent started. [UNTESTED live]
        $ps0 = $null; try { $ps0 = (Get-Process -Id $Id -ErrorAction Stop).StartTime } catch { }
        $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$Id AND SessionId=$($script:BBSession)" -ErrorAction SilentlyContinue | Where-Object { (Test-BBMine $_) -and ($null -eq $ps0 -or $_.CreationDate -ge $ps0) } | ForEach-Object { [int]$_.ProcessId })
    }
    foreach ($k in $kids) { Get-BBTree $k }
    $Id
}
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
# No CIM (non-Windows pwsh, box tests only): fall back to Get-Process. Windows always has CIM.
$script:BBNoCim = ($IsWindows -eq $false) -and -not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)
# Not Windows (box tests only): this user's processes with a command line, as objects shaped like Win32_Process.
function Get-BBProcsNonWin {
    $me = [Environment]::UserName
    @(Get-Process -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -eq $me -and $_.CommandLine } | ForEach-Object { [pscustomobject]@{ ProcessId = $_.Id; Name = $_.ProcessName; CommandLine = $_.CommandLine } })
}
function Get-BBProcs([string]$Script) {
    # Output is unrolled; callers MUST collect with @(Get-BBProcs ...) before .Count (one match would be a scalar).
    $full = Join-Path $script:BBBin $Script
    if ($script:BBNoCim) { return @(Get-BBProcsNonWin | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine.IndexOf($full, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }) }
    @(Get-CimInstance Win32_Process -Filter "SessionId=$($script:BBSession)" -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($full, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and (Test-BBMine $_) })
}
function Get-BBBuild([string]$Dir) {
    if ($script:BBNoCim) { return @(Get-BBProcsNonWin | Where-Object { $_.CommandLine -match '(^|[ /])grok( |$)' -and $_.CommandLine -like "*--cwd*" -and $_.CommandLine.IndexOf($Dir, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }) }
    @(Get-CimInstance Win32_Process -Filter "Name='grok.exe' AND SessionId=$($script:BBSession)" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -like "*--cwd*" -and $_.CommandLine.IndexOf($Dir, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and (Test-BBMine $_) })
}
# Watch a run until it ends, stalls or hits max run. $Alive prints the run's live pids (none = ended).
# Returns the reason ("" if it ended by itself). Progress = size of $OutFiles + number of files in inbox\ and done\.
function Watch-BBRun([scriptblock]$Alive, [string[]]$OutFiles) {
    $script:BBT0 = Get-Date; $last = $script:BBT0
    $sig = { $o = 0; foreach ($f in @($OutFiles)) { if ($f -and (Test-Path -LiteralPath $f)) { $o += (Get-Item -LiteralPath $f).Length } }; "${o}:" + @(Get-ChildItem -LiteralPath (Join-Path $bb "inbox"), (Join-Path $bb "done") -File -ErrorAction SilentlyContinue).Count }
    $prev = & $sig
    while (@(& $Alive).Count -gt 0) {
        Start-Sleep -Seconds $poll
        $now = Get-Date; $cur = & $sig
        if ($cur -ne $prev) { $prev = $cur; $last = $now }
        if (($now - $last).TotalSeconds -ge $stall) { return "no progress for $stall s" }
        if (($now - $script:BBT0).TotalSeconds -ge $maxRun) { return "the $maxRun s max run" }
    }
    return ""
}
function Stop-BBRunTrees([int[]]$Roots) {
    $all = @(); foreach ($r in @($Roots)) { $all += @(Get-BBTree $r) }
    foreach ($id in $all) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    Write-Trace ("STOPPED run tree: " + ($all -join " "))
}
$created = $false
$mutex = New-Object System.Threading.Mutex($false, "Local\BuildBridge-pickup", [ref]$created)
if (-not $mutex.WaitOne(0)) { Write-Trace "SKIP pickup-already-running"; exit 0 }
try {
    $open = @(Get-BBBuild $ProjectDir)
    if (@($open).Count -gt 0) { Write-Trace "QUEUED build-session-open (it picks the job up on its next turn)"; exit 0 }
    $prompt = "Build Bridge pickup run. Check <BB_ROOT>\outbox for jobs not yet in done. Skip any job that has an open <BB_ROOT>\inbox\<id>.needs-approval entry: it waits for the person. Verify each other job with bb-verify.ps1, act on the verified ones using the Build Bridge rule in AGENTS.md, write the replies, then exit.".Replace("<BB_ROOT>", $BBRoot).Replace("<USER_HOME>", $env:USERPROFILE)
    $env:BB_LAUNCHED = "1"; $env:BB_JOB = "pickup"   # marks runs started from here; allow-auto refuses inside them
    $chk = Test-BBCmd $OneShot
    if ($chk -ne "ALLOWED") { Write-Trace ($chk + " in BUILD_ONESHOT_CMD"); ($chk + " in BUILD_ONESHOT_CMD"); exit 3 }
    if ($OneShot -ne ("<BUILD_" + "ONESHOT_CMD>")) {
        Write-Trace "START oneshot"
        # The prompt goes in a file, never into the command string: {PROMPT_FILE} -> its path, plus stdin and BB_PROMPT_FILE.
        $pf = Join-Path $BBRoot "state\pickup-prompt.txt"
        [System.IO.File]::WriteAllText($pf, $prompt + "`r`n", $utf8); $env:BB_PROMPT_FILE = $pf
        if ((Test-BBCmd $pf) -ne "ALLOWED") { Write-Trace "REFUSED prompt file path is not on the allow-list"; "REFUSED prompt file path is not on the allow-list"; exit 3 }
        $cmd = $OneShot.Replace("{PROMPT_FILE}", '"' + $pf + '"')
        $out = Join-Path $bb "logs\pickup-run.out"; $err = $out + ".err"
        $sp = @{ WorkingDirectory = $ProjectDir; PassThru = $true; RedirectStandardInput = $pf; RedirectStandardOutput = $out; RedirectStandardError = $err }
        if ($IsWindows -eq $false) {
            # Not Windows: box tests only. Split the raw command on whitespace with
            # {PROMPT_FILE} held as a sentinel, then put the path into each element as plain text. No shell.
            $parts = @($OneShot.Replace("{PROMPT_FILE}", "BBPROMPTFILE") -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Replace("BBPROMPTFILE", $pf) })
            $sp.FilePath = $parts[0]; if (@($parts).Count -gt 1) { $sp.ArgumentList = @($parts[1..(@($parts).Count - 1)]) }
        } else { $sp.FilePath = "cmd.exe"; $sp.ArgumentList = @("/c", $cmd); $sp.WindowStyle = "Hidden" }
        $p = Start-Process @sp
        $why = Watch-BBRun { if (-not $p.HasExited) { $p.Id } } @($out, $err)
        if (-not $why) { $p.WaitForExit(); Write-Trace ("END oneshot exit " + $p.ExitCode) }
        else { Stop-BBRunTrees @($p.Id); Write-Trace "STALLED-ON-APPROVAL ($why): run stopped, nothing retried"; Write-BBNeedsApproval $why $script:BBT0 }
    } else {
        Write-Trace "START launcher-tab"
        $tn = Get-BBTaskName
        if ($null -eq $tn) { Write-Trace "REFUSED test mode needs BB_TASK_NAME (a TEST task name)"; exit 4 }
        $inboxDone = { @(Get-ChildItem -LiteralPath (Join-Path $bb "inbox"), (Join-Path $bb "done") -File -ErrorAction SilentlyContinue).Count }
        $pre = & $inboxDone
        $preHosts = @(Get-BBProcs "bb-build-tab.ps1" | ForEach-Object { [int]$_.ProcessId })
        & schtasks.exe /Run /TN $tn | Out-Null
        Write-Trace ("END launcher-tab schtasks exit " + $LASTEXITCODE)
        # Watch the tab the same way [UNTESTED live]. Its processes = this user's tab host at the full installed path
        # (<BB_ROOT>\bin\bb-build-tab.ps1) and grok.exe for <PROJECT_DIR>, scoped like bb-off (session + owner + path).
        # Build's console output is not visible here, so progress in this mode = new files in inbox\ or done\ only.
        # Wait up to BB_PICKUP_HOLD s (default 20; this also holds the lock while the tab starts) for the tab host.
        $hold = Get-BBSec $env:BB_PICKUP_HOLD 20 86400; if ($hold -lt 1) { $hold = 20 }
        # What gets stopped on a stall: ONLY the tab host(s) that appeared after this launch (recorded at first sight with
        # pid + start time + command line, re-verified before the stop) and their descendants (the grok.exe it launched and
        # its children). Never any other grok --cwd <PROJECT_DIR>, e.g. one the person opened by hand before or during.
        $newHosts = { @(Get-BBProcs "bb-build-tab.ps1" | Where-Object { $preHosts -notcontains [int]$_.ProcessId } | ForEach-Object { [int]$_.ProcessId }) }
        function Get-BBIdent([int]$Id) { try { $g = Get-Process -Id $Id -ErrorAction Stop; $c = @(Get-BBProcs "bb-build-tab.ps1" | Where-Object { [int]$_.ProcessId -eq $Id }); if (@($c).Count -eq 0) { return "" }; return ("{0}|{1}|{2}" -f $Id, $g.StartTime.ToString("o"), $c[0].CommandLine) } catch { return "" } }
        $h = 0; while (@(& $newHosts).Count -eq 0 -and $h -lt $hold) { Start-Sleep -Seconds 1; $h++ }
        $script:BBRec = @(& $newHosts | ForEach-Object { Get-BBIdent $_ } | Where-Object { $_ })
        # Live recorded hosts: same pid AND same start time AND same command line as at first sight.
        $tabPids = { @($script:BBRec | Where-Object { (Get-BBIdent ([int]($_.Split('|')[0]))) -eq $_ } | ForEach-Object { [int]($_.Split('|')[0]) }) }
        if (@($script:BBRec).Count -eq 0) {
            if ((& $inboxDone) -ne $pre) { Write-Trace "END launcher-tab session ended (finished before it was seen)" } else { Write-Trace "TAB-NOT-SEEN after $hold s" }
            exit 0
        }
        $why = Watch-BBRun $tabPids @()
        if (-not $why) { Write-Trace "END launcher-tab session ended" }
        else { Write-Trace ("TAB recorded at first sight: " + ((@($script:BBRec) | ForEach-Object { $_.Split('|')[0] }) -join " ")); Stop-BBRunTrees @(& $tabPids); Write-Trace "STALLED-ON-APPROVAL ($why): launcher tab stopped, nothing retried"; Write-BBNeedsApproval $why $script:BBT0 }
    }
} finally { $mutex.ReleaseMutex() }
