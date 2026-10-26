# Build Bridge listener (Windows). Build runs this in the background at session start.
# Prints only new ACTION_REQUIRED lines from logs\wake.log. From the proven reference pattern.
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Continue"
$created = $false
$mutex = New-Object System.Threading.Mutex($false, "Local\BuildBridge-listen", [ref]$created)
if (-not $mutex.WaitOne(0)) { Write-Output "LISTENER-ALREADY-ON"; exit 0 }
$log = Join-Path $BBRoot "logs\wake.log"
$utf8 = New-Object System.Text.UTF8Encoding $false
while (-not (Test-Path -LiteralPath $log)) { Start-Sleep -Seconds 2 }
$pos = [int64](Get-Item -LiteralPath $log).Length
Write-Output "LISTENER-ON"
while ($true) {
    $len = [int64](Get-Item -LiteralPath $log).Length
    if ($len -gt $pos) {
        $fs = [System.IO.File]::Open($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            [void]$fs.Seek($pos, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] ([int]($len - $pos))
            $read = $fs.Read($buf, 0, $buf.Length)
            $text = $utf8.GetString($buf, 0, $read)
        } finally { $fs.Close() }
        foreach ($line in ($text -split "`r?`n")) { if ($line -match "ACTION_REQUIRED") { Write-Output $line } }
        $pos = $len
    } elseif ($len -lt $pos) { $pos = $len }
    Start-Sleep -Seconds 2
}
