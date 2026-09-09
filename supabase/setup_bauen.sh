#!/usr/bin/env bash
# Baut supabase/setup.sql aus supabase/migrations/ — die eine Datei, die der
# Nutzer im Supabase-SQL-Editor einfügt. Nach jeder Änderung an
# supabase/migrations/ hier neu laufen lassen; die CI prüft, dass beides
# zusammenpasst.
#
# Die Arbeit macht setup_bauen.mjs; warum verdichtet wird und wie, steht in
# supabase/verdichten.mjs.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
exec node "$HIER/setup_bauen.mjs"
