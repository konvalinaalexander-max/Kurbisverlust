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
         v_palox_stand v_lieferung_masse v_auftrag_masse auswertung_stand v_kohorte_anteil v_koeff_fax \
         ausgang_quelle ausgang_artikel v_ausgang_lage v_ausgang_artikel_vorschlag \
         charge sorte_kaliber gebinde einstellung ausgang_ziel kaeufer sortierschema \
         v_ausgang_kennzahl profil palette v_kontrolle_vorschlag v_lieferung_kohorte v_koeff_palette_netto \
         ausgang_wiegung v_auftrag_angabe v_verkauf_lieferung v_auftrag_wasch_paletten \
         auftrag auftrag_palette auftrag_gebinde schimmel_messung ausschuss_messung \
         verdunstung_wiegung ausgang_zeile \
         sortier_lauf v_charge_rueckgrat; do
  dump "$R" "select * from $R"
done
dump erg_wiegung "select * from erg_wiegung order by wiege_ts desc"

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
