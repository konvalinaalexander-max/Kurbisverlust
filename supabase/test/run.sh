#!/usr/bin/env bash
# Prüft die Datenbankseite komplett:
#   1. Migrationen einzeln einspielen und die Fachlogik durchrechnen
#   2. setup.sql so einspielen, wie der Supabase-SQL-Editor es sendet
#      (alles als ein Query, also eine Transaktion)
#   3. setup.sql ein zweites Mal — muss durchlaufen und dieselbe DB hinterlassen
#  3b. Aktualisierung: alter Stand mit Daten, dann die heutige setup.sql drüber
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
# 0057: Datenbank und App müssen sich über den Stand einig sein — sonst sagt
# die App „veraltet", obwohl gerade alles eingespielt wurde (oder umgekehrt).
HOECHSTE="$(basename "$(ls "$HIER"/../migrations/*.sql | tail -1)" | cut -c1-4 | sed 's/^0*//')"
STAND="$(psql "$URL" -qtA -c 'select schema_stand()')"
[ "$STAND" = "$HOECHSTE" ] \
  || { echo "   FEHLER: schema_stand() sagt $STAND, die höchste Migration ist $HOECHSTE — in der neuen Migration nachziehen"; exit 1; }
ERWARTET="$(grep -oE 'SCHEMA_ERWARTET = [0-9]+' "$HIER/../../src/lib/version.ts" | grep -oE '[0-9]+')"
[ "$ERWARTET" = "$HOECHSTE" ] \
  || { echo "   FEHLER: src/lib/version.ts erwartet $ERWARTET, die höchste Migration ist $HOECHSTE"; exit 1; }
echo "   Stand: Migration $HOECHSTE — Datenbank, App und Migrationen einig"
psql "$URL" -v ON_ERROR_STOP=1 -f "$HIER/pruefung.sql"

echo
echo "── 2. setup.sql als ein Query (wie der Supabase-Editor) ──────"
zuruecksetzen
AUSGABE="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -1 -f "$HIER/../setup.sql" | tail -1)"
echo "   $AUSGABE"
case "$AUSGABE" in
  Fertig.*Chargen*) ;;
  *) echo "   FEHLER: setup.sql meldet keinen Erfolg"; exit 1 ;;
esac
echo "$AUSGABE" | grep -q 'Auswertung berechnet' \
  || { echo "   FEHLER: die Auswertung wurde am Ende nicht berechnet"; exit 1; }

FRISCH="$(mktemp)"
psql "$URL" -v ON_ERROR_STOP=1 -f "$HIER/fingerabdruck.sql" > "$FRISCH"
echo "   Fingerabdruck der frischen Datenbank: $(wc -l < "$FRISCH") Objekte"

echo
echo "── 3. setup.sql ein zweites Mal ──────────────────────────────"
# Früher musste der zweite Durchlauf abbrechen. Das war bequem und falsch:
# eine einmal eingerichtete Datenbank konnte damit nie wieder etwas Neues
# bekommen, und ein Betrieb lief monatelang auf einem Stand, den die App
# längst überholt hatte. Jetzt gilt das Gegenteil — der zweite Durchlauf
# muss gelingen und dieselbe Datenbank hinterlassen.
if ! ZWEITE="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -1 -f "$HIER/../setup.sql" 2>&1)"; then
  echo "   FEHLER: der zweite Durchlauf ist gescheitert:"
  echo "$ZWEITE" | grep -iE 'error|fehler' | head -10; exit 1
fi
echo "   $(echo "$ZWEITE" | tail -1)"
echo "$ZWEITE" | tail -1 | grep -q 'Auswertung berechnet' \
  || { echo "   FEHLER: die Auswertung wurde am Ende nicht berechnet"; exit 1; }
VERBLIEBEN="$(psql "$URL" -qtA -c 'select count(*) from charge')"
[ "$VERBLIEBEN" = "42" ] || { echo "   FEHLER: Daten beschädigt ($VERBLIEBEN Chargen)"; exit 1; }
psql "$URL" -v ON_ERROR_STOP=1 -f "$HIER/fingerabdruck.sql" > "$FRISCH.zwei"
diff -q "$FRISCH" "$FRISCH.zwei" >/dev/null \
  || { echo "   FEHLER: das Schema hat sich beim zweiten Durchlauf verändert:";
       diff "$FRISCH" "$FRISCH.zwei" | head -20; exit 1; }
echo "   läuft durch, Daten unversehrt ($VERBLIEBEN Chargen), Schema unverändert"

echo
echo "── 3b. Aktualisierung von einem alten Stand ──────────────────"
# Der Fall, der das Ganze nötig gemacht hat: Auf dem Hof lief eine Datenbank,
# die vor 0016 eingerichtet worden war. Die App rief auswertung_aktualisieren()
# — eine Funktion, die es dort nie gegeben hatte. Diese Stufe spielt genau das
# nach: alter Stand, echte Daten drin, dann die heutige setup.sql drüber.
zuruecksetzen
for n in 0000 0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 0011 0012 0013 0014 0015; do
  psql "$URL" -v ON_ERROR_STOP=1 -q -f "$HIER"/../migrations/${n}_*.sql
done
psql "$URL" -v ON_ERROR_STOP=1 -q -c "
  insert into auth.users (id, email, raw_user_meta_data)
  values ('11111111-1111-1111-1111-111111111111', 'chef@hof.test', '{\"name\":\"Chef\"}');
  update profil set rolle = 'admin' where id = '11111111-1111-1111-1111-111111111111';
  insert into palette (charge_nr, eingangsdatum, kisten, brutto_kg, gebindeart)
  values (1598, '2026-10-01', 30, 900, 'G2'), (1599, '2026-10-02', 20, 600, 'G2');
  update einstellung set wert = '9'::jsonb where schluessel = 'soll_kg_pro_kiste';"
# Der Wächter aus 0048: Hält der alte Stand noch Zeilen im Alt-Kanal
# marge_messung, darf die Aktualisierung sie nicht still wegwerfen — sie muss
# abbrechen und sagen, was zu tun ist. Erst mit leerer Tabelle geht es weiter.
psql "$URL" -v ON_ERROR_STOP=1 -q -c "
  insert into auftrag (weg, station, charge_nr, eroeffnet_von)
  values ('hand', 'waschen_sortieren', 1598, '11111111-1111-1111-1111-111111111111');
  insert into marge_messung (auftrag_id, art, wert, n_kisten, erfasser)
  select id, 'ueberfuellung', 12, 30, '11111111-1111-1111-1111-111111111111' from auftrag;"
if WAECHTER="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -1 -f "$HIER/../setup.sql" 2>&1)"; then
  echo "   FEHLER: setup.sql lief über eine gefüllte marge_messung hinweg"; exit 1
fi
echo "$WAECHTER" | grep -q 'marge_messung enthält 1 Zeile' \
  || { echo "   FEHLER: der Abbruch nennt nicht den Grund:"; echo "$WAECHTER" | head -5; exit 1; }
echo "   gefüllte marge_messung: Aktualisierung bricht ab und sagt, was zu tun ist"
psql "$URL" -v ON_ERROR_STOP=1 -q -c "delete from auftrag;"

if ! ALT="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -1 -f "$HIER/../setup.sql" 2>&1)"; then
  echo "   FEHLER: die Aktualisierung ist gescheitert:"
  echo "$ALT" | grep -iE 'error|fehler' | head -10; exit 1
fi
echo "   $(echo "$ALT" | tail -1)"
echo "$ALT" | tail -1 | grep -q 'Auswertung berechnet' \
  || { echo "   FEHLER: die Auswertung wurde am Ende nicht berechnet"; exit 1; }

# a) Die Daten müssen da sein — auch die von Hand geänderte Einstellung.
PAL="$(psql "$URL" -qtA -c 'select count(*) from palette')"
SOLL="$(psql "$URL" -qtA -c "select wert::text from einstellung where schluessel = 'soll_kg_pro_kiste'")"
[ "$PAL" = "2" ] || { echo "   FEHLER: Paletten verloren ($PAL statt 2)"; exit 1; }
[ "$SOLL" = "9" ] || { echo "   FEHLER: eigene Einstellung überschrieben ($SOLL statt 9)"; exit 1; }

# b) Genau die Funktion, deren Fehlen den Fehler ausgelöst hat, muss rufbar sein.
psql "$URL" -v ON_ERROR_STOP=1 -qtA -c 'select auswertung_aktualisieren()' >/dev/null \
  || { echo "   FEHLER: auswertung_aktualisieren() fehlt weiterhin"; exit 1; }

# c) Und das Schema muss Objekt für Objekt dem einer Neueinrichtung gleichen.
#    Das ist die eigentliche Zusage: "aktualisiert" heisst nicht "läuft durch",
#    sondern "nicht zu unterscheiden von frisch eingerichtet".
psql "$URL" -v ON_ERROR_STOP=1 -f "$HIER/fingerabdruck.sql" > "$FRISCH.alt"
diff -q "$FRISCH" "$FRISCH.alt" >/dev/null \
  || { echo "   FEHLER: die aktualisierte Datenbank weicht von einer frischen ab:";
       diff "$FRISCH" "$FRISCH.alt" | head -20; exit 1; }
echo "   Daten erhalten, Auswertung rufbar, Schema wie frisch eingerichtet"
rm -f "$FRISCH" "$FRISCH.zwei" "$FRISCH.alt"

zuruecksetzen
psql "$URL" -v ON_ERROR_STOP=1 -q -1 -f "$HIER/../setup.sql" >/dev/null

echo
echo "── 4. Demo-Daten, genau wie im SQL-Editor (ohne Login!) ──────"
# Kein set_config hier: Der Supabase-SQL-Editor hat keinen angemeldeten
# Benutzer, auth.uid() ist dort NULL. Ein Test, der vorher heimlich einen
# Login setzt, prüft etwas anderes als die Wirklichkeit.
psql "$URL" -v ON_ERROR_STOP=1 -q -c "
  insert into auth.users (id, email, raw_user_meta_data)
  values ('11111111-1111-1111-1111-111111111111', 'chef@hof.test', '{\"name\":\"Chef\"}');
  update profil set rolle = 'admin' where id = '11111111-1111-1111-1111-111111111111';"
DEMO="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -1 -f "$HIER/../demo_daten.sql" | tail -1)"
echo "   $DEMO"
case "$DEMO" in
  *Demo-Saison\ steht*) ;;
  *) echo "   FEHLER: Demo-Daten liessen sich nicht laden"; exit 1 ;;
esac
UEBRIG="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -1 -f "$HIER/../demo_daten_entfernen.sql" | tail -1)"
echo "   $UEBRIG"
VERWAIST="$(psql "$URL" -qtA -c "select (select count(*) from verdunstung_wiegung)
  + (select count(*) from ausgang_wiegung) + (select count(*) from sortier_gewicht)
  + (select count(*) from schimmel_messung)")"
[ "$VERWAIST" = "0" ] || { echo "   FEHLER: $VERWAIST verwaiste Zeilen nach dem Entfernen"; exit 1; }
echo "   nichts Verwaistes zurückgeblieben"

echo
echo "── 4b. Aktualisierung mit Paletten, die schwerer geworden sind ─"
# Der Fall vom 7. September: Beim Nachwiegen wog eine Palette mehr als beim
# Eingang (Tara, Kistenzahl, Zahlendreher). Die Rate daraus war negativ, die
# Basis für den Schimmelanteil lief über (numeric field overflow) — im
# Überblick, und in setup.sql selbst, weil die Zwischenfassungen der Formeln
# auf den echten Daten rechneten. Beides darf nie wieder passieren: die
# Aktualisierung muss durchlaufen, die Auswertung am Ende gerechnet sein,
# und die drei Wägungen stehen mit Grund unter den Auffälligkeiten.
psql "$URL" -v ON_ERROR_STOP=1 -qtA -1 -f "$HIER/../demo_daten.sql" >/dev/null
psql "$URL" -v ON_ERROR_STOP=1 -q -c "
  insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                   kisten, gebindeart, sichtbar_schimmel, gemessen, wiege_ts, bemerkung, erfasser)
  select charge_nr, eingangsdatum, 420, 1180, kisten, gebindeart, false, true, eingangsdatum + 2,
         'PRUEF-0056', '11111111-1111-1111-1111-111111111111'
    from verdunstung_wiegung order by id limit 3;"
if ! SCHWER="$(psql "$URL" -v ON_ERROR_STOP=1 -qtA -1 -f "$HIER/../setup.sql" 2>&1)"; then
  echo "   FEHLER: die Aktualisierung scheitert an einer schwereren Palette:"
  echo "$SCHWER" | grep -iE 'error|fehler' | head -10; exit 1
fi
echo "$SCHWER" | tail -1 | grep -q 'Auswertung berechnet' \
  || { echo "   FEHLER: die Auswertung wurde am Ende nicht berechnet: $(echo "$SCHWER" | tail -1)"; exit 1; }
for V in v_saisonbilanz v_plausibilitaet v_schimmel_punkte v_hochrechnung v_koeff_verdunstung; do
  psql "$URL" -v ON_ERROR_STOP=1 -qtA -c "select count(*) from $V" >/dev/null \
    || { echo "   FEHLER: $V läuft mit den schwereren Paletten nicht"; exit 1; }
done
RATE="$(psql "$URL" -qtA -c "select round(min(mittel), 6) from v_koeff_verdunstung")"
[ -n "$RATE" ] && [ "$(echo "$RATE < 0" | bc)" = "0" ] \
  || { echo "   FEHLER: die Verdunstungsrate ist negativ oder fehlt ($RATE)"; exit 1; }
BEFUND="$(psql "$URL" -qtA -c "select count(*) from v_plausibilitaet where art = 'Wägung' and befund like '%mehr als beim Eingang%'")"
[ "$BEFUND" = "3" ] || { echo "   FEHLER: $BEFUND statt 3 Auffälligkeiten „schwerer als beim Eingang\""; exit 1; }
echo "   läuft durch, Rate ≥ 0 (kleinste $RATE), drei Auffälligkeiten nennen den Grund"
psql "$URL" -q -c "delete from verdunstung_wiegung where bemerkung = 'PRUEF-0056'" >/dev/null
psql "$URL" -q -1 -f "$HIER/../demo_daten_entfernen.sql" >/dev/null

echo
echo "── 5. Tempo der Auswertung ───────────────────────────────────"
# Supabase bricht Abfragen nach 8 Sekunden ab. Das Dashboard holt ein Dutzend
# Ansichten gleichzeitig — einmal lagen sie zusammen über 9 Sekunden, weil eine
# Funktion pro Zeile die halbe Auswertung neu rechnete. Diese Stufe fängt es ab,
# bevor es wieder jemandem beim Klicken um die Ohren fliegt.
# Seit 0061 liest das Dashboard nur gespeicherte Ergebnisse (erg_*) — die Liste
# kommt aus dem Frontend selbst, damit sie nicht auseinanderdriftet; gerechnet
# wird in fünf Schritten, jeder muss für sich unter der Supabase-Grenze bleiben.
ANSICHTEN="$(grep -ohE "\berg_[a-z_]+" "$HIER/../../src/auswertung/daten.ts" "$HIER/../../src/pages"/*.tsx | sort -u | tr '\n' ' ')"
[ -n "$ANSICHTEN" ] || { echo "   FEHLER: keine erg_-Ansicht im Frontend gefunden"; exit 1; }
# Das Betriebsleiter-Konto steht bereits aus Stufe 4
psql "$URL" -v ON_ERROR_STOP=1 -qtA -1 -f "$HIER/../demo_daten.sql" >/dev/null
psql "$URL" -q -c "select auswertung_aktualisieren()" >/dev/null
psql "$URL" -q -c "analyze" >/dev/null
schritte_pruefen() {
  # jeder der fünf Schritte einzeln, mit seiner Dauer — keiner darf der
  # 8-Sekunden-Grenze nahekommen (Grenze hier: 6 s, grosszügig für CI-Hardware)
  local n ms
  for n in 1 2 3 4 5; do
    ms="$(psql "$URL" -qtA -c "select (auswertung_schritt($n) ->> 'dauer_ms')::int")"
    printf '   Schritt %s: %s ms\n' "$n" "$ms"
    if [ "$ms" -gt 6000 ]; then echo "   FEHLER: Schritt $n zu langsam — auf Supabase droht der Abbruch"; exit 1; fi
  done
}
schritte_pruefen

GESAMT=0
for V in $ANSICHTEN; do
  MS="$(psql "$URL" -qtA -c "\timing on" -c "select count(*) from $V" 2>&1 \
        | grep -oE 'Time: [0-9.]+ ms' | grep -oE '[0-9.]+')"
  GESAMT="$(echo "$GESAMT + $MS" | bc)"
done
echo "   alle $(echo "$ANSICHTEN" | wc -w) gespeicherten Dashboard-Ansichten: ${GESAMT} ms"
# 3 Sekunden: grosszügig gegenüber langsamer CI-Hardware, aber weit unter den
# 8 Sekunden, bei denen Supabase abbricht.
if [ "$(echo "$GESAMT > 3000" | bc)" = "1" ]; then
  echo "   FEHLER: zu langsam — auf Supabase droht der Abbruch"; exit 1
fi
psql "$URL" -q -1 -f "$HIER/../demo_daten_entfernen.sql" >/dev/null

echo
echo "── 6. Lasttest: dreifache Saisongrösse ───────────────────────"
# Die Demo-Saison ist zu klein, um Tempo zu beurteilen. Hier wird deutlich mehr
# erzeugt, als je anfallen sollte — wenn das zügig läuft, läuft auch die echte
# Saison. Ohne diese Stufe würde die Zusage "skaliert" mit der Zeit verrotten.
zuruecksetzen
psql "$URL" -v ON_ERROR_STOP=1 -q -1 -f "$HIER/../setup.sql" >/dev/null
psql "$URL" -v ON_ERROR_STOP=1 -q -c "
  insert into auth.users (id, email, raw_user_meta_data)
  values ('11111111-1111-1111-1111-111111111111', 'chef@hof.test', '{\"name\":\"Chef\"}');
  update profil set rolle = 'admin' where id = '11111111-1111-1111-1111-111111111111';"
psql "$URL" -v ON_ERROR_STOP=1 -qtA -f "$HIER/last.sql" | tail -1 | sed 's/^/   /'

RECHNEN="$(psql "$URL" -qtA -c "select auswertung_aktualisieren()" >/dev/null; \
           psql "$URL" -qtA -c "select dauer_ms from auswertung_stand")"
echo "   Auswertung neu rechnen: ${RECHNEN} ms"
schritte_pruefen

GESAMT=0
for V in $ANSICHTEN; do
  MS="$(psql "$URL" -qtA -c "\timing on" -c "select count(*) from $V" 2>&1 \
        | grep -oE 'Time: [0-9.]+ ms' | grep -oE '[0-9.]+')"
  GESAMT="$(echo "$GESAMT + $MS" | bc)"
done
echo "   Dashboard bei voller Last: ${GESAMT} ms"
# Grosszügig gegenüber langsamer CI-Hardware, weit unter Supabases 8 Sekunden.
if [ "$(echo "$GESAMT > 2000" | bc)" = "1" ]; then
  echo "   FEHLER: Dashboard zu langsam bei voller Last"; exit 1
fi
# Die App ruft nie alles auf einmal — sie ruft die fünf Schritte nacheinander,
# und die sind oben einzeln geprüft. Diese Summe ist der Regressionsmelder:
# Sie darf wachsen, aber nicht davonlaufen (dreifache Saison, langsame CI).
if [ "$RECHNEN" -gt 12000 ]; then
  echo "   FEHLER: Neuberechnen im Ganzen zu langsam (${RECHNEN} ms) — ein Schritt ist entgleist"; exit 1
fi

echo
echo "── 6b. Lückenscanner: keine Lücke zwischen Maske und Auswertung ─"
# Fängt genau die Art Fehler, die diese Runde ausgelöst hat: eine Spalte, die
# die Datenbank erwartet und keine Maske schreibt (AB-02, AB-07), oder eine
# ausgewertete Tabelle, die niemand füllt. Braucht das Schema, darum hier — die
# Demo ist gerade entfernt, das genügt (geprüft wird das Schema, nicht Daten).
zuruecksetzen
psql "$URL" -v ON_ERROR_STOP=1 -q -1 -f "$HIER/../setup.sql" >/dev/null
"$HIER/../../pruefstand/luecken.sh" "$URL" | sed 's/^/   /'

echo
echo "── 7. setup.sql gegen die Migrationen abgleichen ─────────────"
VORHER="$(cat "$HIER/../setup.sql")"
"$HIER/../setup_bauen.sh" >/dev/null
if [ "$VORHER" != "$(cat "$HIER/../setup.sql")" ]; then
  echo "   FEHLER: setup.sql ist veraltet — ./supabase/setup_bauen.sh ausführen und mitcommitten"
  exit 1
fi
echo "   aktuell"

echo
echo "——— alle Prüfungen bestanden ———"
