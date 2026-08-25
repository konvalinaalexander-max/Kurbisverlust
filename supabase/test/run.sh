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
echo "── 4. Demo-Daten, genau wie im SQL-Editor (ohne Login!) ──────"
# Kein set_config hier: Der Supabase-SQL-Editor hat keinen angemeldeten
# Benutzer, auth.uid() ist dort NULL. Ein Test, der vorher heimlich einen
# Login setzt, prüft etwas anderes als die Wirklichkeit.
psql "$URL" -v ON_ERROR_STOP=1 -q -c "
  insert into auth.users (id, email, raw_user_meta_data)
  values ('11111111-1111-1111-1111-111111111111', 'chef@hof.test', '{\"name\":\"Chef\"}');
  update profil set rolle = 'admin' where id = '11111111-1111-1111-1111-111111111111';"
DEMO="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -c "$(cat "$HIER/../demo_daten.sql")")"
echo "   $DEMO"
case "$DEMO" in
  *Demo-Saison\ steht*) ;;
  *) echo "   FEHLER: Demo-Daten liessen sich nicht laden"; exit 1 ;;
esac
UEBRIG="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -c "$(cat "$HIER/../demo_daten_entfernen.sql")")"
echo "   $UEBRIG"
VERWAIST="$(psql "$URL" -qtA -c "select (select count(*) from verdunstung_wiegung)
  + (select count(*) from ausgang_wiegung) + (select count(*) from sortier_gewicht)
  + (select count(*) from schimmel_messung)")"
[ "$VERWAIST" = "0" ] || { echo "   FEHLER: $VERWAIST verwaiste Zeilen nach dem Entfernen"; exit 1; }
echo "   nichts Verwaistes zurückgeblieben"

echo
echo "── 5. Tempo der Auswertung ───────────────────────────────────"
# Supabase bricht Abfragen nach 8 Sekunden ab. Das Dashboard holt ein Dutzend
# Ansichten gleichzeitig — einmal lagen sie zusammen über 9 Sekunden, weil eine
# Funktion pro Zeile die halbe Auswertung neu rechnete. Diese Stufe fängt es ab,
# bevor es wieder jemandem beim Klicken um die Ohren fliegt.
# Das Betriebsleiter-Konto steht bereits aus Stufe 4
psql "$URL" -v ON_ERROR_STOP=1 -qtA -c "$(cat "$HIER/../demo_daten.sql")" >/dev/null
psql "$URL" -q -c "analyze" >/dev/null

GESAMT=0
for V in v_hochrechnung v_massenbilanz v_datenlage v_marge_buch v_plausibilitaet \
         v_wiegung_kennzahl v_kaliber_verteilung v_schimmel_kurve_anzeige \
         v_koeff_verdunstung v_koeff_ausschuss v_koeff_nebenkanal v_koeff_ueberfuellung; do
  MS="$(psql "$URL" -qtA -c "\timing on" -c "select count(*) from $V" 2>&1 \
        | grep -oE 'Time: [0-9.]+ ms' | grep -oE '[0-9.]+')"
  GESAMT="$(echo "$GESAMT + $MS" | bc)"
done
echo "   alle zwölf Dashboard-Ansichten: ${GESAMT} ms"
# 3 Sekunden: grosszügig gegenüber langsamer CI-Hardware, aber weit unter den
# 8 Sekunden, bei denen Supabase abbricht.
if [ "$(echo "$GESAMT > 3000" | bc)" = "1" ]; then
  echo "   FEHLER: zu langsam — auf Supabase droht der Abbruch"; exit 1
fi
psql "$URL" -q -c "$(cat "$HIER/../demo_daten_entfernen.sql")" >/dev/null

echo
echo "── 6. setup.sql gegen die Migrationen abgleichen ─────────────"
VORHER="$(cat "$HIER/../setup.sql")"
"$HIER/../setup_bauen.sh" >/dev/null
if [ "$VORHER" != "$(cat "$HIER/../setup.sql")" ]; then
  echo "   FEHLER: setup.sql ist veraltet — ./supabase/setup_bauen.sh ausführen und mitcommitten"
  exit 1
fi
echo "   aktuell"

echo
echo "——— alle Prüfungen bestanden ———"
