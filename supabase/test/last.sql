-- =====================================================================
-- Lasttest: eine Saison in voller Grösse, mit Reserve nach oben
--
-- Die Demo-Saison ist zu klein, um Tempo zu beurteilen. Hier wird bewusst
-- deutlich mehr erzeugt, als je anfallen sollte:
--   ~5 000 Eingangspaletten (gegen ~1 500 real)
--   ~800 Arbeiten mit ~12 000 gezählten Paletten
--   ~300 Sortierläufe mit ~250 000 Einzelgewichten
-- Wenn die Auswertung damit zügig läuft, läuft sie auch mit echten Daten.
-- =====================================================================

do $$
declare v_wer uuid;
begin
  select id into v_wer from profil order by erstellt_ts limit 1;
  -- false statt true: Diese Datei wird mit psql -f eingespielt, also läuft jede
  -- Anweisung in einer eigenen Transaktion. Eine transaktionslokale Einstellung
  -- wäre nach dem Block wieder weg.
  perform set_config('request.jwt.claim.sub', v_wer::text, false);
  perform set_config('request.jwt.claims', json_build_object('sub', v_wer)::text, false);
end $$;

-- ---------- Eingangspaletten: alle 42 Chargen, je ~120 -------------------
insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
select c.nr,
       date '2026-09-01' + (i % 45),
       900 + (i * 7) % 90,
       36 + (i % 5),
       case when i % 7 = 0 then 'IFCO 6416' else 'G2' end,
       format('last-%s-%s', c.nr, i)
  from charge c, generate_series(1, 120) i;

-- ---------- Arbeiten: ~20 je Charge über die Saison -----------------------
insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
select case when (c.nr + i) % 2 = 0 then 'hand' else 'maschine' end::verarbeitungsweg,
       case when (c.nr + i) % 2 = 0 then 'waschen_sortieren' else 'sortieren' end::station,
       c.nr,
       (date '2026-10-10' + i * 6)::timestamptz + interval '8 hours',
       (date '2026-10-10' + i * 6)::timestamptz + interval '15 hours',
       'abgeschlossen', 'LASTTEST'
  from charge c, generate_series(1, 20) i;

-- ---------- Gezählte Paletten: ~15 je Arbeit ------------------------------
insert into auftrag_palette (auftrag_id, eingangsdatum)
select a.id, date '2026-09-01' + (i * 3) % 45
  from auftrag a, generate_series(1, 15) i
 where a.bemerkung = 'LASTTEST';

-- ---------- Messungen -----------------------------------------------------
insert into schimmel_messung (auftrag_id, kg)
select id, 80 + (id % 60) from auftrag where bemerkung = 'LASTTEST';

insert into ausschuss_messung (auftrag_id, art, kg)
select a.id, art::ausschuss_art, 200 + (a.id % 100)
  from auftrag a, (values ('zu_klein'), ('zu_gross')) v(art)
 where a.bemerkung = 'LASTTEST' and a.weg = 'hand';

insert into verdunstung_wiegung (auftrag_id, charge_nr, eingangsdatum, brutto_damals_kg,
       brutto_jetzt_kg, kisten, gebindeart, kuerbisse_pro_kiste, wiege_ts)
select a.id, a.charge_nr, date '2026-09-05', 950, 905 + (a.id % 20), 40, 'G2', 5, a.start_ts
  from auftrag a where a.bemerkung = 'LASTTEST' and a.weg = 'hand';

insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, kuerbisse_pro_kiste)
select a.id, a.charge_nr, 335 + (a.id % 8), 32, 'G2', 4
  from auftrag a where a.bemerkung = 'LASTTEST' and a.weg = 'hand';

-- ---------- Sortierläufe: 300 Stück mit je ~850 Gewichtsstufen ------------
-- Direkt eingefügt statt über csv_lauf_speichern: erzeugt dieselbe Struktur,
-- nur ohne 300 einzelne Funktionsaufrufe.
insert into sortier_lauf (charge_nr, datei_name, roh_pruefsumme, datei_zeit, datei_zeit_quelle,
       auftrag_id, zuordnung, reinigung, n_roh, n_overflow, n_klein, n_dubletten, n_gueltig)
select a.charge_nr, format('LASTTEST-%s', a.id), format('last-%s', a.id),
       a.start_ts + interval '90 minutes', 'dateiname', a.id, 'auto',
       '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
       12000, 5, 10, 3000, 8500
  from auftrag a
 where a.bemerkung = 'LASTTEST' and a.station = 'sortieren'
 order by a.id limit 300;

insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
select l.id, g.gewicht, 5 + (g.gewicht % 17), k.klasse, k.kaliber_idx
  from sortier_lauf l
  join charge c on c.nr = l.charge_nr
  cross join lateral generate_series(300, 2000, 2) g(gewicht)
  cross join lateral klassiere(c.sorte, g.gewicht) k
 where l.datei_name like 'LASTTEST-%';

analyze;

select format('Lasttest bereit: %s Paletten, %s Arbeiten, %s gezählte Paletten, '
              || '%s Sortierläufe mit %s Gewichtsstufen. Eingang %s t.',
              (select count(*) from palette),
              (select count(*) from auftrag),
              (select count(*) from auftrag_palette),
              (select count(*) from sortier_lauf),
              (select count(*) from sortier_gewicht),
              (select round(sum(eingang_netto_kg)/1000) from v_charge_rueckgrat)) as ergebnis;
