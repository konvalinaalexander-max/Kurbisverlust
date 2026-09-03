-- =====================================================================
-- 0027 — Der Arbeiter liest ab, die Software rechnet
--
-- Der Palox mit dem Faulen steht auf einer Waage und läuft über mehrere
-- Arbeiten weiter. Bisher musste der Arbeiter selbst die Differenz zum
-- letzten Mal bilden und nur diese eintragen.
--
-- Das ist genau die Sorte Schwierigkeit, an der Erfassung scheitert: Er muss
-- sich merken oder nachschlagen, was vorher draufstand, im Kopf abziehen, und
-- ein Rechenfehler ist hinterher nicht mehr erkennbar — die Differenz sieht
-- aus wie jede andere Zahl.
--
-- Jetzt trägt er ein, was auf der Waage steht. Die Differenz bildet die
-- Software, zeigt sie ihm an, und beide Zahlen bleiben erhalten: der Stand
-- als Beleg, die Differenz als Messwert. Wer später nachrechnen will, kann es.
--
-- Wird der Palox zwischendurch geleert, fällt der Stand. Dann ist der neue
-- Stand selbst die Menge seit dem Leeren — die Software erkennt das und sagt
-- es dem Arbeiter, statt eine negative Menge zu buchen.
-- =====================================================================

alter table schimmel_messung
  add column if not exists palox_stand_kg numeric(8,2)
    check (palox_stand_kg is null or palox_stand_kg >= 0);

comment on column schimmel_messung.palox_stand_kg is
  'Was auf der Palox-Waage stand, als diese Menge gebucht wurde. kg ist die '
  'daraus gebildete Differenz zum vorherigen Stand — beides wird behalten, '
  'damit sich der Wert nachrechnen lässt.';

-- ---------- Was stand zuletzt drauf? --------------------------------------
-- Der Arbeiter-Bildschirm liest das, bevor er die Differenz anzeigt.
create or replace view v_palox_stand with (security_invoker = true) as
select s.id, s.auftrag_id, s.ts, s.palox_stand_kg, s.kg,
       lag(s.palox_stand_kg) over (order by s.ts, s.id)          as vorher,
       case when lag(s.palox_stand_kg) over (order by s.ts, s.id) is null then s.palox_stand_kg
            when s.palox_stand_kg < lag(s.palox_stand_kg) over (order by s.ts, s.id)
                 then s.palox_stand_kg
            else s.palox_stand_kg - lag(s.palox_stand_kg) over (order by s.ts, s.id)
       end                                                        as differenz,
       (lag(s.palox_stand_kg) over (order by s.ts, s.id) is not null
        and s.palox_stand_kg < lag(s.palox_stand_kg) over (order by s.ts, s.id))
                                                                  as zwischendurch_geleert
  from schimmel_messung s
 where s.palox_stand_kg is not null and s.gemessen
 order by s.ts, s.id;

comment on view v_palox_stand is
  'Die Waagenstände der Reihe nach mit der jeweils daraus folgenden Menge. '
  'zwischendurch_geleert = true heisst: der Stand ist gefallen, der Palox '
  'wurde also geleert — dann gilt der neue Stand selbst als Menge.';

-- ---------- Der letzte Stand, für die Eingabemaske ------------------------
create or replace function palox_letzter_stand()
returns numeric language sql stable as $$
  select palox_stand_kg from public.schimmel_messung
   where palox_stand_kg is not null and gemessen
   order by ts desc, id desc limit 1;
$$;

comment on function palox_letzter_stand is
  'Was zuletzt auf der Palox-Waage stand. Der Arbeiter-Bildschirm zieht das '
  'vom neuen Stand ab, damit niemand im Kopf rechnen muss.';

grant select on v_palox_stand to authenticated;
grant execute on function palox_letzter_stand() to authenticated;
