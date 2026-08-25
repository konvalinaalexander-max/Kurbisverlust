#!/usr/bin/env bash
# =====================================================================
# Fährt die Lagen ab, auf die es ankommt, und stellt Verzerrung und
# Überdeckung nebeneinander. Das ist der Bericht, den jede Änderung am
# Modell bestehen muss.
#
#   ./matrix.sh [Saisons je Lage]     (Default 25)
#
# Überdeckung deutlich unter 95 % heisst: Der Bereich verspricht mehr, als
# er hält. Verzerrung deutlich neben 0 heisst: Die Zahl liegt systematisch
# daneben, egal wie viele Saisons man mittelt.
# =====================================================================
set -euo pipefail
N="${1:-25}"
HIER="$(cd "$(dirname "$0")" && pwd)"
URL="${URL:-postgresql://postgres@/postgres?host=/tmp&port=55432}"

# Von vorne anfangen. Ohne das rechnet die Auswertung über alles, was sonst
# noch in der Datenbank liegt — nach einem run.sh etwa über die 4336 t des
# Lasttests —, während die Wahrheit nur die simulierte Saison kennt. Das
# Ergebnis sind Verzerrungen von tausend Prozent, die nichts über das Modell
# aussagen, nur über den Datenbankzustand.
echo "Datenbank zurücksetzen …"
psql "$URL" -q -c "set client_min_messages = warning;
   drop schema if exists public cascade;  create schema public;
   drop schema if exists auth cascade;    drop schema if exists storage cascade;
   drop schema if exists sim cascade;"
psql "$URL" -v ON_ERROR_STOP=1 -q -f "$HIER/../stub_supabase.sql"
for f in "$HIER"/../../migrations/*.sql; do
  psql "$URL" -v ON_ERROR_STOP=1 -q -f "$f" >/dev/null 2>&1
done
psql "$URL" -v ON_ERROR_STOP=1 -q -f "$HIER/aufbau.sql" >/dev/null 2>&1

lage() {
  echo
  echo "═══ $1 ═══"
  "$HIER/lauf.sh" "$N" "$2" "$3" "$4" "$5" 2>&1 | tail -n +3
}

lage "Saisonende, 25 % im Lager"                       0.25 0 12 0
lage "Mitten in der Saison, 50 % im Lager"             0.50 0 12 0
lage "Saisonende, Schlechtes zuerst verarbeitet"       0.25 1 12 0
lage "Mitten in der Saison, Schlechtes zuerst"         0.50 1 12 0
lage "Wie zuvor, aber 12 Lagerkontrollen je Saison"    0.50 1 12 12
lage "Wie zuvor, aber 24 Lagerkontrollen je Saison"    0.50 1 12 24
lage "Knappe Stichprobe: nur 4 Palettenwägungen"       0.50 0 4  0
