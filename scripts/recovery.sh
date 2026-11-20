#!/usr/bin/env bash
#
# recover.sh - undo one bad transaction with MariaDB FLASHBACK (Linux version of recover.ps1).
#
# Usage:
#   scripts/recover.sh -l /var/lib/mysql/mariadb-bin.000040 -s 345 -e 363625 [options]
#
# Required:
#   -l LOGFILE   binary log file that contains the incident (full path)
#   -s START     start position of the incident (from the START marker)
#   -e STOP      stop position of the incident (from the STOP marker)
# Optional:
#   -d DATABASE  database name                (default: shop)
#   -c CNF       option file with credentials (default: config/recovery.cnf)
#   -i           inspect: add --verbose so the output file is human-readable (large)
#   -f           force: continue even if the server wrote to the log after the incident
#   -h           show this help
#
# Notes:
#   - The binlog files in /var/lib/mysql are usually owned by the mysql user. If your user
#     cannot read them, the script uses sudo for mariadb-binlog only, then hands the
#     generated file back to you.
#   - Needs orders_copy (the known-good snapshot made by sql/disaster.sql).

set -euo pipefail

DB="shop"
CNF="config/recovery.cnf"
LOGFILE=""
START=""
STOP=""
INSPECT=0
FORCE=0

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; }
fail()  { echo "ERROR: $*" >&2; exit 1; }

while getopts "l:s:e:d:c:ifh" opt; do
    case "$opt" in
        l) LOGFILE="$OPTARG" ;;
        s) START="$OPTARG" ;;
        e) STOP="$OPTARG" ;;
        d) DB="$OPTARG" ;;
        c) CNF="$OPTARG" ;;
        i) INSPECT=1 ;;
        f) FORCE=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

# ---------- 1. validate ----------
[[ -n "$LOGFILE" && -n "$START" && -n "$STOP" ]] || { usage; fail "-l, -s and -e are required"; }
[[ "$START" =~ ^[0-9]+$ && "$STOP" =~ ^[0-9]+$ ]] || fail "-s and -e must be whole numbers"
(( START < STOP )) || fail "start position ($START) must be smaller than stop position ($STOP)"
[[ -e "$LOGFILE" ]] || fail "Log file not found (or not visible to this user): $LOGFILE"
[[ -f "$CNF" ]] || fail "Option file not found: $CNF (copy config/recovery.cnf.example)"
command -v mariadb >/dev/null || fail "mariadb client not found on PATH"

# MariaDB 10.5+ calls it mariadb-binlog; older installs only have mysqlbinlog.
if   command -v mariadb-binlog >/dev/null; then BINLOG_TOOL="mariadb-binlog"
elif command -v mysqlbinlog    >/dev/null; then BINLOG_TOOL="mysqlbinlog"
else fail "mariadb-binlog (or mysqlbinlog) not found on PATH"; fi

CNF="$(realpath "$CNF")"

sql() {  # run one SQL statement, tab-separated output without headers
    mariadb "--defaults-extra-file=$CNF" "$DB" -N -B -e "$1"
}

now() { echo "${EPOCHREALTIME}"; }                     # seconds with microseconds (bash 5+)
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b - a }'; }

# Rows in orders that differ from the snapshot, plus any difference in row count.
MISMATCH_SQL="
SELECT (SELECT COUNT(*) FROM orders o JOIN orders_copy c ON c.order_id = o.order_id
        WHERE NOT (o.customer_id <=> c.customer_id
               AND o.ordered_at  <=> c.ordered_at
               AND o.status      <=> c.status))
     + ABS((SELECT COUNT(*) FROM orders) - (SELECT COUNT(*) FROM orders_copy));"

# ---------- 2. is there damage to repair? ----------
BEFORE="$(sql "$MISMATCH_SQL")"
echo "Rows differing from orders_copy before recovery: $BEFORE"
if [[ "$BEFORE" == "0" ]]; then
    echo "Nothing to recover: orders already matches orders_copy."
    exit 0
fi

# ---------- 3. safety check: nothing written after the incident ----------
read -r CUR_FILE CUR_POS _ < <(sql "SHOW MASTER STATUS")
LOG_NAME="$(basename "$LOGFILE")"
if [[ "$CUR_FILE" != "$LOG_NAME" || "$CUR_POS" != "$STOP" ]]; then
    msg="Server is at $CUR_FILE:$CUR_POS but the incident ends at $LOG_NAME:$STOP. Something else was written after the incident, and a flashback of this window will not undo it."
    if (( FORCE )); then echo "WARNING: $msg (continuing because of -f)"
    else fail "$msg Check the positions, or use -f to continue anyway."; fi
fi

# ---------- 4. generate the flashback file, timed ----------
mkdir -p out
OUT="out/flashback_$(date +%Y%m%d_%H%M%S).sql"
ARGS=(--flashback "--start-position=$START" "--stop-position=$STOP" "--database=$DB" "--result-file=$OUT")
(( INSPECT )) && ARGS+=(--verbose)

T0="$(now)"
if [[ -r "$LOGFILE" ]]; then
    "$BINLOG_TOOL" "${ARGS[@]}" "$LOGFILE"
else
    echo "Log file is not readable by $USER; using sudo for $BINLOG_TOOL only."
    sudo "$BINLOG_TOOL" "${ARGS[@]}" "$LOGFILE"
    sudo chown "$(id -u):$(id -g)" "$OUT"
fi
T1="$(now)"
[[ -s "$OUT" ]] || fail "No flashback output was produced ($OUT is empty). Check the log file and positions."
GEN_SEC="$(elapsed "$T0" "$T1")"
echo "Generated $OUT in ${GEN_SEC} s"

# ---------- 5. apply it, timed ----------
# Redirect instead of SOURCE, so paths with spaces cannot break it.
T2="$(now)"
mariadb "--defaults-extra-file=$CNF" "$DB" < "$OUT"
T3="$(now)"
APPLY_SEC="$(elapsed "$T2" "$T3")"
echo "Applied in ${APPLY_SEC} s"

# ---------- 6. verify ----------
AFTER="$(sql "$MISMATCH_SQL")"
echo "Status counts now:"
sql "SELECT status, COUNT(*) FROM orders GROUP BY status" | sed 's/^/  /'

# ---------- 7. summary ----------
TOTAL_SEC="$(elapsed "$T0" "$T3")"
echo
echo "================ SUMMARY ================"
echo "Rows differing from snapshot : $BEFORE -> $AFTER"
echo "Generate flashback file      : ${GEN_SEC} s"
echo "Apply                        : ${APPLY_SEC} s"
echo "Total                        : ${TOTAL_SEC} s"
echo "Flashback file               : $OUT"
if [[ "$AFTER" == "0" ]]; then
    echo "VERIFIED: orders matches orders_copy"
else
    echo "NOT VERIFIED: $AFTER rows still differ"
    exit 1
fi