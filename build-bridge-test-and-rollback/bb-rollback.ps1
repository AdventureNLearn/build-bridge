# Build Bridge rollback drill (Windows): undo steps 7 to 2 in reverse order. Moves aside first.
# Then it asks two separate named YESes, typed by the person: DELETE-KEYS deletes the moved-aside keys folder
# (private key, webhook.json, auto-hmac.key), and DELETE-SCANS deletes <root>-scans. No answer or any other answer deletes nothing.
# -Rescan <path to scan.ps1>: after the undo steps, run the scan with -Save 2, which saves scan-2 and prints SCAN-MATCH / SCAN-DIFF.
param([Parameter(Mandatory = $true)][string]$ProjectDir, [string]$Rescan = "")
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
# -Rescan accepts ONLY this package's own scan script: the full path must be ..\build-bridge-scan\scan.ps1 (package layout)
# or scan.ps1 beside this script, and if the package MANIFEST.md lists it, its sha256 must match. Anything else is refused
# before any undo step runs (exit 6, nothing changed).
if ($Rescan) {
    $rf = try { [System.IO.Path]::GetFullPath($Rescan) } catch { "" }
    $ok = @([System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "..", "build-bridge-scan", "scan.ps1")), [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "scan.ps1")))
    if ((-not $rf) -or (-not (Test-Path -LiteralPath $rf -PathType Leaf)) -or (@($ok | Where-Object { $_ -ieq $rf }).Count -eq 0)) { "RESCAN-REFUSED: -Rescan must be the package's own scan.ps1 (" + ($ok -join " or ") + "). Nothing changed."; exit 6 }
    $man = [System.IO.Path]::Combine($PSScriptRoot, "..", "MANIFEST.md")
    if (Test-Path -LiteralPath $man) {
        $line = @(Get-Content -LiteralPath $man | Where-Object { $_ -match '^[0-9a-f]{64}\s+build-bridge-scan/scan\.ps1$' })
        if (@($line).Count -eq 1 -and $rf -ieq $ok[0]) {
            $h = (Get-FileHash -LiteralPath $rf -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($h -ne $line[0].Substring(0, 64)) { "RESCAN-REFUSED: scan.ps1 sha256 $h does not match MANIFEST.md. Nothing changed."; exit 6 }
            "RESCAN-OK scan.ps1 matches MANIFEST.md"
        }
    }
    $Rescan = $rf
}
$bb = $BBRoot
$bin = Join-Path $bb "bin"
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
# AGENTS.md check FIRST, before anything is stopped, removed or moved. It is skipped only when there is nothing to check:
# no AGENTS.md.buildbridge-backup-* or AGENTS.md.buildbridge-none-* file in the project folder (or remove-startup-rule.ps1 is not in bin).
$rsr = Join-Path $bin "remove-startup-rule.ps1"
$fix = "make sure AGENTS.md is in the project folder and has exactly one line '<!-- BEGIN BUILD BRIDGE -->' and, after it, exactly one line '<!-- END BUILD BRIDGE -->', both unchanged (or remove the Build Bridge section by hand)"
function Stop-BBRollback([string]$stopLine, [string]$done) {
    "ROLLBACK-HALTED: " + $done + " Fix AGENTS.md: " + $stopLine + " To fix it, " + $fix + ". Then run the removal again."
    exit 7
}
$hasCopy = @(Get-ChildItem -LiteralPath $ProjectDir -Filter "AGENTS.md.buildbridge-*" -File -ErrorAction SilentlyContinue).Count -gt 0
if (-not $hasCopy) { "PRECHECK-SKIPPED: no AGENTS.md backup or marker in the project folder" }
elseif (-not (Test-Path -LiteralPath $rsr)) { "PRECHECK-SKIPPED: remove-startup-rule.ps1 is not in " + $bin }
else {
    $chk = @(& $ps -NoProfile -ExecutionPolicy Bypass -File $rsr -ProjectDir $ProjectDir -CheckOnly)
    if ($LASTEXITCODE -ne 0) { Stop-BBRollback (($chk | Where-Object { $_ -like "STOP*" }) -join " ") "nothing was changed." }
    $chk
}
# Step 5 off first: stops watchers, listener, Build for this project, and the tab host.
if (Test-Path -LiteralPath (Join-Path $bin "bb-off.ps1")) { & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bin "bb-off.ps1") -ProjectDir $ProjectDir }
# Step 7
$norm = Get-BBTaskName
if ($null -eq $norm) {
    "UNDO-7 REFUSED: test mode needs BB_TASK_NAME set to a TEST task name (contains 'test', never the live name)"
} else {
    & schtasks.exe /Query /TN $norm 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & schtasks.exe /Delete /TN $norm /F | Out-Null
        & schtasks.exe /Query /TN $norm 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { "UNDO-7 FAILED task still present: " + $norm } else { "UNDO-7 task removed: " + $norm }
    } else { "UNDO-7 no task: " + $norm }
}
# Step 6
if (Test-Path -LiteralPath $rsr) {
    $u6 = @(& $ps -NoProfile -ExecutionPolicy Bypass -File $rsr -ProjectDir $ProjectDir)
    $u6rc = $LASTEXITCODE
    "UNDO-6 " + ($u6 -join " ")
    # AGENTS.md changed between the check and here: halt before bin, keys or the folder move.
    if ($u6rc -ne 0) { Stop-BBRollback (($u6 | Where-Object { $_ -like "STOP*" }) -join " ") "step 5 (bb-off) and step 7 (scheduled task removal) already ran; bin, keys and the folder were NOT moved and nothing was deleted." }
}
# Steps 5 and 4 are inside .buildbridge\bin and go with step 2. Step 3:
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$keys = $BBKeysRoot
if (Test-Path -LiteralPath $keys) { Move-Item -LiteralPath $keys -Destination ($keys + "-removed-" + $stamp); "UNDO-3 keys moved aside" } else { "UNDO-3 no keys" }
# Step 2
if (Test-Path -LiteralPath $bb) { Move-Item -LiteralPath $bb -Destination ($bb + "-removed-" + $stamp); "UNDO-2 folder moved aside" } else { "UNDO-2 no folder" }
"ROLLBACK-DONE. Now rerun the step-1 scan and compare-scan."
if ($Rescan) { & $Rescan -ProjectDir $ProjectDir -Save 2 | Where-Object { $_ -like "SCAN-*" -or $_ -like "<= *" -or $_ -like "=> *" } }
# Named YES prompts. Only the exact typed word counts. With no console to ask (input redirected), nothing is deleted.
function Ask-BBYes([string]$Word, [string]$Why) {
    if ([Console]::IsInputRedirected) { return $false }
    Write-Host $Why
    $a = Read-Host ("Type " + $Word + " to delete it, or press Enter to keep it")
    return [bool]($a -ceq $Word)
}
$keysAside = $keys + "-removed-" + $stamp
if (Test-Path -LiteralPath $keysAside) {
    if (Ask-BBYes "DELETE-KEYS" ("The keys folder (private key, webhook.json, auto-hmac.key) is moved aside at " + $keysAside + ". Deleting it is suggested.")) {
        Remove-Item -LiteralPath $keysAside -Recurse -Force
        if (Test-Path -LiteralPath $keysAside) { "DELETE-KEYS FAILED, keys still at: " + $keysAside } else { "DELETE-KEYS done: " + $keysAside }
    } else { "KEYS KEPT at: " + $keysAside }
} else { "DELETE-KEYS skipped: no keys moved aside this run" }
$scansDir = $BBRoot + "-scans"
if (Test-Path -LiteralPath $scansDir) {
    if (Ask-BBYes "DELETE-SCANS" ("The scans folder " + $scansDir + " holds a snapshot of this PC, such as the startup list. Deleting it is suggested.")) {
        Remove-Item -LiteralPath $scansDir -Recurse -Force
        if (Test-Path -LiteralPath $scansDir) { "DELETE-SCANS FAILED, still at: " + $scansDir } else { "DELETE-SCANS done: " + $scansDir }
    } else { "SCANS KEPT at: " + $scansDir }
} else { "DELETE-SCANS skipped: no scans folder" }
