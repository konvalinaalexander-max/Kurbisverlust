-- =====================================================================
-- Simulations-Harness, Teil 2: eine Saison erzeugen
--
-- Aufruf:  psql … -v lauf=1 -v selektion=0 -v n_wiegungen=12 -f saison.sql
--
-- Erzeugt die wahre Welt (sim.palette_wahr), leitet daraus ab, was ein
-- Arbeiter erfasst hätte, und hält die wahren Saisonsummen fest.
-- =====================================================================

-- Ohne angemeldeten Benutzer sind die Erfasser-Spalten NULL und NOT NULL
-- schlägt zu. Für den Testlauf einen beliebigen Benutzer vorgeben.
do $$
declare v_wer uuid;
begin
  select id into v_wer from profil order by erstellt_ts limit 1;
  perform set_config('request.jwt.claim.sub', v_wer::text, false);
  perform set_config('request.jwt.claims', json_build_object('sub', v_wer)::text, false);
end $$;

select setseed(0.1 + (:lauf % 97) / 200.0);

-- ---------- aufräumen -----------------------------------------------------
delete from verdunstung_wiegung where auftrag_id in (select id from auftrag where bemerkung = 'SIM');
-- Lagerkontrollen hängen an keinem Auftrag und würden sich sonst über die
-- Läufe hinweg anhäufen.
delete from verdunstung_wiegung where bemerkung = 'SIM-LAGER';
delete from ausgang_wiegung      where auftrag_id in (select id from auftrag where bemerkung = 'SIM');
delete from sortier_gewicht where lauf_id in (select id from sortier_lauf where datei_name like 'SIM-%');
delete from sortier_lauf where datei_name like 'SIM-%';
delete from auftrag where bemerkung = 'SIM';
delete from palette where extern_id like 'sim-%';
delete from sim.auftrag_wahr where lauf = :lauf;
delete from sim.palette_wahr where lauf = :lauf;
delete from sim.wahrheit     where lauf = :lauf;
delete from sim.schaetzung   where lauf = :lauf;

insert into sim.parameter (lauf, r_basis, schimmel_lambda, schimmel_k,
                           anteil_klein, anteil_gross, selektion, n_wiegungen,
                           n_lagerkontrollen)
-- λ so gewählt, dass nach 200 Lagertagen rund 5 % verdorben sind —
-- die Grössenordnung, um die es auf dem Betrieb geht.
values (:lauf, 0.00060, 0.0000107, 1.6, 0.030, 0.015, :selektion, :n_wiegungen,
        :n_lagerkontrollen)
on conflict (lauf) do update set
  r_basis = excluded.r_basis, schimmel_lambda = excluded.schimmel_lambda,
  schimmel_k = excluded.schimmel_k, anteil_klein = excluded.anteil_klein,
  anteil_gross = excluded.anteil_gross, selektion = excluded.selektion,
  n_wiegungen = excluded.n_wiegungen,
  n_lagerkontrollen = excluded.n_lagerkontrollen;

-- ---------- Wareneingang ---------------------------------------------------
-- 12 Chargen, je 40–80 Paletten, gestaffelt über sechs Wochen eingelagert.
with gewaehlt as (
  -- row_number() liefert bigint; date + bigint gibt es nicht
  select nr, sorte, (row_number() over (order by nr))::int as i
    from charge order by nr limit 12
), erzeugt as (
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
  select g.nr,
         date '2026-09-01' + ((g.i - 1) * 3) + (random() * 20)::int,
         900 + (random() * 90)::numeric(8,2),
         38,
         'G2',
         format('sim-%s-%s-%s', :lauf, g.nr, p)
    from gewaehlt g
    cross join generate_series(1, 40 + (g.i * 4)) p
  returning id, charge_nr, eingangsdatum, brutto_kg
)
insert into sim.palette_wahr (lauf, palette_id, charge_nr, sorte, eingangsdatum,
       netto_eingang_kg, r_wahr, weg, anfaelligkeit)
select :lauf, e.id, e.charge_nr, c.sorte, e.eingangsdatum,
       e.brutto_kg - 38 * 1.5 - 25,
       -- Wahre Verdunstung: je Sorte etwas anders, dazu Streuung je Palette
       (select r_basis from sim.parameter where lauf = :lauf)
         * (0.7 + (e.charge_nr % 7) * 0.1) * (0.85 + random() * 0.3),
       -- Rund die Hälfte der Chargen läuft über die Maschine. Weg 1 hat zwei
       -- Lagerabschnitte: sortieren, dann liegt die Ware in Kaliber-Kisten,
       -- Wochen später waschen. Weg 2 geht in einem Schritt raus.
       case when e.charge_nr % 2 = 1 then 'maschine' else 'hand' end,
       -- Schimmelneigung: die meisten Paletten normal, einige deutlich anfälliger
       case when random() < 0.15 then 1.8 + random() else 0.6 + random() * 0.7 end
  from erzeugt e join charge c on c.nr = e.charge_nr;

-- ---------- Wer wird wann verarbeitet? ------------------------------------
-- Das ist der springende Punkt für die Selektionsverzerrung: Bei selektion = 1
-- kommen anfällige Paletten früher dran, weil sie schlechter aussehen. Bei
-- selektion = 0 entscheidet der Zufall.
update sim.palette_wahr w
   set verarbeitet_am = case
         when r.rang <= r.gesamt * (1 - :anteil_lager)
         -- Verarbeitungsalter über die ganze Saison streuen, nicht nur über die
         -- ersten Wochen: sonst hat das Modell per Konstruktion keine Daten für
         -- lange Lagerdauern und der Test misst nur meinen Generator.
         then w.eingangsdatum + (25 + (r.rang * 175.0 / r.gesamt))::int
         else null end
  from (
    select palette_id,
           row_number() over (
             partition by charge_nr
             order by case when (select selektion from sim.parameter where lauf = :lauf) > 0
                           then -anfaelligkeit else random() end,
                      random()) as rang,
           count(*) over (partition by charge_nr) as gesamt
      from sim.palette_wahr where lauf = :lauf
  ) r
 where w.lauf = :lauf and w.palette_id = r.palette_id;

-- ---------- Weg 1: der zweite Abschnitt -----------------------------------
-- Sortierte Ware liegt 30 bis 90 Tage in Kaliber-Kisten, bevor sie gewaschen
-- wird. Sie verdunstet und verdirbt in dieser Zeit weiter — genau das hat das
-- Modell vor 0024 nicht gesehen. Was bis zum Stichtag nicht gewaschen ist,
-- steht am Stichtag noch da.
update sim.palette_wahr w
   set gewaschen_am = case
         when w.eingangsdatum is null then null
         when (w.verarbeitet_am + (30 + random() * 60)::int) <= date '2027-03-31'
           then w.verarbeitet_am + (30 + random() * 60)::int
         else null end
 where w.lauf = :lauf and w.weg = 'maschine' and w.verarbeitet_am is not null;

-- ---------- Die wahren Saisonsummen ---------------------------------------
-- Stichtag: 31.03.2027, wie in den Einstellungen.
with stand as (
  select w.*,
         -- Das Alter läuft bis zum *letzten* Schritt. Auf Weg 1 ist das das
         -- Waschen, nicht das Sortieren; was noch wartet, altert bis zum
         -- Stichtag weiter.
         case when w.weg = 'maschine'
              then coalesce(w.gewaschen_am, date '2027-03-31')
              else coalesce(w.verarbeitet_am, date '2027-03-31') end
           - w.eingangsdatum                                          as tage,
         p.schimmel_lambda, p.schimmel_k, p.anteil_klein, p.anteil_gross
    from sim.palette_wahr w
    cross join sim.parameter p
   where w.lauf = :lauf and p.lauf = :lauf
), kaskade as (
  select s.*,
         s.netto_eingang_kg * power(1 - s.r_wahr, s.tage)              as m1,
         sim.schimmel_wahr(s.tage, s.schimmel_lambda, s.schimmel_k,
                           s.anfaelligkeit)                            as f
    from stand s
)
insert into sim.wahrheit (lauf, groesse, wert)
select :lauf, g.groesse, g.wert from (
  select 'Eingang' as groesse, sum(netto_eingang_kg) as wert from kaskade
  union all select 'Verdunstung', sum(netto_eingang_kg - m1) from kaskade
  union all select 'Schimmel/Fäulnis', sum(m1 * f) from kaskade
  union all select 'Ausschuss zu klein', sum(m1 * (1 - f) * anteil_klein) from kaskade
  union all select 'Nebenkanal zu gross', sum(m1 * (1 - f) * anteil_gross) from kaskade
  union all select 'r_wahr_mittel',
            sum(r_wahr * netto_eingang_kg) / sum(netto_eingang_kg) from kaskade
) g;
