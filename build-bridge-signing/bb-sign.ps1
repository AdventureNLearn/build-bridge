# Build Bridge (Windows): sign a draft job and place it in the outbox.
# Usage: bb-sign.ps1 -Draft <path to draft .job without sig>
param([Parameter(Mandatory = $true)][string]$Draft)
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\bb-common.ps1"
$priv = Join-Path $script:BBKeys "signing-private.dpapi"
if (-not (Test-Path -LiteralPath $priv)) { Write-Output "SIGN-FAILED NO_KEY"; exit 1 }
$job = Read-BBJob $Draft
if (-not $job.ok) { Write-Output ("SIGN-FAILED " + $job.reason); exit 1 }
if ($job.sig) { Write-Output "SIGN-FAILED ALREADY_SIGNED"; exit 1 }
$id = $job.map["id"].Trim()
$dest = Join-Path $script:BBHome ("outbox\" + $id + ".job")
if ((Test-Path -LiteralPath $dest) -or (Test-Path -LiteralPath (Join-Path $script:BBHome ("done\" + $id + ".job")))) { Write-Output "SIGN-FAILED ID_USED"; exit 1 }
Add-Type -AssemblyName System.Security
$plain = [System.Security.Cryptography.ProtectedData]::Unprotect([System.IO.File]::ReadAllBytes($priv), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
try {
    $rsa.PersistKeyInCsp = $false
    $rsa.FromXmlString([System.Text.Encoding]::UTF8.GetString($plain))
    [Array]::Clear($plain, 0, $plain.Length)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-BBCanonical $job.map))
    $sig = [Convert]::ToBase64String($rsa.SignData($bytes, "SHA256"))
} finally { $rsa.Dispose() }
$body = ([System.IO.File]::ReadAllText($Draft, [System.Text.Encoding]::UTF8)).TrimEnd() + "`nsig: " + $sig + "`n"
$tmp = $dest + ".tmp"
[System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding $false))
Move-Item -LiteralPath $tmp -Destination $dest
Write-Output ("SIGNED " + $id)
