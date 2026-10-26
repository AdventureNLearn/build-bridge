# Build Bridge step 3 (Windows): make the person's own RSA-3072 key pair.
# The private key is DPAPI-protected for this Windows user and stored in an owner-only folder.
# It is never printed. Refuses to overwrite an existing key.
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\bb-common.ps1"
$priv = Join-Path $script:BBKeys "signing-private.dpapi"
$pub = Join-Path $script:BBHome "keys-public\signing-public.xml"
if (Test-Path -LiteralPath $priv) { Write-Output "KEY-EXISTS (nothing changed)"; exit 0 }
if (-not (Test-Path -LiteralPath (Split-Path $pub))) { throw "run step 2 first" }
if (-not (Test-Path -LiteralPath $script:BBKeys)) { New-Item -ItemType Directory -Path $script:BBKeys | Out-Null }
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$icaclsOut = @(& icacls $script:BBKeys /inheritance:r /grant:r ("*{0}:(OI)(CI)F" -f $sid) 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) { throw ("icacls could not make the key folder owner-only (exit " + $LASTEXITCODE + "): " + (($icaclsOut | Where-Object { $_.Trim() }) -join " ; ")) }
if (-not (Test-BBOwnerOnlyAcl $script:BBKeys)) { throw "could not make the key folder owner-only (Test-BBOwnerOnlyAcl failed after icacls exit 0)" }
Add-Type -AssemblyName System.Security
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider 3072
try {
    $rsa.PersistKeyInCsp = $false
    $plain = [System.Text.Encoding]::UTF8.GetBytes($rsa.ToXmlString($true))
    $sealed = [System.Security.Cryptography.ProtectedData]::Protect($plain, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    [Array]::Clear($plain, 0, $plain.Length)
    # Fail closed: the private key file is created empty, locked to owner-only (by SID) and verified BEFORE the sealed key is written.
    [System.IO.File]::WriteAllBytes($priv, [byte[]]@())
    if (-not (Set-BBOwnerOnlyAcl $priv) -or -not (Test-BBOwnerOnlyAcl $priv)) { Remove-Item -LiteralPath $priv -Force -ErrorAction SilentlyContinue; throw "could not make the private key file owner-only (nothing kept)" }
    # If the key write throws, delete the partial key file, then rethrow.
    try {
        [System.IO.File]::WriteAllBytes($priv, $sealed)
    } catch { Remove-Item -LiteralPath $priv -Force -ErrorAction SilentlyContinue; throw }
    if (-not (Test-BBOwnerOnlyAcl $priv)) { Remove-Item -LiteralPath $priv -Force -ErrorAction SilentlyContinue; throw "the private key file is not owner-only after writing (deleted)" }
    [System.IO.File]::WriteAllText($pub, $rsa.ToXmlString($false), (New-Object System.Text.UTF8Encoding $false))
} finally { $rsa.Dispose() }
Write-Output "KEYGEN-OK owner-only=True"
