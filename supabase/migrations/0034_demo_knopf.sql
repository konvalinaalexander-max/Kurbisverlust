-- =====================================================================
-- 0034 — Demo-Saison auf Knopfdruck
--
-- Bisher lag die Demo-Saison als SQL-Datei herum: kopieren, im
-- Supabase-SQL-Editor einfügen, Run — und zum Aufräumen nochmal dasselbe
-- mit einer zweiten Datei. Das ist ein Umweg über ein Werkzeug, das mit der
-- App nichts zu tun hat, und niemand macht ihn zweimal freiwillig.
--
-- Hier werden daraus zwei Funktionen, die die App direkt aufrufen kann.
-- Derselbe Inhalt, dieselben Zahlen — nur eben ein Knopf statt eines
-- Ausflugs ins Dashboard des Datenbank-Anbieters. Die beiden SQL-Dateien
-- rufen ab jetzt nur noch diese Funktionen auf, damit es die Saison nicht
-- an zwei Orten gibt, die auseinanderlaufen können.
--
-- SICHERHEIT
--
-- Beide Funktionen laufen als "security definer", also mit den Rechten des
-- Eigentümers und damit an den Zeilenregeln vorbei. Das ist nötig, weil die
-- Demo Dinge tut, die im Alltag niemand darf: Arbeiten rückdatieren,
-- abgeschlossene Aufträge anlegen, Messungen im Namen anderer erfassen.
-- Das Tor davor ist die Prüfung auf den Betriebsleiter, gleich in der ersten
-- Zeile — ein Arbeiter kommt hier nicht durch.
-- =====================================================================

create or replace function demo_daten_laden()
returns text language plpgsql security definer set search_path = public as $fn$
begin
  -- Aus der App darf das nur der Betriebsleiter. Im SQL-Editor gibt es keinen
  -- Login (auth.uid() ist NULL) — wer dort sitzt, hat ohnehin vollen Zugriff
  -- auf die Datenbank, da wäre die Prüfung nur Theater.
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter laden.';
  end if;

  if exists (select 1 from palette where extern_id like 'demo-%') then
    raise exception E'Die Demo-Saison ist schon geladen.\n'
      'Zum Neuladen zuerst entfernen.';
  end if;

  declare v_wer uuid := auth.uid();
  begin
    -- Aus der App heraus ist jemand angemeldet und gilt als Erfasser. Im
    -- SQL-Editor gibt es keinen Login, auth.uid() ist dort NULL — und alle
    -- Erfasser-Spalten sind NOT NULL. Dann tritt der Betriebsleiter ein.
    if v_wer is null then
      select id into v_wer from profil where rolle = 'admin' order by erstellt_ts limit 1;
    end if;
    if v_wer is null then
      select id into v_wer from profil order by erstellt_ts limit 1;
    end if;
    if v_wer is null then
      raise exception E'Es gibt noch kein Benutzerkonto.\n'
        'Lege zuerst dein Betriebsleiter-Konto an (README, Schritt 7) '
        'und versuche es dann nochmal.';
    end if;
    -- Beide Schreibweisen setzen: Supabase liest je nach Version die eine oder
    -- die andere, und auth.uid() muss hier einen Wert liefern.
    perform set_config('request.jwt.claim.sub', v_wer::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_wer)::text, true);
  end;

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
    -- ---------- Käufer und ein abweichendes Sortierschema -------------------
    -- Coop und Migros gibt es auf dem Betrieb; Coop will Tiana enger sortiert.
    insert into kaeufer (code, name) values ('coop', 'Coop'), ('migros', 'Migros')
    on conflict (code) do nothing;
    insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
    select 'Tiana', 'coop', date '2026-10-01', 'kiste', 8,
           'DEMO — Coop nimmt Tiana in der 8-kg-Kiste'
     where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'coop');

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
        -- Direkt aus der Palettenzuordnung gerechnet, nicht aus v_auftrag_masse:
        -- die ist seit 0016 eine gespeicherte Ansicht und mitten im Anlegen noch
        -- leer. Der frühere Leseversuch dort traf NULL, und das stille
        -- »continue« übersprang sämtliche Messungen der Demo — deshalb zeigte
        -- die Auswertung 0.0 t Verdunstung und ein Modell aus sechs Punkten.
        select sum(m.netto_kg),
               sum((v_start::date - m.eingangsdatum) * m.netto_kg) / nullif(sum(m.netto_kg), 0)
          into v_masse, v_tage
          from v_auftrag_palette_masse m where m.auftrag_id = v_auftrag;
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
                  -- Mit Streuung je Wägung (±20 % auf die Rate): echte Paletten
                  -- verdunsten verschieden schnell, und ein Demo-Bereich von
                  -- ±0.1 % lehrte den Betriebsleiter eine falsche Sicherheit.
                  round((v_netto * power(1 - v_rate * (0.8 + random() * 0.4),
                                         v_start::date - v_datum)
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
  end;

  -- ---------- Weg 1, zweiter Abschnitt: Waschen ----------------------------
  -- Spec §3: Lager → Sortieren → **Lager** → Waschen. Zwischen den beiden
  -- Schritten liegen Wochen, in denen die Ware in Kaliber-Kisten weiter
  -- verdunstet und verdirbt. Ohne diese Aufträge sieht der Betriebsleiter den
  -- zweiten Lagerabschnitt nie — und die Demo zeigt eine Welt, die es so nicht
  -- gibt.
  declare v record; v_neu bigint; v_i int := 0; v_stand numeric := palox_tara_kg();
  begin
    -- v_auftrag_masse ist eine gespeicherte Ansicht. Innerhalb dieser einen
    -- Transaktion kennt sie die eben angelegten Aufträge noch nicht — ohne
    -- Neuberechnung liefe die Schleife ins Leere und die Demo wäre still
    -- unvollständig.
    perform auswertung_aktualisieren();
    for v in
      select a.id, a.charge_nr, a.start_ts, m.eingang_netto_kg
        from auftrag a
        join v_auftrag_masse m on m.auftrag_id = a.id
       where a.bemerkung = 'DEMO' and a.station = 'sortieren'
         and m.eingang_netto_kg is not null
       order by a.id
    loop
      v_i := v_i + 1;
      -- Zwei Drittel sind inzwischen gewaschen, der Rest wartet noch.
      exit when v_i > 6;
      insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status,
                           durchsatz_kg, bemerkung)
      values ('maschine', 'waschen', v.charge_nr,
              v.start_ts + (35 + v_i * 7) * interval '1 day',
              v.start_ts + (35 + v_i * 7) * interval '1 day' + interval '7 hours',
              'abgeschlossen',
              round(v.eingang_netto_kg * 0.90, 2), 'DEMO')
      returning id into v_neu;

      -- Schimmel #2: was seit dem Sortieren dazugekommen ist. Der Palox steht
      -- auf der Waage und läuft über die Arbeiten weiter; die Waage zeigt
      -- brutto (Behälter 45 kg). Gespeichert wird der Stand, die Menge ist
      -- Ableitung — nach dem dritten Waschgang wird der Palox geleert.
      v_stand := case when v_i = 4 then palox_tara_kg() else v_stand end
                 + round(v.eingang_netto_kg * 0.004, 1);
      insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert)
      values (v_neu, round(v.eingang_netto_kg * 0.004)::int, v_stand, v_i = 4);
    end loop;

    -- Ein laufender Waschgang, damit die Kisten-Maske etwas zu zeigen hat.
    insert into auftrag (weg, station, charge_nr, start_ts, status, kaliber_idx, bemerkung)
    select 'maschine', 'waschen', a.charge_nr, now() - interval '2 hours', 'offen', 0, 'DEMO'
      from auftrag a where a.bemerkung = 'DEMO' and a.station = 'sortieren'
     order by a.id desc limit 1
    returning id into v_neu;
    insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl) values (v_neu, 0, 6);

    raise notice 'Demo: zweiter Lagerabschnitt (Waschen) angelegt';
  end;

  -- ---------- Lagerkontrollen ----------------------------------------------
  -- Ein paar zufällig gegriffene Paletten, wie sie der neue Bildschirm
  -- „Palette kontrollieren" erfasst: ohne Arbeit, mit Pflichtfeld „davon faul".
  -- Damit zeigt die Demo auch den Selektionsvergleich mit echtem Befund.
  declare v record; v_i int := 0; v_netto numeric; v_tage int; v_faul numeric;
          v_kontrolltag date;
  begin
    for v in
      select p.charge_nr, p.eingangsdatum, p.brutto_kg, p.kisten, p.gebindeart
        from palette p order by p.id offset 40
    loop
      v_i := v_i + 1;
      exit when v_i > 8;
      -- Der Kontrolltag muss IN der Demo-Saison liegen (Sep 2026 – Mär 2027),
      -- nicht am heutigen Datum: die Demo spielt in der Zukunft, und
      -- current_date ergäbe negative Lagertage.
      v_kontrolltag := date '2027-02-20' - (v_i * 9);
      v_netto := v.brutto_kg - v.kisten * 1.5 - 25;
      v_tage  := greatest(v_kontrolltag - v.eingangsdatum, 1);
      -- Faulanteil grob nach Alter, zwei Kontrollen ohne Befund (0 ist eine
      -- echte Antwort, kein leeres Feld)
      v_faul  := case when v_i % 4 = 0 then 0
                      else round(v_netto * least(v_tage, 200) * 0.00018, 1) end;
      insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg,
             brutto_jetzt_kg, kisten, gebindeart, wiege_ts, faul_kg,
             sichtbar_schimmel, bemerkung)
      values (v.charge_nr, v.eingangsdatum, v.brutto_kg,
              round((v_netto * power(0.9994, v_tage) + v.kisten * 1.5 + 25)::numeric, 1),
              v.kisten, v.gebindeart,
              v_kontrolltag, v_faul, v_faul > 0, 'DEMO-KONTROLLE');
    end loop;
    raise notice 'Demo: Lagerkontrollen angelegt';
  end;

  -- ---------- Warenausgang -------------------------------------------------
  -- Ohne ihn ist der Restbestand eine Hochrechnung, die niemand nachgezählt hat,
  -- und die Bilanz kann nichts prüfen (Spec §9).
  declare v record; v_i int := 0;
  begin
    perform auswertung_aktualisieren();
    for v in
      select b.charge_nr, b.sorte, b.ausgelagert_kg
        from v_hochrechnung_basis b
       where b.ausgelagert_kg > 0 order by b.ausgelagert_kg desc
    loop
      v_i := v_i + 1;
      -- Der grösste Teil geht als Verkauf raus, in Kilo wie auf dem Lieferschein.
      insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
      values (current_date - (v_i * 5), v.charge_nr, v.sorte,
              round(v.ausgelagert_kg * 0.80, 2), 'verkauf',
              case when v_i % 2 = 0 then 'Grosshandel Zürich' else 'Genossenschaft' end,
              'DEMO');
      -- Ein kleiner Teil in Kisten — damit die Umrechnung sichtbar wird.
      if v_i % 3 = 0 then
        insert into lieferung (datum, sorte, kisten, ziel, kunde, bemerkung)
        values (current_date - (v_i * 5) + 1, v.sorte,
                greatest(round(v.ausgelagert_kg * 0.05 / 8)::int, 1), 'verkauf',
                'Hofladen Wetzikon', 'DEMO');
      end if;
    end loop;
    raise notice 'Demo: Warenausgang angelegt';
  end;

  -- ---------- Sortier-CSVs für drei Maschinen-Läufe ------------------------
  -- Histogramm statt Einzelzeilen (so speichert die App es auch). Die Verteilung
  -- ist grob glockenförmig um 900 g, mit Ausläufern unter der Sorten-Grenze und
  -- über 2000 g — daraus entstehen Ausschuss- und Nebenkanal-Anteil.
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

    -- Kisten zählen (0041). Erst hier, denn die Masse je Kaliber steht in der
    -- CSV, die gerade eingelesen wurde. Beim Sortieren zählt der Arbeiter die
    -- gefüllten Kaliber-Kisten; aus beidem folgt, was eine Kiste wiegt — in
    -- der Demo rund 40 kg.
    insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
    select l.auftrag_id, g.kaliber_idx,
           greatest(round(sum(g.anzahl::bigint * g.gewicht_g) / 1000.0 / 40.0)::int, 1)
      from sortier_lauf l
      join sortier_gewicht g on g.lauf_id = l.id
      join auftrag a on a.id = l.auftrag_id
     where a.bemerkung = 'DEMO' and a.station = 'sortieren' and g.klasse = 'kaliber'
       and g.kaliber_idx is not null
     group by l.auftrag_id, g.kaliber_idx
    on conflict (auftrag_id, kaliber_idx) do nothing;

    -- Und ein abgeschlossener Waschgang, der seine Menge nicht eingetippt
    -- bekommt, sondern aus gezählten Kisten rechnet — der Weg, den der Betrieb
    -- ab jetzt geht. Der Schimmel bezieht sich dann auf die kleinere Menge
    -- eines einzelnen Kalibers.
    for v_r in
      select a.id from auftrag a
       where a.bemerkung = 'DEMO' and a.station = 'waschen'
         and a.status = 'abgeschlossen'
       order by a.id desc limit 1
    loop
      update auftrag set durchsatz_kg = null, kaliber_idx = 0 where id = v_r.id;
      insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl) values (v_r.id, 0, 22)
      on conflict (auftrag_id, kaliber_idx) do nothing;
      update schimmel_messung set kg = 4 where auftrag_id = v_r.id;
    end loop;

    raise notice 'Demo: Sortier-CSVs eingelesen und Kisten gezählt';
  end;

  -- ---------- Zwei Sonderfälle, damit man sie einmal gesehen hat -----------
  declare v_auftrag bigint; v_charge int := 1611;
  begin
    -- (1) Eine abgebrochene Arbeit: taucht in keiner Auswertung auf,
    --     ist aber unter Stammdaten → Abgebrochene Arbeiten sichtbar.
    insert into auftrag (weg, station, charge_nr, start_ts, bemerkung)
    values ('hand', 'waschen_sortieren', v_charge, timestamptz '2026-11-03 09:00+01', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, date '2026-09-20' from generate_series(1, 4);
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

    -- (3) Eine laufende Arbeit von heute, mit drei gezählten Paletten: damit
    --     die Arbeiter-Masken in der Demo nicht leer sind und sich anfassen lassen.
    insert into auftrag (weg, station, charge_nr, start_ts, status, kaeufer, bemerkung)
    values ('hand', 'waschen_sortieren', 1650, now() - interval '2 hours', 'offen', 'coop', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, eingangsdatum from palette where charge_nr = 1650
     order by eingangsdatum limit 3;

    raise notice 'Demo: Sonderfälle angelegt (abgebrochen, Zahlendreher, laufende Arbeit)';
  end;
  return (
  select format('Demo-Saison steht: %s Paletten in %s Chargen, %s Arbeiten, %s Sortierläufe. '
                  || 'Eingang %s t. Jetzt in der App unter Auswertung anschauen.',
                  (select count(*) from palette where extern_id like 'demo-%'),
                  (select count(distinct charge_nr) from palette where extern_id like 'demo-%'),
                  (select count(*) from auftrag where bemerkung = 'DEMO'),
                  (select count(*) from sortier_lauf where datei_name like 'DEMO-%'),
                  (select round(sum(eingang_netto_kg) / 1000, 1) from v_charge_rueckgrat))
  );
end $fn$;

comment on function demo_daten_laden is
  'Legt die erfundene Demo-Saison an (Aufträge mit bemerkung = ''DEMO'', Paletten mit extern_id ''demo-…'', Sortierdateien ''DEMO-…''). Echte Daten bleiben unberührt.';

grant execute on function demo_daten_laden() to authenticated;


create or replace function demo_daten_entfernen()
returns text language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter entfernen.';
  end if;

  -- Reihenfolge ist wichtig: verdunstung_wiegung und sortier_lauf hängen mit
  -- "on delete set null" am Auftrag — würde man den Auftrag zuerst löschen,
  -- blieben ihre Zeilen verwaist zurück und zählten weiter mit.
  delete from verdunstung_wiegung
   where auftrag_id in (select id from auftrag where bemerkung = 'DEMO')
      or bemerkung = 'DEMO-KONTROLLE';

  delete from ausgang_wiegung
   where auftrag_id in (select id from auftrag where bemerkung = 'DEMO');

  delete from sortier_gewicht
   where lauf_id in (select id from sortier_lauf where datei_name like 'DEMO-%');
  delete from sortier_lauf where datei_name like 'DEMO-%';

  -- Der Rest hängt mit "on delete cascade" am Auftrag
  delete from lieferung where bemerkung = 'DEMO';
  delete from auftrag where bemerkung = 'DEMO';

  delete from palette where extern_id like 'demo-%';
  delete from sortierschema where bemerkung like 'DEMO%';
  delete from kaeufer k where code in ('coop', 'migros')
     and not exists (select 1 from auftrag a where a.kaeufer = k.code)
     and not exists (select 1 from sortierschema s where s.kaeufer = k.code);

  perform auswertung_aktualisieren();
  return (
    select format('Demo-Daten entfernt. Übrig: %s Paletten, %s Arbeiten, %s Sortierläufe.',
                  (select count(*) from palette),
                  (select count(*) from auftrag),
                  (select count(*) from sortier_lauf))
  );
end $fn$;

comment on function demo_daten_entfernen is
  'Löscht restlos alles, was demo_daten_laden() angelegt hat. Echte Daten bleiben unberührt — erkannt wird die Demo an bemerkung = ''DEMO'', extern_id ''demo-…'' und datei_name ''DEMO-…''.';

grant execute on function demo_daten_entfernen() to authenticated;
