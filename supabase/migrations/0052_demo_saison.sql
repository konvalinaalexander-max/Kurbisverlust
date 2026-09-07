-- =====================================================================
-- 0052 — Die Demo-Saison, neu: so, wie die Daten wirklich kommen
--
-- Die alte Demo (0034) war eine Rechenübung: zehn Chargen, zwei Läufe je
-- Charge, ein Histogramm aus acht Gewichtsstufen, Waschen als eingetippte
-- Menge, Fax als Waschgang. Sie zeigte nicht, was das System seit 0041 bis
-- 0051 erfasst — und einiges davon falsch (die Gewichtsverteilung hatte acht
-- Balken, „liegt seit" eine Zahl).
--
-- Diese Saison ist ein Praxistest: Sie entsteht so, wie der Betrieb arbeitet.
--
--   * Die Chargen sind die der Planungsdatei 2026 (37 mit erwartetem Ertrag),
--     die Mengen auf die Hälfte verkleinert, damit der Knopf in wenigen
--     Sekunden fertig ist. Ernte je Charge in ihrer Erntewoche, an Werktagen,
--     über Tage bis Wochen verteilt — je grösser, desto länger.
--   * Eine Palette sind 30–34 G2-Kisten à 10.8–12.4 kg (Planung: „32 G2",
--     Sorte macht den Unterschied), brutto mit Kisten- und Palettentara.
--   * Kein FIFO: Ein Sortierlauf nimmt Paletten von dem Eingangstag, an den
--     man herankommt — abwechselnd vom jüngsten und vom ältesten Stapel.
--     Manche Chargen sind ganz verarbeitet, manche zur Hälfte, manche liegen
--     noch komplett.
--   * Weg 1 für Hokkaido, Mandarin, Butterkin, Kabocha: Sortieren an der
--     Maschine (CSV mit 150 Gewichtsstufen, Kisten je Kaliber gezählt, zwei
--     Palox-Ablesungen), Wochen später Waschen je Kaliber (geleerte Kisten
--     gezählt, Palox, fertige Palette), dann Fax je Bestellung (Kisten je
--     Kaliber, Faules kistenweise gewogen), dann Lieferungen an den Käufer.
--   * Weg 2 für Butternut: Waschen + Sortieren von Hand, als „Kiste ab 8 kg"
--     für Coop und Rathgeb, nach Kaliber für Migros — mit gewogener Palette
--     (Verdunstung), gewogenem Ausschuss (einer geschätzt), fertiger Palette
--     (überfüllt), dann Fax und Lieferung.
--   * Der Verderb folgt einer Weibull-Kurve je Sorte plus Sockel; die
--     Verdunstung einer Sortenrate mit Streuung je Palette; das Faule beim
--     Fax einem Anteil je Sorte.
--   * Lieferungen gehen über Wochen, verschränkt über Chargen — die eine wird
--     in sechs Teilen geliefert, die andere in zwei.
--   * Lagerkontrollen (zufällig erreichbar, Mitte-unten, gezielt), ein
--     Vorlauf, und die Sonderfälle, die es in jeder Saison gibt: eine
--     abgebrochene Arbeit, ein Zahlendreher, eine Arbeit ohne Ablesung, ein
--     Waschgang ohne gezählte Kisten, eine CSV in der Warteschlange, ein
--     Zetteldatum, das zu keiner Palette passt — und drei laufende Arbeiten
--     von heute (Waschen + Sortieren, Waschen, Fax), damit die Masken etwas
--     zu zeigen haben.
--
-- Alles ist deterministisch (kein random()): Zweimal laden gibt zweimal
-- dieselbe Saison. Die Demo spielt relativ zu heute (Ernte vor rund 200
-- Tagen), damit sie nicht altert; die Kalenderdaten sind deshalb verschoben.
-- =====================================================================

-- Die Demo legt vier Käufer an (Coop, Migros, Rathgeb, Bio Partner). Beim
-- Entfernen dürfen nur die wieder verschwinden, die sie selbst angelegt hat:
-- Wer „coop" schon vor der Demo im Stammdatenregister hatte, behält ihn.
-- Dieselbe Markierung wie überall sonst — DEMO in einer Bemerkung.
alter table kaeufer add column if not exists bemerkung text;
comment on column kaeufer.bemerkung is
  'Freitext zum Käufer. ''DEMO'' markiert die von der Demo-Saison angelegten '
  'Käufer, damit demo_daten_entfernen() nur diese wieder löscht.';

create or replace function demo_daten_laden()
returns text language plpgsql security definer set search_path = public as $fn$
declare
  v_anker date := current_date - 200;
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
    ('coop', 'Coop', 'DEMO'), ('migros', 'Migros', 'DEMO'),
    ('rathgeb', 'Rathgeb', 'DEMO'), ('biopartner', 'Bio Partner', 'DEMO')
  on conflict (code) do nothing;
  -- Coop nimmt Butternut in der 8-kg-Kiste; Migros will Kaori Kuri enger.
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'coop', v_anker + 20, 'kiste', 8, 'DEMO — Coop nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'coop' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
  select 'Tiana', 'rathgeb', v_anker + 25, 'kiste', 8, 'DEMO — Rathgeb nimmt Tiana in der 8-kg-Kiste'
   where not exists (select 1 from sortierschema where sorte = 'Tiana' and kaeufer = 'rathgeb' and art = 'kiste');
  insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab, bemerkung)
  select 'Kaori Kuri', 'migros', v_anker + 60, 'kaliber', 600, '[[600,1000],[1000,1400],[1400,2000]]'::jsonb, 2000,
         'DEMO — Migros will Kaori Kuri in engeren Bändern (beim Eröffnen einer Arbeit geändert)'
   where not exists (select 1 from sortierschema where sorte = 'Kaori Kuri' and kaeufer = 'migros' and art = 'kaliber');
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
  insert into demo_charge (nr, kg, kw, anteil_verarbeitet) values
    (1598,  1600, 36, 1.00), (1601,  1300, 38, 0.00), (1607,  1400, 34, 1.00),
    (1605,   900, 34, 1.00), (1606,   600, 34, 1.00), (1611, 40000, 37, 0.55),
    (1613, 23000, 35, 0.85), (1612, 15000, 35, 0.70), (1614,  3600, 34, 1.00),
    (1615,  3400, 34, 1.00), (1616,  9000, 34, 0.80), (1617,  2600, 35, 1.00),
    (1618,  3800, 34, 1.00), (1619,  1700, 34, 1.00), (1620,  2300, 35, 0.60),
    (1646,  7600, 34, 0.75), (1647,  7500, 39, 0.30), (1623,  8700, 36, 0.65),
    (1624,  8400, 35, 0.80), (1625,  2800, 34, 1.00), (1626,  4300, 39, 0.00),
    (1627,  2600, 39, 0.50), (1648, 10200, 34, 0.90), (1628,  6900, 36, 0.60),
    (1649, 22000, 38, 0.45), (1650,  2200, 39, 0.00), (1651,  3100, 35, 1.00),
    (1630, 10300, 34, 0.95), (1631, 15000, 39, 0.20), (1633, 24000, 38, 0.40),
    (1634,  6200, 36, 0.70), (1635,  6200, 36, 0.85), (1636, 18000, 36, 0.60),
    (1637,  5000, 36, 0.70), (1638,  5000, 36, 0.35), (1632, 37000, 37, 0.50);
  update demo_charge d set sorte = c.sorte from charge c where c.nr = d.nr;
  -- Butternut von Hand, alles andere über die Maschine. Sorteneigenschaften
  -- so, wie sie im Betrieb beobachtet werden: Hokkaido verdunstet schneller,
  -- Butternut hält länger, Mandarin ist klein.
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
    kaeufer = case nr % 4 when 0 then 'coop' when 1 then 'migros' when 2 then 'rathgeb' else 'biopartner' end;
  -- Demeter-Ware geht an Coop und Migros, Knospe an Rathgeb und Bio Partner —
  -- so steht es in der Verkaufsplanung.
  update demo_charge d set kaeufer = case when d.nr % 2 = 0 then 'coop' else 'migros' end
    from charge c where c.nr = d.nr and c.schlag in ('Illnau Bruno', 'Illnau Gross', 'Negi Thalheim', 'Slowgrow Uster',
                                                     'Gossau Eberhard', 'Bonomo', 'Daniel Böhler', 'Klaus Böhler', 'Andi Ball');

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
        exit when v_start > now() - interval '2 days';

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

        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung)
        values (case when d.weg = 'maschine' then 'maschine' else 'hand' end::verarbeitungsweg,
                case when d.weg = 'maschine' then 'sortieren' else 'waschen_sortieren' end::station,
                d.nr, v_start,
                v_start + make_interval(mins => (240 + v_n * 14 + floor(v_zufall * 40)::int)),
                'abgeschlossen', v_kaeufer, v_schema, 'DEMO')
        returning id into v_auftrag;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_auftrag, id from profil order by erstellt_ts limit (2 + (v_lauf % 2))
        on conflict do nothing;

        -- Paletten zählen — mit dem Datum vom Zettel
        insert into auftrag_palette (auftrag_id, eingangsdatum, ts)
        select v_auftrag, datum, v_start + make_interval(mins => (10 + row_number() over (order by id) * 12)::int)
          from demo_pal where id = any(v_pal_ids);

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
            null, format('demo-pruefsumme-%s', v_auftrag),
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
          on conflict (auftrag_id, kaliber_idx) do nothing;
          insert into demo_lauf values (v_auftrag, d.nr, d.sorte, v_start, v_x, v_tage, 'kaliber', v_kaeufer, v_baender, d.kg_kiste, v_kisten);
        else
          -- ---- Von Hand: eine Palette gewogen, Ausschuss gewogen, fertige Palette ----
          select p2.* into p from demo_pal p2 where p2.id = v_pal_ids[1];
          v_wiegung := null;
          v_brutto := p.netto + p.kisten * 1.5 + 25;
          insert into verdunstung_wiegung (auftrag_id, charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg,
                                           kisten, gebindeart, kuerbisse_pro_kiste, wiege_ts)
          values (v_auftrag, d.nr, p.datum, v_brutto,
                  round((p.netto * power(1 - d.r * (0.7 + 0.6 * v_zufall), v_start::date - p.datum) + p.kisten * 1.5 + 25) * 2) / 2.0,
                  p.kisten, 'G2', 4 + (d.nr % 3), v_start + interval '2 hours')
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
          insert into ausschuss_messung (auftrag_id, art, brutto_kg, kisten, gebindeart, ts)
          values (v_auftrag, 'zu_klein', v_klein + v_kisten_p * 1.5 + 25, v_kisten_p, 'G2', v_start + interval '6 hours');
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
  begin
    for l in select * from demo_lauf where art = 'kaliber' and exists (select 1 from auftrag a where a.id = demo_lauf.auftrag_id and a.station = 'sortieren') order by start_ts loop
      v_gewaschen := array[]::int[];
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_zufall := (hashtext(format('wasch-%s-%s', l.auftrag_id, v_i))::bigint & 2147483647)::numeric / 2147483647;
        -- Das letzte Band der späten Läufe wartet noch
        if l.kisten[v_i] = 0 or (v_i = array_length(l.kisten, 1) and l.start_ts > now() - interval '60 days') then
          v_gewaschen := v_gewaschen || 0; continue;
        end if;
        v_start := l.start_ts + make_interval(days => 6 + v_i * 5 + floor(v_zufall * 25)::int) + interval '1 hour';
        while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
        if v_start > now() - interval '1 day' then v_gewaschen := v_gewaschen || 0; continue; end if;
        v_kisten := l.kisten[v_i];
        insert into auftrag (weg, station, charge_nr, start_ts, ende_ts, status, kaliber_idx, sortierschema_id, bemerkung)
        values ('maschine', 'waschen', l.nr, v_start,
                v_start + make_interval(mins => 90 + v_kisten * 5 + floor(v_zufall * 30)::int),
                'abgeschlossen', v_i - 1, (select sortierschema_id from auftrag where id = l.auftrag_id), 'DEMO')
        returning id into v_neu;
        insert into auftrag_teilnehmer (auftrag_id, profil_id)
        select v_neu, id from profil order by erstellt_ts limit 2 on conflict do nothing;
        insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl) values (v_neu, v_i - 1, v_kisten);
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
        values (v_neu, 'eine_charge', 'true'), (v_neu, 'sortierdatum', l.start_ts::date::text);
        -- Fertige Palette nach Kaliber: kein Soll, nur das Kistengewicht
        insert into ausgang_wiegung (auftrag_id, charge_nr, brutto_kg, kisten, gebindeart, ts)
        values (v_neu, l.nr, round((32 * l.kg_je_kiste * (0.96 + 0.08 * v_zufall) + 32 * 1.5 + 25) * 2) / 2.0, 32, 'G2',
                v_start + interval '2 hours');
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
  begin
    for l in select * from demo_lauf order by start_ts loop
      for v_i in 1 .. coalesce(array_length(l.kisten, 1), 0) loop
        v_rest := l.kisten[v_i];
        if v_rest <= 0 then continue; end if;
        v_j := 0;
        while v_rest > 0 loop
          v_j := v_j + 1;
          exit when v_j > 4;
          v_zufall := (hashtext(format('fax-%s-%s-%s', l.auftrag_id, v_i, v_j))::bigint & 2147483647)::numeric / 2147483647;
          -- Ein Teil der Ware wartet noch auf eine Bestellung
          if v_zufall < 0.12 then exit; end if;
          v_teil := least(v_rest, 32 * (1 + floor(v_zufall * 4)::int) + floor(v_zufall * 20)::int);
          v_start := l.start_ts + make_interval(days => 20 + v_i * 6 + v_j * 9 + floor(v_zufall * 12)::int) + interval '2 hours';
          while extract(isodow from v_start) >= 6 loop v_start := v_start + interval '1 day'; end loop;
          exit when v_start > now() - interval '1 day';
          v_kaeufer := case when v_j % 3 = 0 then (case l.kaeufer when 'coop' then 'migros' when 'migros' then 'coop' when 'rathgeb' then 'biopartner' else 'rathgeb' end) else l.kaeufer end;
          v_schema := case when l.art = 'kiste' then sortierschema_fuer(l.sorte, l.kaeufer, v_start::date, 'kiste') else null end;
          insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, ende_ts, status, kaeufer, sortierschema_id, bemerkung)
          values ('maschine', 'waschen', l.nr, true, v_start,
                  v_start + make_interval(mins => 40 + v_teil * 2 + floor(v_zufall * 25)::int),
                  'abgeschlossen', v_kaeufer, v_schema, 'DEMO')
          returning id into v_neu;
          insert into auftrag_teilnehmer (auftrag_id, profil_id)
          select v_neu, id from profil order by erstellt_ts limit 1 on conflict do nothing;
          insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl)
          values (v_neu, case when l.art = 'kiste' then -1 else v_i - 1 end, v_teil);
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
          -- Die Lieferung: alles, was das Fax gemacht hat, minus das Faule —
          -- in Kilo, wie auf dem Lieferschein; 1–7 Tage später.
          v_lief := round(v_masse - v_faul, 1);
          v_kunde := case v_kaeufer when 'coop' then 'Coop Verteilzentrale' when 'migros' then 'Migros Ostschweiz'
                                    when 'rathgeb' then 'Rathgeb Bio' else 'Bio Partner Schweiz' end;
          insert into lieferung (datum, charge_nr, sorte, kg, kisten, gebindeart, ziel, kunde, bemerkung)
          values ((v_start + make_interval(days => 1 + floor(v_zufall * 6)::int))::date, l.nr, l.sorte,
                  v_lief, v_teil, 'G2', 'verkauf', v_kunde, 'DEMO');
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
    raise notice 'Demo: Fax und Lieferungen angelegt';
  end;

  -- ---------- 4b. An jeder Station läuft nur eine Arbeit zugleich -----------
  -- Die Arbeiten sind je Charge entstanden; zwei Chargen können so am selben
  -- Tag zur selben Stunde stehen. Im Betrieb geht das nicht (ein Band, ein
  -- Palox je Station) — also rücken sie hintereinander, samt allem, was an
  -- ihnen hängt. Fax hat keinen Palox und läuft nebenher.
  declare v record; v_prev timestamptz; v_station text := ''; v_delta interval;
  begin
    for v in
      select id, station::text as station, start_ts, ende_ts from auftrag
       where bemerkung = 'DEMO' and not ist_fax and status = 'abgeschlossen' and abgebrochen_ts is null
       order by station, start_ts, id
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
      select s.id, s.auftrag_id, s.kg, a.station::text as station, a.start_ts, a.ende_ts
        from schimmel_messung s
        join auftrag a on a.id = s.auftrag_id
       where a.bemerkung = 'DEMO' and not a.ist_fax and s.palox_stand_kg is null and s.brutto_kg is null
       order by a.station, a.start_ts, s.id
    loop
      v_i := v_i + 1;
      if v.station <> v_station then v_station := v.station; v_stand := palox_tara_kg(); end if;
      -- Jede 17. Arbeit hat die Ablesung zu Beginn vergessen — die Datenqualität zeigt es.
      if v_i % 17 <> 0 then
        insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, palox_geleert, ts)
        values (v.auftrag_id, 0, v_stand, false, v.start_ts + interval '10 minutes');
      end if;
      v_geleert := v_stand + v.kg > 800;
      if v_geleert then v_stand := palox_tara_kg(); end if;
      v_stand := v_stand + v.kg;
      update schimmel_messung
         set palox_stand_kg = v_stand, palox_geleert = v_geleert, ts = coalesce(v.ende_ts, v.start_ts + interval '5 hours') - interval '10 minutes'
       where id = v.id;
    end loop;
    raise notice 'Demo: Palox-Ablesungen nachgetragen';
  end;

  -- ---------- 6. Lagerkontrollen --------------------------------------------
  -- Zufällig gegriffene Paletten, wie sie der Bildschirm „Palette
  -- kontrollieren" erfasst: mit „davon faul" und der Art der Auswahl.
  declare p record; v_i int := 0; v_tag date; v_tage int; v_faul numeric; v_zufall numeric; d record;
  begin
    for p in select * from demo_pal where not verarbeitet order by (hashtext('kontrolle-' || id)::bigint & 2147483647) loop
      v_i := v_i + 1;
      exit when v_i > 24;
      select * into d from demo_charge where nr = p.nr;
      v_zufall := (hashtext('kontr-' || v_i)::bigint & 2147483647)::numeric / 2147483647;
      v_tag := greatest(p.datum + 20, v_anker + 40 + v_i * 6);
      exit when v_tag >= current_date;
      v_tage := v_tag - p.datum;
      v_faul := case when v_i % 3 = 0 then 0
                     else round(p.netto * power(1 - d.r, v_tage) * (d.sockel + 1 - exp(-power(v_tage / d.lambda, d.k))) * (0.7 + 0.6 * v_zufall), 1) end;
      insert into verdunstung_wiegung (charge_nr, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart,
                                       wiege_ts, faul_kg, sichtbar_schimmel, auswahl, bemerkung)
      values (p.nr, p.datum, p.netto + p.kisten * 1.5 + 25,
              round((p.netto * power(1 - d.r * (0.8 + 0.4 * v_zufall), v_tage) + p.kisten * 1.5 + 25) * 2) / 2.0,
              p.kisten, 'G2', v_tag::timestamptz + interval '10 hours', v_faul, v_faul > 0,
              case v_i % 4 when 0 then 'gezielt' when 1 then 'mitte_unten' else 'erreichbar_zufaellig' end,
              'DEMO-KONTROLLE');
    end loop;
    raise notice 'Demo: Lagerkontrollen angelegt';
  end;

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
    perform csv_lauf_speichern(1619, 'DEMO-1619-ohne-arbeit', null, 'demo-pruefsumme-warteschlange',
      (v_anker + 130)::timestamptz + interval '13 hours', 'dateiname',
      '{"overflow_ab":60000,"min_gramm":100,"dubletten_zusammenfassen":true}'::jsonb,
      420, 1, 3, 6,
      '[[800,40],[900,90],[1000,120],[1100,100],[1200,50],[1300,10]]'::jsonb);

    -- (6) Drei laufende Arbeiten von heute — damit die Masken nicht leer sind
    insert into auftrag (weg, station, charge_nr, start_ts, status, kaeufer, sortierschema_id, bemerkung)
    values ('hand', 'waschen_sortieren', 1631, now() - interval '2 hours', 'offen', 'coop',
            sortierschema_fuer('Mieluna', null, current_date, 'kiste'), 'DEMO')
    returning id into v_auftrag;
    insert into auftrag_palette (auftrag_id, eingangsdatum)
    select v_auftrag, datum from demo_pal where nr = 1631 and not verarbeitet order by datum desc limit 3;
    insert into schimmel_messung (auftrag_id, kg, palox_stand_kg, ts) values (v_auftrag, 0, 45, now() - interval '110 minutes');

    insert into auftrag (weg, station, charge_nr, start_ts, status, kaliber_idx, bemerkung)
    select 'maschine', 'waschen', l.nr, now() - interval '90 minutes', 'offen', 0, 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' and l.kisten[1] > 0 order by l.start_ts desc limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl) values (v_auftrag, 0, 6);
    end if;

    insert into auftrag (weg, station, charge_nr, ist_fax, start_ts, status, kaeufer, bemerkung)
    select 'maschine', 'waschen', l.nr, true, now() - interval '50 minutes', 'offen', 'migros', 'DEMO'
      from demo_lauf l join auftrag a on a.id = l.auftrag_id
     where a.station = 'sortieren' order by l.start_ts limit 1
    returning id into v_auftrag;
    if v_auftrag is not null then
      insert into auftrag_gebinde (auftrag_id, kaliber_idx, anzahl) values (v_auftrag, 1, 42), (v_auftrag, 0, 10);
      insert into schimmel_messung (auftrag_id, kg, brutto_kg, kisten, gebindeart, ts)
      values (v_auftrag, 0, 8.5, 1, 'G2', now() - interval '20 minutes');
    end if;

    raise notice 'Demo: Sonderfälle und laufende Arbeiten angelegt';
  end;

  -- ---------- 8. Beteiligte an den laufenden Arbeiten ------------------------
  insert into auftrag_teilnehmer (auftrag_id, profil_id)
  select a.id, v_wer from auftrag a where a.bemerkung = 'DEMO' and a.status = 'offen'
  on conflict do nothing;

  drop table if exists demo_charge; drop table if exists demo_pal; drop table if exists demo_lauf;
  perform auswertung_aktualisieren();

  return (
    select format('Demo-Saison steht: %s Paletten in %s Chargen, %s Arbeiten (davon %s Fax), %s Sortierläufe, %s Lieferungen. '
                  || 'Eingang %s t. Jetzt in der App unter Überblick anschauen.',
                  (select count(*) from palette where extern_id like 'demo-%'),
                  (select count(distinct charge_nr) from palette where extern_id like 'demo-%'),
                  (select count(*) from auftrag where bemerkung = 'DEMO'),
                  (select count(*) from auftrag where bemerkung = 'DEMO' and ist_fax),
                  (select count(*) from sortier_lauf where datei_name like 'DEMO-%'),
                  (select count(*) from lieferung where bemerkung = 'DEMO'),
                  (select round(sum(eingang_netto_kg) / 1000, 1) from v_charge_rueckgrat))
  );
end $fn$;

comment on function demo_daten_laden is
  'Legt die erfundene Demo-Saison an (Aufträge mit bemerkung = ''DEMO'', Paletten mit extern_id ''demo-…'', Sortierdateien ''DEMO-…'', Lieferungen ''DEMO''). Echte Daten bleiben unberührt. Deterministisch.';
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
  delete from charge_vorlauf where bemerkung like 'DEMO%';
  delete from palette where extern_id like 'demo-%';
  delete from sortierschema where bemerkung like 'DEMO%';
  -- Nur die von der Demo angelegten Käufer, und auch die nur, wenn nichts
  -- mehr an ihnen hängt. Ein Käufer, den der Betrieb selbst eingetragen hat,
  -- bleibt — auch wenn er zufällig denselben Code trägt.
  delete from kaeufer k where k.bemerkung = 'DEMO'
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
