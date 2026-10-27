# Build Bridge step 3 (Windows): make the person's own RSA-3072 key pair.
# The private key is DPAPI-protected for this Windows user and stored in an owner-only folder.
# It is never printed. Never overwrites or deletes an existing key: if the key folder is not empty it stops and writes nothing.
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\bb-common.ps1"
# v1.0.1 (PC case B): stop if the key folder has ANY entry, checked with .NET on the fully resolved path,
# before anything is written. Nothing above this point writes to the key folder (bb-common.ps1 only sets variables).
function Stop-BBKeysNotEmpty([string]$Dir) {
    $full = (Resolve-Path -LiteralPath $Dir -ErrorAction Stop).ProviderPath
    $entries = [System.IO.Directory]::GetFileSystemEntries($full)
    if ($entries.Length -gt 0) {
        if (Test-Path -LiteralPath (Join-Path $full "signing-private.dpapi")) { Write-Output "KEY-EXISTS STOP: a key already exists in the key folder. Nothing was changed, overwritten or deleted. Tell the person; do not re-run keygen."; exit 3 }
        Write-Output ("KEYS-FOLDER-NOT-EMPTY STOP: the key folder already has " + $entries.Length + " entr(y/ies). Nothing was changed, overwritten or deleted. Tell the person."); exit 3
    }
    return $full
}
if (Test-Path -LiteralPath $script:BBKeys) { [void](Stop-BBKeysNotEmpty $script:BBKeys) }
$pubDir = Join-Path $script:BBHome "keys-public"
if (-not (Test-Path -LiteralPath $pubDir)) { throw "run step 2 first" }
if (-not (Test-Path -LiteralPath $script:BBKeys)) { New-Item -ItemType Directory -Path $script:BBKeys | Out-Null }
# Re-check right before any write, and use full paths from here on (.NET file calls do not follow the PowerShell location).
$keysFull = Stop-BBKeysNotEmpty $script:BBKeys
$script:BBKeys = $keysFull
$priv = Join-Path $keysFull "signing-private.dpapi"
$pub = Join-Path (Resolve-Path -LiteralPath $pubDir -ErrorAction Stop).ProviderPath "signing-public.xml"
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$icaclsOut = @(& icacls $script:BBKeys /inheritance:r /grant:r ("*{0}:(OI)(CI)F" -f $sid) 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) { throw ("icacls could not make the key folder owner-only (exit " + $LASTEXITCODE + "): " + (($icaclsOut | Where-Object { $_.Trim() }) -join " ; ")) }
# v1.0.1 fix: /inheritance:r keeps explicit SYSTEM and Administrators entries on a normal PC. Remove them, and any other non-owner SID.
$icaclsOut = @(& icacls $script:BBKeys /remove:g "*S-1-5-18" "*S-1-5-32-544" 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) { throw ("icacls could not remove SYSTEM/Administrators from the key folder (exit " + $LASTEXITCODE + "): " + (($icaclsOut | Where-Object { $_.Trim() }) -join " ; ")) }
foreach ($o in @((Get-Acl -LiteralPath $script:BBKeys).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Where-Object { $_ -ne $sid } | Sort-Object -Unique)) {
    & icacls $script:BBKeys /remove:g ("*" + $o) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw ("icacls could not remove a non-owner entry from the key folder (exit " + $LASTEXITCODE + ")") }
}
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
