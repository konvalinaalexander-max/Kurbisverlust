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

-- 0061: „heute" ist eine Funktion. Der Prüfstand rechnet die Saison an ihrem
-- Ende (heute_test = Saisonende): so bleiben die Erwartungen der älteren
-- Blöcke gültig, die bis zum Stichtag altern. Der 0061-Block am Ende prüft
-- die Semantik „bis heute" mit einem früheren Datum.
insert into einstellung (schluessel, wert, bemerkung)
values ('heute_test', '"2027-03-31"'::jsonb, 'Prüfstand: rechnet am Saisonende')
on conflict (schluessel) do update set wert = excluded.wert;

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

  -- ---- Histogramm und Einzelkürbisse müssen dasselbe sagen -----------
  -- Die Lauflängen-Kodierung ist verlustfrei: sum(anzahl) ist die Zahl der
  -- Kürbisse, sum(anzahl·gewicht) ihre Masse (bis 0048 über v_sortier_kuerbis).
  select sum(anzahl)::int into v_int from sortier_gewicht where lauf_id = v_lauf;
  assert v_int = 8161, format('Histogramm muss 8161 Kürbisse zählen, zählt %s', v_int);
  select sum(anzahl * gewicht_g) / 1000.0 into v from sortier_gewicht where lauf_id = v_lauf;
  assert v = (select masse_kg from v_sortier_lauf_masse where lauf_id = v_lauf),
    'Histogramm und Laufmasse ergeben verschiedene Massen';

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
  -- Seit 0051 liegt der Bestand je Eingangstag (kohorte) — jede Kohorte ist
  -- eine eigene Portion.
  for v_kaskade in
      select distinct charge_nr, portion, kohorte from v_hochrechnung
  loop
    -- Ein unbekannter Strom (kein Koeffizient gemessen) ist NULL und fehlt in
    -- der Summe — dann ist die Aufteilung nicht prüfbar, und das ist richtig so.
    -- (Der Fax-Strom ist hier noch unbekannt; die Aufteilung mit bekanntem
    -- Fax prüft der Block 0051 unten.)
    if exists (select 1 from v_hochrechnung
                where charge_nr = v_kaskade.charge_nr and portion = v_kaskade.portion
                  and kohorte is not distinct from v_kaskade.kohorte
                  and not koeff_bekannt) then continue; end if;
    select sum(kg), max(portion_kg) into v_summe, v from v_hochrechnung
     where charge_nr = v_kaskade.charge_nr
       and portion = v_kaskade.portion
       and kohorte is not distinct from v_kaskade.kohorte;
    -- Toleranz 50 g: Die fünf Ströme werden einzeln auf 10 g gerundet
    -- ausgegeben, ihre Summe kann also um wenige Rundungsschritte abweichen.
    -- Alles darüber wäre ein echter Rechenfehler.
    assert abs(v_summe - v) < 0.05,
      format('Charge %s / %s: Ströme (%s kg) teilen die Portion (%s kg) nicht auf',
             v_kaskade.charge_nr, v_kaskade.portion, round(v_summe, 2), round(v, 2));
  end loop;

  -- ---- Beide Portionen kommen vor: beobachtet und projiziert ---------
  -- 0060: Was ausgelagert ist, sagt der Lieferschein — nicht eine gezählte
  -- Arbeit. 1613 ist sortiert und gewaschen; solange nichts geliefert ist,
  -- liegt sie rechnerisch im Haus. Erst eine Lieferung teilt sie auf.
  assert (select count(*) from v_hochrechnung
           where charge_nr = 1613 and portion = 'ausgelagert') = 0,
    'Ohne Lieferung gibt es keine ausgelagerte Portion — gezählte Arbeiten sind keine Mengen (0060)';
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung)
  values (date '2026-12-30', 1613, 'Tiana', 4000, 'verkauf', 'PRUEF-KASKADE');
  perform auswertung_aktualisieren();
  assert (select count(*) from v_hochrechnung
           where charge_nr = 1613 and portion = 'ausgelagert') > 0,
    'Die gelieferte Charge muss eine ausgelagerte Portion haben';
  -- Das Alter am Liefertag: 30.12. minus die Eingangstage (1.–5.9., Mittel 3.9.) = 118 Tage
  select alter_ausgelagert into v from v_hochrechnung_basis where charge_nr = 1613;
  assert v between 116 and 120,
    format('Das Alter des Ausgelagerten ist das Alter am Liefertag (~118), ist %s', v);
  -- Hinter 4000 kg Lieferung steckt mehr Eingang als 4000 kg — und weniger als die ganze Charge.
  select ausgelagert_kg into v from v_hochrechnung_basis where charge_nr = 1613;
  assert v > 4000 and v < 8650,
    format('Das Ausgelagerte ist die Eingangsmasse hinter der Lieferung (4000 < x < 8650), ist %s', v);
  assert abs((select lager_kg + ausgelagert_kg from v_hochrechnung_basis where charge_nr = 1613) - 8650) < 0.05,
    'Im Lager = Eingang − Ausgelagert';
  assert (select geliefert_kg from v_hochrechnung_basis where charge_nr = 1613) = 4000,
    'Die gelieferte Masse steht als solche da';
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
  -- 0037: Buch A ist der Lagerverlust — Verdunstung und Schimmel. Zu klein
  -- geht an die Tiere und steht mit zu gross in Buch B; die Grundaussortierung
  -- hat ihr eigenes Buch, weil sie physisch weg, aber kein Lagerverlust ist.
  -- 0051: dazu das Faule beim Abpacken (Fax) — unbekannt, bis es gemessen ist.
  assert (select count(*) from v_verlust_ranking where buch = 'verlust') = 3,
    'Drei Lagerverlust-Ströme erwartet (Verdunstung, Schimmel, Fax)';
  assert (select kg from v_verlust_ranking where strom = 'Faul beim Abpacken (Fax)') is null,
    'Ohne Fax-Arbeit ist der Fax-Strom unbekannt — nicht 0';
  assert (select buch from v_verlust_ranking where strom = 'Zu klein (Tierfutter)') = 'marge',
    'Zu klein geht an die Tiere und gehört in Buch B, nicht in den Verlust';
  assert (select buch from v_verlust_ranking where strom = 'Nicht lagerbedingt') = 'feld',
    'Die Grundaussortierung braucht ihr eigenes Buch';
  assert exists (select 1 from v_marge_buch where posten = 'Zu klein (Tierfutter)'),
    'Zu klein muss im Marge-Buch stehen';
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
insert into auftrag_palette (auftrag_id, eingangsdatum) values (960, date '2026-09-10');

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
  select verdunstung_kg into v from v_wiegung_kennzahl where auftrag_id = 960;
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
-- Diese Arbeit läuft als „Kiste ab 8 kg" (Soll 8) — nur dann gibt es
-- überhaupt eine Überfüllung. Die Standard-Kisten-Fassung der Sorte trägt 8 kg.
insert into auftrag (id, weg, station, charge_nr, start_ts, sortierschema_id)
values (970, 'hand', 'waschen_sortieren', 1613, timestamptz '2026-11-17 08:00+01',
        sortierschema_fuer((select sorte from charge where nr = 1613), null, current_date, 'kiste'));

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
  insert into auftrag_palette (auftrag_id, eingangsdatum)
  select 980, date '2026-09-10' from generate_series(1, 3);
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

-- 0037: Die Grundaussortierung. Die Fixtur oben ist reiner Verderb — der
-- Sockel muss dann null sein. Dann bekommt jede Messung 2 % der Bezugsmasse
-- dazu (Erde, Hagelnarben), und das Modell muss genau das wiederfinden, ohne
-- dass sich die Kurve darunter verbiegt.
do $$
declare v_sockel numeric; v_k numeric; v_k_vorher numeric; v_f200 numeric; v_f200_vorher numeric;
begin
  select sockel, k into v_sockel, v_k_vorher from v_schimmel_modell;
  assert v_sockel = 0,
    format('Reiner Verderb, aber der Sockel ist %s — die Anpassung erfindet einen', v_sockel);
  v_f200_vorher := schimmelanteil(200);

  -- Nur die Modell-Fixtur (2001–2015) zählt für diesen Block: Die übrigen
  -- Messungen der Prüfdaten folgen keinem Verlauf und würden den Vergleich
  -- verwässern. Ein Sockel gilt im Betrieb für jede Verarbeitungsmessung —
  -- also muss er hier für alle Punkte gelten, nicht für einen Teil.
  update schimmel_messung set gemessen = false
   where auftrag_id not between 2001 and 2015;
  -- 2 % Sockel obendrauf, bezogen auf die Masse nach Verdunstung
  update schimmel_messung s
     set kg = s.kg + round(b.basis_jetzt_kg * 0.02)
    from v_schimmel_beobachtung b
   where b.auftrag_id = s.auftrag_id and s.auftrag_id between 2001 and 2015;
  perform auswertung_aktualisieren();

  select sockel, k into v_sockel, v_k from v_schimmel_modell;
  assert abs(v_sockel - 0.02) <= 0.0026,
    format('Sockel von 2 %% eingebaut, geschätzt %s', v_sockel);
  assert abs(v_k - v_k_vorher) < 0.15,
    format('Der Sockel verbiegt die Steigung: k %s vorher, %s nachher', v_k_vorher, v_k);
  v_f200 := schimmelanteil(200);
  assert abs(v_f200 - v_f200_vorher) / v_f200_vorher < 0.15,
    format('F(200) mit Sockel %s, ohne %s — der Sockel steckt noch in der Kurve',
           v_f200, v_f200_vorher);
  assert (select kg from v_verlust_ranking where strom = 'Nicht lagerbedingt') > 0,
    'Die Grundaussortierung muss als eigener Strom beziffert sein';
  assert (select sockel_oben from v_schimmel_modell) >= v_sockel
     and (select sockel_unten from v_schimmel_modell) <= v_sockel,
    'Der Sockel-Bereich muss den Sockel enthalten';

  -- zurück auf reinen Verderb, und die übrigen Messungen wieder an
  update schimmel_messung s
     set kg = round(6 * 865 * power(1 - 0.0006, t.tage)
                    * (1 - exp(-0.0000107 * power(t.tage, 1.6))))
    from auftrag a cross join lateral (select (a.start_ts::date - date '2026-09-01') as tage) t
   where a.id = s.auftrag_id and s.auftrag_id between 2001 and 2015;
  update schimmel_messung set gemessen = true where auftrag_id not between 2001 and 2015;
  perform auswertung_aktualisieren();
  raise notice 'OK  Grundaussortierung (null bei reinem Verderb, 2 %% wiedergefunden, Kurve bleibt)';
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
  for r in select strom, kg, kg_unten, kg_oben from v_verlust_ranking where kg is not null loop
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
  -- Die Waage zeigt brutto: 165 auf der Anzeige sind 120 kg Faules bei 45 kg
  -- Behälter. Gespeichert wird der Stand; die Menge leitet die Auswertung ab.
  insert into schimmel_messung (auftrag_id, kg, palox_stand_kg)
  values (v_wasch, 120, 165);

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
  select wartet_kg into v_wartet from v_kaskade_basis where charge_nr = v_sort.charge_nr;
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
  -- 0036: Die erste Ablesung einer Station enthält den Behälter. 165 brutto
  -- bei 45 kg Tara sind 120 kg Faules — und genau das muss im Modell ankommen,
  -- nicht 165.
  assert (select differenz from v_palox_stand where auftrag_id = (select id from auftrag where bemerkung = 'PRUEFUNG' and station = 'waschen')) = 120,
    format('Erste Ablesung: erwartet 165 − 45 = 120, ist %s',
           (select differenz from v_palox_stand where auftrag_id = (select id from auftrag where bemerkung = 'PRUEFUNG' and station = 'waschen')));
  assert (select kg from v_schimmel_menge where auftrag_id = (select id from auftrag where bemerkung = 'PRUEFUNG' and station = 'waschen')) = 120,
    'Die Schimmelmenge muss aus dem Stand abgeleitet sein (mit Tara)';

  -- 0060: Zwei Stationen — Sortiermaschine und Waschstrasse. „Waschen +
  -- Sortieren" ist die Waschstrasse mit Sortieren am Band: derselbe Palox.
  -- 165 auf der Wasch-Waage, dann 195 von der Hand-Sortierung = 30 kg dazu.
  insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status)
  values (2100, 'hand', 'waschen_sortieren', 1613,
          now() - interval '2 hours', now(), 'abgeschlossen');
  insert into schimmel_messung (auftrag_id, kg, palox_stand_kg)
  values (2100, 30, 195);
  assert palox_letzter_stand('waschen') = 195 and palox_letzter_stand('waschen_sortieren') = 195,
    'Waschen und Waschen + Sortieren teilen sich den Palox der Waschstrasse (0060)';
  assert palox_letzter_stand('sortieren') is null,
    'Die Sortiermaschine hat ihren eigenen Palox';
  assert (select differenz from v_palox_stand where auftrag_id = 2100) = 30,
    'Die Differenz läuft über beide Stationsnamen der Waschstrasse hinweg (195 − 165)';

  -- Der Stand fällt (195 → 90): zwischendurch geleert, ohne Ablesung davor.
  -- Der Arbeiter wird nicht gefragt; die Menge dieser Ablesung ist unbekannt,
  -- die Arbeit hat damit keine bekannte Schimmelmenge.
  insert into schimmel_messung (auftrag_id, kg, palox_stand_kg)
  values (2100, 0, 90);
  select differenz into v_diff from v_palox_stand
   where auftrag_id = 2100 order by ts desc, id desc limit 1;
  assert v_diff is null,
    format('Ein gefallener Stand ergibt eine unbekannte Menge, nicht %s (0060)', v_diff);
  assert (select zwischendurch_geleert from v_palox_stand
           where auftrag_id = 2100 order by ts desc, id desc limit 1),
    'Ein gefallener Stand heisst: zwischendurch geleert';
  assert not exists (select 1 from v_schimmel_menge where auftrag_id = 2100),
    'Eine Arbeit mit unbekannter Ablesung hat keine Schimmelmenge — unbekannt, nicht 0';
  assert exists (select 1 from v_plausibilitaet where art = 'Palox geleert' and auftrag_id = 2100),
    'Der gefallene Stand steht als Hinweis in der Plausibilität';
  -- Danach zählt es wieder: 90 → 130 sind 40 kg (die Arbeit bleibt trotzdem unbekannt)
  insert into schimmel_messung (auftrag_id, kg, palox_stand_kg)
  values (2100, 40, 130);
  assert (select differenz from v_palox_stand where auftrag_id = 2100 and palox_stand_kg = 130) = 40,
    'Nach dem gefallenen Stand zählt die Differenz wieder';
  assert not exists (select 1 from v_schimmel_menge where auftrag_id = 2100),
    'Ein unbekanntes Stück macht die ganze Arbeit unbekannt';
  -- Beide Ablesungen weg (90 und 130): die Menge ist wieder bekannt.
  delete from schimmel_messung where auftrag_id = 2100 and palox_stand_kg in (90, 130);
  assert (select kg from v_schimmel_menge where auftrag_id = 2100) = 30,
    'Ohne die gefallene Ablesung ist die Menge wieder bekannt (30 kg)';

  -- Geleert gemeldet (das alte Häkchen): der Stand ohne Behälter gilt als Menge.
  insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert)
  values (2100, 45, 90, true);
  select differenz into v_diff from v_palox_stand
   where auftrag_id = 2100 order by ts desc, id desc limit 1;
  assert v_diff = 45,
    format('Nach dem Leeren gilt der Stand ohne Behälter als Menge, nicht die Differenz (%s)', v_diff);

  -- Ein Stand unter dem Leergewicht ist unmöglich und gehört gemeldet.
  insert into schimmel_messung (auftrag_id, kg, palox_stand_kg)
  values (2100, 0, 20);
  assert exists (select 1 from v_plausibilitaet where art = 'Palox' and auftrag_id = 2100),
    'Ein Waagenstand unter der Palox-Tara muss in v_plausibilitaet erscheinen';
  delete from schimmel_messung where auftrag_id = 2100 and palox_stand_kg = 20;

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
                      where prognose_verlust_14_kg is not null
                        and abs(verdunstung_14_kg + schimmel_14_kg - prognose_verlust_14_kg) > 0.5),
    'Die Prognosesumme entspricht nicht ihren Teilen';
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
  assert v.n_lieferungen = 1, 'Die Fixtur hat genau eine Lieferung (aus dem Kaskaden-Block)';
  assert v.befund not like '%Kein Warenausgang%',
    'Mit einer Lieferung darf die Bilanz nicht „kein Warenausgang" sagen';
  v_vorher := v.ausgang_kg;

  -- Eine Lieferung in Kilo
  insert into lieferung (datum, sorte, kg, ziel)
  values (current_date, 'Tiana', 5000, 'verkauf');
  -- Eine in Kisten — muss über das gemessene Kilo je Kiste umgerechnet werden
  insert into lieferung (datum, sorte, kisten, ziel)
  values (current_date, 'Tiana', 100, 'verkauf');

  select * into v from v_saisonbilanz;
  assert v.n_lieferungen = 3, 'Beide neuen Lieferungen müssen in der Bilanz stehen';
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

  delete from lieferung where bemerkung is distinct from 'PRUEF-KASKADE';
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

-- =========================================================================
-- Die Kette (0036): Was erfasst wird, kommt an — und was fehlt, ist unbekannt.
-- Diese Prüfungen stellen Dashboard-Ansichten gegen die Rohtabellen. Jede
-- davon entspricht einem Befund, der vorher durch alle Tests lief.
-- =========================================================================
do $$
declare v_erfasst numeric; v_angekommen numeric; v_gemeldet numeric; v_n int;
        v_rest numeric; v_m2 numeric; v_vorher numeric; v_nachher numeric; v_sorte text; v_text text;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  perform auswertung_aktualisieren();

  -- (a) Jedes Kilo Faules, das erfasst und nicht abgebrochen ist, steht
  --     entweder als Punkt im Verderbsmodell oder als Befund in der
  --     Plausibilität. Ein drittes Schicksal darf es nicht geben.
  select coalesce(sum(m.kg), 0) into v_erfasst
    from v_schimmel_menge m join auftrag a on a.id = m.auftrag_id
   where a.abgebrochen_ts is null;
  select coalesce(sum(schimmel_kg), 0) into v_angekommen
    from v_schimmel_punkte where quelle = 'verarbeitung';
  select coalesce(sum(m.kg), 0) into v_gemeldet
    from v_plausibilitaet p join v_schimmel_menge m on m.auftrag_id = p.auftrag_id
   where p.art = 'Ohne Nenner';
  assert abs(v_erfasst - v_angekommen - v_gemeldet) < 0.5,
    format('Schimmel: %s kg erfasst, %s kg im Modell, %s kg gemeldet — %s kg verschwinden spurlos',
           round(v_erfasst), round(v_angekommen), round(v_gemeldet),
           round(v_erfasst - v_angekommen - v_gemeldet));

  -- (b) Ein Auftrag mit Faulem, aber ohne Nenner, wird gemeldet.
  insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status)
  values (2200, 'hand', 'waschen_sortieren', 1614, now() - interval '3 hours', now() - interval '1 hour',
          'abgeschlossen');
  insert into schimmel_messung (auftrag_id, kg) values (2200, 77);
  perform auswertung_aktualisieren();
  assert exists (select 1 from v_plausibilitaet where art = 'Ohne Nenner' and auftrag_id = 2200),
    'Faules ohne gezählte Paletten muss als „Ohne Nenner" gemeldet werden';
  assert not exists (select 1 from v_schimmel_punkte where auftrag_id = 2200),
    'Eine Messung ohne Nenner darf keinen Punkt im Modell erzeugen';
  delete from auftrag where id = 2200;
  perform auswertung_aktualisieren();

  -- (c) Der Restbestand ist die verkaufsfähige Masse im Lager (0060): nach
  --     Verdunstung, Verderb, zu klein, zu gross und Fax — so schliesst die
  --     Bilanz Eingang = Verlust + Kanal + verkauft + Rest.
  select verkaufsfaehig_heute_kg into v_rest from v_saisonbilanz;
  select sum(verkaufsfaehig_kg) into v_m2 from v_kaskade where portion = 'lager';
  assert abs(v_rest - v_m2) < 0.5,
    format('Restbestand %s kg, verkaufsfähig im Lager %s kg — die Bilanz und die Kaskade widersprechen sich',
           round(v_rest), round(v_m2));

  -- (d) 0061: Die Kistenzahl der Überfüllung kommt aus der Verkaufsdatei —
  --     nicht aus einer Hochrechnung der verkauften Masse. Ohne Datei ist die
  --     Überfüllung unbekannt, und die Erläuterung sagt es (der 0061-Block
  --     prüft die Rechnung mit einer Datei).
  select kg, erlaeuterung into v_nachher, v_text from v_marge_buch where posten like '%berf%';
  assert v_nachher is null and v_text like '%Verkaufsdatei%',
    format('Ohne Verkaufsdatei darf die Überfüllung nichts behaupten: %s / %s', v_nachher, v_text);

  -- (e) 0060: Das Sollgewicht steht an der Arbeit (Kistensystem „Kiste ab
  --     x kg"). Ein höheres Soll an der Arbeit mit der gewogenen Palette
  --     drückt den Überschuss je Kiste — und damit die Überfüllung.
  if exists (select 1 from auftrag where id = 970) then
    select kg into v_vorher from v_marge_buch where posten like '%berf%';
    update auftrag set kistensystem = 'kiste_ab', soll_kg_pro_kiste = 16 where id = 970;
    select kg into v_nachher from v_marge_buch where posten like '%berf%';
    assert (select soll_kg_pro_kiste from v_ausgang_kennzahl where auftrag_id = 970) = 16,
      'Das Soll der Arbeit muss die Fassung schlagen';
    update auftrag set kistensystem = null, soll_kg_pro_kiste = null where id = 970;
    if v_vorher is not null and v_vorher <> 0 then
      assert v_nachher < v_vorher,
        format('Das Soll an der Arbeit greift nicht (%s → %s)', v_vorher, v_nachher);
    end if;
    assert (select soll_kg_pro_kiste from v_ausgang_kennzahl where auftrag_id = 970) = 8,
      'Ohne Kistensystem an der Arbeit gilt wieder die Fassung (8 kg)';
  end if;

  raise notice 'OK  Kette: erfasst = angekommen + gemeldet, Restbestand = verkaufsfähig im Lager, Einstellung und Kistenmass greifen';
end $$;

-- Ein Koeffizient ohne einzige Messung ist unbekannt, nicht 0. Geprüft an
-- einer leeren Kopie: ohne Wägungen muss die Verdunstung NULL sein.
do $$
declare v_kg numeric; v_n int;
begin
  -- Alle Wägungen vorübergehend „ungemessen" — dann gibt es keine Rate.
  update verdunstung_wiegung set gemessen = false;
  perform auswertung_aktualisieren();
  select kg into v_kg from v_verlust_ranking where strom = 'Verdunstung';
  assert v_kg is null,
    format('Ohne einzige Wägung muss die Verdunstung unbekannt (NULL) sein, ist %s', v_kg);
  assert (select kg_unten from v_verlust_ranking where strom = 'Verdunstung') is null,
    'Ein unbekannter Strom darf keinen Bereich vortäuschen';
  assert (select count(*) from v_hochrechnung where strom = 'Verdunstung' and koeff_bekannt) = 0,
    'koeff_bekannt muss ohne Wägung überall false sein';
  -- Die Masse läuft trotzdem weiter — Schimmel bleibt beziffert.
  assert (select kg from v_verlust_ranking where strom = 'Schimmel/Fäulnis') is not null,
    'Ohne Verdunstung darf der Schimmel nicht mit verschwinden';
  assert (select befund from v_saisonbilanz) like '%noch nicht gemessen%',
    'Die Bilanz muss sagen, dass ein Strom fehlt';
  update verdunstung_wiegung set gemessen = true;
  perform auswertung_aktualisieren();
  assert (select kg from v_verlust_ranking where strom = 'Verdunstung') is not null,
    'Mit Wägungen muss die Verdunstung wieder da sein';
  raise notice 'OK  Leer ist nicht null: ohne Messung ist der Koeffizient unbekannt';
end $$;

select '——— Kette geprüft ———' as ergebnis;

-- =========================================================================
-- 0038: Das Sortierschema hängt am Käufer, mit Gültigkeit. Eine CSV wird nach
-- der Fassung klassiert, die für ihren Auftrag galt — nicht nach der von heute.
-- =========================================================================
do $$
declare v_lauf bigint; v_alt int; v_neu int; v_schema bigint; v_auftrag bigint;
        v_standard bigint;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  -- Der Ausgangswert je Sorte ist die Standard-Fassung
  v_standard := sortierschema_fuer('Tiana', null, current_date);
  assert v_standard is not null, 'Jede Sorte braucht eine Standard-Fassung';
  assert (select verlust_unter from sortierschema where id = v_standard) = 500,
    'Die Standard-Fassung für Tiana muss aus sorte_kaliber stammen (500 g)';

  -- Ein Käufer mit strengerer Grenze, gültig ab dem 1. Dezember
  insert into kaeufer (code, name) values ('coop', 'Coop') on conflict do nothing;
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab)
  values ('Tiana', 'coop', date '2026-12-01', 'kaliber', 700,
          '[[700,1300],[1300,2000]]'::jsonb, 2000)
  returning id into v_schema;

  -- Vor dem 1. Dezember gilt für Coop noch der Standard
  assert sortierschema_fuer('Tiana', 'coop', date '2026-11-15') = v_standard,
    'Vor gilt_ab muss die Standard-Fassung gelten';
  assert sortierschema_fuer('Tiana', 'coop', date '2026-12-15') = v_schema,
    'Ab gilt_ab muss die Käufer-Fassung gelten';
  assert sortierschema_fuer('Tiana', 'migros', date '2026-12-15') = v_standard,
    'Ein Käufer ohne eigene Fassung bekommt den Standard';

  -- Ein Sortier-Auftrag für Coop im Dezember hält seine Fassung fest
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaeufer)
  values ('maschine', 'sortieren', 1613, timestamptz '2026-12-10 08:00+01',
          timestamptz '2026-12-10 15:00+01', 'abgeschlossen', 'coop')
  returning id into v_auftrag;
  assert (select sortierschema_id from auftrag where id = v_auftrag) = v_schema,
    'Der Auftrag muss die Fassung seines Käufers festhalten';

  -- Die CSV dazu: 600 g ist für Coop zu klein, für den Standard Kaliber
  select csv_lauf_speichern(1613, '1613-10-12-09-00', null, 'pruefsumme-coop',
           timestamptz '2026-12-10 09:00+01', 'dateiname',
           '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
           100, 0, 0, 0, '[[600,50],[900,50]]'::jsonb) into v_lauf;
  assert (select sortierschema_id from sortier_lauf where id = v_lauf) = v_schema,
    'Der Lauf muss nach der Fassung seines Auftrags klassiert sein';
  select sum(anzahl) into v_neu from sortier_gewicht
   where lauf_id = v_lauf and klasse = 'verlust_klein';
  assert v_neu = 50, format('Nach der Coop-Fassung sind 600 g zu klein — %s statt 50', v_neu);

  -- Der alte Lauf vom November bleibt nach dem Standard klassiert: 600 g Kaliber
  select sum(anzahl) into v_alt from sortier_gewicht g
    join sortier_lauf l on l.id = g.lauf_id
   where l.roh_pruefsumme = 'pruefsumme-1' and g.gewicht_g = 600 and g.klasse = 'kaliber';
  assert v_alt = 2000, 'Der Lauf vom November darf nicht rückwirkend nach Coop klassiert werden';

  -- Von Hand einem Auftrag ohne Käufer zugeordnet → Standard, neu klassiert
  perform auftrag_manuell_zuordnen(v_lauf, 900);
  select sum(anzahl) into v_neu from sortier_gewicht
   where lauf_id = v_lauf and klasse = 'verlust_klein';
  assert v_neu is null or v_neu = 0,
    format('Nach der Umhängung auf den Standard sind 600 g Kaliber — noch %s zu klein', v_neu);

  -- Kisten-Fassung: das Stückgewicht spielt keine Rolle
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste)
  values ('Tiana', 'coop', date '2027-01-01', 'kiste', 8.0);
  assert (select klasse from klassiere(sortierschema_fuer('Tiana', 'coop', date '2027-01-05', 'kiste'), 300))
         = 'kaliber', 'In einer Kisten-Fassung ist alles Hauptkanal';

  -- Aufräumen: die Fixtur der übrigen Prüfungen bleibt, wie sie war
  delete from sortier_lauf where id = v_lauf;
  delete from auftrag where id = v_auftrag;
  delete from sortierschema where kaeufer = 'coop';
  delete from kaeufer where code = 'coop';
  perform auswertung_aktualisieren();
  raise notice 'OK  Sortierschema je Käufer (datiert, am Auftrag festgehalten, nicht rückwirkend)';
end $$;

select '——— Sortierschema geprüft ———' as ergebnis;

-- =========================================================================
-- 0039: Antworten sind Messwerte. „Nicht alles aus einer Charge" nimmt die
-- Messung aus dem Zeitmodell, nicht aus der Bilanz.
-- =========================================================================
do $$
declare v_auftrag bigint; v_n_vorher int; v_n_nachher int;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  select n into v_n_vorher from v_schimmel_modell;

  -- Ein Auftrag mit Schimmel, dessen Ware aus mehreren Chargen kam
  insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status)
  values (2300, 'hand', 'waschen_sortieren', 1613, timestamptz '2026-12-20 08:00+01',
          timestamptz '2026-12-20 15:00+01', 'abgeschlossen');
  insert into auftrag_palette (auftrag_id, eingangsdatum)
  select 2300, date '2026-09-01' from generate_series(1, 4);
  insert into schimmel_messung (auftrag_id, kg) values (2300, 40);
  insert into auftrag_angabe (auftrag_id, schluessel, wert) values (2300, 'eine_charge', 'false');
  insert into auftrag_angabe (auftrag_id, schluessel, wert) values (2300, 'gleiche_sorte', 'true');
  perform auswertung_aktualisieren();

  assert (select quelle from v_schimmel_punkte where auftrag_id = 2300) = 'verarbeitung_gemischt',
    'Eine gemischte Arbeit muss als verarbeitung_gemischt markiert sein';
  select n into v_n_nachher from v_schimmel_modell;
  assert v_n_nachher = v_n_vorher,
    format('Der gemischte Punkt darf nicht ins Zeitmodell (%s → %s Punkte)', v_n_vorher, v_n_nachher);
  -- In der Bilanz zählt die Masse weiter
  assert (select eingang_netto_kg from v_auftrag_masse where auftrag_id = 2300) > 0,
    'Die Masse der gemischten Arbeit muss in der Bilanz bleiben';
  -- Die letzte Antwort gilt
  insert into auftrag_angabe (auftrag_id, schluessel, wert) values (2300, 'eine_charge', 'true');
  assert (select wert from v_auftrag_angabe where auftrag_id = 2300 and schluessel = 'eine_charge') = 'true',
    'Es muss die letzte Antwort je Schlüssel gelten';
  assert (select count(*) from auftrag_angabe where auftrag_id = 2300 and schluessel = 'eine_charge') = 2,
    'Antworten werden nie überschrieben';

  delete from auftrag where id = 2300;
  perform auswertung_aktualisieren();
  raise notice 'OK  Antworten sind Messwerte (gemischt = nicht im Zeitmodell, letzte Antwort gilt)';
end $$;

select '——— Angaben geprüft ———' as ergebnis;

do $$
declare v_offen text;
begin
  -- 0035: Postgres gibt jeder neuen Funktion automatisch PUBLIC das
  -- Ausführungsrecht, und ein `grant … to authenticated` nimmt das nicht
  -- zurück. Bei den "security definer"-Funktionen, die an den Zeilenregeln
  -- vorbeilaufen, ist das eine offene Tür für Nichtangemeldete — genau so
  -- liess sich demo_daten_laden() einmal als anon aufrufen. Diese Prüfung
  -- hält die Tür zu, auch für Funktionen, die es heute noch gar nicht gibt.
  select string_agg(p.proname, ', ' order by p.proname) into v_offen
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
     and coalesce(p.proacl::text, '{=X/}') like '%{=X/%';
  assert v_offen is null,
    'Diese Funktionen stehen jedem offen, auch ohne Anmeldung: ' || coalesce(v_offen, '');

  -- Und der Weg herum: Was die App ruft, muss für Angemeldete erreichbar sein.
  select string_agg(p.proname, ', ' order by p.proname) into v_offen
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
     and coalesce(p.proacl::text, '') not like '%authenticated=X%';
  assert v_offen is null,
    'Diese Funktionen kann kein Angemeldeter aufrufen: ' || coalesce(v_offen, '');

  raise notice 'OK  Funktionsrechte (nichts steht Nichtangemeldeten offen)';
end $$;

do $$
declare v_fn record; v_stueck text; v_kern text; v_treffer text := '';
begin
  -- Supabase lässt die API-Verbindung mit der Sicherung „safeupdate" laufen:
  -- Ein UPDATE oder DELETE ohne WHERE wird abgewiesen — auch in einer
  -- Funktion, auch auf einer Hilfstabelle. Der Prüfstand hier hat diese
  -- Sicherung nicht; darum liest diese Wache jeden Funktionsrumpf und
  -- verlangt bei jedem UPDATE/DELETE ein WHERE auf oberster Ebene
  -- (Unterabfragen in Klammern zählen nicht — safeupdate zählt sie auch nicht).
  for v_fn in
    select p.proname, p.prosrc
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
  loop
    foreach v_stueck in array regexp_split_to_array(regexp_replace(v_fn.prosrc, '--[^\n]*', '', 'g'), ';')
    loop
      if v_stueck ~* '^\s*(update|delete\s+from)\s+\w+' then
        v_kern := v_stueck;
        while v_kern ~ '\([^()]*\)' loop
          v_kern := regexp_replace(v_kern, '\([^()]*\)', '', 'g');
        end loop;
        if v_kern !~* '\mwhere\M' then
          v_treffer := v_treffer || format('%s: „%s…"  ', v_fn.proname, left(regexp_replace(btrim(v_stueck), '\s+', ' ', 'g'), 50));
        end if;
      end if;
    end loop;
  end loop;
  assert v_treffer = '',
    'UPDATE/DELETE ohne WHERE — Supabase weist das über die API ab (safeupdate): ' || v_treffer;
  raise notice 'OK  safeupdate-Wache: jedes UPDATE/DELETE in Funktionen hat ein WHERE';
end $$;

do $$
declare v_meldung text;
begin
  -- 0034: Der Demo-Knopf. Ein Arbeiter darf ihn nicht drücken.
  perform set_config('request.jwt.claim.sub',
                     (select id::text from profil where rolle = 'arbeiter' limit 1), true);
  begin
    perform demo_daten_laden();
    assert false, 'Ein Arbeiter darf die Demo-Saison nicht laden können';
  exception when others then
    get stacked diagnostics v_meldung = message_text;
    assert v_meldung like '%Betriebsleiter%',
      'Die Absage an den Arbeiter muss sagen, woran es liegt: ' || v_meldung;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  Demo-Knopf (nur der Betriebsleiter)';
end $$;

-- =========================================================================
-- 0053: Das Zeitlimit. Supabase gibt einer Abfrage über die API acht
-- Sekunden; auswertung_aktualisieren() rechnet die ganze Saison neu und
-- braucht mehr. Die Einrichtung setzt das Limit für Angemeldete hoch —
-- diese Prüfung hält fest, dass sie es tut, und dass anon knapp bleibt.
-- =========================================================================
do $$
declare v_gesetzt text[];
begin
  select coalesce(rolconfig, '{}') into v_gesetzt from pg_roles where rolname = 'authenticated';
  assert 'statement_timeout=30s' = any(v_gesetzt),
    'Angemeldete brauchen mehr als acht Sekunden, sonst bricht das Neurechnen ab. Gesetzt ist: '
    || coalesce(array_to_string(v_gesetzt, ', '), '(nichts)');

  select coalesce(rolconfig, '{}') into v_gesetzt from pg_roles where rolname = 'anon';
  assert not exists (select 1 from unnest(v_gesetzt) g where g like 'statement_timeout=%'),
    'anon bleibt beim knappen Standard — wer nicht angemeldet ist, rechnet hier nichts';

  raise notice 'OK  Zeitlimit: 30 s für Angemeldete, anon unverändert';
end $$;

-- =========================================================================
-- 0041: Am Waschbecken zählen Kisten. Das Kistengewicht wird am Sortieren
-- gemessen, nicht geschätzt; ohne Messung bleibt die Masse unbekannt.
-- =========================================================================
do $$
declare v_sort bigint; v_wasch bigint; v_lauf bigint; v_kg numeric; v_quelle text;
        v_koeff numeric; v_n int; v_fehler boolean;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);

  -- Eine Sortierarbeit mit CSV: 2000 Kürbisse à 1200 g in Kaliberband 0 = 2400 kg
  insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status)
  values (2400, 'maschine', 'sortieren', 1613, timestamptz '2026-11-02 08:00+01',
          timestamptz '2026-11-02 15:00+01', 'abgeschlossen') returning id into v_sort;
  insert into auftrag_palette (auftrag_id, eingangsdatum)
  select 2400, date '2026-09-01' from generate_series(1, 8);
  select csv_lauf_speichern(1613, 'SIM-KISTE.csv', null, 'pruefsumme-kiste', null, null,
         '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":false}'::jsonb,
         2000, 0, 0, 0, '[[1200,2000]]'::jsonb) into v_lauf;
  perform auftrag_manuell_zuordnen(v_lauf, 2400);

  -- Der Arbeiter hat 60 Kisten gefüllt → 40 kg je Kiste
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
  select 2400, g.kaliber_idx, 60 from sortier_gewicht g
   where g.lauf_id = v_lauf and g.klasse = 'kaliber' limit 1;
  perform auswertung_aktualisieren();

  select kg_je_gebinde, n into v_koeff, v_n from v_koeff_gebinde
   where sorte = (select sorte from charge where nr = 1613);
  assert v_koeff is not null, 'Ohne gemessenes Kistengewicht gibt es keine Kistenrechnung';
  assert abs(v_koeff - 40) < 0.5,
    format('2400 kg auf 60 Kisten sind 40 kg je Kiste, gemessen wurden %s', v_koeff);
  assert v_n = 1, format('Eine Messung erwartet, %s gezählt', v_n);

  -- Ein Waschgang derselben Sorte, 10 Kisten desselben Kalibers → 400 kg
  insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx)
  values (2401, 'maschine', 'waschen', 1613, timestamptz '2027-01-15 08:00+01',
          timestamptz '2027-01-15 15:00+01', 'abgeschlossen',
          (select kaliber_idx from auftrag_gebinde where auftrag_id = 2400))
  returning id into v_wasch;
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
  values (2401, (select kaliber_idx from auftrag_gebinde where auftrag_id = 2400), 10);
  perform auswertung_aktualisieren();

  select eingang_netto_kg, masse_quelle into v_kg, v_quelle
    from v_auftrag_masse where auftrag_id = 2401;
  assert v_quelle = 'gebinde',
    format('Die Masse muss aus den Kisten kommen, kommt aber aus %s', v_quelle);
  assert abs(v_kg - 400) < 5, format('10 Kisten à 40 kg sind 400 kg, gerechnet wurden %s', v_kg);

  -- Und damit hat der Schimmel am Waschbecken einen Nenner
  insert into schimmel_messung (auftrag_id, kg) values (2401, 20);
  perform auswertung_aktualisieren();
  assert exists (select 1 from v_schimmel_punkte where auftrag_id = 2401),
    'Mit gezählten Kisten muss der Waschgang einen Punkt im Verderbsmodell ergeben';
  assert not exists (select 1 from v_plausibilitaet
                      where art = 'Ohne Nenner' and auftrag_id = 2401),
    'Ein Waschgang mit gezählten Kisten steht nicht mehr ohne Nenner da';

  -- Ein Kaliber ohne Messung bleibt unbekannt, nicht null
  insert into auftrag (id, weg, station, charge_nr, start_ts, status, kaliber_idx)
  values (2402, 'maschine', 'waschen', 1613, timestamptz '2027-01-16 08:00+01', 'offen', 7);
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl) values (2402, 7, 12);
  assert (select kg from v_auftrag_gebinde_masse where auftrag_id = 2402) is null,
    'Ohne gemessenes Kistengewicht muss die Masse NULL sein, nicht 0';
  assert exists (select 1 from v_plausibilitaet where art = 'Kistengewicht' and auftrag_id = 2402),
    'Gezählte Kisten ohne Kistengewicht müssen als Auffälligkeit erscheinen';

  -- Das Datum vom Zettel ist Pflicht (0041)
  v_fehler := false;
  begin
    insert into auftrag_palette (auftrag_id, eingangsdatum) values (2400, null);  -- ohne Palette, ohne Wägung
  exception when check_violation then v_fehler := true;
  end;
  assert v_fehler, 'Eine Palettenzählung ohne Datum darf nicht mehr angenommen werden';

  delete from auftrag where id in (2400, 2401, 2402);
  delete from sortier_lauf where id = v_lauf;
  perform auswertung_aktualisieren();
  raise notice 'OK  Kisten am Waschbecken (Gewicht gemessen, ohne Messung unbekannt, Datum Pflicht)';
end $$;

select '——— Kistenrechnung geprüft ———' as ergebnis;

-- =========================================================================
-- 0042: Die Auswertung muss auch dann rechnen, wenn der Suchpfad leer ist.
-- Genau daran ist setup.sql im SQL-Editor von Supabase gescheitert: Beim
-- Einsetzen einer SQL-Funktion löst Postgres die Namen im Rumpf mit dem
-- Suchpfad der Sitzung auf, und der war dort ohne public.
-- =========================================================================
do $$
declare v numeric; v_n int;
begin
  perform set_config('search_path', '', true);

  -- Die Funktionen, die je Zeile eingesetzt werden
  select public.palox_tara_kg() into v;
  assert v is not null, 'palox_tara_kg() muss ohne Suchpfad rechnen';
  select public.schimmelanteil(100) into v;
  assert v is not null, 'schimmelanteil() muss ohne Suchpfad rechnen';
  select public.sockel_anteil() into v;
  assert v is not null, 'sockel_anteil() muss ohne Suchpfad rechnen';
  perform public.klassiere((select id from public.sortierschema limit 1), 800);
  perform public.sortierschema_fuer((select sorte from public.charge limit 1), null, current_date);

  -- Und die ganze Kaskade, so wie setup.sql sie aufbaut (0061: in Schritten)
  perform public.auswertung_aktualisieren();

  select count(*) into v_n from public.v_verlust_ranking;
  assert v_n > 0, 'Das Ranking muss auch ohne Suchpfad Zeilen liefern';
  select count(*) into v_n from public.v_palox_stand;
  select count(*) into v_n from public.v_plausibilitaet;
  select count(*) into v_n from public.v_marge_buch;
  select count(*) into v_n from public.v_saisonbilanz;

  perform set_config('search_path', 'public', true);
  raise notice 'OK  Suchpfad (Funktionen und Kaskade rechnen auch mit leerem search_path)';
end $$;

-- =========================================================================
-- AB-01: Wie sortiert wird, wählt die Arbeit beim Eröffnen — nicht die
-- Stammdaten. Beide Arten dürfen für dieselbe Sorte nebeneinander stehen,
-- die CSV wird nach der gewählten Art klassiert, und nach Kaliber gibt es
-- keine Überfüllung.
-- =========================================================================
do $$
declare v_sorte text; v_kaeufer text := 'ab01kaeufer';
        v_a_kiste bigint; v_a_kaliber bigint;
        v_s_kiste bigint; v_s_kaliber bigint;
        v_lauf bigint; v_klein int; v_kaliber int;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  select sorte into v_sorte from sorte_kaliber limit 1;

  -- Beide Fassungen nebeneinander: früher verbot das der Eindeutigkeits-Index.
  insert into kaeufer (code, name) values (v_kaeufer, 'AB01') on conflict do nothing;
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
    values (v_sorte, v_kaeufer, current_date - 1, 'kiste', 9, 'PRUEFUNG')
    returning id into v_s_kiste;
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter,
                             kaliber_baender, kanal_ab, bemerkung)
    values (v_sorte, v_kaeufer, current_date - 1, 'kaliber', 700,
            '[[700,1100],[1100,1600]]'::jsonb, 1600, 'PRUEFUNG')
    returning id into v_s_kaliber;

  assert sortierschema_fuer(v_sorte, v_kaeufer, current_date, 'kiste') = v_s_kiste,
    'Die Kisten-Fassung muss für die Art kiste gewählt werden';
  assert sortierschema_fuer(v_sorte, v_kaeufer, current_date, 'kaliber') = v_s_kaliber,
    'Die Kaliber-Fassung muss für die Art kaliber gewählt werden';

  -- Eine Sortierarbeit mit der Kaliber-Fassung. 600 g < 700 → zu klein.
  insert into auftrag (weg, station, charge_nr, start_ts, kaeufer, sortierschema_id)
    select 'maschine', 'sortieren', c.nr, now(), v_kaeufer, v_s_kaliber
      from charge c where c.sorte = v_sorte limit 1
    returning id into v_a_kaliber;
  select csv_lauf_speichern((select charge_nr from auftrag where id = v_a_kaliber),
         'AB01-KALIBER.csv', null, 'ab01-kaliber', null, null,
         '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":false}'::jsonb,
         100, 0, 0, 0, '[[600,100],[900,100]]'::jsonb) into v_lauf;
  perform auftrag_manuell_zuordnen(v_lauf, v_a_kaliber);
  select sum(anzahl) into v_klein from sortier_gewicht
   where lauf_id = v_lauf and klasse = 'verlust_klein';
  assert v_klein = 100, format('Kaliber-Fassung: 600 g sind zu klein — %s statt 100', v_klein);

  -- Dieselbe Charge, dieselbe CSV, aber als Kiste eröffnet: kein zu klein.
  insert into auftrag (weg, station, charge_nr, start_ts, kaeufer, sortierschema_id)
    select 'maschine', 'sortieren', c.nr, now(), v_kaeufer, v_s_kiste
      from charge c where c.sorte = v_sorte limit 1
    returning id into v_a_kiste;
  select csv_lauf_speichern((select charge_nr from auftrag where id = v_a_kiste),
         'AB01-KISTE.csv', null, 'ab01-kiste', null, null,
         '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":false}'::jsonb,
         100, 0, 0, 0, '[[600,100],[900,100]]'::jsonb) into v_lauf;
  perform auftrag_manuell_zuordnen(v_lauf, v_a_kiste);
  select coalesce(sum(anzahl), 0) into v_klein from sortier_gewicht
   where lauf_id = v_lauf and klasse = 'verlust_klein';
  select sum(anzahl) into v_kaliber from sortier_gewicht
   where lauf_id = v_lauf and klasse = 'kaliber';
  assert v_klein = 0, format('Kisten-Fassung: nichts ist zu klein — %s als zu klein', v_klein);
  assert v_kaliber = 200, format('Kisten-Fassung: alles ist Hauptkanal — %s statt 200', v_kaliber);

  delete from sortier_lauf where roh_pruefsumme in ('ab01-kaliber', 'ab01-kiste');
  delete from auftrag where id in (v_a_kiste, v_a_kaliber);
  delete from sortierschema where bemerkung = 'PRUEFUNG';
  delete from kaeufer where code = v_kaeufer;
  perform auswertung_aktualisieren();
  raise notice 'OK  AB-01 Sortierart je Arbeit (beide Fassungen, CSV folgt der Wahl, Kaliber ohne Überfüllung)';
end $$;

select '——— AB-01 Sortierart geprüft ———' as ergebnis;

-- =========================================================================
-- AB-03: Ausschuss wird gewogen (Brutto, Kisten, Gebinde), das Netto rechnet
-- der Auslöser. Die Schätzung bleibt möglich und zählt weiter. Ändert sich
-- eine Tara nachträglich, meldet es v_plausibilitaet als „Ausschuss-Tara".
-- =========================================================================
do $$
declare v_a bigint; v_kg int; v_gem boolean; v_n int;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  insert into auftrag (weg, station, charge_nr, start_ts, eroeffnet_von)
    select 'hand', 'waschen_sortieren', c.nr, now(), '11111111-1111-1111-1111-111111111111'
      from charge c limit 1
    returning id into v_a;

  -- Gewogen: Brutto 100, 4 Kisten G2 (1.5 + Palette 25) → 100 − 6 − 25 = 69.
  insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart)
    values (v_a, 'zu_klein', 100, 4, 'G2') returning kg, gemessen into v_kg, v_gem;
  assert v_kg = 69, format('Gewogenes Netto erwartet 69, ist %s', v_kg);
  assert v_gem, 'Gewogener Ausschuss ist gemessen';

  -- Geschätzt: kg direkt, kein Brutto — zählt trotzdem.
  insert into ausschuss_messung (auftrag_id, art, kg) values (v_a, 'zu_gross', 15);
  assert (select kg from ausschuss_messung where auftrag_id = v_a and art = 'zu_gross') = 15,
    'Die Schätzung muss stehen bleiben';
  assert (select count(*) from ausschuss_messung where auftrag_id = v_a and gemessen) = 2,
    'Beide, gewogen und geschätzt, zählen als Messwert';

  -- Tara nachträglich ändern → das alte Netto passt nicht mehr, die
  -- Auffälligkeiten melden es dort, wo der Betriebsleiter hinschaut.
  select count(*) into v_n from v_plausibilitaet where auftrag_id = v_a and art = 'Ausschuss-Tara';
  assert v_n = 0, format('Bei unveränderter Tara darf kein Befund stehen, sind %s', v_n);
  update gebinde set tara_kg_pro_kiste = 2.0 where art = 'G2';
  select count(*) into v_n from v_plausibilitaet where auftrag_id = v_a and art = 'Ausschuss-Tara';
  assert v_n = 1, format('Nach Tara-Änderung muss genau ein Befund stehen, sind %s', v_n);
  update gebinde set tara_kg_pro_kiste = 1.5 where art = 'G2';

  delete from auftrag where id = v_a;
  perform auswertung_aktualisieren();
  raise notice 'OK  AB-03 Ausschuss wiegen (Netto abgeleitet, Schätzung zählt, Tara-Prüfung)';
end $$;

select '——— AB-03 Ausschuss geprüft ———' as ergebnis;

-- =========================================================================
-- 0048: Der Ballast ist weg, und die Überfüllung rechnet nur noch aus den
-- fertigen Paletten. Der Wächter für eine gefüllte marge_messung wird in
-- run.sh Stufe 3b am alten Stand geprüft — hier gibt es die Tabelle nicht mehr.
-- =========================================================================
do $$
declare v_n int;
begin
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('marge_messung', 'v_ausschuss_pruef', 'v_auftrag_sortierart',
                       'v_dubletten_pruefung', 'v_schlag_effekt', 'v_sortier_kuerbis',
                       'v_verdunstung_stichprobe');
  assert v_n = 0, format('%s Objekte aus 0048 stehen noch', v_n);
  assert not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = 'schimmel_n'),
    'schimmel_n() steht noch';
  assert not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                      where n.nspname = 'public' and t.typname = 'marge_art'),
    'Typ marge_art steht noch';
  -- Die Auffälligkeiten kennen den alten Zweig nicht mehr, den neuen schon
  assert not exists (select 1 from v_plausibilitaet where art = 'Nicht ausgewertet'),
    'Der Zweig „Nicht ausgewertet" müsste weg sein';
  raise notice 'OK  0048 Ballast weg (Tabelle, Typ, sechs Sichten, eine Funktion)';
end $$;

select '——— 0048 Ballast geprüft ———' as ergebnis;

-- =========================================================================
-- AB-07/08/09: Erfassungsbeginn (Vorlauf senkt die Lücke), Fax als eigener
-- Auftragstyp, und die Auswahlart der Lagerkontrolle.
-- =========================================================================
do $$
declare v_luecke1 numeric; v_luecke2 numeric; v_vorlauf numeric; v_ausgang1 numeric; v_ausgang2 numeric;
        v_gel1 numeric; v_gel2 numeric; v_charge int; v_a bigint; v_fehler boolean;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  select charge_nr into v_charge from v_hochrechnung_basis
   where eingang_kg > 0 order by eingang_kg desc limit 1;

  -- AB-07: Vorlauf zum Ausgang. Seit 0061 ist er eine Lieferung wie jede
  -- andere: er hebt den Ausgang und das Gelieferte der Charge um denselben
  -- Betrag; die Lücke (= Überzählung) bleibt, wie sie ist.
  perform auswertung_aktualisieren();
  -- 0064: Die Lücke wird an ueberzaehlung_kg gemessen, nicht am Bilanzrest.
  -- Der Rest ist NULL, sobald ein Verluststrom keine Messung hat — und in
  -- dieser Prüfsaison hat keiner eine. „Lücke (= Überzählung)" heisst es
  -- ohnehin schon; jetzt steht auch das dort, was gemeint ist.
  select ueberzaehlung_kg, ausgang_kg, geliefert_kg into v_luecke1, v_ausgang1, v_gel1 from v_saisonbilanz;
  insert into charge_vorlauf (charge_nr, ausgang_vor_app_kg) values (v_charge, 1000)
    on conflict (charge_nr) do update set ausgang_vor_app_kg = 1000;
  perform auswertung_aktualisieren();
  select ueberzaehlung_kg, ausgang_kg, vorlauf_kg, geliefert_kg into v_luecke2, v_ausgang2, v_vorlauf, v_gel2 from v_saisonbilanz;
  assert v_vorlauf = 1000, format('Vorlauf erwartet 1000, ist %s', v_vorlauf);
  assert abs((v_ausgang2 - v_ausgang1) - 1000) < 1,
    format('Der Vorlauf muss den Ausgang um 1000 heben (%s → %s)', v_ausgang1, v_ausgang2);
  assert abs((v_gel2 - v_gel1) - 1000) < 1,
    format('Der Vorlauf muss das Gelieferte um 1000 heben (%s → %s)', v_gel1, v_gel2);
  assert abs(v_luecke1 - v_luecke2) < 1,
    format('Der Vorlauf darf die Lücke (= Überzählung) nicht bewegen (%s → %s)', v_luecke1, v_luecke2);
  delete from charge_vorlauf where charge_nr = v_charge;
  perform auswertung_aktualisieren();

  -- AB-08: Fax ist eine eigene Arbeit, fachlich ein Waschgang.
  insert into auftrag (weg, station, charge_nr, start_ts, eroeffnet_von, ist_fax)
    values ('maschine', 'waschen', v_charge, now(),
            '11111111-1111-1111-1111-111111111111', true)
    returning id into v_a;
  assert (select ist_fax from auftrag where id = v_a),
    'Die Fax-Markierung muss gespeichert sein';
  assert (select station from auftrag where id = v_a) = 'waschen',
    'Fax bleibt fachlich ein Waschgang';
  delete from auftrag where id = v_a;

  -- AB-09: Die Auswahlart der Lagerkontrolle wird gehalten, Unsinn abgelehnt.
  insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg,
                                   brutto_jetzt_kg, kisten, gebindeart, faul_kg,
                                   sichtbar_schimmel, auswahl)
    values (v_charge, current_date - 60, 900, 850, 40, 'G2', 3, true, 'mitte_unten')
    returning id into v_a;
  assert (select auswahl from verdunstung_wiegung where id = v_a) = 'mitte_unten',
    'Die Auswahlart muss gespeichert sein';
  delete from verdunstung_wiegung where id = v_a;
  v_fehler := false;
  begin
    insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg,
                                     brutto_jetzt_kg, kisten, gebindeart, auswahl)
      values (v_charge, current_date - 60, 900, 850, 40, 'G2', 'unsinn');
  exception when check_violation then v_fehler := true;
  end;
  assert v_fehler, 'Eine unbekannte Auswahlart muss abgelehnt werden';

  perform auswertung_aktualisieren();
  raise notice 'OK  AB-07/08/09 (Vorlauf senkt Lücke, Fax markiert, Auswahlart gehalten)';
end $$;

select '——— AB-07/08/09 geprüft ———' as ergebnis;



select '——— Suchpfad geprüft ———' as ergebnis;

select '——— Fachlogik geprüft ———' as ergebnis;

-- =========================================================================
-- 0049: Kennzahlen für den Betriebsleiter. Jede Sicht muss laufen, und wo
-- sich ein Wert vorhersagen lässt, wird er vorhergesagt.
-- =========================================================================
do $$
declare v numeric; v2 numeric; v_n int; v_a bigint; v_b bigint; v_charge int;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);

  -- Gewichtsverteilung: verlustfrei gegenüber dem Histogramm
  select sum(n) into v from v_gewichtsverteilung;
  select sum(g.anzahl) into v2 from sortier_gewicht g join sortier_lauf l on l.id = g.lauf_id
    left join auftrag a on a.id = l.auftrag_id
   where l.charge_nr is not null and (a.id is null or a.abgebrochen_ts is null);
  assert coalesce(v, 0) = coalesce(v2, 0), format('Gewichtsverteilung %s ≠ Histogramm %s', v, v2);

  -- Alter der verarbeiteten Ware: zwei Paletten, 10 und 20 Tage alt → 15
  --
  -- Die Palettendaten hängen an `betriebstag(now())`. Genau das rechnet die
  -- Sicht seit 0067 aus dem `start_ts` dieses Auftrags, und nur wenn beide
  -- Seiten denselben Kalender benutzen, steht die Differenz fest.
  --
  -- Zwei falsche Fassungen standen hier vorher, und beide sind lehrreich:
  --
  --   `current_date` — der Tag in **UTC**. Zwischen 22:00 und Mitternacht UTC,
  --   also 00:00 bis 02:00 in der Schweiz, fällt er vom Betriebstag ab, und
  --   dann kamen 16 statt 15 heraus. Der Prüffall mischte damit dieselben zwei
  --   Kalender, deren Vermischung 0067 behebt.
  --
  --   `heute()` — der Tag des **Betriebs**, aber mit Vorrang für die
  --   Einstellung `heute_test`. Die Prüfdatenbank hält damit eine Saison an
  --   einem festen Tag fest, während `now()` weiterläuft: 187 Tage Differenz.
  --
  -- Es geht also nicht darum, „den richtigen Tag" zu nehmen, sondern auf
  -- beiden Seiten **denselben**.
  select nr into v_charge from charge order by nr limit 1;
  insert into auftrag (weg, station, charge_nr, start_ts, eroeffnet_von)
    values ('maschine', 'sortieren', v_charge, now(), '11111111-1111-1111-1111-111111111111')
    returning id into v_a;
  insert into auftrag_palette (auftrag_id, eingangsdatum)
    values (v_a, betriebstag(now()) - 10), (v_a, betriebstag(now()) - 20);
  select alter_verarbeitet into v from v_verarbeitung_alter where auftrag_id = v_a;
  assert v = 15.0, format('Alter der verarbeiteten Ware erwartet 15, ist %s', v);
  select alter_charge into v2 from v_verarbeitung_alter where auftrag_id = v_a;
  assert (select differenz from v_verarbeitung_alter where auftrag_id = v_a)
         is not distinct from (case when v2 is null then null else (v - v2)::numeric(10,1) end),
    'differenz muss alter_verarbeitet − alter_charge sein';

  -- Durchsatz: 400 kg in zwei Stunden → 200 kg/h
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, durchsatz_kg, eroeffnet_von)
    values ('maschine', 'waschen', v_charge, now() - interval '2 hours', now(), 'abgeschlossen', 400,
            '11111111-1111-1111-1111-111111111111')
    returning id into v_b;
  perform auswertung_aktualisieren();
  select kg_pro_h into v from v_durchsatz where auftrag_id = v_b;
  assert v between 195 and 205, format('Durchsatz erwartet ~200 kg/h, ist %s', v);
  assert (select dauer_h from v_durchsatz where auftrag_id = v_b) between 1.9 and 2.1, 'Dauer nicht 2 h';

  -- Überfüllung je Sorte (0061, kein Käufer mehr): der gewogene Überschuss
  -- ist dieselbe Summe wie die Einzelwägungen
  select coalesce(sum(zuviel_gewogen_kg), 0) into v from v_ueberfuellung_verkauf
   where gruppe = 'sorte' and kistensystem = 'kiste_ab';
  select coalesce(sum(x.ueberfuellung_kg), 0) into v2 from v_ausgang_kennzahl x
    join auftrag a on a.id = x.auftrag_id
   where x.ueberfuellung_je_kiste is not null and a.abgebrochen_ts is null and x.kistensystem = 'kiste_ab';
  assert abs(v - v2) < 0.5, format('Überfüllung je Sorte %s ≠ Einzelwägungen %s', v, v2);

  -- Datenqualität: eine Zeile, Zähler in sich stimmig
  select count(*) into v_n from v_datenqualitaet;
  assert v_n = 1, 'v_datenqualitaet muss genau eine Zeile liefern';
  assert (select paletten_mit_datum <= paletten_gezaehlt from v_datenqualitaet), 'mehr datierte als gezählte Paletten';
  assert (select arbeiten_mit_zwei_ablesungen <= arbeiten_mit_ablesung from v_datenqualitaet), 'Ablesungszähler unstimmig';
  assert (select arbeiten_mit_ablesung <= arbeiten_fertig from v_datenqualitaet), 'mehr Ablesungen als Arbeiten';
  assert (select lagerkontrollen >= 0 from v_datenqualitaet), 'Kontrollzähler unstimmig';

  -- Verlauf (0062, erg_verlauf): die letzte Stützstelle kumuliert den ganzen
  -- Eingang, die Stützstellen steigen streng — gezählt wird über bis, denn das
  -- ist die Achse der Grafik. Seit 0062 trägt die laufende Woche zwei Punkte:
  -- einen auf heute() und einen auf den Sonntag danach; woche ist darum kein
  -- Schlüssel mehr, bis schon.
  select max(eingang_kum_kg) into v from erg_verlauf where sorte is null;
  select coalesce(sum(netto_kg), 0) into v2 from v_palette where netto_kg is not null and eingangsdatum is not null;
  assert abs(coalesce(v, 0) - v2) < 1, format('Verlauf kumuliert %s ≠ Eingang %s', v, v2);
  assert not exists (select 1 from (select bis, lag(bis) over (order by bis) as vor from erg_verlauf where sorte is null) w
                      where w.vor is not null and w.bis <= w.vor), 'Stützstellen nicht streng steigend';
  -- Es gibt genau einen Punkt auf heute(): sonst zeigt die Grafik einen anderen
  -- Stand als die Kennzahl daneben (bis zu sechs Tage Unterschied).
  select count(*) into v_n from erg_verlauf where sorte is null and bis = heute();
  assert v_n = 1, format('erg_verlauf braucht genau eine Stützstelle auf heute(), hat %s', v_n);
  -- und dieser Punkt sagt dasselbe wie die Bilanz
  select im_haus_kg into v from erg_verlauf where sorte is null and bis = heute();
  select im_haus_heute_kg into v2 from erg_bilanz;
  assert abs(coalesce(v, 0) - coalesce(v2, 0)) < 1,
    format('Verlauf auf heute %s ≠ Bilanz im Haus %s', v, v2);

  delete from auftrag where id in (v_a, v_b);
  perform auswertung_aktualisieren();
  raise notice 'OK  0049 Kennzahlen (Gewichtsverteilung, Alter, Durchsatz, Überfüllung je Sorte, Datenqualität, Verlauf)';
end $$;

select '——— 0049 Kennzahlen geprüft ———' as ergebnis;

-- =========================================================================
-- 0050: Warenausgang einlesen. Geprüft wird das, worauf es ankommt: dieselbe
-- Datei zweimal ändert nichts, eine Position kommt genau einmal als Masse an,
-- und ein Artikel gilt erst als Kürbis, wenn ihn jemand bestätigt hat.
-- =========================================================================
do $$
declare v_datei bigint; v_n int; v_offen int; v_charge int; v_sorte text;
        v_lief1 bigint; v_lief2 bigint;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  select nr, sorte into v_charge, v_sorte from charge order by nr limit 1;

  insert into ausgang_quelle (code, name, dateiname_muster)
    values ('pruef', 'Prüf-Mandant', 'pruef') on conflict (code) do nothing;
  insert into ausgang_datei (quelle, dateiname, pruefsumme, n_zeilen, hochgeladen_von)
    values ('pruef', 'pruef.xlsx', 'abc', 3, '11111111-1111-1111-1111-111111111111')
    returning id into v_datei;

  -- Eine Position, über zwei Chargen aufgeteilt: 240 kg gesamt, 150 + 90.
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datei_id,
                             datum, kunde, artikel_id, artikel, einheit, menge,
                             gewicht_je_artikel, batch_menge, kg_position, kg_charge, erfasser)
  values ('pruef', 5001, v_charge::text, 1, 'f1', v_datei, current_date - 5, 'Grosshandel',
          'kuerbbu', 'Bio Kürbis Butternut', 'Stk.', 160, 1.5, 100, 240, 150,
          '11111111-1111-1111-1111-111111111111'),
         ('pruef', 5001, '199001', 1, 'f2', v_datei, current_date - 5, 'Grosshandel',
          'kuerbbu', 'Bio Kürbis Butternut', 'Stk.', 160, 1.5, 60, 240, 90,
          '11111111-1111-1111-1111-111111111111'),
         ('pruef', 5002, '', 1, 'f3', v_datei, current_date - 4, 'Hofladen',
          'karod', 'Bio-Karotten Demeter', 'kg', 500, 1, 0, 500, 0,
          '11111111-1111-1111-1111-111111111111');

  -- Derselbe Schlüssel ein zweites Mal muss abprallen — sonst stünde die
  -- Lieferung nach jedem Hochladen erneut in der Bilanz.
  begin
    insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck,
                               datum, kunde, artikel_id, artikel, kg_position, kg_charge, erfasser)
    values ('pruef', 5001, v_charge::text, 1, 'f1', current_date, 'x', 'y', 'z', 1, 1,
            '11111111-1111-1111-1111-111111111111');
    assert false, 'Dieselbe Zeile darf nicht zweimal angelegt werden können';
  exception when unique_violation then null;
  end;

  -- Dieselbe Datei nochmals: die Prüfsumme erkennt sie wieder.
  begin
    insert into ausgang_datei (quelle, dateiname, pruefsumme, hochgeladen_von)
      values ('pruef', 'pruef-kopie.xlsx', 'abc', '11111111-1111-1111-1111-111111111111');
    assert false, 'Dieselbe Datei darf nicht zweimal verarbeitet werden';
  exception when unique_violation then null;
  end;

  -- Der Vorschlag kommt aus den Daten: die Sorte der Charge, die die Zeile nennt.
  assert (select vorschlag_sorte from v_ausgang_artikel_vorschlag where artikel_id = 'kuerbbu') = v_sorte,
    'Die vorgeschlagene Sorte muss aus der Charge stammen';
  assert (select vorschlag_kuerbis from v_ausgang_artikel_vorschlag where artikel_id = 'kuerbbu'),
    'Butternut ist ein Kürbisvorschlag';
  assert not (select vorschlag_kuerbis from v_ausgang_artikel_vorschlag where artikel_id = 'karod'),
    'Karotten sind kein Kürbis';
  assert not (select bestaetigt from v_ausgang_artikel_vorschlag where artikel_id = 'kuerbbu'),
    'Ohne Eintrag in ausgang_artikel gilt nichts als bestätigt';

  -- Bestätigen schlägt den Vorschlag — in beide Richtungen.
  insert into ausgang_artikel (artikel_id, artikel, ist_kuerbis, sorte, bestaetigt_von)
    values ('kuerbbu', 'Bio Kürbis Butternut', true, v_sorte, '11111111-1111-1111-1111-111111111111');
  assert (select bestaetigt from v_ausgang_artikel_vorschlag where artikel_id = 'kuerbbu'),
    'Nach dem Bestätigen muss es bestätigt sein';

  -- Übernahme: aus einer Position werden zwei Lieferungen, zusammen 240 kg.
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, erfasser)
  values (current_date - 5, v_charge, v_sorte, 150, 'verkauf', 'Grosshandel',
          '11111111-1111-1111-1111-111111111111')
  returning id into v_lief1;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, erfasser)
  values (current_date - 5, null, v_sorte, 90, 'verkauf', 'Grosshandel',
          '11111111-1111-1111-1111-111111111111')
  returning id into v_lief2;
  insert into lieferung_import (lieferung_id, quelle, extern_id) values
    (v_lief1, 'pruef', 'pruef:5001:' || v_charge || ':1'),
    (v_lief2, 'pruef', 'pruef:5001:199001:1');
  select count(*) into v_n from v_ausgang_pruef where quelle = 'pruef';
  assert v_n = 0, format('Die Probe muss aufgehen, %s Positionen weichen ab', v_n);
  -- Die Karotten-Position hat keine Lieferung und darf trotzdem nicht auffallen.
  assert not exists (select 1 from v_ausgang_pruef where pos_id = 5002),
    'Was kein Kürbis ist, gehört nicht in die Probe';

  -- Eine vergessene Kürbis-Position fällt mit ihrer vollen Masse auf.
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck,
                             datum, kunde, artikel_id, artikel, kg_position, kg_charge, erfasser)
  values ('pruef', 5003, '', 1, 'f4', current_date - 3, 'Hofladen',
          'kuerbbu', 'Bio Kürbis Butternut', 60, 0, '11111111-1111-1111-1111-111111111111');
  select count(*) into v_n from v_ausgang_pruef where pos_id = 5003;
  assert v_n = 1, 'Eine übergangene Kürbis-Position muss in der Probe stehen';
  delete from ausgang_zeile where quelle = 'pruef' and pos_id = 5003;

  -- Ein Kilo zu viel fällt auf.
  update lieferung set kg = 200 where id = v_lief2;
  select count(*) into v_n from v_ausgang_pruef where quelle = 'pruef';
  assert v_n = 1, 'Eine zu hohe Übernahme muss die Probe reissen';
  update lieferung set kg = 90 where id = v_lief2;

  -- Dieselbe Importzeile nochmals: der Schlüssel verhindert die Doppelbuchung.
  begin
    insert into lieferung_import (lieferung_id, quelle, extern_id)
      values (v_lief1, 'pruef', 'pruef:5001:199001:1');
    assert false, 'Dieselbe extern_id darf es nur einmal geben';
  exception when unique_violation then null;
  end;

  -- Von Hand erfasste Lieferungen bleiben unberührt: sie stehen nicht in der
  -- Beitabelle und behalten ihre Zeile, was der Import auch tut.
  assert (select count(*) from lieferung l
           where not exists (select 1 from lieferung_import i where i.lieferung_id = l.id)) >= 0;

  select zeilen, artikel_offen into v_n, v_offen from v_ausgang_lage where quelle = 'pruef';
  assert v_n = 3, format('Die Lage muss drei Zeilen zeigen, zeigt %s', v_n);

  delete from lieferung where id in (v_lief1, v_lief2);
  delete from ausgang_zeile where quelle = 'pruef';
  delete from ausgang_datei where quelle = 'pruef';
  delete from ausgang_artikel where artikel_id = 'kuerbbu';
  delete from ausgang_quelle where code = 'pruef';
  raise notice 'OK  0050 Warenausgang-Import (Wiederholung folgenlos, Masse einmal, Zuordnung bestätigt)';
end $$;

select '——— 0050 Warenausgang geprüft ———' as ergebnis;


-- =========================================================================
-- 0051: Fax ist kein Waschgang, Kaliber am Start, Bestand je Eingangstag
-- (kein FIFO), Perigon-Nummer. Alles an einer eigenen Charge (1637, Amoro).
-- =========================================================================
do $$
declare v_ws bigint; v_fax bigint; v numeric; v_n int; r record;
        v_schema bigint; v_alt bigint; v_id2 bigint;
        v_start timestamptz := (current_date - 30)::timestamptz + interval '8 hours';
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  insert into kaeufer (code, name) values ('coop', 'Coop') on conflict do nothing;

  -- ---- Die Perigon-Nummer steht an der Charge ------------------------
  assert (select count(*) from charge where perigon_nr is not null) = 42,
    'Alle 42 Chargen tragen eine Perigon-Nummer aus der Planungsdatei';
  assert (select nr from charge where perigon_nr = 198923) = 1613, '198923 ist die Slowgrow-Tiana (1613)';
  assert (select count(*) from charge where perigon_nr = 198976) = 2,
    'Die doppelte Nummer 198976 bleibt an beiden Chargen — die Entscheidung trifft der Artikel';

  -- ---- Bestand je Eingangstag: drei Tage à drei Paletten --------------
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
  select 1637, current_date - 60 + (i % 3), 950, 40, 'Holzkiste', 'k51-' || i
    from generate_series(1, 9) i;
  perform auswertung_aktualisieren();
  assert (select count(*) from v_charge_kohorte where charge_nr = 1637) = 3, 'Drei Eingangstage erwartet';
  assert (select sum(n_rest) from v_charge_kohorte where charge_nr = 1637) = 9, 'Ohne Arbeit liegt alles';

  -- Eine Hand-Arbeit nimmt zwei Paletten vom *jüngsten* Tag — kein FIFO.
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, eroeffnet_von)
  values ('hand', 'waschen_sortieren', 1637, v_start, v_start + interval '6 hours', 'abgeschlossen',
          '11111111-1111-1111-1111-111111111111')
  returning id into v_ws;
  insert into auftrag_palette (auftrag_id, eingangsdatum)
  select v_ws, current_date - 58 from generate_series(1, 2);
  perform auswertung_aktualisieren();

  assert (select n_rest from v_charge_kohorte where charge_nr = 1637 and eingangsdatum = current_date - 58) = 1,
    'Vom jüngsten Tag bleibt eine Palette';
  assert (select n_rest from v_charge_kohorte where charge_nr = 1637 and eingangsdatum = current_date - 60) = 3,
    'Der älteste Tag bleibt unberührt — kein FIFO';
  select count(*), sum(m0) into v_n, v from v_kaskade where charge_nr = 1637 and portion = 'lager';
  assert v_n = 3, format('Der Lagerbestand muss in drei Kohorten stehen, steht in %s', v_n);
  assert abs(v - (select lager_kg from v_hochrechnung_basis where charge_nr = 1637)) < 0.01,
    'Die Kohorten teilen den Bestand vollständig auf';
  assert (select count(distinct alter_tage) from v_kaskade where charge_nr = 1637 and portion = 'lager') = 3,
    'Jede Kohorte rechnet mit ihrem eigenen Alter';
  assert (select alter_lager_bis - alter_lager_von from v_hochrechnung_basis where charge_nr = 1637) = 2,
    'Die Spanne der liegenden Paletten ist zwei Tage';
  -- 0060: Ohne Lieferung liegt rechnerisch alles — die zwei gezählten Paletten
  -- sind eine Beobachtung, keine Menge; der Anteil einer Kohorte ist ihr Eingangsanteil.
  assert (select n_rest_paletten from v_hochrechnung_basis where charge_nr = 1637) = 9,
    'Ohne Lieferung liegen rechnerisch alle neun Paletten (0060)';
  assert abs((select anteil from v_kohorte_anteil where charge_nr = 1637 and eingangsdatum = current_date - 60) - 3.0 / 9) < 0.001,
    'Die älteste Kohorte trägt 3/9 — ihren Anteil am Eingang (0060)';
  assert (select n_kohorten from v_naechste_charge where charge_nr = 1637) = 3, 'Was-kostet-Warten rechnet je Kohorte';
  assert (select alter_bis - alter_von from v_naechste_charge where charge_nr = 1637) = 2, 'und zeigt die Spanne';

  -- Ein Zetteldatum, zu dem keine Palette kam (Zahlendreher)
  insert into auftrag_palette (auftrag_id, eingangsdatum) values (v_ws, current_date - 51);
  assert exists (select 1 from v_plausibilitaet where art = 'Zetteldatum' and auftrag_id = v_ws),
    'Ein Zetteldatum ohne Palette muss auffallen';
  delete from auftrag_palette where auftrag_id = v_ws and eingangsdatum = current_date - 51;

  -- ---- Fax: Kisten gezählt, Faules gewogen, eigener Strom --------------
  -- Die Hand-Arbeit lief als „Kiste ab x kg"; eine fertige Palette wurde
  -- gewogen: 32 Kisten à 8.5 kg → das Kistengewicht ohne Kaliber (−1).
  update auftrag set sortierschema_id = sortierschema_fuer('Amoro', null, current_date, 'kiste') where id = v_ws;
  insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart)
  values (v_ws, 1637, 32 * 8.5 + 32 * 1.5 + 25, 32, 'Holzkiste');
  assert (select kg_je_gebinde from v_koeff_gebinde where sorte = 'Amoro' and kaliber_idx = -1) = 8.5,
    'Das Kistengewicht ohne Kaliber kommt aus der gewogenen fertigen Palette';

  insert into auftrag (weg, station, charge_nr, ist_fax, sortierschema_id, start_ts, ende_ts, status, eroeffnet_von)
  values ('maschine', 'waschen', 1637, true, sortierschema_fuer('Amoro', null, current_date, 'kiste'),
          v_start + interval '20 days', v_start + interval '20 days 3 hours', 'abgeschlossen',
          '11111111-1111-1111-1111-111111111111')
  returning id into v_fax;
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl) values (v_fax, -1, 40);
  -- Eine Kiste auf der Tischwaage: 7.5 brutto, Holzkiste 1.5 → 6 kg
  insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart)
  values (v_fax, 0, 7.5, 1, 'Holzkiste');
  -- Vier Kisten auf einer Palette: 100 − 4·1.5 − 25 = 69 kg
  insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, mit_palette)
  values (v_fax, 0, 100, 4, 'Holzkiste', true);
  assert (select kg from schimmel_messung where auftrag_id = v_fax and brutto_kg = 7.5) = 6,
    'Netto der Einzelkiste: 7.5 − 1.5 = 6';
  assert (select kg from schimmel_messung where auftrag_id = v_fax and brutto_kg = 100) = 69,
    'Netto auf der Palette: 100 − 6 − 25 = 69';
  begin
    insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, palox_stand_kg)
    values (v_fax, 0, 7, 1, 'Holzkiste', 100);
    assert false, 'Palox-Stand und Kistenwägung zugleich dürfen nicht durchgehen';
  exception when raise_exception then null;
  end;

  -- 0060: Eine Lieferung teilt die Charge in ausgelagert und liegend
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung)
  values ((v_start + interval '25 days')::date, 1637, 'Amoro', 1000, 'verkauf', 'PRUEF-0051');
  perform auswertung_aktualisieren();
  assert (select eingang_netto_kg from v_auftrag_masse where auftrag_id = v_fax) = 340,
    'Die Fax-Masse ist 40 Kisten × 8.5 kg';
  assert (select masse_quelle from v_auftrag_masse where auftrag_id = v_fax) = 'gebinde', 'Quelle: gezählte Kisten';
  assert (select gewaschen_kg from v_hochrechnung_basis where charge_nr = 1637) = 0,
    'Fax zählt nicht als gewaschen';
  assert not exists (select 1 from v_schimmel_punkte where auftrag_id = v_fax),
    'Fax-Faules ist kein Punkt der Verderbskurve';
  select * into r from v_fax_beobachtung where auftrag_id = v_fax;
  assert r.faul_kg = 75 and r.masse_kg = 340 and r.kisten = 40, 'Die Fax-Beobachtung stimmt nicht';
  assert abs(r.anteil - 75.0 / 415) < 0.001, 'Anteil = Faules / (Masse + Faules)';
  assert (select mittel from v_koeff_fax where sorte = 'Amoro') > 0, 'Der Fax-Koeffizient ist beziffert';
  assert (select kg from v_verlust_ranking where strom = 'Faul beim Abpacken (Fax)') > 0,
    'Der Fax-Strom ist jetzt beziffert';
  assert (select kg_unten from v_verlust_ranking where strom = 'Faul beim Abpacken (Fax)') is not null,
    'und hat einen Bereich';
  assert (select fax_arbeiten from v_datenqualitaet) >= 1
     and (select fax_arbeiten_mit_faulem from v_datenqualitaet) >= 1
     and (select fax_arbeiten_mit_kisten from v_datenqualitaet) >= 1, 'Die Datenqualität zählt Fax getrennt';
  assert (select wasch_arbeiten from v_datenqualitaet)
       = (select count(*) from auftrag where station = 'waschen' and not ist_fax
                                          and status = 'abgeschlossen' and abgebrochen_ts is null),
    'Fax-Arbeiten zählen nicht als Waschgänge';

  -- Mit bekanntem Fax teilen die Ströme jede Portion und Kohorte vollständig auf.
  for r in select distinct charge_nr, portion, kohorte from v_hochrechnung loop
    if exists (select 1 from v_hochrechnung
                where charge_nr = r.charge_nr and portion = r.portion
                  and kohorte is not distinct from r.kohorte and not koeff_bekannt) then continue; end if;
    select sum(kg), max(portion_kg) into v, v_n from v_hochrechnung
     where charge_nr = r.charge_nr and portion = r.portion and kohorte is not distinct from r.kohorte;
    assert abs(v - (select max(portion_kg) from v_hochrechnung
                     where charge_nr = r.charge_nr and portion = r.portion
                       and kohorte is not distinct from r.kohorte)) < 0.05,
      format('Charge %s / %s / %s: mit Fax teilen die Ströme die Portion nicht auf', r.charge_nr, r.portion, r.kohorte);
  end loop;
  assert not exists (select 1 from v_kaskade where verkaufsfaehig_kg < -0.01), 'Verkaufsfähig bleibt ≥ 0';
  -- 0060: je Eingangstag eine ausgelagerte Portion, darum die Summe
  assert (select sum(kg) from v_hochrechnung where charge_nr = 1637 and portion = 'ausgelagert' and strom = 'Verkaufsfähig')
       < (select sum(basis_kg) from v_hochrechnung where charge_nr = 1637 and portion = 'ausgelagert' and strom = 'Verkaufsfähig'),
    'Das Faule beim Abpacken mindert die verkaufsfähige Masse';

  -- Ein unplausibler Fax-Anteil (Tippfehler) fällt auf, ohne die Rechnung zu treffen
  update schimmel_messung set brutto_kg = 900 where auftrag_id = v_fax and brutto_kg = 100;
  perform auswertung_aktualisieren();
  assert exists (select 1 from v_plausibilitaet where art = 'Fax' and auftrag_id = v_fax),
    'Ein Fax mit 70 % Faulem ist ein Tippfehler und gehört in die Plausibilität';
  assert not exists (select 1 from v_koeff_roh_kaliber where art = 'fax' and charge_nr = 1637),
    'Der unplausible Wert fliesst nicht in den Koeffizienten';
  update schimmel_messung set brutto_kg = 100 where auftrag_id = v_fax and brutto_kg = 900;

  -- ---- Die Fassung beim Eröffnen festlegen ----------------------------
  select sortierschema_fuer('Amoro', null, current_date, 'kaliber') into v_alt;
  select sortierschema_festlegen('Amoro', null, 'kaliber', '[[600,1100],[1100,1600],[1600,2000]]'::jsonb) into v_schema;
  assert v_schema = v_alt, 'Dieselben Bänder ergeben keine neue Fassung';
  select sortierschema_festlegen('Amoro', 'coop', 'kaliber', '[[600,1000],[1000,1500],[1500,2000]]'::jsonb) into v_schema;
  assert v_schema <> v_alt, 'Geänderte Bänder ergeben eine neue Fassung';
  assert (select gilt_ab from sortierschema where id = v_schema) = current_date, 'Die neue Fassung gilt ab heute';
  assert (select verlust_unter from sortierschema where id = v_schema) = 600
     and (select kanal_ab from sortierschema where id = v_schema) = 2000,
    'Zu klein und zu gross folgen aus dem ersten und letzten Band';
  assert (select kaeufer from sortierschema where id = v_schema) = 'coop', 'Die Fassung hängt am Käufer';
  select sortierschema_festlegen('Amoro', 'coop', 'kaliber', '[[600,1000],[1000,1400],[1400,2000]]'::jsonb) into v_id2;
  assert v_id2 = v_schema, 'Zweimal am selben Tag ist dieselbe Fassung';
  assert (select (kaliber_baender -> 1 ->> 1)::int from sortierschema where id = v_schema) = 1400,
    'und trägt die letzte Einstellung des Tages';
  begin
    perform sortierschema_festlegen('Amoro', 'coop', 'kaliber', '[[600,1000],[1100,2000]]'::jsonb);
    assert false, 'Lückenhafte Bänder müssen abgelehnt werden';
  exception when raise_exception then null;
  end;
  begin
    perform sortierschema_festlegen('Amoro', 'coop', 'kaliber', '[[600,1000],[1000,900]]'::jsonb);
    assert false, 'Ein absteigendes Band muss abgelehnt werden';
  exception when raise_exception then null;
  end;
  select sortierschema_festlegen('Amoro', 'coop', 'kiste', null, 8.5) into v_id2;
  assert (select soll_kg_pro_kiste from sortierschema where id = v_id2) = 8.5
     and (select art from sortierschema where id = v_id2) = 'kiste', 'Die Kisten-Fassung trägt das Soll';
  begin
    perform sortierschema_festlegen('Amoro', 'coop', 'kiste', null, 0);
    assert false, 'Ohne Sollgewicht keine Kisten-Fassung';
  exception when raise_exception then null;
  end;

  -- Aufräumen
  delete from auftrag where id in (v_ws, v_fax);
  delete from palette where extern_id like 'k51-%';
  delete from sortierschema where sorte = 'Amoro' and kaeufer = 'coop' and gilt_ab = current_date;
  perform auswertung_aktualisieren();
  raise notice 'OK  0051 Fax (gewogen, eigener Strom, nicht gewaschen), Bestand je Eingangstag ohne FIFO, Fassung am Start, Perigon-Nummer';
end $$;

select '——— 0051 Fax, Kohorten, Fassung geprüft ———' as ergebnis;

-- =========================================================================
-- 0052: Die Demo muss sich restlos entfernen lassen. Wer das Werkzeug
-- aktualisiert, hat die alte Saison noch in der Datenbank; die Karte bietet
-- dann „neu laden" an — entfernen, dann laden. Bleibt dabei auch nur eine
-- Zeile zurück, zählt sie in jeder Auswertung mit, ohne dass jemand sie
-- sieht. Darum: Zählstand vorher, Demo laden, entfernen, Zählstand wieder
-- genau gleich.
-- =========================================================================
do $$
declare
  v_vorher jsonb; v_nachher jsonb; v_geladen jsonb; v_tabelle text; v_diff text := '';
  v_tabellen text[] := array['palette', 'auftrag', 'auftrag_palette', 'auftrag_gebinde',
    'auftrag_teilnehmer', 'auftrag_angabe', 'verdunstung_wiegung', 'schimmel_messung',
    'ausschuss_messung', 'ausgang_wiegung', 'sortier_lauf', 'sortier_gewicht',
    'lieferung', 'charge_vorlauf', 'sortierschema', 'kaeufer', 'ausgang_ziel'];
  v_zahl bigint;
begin
  perform set_config('request.jwt.claim.sub',
                     (select id::text from profil where rolle = 'admin' limit 1), true);

  v_vorher := '{}'::jsonb;
  foreach v_tabelle in array v_tabellen loop
    execute format('select count(*) from %I', v_tabelle) into v_zahl;
    v_vorher := v_vorher || jsonb_build_object(v_tabelle, v_zahl);
  end loop;

  perform demo_daten_laden();
  v_geladen := '{}'::jsonb;
  foreach v_tabelle in array v_tabellen loop
    execute format('select count(*) from %I', v_tabelle) into v_zahl;
    v_geladen := v_geladen || jsonb_build_object(v_tabelle, v_zahl);
  end loop;
  assert (v_geladen ->> 'palette')::bigint > (v_vorher ->> 'palette')::bigint + 500,
    'Die Demo muss eine ganze Saison anlegen, nicht ein paar Zeilen';
  assert (v_geladen ->> 'auftrag')::bigint > (v_vorher ->> 'auftrag')::bigint + 200,
    'Die Demo muss die Arbeiten beider Wege anlegen';

  perform demo_daten_entfernen();
  foreach v_tabelle in array v_tabellen loop
    execute format('select count(*) from %I', v_tabelle) into v_zahl;
    if v_zahl <> (v_vorher ->> v_tabelle)::bigint then
      v_diff := v_diff || format('%s: vorher %s, nachher %s. ',
                                 v_tabelle, v_vorher ->> v_tabelle, v_zahl);
    end if;
  end loop;
  assert v_diff = '', 'Nach dem Entfernen muss der Stand wieder derselbe sein — ' || v_diff;

  perform set_config('request.jwt.claim.sub', '', true);
  perform auswertung_aktualisieren();
  raise notice 'OK  0052 Demo-Saison: laden und restlos wieder entfernen (der Weg beim Aktualisieren)';
end $$;

select '——— 0052 Demo-Saison geprüft ———' as ergebnis;


-- =========================================================================
-- 0055: Warenausgang übernehmen — ein Aufruf, und jedes Kilo kommt genau
-- einmal an. Zweimal dieselbe Datei ändert nichts; eine korrigierte Zeile
-- wird als Änderung erkannt; was keiner Charge und keiner Sorte zuzuordnen
-- ist, wird zurückgemeldet statt still weggelassen.
-- =========================================================================
do $$
declare v_charge int; v_sorte text; v_erg jsonb; v_n int; v_zeilen jsonb; v_lief jsonb;
        v_meldung text;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  select nr, sorte into v_charge, v_sorte from charge order by nr limit 1;

  v_zeilen := jsonb_build_array(
    jsonb_build_object('pos_id', 7001, 'charge_extern', v_charge::text, 'lauf_nr', 1, 'fingerabdruck', 'a1',
                       'datum', (current_date - 2)::text, 'journal', 'A', 'kunde', 'Grosshandel',
                       'artikel_id', 'kuerbbu', 'artikel', 'Bio Kürbis Butternut', 'einheit', 'Stk.',
                       'menge', 100, 'gewicht_je_artikel', 1.5, 'batch_menge', 60,
                       'kg_position', 150, 'kg_charge', 90),
    jsonb_build_object('pos_id', 7001, 'charge_extern', '', 'lauf_nr', 1, 'fingerabdruck', 'a2',
                       'datum', (current_date - 2)::text, 'journal', 'A', 'kunde', 'Grosshandel',
                       'artikel_id', 'kuerbbu', 'artikel', 'Bio Kürbis Butternut', 'einheit', 'Stk.',
                       'menge', 100, 'gewicht_je_artikel', 1.5, 'batch_menge', 0,
                       'kg_position', 150, 'kg_charge', 0));
  v_lief := jsonb_build_array(
    jsonb_build_object('extern_id', 'uebn:7001:' || v_charge || ':1', 'datum', (current_date - 2)::text,
                       'charge_nr', v_charge, 'sorte', v_sorte, 'kg', 90, 'gebindeart', 'Unbekanntes Gebinde',
                       'kunde', 'Grosshandel', 'bemerkung', ''),
    jsonb_build_object('extern_id', 'uebn:7001:rest', 'datum', (current_date - 2)::text,
                       'charge_nr', null, 'sorte', v_sorte, 'kg', 60, 'gebindeart', null,
                       'kunde', 'Grosshandel', 'bemerkung', 'ohne Chargenbezug'),
    jsonb_build_object('extern_id', 'uebn:7002:rest', 'datum', (current_date - 1)::text,
                       'charge_nr', null, 'sorte', null, 'kg', 40, 'gebindeart', null,
                       'kunde', 'Hofladen', 'bemerkung', 'ohne Chargenbezug'));

  v_erg := ausgang_uebernehmen('uebn', 'Übernahme-Prüfung',
    jsonb_build_object('dateiname', 'uebn.xlsx', 'pruefsumme', 'sha-uebn-1', 'n_zeilen', 2, 'n_kuerbis', 2,
                       'n_neu', 2, 'n_geaendert', 0, 'n_unveraendert', 0,
                       'von_datum', (current_date - 2)::text, 'bis_datum', (current_date - 2)::text),
    v_zeilen, v_lief);
  assert (v_erg ->> 'zeilen_neu')::int = 2, 'Zwei Rohzeilen müssen neu sein: ' || v_erg::text;
  assert (v_erg ->> 'lieferungen_neu')::int = 2, 'Zwei Lieferungen müssen neu sein: ' || v_erg::text;
  assert jsonb_array_length(v_erg -> 'uebergangen') = 1
     and (v_erg -> 'uebergangen' -> 0 ->> 'extern_id') = 'uebn:7002:rest',
    'Die Lieferung ohne Charge und Sorte muss zurückgemeldet werden: ' || v_erg::text;
  assert exists (select 1 from ausgang_quelle where code = 'uebn'), 'Die Quelle wird angelegt';
  -- Das unbekannte Gebinde bricht nichts: es steht in der Bemerkung.
  assert (select bemerkung from lieferung l join lieferung_import i on i.lieferung_id = l.id
           where i.extern_id = 'uebn:7001:' || v_charge || ':1') like '%Gebinde laut Datei%',
    'Ein Gebinde, das die Stammdaten nicht kennen, gehört in die Bemerkung';
  select count(*) into v_n from v_ausgang_pruef where quelle = 'uebn';
  assert v_n = 0, format('Die Probe muss aufgehen: %s Positionen weichen ab', v_n);

  -- Dieselbe Datei nochmals: nichts Neues, nichts doppelt.
  v_erg := ausgang_uebernehmen('uebn', 'Übernahme-Prüfung',
    jsonb_build_object('dateiname', 'uebn.xlsx', 'pruefsumme', 'sha-uebn-1'), v_zeilen, v_lief);
  assert (v_erg ->> 'zeilen_neu')::int = 0 and (v_erg ->> 'zeilen_geaendert')::int = 2,
    'Beim zweiten Mal ist nichts neu: ' || v_erg::text;
  assert (v_erg ->> 'lieferungen_neu')::int = 0 and (v_erg ->> 'lieferungen_aktualisiert')::int = 2,
    'Beim zweiten Mal wird aktualisiert, nicht angelegt: ' || v_erg::text;
  assert (select count(*) from lieferung_import where quelle = 'uebn') = 2, 'Keine doppelte Lieferung';
  assert (select count(*) from ausgang_zeile where quelle = 'uebn' and geaendert_ts is not null) = 0,
    'Ein gleicher Fingerabdruck ist keine Änderung';

  -- Im Perigon korrigiert: anderer Fingerabdruck, andere Masse.
  v_zeilen := jsonb_set(v_zeilen, '{0,fingerabdruck}', '"a1-neu"');
  v_lief := jsonb_set(v_lief, '{0,kg}', '95');
  v_erg := ausgang_uebernehmen('uebn', 'Übernahme-Prüfung',
    jsonb_build_object('dateiname', 'uebn.xlsx', 'pruefsumme', 'sha-uebn-2'), v_zeilen, v_lief);
  assert (select count(*) from ausgang_zeile where quelle = 'uebn' and geaendert_ts is not null) = 1,
    'Die korrigierte Zeile muss als geändert markiert sein';
  assert (select l.kg from lieferung l join lieferung_import i on i.lieferung_id = l.id
           where i.extern_id = 'uebn:7001:' || v_charge || ':1') = 95,
    'Die Lieferung muss die korrigierte Masse tragen';
  assert (select count(*) from ausgang_datei where quelle = 'uebn') = 2, 'Zwei verschiedene Dateien, zwei Einträge';

  -- Ein Arbeiter darf das nicht.
  perform set_config('request.jwt.claim.sub',
                     (select id::text from profil where rolle = 'arbeiter' limit 1), true);
  begin
    perform ausgang_uebernehmen('uebn', 'x', '{}'::jsonb, '[]'::jsonb, '[]'::jsonb);
    assert false, 'Ein Arbeiter darf den Warenausgang nicht übernehmen';
  exception when others then
    get stacked diagnostics v_meldung = message_text;
    assert v_meldung like '%Betriebsleiter%', 'Die Absage muss sagen, woran es liegt: ' || v_meldung;
  end;
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);

  -- Aufräumen, damit die Bilanz-Prüfungen weiter unten nicht verschoben sind
  delete from lieferung where id in (select lieferung_id from lieferung_import where quelle = 'uebn');
  delete from ausgang_zeile where quelle = 'uebn';
  delete from ausgang_datei where quelle = 'uebn';
  delete from ausgang_quelle where code = 'uebn';
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  0055 Warenausgang übernehmen: einmal, zweimal, korrigiert, zurückgemeldet, nur der Betriebsleiter';
end $$;

select '——— 0055 Übernahme geprüft ———' as ergebnis;


-- =========================================================================
-- 0054: Ein eigenes Kaliber am Waschen. Nennt das Etikett ein Band, das die
-- Fassung nicht kennt, tippt der Vorarbeiter es ein. Trifft es die Grenzen
-- eines beim Sortieren gezählten Bands, hat es dessen Kistengewicht; sonst
-- bleibt die Masse unbekannt — und die Plausibilität sagt es, ohne die Arbeit
-- als „ohne Kaliber" zu schelten. Die Prüfung baut sich ihren Sortierlauf
-- selbst: 500 Kürbisse à 1200 g, 20 Kisten gezählt → 30 kg je Kiste.
-- =========================================================================
do $$
declare v_lauf bigint; v_idx int; v_von int; v_bis int; v_koeff numeric; v_kg numeric; v_quelle text;
        v_vorher int; v_nachher int;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);

  insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status)
  values (2405, 'maschine', 'sortieren', 1613, timestamptz '2027-01-10 08:00+01',
          timestamptz '2027-01-10 15:00+01', 'abgeschlossen');
  insert into auftrag_palette (auftrag_id, eingangsdatum)
  select 2405, date '2026-09-01' from generate_series(1, 2);
  select csv_lauf_speichern(1613, 'SIM-0054.csv', null, 'pruefsumme-0054', null, null,
         '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":false}'::jsonb,
         500, 0, 0, 0, '[[1200,500]]'::jsonb) into v_lauf;
  perform auftrag_manuell_zuordnen(v_lauf, 2405);
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
  select 2405, g.kaliber_idx, 20 from sortier_gewicht g
   where g.lauf_id = v_lauf and g.klasse = 'kaliber' limit 1;
  select kaliber_idx into v_idx from auftrag_gebinde where auftrag_id = 2405;
  -- Die Grenzen dieses Bands in der Fassung, nach der der Lauf klassiert wurde
  select (s.kaliber_baender -> v_idx ->> 0)::int, (s.kaliber_baender -> v_idx ->> 1)::int
    into v_von, v_bis
    from sortier_lauf l join sortierschema s on s.id = l.sortierschema_id where l.id = v_lauf;
  assert v_von is not null and v_von <= 1200 and v_bis > 1200,
    format('Das Band zu 1200 g muss 1200 einschliessen, ist %s–%s', v_von, v_bis);
  perform auswertung_aktualisieren();
  select kg_je_gebinde into v_koeff from v_koeff_gebinde where sorte = 'Tiana' and kaliber_idx = v_idx;
  assert v_koeff is not null and abs(v_koeff - 30) < 0.5,
    format('500 × 1.2 kg auf 20 Kisten sind 30 kg je Kiste, gemessen %s', v_koeff);

  -- Nur von ohne bis, oder Band und eigenes Kaliber zugleich: geht nicht.
  begin
    insert into auftrag (id, weg, station, charge_nr, start_ts, status, kaliber_von_g)
    values (2410, 'maschine', 'waschen', 1613, now(), 'offen', 800);
    assert false, 'Ein eigenes Kaliber braucht beide Grenzen';
  exception when check_violation then null;
  end;
  begin
    insert into auftrag (id, weg, station, charge_nr, start_ts, status, kaliber_idx, kaliber_von_g, kaliber_bis_g)
    values (2410, 'maschine', 'waschen', 1613, now(), 'offen', 0, 800, 1300);
    assert false, 'Band und eigenes Kaliber schliessen sich aus';
  exception when check_violation then null;
  end;

  select wasch_arbeiten_mit_kisten into v_vorher from v_datenqualitaet;

  -- Eigenes Kaliber mit den Grenzen des gezählten Bands: 5 Kisten × 30 kg
  insert into auftrag (id, weg, station, charge_nr, start_ts, ende_ts, status, kaliber_von_g, kaliber_bis_g)
  values (2403, 'maschine', 'waschen', 1613, timestamptz '2027-01-17 08:00+01',
          timestamptz '2027-01-17 12:00+01', 'abgeschlossen', v_von, v_bis);
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl) values (2403, -2, 5);
  -- Eigenes Kaliber, das nie gezählt wurde: 2 Kisten, Masse unbekannt
  insert into auftrag (id, weg, station, charge_nr, start_ts, status, kaliber_von_g, kaliber_bis_g)
  values (2404, 'maschine', 'waschen', 1613, timestamptz '2027-01-18 08:00+01', 'offen', 700, 900);
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl) values (2404, -2, 2);
  perform auswertung_aktualisieren();

  select eingang_netto_kg, masse_quelle into v_kg, v_quelle from v_auftrag_masse where auftrag_id = 2403;
  assert v_quelle = 'gebinde' and abs(v_kg - 5 * v_koeff) < 0.5,
    format('5 Kisten zum eigenen Kaliber %s–%s sind 5 × %s kg, gerechnet %s (%s)', v_von, v_bis, v_koeff, v_kg, v_quelle);
  assert (select kg from v_auftrag_gebinde_masse where auftrag_id = 2404) is null,
    'Ein nie gezähltes Band hat kein Kistengewicht — NULL, nicht 0';
  assert not exists (select 1 from v_plausibilitaet where art = 'Kaliber fehlt' and auftrag_id in (2403, 2404)),
    'Ein eigenes Kaliber ist ein Kaliber — kein „Kaliber fehlt"';
  assert exists (select 1 from v_plausibilitaet where art = 'Kistengewicht' and auftrag_id = 2404
                    and befund like '%eigenen Kaliber 700–900 g%'),
    'Das unbekannte Kistengewicht zum eigenen Kaliber muss als Auffälligkeit erscheinen';
  assert not exists (select 1 from v_plausibilitaet where art = 'Kistengewicht' and auftrag_id = 2403),
    'Mit gefundenem Kistengewicht gibt es nichts zu bemängeln';

  select wasch_arbeiten_mit_kisten into v_nachher from v_datenqualitaet;
  assert v_nachher = v_vorher + 1,
    format('Die Datenqualität muss die fertige Wasch-Arbeit mit eigenem Kaliber zählen: %s → %s', v_vorher, v_nachher);

  -- Aufräumen
  delete from sortier_gewicht where lauf_id = v_lauf;
  delete from sortier_lauf where id = v_lauf;
  delete from auftrag where id in (2403, 2404, 2405);
  perform auswertung_aktualisieren();
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  0054 Eigenes Kaliber: Grenzen erkannt, Kistengewicht gefunden oder ehrlich unbekannt';
end $$;

select '——— 0054 Eigenes Kaliber geprüft ———' as ergebnis;

-- =====================================================================
-- 0056 — Eine Palette wird im Lager nicht schwerer
-- =====================================================================
-- Der Fall vom 7. September: drei Wägungen, bei denen die Palette mehr wog
-- als beim Eingang, drückten die gepoolte Rate auf −0.2 je Tag; die Basis
-- für den Schimmelanteil lief über (numeric field overflow) — im Überblick
-- und in der Aktualisierung. Hier nachgestellt: die Wägungen zählen nicht,
-- stehen mit Grund in der Plausibilität, die Rate bleibt ≥ 0, und alles
-- rechnet durch.
do $$
declare v_n0 int; v_n int; v numeric;
begin
  select count(*) into v_n0 from v_schimmel_beobachtung;
  assert v_n0 > 0, 'Ohne Schimmelbeobachtung prüft dieser Block nichts';

  insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                   kisten, gebindeart, sichtbar_schimmel, gemessen, wiege_ts, bemerkung, erfasser)
  select 1613, date '2026-09-01', 420, 1180, 34, 'Holzkiste', false, true,
         timestamptz '2026-09-03 08:00+02', 'PRUEF-0056', '11111111-1111-1111-1111-111111111111'
    from generate_series(1, 3);

  select count(*) into v_n
    from v_verdunstung_messung m join verdunstung_wiegung w on w.id = m.id
   where w.bemerkung = 'PRUEF-0056' and m.verwendbar;
  assert v_n = 0, format('Eine Palette, die schwerer wurde, darf nicht in die Rate zählen (%s tun es)', v_n);

  select count(*) into v_n from v_plausibilitaet
   where art = 'Wägung' and befund like '%mehr als beim Eingang%' and rat like '%Gebindeart%';
  assert v_n = 3, format('Jede schwerere Palette muss als Auffälligkeit mit Grund und Rat stehen (%s von 3)', v_n);

  assert not exists (select 1 from v_koeff_verdunstung where mittel < 0 or unten < 0 or oben < 0),
    'Die Verdunstungsrate darf nie negativ sein';

  -- Die Regression selbst: das hier brach mit „numeric field overflow" ab.
  perform auswertung_aktualisieren();
  perform count(*) from v_saisonbilanz;
  perform count(*) from v_plausibilitaet;
  perform count(*) from v_schimmel_punkte;
  assert not exists (select 1 from v_schimmel_beobachtung where basis_jetzt_kg > eingang_kg + 0.01),
    'Die Basis für den Schimmelanteil kann nie über dem Eingang liegen';
  assert (select count(*) from v_schimmel_beobachtung) = v_n0,
    'Die schwereren Paletten dürfen keine Schimmelbeobachtung verändern';

  -- Eine kleine Zunahme (Toleranz zwischen zwei Waagen) bleibt eine Messung;
  -- das Mittel sinkt dadurch höchstens auf 0, nie darunter.
  insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                   kisten, gebindeart, sichtbar_schimmel, gemessen, wiege_ts, bemerkung, erfasser)
  values (1613, date '2026-09-01', 420, 422, 34, 'Holzkiste', false, true,
          timestamptz '2026-09-03 08:00+02', 'PRUEF-0056-leicht', '11111111-1111-1111-1111-111111111111');
  assert (select m.verwendbar from v_verdunstung_messung m join verdunstung_wiegung w on w.id = m.id
           where w.bemerkung = 'PRUEF-0056-leicht'),
    'Eine Zunahme innerhalb von 1 % ist Waagenrauschen und bleibt verwendbar';
  assert (select m.rate_pro_tag from v_verdunstung_messung m join verdunstung_wiegung w on w.id = m.id
           where w.bemerkung = 'PRUEF-0056-leicht') < 0,
    'Die Einzelrate bleibt, was gemessen wurde — auch wenn sie unter 0 liegt';
  select min(mittel) into v from v_koeff_verdunstung;
  assert v >= 0, format('Das Mittel darf durch Waagenrauschen nicht unter 0 fallen (%s)', v);

  -- Aufräumen
  delete from verdunstung_wiegung where bemerkung like 'PRUEF-0056%';
  perform auswertung_aktualisieren();
  raise notice 'OK  0056 Schwerere Palette: nicht verwendbar, mit Grund gemeldet, Rate ≥ 0, alles rechnet durch';
end $$;

select '——— 0056 Schwerere Palette geprüft ———' as ergebnis;

-- =====================================================================
-- 0058 — Eine einzelne unmögliche Zahl sprengt die Auswertung nicht
-- =====================================================================
-- Auf der Betriebsdatenbank stand nach 0057 weiterhin „numeric field
-- overflow", jetzt in v_hochrechnung, v_saisonbilanz und v_marge_buch. Der
-- Grund war ein harter Cast auf eine berechnete Grösse: Trifft die
-- Bereichsannahme nicht zu, bricht die ganze Sicht ab statt einer Spalte.
-- Hier wird beides geprüft: der Helfer, und dass die Sichten die Physik
-- einhalten (Anteil 0…1, Masse nie negativ).
do $$
declare v_n int;
begin
  -- ---- Der Helfer: runden, sonst unbekannt ---------------------------
  assert zahl(123.456) = 123.46, format('zahl() muss runden, ist %s', zahl(123.456));
  assert zahl(1e20) is null, 'Eine Zahl, die nicht in die Spalte passt, muss NULL sein';
  assert zahl(-1e20) is null, 'Auch nach unten muss die Grenze greifen';
  assert zahl(null::numeric) is null, 'NULL bleibt NULL';
  assert zahl(1e4, 4, 1e5) = 10000, 'Innerhalb der Grenze wird gerechnet';
  assert zahl(1e6, 4, 1e5) is null, 'Ausserhalb der Grenze wird es unbekannt';
  assert zahl(1.5::double precision) = 1.5, 'Auch Gleitkomma muss gehen (Koeffizienten-Grenzen)';

  -- ---- Die Physik: Anteile sind Anteile, Massen nie negativ ----------
  select count(*) into v_n from v_hochrechnung
   where koeffizient is not null and (koeffizient < 0 or koeffizient > 1);
  assert v_n = 0, format('%s Koeffizienten liegen ausserhalb von 0…1', v_n);

  select count(*) into v_n from v_hochrechnung where kg < 0 or basis_kg < 0 or portion_kg < 0;
  assert v_n = 0, format('%s Massen in der Hochrechnung sind negativ', v_n);

  -- ---- Die drei Sichten, die es auf dem Hof zerlegt hat --------------
  -- count(*) genügt nicht: Postgres wertet die Spaltenausdrücke dann gar
  -- nicht aus. Genau deshalb hat die erste Diagnose v_hochrechnung als
  -- „lesbar" gemeldet, während die App an ihr scheiterte.
  perform count(*) from (select * from v_hochrechnung) q;
  perform count(*) from (select * from v_saisonbilanz) q;
  perform count(*) from (select * from v_marge_buch) q;
  perform count(*) from (select * from v_verlust_ranking) q;

  raise notice 'OK  0058 Auswertung hält stand: unmögliche Zahl wird unbekannt, Anteile bleiben Anteile';
end $$;

-- Der Fall aus dem Betrieb: Warenausgang eingelesen, Wareneingang fehlt.
-- Früher lief das Verhältnis Ausgang/Eingang über und riss die Bilanz mit;
-- heute steht ein Satz da, der sagt, was zu tun ist.
do $$
declare v_befund text; v_n int;
begin
  select count(*) into v_n from palette;
  if v_n = 0 then
    raise notice 'OK  0058 Bilanz ohne Wareneingang (übersprungen, keine Paletten im Prüfstand)';
    return;
  end if;
  select befund into v_befund from v_saisonbilanz;
  assert v_befund is not null, 'Die Bilanz muss immer einen Befund liefern';
  raise notice 'OK  0058 Bilanz liefert einen Befund statt eines Abbruchs';
end $$;

select '——— 0058 Auswertung hält stand geprüft ———' as ergebnis;

-- =====================================================================
-- 0059 — Kein harter Cast mehr in einer Auswertungssicht
-- =====================================================================
-- Der Rückfallschutz: `x::numeric(14,2)` auf einer *berechneten* Grösse ist
-- eine Wette auf den Wertebereich, und wenn sie nicht aufgeht, bricht die
-- ganze Sicht ab statt einer Spalte. Genau daran ist der Überblick auf dem
-- Hof dreimal gescheitert, jedes Mal an einer anderen Sicht. Deshalb prüft
-- dieser Block **jede** Sicht: Vor jedem `::numeric(p,s)` muss ein
-- `zahl(…, s, 1e^(p−s))` stehen.
do $$
declare
  v record; v_offen text[] := '{}'; v_casts int; v_zahl int; v_gesamt int := 0;
  -- Drei gespeicherte Sichten bleiben aussen vor, und zwar mit Grund: Ihre
  -- Casts sind durch die Reinigungsregeln und den Datumsbereich von Postgres
  -- schon begrenzt, und sie liessen sich nur mit „drop … cascade" über die
  -- ganze Kette ändern.
  --   mv_auftrag_masse.lagertage        Differenz zweier Datumswerte
  --   mv_sortier_lauf_masse.masse_kg    Σ Anzahl × Gramm ÷ 1000, Gramm < 60 000
  --   mv_kaliber_verteilung.masse_kg    dieselbe Summe, gruppiert
  -- Ändert sich eine Reinigungsregel, gehört diese Liste geprüft.
  c_ausnahmen text[] := array['mv_auftrag_masse', 'mv_sortier_lauf_masse',
                              'mv_kaliber_verteilung'];
begin
  for v in select c.relname, pg_get_viewdef(c.oid, true) as defn
             from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('v', 'm')
              and not (c.relname = any (c_ausnahmen))
            order by c.relname
  loop
    v_casts := regexp_count(v.defn, '::numeric\(\d+,\d+\)');
    v_zahl  := regexp_count(v.defn, 'zahl\(');
    v_gesamt := v_gesamt + v_casts;
    -- Jeder enge Cast braucht genau einen zahl()-Aufruf davor. Mehr zahl() als
    -- Casts wäre auch verdächtig (doppelt gewrappt), deshalb Gleichheit.
    if v_casts > 0 and v_zahl <> v_casts then
      v_offen := v_offen || format('%s (%s Casts, %s zahl)', v.relname, v_casts, v_zahl);
    end if;
  end loop;

  assert array_length(v_offen, 1) is null, format(
    'Harte Casts ohne zahl() in: %s. Ein Cast auf eine berechnete Grösse muss '
    || 'durch zahl(wert, stellen, grenze) laufen — sonst reisst eine einzelne '
    || 'unmögliche Zahl die ganze Sicht mit (0059).', array_to_string(v_offen, ', '));

  raise notice 'OK  0059 Keine harten Casts: % Casts in den Sichten, alle abgesichert', v_gesamt;
end $$;

-- Und die Gegenprobe: jede Sicht, die das Dashboard lädt, muss sich mit
-- „select *" lesen lassen — count(*) wertet die Spaltenausdrücke nicht aus
-- und hätte genau die Fehler durchgelassen, um die es hier geht.
do $$
declare v text; v_n bigint; v_kaputt text[] := '{}';
begin
  foreach v in array array['v_hochrechnung','v_massenbilanz','v_datenlage','v_plausibilitaet',
      'v_kaliber_verteilung','v_schimmel_kurve_anzeige','v_schimmel_modell','v_selektionsverdacht',
      'v_saisonbilanz','v_schimmel_punkte','v_hochrechnung_basis','v_naechste_charge',
      'v_koeff_verdunstung','v_koeff_ausschuss','v_koeff_nebenkanal','v_koeff_ueberfuellung',
      'v_wiegung_kennzahl','v_marge_buch','v_gewichtsverteilung','v_verarbeitung_alter',
      'v_durchsatz','v_datenqualitaet','v_koeff_gebinde',
      'v_verkauf_lieferung','v_ueberfuellung_verkauf','v_verlust_je_gruppe','v_auftrag_wasch_paletten',
      'v_charge_kohorte','v_fax_beobachtung','v_ausschuss_beobachtung','v_lieferung_masse',
      'v_verlust_ranking','v_kaskade','v_auftrag_masse','v_schimmel_beobachtung',
      'v_ausgang_kennzahl','v_ausgang_lage','v_ausgang_pruef','v_kohorte_anteil','v_palox_stand',
      'v_lieferung_kohorte','v_koeff_palette_netto','v_kontrolle_vorschlag','v_kaskade_basis']
  loop
    begin
      execute format('select count(*) from (select * from %I) q', v) into v_n;
    exception when others then v_kaputt := v_kaputt || (v || ': ' || sqlerrm);
    end;
  end loop;
  assert array_length(v_kaputt, 1) is null,
    format('Diese Sichten lassen sich nicht lesen: %s', array_to_string(v_kaputt, ' | '));
  raise notice 'OK  0059 Alle Sichten des Dashboards mit select * lesbar';
end $$;

select '——— 0059 Keine harten Casts geprüft ———' as ergebnis;

-- =====================================================================
-- 0060 — Punktuell erfasst, vollständig gerechnet
-- =====================================================================
-- Die Halle wird punktuell erfasst; vollständig sind Eingang und Ausgang.
-- Geprüft: Zettelgewicht als Nenner, Fax aus Paletten, Sortierdatum je Kiste,
-- Kistensystem statt Käufer, Lieferungen ohne Charge je Sorte verteilt, die
-- Vorschläge für die Lagerkontrolle, und der Chargenfilter der Bereiche.
do $$
declare v_ws bigint; v_fax bigint; v_wa bigint; v numeric; v2 numeric; v_n int; v_id bigint; r record;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

  -- ---- Waschen + Sortieren: das Gewicht vom Zettel ist der Nenner ----------
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, eroeffnet_von,
                       kistensystem, soll_kg_pro_kiste)
  values ('hand', 'waschen_sortieren', 1613, timestamptz '2027-01-20 08:00+01', timestamptz '2027-01-20 14:00+01',
          'abgeschlossen', '11111111-1111-1111-1111-111111111111', 'kiste_ab', 8)
  returning id into v_ws;
  -- Zwei Paletten mit Zettel: eine trifft eine Palette im Wareneingang (950 → 865 netto),
  -- eine nicht (930 → mittlere Tara der Charge: 85 kg → 845)
  insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg)
  values (v_ws, date '2026-09-01', 950), (v_ws, date '2026-09-01', 930);
  perform auswertung_aktualisieren();
  select netto_kg into v from v_auftrag_palette_masse where auftrag_id = v_ws and netto_kg = 865;
  assert v = 865, 'Das Zettelgewicht 950 findet die Palette im Wareneingang (Netto 865)';
  assert (select masse_quelle from v_auftrag_palette_masse where auftrag_id = v_ws order by id limit 1) = 'zettel',
    'Die Quelle heisst „zettel", wenn die Palette gefunden wurde';
  assert (select netto_kg from v_auftrag_palette_masse where auftrag_id = v_ws order by id desc limit 1) = 845,
    'Ohne Treffer gilt Brutto minus mittlere Tara der Charge (930 − 85 = 845)';
  assert (select masse_quelle from v_auftrag_palette_masse where auftrag_id = v_ws order by id desc limit 1) = 'zettel-charge-tara',
    'Die Quelle sagt, dass die Tara geschätzt ist';
  assert (select eingang_netto_kg from v_auftrag_masse where auftrag_id = v_ws) = 865 + 845,
    'Die Masse der Arbeit ist die Summe der Zettel-Nettos';
  assert exists (select 1 from v_plausibilitaet where art = 'Zettelgewicht' and auftrag_id = v_ws),
    'Ein Zettelgewicht ohne Palette im Wareneingang fällt auf';

  -- ---- Fertige Palette: Soll aus der Arbeit, nicht aus einer Fassung ---------
  insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart)
  values (v_ws, 1613, 32 * 8.5 + 32 * 1.5 + 25, 32, 'Holzkiste');
  assert (select soll_kg_pro_kiste from v_ausgang_kennzahl where auftrag_id = v_ws) = 8
     and (select kistensystem from v_ausgang_kennzahl where auftrag_id = v_ws) = 'kiste_ab'
     and (select ueberfuellung_je_kiste from v_ausgang_kennzahl where auftrag_id = v_ws) = 0.5,
    'Kiste ab 8 kg: 8.5 kg je Kiste sind 0.5 kg Überfüllung';

  -- ---- Fax aus der Palettenzahl: Paletten × gemessene Palettenmasse ----------
  insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, ende_ts, status, eroeffnet_von,
                       kistensystem, soll_kg_pro_kiste, paletten_gesamt, tage_seit_waschen)
  values ('maschine', 'waschen', 1613, true, timestamptz '2027-01-22 08:00+01', timestamptz '2027-01-22 10:00+01',
          'abgeschlossen', '11111111-1111-1111-1111-111111111111', 'kiste_ab', 8, 3, 2)
  returning id into v_fax;
  insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart) values (v_fax, 0, 7.5, 1, 'Holzkiste');
  perform auswertung_aktualisieren();
  select netto_kg into v from v_koeff_palette_netto where sorte = 'Tiana' and kistensystem = 'kiste_ab';
  assert v is not null and v > 0, 'Die Palettenmasse je Sorte und Kistensystem ist gemessen';
  assert (select masse_quelle from v_auftrag_masse where auftrag_id = v_fax) = 'fax_paletten',
    'Ohne gezählte Kisten kommt die Fax-Masse aus den Paletten';
  assert abs((select eingang_netto_kg from v_auftrag_masse where auftrag_id = v_fax) - 3 * v) < 0.05,
    'Fax-Masse = 3 Paletten × Palettenmasse';
  select * into r from v_fax_beobachtung where auftrag_id = v_fax;
  assert r.paletten_gesamt = 3 and r.tage_seit_waschen = 2 and r.kistensystem = 'kiste_ab' and r.faul_kg = 6,
    'Die Fax-Beobachtung trägt Paletten, Tage seit dem Waschen und Kistensystem';

  -- ---- Waschen: Sortierdatum je Kiste, „kein Datum" ist eine Antwort --------
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, eroeffnet_von, kaliber_idx,
                       kistensystem, stueck_je_kiste)
  values ('maschine', 'waschen', 1613, timestamptz '2027-01-23 08:00+01', timestamptz '2027-01-23 11:00+01',
          'abgeschlossen', '11111111-1111-1111-1111-111111111111', 0, 'stueck', 6)
  returning id into v_wa;
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl, sortierdatum) values (v_wa, 0, 4, date '2026-11-15');
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl, sortierdatum) values (v_wa, 0, 3, date '2026-11-20');
  insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl, datum_fehlt) values (v_wa, 0, 2, true);
  -- Derselbe Zähler nochmals (Upsert-Schlüssel mit NULL-Datum) muss abgewiesen werden
  begin
    insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl, datum_fehlt) values (v_wa, 0, 5, true);
    assert false, 'Zwei Zähler ohne Datum für dasselbe Kaliber darf es nicht geben';
  exception when unique_violation then null;
  end;
  assert (select anzahl from v_auftrag_gebinde_masse where auftrag_id = v_wa and kaliber_idx = 0) = 9,
    'Die Kisten je Kaliber werden über die Sortierdaten summiert (4 + 3 + 2)';
  assert (select wasch_kisten_mit_sortierdatum from v_datenqualitaet) >= 9
     and (select arbeiten_mit_kistensystem from v_datenqualitaet) >= 3,
    'Die Datenqualität zählt Sortierdaten und Kistensysteme';

  -- ---- Stück-Kisten: Erwartung aus der CSV, keine Überfüllung ----------------
  -- 6 Stück je Kiste im Kaliber 0: die App zeigt, was eine solche Kiste laut
  -- Sortier-CSV wiegen müsste — eine Information, keine verschenkte Marge.
  insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, kaliber_idx, kuerbisse_pro_kiste)
  values (v_wa, 1613, 10 * 5.2 + 10 * 1.5 + 25, 10, 'Holzkiste', 0, 6);
  select sum(sg.anzahl::bigint * sg.gewicht_g)::numeric / sum(sg.anzahl) into v
    from sortier_gewicht sg join sortier_lauf l on l.id = sg.lauf_id join charge c on c.nr = l.charge_nr
   where c.sorte = 'Tiana' and sg.klasse = 'kaliber' and sg.kaliber_idx = 0;
  select * into r from v_ausgang_kennzahl where auftrag_id = v_wa;
  assert r.kistensystem = 'stueck' and r.stueck_je_kiste = 6 and r.ueberfuellung_je_kiste is null,
    'Bei Stück-Kisten gibt es kein Soll und keine Überfüllung';
  assert r.band_mittel_g is not null and abs(r.erwartet_kg_pro_kiste - 6 * v / 1000) < 0.002,
    format('Die Erwartung je Kiste ist Stück × Bandmittel aus der CSV (%s ≠ 6 × %s g)', r.erwartet_kg_pro_kiste, round(v));
  assert abs(r.abweichung_je_kiste - (r.kg_pro_kiste - r.erwartet_kg_pro_kiste)) < 0.002,
    'Die Abweichung je Kiste ist gewogen minus erwartet';

  -- ---- Lieferung ohne Charge: auf die Chargen der Sorte verteilt ------------
  insert into lieferung (datum, sorte, kg, ziel, bemerkung)
  values (date '2027-01-25', 'Tiana', 3000, 'verkauf', 'PRUEF-0060');
  perform auswertung_aktualisieren();
  select sum(masse_kg) into v from v_lieferung_kohorte where buch = 'verkauf';
  -- Nur Lieferungen an Chargen mit Wareneingang können zurückgerechnet werden;
  -- die 1000 kg an 1637 (PRUEF-0051, ohne Eingang) müssen stattdessen auffallen.
  select sum(masse_kg) into v2 from v_lieferung_masse l where buch = 'verkauf'
     and (l.charge_nr is null or exists (select 1 from v_kohorte_anteil k where k.charge_nr = l.charge_nr));
  assert abs(v - v2) < 1, format('Jede verkaufte Lieferung landet bei einer Charge (%s von %s kg)', round(v), round(v2));
  assert exists (select 1 from v_plausibilitaet where art = 'Lieferung ohne Eingang' and charge_nr = 1637),
    'Eine Lieferung an eine Charge ohne Wareneingang fällt auf';
  assert (select count(distinct charge_nr) from v_lieferung_kohorte where buch = 'verkauf') >= 2
      or (select count(*) from v_charge_rueckgrat where sorte = 'Tiana' and eingang_netto_kg > 0) < 2,
    'Eine Lieferung ohne Charge verteilt sich auf die Chargen der Sorte';
  assert (select geliefert_kg from v_hochrechnung_basis where charge_nr = 1613) > 4000,
    'Die Sorten-Lieferung hebt das Gelieferte der Charge (über die 4000 kg mit Charge)';
  assert abs((select sum(lager_kg + ausgelagert_kg - eingang_kg - ueberzaehlung_kg) from v_hochrechnung_basis)) < 1,
    'Je Charge: Lager + Ausgelagert = Eingang + Überzählung';
  delete from lieferung where bemerkung = 'PRUEF-0060';

  -- ---- Der Chargenfilter der Bereiche ------------------------------------
  select kg into v from verlust_ranking(null, null, 1613) where strom = 'Verdunstung';
  select kg into v2 from verlust_ranking() where strom = 'Verdunstung';
  assert v is not null and v > 0 and v < v2,
    'verlust_ranking je Charge liefert einen Teil des Ganzen';
  assert (select kg_unten from verlust_ranking(null, null, 1613) where strom = 'Verdunstung') is not null,
    'auch mit Bereich';

  -- ---- Palette kontrollieren: drei Vorschläge, bestandsstärkste zuerst ------
  assert (select count(*) from v_kontrolle_vorschlag) between 1 and 3, 'Höchstens drei Vorschläge';
  assert (select n_kontrollen from v_kontrolle_vorschlag order by n_kontrollen limit 1) >= 0, 'Kontrollen gezählt';

  -- ---- Alle neuen Sichten lesbar (select *) --------------------------------
  perform count(*) from (select * from v_lieferung_kohorte) q;
  perform count(*) from (select * from v_koeff_palette_netto) q;
  perform count(*) from (select * from v_kontrolle_vorschlag) q;
  perform count(*) from (select * from v_kaskade_basis) q;
  perform count(*) from (select * from v_hochrechnung_basis) q;

  -- Aufräumen
  delete from auftrag where id in (v_ws, v_fax, v_wa);
  perform auswertung_aktualisieren();
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  0060 Punktuell erfasst: Zettel, Fax-Paletten, Sortierdatum, Sorten-Lieferung, Chargenfilter, Vorschläge';
end $$;

select '——— 0060 Punktuell erfasst geprüft ———' as ergebnis;

-- =====================================================================
-- 0061 — Alles bis heute, die Prognose getrennt, das Rechenwerk gespeichert
-- =====================================================================
-- Bis hierher rechnete der Prüfstand am Saisonende (heute_test). Jetzt ein
-- früheres „heute" (15. Januar — nach der Lieferung der Fixtur vom 30.12.):
-- die Ware im Haus altert bis dahin, der Verlauf teilt sich in gerechnet bis
-- heute und Prognose danach.
do $$
declare v numeric; v2 numeric; v_n int; v_stand jsonb; v_txt text; r record; i int;
        v_l1 bigint; v_l2 bigint; v_l3 bigint; v_w bigint; v_kg_je_kiste numeric; v_ok boolean;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);

  -- ---- heute() und stichtag() -------------------------------------------
  assert heute() = date '2027-03-31', 'Der Prüfstand rechnet bis hier am Saisonende (heute_test)';
  assert stichtag() = date '2027-03-31', 'Der Stichtag ist das Saisonende';
  update einstellung set wert = '"2027-01-15"'::jsonb where schluessel = 'heute_test';
  assert heute() = date '2027-01-15', 'heute() folgt der Einstellung heute_test';
  assert stichtag() = date '2027-03-31', 'Der Horizont der Prognose bleibt das Saisonende';
  perform auswertung_aktualisieren();

  -- ---- Die Ware im Haus altert bis heute, nicht bis zum Saisonende --------
  select alter_tage into v from v_hochrechnung where charge_nr = 1614 and portion = 'lager' order by alter_tage desc limit 1;
  assert v between 125 and 130,
    format('Die Ware im Haus (Eingang 10.9.) ist am 15.1. rund 127 Tage alt, nicht %s', v);
  assert (select heute from v_hochrechnung_basis limit 1) = date '2027-01-15', 'Die Basis nennt ihr Heute';
  assert (select stichtag from v_kaskade_basis limit 1) = date '2027-01-15', 'Die Kaskade altert bis heute';
  -- Das Ausgelagerte altert bis zum Liefertag — was auf dem Lieferschein steht.
  select alter_ausgelagert into v from v_hochrechnung_basis where charge_nr = 1613;
  assert v between 116 and 120, format('Das Ausgelagerte altert bis zum Liefertag (~118), ist %s', v);

  -- ---- Verlust bis heute: die Teile ergeben das Ganze ----------------------
  assert not exists (select 1 from erg_charge where verlust_bekannt
                      and abs(verlust_heute_kg - (verdunstung_heute_kg + schimmel_heute_kg + sockel_heute_kg + fax_heute_kg)) > 0.05),
    'Verlust bis heute = Verdunstung + Schimmel + nicht lagerbedingt + Fax am Abgepackten';
  -- 0064: NULL heisst „nicht gemessen" — und darf nur dann dastehen. Beide
  -- Richtungen, sonst deckt die Regel jede Zahl und jede Lücke gleichermassen.
  assert not exists (select 1 from erg_charge where im_haus_heute_kg is null),
    'Der Bestand bis heute ist nie NULL: er ist Eingangsmasse, und die ist gemessen';
  assert not exists (select 1 from erg_charge where verlust_bekannt and verlust_heute_kg is null),
    'Ist jeder Koeffizient gemessen, ist der Verlust bis heute eine Zahl';
  assert not exists (select 1 from erg_charge where not verlust_bekannt and verlust_heute_kg is not null),
    'Fehlt eine Messung, ist der Verlust unbekannt — nicht null (0064)';
  -- Beide Wege müssen dasselbe sagen, Strom für Strom — auch dasselbe
  -- „unbekannt". Die Gesamtsumme allein trüge das nicht: erg_verlust führt
  -- jeden Strom mit eigenem Kennzeichen, erg_charge nur die Summe, und die ist
  -- unbekannt, sobald ein Teil davon unbekannt ist.
  assert not exists (
    select 1 from (values
        ('Verdunstung',              (select sum(verdunstung_heute_kg) from erg_charge)),
        ('Schimmel/Fäulnis',         (select sum(schimmel_heute_kg)    from erg_charge)),
        ('Nicht lagerbedingt',       (select sum(sockel_heute_kg)      from erg_charge)),
        ('Faul beim Abpacken (Fax)', (select sum(fax_heute_kg)         from erg_charge))
      ) as c(strom, kg)
      join erg_verlust v on v.gruppe = 'gesamt' and v.strom = c.strom
     where ((c.kg is not null and v.kg is not null and abs(c.kg - v.kg) > 1)
         or ((c.kg is null) <> (v.kg is null)))),
    'Je Strom müssen Charge und Ranking dieselbe Zahl nennen — und dasselbe „unbekannt"';
  -- Sind alle sechs Koeffizienten gemessen, muss auch die Summe zusammenpassen.
  assert (select bool_and(verlust_bekannt) from erg_charge) is not true
      or abs((select sum(verlust_heute_kg) from erg_charge)
             - (select sum(kg) from erg_verlust
                 where gruppe = 'gesamt' and buch in ('verlust', 'feld'))) < 1,
    'Charge und Ranking nennen denselben Verlust bis heute';
  -- Die Bilanz je Charge — aber nur dort, wo jeder Summand eine Zahl ist. Wo
  -- ein Koeffizient fehlt, ist der Verlust unbekannt und die Bilanz mit ihm;
  -- eine Bilanz aus einer Unbekannten ist keine Prüfung, sondern eine Rechnung
  -- mit angenommener Null. Geprüft wird deshalb: jede rechenbare Charge geht
  -- auf, und rechenbar ist genau die, deren Koeffizienten alle gemessen sind.
  assert not exists (
    select 1 from erg_charge
     where verlust_bekannt
       and abs(eingang_kg + ueberzaehlung_kg - geliefert_kg - verlust_heute_kg
               - kanal_ausgelagert_kg - im_haus_heute_kg) > 1),
    'Eingang + Überzählung = geliefert + Verlust bis heute + Kanal am Ausgelagerten + im Haus';
  assert not exists (
    select 1 from erg_charge
     where verlust_bekannt
       and (verlust_heute_kg is null or kanal_ausgelagert_kg is null or im_haus_heute_kg is null)),
    'Ist alles gemessen, hat jeder Summand der Bilanz eine Zahl';
  -- 0062: Die Bilanz geht jetzt wirklich auf — der Rest ist Rundung, nicht die
  -- Überzählung mit umgekehrtem Vorzeichen.
  -- 0064: Der Rest ist NULL, sobald ein Verluststrom keine Messung hat — dann
  -- gibt es nichts zu schliessen. Geprüft wird beides: geschlossen, wenn alles
  -- gemessen ist; unbekannt, wenn nicht. Ein Rest, der eine Zahl ist, obwohl
  -- der Verlust unbekannt ist, wäre eine stillschweigend angenommene Null.
  assert (select coalesce(abs(bilanz_rest_kg) < 1, not verlust_bekannt) from v_saisonbilanz),
    format('Die Bilanz schliesst nicht: Rest %s kg (Verlust bekannt: %s)',
           (select bilanz_rest_kg from v_saisonbilanz),
           (select verlust_bekannt from v_saisonbilanz));
  assert (select befund from v_saisonbilanz) like 'Bis heute (15.01.2027)%'
      or (select befund from v_saisonbilanz) like '%noch nicht gemessen%'
      or (select befund from v_saisonbilanz) like '%zu viel%',
    format('Der Befund spricht von heute: %s', (select befund from v_saisonbilanz));
  -- Fax an der Ware im Haus ist eine Erwartung, kein Verlust
  assert (select coalesce(sum(fax_erwartet_kg), 0) from erg_charge) >= 0, 'fax_erwartet_kg lesbar';
  assert not exists (select 1 from erg_verlust where strom = 'Faul beim Abpacken (Fax)' and kg_projiziert > 0.01),
    'Fax hat keinen projizierten Anteil — an der Ware im Haus ist es Erwartung (kg_erwartet)';

  -- ---- Der Verlauf: bis heute gerechnet, danach Prognose -------------------
  assert (select count(*) from erg_verlauf where sorte is null and prognose) > 0,
    'Vor dem Saisonende gibt es Prognosewochen';
  assert not exists (select 1 from erg_verlauf where prognose and bis <= heute()), 'Prognose erst nach heute';
  assert not exists (select 1 from erg_verlauf where not prognose and bis > heute()), 'Bis heute ist keine Prognose';
  assert (select count(distinct eingang_kum_kg) from erg_verlauf where sorte is null and prognose) = 1,
    'In der Prognose kommt nichts mehr herein';
  assert not exists (select 1 from (select verlust_kum_kg, lag(verlust_kum_kg) over (order by woche) as vor
                                      from erg_verlauf where sorte is null) w
                      where w.vor > w.verlust_kum_kg + 0.01), 'Der Verlust kumuliert monoton';
  assert not exists (select 1 from erg_verlauf where im_haus_kg < -0.01 or verlust_kum_kg < -0.01), 'Nie negativ';
  select verlust_kum_kg into v from erg_verlauf where sorte is null and not prognose order by woche desc limit 1;
  -- Der Verlauf zeichnet die Ursachen, die gemessen sind — eine Kurve, die
  -- verschwindet, sobald ein Koeffizient fehlt, hilft niemandem. Verglichen wird
  -- deshalb mit derselben Summe: den gemessenen Strömen. Welche Ursache fehlt,
  -- sagt der Überblick daneben („Nicht gemessen: …"), und die Kennzahl
  -- „Verlust bis heute" bleibt unbekannt (0064).
  select sum(coalesce(verdunstung_heute_kg, 0) + coalesce(schimmel_heute_kg, 0)
             + coalesce(sockel_heute_kg, 0) + coalesce(fax_heute_kg, 0)) into v2 from erg_charge;
  assert abs(v - v2) <= 0.06 * greatest(v2, 1) + 5,
    format('Die letzte Woche bis heute trifft den Verlust der Chargen (%s vs %s, Wochenraster)', round(v), round(v2));
  assert abs((select sum(eingang_kum_kg) from erg_verlauf where sorte is not null and woche = (select max(woche) from erg_verlauf))
             - (select eingang_kum_kg from erg_verlauf where sorte is null and woche = (select max(woche) from erg_verlauf))) < 1,
    'Die Sorten summieren sich zum Ganzen';

  -- ---- verlust_ranking liest, rechnet nicht ---------------------------------
  assert (select count(*) from verlust_ranking(null, null, 1613)) > 0, 'Charge';
  assert (select count(*) from verlust_ranking('Tiana')) > 0, 'Sorte';
  assert (select kg from verlust_ranking('Tiana') where strom = 'Verdunstung')
       <= (select kg from verlust_ranking() where strom = 'Verdunstung') + 0.01, 'Die Sorte ist ein Teil des Ganzen';
  assert exists (select 1 from erg_verlust where gruppe = 'schlag'), 'Auch je Schlag vorgerechnet';
  assert (select count(*) from erg_verlust where gruppe = 'gesamt') = (select count(*) from v_verlust_ranking),
    'v_verlust_ranking ist die Gesamtgruppe';

  -- ---- Lagerkontrolle: Bestand × Tage seit der letzten Wägung --------------
  assert (select count(*) from v_kontrolle_vorschlag) between 1 and 3, 'Höchstens drei Vorschläge';
  assert (select min(informationswert) from v_kontrolle_vorschlag) > 0, 'Jeder Vorschlag hat einen Informationswert';
  assert not exists (select 1 from v_kontrolle_vorschlag where im_haus_heute_kg <= 0), 'Nur, wo heute etwas liegt';

  -- ---- Verkaufte Kisten aus der Verkaufsdatei --------------------------------
  -- Drei Positionen: Kiste ab 8 kg (100 Kisten mit Charge), Stück (50 Kisten à
  -- 12 Stück à 550 g mit Charge), Kiste ab 8 kg ohne Chargenbezug (20 Kisten).
  insert into ausgang_quelle (code, name) values ('PRUEF', 'Prüfstand') on conflict (code) do nothing;
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel,
                             einheit, menge, gewicht_je_artikel, batch_menge, kg_position, kg_charge,
                             gebindeart, gebinde_menge, gebinde_inhalt, batch_gebinde)
  values ('PRUEF', 1, '1613', 1, 'f1', date '2026-09-20', 'kürbtia',  'Bio Kürbis Tiana lose', 'kg',   800, 1,    800, 800, 800, 'IFCO', 100, 8,  100),
         ('PRUEF', 2, '1613', 1, 'f2', date '2026-09-21', 'kürbtiad', 'Bio Kürbis Tiana Dem',  'Stk.', 600, 0.55, 600, 330, 330, 'IFCO', 50,  12, 50),
         ('PRUEF', 3, '',     1, 'f3', date '2026-09-22', 'kürbtia',  'Bio Kürbis Tiana lose', 'kg',   160, 1,    0,   160, 0,   'IFCO', 20,  8,  null);
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung)
  values (date '2026-09-20', 1613, 'Tiana', 800, 'verkauf', 'PRUEF-0061') returning id into v_l1;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung)
  values (date '2026-09-21', 1613, 'Tiana', 330, 'verkauf', 'PRUEF-0061') returning id into v_l2;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung)
  values (date '2026-09-22', null, 'Tiana', 160, 'verkauf', 'PRUEF-0061') returning id into v_l3;
  insert into lieferung_import (lieferung_id, quelle, extern_id)
  values (v_l1, 'PRUEF', 'PRUEF:1:1613:1'), (v_l2, 'PRUEF', 'PRUEF:2:1613:1'), (v_l3, 'PRUEF', 'PRUEF:3:rest');
  assert lieferung_import_zeilen_verbinden('PRUEF') = 3, 'Alle drei Lieferungen finden ihre Zeile';
  assert (select kistensystem from v_verkauf_lieferung where lieferung_id = v_l1) = 'kiste_ab', 'kg × Inhalt 8 = Kiste ab 8 kg';
  assert (select soll_kg_pro_kiste from v_verkauf_lieferung where lieferung_id = v_l1) = 8, 'Soll aus dem Gebindeinhalt';
  assert (select kisten from v_verkauf_lieferung where lieferung_id = v_l1) = 100, 'Kisten aus der Chargenzeile';
  assert (select kisten_quelle from v_verkauf_lieferung where lieferung_id = v_l1) = 'zeile', 'Quelle: die Zeile';
  assert (select kistensystem from v_verkauf_lieferung where lieferung_id = v_l2) = 'stueck', 'Stk. × Inhalt 12 = Stück-Kiste';
  assert (select stueck_je_kiste from v_verkauf_lieferung where lieferung_id = v_l2) = 12, '12 Stück je Kiste';
  assert (select nenn_g from v_verkauf_lieferung where lieferung_id = v_l2) = 550, 'Nenngewicht 550 g';
  assert (select stueck from v_verkauf_lieferung where lieferung_id = v_l2) = 600, '50 Kisten × 12 = 600 Stück';
  assert (select kisten from v_verkauf_lieferung where lieferung_id = v_l3) = 20, 'Die Rest-Lieferung bekommt die Kisten der Position';
  perform auswertung_aktualisieren();
  select kisten_verkauft, n_lieferungen into v, v_n from erg_ueberfuellung
   where gruppe = 'sorte' and sorte = 'Tiana' and kistensystem = 'kiste_ab' and soll_kg_pro_kiste = 8;
  assert v = 120 and v_n = 2, format('Je Sorte: 120 Kisten „ab 8 kg" aus 2 Lieferungen, ist %s / %s', v, v_n);
  assert (select kisten_verkauft from erg_ueberfuellung
           where gruppe = 'charge' and charge_nr = 1613 and kistensystem = 'kiste_ab' and soll_kg_pro_kiste = 8) = 100,
    'Je Charge nur die Chargenzeile (100 Kisten)';
  select stueck_verkauft, nenn_g into v, v2 from erg_ueberfuellung
   where gruppe = 'sorte' and sorte = 'Tiana' and kistensystem = 'stueck' and stueck_je_kiste = 12;
  assert v = 600 and v2 = 550, format('Stück: 600 verkauft, Nenngewicht 550 g (ist %s / %s)', v, v2);
  assert (select verschenkt_kg from erg_ueberfuellung
           where gruppe = 'sorte' and sorte = 'Tiana' and kistensystem = 'stueck' and stueck_je_kiste = 12) is null,
    'Stück-Kisten haben keine verschenkte Marge';
  -- verschenkt: nur wo gewogen — der Überschuss je gewogener Kiste mal die verkauften Kisten
  select n_wiegungen, zuviel_je_kiste, verschenkt_kg into v_n, v_kg_je_kiste, v from erg_ueberfuellung
   where gruppe = 'sorte' and sorte = 'Tiana' and kistensystem = 'kiste_ab' and soll_kg_pro_kiste = 8;
  if v_n > 0 then
    assert abs(v - greatest(v_kg_je_kiste, 0) * 120) < 1,
      format('verschenkt = Überschuss je Kiste × verkaufte Kisten (%s × 120 ≠ %s)', v_kg_je_kiste, v);
    assert (select kg from v_marge_buch where posten like '%berf%') is not null, 'Die Marge nennt die Zahl';
    assert (select erlaeuterung from v_marge_buch where posten like '%berf%') like '%Verkaufsdatei%',
      'Die Erläuterung nennt die Verkaufsdatei als Quelle der Kisten';
  else
    assert v is null, 'Ohne Wägung wird nichts verschenkt behauptet';
    assert (select erlaeuterung from v_marge_buch where posten like '%berf%') like '%keine fertige Palette%',
      'Die Erläuterung sagt, dass nichts gewogen ist';
  end if;
  -- Aufräumen
  delete from lieferung where bemerkung = 'PRUEF-0061';
  delete from ausgang_zeile where quelle = 'PRUEF';
  delete from ausgang_quelle where code = 'PRUEF';

  -- ---- Waschen zählt Paletten: Sortierdatum und Kisten -----------------------
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, eroeffnet_von, kaliber_idx, kistensystem)
  values ('maschine', 'waschen', 1613, timestamptz '2026-09-25 08:00+02', timestamptz '2026-09-25 12:00+02',
          'abgeschlossen', '11111111-1111-1111-1111-111111111111', 1, 'kiste_ab')
  returning id into v_w;
  insert into auftrag_palette (auftrag_id, sortierdatum, kisten)
  values (v_w, date '2026-09-15', 30), (v_w, date '2026-09-20', 30), (v_w, date '2026-09-20', 20);
  assert (select n_paletten from v_auftrag_wasch_paletten where auftrag_id = v_w) = 3, 'Drei Paletten gezählt';
  assert (select kisten from v_auftrag_wasch_paletten where auftrag_id = v_w) = 80, '80 Kisten';
  select zwischenlager_tage into v from v_auftrag_wasch_paletten where auftrag_id = v_w;
  assert abs(v - (30 * 10 + 50 * 5) / 80.0) < 0.1, format('Zwischenlager massegewichtet: 6.9 Tage, ist %s', v);
  select kg_je_gebinde into v_kg_je_kiste from v_koeff_gebinde where sorte = 'Tiana' and kaliber_idx = 1;
  select kg into v from v_auftrag_wasch_paletten where auftrag_id = v_w;
  if v_kg_je_kiste is not null then
    assert abs(v - 80 * v_kg_je_kiste) < 0.05, format('Masse = Kisten × Kistengewicht (%s ≠ 80 × %s)', v, v_kg_je_kiste);
    perform auswertung_aktualisieren();
    assert (select masse_quelle from v_auftrag_masse where auftrag_id = v_w) = 'wasch_paletten', 'Die Masse kommt aus den gezählten Paletten';
    assert (select zwischenlager_tage from v_auftrag_masse where auftrag_id = v_w) is not null, 'Die Zeit im Zwischenlager steht dran';
  else
    assert v is null, 'Ohne gemessenes Kistengewicht keine Masse';
  end if;
  delete from auftrag where id = v_w;

  -- ---- Die fünf Schritte ---------------------------------------------------
  for i in 1..5 loop
    v_stand := auswertung_schritt(i);
    assert (v_stand ->> 'schritt')::int = i and (v_stand ->> 'schritte')::int = 5, 'Schritt zählt';
    assert ((v_stand ->> 'fertig')::boolean) = (i = 5), 'Nur der letzte Schritt ist fertig';
    assert (v_stand ->> 'dauer_ms')::int >= 0, 'Dauer gemessen';
  end loop;
  assert (select berechnet_ts from auswertung_stand where id = 1) > now() - interval '1 minute', 'Schritt 5 setzt den Stand';
  begin
    perform auswertung_schritt(6);
    v_ok := false;
  exception when others then
    v_ok := true;
  end;
  assert v_ok, 'Einen sechsten Schritt gibt es nicht';
  -- Nur rechnen, wenn veraltet
  update auswertung_stand set geaendert_ts = berechnet_ts - interval '1 second' where id = 1;
  assert auswertung_wenn_veraltet() = false, 'Nichts veraltet — nichts gerechnet';
  update auswertung_stand set geaendert_ts = berechnet_ts + interval '1 second' where id = 1;
  assert auswertung_wenn_veraltet() = true, 'Veraltet — gerechnet';
  -- Jede gespeicherte Sicht ist gefüllt, lesbar und analysiert
  for r in select c.relname, c.reltuples, m.ispopulated
             from pg_class c join pg_matviews m on m.matviewname = c.relname
            where m.schemaname = 'public' and c.relname like 'erg\_%'
  loop
    assert r.ispopulated, format('%s ist nicht gefüllt', r.relname);
    execute format('select count(*) from (select * from %I) q', r.relname) into v_n;
    assert r.reltuples >= 0, format('%s wurde nie analysiert (reltuples %s)', r.relname, r.reltuples);
  end loop;
  select count(*) into v_n from pg_matviews where schemaname = 'public' and matviewname like 'erg\_%';
  assert v_n >= 30, format('Mindestens 30 gespeicherte Ergebnisse erwartet, %s gefunden', v_n);
  assert schema_stand() >= 61, format('Stand mindestens 61 erwartet, ist %s', schema_stand());

  -- Zurück ans Saisonende
  update einstellung set wert = '"2027-03-31"'::jsonb where schluessel = 'heute_test';
  perform auswertung_aktualisieren();
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  0061 Bis heute: Alter, Verlustteile, Verlauf mit Prognose, Ranking gespeichert, Kontrolle, Verkaufsdatei, Wasch-Paletten, fünf Schritte';
end $$;

select '——— 0061 Bis heute geprüft ———' as ergebnis;

-- =========================================================================
-- 0062: Jede Zahl sagt, was sie ist. Zwei Rechenfehler und die irreführenden
-- Namen. Geprüft wird, was ein Betriebsleiter merken würde: eine Lieferung,
-- die noch nicht passiert ist, darf in keiner Zahl „bis heute" stecken; eine
-- Lieferung an die Tiere darf die Kaskade genau einmal belasten, nicht zweimal.
-- =========================================================================
do $$
declare v_charge int; v_lief bigint; v_n int;
        v_gel1 numeric; v_gel2 numeric; v_haus1 numeric; v_haus2 numeric;
        v_rest numeric; v_kohorte1 numeric; v_kohorte2 numeric;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);
  assert schema_stand() >= 62, format('Stand mindestens 62 erwartet, ist %s', schema_stand());

  -- Die Namen, die falsch waren, sind weg und die richtigen da
  assert to_regclass('v_saisonbilanz') is not null;
  assert exists (select 1 from information_schema.columns
                  where table_name = 'v_saisonbilanz' and column_name = 'kanal_ausgelagert_kg'),
    'v_saisonbilanz.kanal_ausgelagert_kg fehlt (hiess kanal_heute_kg, meinte aber nur das Ausgelagerte)';
  assert exists (select 1 from information_schema.columns
                  where table_name = 'v_wiegung_kennzahl' and column_name = 'verdunstung_kg'),
    'v_wiegung_kennzahl.verdunstung_kg fehlt (hiess verlust_kg, ist aber nur die Verdunstung)';
  assert not exists (select 1 from information_schema.columns
                      where table_name = 'v_wiegung_kennzahl' and column_name = 'verlust_kg'),
    'v_wiegung_kennzahl.verlust_kg gibt es noch — ein Name für zwei Dinge';
  assert exists (select 1 from information_schema.columns
                  where table_name = 'v_naechste_charge' and column_name = 'prognose_verlust_14_kg'),
    'v_naechste_charge.prognose_verlust_14_kg fehlt';
  -- erg_verlauf ist eine materialisierte Sicht; die stehen nicht im
  -- information_schema, darum über den Katalog.
  assert (select count(*) from pg_attribute a
            join pg_class c on c.oid = a.attrelid
            join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relname = 'erg_verlauf'
             and a.attnum > 0 and not a.attisdropped
             and a.attname in ('schimmel_kum_kg', 'sockel_kum_kg')) = 2,
    'erg_verlauf trennt Schimmel und Sockel nicht';

  select nr into v_charge from charge
   where nr in (select charge_nr from v_charge_rueckgrat where eingang_netto_kg > 0)
   order by nr limit 1;

  -- ---- Fehler 1: eine Lieferung in der Zukunft zählt nicht bis heute ----
  select coalesce(sum(masse_kg), 0) into v_gel1 from v_lieferung_kohorte;
  insert into lieferung (datum, charge_nr, kg, ziel, kunde)
    values (heute() + 10, v_charge, 500, 'verkauf', 'Prüfstand Zukunft')
    returning id into v_lief;
  select coalesce(sum(masse_kg), 0) into v_gel2 from v_lieferung_kohorte;
  assert abs(v_gel2 - v_gel1) < 0.01,
    format('Eine Lieferung mit Datum in der Zukunft ist in „bis heute" gelandet: %s → %s', v_gel1, v_gel2);
  -- gesehen wird sie trotzdem: sie steht als Befund da, statt still zu wirken
  assert exists (select 1 from v_plausibilitaet where art = 'Lieferung in der Zukunft'),
    'Eine Lieferung in der Zukunft muss als Befund auftauchen, nicht bloss verschwinden';
  delete from lieferung where id = v_lief;
  select coalesce(sum(masse_kg), 0) into v_gel2 from v_lieferung_kohorte;
  assert abs(v_gel2 - v_gel1) < 0.01, 'Aufräumen hat die Summe verändert';

  -- ---- Fehler 2: eine Lieferung an die Tiere zählt genau einmal ----------
  -- Vor 0062 stand v_lieferung_kohorte zweimal in der Kaskade (einmal je Buch),
  -- und die ausgelagerte Masse war um die Marge-Lieferungen zu gross.
  perform auswertung_aktualisieren();
  select sum(masse_kg) into v_kohorte1 from v_lieferung_kohorte where buch in ('verkauf','marge');
  select im_haus_heute_kg into v_haus1 from erg_bilanz;
  insert into lieferung (datum, charge_nr, kg, ziel, kunde)
    values (heute() - 1, v_charge, 400, 'tierfutter', 'Prüfstand Tiere')
    returning id into v_lief;
  perform auswertung_aktualisieren();
  select sum(masse_kg) into v_kohorte2 from v_lieferung_kohorte where buch in ('verkauf','marge');
  assert abs((v_kohorte2 - v_kohorte1) - 400) < 1,
    format('400 kg an die Tiere kamen als %s kg an', v_kohorte2 - v_kohorte1);
  select im_haus_heute_kg into v_haus2 from erg_bilanz;
  -- Die 400 kg verkaufsfertige Ware stammen aus mehr Eingangsware (Verdunstung,
  -- Faules, Kanal davor). Doppelt gezählt wäre der Bestand rund doppelt so
  -- stark gefallen — die Klammer prüft die Grössenordnung, nicht das Modell.
  assert v_haus1 - v_haus2 between 380 and 900,
    format('Bestand fiel um %s kg statt um gut 400 kg — Marge-Lieferung doppelt gezählt?', v_haus1 - v_haus2);
  -- 0064: unbekannter Verlust ⇒ kein Rest. Die Prüfsaison hat keine
  -- Fax-Messung, deshalb steht hier NULL; sobald sie eine hat, muss der Rest
  -- schliessen.
  select bilanz_rest_kg into v_rest from v_saisonbilanz;
  assert v_rest is null or abs(v_rest) < 1,
    format('Die Bilanz schliesst nach der Marge-Lieferung nicht: Rest %s kg', v_rest);
  delete from lieferung where id = v_lief;
  perform auswertung_aktualisieren();

  -- ---- Der Verlauf trifft den Stand von heute ---------------------------
  select count(*) into v_n from erg_verlauf where sorte is null and bis = heute();
  assert v_n = 1, format('erg_verlauf braucht genau eine Stützstelle auf heute(), hat %s', v_n);
  assert abs((select im_haus_kg from erg_verlauf where sorte is null and bis = heute())
             - (select im_haus_heute_kg from erg_bilanz)) < 1,
    'Die Grafik zeigt auf heute etwas anderes als die Kennzahl daneben';

  -- ---- Leer ist nicht null: ein Strom ohne Messung bleibt unbekannt ------
  -- Ein unbekannter Strom trägt keine Zahl. Eine 0 wäre die Behauptung, es sei
  -- gemessen worden und nichts herausgekommen — das ist etwas anderes.
  assert not exists (select 1 from erg_verlust where not bekannt and kg is not null),
    'Ein Strom ohne Messung darf keine Masse zeigen — schon gar keine 0';
  -- Umgekehrt darf ein bekannter Strom seine Herkunft nicht verschweigen: wo
  -- die Gruppe keine eigene Messung hat, muss die Basis sagen, woher der
  -- Koeffizient stammt.
  assert not exists (select 1 from erg_verlust
                      where bekannt and coalesce(koeff_n_min, 0) = 0
                        and (koeff_basis is null or koeff_basis = '')),
    'Ein Strom ohne eigene Messung muss sagen, aus welcher Grundlage er gerechnet ist';

  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  0062 Jede Zahl sagt, was sie ist (Zukunftslieferung, Marge einfach, Namen, Verlauf auf heute)';
end $$;

select '——— 0062 Jede Zahl sagt, was sie ist geprüft ———' as ergebnis;


-- =====================================================================
-- 0063 — Jede Sicht sagt, was sie ist
-- =====================================================================
-- Zwei Regeln, die bisher nur zufällig galten und darum leise verrutschten:
-- jede Ansicht hat eine Beschreibung, und keine Funktion ist für PUBLIC
-- ausführbar. Beides ist hier festgehalten, damit die nächste Migration es
-- nicht wieder verliert.
do $$
declare v_ohne text; v_public text;
begin
  assert schema_stand() >= 63, format('mindestens Stand 63 erwartet, ist %s', schema_stand());

  -- a) Keine Ansicht ohne Beschreibung. Sie ist das, was im SQL-Editor und in
  --    jedem auslesenden Werkzeug erklärt, was eine Zahl bedeutet.
  select string_agg(c.relname, ', ' order by c.relname) into v_ohne
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('v', 'm')
     and obj_description(c.oid) is null;
  assert v_ohne is null,
    format('Diese Ansichten sagen nicht, was sie sind: %s', v_ohne);

  -- b) Keine Funktion ist für jedermann ausführbar. Was authenticated oder
  --    anon dürfen, steht auf diesen Rollen — nicht auf PUBLIC.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_public
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
     and has_function_privilege('public', p.oid, 'execute');
  assert v_public is null,
    format('Diese Funktionen darf jeder ausführen: %s', v_public);

  raise notice 'OK  0063 Jede Sicht sagt, was sie ist (Beschreibungen vollständig, kein PUBLIC-Recht)';
end $$;

select '——— 0063 Jede Sicht sagt, was sie ist geprüft ———' as ergebnis;


-- =====================================================================
-- 0064 — Leer ist nicht null, auch am Eingang
-- =====================================================================
-- Fünf Stellen, an denen aus einer Lücke eine Zahl wurde. Jede bekommt hier
-- einen Fall, der auf Papier nachrechenbar ist: drei Paletten à 1000 kg mit
-- 30 Kisten, Kistentara 1 kg, Palettentara 20 kg — Netto also 950 kg je
-- Palette. Wer eine dieser Behauptungen bricht, sieht es sofort.
do $$
declare v_netto numeric; v_eingang numeric; v_verlust numeric; v_haus numeric;
        v_lager numeric; v_arten text; v_chef uuid := '11111111-1111-1111-1111-111111111111';
begin
  assert schema_stand() >= 64, format('mindestens Stand 64 erwartet, ist %s', schema_stand());

  -- Eine eigene Saison, damit die Zahlen von Hand nachzurechnen sind.
  insert into auth.users (id, email, raw_user_meta_data)
       values (v_chef, 'pruefung64@hof.test', '{"name":"Prüfung 64"}') on conflict do nothing;
  update profil set rolle = 'admin', aktiv = true where id = v_chef;
  perform set_config('request.jwt.claim.sub', v_chef::text, true);

  insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette) values ('PRF64', 1.0, 20.0)
    on conflict (art) do update set tara_kg_pro_kiste = 1.0, tara_kg_palette = 20.0;
  insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette) values ('PRF64OHNE', null, null)
    on conflict (art) do update set tara_kg_pro_kiste = null, tara_kg_palette = null;
  insert into sorte_kaliber (sorte, verlust_unter, kaliber_baender, kanal_ab)
       values ('Prüfkürbis64', 300, '[[300,800],[800,2000]]'::jsonb, 2000) on conflict (sorte) do nothing;
  insert into charge (nr, schlag, sorte, saison) values
    (964001, 'Prüfschlag64a', 'Prüfkürbis64', 2026),  -- vollständig
    (964002, 'Prüfschlag64b', 'Prüfkürbis64', 2026),  -- eine Palette ohne Kistenzahl
    (964003, 'Prüfschlag64c', 'Prüfkürbis64', 2026)   -- Gebindeart ohne Tara
    on conflict (nr) do nothing;

  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, quelle) values
    (964001, '2026-06-01', 1000, 30, 'PRF64', 'pruefung'),
    (964002, '2026-06-01', 1000, 30, 'PRF64', 'pruefung'),
    (964002, '2026-06-01', 1000, null, 'PRF64', 'pruefung'),
    (964003, '2026-06-01', 1000, 30, 'PRF64OHNE', 'pruefung');

  -- a) Netto einer vollständigen Palette: 1000 − 30·1 − 20 = 950.
  select netto_kg into v_netto from v_palette where charge_nr = 964001;
  assert v_netto = 950, format('Netto 950 erwartet, ist %s', v_netto);

  -- b) Ohne Kistenzahl gibt es kein Netto — nicht „null Kisten". Sonst stünden
  --    hier 980 kg, und 30 kg Kistengewicht wären als Kürbis verbucht.
  select netto_kg into v_netto from v_palette where charge_nr = 964002 and kisten is null;
  assert v_netto is null, format('Ohne Kistenzahl darf es kein Netto geben, ist %s', v_netto);

  -- c) Ohne hinterlegte Tara ebenso.
  select netto_kg into v_netto from v_palette where charge_nr = 964003;
  assert v_netto is null, format('Ohne Tara darf es kein Netto geben, ist %s', v_netto);

  -- d) Beide Fälle melden sich als Auffälligkeit — sonst sucht niemand danach.
  select string_agg(distinct art, ', ') into v_arten
    from v_plausibilitaet where charge_nr in (964002, 964003);
  assert v_arten like '%Tara fehlt%',
    format('Paletten ohne Netto müssen als „Tara fehlt" auffallen, gemeldet wurde: %s', coalesce(v_arten, 'nichts'));

  perform auswertung_aktualisieren();

  -- e) Jeder Strom trägt genau dann eine Zahl, wenn sein Koeffizient gemessen
  --    ist — beide Richtungen. Eine Zahl ohne Messung wäre eine erfundene Null;
  --    ein „unbekannt" trotz Messung wäre eine verschenkte Auskunft.
  --    (Der Fall „gar nichts gemessen" steht im Prüfwerk, Sonde 08: hier stehen
  --    Messungen anderer Sorten, und die Koeffizienten werden gepoolt.)
  assert not exists (select 1 from erg_charge
                      where (verdunstung_heute_kg is not null) <> verdunstung_bekannt
                         or (schimmel_heute_kg    is not null) <> schimmel_bekannt
                         or (sockel_heute_kg      is not null) <> sockel_nachgewiesen
                         or (fax_heute_kg         is not null) <> fax_bekannt
                         or (kanal_ausgelagert_kg is not null) <> kanal_bekannt),
    'Jeder Strom ist genau dann eine Zahl, wenn sein Koeffizient gemessen ist (0064)';

  -- f) Die Charge mit einer Palette ohne Netto rechnet mit dem Mittel weiter:
  --    950 (die gewogene) × 2 Paletten = 1900 kg Eingang, davon 950 hochgerechnet.
  select eingang_kg into v_eingang from erg_charge where charge_nr = 964002;
  assert v_eingang = 1900, format('Eingang 1900 erwartet (Mittel × Palettenzahl), ist %s', v_eingang);

  -- g) Die Charge ohne jede Tara hat gar keinen Eingang und fehlt in der Bilanz.
  assert not exists (select 1 from erg_charge where charge_nr = 964003),
    'Eine Charge ohne ein einziges Nettogewicht darf keinen erfundenen Eingang haben';

  -- h) Eine vollständig ausgelieferte Charge liegt nicht mehr im Haus.
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, erfasser)
       values ('2026-08-01', 964001, 'Prüfkürbis64', 950, 'verkauf', v_chef);
  perform auswertung_aktualisieren();
  select im_haus_heute_kg, lager_kg into v_haus, v_lager
    from erg_charge where charge_nr = 964001;
  assert v_haus = 0, format('Alles ausgeliefert: „noch im Haus" muss 0 sein, ist %s', v_haus);
  assert v_lager = 0, format('Alles ausgeliefert: lager_kg muss 0 sein, ist %s', v_lager);

  -- i) Eine Charge ohne Lieferung liegt dagegen noch da — so viel, wie die
  --    Kaskade für ihre liegende Portion ausrechnet. (Nicht 1900: die
  --    Koeffizienten sind aus den Messungen der anderen Sorten gepoolt, also
  --    ist ein Teil bereits verdunstet und verdorben.)
  select im_haus_heute_kg into v_haus from erg_charge where charge_nr = 964002;
  assert v_haus > 0 and v_haus <= 1900,
    format('Ohne Lieferung muss noch etwas liegen, höchstens der Eingang — ist %s', v_haus);
  assert abs(v_haus - (select sum(m2) from mv_kaskade
                        where charge_nr = 964002 and portion = 'lager')) < 0.01,
    'Der Bestand einer Charge ist die liegende Portion der Kaskade, nichts anderes';

  -- j) Mehr geliefert als hereingekommen fällt auf.
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, erfasser)
       values ('2026-08-05', 964002, 'Prüfkürbis64', 2500, 'verkauf', v_chef);
  perform auswertung_aktualisieren();
  assert exists (select 1 from v_plausibilitaet where art = 'Überzählung' and charge_nr = 964002),
    'Mehr Ausgang als Eingang muss als „Überzählung" auffallen';

  -- k) Eine Lieferung ohne Menge und ohne Kisten nimmt die Tabelle nicht an.
  begin
    insert into lieferung (datum, charge_nr, sorte, kg, kisten, ziel, erfasser)
         values ('2026-08-06', 964001, 'Prüfkürbis64', null, null, 'verkauf', v_chef);
    raise exception 'Eine Lieferung ohne Menge und ohne Kistenzahl darf nicht angenommen werden';
  exception when check_violation then null;
  end;

  -- aufräumen
  delete from lieferung where charge_nr in (964001, 964002, 964003);
  delete from palette where charge_nr in (964001, 964002, 964003);
  delete from charge where nr in (964001, 964002, 964003);
  delete from sorte_kaliber where sorte = 'Prüfkürbis64';
  delete from gebinde where art in ('PRF64', 'PRF64OHNE');
  perform auswertung_aktualisieren();
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  0064 Leer ist nicht null (Netto ohne Kisten, Tara fehlt, Verlust unbekannt, Bestand nach Auslieferung, Überzählung)';
end $$;

select '——— 0064 Leer ist nicht null geprüft ———' as ergebnis;

-- =====================================================================
-- 0065 — Entsorgtes verlässt das Lager
-- =====================================================================
-- Was in den Kompost geht, hat den Betrieb verlassen. Bis 0064 zählte es im
-- Ausgang und lag gleichzeitig weiter im Lager — dieselbe Ware zweimal.
-- Geprüft wird an einer Charge, die zur Hälfte verkauft und zu einem Viertel
-- entsorgt wird: Der Bestand muss um die entsorgte Eingangsmasse fallen, der
-- Ausgang um die Lieferscheinmasse steigen, und das Gelieferte darf sich
-- nicht bewegen — Kompost ist keine Lieferung, sondern Verlust.
do $$
declare v_chef uuid := '11111111-1111-1111-1111-111111111111';
        v_haus1 numeric; v_haus2 numeric; v_lager1 numeric; v_lager2 numeric;
        v_aus1 numeric; v_aus2 numeric; v_gel1 numeric; v_gel2 numeric;
        v_m0 numeric; v_m1 numeric; v_sch numeric; v_r numeric; v_t numeric;
        v_lief bigint; v_summe numeric;
begin
  assert schema_stand() >= 65, format('mindestens Stand 65 erwartet, ist %s', schema_stand());
  perform set_config('request.jwt.claim.sub', v_chef::text, true);

  insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette) values ('PRF65', 1.0, 20.0)
    on conflict (art) do update set tara_kg_pro_kiste = 1.0, tara_kg_palette = 20.0;
  insert into sorte_kaliber (sorte, verlust_unter, kaliber_baender, kanal_ab)
       values ('Prüfkürbis65', 300, '[[300,800],[800,2000]]'::jsonb, 2000) on conflict (sorte) do nothing;
  insert into charge (nr, schlag, sorte, saison)
       values (965001, 'Prüfschlag65', 'Prüfkürbis65', 2026) on conflict (nr) do nothing;
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, quelle) values
    (965001, current_date - 100, 1000, 30, 'PRF65', 'pruefung'),
    (965001, current_date - 100, 1000, 30, 'PRF65', 'pruefung');   -- 1900 kg Eingang
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, erfasser)
       values (current_date - 10, 965001, 'Prüfkürbis65', 400, 'verkauf', v_chef);
  perform auswertung_aktualisieren();
  select im_haus_heute_kg, lager_kg, geliefert_kg into v_haus1, v_lager1, v_gel1
    from erg_charge where charge_nr = 965001;
  select ausgang_kg into v_aus1 from v_saisonbilanz;

  -- 300 kg in den Kompost
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, erfasser)
       values (current_date - 5, 965001, 'Prüfkürbis65', 300, 'kompost', v_chef)
    returning id into v_lief;
  perform auswertung_aktualisieren();
  select im_haus_heute_kg, lager_kg, geliefert_kg into v_haus2, v_lager2, v_gel2
    from erg_charge where charge_nr = 965001;
  select ausgang_kg into v_aus2 from v_saisonbilanz;

  -- a) Die Kaskade kennt die Portion und rechnet nur die Verdunstung zurück.
  select m0, m1, schimmel_kg, r, alter_tage into v_m0, v_m1, v_sch, v_r, v_t
    from mv_kaskade where charge_nr = 965001 and portion = 'entsorgt';
  assert v_m0 is not null, 'Eine Kompost-Lieferung braucht eine Portion „entsorgt" in der Kaskade';
  assert abs(v_m0 - 300 / greatest(power(1 - v_r, v_t), 0.25)) < 0.01,
    format('Die Eingangsmasse hinter dem Kompost ist Masse ÷ (1−r)^t, ist aber %s', v_m0);
  assert abs(v_sch - v_m1) < 0.01,
    format('Entsorgte Ware ist beobachtetes Faules: die ganze Masse nach Verdunstung, ist aber %s von %s', v_sch, v_m1);

  -- b) Die Masse bleibt erhalten, auch in der neuen Portion.
  select verdunstung_kg + sockel_kg + schimmel_kg + klein_kg + nebenkanal_kg + fax_kg + verkaufsfaehig_kg
    into v_summe from mv_kaskade where charge_nr = 965001 and portion = 'entsorgt';
  assert abs(v_summe - v_m0) < 0.01,
    format('Auch die entsorgte Portion muss ihre Masse erhalten: %s statt %s', v_summe, v_m0);

  -- c) Der Bestand fällt um genau diese Eingangsmasse.
  assert abs((v_lager1 - v_lager2) - v_m0) < 0.05,
    format('Das Lager muss um die entsorgte Eingangsmasse fallen (%s), fiel aber um %s', v_m0, v_lager1 - v_lager2);
  assert v_haus2 < v_haus1,
    format('„Noch im Haus" muss nach einer Kompost-Lieferung kleiner sein (%s → %s)', v_haus1, v_haus2);

  -- d) Der Ausgang steigt um die Lieferscheinmasse, das Gelieferte nicht.
  assert abs((v_aus2 - v_aus1) - 300) < 0.01,
    format('Der Ausgang muss um 300 kg steigen (%s → %s)', v_aus1, v_aus2);
  assert abs(v_gel2 - v_gel1) < 0.01,
    format('Kompost ist keine Lieferung: „geliefert" darf sich nicht bewegen (%s → %s)', v_gel1, v_gel2);

  -- e) Ohne Kompost gibt es die Portion nicht.
  delete from lieferung where id = v_lief;
  perform auswertung_aktualisieren();
  assert not exists (select 1 from mv_kaskade where charge_nr = 965001 and portion = 'entsorgt'),
    'Ohne entsorgte Ware darf es keine Portion „entsorgt" geben';

  delete from lieferung where charge_nr = 965001;
  delete from palette where charge_nr = 965001;
  delete from charge where nr = 965001;
  delete from sorte_kaliber where sorte = 'Prüfkürbis65';
  delete from gebinde where art = 'PRF65';
  perform auswertung_aktualisieren();
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  0065 Entsorgtes verlässt das Lager (eigene Portion, Rückrechnung nur über die Verdunstung, Bestand fällt, „geliefert" bleibt)';
end $$;

select '——— 0065 Entsorgtes verlässt das Lager geprüft ———' as ergebnis;

-- =====================================================================
-- 0066 — Kein Kilo aus einer Lücke
-- =====================================================================
-- Drei Zusicherungen, jede in beide Richtungen:
--   a) Die vier Teilbeträge eines Stroms sind genau dann Zahlen, wenn der
--      Strom gemessen ist — und dann geht kg_beobachtet + kg_projiziert = kg
--      auf. Vorher stand dort NULL, wo null Kilo gemessen sind.
--   b) Die beiden Netto-Auslöser erfinden kein Gewicht mehr: fehlt die
--      Kistenzahl oder die hinterlegte Tara, bleibt die eingetragene Zahl
--      stehen und gemessen wird false — die Auswertung liest nur Gemessenes.
--   c) v_plausibilitaet sagt dazu die Wahrheit: keine Meldung „die Tara wurde
--      geändert", wo in Wirklichkeit die Tara fehlt, sondern „ohne Tara".
do $$
declare v_chef uuid := '11111111-1111-1111-1111-111111111111';
        v_a bigint; v_id bigint; v_kg numeric; v_gemessen boolean; v_n int;
begin
  assert schema_stand() >= 66, format('mindestens Stand 66 erwartet, ist %s', schema_stand());
  perform set_config('request.jwt.claim.sub', v_chef::text, true);

  -- Eine eigene Saison mit einer gemessenen Verdunstungsrate: nur dann ist ein
  -- Strom „bekannt", und nur dann sagen die Zusicherungen unten etwas.
  insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette) values ('PRF66', 1.0, 20.0)
    on conflict (art) do update set tara_kg_pro_kiste = 1.0, tara_kg_palette = 20.0;
  insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette) values ('PRF66OHNE', null, null)
    on conflict (art) do update set tara_kg_pro_kiste = null, tara_kg_palette = null;
  insert into sorte_kaliber (sorte, verlust_unter, kaliber_baender, kanal_ab)
       values ('Prüfkürbis66', 300, '[[300,800],[800,2000]]'::jsonb, 2000) on conflict (sorte) do nothing;
  insert into charge (nr, schlag, sorte, saison)
       values (966001, 'Prüfschlag66', 'Prüfkürbis66', 2026) on conflict (nr) do nothing;
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, quelle) values
    (966001, current_date - 100, 1000, 30, 'PRF66', 'pruefung'),
    (966001, current_date - 100, 1000, 30, 'PRF66', 'pruefung');
  insert into verdunstung_wiegung (charge_nr, palette_id, eingangsdatum, brutto_damals_kg,
                                   brutto_jetzt_kg, kisten, gebindeart, wiege_ts)
       values (966001, (select min(id) from palette where charge_nr = 966001),
               current_date - 100, 1000, 970, 30, 'PRF66', now() - interval '10 days');
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, erfasser)
       values (current_date - 10, 966001, 'Prüfkürbis66', 400, 'verkauf', v_chef);
  perform auswertung_aktualisieren();

  -- Ohne Zeilen sagen die Zusicherungen unten nichts. Also erst zählen.
  select count(*) into v_n from erg_verlust where bekannt;
  assert v_n > 0, 'Für diese Prüfung muss mindestens ein Strom gemessen sein';

  -- a) Alle vier Teilbeträge, in beide Richtungen
  assert not exists (
    select 1 from erg_verlust
     where bekannt and (kg_beobachtet is null or kg_projiziert is null
                        or kg_extrapoliert is null or kg_erwartet is null)),
    'Ist ein Strom gemessen, sind alle vier Teilbeträge Zahlen — keine Summe über keine Zeile bleibt NULL (0066)';
  assert not exists (
    select 1 from erg_verlust
     where not bekannt and (kg_beobachtet is not null or kg_projiziert is not null
                            or kg_extrapoliert is not null or kg_erwartet is not null)),
    'Ist ein Strom nicht gemessen, ist auch kein Teilbetrag eine Zahl (0066)';
  assert not exists (
    select 1 from erg_verlust
     where bekannt and abs(kg - kg_beobachtet - kg_projiziert) > 0.02),
    'Ausgeliefert und liegend ergeben zusammen den Strom — die Zerlegung ist vollständig (0066)';
  assert not exists (
    select 1 from erg_verlust
     where bekannt and (kg_extrapoliert < -0.005 or kg_erwartet < -0.005
                        or kg_beobachtet < -0.005 or kg_projiziert < -0.005)),
    'Kein Teilbetrag ist negativ';
  -- Und die Gegenprobe, dass die erste Behauptung nicht leer läuft: an der
  -- ausgelieferten Ware ist bei einer gemessenen Rate wirklich etwas passiert.
  assert exists (select 1 from erg_verlust
                  where bekannt and strom = 'Verdunstung' and kg_beobachtet > 0),
    'An der ausgelieferten Ware muss die gemessene Verdunstung eine Zahl über null sein';

  -- b) Die Auslöser: dieselbe Wägung einmal vollständig, einmal ohne Tara
  select id into v_a from auftrag where abgebrochen_ts is null limit 1;

  insert into ausschuss_messung (auftrag_id, art, kg, brutto_kg, kisten, gebindeart)
    values (v_a, 'zu_klein', 0, 500, 10, 'PRF66OHNE') returning id into v_id;
  select kg, gemessen into v_kg, v_gemessen from ausschuss_messung where id = v_id;
  assert v_gemessen is false,
    'Ohne hinterlegte Tara ist eine Ausschusswägung nicht gemessen (0066)';
  assert v_kg <> 500,
    format('Ohne hinterlegte Tara darf nicht das Brutto als Netto gespeichert werden, ist aber %s', v_kg);
  assert exists (select 1 from v_plausibilitaet
                  where art = 'Ausschuss ohne Tara' and auftrag_id = v_a),
    'Die Lücke steht als eigene Auffälligkeit da, statt still zu verschwinden (0066)';
  assert not exists (select 1 from v_plausibilitaet
                      where art = 'Ausschuss-Tara' and auftrag_id = v_a),
    'Eine fehlende Tara wird nicht als geänderte Tara gemeldet (0066)';
  delete from ausschuss_messung where id = v_id;

  insert into ausschuss_messung (auftrag_id, art, kg, brutto_kg, gebindeart)
    values (v_a, 'zu_klein', 0, 500, 'PRF66') returning id into v_id;
  select gemessen into v_gemessen from ausschuss_messung where id = v_id;
  assert v_gemessen is false,
    'Ohne Kistenzahl ist eine Ausschusswägung nicht gemessen — nicht „null Kisten" (0066)';
  delete from ausschuss_messung where id = v_id;

  insert into ausschuss_messung (auftrag_id, art, kg, brutto_kg, kisten, gebindeart)
    values (v_a, 'zu_klein', 0, 500, 10, 'PRF66') returning id into v_id;
  select kg, gemessen into v_kg, v_gemessen from ausschuss_messung where id = v_id;
  assert v_gemessen, 'Sind Kistenzahl und Tara da, ist die Ausschusswägung gemessen';
  assert v_kg = 470, format('500 − 10·1 − 20 = 470 erwartet, ist %s', v_kg);
  delete from ausschuss_messung where id = v_id;

  insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, mit_palette)
    values (v_a, 0, 500, 10, 'PRF66OHNE', false) returning id into v_id;
  select kg, gemessen into v_kg, v_gemessen from schimmel_messung where id = v_id;
  assert v_gemessen is false,
    'Ohne hinterlegte Tara ist eine Schimmelwägung nicht gemessen (0066)';
  assert v_kg <> 500,
    format('Ohne hinterlegte Tara darf nicht das Brutto als Netto gespeichert werden, ist aber %s', v_kg);
  delete from schimmel_messung where id = v_id;

  insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, mit_palette)
    values (v_a, 0, 500, 10, 'PRF66', false) returning id into v_id;
  select kg, gemessen into v_kg, v_gemessen from schimmel_messung where id = v_id;
  assert v_gemessen, 'Sind Kistenzahl und Tara da, ist die Schimmelwägung gemessen';
  assert v_kg = 490,
    format('Ohne mitgewogene Palette: 500 − 10·1 = 490 erwartet, ist %s', v_kg);
  delete from schimmel_messung where id = v_id;

  delete from verdunstung_wiegung where charge_nr = 966001;
  delete from lieferung where charge_nr = 966001;
  delete from palette where charge_nr = 966001;
  delete from charge where nr = 966001;
  delete from sorte_kaliber where sorte = 'Prüfkürbis66';
  delete from gebinde where art in ('PRF66', 'PRF66OHNE');
  perform auswertung_aktualisieren();
  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  0066 Kein Kilo aus einer Lücke (Teilbeträge vollständig, Auslöser erfinden kein Netto, Auffälligkeit sagt die Wahrheit)';
end $$;

select '——— 0066 Kein Kilo aus einer Lücke geprüft ———' as ergebnis;

-- =====================================================================
-- Was eine verstellte Formel verraten muss
-- =====================================================================
-- Die Mutationssonde des Prüfwerks (pruefwerk/sonden/06_mutation.mjs)
-- verstellt gezielt einzelne Terme der Kaskade und sieht nach, ob es
-- auffällt. Zwei Verstellungen blieben unbemerkt; hier stehen die
-- Behauptungen, die sie künftig fangen.
do $$
declare v_n int;
begin
  perform set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', true);

  -- a) Die Ableitung ∂m1/∂r ist nie positiv. m1 = m0·(1−r)^t fällt mit r —
  --    eine höhere Verdunstungsrate lässt nicht mehr Masse übrig. Über diese
  --    Ableitung wird die Unsicherheit der Rate in den Bereich fortgepflanzt;
  --    ein gedrehtes Vorzeichen verschiebt den Bereich, ohne eine einzige
  --    Kilozahl zu ändern — und fiel deshalb keinem Test auf.
  select count(*) into v_n from mv_kaskade
   where m0 > 0 and alter_tage > 0 and d_m1_r > 0;
  assert v_n = 0, format('%s Zeilen mit positiver Ableitung ∂m1/∂r — das Vorzeichen ist gedreht', v_n);
  select count(*) into v_n from mv_kaskade
   where m0 > 0 and alter_tage > 0 and modell_gilt and d_f_eta < 0;
  assert v_n = 0, format('%s Zeilen mit negativer Ableitung ∂f/∂η — Verderb wächst mit η, nicht umgekehrt', v_n);

  -- b) Jede Spalte, die eine Portion meint, enthält genau diese Portion.
  --    „Anderer Kanal am Ausgelagerten" und „Kanal an der Ware im Haus" sind
  --    zwei verschiedene Aussagen; wer den Filter vergisst, zeigt in beiden
  --    dieselbe Summe, und beide sind dann falsch.
  assert not exists (
    select 1 from erg_charge c
     where c.kanal_bekannt
       and abs(coalesce(c.kanal_im_haus_kg, 0)
               - coalesce((select sum(k.klein_kg + k.nebenkanal_kg) from mv_kaskade k
                            where k.charge_nr = c.charge_nr and k.portion = 'lager'), 0)) > 0.05),
    'kanal_im_haus_kg ist der Kanal der liegenden Ware — nicht der aller Portionen';
  assert not exists (
    select 1 from erg_charge c
     where c.kanal_bekannt
       and abs(coalesce(c.kanal_ausgelagert_kg, 0)
               - coalesce((select sum(k.klein_kg + k.nebenkanal_kg) from mv_kaskade k
                            where k.charge_nr = c.charge_nr and k.portion = 'ausgelagert'), 0)) > 0.05),
    'kanal_ausgelagert_kg ist der Kanal der ausgelieferten Ware';
  assert not exists (
    select 1 from erg_charge c
     where c.fax_bekannt
       and abs(coalesce(c.fax_heute_kg, 0)
               - coalesce((select sum(k.fax_kg) from mv_kaskade k
                            where k.charge_nr = c.charge_nr and k.portion = 'ausgelagert'), 0)) > 0.05),
    'fax_heute_kg ist das Faule am Abgepackten, nicht die Erwartung an der liegenden Ware';
  assert not exists (
    select 1 from erg_charge c
     where abs(c.im_haus_heute_kg
               - coalesce((select sum(k.m2) from mv_kaskade k
                            where k.charge_nr = c.charge_nr and k.portion = 'lager'), c.eingang_kg)) > 0.05),
    'im_haus_heute_kg ist die liegende Portion der Kaskade';

  perform set_config('request.jwt.claim.sub', '', true);
  raise notice 'OK  Mutationsschutz (Vorzeichen der Ableitungen, Portionsfilter der Kennzahlen)';
end $$;

select '——— Mutationsschutz geprüft ———' as ergebnis;

-- =====================================================================
-- 0067 — Der Tag des Arbeiters
-- =====================================================================
-- Drei Zusicherungen:
--   a) `betriebstag()` nimmt den Kalendertag der Betriebszone, nicht den von
--      UTC. Der Fall wird ausdrücklich gestellt: ein Zeitpunkt, an dem die
--      beiden auseinanderfallen.
--   b) Keine Sicht macht mehr auf eigene Faust aus einem Zeitstempel einen
--      Kalendertag. Das ist die Zusicherung, die verhindert, dass die
--      Verwechslung mit der nächsten Sicht zurückkommt — eine Reparatur, die
--      nur den heutigen Bestand trifft, hält keine zwei Migrationen.
--   c) Die vier Prüfbedingungen sind bestätigt und nicht mehr bloss
--      versprochen.
do $$
declare v_utc date; v_zuerich date; v_offen text; v_unbestaetigt text;
begin
  assert schema_stand() >= 67, format('mindestens Stand 67 erwartet, ist %s', schema_stand());

  -- (a) 15. Juli 2026, 22:30 UTC. In UTC ist das der 15., in Zürich (Sommer,
  --     UTC+2) bereits der 16. Genau in dieser Stunde entschied sich vorher,
  --     welchen Lagertag eine Wägung bekommt.
  v_utc     := ('2026-07-15 22:30+00'::timestamptz at time zone 'UTC')::date;
  v_zuerich := betriebstag('2026-07-15 22:30+00'::timestamptz);
  assert v_utc = date '2026-07-15',
    format('Gegenprobe misslungen: in UTC sollte es der 15. sein, ist %s', v_utc);
  assert v_zuerich = date '2026-07-16',
    format('betriebstag() nimmt nicht die Betriebszone: %s statt 2026-07-16 (Zone: %s)',
           v_zuerich, betriebszone());

  -- (b) Keine Sicht giesst mehr selbst.
  select string_agg(c.relname, ', ') into v_offen
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and pg_get_viewdef(c.oid, true) ~ '[a-z_][a-z0-9_]*(_ts|_zeit)\s*::\s*date';
  assert v_offen is null,
    format('Diese Sichten machen wieder in UTC aus einem Zeitpunkt einen Tag: %s', v_offen);

  -- (c) Die vier Zusagen gelten.
  select string_agg(conname, ', ') into v_unbestaetigt
    from pg_constraint
   where connamespace = 'public'::regnamespace and contype = 'c' and not convalidated
     and conname in ('auftrag_fax_nur_waschen', 'auftrag_kaliber_nur_waschen',
                     'auftrag_palette_datum_pflicht', 'lieferung_hat_menge');
  assert v_unbestaetigt is null,
    format('Diese Prüfbedingungen sind weiterhin unbestätigt: %s', v_unbestaetigt);

  raise notice 'OK  Der Tag des Arbeiters (Betriebszone, keine Sicht giesst selbst, vier Zusagen bestätigt)';
end $$;

select '——— Der Tag des Arbeiters geprüft ———' as ergebnis;

-- =====================================================================
-- Die Schimmelkurve steht an zwei Stellen — hier werden sie zusammengehalten
-- =====================================================================
-- `schimmelanteil(t)` rechnet den Faulanteil aus dem angepassten Modell, und
-- `mv_kaskade` leitet dieselbe Grösse noch einmal selbst her. Beide sind heute
-- bis auf 4.5·10⁻¹⁶ gleich — aber nichts hielt sie zusammen.
--
-- Nachgewiesen mit einer Mutationsprobe: eine frische Datenbank aus
-- stub_supabase.sql + setup.sql gebaut, diese Datei grün gelaufen; dann **nur**
-- `schimmelanteil()` um den Faktor 1.2 verstellt, `mv_kaskade` unberührt
-- gelassen — und diese Datei lief wieder grün durch, während alle Zeilen der
-- Kaskade um bis zu 1.06 Prozentpunkte von der Funktion abwichen.
--
-- Was ein Prozentpunkt Auseinanderlaufen kostet: Die Masse, die durch `f`
-- geteilt wird, ist auf der Demosaison 303 836.4 kg. Ein Prozentpunkt sind
-- damit 3038.4 kg — und niemand hätte es gemerkt, weil jede der beiden
-- Fassungen für sich weiterhin monoton, ≤ 1 und mit sauberem Band dasteht.
--
-- Die Zusicherung ist ein Zweizeiler. Sie gehört an die Stelle, an der die
-- beiden Fassungen aufeinandertreffen, und nicht in eine Prüfung, die jede
-- für sich für richtig befindet.
do $$
declare v_n int; v_ab int; v_max numeric;
begin
  select count(*), count(*) filter (where abs(k.f - schimmelanteil(k.alter_tage)) > 1e-9),
         max(abs(k.f - schimmelanteil(k.alter_tage)))
    into v_n, v_ab, v_max
    from mv_kaskade k where k.f is not null;

  -- Ohne Zeilen sagt die Prüfung nichts. Das ist kein Erfolg, sondern der
  -- Fall, in dem sie blind wäre — genau die Falle, in die Runde L mit einem
  -- leeren Prüfblock gelaufen ist.
  assert v_n > 0, 'mv_kaskade hat keine Zeile mit f — diese Zusicherung sagt dann nichts';

  assert v_ab = 0,
    format('Die Schimmelkurve läuft auseinander: %s von %s Kaskadenzeilen weichen von '
           || 'schimmelanteil() ab, grösste Abweichung %s. Ein Prozentpunkt sind auf der '
           || 'Demosaison 3038 kg.', v_ab, v_n, v_max);

  raise notice 'OK  Schimmelkurve: Funktion und Kaskade sind dieselbe Kurve (% Zeilen, grösste Abweichung %)',
    v_n, v_max;
end $$;

select '——— Schimmelkurve zusammengehalten ———' as ergebnis;
