# Build Bridge step 8 self-test (Windows). Needs the watchers on. Writes only BB-SELFTEST-* files.
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
$bb = $BBRoot
$bin = Join-Path $bb "bin"
$stamp = Get-Date -Format "yyyyMMddHHmmss"
$utf8 = New-Object System.Text.UTF8Encoding $false
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
function Draft([string]$id) {
    "v: 3`nid: $id`nfrom: GrokBot`nto: Build`npriority: normal`ntime: $((Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz'))`njob: Self-test. Change nothing and reply done.`ndone-when: A reply with this id is in the inbox.`n"
}
$fail = 0
$good = "BB-SELFTEST-$stamp-1"; $uns = "BB-SELFTEST-$stamp-2"; $bad = "BB-SELFTEST-$stamp-3"
$tmp = Join-Path $env:TEMP "$good.draft"
[System.IO.File]::WriteAllText($tmp, (Draft $good), $utf8)
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bin "bb-sign.ps1") -Draft $tmp | Out-Null
Remove-Item -LiteralPath $tmp
[System.IO.File]::WriteAllText((Join-Path $bb "outbox\$uns.job"), (Draft $uns), $utf8)
$t2 = Join-Path $env:TEMP "$bad.draft"
[System.IO.File]::WriteAllText($t2, (Draft $bad), $utf8)
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bin "bb-sign.ps1") -Draft $t2 | Out-Null
Remove-Item -LiteralPath $t2
$bp = Join-Path $bb "outbox\$bad.job"
[System.IO.File]::WriteAllText($bp, ([System.IO.File]::ReadAllText($bp).Replace("Change nothing", "Change everything")), $utf8)
Start-Sleep -Seconds 15
$wake = Join-Path $bb "logs\wake.log"
if ((Test-Path -LiteralPath $wake) -and (Select-String -LiteralPath $wake -SimpleMatch "ACTION_REQUIRED job $good" -Quiet)) { "PASS signed-accepted" } else { "FAIL signed-accepted"; $fail++ }
foreach ($p in @(@($uns, "UNSIGNED", "unsigned-rejected"), @($bad, "BAD_SIG", "tampered-rejected"))) {
    $r = Join-Path $bb ("rejected\" + $p[0] + ".job.reason")
    if ((Test-Path -LiteralPath $r) -and (([System.IO.File]::ReadAllText($r)).Trim() -eq $p[1])) { "PASS " + $p[2] } else { "FAIL " + $p[2]; $fail++ }
}
# Clean up: the signed test job goes to done if Build has not already moved it.
$gp = Join-Path $bb "outbox\$good.job"
if (Test-Path -LiteralPath $gp) { Move-Item -LiteralPath $gp -Destination (Join-Path $bb "done\$good.job") }
if ($fail) { "SELFTEST-FAILED $fail"; exit 1 } else { "SELFTEST-OK" }
