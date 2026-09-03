#!/usr/bin/env bash
# =====================================================================
# Simulations-Harness: viele Saisons erzeugen und die Auswertung messen
#
#   ./lauf.sh [Anzahl] [anteil_lager] [selektion] [n_wiegungen] [n_lagerkontrollen]
#
# Erzeugt N Saisons mit bekannter Wahrheit, lässt die Auswertung darüber
# laufen und hält je Lauf fest, was sie geschätzt hat. Am Ende steht, wie
# stark sie systematisch danebenliegt (Verzerrung) und wie oft der
# ausgewiesene Bereich den wahren Wert tatsächlich enthält (Überdeckung).
#
# Ein Bereich, der 95 % heissen soll, muss in rund 95 % der Läufe treffen.
# Alles deutlich darunter ist ein Versprechen, das die Zahl nicht hält.
# =====================================================================
set -euo pipefail
N="${1:-40}"; LAGER="${2:-0.25}"; SELEKTION="${3:-0}"; WIEGUNGEN="${4:-12}"
KONTROLLEN="${5:-0}"; SOCKEL="${6:-0}"
URL="${URL:-postgresql://postgres@/postgres?host=/tmp&port=55432}"
HIER="$(cd "$(dirname "$0")" && pwd)"

echo "Simulation: $N Saisons · ${LAGER} im Lager · Selektion=$SELEKTION · $WIEGUNGEN Wiegungen · $KONTROLLEN Lagerkontrollen · Sockel=$SOCKEL"
psql "$URL" -qtA -c "delete from sim.schaetzung; delete from sim.wahrheit;" >/dev/null

for i in $(seq 1 "$N"); do
  psql "$URL" -v ON_ERROR_STOP=1 -q -v lauf="$i" -v selektion="$SELEKTION" \
       -v n_wiegungen="$WIEGUNGEN" -v anteil_lager="$LAGER" \
       -v n_lagerkontrollen="$KONTROLLEN" -v anteil_sockel="$SOCKEL" -f "$HIER/saison.sql" >/dev/null
  psql "$URL" -v ON_ERROR_STOP=1 -q -v lauf="$i" -f "$HIER/erfassung.sql" >/dev/null
  psql "$URL" -qtA -c "select auswertung_aktualisieren()" >/dev/null
  psql "$URL" -v ON_ERROR_STOP=1 -q -c "
    insert into sim.schaetzung (lauf, groesse, mittel, unten, oben)
    select $i, strom, kg, kg_unten, kg_oben from v_verlust_ranking
    on conflict (lauf, groesse) do update
      set mittel = excluded.mittel, unten = excluded.unten, oben = excluded.oben;
    insert into sim.schaetzung (lauf, groesse, mittel, unten, oben)
    select $i, 'r_wahr_mittel', avg(mittel), avg(unten), avg(oben)
      from v_koeff_verdunstung where mittel is not null
    on conflict (lauf, groesse) do update
      set mittel = excluded.mittel, unten = excluded.unten, oben = excluded.oben;
    -- Der Sockel-Nachweis je Saison, um die Schwelle zu beurteilen
    insert into sim.schaetzung (lauf, groesse, mittel, unten, oben)
    select $i, 'sockel_nachweis', sockel_nachweis, sockel, sockel_schwelle from v_schimmel_modell
    on conflict (lauf, groesse) do update
      set mittel = excluded.mittel, unten = excluded.unten, oben = excluded.oben;" >/dev/null
  printf '\r  %s/%s' "$i" "$N"
done
echo

# Die eigentliche Frage aus Spec §9 ist nicht die Kilozahl, sondern die
# Rangfolge: Nennt die Auswertung dieselbe Hauptursache wie die Wahrheit, und
# steht die ganze Reihenfolge richtig?
psql "$URL" -P pager=off -c "
with wahr as (
  select lauf, groesse, rank() over (partition by lauf order by wert desc) as rang
    from sim.wahrheit
   where groesse in ('Verdunstung', 'Schimmel/Fäulnis', 'Zu klein (Tierfutter)')
), geschaetzt as (
  select lauf, groesse, rank() over (partition by lauf order by mittel desc) as rang
    from sim.schaetzung
   where groesse in ('Verdunstung', 'Schimmel/Fäulnis', 'Zu klein (Tierfutter)')
), je_lauf as (
  select w.lauf,
         bool_and(w.rang = g.rang)                            as ganz_richtig,
         bool_and(w.rang <> 1 or g.rang = 1)                  as haupt_richtig
    from wahr w join geschaetzt g on g.lauf = w.lauf and g.groesse = w.groesse
   group by w.lauf
)
select count(*)                                                       as laeufe,
       round(100.0 * count(*) filter (where haupt_richtig) / count(*)) || ' %'
                                                                      as hauptursache_getroffen,
       round(100.0 * count(*) filter (where ganz_richtig) / count(*)) || ' %'
                                                                      as rangfolge_ganz_richtig
  from je_lauf;"

psql "$URL" -P pager=off -c "
select 'Sockel-Nachweis (Fehler ohne / mit Sockel)' as was,
       round(min(mittel), 2) as min, round(percentile_cont(0.25) within group (order by mittel)::numeric, 2) as q25,
       round(percentile_cont(0.5) within group (order by mittel)::numeric, 2) as median,
       round(percentile_cont(0.75) within group (order by mittel)::numeric, 2) as q75,
       round(max(mittel), 2) as max, round(avg(oben), 2) as schwelle,
       round(100.0 * count(*) filter (where unten > 0) / count(*)) || ' %' as sockel_gesetzt
  from sim.schaetzung where groesse = 'sockel_nachweis';"

psql "$URL" -P pager=off -c "
select s.groesse,
       count(*)                                                    as laeufe,
       -- Ist die Wahrheit 0 (kein Sockel), gibt es keine relative Verzerrung;
       -- dann steht die mittlere Schätzung in kg da — sie sollte nahe 0 sein.
       case when max(w.wert) > 0
            then round(avg((s.mittel - w.wert) / nullif(w.wert, 0) * 100), 1) || ' %'
            else round(avg(s.mittel)) || ' kg (Wahrheit 0)' end    as verzerrung,
       round(stddev_samp((s.mittel - w.wert) / nullif(w.wert, 0) * 100), 1) || ' %' as streuung,
       round(avg((s.oben - s.unten) / nullif(s.mittel,0) * 100), 1) || ' %' as bereichsbreite,
       round(100.0 * count(*) filter (where w.wert between s.unten and s.oben)
             / count(*)) || ' %'                                   as ueberdeckung
  from sim.schaetzung s
  join sim.wahrheit w on w.lauf = s.lauf and w.groesse = s.groesse
 group by s.groesse order by 1;"
