-- ENTWURF Runde P (nicht angewendet): v_wohin
-- „Wohin ging der Kürbis?" — je Gruppe eine Zeile, die den ganzen Eingang
-- aufteilt, bis heute. Die Ströme kommen aus erg_verlust: kg_beobachtet ist der
-- Teil an der ausgelieferten Ware (schon passiert), kg_projiziert der Teil an
-- der liegenden Ware (bis heute gerechnet). Die liegende Ware selbst aus
-- erg_charge (lager_kg = Eingangsware, die nicht hinter einer Lieferung steckt).
--
-- Identität (bis auf Rundung, geprüft auf der Demo: |rest| ≤ 0.05 kg):
--   eingang + ueberzaehlung
--     = geliefert + kanal_ausgelagert + verdunstet_ausgelagert + faul_ausgelagert + fax + lager
--   lager = lager_verkaufsfaehig + lager_kanal + lager_fax + lager_faul + lager_verdunstet
-- „faul" enthält den Sockel (nicht lagerbedingt) — er steht daneben eigens.
create or replace view v_wohin with (security_invoker = true) as
with gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from erg_charge
  union all select 'sorte',  sorte,           charge_nr from erg_charge
  union all select 'schlag', schlag,          charge_nr from erg_charge
  union all select 'charge', charge_nr::text, charge_nr from erg_charge
),
charge as (
  select g.gruppe, g.schluessel,
         count(*)::int as n_chargen,
         sum(c.eingang_kg) as eingang_kg,
         sum(c.ueberzaehlung_kg) as ueberzaehlung_kg,
         sum(c.geliefert_kg) as geliefert_kg,
         sum(c.kanal_ausgelagert_kg) as kanal_ausgelagert_kg,
         sum(c.fax_heute_kg) as fax_kg,
         sum(c.lager_kg) as lager_kg,
         sum(c.im_haus_heute_kg) as lager_gute_ware_kg,
         sum(c.verkaufsfaehig_lager_kg) as lager_verkaufsfaehig_kg,
         sum(c.kanal_im_haus_kg) as lager_kanal_kg,
         sum(c.fax_erwartet_kg) as lager_fax_kg,
         bool_and(c.verlust_bekannt) as vollstaendig
    from gruppen g join erg_charge c on c.charge_nr = g.charge_nr
   group by g.gruppe, g.schluessel
),
stroeme as (
  select gruppe, schluessel,
         sum(kg_beobachtet) filter (where strom = 'Verdunstung')                              as verdunstet_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Verdunstung')                              as lager_verdunstet_kg,
         sum(kg_beobachtet) filter (where strom = 'Schimmel/Fäulnis')                         as faul_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Schimmel/Fäulnis')                         as lager_faul_kg,
         sum(kg_beobachtet) filter (where strom = 'Nicht lagerbedingt')                       as sockel_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Nicht lagerbedingt')                       as lager_sockel_kg,
         sum(kg_beobachtet) filter (where strom = 'Zu klein (Tierfutter)')                    as klein_ausgelagert_kg,
         sum(kg_beobachtet) filter (where strom = 'Nebenkanal zu gross')                      as gross_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Zu klein (Tierfutter)')                    as lager_klein_kg,
         sum(kg_projiziert) filter (where strom = 'Nebenkanal zu gross')                      as lager_gross_kg
    from erg_verlust
   group by gruppe, schluessel
)
select c.gruppe, c.schluessel, c.n_chargen,
       zahl(c.eingang_kg)::numeric(14,2)                 as eingang_kg,
       zahl(c.ueberzaehlung_kg)::numeric(14,2)           as ueberzaehlung_kg,
       zahl(c.geliefert_kg)::numeric(14,2)               as geliefert_kg,
       zahl(c.kanal_ausgelagert_kg)::numeric(14,2)       as kanal_ausgelagert_kg,
       zahl(s.klein_ausgelagert_kg)::numeric(14,2)       as klein_ausgelagert_kg,
       zahl(s.gross_ausgelagert_kg)::numeric(14,2)       as gross_ausgelagert_kg,
       zahl(s.verdunstet_ausgelagert_kg)::numeric(14,2)  as verdunstet_ausgelagert_kg,
       zahl(s.faul_ausgelagert_kg + coalesce(s.sockel_ausgelagert_kg, 0))::numeric(14,2) as faul_ausgelagert_kg,
       zahl(s.sockel_ausgelagert_kg)::numeric(14,2)      as sockel_ausgelagert_kg,
       zahl(c.fax_kg)::numeric(14,2)                     as fax_kg,
       zahl(c.lager_kg)::numeric(14,2)                   as lager_kg,
       zahl(c.lager_gute_ware_kg)::numeric(14,2)         as lager_gute_ware_kg,
       zahl(c.lager_verkaufsfaehig_kg)::numeric(14,2)    as lager_verkaufsfaehig_kg,
       zahl(c.lager_kanal_kg)::numeric(14,2)             as lager_kanal_kg,
       zahl(s.lager_klein_kg)::numeric(14,2)             as lager_klein_kg,
       zahl(s.lager_gross_kg)::numeric(14,2)             as lager_gross_kg,
       zahl(c.lager_fax_kg)::numeric(14,2)               as lager_fax_kg,
       zahl(s.lager_faul_kg + coalesce(s.lager_sockel_kg, 0))::numeric(14,2) as lager_faul_kg,
       zahl(s.lager_sockel_kg)::numeric(14,2)            as lager_sockel_kg,
       zahl(s.lager_verdunstet_kg)::numeric(14,2)        as lager_verdunstet_kg,
       zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.kanal_ausgelagert_kg
            - s.verdunstet_ausgelagert_kg - s.faul_ausgelagert_kg - coalesce(s.sockel_ausgelagert_kg, 0)
            - c.fax_kg - c.lager_kg)::numeric(14,2)      as rest_kg,
       zahl(c.lager_kg - c.lager_verkaufsfaehig_kg - c.lager_kanal_kg - c.lager_fax_kg
            - s.lager_faul_kg - coalesce(s.lager_sockel_kg, 0) - s.lager_verdunstet_kg)::numeric(14,2) as lager_rest_kg,
       c.vollstaendig
  from charge c
  left join stroeme s on s.gruppe = c.gruppe and s.schluessel = c.schluessel;
