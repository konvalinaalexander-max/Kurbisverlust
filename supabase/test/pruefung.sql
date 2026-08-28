-- =====================================================================
-- Prüfabfragen: füttert das Schema mit einem realistischen Mini-Datensatz
-- und kontrolliert, dass Reinigung, Klassierung, Zuordnung, Koeffizienten
-- und Hochrechnung die erwarteten Zahlen liefern.
--   psql … -f supabase/test/pruefung.sql
-- =====================================================================
\set ON_ERROR_STOP on
\timing off
set client_min_messages = notice;

-- --- Benutzer -----------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'chef@hof.test',    '{"name":"Chef"}'),
       ('22222222-2222-2222-2222-222222222222', 'arbeit@hof.test',  '{"name":"Arbeiter"}');
update profil set rolle = 'admin' where id = '11111111-1111-1111-1111-111111111111';
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- --- Stammdaten ---------------------------------------------------------
insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette)
values ('Holzkiste', 1.500, 25.000), ('Ohne Tara', null, null);

-- --- Wareneingang: 10 Paletten Tiana, gestaffelt eingelagert -------------
-- Brutto 950 kg, 40 Kisten → Netto 950 − 40·1.5 − 25 = 865 kg je Palette.
-- Die Werte sind so gewählt, dass die Kaskade am Ende genau die Masse der
-- Sortier-CSV vorhersagt: damit prüft die Massenbilanz die ganze Kette.
insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
select 1613, date '2026-09-01' + (i / 2), 950.00, 40, 'Holzkiste', 'sheet-' || i
  from generate_series(0, 9) i;

-- =====================================================================
do $$
declare v numeric; v_txt text; v_int int; v_id bigint;
begin
  -- ---- Netto je Palette: 500 − 40·1.5 − 25 = 415 --------------------
  select netto_kg into v from v_palette limit 1;
  assert v = 865.00, format('Netto je Palette erwartet 865, ist %s', v);

  select eingang_netto_kg into v from v_charge_rueckgrat where charge_nr = 1613;
  assert v = 8650.00, format('Eingang der Charge erwartet 8650, ist %s', v);

  -- Gestaffelte Einlagerung: das massegewichtete Datum liegt in der Mitte
  assert (select eingangsdatum_mittel from v_charge_rueckgrat where charge_nr = 1613)
         = date '2026-09-03', 'Massegewichtetes Eingangsdatum falsch';

  -- ---- Unbekannte Tara darf nicht als 0 durchgehen -------------------
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
  values (1614, date '2026-09-05', 950, 40, 'Ohne Tara', 'sheet-ohne-tara');
  select netto_kg into v from v_palette where charge_nr = 1614;
  assert v is null, 'Ohne Tara muss das Netto NULL bleiben (Leer ≠ 0)';
  delete from palette where extern_id = 'sheet-ohne-tara';

  -- ---- Klassierung (Tiana: <500 Verlust, Bänder bis 2000, ab 2000 Kanal)
  assert (select klasse from klassiere('Tiana', 499))  = 'verlust_klein', 'Tiana 499 g = Verlust';
  assert (select klasse from klassiere('Tiana', 500))  = 'kaliber',       'Tiana 500 g = Kaliber';
  assert (select kaliber_idx from klassiere('Tiana', 500)) = 0,           'Tiana 500 g = erstes Band';
  assert (select kaliber_idx from klassiere('Tiana', 800)) = 1,           'Tiana 800 g = zweites Band (Grenze gehört nach oben)';
  assert (select kaliber_idx from klassiere('Tiana', 1999)) = 3,          'Tiana 1999 g = viertes Band';
  assert (select klasse from klassiere('Tiana', 2000)) = 'nebenkanal',    'Tiana 2000 g = Nebenkanal';
  assert (select klasse from klassiere('Unbekannt', 900)) = 'unklassiert','Unbekannte Sorte = unklassiert';
  assert (select klasse from klassiere('Butterkin', 550)) = 'kaliber',    'Butterkin hat ein schmales erstes Band 500–600';

  -- ---- Tara aus dem Erntejournal ist vorbelegt (Migration 0010) -------
  assert (select tara_kg_pro_kiste from gebinde where art = 'G2') = 1.500,
    'G2-Tara muss 1.5 kg sein (aus dem Erntejournal)';
  assert (select tara_kg_palette from gebinde where art = 'G2') = 25.000,
    'Palettengewicht muss 25 kg sein';
  assert (select tara_kg_pro_kiste from gebinde where art = 'IFCO 6424') = 2.000,
    'IFCO-6424-Tara falsch';

  raise notice 'OK  Stammdaten, Netto, Klassierung';
end $$;

-- --- Zweite Charge: 6 Paletten, nie verarbeitet ------------------------
-- Sie liegt am Stichtag noch im Lager und ist damit rechts-zensiert — genau
-- der Fall, für den es die Projektion gibt (Spec §9).
insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
select 1614, date '2026-09-10', 950.00, 40, 'Holzkiste', 'sheet-b-' || i
  from generate_series(0, 5) i;

-- --- Auftrag Weg 1: Sortieren am 15.11., alle 10 Paletten ---------------
insert into auftrag (id, weg, station, charge_nr, start_ts, status)
values (900, 'maschine', 'sortieren', 1613, timestamptz '2026-11-15 08:00+01', 'offen');
select setval(pg_get_serial_sequence('auftrag', 'id'), 1000);

insert into auftrag_palette (auftrag_id, palette_id)
select 900, id from v_palette where charge_nr = 1613;

insert into schimmel_messung (auftrag_id, kg) values (900, 60);

-- --- Und der zweite Abschnitt: Waschen, 40 Tage nach dem Sortieren -------
-- Weg 1 ist erst nach dem Waschen zu Ende (Spec §3). Ohne diesen Schritt gilt
-- die Charge zu Recht als noch im Haus — sortierte Ware steht in
-- Kaliber-Kisten in derselben Halle und altert weiter.
insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status, durchsatz_kg)
values (903, 'maschine', 'waschen', 1613, timestamptz '2026-12-25 08:00+01',
        timestamptz '2026-12-25 15:00+01', 'abgeschlossen', 8200);

-- --- Verdunstungswägung: dieselbe Palette, 75 Tage später ---------------
insert into verdunstung_wiegung (charge_nr, palette_id, eingangsdatum, brutto_damals_kg,
                                 brutto_jetzt_kg, kisten, gebindeart, wiege_ts)
values (1613, (select min(id) from palette where charge_nr = 1613), date '2026-09-01',
        950.00, 908.00, 40, 'Holzkiste', timestamptz '2026-11-15 08:00+01');

-- --- Sortier-CSV: Histogramm über die Klassen hinweg --------------------
select csv_lauf_speichern(
  1613, '1613-15-11-09-30', 'rohdaten/1613-15-11-09-30.csv', 'pruefsumme-1',
  timestamptz '2026-11-15 09:30+01', 'dateiname',
  '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
  11370, 5, 11, 3204,
  '[[300,200],[400,300],[600,2000],[900,3000],[1400,2000],[1900,500],[2100,161]]'::jsonb
);

-- Die Auswertung liegt seit 0016 gespeichert vor: nach jeder Erfassung
-- einmal neu rechnen, sonst prüft man den Stand von vorhin.
select auswertung_aktualisieren() \gset stand_

do $$
declare v numeric; v_int int; v_status text; v_lauf bigint;
begin
  select id into v_lauf from sortier_lauf where roh_pruefsumme = 'pruefsumme-1';
  -- ---- Reinigungs-Trichter und Klassenmassen -------------------------
  select n_gueltig into v_int from sortier_lauf where id = v_lauf;
  assert v_int = 8161, format('n_gueltig erwartet 8161, ist %s', v_int);

  select n_klein into v_int from v_sortier_lauf_masse where lauf_id = v_lauf;
  assert v_int = 500, format('Kürbisse unter 500 g erwartet 500, sind %s', v_int);
  select n_nebenkanal into v_int from v_sortier_lauf_masse where lauf_id = v_lauf;
  assert v_int = 161, format('Nebenkanal erwartet 161, sind %s', v_int);
  select masse_klein_kg into v from v_sortier_lauf_masse where lauf_id = v_lauf;
  assert v = 180.00, format('Masse zu klein erwartet 180 kg (200·0.3 + 300·0.4), ist %s', v);

  -- ---- Histogramm und Einzelzeilen müssen dasselbe sagen -------------
  select count(*)::int into v_int from v_sortier_kuerbis where lauf_id = v_lauf;
  assert v_int = 8161, format('v_sortier_kuerbis muss 8161 Zeilen liefern, liefert %s', v_int);
  select sum(gewicht_g) / 1000.0 into v from v_sortier_kuerbis where lauf_id = v_lauf;
  assert v = (select masse_kg from v_sortier_lauf_masse where lauf_id = v_lauf),
    'Expandierte Zeilen und Histogramm ergeben verschiedene Massen';

  -- ---- Automatische Zuordnung zum Auftrag ----------------------------
  select zuordnung::text into v_status from sortier_lauf where id = v_lauf;
  assert v_status = 'auto', format('Zuordnung erwartet auto, ist %s', v_status);
  assert (select auftrag_id from sortier_lauf where id = v_lauf) = 900, 'Falscher Auftrag zugeordnet';

  raise notice 'OK  CSV-Aufnahme, Klassenmassen, Auftrags-Zuordnung';
end $$;

-- --- Zuordnung in den Grenzfällen ---------------------------------------
do $$
declare v_status text; v_lauf bigint;
begin
  select id into v_lauf from sortier_lauf where roh_pruefsumme = 'pruefsumme-1';

  -- Ein zweiter Auftrag um 10:00 darf die 09:30-Datei nicht an sich ziehen:
  -- der offene Auftrag von 08:00 endet spätestens beim nächsten Start.
  insert into auftrag (id, weg, station, charge_nr, start_ts)
  values (901, 'maschine', 'sortieren', 1613, timestamptz '2026-11-15 10:00+01');
  select auftrag_zuordnen(v_lauf)::text into v_status;
  assert v_status = 'auto', format('09:30 gehört eindeutig zum 08:00-Auftrag, ist %s', v_status);
  assert (select auftrag_id from sortier_lauf where id = v_lauf) = 900, 'Falscher Auftrag';
  delete from auftrag where id = 901;

  -- Echt mehrdeutig: zwei abgeschlossene Aufträge, die Datei liegt zwischen
  -- beiden und gleich weit von beiden Startzeiten entfernt.
  update auftrag set ende_ts = timestamptz '2026-11-15 09:00+01' where id = 900;
  insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts)
  values (902, 'maschine', 'sortieren', 1613,
          timestamptz '2026-11-15 18:00+01', timestamptz '2026-11-15 19:00+01');
  update sortier_lauf set datei_zeit = timestamptz '2026-11-15 12:00+01' where id = v_lauf;
  select auftrag_zuordnen(v_lauf)::text into v_status;
  assert v_status = 'mehrdeutig',
    format('Zwei gleich plausible Aufträge müssen in die Warteschlange, ist %s', v_status);
  assert (select auftrag_id from sortier_lauf where id = v_lauf) is null,
    'Bei Mehrdeutigkeit darf nichts zugeordnet bleiben';

  -- Kein Treffer weit außerhalb jedes Fensters
  update sortier_lauf set datei_zeit = timestamptz '2026-12-24 09:30+01' where id = v_lauf;
  select auftrag_zuordnen(v_lauf)::text into v_status;
  assert v_status = 'offen', format('Kein Treffer muss offen ergeben, ist %s', v_status);

  -- Manuelle Zuordnung durch den Betriebsleiter
  perform auftrag_manuell_zuordnen(v_lauf, 900);
  assert (select zuordnung::text from sortier_lauf where id = v_lauf) = 'manuell',
    'Manuelle Zuordnung muss als solche vermerkt werden';

  -- zurück in den auswertbaren Zustand
  delete from auftrag where id = 902;
  update auftrag set ende_ts = null where id = 900;
  update sortier_lauf set datei_zeit = timestamptz '2026-11-15 09:30+01' where id = v_lauf;
  perform auftrag_zuordnen(v_lauf);
  raise notice 'OK  Zuordnung: eindeutig, mehrdeutig, kein Treffer, manuell';
end $$;

-- =====================================================================
do $$
declare v numeric; v_erwartet numeric; v_int int; v_txt text;
begin
  -- ---- Verdunstungsrate: 1 − (395/415)^(1/75) ------------------------
  select rate_pro_tag into v from v_verdunstung_messung;
  v_erwartet := 1 - power(823.0 / 865.0, 1.0 / 75);
  assert abs(v - v_erwartet) < 1e-6, format('Verdunstungsrate %s, erwartet %s', v, v_erwartet);
  assert (select verwendbar from v_verdunstung_messung), 'Wägung muss verwendbar sein';

  select basis into v_txt from v_koeff_verdunstung where sorte = 'Tiana';
  assert v_txt like '%aller Sorten%',
    format('Bei einer einzigen Wägung muss auf den Gesamtwert zurückgefallen werden, basis=%s', v_txt);

  -- ---- Lagerdauer des Auftrags: 15.11. minus gestaffelte Eingänge ----
  select lagertage into v from v_auftrag_masse where auftrag_id = 900;
  assert v = 73.0, format('Lagertage erwartet 73.0 (15.11. minus 03.09.), sind %s', v);
  select eingang_netto_kg into v from v_auftrag_masse where auftrag_id = 900;
  assert v = 8650.00, format('10 Paletten à 865 kg = 8650, ist %s', v);

  -- ---- Schimmelanteil: 60 kg auf die heutige (verdunstete) Masse -----
  select anteil into v from v_schimmel_beobachtung where auftrag_id = 900;
  assert v > 60.0 / 8650.0,
    'Der Anteil muss auf die verdunstete Masse bezogen sein und damit über 60/8650 liegen';
  assert v < 0.05, format('Schimmelanteil unplausibel hoch: %s', v);

  -- ---- Schimmelkurve ist monoton -------------------------------------
  assert not exists (
    select 1 from (select anteil_mono, lag(anteil_mono) over (order by von) vor
                     from v_schimmel_kurve) t
     where anteil_mono < vor),
    'Die kumulative Schimmelkurve darf nicht fallen';
  assert schimmelanteil(200) >= schimmelanteil(10), 'schimmelanteil() muss mit dem Alter wachsen';
  assert schimmelanteil(5) = 0, 'Ohne Beobachtung unter 14 Tagen ist der Anteil 0';

  raise notice 'OK  Verdunstung, Schimmel, Kurve';
end $$;

-- =====================================================================
do $$
declare v numeric; v_kaskade record; v_summe numeric;
begin
  -- ---- Ausschuss-Koeffizient aus der CSV -----------------------------
  select mittel into v from v_koeff_ausschuss where sorte = 'Tiana';
  assert v > 0 and v < 0.2, format('Ausschussanteil unplausibel: %s', v);

  -- ---- Die Kaskade darf keine Masse erfinden -------------------------
  for v_kaskade in select * from v_kaskade loop
    assert v_kaskade.m1 <= v_kaskade.m0 + 1e-9,
      format('Nach Verdunstung mehr Masse als vorher (Charge %s)', v_kaskade.charge_nr);
    assert v_kaskade.m2 <= v_kaskade.m1 + 1e-9, 'Nach Schimmel mehr Masse als vorher';
    assert v_kaskade.verkaufsfaehig_kg >= -1e-9, 'Verkaufsfähige Masse darf nicht negativ werden';
  end loop;

  -- ---- Die Ströme müssen jede Portion vollständig aufteilen ----------
  for v_kaskade in
      select distinct charge_nr, portion from v_hochrechnung
  loop
    select sum(kg), max(portion_kg) into v_summe, v from v_hochrechnung
     where charge_nr = v_kaskade.charge_nr
       and portion = v_kaskade.portion;
    -- Toleranz 50 g: Die fünf Ströme werden einzeln auf 10 g gerundet
    -- ausgegeben, ihre Summe kann also um wenige Rundungsschritte abweichen.
    -- Alles darüber wäre ein echter Rechenfehler.
    assert abs(v_summe - v) < 0.05,
      format('Charge %s / %s: Ströme (%s kg) teilen die Portion (%s kg) nicht auf',
             v_kaskade.charge_nr, v_kaskade.portion, round(v_summe, 2), round(v, 2));
  end loop;

  -- ---- Beide Portionen kommen vor: beobachtet und projiziert ---------
  -- 1613 ist sortiert *und* gewaschen, also den ganzen Weg 1 durch. Erst
  -- damit gilt sie als draussen — vor 0024 reichte dafür das Sortieren, und
  -- die Ware verdunstete in der Rechnung nicht mehr weiter, obwohl sie noch
  -- wochenlang in der Halle stand.
  assert (select count(*) from v_hochrechnung
           where charge_nr = 1613 and portion = 'ausgelagert') > 0,
    'Die vollständig verarbeitete Charge muss als beobachtet erscheinen';
  assert (select alter_ausgelagert from v_hochrechnung_basis where charge_nr = 1613)
       > (select lagertage from v_auftrag_masse where auftrag_id = 900),
    'Das Endalter muss beim Waschen liegen, nicht beim Sortieren';
  assert (select count(*) from v_hochrechnung
           where charge_nr = 1614 and portion = 'lager') > 0,
    'Die noch eingelagerte Charge muss projiziert werden';
  assert (select kg_projiziert from v_verlust_ranking where strom = 'Verdunstung') > 0,
    'Die Projektion für die Ware im Lager muss beziffert sein';
  assert (select kg_beobachtet from v_verlust_ranking where strom = 'Verdunstung') > 0,
    'Der beobachtete Anteil muss beziffert sein';

  -- ---- Längere Lagerdauer heißt mehr Verdunstung ---------------------
  assert (select alter_tage from v_hochrechnung
           where charge_nr = 1614 and portion = 'lager' limit 1)
       > (select alter_tage from v_hochrechnung
           where charge_nr = 1613 and portion = 'ausgelagert' limit 1),
    'Die noch lagernde Charge muss bis zum Stichtag älter werden';

  -- ---- Bereiche: unten ≤ mittel ≤ oben -------------------------------
  -- Seit 0019 steht der Bereich nicht mehr aus drei Szenarien, sondern aus
  -- der Fehlerfortpflanzung. Genau daran war der alte Aufbau gescheitert:
  -- bei nachgelagerten Strömen lag „unten" über „oben".
  assert not exists (
    select 1 from v_verlust_ranking
     where kg_unten > kg + 0.01 or kg > kg_oben + 0.01),
    'Der untere Bereich muss unter dem mittleren liegen und dieser unter dem oberen';

  -- ---- Ranking und Bilanz liefern etwas ------------------------------
  assert (select count(*) from v_verlust_ranking where buch = 'verlust') = 3,
    'Drei Verlustströme erwartet';
  assert (select kg from v_verlust_ranking order by kg desc nulls last limit 1) > 0,
    'Der Hauptverlust muss beziffert sein';
  -- Der eigentliche Test der ganzen Kette: das Modell sagt die Masse am
  -- Sortierband voraus, die CSV hat sie gewogen. Beide müssen sich treffen.
  select abweichung_anteil into v from v_massenbilanz where charge_nr = 1613;
  assert v is not null, 'Die Massenbilanz muss die gemessene CSV-Masse kennen';
  assert abs(v) < 0.02,
    format('Modell und CSV weichen um %s %% voneinander ab — die Kaskade rechnet falsch',
           round(v * 100, 1));
  assert (select n_sortierlaeufe from v_datenlage where charge_nr = 1613) = 1, 'Datenlage falsch';

  raise notice 'OK  Kaskade, Bereiche, Ranking, Bilanz';
end $$;

-- Die Auswertung liegt seit 0016 gespeichert vor: nach jeder Erfassung
-- einmal neu rechnen, sonst prüft man den Stand von vorhin.
select auswertung_aktualisieren() \gset stand_

-- =====================================================================
-- Wiegen beim Zählen: gewogene Palette schlägt jede Schätzung (0012)
-- =====================================================================
insert into auftrag (id, weg, station, charge_nr, start_ts)
values (960, 'hand', 'waschen_sortieren', 1613, timestamptz '2026-11-16 08:00+01');

-- Nur gezählt, ohne jede Angabe
insert into auftrag_palette (auftrag_id) values (960);

-- Dieselbe Arbeit, aber diese Palette wurde gewogen:
-- 950 kg brutto beim Eingang, 40 Kisten G2 → Netto damals 950 − 40·1.5 − 25 = 865
with w as (
  insert into verdunstung_wiegung (auftrag_id, charge_nr, eingangsdatum,
         brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, kuerbisse_pro_kiste, wiege_ts)
  values (960, 1613, date '2026-09-01', 950.00, 908.00, 40, 'G2', 6,
          timestamptz '2026-11-16 08:00+01')
  returning id
)
insert into auftrag_palette (auftrag_id, eingangsdatum, wiegung_id)
select 960, date '2026-09-01', id from w;

do $$
declare v numeric; v_quelle text;
begin
  -- Ohne Angaben bleibt nur die Schätzung über das Chargenmittel
  select masse_quelle into v_quelle from v_auftrag_palette_masse
   where auftrag_id = 960 and netto_kg is not null
     and id = (select min(id) from auftrag_palette where auftrag_id = 960);
  assert v_quelle = 'charge-mittel',
    format('Nur gezählt muss geschätzt werden, ist %s', v_quelle);

  -- Die gewogene Palette bringt ihr Eingangsgewicht exakt mit
  select m.netto_kg, m.masse_quelle into v, v_quelle
    from v_auftrag_palette_masse m
    join auftrag_palette ap on ap.id = m.id
   where ap.auftrag_id = 960 and ap.wiegung_id is not null;
  assert v_quelle = 'gewogen',
    format('Eine gewogene Palette muss als „gewogen" gelten, ist %s', v_quelle);
  assert v = 865.00, format('Netto der gewogenen Palette erwartet 865, ist %s', v);

  -- Kennzahlen: netto jetzt = 908 − 40·1.5 − 25 = 823 kg
  select kg_pro_kiste into v from v_wiegung_kennzahl where auftrag_id = 960;
  assert abs(v - 823.0 / 40) < 0.01, format('kg je Kiste erwartet ~20.6, ist %s', v);
  select kg_pro_kuerbis into v from v_wiegung_kennzahl where auftrag_id = 960;
  assert abs(v - 823.0 / 240) < 0.01, format('kg je Kürbis erwartet ~3.43, ist %s', v);
  select verlust_kg into v from v_wiegung_kennzahl where auftrag_id = 960;
  assert v = 42.00, format('Gewichtsverlust erwartet 42 kg, ist %s', v);
  select lagertage into v from v_wiegung_kennzahl where auftrag_id = 960;
  assert v = 76, format('Lagertage erwartet 76, sind %s', v);

  -- Die Wägung zählt auch als Verdunstungsmessung, ohne dass eine Palette
  -- aus der Liste gesucht werden musste
  assert (select count(*) from v_verdunstung_messung
           where auftrag_id = 960 and verwendbar) = 1,
    'Die Wägung muss als verwendbare Verdunstungsmessung ankommen';

  -- Ohne Kürbiszahl bleibt das Durchschnittsgewicht leer statt falsch
  update verdunstung_wiegung set kuerbisse_pro_kiste = null where auftrag_id = 960;
  assert (select kg_pro_kuerbis from v_wiegung_kennzahl where auftrag_id = 960) is null,
    'Ohne Kürbisse je Kiste darf kein Durchschnitt je Kürbis erscheinen';
  assert (select kg_pro_kiste from v_wiegung_kennzahl where auftrag_id = 960) is not null,
    'kg je Kiste muss trotzdem da sein';

  raise notice 'OK  Wiegen beim Zählen (gewogen schlägt geschätzt, Kennzahlen stimmen)';
end $$;

delete from auftrag where id = 960;

-- Die Auswertung liegt seit 0016 gespeichert vor: nach jeder Erfassung
-- einmal neu rechnen, sonst prüft man den Stand von vorhin.
select auswertung_aktualisieren() \gset stand_

-- =====================================================================
-- Fertige Palette: wie viel Kürbis liegt wirklich in einer Kiste? (0013)
-- =====================================================================
insert into auftrag (id, weg, station, charge_nr, start_ts)
values (970, 'hand', 'waschen_sortieren', 1613, timestamptz '2026-11-17 08:00+01');

-- Dein Rechenbeispiel: 32 Kisten G2 (je 1.5 kg), Palette 25 kg.
-- Soll wäre 32 × 8 = 256 kg Kürbis → Brutto 25 + 48 + 256 = 329 kg.
-- Gewogen werden 340 kg → 11 kg mehr → x = 267/32 = 8.34 kg je Kiste.
insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart,
                             kuerbisse_pro_kiste)
values (970, 1613, 340.00, 32, 'G2', 4);

do $$
declare v numeric; v_n int;
begin
  select netto_kg into v from v_ausgang_kennzahl where auftrag_id = 970;
  assert v = 267.00, format('Netto erwartet 340 − 25 − 32·1.5 = 267, ist %s', v);

  select kg_pro_kiste into v from v_ausgang_kennzahl where auftrag_id = 970;
  assert abs(v - 267.0 / 32) < 0.001, format('x erwartet 8.344, ist %s', v);

  select ueberfuellung_je_kiste into v from v_ausgang_kennzahl where auftrag_id = 970;
  assert abs(v - (267.0 / 32 - 8)) < 0.001,
    format('Überschuss je Kiste erwartet 0.344, ist %s', v);

  select ueberfuellung_kg into v from v_ausgang_kennzahl where auftrag_id = 970;
  assert v = 11.00, format('Überschuss gesamt erwartet 11 kg, ist %s', v);

  -- 4 Kürbisse je Kiste → 267 / (32·4) = 2.086 kg je Kürbis
  select kg_pro_kuerbis into v from v_ausgang_kennzahl where auftrag_id = 970;
  assert abs(v - 267.0 / 128) < 0.001, format('kg je Kürbis erwartet 2.086, ist %s', v);

  -- Der Überschuss landet im Marge-Buch, nicht im Verlust-Buch
  select kg_pro_kiste into v from v_koeff_ueberfuellung;
  assert abs(v - 11.0 / 32) < 0.001,
    format('Überfüllungs-Koeffizient erwartet 0.344 kg je Kiste, ist %s', v);
  assert not exists (select 1 from v_hochrechnung
                      where buch = 'verlust' and strom ilike '%%berfüllung%%'),
    'Überfüllung darf niemals als Verlust gezählt werden';

  raise notice 'OK  Fertige Palette (x je Kiste, Überschuss geht ins Marge-Buch)';
end $$;

-- =====================================================================
-- Abbrechen: Zeilen bleiben als Spur, zählen aber nirgends mehr (0013)
-- =====================================================================
do $$
declare v_vorher numeric; v_nachher numeric; v_n int; v_status text;
begin
  -- Eine Arbeit mit Messungen, die anschliessend verworfen wird
  insert into auftrag (id, weg, station, charge_nr, start_ts)
  values (980, 'hand', 'waschen_sortieren', 1613, timestamptz '2026-11-18 08:00+01');
  insert into auftrag_palette (auftrag_id) select 980 from generate_series(1, 3);
  insert into schimmel_messung (auftrag_id, kg) values (980, 40);
  insert into verdunstung_wiegung (auftrag_id, charge_nr, eingangsdatum,
         brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, wiege_ts)
  values (980, 1613, date '2026-09-01', 950, 900, 40, 'G2',
          timestamptz '2026-11-18 08:00+01');
  perform auswertung_aktualisieren();

  assert (select count(*) from v_auftrag_masse where auftrag_id = 980) = 1,
    'Die laufende Arbeit muss in der Auswertung sein';
  assert (select verwendbar from v_verdunstung_messung where auftrag_id = 980),
    'Die Wägung muss zunächst zählen';

  perform auftrag_abbrechen(980, 'Falsche Charge gewählt');
  perform auswertung_aktualisieren();

  -- Verschwindet überall aus der Rechnung …
  assert (select count(*) from v_auftrag_masse where auftrag_id = 980) = 0,
    'Eine abgebrochene Arbeit darf nicht mehr in v_auftrag_masse stehen';
  assert not (select verwendbar from v_verdunstung_messung where auftrag_id = 980),
    'Die Wägung einer abgebrochenen Arbeit darf die Verdunstungsrate nicht beeinflussen';
  assert (select count(*) from v_wiegung_kennzahl where auftrag_id = 980) = 0,
    'Abgebrochene Wägungen gehören nicht in die Kennzahlen';
  assert (select count(*) from v_schimmel_beobachtung where auftrag_id = 980) = 0,
    'Abgebrochener Schimmel darf nicht in die Kurve';

  -- … die Zeilen bleiben aber als Spur stehen
  assert (select count(*) from auftrag_palette where auftrag_id = 980) = 3,
    'Die Erfassungen sollen als Spur erhalten bleiben';
  assert (select abbruch_grund from auftrag where id = 980) = 'Falsche Charge gewählt',
    'Der Grund muss festgehalten werden';

  raise notice 'OK  Abbrechen (aus der Rechnung raus, als Spur erhalten)';
end $$;

-- Endgültig löschen räumt auch die Tabellen mit "on delete set null" auf
do $$
declare v_n int;
begin
  perform auftrag_endgueltig_loeschen(980);

  assert (select count(*) from auftrag where id = 980) = 0, 'Auftrag muss weg sein';
  assert (select count(*) from auftrag_palette where auftrag_id = 980) = 0,
    'Gezählte Paletten müssen mitgelöscht werden (cascade)';
  -- Der eigentliche Punkt: ohne Aufräumen bliebe diese Zeile verwaist zurück
  -- (auftrag_id würde nur auf NULL gesetzt) und zählte weiter mit.
  select count(*) into v_n from verdunstung_wiegung
   where auftrag_id is null and eingangsdatum = date '2026-09-01'
     and brutto_jetzt_kg = 900;
  assert v_n = 0, 'Beim Löschen darf keine verwaiste Wägung zurückbleiben';

  raise notice 'OK  Endgültig löschen (keine verwaisten Wägungen)';
end $$;

-- Die Auswertung liegt seit 0016 gespeichert vor: nach jeder Erfassung
-- einmal neu rechnen, sonst prüft man den Stand von vorhin.
select auswertung_aktualisieren() \gset stand_

-- =====================================================================
-- Plausibilität: ein vertippter Wert darf die Rechnung nicht umwerfen (0011)
-- =====================================================================
do $$
declare v numeric; v_n int;
begin
  -- 5000 kg Schimmel auf einer Charge mit 8650 kg Eingang: physisch möglich?
  -- Nein — die Charge ist zu diesem Zeitpunkt längst kleiner. Vor dem Fix
  -- erzeugte so ein Tippfehler negative „verkaufsfähige" Masse.
  insert into auftrag (id, weg, station, charge_nr, start_ts)
  values (950, 'hand', 'waschen_sortieren', 1614, timestamptz '2026-11-20 08:00+01');
  insert into auftrag_palette (auftrag_id, palette_id)
  select 950, id from palette where charge_nr = 1614;
  insert into schimmel_messung (auftrag_id, kg) values (950, 99000);
  perform auswertung_aktualisieren();

  assert not (select plausibel from v_schimmel_beobachtung where auftrag_id = 950),
    'Ein Schimmelanteil weit über 100 % muss als unplausibel erkannt werden';

  -- Der Unsinn darf nicht in die Kurve und nicht in die Kaskade gelangen
  assert schimmelanteil(200) <= 1, 'schimmelanteil() darf nie über 1 liegen';
  assert not exists (select 1 from v_kaskade where m2 < 0),
    'Keine negative Masse nach dem Schimmel-Schritt';
  assert not exists (select 1 from v_kaskade where verkaufsfaehig_kg < -0.01),
    'Keine negative verkaufsfähige Masse';
  assert not exists (select 1 from v_hochrechnung where kg < -0.01),
    'Kein Strom darf negativ werden';

  -- Aber: der Befund muss dem Betriebsleiter gemeldet werden
  select count(*) into v_n from v_plausibilitaet where auftrag_id = 950;
  assert v_n >= 1, 'Die unplausible Messung muss in v_plausibilitaet auftauchen';

  -- Auch als marge_messung(nebenkanal) erfasste Mengen dürfen nicht spurlos
  -- verschwinden — keine Auswertung liest sie.
  insert into marge_messung (auftrag_id, art, wert) values (950, 'nebenkanal', 42);
  perform auswertung_aktualisieren();
  assert exists (select 1 from v_plausibilitaet
                  where auftrag_id = 950 and art = 'Nicht ausgewertet'),
    'Nicht ausgewertete Erfassungen müssen gemeldet werden';

  delete from marge_messung where auftrag_id = 950;
  delete from schimmel_messung where auftrag_id = 950;
  delete from auftrag where id = 950;
  raise notice 'OK  Plausibilität (Tippfehler bricht die Rechnung nicht, wird gemeldet)';
end $$;

-- =====================================================================
-- Anonyme Arbeiter (QR-Code-Anmeldung, Migration 0009)
-- =====================================================================
do $$
declare v_name text; v_anonym boolean;
begin
  -- Arbeiter ohne Konto: keine E-Mail, Name aus den Metadaten
  insert into auth.users (id, email, raw_user_meta_data)
  values ('33333333-3333-3333-3333-333333333333', null, '{"name":"Hans im Feld"}');
  select name, anonym into v_name, v_anonym from profil
   where id = '33333333-3333-3333-3333-333333333333';
  assert v_name = 'Hans im Feld', format('Name der anonymen Anmeldung falsch: %s', v_name);
  assert v_anonym, 'Ein Nutzer ohne E-Mail muss als anonym markiert sein';

  -- Ganz ohne Namen darf die Anmeldung nicht scheitern → Rückfall auf "Gast"
  insert into auth.users (id, email, raw_user_meta_data)
  values ('44444444-4444-4444-4444-444444444444', null, '{}');
  select name into v_name from profil where id = '44444444-4444-4444-4444-444444444444';
  assert v_name = 'Gast', format('Namensloser Nutzer muss "Gast" heißen, ist %s', v_name);

  -- Der Betriebsleiter mit E-Mail bleibt nicht-anonym
  assert not (select anonym from profil where id = '11111111-1111-1111-1111-111111111111'),
    'Ein Konto mit E-Mail darf nicht als anonym gelten';

  raise notice 'OK  Anonyme Arbeiter (Name, Gast-Rückfall, anonym-Kennzeichen)';
end $$;

-- =====================================================================
-- Row Level Security aus Sicht eines Arbeiters
-- =====================================================================
do $$
declare v_ok boolean;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);

  -- lesen darf er
  perform 1 from v_verlust_ranking;
  perform 1 from charge;

  -- Stammdaten ändern nicht
  begin
    insert into charge (nr, schlag, sorte, saison) values (9999, 'Heimlich', 'Tiana', 2026);
    raise exception 'Arbeiter durfte eine Charge anlegen — Policy greift nicht';
  exception when insufficient_privilege then null; end;

  -- sich selbst zum Chef machen auch nicht
  begin
    update profil set rolle = 'admin' where id = '22222222-2222-2222-2222-222222222222';
    raise exception 'Arbeiter durfte sich selbst zum Admin machen';
  exception when raise_exception then
    if sqlerrm not like '%Betriebsleiter%' then raise; end if;
  end;

  -- Messungen erfassen darf er
  insert into schimmel_messung (auftrag_id, kg) values (900, 5);

  -- CSV hochladen nicht
  begin
    insert into sortier_lauf (charge_nr, datei_name, reinigung, n_roh, n_overflow,
                              n_klein, n_dubletten, n_gueltig)
    values (1613, 'geschummelt', '{}'::jsonb, 1, 0, 0, 0, 1);
    raise exception 'Arbeiter durfte einen Sortierlauf anlegen';
  exception when insufficient_privilege then null; end;

  reset role;
  raise notice 'OK  Row Level Security (Arbeiter darf messen, nicht verwalten)';
end $$;


-- =========================================================================
-- Fixtur für die Modellprüfung: Ohne Messungen aus mehreren Chargen über
-- verschiedene Lagerdauern lässt sich kein Verlauf anpassen — dann greift
-- (richtigerweise) die Treppenfunktion und die Prüfungen unten liefen ins
-- Leere. Hier werden drei Chargen mit je fünf Arbeiten über 30–210 Tage
-- angelegt, deren Schimmelmengen einem bekannten Verlauf folgen:
--   F(t) = 1 − exp(−1.07e-5 · t^1.6)
-- Das ist dieselbe Form, die das Modell annimmt. Geprüft wird damit nicht,
-- ob die Annahme stimmt (das misst der Simulations-Harness), sondern ob die
-- Anpassung sie zurückgewinnt und richtig fehlerbehaftet.
-- =========================================================================
insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart)
select c.nr, date '2026-09-01', 865 + 38 * 1.5 + 25, 38, 'G2'
  from (values (1603), (1604), (1606)) c(nr)
 cross join generate_series(1, 30);

insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status)
select 2000 + row_number() over (order by c.nr, t.tage),
       'maschine', 'sortieren', c.nr,
       (date '2026-09-01' + t.tage)::timestamptz + interval '8 hours',
       (date '2026-09-01' + t.tage)::timestamptz + interval '15 hours',
       'abgeschlossen'
  from (values (1603), (1604), (1606)) c(nr)
 cross join (values (30), (75), (120), (165), (210)) t(tage);

-- Eine Zeile je gezählter Palette; sechs Paletten je Arbeit.
insert into auftrag_palette (auftrag_id, eingangsdatum)
select a.id, date '2026-09-01'
  from auftrag a cross join generate_series(1, 6)
 where a.id between 2001 and 2015;

-- Schimmelmenge nach dem bekannten Verlauf, bezogen auf die Masse nach
-- Verdunstung. Ohne Rauschen: der Test prüft die Rechnung, nicht die Streuung.
insert into schimmel_messung (auftrag_id, kg)
select a.id,
       round(6 * 865 * power(1 - 0.0006, t.tage)
             * (1 - exp(-0.0000107 * power(t.tage, 1.6))))
  from auftrag a
  cross join lateral (select (a.start_ts::date - date '2026-09-01') as tage) t
 where a.id between 2001 and 2015;

-- Die Auswertung liest gespeicherte Ansichten; ohne Neuberechnung sieht sie
-- von der Fixtur nichts.
select auswertung_aktualisieren();

-- =========================================================================
-- Statistik: was die Überprüfung von 0017–0022 nachgewiesen hat, bleibt
-- nachgewiesen. Diese Blöcke prüfen keine Zahlen aus der Simulation, sondern
-- die Eigenschaften, aus denen sie folgen — die halten auch auf echten Daten.
-- =========================================================================

do $$
declare v_f30 numeric; v_f90 numeric; v_f200 numeric;
        v_brauchbar boolean; v_smearing numeric;
begin
  select brauchbar, smearing into v_brauchbar, v_smearing from v_schimmel_modell;
  assert v_brauchbar, 'Das Verderbsmodell lässt sich mit den Testdaten nicht anpassen';

  -- Der Kern von 0017: der Verlauf steigt über die längste gemessene
  -- Lagerdauer hinaus weiter. Die alte Treppenfunktion lief hier flach —
  -- das war die −46-%-Verzerrung bei halb vollem Lager.
  v_f30  := schimmelanteil(30);
  v_f90  := schimmelanteil(90);
  v_f200 := schimmelanteil(200);
  assert v_f30 < v_f90 and v_f90 < v_f200,
         format('Schimmelverlauf steigt nicht: 30 T = %s, 90 T = %s, 200 T = %s',
                v_f30, v_f90, v_f200);
  assert v_f200 > v_f90 * 1.2,
         format('Bei 200 Tagen kaum mehr Schimmel als bei 90 — wird wieder flach '
                || 'fortgeschrieben? (%s vs. %s)', v_f200, v_f90);

  -- Duan-Smearing: Rücktransformation aus dem Log-Raum. Unter 1 wäre falsch
  -- herum, über 2 wäre kein Korrekturfaktor mehr, sondern ein Symptom.
  assert v_smearing >= 1.0 and v_smearing < 2.0,
         format('Smearing-Faktor unplausibel: %s', v_smearing);

  -- Der Bereich muss dort breiter werden, wo extrapoliert wird.
  assert (schimmelanteil(200, 'oben') - schimmelanteil(200, 'unten'))
       > (schimmelanteil(60, 'oben') - schimmelanteil(60, 'unten')),
         'Der Bereich wird beim Hochrechnen nicht breiter — die Unsicherheit '
         || 'der Extrapolation fehlt';

  raise notice 'OK  Verderbsmodell (steigt, korrigiert zurück, wird unsicherer)';
end $$;

do $$
declare v_n int; v_c int;
begin
  -- 0017/0018: Messungen aus derselben Charge sind keine unabhängigen
  -- Beobachtungen. Wenn c_chargen wieder gleich n wäre, zählte jemand
  -- Messungen statt Gruppen — das war der 31-fach zu kleine Fehler.
  select n, c_chargen into v_n, v_c from v_schimmel_modell;
  assert v_c <= v_n, 'Mehr Chargen als Messungen — das kann nicht sein';
  assert v_c >= 3, format('Nur %s Chargen im Modell — der Fehler ist so nicht '
                          || 'schätzbar', v_c);

  -- Die Freiheitsgrade folgen den Chargen, nicht den Messungen.
  assert (select t_faktor from v_schimmel_modell) = t_quantil_95(v_c - 1),
         'Der t-Faktor passt nicht zur Zahl der Chargen';
  raise notice 'OK  Fehler folgt den Chargen, nicht der Zahl der Messungen';
end $$;

do $$
declare r record;
begin
  perform auswertung_aktualisieren();

  -- 0019: Der Befund, der die drei Szenarien erledigt hat. Bei nachgelagerten
  -- Strömen stand kg_unten über kg_oben, weil „unten" alle Koeffizienten
  -- gleichzeitig senkte und damit die Masse *erhöhte*, aus der sie rechnen.
  for r in select strom, kg, kg_unten, kg_oben from v_verlust_ranking loop
    assert r.kg_unten <= r.kg, format('%s: Untergrenze %s über dem Wert %s',
                                      r.strom, r.kg_unten, r.kg);
    assert r.kg_oben >= r.kg,  format('%s: Obergrenze %s unter dem Wert %s',
                                      r.strom, r.kg_oben, r.kg);
  end loop;

  -- Und der Fehler muss überhaupt ankommen: ein Strom ohne jede Streuung
  -- wäre eine Zahl ohne Aussage.
  assert (select count(*) from v_verlust_ranking where coalesce(streuung_kg, 0) > 0) >= 2,
         'Kein einziger Strom hat eine Streuung — die Fortpflanzung greift nicht';
  raise notice 'OK  Fortgepflanzter Bereich (Grenzen in der richtigen Reihenfolge)';
end $$;

do $$
declare v_ohne numeric; v_mit numeric;
begin
  -- 0018: Eine Sorte ohne eigene Messung bekommt den Gesamtwert, nicht 0.
  -- Der Fehler hat in der Simulation 37 % der Verdunstung verschluckt.
  assert not exists (select 1 from v_koeff_verdunstung
                      where mittel = 0 and basis <> 'keine Wiegung vorhanden'),
         'Eine Sorte mit Messungen hat den Koeffizienten 0 — Bündelung greift nicht';
  assert not exists (select 1 from v_koeff_ausschuss
                      where mittel = 0 and basis <> 'keine Messung vorhanden'),
         'Eine Sorte mit Messungen hat Ausschuss 0 — Bündelung greift nicht';

  -- Der gebündelte Wert liegt immer zwischen eigenem und gemeinsamem Wert.
  assert not exists (
    select 1 from v_koeff_kaliber_geschaetzt
     where mittel_roh is not null and mittel_gesamt is not null
       and (mittel > greatest(mittel_roh, mittel_gesamt) + 1e-9
         or mittel < least(mittel_roh, mittel_gesamt) - 1e-9)),
    'Ein gebündelter Koeffizient liegt ausserhalb von eigenem und Gesamtwert';
  raise notice 'OK  Teilbündelung (kein Sprung, keine Sorte auf 0)';
end $$;

do $$
declare v_eingang numeric; v_gemessen numeric; v_n int; v_n_netto int;
begin
  -- 0021: Fehlende Tara darf die Charge nicht kleiner machen.
  select eingang_netto_kg, eingang_netto_gemessen_kg, n_paletten, n_paletten_mit_netto
    into v_eingang, v_gemessen, v_n, v_n_netto
    from v_charge_rueckgrat where eingang_netto_kg is not null
   order by charge_nr limit 1;
  assert v_eingang >= v_gemessen - 1e-6,
         'Die hochgerechnete Eingangsmasse liegt unter der gemessenen';
  if v_n = v_n_netto then
    assert abs(v_eingang - v_gemessen) < 1e-6,
           'Ohne fehlende Tara darf die Hochrechnung nichts ändern';
  end if;
  raise notice 'OK  Fehlende Tara wird hochgerechnet statt verschluckt';
end $$;

select '——— Statistik geprüft ———' as ergebnis;


-- =========================================================================
-- Ablauf: Weg 1 hat zwei Lagerabschnitte. Das war der grösste Fehler der
-- Überarbeitung von 0024–0026 — geprüft wird hier nicht das Ergebnis der
-- Simulation, sondern die Eigenschaften, aus denen es folgt.
-- =========================================================================

do $$
declare v_sort record; v_wasch bigint; v_punkte int; v_lager numeric; v_wartet numeric;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  select auftrag_id, charge_nr, start_ts, eingang_netto_kg into v_sort
    from v_auftrag_masse where station = 'sortieren' order by auftrag_id limit 1;
  if v_sort.auftrag_id is null then
    raise notice 'ÜBERSPRUNGEN  Weg 1 (kein Sortier-Auftrag in der Fixtur)';
    return;
  end if;

  select lager_kg into v_lager from v_hochrechnung_basis where charge_nr = v_sort.charge_nr;

  -- Ein Waschgang, 60 Tage nach dem Sortieren, mit Schimmel #2.
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status,
                       durchsatz_kg, bemerkung)
  values ('maschine', 'waschen', v_sort.charge_nr,
          v_sort.start_ts + interval '60 days',
          v_sort.start_ts + interval '60 days 7 hours', 'abgeschlossen',
          v_sort.eingang_netto_kg * 0.9, 'PRUEFUNG')
  returning id into v_wasch;
  insert into schimmel_messung (auftrag_id, kg, palox_stand_kg)
  values (v_wasch, 120, 120);

  perform auswertung_aktualisieren();

  -- Ohne Paletten zu zählen muss die Lagerdauer trotzdem bekannt sein, sonst
  -- fällt Schimmel #2 aus dem Modell — genau das ist vor 0024 passiert.
  assert (select lagertage from v_auftrag_masse where auftrag_id = v_wasch) is not null,
    'Ein Wasch-Auftrag hat keine Lagerdauer — Schimmel #2 fällt aus der Auswertung';
  assert (select lagertage from v_auftrag_masse where auftrag_id = v_wasch)
       > (select lagertage from v_auftrag_masse where auftrag_id = v_sort.auftrag_id),
    'Beim Waschen muss die Ware älter sein als beim Sortieren';

  select count(*) into v_punkte from v_schimmel_punkte where auftrag_id = v_wasch;
  assert v_punkte = 1, format('Schimmel #2 erzeugt %s Punkte statt 1', v_punkte);

  -- Der Waschen-Punkt ist ein kumulativer Anteil: er muss mindestens so gross
  -- sein wie der der Charge beim Sortieren.
  assert (select anteil from v_schimmel_punkte where auftrag_id = v_wasch)
       >= coalesce((select anteil from v_schimmel_punkte
                     where auftrag_id = v_sort.auftrag_id), 0) - 1e-9,
    'Der kumulative Anteil beim Waschen liegt unter dem beim Sortieren';

  -- Sortierte, aber noch nicht gewaschene Ware bleibt Bestand.
  select wartet_kg into v_wartet from v_hochrechnung_basis where charge_nr = v_sort.charge_nr;
  assert v_wartet >= 0, 'Wartende Menge darf nicht negativ sein';
  assert (select lager_kg from v_hochrechnung_basis where charge_nr = v_sort.charge_nr)
       >= v_wartet - 1e-6,
    'Was aufs Waschen wartet, muss im Bestand enthalten sein';

  raise notice 'OK  Weg 1 zweistufig (Schimmel #2 kommt an, Wartendes bleibt Bestand)';
end $$;

do $$
declare v_hand bigint; v_diff numeric;
begin
  -- 0027/0032: Der Arbeiter trägt den Waagenstand ein, die Differenz rechnet
  -- die Software — und zwar je Station: Sortierband, Waschbecken und
  -- Hand-Linie haben je einen eigenen Palox auf eigener Waage. Vor 0032 war
  -- der Stand global; liefen zwei Linien gleichzeitig, verzahnten sich ihre
  -- Ablesungen und jede Differenz war falsch.
  assert (select count(*) from v_palox_stand where differenz < 0) = 0,
    'Eine Palox-Differenz ist negativ — der Stand wurde falsch verrechnet';
  assert palox_letzter_stand('waschen') is not null,
    'Der letzte Waagenstand ist nicht abrufbar — die Eingabemaske kann nicht rechnen';

  -- Eine Ablesung auf der Hand-Linie darf den Stand der Wasch-Station nicht
  -- verschieben: 30 kg auf der Hand-Waage sind keine Differenz zu 120 kg auf
  -- der Wasch-Waage.
  insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status)
  values (2100, 'hand', 'waschen_sortieren', 1613,
          now() - interval '2 hours', now(), 'abgeschlossen');
  insert into schimmel_messung (auftrag_id, kg, palox_stand_kg)
  values (2100, 30, 30);
  assert palox_letzter_stand('waschen') = 120,
    'Der Hand-Palox hat den Stand der Wasch-Station verschoben — je Station!';
  assert (select differenz from v_palox_stand where auftrag_id = 2100) = 30,
    'Die erste Ablesung einer Station muss selbst die Menge sein';

  -- Geleert und über den alten Stand hinaus neu befüllt: die Zahlenreihe
  -- sieht harmlos aus (30 → 45), nur das Häkchen des Arbeiters weiss es.
  insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert)
  values (2100, 45, 45, true);
  select differenz into v_diff from v_palox_stand
   where auftrag_id = 2100 order by ts desc, id desc limit 1;
  assert v_diff = 45,
    format('Nach dem Leeren gilt der volle Stand als Menge, nicht die Differenz (%s)', v_diff);

  raise notice 'OK  Palox-Waage (je Station, Leeren gemeldet, ablesen statt kopfrechnen)';
end $$;

do $$
declare v_zeile record;
begin
  -- 0033: Was kostet Warten? Für jede liegende Charge der voraussichtliche
  -- Verlust zweier weiterer Wochen. Die Grössen müssen zusammenpassen:
  -- nie negativ, Summe = Teile, und ohne tragfähiges Modell ehrlich NULL.
  assert not exists (select 1 from v_naechste_charge
                      where verdunstung_14_kg < 0 or schimmel_14_kg < 0),
    'Ein projizierter Verlust ist negativ';
  assert not exists (select 1 from v_naechste_charge
                      where abs(coalesce(verdunstung_14_kg,0) + coalesce(schimmel_14_kg,0)
                                - verlust_14_kg) > 0.5),
    'Die Verlustsumme entspricht nicht ihren Teilen';
  assert not exists (select 1 from v_naechste_charge where masse_jetzt_kg > lager_kg + 0.01),
    'Die heutige Masse liegt über dem Eingang — Verdunstung rückwärts?';
  raise notice 'OK  Was kostet Warten (nie negativ, Summe stimmt, ehrlich bei dünnem Modell)';
end $$;

do $$
declare v record; v_vorher numeric; v_nachher numeric;
begin
  -- 0028/0029: Der Warenausgang schliesst die Bilanz. Ohne Lieferungen muss
  -- die Ansicht das sagen, statt eine Lücke auszuweisen, die nichts bedeutet.
  select * into v from v_saisonbilanz;
  assert v.n_lieferungen = 0, 'Die Fixtur sollte noch keine Lieferungen haben';
  assert v.befund like '%Kein Warenausgang%',
    'Ohne Lieferungen muss die Bilanz sagen, dass sie nichts prüfen kann';
  v_vorher := v.ausgang_kg;

  -- Eine Lieferung in Kilo
  insert into lieferung (datum, sorte, kg, ziel)
  values (current_date, 'Tiana', 5000, 'verkauf');
  -- Eine in Kisten — muss über das gemessene Kilo je Kiste umgerechnet werden
  insert into lieferung (datum, sorte, kisten, ziel)
  values (current_date, 'Tiana', 100, 'verkauf');

  select * into v from v_saisonbilanz;
  assert v.n_lieferungen = 2, 'Beide Lieferungen müssen in der Bilanz stehen';
  assert v.ausgang_kg > v_vorher + 4999,
    format('Der Ausgang ist nur um %s kg gewachsen', round(v.ausgang_kg - v_vorher));

  -- Kilo-Angaben sind gewogen, Kistenangaben hochgerechnet — und das muss
  -- dranstehen, sonst sieht eine Umrechnung aus wie eine Messung.
  assert (select masse_quelle from v_lieferung_masse where kg is not null limit 1) = 'gewogen',
    'Eine Kilo-Angabe darf nicht als hochgerechnet gelten';
  assert (select masse_fehler_kg from v_lieferung_masse where kg is not null limit 1) = 0,
    'Eine gewogene Lieferung hat keinen Umrechnungsfehler';

  -- Ziel entscheidet über das Buch: Kompost ist Verlust, Tierfutter nicht.
  assert (select buch from ausgang_ziel where code = 'kompost') = 'verlust',
    'Kompost gehört ins Verlust-Buch';
  assert (select buch from ausgang_ziel where code = 'tierfutter') = 'marge',
    'Tierfutter ist kein physischer Verlust — es hat einen anderen Kanal';

  delete from lieferung;
  raise notice 'OK  Warenausgang (Kilo und Kisten, Ziel bestimmt das Buch)';
end $$;

do $$
declare v_versatz numeric;
begin
  -- 0032: Der Selektionszuschlag darf nur feuern, wenn es Lagerkontrollen gibt
  -- und der Unterschied grösser ist als sein eigenes Rauschen. Sonst würde
  -- jeder Bereich grundlos aufgeblasen.
  select selektions_versatz into v_versatz from v_schimmel_modell;
  assert v_versatz is null,
    'Ohne Lagerkontrollen darf es keinen Selektionszuschlag geben';
  assert (select befund from v_selektionsverdacht) like '%nicht prüfbar%',
    'Ohne Lagerkontrollen muss das Dashboard sagen, dass Selektion nicht prüfbar ist';

  -- Und die Grenzen bleiben in der richtigen Reihenfolge, mit wie ohne Zuschlag.
  assert not exists (select 1 from v_verlust_ranking where kg_unten > kg or kg > kg_oben),
    'Der Selektionszuschlag hat die Grenzen verdreht';
  raise notice 'OK  Selektionszuschlag (feuert nur mit Beleg)';
end $$;

select '——— Ablauf geprüft ———' as ergebnis;

select '——— Fachlogik geprüft ———' as ergebnis;
