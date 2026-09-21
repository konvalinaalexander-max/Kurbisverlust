#!/usr/bin/env bash
# Zieht die Antworten, die Supabase der App geben würde, als JSON-Dateien aus
# der lokalen Demo-Datenbank. Der Prüfstand (bildschirme.mjs) spielt sie der
# App dann als abgefangene Netzwerkantworten vor — echte Datenformen, echte
# Zahlen, kein ausgedachtes Fixture, das mit dem Schema auseinanderläuft.
set -euo pipefail
U="${1:-postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432}"
HIER="$(cd "$(dirname "$0")" && pwd)"
# Zweites Argument: ein anderer Zielordner (Runde N: gegenprobe/bildschirm/daten für die böse Saison).
ZIEL="${2:-$HIER/daten}"
mkdir -p "$ZIEL"

dump() {
  psql "$U" -qtA -c "select coalesce(json_agg(t), '[]'::json) from ($2) t" > "$ZIEL/$1.json"
}

# Tabellen und Ansichten, die die App liest — seit 0061 die gespeicherten
# Ergebnisse (erg_*), dazu die Tabellen und die wenigen Sichten der Masken.
for R in v_hochrechnung erg_massenbilanz erg_datenlage erg_marge erg_plausibilitaet \
         erg_kaliber erg_kurve erg_koeff_verdunstung erg_koeff_ausschuss erg_koeff_nebenkanal \
         erg_koeff_ueberfuellung erg_gewichte erg_verarbeitung_alter erg_durchsatz erg_ueberfuellung \
         erg_datenqualitaet erg_verlauf erg_verlust erg_gebinde erg_lieferung erg_modell erg_selektion \
         erg_bilanz erg_punkte erg_charge erg_naechste_charge erg_kohorte erg_fax erg_ausschuss erg_ausgang \
         erg_prognose erg_wohin erg_fax_wartezeit erg_koeff_fax erg_marge_wiegung \
         v_palox_stand v_lieferung_masse v_auftrag_masse auswertung_stand v_kohorte_anteil v_koeff_fax \
         ausgang_quelle ausgang_artikel v_ausgang_lage v_ausgang_artikel_vorschlag \
         charge sorte_kaliber gebinde einstellung ausgang_ziel kaeufer sortierschema \
         v_ausgang_kennzahl profil palette v_kontrolle_vorschlag v_lieferung_kohorte v_koeff_palette_netto \
         ausgang_wiegung v_auftrag_angabe v_verkauf_lieferung v_auftrag_wasch_paletten \
         auftrag auftrag_palette auftrag_gebinde schimmel_messung ausschuss_messung \
         verdunstung_wiegung ausgang_zeile \
         kontrollpalette kontrollpalette_wiegung v_kontrollpalette_vorschlag v_ausgang_voll \
         sortier_lauf v_charge_rueckgrat; do
  dump "$R" "select * from $R"
done
dump erg_wiegung "select * from erg_wiegung order by wiege_ts desc"

# Runde R: die beiden Stichtag-Funktionen. Sie rechnen beim Aufruf, also gibt
# es je Stichtag eine eigene Datei — der Prüfstand soll für „in 6 Wochen" nicht
# die Zahlen von heute sehen. h = 0 ist heute, sonst Wochen mal sieben.
for H in 0 7 14 21 28 35 42 56 84; do
  dump "rpc_lager_kaliber_$H"  "select * from lager_kaliber($H)"
  dump "rpc_kaliber_glocke_$H" "select * from kaliber_glocke($H)"
done

# Eingebettete Abfrage: auftrag_teilnehmer mit profil(name)
dump auftrag_teilnehmer "select at.auftrag_id, at.profil_id, at.verlassen_ts,
       json_build_object('name', p.name) as profil
  from auftrag_teilnehmer at join profil p on p.id = at.profil_id"

# RPC-Antworten
psql "$U" -qtA -c "select json_build_object('schritt', 5, 'schritte', 5, 'titel', 'Befunde', 'dauer_ms', 0, 'fertig', true)" \
  > "$ZIEL/rpc_auswertung_schritt.json"
psql "$U" -qtA -c "select json_build_object(
  'sortieren',         palox_letzter_stand('sortieren'),
  'waschen',           palox_letzter_stand('waschen'),
  'waschen_sortieren', palox_letzter_stand('waschen_sortieren'))" \
  > "$ZIEL/rpc_palox_letzter_stand.json"

echo "Fixtures: $(ls "$ZIEL" | wc -l) Dateien, $(du -sh "$ZIEL" | cut -f1)"
