-- =====================================================================
-- 0093 — Die Demo-Saison hat Rückmeldungen
--
-- 0081 verlangt, dass die Demo jede Fähigkeit der App zeigt, und ihr
-- Prüfblock lässt keine Sicht der Auswertung leer. 0091 hat die
-- Rückmeldung zur Ware gebracht und mit ihr v_arbeit_kommentar — auf der
-- Demo-Saison blieb die Sicht leer, und der Prüfblock hat es gemeldet,
-- wie er soll. Also hinterlässt die Demo, was die Halle seit 0091
-- hinterlassen kann: drei Rückmeldungen zur Ware und eine zur App, an
-- Arbeiten, an denen man sie im Dashboard auch findet — am Punkt der
-- Faul-Kurve, an einer Auffälligkeit, im Arbeitsfenster, unter Betrieb →
-- Arbeiten. Geschrieben, nicht gesprochen: eine Aufnahme wäre eine Datei
-- im Bucket, und die kann eine SQL-Funktion nicht anlegen.
--
-- Die Ladefunktion steht hier noch einmal ganz, wie schon 0081 sie nach
-- 0052 ganz neu schrieb — neu ist allein Abschnitt 9 (und der Satz am
-- Ende zählt die Rückmeldungen mit). Warum nicht nur ein Nachtrag: Die
-- Funktion ist ein Zustand, keine Geschichte. setup.sql behält von jeder
-- Funktion nur die letzte Fassung (supabase/verdichten.mjs), das
-- Abschreiben kostet dort also nichts, und wer wissen will, wie die Demo
-- heute entsteht, liest eine Datei, nicht eine Kette von Nachträgen.
-- =====================================================================

create or replace function demo_daten_laden()
returns text language plpgsql security definer set search_path = public as $fn$
declare
  v_anker date := current_date - 215;
  -- Der Schnitt „was ist schon passiert" hing bisher an now(). Damit war die
  -- Saison nur *fast* reproduzierbar: lud man sie morgens und mittags, kamen
  -- verschieden viele Arbeiten heraus, weil ein Start von gestern abend beim
  -- einen Lauf noch vor der Grenze lag und beim anderen dahinter. Gemessen:
  -- 367 gegen 376 Arbeiten, zwei Läufe im Abstand von Minuten. Jetzt liegt
  -- die Grenze auf einer festen Stunde des Tages — zweimal laden am selben
  -- Tag gibt zweimal dieselbe Saison. Nur die laufenden Arbeiten am Schluss
  -- hängen weiter an now(), denn die sollen wirklich gerade laufen.
  v_jetzt timestamptz := current_date::timestamptz + interval '17 hours';
  v_wer   uuid := auth.uid();
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter laden.';
  end if;
  if exists (select 1 from palette where extern_id like 'demo-%') then
    raise exception E'Die Demo-Saison ist schon geladen.\nZum Neuladen zuerst entfernen.';
  end if;

  -- Im SQL-Editor gibt es keinen Login — dann tritt der Betriebsleiter ein.
  if v_wer is null then
    select id into v_wer from profil where rolle = 'admin' order by erstellt_ts limit 1;
  end if;
  if v_wer is null then select id into v_wer from profil order by erstellt_ts limit 1; end if;
  if v_wer is null then
    raise exception E'Es gibt noch kein Benutzerkonto.\nLege zuerst dein Betriebsleiter-Konto an (README, Schritt 7) und versuche es dann nochmal.';
  end if;
  perform set_config('request.jwt.claim.sub', v_wer::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_wer)::text, true);

  -- ---------- Stammdaten der Demo ----------------------------------------
  -- Bei Konflikt bleibt der bestehende Käufer, wie er ist — samt seiner
  -- (leeren) Bemerkung. Genau daran erkennt das Entfernen ihn als echten.
  insert into kaeufer (code, name, bemerkung) values
    ('nordmarkt', 'Nordmarkt Genossenschaft', 'DEMO'), ('talhof', 'Talhof Bio AG', 'DEMO'),
    ('gruenwerk', 'Grünwerk Handel', 'DEMO'), ('feldfrisch', 'Feldfrisch Ost', 'DEMO')
  on conflict (code) do nothing;
  -- Nordmarkt nimmt Butternut in der 8-kg-Kiste; Talhof will Kaori Kuri enger.
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'nordmarkt', v_anker + 20, 'kiste', 8, 'DEMO — Nordmarkt nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'nordmarkt' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'gruenwerk', v_anker + 25, 'kiste', 8, 'DEMO — Grünwerk nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'gruenwerk' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab, bemerkung)
  select 'Kaori Kuri', 'talhof', v_anker + 60, 'kaliber', 600, '[[600,1000],[1000,1400],[1400,2000]]'::jsonb, 2000,
         'DEMO — Talhof will Kaori Kuri in engeren Bändern (beim Eröffnen einer Arbeit geändert)'
   where not exists (select 1 from sortierschema where sorte = 'Kaori Kuri' and kaeufer = 'talhof' and art = 'kaliber');
  -- Ein Vorlauf: Charge 1611 lieferte schon 5 t, bevor die App lief.
  insert into charge_vorlauf (charge_nr, ausgang_vor_app_kg, bemerkung)
  values (1611, 5000, 'DEMO — vor dem Erfassungsbeginn ausgeliefert')
  on conflict (charge_nr) do nothing;

  -- ---------- Hilfstabellen ------------------------------------------------
  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;
  create temp table demo_charge (
    nr int primary key, sorte text, weg text, kg numeric, kw int,
    anteil_verarbeitet numeric,      -- wie viel der Charge bis heute verarbeitet ist
    r numeric,                       -- Verdunstung je Tag
    lambda numeric, k numeric, sockel numeric,   -- Verderbskurve
    fax_anteil numeric, gramm int, sd int,       -- Faules beim Fax, Gewicht je Kürbis
    kg_kiste numeric, kaeufer text
  );
  -- Die ganze Anbauplanung, nicht nur ein Teil davon: jede Charge des
  -- Stammdatenregisters bekommt einen Eingang. Vorher blieben sechs ohne
  -- jede Zeile — im Dashboard standen sie als Chargen ohne Daten, und wer
  -- die Demo anschaute, hielt das für einen Fehler des Werkzeugs.
  insert into demo_charge (nr, kg, kw, anteil_verarbeitet) values
    (1598,  2200, 35, 1.00), (1599,  1400, 34, 0.85), (1601,  9800, 38, 0.25),
    (1603,  3100, 36, 1.00), (1604,  2600, 34, 0.90), (1605,  1200, 34, 1.00),
    (1606,   800, 33, 1.00), (1607,  1900, 34, 1.00), (1608,  6400, 36, 0.70),
    (1609, 12500, 35, 0.80), (1610,  4200, 37, 0.45), (1611, 38000, 37, 0.60),
    (1612, 16500, 35, 0.75), (1613, 24000, 35, 0.90), (1614,  3900, 34, 1.00),
    (1615,  3100, 34, 1.00), (1616,  8600, 34, 0.85), (1617,  2400, 35, 1.00),
    (1618,  4100, 34, 1.00), (1619,  1800, 34, 1.00), (1620,  2900, 35, 0.55),
    (1623,  9100, 36, 0.65), (1624,  7800, 35, 0.85), (1625,  2600, 34, 1.00),
    (1626,  4600, 39, 0.00), (1627,  2900, 39, 0.40), (1628, 11000, 34, 0.95),
    (1630, 10800, 34, 0.90), (1631, 14200, 39, 0.15), (1632, 35000, 37, 0.50),
    (1633, 22000, 38, 0.35), (1634,  6600, 36, 0.70), (1635,  5900, 36, 0.80),
    (1636, 17000, 36, 0.55), (1637,  5400, 36, 0.75), (1638,  4800, 36, 0.30),
    (1646,  7200, 34, 0.80), (1647,  8100, 39, 0.25), (1648,  9700, 34, 0.90),
    (1649, 20500, 38, 0.40), (1650,  2400, 39, 0.00), (1651,  3300, 35, 1.00);
  update demo_charge d set sorte = c.sorte from charge c where c.nr = d.nr;
  -- Butternut von Hand, alles andere über die Maschine. Sorteneigenschaften
  -- so, wie sie im Betrieb beobachtet werden: Hokkaido verdunstet schneller,
  -- Butternut hält länger, Mandarin ist klein.
  -- Mit WHERE, obwohl jede Zeile gemeint ist: Supabase lässt die API-Verbindung
  -- mit der Sicherung safeupdate laufen, die ein UPDATE ohne Bedingung abweist —
  -- auch in einer Funktion, auch auf einer Hilfstabelle.
  update demo_charge set
    weg    = case when sorte in ('Tiana', 'Mieluna') then 'hand' else 'maschine' end,
    r      = case sorte when 'Tiana' then 0.00045 when 'Mieluna' then 0.00050 when 'Butterkin' then 0.00060
                        when 'Orangita' then 0.00090 when 'Lekor' then 0.00065 else 0.00080 end,
    -- λ so, dass nach 150 Tagen rund 8 % (Butternut) bis 14 % (Mandarin) faul sind
    lambda = case sorte when 'Tiana' then 800 when 'Mieluna' then 720 when 'Butterkin' then 600
                        when 'Orangita' then 450 when 'Lekor' then 560 when 'Kaori Kuri' then 520 else 500 end,
    k      = case sorte when 'Tiana' then 1.5 when 'Orangita' then 1.9 else 1.7 end,
    sockel = case sorte when 'Orangita' then 0.006 else 0.004 end,
    fax_anteil = case sorte when 'Tiana' then 0.012 when 'Mieluna' then 0.015 when 'Orangita' then 0.030
                            when 'Butterkin' then 0.020 else 0.024 end,
    gramm  = case sorte when 'Orangita' then 560 when 'Butterkin' then 1250 when 'Lekor' then 1500
                        when 'Kaori Kuri' then 1100 when 'Amoro' then 1300 when 'Ker Madec' then 1000
                        when 'Fictor' then 1400 when 'Orange Summer' then 1200 when 'Bolp 5110' then 1200
                        when 'Tiana' then 1400 else 1200 end,
    sd     = case sorte when 'Orangita' then 170 when 'Tiana' then 420 when 'Lekor' then 420 else 320 end,
    kg_kiste = case sorte when 'Orangita' then 10.8 when 'Tiana' then 12.4 when 'Mieluna' then 12.0
                          when 'Butterkin' then 11.8 else 11.4 end,
    kaeufer = case nr % 4 when 0 then 'nordmarkt' when 1 then 'talhof' when 2 then 'gruenwerk' else 'feldfrisch' end
   where sorte is not null;
  -- Die zwei grossen Abnehmer teilen sich die frühen Chargen; die zwei
  -- kleineren nehmen, was später kommt — so steht es in der Verkaufsplanung.
  update demo_charge set kaeufer = case when nr % 2 = 0 then 'nordmarkt' else 'talhof' end
   where kw <= 35;

  create temp table demo_pal (
    id bigint, nr int, datum date, netto numeric, kisten int, verarbeitet boolean default false
  );
  create temp table demo_lauf (
    auftrag_id bigint, nr int, sorte text, start_ts timestamptz, masse_kg numeric, alter_tage numeric,
    art text, kaeufer text, baender jsonb, kg_je_kiste numeric,
    kisten int[]       -- gefüllte Kisten je Band (Index = Band)
  );

  -- ---------- 1. Wareneingang: je Charge in ihrer Erntewoche ---------------
  declare d record; v_n int; v_p int; v_tag date; v_kisten int; v_netto numeric; v_je_tag int;
          v_zufall numeric; v_art text; v_id bigint;
  begin
    for d in select * from demo_charge order by nr loop
      v_n := greatest(round(d.kg / (32 * d.kg_kiste))::int, 2);
      v_je_tag := case when v_n <= 6 then 4 when v_n <= 20 then 8 when v_n <= 60 then 14 else 22 end;
      v_tag := v_anker + (d.kw - 34) * 7 + (d.nr % 3);
      for v_p in 1 .. v_n loop
        -- Werktage: Samstag und Sonntag wird nicht geerntet
        if v_p > 1 and (v_p - 1) % v_je_tag = 0 then v_tag := v_tag + 1; end if;
        while extract(isodow from v_tag) >= 6 loop v_tag := v_tag + 1; end loop;
        v_zufall := (hashtext(format('pal-%s-%s', d.nr, v_p))::bigint & 2147483647)::numeric / 2147483647;
        v_kisten := 30 + (v_p * 7 + d.nr) % 5;
        v_netto  := round(v_kisten * d.kg_kiste * (0.94 + 0.12 * v_zufall), 1);
        -- Fremde Produzenten liefern teils in IFCO-Kisten
        v_art := case when d.nr in (1648, 1628, 1630, 1631) and v_p % 3 = 0 then 'IFCO 6416' else 'G2' end;
        insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id)
        values (d.nr, v_tag, v_netto + v_kisten * (case when v_art = 'G2' then 1.5 else 1.68 end) + 25,
                v_kisten, v_art, format('demo-%s-%s', d.nr, v_p))
        returning id into v_id;
        insert into demo_pal (id, nr, datum, netto, kisten) values (v_id, d.nr, v_tag, v_netto, v_kisten);
      end loop;
    end loop;
    raise notice 'Demo: Wareneingang angelegt (% Paletten)', (select count(*) from demo_pal);
  end;

  -- ---------- 2. Verarbeitung -----------------------------------------------
  -- Sortieren (Maschine) bzw. Waschen + Sortieren (Hand), in mehreren Läufen,
  -- ohne FIFO. Je Lauf: Paletten mit Datum vom Zettel, Palox zu Beginn und am
  -- Ende (Faules nach der Verderbskurve), CSV oder Wägungen, Kisten je Kaliber.
  declare d record; v_lauf int; v_n_laeufe int; v_n_pal int; v_verarbeitet int; v_ziel int;
          v_start timestamptz; v_auftrag bigint; v_masse numeric; v_tage numeric; v_f numeric;
          v_schimmel numeric; v_zufall numeric; v_schema bigint; v_art text; v_kaeufer text;
          v_baender jsonb; v_nb int; v_i int; v_hist jsonb; v_n int; v_gramm numeric;
          v_kisten int[]; v_kg_band numeric; v_klein numeric; v_gross numeric; v_x numeric;
          p record; v_pal_ids bigint[]; v_netto numeric; v_kisten_p int; v_brutto numeric;
          v_wiegung bigint; v_datum date; v_abstand int;
  begin
    for d in select * from demo_charge where anteil_verarbeitet > 0 order by nr loop
      select count(*) into v_n_pal from demo_pal where nr = d.nr;
      v_ziel := round(v_n_pal * d.anteil_verarbeitet)::int;
      if v_ziel = 0 then continue; end if;
      v_n_laeufe := greatest(ceil(v_ziel / 16.0)::int, 1);
      v_verarbeitet := 0;
      v_abstand := greatest(round(172.0 / v_n_laeufe)::int, 8);

      for v_lauf in 1 .. v_n_laeufe loop
        -- Wie viele Paletten dieser Lauf nimmt, und wann
        v_n := least(v_ziel - v_verarbeitet, 12 + (d.nr + v_lauf) % 8);
        exit when v_n <= 0;
        v_zufall := (hashtext(format('lauf-%s-%s', d.nr, v_lauf))::bigint & 2147483647)::numeric / 2147483647;
        -- Jede Charge kommt zu ihrer Zeit dran: die einen bald nach der Ernte,
        -- die anderen Wochen später — so bleibt bis heute etwas zu tun.
        v_start := (v_anker + (d.kw - 34) * 7 + 12 + (d.nr % 7) * 12 + (v_lauf - 1) * v_abstand + floor(v_zufall * 6)::int)::timestamptz
                   + interval '7 hours' + (d.nr % 3) * interval '30 minutes';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        exit when v_start > v_jetzt - interval '2 days';

        -- Kein FIFO: ungerade Läufe greifen die jüngsten Paletten, gerade die
        -- ältesten — je nachdem, an welchen Stapel man herankommt.
        select array_agg(id) into v_pal_ids from (
          select id from demo_pal where nr = d.nr and not verarbeitet
           order by case when v_lauf % 2 = 1 then datum end desc,
                    case when v_lauf % 2 = 0 then datum end asc, id
           limit v_n) s;
        update demo_pal set verarbeitet = true where id = any(v_pal_ids);
        select sum(netto), sum(netto * (v_start::date - datum)) / sum(netto)
          into v_masse, v_tage from demo_pal where id = any(v_pal_ids);
        v_verarbeitet := v_verarbeitet + v_n;

        -- Die Fassung: Maschine immer Kaliber; von Hand die 8-kg-Kiste — bis auf
        -- eine Charge, die Migros nach Kaliber will (dort bleibt das Kisten-
        -- gewicht beim Fax unbekannt, und die Auswertung sagt es).
        v_kaeufer := d.kaeufer;
        v_art := case when d.weg = 'maschine' then 'kaliber'
                      when d.nr = 1647 then 'kaliber' else 'kiste' end;
        v_schema := sortierschema_fuer(d.sorte, v_kaeufer, v_start::date, v_art);
        select kaliber_baender into v_baender from sortierschema where id = v_schema;
        if v_art = 'kaliber' and v_baender is null then
          select kaliber_baender into v_baender from sortierschema
           where sorte = d.sorte and art = 'kaliber' and kaeufer is null order by gilt_ab desc limit 1;
        end if;
        v_nb := coalesce(jsonb_array_length(v_baender), 0);

        -- 0060: das Kistensystem steht an der Arbeit — von Hand „Kiste ab 8 kg"
        -- oder Stück-Kisten eines Kalibers; die Sortiermaschine fragt nicht.
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung,
                             geplante_paletten, kistensystem, soll_kg_pro_kiste, stueck_je_kiste)
        values (case when d.weg = 'maschine' then 'maschine' else 'hand' end::verarbeitungsweg,
                case when d.weg = 'maschine' then 'sortieren' else 'waschen_sortieren' end::station,
                d.nr, v_start,
                v_start + make_interval(mins => (240 + v_n * 14 + floor(v_zufall * 40)::int)),
                'abgeschlossen', v_kaeufer, v_schema, 'DEMO', v_n,
                case when d.weg = 'maschine' then null when v_art = 'kiste' then 'kiste_ab' else 'stueck' end,
                case when d.weg <> 'maschine' and v_art = 'kiste' then 8 end,
                case when d.weg <> 'maschine' and v_art = 'kaliber' then greatest(round(d.kg_kiste * 1000 / d.gramm)::int, 1) end)
        returning id into v_auftrag;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_auftrag, id from profil order by erstellt_ts limit (2 + (v_lauf % 2))
        on conflict do nothing;

        -- Paletten zählen — mit dem Datum vom Zettel; beim Waschen + Sortieren
        -- auch mit dem Gewicht vom Zettel (0060), damit der Palox einen Nenner hat.
        -- 0076: die Maske lässt die Palette aus der Liste greifen — dann steht
        -- sie mit ihrer Nummer da und die Masse ist exakt bekannt. Jede dritte
        -- Arbeit tippt stattdessen nur das Zetteldatum ab; dort bleibt die
        -- Masse ein Mittel. Beides kommt vor, und die Herkunftsspalte im
        -- Dashboard soll beides zeigen.
        -- 0072: in welchem Gebinde die Palette steht, wird gefragt — meistens
        -- G2, manchmal IFCO.
        insert into auftrag_palette (auftrag_id, palette_id, eingangsdatum, ts, brutto_zettel_kg, gebindeart)
        select v_auftrag,
               case when (d.nr + v_lauf) % 3 <> 0 then dp.id end,
               dp.datum, v_start + make_interval(mins => (10 + row_number() over (order by dp.id) * 12)::int),
               case when d.weg <> 'maschine' then (select pl.brutto_kg from palette pl where pl.id = dp.id) end,
               (select pl.gebindeart from palette pl where pl.id = dp.id)
          from demo_pal dp where dp.id = any(v_pal_ids);

        -- Verderb bis heute: Weibull je Sorte plus Sockel, mit Streuung je Lauf
        v_f := 1 - exp(-power(v_tage / d.lambda, d.k));
        v_schimmel := round(v_masse * power(1 - d.r, v_tage) * (d.sockel + v_f) * (0.8 + 0.4 * v_zufall));
        insert into schimmel_messung (auftrag_id, kg, ts) values (v_auftrag, greatest(v_schimmel, 1)::int, v_start + interval '5 hours');
        insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

        if d.weg = 'maschine' then
          -- ---- Die Sortier-CSV: was am Band ankommt, jeder Kürbis gewogen ----
          -- Masse am Band = Eingang − Verdunstung − Faules; das Gewicht je
          -- Kürbis ist mit der Lagerdauer entsprechend kleiner.
          v_x := v_masse * power(1 - d.r, v_tage) - v_schimmel;
          v_gramm := d.gramm * power(1 - d.r, v_tage);
          v_n := greatest(round(v_x * 1000 / v_gramm)::int, 50);
          -- Glockenförmig in 10-g-Stufen von −3σ bis +3σ, plus ein leichter
          -- zweiter Gipfel bei manchen Schlägen (ungleiche Reife).
          select jsonb_agg(jsonb_build_array(g, anz)) into v_hist from (
            select g, greatest(round(v_n * 10 * (
                     exp(-power((g - v_gramm) / d.sd, 2) / 2) / (d.sd * 2.5066)
                     + case when d.nr % 5 = 0 then 0.35 * exp(-power((g - v_gramm * 1.45) / (d.sd * 0.6), 2) / 2) / (d.sd * 0.6 * 2.5066) else 0 end
                   ))::int, 0) as anz
              from generate_series(greatest(round((v_gramm - 3 * d.sd) / 10) * 10, 100)::int,
                                   round((v_gramm + 3.5 * d.sd) / 10)::int * 10, 10) g) h
           where anz > 0;
          perform csv_lauf_speichern(
            d.nr, format('DEMO-%s-%s', d.nr, to_char(v_start, 'DD-MM-HH24-MI')),
            format('demo/sortierdateien/%s-%s.csv', d.nr, to_char(v_start, 'YYYYMMDD')),
            format('demo-pruefsumme-%s', v_auftrag),
            v_start + interval '90 minutes', 'dateiname',
            '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
            (v_n * 1.03)::int, 2 + v_lauf % 3, 5 + v_lauf % 7, (v_n * 0.02)::int, v_hist);

          -- Kisten je Kaliber gezählt: Masse des Bands durch das Kistengewicht
          v_kisten := array[]::int[];
          for v_i in 0 .. v_nb - 1 loop
            select coalesce(sum((e->>1)::numeric * (e->>0)::numeric), 0) / 1000 into v_kg_band
              from jsonb_array_elements(v_hist) e
             where (e->>0)::int >= (v_baender->v_i->>0)::int and (e->>0)::int < (v_baender->v_i->>1)::int;
            v_kisten := v_kisten || greatest(round(v_kg_band / (d.kg_kiste * (0.97 + 0.06 * v_zufall)))::int, 0);
          end loop;
          insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
          select v_auftrag, i - 1, v_kisten[i] from generate_series(1, v_nb) i where v_kisten[i] > 0
          on conflict (auftrag_id, kaliber_idx, sortierdatum) do nothing;
          insert into demo_lauf values (v_auftrag, d.nr, d.sorte, v_start, v_x, v_tage, 'kaliber', v_kaeufer, v_baender, d.kg_kiste, v_kisten);
        else
          -- ---- Von Hand: eine Palette gewogen, Ausschuss gewogen, fertige Palette ----
          select p2.* into p from demo_pal p2 where p2.id = v_pal_ids[1];
          v_wiegung := null;
          v_brutto := p.netto + p.kisten * 1.5 + 25;
          -- 0076: die gewogene Palette ist bekannt, nicht nur ihr Eingangstag.
          -- Jede vierte Wägung sagt ausserdem, wie viel davon faul war — der
          -- einzige Schimmelwert, dessen Palette nicht nach dem Aussehen
          -- ausgewählt wurde.
          insert into verdunstung_wiegung (auftrag_id, charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                           kisten, gebindeart, kuerbisse_pro_kiste, faul_kg, wiege_ts)
          values (v_auftrag, d.nr, p.id, p.datum, v_brutto,
                  round((p.netto * power(1 - d.r * (0.7 + 0.6 * v_zufall), v_start::date - p.datum) + p.kisten * 1.5 + 25) * 2) / 2.0,
                  p.kisten, 'G2', 4 + (d.nr % 3),
                  case when v_lauf % 4 = 0 then round(p.netto * (0.004 + 0.02 * v_zufall), 1) end,
                  v_start + interval '2 hours')
          returning id into v_wiegung;
          -- Die Wägung gehört zu der gezählten Palette mit demselben Zetteldatum —
          -- sonst zählte die Kohortenrechnung sie einem anderen Eingangstag zu.
          update auftrag_palette set wiegung_id = v_wiegung
           where id = (select min(id) from auftrag_palette
                        where auftrag_id = v_auftrag and eingangsdatum = p.datum);

          v_x := v_masse * power(1 - d.r, v_tage) - v_schimmel;
          v_klein := round(v_x * (0.025 + 0.02 * v_zufall));
          v_gross := round(v_x * (0.010 + 0.015 * (1 - v_zufall)));
          v_kisten_p := greatest(ceil(v_klein / 22.0), 1)::int;
          insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts, bemerkung)
          values (v_auftrag, 'zu_klein', v_klein + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours',
                  case when v_lauf % 6 = 0 then 'Viel Kleines in dieser Charge' end);
          if v_lauf % 3 = 0 then
            -- Einmal nicht gewogen, nur geschätzt — das zeigt die Datenqualität.
            insert into ausschuss_messung (auftrag_id, art, kg, ts) values (v_auftrag, 'zu_gross', v_gross::int, v_start + interval '6 hours');
          else
            v_kisten_p := greatest(ceil(v_gross / 22.0), 1)::int;
            insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts)
            values (v_auftrag, 'zu_gross', v_gross + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours');
          end if;
          insert into auftrag_angabe (auftrag_id, schluessel, wert)
          values (v_auftrag, 'ausschuss_leer', 'true'), (v_auftrag, 'ausschuss_von_auftrag', 'true');

          -- Fertige Paletten: bei „Kiste ab 8 kg" überfüllt (8.2–8.6), nach
          -- Kaliber ohne Soll — dort zählt nur das Kistengewicht.
          v_kg_band := case when v_art = 'kiste' then 8.15 + 0.45 * v_zufall else 11.5 + 1.5 * v_zufall end;
          for v_i in 1 .. 2 loop
            insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, kuerbisse_pro_kiste, ts)
            values (v_auftrag, d.nr, round((32 * (v_kg_band + 0.05 * v_i) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                    case when v_art = 'kiste' then 5 + (d.nr % 2) else null end,
                    v_start + make_interval(hours => 3 + v_i));
          end loop;
          -- Für das Fax: die Masse in Kisten (−1 = Kiste nach Soll, sonst Bänder gleich verteilt)
          v_kisten := array[]::int[];
          if v_art = 'kiste' then
            v_kisten := array[greatest(round((v_x - v_klein - v_gross) / v_kg_band)::int, 1)];
          else
            for v_i in 0 .. v_nb - 1 loop
              v_kisten := v_kisten || greatest(round((v_x - v_klein - v_gross) / v_nb / v_kg_band)::int, 0);
            end loop;
          end if;
          -- 0072: „die fertigen paletten werden eher nicht gezählt" — aber
          -- wenn doch, ist die Ausgangsmasse der Arbeit bekannt statt nur
          -- geschätzt. Zwei von drei Arbeiten zählen sie.
          if v_lauf % 3 <> 0 then
            update auftrag set fertige_paletten_gesamt =
                   greatest(ceil((v_x - v_klein - v_gross) / (32 * v_kg_band))::int, 1)
             where id = v_auftrag;
          end if;
          insert into demo_lauf values (v_auftrag, d.nr, d.sorte, v_start, v_x - v_klein - v_gross, v_tage, v_art, v_kaeufer, v_baender, v_kg_band, v_kisten);
        end if;
      end loop;
    end loop;
    raise notice 'Demo: Sortieren und Waschen + Sortieren angelegt (% Arbeiten)', (select count(*) from demo_lauf);
  end;

  -- ---------- 3. Waschen je Kaliber, Wochen später (Weg 1) ------------------
  -- Aus jedem Sortierlauf werden die Bänder nacheinander gewaschen: die
  -- gefüllten Kisten geleert, Palox abgelesen (Schimmel #2, klein), eine
  -- fertige Palette gewogen. Nicht jedes Band ist schon dran — was wartet,
  -- steht in der Auswertung als „wartet aufs Waschen".
  declare l record; v_i int; v_start timestamptz; v_neu bigint; v_zufall numeric; v_kg numeric; v_kisten int;
          v_anteil numeric; v_gewaschen int[]; v_zufall2 numeric;
          v_eigen boolean; v_ohne_pal boolean; v_von int; v_bis int;
  begin
    for l in select * from demo_lauf where art = 'kaliber' and exists (select 1 from auftrag a where a.id = demo_lauf.auftrag_id and a.station = 'sortieren') order by start_ts loop
      v_gewaschen := array[]::int[];
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_zufall := (hashtext(format('wasch-%s-%s-%s', l.nr, l.start_ts::date, v_i))::bigint & 2147483647)::numeric / 2147483647;
        -- Das letzte Band der späten Läufe wartet noch
        if l.kisten[v_i] = 0 or (v_i = array_length(l.kisten, 1) and l.start_ts > v_jetzt - interval '60 days') then
          v_gewaschen := v_gewaschen || 0; continue;
        end if;
        v_start := l.start_ts + make_interval(days => 6 + v_i * 5 + floor(v_zufall * 25)::int) + interval '1 hour';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        if v_start > v_jetzt - interval '1 day' then v_gewaschen := v_gewaschen || 0; continue; end if;
        v_kisten := l.kisten[v_i];
        -- 0054: manchmal nennt das Etikett kein Band der Fassung, sondern ein
        -- eigenes Kaliber — „ab 900 g" statt „Band 2". Dann steht die Grenze
        -- an der Arbeit und der Bandindex bleibt leer.
        v_eigen := (l.nr + v_i) % 13 = 0 and l.baender is not null
                   and jsonb_array_length(l.baender) > v_i - 1;
        if v_eigen then
          v_von := (l.baender->(v_i - 1)->>0)::int + 50;
          v_bis := (l.baender->(v_i - 1)->>1)::int - 50;
          if v_bis <= v_von then v_eigen := false; end if;
        end if;
        -- Auf Weg 1 sind die Eingangspaletten beim Waschen längst in
        -- Kaliberkisten aufgelöst. Meistens zählt der Vorarbeiter die
        -- Zwischenlager-Paletten; jede vierte Arbeit kann das nicht und gibt
        -- stattdessen die verarbeitete Menge an — sonst hätte der dort
        -- gemessene Schimmel keinen Nenner. Beim eigenen Kaliber ist das
        -- immer so: dort kennt niemand das Gewicht einer Kiste, weil dieses
        -- Band beim Sortieren nie gezählt wurde. Gemessen, bevor das hier
        -- stand: fünf Waschgänge meldeten „die Messung hat keinen Nenner" —
        -- richtig gerechnet, aber in einer Demo unnötig.
        v_ohne_pal := (l.nr + v_i + extract(day from l.start_ts)::int) % 4 = 0 or v_eigen;
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, sortierschema_id, bemerkung,
                             kistensystem, stueck_je_kiste, kaliber_von_g, kaliber_bis_g, durchsatz_kg, geplante_paletten)
        values ('maschine', 'waschen', l.nr, v_start,
                v_start + make_interval(mins => 90 + v_kisten * 5 + floor(v_zufall * 30)::int),
                'abgeschlossen', case when v_eigen then null else v_i - 1 end,
                (select sortierschema_id from auftrag where id = l.auftrag_id), 'DEMO',
                'stueck', greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1),
                case when v_eigen then v_von end, case when v_eigen then v_bis end,
                case when v_ohne_pal then round(v_kisten * l.kg_je_kiste) end,
                case when v_ohne_pal then null else ceil(v_kisten / 32.0)::int end)
        returning id into v_neu;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_neu, id from profil order by erstellt_ts limit 2 on conflict do nothing;
        -- Q22, Schichtwechsel: an langen Waschgängen geht einer um vier Uhr
        -- und ein anderer übernimmt. Wer gegangen ist, steht mit seiner Zeit da.
        if v_kisten > 120 then
          update auftrag_teilnehmer set verlassen_ts = v_start + interval '4 hours'
           where auftrag_id = v_neu
             and profil_id = (select profil_id from auftrag_teilnehmer where auftrag_id = v_neu order by profil_id limit 1);
          insert into auftrag_teilnehmer (auftrag_id, profil_id, beigetreten_ts)
          select v_neu, id, v_start + interval '4 hours' from profil
           where id not in (select profil_id from auftrag_teilnehmer where auftrag_id = v_neu)
           order by erstellt_ts limit 1
          on conflict do nothing;
        end if;
        -- 0061: beim Waschen werden Paletten gezählt — das Sortierdatum vom
        -- Zettel und die Kisten je Palette (höchstens 32), so wie die Maske.
        if not v_ohne_pal then
          insert into auftrag_palette (auftrag_id, sortierdatum, kisten, gebindeart)
          select v_neu, l.start_ts::date, least(32, v_kisten - (s - 1) * 32),
                 case when s % 5 = 0 then 'IFCO 6416' else 'G2' end
            from generate_series(1, ceil(v_kisten / 32.0)::int) s;
        end if;
        -- Schimmel #2: was seit dem Sortieren in der Kiste dazukam. Der Verderb
        -- geht in der Kiste weiter, nach derselben Kurve — bedingt auf das, was
        -- beim Sortieren noch gut war: (F(t_wasch) − F(t_sort)) / (1 − F(t_sort)).
        v_kg := v_kisten * l.kg_je_kiste;
        select d2.lambda, d2.k into v_anteil, v_zufall2 from demo_charge d2 where d2.nr = l.nr;
        v_anteil := greatest(
          ((1 - exp(-power((l.alter_tage + (v_start::date - l.start_ts::date)) / v_anteil, v_zufall2)))
           - (1 - exp(-power(l.alter_tage / v_anteil, v_zufall2))))
          / (exp(-power(l.alter_tage / v_anteil, v_zufall2))), 0.002);
        insert into schimmel_messung (auftrag_id, kg, ts)
        values (v_neu, greatest(round(v_kg * v_anteil * (0.75 + 0.5 * v_zufall)), 1)::int, v_start + interval '3 hours');
        insert into auftrag_angabe (auftrag_id, schluessel, wert)
        values (v_neu, 'eine_charge', 'true');
        -- Fertige Palette nach Kaliber: kein Soll, nur das Kistengewicht
        insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, ts, kaliber_idx, kuerbisse_pro_kiste, bemerkung)
        values (v_neu, l.nr, round((32 * l.kg_je_kiste * (0.96 + 0.08 * v_zufall) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                v_start + interval '2 hours', case when v_eigen then null else v_i - 1 end,
                greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1),
                case when v_eigen then format('Eigenes Kaliber %s–%s g', v_von, v_bis) end);
        -- Wie viele fertige Paletten am Ende dastanden. Ohne diese Zahl kennt
        -- die App nur die *gewogene* — die Ausgangsmasse wäre unbekannt.
        if (l.nr + v_i) % 3 <> 0 then
          update auftrag set fertige_paletten_gesamt = greatest(ceil(v_kisten / 32.0)::int, 1) where id = v_neu;
        end if;
        v_gewaschen := v_gewaschen || v_kisten;
      end loop;
      update demo_lauf set kisten = v_gewaschen where auftrag_id = l.auftrag_id;
    end loop;
    raise notice 'Demo: Waschgänge angelegt';
  end;

  -- ---------- 4. Fax und Lieferungen ----------------------------------------
  -- Nach dem Waschen steht die Ware in Kisten, bis eine Bestellung kommt. Das
  -- Fax macht daraus Paletten mit Etikett und sortiert dabei Faules aus —
  -- gewogen, kistenweise. Was gemacht wird, geht innert Tagen raus. Die
  -- Lieferungen einer Charge verteilen sich so über Wochen und verschränken
  -- sich mit denen anderer Chargen.
  declare l record; v_i int; v_start timestamptz; v_neu bigint; v_zufall numeric; v_kisten int; v_rest int;
          v_teil int; v_masse numeric; v_faul numeric; v_n_faul int; v_j int; v_kaeufer text; v_kunde text;
          v_lief numeric; v_schema bigint;
          -- 0061: die Verkaufsdatei zur Lieferung
          v_pos int := 0; v_lief_id bigint; v_lief_datum date; v_einheit text; v_inhalt int;
          v_gja numeric; v_menge numeric; v_stueck int; v_artikel text; v_artikel_id text;
  begin
    -- Die Warenwirtschaft der Demo: jede Lieferung steht auch als Zeile einer
    -- Verkaufsdatei da (Einheit, Gebindeinhalt, Kisten je Chargenzeile), so wie
    -- sie der Import aus dem Perigon anlegt. Daraus die verkauften Kisten.
    insert into ausgang_quelle (code, name, dateiname_muster, bemerkung)
    values ('DEMO', 'Demo-Warenwirtschaft', 'demo', 'DEMO') on conflict (code) do nothing;
    for l in select * from demo_lauf order by start_ts loop
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_rest := l.kisten[v_i];
        if v_rest <= 0 then continue; end if;
        v_j := 0;
        while v_rest > 0 loop
          v_j := v_j + 1;
          exit when v_j > 4;
          v_zufall := (hashtext(format('fax-%s-%s-%s-%s', l.nr, l.start_ts::date, v_i, v_j))::bigint & 2147483647)::numeric / 2147483647;
          -- Ein Teil der Ware wartet noch auf eine Bestellung
          if v_zufall < 0.12 then exit; end if;
          v_teil := least(v_rest, 32 * (1 + floor(v_zufall * 4)::int) + floor(v_zufall * 20)::int);
          v_start := l.start_ts + make_interval(days => 20 + v_i * 6 + v_j * 9 + floor(v_zufall * 12)::int) + interval '2 hours';
          while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
          exit when v_start > v_jetzt - interval '1 day';
          v_kaeufer := case when v_j % 3 = 0 then (case l.kaeufer when 'nordmarkt' then 'talhof' when 'talhof' then 'nordmarkt' when 'gruenwerk' then 'feldfrisch' else 'gruenwerk' end) else l.kaeufer end;
          v_schema := case when l.art = 'kiste' then sortierschema_fuer(l.sorte, l.kaeufer, v_start::date, 'kiste') else null end;
          -- 0060: die Palettenzahl als Gesamtzahl, die Tage seit dem Waschen, das
          -- Kistensystem. Jede zweite Fax-Arbeit zählt zusätzlich noch Kisten
          -- (der Weg vor 0060) — beide Wege müssen dieselbe Masse ergeben.
          insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung,
                               kistensystem, soll_kg_pro_kiste, paletten_gesamt, tage_seit_waschen)
          values ('maschine', 'waschen', l.nr, true, v_start,
                  v_start + make_interval(mins => 40 + v_teil * 2 + floor(v_zufall * 25)::int),
                  'abgeschlossen', v_kaeufer, v_schema, 'DEMO',
                  case when l.art = 'kiste' then 'kiste_ab' else 'stueck' end,
                  case when l.art = 'kiste' then 8 end,
                  ceil(v_teil / 32.0)::int,
                  case when v_j % 3 = 0 then null else 1 + floor(v_zufall * 3)::int end)
          returning id into v_neu;
          insert into auftrag_teilnehmer (auftrag_id, profil_id)
          select v_neu, id from profil order by erstellt_ts limit 1 on conflict do nothing;
          if v_j % 2 = 1 then
            insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
            values (v_neu, case when l.art = 'kiste' then -1 else v_i - 1 end, v_teil);
          end if;
          insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_neu, 'eine_charge', 'true');
          -- Faules: kistenweise gewogen, 1–3 Kisten, Anteil je Sorte mit Streuung.
          -- Jede fünfte Fax-Arbeit hat nichts Faules — auch das ist eine Messung.
          v_masse := v_teil * l.kg_je_kiste;
          v_faul := round(v_masse * (select fax_anteil from demo_charge where nr = l.nr) * (0.4 + 1.2 * v_zufall), 1);
          if v_j % 5 = 0 or v_faul < 1 then
            insert into schimmel_messung (auftrag_id, kg, ts, bemerkung) values (v_neu, 0, v_start + interval '1 hour', 'Nichts Faules');
            v_faul := 0;
          else
            v_n_faul := least(greatest(ceil(v_faul / 9.0)::int, 1), 3);
            insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, mit_palette, ts)
            select v_neu, 0, round(v_faul / v_n_faul + 1.5 + (s - 1) * 0.5, 1), 1, 'G2', false,
                   v_start + make_interval(mins => 30 + s * 20)
              from generate_series(1, v_n_faul) s;
            select coalesce(sum(kg), 0) into v_faul from schimmel_messung where auftrag_id = v_neu;
          end if;
          -- Die Lieferung, wie die Verkaufsdatei sie führt (0061): Kisten × Inhalt,
          -- nominal — „Kiste ab 8 kg" steht mit 8 kg auf dem Lieferschein, die
          -- Stück-Kiste mit Stück × Nenngewicht. Was die Kiste wirklich wiegt,
          -- weiss nur die Waage (Überfüllung). 1–7 Tage nach dem Fax.
          v_lief_datum := (v_start + make_interval(days => 1 + floor(v_zufall * 6)::int))::date;
          v_kunde := case v_kaeufer when 'nordmarkt' then 'Nordmarkt Verteilzentrale' when 'talhof' then 'Talhof Bio AG'
                                    when 'gruenwerk' then 'Grünwerk Handel' else 'Feldfrisch Ost' end;
          v_pos := v_pos + 1;
          if l.art = 'kiste' then
            v_einheit := 'kg'; v_inhalt := 8; v_gja := 1;
            v_artikel := 'Bio Kürbis ' || l.sorte || ' lose'; v_artikel_id := 'kürb' || lower(left(l.sorte, 3));
          else
            v_stueck := greatest(round(l.kg_je_kiste * 1000 / (select gramm from demo_charge where nr = l.nr))::int, 1);
            v_einheit := 'Stk.'; v_inhalt := v_stueck;
            v_gja := round((select gramm from demo_charge where nr = l.nr) / 1000.0, 2);
            v_artikel := 'Bio Kürbis ' || l.sorte || ' Dem'; v_artikel_id := 'kürb' || lower(left(l.sorte, 3)) || 'd';
          end if;
          v_menge := v_teil * v_inhalt;
          v_lief := round(v_menge * v_gja, 1);
          insert into ausgang_artikel (artikel_id, artikel, ist_kuerbis, sorte, bemerkung)
          values (v_artikel_id, v_artikel, true, l.sorte, 'DEMO') on conflict (artikel_id, artikel) do nothing;
          insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, journal, auftragsnr,
                                     kunde, artikel_id, artikel, einheit, menge, gewicht_je_artikel, batch_menge,
                                     kg_position, kg_charge, gebindeart, gebinde_menge, gebinde_inhalt, batch_gebinde, produzent,
                                     erloes)
          values ('DEMO', v_pos, l.nr::text, 1, 'demo-' || v_pos, v_lief_datum, 'Lieferschein', 'LS-' || (100000 + v_pos),
                  v_kunde, v_artikel_id, v_artikel, v_einheit, v_menge, v_gja, v_menge,
                  v_lief, v_lief, 'IFCO', v_teil, v_inhalt, v_teil, 'Demo-Hof',
                  round(v_lief * (1.55 + 0.5 * v_zufall), 2))
          on conflict (quelle, pos_id, charge_extern, lauf_nr) do nothing;
          insert into lieferung (datum, charge_nr, sorte, kg, kisten, gebindeart, ziel, kunde, bemerkung)
          values (v_lief_datum, l.nr, l.sorte, v_lief, v_teil, 'G2', 'verkauf', v_kunde, 'DEMO')
          returning id into v_lief_id;
          insert into lieferung_import (lieferung_id, quelle, extern_id)
          values (v_lief_id, 'DEMO', format('DEMO:%s:%s:1', v_pos, l.nr));
          v_rest := v_rest - v_teil;
        end loop;
      end loop;
    end loop;
    -- Zu klein geht an die Tiere — als Lieferung mit Ziel Tierfutter, damit die
    -- Bilanz es sieht.
    insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
    select (a.start_ts + interval '3 days')::date, a.charge_nr, c.sorte, sum(m.kg), 'tierfutter', 'Hof Zürcher (Tiere)', 'DEMO'
      from ausschuss_messung m join auftrag a on a.id = m.auftrag_id join charge c on c.nr = a.charge_nr
     where a.bemerkung = 'DEMO' and m.art = 'zu_klein'
     group by a.id, a.start_ts, a.charge_nr, c.sorte;
    -- Und der Hofladen nimmt ab und zu ein paar Kisten
    insert into lieferung (datum, sorte, kisten, ziel, kunde, bemerkung)
    select (v_anker + 40 + i * 11)::date, case when i % 2 = 0 then 'Tiana' else 'Kaori Kuri' end, 6 + i % 5, 'hofladen', 'Hofladen', 'DEMO'
      from generate_series(1, 10) i;
    perform lieferung_import_zeilen_verbinden('DEMO');
    raise notice 'Demo: Fax und Lieferungen angelegt (mit Verkaufsdatei)';
  end;

  -- ---------- 4b. An jeder Station läuft nur eine Arbeit zugleich -----------
  -- Die Arbeiten sind je Charge entstanden; zwei Chargen können so am selben
  -- Tag zur selben Stunde stehen. Im Betrieb geht das nicht (ein Band, ein
  -- Palox je Station) — also rücken sie hintereinander, samt allem, was an
  -- ihnen hängt. Fax hat keinen Palox und läuft nebenher.
  declare v record; v_prev timestamptz; v_station text := ''; v_delta interval;
  begin
    for v in
      select id, palox_station(station)::text as station, start_ts, ende_ts from auftrag
       where bemerkung = 'DEMO' and not ist_fax and status = 'abgeschlossen' and abgebrochen_ts is null
       order by palox_station(station), start_ts, id
    loop
      if v.station <> v_station then v_station := v.station; v_prev := null; end if;
      if v_prev is not null and v.start_ts < v_prev + interval '20 minutes' then
        v_delta := (v_prev + interval '20 minutes') - v.start_ts;
        update auftrag set start_ts = start_ts + v_delta, ende_ts = ende_ts + v_delta where id = v.id;
        update auftrag_palette set ts = ts + v_delta where auftrag_id = v.id;
        update schimmel_messung set ts = ts + v_delta where auftrag_id = v.id;
        update ausschuss_messung set ts = ts + v_delta where auftrag_id = v.id;
        update ausgang_wiegung set ts = ts + v_delta where auftrag_id = v.id;
        update verdunstung_wiegung set wiege_ts = wiege_ts + v_delta where auftrag_id = v.id;
        update sortier_lauf set datei_zeit = datei_zeit + v_delta where auftrag_id = v.id;
        v.ende_ts := v.ende_ts + v_delta;
      end if;
      v_prev := v.ende_ts;
    end loop;
  end;

  -- ---------- 5. Palox-Ablesungen je Arbeit (AB-02) -------------------------
  -- Je Station läuft der Stand über die Arbeiten weiter: eine Ablesung zu
  -- Beginn (Stand unverändert) und eine am Ende. Geleert, wenn er sonst
  -- überliefe. Gespeichert wird der Stand, die Menge folgt daraus. Fax hat
  -- keinen Palox — dort ist das Faule gewogen.
  declare v record; v_stand numeric := 0; v_station text := ''; v_geleert boolean; v_i int := 0;
  begin
    for v in
      select s.id, s.auftrag_id, s.kg, palox_station(a.station)::text as station, a.start_ts, a.ende_ts
        from schimmel_messung s
        join auftrag a on a.id = s.auftrag_id
       where a.bemerkung = 'DEMO' and not a.ist_fax and s.palox_stand_kg is null and s.brutto_kg is null
       order by palox_station(a.station), a.start_ts, s.id
    loop
      v_i := v_i + 1;
      if v.station <> v_station then v_station := v.station; v_stand := palox_tara_kg(); end if;
      -- Zwischen zwei Arbeiten geleert, weil der Palox sonst überliefe. Das
      -- ist der Normalfall, und er kostet seit 0073 keine Messung mehr: die
      -- neue Arbeit beginnt einfach bei der leeren Box und liest ihren
      -- eigenen Anfang ab.
      if v_stand + v.kg > 800 then v_stand := palox_tara_kg(); end if;
      -- Jede 17. Arbeit hat die Ablesung zu Beginn vergessen — die Datenqualität zeigt es.
      if v_i % 17 <> 0 then
        insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert, ts)
        values (v.auftrag_id, 0, v_stand, false, v.start_ts + interval '10 minutes');
      end if;
      -- Jede 23. Arbeit wird MITTENDRIN geleert. Der Betrieb sagt, das kommt
      -- vor. Dann ist die Menge dieser Arbeit unbekannt — nicht null: wie
      -- viel beim Leeren herausging, weiss niemand (0073).
      v_geleert := v_i % 23 = 0;
      if v_geleert
        then v_stand := palox_tara_kg() + round(v.kg * 0.4);
        else v_stand := v_stand + v.kg;
      end if;
      update schimmel_messung
         set palox_stand_kg = v_stand, palox_geleert = v_geleert, ts = coalesce(v.ende_ts, v.start_ts + interval '5 hours') - interval '10 minutes'
       where id = v.id;
      if v_geleert then
        update auftrag set palox_unbekannt = true where id = v.auftrag_id;
      end if;
    end loop;
    raise notice 'Demo: Palox-Ablesungen nachgetragen';
  end;

  -- ---------- 6. Lagerkontrollen --------------------------------------------
  -- Gegriffene Paletten, wie sie der Bildschirm „Palette kontrollieren"
  -- erfasst: Eingangsdatum, Gewicht damals und jetzt, Kisten, Kistenart.
  -- Seit 0061 ohne „davon faul" und ohne Auswahlart — die Kontrolle ist eine
  -- Verdunstungsmessung, nichts weiter.
  declare p record; v_i int := 0; v_tag date; v_tage int; v_zufall numeric; d record;
  begin
    for p in select * from demo_pal where not verarbeitet
              order by (hashtext(format('kontrolle-%s-%s', nr, datum))::bigint & 2147483647), id loop
      v_i := v_i + 1;
      exit when v_i > 24;
      select * into d from demo_charge where nr = p.nr;
      v_zufall := (hashtext('kontr-' || v_i)::bigint & 2147483647)::numeric / 2147483647;
      v_tag := greatest(p.datum + 20, v_anker + 40 + v_i * 6);
      exit when v_tag >= current_date;
      v_tage := v_tag - p.datum;
      -- Wie die Palette gegriffen wurde, entscheidet, ob die Messung für die
      -- Selektionsprüfung taugt: zufällig erreichbar ist die ehrliche Vorgabe,
      -- Mitte-unten ist besser, gezielt („die sieht schlecht aus") ist für den
      -- Vergleich untauglich — und genau das soll die Demo zeigen.
      insert into verdunstung_wiegung (charge_nr, palette_id, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                       kisten, gebindeart, auswahl, faul_kg, wiege_ts, bemerkung)
      values (p.nr, p.id, p.datum, p.netto + p.kisten * 1.5 + 25,
              round((p.netto * power(1 - d.r * (0.8 + 0.4 * v_zufall), v_tage) + p.kisten * 1.5 + 25) * 2) / 2.0,
              p.kisten, 'G2',
              case v_i % 5 when 0 then 'gezielt' when 1 then 'mitte_unten' else 'erreichbar_zufaellig' end,
              case when v_i % 3 <> 0 then round(p.netto * (0.003 + 0.03 * v_zufall), 1) end,
              v_tag::timestamptz + interval '10 hours', 'DEMO-KONTROLLE');
    end loop;
    raise notice 'Demo: Lagerkontrollen angelegt';
  end;

  -- ---------- 6b. Kontrollpaletten: dieselbe Palette immer wieder ----------
  -- Die Lagerkontrolle (Bildschirm „Palette kontrollieren") lebt davon, dass
  -- eine gekennzeichnete Palette über Wochen immer wieder auf dieselbe Waage
  -- kommt. Zwei Wägungen derselben Palette ergeben eine Verdunstungsrate je
  -- Tag, ohne jede Annahme — der sauberste Wert, den der Betrieb hat.
  -- Ohne diesen Abschnitt blieb der ganze Bildschirm in der Demo leer.
  declare pk record; v_kp bigint; v_i int := 0; v_tag date; v_netto numeric;
          v_schimmel boolean; v_zufall numeric; v_j int; v_rate numeric;
  begin
    for pk in
      select dp.id, dp.nr, dp.datum, dp.netto, dp.kisten, dc.r, dc.sorte
        from demo_pal dp join demo_charge dc on dc.nr = dp.nr
       where not dp.verarbeitet
       order by dc.sorte, (hashtext(format('kp-%s-%s', dp.nr, dp.datum))::bigint & 2147483647)
    loop
      -- Je Sorte eine Kontrollpalette, höchstens zwölf.
      continue when exists (select 1 from kontrollpalette k join charge c on c.nr = k.charge_nr
                             where c.sorte = pk.sorte and k.bemerkung = 'DEMO');
      v_i := v_i + 1;
      exit when v_i > 12;
      v_tag := pk.datum + 14 + (pk.nr % 7);
      -- Zu spät angelegt lohnt sich nicht — aber das ist der Grund, diese
      -- Palette zu überspringen, nicht der Grund, aufzuhören.
      if v_tag >= current_date - 30 then v_i := v_i - 1; continue; end if;
      insert into kontrollpalette (charge_nr, palette_id, kennzeichen, standort, angelegt_ts, angelegt_von,
                                   eingangsdatum, brutto_eingang_kg, bemerkung)
      values (pk.nr, pk.id, format('K-%s-%s', pk.nr, chr(64 + v_i)),
              format('Halle %s, Reihe %s', 1 + v_i % 2, 1 + v_i % 6),
              v_tag::timestamptz + interval '9 hours', v_wer,
              pk.datum, round((pk.netto + pk.kisten * 1.5 + 25) * 2) / 2.0, 'DEMO')
      returning id into v_kp;
      -- Alle zwei bis drei Wochen gewogen, bis heute. Die Palette wird
      -- leichter, nie schwerer — und bei einer sieht man am Ende Schimmel,
      -- dann taugt das Paar nicht mehr für die Rate.
      v_j := 0;
      loop
        v_j := v_j + 1;
        v_tag := v_tag + 14 + ((hashtext(format('kpw-%s-%s-%s', pk.nr, pk.datum, v_j))::bigint & 7))::int;
        exit when v_tag >= current_date or v_j > 12;
        v_zufall := (hashtext(format('kpz-%s-%s-%s', pk.nr, pk.datum, v_j))::bigint & 2147483647)::numeric / 2147483647;
        v_netto := pk.netto * power(1 - pk.r * (0.85 + 0.3 * v_zufall), (v_tag - pk.datum));
        v_schimmel := v_i = 3 and v_tag > current_date - 45;
        insert into kontrollpalette_wiegung (kontrollpalette_id, brutto_kg, kisten, gebindeart,
                                             sichtbar_schimmel, erfasser, wiege_ts, ts, bemerkung)
        values (v_kp, round((v_netto + pk.kisten * 1.5 + 25) * 2) / 2.0, pk.kisten, 'G2',
                v_schimmel, v_wer, v_tag::timestamptz + interval '10 hours',
                v_tag::timestamptz + interval '10 hours',
                case when v_schimmel then 'Erste faule Stellen sichtbar'
                     when v_j = 1 then 'Erste Wägung nach dem Einlagern' end);
      end loop;
      -- Eine Kontrollpalette ist inzwischen verarbeitet — sie wird beendet,
      -- statt einfach zu verschwinden.
      if v_i = 5 then
        update kontrollpalette set beendet_ts = (current_date - 12)::timestamptz + interval '11 hours',
               beendet_grund = 'Palette verarbeitet'
         where id = v_kp;
      end if;
    end loop;
    raise notice 'Demo: Kontrollpaletten angelegt (% Stück, % Wägungen)',
      (select count(*) from kontrollpalette where bemerkung = 'DEMO'),
      (select count(*) from kontrollpalette_wiegung);
  end;

  -- ---------- 6c. Die Verkaufsdatei als Datei ------------------------------
  -- Die Zeilen der Warenwirtschaft kommen im Betrieb nicht einzeln, sondern
  -- als Excel-Datei: einmal im Monat hochgeladen, mit Prüfsumme und Zeitraum.
  -- Ohne diesen Abschnitt stand der Warenausgang-Import der Demo ohne eine
  -- einzige Datei da — als wäre die Ware aus dem Nichts gekommen.
  declare m record; v_datei bigint; v_n int;
  begin
    for m in
      select date_trunc('month', datum)::date as monat, min(datum) as von, max(datum) as bis,
             count(*)::int as n
        from ausgang_zeile where quelle = 'DEMO' group by 1 order by 1
    loop
      insert into ausgang_datei (quelle, dateiname, pruefsumme, n_zeilen, n_kuerbis, n_neu,
                                 n_geaendert, n_unveraendert, von_datum, bis_datum, bemerkung,
                                 hochgeladen_von, ts)
      values ('DEMO', format('Lieferungen_%s.xlsx', to_char(m.monat, 'YYYY-MM')),
              format('demo-datei-%s', to_char(m.monat, 'YYYYMM')),
              m.n + 4, m.n, m.n - (case when m.monat = (select min(date_trunc('month', datum)::date)
                                            from ausgang_zeile where quelle = 'DEMO') then 2 else 0 end),
              case when m.monat = (select min(date_trunc('month', datum)::date)
                                     from ausgang_zeile where quelle = 'DEMO') then 2 else 0 end,
              4, m.von, m.bis, 'DEMO', v_wer,
              (m.bis + 2)::timestamptz + interval '8 hours')
      returning id into v_datei;
      update ausgang_zeile set datei_id = v_datei
       where quelle = 'DEMO' and date_trunc('month', datum)::date = m.monat;
      -- Der erste Monat wurde ein zweites Mal hochgeladen, weil zwei Positionen
      -- in der Warenwirtschaft nachträglich korrigiert worden waren. Die Datei
      -- zählt sie als geändert, und die Zeilen tragen ihre Änderungszeit.
      if v_datei is not null and m.monat = (select min(date_trunc('month', datum)::date)
                                              from ausgang_zeile where quelle = 'DEMO') then
        update ausgang_zeile set geaendert_ts = (m.bis + 9)::timestamptz + interval '8 hours'
         where id in (select id from ausgang_zeile where datei_id = v_datei order by pos_id limit 2);
      end if;
    end loop;
    -- Zwei Abweichungen, wie sie wirklich vorkommen: einmal wurde eine
    -- Lieferung von Hand nachkorrigiert, einmal blieb eine Palette am Rampen-
    -- rand stehen. Der Abgleich „Datei gegen Lieferung" soll in der Demo nicht
    -- leer sein — sonst sieht niemand, dass es ihn gibt.
    -- Sortiert nach Datum, Charge und Menge, nicht nach der laufenden Nummer:
    -- die Nummer ist nach einem Neuaufbau eine andere, das Datum nicht.
    update lieferung set kg = round(kg * 0.94, 1)
     where id in (select l.id from lieferung l join lieferung_import i on i.lieferung_id = l.id
                   where l.bemerkung = 'DEMO' and l.kg > 400
                   order by l.datum, l.charge_nr, l.kg limit 1);
    update lieferung set kg = round(kg * 1.07, 1)
     where id in (select l.id from lieferung l join lieferung_import i on i.lieferung_id = l.id
                   where l.bemerkung = 'DEMO' and l.kg > 400
                   order by l.datum desc, l.charge_nr desc, l.kg desc limit 1);
    raise notice 'Demo: Verkaufsdateien angelegt (%)', (select count(*) from ausgang_datei where bemerkung = 'DEMO');
  end;

  -- ---------- 6d. Ernte abgeschlossen --------------------------------------
  -- Solange die Ernte einer Charge läuft, wandert ihr mittleres Eingangsdatum
  -- mit jeder Palette, und jede Altersangabe trägt den Zusatz „Ernte läuft
  -- noch". Für die früh geernteten Chargen hat der Betrieb längst gesagt, dass
  -- nichts mehr kommt — die späten stehen noch offen. Beides soll man sehen.
  update charge set ernte_abgeschlossen_ts = (
           select max(p.eingangsdatum) + 3 from palette p where p.charge_nr = charge.nr)::timestamptz + interval '18 hours'
   where nr in (select nr from demo_charge where kw <= 37)
     and ernte_abgeschlossen_ts is null
     and exists (select 1 from palette p where p.charge_nr = charge.nr and p.extern_id like 'demo-%');

  -- ---------- 7. Sonderfälle, wie sie in jeder Saison vorkommen -------------
  declare v_auftrag bigint; v_datum date; v_id bigint;
  begin
    -- (1) Eine abgebrochene Arbeit: falsche Charge gewählt
    insert into auftrag (weg, station, charge_nr, start_ts, bemerkung)
    values ('hand', 'waschen_sortieren', 1611, (v_anker + 63)::timestamptz + interval '9 hours', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, datum from demo_pal where nr = 1611 order by id limit 3;
    perform auftrag_abbrechen(v_auftrag, 'Falsche Charge gewählt');

    -- (2) Ein Zahlendreher beim Palox: 4500 statt 450 kg — die Rechnung lässt
    --     ihn aus, die Auffälligkeiten melden ihn ganz oben.
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung)
    values ('hand', 'waschen_sortieren', 1611, (v_anker + 70)::timestamptz + interval '8 hours',
            (v_anker + 70)::timestamptz + interval '15 hours', 'abgeschlossen', 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, datum from demo_pal where nr = 1611 and not verarbeitet order by datum limit 6;
    update demo_pal set verarbeitet = true where id in (select id from demo_pal where nr = 1611 and not verarbeitet order by datum limit 6);
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 4500, 4545, (v_anker + 70)::timestamptz + interval '14 hours');
    insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

    -- (3) Ein Zetteldatum, das zu keiner Palette passt (12 und 21 vertauscht)
    select datum into v_datum from demo_pal where nr = 1613 order by datum limit 1;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select a.id, v_datum + 9 from auftrag a where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
     order by a.start_ts limit 1;

    -- (4) Ein Waschgang ohne gezählte Kisten: die Messung hat keinen Nenner
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, bemerkung)
    values ('maschine', 'waschen', 1614, (v_anker + 95)::timestamptz + interval '8 hours',
            (v_anker + 95)::timestamptz + interval '11 hours', 'abgeschlossen', 1, 'DEMO')
    returning id into v_auftrag;
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 9, 300, (v_anker + 95)::timestamptz + interval '10 hours');

    -- (5) Eine Sortier-CSV, die keiner Arbeit zugeordnet ist (Warteschlange)
    perform csv_lauf_speichern(1619, 'DEMO-1619-ohne-arbeit', 'demo/sortierdateien/1619-ohne-arbeit.csv',
      'demo-pruefsumme-warteschlange',
      (v_anker + 130)::timestamptz + interval '13 hours', 'dateiname',
      '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
      420, 1, 3, 6,
      '[[800,40],[900,90],[1000,120],[1100,100],[1200,50],[1300,10]]'::jsonb);

    -- (6) Drei laufende Arbeiten von heute — damit die Masken nicht leer sind
    insert into auftrag (weg, station, charge_nr, start_ts, status, kaeufer, sortierschema_id, bemerkung,
                         kistensystem, soll_kg_pro_kiste)
    values ('hand', 'waschen_sortieren', 1631, now() - interval '2 hours', 'offen', 'nordmarkt',
            sortierschema_fuer('Mieluna', null, current_date, 'kiste'), 'DEMO', 'kiste_ab', 8)
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg)
    select v_auftrag, dp.datum, (select pl.brutto_kg from palette pl where pl.id = dp.id)
      from demo_pal dp where dp.nr = 1631 and not dp.verarbeitet order by dp.datum desc limit 3;
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 0, 45, now() - interval '110 minutes');

    insert into auftrag (weg, station, charge_nr, start_ts, status, kaliber_idx, bemerkung)
    select 'maschine', 'waschen', l.nr, now() - interval '90 minutes', 'offen', 0, 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' and l.kisten[1] > 0 order by l.start_ts desc limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      update auftrag set kistensystem = 'stueck', stueck_je_kiste = 6 where id = v_auftrag;
      insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl, sortierdatum) values (v_auftrag, 0, 6, current_date - 21);
    end if;

    insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, status, kaeufer, bemerkung)
    select 'maschine', 'waschen', l.nr, true, now() - interval '50 minutes', 'offen', 'talhof', 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' order by l.start_ts limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      update auftrag set kistensystem = 'stueck', stueck_je_kiste = 6 where id = v_auftrag;
      insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, ts)
      values (v_auftrag, 0, 8.5, 1, 'G2', now() - interval '20 minutes');
    end if;

    -- (7) Ein Palox, der zwischendurch geleert wurde, ohne dass jemand abgelesen
    --     hat: der Stand fällt von 410 auf 130. Die Menge dieser Arbeit ist
    --     unbekannt (0060) — die Auswertung sagt es, der Arbeiter wird nicht gefragt.
    insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, bemerkung, kistensystem, soll_kg_pro_kiste)
    values ('hand', 'waschen_sortieren', 1613, (v_anker + 118)::timestamptz + interval '8 hours',
            (v_anker + 118)::timestamptz + interval '14 hours', 'abgeschlossen', 'DEMO', 'kiste_ab', 8)
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg)
    select v_auftrag, dp.datum, (select pl.brutto_kg from palette pl where pl.id = dp.id)
      from demo_pal dp where dp.nr = 1613 and not dp.verarbeitet order by dp.datum limit 4;
    update demo_pal set verarbeitet = true where id in (select id from demo_pal where nr = 1613 and not verarbeitet order by datum limit 4);
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts)
    values (v_auftrag, 0, 410, (v_anker + 118)::timestamptz + interval '8 hours 10 minutes'),
           (v_auftrag, 0, 130, (v_anker + 118)::timestamptz + interval '13 hours 50 minutes');
    insert into auftrag_angabe (auftrag_id, schluessel, wert) values (v_auftrag, 'eine_charge', 'true');

    raise notice 'Demo: Sonderfälle und laufende Arbeiten angelegt';
  end;

  -- ---------- 8. Beteiligte an den laufenden Arbeiten ------------------------
  insert into auftrag_teilnehmer (auftrag_id, profil_id)
  select a.id, v_wer from auftrag a where a.bemerkung = 'DEMO' and a.status = 'offen'
  on conflict do nothing;

  -- ---------- 9. Rückmeldungen aus der Halle (0091, neu in 0093) ------------
  -- Geschrieben, nicht gesprochen: Eine Aufnahme wäre eine Datei im Bucket,
  -- und die kann eine SQL-Funktion nicht anlegen. Jede Rückmeldung steht kurz
  -- nach dem Ende der Arbeit bei einer Person, die daran beteiligt war — die
  -- Arbeit aus Sonderfall 7 hat keine Beteiligten, dort ist es der
  -- Betriebsleiter selbst. Und sie steht an Arbeiten, an denen man sie im
  -- Dashboard auch findet.
  declare v_a1 bigint; v_a2 bigint; v_a3 bigint;
  begin
    -- (1) Zur Ware, an der Sortier-Arbeit mit dem meisten Faulen: der Grund
    --     steht dann am Punkt der Faul-Kurve unter Ursachen.
    select a.id into v_a1
      from auftrag a join schimmel_messung s on s.auftrag_id = a.id
     where a.bemerkung = 'DEMO' and a.status = 'abgeschlossen' and a.station = 'sortieren'
     order by s.kg desc, a.id limit 1;
    -- (2) Zur Ware, an der Arbeit mit dem falschen Zetteldatum (Sonderfall 3):
    --     die Auffälligkeit zeigt den Kommentar mit an.
    select a.id into v_a2 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
     order by a.start_ts limit 1;
    -- (3) Zur Ware und (4) zur App, an der Arbeit, deren Palox zwischendurch
    --     geleert wurde (Sonderfall 7): beide Arten an einer Arbeit, wie es
    --     das Arbeitsfenster und Betrieb → Arbeiten zeigen.
    select a.id into v_a3 from auftrag a
     where a.bemerkung = 'DEMO' and a.charge_nr = 1613 and a.station = 'waschen_sortieren'
       and exists (select 1 from schimmel_messung s where s.auftrag_id = a.id and s.palox_stand_kg = 410)
     order by a.start_ts limit 1;
    if v_a1 is null or v_a2 is null or v_a3 is null then
      raise exception 'Demo: die Arbeiten für die Rückmeldungen fehlen — die Saison oben hat sich geändert.';
    end if;
    insert into auftrag_rueckmeldung (auftrag_id, art, text, erfasser, ts)
    select r.auftrag_id, r.art, r.text,
           coalesce((select t.profil_id from auftrag_teilnehmer t
                      where t.auftrag_id = r.auftrag_id order by t.profil_id limit 1), v_wer),
           coalesce(a.ende_ts, a.start_ts) + make_interval(mins => 3 * r.nr)
      from (values
              (1, v_a1, 'ware', 'Hagelschaden: viele Kürbisse mit Dellen und Rissen, darum so viel Faules.'),
              (2, v_a2, 'ware', 'Der Zettel war nass, das Datum kaum zu lesen.'),
              (3, v_a3, 'ware', 'Sehr viel Faules, der Palox war randvoll — wir haben ihn zwischendurch geleert.'),
              (4, v_a3, 'app',  'Wo trage ich ein, dass der Palox geleert wurde? Ich habe es nicht gefunden.')
           ) as r(nr, auftrag_id, art, text)
      join auftrag a on a.id = r.auftrag_id
     order by r.nr;
    raise notice 'Demo: Rückmeldungen aus der Halle angelegt';
  end;

  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;

  -- Die Auswertung wird hier absichtlich nicht neu gerechnet: Supabase gibt
  -- einem API-Aufruf acht Sekunden, und das Rechnen ist der teuerste Teil.
  -- Die App ruft auswertung_aktualisieren() gleich danach als eigenen
  -- Aufruf; demo_daten.sql tut dasselbe. Bis dahin steht die Auswertung als
  -- veraltet da — die Auslöser an den Tabellen haben das schon vermerkt.
  return (
    select format('Demo-Saison steht: %s Paletten in %s Chargen, %s Arbeiten (davon %s Fax), %s Sortierläufe, '
                  || '%s Lieferungen, %s Kontrollpaletten mit %s Wägungen, %s Verkaufsdateien, %s Rückmeldungen. '
                  || 'Eingang %s t. Jetzt in der App unter Lagermanagement anschauen.',
                  (select count(*) from palette where extern_id like 'demo-%'),
                  (select count(distinct charge_nr) from palette where extern_id like 'demo-%'),
                  (select count(*) from auftrag where bemerkung = 'DEMO'),
                  (select count(*) from auftrag where bemerkung = 'DEMO' and ist_fax),
                  (select count(*) from sortier_lauf where datei_name like 'DEMO-%'),
                  (select count(*) from lieferung where bemerkung = 'DEMO'),
                  (select count(*) from kontrollpalette where bemerkung = 'DEMO'),
                  (select count(*) from kontrollpalette_wiegung),
                  (select count(*) from ausgang_datei where bemerkung = 'DEMO'),
                  (select count(*) from auftrag_rueckmeldung r join auftrag a on a.id = r.auftrag_id where a.bemerkung = 'DEMO'),
                  (select round(sum(eingang_netto_kg) / 1000, 1) from v_charge_rueckgrat))
  );
end $fn$;


comment on function demo_daten_laden is
  'Legt die erfundene Demo-Saison an (Arbeiten mit bemerkung = ''DEMO'', Paletten mit extern_id ''demo-…'', Sortierdateien ''DEMO-…'', Lieferungen und Verkaufsdateien ''DEMO'', Kontrollpaletten mit bemerkung ''DEMO''). Echte Daten bleiben unberührt; im Echtmodus lässt sie sich gar nicht laden (0072). Seit 0093 mit den Rückmeldungen aus der Halle. Deterministisch: zweimal laden gibt zweimal dieselbe Saison (0081).';
revoke execute on function demo_daten_laden() from public;
grant execute on function demo_daten_laden() to authenticated;

-- ---------------------------------------------------------------------
-- Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 93 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
