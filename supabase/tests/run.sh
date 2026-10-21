#!/usr/bin/env bash
# Lance les tests SQL sur un Postgres local (PGHOST/PGPORT/PGUSER standards). Usage : ./run.sh
set -euo pipefail
cd "$(dirname "$0")"
DB=grnfr_test
dropdb --if-exists "$DB" >/dev/null 2>&1 || true
createdb "$DB"
P="psql -d $DB -v ON_ERROR_STOP=1 -q"
$P -f stub_supabase.sql
for f in ../migrations/*.sql; do $P -f "$f" 2>&1 | grep -v NOTICE || true; done
$P -f tests.sql 2>&1 >/dev/null | sed 's/^psql:[^ ]* //'
