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
      select distinct charge_nr, portion from v_hochrechnung where szenario = 'mittel'
  loop
    select sum(kg), max(portion_kg) into v_summe, v from v_hochrechnung
     where szenario = 'mittel' and charge_nr = v_kaskade.charge_nr
       and portion = v_kaskade.portion;
    assert abs(v_summe - v) < 0.01,
      format('Charge %s / %s: Ströme (%s kg) teilen die Portion (%s kg) nicht auf',
             v_kaskade.charge_nr, v_kaskade.portion, round(v_summe, 2), round(v, 2));
  end loop;

  -- ---- Beide Portionen kommen vor: beobachtet und projiziert ---------
  assert (select count(*) from v_hochrechnung
           where charge_nr = 1613 and portion = 'ausgelagert') > 0,
    'Die vollständig verarbeitete Charge muss als beobachtet erscheinen';
  assert (select count(*) from v_hochrechnung
           where charge_nr = 1613 and portion = 'lager') = 0,
    'Eine vollständig verarbeitete Charge hat keinen Lagerbestand mehr';
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
  assert not exists (
    select 1 from (
      select strom, sum(kg) filter (where szenario='unten')  u,
                    sum(kg) filter (where szenario='mittel') m,
                    sum(kg) filter (where szenario='oben')   o
        from v_hochrechnung where buch = 'verlust' group by strom) t
     where u > m + 0.01 or m > o + 0.01),
    'Der untere Bereich muss unter dem mittleren liegen und dieser unter dem oberen';

  -- ---- Ranking und Bilanz liefern etwas ------------------------------
  assert (select count(*) from v_verlust_ranking) = 3, 'Drei Verlustströme erwartet';
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

select '——— Fachlogik geprüft ———' as ergebnis;
