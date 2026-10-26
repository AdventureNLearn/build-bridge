# Build Bridge (Windows): compare the step-1 scan with the post-rollback scan. Reads only.
# Both scans must carry the same project= line (else SCAN-PROJECT-MISMATCH, exit 2). "info: " lines (the person's own
# Build sessions) are reported but not compared.
param([Parameter(Mandatory = $true)][string]$Baseline, [Parameter(Mandatory = $true)][string]$After)
$a = @(Get-Content -LiteralPath $Baseline); $b = @(Get-Content -LiteralPath $After)
$pa = @($a | Where-Object { $_ -like "project=*" }); $pb = @($b | Where-Object { $_ -like "project=*" })
if (@($pa).Count -ne 1 -or @($pb).Count -ne 1 -or $pa[0] -cne $pb[0]) { "SCAN-PROJECT-MISMATCH baseline " + ($pa -join ",") + " / after " + ($pb -join ","); exit 2 }
$d = @(Compare-Object -ReferenceObject @($a | Where-Object { $_ -notlike "info: *" }) -DifferenceObject @($b | Where-Object { $_ -notlike "info: *" }) -SyncWindow 0)
if (@($d).Count -eq 0) { "SCAN-MATCH"; exit 0 }
"SCAN-DIFF"; $d | ForEach-Object { "{0} {1}" -f $_.SideIndicator, $_.InputObject }; exit 1
