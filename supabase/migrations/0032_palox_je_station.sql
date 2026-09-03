-- =====================================================================
-- 0032 — Der Palox-Stand gehört zur Station, nicht zum Betrieb
--
-- Der Palox mit dem Faulen steht auf einer Waage; der Arbeiter liest den
-- Stand ab, die Software bildet die Differenz zum letzten Mal (0027). Der
-- Betrieb hat zwei Dinge klargestellt, die diese Rechnung bisher übersah:
--
-- 1. „Das letzte Mal" war global. Sortierband, Waschbecken und Hand-Linie
--    sind aber verschiedene Arbeitsplätze mit je eigenem Sammelbehälter —
--    niemand trägt einen Palox samt Waage durch die Halle. Liefen zwei
--    Linien gleichzeitig, verzahnten sich ihre Ablesungen und jede Differenz
--    war falsch. Der Stand wird jetzt je Station geführt.
--
--    (Annahme dahinter, in docs/ABLAUF.md vermerkt: je Station genau ein
--    Palox. Sollten zwei Teams an derselben Station parallel arbeiten,
--    bräuchte es eine Behälter-Kennung — das wäre ein Feld mehr für den
--    Arbeiter und wird erst gebaut, wenn der Betrieb sagt, dass es vorkommt.)
--
-- 2. Zwischen zwei Ablesungen kann der Palox geleert worden sein. Fällt der
--    Stand, merkt die Software das selbst. Wird er aber geleert und danach
--    ÜBER den alten Stand hinaus neu befüllt, sieht die Zahlenreihe harmlos
--    aus und die Differenz unterschlägt still die entsorgte Menge. Dagegen
--    hilft nur der Arbeiter: ein Kennzeichen „war zwischendurch leer", das
--    die Rechnung auf den vollen Stand umstellt. Das Kennzeichen wird
--    gespeichert, damit jede Menge nachrechenbar bleibt.
--
-- Was der Betrieb ausserdem angeregt hat — die Palettenzahl der Arbeit als
-- Prüfgrösse — passiert in der Eingabemaske: Sie zeigt die Differenz sofort
-- als „kg je Palette" und warnt, wenn das unplausibel gross wird. Meist
-- heisst das: eine Ablesung wurde vergessen, und die Menge zweier Arbeiten
-- ist auf einer gelandet.
-- =====================================================================

alter table schimmel_messung
  add column if not exists palox_geleert boolean not null default false;

comment on column schimmel_messung.palox_geleert is
  'Der Arbeiter hat den Palox seit der letzten Ablesung geleert. Dann ist der '
  'neue Stand selbst die Menge — auch wenn er über dem alten liegt.';

-- ---------- Der letzte Stand, je Station ----------------------------------
drop function if exists palox_letzter_stand();

create or replace function palox_letzter_stand(p_station station)
returns numeric language sql stable as $$
  select s.palox_stand_kg
    from public.schimmel_messung s
    join public.auftrag a on a.id = s.auftrag_id
   where s.palox_stand_kg is not null and s.gemessen
     and a.station = p_station
   order by s.ts desc, s.id desc limit 1;
$$;

comment on function palox_letzter_stand(station) is
  'Was zuletzt auf der Palox-Waage DIESER Station stand. Die Eingabemaske '
  'zieht das vom neuen Stand ab, damit niemand im Kopf rechnen muss.';

-- ---------- Die Ablesungen der Reihe nach, je Station ---------------------
create or replace view v_palox_stand with (security_invoker = true) as
select s.id, s.auftrag_id, s.ts, s.palox_stand_kg, s.kg,
       lag(s.palox_stand_kg) over w                                as vorher,
       case
         when s.palox_geleert then s.palox_stand_kg
         when lag(s.palox_stand_kg) over w is null then s.palox_stand_kg
         when s.palox_stand_kg < lag(s.palox_stand_kg) over w then s.palox_stand_kg
         else s.palox_stand_kg - lag(s.palox_stand_kg) over w
       end                                                          as differenz,
       (s.palox_geleert
        or (lag(s.palox_stand_kg) over w is not null
            and s.palox_stand_kg < lag(s.palox_stand_kg) over w))   as zwischendurch_geleert,
       a.station
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
 where s.palox_stand_kg is not null and s.gemessen
window w as (partition by a.station order by s.ts, s.id)
 order by a.station, s.ts, s.id;

comment on view v_palox_stand is
  'Die Waagenstände je Station der Reihe nach, mit der jeweils daraus '
  'folgenden Menge. zwischendurch_geleert: der Stand ist gefallen oder der '
  'Arbeiter hat das Leeren gemeldet — dann gilt der neue Stand als Menge.';

grant execute on function palox_letzter_stand(station) to authenticated;
grant select on v_palox_stand to authenticated;
