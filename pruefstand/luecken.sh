#!/usr/bin/env bash
# =====================================================================
# Lückenscanner: prüft in beide Richtungen, dass zwischen den Masken und
# der Auswertung nichts nur auf einer Seite existiert.
#
#   ./pruefstand/luecken.sh 'postgresql://…'
#
# VORWÄRTS  Jede Spalte einer Erfassungstabelle, die ein Arbeiter oder der
#           Betriebsleiter füllt, muss irgendwo im Frontend (src/) geschrieben
#           werden. Eine Spalte, die die Datenbank kennt und die App nie
#           schreibt, ist genau die Art Lücke, die AB-02 (Palox) und AB-07
#           (Erfassungsbeginn) waren: das Backend erwartet etwas, das nie
#           ankommt. Echte Ausnahmen stehen unten mit Begründung.
#
# RÜCKWÄRTS Jede Erfassungstabelle, aus der die Auswertung liest, muss von der
#           App auch beschrieben werden — sonst zeigt das Dashboard eine Zahl,
#           die niemand erfassen kann.
# =====================================================================
set -euo pipefail
URL="${1:-postgresql://postgres@/pruef?host=/tmp/pgsock&port=55432}"
HIER="$(cd "$(dirname "$0")" && pwd)"
SRC="$HIER/../src"

# Die Erfassungstabellen: was ein Mensch über die Masken füllt.
TABELLEN=(auftrag auftrag_palette auftrag_gebinde schimmel_messung
          ausschuss_messung verdunstung_wiegung ausgang_wiegung
          auftrag_angabe charge_vorlauf kaeufer sortierschema)
# Nicht dabei: marge_messung — ein Alt-Kanal für von Hand eingetippte
# Marge-Posten. Seit AB-03 kommt die Überfüllung aus ausgang_wiegung und der
# Nebenkanal aus der CSV; keine Arbeiter-Maske schreibt marge_messung mehr. Die
# Überfüllungs-Ansicht liest sie noch (als leere Vereinigung, ohne Wirkung).
# Das Aufräumen gehört in eine Modellrunde, nicht in die Erfassung — vermerkt
# in FRAGEN.md.

# Spalten, die kein Mensch tippt: Schlüssel, Zeitstempel, Erfasser, abgeleitete
# Grössen, Vorgaben. Je Eintrag eine Begründung, damit die Liste ehrlich bleibt.
declare -A AUSNAHME=(
  [id]="Primärschlüssel, von der Datenbank vergeben"
  [ts]="Zeitstempel, Vorgabe now()"
  [erfasser]="aus der Anmeldung (auth.uid)"
  [eroeffnet_von]="aus der Anmeldung"
  [hochgeladen_von]="aus der Anmeldung"
  [auftrag_id]="Kontext der Arbeit, aus der Navigation"
  [charge_nr]="Kontext der Arbeit"
  [start_ts]="Startzeit setzt der Server"
  [ende_ts]="Endzeit setzt der Server (Auslöser)"
  [status]="vom Abschluss-Ablauf gesetzt"
  [abgebrochen_ts]="vom Abbrechen gesetzt"
  [abbruch_grund]="über auftrag_abbrechen()"
  [geplante_paletten]="nicht mehr verwendet (Wiegen gehört ans Zählen, 0012)"
  [bemerkung]="frei, optional an mehreren Stellen"
  [gemessen]="Vorgabe true; false nur intern/Test"
  [kg]="beim Ausschuss und Palox abgeleitet aus Brutto bzw. Stand"
  [aktiv]="Vorgabe true; Pflege über Benutzer/Käufer getrennt"
  [sortierschema_id]="aus der gewählten Fassung, Auslöser als Rückfall"
  [palette_id]="nur beim Palettenscan, hier nicht erfasst"
  [wiegung_id]="Verknüpfung, von der App beim Wiegen gesetzt"
  [roh_datei_ref]="CSV-Upload, Speicherpfad"
  [roh_pruefsumme]="CSV-Upload, aus der Datei"
  [datei_zeit]="CSV-Upload, aus der Datei"
  [datei_zeit_quelle]="CSV-Upload, abgeleitet"
  [zuordnung]="CSV-Zuordnung, vom Server"
  [reinigung]="CSV-Reinigung, vom Server"
  [n_roh]="CSV, gezählt" [n_overflow]="CSV, gezählt" [n_klein]="CSV, gezählt"
  [n_dubletten]="CSV, gezählt" [n_gueltig]="CSV, gezählt"
  [gelesen_ts]="CSV, Zeitstempel"
  [datei_name]="CSV-Upload, aus der Datei"
  [sichtbar_schimmel]="abgeleitet aus faul_kg > 0"
  [teilgewicht]="Alt-Spalte (war-die-Box-voll), von keiner heutigen Maske genutzt"
)

echo "── Lückenscanner ──────────────────────────────────────────────"
fehler=0

# ---------- VORWÄRTS ----------
for t in "${TABELLEN[@]}"; do
  spalten=$(psql "$URL" -qtA -c "select column_name from information_schema.columns
              where table_schema='public' and table_name='$t' order by ordinal_position")
  for c in $spalten; do
    [[ -n "${AUSNAHME[$c]:-}" ]] && continue
    # Wird die Spalte irgendwo im Frontend geschrieben? Wir suchen den Namen
    # als Objekt-Schlüssel oder in einer Zeichenkette (select/upsert/eq).
    if grep -rqE "(^|[^a-z_])$c[[:space:]]*[:,}]" "$SRC" 2>/dev/null \
       || grep -rqF "'$c'" "$SRC" 2>/dev/null \
       || grep -rqF "\"$c\"" "$SRC" 2>/dev/null; then
      :
    else
      echo "  ✗ VORWÄRTS  $t.$c wird von keiner Maske geschrieben"
      fehler=$((fehler+1))
    fi
  done
done

# ---------- RÜCKWÄRTS ----------
# Jede Erfassungstabelle, aus der eine Auswertung (Ansicht/mv) liest, muss von
# der App auch geschrieben werden.
for t in "${TABELLEN[@]}"; do
  liest=$(psql "$URL" -qtA -c "
    select count(*) from pg_depend d
      join pg_rewrite r on r.oid = d.objid
      join pg_class dv on dv.oid = r.ev_class
      join pg_class st on st.oid = d.refobjid
      join pg_namespace n on n.oid = dv.relnamespace
     where st.relname = '$t' and dv.relname <> '$t' and n.nspname='public'
       and dv.relname ~ '^m?v_'")
  if [[ "$liest" -gt 0 ]]; then
    if grep -rqE "from\\('$t'\\)|\\.from\\(\"$t\"\\)" "$SRC" 2>/dev/null \
       || grep -rqF "'$t'" "$SRC" 2>/dev/null; then
      :
    else
      echo "  ✗ RÜCKWÄRTS  $t wird ausgewertet, aber von keiner Maske beschrieben"
      fehler=$((fehler+1))
    fi
  fi
done

if [[ "$fehler" -eq 0 ]]; then
  echo "  OK  Keine Lücke: jede Erfassungsspalte hat ihre Maske, jede"
  echo "      ausgewertete Tabelle wird beschrieben."
  echo "───────────────────────────────────────────────────────────────"
else
  echo "───────────────────────────────────────────────────────────────"
  echo "  $fehler Lücke(n) gefunden."
  exit 1
fi
