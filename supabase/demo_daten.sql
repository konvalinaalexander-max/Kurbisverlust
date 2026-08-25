-- =====================================================================
-- DEMO-DATEN — eine erfundene, aber realistische Saison zum Durchklicken
--
-- Zweck: Das Dashboard zeigt ohne Daten nichts. Diese Datei füllt die
-- Datenbank mit einer vollständigen Saison, damit man sieht, was am Ende
-- herauskommt — bevor die erste echte Palette gezählt ist.
--
-- SO WIRD SIE BENUTZT
--   1. Inhalt kopieren, im Supabase-SQL-Editor einfügen, Run.
--   2. In der App als Betriebsleiter anmelden und durch die Auswertung klicken.
--   3. Wenn die echten Daten kommen: supabase/demo_daten_entfernen.sql
--      einspielen — dann ist alles Erfundene wieder weg.
--
-- Alles Erfundene ist markiert: Aufträge tragen bemerkung = 'DEMO',
-- Paletten haben extern_id 'demo-…', Sortierdateien beginnen mit 'DEMO-'.
-- Echte Daten werden nicht angefasst.
--
-- Die Zahlen sind so gewählt, dass realistische Koeffizienten entstehen:
-- rund 0.06 % Verdunstung je Tag, 1–5 % Schimmel je nach Lagerdauer,
-- ~3 % Ausschuss, ~1.5 % Nebenkanal, ~0.3 kg Überfüllung je Kiste.
-- =====================================================================

do $$
declare
  v_chargen int[] := array[1613, 1614, 1616, 1606, 1611, 1626, 1630, 1635, 1647, 1650];
  v_charge  int;
  v_i       int;
  v_p       int;
  v_n_pal   int;
  v_datum   date;
  v_brutto  numeric;
  v_kisten  int;
  v_art     text;
  v_auftrag bigint;
  v_lauf    int;
  v_start   timestamptz;
  v_tage    int;
  v_netto   numeric;
  v_masse   numeric;
  v_rate    numeric := 0.0006;      -- Verdunstung je Tag
  v_wiegung bigint;
  v_klein   numeric;
  v_gross   numeric;
  v_schimmel numeric;
  v_anteil  numeric;
begin
  -- ---------- Wareneingang: 10 Chargen, gestaffelt eingelagert ----------
  foreach v_charge in array v_chargen loop
    v_i := array_position(v_chargen, v_charge);
    v_n_pal := 30 + (v_i * 13) % 40;               -- 30 bis 69 Paletten
    for v_p in 1 .. v_n_pal loop
      -- Einlagerung über zwei bis drei Wochen verteilt
      v_datum  := date '2026-09-01' + ((v_i - 1) * 5) + (v_p * 17) % 18;
      v_brutto := 900 + ((v_i * 7 + v_p * 11) % 90);
      v_kisten := 36 + (v_p % 5);
      v_art    := case when (v_i + v_p) % 7 = 0 then 'IFCO 6416' else 'G2' end;
      insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
      values (v_charge, v_datum, v_brutto, v_kisten, v_art,
              format('demo-%s-%s', v_charge, v_p));
    end loop;
  end loop;

  -- ---------- Verarbeitung: Aufträge über Oktober bis Februar ----------
  foreach v_charge in array v_chargen loop
    v_i := array_position(v_chargen, v_charge);

    for v_lauf in 1 .. 2 loop
      -- Erster Lauf früh, zweiter deutlich später — so entstehen kurze und
      -- lange Lagerdauern und die Schimmelkurve bekommt mehrere Stützstellen.
      v_start := (date '2026-10-15' + ((v_i - 1) * 6) + (v_lauf - 1) * 55)::timestamptz
                 + interval '8 hours';

      -- Ungerade Chargen über die Maschine, gerade von Hand — beide Wege belegt
      if (v_i + v_lauf) % 2 = 1 then
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
        values ('maschine', 'sortieren', v_charge, v_start,
                v_start + interval '6 hours', 'abgeschlossen', 'DEMO')
        returning id into v_auftrag;
      else
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
        values ('hand', 'waschen_sortieren', v_charge, v_start,
                v_start + interval '7 hours', 'abgeschlossen', 'DEMO')
        returning id into v_auftrag;
      end if;

      -- Paletten zählen: 8 bis 20 Stück je Lauf, mit Datum vom Zettel
      v_n_pal := 8 + (v_i * 3 + v_lauf * 5) % 13;
      insert into auftrag_palette (auftrag_id, eingangsdatum)
      select v_auftrag, p.eingangsdatum
        from (select eingangsdatum from palette
               where charge_nr = v_charge order by eingangsdatum
               offset (v_lauf - 1) * 15 limit v_n_pal) p;

      -- Wie viel Masse hat dieser Lauf bewegt, und wie alt war sie?
      select eingang_netto_kg, lagertage into v_masse, v_tage
        from v_auftrag_masse where auftrag_id = v_auftrag;
      if v_masse is null or v_tage is null then continue; end if;

      -- ---------- Schimmel: wächst mit der Lagerdauer ----------
      v_anteil := case when v_tage <  30 then 0.010
                       when v_tage <  60 then 0.020
                       when v_tage <  90 then 0.033
                       when v_tage < 120 then 0.045
                       else                   0.058 end;
      v_schimmel := round(v_masse * power(1 - v_rate, v_tage) * v_anteil);
      if v_schimmel > 0 then
        insert into schimmel_messung (auftrag_id, kg) values (v_auftrag, v_schimmel::int);
      end if;

      -- ---------- Eine Palette wiegen (nur auf der Hand-Linie) ----------
      if (v_i + v_lauf) % 2 = 0 then
        select brutto_kg, kisten, gebindeart, eingangsdatum
          into v_brutto, v_kisten, v_art, v_datum
          from palette where charge_nr = v_charge
          order by eingangsdatum offset (v_lauf - 1) * 15 limit 1;

        v_netto := v_brutto - v_kisten * 1.5 - 25;
        insert into verdunstung_wiegung (auftrag_id, charge_nr, eingangsdatum,
               brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart,
               kuerbisse_pro_kiste, wiege_ts)
        values (v_auftrag, v_charge, v_datum, v_brutto,
                round((v_netto * power(1 - v_rate, v_start::date - v_datum)
                       + v_kisten * 1.5 + 25)::numeric, 1),
                v_kisten, v_art, 4 + (v_i % 3), v_start)
        returning id into v_wiegung;

        update auftrag_palette set wiegung_id = v_wiegung, eingangsdatum = v_datum
         where id = (select min(id) from auftrag_palette where auftrag_id = v_auftrag);

        -- ---------- Ausschuss nach Augenmass ----------
        v_klein := round(v_masse * 0.030);
        v_gross := round(v_masse * 0.015);
        insert into ausschuss_messung (auftrag_id, art, kg)
        values (v_auftrag, 'zu_klein', v_klein::int), (v_auftrag, 'zu_gross', v_gross::int);

        -- ---------- Fertige Palette: 8.2 bis 8.4 kg je Kiste ----------
        insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten,
               gebindeart, kuerbisse_pro_kiste)
        values (v_auftrag, v_charge,
                round((32 * (8.20 + (v_i % 3) * 0.10) + 32 * 1.5 + 25)::numeric, 1),
                32, 'G2', 4);
      end if;
    end loop;
  end loop;

  raise notice 'Demo: Wareneingang und Verarbeitung angelegt';
end $$;

-- ---------- Sortier-CSVs für drei Maschinen-Läufe ------------------------
-- Histogramm statt Einzelzeilen (so speichert die App es auch). Die Verteilung
-- ist grob glockenförmig um 900 g, mit Ausläufern unter der Sorten-Grenze und
-- über 2000 g — daraus entstehen Ausschuss- und Nebenkanal-Anteil.
do $$
declare
  v_auftrag bigint;
  v_charge  int;
  v_masse   numeric;
  v_hist    jsonb;
  v_n       int;
  v_r       record;
begin
  for v_r in
    select a.id, a.charge_nr, a.start_ts, m.eingang_netto_kg, m.lagertage
      from auftrag a
      join v_auftrag_masse m on m.auftrag_id = a.id
     where a.bemerkung = 'DEMO' and a.station = 'sortieren'
       and m.eingang_netto_kg is not null and m.lagertage is not null
     order by a.id limit 3
  loop
    -- Die CSV soll das wiegen, was am Band ankommt: Eingang minus Verdunstung
    -- minus Schimmel. Nur dann ist die Massenbilanz eine echte Probe und nicht
    -- bloss ein Vergleich zweier unabhängiger Erfindungen.
    v_masse := v_r.eingang_netto_kg
               * power(1 - 0.0006, v_r.lagertage)
               * (1 - case when v_r.lagertage <  30 then 0.010
                           when v_r.lagertage <  60 then 0.020
                           when v_r.lagertage <  90 then 0.033
                           when v_r.lagertage < 120 then 0.045
                           else                          0.058 end);
    -- Das Histogramm unten wiegt im Mittel 1.075 kg je Kürbis
    v_n := greatest((v_masse / 1.075)::int, 100);

    v_hist := jsonb_build_array(
      jsonb_build_array( 350, (v_n * 0.010)::int),   -- unter 500 g → Verlust
      jsonb_build_array( 450, (v_n * 0.020)::int),
      jsonb_build_array( 650, (v_n * 0.120)::int),
      jsonb_build_array( 850, (v_n * 0.260)::int),
      jsonb_build_array(1050, (v_n * 0.280)::int),
      jsonb_build_array(1350, (v_n * 0.190)::int),
      jsonb_build_array(1700, (v_n * 0.100)::int),
      jsonb_build_array(2150, (v_n * 0.020)::int)    -- ab 2000 g → Nebenkanal
    );

    perform csv_lauf_speichern(
      v_r.charge_nr,
      format('DEMO-%s-%s', v_r.charge_nr, to_char(v_r.start_ts, 'DD-MM-HH24-MI')),
      null, format('demo-pruefsumme-%s', v_r.id),
      v_r.start_ts + interval '90 minutes', 'dateiname',
      '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
      (v_n * 1.28)::int, 4, 9, (v_n * 0.27)::int,
      v_hist);
  end loop;
  raise notice 'Demo: Sortier-CSVs eingelesen';
end $$;

-- ---------- Zwei Sonderfälle, damit man sie einmal gesehen hat -----------
do $$
declare v_auftrag bigint; v_charge int := 1611;
begin
  -- (1) Eine abgebrochene Arbeit: taucht in keiner Auswertung auf,
  --     ist aber unter Stammdaten → Abgebrochene Arbeiten sichtbar.
  insert into auftrag (weg, station, charge_nr, start_ts, bemerkung)
  values ('hand', 'waschen_sortieren', v_charge, timestamptz '2026-11-03 09:00+01', 'DEMO')
  returning id into v_auftrag;
  insert into auftrag_palette (auftrag_id) select v_auftrag from generate_series(1, 4);
  perform auftrag_abbrechen(v_auftrag, 'Falsche Charge gewählt');

  -- (2) Ein Zahlendreher: 4500 statt 450 kg Schimmel. Die Rechnung bleibt
  --     davon unberührt; das Dashboard meldet den Fund ganz oben.
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
  values ('hand', 'waschen_sortieren', v_charge, timestamptz '2026-11-10 08:00+01',
          timestamptz '2026-11-10 15:00+01', 'abgeschlossen', 'DEMO')
  returning id into v_auftrag;
  insert into auftrag_palette (auftrag_id, eingangsdatum)
  select v_auftrag, eingangsdatum from palette where charge_nr = v_charge
   order by eingangsdatum limit 6;
  insert into schimmel_messung (auftrag_id, kg) values (v_auftrag, 4500);

  raise notice 'Demo: Sonderfälle angelegt (abgebrochen, Zahlendreher)';
end $$;

select format('Demo-Saison steht: %s Paletten in %s Chargen, %s Arbeiten, %s Sortierläufe. '
              || 'Eingang %s t. Jetzt in der App unter Auswertung anschauen.',
              (select count(*) from palette where extern_id like 'demo-%'),
              (select count(distinct charge_nr) from palette where extern_id like 'demo-%'),
              (select count(*) from auftrag where bemerkung = 'DEMO'),
              (select count(*) from sortier_lauf where datei_name like 'DEMO-%'),
              (select round(sum(eingang_netto_kg) / 1000, 1) from v_charge_rueckgrat)) as ergebnis;
