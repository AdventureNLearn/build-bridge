# Build Bridge (Windows): verify one job with the public key only.
# Exit 0 + "VERIFY-OK <id>", or exit 2 + "REJECT <REASON>". Never runs anything.
param([Parameter(Mandatory = $true)][string]$File, [switch]$AllowUnsigned)
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\bb-common.ps1"
try {
    $job = Read-BBJob $File
    if (-not $job.ok) { Write-Output ("REJECT " + $job.reason); exit 2 }
    $id = $job.map["id"].Trim()
    if ([System.IO.Path]::GetFileName($File) -ne ($id + ".job")) { Write-Output "REJECT NAME_MISMATCH"; exit 2 }
    if (-not $job.sig) {
        if ($AllowUnsigned) { Write-Output ("VERIFY-OK " + $id + " UNSIGNED"); exit 0 }
        Write-Output "REJECT UNSIGNED"; exit 2
    }
    $pub = Join-Path $script:BBHome "keys-public\signing-public.xml"
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsa.PersistKeyInCsp = $false
        $rsa.FromXmlString([System.IO.File]::ReadAllText($pub))
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-BBCanonical $job.map))
        $ok = $rsa.VerifyData($bytes, "SHA256", [Convert]::FromBase64String($job.sig))
    } finally { $rsa.Dispose() }
    if ($ok) { Write-Output ("VERIFY-OK " + $id); exit 0 }
    Write-Output "REJECT BAD_SIG"; exit 2
} catch {
    Write-Output "REJECT ERROR"; exit 2
}
