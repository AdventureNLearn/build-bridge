# Build Bridge reply watcher (Windows). When new reply files appear, send ONE wake ping
# to the person's own webhook. The ping carries no job content, no ids, no paths.
# Pattern from the proven reference pattern. Logs status codes only.
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Continue"
$bb = $BBRoot
$cfgPath = Join-Path $BBKeysRoot "webhook.json"
$pingedPath = Join-Path $bb "state\inbox-pinged.txt"
$trace = Join-Path $bb "logs\watch-inbox.log"
$utf8 = New-Object System.Text.UTF8Encoding $false
$created = $false
$mutex = New-Object System.Threading.Mutex($false, "Local\BuildBridge-inbox", [ref]$created)
if (-not $mutex.WaitOne(0)) { exit 0 }
function Write-Trace([string]$m) { [System.IO.File]::AppendAllText($trace, ((Get-Date).ToString("o") + " " + $m + "`r`n"), $utf8) }
function Send-Wake {
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
# First run: replies already present count as pinged, so a restart never floods.
if (-not (Test-Path -LiteralPath $pingedPath)) {
    $names = @(Get-ChildItem -LiteralPath (Join-Path $bb "inbox") -Filter "*.reply" -File | ForEach-Object { $_.Name })
    [System.IO.File]::WriteAllText($pingedPath, (($names -join "`r`n") + "`r`n"), $utf8)
    Write-Trace ("BASELINE " + @($names).Count)
}
$tries = 0
Write-Trace "ENTER-LOOP"
while ($true) {
    Start-Sleep -Seconds 5
    try {
        $pinged = @{}
        foreach ($l in [System.IO.File]::ReadAllLines($pingedPath)) { if ($l) { $pinged[$l] = $true } }
        $new = @(Get-ChildItem -LiteralPath (Join-Path $bb "inbox") -Filter "*.reply" -File | Where-Object { -not $pinged.ContainsKey($_.Name) })
        if (@($new).Count -eq 0) { $tries = 0; continue }
        $code = Send-Wake
        $tries++
        # Mark once on success, or after 3 failed tries so one bad URL can't loop forever.
        if (($code -ge 200 -and $code -lt 300) -or $tries -ge 3) {
            [System.IO.File]::AppendAllText($pingedPath, ((($new | ForEach-Object { $_.Name }) -join "`r`n") + "`r`n"), $utf8)
            if ($code -lt 200 -or $code -ge 300) { Write-Trace "GAVE-UP after 3 tries" }
            $tries = 0
        }
    } catch { Write-Trace ("LOOP-ERROR " + $_.Exception.GetType().Name) }
}
