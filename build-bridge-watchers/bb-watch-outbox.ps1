# Build Bridge outbound watcher (Windows). Verifies each new job once.
# Good job -> one "ACTION_REQUIRED job <id>" line in logs\wake.log for Build's listener.
# Bad job  -> moved to rejected\ with a .reason file. Never runs a job itself.
# Pattern from the proven reference pattern (named mutex, 5 s loop, trace log).
# Unpicked-job alert: a verified job still in outbox\ more than BB_UNPICKED_MIN minutes (default 15; 0 = off) after it
# was first verified, with no done\<id>.job, no inbox\<id>.reply and no inbox\<id>.needs-approval, gets exactly ONE
# wake ping (same webhook and same body as bb-watch-inbox; no job content, id or path). State: state\unpicked-alert.txt
# (tab-separated lines "S<TAB><base64 UTF-8 job name><TAB><first-verified UTC ticks>" and "A<TAB><base64 job name>";
# base64 so any legal file name, with spaces, unicode or long, round-trips), rewritten atomically under state\unpicked-alert.lock.
# Mark-before-send: before any ping, a per-job marker state\alerted\<sha256 of job name>.pinged is created (CreateNew). The state-file
# code never rewrites or deletes markers, so the "pinged" record survives loss or corruption of unpicked-alert.txt.
# No marker written = no ping. Markers are removed only after their job has left outbox\ (picked, done or rejected).
# Missing state file while outbox-seen.txt already lists jobs (upgrade or state loss), or an unreadable/corrupt state
# file: every job then in outbox\ gets its first-verified time reset to NOW (no ping now); if still unpicked more than
# BB_UNPICKED_MIN minutes later it gets one ping. A job that has a marker is treated as pinged and never pinged again.
param([switch]$AllowUnsigned)
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Continue"
$bb = $BBRoot
$bin = Join-Path $bb "bin"
$seenPath = Join-Path $bb "state\outbox-seen.txt"
$wake = Join-Path $bb "logs\wake.log"
$trace = Join-Path $bb "logs\watch-outbox.log"
$alertPath = Join-Path $bb "state\unpicked-alert.txt"
$alertLock = Join-Path $bb "state\unpicked-alert.lock"
$markDir = Join-Path $bb "state\alerted"
$cfgPath = Join-Path $BBKeysRoot "webhook.json"
$unpickedMin = 15
if ($env:BB_UNPICKED_MIN -match '^\d{1,5}$') { $unpickedMin = [int]$env:BB_UNPICKED_MIN }
$isTest = ($env:BB_TEST -eq "1")
$utf8 = New-Object System.Text.UTF8Encoding $false
$created = $false
$mutex = New-Object System.Threading.Mutex($false, "Local\BuildBridge-outbox", [ref]$created)
if (-not $mutex.WaitOne(0)) { exit 0 }
function Write-Trace([string]$m) { [System.IO.File]::AppendAllText($trace, ((Get-Date).ToString("o") + " " + $m + "`r`n"), $utf8) }
function Move-Reject([System.IO.FileInfo]$f, [string]$reason) {
    $dest = Join-Path $bb ("rejected\" + $f.Name)
    if (Test-Path -LiteralPath $dest) { $dest = $dest + "." + (Get-Date -Format "yyyyMMddHHmmss") }
    Move-Item -LiteralPath $f.FullName -Destination $dest -Force
    [System.IO.File]::WriteAllText($dest + ".reason", $reason + "`r`n", $utf8)
    Write-Trace ("REJECT " + $f.Name + " " + $reason)
}
# Test hooks work only with BB_TEST=1 (which already refuses the live BB_HOME): BB_TEST_NOW = fake UTC clock
# (ISO 8601), BB_TEST_ONCE=1 = run one loop pass and exit. Real runs ignore both.
function Get-NowUtc {
    if ($isTest -and $env:BB_TEST_NOW) { return [DateTime]::Parse($env:BB_TEST_NOW, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal) }
    return [DateTime]::UtcNow
}
function Send-Wake {   # same sender and body as bb-watch-inbox.ps1; one attempt, no retry
    if (-not (Test-Path -LiteralPath $cfgPath)) { Write-Trace "WEBHOOK_NOT_SET"; return 0 }
    try { $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json } catch { Write-Trace "WEBHOOK_NOT_SET"; return 0 }
    $url = [string]$cfg.url; $key = [string]$cfg.key
    $name = if ($cfg.header) { [string]$cfg.header } else { "Authorization" }
    $value = if ($name -eq "Authorization") { "Bearer " + $key } else { $key }
    if (-not $url -or -not $key) { Write-Trace "WEBHOOK_NOT_SET"; return 0 }
    $code = 0
    try {
        $r = Invoke-WebRequest -Uri $url -Method Post -Headers @{ $name = $value } -Body '{"event":"ACTION_REQUIRED","source":"buildbridge"}' -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 20
        $code = [int]$r.StatusCode
    } catch { if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch { $code = 0 } } }
    Write-Trace ("WEBHOOK " + $code)
    return $code
}
# Writer lock, same style as the share writer: CreateNew, keep the bytes written, delete only if still ours.
$script:lockBytes = $null
function Enter-AlertLock {
    $b = $utf8.GetBytes(([string]$PID) + " " + [guid]::NewGuid().ToString("N"))
    for ($n = 0; $n -lt 2; $n++) {
        try {
            $fs = [System.IO.File]::Open($alertLock, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try { $fs.Write($b, 0, $b.Length) } finally { $fs.Close() }
            $script:lockBytes = $b; return $true
        } catch {
            # Only this watcher (single instance by mutex) writes the state, so a lock whose process is gone is stale.
            $owner = 0
            try { $owner = [int](([System.IO.File]::ReadAllText($alertLock)) -split ' ')[0] } catch { $owner = 0 }
            if ($owner -gt 0 -and $owner -ne $PID -and (Get-Process -Id $owner -ErrorAction SilentlyContinue)) { Write-Trace "LOCK-BUSY"; return $false }
            Remove-Item -LiteralPath $alertLock -Force -ErrorAction SilentlyContinue; Write-Trace "LOCK-STALE-REMOVED"
        }
    }
    Write-Trace "LOCK-BUSY"; return $false
}
function Exit-AlertLock {
    try {
        $now = [System.IO.File]::ReadAllBytes($alertLock)
        if ($script:lockBytes -and ([Convert]::ToBase64String($now) -eq [Convert]::ToBase64String($script:lockBytes))) { Remove-Item -LiteralPath $alertLock -Force }
        else { Write-Trace "LOCK-NOT-OURS" }
    } catch { Write-Trace "LOCK-NOT-OURS" }
    $script:lockBytes = $null
}
# Job names are stored base64 (UTF-8) so any legal name round-trips; markers are named by the name's SHA-256.
function ConvertTo-B64([string]$t) { return [Convert]::ToBase64String($utf8.GetBytes($t)) }
function ConvertFrom-B64([string]$t) { return $utf8.GetString([Convert]::FromBase64String($t)) }
function Get-MarkName([string]$t) {
    $h = [System.Security.Cryptography.SHA256]::Create()
    try { return (([BitConverter]::ToString($h.ComputeHash($utf8.GetBytes($t)))) -replace '-', '').ToLowerInvariant() + ".pinged" } finally { $h.Dispose() }
}
function Save-AlertState([System.Collections.Specialized.OrderedDictionary]$first, [hashtable]$alerted) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($k in $first.Keys) { [void]$sb.Append("S`t" + (ConvertTo-B64 $k) + "`t" + $first[$k] + "`r`n") }
    foreach ($k in $alerted.Keys) { [void]$sb.Append("A`t" + (ConvertTo-B64 $k) + "`r`n") }
    $tmp = $alertPath + ".tmp"
    [System.IO.File]::WriteAllText($tmp, $sb.ToString(), $utf8)
    if (Test-Path -LiteralPath $alertPath) { [System.IO.File]::Replace($tmp, $alertPath, [NullString]::Value) } else { [System.IO.File]::Move($tmp, $alertPath) }
}
function Invoke-UnpickedCheck([hashtable]$seen) {
    if ($unpickedMin -le 0) { return }
    if (-not (Enter-AlertLock)) { return }
    try {
        $now = Get-NowUtc
        $first = New-Object System.Collections.Specialized.OrderedDictionary
        $alerted = @{}
        $baseline = $false; $dirty = $false
        if (Test-Path -LiteralPath $alertPath) {
            try {
                foreach ($l in [System.IO.File]::ReadAllLines($alertPath)) {
                    if (-not $l) { continue }
                    if ($l -match '^S\t([A-Za-z0-9+/=]+)\t(\d{1,19})$') { $first[(ConvertFrom-B64 $Matches[1])] = [long]$Matches[2] }
                    elseif ($l -match '^A\t([A-Za-z0-9+/=]+)$') { $alerted[(ConvertFrom-B64 $Matches[1])] = $true }
                    else { throw "bad line" }
                }
            } catch {
                $bad = $alertPath + ".corrupt-" + $now.ToString("yyyyMMddHHmmss")
                Move-Item -LiteralPath $alertPath -Destination $bad -Force -ErrorAction SilentlyContinue
                Write-Trace "STATE-CORRUPT kept-as-corrupt-copy"
                $first = New-Object System.Collections.Specialized.OrderedDictionary; $alerted = @{}; $baseline = $true
            }
        } else { $dirty = $true; if ($seen.Count -gt 0) { $baseline = $true; Write-Trace "STATE-MISSING" } }
        $jobs = @(Get-ChildItem -LiteralPath (Join-Path $bb "outbox") -Filter "*.job" -File | Where-Object { $seen.ContainsKey($_.Name) })
        if ($baseline) {
            # Restart each waiting job's clock at NOW: no ping now, one ping if still unpicked later.
            foreach ($j in $jobs) { $first[$j.Name] = $now.Ticks }
            Write-Trace ("ALERT-CLOCK-RESTART " + @($jobs).Count); $dirty = $true
        }
        $present = @{}
        $allOut = @{}
        foreach ($o in @(Get-ChildItem -LiteralPath (Join-Path $bb "outbox") -Filter "*.job" -File)) { $allOut[(Get-MarkName $o.Name)] = $o.Name }
        # Durable markers win over the state file (they survive its loss or corruption).
        if (Test-Path -LiteralPath $markDir -PathType Container) {
            foreach ($m in @(Get-ChildItem -LiteralPath $markDir -Filter "*.pinged" -File | Where-Object { $_.Name -cmatch '^[0-9a-f]{64}\.pinged$' })) {
                if ($allOut.ContainsKey($m.Name)) { $jn = $allOut[$m.Name]; if (-not $alerted.ContainsKey($jn)) { $alerted[$jn] = $true; $dirty = $true } }
                else { Remove-Item -LiteralPath $m.FullName -Force -ErrorAction SilentlyContinue; Write-Trace "MARKER-CLEANED" }
            }
        }
        foreach ($j in $jobs) {
            $present[$j.Name] = $true
            if (-not $first.Contains($j.Name)) { $first[$j.Name] = $now.Ticks; $dirty = $true }
        }
        # Forget jobs that left the outbox (picked, done or rejected) so the state file stays small.
        foreach ($k in @($first.Keys)) { if (-not $present.ContainsKey($k)) { $first.Remove($k); $dirty = $true } }
        foreach ($k in @($alerted.Keys)) { if (-not $present.ContainsKey($k)) { $alerted.Remove($k); $dirty = $true } }
        $due = @(); $send = @()
        foreach ($j in $jobs) {
            if ($alerted.ContainsKey($j.Name)) { continue }
            $id = $j.BaseName
            if (Test-Path -LiteralPath (Join-Path $bb ("done\" + $j.Name))) { continue }
            if (Test-Path -LiteralPath (Join-Path $bb ("inbox\" + $id + ".reply"))) { continue }
            if (Test-Path -LiteralPath (Join-Path $bb ("inbox\" + $id + ".needs-approval"))) { continue }
            $age = $now - (New-Object DateTime ([long]$first[$j.Name]), ([DateTimeKind]::Utc))
            if ($age.TotalSeconds -gt ($unpickedMin * 60)) { $due += $j }
        }
        $send = @()
        foreach ($j in $due) {
            # Marker first (atomic CreateNew). If it can't be written, do not ping.
            try {
                if (-not (Test-Path -LiteralPath $markDir -PathType Container)) { [void](New-Item -ItemType Directory -Path $markDir -ErrorAction Stop) }
                $fs = [System.IO.File]::Open((Join-Path $markDir (Get-MarkName $j.Name)), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $fs.Close()
                $alerted[$j.Name] = $true; $dirty = $true; $send += $j
            } catch { Write-Trace ("MARKER-FAIL no-ping " + $j.BaseName) }
        }
        if ($dirty) { Save-AlertState $first $alerted }
    } finally { Exit-AlertLock }
    # Marked (and saved) before sending: if the save failed we never get here, so nothing is sent.
    foreach ($j in $send) { Write-Trace ("UNPICKED-ALERT " + $j.BaseName); [void](Send-Wake) }
}
if (-not (Test-Path -LiteralPath $seenPath)) { [System.IO.File]::WriteAllText($seenPath, "", $utf8) }
# Startup pass (before any new job is verified): creates the state file, or baselines jobs seen before this version.
try {
    $seen0 = @{}
    foreach ($l in [System.IO.File]::ReadAllLines($seenPath)) { if ($l) { $seen0[$l] = $true } }
    Invoke-UnpickedCheck $seen0
} catch { Write-Trace ("ALERT-ERROR " + $_.Exception.GetType().Name) }
Write-Trace "ENTER-LOOP"
while ($true) {
    try {
        $seen = @{}
        foreach ($l in [System.IO.File]::ReadAllLines($seenPath)) { if ($l) { $seen[$l] = $true } }
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $bb "outbox") -Filter "*.job" -File)) {
            if ($seen.ContainsKey($f.Name)) { continue }
            if (Test-Path -LiteralPath (Join-Path $bb ("done\" + $f.Name))) { Move-Reject $f "DUPLICATE"; continue }
            $verifyArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $bin "bb-verify.ps1"), "-File", $f.FullName)
            if ($AllowUnsigned) { $verifyArgs += "-AllowUnsigned" }
            $out = (& powershell.exe @verifyArgs) -join " "
            if ($LASTEXITCODE -ne 0) { Move-Reject $f ($out -replace '^REJECT ', ''); continue }
            [System.IO.File]::AppendAllText($seenPath, $f.Name + "`r`n", $utf8)
            [System.IO.File]::AppendAllText($wake, ((Get-Date).ToString("o") + " ACTION_REQUIRED job " + $f.BaseName + "`r`n"), $utf8)
            Write-Trace ("WAKE " + $f.BaseName)
            # Pickup: an open, idle Build session can't be woken from here, so bb-pickup runs a job only when
            # no session is open (and only if auto pickup is on). It runs detached, so this loop keeps going.
            Start-Process -FilePath (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ('"' + (Join-Path $bin "bb-pickup.ps1") + '"'), "-Run") -WindowStyle Hidden
        }
    } catch { Write-Trace ("LOOP-ERROR " + $_.Exception.GetType().Name) }
    try {
        $seen = @{}
        foreach ($l in [System.IO.File]::ReadAllLines($seenPath)) { if ($l) { $seen[$l] = $true } }
        Invoke-UnpickedCheck $seen
    } catch { Write-Trace ("ALERT-ERROR " + $_.Exception.GetType().Name) }
    if ($isTest -and $env:BB_TEST_ONCE -eq "1") { break }
    Start-Sleep -Seconds 5
}
