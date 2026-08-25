-- =====================================================================
-- 0015 — Tempo: die Auswertung lief in Supabases Zeitlimit
--
-- Symptom: „canceling statement due to statement timeout" beim Öffnen der
-- Auswertung. Gemessen an der Demo-Saison (535 Paletten, 22 Arbeiten):
--   v_hochrechnung   2 553 ms
--   v_verlust_ranking 2 441 ms
--   v_marge_buch     3 895 ms
-- Das Dashboard holt ein Dutzend Ansichten gleichzeitig — auf der geteilten
-- Gratis-CPU reicht das für die 8-Sekunden-Grenze.
--
-- Zwei Ursachen, beide dieselbe Sorte Fehler: etwas Teures wird pro Zeile
-- statt einmal gerechnet.
--
--   1. schimmelanteil() ist eine Funktion, die intern die ganze Kette
--      v_schimmel_kurve → v_schimmel_beobachtung → v_auftrag_masse abfragt.
--      In v_kaskade stand sie in der Select-Liste — also 60 Aufrufe à 16 ms,
--      jeder mit der vollständigen Kette dahinter. Jetzt wird die Kurve einmal
--      in eine materialisierte CTE gelegt und angejoint.
--
--   2. v_auftrag_palette_masse holte das Chargen- und Datumsmittel über
--      seitliche Unterabfragen — für jede der 286 gezählten Paletten neu,
--      inklusive einer Aggregation über alle 535 Eingangspaletten. Jetzt
--      werden diese Mittel einmal gebildet und normal angejoint.
--
-- Ergebnis identisch, nur schneller: Die Prüfabfragen rechnen dieselben Zahlen.
-- =====================================================================

-- ---------- 1. Masse hinter einer gezählten Palette -----------------------
create or replace view v_auftrag_palette_masse with (security_invoker = true) as
with wiegung as materialized (
  -- Eingangs-Netto der gewogenen Paletten, einmal für alle
  select vw.id,
         (vw.brutto_damals_kg
          - coalesce(vw.kisten, 0) * g.tara_kg_pro_kiste
          - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_damals_kg,
         vw.eingangsdatum
    from verdunstung_wiegung vw
    left join gebinde g on g.art = vw.gebindeart
), datum_mittel as materialized (
  select charge_nr, eingangsdatum, avg(netto_kg) as netto_mittel
    from v_palette group by charge_nr, eingangsdatum
), charge_mittel as materialized (
  select charge_nr, avg(netto_kg) as netto_mittel
    from v_palette group by charge_nr
), charge_datum as materialized (
  select charge_nr, eingangsdatum_mittel from v_charge_rueckgrat
)
select ap.id, ap.auftrag_id, a.charge_nr, a.start_ts,
       coalesce(w.netto_damals_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) as netto_kg,
       coalesce(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum,
                cd.eingangsdatum_mittel)                                        as eingangsdatum,
       case when w.netto_damals_kg is not null then 'gewogen'
            when p.netto_kg        is not null then 'palette'
            when d.netto_mittel    is not null then 'datum-mittel'
            when cm.netto_mittel   is not null then 'charge-mittel'
            else 'unbekannt' end                                                as masse_quelle
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  left join wiegung w  on w.id = ap.wiegung_id
  left join v_palette p on p.id = ap.palette_id
  left join datum_mittel d on d.charge_nr = a.charge_nr and d.eingangsdatum = ap.eingangsdatum
  left join charge_mittel cm on cm.charge_nr = a.charge_nr
  left join charge_datum cd on cd.charge_nr = a.charge_nr;

-- ---------- 2. Die Kaskade ohne Funktionsaufruf je Zeile ------------------
drop view if exists v_marge_buch;
drop view if exists v_verlust_ranking;
drop view if exists v_massenbilanz;
drop view if exists v_hochrechnung;
drop view if exists v_kaskade;

create view v_kaskade with (security_invoker = true) as
with sz(szenario) as (values ('unten'), ('mittel'), ('oben')),
kurve as materialized (
  -- Einmal berechnet statt einmal je Zeile — das war der teure Teil
  select von, anteil_mono, unten, oben, n from v_schimmel_kurve where n > 0
),
koeff as (
  select b.*, sz.szenario,
         least(greatest(case sz.szenario when 'unten' then kv.unten
                                         when 'oben'  then kv.oben
                                         else kv.mittel end, 0), 0.05) as r,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(case sz.szenario when 'unten' then ka.unten
                                         when 'oben'  then ka.oben
                                         else ka.mittel end, 0), 1) as a_klein,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(case sz.szenario when 'unten' then kn.unten
                                         when 'oben'  then kn.oben
                                         else kn.mittel end, 0), 1) as a_gross,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    cross join sz
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  select k.*, t.portion, t.m0, t.alter_tage,
         -- Treppenfunktion: die höchste Altersklasse, die nicht über dem Alter
         -- liegt. Der Join geht gegen die kleine CTE, nicht gegen die Kette.
         least(greatest(coalesce(
           case k.szenario when 'unten' then coalesce(s.unten, s.anteil_mono)
                           when 'oben'  then coalesce(s.oben,  s.anteil_mono)
                           else s.anteil_mono end, 0), 0), 1)          as f,
         s.n                                                           as f_n
    from koeff_norm k
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
    left join lateral (
        select c.anteil_mono, c.unten, c.oben, c.n from kurve c
         where c.von <= t.alter_tage order by c.von desc limit 1
       ) s on true
   where t.m0 > 0
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))::numeric              as m1,
         (t.m0 * power(1 - t.r, t.alter_tage) * (1 - t.f))::numeric  as m2
    from teile t
)
select k.*,
       k.m0 - k.m1                                    as verdunstung_kg,
       k.m1 - k.m2                                    as schimmel_kg,
       k.m2 * k.a_klein_n                             as klein_kg,
       k.m2 * k.a_gross_n                             as nebenkanal_kg,
       k.m2 * (1 - k.a_klein_n - k.a_gross_n)         as verkaufsfaehig_kg
  from kaskade k;

create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.szenario, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg,
       s.strom, s.buch,
       s.kg::numeric(14,2)          as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       s.koeffizient::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung',      'verlust', k.verdunstung_kg, k.m0, k.r,       k.r_n,     k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'),
    ('Schimmel/Fäulnis', 'verlust', k.schimmel_kg,    k.m1, k.f,       k.f_n,
     'Schimmelkurve nach Lagerdauer',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer'),
    ('Ausschuss zu klein','verlust', k.klein_kg,      k.m2, k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze'),
    ('Nebenkanal zu gross','marge',  k.nebenkanal_kg, k.m2, k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'),
    ('Verkaufsfähig',    'bilanz',  k.verkaufsfaehig_kg, k.m2, null::numeric, null::int, null::text,
     'Rest der Kaskade')
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel);

create view v_verlust_ranking with (security_invoker = true) as
select strom, buch,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       sum(kg) filter (where szenario = 'mittel' and portion = 'ausgelagert') as kg_beobachtet,
       sum(kg) filter (where szenario = 'mittel' and portion = 'lager')       as kg_projiziert,
       min(koeff_n)                                                          as koeff_n_min
  from v_hochrechnung
 where buch = 'verlust'
 group by strom, buch
 order by 3 desc nulls last;

-- v_marge_buch fragte v_hochrechnung zweimal ab — einmal direkt und einmal in
-- einer seitlichen Unterabfrage. Jetzt einmal, in einer materialisierten CTE.
create view v_marge_buch with (security_invoker = true) as
with hr as materialized (
  select charge_nr, strom, buch, szenario, kg from v_hochrechnung
), kisten as materialized (
  select sum(h.kg * b.weg2_anteil) / 8.0 as anzahl
    from hr h
    join v_hochrechnung_basis b on b.charge_nr = h.charge_nr
   where h.strom = 'Verkaufsfähig' and h.szenario = 'mittel'
)
select 'Nebenkanal zu gross'::text as posten,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from hr where buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;

create view v_massenbilanz with (security_invoker = true) as
with modell as materialized (
  select charge_nr,
         sum(m2) filter (where portion = 'ausgelagert') as modell_kg,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade where szenario = 'mittel' group by charge_nr
), csv_anteil as materialized (
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
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       (m.modell_kg * q.anteil_mit_csv)::numeric(14,2)      as modell_am_band_kg,
       c.gemessen_kg                                        as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)::numeric(14,2) as abweichung_kg,
       case when m.modell_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)
                  / (m.modell_kg * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       m.restbestand_kg::numeric(14,2)                      as restbestand_kg
  from v_hochrechnung_basis b
  left join modell m     on m.charge_nr = b.charge_nr
  left join csv_anteil q on q.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

-- ---------- Indizes für die Auswertungspfade ------------------------------
create index if not exists palette_charge_netto on palette (charge_nr, eingangsdatum, gebindeart);
create index if not exists schimmel_auftrag on schimmel_messung (auftrag_id) where gemessen;
create index if not exists ausschuss_auftrag on ausschuss_messung (auftrag_id, art) where gemessen;
create index if not exists verdunstung_auftrag on verdunstung_wiegung (auftrag_id) where gemessen;
create index if not exists sortier_lauf_auftrag on sortier_lauf (auftrag_id) where auftrag_id is not null;
