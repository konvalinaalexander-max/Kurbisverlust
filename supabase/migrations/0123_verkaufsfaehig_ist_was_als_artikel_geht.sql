-- 0123 — Im Lager steht, was vom Eingang noch dasteht; verkaufsfähig ist,
--        was wir als Artikel tatsächlich verkaufen können
--
-- WARUM
--
-- Der Betrieb, 23. Oktober, zur Kachel „davon verkaufsfähig 285.6 t · 96 %":
-- „96 % von was? Kann ja nicht sein, dass von allem, was im Lager ist, 96 %
-- verkaufsfähig sind … Im Lager will ich, was wirklich steht — Paletten,
-- bevor wir etwas in den Palox schmeissen, bevor es Arbeiten erlebt, und vor
-- der Verdunstung: wie viele Paletten vom Eingang noch im Lager stehen. Und
-- verkaufsfähig sollst du wirklich das machen, was wir verkaufen können —
-- minus allem: innerhalb der Artikelgewichte, verschenkte Marge abgezogen,
-- Palox, Verdunstung. Wie viele Kilo können wir tatsächlich verkaufen."
--
-- Die 96 % waren das Verkaufsfähige geteilt durch die gute Ware (was nach
-- Verdunstung und Faulem noch auf den Paletten liegt) — und abgezogen war
-- davon nur, was die Sortiermaschine als zu klein oder zu gross herausnimmt.
-- Die Leiste darunter rechnete vom Eingang her. Zwei Bezüge in einer Kachel.
--
-- Jetzt, an jeder Stelle gleich:
--   Im Lager      = die Eingangspaletten, die noch dastehen (n_rest_paletten),
--                   mit dem Gewicht beim Eingang (eingang_kg) — ohne Abzug.
--   verkaufsfähig = verkaufbar_kg: eingang_kg − verdunstet − faul (Palox)
--                   − zu klein − zu gross (Sortiermaschine) − Faules beim
--                   Abpacken − passt in keinen Artikel (keinen_artikel_kg:
--                   leichter oder schwerer als die Gewichte der Artikel, aus
--                   artikel_lager_teile) − Überfüllung (ueberfuellung_kg:
--                   was in den Kisten über dem Soll verschenkt wird, auf dem
--                   Teil, der als Artikel geht). Unique (Hagel) ist ein Artikel
--                   und zählt mit.
-- Was nicht gemessen ist, wird nicht null: Ist die Überfüllung einer Charge
-- (und ihrer Sorte) nicht gewogen oder fehlt die Sortier-CSV, ist
-- verkaufbar_kg eine obere Schranke, und verkaufbar_offen sagt, warum.
--
-- Die Spalten von 0121 bleiben, wie sie waren (verkaufsfaehig_kg ist weiter
-- das Verkaufsfähige der Sortiermaschine, marge_kg und verrechenbar_kg
-- beziehen sich darauf); neu sind die Spalten am Ende.
-- =====================================================================

create or replace view v_lager_ausweis with (security_invoker = true) as
with hagel_lager as (
  select k.charge_nr, max(k.hagel) filter (where k.portion = 'lager' and k.m0 > 0) as h,
         sum(case when k.portion <> 'lager' and k.hagel > 0 and k.hagel < 1 then k.m2 * k.hagel / (1 - k.hagel) else 0 end) as hagel_ausgelagert
    from mv_kaskade k group by k.charge_nr
), marge_charge as (
  select m.charge_nr,
         sum(m.zuviel_je_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)
           / nullif(sum(m.soll_kg_pro_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null), 0) as a,
         sum(m.n_wiegungen) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)::int as n_kg,
         bool_or(m.kistensystem = 'stueck') as stueck
    from erg_marge_charge m group by m.charge_nr
), marge_sorte as (
  select m.sorte,
         sum(m.zuviel_je_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)
           / nullif(sum(m.soll_kg_pro_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null), 0) as a,
         sum(m.n_wiegungen) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)::int as n_kg,
         bool_or(m.kistensystem = 'stueck') as stueck
    from erg_marge_charge m group by m.sorte
), basis as (
  select c.charge_nr, c.sorte, c.schlag, c.n_rest_paletten as paletten, c.lager_kg as liegend_kg,
         p.lager_kg, p.alter_tage, p.verdunstet_kg, p.verdunstet_je_tag_kg, p.faul_kg as faul_mit_hagel_kg,
         p.gute_ware_kg, p.klein_kg, p.gross_kg, p.fax_kg, p.verkaufsfaehig_kg,
         p.r_bekannt, p.f_bekannt, p.kanal_bekannt, p.fax_bekannt,
         coalesce(hl.h, 0) as h, coalesce(hl.hagel_ausgelagert, 0) as hagel_ausgelagert,
         c.verlust_heute_kg,
         case when mc.a is not null then mc.a
              when mc.stueck then 0
              when ms.a is not null then ms.a
              when ms.stueck then 0 end as marge_anteil,
         case when mc.a is not null then format('gewogen: %s %s dieser Charge', mc.n_kg, case when mc.n_kg = 1 then 'Palette' else 'Paletten' end)
              when mc.stueck then 'Stück-Kisten: ohne Sollgewicht keine Überfüllung'
              when ms.a is not null then format('Sorte %s: %s gewogene %s', c.sorte, ms.n_kg, case when ms.n_kg = 1 then 'Palette' else 'Paletten' end)
              when ms.stueck then 'Stück-Kisten: ohne Sollgewicht keine Überfüllung'
              else 'nicht gewogen' end as marge_quelle
    from erg_charge c
    left join erg_prognose p on p.gruppe = 'charge' and p.schluessel = c.charge_nr::text and p.h = 0
    left join hagel_lager hl on hl.charge_nr = c.charge_nr
    left join marge_charge mc on mc.charge_nr = c.charge_nr
    left join marge_sorte ms on ms.sorte = c.sorte
), mit_hagel as (
  select b.*,
         case when b.gute_ware_kg is null then null
              when b.h <= 0 then 0::numeric
              when b.h >= 1 then null
              else b.gute_ware_kg * b.h / (1 - b.h) end as unique_kg
    from basis b
), artikel as (
  -- 0123: das Verkaufsfähige der Sortiermaschine auf die Gewichte der Artikel
  -- geteilt (artikel_lager_teile, heute) — was in kein Artikelgewicht passt
  -- (darunter, darüber, dazwischen, Sorte ohne Artikel) und was ohne
  -- Sortier-CSV offen bleibt.
  select t.charge_nr,
         sum(t.kg) filter (where t.groesse in ('darunter', 'darueber', 'dazwischen', 'lose')) as keinen_artikel_kg,
         sum(t.kg) filter (where t.groesse = 'ohne Verteilung') as groesse_offen_kg
    from artikel_lager_teile(0) t
   group by t.charge_nr
), verkaufbar as (
  select m.*,
         case when m.verkaufsfaehig_kg is null then null
              when m.verkaufsfaehig_kg <= 0 then 0::numeric
              else coalesce(a.keinen_artikel_kg, 0) end as keinen_artikel_kg,
         case when m.verkaufsfaehig_kg > 0 then coalesce(a.groesse_offen_kg, 0) else 0::numeric end as groesse_offen_kg
    from mit_hagel m
    left join artikel a on a.charge_nr = m.charge_nr
), netto as (
  select v.*,
         v.verkaufsfaehig_kg - v.keinen_artikel_kg as als_artikel_kg,
         (v.verkaufsfaehig_kg - v.keinen_artikel_kg) * v.marge_anteil / (1 + v.marge_anteil) as ueberfuellung_kg
    from verkaufbar v
)
select m.charge_nr, m.sorte, m.schlag,
       m.paletten,
       zahl(coalesce(m.lager_kg, m.liegend_kg), 2, 1e12)::numeric(14,2) as eingang_kg,
       m.alter_tage,
       zahl(m.verdunstet_kg, 2, 1e12)::numeric(14,2) as verdunstet_kg,
       zahl(m.verdunstet_je_tag_kg, 2, 1e12)::numeric(14,2) as verdunstet_je_tag_kg,
       zahl(m.faul_mit_hagel_kg - coalesce(m.unique_kg, 0), 2, 1e12)::numeric(14,2) as faul_kg,
       zahl(m.unique_kg, 2, 1e12)::numeric(14,2) as unique_kg,
       zahl(nullif(m.h, 0), 4, 1e1)::numeric(5,4) as hagel_anteil,
       zahl(m.klein_kg, 2, 1e12)::numeric(14,2) as zu_klein_kg,
       zahl(m.gross_kg, 2, 1e12)::numeric(14,2) as zu_gross_kg,
       zahl(m.fax_kg, 2, 1e12)::numeric(14,2) as fax_kg,
       zahl(m.verkaufsfaehig_kg, 2, 1e12)::numeric(14,2) as verkaufsfaehig_kg,
       zahl(m.marge_anteil, 5, 1e3)::numeric(8,5) as marge_anteil,
       m.marge_quelle,
       zahl(m.verkaufsfaehig_kg * m.marge_anteil / (1 + m.marge_anteil), 2, 1e12)::numeric(14,2) as marge_kg,
       zahl(m.verkaufsfaehig_kg / (1 + m.marge_anteil), 2, 1e12)::numeric(14,2) as verrechenbar_kg,
       zahl(m.hagel_ausgelagert + coalesce(m.unique_kg, 0), 2, 1e12)::numeric(14,2) as hagel_bis_heute_kg,
       coalesce(m.r_bekannt, false) as r_bekannt, coalesce(m.f_bekannt, false) as f_bekannt,
       coalesce(m.kanal_bekannt, false) as kanal_bekannt, coalesce(m.fax_bekannt, false) as fax_bekannt,
       -- 0123: was wir als Artikel tatsächlich verkaufen können
       zahl(m.keinen_artikel_kg, 2, 1e12)::numeric(14,2) as keinen_artikel_kg,
       zahl(m.groesse_offen_kg, 2, 1e12)::numeric(14,2) as groesse_offen_kg,
       zahl(m.ueberfuellung_kg, 2, 1e12)::numeric(14,2) as ueberfuellung_kg,
       zahl(m.als_artikel_kg - coalesce(m.ueberfuellung_kg, 0) + coalesce(m.unique_kg, 0), 2, 1e12)::numeric(14,2) as verkaufbar_kg,
       nullif(concat_ws(', ',
         case when m.verkaufsfaehig_kg > 0 and m.marge_anteil is null then 'Überfüllung nicht gewogen' end,
         case when m.groesse_offen_kg > 0 then 'Grösse offen (keine Sortier-CSV)' end), '') as verkaufbar_offen
  from netto m;

comment on view v_lager_ausweis is
  'Was im Lager liegt, Schritt für Schritt, je Charge heute (0121, 0123): eingang_kg (Eingangsmasse auf den Paletten, die noch stehen — „im Lager") − verdunstet − faul (Palox, ohne Hagel) − unique (Hagel, wird als Knospe verkauft) − zu klein − zu gross (Sortiermaschine) − Faules beim Abpacken = verkaufsfaehig_kg (nach der Sortiermaschine); davon marge_kg Überfüllung (marge_anteil = zu viel ÷ Soll, gewogen je Charge, sonst je Sorte; Stück-Kisten 0), verrechenbar_kg der Rest. 0123: verkaufbar_kg = verkaufsfaehig_kg − keinen_artikel_kg (passt in kein Artikelgewicht, artikel_lager_teile) − ueberfuellung_kg (auf dem Teil, der als Artikel geht) + unique_kg — was als Artikel tatsächlich verkauft werden kann; groesse_offen_kg ohne Sortier-CSV; verkaufbar_offen sagt, was fehlt (dann ist verkaufbar_kg eine obere Schranke). hagel_bis_heute_kg: der Hagel-Teil im Faulen bis heute, kein Verlust. Aus erg_prognose (h = 0), erg_charge, mv_kaskade, erg_marge_charge, artikel_lager_teile(0).';
grant select on v_lager_ausweis to authenticated;

-- =====================================================================
-- Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 123 $$;
