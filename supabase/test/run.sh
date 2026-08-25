#!/usr/bin/env bash
# Prüft die Datenbankseite komplett:
#   1. Migrationen einzeln einspielen und die Fachlogik durchrechnen
#   2. setup.sql so einspielen, wie der Supabase-SQL-Editor es sendet
#      (alles als ein Query, also eine Transaktion)
#   3. setup.sql ein zweites Mal — muss freundlich abbrechen, nichts ändern
#   4. setup.sql gegen die Migrationen abgleichen (kein Auseinanderdriften)
#
#   ./supabase/test/run.sh 'postgresql://…'   (Default: lokaler Cluster)
set -euo pipefail
URL="${1:-postgresql://postgres@/postgres?host=/tmp&port=55432}"
HIER="$(cd "$(dirname "$0")" && pwd)"

zuruecksetzen() {
  psql "$URL" -v ON_ERROR_STOP=1 -q -c "set client_min_messages = warning;
     drop schema if exists public cascade;  create schema public;
     drop schema if exists auth cascade;    drop schema if exists storage cascade;"
  psql "$URL" -v ON_ERROR_STOP=1 -q -f "$HIER/stub_supabase.sql"
}

echo "── 1. Migrationen und Fachlogik ──────────────────────────────"
zuruecksetzen
for f in "$HIER"/../migrations/*.sql; do
  echo "   $(basename "$f")"
  psql "$URL" -v ON_ERROR_STOP=1 -q -f "$f"
done
psql "$URL" -v ON_ERROR_STOP=1 -f "$HIER/pruefung.sql"

echo
echo "── 2. setup.sql als ein Query (wie der Supabase-Editor) ──────"
zuruecksetzen
AUSGABE="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -c "$(cat "$HIER/../setup.sql")")"
echo "   $AUSGABE"
case "$AUSGABE" in
  Fertig.*Chargen*) ;;
  *) echo "   FEHLER: setup.sql meldet keinen Erfolg"; exit 1 ;;
esac

echo
echo "── 3. setup.sql ein zweites Mal ──────────────────────────────"
if ZWEITE="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -c "$(cat "$HIER/../setup.sql")" 2>&1)"; then
  echo "   FEHLER: der zweite Durchlauf hätte abbrechen müssen"; exit 1
fi
case "$ZWEITE" in
  *"bereits eingespielt"*) echo "   bricht freundlich ab, wie vorgesehen" ;;
  *) echo "   FEHLER: unerwartete Meldung:"; echo "$ZWEITE"; exit 1 ;;
esac
VERBLIEBEN="$(psql "$URL" -qtA -c 'select count(*) from charge')"
[ "$VERBLIEBEN" = "42" ] || { echo "   FEHLER: Daten beschädigt ($VERBLIEBEN Chargen)"; exit 1; }
echo "   Daten unversehrt ($VERBLIEBEN Chargen)"

echo
echo "── 4. setup.sql gegen die Migrationen abgleichen ─────────────"
VORHER="$(cat "$HIER/../setup.sql")"
"$HIER/../setup_bauen.sh" >/dev/null
if [ "$VORHER" != "$(cat "$HIER/../setup.sql")" ]; then
  echo "   FEHLER: setup.sql ist veraltet — ./supabase/setup_bauen.sh ausführen und mitcommitten"
  exit 1
fi
echo "   aktuell"

echo
echo "——— alle Prüfungen bestanden ———"
