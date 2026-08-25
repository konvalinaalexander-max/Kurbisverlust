#!/usr/bin/env bash
# Spielt Stub + alle Migrationen + die Prüfabfragen in eine frische
# Test-Datenbank ein. Bricht bei der ersten Fehlermeldung ab.
#   ./supabase/test/run.sh 'postgresql://…'   (Default: lokaler Cluster)
set -euo pipefail
URL="${1:-postgresql://postgres@/postgres?host=/tmp&port=55432}"
HIER="$(cd "$(dirname "$0")" && pwd)"

psql "$URL" -v ON_ERROR_STOP=1 -q -c "set client_min_messages = warning;
     drop schema if exists public cascade;  create schema public;
     drop schema if exists auth cascade;    drop schema if exists storage cascade;" 
psql "$URL" -v ON_ERROR_STOP=1 -q -f "$HIER/stub_supabase.sql"
for f in "$HIER"/../migrations/*.sql; do
  echo "-- $(basename "$f")"
  psql "$URL" -v ON_ERROR_STOP=1 -q -f "$f"
done
psql "$URL" -v ON_ERROR_STOP=1 -f "$HIER/pruefung.sql"
