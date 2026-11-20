#!/usr/bin/env bash
#
# restore.sh - restore a full mariadb-dump, time it, and verify (Linux version of restore.ps1).
# This is the backup side of the FLASHBACK vs full-restore comparison.
#
# Usage:
#   scripts/restore.sh -b shop_backup.sql [options]
#
# Required:
#   -b DUMPFILE  the dump to restore (taken from healthy data, before the disaster)
# Optional:
#   -d DATABASE  database name                (default: shop)
#   -c CNF       option file with credentials (default: config/recovery.cnf)
#   -f           force: restore even if orders already matches orders_copy
#   -h           show this help
#
# Notes:
#   - Run it on the SAME damaged state you used for recover.sh (run sql/disaster.sql first).
#   - A restore overwrites the WHOLE database with the dump's contents: anything written
#     after the dump was taken is lost. FLASHBACK only reverses the one bad transaction.
#   - Verification compares orders with orders_copy. Both come from the dump, so this only
#     proves something because the dump's orders_copy was a healthy snapshot. Also compare
#     CHECKSUM TABLE output (sql/checksums.sql) before the disaster and after.

set -euo pipefail

DB="shop"
CNF="config/recovery.cnf"
DUMP=""
FORCE=0

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }
fail()  { echo "ERROR: $*" >&2; exit 1; }

while getopts "b:d:c:fh" opt; do
    case "$opt" in
        b) DUMP="$OPTARG" ;;
        d) DB="$OPTARG" ;;
        c) CNF="$OPTARG" ;;
        f) FORCE=1 ;;
        h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

# ---------- 1. validate ----------
[[ -n "$DUMP" ]] || { usage; fail "-b DUMPFILE is required"; }
[[ -f "$DUMP" ]] || fail "Dump file not found: $DUMP"
[[ -f "$CNF"  ]] || fail "Option file not found: $CNF (copy config/recovery.cnf.example)"
command -v mariadb >/dev/null || fail "mariadb client not found on PATH"
CNF="$(realpath "$CNF")"

sql() { mariadb "--defaults-extra-file=$CNF" "$DB" -N -B -e "$1"; }
now() { echo "${EPOCHREALTIME}"; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b - a }'; }

MISMATCH_SQL="
SELECT (SELECT COUNT(*) FROM orders o JOIN orders_copy c ON c.order_id = o.order_id
        WHERE NOT (o.customer_id <=> c.customer_id
               AND o.ordered_at  <=> c.ordered_at
               AND o.status      <=> c.status))
     + ABS((SELECT COUNT(*) FROM orders) - (SELECT COUNT(*) FROM orders_copy));"

SIZE_MB="$(awk -v b="$(stat -c %s "$DUMP")" 'BEGIN { printf "%.1f", b / 1048576 }')"
echo "Dump: $(basename "$DUMP") (${SIZE_MB} MB, written $(date -r "$DUMP" '+%Y-%m-%d %H:%M:%S'))"

# ---------- 2. is there damage to repair? ----------
BEFORE="$(sql "$MISMATCH_SQL")"
echo "Rows differing from orders_copy before restore: $BEFORE"
if [[ "$BEFORE" == "0" ]] && (( ! FORCE )); then
    fail "orders already matches orders_copy, so there is nothing to compare. Run sql/disaster.sql first (or use -f)."
fi

# ---------- 3. restore, timed ----------
T0="$(now)"
mariadb "--defaults-extra-file=$CNF" "$DB" < "$DUMP"
T1="$(now)"
RESTORE_SEC="$(elapsed "$T0" "$T1")"
echo "Restored in ${RESTORE_SEC} s"

# ---------- 4. verify ----------
AFTER="$(sql "$MISMATCH_SQL")"
echo "Status counts now:"
sql "SELECT status, COUNT(*) FROM orders GROUP BY status" | sed 's/^/  /'

# ---------- 5. summary ----------
echo
echo "================ SUMMARY ================"
echo "Rows differing from snapshot : $BEFORE -> $AFTER"
echo "Restore (whole database)     : ${RESTORE_SEC} s"
echo "Dump file                    : $DUMP"
if [[ "$AFTER" == "0" ]]; then
    echo "VERIFIED: orders matches orders_copy"
else
    echo "NOT VERIFIED: $AFTER rows still differ"
    exit 1
fi