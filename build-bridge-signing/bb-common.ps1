# Build Bridge shared job helpers (Windows). Dot-source: . "$PSScriptRoot\bb-common.ps1"
# Root: BB_HOME if set, else <USER_HOME>\.buildbridge. Keys live next to it in "<root>-keys".
# Test mode (BB_TEST=1) refuses to run unless BB_HOME points at a test folder, never the live one.
$BBRoot = if ($env:BB_HOME) { $env:BB_HOME } else { Join-Path $env:USERPROFILE ".buildbridge" }
$BBKeysRoot = $BBRoot + "-keys"
if ($env:BB_TEST -eq "1" -and ((-not $env:BB_HOME) -or ($env:BB_HOME.TrimEnd('\', '/') -eq (Join-Path $env:USERPROFILE ".buildbridge")))) { Write-Output "TEST-REFUSED: BB_TEST=1 needs BB_HOME set to a test folder (never the live one)"; exit 4 }
$script:BBFields = @("v", "id", "from", "to", "priority", "time", "job", "done-when")
$script:BBHome = $BBRoot
$script:BBKeys = $BBKeysRoot

function Read-BBJob([string]$Path) {
    # Returns @{ ok; reason; map; sig }. Unknown or repeated fields are refused.
    $map = @{}; $sig = $null; $current = $null
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    foreach ($raw in ($text -split "`n")) {
        $line = $raw.TrimEnd("`r")
        if ($line -cmatch '^([a-z][a-z0-9-]*): ?(.*)$') {
            $name = $Matches[1]; $value = $Matches[2]
            if ($name -eq "sig") { if ($null -ne $sig) { return @{ ok = $false; reason = "BAD_FIELD" } }; $sig = $value.Trim(); $current = "sig"; continue }
            if ($script:BBFields -notcontains $name) { return @{ ok = $false; reason = "BAD_FIELD" } }
            if ($map.ContainsKey($name)) { return @{ ok = $false; reason = "BAD_FIELD" } }
            $map[$name] = $value; $current = $name
        } elseif ($line.Trim() -ne "") {
            if ($current -ne "job" -and $current -ne "done-when") { return @{ ok = $false; reason = "BAD_FIELD" } }
            $map[$current] = $map[$current] + " " + $line
        }
    }
    foreach ($n in $script:BBFields) { if (-not $map.ContainsKey($n) -or [string]::IsNullOrWhiteSpace($map[$n])) { return @{ ok = $false; reason = "MISSING_FIELD" } } }
    if ($map["v"].Trim() -ne "3") { return @{ ok = $false; reason = "OLD_FORMAT" } }
    if (@("normal", "urgent") -notcontains $map["priority"].Trim()) { return @{ ok = $false; reason = "BAD_PRIORITY" } }
    if ($map["id"].Trim() -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$') { return @{ ok = $false; reason = "BAD_ID" } }
    return @{ ok = $true; reason = ""; map = $map; sig = $sig }
}

function Get-BBCanonical([hashtable]$Map) {
    $lines = foreach ($n in $script:BBFields) { $n + "=" + ([regex]::Replace(([string]$Map[$n]).Trim(), '\s+', ' ')) }
    return ($lines -join "`n")
}

function Test-BBOwnerOnly([string]$Dir) {
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = Get-Acl -LiteralPath $Dir
    $rules = @($acl.Access)
    return ($acl.AreAccessRulesProtected -and @($rules).Count -ge 1 -and @($rules | Where-Object { $_.IdentityReference.Value -ne $me }).Count -eq 0)
}


# ---------- Launcher name check (used by bb-on, bb-pickup, bb-rollback, scan) ----------
# Live task "Build Bridge Launch". In test mode (BB_TEST=1) BB_TASK_NAME is REQUIRED (no default), must contain
# "test", and is never the live name. Returns $null when refused.
function Get-BBTaskName {
    $live = "Build Bridge Launch"
    if ($env:BB_TEST -ne "1") { return $live }
    $n = ([string]$env:BB_TASK_NAME).Trim().TrimStart('\')
    if ((-not $n) -or ($n -ieq $live) -or ($n -notmatch '(?i)test')) { return $null }
    return $n
}

# ---------- Permission-mode auto: recorded YES and deny-list ----------
$script:BBAutoYes = Join-Path $BBRoot "state\permission-auto.yes"
$script:BBAutoMark = "made-by=bb-allow-auto interactive=1"
$script:BBAutoMac = $script:BBAutoYes + ".hmac"
# Dedicated HMAC secret in the owner-only keys folder. Not the job-signing private key: that key is RSA and
# DPAPI-wrapped for one purpose (signing jobs); reusing it would mean unwrapping it here and mixing purposes.
$script:BBAutoKey = Join-Path $BBKeysRoot "auto-hmac.key"
function Get-BBHmacHex([string]$KeyPath, [string]$DataPath) {
    if (-not (Test-Path -LiteralPath $KeyPath) -or -not (Test-Path -LiteralPath $DataPath)) { return "" }
    $hex = ([System.IO.File]::ReadAllText($KeyPath)).Trim()
    if ($hex -notmatch '^[0-9a-f]{64}$') { return "" }
    $k = New-Object byte[] 32
    for ($i = 0; $i -lt 32; $i++) { $k[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
    $h = [System.Security.Cryptography.HMACSHA256]::new($k)
    $m = $h.ComputeHash([System.IO.File]::ReadAllBytes($DataPath)); $h.Dispose()
    return ((@($m) | ForEach-Object { $_.ToString("x2") }) -join "")
}
# Owner-only ACL on one file: drop inherited entries, grant only the current user (by SID) Full control. [UNTESTED live]
function Set-BBOwnerOnlyAcl([string]$Path) {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $Path /inheritance:r /grant:r ("*" + $sid + ":F") | Out-Null
    return ($LASTEXITCODE -eq 0)
}
# Verify: inheritance off, exactly one Allow rule, for the current user's SID, with FullControl. [UNTESTED live]
function Test-BBOwnerOnlyAcl([string]$Path) {
    try {
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $acl = Get-Acl -LiteralPath $Path
        if (-not $acl.AreAccessRulesProtected) { return $false }
        $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        if (@($rules).Count -ne 1) { return $false }
        $r = $rules[0]
        return ($r.IdentityReference.Value -eq $sid -and $r.AccessControlType -eq "Allow" -and (($r.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -eq [System.Security.AccessControl.FileSystemRights]::FullControl))
    } catch { return $false }
}
# Creates the HMAC key once (32 random bytes, hex) inside the existing keys folder. Fails closed: the file is created
# empty, locked to owner-only and verified BEFORE the secret is written; on any failure it is deleted and $false returned.
# An existing key is used only if its ACL still verifies.
function New-BBAutoKey {
    if (-not (Test-Path -LiteralPath $BBKeysRoot)) { return $false }
    if (Test-Path -LiteralPath $script:BBAutoKey) { return (Test-BBOwnerOnlyAcl $script:BBAutoKey) }
    [System.IO.File]::WriteAllText($script:BBAutoKey, "")
    if (-not (Set-BBOwnerOnlyAcl $script:BBAutoKey) -or -not (Test-BBOwnerOnlyAcl $script:BBAutoKey)) { Remove-Item -LiteralPath $script:BBAutoKey -Force -ErrorAction SilentlyContinue; return $false }
    $b = New-Object byte[] 32; $r = [System.Security.Cryptography.RandomNumberGenerator]::Create(); $r.GetBytes($b); $r.Dispose()
    [System.IO.File]::WriteAllText($script:BBAutoKey, ((@($b) | ForEach-Object { $_.ToString("x2") }) -join ""))
    if (-not (Test-BBOwnerOnlyAcl $script:BBAutoKey)) { Remove-Item -LiteralPath $script:BBAutoKey -Force -ErrorAction SilentlyContinue; return $false }
    return $true
}
# Constant-time compare of two hex strings. Uses .NET CryptographicOperations.FixedTimeEquals when present (PS 7),
# else an XOR-accumulate loop (PS 5.1). -NoNet forces the loop (for tests).
function Compare-BBFixedTime([string]$A, [string]$B, [switch]$NoNet) {
    if ($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length -or $A.Length -eq 0) { return $false }
    $ba = [System.Text.Encoding]::ASCII.GetBytes($A); $bb = [System.Text.Encoding]::ASCII.GetBytes($B)
    $t = "System.Security.Cryptography.CryptographicOperations" -as [type]
    if (-not $NoNet -and $null -ne $t) { return [bool]$t::FixedTimeEquals([byte[]]$ba, [byte[]]$bb) }
    $d = 0
    for ($i = 0; $i -lt $ba.Length; $i++) { $d = $d -bor ($ba[$i] -bxor $bb[$i]) }
    return ($d -eq 0)
}
# Valid only if the record carries the marker that the interactive allow-auto step writes. This is a guard against
# mistakes, not a security boundary: anything with full access to the person's files (including Build) could forge it.
function Test-BBAutoYes {
    if (-not (Test-Path -LiteralPath $script:BBAutoYes) -or -not (Test-Path -LiteralPath $script:BBAutoMac)) { return $false }
    if (-not (@(Get-Content -LiteralPath $script:BBAutoYes -ErrorAction SilentlyContinue) -contains $script:BBAutoMark)) { return $false }
    $m = Get-BBHmacHex $script:BBAutoKey $script:BBAutoYes
    return (Compare-BBFixedTime $m ([System.IO.File]::ReadAllText($script:BBAutoMac)).Trim())
}
# Normalize before matching: drop quotes; turn shell separators, parens, backticks and redirects into spaces.
# Also: drop ^ (cmd escape), map Unicode dashes to -, and close up spaces around =.
function ConvertTo-BBNormCmd([string]$c) {
    $n = $c -replace "[\x22\x27\x5E]", ""
    $n = $n -replace '[\u2010-\u2015\u2212\uFE58\uFE63\uFF0D]', '-'
    $n = $n -replace '[;&|()`<>]', ' '
    return ($n -replace '\s*=\s*', '=')
}
# Allow-list (raw command, before normalization): letters, digits, space, and . _ / \ : = , + @ { } " ' -
# Anything else (% $ ! ^ ; & | ( ) ` < > * ? ~ # [ ] and every non-ASCII character) is refused. Safer than a
# deny-list: an unknown expansion or separator is refused by default. The prompt is never in the command: use
# {PROMPT_FILE} (replaced by the prompt file's path); the prompt is also on stdin and in BB_PROMPT_FILE.
function Test-BBCmd([string]$c) {
    if ($c -eq ("<BUILD_" + "ONESHOT_CMD>")) { return "ALLOWED" }
    if ($c.Contains("{PROMPT}")) { return "REFUSED {PROMPT} is no longer supported (the prompt is not put in the command); use {PROMPT_FILE}" }
    $bad = [regex]::Match($c, "[^A-Za-z0-9 ._/\\:=,+@{}\x22\x27-]")
    if ($bad.Success) { return ("REFUSED character not on the allow-list: U+" + ([int][char]$bad.Value).ToString("X4") + " (variable/expansion/separator risk; write the command out literally)") }
    $n = ConvertTo-BBNormCmd $c
    if ($n -match '(?i)--permission-mode(=|\s+)?\S*[%$!]') { return "REFUSED --permission-mode value contains %, `$ or ! (variable/expansion risk; write the mode out literally)" }
    if ($n -match '(?i)yolo|dangerous|--force|always-approve|auto-approve|skip[-_]permission|bypass|no-confirm|no-verify|trust-all|(^|\s)(-y|--yes)(\s|=|$)') { return "REFUSED bypass flag" }
    if ($n -match '(?i)--permission-mode(\s+|=)auto(\s|$)' -and -not (Test-BBAutoYes)) { return "REFUSED permission-mode auto has no valid recorded YES (the person runs allow-auto in their own terminal)" }
    return "ALLOWED"
}

# ---------- Is this a Build / Build Bridge launched session? ----------
# Markers: BB_LAUNCHED / BB_JOB are set by the launcher tab host and by pickup runs. A Grok Build session's own
# environment marker is [UNKNOWN], so we also walk the parent processes (Windows only) looking for grok.exe or a
# Build Bridge launcher/pickup/watcher script.
function Test-BBLaunchedSession {
    if ($env:BB_LAUNCHED -or $env:BB_JOB) { return "env BB_LAUNCHED/BB_JOB is set" }
    try {
        $id = $PID
        for ($i = 0; $i -lt 30; $i++) {
            $p = @(Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction Stop)
            if (@($p).Count -eq 0) { break }
            $cmd = [string]$p[0].CommandLine
            if ($cmd -match '(?i)bb-pickup.*AllowAuto') { $cmd = "" }   # the shell that typed allow-auto is not a pickup run
            if ($p[0].Name -ieq "grok.exe" -or $cmd -match '(?i)bb-build-tab|bb-pickup|bb-watch-') { return ("parent process " + $p[0].Name) }
            $next = [int]$p[0].ParentProcessId
            if ($next -le 0 -or $next -eq $id) { break }
            $id = $next
        }
    } catch { }
    return ""
}
