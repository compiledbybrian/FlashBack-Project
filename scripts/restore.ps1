<#
.SYNOPSIS
  Backup-restore side of the comparison: restore a full mariadb-dump of the database,
  time it, and verify the result the same way recover.ps1 does.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\restore.ps1 -DumpFile shop_backup.sql

.NOTES
  - Run it on the SAME damaged state you used for recover.ps1 (run sql/03_disaster.sql first).
  - The dump must have been taken from healthy data, before the disaster.
  - A restore overwrites the WHOLE database with the dump's contents: anything written
    after the dump was taken is lost. FLASHBACK only reverses the one bad transaction.
  - Needs config/recovery.cnf (see recovery.cnf.example).
  - Verification compares orders with orders_copy. Both come from the dump here, so this
    proves orders is healthy only because the dump's orders_copy was a healthy snapshot.
    Also compare CHECKSUM TABLE output (sql/checksums.sql) before the disaster and after.
#>
param(
    [Parameter(Mandatory)] [string] $DumpFile,
    [string] $Database = "shop",
    [string] $Cnf      = "config/recovery.cnf",
    [switch] $Force                                   # restore even if orders already looks healthy
)

$ErrorActionPreference = "Stop"

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

function Invoke-Sql([string] $sql) {
    $out = & mariadb "--defaults-extra-file=$Cnf" $Database -N -B "--execute=$sql"
    if ($LASTEXITCODE -ne 0) { Fail "SQL failed: $sql" }
    return $out
}

# Rows in orders that differ from the snapshot, plus any difference in row count.
$MismatchSql = @"
SELECT (SELECT COUNT(*) FROM orders o JOIN orders_copy c ON c.order_id = o.order_id
        WHERE NOT (o.customer_id <=> c.customer_id
               AND o.ordered_at  <=> c.ordered_at
               AND o.status      <=> c.status))
     + ABS((SELECT COUNT(*) FROM orders) - (SELECT COUNT(*) FROM orders_copy));
"@

# ---------- 1. validate ----------
if (-not (Test-Path $DumpFile)) { Fail "Dump file not found: $DumpFile" }
if (-not (Test-Path $Cnf))      { Fail "Option file not found: $Cnf (copy config/recovery.cnf.example)" }
if (-not (Get-Command mariadb -ErrorAction SilentlyContinue)) { Fail "mariadb not found on PATH" }
$Cnf = (Resolve-Path $Cnf).Path
$dumpInfo = Get-Item $DumpFile
Write-Host ("Dump: {0} ({1:N1} MB, written {2})" -f $dumpInfo.Name, ($dumpInfo.Length / 1MB), $dumpInfo.LastWriteTime)

# ---------- 2. is there actually damage to repair? ----------
$before = [int](Invoke-Sql $MismatchSql)
Write-Host "Rows differing from orders_copy before restore: $before"
if (($before -eq 0) -and (-not $Force)) {
    Fail "orders already matches orders_copy, so there is nothing to compare. Run sql/03_disaster.sql first (or use -Force)."
}

# ---------- 3. restore, timed ----------
$sqlPath = (Resolve-Path $DumpFile).Path -replace '\\', '/'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& mariadb "--defaults-extra-file=$Cnf" $Database "--execute=SOURCE $sqlPath" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Restore failed" }
$restoreSec = $sw.Elapsed.TotalSeconds
Write-Host ("Restored in {0:N2} s" -f $restoreSec)

# ---------- 4. verify ----------
$after = [int](Invoke-Sql $MismatchSql)
Write-Host "Status counts now:"
Invoke-Sql "SELECT status, COUNT(*) FROM orders GROUP BY status" | ForEach-Object { Write-Host "  $_" }

# ---------- 5. summary ----------
Write-Host ""
Write-Host "================ SUMMARY ================"
Write-Host ("Rows differing from snapshot : {0} -> {1}" -f $before, $after)
Write-Host ("Restore (whole database)     : {0:N2} s" -f $restoreSec)
Write-Host "Dump file                    : $DumpFile"
if ($after -eq 0) { Write-Host "VERIFIED: orders matches orders_copy" -ForegroundColor Green; exit 0 }
else              { Write-Host "NOT VERIFIED: $after rows still differ" -ForegroundColor Red; exit 1 }