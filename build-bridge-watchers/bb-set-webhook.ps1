# Build Bridge (Windows): the PERSON runs this in their own terminal and types their own
# webhook address and key. Nothing is echoed. Saved only in the owner-only key folder.
param([switch]$Test)
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
# Test mode (no typing, never writes the real config): $env:BB_WEBHOOK_TEST_URL = "http://127.0.0.1:<port>/"; bb-set-webhook.ps1 -Test
# Only http://127.0.0.1 or http://localhost is accepted. Sends the same content-free wake ping, prints the code, saves nothing.
if ($Test) {
    $u = [string]$env:BB_WEBHOOK_TEST_URL
    if ($u -notmatch '^http://(127\.0\.0\.1|localhost)(:[0-9]{1,5})?(/\S*)?$') { Write-Output "TEST-REFUSED url must be http://127.0.0.1 or http://localhost"; exit 1 }
    $code = 0
    try {
        $r = Invoke-WebRequest -Uri $u -Method Post -Headers @{ Authorization = "Bearer test-only" } -Body '{"event":"ACTION_REQUIRED","source":"buildbridge"}' -ContentType "application/json; charset=utf-8" -UseBasicParsing -TimeoutSec 10
        $code = [int]$r.StatusCode
    } catch { $code = 0 }
    if ($code -ge 200 -and $code -lt 300) { Write-Output "WEBHOOK-TEST-OK $code (nothing saved)"; exit 0 }
    Write-Output "WEBHOOK-TEST-FAILED $code (nothing saved)"; exit 1
}
$keys = $BBKeysRoot
if (-not (Test-Path -LiteralPath $keys)) { throw "run step 3 first (owner-only key folder)" }
$url = Read-Host "Webhook URL (from your own Grok Bot routine)"
if ($url -notmatch '^https://') { throw "URL must start with https://" }
$sec = Read-Host "Webhook key" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
$header = Read-Host "Header name (press Enter for Authorization: Bearer)"
$obj = @{ url = $url; key = $key }
if ($header) { $obj.header = $header }
[System.IO.File]::WriteAllText((Join-Path $keys "webhook.json"), ($obj | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding $false))
Write-Output "WEBHOOK-SAVED"
