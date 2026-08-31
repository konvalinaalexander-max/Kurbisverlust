#!/usr/bin/env bash
# Zieht die Antworten, die Supabase der App geben würde, als JSON-Dateien aus
# der lokalen Demo-Datenbank. Der Prüfstand (bildschirme.mjs) spielt sie der
# App dann als abgefangene Netzwerkantworten vor — echte Datenformen, echte
# Zahlen, kein ausgedachtes Fixture, das mit dem Schema auseinanderläuft.
set -euo pipefail
U="${1:-postgresql://postgres@/postgres?host=/tmp/pgsock&port=55432}"
HIER="$(cd "$(dirname "$0")" && pwd)"
ZIEL="$HIER/daten"
mkdir -p "$ZIEL"

dump() {
  psql "$U" -qtA -c "select coalesce(json_agg(t), '[]'::json) from ($2) t" > "$ZIEL/$1.json"
}

# Tabellen und Ansichten, die die App liest
for R in v_hochrechnung v_massenbilanz v_datenlage v_marge_buch v_plausibilitaet \
         v_kaliber_verteilung v_schimmel_kurve_anzeige v_koeff_verdunstung \
         v_koeff_ausschuss v_koeff_nebenkanal v_koeff_ueberfuellung \
         v_schimmel_modell v_selektionsverdacht v_saisonbilanz v_schimmel_punkte \
         v_hochrechnung_basis v_naechste_charge auswertung_stand \
         charge sorte_kaliber gebinde einstellung ausgang_ziel \
         v_lieferung_masse v_ausgang_kennzahl profil palette \
         auftrag auftrag_palette schimmel_messung ausschuss_messung \
         sortier_lauf v_charge_rueckgrat; do
  dump "$R" "select * from $R"
done
dump v_wiegung_kennzahl "select * from v_wiegung_kennzahl order by wiege_ts desc"

# Eingebettete Abfrage: auftrag_teilnehmer mit profil(name)
dump auftrag_teilnehmer "select at.auftrag_id, at.profil_id, at.verlassen_ts,
       json_build_object('name', p.name) as profil
  from auftrag_teilnehmer at join profil p on p.id = at.profil_id"

# RPC-Antworten
psql "$U" -qtA -c "select coalesce(json_agg(t), '[]'::json)
  from (select * from verlust_ranking(null, null, null)) t" > "$ZIEL/rpc_verlust_ranking.json"
psql "$U" -qtA -c "select json_build_object(
  'sortieren',         palox_letzter_stand('sortieren'),
  'waschen',           palox_letzter_stand('waschen'),
  'waschen_sortieren', palox_letzter_stand('waschen_sortieren'))" \
  > "$ZIEL/rpc_palox_letzter_stand.json"

echo "Fixtures: $(ls "$ZIEL" | wc -l) Dateien, $(du -sh "$ZIEL" | cut -f1)"
