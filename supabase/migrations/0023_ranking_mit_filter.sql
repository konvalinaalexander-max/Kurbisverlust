-- =====================================================================
-- 0023 — Das Ranking auch gefiltert richtig rechnen
--
-- Das Dashboard lässt nach Sorte, Schlag und Mindest-Lagerdauer filtern und
-- summierte die Ströme dafür bisher selbst im Browser. Solange der Bereich
-- aus drei Szenarien bestand, ging das: drei Summen, fertig. Seit 0019 ist
-- der Bereich eine fortgepflanzte Streuung — Summieren führt dabei zum
-- falschen Ergebnis, weil sich Fehler nicht addieren, sondern je nach
-- Korrelation quadratisch oder linear zusammensetzen.
--
-- Die Statistik ein zweites Mal in TypeScript zu schreiben wäre die sicherste
-- Art, die beiden auseinanderlaufen zu lassen. Statt dessen wandert der Filter
-- dorthin, wo gerechnet wird. Die Kaskade hat je Charge und Portion eine
-- Zeile — ein paar Dutzend —, das kostet nichts.
-- =====================================================================

drop view if exists v_marge_buch;
drop view if exists v_verlust_ranking;

create or replace function verlust_ranking(
  p_sorte          text    default null,
  p_schlag         text    default null,
  p_min_lagertage  numeric default null)
returns table (
  strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric,
  kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric,
  koeff_n_min int, streuung_kg numeric, df int)
language sql stable as $$
with zeilen as materialized (
  select * from v_hochrechnung
   where buch in ('verlust', 'marge')
     and (p_sorte is null or sorte = p_sorte)
     and (p_schlag is null or schlag = p_schlag)
     and (p_min_lagertage is null or alter_tage >= p_min_lagertage)
),
je_sorte as (
  select z.strom, z.buch, z.sorte, max(z.koeff_art) as koeff_art,
         sum(z.d_r) as g_r, sum(z.d_a) as g_a
    from zeilen z group by z.strom, z.buch, z.sorte
),
je_strom_modell as (
  select z.strom, z.buch,
         sum(z.d_eta)       as g_achse,
         sum(z.d_eta * z.u) as g_steigung
    from zeilen z group by z.strom, z.buch
),
varianz_r as (
  select s.strom, s.buch,
         sum(power(s.g_r, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_r * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = 'verdunstung' and u.sorte is not distinct from s.sorte
   group by s.strom, s.buch
),
varianz_a as (
  select s.strom, s.buch,
         sum(power(s.g_a, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_a * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = s.koeff_art and u.sorte is not distinct from s.sorte
   where s.koeff_art is not null
   group by s.strom, s.buch
),
varianz_f as (
  select m.strom, m.buch,
         power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
         + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
         + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)       as varianz,
         coalesce(sm.c_chargen - 1, 1)                          as df
    from je_strom_modell m cross join v_schimmel_modell sm
),
summe as (
  select z.strom, z.buch,
         sum(z.kg)                                                as kg,
         sum(z.kg) filter (where z.portion = 'ausgelagert')       as kg_beobachtet,
         sum(z.kg) filter (where z.portion = 'lager')             as kg_projiziert,
         sum(z.kg) filter (where z.f_extrapoliert)                as kg_extrapoliert,
         min(z.koeff_n)                                           as koeff_n_min
    from zeilen z group by z.strom, z.buch
)
select s.strom, s.buch, s.kg,
       greatest(s.kg - g.t * g.streuung, 0)::numeric(14,2),
       (s.kg + g.t * g.streuung)::numeric(14,2),
       s.kg_beobachtet, s.kg_projiziert, s.kg_extrapoliert, s.koeff_n_min,
       g.streuung::numeric(14,2), g.df
  from summe s
  left join varianz_r vr on vr.strom = s.strom and vr.buch = s.buch
  left join varianz_a va on va.strom = s.strom and va.buch = s.buch
  left join varianz_f vf on vf.strom = s.strom and vf.buch = s.buch
  cross join lateral (
    select sqrt(greatest(coalesce(vr.varianz, 0) + coalesce(va.varianz, 0)
                         + coalesce(vf.varianz, 0), 0))       as streuung,
           least(coalesce(vr.df, 999), coalesce(va.df, 999),
                 coalesce(vf.df, 999))                        as df
  ) g0
  cross join lateral (select g0.streuung, g0.df, t_quantil_95(g0.df) as t) g
 order by s.kg desc nulls last;
$$;

comment on function verlust_ranking(text, text, numeric) is
  'Die Ströme mit fortgepflanztem 95-%-Bereich, wahlweise auf Sorte, Schlag '
  'oder Mindest-Lagerdauer eingeschränkt. Der Bereich lässt sich nicht durch '
  'Summieren gefilterter Zeilen gewinnen — deshalb gehört der Filter hierher.';

create view v_verlust_ranking with (security_invoker = true) as
select * from verlust_ranking();

comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall: die '
  'Empfindlichkeit jedes Stroms gegenüber jedem Koeffizienten mal dessen '
  'Fehler, zusammengesetzt nach der tatsächlichen Korrelation.';

create view v_marge_buch with (security_invoker = true) as
with kisten as materialized (
  select sum(k.verkaufsfaehig_kg * b.weg2_anteil) / 8.0 as anzahl
    from v_kaskade k join v_hochrechnung_basis b on b.charge_nr = k.charge_nr
)
select r.strom as posten, r.kg, r.kg_unten, r.kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from v_verlust_ranking r where r.buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;

grant execute on function verlust_ranking(text, text, numeric) to authenticated;
grant select on v_verlust_ranking, v_marge_buch to authenticated;
