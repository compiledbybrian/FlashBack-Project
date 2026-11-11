<#
.
  FLASHBACK recovery drill: reverse one bad transaction from the MariaDB binary log,
  verify the result against a known-good snapshot, and time every step.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\recover.ps1 `
      -LogFile "C:/ProgramData/MariaDB/data/mariadb-bin.000040" -StartPos 345 -StopPos 363625

.NOTES
  - Needs config/recovery.cnf (copy recovery.cnf.example and fill in your password).
  - Needs the snapshot table orders_copy, taken BEFORE the incident.
  - Only reads the binlog and writes out/flashback_<timestamp>.sql until the apply step.
  - Applying the same flashback file twice fails (rows no longer match); the script
    detects "already recovered" first and exits.
#>
param(
    [Parameter(Mandatory)] [string] $LogFile,     # full path of the binlog file holding the incident
    [Parameter(Mandatory)] [int]    $StartPos,    # position where the bad transaction starts
    [Parameter(Mandatory)] [int]    $StopPos,     # position where it ends (End_log_pos of the commit)
    [string] $Database = "shop",
    [string] $Cnf      = "config/recovery.cnf",   # client option file with user and password
    [switch] $Inspect,                            # add --verbose so the output file is readable
    [switch] $Force                               # continue even if the safety check fails
)

$ErrorActionPreference = "Stop"

# ---------- helpers ----------
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# Runs one SQL statement and returns the output lines (plain, tab separated).
function Invoke-Sql([string] $sql, [switch] $NoDb) {
    if ($NoDb) { $out = & mariadb "--defaults-extra-file=$Cnf" -N -B "--execute=$sql" }
    else       { $out = & mariadb "--defaults-extra-file=$Cnf" $Database -N -B "--execute=$sql" }
    if ($LASTEXITCODE -ne 0) { Fail "SQL failed: $sql" }
    return $out
}

# Number of rows in orders that differ from the snapshot, plus any difference in row count.
$MismatchSql = @"
SELECT (SELECT COUNT(*) FROM orders o JOIN orders_copy c ON c.order_id = o.order_id
        WHERE NOT (o.customer_id <=> c.customer_id
               AND o.ordered_at  <=> c.ordered_at
               AND o.status      <=> c.status))
     + ABS((SELECT COUNT(*) FROM orders) - (SELECT COUNT(*) FROM orders_copy));
"@

# ---------- 1. validate inputs ----------
if (-not (Test-Path $LogFile)) { Fail "Log file not found: $LogFile" }
if (-not (Test-Path $Cnf))     { Fail "Option file not found: $Cnf (copy config/recovery.cnf.example)" }
if ($StartPos -ge $StopPos)    { Fail "StartPos ($StartPos) must be smaller than StopPos ($StopPos)" }
foreach ($tool in "mariadb", "mariadb-binlog") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "$tool not found on PATH" }
}
$Cnf = (Resolve-Path $Cnf).Path

# ---------- 2. already recovered? ----------
$before = [int](Invoke-Sql $MismatchSql)
Write-Host "Rows differing from orders_copy before recovery: $before"
if ($before -eq 0) {
    Write-Host "Nothing to recover: orders already matches orders_copy." -ForegroundColor Green
    exit 0
}

# ---------- 3. safety check: has anything been written since the incident? ----------
$row = (Invoke-Sql "SHOW MASTER STATUS" -NoDb) -split "`t"
$curFile = $row[0]
$curPos  = [int]$row[1]
$logName = Split-Path $LogFile -Leaf
if (($curFile -ne $logName) -or ($curPos -ne $StopPos)) {
    $msg = "Server log is at $curFile / $curPos but the incident ends at $logName / $StopPos. " +
           "Something may have written since, and FLASHBACK would overwrite those changes with old values."
    if ($Force) { Write-Host "WARNING: $msg (continuing because of -Force)" -ForegroundColor Yellow }
    else        { Fail "$msg Re-run with -Force only if you are sure." }
}

# ---------- 4. generate the flashback file ----------
New-Item -ItemType Directory -Force out | Out-Null
$OutFile = "out/flashback_{0}.sql" -f (Get-Date -Format "yyyyMMdd_HHmmss")

$binlogArgs = @("--flashback", "--start-position=$StartPos", "--stop-position=$StopPos",
                "--database=$Database", "--result-file=$OutFile")
if ($Inspect) { $binlogArgs += "--verbose" }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& mariadb-binlog @binlogArgs $LogFile
if ($LASTEXITCODE -ne 0) { Fail "mariadb-binlog failed" }
$genSec = $sw.Elapsed.TotalSeconds
$sizeKb = [math]::Round((Get-Item $OutFile).Length / 1KB)
Write-Host ("Generated {0} ({1} KB) in {2:N2} s" -f $OutFile, $sizeKb, $genSec)

# ---------- 5. apply it ----------
$sqlPath = (Resolve-Path $OutFile).Path -replace '\\', '/'
$sw.Restart()
& mariadb "--defaults-extra-file=$Cnf" $Database "--execute=SOURCE $sqlPath" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Applying $OutFile failed (nothing is half-applied: the file is one transaction)" }
$applySec = $sw.Elapsed.TotalSeconds
Write-Host ("Applied in {0:N2} s" -f $applySec)

# ---------- 6. verify ----------
$after = [int](Invoke-Sql $MismatchSql)
Write-Host "Status counts now:"
Invoke-Sql "SELECT status, COUNT(*) FROM orders GROUP BY status" | ForEach-Object { Write-Host "  $_" }

# ---------- 7. summary ----------
$total = $genSec + $applySec
Write-Host ""
Write-Host "================ SUMMARY ================"
Write-Host ("Rows differing from snapshot : {0} -> {1}" -f $before, $after)
Write-Host ("Generate                     : {0:N2} s" -f $genSec)
Write-Host ("Apply                        : {0:N2} s" -f $applySec)
Write-Host ("FLASHBACK total              : {0:N2} s" -f $total)
Write-Host "Flashback file               : $OutFile"
if ($after -eq 0) { Write-Host "VERIFIED: orders matches orders_copy" -ForegroundColor Green; exit 0 }
else              { Write-Host "NOT VERIFIED: $after rows still differ" -ForegroundColor Red; exit 1 }