-- =====================================================================
-- 0030 — Die Massenbilanz muss denselben Zeitpunkt vergleichen
--
-- v_massenbilanz stellt das Modell neben die Sortier-CSV: Die Maschine hat
-- jeden Kürbis gewogen, das Modell sagt voraus, wie viel über das Band laufen
-- müsste. Weichen die beiden systematisch ab, rechnet die Kaskade falsch.
--
-- Seit 0024 endet die Kaskade auf Weg 1 aber erst beim *Waschen*, Wochen nach
-- dem Sortieren. Verglichen wurde damit die Masse am Ende des zweiten
-- Lagerabschnitts mit einer Wägung vom Anfang — in der Prüffixtur 40 Tage
-- Unterschied und prompt 8.2 % Abweichung, die niemandes Fehler war ausser
-- dieser Gegenüberstellung.
--
-- Die CSV wiegt, was beim Sortieren über das Band lief. Also muss das Modell
-- genau dafür seine Vorhersage machen: Eingangsmasse, vermindert um
-- Verdunstung und Schimmel **bis zum Sortiertag**.
-- =====================================================================

-- Das Alter am Band, getrennt vom Endalter der Kaskade.
create or replace view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung
                    where schluessel = 'saison_ende'), current_date) as bis
), je_station as (
  select charge_nr,
         sum(eingang_netto_kg) filter (where station = 'sortieren')          as sortiert_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen')            as gewaschen_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren')  as hand_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren'
                                         and weg = 'hand')                   as kg_hand,
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('waschen', 'waschen_sortieren') and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('waschen', 'waschen_sortieren') and lagertage is not null), 0)
                                                                             as alter_ende,
         sum(eingang_netto_kg * lagertage) filter (where lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (where lagertage is not null), 0)
                                                                             as alter_irgendwas,
         -- Wann lief die Ware über ein Band? Das ist der Zeitpunkt, den die
         -- Sortier-CSV gewogen hat.
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('sortieren', 'waschen_sortieren') and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('sortieren', 'waschen_sortieren') and lagertage is not null), 0)
                                                                             as alter_band,
         sum(eingang_netto_kg) filter (where station in ('sortieren', 'waschen_sortieren'))
                                                                             as am_band_kg
    from v_auftrag_masse
   where eingang_netto_kg is not null
   group by charge_nr
), anteil as (
  select s.*,
         least(coalesce(s.gewaschen_kg, 0) / nullif(s.sortiert_kg, 0), 1)     as anteil_gewaschen
    from je_station s
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       (coalesce(a.hand_kg, 0)
        + coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0))       as ausgelagert_kg,
       coalesce(a.alter_ende, a.alter_irgendwas)                              as alter_ausgelagert,
       greatest(r.eingang_netto_kg
                - coalesce(a.hand_kg, 0)
                - coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0), 0)
                                                                              as lager_kg,
       (s.bis - r.eingangsdatum_mittel)::numeric                              as alter_lager,
       (current_date - r.eingangsdatum_mittel)::numeric                       as alter_lager_heute,
       coalesce(a.kg_hand / nullif(coalesce(a.hand_kg, 0)
                                   + coalesce(a.sortiert_kg, 0), 0), 0)       as weg2_anteil,
       s.bis                                                                  as stichtag,
       r.n_paletten_mit_netto,
       greatest(coalesce(a.hand_kg, 0) + coalesce(a.sortiert_kg, 0)
                - r.eingang_netto_kg, 0)                                      as ueberzaehlung_kg,
       coalesce(a.sortiert_kg, 0)                                             as sortiert_kg,
       coalesce(a.gewaschen_kg, 0)                                            as gewaschen_kg,
       (coalesce(a.sortiert_kg, 0) * (1 - coalesce(a.anteil_gewaschen, 0)))    as wartet_kg,
       coalesce(a.anteil_gewaschen, 0)                                        as anteil_gewaschen,
       a.alter_band,
       coalesce(a.am_band_kg, 0)                                              as am_band_kg
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

-- ---------- Modell und CSV am selben Tag ----------------------------------
create or replace view v_massenbilanz with (security_invoker = true) as
with csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (
             where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
           / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren')
     and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
), rest as materialized (
  select charge_nr, sum(verkaufsfaehig_kg) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade group by charge_nr
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       -- Was das Modell für den Tag am Band vorhersagt: Eingangsmasse minus
       -- Verdunstung und Schimmel *bis dahin*, nicht bis zum Waschen.
       (b.am_band_kg
        * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
        * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
        * q.anteil_mit_csv)::numeric(14,2)                   as modell_am_band_kg,
       c.gemessen_kg                                         as csv_gemessen_kg,
       (c.gemessen_kg
        - b.am_band_kg
          * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
          * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
          * q.anteil_mit_csv)::numeric(14,2)                 as abweichung_kg,
       case when b.am_band_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg
                   - b.am_band_kg
                     * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05),
                             coalesce(b.alter_band, 0))
                     * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
                     * q.anteil_mit_csv)
                  / (b.am_band_kg
                     * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05),
                             coalesce(b.alter_band, 0))
                     * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
                     * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       r.restbestand_kg::numeric(14,2)                       as restbestand_kg,
       b.alter_band
  from v_hochrechnung_basis b
  left join csv_anteil q on q.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr
  left join rest r       on r.charge_nr = b.charge_nr
  left join v_koeff_verdunstung kv on kv.sorte = b.sorte;

comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. '
  'abweichung_anteil nahe 0 heisst, die Koeffizienten treffen die Realität. '
  'Nur aussagekräftig für Chargen mit CSV — und sie prüft die Koeffizienten, '
  'nicht die Verluste: die CSV wiegt, was ankommt, nicht was verschwand.';

grant select on v_hochrechnung_basis, v_massenbilanz to authenticated;
