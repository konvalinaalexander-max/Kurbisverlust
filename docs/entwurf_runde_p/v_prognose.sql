-- ENTWURF Runde P (nicht angewendet): v_prognose
-- Je Gruppe (gesamt, sorte, schlag, charge) und Horizont h Tage ab heute():
-- die liegende Ware als Eingangsware (lager_kg = Σ m0 der Portion „lager") und
-- was daraus bei heute + h wird, wenn nichts verkauft wird — mit genau den
-- Strömen und Formeln der Kaskade (mv_kaskade), nur an einem späteren Tag
-- ausgewertet. Bei h = 0 muss jede Zahl mit erg_charge übereinstimmen.
create or replace view v_prognose with (security_invoker = true) as
with modell as materialized (select * from v_schimmel_modell),
kurve as materialized (select von, anteil_mono from v_schimmel_kurve where n > 0),
horizonte as (select unnest(array[0, 7, 14, 28, 56, 84]) as h),
lager as (
  select k.charge_nr, k.sorte, k.schlag, k.kohorte, k.alter_tage, k.m0,
         k.r, k.a0, k.a_klein_n, k.a_gross_n, k.a_fax,
         k.r_bekannt, k.f_bekannt, k.a0_bekannt, k.a_klein_bekannt, k.a_gross_bekannt, k.a_fax_bekannt,
         k.modell_gilt, k.u
    from mv_kaskade k
   where k.portion = 'lager' and k.m0 > 0
),
je_tag as (
  select l.*, h.h, l.alter_tage + h.h as t,
         -- f wie in der Kaskade (mit_f): Modell, sonst Treppe; gleiche Klammern
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(m.ln_lambda_korrigiert + m.k * ln(greatest(l.alter_tage + h.h, 1)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select c.anteil_mono from kurve c where c.von <= l.alter_tage + h.h order by c.von desc limit 1), 0), 0), 1)
         end as f
    from lager l cross join horizonte h cross join modell m
),
stroeme as (
  select j.*,
         j.m0 * power(1 - j.r, j.t)                                                as m1,
         j.m0 * power(1 - j.r, j.t) * (1 - j.a0) * (1 - j.f)                        as m2
    from je_tag j
),
gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from v_kaskade_basis
  union all select 'sorte',  sorte,            charge_nr from v_kaskade_basis
  union all select 'schlag', schlag,           charge_nr from v_kaskade_basis
  union all select 'charge', charge_nr::text,  charge_nr from v_kaskade_basis
),
summe as (
  select g.gruppe, g.schluessel, s.h,
         count(distinct s.charge_nr)::int                                            as n_chargen,
         sum(s.m0)                                                                   as lager_kg,
         sum(s.m0 - s.m1)                                                            as verdunstet_kg,
         sum(s.m1 * s.a0)                                                            as sockel_kg,
         sum(s.m1 * (1 - s.a0) * s.f)                                                as faul_kg,
         sum(s.m2 * (s.a_klein_n + s.a_gross_n))                                     as kanal_kg,
         sum(s.m2 * (1 - s.a_klein_n - s.a_gross_n) * s.a_fax)                       as fax_kg,
         sum(s.m2 * (1 - s.a_klein_n - s.a_gross_n) * (1 - s.a_fax))                 as verkaufsfaehig_kg,
         sum(s.m2)                                                                   as gute_ware_kg,
         bool_and(s.r_bekannt) as r_bekannt, bool_and(s.f_bekannt) as f_bekannt,
         bool_and(s.a_klein_bekannt and s.a_gross_bekannt) as kanal_bekannt,
         bool_and(s.a_fax_bekannt) as fax_bekannt,
         bool_and(s.modell_gilt) as modell_gilt,
         sum(s.m0 * s.t) / nullif(sum(s.m0), 0) as alter_tage
    from stroeme s join gruppen g on g.charge_nr = s.charge_nr
   group by g.gruppe, g.schluessel, s.h
)
select gruppe, schluessel, h, n_chargen,
       zahl(lager_kg, 2, 1e12)::numeric(14,2)            as lager_kg,
       zahl(verdunstet_kg, 2, 1e12)::numeric(14,2)       as verdunstet_kg,
       zahl(sockel_kg, 2, 1e12)::numeric(14,2)           as sockel_kg,
       zahl(faul_kg, 2, 1e12)::numeric(14,2)             as faul_kg,
       zahl(kanal_kg, 2, 1e12)::numeric(14,2)            as kanal_kg,
       zahl(fax_kg, 2, 1e12)::numeric(14,2)              as fax_kg,
       zahl(verkaufsfaehig_kg, 2, 1e12)::numeric(14,2)   as verkaufsfaehig_kg,
       zahl(gute_ware_kg, 2, 1e12)::numeric(14,2)        as gute_ware_kg,
       zahl(verkaufsfaehig_kg / nullif(lager_kg, 0), 4, 1)::numeric(6,4) as verkaufsfaehig_anteil,
       r_bekannt, f_bekannt, kanal_bekannt, fax_bekannt,
       (r_bekannt and f_bekannt and kanal_bekannt and fax_bekannt) as vollstaendig,
       modell_gilt,
       round(alter_tage)::int as alter_tage
  from summe;
