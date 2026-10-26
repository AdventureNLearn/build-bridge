# Build Bridge tab host (Windows). Windows Terminal runs THIS in the tab; it runs Build,
# then always exits 0 so the tab closes when Build ends or is stopped by bb-off.
param([Parameter(Mandatory = $true)][string]$ProjectDir, [Parameter(Mandatory = $true)][string]$Grok)
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$prompt = "This is your starting message from the Build Bridge launcher. The Build Bridge rule in AGENTS.md applies from now on, because a session ignores it until its first message. Turn the Build Bridge listener on in the background: run <BB_ROOT>\bin\bb-listen.ps1 only if it is not already running. Then check <BB_ROOT>\outbox for jobs not yet in done and act on them using the Build Bridge rule in AGENTS.md. From now on, check that outbox again at the start of every turn and after every finished task, because the listener cannot wake you while you are idle."
$prompt = $prompt.Replace("<BB_ROOT>", $BBRoot).Replace("<USER_HOME>", $env:USERPROFILE)
$env:BB_LAUNCHED = "1"   # marks this as a launched session; allow-auto refuses inside it
try { & $Grok --cwd $ProjectDir $prompt } catch { }
exit 0
