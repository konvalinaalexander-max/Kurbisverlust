-- =====================================================================
-- Simulations-Harness, Teil 3: was der Arbeiter davon erfasst
--
-- Hier wird aus der wahren Welt das, was das Modell tatsächlich zu sehen
-- bekommt. Genau an dieser Verengung entstehen die Fehler, die wir messen
-- wollen: Nur ein Bruchteil der Paletten wird gewogen, Schimmel wird je
-- Arbeit als Summe erfasst, und die Sortier-CSV kennt nur die gesunde Ware.
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

-- ---------- Arbeiten: Paletten desselben Tages und derselben Charge --------
with gruppen as (
  select charge_nr, verarbeitet_am, w.weg,
         count(*) as n_paletten,
         sum(netto_eingang_kg) as netto_eingang,
         sum(netto_eingang_kg * power(1 - r_wahr, verarbeitet_am - eingangsdatum)) as m1,
         sum(netto_eingang_kg * power(1 - r_wahr, verarbeitet_am - eingangsdatum)
             * sim.schimmel_wahr(verarbeitet_am - eingangsdatum, p.schimmel_lambda,
                                 p.schimmel_k, w.anfaelligkeit)) as schimmel
    from sim.palette_wahr w cross join sim.parameter p
   where w.lauf = :lauf and p.lauf = :lauf and w.verarbeitet_am is not null
   group by charge_nr, verarbeitet_am, w.weg
), neu as (
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
  select g.weg::verarbeitungsweg,
         case when g.weg = 'hand' then 'waschen_sortieren' else 'sortieren' end::station,
         g.charge_nr, g.verarbeitet_am::timestamptz + interval '8 hours',
         g.verarbeitet_am::timestamptz + interval '15 hours', 'abgeschlossen', 'SIM'
    from gruppen g
  returning id, charge_nr, start_ts, weg, station
)
insert into sim.auftrag_wahr (lauf, auftrag_id, charge_nr, verarbeitet_am,
       n_paletten, netto_eingang, m1, schimmel)
select :lauf, n.id, n.charge_nr, g.verarbeitet_am, g.n_paletten,
       g.netto_eingang, g.m1, g.schimmel
  from neu n join gruppen g
    on g.charge_nr = n.charge_nr and g.verarbeitet_am = n.start_ts::date;

-- ---------- Paletten zählen (Pflichtangabe, immer vollständig) -------------
insert into auftrag_palette (auftrag_id, eingangsdatum)
select a.auftrag_id, w.eingangsdatum
  from sim.auftrag_wahr a
  join sim.palette_wahr w
    on w.lauf = a.lauf and w.charge_nr = a.charge_nr and w.verarbeitet_am = a.verarbeitet_am
 where a.lauf = :lauf;

-- ---------- Faule wiegen: Summe je Arbeit, auf Kilo gerundet ---------------
-- Mit etwas Wägefehler, wie an einer Palox-Waage.
insert into schimmel_messung (auftrag_id, kg)
select auftrag_id, greatest(round(schimmel * (0.95 + random() * 0.1))::int, 0)
  from sim.auftrag_wahr where lauf = :lauf and schimmel >= 1;

-- ---------- Palettenwägungen: nur eine Handvoll je Saison ------------------
-- Das ist die knappste Stichprobe im ganzen System und trägt die
-- Verdunstungsrate.
insert into verdunstung_wiegung (auftrag_id, charge_nr, eingangsdatum,
       brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, wiege_ts)
select a.auftrag_id, w.charge_nr, w.eingangsdatum,
       (w.netto_eingang_kg + 38 * 1.5 + 25)::numeric(8,2),
       -- Wägefehler der Palettenwaage: rund ±0.5 kg
       (w.netto_eingang_kg * power(1 - w.r_wahr, w.verarbeitet_am - w.eingangsdatum)
        + 38 * 1.5 + 25 + (random() - 0.5))::numeric(8,2),
       38, 'G2', a.verarbeitet_am::timestamptz + interval '8 hours'
  from (
    select w.*, row_number() over (order by random()) as rang
      from sim.palette_wahr w
     where w.lauf = :lauf and w.verarbeitet_am is not null
  ) w
  join sim.auftrag_wahr a
    on a.lauf = :lauf and a.charge_nr = w.charge_nr and a.verarbeitet_am = w.verarbeitet_am
 where w.rang <= (select n_wiegungen from sim.parameter where lauf = :lauf);

-- ---------- Ausschuss: auf der Hand-Linie nach Augenmass -------------------
insert into ausschuss_messung (auftrag_id, art, kg)
select a.auftrag_id, v.art::ausschuss_art,
       greatest(round((a.m1 - a.schimmel) * v.anteil * (0.9 + random() * 0.2))::int, 0)
  from sim.auftrag_wahr a
  join auftrag t on t.id = a.auftrag_id
  cross join lateral (values
      ('zu_klein', (select anteil_klein from sim.parameter where lauf = :lauf)),
      ('zu_gross', (select anteil_gross from sim.parameter where lauf = :lauf))
    ) v(art, anteil)
 where a.lauf = :lauf and t.weg = 'hand';

-- ---------- Sortier-CSV: auf der Maschinen-Linie ---------------------------
-- Die CSV wiegt die gesunde Ware, die über das Band läuft — also m1 abzüglich
-- des vorher aussortierten Schimmels.
insert into sortier_lauf (charge_nr, datei_name, roh_pruefsumme, datei_zeit,
       datei_zeit_quelle, auftrag_id, zuordnung, reinigung,
       n_roh, n_overflow, n_klein, n_dubletten, n_gueltig)
select a.charge_nr, format('SIM-%s-%s', :lauf, a.auftrag_id),
       format('sim-%s-%s', :lauf, a.auftrag_id),
       a.verarbeitet_am::timestamptz + interval '9 hours', 'dateiname',
       a.auftrag_id, 'auto',
       '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
       0, 0, 0, 0, 0
  from sim.auftrag_wahr a
  join auftrag t on t.id = a.auftrag_id
 where a.lauf = :lauf and t.station = 'sortieren';

-- Histogramm: Massenanteile treffen anteil_klein und anteil_gross exakt,
-- damit sich prüfen lässt, ob die Auswertung sie zurückgewinnt.
insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
select l.id, h.gewicht,
       greatest(round((a.m1 - a.schimmel) * h.anteil * 1000 / h.gewicht)::int, 1),
       k.klasse, k.kaliber_idx
  from sortier_lauf l
  join sim.auftrag_wahr a on a.auftrag_id = l.auftrag_id and a.lauf = :lauf
  join charge c on c.nr = l.charge_nr
  cross join lateral (values
      (400,  (select anteil_klein from sim.parameter where lauf = :lauf)),
      (2200, (select anteil_gross from sim.parameter where lauf = :lauf)),
      (700,  0.25), (950, 0.35), (1250, 0.25),
      (1600, 1 - 0.25 - 0.35 - 0.25
             - (select anteil_klein + anteil_gross from sim.parameter where lauf = :lauf))
    ) h(gewicht, anteil)
  cross join lateral klassiere(c.sorte, h.gewicht) k
 where l.datei_name like format('SIM-%s-%%', :lauf);

update sortier_lauf l
   set n_gueltig = s.n, n_roh = (s.n * 1.3)::int, n_dubletten = (s.n * 0.25)::int
  from (select lauf_id, sum(anzahl) as n from sortier_gewicht group by lauf_id) s
 where s.lauf_id = l.id and l.datei_name like format('SIM-%s-%%', :lauf);

-- ---------- Weg 1, zweiter Abschnitt: Waschen -----------------------------
-- Wochen nach dem Sortieren geht die Ware aus den Kaliber-Kisten ans
-- Waschbecken. Dort wird nochmals Faules aussortiert — Spec §3 nennt das
-- „Schimmel #2, zeitaufgelöst". Erfasst wird kein Palettenzählen (die
-- Original-Paletten gibt es nicht mehr), sondern der Durchsatz in Kilo.
with gruppen as (
  select w.charge_nr, w.gewaschen_am,
         -- Masse nach Verdunstung bis zum Waschen bzw. bis zum Sortieren
         sum(w.netto_eingang_kg * power(1 - w.r_wahr, w.gewaschen_am - w.eingangsdatum))
                                                                          as m_waschen,
         sum(w.netto_eingang_kg * power(1 - w.r_wahr, w.gewaschen_am - w.eingangsdatum)
             * sim.schimmel_wahr(w.gewaschen_am - w.eingangsdatum,
                                 p.schimmel_lambda, p.schimmel_k, w.anfaelligkeit))
                                                                          as schimmel_gesamt,
         sum(w.netto_eingang_kg * power(1 - w.r_wahr, w.verarbeitet_am - w.eingangsdatum)
             * sim.schimmel_wahr(w.verarbeitet_am - w.eingangsdatum,
                                 p.schimmel_lambda, p.schimmel_k, w.anfaelligkeit))
                                                                          as schimmel_beim_sortieren,
         p.anteil_klein, p.anteil_gross
    from sim.palette_wahr w cross join sim.parameter p
   where w.lauf = :lauf and p.lauf = :lauf
     and w.weg = 'maschine' and w.gewaschen_am is not null
   group by w.charge_nr, w.gewaschen_am, p.anteil_klein, p.anteil_gross
), neu as (
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status,
                       durchsatz_kg, bemerkung)
  select 'maschine', 'waschen', g.charge_nr,
         g.gewaschen_am::timestamptz + interval '8 hours',
         g.gewaschen_am::timestamptz + interval '15 hours', 'abgeschlossen',
         -- Was tatsächlich durchs Becken läuft: nach Verdunstung, nach allem
         -- Schimmel, ohne den beim Sortieren entnommenen Ausschuss.
         round((g.m_waschen - g.schimmel_gesamt)
               * (1 - g.anteil_klein - g.anteil_gross))::numeric(12,2),
         'SIM'
    from gruppen g
  returning id, charge_nr, start_ts
)
insert into schimmel_messung (auftrag_id, kg)
select n.id,
       -- Der Ausschuss ist beim Sortieren entnommen worden; was im zweiten
       -- Abschnitt verdirbt, verdirbt in der *verbliebenen* Masse. Ohne diesen
       -- Faktor wäre der Palox am Waschbecken relativ zum Durchsatz zu voll
       -- und das Modell würde die Kurve zu hoch anpassen (gemessen: +8.8 %).
       greatest(round((g.schimmel_gesamt - g.schimmel_beim_sortieren)
                      * (1 - g.anteil_klein - g.anteil_gross)
                      * (0.95 + random() * 0.1))::int, 0)
  from neu n
  join gruppen g on g.charge_nr = n.charge_nr and g.gewaschen_am = n.start_ts::date
 where (g.schimmel_gesamt - g.schimmel_beim_sortieren)
       * (1 - g.anteil_klein - g.anteil_gross) >= 1;

-- ---------- Lagerkontrollen: zufällig gegriffene Paletten ------------------
-- Der Gegenentwurf zur Verarbeitungsmessung: Diese Paletten werden *nicht*
-- danach ausgewählt, wie sie aussehen. Genau darum können sie die
-- Selektionsverzerrung aufdecken — und, wenn es genug sind, beheben.
-- Erfasst wird an einer Wägung, die es ohnehin gibt: ein Feld „davon faul".
insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg,
       brutto_jetzt_kg, kisten, gebindeart, wiege_ts, faul_kg, sichtbar_schimmel,
       bemerkung)
select w.charge_nr, w.eingangsdatum,
       (w.netto_eingang_kg + 38 * 1.5 + 25)::numeric(8,2),
       (w.netto_eingang_kg * power(1 - w.r_wahr, w.kontroll_datum - w.eingangsdatum)
        + 38 * 1.5 + 25 + (random() - 0.5))::numeric(8,2),
       38, 'G2', w.kontroll_datum::timestamptz + interval '10 hours',
       -- Schätzung nach Augenmass, rund ±15 %
       greatest(round((w.netto_eingang_kg
         * power(1 - w.r_wahr, w.kontroll_datum - w.eingangsdatum)
         * sim.schimmel_wahr(w.kontroll_datum - w.eingangsdatum, p.schimmel_lambda,
                             p.schimmel_k, w.anfaelligkeit)
         * (0.85 + random() * 0.3))::numeric, 1), 0),
       true, 'SIM-LAGER'
  from (
    select w.*,
           -- So läuft es wirklich: Jemand geht an einem Tag in die Halle und
           -- macht auf, was dort *noch steht*. Eine Palette, die längst
           -- verarbeitet ist, kann man nicht mehr kontrollieren — und eine,
           -- die noch lange liegen bleibt, kann man mehrfach antreffen.
           -- Frühere Fassungen zogen den Kontrolltag zwischen Einlagerung und
           -- Verarbeitung: Bei „Schlechtes zuerst" wurden dadurch ausgerechnet
           -- die anfälligen Paletten früh kontrolliert, und die Kontrollen
           -- verschoben die Kurve, statt sie zu korrigieren.
           t.tag as kontroll_datum,
           row_number() over (order by random()) as rang
      from generate_series(1, 12) g(monat)
      cross join lateral (
        select date '2026-09-15' + ((g.monat - 1) * 15) as tag
      ) t
      join sim.palette_wahr w
        on w.lauf = :lauf
       and w.eingangsdatum + 20 <= t.tag
       and (w.verarbeitet_am is null or w.verarbeitet_am > t.tag)
       and t.tag <= date '2027-03-31'
  ) w
  cross join sim.parameter p
 where p.lauf = :lauf
   and w.rang <= coalesce((select n_lagerkontrollen from sim.parameter where lauf = :lauf), 0);
