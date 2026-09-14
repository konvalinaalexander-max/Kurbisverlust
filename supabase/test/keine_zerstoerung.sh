#!/usr/bin/env bash
# =====================================================================
# Keine Migration darf eine Messung vernichten
#
# Der Betrieb hat es so gesagt: „mir ist dann wichtig dass die daten der
# arbeiter app von nun an richtig erfasst werden - richtig in der datenbank
# angelegt - und auch genügend geschützt dass dort nicht mehr gross
# rumgepfuscht wird von der KI und falls schon, dann nur so dass nichts
# verloren geht."
#
# Zwei Netze halten das. Das erste ist erfassung_journal (0072): jede
# Änderung an jeder Messtabelle wird festgehalten, bei einem Löschen die
# ganze alte Zeile als jsonb. Das zweite ist dieses Skript: es liest die
# Migrationen und ist rot, sobald eine davon eine Tabelle, eine Spalte
# oder Zeilen wegnimmt.
#
# Das Journal fängt, was trotzdem passiert. Dieses Skript sorgt dafür,
# dass es gar nicht erst passiert.
#
#   ./supabase/test/keine_zerstoerung.sh
# =====================================================================
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
MIGRATIONEN="$HIER/../migrations"

echo "── Keine Zerstörung ───────────────────────────────────────────"

# ---------------------------------------------------------------------
# Die Freigabeliste. Jeder Eintrag ist ein Altfall, der geprüft und
# begründet ist. Wer etwas hinzufügt, schreibt den Grund dazu — sonst ist
# die Liste in einem Jahr eine Sammelstelle für alles, was mal nicht
# durchging.
#
# Format: Datei:Zeile
# ---------------------------------------------------------------------
FREIGEGEBEN=(
  # 0048 wirft den Alt-Kanal marge_messung weg. Das ist kein stilles
  # Löschen: die Migration prüft vorher, dass die Tabelle LEER ist, und
  # bricht sonst mit einer Anleitung ab („sichern, dann delete from
  # marge_messung; und setup.sql erneut ausführen"). Der Prüfstand fährt
  # diesen Abbruch in Stufe 3b ausdrücklich nach.
  "0048_ballast.sql:207"
  # 0052 legt drei Hilfstabellen für die Beispieldaten an und räumt sie
  # am Anfang und am Ende wieder weg. Sie enthalten nie eine Messung —
  # sie sind Notizzettel innerhalb einer Funktion.
  "0052_demo_saison.sql:106"
  "0052_demo_saison.sql:756"
)

freigegeben() {
  local treffer="$1"
  for f in "${FREIGEGEBEN[@]}"; do [ "$treffer" = "$f" ] && return 0; done
  return 1
}

# ---------------------------------------------------------------------
# Wonach gesucht wird
# ---------------------------------------------------------------------
# Bewusst NICHT gesucht wird nach:
#   · drop view / drop materialized view — Sichten sind Rechenwerk, keine
#     Daten. Sie werden in jeder Runde neu gebaut, das ist ihr Zweck.
#   · drop function — dasselbe.
#   · drop constraint — die Migrationen schreiben durchweg
#     „drop constraint if exists X" unmittelbar vor „add constraint X",
#     um die Bedingung neu zu setzen. Dass eine Zusage danach wieder
#     gilt, prüft 0067 gesondert („Zusage … bestätigt").
MUSTER=(
  'drop[[:space:]]+table'
  'drop[[:space:]]+column'
  'truncate'
)

GEFUNDEN=0
for muster in "${MUSTER[@]}"; do
  while IFS= read -r zeile; do
    [ -z "$zeile" ] && continue
    datei="$(basename "${zeile%%:*}")"
    rest="${zeile#*:}"
    nr="${rest%%:*}"
    text="$(echo "${rest#*:}" | sed 's/^[[:space:]]*//' | cut -c1-90)"
    if freigegeben "$datei:$nr"; then continue; fi
    echo "  ✗ $datei:$nr  $text"
    GEFUNDEN=$((GEFUNDEN + 1))
  done < <(grep -rniE "$muster" "$MIGRATIONEN"/*.sql || true)
done

# „delete from <tabelle>" ohne where — trifft alle Zeilen auf einmal.
# Nur echte Anweisungen, keine Kommentarzeilen und keine Fliesstexte in
# Zeichenketten (dort steht es als Anleitung für den Betriebsleiter).
while IFS= read -r zeile; do
  [ -z "$zeile" ] && continue
  datei="$(basename "${zeile%%:*}")"
  rest="${zeile#*:}"; nr="${rest%%:*}"
  text="$(echo "${rest#*:}" | sed 's/^[[:space:]]*//')"
  case "$text" in
    --*|"'"*|*"'"*) continue ;;   # Kommentar oder Zeichenkette
  esac
  if freigegeben "$datei:$nr"; then continue; fi
  echo "  ✗ $datei:$nr  $(echo "$text" | cut -c1-90)"
  GEFUNDEN=$((GEFUNDEN + 1))
done < <(grep -rniE "^[[:space:]]*delete[[:space:]]+from[[:space:]]+[a-z_]+[[:space:]]*;" "$MIGRATIONEN"/*.sql || true)

if [ "$GEFUNDEN" -gt 0 ]; then
  echo
  echo "  $GEFUNDEN Anweisung(en), die Daten wegnehmen."
  echo "  Eine Migration legt an und ändert — sie nimmt nichts weg. Was nicht"
  echo "  mehr gebraucht wird, verschwindet aus der Oberfläche und bekommt im"
  echo "  Schema einen Kommentar. Ist der Fall wirklich unvermeidlich, gehört"
  echo "  er mit Begründung in die Freigabeliste oben in diesem Skript."
  echo "───────────────────────────────────────────────────────────────"
  exit 1
fi

ANZ_DATEIEN="$(ls "$MIGRATIONEN"/*.sql | wc -l | tr -d ' ')"
echo "  OK  $ANZ_DATEIEN Migrationen, keine nimmt Daten weg"
echo "      (${#FREIGEGEBEN[@]} geprüfte Altfälle in der Freigabeliste)"
echo "───────────────────────────────────────────────────────────────"
