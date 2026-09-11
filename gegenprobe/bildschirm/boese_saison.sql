-- =====================================================================
-- DIE BÖSE SAISON — Daten, wie sie auf dem Betrieb wirklich vorkommen,
-- wenn jemand müde ist, die Waage spinnt oder ein Zettel das falsche Jahr trägt.
--
-- Wozu: Die Demo-Saison ist brav. Jede Zahl darin ist plausibel, und deshalb
-- hat kein Prüfstand je gesehen, was die App mit einem Zettel von 2029 macht
-- (auf dem Betrieb: eine x-Achse bis −1000 Tage, alle Punkte als ein Strich).
-- Diese Datei legt **auf die Demo-Saison** ein Dutzend solcher Fälle, jeder
-- mit Buchstabe und Erwartung. Danach: `select auswertung_aktualisieren();`
--
-- So wird sie benutzt (lokal, nie auf dem Betrieb):
--   psql "$U" -c "create database boese template demo"
--   psql "postgresql://…/boese" -v ON_ERROR_STOP=1 -f gegenprobe/bildschirm/boese_saison.sql
--   psql "postgresql://…/boese" -c "select auswertung_aktualisieren()"
--   ./pruefstand/daten_dumpen.sh "postgresql://…/boese" gegenprobe/bildschirm/daten
--   node gegenprobe/bildschirm/invarianten.mjs
--
-- Alles hier ist markiert: Chargen 9901–9907, Paletten extern_id 'boese-…',
-- Aufträge und Lieferungen mit bemerkung 'BOESE'.
--
-- Die Erwartungen (E…) sind das, was die App tun **soll** — nicht, was sie
-- heute tut. Was sie heute tut, misst gegen_db.test.ts (GEGENPROBE_DBNAME=boese)
-- und invarianten.mjs; die Differenz ist die Arbeitsliste von Phase 3.
-- =====================================================================
set client_min_messages = warning;

do $$
declare
  v_auftrag bigint;
  v_wiegung bigint;
  v_heute date := heute();
  -- Wer eröffnet: der erste Betriebsleiter (auf der Demo: „Alexander"). Auf dem
  -- Betrieb setzt die App auth.uid(); hier gibt es keine Anmeldung.
  v_wer uuid := (select id from profil where rolle = 'admin' order by erstellt_ts limit 1);
begin
  if v_wer is null then raise exception 'Kein Betriebsleiter in profil — erst pruefstand/demo_bauen.sh'; end if;
  -- auth.uid() liest den Anspruch aus der Sitzung; die Vorgabewerte erfasser/eroeffnet_von hängen daran.
  perform set_config('request.jwt.claim.sub', v_wer::text, true);
  -- Die sieben Chargen. Sorten, die es in sorte_kaliber gibt.
  insert into charge (nr, schlag, sorte, saison) values
    (9901, 'Böse 1', 'Orangita',   extract(year from v_heute)::int),
    (9902, 'Böse 2', 'Orangita',   extract(year from v_heute)::int),
    (9903, 'Böse 3', 'Kaori Kuri', extract(year from v_heute)::int),
    (9904, 'Böse 4', 'Kaori Kuri', extract(year from v_heute)::int),
    (9905, 'Böse 5', 'Orangita',   extract(year from v_heute)::int),
    (9906, 'Böse 6', 'Kaori Kuri', extract(year from v_heute)::int),
    (9907, 'Böse 7', 'Lekor',      extract(year from v_heute)::int)
  on conflict (nr) do nothing;

  -- ---------------------------------------------------------------------
  -- B1  Der Zettel mit dem falschen Jahr.
  --     Sechs Paletten, alle vor 45 Tagen gekommen. Beim Sortieren tippt der
  --     Zähler bei einer davon „2029" statt „2026". Dazu ein zweiter Auftrag
  --     mit **nur** dieser einen Palette — so entsteht der Punkt bei −1000.
  -- E1  Kein Punkt mit negativen Lagertagen in erg_punkte/v_schimmel_punkte
  --     (oder: da, aber plausibel = false und in der Auffälligkeiten-Liste
  --     mit dem Satz „Eingangsdatum liegt nach der Arbeit").
  -- E2  Das Diagramm „Palox: Faules im Lager" beginnt bei 0 Lagertagen,
  --     und ein Hinweis nennt die ausgeschlossene Messung.
  -- ---------------------------------------------------------------------
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
  select 9901, v_heute - 45, 500, 30, 'G2', 'boese-9901-' || i from generate_series(1, 6) i;

  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, eroeffnet_von)
  values ('maschine', 'sortieren', 9901, (v_heute - 1)::timestamp + interval '8 hours', (v_heute - 1)::timestamp + interval '12 hours', 'abgeschlossen', 'BOESE B1 fünf richtig, eine 2029', v_wer)
  returning id into v_auftrag;
  insert into auftrag_palette (auftrag_id, eingangsdatum, ts)
  select v_auftrag, case when i = 6 then (v_heute - 45 + interval '3 years')::date else v_heute - 45 end,
         (v_heute - 1)::timestamp + interval '8 hours' + make_interval(mins => i * 10)
    from generate_series(1, 6) i;
  insert into schimmel_messung (auftrag_id, kg, ts) values (v_auftrag, 40, (v_heute - 1)::timestamp + interval '12 hours');
  insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, eroeffnet_von)
  values ('hand', 'waschen_sortieren', 9901, (v_heute - 2)::timestamp + interval '8 hours', (v_heute - 2)::timestamp + interval '11 hours', 'abgeschlossen', 'BOESE B1 nur die 2029-Palette', v_wer)
  returning id into v_auftrag;
  insert into auftrag_palette (auftrag_id, eingangsdatum, ts, brutto_zettel_kg)
  values (v_auftrag, (v_heute - 45 + interval '3 years')::date, (v_heute - 2)::timestamp + interval '8 hours 10 minutes', 500);
  insert into schimmel_messung (auftrag_id, kg, ts) values (v_auftrag, 12, (v_heute - 2)::timestamp + interval '11 hours');
  insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

  -- Dieselbe Palette, per Lagerkontrolle gewogen — mit dem 2029-Datum.
  -- E3  Nicht verwendbar; Grund „Wiegetag vor dem Eingang"; nicht in der Verdunstungs-Grafik.
  insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, gemessen, wiege_ts, faul_kg, bemerkung)
  values (9901, (v_heute - 45 + interval '3 years')::date, 500, 490, 30, 'G2', true, (v_heute - 3)::timestamp + interval '10 hours', 3, 'BOESE B1 Lagerkontrolle 2029');

  -- ---------------------------------------------------------------------
  -- B2  Schwerer geworden: Palette wiegt 5 % mehr als beim Eingang
  --     (falsche Palette gewogen oder Zettel-Brutto falsch).
  -- E4  verwendbar = false, Grund sichtbar; keine negative Rate im Koeffizienten.
  -- ---------------------------------------------------------------------
  insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, gemessen, wiege_ts, bemerkung)
  values (9901, v_heute - 45, 500, 525, 30, 'G2', true, (v_heute - 4)::timestamp + interval '10 hours', 'BOESE B2 schwerer');

  -- ---------------------------------------------------------------------
  -- B3  Die doppelte Lieferung: dieselbe Zeile zweimal aus dem Warenausgang.
  --     Charge 9902: 4 Paletten ≈ 1720 kg netto. Geliefert: 2 × 1500 kg.
  -- E5  ueberzaehlung_kg > 0 in der Kaskade; K1 hält; die Charge steht in
  --     den Auffälligkeiten („mehr geliefert als eingegangen").
  -- ---------------------------------------------------------------------
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
  select 9902, v_heute - 60, 500, 30, 'G2', 'boese-9902-' || i from generate_series(1, 4) i;
  insert into lieferung (datum, charge_nr, sorte, kg, kisten, gebindeart, ziel, kunde, bemerkung) values
    (v_heute - 10, 9902, 'Orangita', 1500, 100, 'G2', 'verkauf', 'Böser Kunde', 'BOESE B3 doppelt 1'),
    (v_heute - 10, 9902, 'Orangita', 1500, 100, 'G2', 'verkauf', 'Böser Kunde', 'BOESE B3 doppelt 2');

  -- ---------------------------------------------------------------------
  -- B4  Palette ohne Gebindeart: kein Netto, kein Kilo aus der Lücke.
  -- E6  eingang_kg der Charge ist hochgerechnet (n_paletten_mit_netto = 1 von 2)
  --     und die Charge sagt das; nirgends steht 0 kg oder NaN.
  -- ---------------------------------------------------------------------
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id) values
    (9903, v_heute - 30, 500, 30, 'G2', 'boese-9903-1'),
    (9903, v_heute - 30, 480, 28, null, 'boese-9903-2');

  -- ---------------------------------------------------------------------
  -- B5  Faules über der Basis: 900 kg Faules bei 430 kg Eingang (Tippfehler,
  --     oder der Palox war von einer anderen Charge).
  -- E7  anteil > 1 → plausibel = false; das Diagramm zeigt den Punkt nicht
  --     auf einer y-Achse bis 200 %, sondern nennt ihn als Auffälligkeit.
  -- ---------------------------------------------------------------------
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
  values (9904, v_heute - 50, 500, 30, 'G2', 'boese-9904-1');
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, eroeffnet_von)
  values ('maschine', 'sortieren', 9904, (v_heute - 5)::timestamp + interval '8 hours', (v_heute - 5)::timestamp + interval '10 hours', 'abgeschlossen', 'BOESE B5 Faules über Basis', v_wer)
  returning id into v_auftrag;
  insert into auftrag_palette (auftrag_id, eingangsdatum, ts) values (v_auftrag, v_heute - 50, (v_heute - 5)::timestamp + interval '8 hours 10 minutes');
  insert into schimmel_messung (auftrag_id, kg, ts) values (v_auftrag, 900, (v_heute - 5)::timestamp + interval '10 hours');
  insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

  -- ---------------------------------------------------------------------
  -- B6  Lieferung vor dem Eingang: geliefert am Tag −5 relativ zum Zettel.
  -- E8  alter_tage ≥ 0 in der Kaskade oder die Lieferung wird ausgewiesen;
  --     nie ein verkaufsfaehig_anteil > 1 (K3) und nie geliefert > m0 (K4).
  -- ---------------------------------------------------------------------
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
  select 9905, v_heute - 20, 500, 30, 'G2', 'boese-9905-' || i from generate_series(1, 3) i;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
  values (v_heute - 25, 9905, 'Orangita', 300, 'verkauf', 'Böser Kunde', 'BOESE B6 vor dem Eingang');

  -- ---------------------------------------------------------------------
  -- B7  Der Tippfehler: 99 999 kg brutto auf einer Palette.
  -- E9  Die Charge fällt in den Auffälligkeiten auf (Palette > 2 t); kein
  --     Diagramm „Eingang je Charge" wird von ihr allein bestimmt (A5).
  -- ---------------------------------------------------------------------
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id) values
    (9906, v_heute - 40, 99999, 30, 'G2', 'boese-9906-1'),
    (9906, v_heute - 40, 510, 30, 'G2', 'boese-9906-2');

  -- ---------------------------------------------------------------------
  -- B8  Nachts um halb eins: Wägung am Folgetag 00:30 Ortszeit = 22:30 UTC
  --     des Eingangstags. Betriebstag: 1 Lagertag; UTC: 0.
  -- E10 lagertage = 1 (betriebstag), verwendbar = true.
  -- ---------------------------------------------------------------------
  insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, gemessen, wiege_ts, bemerkung)
  values (9905, v_heute - 20, 500, 499.5, 30, 'G2', true, ((v_heute - 19)::timestamp + interval '30 minutes') at time zone 'Europe/Zurich', 'BOESE B8 halb eins');

  -- ---------------------------------------------------------------------
  -- B9  Umpalettiert: nach dem Sortieren stehen die Kisten auf neuen Paletten —
  --     Kistenzahl und Sortierdatum bekannt, Eingangsdatum und -gewicht nicht.
  --     Beim Waschen werden solche Paletten gezählt.
  -- E11 v_auftrag_masse hat eine Masse (wasch_paletten oder gebinde), Lagertage
  --     kommen aus der Charge (mv_sortier_eingang / Spanne), kein NULL-Absturz;
  --     die Chargen-Seite nennt die Herkunft „aus den gewaschenen Paletten".
  -- ---------------------------------------------------------------------
  insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, kistensystem, soll_kg_pro_kiste, eroeffnet_von)
  values ('hand', 'waschen', 9901, v_heute::timestamp + interval '7 hours', v_heute::timestamp + interval '9 hours', 'abgeschlossen', 'BOESE B9 umpalettiert', 'kiste_ab', 8, v_wer)
  returning id into v_auftrag;
  insert into auftrag_palette (auftrag_id, sortierdatum, kisten, ts)
  select v_auftrag, v_heute - 1, 32, v_heute::timestamp + interval '7 hours' + make_interval(mins => i * 10) from generate_series(1, 3) i;
  insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

  -- ---------------------------------------------------------------------
  -- B10 Abgebrochen: eine Arbeit mit Messungen, dann abgebrochen.
  -- E12 Nichts davon in Kaskade, Kurve oder Koeffizienten.
  -- ---------------------------------------------------------------------
  insert into auftrag (weg, station, charge_nr, start_ts, status, bemerkung, abgebrochen_ts, abbruch_grund, eroeffnet_von)
  values ('maschine', 'sortieren', 9902, (v_heute - 3)::timestamp + interval '8 hours', 'offen', 'BOESE B10 abgebrochen', (v_heute - 3)::timestamp + interval '9 hours', 'falsche Charge', v_wer)
  returning id into v_auftrag;
  insert into auftrag_palette (auftrag_id, eingangsdatum, ts) values (v_auftrag, v_heute - 60, (v_heute - 3)::timestamp + interval '8 hours 10 minutes');
  insert into schimmel_messung (auftrag_id, kg, ts) values (v_auftrag, 200, (v_heute - 3)::timestamp + interval '8 hours 50 minutes');

  -- ---------------------------------------------------------------------
  -- B11 Eine Sorte ohne jede Messung (Lekor): nur Eingang und eine Lieferung.
  -- E13 Koeffizienten aus dem Gesamtwert, Basis-Text sagt es; kein NaN, kein
  --     leeres Diagramm ohne Erklärung; Sortenvergleich zeigt „keine Messung".
  -- ---------------------------------------------------------------------
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
  select 9907, v_heute - 35, 500, 30, 'G2', 'boese-9907-' || i from generate_series(1, 5) i;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
  values (v_heute - 7, 9907, 'Lekor', 600, 'verkauf', 'Böser Kunde', 'BOESE B11 ohne Messung');

  -- ---------------------------------------------------------------------
  -- B12 Alles an einem Tag, alles auf einmal: Charge 9904 bekommt am selben
  --     Tag Eingang, Wägung und Lieferung — Lagertage 0 überall.
  -- E14 Keine Division durch null, keine Rate aus 0 Tagen, Kaskade mit
  --     alter_tage 0 und (1−r)^0 = 1.
  -- ---------------------------------------------------------------------
  insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, gemessen, wiege_ts, bemerkung)
  values (9904, v_heute - 50, 500, 500, 30, 'G2', true, (v_heute - 50)::timestamp + interval '15 hours', 'BOESE B12 am selben Tag');
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
  values (v_heute - 50, 9904, 'Kaori Kuri', 100, 'hofladen', 'Hofladen', 'BOESE B12 am selben Tag');

  raise notice 'Böse Saison gelegt: 7 Chargen, % Paletten, % Aufträge, % Lieferungen.',
    (select count(*) from palette where extern_id like 'boese-%'),
    (select count(*) from auftrag where bemerkung like 'BOESE%'),
    (select count(*) from lieferung where bemerkung like 'BOESE%');
end $$;
