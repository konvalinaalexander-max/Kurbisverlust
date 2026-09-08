-- =====================================================================
-- 0061 — Alles bis heute, die Prognose getrennt, das Rechenwerk gespeichert
--
-- Der Betrieb hat am 8. September gefragt, was „Verlust" heisst. Die
-- Antwort war unangenehm: Die Ware im Haus wurde bis zum Saisonende gealtert
-- (31. März), nicht bis heute — von 103 t „Verlust" waren 73 t eine Prognose
-- sieben Monate in die Zukunft, angezeigt wie ein Faktum. Ab jetzt gilt:
--
--   · Jede Zahl ist eine Zahl BIS HEUTE. Verlust bis heute, im Haus heute,
--     verkaufsfähig heute. Die Ware im Haus altert bis heute(), nicht weiter.
--   · Die Prognose ist eine eigene Reihe (erg_verlauf ab heute, gestrichelt),
--     nie in einer Kennzahl versteckt.
--   · Das Dashboard liest nur noch gespeicherte Ergebnisse (erg_*): klein,
--     indiziert, mit Statistik. Nichts, was die App lädt, rechnet beim Laden.
--     Auf Supabase liefen sieben live gerechnete Sichten ins Zeitlimit.
--   · Die Neuberechnung läuft in Schritten (auswertung_schritt), jeder kurz
--     genug für das Zeitlimit einer Verbindung; jeder Schritt analysiert seine
--     Sichten (materialized views bekommen sonst nie Statistiken).
--
-- Dazu aus dem Feedback: die Überfüllung aus den Verkaufsdaten (verkaufte
-- Kisten je Kistensystem, nichts mehr hochgerechnet), beim Waschen Paletten
-- mit Sortierdatum und Kistenzahl, die Lagerkontrolle als reine
-- Verdunstungsmessung, kein Käufer mehr.
-- =====================================================================

-- ---------- 0. heute() und stichtag() -------------------------------------
-- „Heute" ist eine Funktion, damit der Simulations-Harness eine Saison an
-- ihrem Stichtag prüfen kann (Einstellung heute_test). Im Betrieb ist es
-- current_date, und die Einstellung fehlt.
create or replace function heute() returns date
language sql stable set search_path = public as $$
  select coalesce((select nullif(wert #>> '{}', '')::date from public.einstellung where schluessel = 'heute_test'),
                  current_date)
$$;
comment on function heute() is
  'Der Tag, bis zu dem gerechnet wird — current_date, im Test die Einstellung heute_test (0061).';
revoke all on function heute() from public;
grant execute on function heute() to authenticated;

-- Der Stichtag ist nur noch der Horizont der Prognose.
create or replace function stichtag() returns date
language sql stable set search_path = public as $$
  select greatest((select nullif(wert #>> '{}', '')::date from public.einstellung where schluessel = 'saison_ende'),
                  public.heute())
$$;
comment on function stichtag() is
  'Bis wohin die Prognose reicht: das Saisonende aus den Einstellungen, mindestens heute (0061).';
revoke all on function stichtag() from public;
grant execute on function stichtag() to authenticated;

-- ---------- 1. Waschen zählt Paletten: Sortierdatum und Kisten je Palette --
-- Nach dem Sortieren stehen die Kaliber-Kisten wieder auf Paletten, mit
-- einem Zettel: dem Sortierdatum. Beim Waschen wird die Palette gezählt (ein
-- Tipp), mit ihrem Sortierdatum und der Kistenzahl — nicht Kiste für Kiste.
alter table auftrag_palette add column if not exists sortierdatum date;
alter table auftrag_palette add column if not exists kisten int check (kisten is null or kisten > 0);
comment on column auftrag_palette.sortierdatum is
  'Beim Waschen: das Sortierdatum vom Zettel der Palette (die Zeit im Zwischenlager). 0061.';
comment on column auftrag_palette.kisten is
  'Beim Waschen: wie viele Kaliber-Kisten auf dieser Palette standen — die Masse ist Kisten × Kistengewicht. 0061.';
create index if not exists auftrag_palette_sortierdatum on auftrag_palette (auftrag_id, sortierdatum);
-- Beim Waschen trägt die Palette ihr Sortierdatum, kein Eingangsdatum (das
-- steht auf keinem Zettel mehr). Die Pflicht „ein Datum" bleibt.
alter table auftrag_palette drop constraint if exists auftrag_palette_datum_pflicht;
alter table auftrag_palette add constraint auftrag_palette_datum_pflicht
  check (eingangsdatum is not null or sortierdatum is not null or kisten is not null
         or palette_id is not null or wiegung_id is not null)
  not valid;

-- Eine beim Waschen gezählte Palette (mit Kisten) ist eine Kaliber-Palette
-- aus dem Zwischenlager — keine Eingangspalette. Sie darf nicht mit der
-- mittleren Palettenmasse der Charge als Eingang zählen; ihre Masse sind die
-- Kisten mal das gemessene Kistengewicht (unten). Sonst wie 0060.
create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  select vw.id,
         zahl(vw.brutto_damals_kg - coalesce(vw.kisten, 0) * g.tara_kg_pro_kiste
              - coalesce(g.tara_kg_palette, 0), 2, 1e8)::numeric(10,2) as netto_damals_kg,
         vw.eingangsdatum
    from verdunstung_wiegung vw
    left join gebinde g on g.art = vw.gebindeart
), datum_mittel as materialized (
  select charge_nr, eingangsdatum, avg(netto_kg) as netto_mittel
    from v_palette group by charge_nr, eingangsdatum
), charge_mittel as materialized (
  select charge_nr, avg(netto_kg) as netto_mittel,
         avg(brutto_kg - netto_kg) filter (where netto_kg is not null) as tara_mittel
    from v_palette group by charge_nr
), charge_datum as materialized (
  select charge_nr, eingangsdatum_mittel from v_charge_rueckgrat
), zettel as materialized (
  select ap.id,
         coalesce(pe.netto_kg,
                  zahl(ap.brutto_zettel_kg - cm.tara_mittel, 2, 1e8)::numeric(10,2)) as netto_kg,
         (pe.id is not null) as exakt
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join lateral (
      select p.id, p.netto_kg from v_palette p
       where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum
         and p.brutto_kg = ap.brutto_zettel_kg and p.netto_kg is not null
       order by p.id limit 1) pe on true
    left join charge_mittel cm on cm.charge_nr = a.charge_nr
   where ap.brutto_zettel_kg is not null
)
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(w.netto_damals_kg, z.netto_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) as eingangsdatum,
       case when w.netto_damals_kg is not null then 'gewogen'
            when z.netto_kg is not null and z.exakt then 'zettel'
            when z.netto_kg is not null then 'zettel-charge-tara'
            when p.netto_kg is not null then 'palette'
            when d.netto_mittel is not null then 'datum-mittel'
            when cm.netto_mittel is not null then 'charge-mittel'
            else 'unbekannt' end::text                                                 as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w on w.id = ap.wiegung_id
  left join zettel z on z.id = ap.id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr
 where ap.kisten is null;   -- 0061: gezählte Kaliber-Paletten sind kein Eingang
comment on view v_auftrag_palette_masse is
  'Netto je gezählter Eingangspalette: gewogen, vom Zettel, aus dem Wareneingang, '
  'oder das Mittel des Eingangstags / der Charge. Beim Waschen gezählte Paletten '
  '(mit Kisten) stehen nicht hier — ihre Masse rechnet v_auftrag_wasch_paletten (0061).';

-- Die Masse je Arbeit: beim Waschen aus den gezählten Paletten (Kisten ×
-- Kistengewicht des Kalibers); die alten Kisten-Zähler (auftrag_gebinde mit
-- Sortierdatum, 0060) bleiben lesbar.
create or replace view v_auftrag_wasch_paletten with (security_invoker = true) as
with band as (
  select distinct s.sorte, i.idx as kaliber_idx,
         (s.kaliber_baender -> i.idx ->> 0)::int as von,
         (s.kaliber_baender -> i.idx ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) as i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null
)
select a.id as auftrag_id,
       count(*)::int                                                   as n_paletten,
       sum(ap.kisten)::int                                              as kisten,
       zahl(sum(ap.kisten) * max(k.kg_je_gebinde), 2, 1e10)::numeric(12,2) as kg,
       max(k.n)                                                         as n_messungen,
       -- die Zeit im Zwischenlager, massegewichtet über die Kisten
       zahl(sum((ap.kisten * (a.start_ts::date - ap.sortierdatum))::numeric) filter (where ap.sortierdatum is not null)
            / nullif(sum(ap.kisten) filter (where ap.sortierdatum is not null), 0), 1, 1e5)::numeric(8,1)
                                                                        as zwischenlager_tage,
       count(*) filter (where ap.sortierdatum is not null)::int          as n_mit_sortierdatum
  from auftrag a
  join charge c on c.nr = a.charge_nr
  join auftrag_palette ap on ap.auftrag_id = a.id and ap.kisten is not null
  left join lateral (
    select b.kaliber_idx from band b
     where a.kaliber_idx is null and b.sorte = c.sorte
       and b.von = a.kaliber_von_g and b.bis = a.kaliber_bis_g
     order by b.kaliber_idx limit 1
  ) e on true
  left join v_koeff_gebinde k
         on k.sorte = c.sorte and k.kaliber_idx = coalesce(a.kaliber_idx, e.kaliber_idx)
 where a.station = 'waschen' and not a.ist_fax and a.abgebrochen_ts is null
 group by a.id;
comment on view v_auftrag_wasch_paletten is
  'Beim Waschen gezählte Paletten: Kisten gesamt, Masse = Kisten × gemessenes '
  'Kistengewicht des Kalibers, Tage im Zwischenlager aus dem Sortierdatum (0061).';
grant select on v_auftrag_wasch_paletten to authenticated;

create or replace view v_auftrag_masse with (security_invoker = true) as
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten,
       coalesce(m.eingang_netto_kg, wp.kg, gb.kg, fp.kg)::numeric        as eingang_netto_kg,
       (case when m.masse_quelle <> 'fehlt' then m.masse_quelle
             when wp.kg is not null         then 'wasch_paletten'
             when gb.kg is not null         then 'gebinde'
             when fp.kg is not null         then 'fax_paletten'
             else 'fehlt' end)::text                                    as masse_quelle,
       zahl(coalesce(m.lagertage,
         case when m.station = 'waschen'
              then (m.start_ts::date - date '2000-01-01')::numeric
                   - coalesce(se.tage_seit_epoche,
                              (r.eingangsdatum_mittel - date '2000-01-01')::numeric)
              else null end), 1, 1e9)::numeric(10,1)                    as lagertage,
       a.ist_fax,
       -- neu (0061): die Zeit im Zwischenlager, wo sie gezählt wurde
       wp.zwischenlager_tage
  from mv_auftrag_masse m
  join auftrag a on a.id = m.auftrag_id
  left join mv_sortier_eingang se on se.charge_nr = m.charge_nr
  left join v_charge_rueckgrat r  on r.charge_nr  = m.charge_nr
  left join v_auftrag_wasch_paletten wp on wp.auftrag_id = m.auftrag_id
  left join (select auftrag_id, sum(kg) as kg from v_auftrag_gebinde_masse group by auftrag_id) gb
         on gb.auftrag_id = m.auftrag_id
  left join lateral (
    select zahl(a.paletten_gesamt * p.netto_kg, 2, 1e10)::numeric(12,2) as kg
      from v_koeff_palette_netto p
     where a.ist_fax and a.paletten_gesamt > 0 and p.sorte = m.sorte
       and (p.kistensystem = a.kistensystem or (p.kistensystem is null and a.kistensystem is distinct from 'anderes'))
     order by (p.kistensystem = a.kistensystem) desc nulls last limit 1
  ) fp on true;
comment on view v_auftrag_masse is
  'Masse je Arbeit: gewogene Paletten oder Zettel, beim Waschen gezählte Paletten '
  '(Kisten × Kistengewicht, 0061), sonst gezählte Kisten, beim Fax die Palettenzahl '
  'mal gemessener Palettenmasse. ist_fax: kein Waschgang.';

-- ---------- 2. Die Basis rechnet bis heute -----------------------------------
-- v_kaskade_basis.stichtag war der Tag, bis zu dem die Ware im Haus gealtert
-- wurde: das Saisonende. Jetzt ist es heute(). mv_kaskade liest die Spalte
-- beim Erneuern — die Kaskade selbst bleibt, wie sie ist. Zwei neue Spalten
-- am Ende sagen es deutlich.
create or replace view v_kaskade_basis with (security_invoker = true) as
with stichtag as (
  -- 0061: bis heute — nicht bis zum Saisonende. Der Name bleibt, weil
  -- mv_kaskade die Spalte so liest; die Spalten heute/saison_ende am Ende
  -- sagen, was gemeint ist.
  select heute() as bis
), je_station as (
  select charge_nr,
         sum(eingang_netto_kg) filter (where station = 'sortieren')          as sortiert_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen' and not ist_fax) as gewaschen_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren')  as hand_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren'
                                         and weg = 'hand')                   as kg_hand,
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
), kohorte as (
  select k.charge_nr,
         min(k.eingangsdatum)                                     as eingang_von,
         max(k.eingangsdatum)                                     as eingang_bis,
         count(*)::int                                            as n_eingangstage
    from v_charge_kohorte k
   group by k.charge_nr
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg                                                     as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       s.bis                                                                  as stichtag,
       r.n_paletten_mit_netto,
       -- Gegenproben aus den (punktuell) erfassten Arbeiten — keine Mengen
       -- für Überblick oder Ursachen, nur für Modell-gegen-CSV.
       coalesce(a.sortiert_kg, 0)                                             as sortiert_kg,
       coalesce(a.gewaschen_kg, 0)                                            as gewaschen_kg,
       coalesce(a.hand_kg, 0)                                                 as hand_kg,
       (coalesce(a.sortiert_kg, 0) * (1 - coalesce(a.anteil_gewaschen, 0)))    as wartet_kg,
       coalesce(a.anteil_gewaschen, 0)                                        as anteil_gewaschen,
       coalesce(a.kg_hand / nullif(coalesce(a.hand_kg, 0)
                                   + coalesce(a.sortiert_kg, 0), 0), 0)       as weg2_anteil,
       a.alter_band,
       coalesce(a.am_band_kg, 0)                                              as am_band_kg,
       k.eingang_von, k.eingang_bis, k.n_eingangstage,
       -- neu (0061)
       heute()                                                                as heute,
       stichtag()                                                             as saison_ende
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
  left join kohorte k on k.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;
comment on view v_kaskade_basis is
  'Eingang je Charge (vollständig, aus dem Erntejournal) und die Gegenproben aus '
  'den erfassten Arbeiten. stichtag ist seit 0061 heute(): die Ware im Haus altert '
  'bis heute, nicht bis zum Saisonende; saison_ende ist nur der Horizont der Prognose.';

-- ---------- 3. Die Kennzahlen je Charge, alle bis heute -------------------
-- v_hochrechnung_basis bekommt die Zahlen, die der Überblick zeigen soll —
-- mit ihrem Zeitbezug im Namen:
--   verlust_heute_kg      Verdunstung + Schimmel + nicht lagerbedingt Faules
--                         (beide Portionen beim eigenen Alter: Liefertag / heute)
--                         + Fax-Faules am Abgepackten; die Teile stehen einzeln
--                         daneben. Fax an der Ware im Haus ist fax_erwartet_kg —
--                         eine Erwartung fürs Abpacken, kein Verlust bis heute.
--   im_haus_heute_kg      was heute noch im Haus liegt, nach Verdunstung und
--                         Verderb — Eingang − Ausgang − Verlust bis heute
--   verkaufsfaehig_heute  davon in der richtigen Grösse und ohne Fax-Faules
--   kanal_heute_kg        zu klein / zu gross (anderer Kanal, nicht verloren)
-- Die Sicht bekommt neue Spalten mitten drin (die Verlustteile) — also neu
-- anlegen; was daran hing, wird weiter unten neu angelegt (Massenbilanz,
-- nächste Charge, Lagerkontrolle, Saisonbilanz).
drop view if exists v_hochrechnung_basis cascade;
create view v_hochrechnung_basis with (security_invoker = true) as
with je_charge as (
  select charge_nr,
         sum(m0) filter (where portion = 'ausgelagert')                       as ausgelagert_kg,
         sum(m0 * alter_tage) filter (where portion = 'ausgelagert')
           / nullif(sum(m0) filter (where portion = 'ausgelagert'), 0)        as alter_ausgelagert,
         sum(m0) filter (where portion = 'lager')                             as lager_kg,
         sum(m0 * alter_tage) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as alter_lager,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager')              as verkaufsfaehig_lager_kg,
         sum(geliefert_kg)                                                    as geliefert_kg,
         sum(ueberzaehlung_kg)                                                as ueberzaehlung_kg,
         sum(n_lieferungen)::int                                              as n_lieferungen,
         min(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_von,
         max(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_bis,
         count(*) filter (where portion = 'lager' and m0 > 0)::int            as n_rest_kohorten,
         sum(m0 * (kohorte - date '2000-01-01')) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as rest_tage_seit_epoche,
         -- 0061: bis heute
         sum(verdunstung_kg)                                                  as verdunstung_heute_kg,
         sum(schimmel_kg)                                                     as schimmel_heute_kg,
         sum(sockel_kg)                                                       as sockel_heute_kg,
         sum(klein_kg + nebenkanal_kg)                                        as kanal_heute_kg,
         -- Fax-Faules ist gemessen an dem, was abgepackt wurde (ausgelagert);
         -- für die Ware im Haus ist es eine Erwartung, kein Verlust bis heute
         sum(fax_kg) filter (where portion = 'ausgelagert')                   as fax_heute_kg,
         sum(fax_kg) filter (where portion = 'lager')                         as fax_erwartet_kg,
         sum(m2) filter (where portion = 'lager')                             as im_haus_heute_kg,
         sum(klein_kg + nebenkanal_kg) filter (where portion = 'lager')       as kanal_im_haus_kg,
         bool_and(r_bekannt and f_bekannt)                                    as verlust_bekannt
    from mv_kaskade
   group by charge_nr
)
select b.charge_nr, b.schlag, b.sorte,
       b.eingang_kg,
       b.n_paletten,
       b.eingangsdatum_mittel,
       zahl(coalesce(k.ausgelagert_kg, 0), 2, 1e12)::numeric(14,2)             as ausgelagert_kg,
       zahl(k.alter_ausgelagert, 1, 1e5)::numeric(8,1)                         as alter_ausgelagert,
       zahl(coalesce(k.lager_kg, b.eingang_kg), 2, 1e12)::numeric(14,2)         as lager_kg,
       zahl(coalesce(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)), 1, 1e5)::numeric(8,1)
                                                                              as alter_lager,
       zahl((heute() - x.rest_datum), 1, 1e5)::numeric(8,1)                    as alter_lager_heute,
       b.weg2_anteil,
       b.stichtag,
       b.n_paletten_mit_netto,
       zahl(coalesce(k.ueberzaehlung_kg, 0), 2, 1e12)::numeric(14,2)           as ueberzaehlung_kg,
       b.sortiert_kg, b.gewaschen_kg, b.wartet_kg, b.anteil_gewaschen, b.alter_band, b.am_band_kg,
       x.rest_datum                                                           as eingangsdatum_rest,
       (coalesce(k.n_lieferungen, 0) > 0)                                     as rest_alter_aus_zaehlung,
       b.eingang_von, b.eingang_bis, b.n_eingangstage,
       coalesce(k.rest_von, b.eingang_von)                                    as rest_von,
       coalesce(k.rest_bis, b.eingang_bis)                                    as rest_bis,
       round(coalesce(k.lager_kg, b.eingang_kg)
             / nullif(b.eingang_kg / nullif(b.n_paletten, 0), 0))::int        as n_rest_paletten,
       coalesce(k.n_rest_kohorten, b.n_eingangstage)                          as n_rest_kohorten,
       (heute() - coalesce(k.rest_bis, b.eingang_bis))::int                   as alter_lager_von,
       (heute() - coalesce(k.rest_von, b.eingang_von))::int                   as alter_lager_bis,
       zahl(coalesce(k.geliefert_kg, 0), 2, 1e12)::numeric(14,2)              as geliefert_kg,
       zahl(k.verkaufsfaehig_lager_kg, 2, 1e12)::numeric(14,2)                 as verkaufsfaehig_lager_kg,
       coalesce(k.n_lieferungen, 0)                                           as n_lieferungen,
       -- neu (0061): alles bis heute, mit Namen, die es sagen
       zahl(k.verdunstung_heute_kg, 2, 1e12)::numeric(14,2)                   as verdunstung_heute_kg,
       zahl(k.schimmel_heute_kg, 2, 1e12)::numeric(14,2)                      as schimmel_heute_kg,
       zahl(k.sockel_heute_kg, 2, 1e12)::numeric(14,2)                        as sockel_heute_kg,
       zahl(coalesce(k.fax_heute_kg, 0), 2, 1e12)::numeric(14,2)              as fax_heute_kg,
       zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.sockel_heute_kg + coalesce(k.fax_heute_kg, 0),
            2, 1e12)::numeric(14,2)                                           as verlust_heute_kg,
       zahl(k.kanal_heute_kg, 2, 1e12)::numeric(14,2)                         as kanal_heute_kg,
       zahl(coalesce(k.fax_erwartet_kg, 0), 2, 1e12)::numeric(14,2)           as fax_erwartet_kg,
       zahl(coalesce(k.im_haus_heute_kg, b.eingang_kg), 2, 1e12)::numeric(14,2) as im_haus_heute_kg,
       zahl(k.kanal_im_haus_kg, 2, 1e12)::numeric(14,2)                       as kanal_im_haus_kg,
       coalesce(k.verlust_bekannt, false)                                     as verlust_bekannt,
       heute()                                                                as heute
  from v_kaskade_basis b
  left join je_charge k on k.charge_nr = b.charge_nr
  cross join lateral (
    select case when k.rest_tage_seit_epoche is not null
                then date '2000-01-01' + round(k.rest_tage_seit_epoche)::int
                else b.eingangsdatum_mittel end as rest_datum
  ) x
 where b.eingang_kg is not null;
comment on view v_hochrechnung_basis is
  'Je Charge, alles bis heute (0061): Eingang und geliefert (gemessen), '
  'ausgelagert (Eingangsmasse hinter den Lieferungen), lager_kg (Eingang minus '
  'ausgelagert, in Eingangskilo), verlust_heute_kg (Verdunstung + Schimmel + Sockel bis '
  'heute + Fax am Abgepackten; fax_erwartet_kg steht daneben), '
  'im_haus_heute_kg (was heute nach Verdunstung und Verderb noch da ist), '
  'verkaufsfaehig_lager_kg (davon in der richtigen Grösse). Keine Prognose.';

-- ---------- 4. Der Verlauf: Eingang, Ausgang, Verlust bis heute — dann Prognose
-- Die Grafik, die der Betrieb sehen will: drei Linien über die Wochen.
-- Eingang und Ausgang (alle Lieferungen) sind gemessen und enden heute. Der
-- Verlust ist gerechnet — bis heute aus dem, was jede Portion bei ihrem Alter
-- verloren hat, danach als Prognose: die Ware im Haus altert weiter bis zum
-- Saisonende, nichts Neues kommt herein, nichts geht hinaus (das weiss niemand).
-- „Im Haus" ist dieselbe Rechnung je Portion, nicht Eingang − Ausgang − Verlust:
-- hinter einer Lieferung steckt mehr Eingangsware als das Gelieferte (das zu
-- Kleine daran ging an die Tiere, ohne Lieferschein), und das darf nicht als
-- „noch im Haus" stehen bleiben.
--
-- Je Portion der Kaskade (Charge, Eingangstag, ausgelagert/lager) und Woche:
--   t = Alter am Wochenende, bei ausgelagerter Ware höchstens bis zum Liefertag
--   Verdunstung(t) = m0 · (1 − (1−r)^t)
--   Faules(t)      = m0 · (1−r)^t · (a0 + (1−a0)·F(t))
--   Fax            = das gemessene Fax-Faule der Portion, gebucht am Liefertag
-- F(t) ist das Verderbsmodell — dieselbe Formel wie in der Kaskade.
drop materialized view if exists erg_verlauf cascade;
create materialized view erg_verlauf as
with modell as materialized (
  select * from v_schimmel_modell
), kurve as materialized (
  select von, anteil_mono from v_schimmel_kurve where n > 0
), wochen as materialized (
  select w::date as woche, (w + interval '6 days')::date as bis
    from generate_series(
      date_trunc('week', coalesce((select min(eingangsdatum) from palette), heute()))::date,
      date_trunc('week', stichtag())::date, interval '7 days') w
), portionen as materialized (
  select k.charge_nr, k.sorte, k.portion, k.kohorte, k.m0, k.r, k.a0, k.modell_gilt,
         case when k.portion = 'ausgelagert' then k.kohorte + round(k.alter_tage)::int end as liefertag,
         case when k.portion = 'ausgelagert' then k.fax_kg else 0 end                     as fax_kg
    from mv_kaskade k
   where k.m0 > 0 and k.kohorte is not null
-- F(t) hängt nur vom Alter in Tagen ab, nicht von der Portion. Einmal je Tag
-- gerechnet statt einmal je Portion und Woche: bei dreifacher Saison sind das
-- 400 Zeilen statt 113 000 — und die Kurvensuche (ein Sortieren je Zeile)
-- entfällt genauso oft. Das ist der Unterschied zwischen 4.9 und 0.6 Sekunden.
), f_je_tag as materialized (
  select gs.t,
         case when gs.t <= 0 then 0
              when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                     m.ln_lambda_korrigiert + m.k * ln(greatest(gs.t::numeric, 1)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select c.anteil_mono from kurve c
                                              where c.von <= gs.t order by c.von desc limit 1), 0), 0), 1)
         end as f
    from generate_series(0, greatest(coalesce(
           (select max(w.bis) from wochen w) - (select min(p.kohorte) from portionen p), 0), 0)) gs(t)
   cross join modell m
), je_woche as (
  select w.woche, w.bis, p.sorte,
         p.m0 * (1 - power(1 - p.r, x.t))                                     as verdunstung_kg,
         p.m0 * power(1 - p.r, x.t) * (p.a0 + (1 - p.a0) * f.f)                as faul_kg,
         -- Fax-Faules: gemessen am Abgepackten, gebucht am Liefertag
         case when p.liefertag is not null and p.liefertag <= w.bis then p.fax_kg else 0 end as fax_kg,
         -- im Haus: was von der Portion nach Verdunstung und Verderb noch da
         -- ist — solange sie nicht ausgeliefert ist. Danach ist sie weg, samt
         -- dem, was an ihr zu klein oder zu gross war.
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0 - (1 - p.a0) * f.f)
              else 0 end                                                      as im_haus_kg
    from wochen w
    join portionen p on p.kohorte <= w.bis
    cross join lateral (
      select greatest(least(w.bis, coalesce(p.liefertag, w.bis)) - p.kohorte, 0) as t
    ) x
    join f_je_tag f on f.t = x.t
), verlust as (
  select woche, bis, sorte,
         sum(verdunstung_kg) as verdunstung_kg, sum(faul_kg) as faul_kg, sum(fax_kg) as fax_kg,
         sum(im_haus_kg) as im_haus_kg
    from je_woche
   group by grouping sets ((woche, bis, sorte), (woche, bis))
), eingang as (
  select w.woche, p.sorte, sum(p.netto_kg) as kg
    from wochen w
    join (select v.eingangsdatum, c.sorte, v.netto_kg from v_palette v join charge c on c.nr = v.charge_nr) p
      on p.eingangsdatum <= w.bis
   group by grouping sets ((w.woche, p.sorte), (w.woche))
), ausgang as (
  select w.woche, l.sorte, sum(l.masse_kg) as kg
    from wochen w
    join (select l.datum, coalesce(l.sorte, c.sorte) as sorte, l.masse_kg
            from v_lieferung_masse l left join charge c on c.nr = l.charge_nr
           where l.masse_kg is not null
          union all
          select coalesce((select nullif(wert #>> '{}', '')::date from einstellung where schluessel = 'erfassungsbeginn'),
                          r.letzter_eingang), r.sorte, cv.ausgang_vor_app_kg
            from charge_vorlauf cv join v_charge_rueckgrat r on r.charge_nr = cv.charge_nr
           where cv.ausgang_vor_app_kg > 0) l
      on l.datum <= w.bis
   group by grouping sets ((w.woche, l.sorte), (w.woche))
)
select w.woche, w.bis, (w.bis > heute())                                      as prognose,
       s.sorte,
       zahl(coalesce(e.kg, 0), 2, 1e12)::numeric(14,2)                         as eingang_kum_kg,
       zahl(coalesce(a.kg, 0), 2, 1e12)::numeric(14,2)                         as ausgang_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0), 2, 1e12)::numeric(14,2)             as verdunstung_kum_kg,
       zahl(coalesce(v.faul_kg, 0), 2, 1e12)::numeric(14,2)                    as faul_kum_kg,
       zahl(coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)                     as fax_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0) + coalesce(v.faul_kg, 0) + coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)
                                                                              as verlust_kum_kg,
       zahl(coalesce(v.im_haus_kg, 0), 2, 1e12)::numeric(14,2)                 as im_haus_kg
  from wochen w
  cross join (select distinct sorte from verlust) s
  left join verlust v on v.woche = w.woche and v.sorte is not distinct from s.sorte
  left join eingang e on e.woche = w.woche and e.sorte is not distinct from s.sorte
  left join ausgang a on a.woche = w.woche and a.sorte is not distinct from s.sorte
 with no data;
create unique index if not exists erg_verlauf_pk on erg_verlauf (woche, coalesce(sorte, ''));
grant select on erg_verlauf to authenticated;
comment on materialized view erg_verlauf is
  'Je Woche (und je Sorte; sorte NULL = alles): Eingang und Ausgang kumuliert '
  '(gemessen, Ausgang: alle Lieferungen), der Verlust kumuliert (gerechnet, bis heute), '
  'danach als Prognose bis zum Saisonende (prognose = true). im_haus_kg: je Portion, '
  'was nach Verdunstung und Verderb noch da ist, solange sie nicht ausgeliefert ist (0061).';

-- ---------- 5. Die Ströme je Gruppe, mit Bereich: vorgerechnet ------------
-- verlust_ranking() rechnete den Bereich je Aufruf — und die App rief es je
-- Filter, je Reiter, bei jedem Öffnen. Jetzt steht das Ergebnis für jede
-- Gruppe, die es gibt (Gesamt, jede Sorte, jeder Schlag, jede Charge), in
-- einer gespeicherten Sicht; die Funktion liest nur noch daraus. Die Summen
-- sind über Chargen additiv, also lässt sich die Rechnung gruppieren.
-- Die Zwischenschritte sind „materialized": sonst rechnet der Planer die
-- Varianz je Ausgabezeile neu (366 Schleifen, 3 s statt 0.3 s).
drop view if exists v_marge_buch cascade;
drop view if exists v_saisonbilanz cascade;
drop view if exists v_verlust_ranking cascade;
drop function if exists verlust_ranking(text, text, numeric, int);
drop function if exists verlust_ranking(text, text, int);
drop materialized view if exists erg_verlust cascade;
drop view if exists v_verlust_je_gruppe cascade;

create view v_verlust_je_gruppe with (security_invoker = true) as
with gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from v_kaskade_basis
  union all select 'sorte',  sorte,            charge_nr from v_kaskade_basis
  union all select 'schlag', schlag,           charge_nr from v_kaskade_basis
  union all select 'charge', charge_nr::text,  charge_nr from v_kaskade_basis
),
zeilen as materialized (
  select g.gruppe, g.schluessel, h.*,
         -- Fax-Faules an der Ware im Haus: eine Erwartung fürs Abpacken, kein
         -- Verlust bis heute — wird getrennt ausgewiesen (kg_erwartet)
         (h.strom = 'Faul beim Abpacken (Fax)' and h.portion = 'lager') as erwartet
    from mv_hochrechnung h
    join gruppen g on g.charge_nr = h.charge_nr
   where h.buch in ('verlust', 'marge', 'feld')
),
unsicherheit as materialized (
  select * from v_koeff_unsicherheit
),
modell as materialized (
  select * from v_schimmel_modell
),
eingang as materialized (
  select g.gruppe, g.schluessel, sum(b.eingang_kg) as eingang_kg, count(*)::int as n_chargen
    from gruppen g join v_kaskade_basis b on b.charge_nr = g.charge_nr
   group by g.gruppe, g.schluessel
),
je_sorte as materialized (
  select z.gruppe, z.schluessel, z.strom, z.buch, z.sorte, max(z.koeff_art) as koeff_art,
         sum(z.d_r) as g_r, sum(z.d_a) as g_a
    from zeilen z where not z.erwartet group by z.gruppe, z.schluessel, z.strom, z.buch, z.sorte
),
je_strom_modell as materialized (
  select z.gruppe, z.schluessel, z.strom, z.buch,
         sum(z.d_eta)       as g_achse,
         sum(z.d_eta * z.u) as g_steigung,
         sum(z.d_a0)        as g_a0
    from zeilen z where not z.erwartet group by z.gruppe, z.schluessel, z.strom, z.buch
),
varianz_r as materialized (
  select s.gruppe, s.schluessel, s.strom, s.buch,
         sum(power(s.g_r, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_r * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join unsicherheit u
           on u.art = 'verdunstung' and u.sorte is not distinct from s.sorte
   group by s.gruppe, s.schluessel, s.strom, s.buch
),
varianz_a as materialized (
  select s.gruppe, s.schluessel, s.strom, s.buch,
         sum(power(s.g_a, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_a * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join unsicherheit u
           on u.art = s.koeff_art and u.sorte is not distinct from s.sorte
   where s.koeff_art is not null
   group by s.gruppe, s.schluessel, s.strom, s.buch
),
varianz_f as materialized (
  select m.gruppe, m.schluessel, m.strom, m.buch,
         power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
         + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
         + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)
         + power(m.g_a0, 2) * case when sm.brauchbar then coalesce(sm.sockel_var, 0) else 0 end
                                                                as varianz,
         coalesce(sm.c_chargen - 1, 1)                          as df
    from je_strom_modell m cross join modell sm
),
summe as materialized (
  select z.gruppe, z.schluessel, z.strom, z.buch,
         sum(z.kg) filter (where not z.erwartet)                  as kg,
         bool_and(z.koeff_bekannt)                                as bekannt,
         sum(z.kg) filter (where z.portion = 'ausgelagert')       as kg_beobachtet,
         sum(z.kg) filter (where z.portion = 'lager' and not z.erwartet) as kg_projiziert,
         sum(z.kg) filter (where z.f_extrapoliert and not z.erwartet)    as kg_extrapoliert,
         sum(z.kg) filter (where z.erwartet)                      as kg_erwartet,
         min(z.koeff_n)                                           as koeff_n_min,
         sum(z.basis_kg)                                          as basis_kg,
         max(z.koeff_basis)                                       as koeff_basis,
         max(z.koeff_art)                                         as koeff_art,
         max(z.formel)                                            as formel
    from zeilen z group by z.gruppe, z.schluessel, z.strom, z.buch
)
select s.gruppe, s.schluessel, s.strom, s.buch,
       (case when s.bekannt then zahl(s.kg) end)::numeric(14,2)                                            as kg,
       (case when s.bekannt then zahl(greatest(s.kg - g.t * g.streuung - zu.zuschlag, 0)) end)::numeric(14,2) as kg_unten,
       (case when s.bekannt then zahl(s.kg + g.t * g.streuung + zu.zuschlag) end)::numeric(14,2)          as kg_oben,
       (case when s.bekannt then zahl(s.kg_beobachtet) end)::numeric(14,2)                                 as kg_beobachtet,
       (case when s.bekannt then zahl(s.kg_projiziert) end)::numeric(14,2)                                 as kg_projiziert,
       (case when s.bekannt then zahl(s.kg_extrapoliert) end)::numeric(14,2)                               as kg_extrapoliert,
       (case when s.bekannt then zahl(s.kg_erwartet) end)::numeric(14,2)                                   as kg_erwartet,
       s.koeff_n_min,
       (case when s.bekannt then zahl(g.streuung) end)::numeric(14,2)                                      as streuung_kg,
       g.df,
       zahl(s.basis_kg)::numeric(14,2)                                                                    as basis_kg,
       s.koeff_basis, s.koeff_art, s.formel, s.bekannt,
       zahl(e.eingang_kg)::numeric(14,2)                                                                  as eingang_kg,
       e.n_chargen
  from summe s
  join eingang e on e.gruppe = s.gruppe and e.schluessel = s.schluessel
  left join varianz_r vr on vr.gruppe = s.gruppe and vr.schluessel = s.schluessel and vr.strom = s.strom and vr.buch = s.buch
  left join varianz_a va on va.gruppe = s.gruppe and va.schluessel = s.schluessel and va.strom = s.strom and va.buch = s.buch
  left join varianz_f vf on vf.gruppe = s.gruppe and vf.schluessel = s.schluessel and vf.strom = s.strom and vf.buch = s.buch
  cross join lateral (select coalesce(sm2.selektions_versatz, 0) as versatz from modell sm2) sel
  cross join lateral (
    select sqrt(greatest(coalesce(vr.varianz, 0) + coalesce(va.varianz, 0)
                         + coalesce(vf.varianz, 0), 0))       as streuung,
           least(coalesce(vr.df, 999), coalesce(va.df, 999),
                 coalesce(vf.df, 999))                        as df
  ) g0
  cross join lateral (select g0.streuung, g0.df, t_quantil_95(g0.df) as t) g
  cross join lateral (
    select case when s.strom = 'Schimmel/Fäulnis'
                then coalesce(s.kg_projiziert, 0) * abs(exp(sel.versatz) - 1)
                else 0 end                                    as zuschlag) zu;
comment on view v_verlust_je_gruppe is
  'Jeder Strom mit fortgepflanztem 95-%-Bereich für jede Gruppe: gesamt, je Sorte, '
  'je Schlag, je Charge (0061). kg NULL = Koeffizient nie gemessen. Alles bis heute: '
  'kg_beobachtet ist die ausgelieferte Ware, kg_projiziert die Ware im Haus bis heute; '
  'kg_erwartet (nur Fax) ist, was beim Abpacken der Ware im Haus noch anfallen dürfte — nicht in kg.';
grant select on v_verlust_je_gruppe to authenticated;

create materialized view erg_verlust as select * from v_verlust_je_gruppe with no data;
create unique index if not exists erg_verlust_pk on erg_verlust (gruppe, schluessel, strom);
grant select on erg_verlust to authenticated;
comment on materialized view erg_verlust is
  'Das Ergebnis für die App: die Ströme je Gruppe, gespeichert (0061). Wird mit '
  'auswertung_schritt(4) erneuert.';

-- Die Funktion bleibt für Tests und den SQL-Editor — sie liest nur noch.
create function verlust_ranking(p_sorte text default null, p_schlag text default null, p_charge int default null)
returns table (
  strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric,
  kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric, kg_erwartet numeric,
  koeff_n_min int, streuung_kg numeric, df int)
language sql stable set search_path = public as $$
  select e.strom, e.buch, e.kg, e.kg_unten, e.kg_oben, e.kg_beobachtet, e.kg_projiziert, e.kg_extrapoliert,
         e.kg_erwartet, e.koeff_n_min, e.streuung_kg, e.df
    from public.erg_verlust e
   where e.gruppe = case when p_charge is not null then 'charge'
                         when p_sorte  is not null then 'sorte'
                         when p_schlag is not null then 'schlag'
                         else 'gesamt' end
     and e.schluessel = case when p_charge is not null then p_charge::text
                             when p_sorte  is not null then p_sorte
                             when p_schlag is not null then p_schlag
                             else '' end
   order by e.kg desc nulls last
$$;
comment on function verlust_ranking(text, text, int) is
  'Alle Ströme mit Bereich, wahlweise je Charge, Sorte oder Schlag — aus erg_verlust '
  'gelesen, nicht gerechnet (0061). Eine Kombination der Filter gibt es nicht mehr.';
revoke all on function verlust_ranking(text, text, int) from public;
grant execute on function verlust_ranking(text, text, int) to authenticated;

create view v_verlust_ranking with (security_invoker = true) as
select * from verlust_ranking();
comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall; kg NULL heisst: der '
  'Koeffizient wurde nie gemessen. Bis heute, nicht bis zum Saisonende (0061).';
grant select on v_verlust_ranking to authenticated;

-- ---------- 6. Verkaufte Kisten: aus der Verkaufsdatei, nicht hochgerechnet
-- Die Überfüllung wurde bisher auf die verkaufte Masse hochgerechnet (Anteil
-- der gewogenen Paletten, die als „Kiste ab x kg" liefen). Die Verkaufsdatei
-- weiss es besser: Jede Position trägt Einheit (kg oder Stk.), Gebindeinhalt
-- (8 kg, 10 kg — oder 12 Stück, 8 Stück) und Gebindemenge; jede Chargenzeile
-- ihre eigene Kistenzahl (AufPosBatchPackageQuantity). Geprüft an den echten
-- Dateien: Menge = Gebindemenge × Gebindeinhalt in allen 185 Kürbiszeilen mit
-- Chargenbezug, Chargenmenge = Chargenkisten × Inhalt ebenso.
--
-- Daraus das Kistensystem einer verkauften Lieferung, ohne zu raten:
--   Einheit kg,  Inhalt > 1     → Kiste ab <Inhalt> kg
--   Einheit Stk., Inhalt > 0    → <Inhalt> Stück je Kiste, Nenngewicht je Stück
--   sonst                       → unbekannt (nur Kilo — nichts behaupten)
alter table ausgang_zeile add column if not exists batch_gebinde int;
comment on column ausgang_zeile.batch_gebinde is
  'Kisten dieser Chargenzeile (AufPosBatchPackageQuantity Charge). Die Kistenzahl '
  'der Position steht in gebinde_menge. 0061.';

-- Die Lieferung kennt ihre Zeile. Bisher stand nur die Kennung in
-- lieferung_import; zeile_id blieb leer. Nachgetragen aus der Kennung
-- (Quelle:Position:Charge:Lauf); die Rest-Lieferung einer Position (ohne
-- Chargenbezug) bekommt die erste Zeile der Position — Artikel, Einheit und
-- Gebinde sind auf allen Zeilen einer Position gleich.
create or replace function lieferung_import_zeilen_verbinden(p_quelle text default null)
returns int language sql volatile set search_path = public as $$
  with charge_zeilen as (
    update lieferung_import i
       set zeile_id = z.id
      from ausgang_zeile z
     where i.zeile_id is null
       and (p_quelle is null or i.quelle = p_quelle)
       and z.quelle = i.quelle
       and i.extern_id = z.quelle || ':' || z.pos_id || ':' || z.charge_extern || ':' || z.lauf_nr
     returning 1
  ), rest_zeilen as (
    update lieferung_import i
       set zeile_id = z.id
      from (select distinct on (quelle, pos_id) id, quelle, pos_id
              from ausgang_zeile order by quelle, pos_id, lauf_nr, id) z
     where i.zeile_id is null
       and (p_quelle is null or i.quelle = p_quelle)
       and z.quelle = i.quelle
       and i.extern_id = z.quelle || ':' || z.pos_id || ':rest'
     returning 1
  )
  select (select count(*) from charge_zeilen) + (select count(*) from rest_zeilen)
$$;
comment on function lieferung_import_zeilen_verbinden(text) is
  'Trägt lieferung_import.zeile_id aus der Kennung nach (Chargenzeile oder erste '
  'Zeile der Position). Läuft nach jeder Übernahme; einmal für alles Bestehende (0061).';
revoke all on function lieferung_import_zeilen_verbinden(text) from public;
grant execute on function lieferung_import_zeilen_verbinden(text) to authenticated;
do $$ begin perform lieferung_import_zeilen_verbinden(null); end $$;

-- Die Übernahme schreibt die Kistenzahl der Chargenzeile mit und verbindet
-- die Lieferungen mit ihren Zeilen. Sonst wie 0055.
create or replace function ausgang_uebernehmen(
  p_quelle       text,
  p_quelle_name  text,
  p_datei        jsonb,
  p_zeilen       jsonb,
  p_lieferungen  jsonb
) returns jsonb
language plpgsql security invoker set search_path = public as $fn$
declare
  v_datei_id     bigint;
  v_zeilen_neu   int := 0;
  v_zeilen_alt   int := 0;
  v_lief_neu     int := 0;
  v_lief_alt     int := 0;
  v_uebergangen  jsonb := '[]'::jsonb;
  l              record;
  v_lief_id      bigint;
  v_gebinde      text;
  v_sorte        text;
  v_charge       int;
begin
  if not ist_admin() then
    raise exception 'Den Warenausgang übernimmt nur der Betriebsleiter.';
  end if;
  if p_quelle is null or p_quelle = '' then
    raise exception 'Ohne Quelle (Firma) keine Übernahme — an ihr hängt die Eindeutigkeit der Positionsnummern.';
  end if;

  insert into ausgang_quelle (code, name, dateiname_muster)
  values (p_quelle, coalesce(nullif(p_quelle_name, ''), p_quelle), p_quelle)
  on conflict (code) do nothing;

  insert into ausgang_datei (quelle, dateiname, pruefsumme, n_zeilen, n_kuerbis,
                             n_neu, n_geaendert, n_unveraendert, von_datum, bis_datum)
  values (p_quelle,
          p_datei ->> 'dateiname', p_datei ->> 'pruefsumme',
          coalesce((p_datei ->> 'n_zeilen')::int, 0), coalesce((p_datei ->> 'n_kuerbis')::int, 0),
          coalesce((p_datei ->> 'n_neu')::int, 0), coalesce((p_datei ->> 'n_geaendert')::int, 0),
          coalesce((p_datei ->> 'n_unveraendert')::int, 0),
          nullif(p_datei ->> 'von_datum', '')::date, nullif(p_datei ->> 'bis_datum', '')::date)
  on conflict (quelle, pruefsumme) do update
    set dateiname = excluded.dateiname, n_zeilen = excluded.n_zeilen, n_kuerbis = excluded.n_kuerbis,
        n_neu = excluded.n_neu, n_geaendert = excluded.n_geaendert,
        n_unveraendert = excluded.n_unveraendert, von_datum = excluded.von_datum,
        bis_datum = excluded.bis_datum, ts = now()
  returning id into v_datei_id;

  with eingang as (
    select * from jsonb_to_recordset(p_zeilen) as x(
      pos_id bigint, charge_extern text, lauf_nr int, fingerabdruck text,
      datum date, journal text, auftragsnr text, kunde text,
      artikel_id text, artikel text, einheit text,
      menge numeric, gewicht_je_artikel numeric, batch_menge numeric,
      kg_position numeric, kg_charge numeric,
      gebindeart text, gebinde_menge numeric, gebinde_inhalt numeric,
      batch_gebinde numeric,
      produzent text, erloes numeric)
  ), geschrieben as (
    insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datei_id,
                               datum, journal, auftragsnr, kunde, artikel_id, artikel, einheit,
                               menge, gewicht_je_artikel, batch_menge, kg_position, kg_charge,
                               gebindeart, gebinde_menge, gebinde_inhalt, batch_gebinde, produzent, erloes)
    select p_quelle, z.pos_id, coalesce(z.charge_extern, ''), coalesce(z.lauf_nr, 1), z.fingerabdruck, v_datei_id,
           z.datum, z.journal, z.auftragsnr, z.kunde, z.artikel_id, z.artikel, z.einheit,
           z.menge, z.gewicht_je_artikel, z.batch_menge, z.kg_position, z.kg_charge,
           z.gebindeart, round(z.gebinde_menge)::int, round(z.gebinde_inhalt)::int,
           round(z.batch_gebinde)::int, z.produzent, z.erloes
      from eingang z
     where z.pos_id is not null and z.datum is not null and z.artikel_id is not null
    on conflict (quelle, pos_id, charge_extern, lauf_nr) do update
      set geaendert_ts = case when ausgang_zeile.fingerabdruck <> excluded.fingerabdruck
                              then now() else ausgang_zeile.geaendert_ts end,
          fingerabdruck = excluded.fingerabdruck, datei_id = excluded.datei_id,
          datum = excluded.datum, journal = excluded.journal, auftragsnr = excluded.auftragsnr,
          kunde = excluded.kunde, artikel_id = excluded.artikel_id, artikel = excluded.artikel,
          einheit = excluded.einheit, menge = excluded.menge,
          gewicht_je_artikel = excluded.gewicht_je_artikel, batch_menge = excluded.batch_menge,
          kg_position = excluded.kg_position, kg_charge = excluded.kg_charge,
          gebindeart = excluded.gebindeart, gebinde_menge = excluded.gebinde_menge,
          gebinde_inhalt = excluded.gebinde_inhalt, batch_gebinde = excluded.batch_gebinde,
          produzent = excluded.produzent, erloes = excluded.erloes
    returning (xmax = 0) as neu
  )
  select count(*) filter (where neu), count(*) filter (where not neu)
    into v_zeilen_neu, v_zeilen_alt from geschrieben;

  for l in
    select * from jsonb_to_recordset(p_lieferungen) as x(
      extern_id text, datum date, charge_nr int, sorte text, kg numeric,
      gebindeart text, kunde text, bemerkung text)
  loop
    if l.extern_id is null or l.datum is null or l.kg is null or l.kg <= 0 then
      v_uebergangen := v_uebergangen || jsonb_build_object(
        'extern_id', l.extern_id, 'grund', 'ohne Kennung, Datum oder Masse');
      continue;
    end if;
    v_charge := case when exists (select 1 from charge c where c.nr = l.charge_nr) then l.charge_nr end;
    v_sorte  := case when exists (select 1 from sorte_kaliber s where s.sorte = l.sorte) then l.sorte end;
    if v_charge is null and v_sorte is null then
      v_uebergangen := v_uebergangen || jsonb_build_object(
        'extern_id', l.extern_id, 'kg', l.kg, 'datum', l.datum, 'kunde', l.kunde,
        'grund', 'weder Charge noch bestätigte Sorte — der Artikel ist noch nicht zugeordnet');
      continue;
    end if;
    v_gebinde := case when exists (select 1 from gebinde g where g.art = l.gebindeart) then l.gebindeart end;

    select i.lieferung_id into v_lief_id from lieferung_import i where i.extern_id = l.extern_id;
    if v_lief_id is not null then
      update lieferung
         set datum = l.datum, charge_nr = v_charge, sorte = v_sorte, kg = l.kg,
             gebindeart = v_gebinde, kunde = l.kunde,
             bemerkung = nullif(concat_ws(' · ', nullif(l.bemerkung, ''),
                                          case when v_gebinde is null and l.gebindeart is not null
                                               then 'Gebinde laut Datei: ' || l.gebindeart end), '')
       where id = v_lief_id;
      update lieferung_import set ts = now() where lieferung_id = v_lief_id;
      v_lief_alt := v_lief_alt + 1;
    else
      insert into lieferung (datum, charge_nr, sorte, kg, gebindeart, ziel, kunde, bemerkung)
      values (l.datum, v_charge, v_sorte, l.kg, v_gebinde, 'verkauf', l.kunde,
              nullif(concat_ws(' · ', nullif(l.bemerkung, ''),
                               case when v_gebinde is null and l.gebindeart is not null
                                    then 'Gebinde laut Datei: ' || l.gebindeart end), ''))
      returning id into v_lief_id;
      insert into lieferung_import (lieferung_id, quelle, extern_id)
      values (v_lief_id, p_quelle, l.extern_id);
      v_lief_neu := v_lief_neu + 1;
    end if;
  end loop;

  -- 0061: jede Lieferung dieser Quelle kennt ihre Zeile
  perform lieferung_import_zeilen_verbinden(p_quelle);

  return jsonb_build_object(
    'datei_id', v_datei_id,
    'zeilen_neu', v_zeilen_neu, 'zeilen_geaendert', v_zeilen_alt,
    'lieferungen_neu', v_lief_neu, 'lieferungen_aktualisiert', v_lief_alt,
    'uebergangen', v_uebergangen);
end $fn$;
comment on function ausgang_uebernehmen is
  'Schreibt eine hochgeladene Warenausgangsdatei in einem Zug: Quelle (falls neu), '
  'Datei (Prüfsumme), Rohzeilen (Upsert, geaendert_ts bei anderem Fingerabdruck, seit '
  '0061 mit Kisten je Chargenzeile) und Lieferungen (Upsert über lieferung_import.extern_id, '
  'mit ihrer Zeile verbunden). Löscht nichts. Gibt zurück, was neu, was aktualisiert '
  'und was nicht übernommen wurde (mit Grund).';
revoke all on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) from public;
grant execute on function ausgang_uebernehmen(text, text, jsonb, jsonb, jsonb) to authenticated;

-- Je verkaufter Lieferung: das Kistensystem und die Kisten aus der Datei.
create or replace view v_verkauf_lieferung with (security_invoker = true) as
with position as (
  select quelle, pos_id,
         max(gebinde_menge)                                                    as gebinde_menge,
         max(kg_position)                                                      as kg_position,
         sum(batch_gebinde)      filter (where charge_extern <> '')             as batch_gebinde_summe,
         bool_and(batch_gebinde is not null) filter (where charge_extern <> '') as alle_gezaehlt
    from ausgang_zeile
   group by quelle, pos_id
), band as (
  -- das aktuelle Kaliberschema je Sorte (ohne Käufer, art = kaliber)
  select distinct on (s.sorte, i.idx) s.sorte, i.idx as kaliber_idx,
         (s.kaliber_baender -> i.idx ->> 0)::int as von,
         (s.kaliber_baender -> i.idx ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) as i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null and s.kaeufer is null
     and s.gilt_ab <= heute()
   order by s.sorte, i.idx, s.gilt_ab desc
)
select l.id                                                                     as lieferung_id,
       l.datum, l.charge_nr,
       coalesce(l.sorte, c.sorte)                                               as sorte,
       l.kg, i.quelle, z.artikel, z.einheit, z.gebinde_inhalt, z.gewicht_je_artikel,
       ks.kistensystem,
       case when ks.kistensystem = 'kiste_ab' then zahl(z.gebinde_inhalt, 2, 1e4)::numeric(6,2) end as soll_kg_pro_kiste,
       case when ks.kistensystem = 'stueck'   then z.gebinde_inhalt end          as stueck_je_kiste,
       case when ks.kistensystem = 'stueck'   then round(z.gewicht_je_artikel * 1000)::int end as nenn_g,
       case when ks.kistensystem = 'stueck'   then b.kaliber_idx end             as kaliber_idx,
       zahl(k.kisten, 1, 1e7)::numeric(10,1)                                    as kisten,
       k.kisten_quelle,
       case when ks.kistensystem = 'stueck'
            then zahl(k.kisten * z.gebinde_inhalt, 0, 1e9)::numeric(12,0) end    as stueck
  from lieferung l
  join lieferung_import i on i.lieferung_id = l.id
  join ausgang_zeile z    on z.id = i.zeile_id
  join position p         on p.quelle = z.quelle and p.pos_id = z.pos_id
  left join charge c      on c.nr = l.charge_nr
  cross join lateral (
    select case when z.einheit ~* '^stk' and coalesce(z.gebinde_inhalt, 0) > 0
                     and coalesce(z.gewicht_je_artikel, 0) > 0                 then 'stueck'
                when z.einheit ~* '^kg' and coalesce(z.gebinde_inhalt, 0) > 1   then 'kiste_ab'
                else 'unbekannt' end::text as kistensystem) ks
  left join band b on ks.kistensystem = 'stueck' and b.sorte = coalesce(l.sorte, c.sorte)
                  and round(z.gewicht_je_artikel * 1000) >= b.von and round(z.gewicht_je_artikel * 1000) < b.bis
  cross join lateral (
    select case
             -- die Chargenzeile zählt ihre Kisten selbst
             when i.extern_id not like '%:rest' and z.batch_gebinde > 0
               then z.batch_gebinde::numeric
             -- der Rest der Position: Kisten der Position minus die gezählten Chargenzeilen
             when i.extern_id like '%:rest' and coalesce(p.alle_gezaehlt, true) and p.gebinde_menge > 0
               then greatest(p.gebinde_menge - coalesce(p.batch_gebinde_summe, 0), 0)::numeric
             -- sonst der Anteil an der Position (gleiche Kisten je Kilo)
             when p.gebinde_menge > 0 and p.kg_position > 0
               then p.gebinde_menge * l.kg / p.kg_position
           end as kisten,
           case
             when i.extern_id not like '%:rest' and z.batch_gebinde > 0 then 'zeile'
             when i.extern_id like '%:rest' and coalesce(p.alle_gezaehlt, true) and p.gebinde_menge > 0 then 'rest'
             when p.gebinde_menge > 0 and p.kg_position > 0 then 'anteil'
           end::text as kisten_quelle) k
 where l.ziel = 'verkauf' and ks.kistensystem is not null;
comment on view v_verkauf_lieferung is
  'Jede importierte Verkaufslieferung mit dem Kistensystem aus der Datei (Einheit × '
  'Gebindeinhalt): Kiste ab x kg, Stück je Kiste mit Nenngewicht, oder unbekannt. '
  'kisten aus der Chargenzeile (zeile), dem Rest der Position (rest) oder anteilig '
  'an der Position (anteil). Von Hand erfasste Lieferungen stehen nicht hier (0061).';
grant select on v_verkauf_lieferung to authenticated;

-- Verkauft gegen gewogen, je Sorte (und je Charge) und Kistensystem.
-- Verschenkt wird nur gerechnet, wo beides da ist: gewogene Kisten desselben
-- Systems (der Überschuss je Kiste) und verkaufte Kisten aus der Datei.
-- Bei Stück-Kisten gibt es kein Soll und keine verschenkte Marge — nur das
-- gemessene Stückgewicht neben dem Nenngewicht der Datei.
create or replace view v_ueberfuellung_verkauf with (security_invoker = true) as
with verkauft as (
  select case when grouping(v.charge_nr) = 1 then 'sorte' else 'charge' end as gruppe,
         v.sorte, v.charge_nr, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx,
         count(*)::int                                                       as n_lieferungen,
         sum(v.kg)                                                           as kg_verkauft,
         sum(v.kisten)                                                       as kisten_verkauft,
         count(*) filter (where v.kisten_quelle = 'anteil')::int             as n_anteilig,
         sum(v.stueck)                                                       as stueck_verkauft,
         sum(v.stueck * v.nenn_g) / nullif(sum(v.stueck), 0)                 as nenn_g,
         min(v.datum)                                                        as von,
         max(v.datum)                                                        as bis
    from v_verkauf_lieferung v
   where v.sorte is not null
   group by grouping sets ((v.sorte, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx),
                           (v.sorte, v.charge_nr, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx))
), gewogen as (
  select case when grouping(k.charge_nr) = 1 then 'sorte' else 'charge' end as gruppe,
         k.sorte, k.charge_nr, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
         case when k.kistensystem = 'stueck' then k.kaliber_idx end          as kaliber_idx,
         count(*)::int                                                       as n_wiegungen,
         sum(k.kisten)                                                       as kisten_gewogen,
         sum(k.netto_kg) / nullif(sum(k.kisten), 0)                          as kg_je_kiste,
         stddev_samp(k.kg_pro_kiste)                                         as sd_je_kiste,
         sum(k.ueberfuellung_kg)                                             as zuviel_gewogen_kg,
         sum(k.netto_kg) / nullif(sum(k.kisten * k.stueck_je_kiste), 0) * 1000 as g_je_kuerbis,
         max(k.band_mittel_g)                                                as band_mittel_g
    from v_ausgang_kennzahl k
   where k.kistensystem in ('kiste_ab', 'stueck')
     and (k.kistensystem <> 'kiste_ab' or k.soll_kg_pro_kiste is not null)
     and (k.kistensystem <> 'stueck'   or k.stueck_je_kiste is not null)
   group by grouping sets ((k.sorte, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
                            case when k.kistensystem = 'stueck' then k.kaliber_idx end),
                           (k.sorte, k.charge_nr, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
                            case when k.kistensystem = 'stueck' then k.kaliber_idx end))
), band as (
  select distinct on (s.sorte, i.idx) s.sorte, i.idx as kaliber_idx,
         (s.kaliber_baender -> i.idx ->> 0)::int as von,
         (s.kaliber_baender -> i.idx ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) as i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null and s.kaeufer is null
     and s.gilt_ab <= heute()
   order by s.sorte, i.idx, s.gilt_ab desc
)
select coalesce(v.gruppe, g.gruppe)                                           as gruppe,
       coalesce(v.sorte, g.sorte)                                             as sorte,
       coalesce(v.charge_nr, g.charge_nr)                                     as charge_nr,
       coalesce(v.kistensystem, g.kistensystem)                               as kistensystem,
       coalesce(v.soll_kg_pro_kiste, g.soll_kg_pro_kiste)                     as soll_kg_pro_kiste,
       coalesce(v.stueck_je_kiste, g.stueck_je_kiste)                         as stueck_je_kiste,
       coalesce(v.kaliber_idx, g.kaliber_idx)                                 as kaliber_idx,
       b.von                                                                  as band_von_g,
       b.bis                                                                  as band_bis_g,
       zahl(v.nenn_g, 0, 1e6)::numeric(8,0)                                   as nenn_g,
       coalesce(v.n_lieferungen, 0)                                           as n_lieferungen,
       zahl(v.kg_verkauft, 1, 1e11)::numeric(12,1)                            as kg_verkauft,
       zahl(v.kisten_verkauft, 0, 1e9)::numeric(12,0)                         as kisten_verkauft,
       coalesce(v.n_anteilig, 0)                                              as n_anteilig,
       zahl(v.stueck_verkauft, 0, 1e9)::numeric(12,0)                         as stueck_verkauft,
       v.von, v.bis,
       coalesce(g.n_wiegungen, 0)                                             as n_wiegungen,
       g.kisten_gewogen,
       zahl(g.kg_je_kiste, 3, 1e7)::numeric(10,3)                             as kg_je_kiste,
       zahl(g.sd_je_kiste, 3, 1e7)::numeric(10,3)                             as sd_je_kiste,
       zahl(g.kg_je_kiste - g.soll_kg_pro_kiste, 3, 1e7)::numeric(10,3)       as zuviel_je_kiste,
       zahl(g.zuviel_gewogen_kg, 1, 1e11)::numeric(12,1)                      as zuviel_gewogen_kg,
       -- verschenkt: nur wo gewogen UND verkaufte Kisten aus der Datei
       zahl(case when g.n_wiegungen > 0 and v.kisten_verkauft is not null and g.kistensystem = 'kiste_ab'
                 then greatest(g.kg_je_kiste - g.soll_kg_pro_kiste, 0) * v.kisten_verkauft end,
            1, 1e11)::numeric(12,1)                                           as verschenkt_kg,
       zahl(case when g.n_wiegungen >= 2 and v.kisten_verkauft is not null and g.kistensystem = 'kiste_ab'
                 then t_quantil_95(g.n_wiegungen - 1) * g.sd_je_kiste / sqrt(g.n_wiegungen) * v.kisten_verkauft end,
            1, 1e11)::numeric(12,1)                                           as verschenkt_fehler_kg,
       zahl(g.g_je_kuerbis, 0, 1e6)::numeric(8,0)                             as g_je_kuerbis,
       zahl(g.band_mittel_g, 0, 1e6)::numeric(8,0)                            as band_mittel_g
  from verkauft v
  full outer join gewogen g
         on g.gruppe = v.gruppe and g.sorte = v.sorte and g.charge_nr is not distinct from v.charge_nr
        and g.kistensystem = v.kistensystem
        and g.soll_kg_pro_kiste is not distinct from v.soll_kg_pro_kiste
        and g.stueck_je_kiste is not distinct from v.stueck_je_kiste
        and g.kaliber_idx is not distinct from v.kaliber_idx
  left join band b on b.sorte = coalesce(v.sorte, g.sorte) and b.kaliber_idx = coalesce(v.kaliber_idx, g.kaliber_idx);
comment on view v_ueberfuellung_verkauf is
  'Je Sorte (gruppe sorte) und je Charge (gruppe charge), je Kistensystem: verkaufte '
  'Kisten und Kilo aus der Verkaufsdatei, gewogene Kisten und Kilo je Kiste aus den '
  'fertigen Paletten. verschenkt_kg = Überschuss je gewogener Kiste × verkaufte Kisten, '
  'nur bei „Kiste ab x kg" und nur, wo beides gemessen ist. Stück-Kisten: gemessenes '
  'Stückgewicht neben dem Nenngewicht, keine Marge (0061).';
grant select on v_ueberfuellung_verkauf to authenticated;

drop materialized view if exists erg_ueberfuellung cascade;
create materialized view erg_ueberfuellung as select * from v_ueberfuellung_verkauf with no data;
create index if not exists erg_ueberfuellung_gruppe on erg_ueberfuellung (gruppe, sorte, charge_nr);
grant select on erg_ueberfuellung to authenticated;
comment on materialized view erg_ueberfuellung is
  'v_ueberfuellung_verkauf, gespeichert für die App (0061). Erneuert mit auswertung_schritt(1).';

-- ---------- 7. Die Charge gespeichert; Bilanz, Marge, Vorschläge lesen daraus
-- erg_charge ist v_hochrechnung_basis als Tabelle: eine Zeile je Charge, alles
-- bis heute. Was daran hängt (Massenbilanz, nächste Charge, Lagerkontrolle,
-- Saisonbilanz), liest die gespeicherte Zeile statt die Kaskade neu zu rechnen.
drop materialized view if exists erg_charge cascade;
create materialized view erg_charge as select * from v_hochrechnung_basis with no data;
create unique index if not exists erg_charge_pk on erg_charge (charge_nr);
create index if not exists erg_charge_sorte on erg_charge (sorte);
grant select on erg_charge to authenticated;
comment on materialized view erg_charge is
  'v_hochrechnung_basis, gespeichert: je Charge Eingang, ausgelagert, im Haus und '
  'Verlust bis heute (0061). Erneuert mit auswertung_schritt(3).';

-- Modell gegen CSV — wie 0060, die Charge aus erg_charge.
create or replace view v_massenbilanz with (security_invoker = true) as
with csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (where exists (
                    select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
                  / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren') and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
), rest as materialized (
  select charge_nr, sum(m2) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade group by charge_nr
), modell as materialized (
  select b.charge_nr,
         b.am_band_kg
         * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
         * (1 - sockel_anteil()) * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
         * q.anteil_mit_csv                                   as am_band_modell_kg
    from v_kaskade_basis b
    left join csv_anteil q on q.charge_nr = b.charge_nr
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
)
select b.charge_nr, b.sorte, b.schlag, b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       zahl(m.am_band_modell_kg, 2, 1e12)::numeric(14,2)                       as modell_am_band_kg,
       c.gemessen_kg                                                           as csv_gemessen_kg,
       zahl(c.gemessen_kg - m.am_band_modell_kg, 2, 1e12)::numeric(14,2)       as abweichung_kg,
       case when m.am_band_modell_kg > 0
            then zahl((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg, 4, 1e6)::numeric(10,4)
       end                                                                     as abweichung_anteil,
       zahl(r.restbestand_kg, 2, 1e12)::numeric(14,2)                          as restbestand_kg,
       kb.alter_band
  from erg_charge b
  join v_kaskade_basis kb on kb.charge_nr = b.charge_nr
  left join modell m on m.charge_nr = b.charge_nr
  left join gemessen c on c.charge_nr = b.charge_nr
  left join rest r on r.charge_nr = b.charge_nr;
comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band — die '
  'eine Gegenprobe, die an gezählten Arbeiten hängt (und nur dort gilt). '
  'Die Charge kommt aus erg_charge (0061).';

-- Was kostet Warten — je Eingangstag, ab heute().
create or replace view v_naechste_charge with (security_invoker = true) as
with modell as materialized (
  select * from v_schimmel_modell
), kohorten as materialized (
  select charge_nr, eingangsdatum, anteil from v_kohorte_anteil
), bestand as (
  select b.charge_nr, b.sorte, b.schlag, b.lager_kg,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05) as r,
         t.m0, t.alter_tage
    from erg_charge b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    cross join lateral (
      select b.lager_kg * c.anteil as m0,
             greatest((heute() - c.eingangsdatum)::numeric, 0) as alter_tage
        from kohorten c where c.charge_nr = b.charge_nr
      union all
      select b.lager_kg, greatest(b.alter_lager_heute, 0)
       where not exists (select 1 from kohorten c where c.charge_nr = b.charge_nr)
    ) t
   where b.lager_kg > 0
), mit_f as (
  select b.*,
         b.m0 * power(1 - b.r, b.alter_tage) as masse_jetzt_kg,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage, 1)), -40), 3))), 0), 0.99) end as f_jetzt,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage + 14, 1)), -40), 3))), 0), 0.99) end as f_dann,
         (m.brauchbar and b.alter_tage > m.t_max) as hochgerechnet,
         m.brauchbar as modell_gilt
    from bestand b cross join modell m
), je_charge as (
  select charge_nr, sorte, schlag, lager_kg, modell_gilt,
         bool_or(hochgerechnet)                                        as hochgerechnet,
         sum(masse_jetzt_kg)                                           as masse_jetzt_kg,
         sum(masse_jetzt_kg * alter_tage) / nullif(sum(masse_jetzt_kg), 0) as alter_tage,
         min(alter_tage) as alter_von, max(alter_tage) as alter_bis,
         count(*)::int as n_kohorten,
         sum(masse_jetzt_kg * (1 - power(1 - r, 14)))                  as verdunstung_14_kg,
         case when modell_gilt
              then sum(masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0)) end as schimmel_14_kg
    from mit_f
   group by charge_nr, sorte, schlag, lager_kg, modell_gilt
)
select charge_nr, sorte, schlag,
       zahl(lager_kg, 2, 1e12)::numeric(14,2)                               as lager_kg,
       round(alter_tage)::int                                               as alter_tage,
       zahl(masse_jetzt_kg, 2, 1e12)::numeric(14,2)                         as masse_jetzt_kg,
       zahl(verdunstung_14_kg, 1, 1e11)::numeric(12,1)                      as verdunstung_14_kg,
       zahl(schimmel_14_kg, 1, 1e11)::numeric(12,1)                         as schimmel_14_kg,
       zahl(verdunstung_14_kg + coalesce(schimmel_14_kg, 0), 1, 1e11)::numeric(12,1) as verlust_14_kg,
       hochgerechnet, modell_gilt,
       round(alter_von)::int as alter_von, round(alter_bis)::int as alter_bis, n_kohorten
  from je_charge
 order by zahl(verdunstung_14_kg + coalesce(schimmel_14_kg, 0), 1, 1e11)::numeric(12,1) desc nulls last;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag '
  'ab heute() gerechnet und je Charge summiert; der Bestand aus erg_charge (0061).';

-- Die Lagerkontrolle ist eine Verdunstungsmessung: Wo bringt eine Wägung am
-- meisten? Dort, wo viel liegt und lange niemand gewogen hat — Bestand mal
-- Tage seit der letzten Wägung (jede Wägung zählt, auch die bei der Arbeit).
-- Nie gewogen: die Tage seit dem Eingang.
drop view if exists v_kontrolle_vorschlag cascade;
create view v_kontrolle_vorschlag with (security_invoker = true) as
select b.charge_nr, b.sorte, b.schlag, b.lager_kg,
       b.alter_lager_von, b.alter_lager_bis, b.eingang_von, b.eingang_bis,
       coalesce(k.n_kontrollen, 0)                                          as n_kontrollen,
       k.zuletzt,
       b.im_haus_heute_kg,
       (heute() - coalesce(k.zuletzt, b.eingang_von))::int                  as tage_seit_wiegung,
       zahl(b.im_haus_heute_kg * greatest(heute() - coalesce(k.zuletzt, b.eingang_von), 1),
            0, 1e13)::numeric(14,0)                                         as informationswert
  from erg_charge b
  left join (select charge_nr,
                    count(*) filter (where auftrag_id is null)::int as n_kontrollen,
                    max(wiege_ts)::date                             as zuletzt
               from verdunstung_wiegung
              where gemessen
              group by charge_nr) k on k.charge_nr = b.charge_nr
 where b.im_haus_heute_kg > 0
 order by informationswert desc nulls last, b.im_haus_heute_kg desc
 limit 3;
comment on view v_kontrolle_vorschlag is
  'Drei Vorschläge für die Lagerkontrolle: die Chargen, bei denen eine Wägung am '
  'meisten Information bringt — Bestand heute × Tage seit der letzten Wägung (0061). '
  'Wer eine andere Palette greift, trägt ihre Charge selbst ein.';
grant select on v_kontrolle_vorschlag to authenticated;

-- Die Saisonbilanz, alles bis heute. Sie geht per Konstruktion auf (das
-- Ausgelagerte kommt aus den Lieferungen); geprüft wird an den Rändern.
create view v_saisonbilanz with (security_invoker = true) as
with charge as (
  select sum(eingang_kg)                 as eingang_kg,
         sum(ausgelagert_kg)             as ausgelagert_kg,
         sum(geliefert_kg)               as geliefert_kg,
         sum(lager_kg)                   as lager_kg,
         sum(wartet_kg)                  as wartet_kg,
         sum(ueberzaehlung_kg)           as ueberzaehlung_kg,
         sum(verkaufsfaehig_lager_kg)    as verkaufsfaehig_heute_kg,
         sum(im_haus_heute_kg)           as im_haus_heute_kg,
         sum(kanal_im_haus_kg)           as kanal_im_haus_kg,
         sum(verlust_heute_kg)           as verlust_heute_kg,
         sum(verdunstung_heute_kg)       as verdunstung_heute_kg,
         sum(schimmel_heute_kg)          as schimmel_heute_kg,
         sum(sockel_heute_kg)            as sockel_heute_kg,
         sum(fax_heute_kg)               as fax_heute_kg,
         sum(fax_erwartet_kg)            as fax_erwartet_kg,
         sum(kanal_heute_kg)             as kanal_heute_kg,
         bool_and(verlust_bekannt)       as bekannt,
         count(*)::int                   as n_chargen,
         max(heute)                      as heute
    from erg_charge
), bereich as (
  select sum(kg_unten) filter (where buch in ('verlust', 'feld')) as verlust_unten_kg,
         sum(kg_oben)  filter (where buch in ('verlust', 'feld')) as verlust_oben_kg,
         sum(kg)       filter (where buch in ('verlust', 'feld')) as verlust_kg,
         sum(kg_unten) filter (where buch = 'marge')              as kanal_unten_kg,
         sum(kg_oben)  filter (where buch = 'marge')              as kanal_oben_kg
    from erg_verlust where gruppe = 'gesamt'
), vorlauf as (
  select coalesce(sum(ausgang_vor_app_kg), 0) as kg from charge_vorlauf
), ausgang as (
  select coalesce(sum(masse_kg), 0)                                as kg,
         coalesce(sum(masse_kg) filter (where buch = 'verkauf'), 0) as verkauf_kg,
         coalesce(sum(masse_kg) filter (where buch = 'marge'), 0)   as marge_kg,
         coalesce(sum(masse_kg) filter (where buch = 'verlust'), 0) as entsorgt_kg,
         coalesce(sum(masse_fehler_kg), 0)                          as fehler_kg,
         count(*)::int                                             as n_lieferungen,
         max(datum)                                                as letzte_lieferung
    from v_lieferung_masse
), fax as (
  select coalesce(sum(masse_kg), 0) as kg, count(*)::int as n
    from v_fax_beobachtung where status = 'abgeschlossen' and masse_kg is not null
)
select c.heute,
       zahl(c.eingang_kg)::numeric(14,2)                       as eingang_kg,
       c.n_chargen,
       -- was den Betrieb verlassen hat (gemessen)
       zahl(a.kg + vl.kg)::numeric(14,2)                       as ausgang_kg,
       zahl(a.verkauf_kg)::numeric(14,2)                       as verkauf_kg,
       zahl(a.marge_kg)::numeric(14,2)                         as marge_kg,
       zahl(a.entsorgt_kg)::numeric(14,2)                      as entsorgt_kg,
       zahl(a.fehler_kg)::numeric(14,2)                        as ausgang_fehler_kg,
       a.n_lieferungen,
       a.letzte_lieferung,
       zahl(vl.kg)::numeric(14,2)                              as vorlauf_kg,
       zahl(c.geliefert_kg)::numeric(14,2)                     as geliefert_kg,
       zahl(c.ausgelagert_kg)::numeric(14,2)                   as ausgelagert_kg,
       -- der Verlust bis heute (gerechnet), mit Bereich
       zahl(c.verlust_heute_kg)::numeric(14,2)                 as verlust_heute_kg,
       zahl(b.verlust_unten_kg)::numeric(14,2)                 as verlust_unten_kg,
       zahl(b.verlust_oben_kg)::numeric(14,2)                  as verlust_oben_kg,
       zahl(c.verdunstung_heute_kg)::numeric(14,2)             as verdunstung_heute_kg,
       zahl(c.schimmel_heute_kg)::numeric(14,2)                as schimmel_heute_kg,
       zahl(c.sockel_heute_kg)::numeric(14,2)                  as sockel_heute_kg,
       zahl(c.fax_heute_kg)::numeric(14,2)                     as fax_heute_kg,
       zahl(c.fax_erwartet_kg)::numeric(14,2)                  as fax_erwartet_kg,
       -- kein echter Verlust: anderer Kanal
       zahl(c.kanal_heute_kg)::numeric(14,2)                   as kanal_heute_kg,
       zahl(b.kanal_unten_kg)::numeric(14,2)                   as kanal_unten_kg,
       zahl(b.kanal_oben_kg)::numeric(14,2)                    as kanal_oben_kg,
       -- was heute noch da ist
       zahl(c.im_haus_heute_kg)::numeric(14,2)                 as im_haus_heute_kg,
       zahl(c.verkaufsfaehig_heute_kg)::numeric(14,2)          as verkaufsfaehig_heute_kg,
       zahl(c.kanal_im_haus_kg)::numeric(14,2)                 as kanal_im_haus_kg,
       zahl(c.lager_kg)::numeric(14,2)                         as lager_kg,
       zahl(c.wartet_kg)::numeric(14,2)                        as wartet_kg,
       zahl(c.ueberzaehlung_kg)::numeric(14,2)                 as ueberzaehlung_kg,
       zahl(f.kg)::numeric(14,2)                               as fax_kg,
       f.n                                                     as n_fax,
       coalesce(c.bekannt, false)                              as verlust_bekannt,
       -- Eingang = geliefert + Verlust + Kanal (am Ausgelagerten) + im Haus;
       -- was übrig bleibt, ist die Überzählung (Lieferungen ohne Eingang)
       zahl(c.eingang_kg - c.geliefert_kg - c.verlust_heute_kg
            - (c.kanal_heute_kg - c.kanal_im_haus_kg) - c.im_haus_heute_kg)::numeric(14,2)
                                                               as luecke_kg,
       zahl(case when c.eingang_kg > 0
                 then (c.eingang_kg - c.geliefert_kg - c.verlust_heute_kg
                       - (c.kanal_heute_kg - c.kanal_im_haus_kg) - c.im_haus_heute_kg) / c.eingang_kg end,
            4, 1e5)::numeric(10,4)                             as luecke_anteil,
       zahl(case when c.eingang_kg > 0 then (a.kg + vl.kg) / c.eingang_kg end, 4, 1e5)::numeric(10,4)
                                                               as ausgang_deckung,
       case
         when coalesce(c.eingang_kg, 0) <= 0
           then 'Es ist kein Wareneingang erfasst. Ohne das Erntejournal gibt es '
                || 'nichts, worauf sich Verlust und Bestand beziehen könnten.'
         when coalesce(c.ueberzaehlung_kg, 0) > 0.05 * c.eingang_kg
           then format('Hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — '
                       || 'bei einigen Chargen rund %s kg zu viel. Fast immer fehlt der '
                       || 'Wareneingang dieser Chargen (Erntejournal unvollständig) oder eine '
                       || 'Lieferung ist der falschen Charge zugeordnet.',
                       round(c.ueberzaehlung_kg))
         when a.n_lieferungen = 0 and vl.kg = 0
           then 'Kein Warenausgang erfasst — dann liegt rechnerisch noch alles im Haus, '
                || 'und der Verlust bis heute gilt für die ganze Eingangsmasse. Sobald die '
                || 'Lieferscheine eingelesen sind, teilt sich die Ware in ausgeliefert und liegend.'
         when not coalesce(c.bekannt, false)
           then 'Ein Verluststrom ist noch nicht gemessen — die Ursachen sind erst '
                || 'vollständig, wenn jeder Koeffizient mindestens eine Messung hat.'
         else format('Bis heute (%s): %s t Eingang = %s t verkauft + %s t Verlust '
                     || '(Verdunstung %s t, Faules %s t, Fax %s t) + %s t anderer Kanal '
                     || '+ %s t noch im Haus (davon %s t verkaufsfähig). Die Prognose bis zum '
                     || 'Saisonende steht in der Grafik, nicht in diesen Zahlen.%s',
                     to_char(c.heute, 'DD.MM.YYYY'),
                     round(c.eingang_kg / 1000.0, 1),
                     round(c.geliefert_kg / 1000.0, 1),
                     round(c.verlust_heute_kg / 1000.0, 1),
                     round(c.verdunstung_heute_kg / 1000.0, 1),
                     round((c.schimmel_heute_kg + c.sockel_heute_kg) / 1000.0, 1),
                     round(c.fax_heute_kg / 1000.0, 1),
                     round((c.kanal_heute_kg - c.kanal_im_haus_kg) / 1000.0, 1),
                     round(c.im_haus_heute_kg / 1000.0, 1),
                     round(c.verkaufsfaehig_heute_kg / 1000.0, 1),
                     concat_ws(' ', '',
                       case when a.marge_kg > 0
                            then format('An die Tiere und in den Nebenkanal geliefert: %s kg, gerechnet: %s kg.',
                                        round(a.marge_kg), round(c.kanal_heute_kg - c.kanal_im_haus_kg)) end,
                       case when a.entsorgt_kg > 0
                            then format('Entsorgt: %s kg, gerechneter Schimmel: %s kg.',
                                        round(a.entsorgt_kg), round(c.schimmel_heute_kg)) end,
                       case when coalesce(c.ueberzaehlung_kg, 0) > 0
                            then format('%s kg Überzählung.', round(c.ueberzaehlung_kg)) end))
       end                                                     as befund
  from charge c cross join bereich b cross join ausgang a cross join vorlauf vl cross join fax f;
comment on view v_saisonbilanz is
  'Eingang = verkauft + Verlust bis heute + anderer Kanal + noch im Haus (0061). '
  'Alles bis heute(); nichts davon ist Prognose. luecke_kg ist die Überzählung '
  '(Lieferungen, hinter denen kein Eingang steht), sonst null.';
grant select on v_saisonbilanz to authenticated;

-- Kein echter Verlust: anderer Kanal (aus erg_verlust) und die verschenkte
-- Marge aus überfüllten Kisten — verkaufte Kisten aus der Verkaufsdatei,
-- Überschuss je Kiste aus den Wägungen, nur wo beides da ist.
create view v_marge_buch with (security_invoker = true) as
with verkauf as (
  select sum(verschenkt_kg)                                                   as verschenkt_kg,
         sum(case when verschenkt_kg is null then null
                  else greatest(verschenkt_kg - coalesce(verschenkt_fehler_kg, 0), 0) end) as verschenkt_unten_kg,
         sum(verschenkt_kg + coalesce(verschenkt_fehler_kg, 0))               as verschenkt_oben_kg,
         sum(kisten_verkauft) filter (where n_wiegungen > 0)                  as kisten_gerechnet,
         sum(kisten_verkauft) filter (where n_wiegungen = 0)                  as kisten_ungewogen,
         sum(n_wiegungen)                                                     as n_wiegungen,
         sum(kisten_gewogen)                                                  as kisten_gewogen,
         sum(zuviel_je_kiste * kisten_gewogen) / nullif(sum(kisten_gewogen) filter (where zuviel_je_kiste is not null), 0)
                                                                              as zuviel_je_kiste,
         count(*) filter (where n_lieferungen > 0)::int                       as n_gruppen_verkauft
    from erg_ueberfuellung
   where gruppe = 'sorte' and kistensystem = 'kiste_ab'
), datei as (
  select count(*)::int as n from lieferung_import
)
select r.strom as posten, r.kg, r.kg_unten, r.kg_oben,
       case r.strom
         when 'Nebenkanal zu gross' then 'Ware über der oberen Kalibergrenze geht in einen anderen Verkaufskanal — nicht weg, nur nicht zum besten Preis'
         when 'Zu klein (Tierfutter)' then 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'
         else '' end::text                                       as erlaeuterung,
       (r.kg is not null)                                        as gemessen
  from erg_verlust r where r.gruppe = 'gesamt' and r.buch = 'marge'
union all
select 'Überfüllung der Kisten',
       zahl(v.verschenkt_kg)::numeric(14,2),
       zahl(v.verschenkt_unten_kg)::numeric(14,2),
       zahl(v.verschenkt_oben_kg)::numeric(14,2),
       case
         when d.n = 0
           then 'Keine Verkaufsdatei eingelesen — wie viele Kisten „ab x kg" verkauft wurden, weiss die App nicht. Nichts gerechnet.'
         when coalesce(v.n_wiegungen, 0) = 0
           then format('%s Kisten „ab x kg" laut Verkaufsdatei verkauft, aber keine fertige Palette dieses Systems gewogen — nichts gerechnet.',
                       round(coalesce(v.kisten_ungewogen, 0)))
         else format('%s gewogene Paletten (%s Kisten): im Schnitt %s kg je Kiste über dem Soll. '
                     || 'Verkauft laut Verkaufsdatei: %s Kisten desselben Systems — daraus die Zahl. '
                     || '%s',
                     v.n_wiegungen, round(coalesce(v.kisten_gewogen, 0)), round(coalesce(v.zuviel_je_kiste, 0), 3),
                     round(coalesce(v.kisten_gerechnet, 0)),
                     case when coalesce(v.kisten_ungewogen, 0) > 0
                          then format('Weitere %s verkaufte Kisten haben kein gewogenes Gegenstück (Sorte oder Soll ohne Wägung) und sind nicht gerechnet.',
                                      round(v.kisten_ungewogen))
                          else 'Kisten nach Stück haben kein Sollgewicht und damit keine Überfüllung.' end)
       end,
       (v.verschenkt_kg is not null)
  from verkauf v cross join datei d;
comment on view v_marge_buch is
  'Kein echter Verlust: Ware, die den Betrieb über einen anderen Kanal verlässt, '
  'und die verschenkte Marge aus überfüllten Kisten — verkaufte Kisten aus der '
  'Verkaufsdatei mal gewogenem Überschuss je Kiste; ohne Datei oder Wägung NULL (0061).';
grant select on v_marge_buch to authenticated;

-- Ersetzt: die Überfüllung je Käufer (der Käufer ist weg) und der alte
-- Saisonverlauf ohne Verlust (erg_verlauf hat alle drei Linien).
drop view if exists v_ueberfuellung_kaeufer cascade;
drop view if exists v_saisonverlauf cascade;

-- ---------- 7a. Auffälligkeit: Wasch-Paletten ohne Kistengewicht ----------
-- Bis 0060 hing der Befund „Kistengewicht unbekannt" an den gezählten Kisten
-- (auftrag_gebinde). Beim Waschen werden seit 0061 Paletten gezählt — ohne
-- diesen Zusatz hätte eine Wasch-Arbeit ohne bekanntes Kistengewicht gar
-- keine Masse und niemand erführe warum. Der Zusatz heisst weiter nach 0054,
-- weil v_plausibilitaet ihn unter diesem Namen einbindet; er trägt jetzt
-- beide Fälle.
create or replace view v_plausibilitaet_0054_zusatz with (security_invoker = true) as
select 'Kistengewicht'::text as art, g.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber ein Band mit diesen '
              || 'Grenzen wurde beim Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt',
              g.anzahl, a.kaliber_von_g, a.kaliber_bis_g)                         as befund,
       'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '
       || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'       as rat
  from v_auftrag_gebinde_masse g
  join auftrag a on a.id = g.auftrag_id
  join charge c on c.nr = a.charge_nr
 where g.kg is null and g.anzahl > 0 and g.kaliber_idx = -2
union all
select 'Kistengewicht', wp.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '
              || 'die Menge dieser Arbeit damit auch',
              wp.n_paletten, wp.kisten,
              case when a.kaliber_von_g is not null
                   then format('ein Band %s–%s g wurde beim Sortieren noch nie mitgezählt',
                               a.kaliber_von_g, a.kaliber_bis_g)
                   else 'für dieses Kaliber wurde beim Sortieren noch nie mitgezählt' end),
       case when a.kaliber_von_g is not null
            then 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '
                 || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'
            else 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '
                 || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.' end
  from v_auftrag_wasch_paletten wp
  join auftrag a on a.id = wp.auftrag_id
  join charge c on c.nr = a.charge_nr
 where wp.kg is null and wp.kisten > 0;
grant select on v_plausibilitaet_0054_zusatz to authenticated;

-- ---------- 7b. Datenqualität: Waschen zählt Paletten ----------------------
-- Die Spalten von 0060 ohne lagerkontrollen_zufaellig (die Kontrolle fragt
-- nicht mehr, wie gegriffen wurde — jede zählt gleich); die Wasch-Zähler sehen
-- die gezählten Paletten (Kisten je Palette mit Sortierdatum). Eine Spalte
-- weniger heisst: neu anlegen, nicht ersetzen (erg_datenqualitaet folgt unten).
drop view if exists v_datenqualitaet cascade;
create view v_datenqualitaet with (security_invoker = true) as
with arbeiten as (select a.* from auftrag a where a.abgebrochen_ts is null),
     fertig as (select * from arbeiten where status = 'abgeschlossen')
select
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id)::int as paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where ap.eingangsdatum is not null)::int                                             as paletten_mit_datum,
  (select count(*) from fertig where not ist_fax)::int                                    as arbeiten_fertig,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null))::int                     as arbeiten_mit_ablesung,
  (select count(*) from fertig f where not f.ist_fax and (select count(*) from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null) >= 2)::int                as arbeiten_mit_zwei_ablesungen,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from auftrag_angabe g
    where g.auftrag_id = f.id and g.schluessel = 'eine_charge'))::int                     as arbeiten_mit_antwort,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen)::int                                                                as ausschuss_messungen,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen and m.brutto_kg is not null)::int                                    as ausschuss_gewogen,
  -- 0061: die Lagerkontrolle ist eine Verdunstungsmessung — gezählt wird jede
  -- gemessene Kontrolle, nicht nur die mit Faul-Angabe
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.gemessen)::int                                       as lagerkontrollen,
  (select count(*) from sortier_lauf)::int                                                as sortierlaeufe,
  (select count(*) from sortier_lauf where auftrag_id is not null)::int                   as sortierlaeufe_zugeordnet,
  (select count(*) from fertig f where f.station = 'sortieren')::int                      as sortier_arbeiten,
  (select count(*) from fertig f where f.station = 'sortieren' and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as sortier_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax)::int      as wasch_arbeiten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax
    and (f.kaliber_idx is not null or f.kaliber_von_g is not null)
    and (exists (select 1 from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)
         or exists (select 1 from auftrag_palette p where p.auftrag_id = f.id and p.kisten > 0)))::int
                                                                                          as wasch_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax)::int                                    as fax_arbeiten,
  (select count(*) from fertig f where f.ist_fax and (f.paletten_gesamt > 0 or exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0)))::int             as fax_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from schimmel_messung s where s.auftrag_id = f.id and s.gemessen))::int               as fax_arbeiten_mit_faulem,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren')::int                                           as ws_paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where a.station = 'waschen_sortieren' and ap.brutto_zettel_kg is not null)::int       as ws_paletten_mit_zettelgewicht,
  (select count(*) from fertig f where f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))::int
                                                                                          as arbeiten_nach_waschen,
  (select count(*) from fertig f where (f.ist_fax or f.station in ('waschen', 'waschen_sortieren'))
    and f.kistensystem is not null)::int                                                  as arbeiten_mit_kistensystem,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax)
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax))::int                               as wasch_kisten_gezaehlt,
  ((select coalesce(sum(g.anzahl), 0) from auftrag_gebinde g join arbeiten a on a.id = g.auftrag_id
     where a.station = 'waschen' and not a.ist_fax and (g.sortierdatum is not null or g.datum_fehlt))
   + (select coalesce(sum(p.kisten), 0) from auftrag_palette p join arbeiten a on a.id = p.auftrag_id
       where a.station = 'waschen' and not a.ist_fax and p.sortierdatum is not null))::int
                                                                                          as wasch_kisten_mit_sortierdatum,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from v_palox_stand p
    where p.auftrag_id = f.id and p.differenz is null))::int                              as arbeiten_mit_palox_unbekannt;
comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Seit 0061 zählen beim Waschen die '
  'gezählten Paletten (Kisten mit Sortierdatum) mit; die Lagerkontrolle zählt '
  'als Verdunstungsmessung, ohne Faul-Angabe.';

-- ---------- 8. Alles, was die App liest, ist gespeichert -------------------
-- Auf Supabase liefen sieben live gerechnete Sichten ins Zeitlimit — jede für
-- sich schnell, zusammen beim Laden zu viel, und ohne Statistik (materialized
-- views bekommen nie welche, wenn niemand ANALYZE sagt) mit schlechten Plänen.
-- Ab jetzt: jede Sicht, die die Auswertung lädt, hat ein gespeichertes
-- Gegenstück erg_*. Die v_*-Sichten bleiben — für Tests, den SQL-Editor und
-- als Definition. Die Auswertung des Betriebsleiters liest nur erg_*; die
-- Arbeiter-Masken lesen weiter ihre v_*-Sichten (Palox-Stand, Auftragsmasse,
-- Kontrollvorschläge), die je Arbeit ein paar Zeilen liefern.
do $$
declare
  paar text[];
  paare text[][] := array[
    -- [erg-Name, Quelle]
    ['erg_gewichte',           'v_gewichtsverteilung'],
    ['erg_kaliber',            'v_kaliber_verteilung'],
    ['erg_gebinde',            'v_koeff_gebinde'],
    ['erg_ausgang',            'v_ausgang_kennzahl'],
    ['erg_lieferung',          'v_lieferung_masse'],
    ['erg_kohorte',            'v_charge_kohorte'],
    ['erg_punkte',             'v_schimmel_punkte'],
    ['erg_modell',             'v_schimmel_modell'],
    ['erg_kurve',              'v_schimmel_kurve_anzeige'],
    ['erg_selektion',          'v_selektionsverdacht'],
    ['erg_koeff_verdunstung',  'v_koeff_verdunstung'],
    ['erg_koeff_ausschuss',    'v_koeff_ausschuss'],
    ['erg_koeff_nebenkanal',   'v_koeff_nebenkanal'],
    ['erg_koeff_ueberfuellung','v_koeff_ueberfuellung'],
    ['erg_wiegung',            'v_wiegung_kennzahl'],
    ['erg_fax',                'v_fax_beobachtung'],
    ['erg_ausschuss',          'v_ausschuss_beobachtung'],
    ['erg_verarbeitung_alter', 'v_verarbeitung_alter'],
    ['erg_durchsatz',          'v_durchsatz'],
    ['erg_bilanz',             'v_saisonbilanz'],
    ['erg_marge',              'v_marge_buch'],
    ['erg_massenbilanz',       'v_massenbilanz'],
    ['erg_naechste_charge',    'v_naechste_charge'],
    ['erg_datenlage',          'v_datenlage'],
    ['erg_plausibilitaet',     'v_plausibilitaet'],
    ['erg_datenqualitaet',     'v_datenqualitaet']
  ];
begin
  foreach paar slice 1 in array paare loop
    execute format('drop materialized view if exists %I cascade', paar[1]);
    execute format('create materialized view %I as select * from %I with no data', paar[1], paar[2]);
    execute format('grant select on %I to authenticated', paar[1]);
    execute format('comment on materialized view %I is %L', paar[1],
                   format('%s, gespeichert für die App (0061). Erneuert mit auswertung_schritt().', paar[2]));
  end loop;
end $$;
-- Indizes, wo die App filtert oder sortiert
create index if not exists erg_gewichte_sorte     on erg_gewichte (sorte);
create index if not exists erg_ausgang_ts         on erg_ausgang (ts);
create index if not exists erg_lieferung_datum    on erg_lieferung (datum);
create index if not exists erg_kohorte_charge     on erg_kohorte (charge_nr, eingangsdatum);
create index if not exists erg_punkte_charge      on erg_punkte (charge_nr);
create index if not exists erg_wiegung_ts         on erg_wiegung (wiege_ts);
create index if not exists erg_fax_start          on erg_fax (start_ts);
create index if not exists erg_durchsatz_start    on erg_durchsatz (start_ts);
create index if not exists erg_verarbeitung_tag   on erg_verarbeitung_alter (tag);
create index if not exists erg_verlauf_woche      on erg_verlauf (woche);

-- Die Neuberechnung in fünf Schritten. Jeder Schritt ist ein eigener Aufruf
-- der App — kurz genug für das Zeitlimit einer Verbindung — und analysiert,
-- was er erneuert hat, damit der nächste Schritt gute Pläne bekommt.
--   1  Rohdaten:  CSV-Sichten, Gewichte, Kaliber, Kisten, Lieferungen, Eingangstage
--   2  Arbeiten:  Masse je Arbeit, Verderbspunkte und -modell, Koeffizienten
--   3  Kaskade:   je Charge und Eingangstag bis heute; die Charge (erg_charge)
--   4  Ergebnis:  Ströme je Gruppe, Verlauf mit Prognose, Überfüllung, Bilanz, Marge
--   5  Befunde:   Plausibilität, Datenqualität; der Stand
create or replace function auswertung_schritt(p_schritt int)
returns jsonb language plpgsql security definer
set search_path = public set jit = off as $$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
begin
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'mv_schimmel_punkte', 'mv_schimmel_modell',
                       'erg_punkte', 'erg_modell', 'erg_kurve', 'erg_selektion',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_ueberfuellung', 'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_verlauf', 'erg_bilanz', 'erg_marge',
                       'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  -- Schritt 1 bringt zuerst die Statistik der Rohtabellen auf Stand. Nach
  -- einem grossen Import (Saisonstart, Warenausgang, Demo) schätzt der Planer
  -- sonst mit Zahlen von vorher und wählt Pläne, die um Grössenordnungen
  -- danebenliegen: gemessen 33 Sekunden für Schritt 2, wo er mit frischer
  -- Statistik 1.1 braucht. Das Analysieren aller Rohtabellen kostet auf der
  -- Demo 0.2 Sekunden — der beste Handel im ganzen Rechenwerk.
  if p_schritt = 1 then
    for v_name in
      select c.relname
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r'
       order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
  end if;

  foreach v_name in array v_namen loop
    execute format('refresh materialized view %I', v_name);
    execute format('analyze %I', v_name);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),   -- nicht now(): das wäre der Beginn der Transaktion
           dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif p_schritt = 1 then
    update auswertung_stand
       set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  else
    update auswertung_stand
       set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5);
end $$;
comment on function auswertung_schritt(int) is
  'Ein Schritt der Neuberechnung (1 Rohdaten, 2 Arbeiten, 3 Kaskade, 4 Ergebnis, '
  '5 Befunde). Die App ruft die fünf nacheinander; jeder erneuert und analysiert '
  'seine gespeicherten Sichten. Schritt 5 setzt den Stand (0061).';
revoke all on function auswertung_schritt(int) from public;
grant execute on function auswertung_schritt(int) to authenticated;

-- Alles in einem Aufruf — für Tests, den SQL-Editor und den Zeitplan.
create or replace function auswertung_aktualisieren()
returns timestamptz language plpgsql security definer
set search_path = public set jit = off as $$
declare i int;
begin
  for i in 1..5 loop
    perform auswertung_schritt(i);
  end loop;
  return now();
end $$;
comment on function auswertung_aktualisieren() is
  'Die fünf Schritte der Neuberechnung nacheinander (0061). Die App ruft sie '
  'einzeln (auswertung_schritt), damit keiner ins Zeitlimit läuft.';

-- Nur rechnen, wenn sich etwas geändert hat (auswertung_veraltet setzt geaendert_ts).
create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand;
begin
  select * into v_stand from auswertung_stand where id = 1;
  if v_stand.berechnet_ts is not null and v_stand.geaendert_ts <= v_stand.berechnet_ts then
    return false;
  end if;
  perform auswertung_aktualisieren();
  return true;
end $$;
comment on function auswertung_wenn_veraltet() is
  'Rechnet neu, wenn seit der letzten Berechnung etwas geschrieben wurde — sonst '
  'nichts. Für einen Zeitplan (pg_cron), damit die App fertige Zahlen vorfindet (0061).';
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

-- Wo pg_cron da ist (Supabase), rechnet die Datenbank alle zehn Minuten nach,
-- wenn etwas veraltet ist. Wo nicht, bleibt es beim Rechnen aus der App.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'auswertung_wenn_veraltet';
    perform cron.schedule('auswertung_wenn_veraltet', '*/10 * * * *',
                          'select public.auswertung_wenn_veraltet()');
    raise notice 'Zeitplan: auswertung_wenn_veraltet() alle zehn Minuten (pg_cron).';
  else
    raise notice 'pg_cron fehlt — die App rechnet selbst nach, wenn etwas veraltet ist.';
  end if;
exception when others then
  raise notice 'Zeitplan nicht angelegt (%): die App rechnet selbst nach.', sqlerrm;
end $$;

-- ---------- 9. Stand der Datenbank ----------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 61 $$;
