#!/usr/bin/env bash
# Die schnelle Stufe des Prüfrituals (CLAUDE.md § 3, seit Runde AJ): was vor
# jedem Push grün sein muss, in Minuten. Die volle Stufe (run.sh, Bildschirme,
# Abnahme) läuft einmal am Tag oder vor einem Push, der Bildschirme oder das
# Rechenwerk breit ändert.
#
#   ./pruefstand/schnell.sh '<url>'                 # url: die Prüf- oder Demo-Datenbank
#   ./pruefstand/schnell.sh '<url>' 0106            # dazu die Migration und den Prüfblock der Runde
#
# Der Prüfblock der Runde liegt als Datei neben der Migration:
# supabase/test/bloecke/<nnnn>.sql (der Block aus pruefung.sql, allein
# lauffähig). Mutationen fährt die Runde selbst (docs/ENTSCHEIDUNGEN.md sagt,
# welche); dieses Skript prüft nur, dass der Block im Original grün ist.
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
URL="${1:?Datenbank-URL fehlt}"
RUNDE="${2:-}"
cd "$HIER/.."

echo "── 1. Typen und Tests ─────────────────────────────────────"
npx tsc -b
npm test --silent

echo "── 2. setup.sql verdichten ───────────────────────────────"
./supabase/setup_bauen.sh > /dev/null
./supabase/test/keine_zerstoerung.sh

if [ -n "$RUNDE" ]; then
  echo "── 3. Migration und Prüfblock der Runde $RUNDE ───────────"
  MIG="$(ls supabase/migrations/${RUNDE}_*.sql | head -1)"
  psql "$URL" -v ON_ERROR_STOP=1 -q -f "$MIG"
  if [ -f "supabase/test/bloecke/${RUNDE}.sql" ]; then
    psql "$URL" -v ON_ERROR_STOP=1 -q -f "supabase/test/bloecke/${RUNDE}.sql" | tail -2
  else
    echo "   (kein Block unter supabase/test/bloecke/${RUNDE}.sql — nur die Migration eingespielt)"
  fi
fi

echo "── 4. Die Kette (Halle → Datenbank → Dashboard) ──────────"
node pruefstand/kette.mjs
./pruefstand/kette_pruefen.sh "$URL"

echo "── 5. Beschriftung ───────────────────────────────────────"
node pruefstand/beschriftung.mjs

echo "schnelle Stufe grün — die volle Stufe (run.sh, bildschirme, abnahme) einmal am Tag"
