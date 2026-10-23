-- =====================================================================
-- 0122 — Wer im Perigon wie heisst; der Weg der Ware je Charge
--
-- (a) Die Liste vom 23. Oktober: 1719 = 199156, 1763 = 199158; berichtigt
--     am selben Tag: 198976 ist 1649, 198977 ist 1650.
-- (b) Ein Name, zwei Schreibweisen: Inauen und „Oettli, Inauen" sind
--     Oettli, Trüb (auch als u + Trema) ist Trüeb, Trüeb ist Trüeb; ein
--     unbekannter Name ist niemand.
-- (c) Die Halle ändert schlag_alias nicht, der Betriebsleiter schon.
-- (d) Ein Lieferschein mit einer Nummer an keiner Charge bekommt seine
--     Charge über den Produzenten, wenn Schlag und Artikel genau eine
--     zeigen; die Nummer der Liste (199156) über Stufe 1; Mix, ein
--     unbekannter Produzent und ein Rest bleiben ohne. Der Grund steht in
--     lieferung_nachordnung, der Hinweis in v_ungereimtheit.
-- (e) Gelernt wird ein Name nur, wenn er bei Chargen eines einzigen
--     Schlags vorkommt; hat der Schlag zwei Chargen mit dem Artikel, wird
--     nichts zugeordnet.
-- (f) v_charge_spur: herein laut Journal, wie die App jetzt zählt,
--     umgebucht weg und her, Lieferscheine, davon nachgeordnet.
-- (g) Kandidaten: genau die Chargen nach der Regel, in der Reihenfolge.
-- (i) Das Chargenregister selbst: eine Perigon-Nummer an zwei Chargen (mit
--     den verwandten Nummern der Dateien: nah daneben oder vom selben
--     Produzenten), eine Charge mit Ware ohne Perigon-Nummer, ein Schlag
--     unter zwei Namen — und nichts davon, wo alles stimmt (1649/1650 seit
--     der berichtigten Liste).
-- (h) Stand 122.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false; v_gerechnet boolean := false;
  v_u uuid := '00000000-0122-0000-0000-000000000001';
  v_w uuid := '00000000-0122-0000-0000-000000000002';
  v_quelle text; v_x record; v_z bigint; v_l bigint; v_p bigint; v_s int; v_txt text; v_fehler text;
  v_ist jsonb; v_soll jsonb; v_n int := 0;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0122"}');
  update profil set rolle = 'admin' where id = v_u;
  insert into auth.users (id, email, raw_user_meta_data) values (v_w, null, '{"name":"Prüf-0122 Halle"}');
  update profil set rolle = 'arbeiter' where id = v_w;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from sortier_lauf) then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  if not exists (select 1 from erg_charge) then
    update auswertung_stand set rechnet_seit = null where id = 1;
    for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
    v_gerechnet := true;
  end if;

  -- (a) die Liste
  assert (select perigon_nr from charge where nr = 1719) = 199156,
    format('0122 (a1): 1719 trägt die Perigon-Nr. %s statt 199156', (select perigon_nr from charge where nr = 1719));
  assert (select perigon_nr from charge where nr = 1763) = 199158,
    format('0122 (a2): 1763 trägt die Perigon-Nr. %s statt 199158', (select perigon_nr from charge where nr = 1763));
  -- Die erste Fassung der Liste nannte 198976 zweimal; der Betrieb hat sie berichtigt.
  -- Der Test folgt der Liste: vorher „bleibt an beiden", jetzt 1649 = 198976, 1650 = 198977.
  assert (select perigon_nr from charge where nr = 1649) = 198976 and (select perigon_nr from charge where nr = 1650) = 198977,
    format('0122 (a3): 1649/1650 tragen %s/%s statt 198976/198977 (Liste vom 23. Oktober, berichtigt)',
           (select perigon_nr from charge where nr = 1649), (select perigon_nr from charge where nr = 1650));

  -- (b) Namen
  assert schlag_von_produzent('Inauen') = 'Oettli', format('0122 (b1): Inauen ist %s', schlag_von_produzent('Inauen'));
  assert schlag_von_produzent('Oettli, Inauen') = 'Oettli', '0122 (b2): „Oettli, Inauen" ist nicht Oettli';
  assert schlag_von_produzent('  inauen ') = 'Oettli', '0122 (b3): klein und mit Leerzeichen ist Inauen nicht Oettli';
  assert schlag_von_produzent('Trüb') = 'Trüeb', format('0122 (b4): Trüb ist %s', schlag_von_produzent('Trüb'));
  assert schlag_von_produzent(U&'Tru\0308b') = 'Trüeb', '0122 (b5): Trüb mit u + Trema ist nicht Trüeb';
  assert schlag_von_produzent('Trüeb') = 'Trüeb', '0122 (b6): Trüeb ist nicht mehr Trüeb';
  assert schlag_von_produzent('Niemand AG') is null, '0122 (b7): ein unbekannter Name bekommt einen Schlag';

  -- (c) wer schlag_alias ändern darf
  perform set_config('request.jwt.claim.sub', v_w::text, true);
  set local role authenticated;
  begin
    insert into schlag_alias (alias, schlag) values ('Halle 0122', 'Oettli');
    v_fehler := 'durfte';
  exception when insufficient_privilege then v_fehler := 'verweigert';
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  assert v_fehler = 'verweigert', '0122 (c1): die Halle durfte einen Namen verknüpfen';
  set local role authenticated;
  insert into schlag_alias (alias, schlag) values ('Leiter 0122', 'Oettli');
  reset role;
  assert schlag_von_produzent('Leiter 0122') = 'Oettli', '0122 (c2): der Betriebsleiter konnte keinen Namen verknüpfen';
  delete from schlag_alias where alias = 'Leiter 0122';
  -- (c3) ein Name ist nicht sein eigener zweiter Name, und leer ist kein Name —
  -- auch nach erneutem Einspielen von setup.sql (die Bedingungen hängen an name_norm())
  begin
    insert into schlag_alias (alias, schlag) values ('OETTLI', 'Oettli');
    v_fehler := 'angenommen';
  exception when check_violation then v_fehler := 'abgewiesen';
  end;
  assert v_fehler = 'abgewiesen', '0122 (c3): „OETTLI" als zweiter Name von Oettli wurde angenommen';
  begin
    insert into schlag_alias (alias, schlag) values (' … ', 'Oettli');
    v_fehler := 'angenommen';
  exception when check_violation then v_fehler := 'abgewiesen';
  end;
  assert v_fehler = 'abgewiesen', '0122 (c3): ein Name nur aus Satzzeichen wurde angenommen';

  -- (d) Zuordnung über den Produzenten
  -- 99221 und 99222 teilen sich eine Perigon-Nummer wie 1649 und 1650 (für (i))
  insert into charge (nr, schlag, sorte, saison, perigon_nr) values
    (99221, 'Prüf-0122', 'Tiana', 2026, 991220), (99222, 'Prüf-0122', 'Butterkin', 2026, 991220), (99224, 'Prüf-0122 b', 'Butterkin', 2026, null);
  select code into v_quelle from ausgang_quelle order by code limit 1;
  for v_x in select * from (values
      (1, '99222',  'Bio Kürbis Muscat/Butterkin Dem gross', 'Prüfhof Süd', 99222, false),
      (2, '991221', 'Bio Kürbis Butternut lose',             'Prüfhof Süd', null,  false),
      (3, '991222', 'Bio Kürbis Mix OS',                     'Prüfhof Süd', null,  false),
      (4, '991223', 'Bio Kürbis Butternut lose',             'Niemand AG',  null,  false),
      (5, '991224', 'Bio Kürbis oranger Knirps lose',        'Inauen',      null,  false),
      (6, '199156', 'Bio Kürbis oranger Knirps lose',        'Inauen',      null,  false),
      (7, '991225', 'Bio Kürbis Butternut lose',             'Prüfhof Süd', null,  true),
      (8, '99222',  'Bio Kürbis Muscat/Butterkin Dem gross', 'Zweihof',     99222, false),
      (9, '99224',  'Bio Kürbis Muscat/Butterkin Dem gross', 'Zweihof',     99224, false)) t(n, nummer, artikel, produzent, charge, rest)
  loop
    insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_charge, produzent)
    values (v_quelle, 9912200 + v_x.n, v_x.nummer, 1, format('pruef-0122-%s', v_x.n), date '2026-10-10', 'P0122', v_x.artikel, 100, v_x.produzent)
    returning id into v_z;
    insert into lieferung (datum, charge_nr, sorte, kg, ziel)
    values (date '2026-10-10', v_x.charge, case when v_x.charge is null then 'Tiana' end, 100, 'verkauf') returning id into v_l;
    insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id)
    values (v_l, v_quelle, format('%s:%s:pruef-0122%s', v_quelle, 9912200 + v_x.n, case when v_x.rest then ':rest' else '' end), v_z);
  end loop;
  update auswertung_stand set rechnet_seit = null where id = 1;
  perform auswertung_schritt_intern(1, false);
  update auswertung_stand set rechnet_seit = null where id = 1;
  select string_agg(format('%s→%s', z.pos_id - 9912200, coalesce(l.charge_nr::text, '–')), ', ' order by z.pos_id)
    into v_fehler
    from lieferung_import li join lieferung l on l.id = li.lieferung_id join ausgang_zeile z on z.id = li.zeile_id
   where z.fingerabdruck like 'pruef-0122-%';
  assert v_fehler = '1→99222, 2→99221, 3→–, 4→–, 5→1719, 6→1719, 7→–, 8→99222, 9→99224',
    format('0122 (d1): zugeordnet wurde %s (erwartet 1→99222, 2→99221, 3→–, 4→–, 5→1719, 6→1719, 7→–, 8→99222, 9→99224)', v_fehler);
  select n.weg || ' | ' || n.grund into v_txt
    from lieferung_nachordnung n join lieferung_import li on li.lieferung_id = n.lieferung_id join ausgang_zeile z on z.id = li.zeile_id
   where z.fingerabdruck = 'pruef-0122-2';
  assert v_txt like 'produzent | %991221%Prüfhof Süd%Prüf-0122%Butternut%99221%',
    format('0122 (d2): der Grund der Zuordnung sagt nicht Nummer, Produzent, Schlag, Artikel und Charge: %s', v_txt);
  assert (select n.weg from lieferung_nachordnung n join lieferung_import li on li.lieferung_id = n.lieferung_id
           join ausgang_zeile z on z.id = li.zeile_id where z.fingerabdruck = 'pruef-0122-6') = 'nummer',
    '0122 (d3): die Nummer der Liste (199156) ging nicht über Stufe 1';
  assert exists (select 1 from v_ungereimtheit where art = 'nachgeordnet' and charge_nr = 99221 and n = 1
                    and mehr->>'produzent' = 'Prüfhof Süd' and mehr->'nummern' ? '991221'),
    '0122 (d4): die Zuordnung über den Produzenten steht nicht als Hinweis in v_ungereimtheit';
  assert exists (select 1 from v_perigon_produzent where produzent = 'prüfhof süd' and schlag = 'Prüf-0122' and quelle = 'gelernt'),
    '0122 (d5): der Name aus Spalte X einer Zeile mit bekannter Nummer wurde nicht gelernt';
  -- (d6) trägt der Betriebsleiter die Nummer bei der Charge ein, steht es fest — der Hinweis verschwindet
  update charge set perigon_nr = 991221 where nr = 99221;
  assert not exists (select 1 from v_ungereimtheit where art = 'nachgeordnet' and charge_nr = 99221),
    '0122 (d6): die Nummer steht bei der Charge, der Hinweis „über den Produzenten zugeordnet" bleibt trotzdem';
  update charge set perigon_nr = 991220 where nr = 99221;
  assert exists (select 1 from v_ungereimtheit where art = 'nachgeordnet' and charge_nr = 99221),
    '0122 (d6): ohne die Nummer bei der Charge fehlt der Hinweis';

  -- (e) eindeutig oder gar nicht
  assert not exists (select 1 from v_perigon_produzent where produzent = 'zweihof'),
    '0122 (e1): ein Name, der bei zwei Schlägen vorkommt, wurde einem zugeordnet';
  insert into charge (nr, schlag, sorte, saison) values (99223, 'Prüf-0122', 'Mieluna', 2026);
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_charge, produzent)
  values (v_quelle, 9912210, '991226', 1, 'pruef-0122-10', date '2026-10-10', 'P0122', 'Bio Kürbis Butternut lose', 100, 'Prüfhof Süd')
  returning id into v_z;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (date '2026-10-10', null, 'Tiana', 100, 'verkauf') returning id into v_l;
  insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, v_quelle, format('%s:9912210:pruef-0122', v_quelle), v_z);
  perform auswertung_schritt_intern(1, false);
  update auswertung_stand set rechnet_seit = null where id = 1;
  assert (select charge_nr from lieferung where id = v_l) is null,
    '0122 (e2): bei zwei Butternut-Chargen desselben Schlags wurde trotzdem eine gewählt';
  assert (select l.charge_nr from lieferung l join lieferung_import li on li.lieferung_id = l.id join ausgang_zeile z on z.id = li.zeile_id
           where z.fingerabdruck = 'pruef-0122-2') = 99221,
    '0122 (e3): eine schon gemachte Zuordnung ging verloren';

  -- (f) der Weg der Ware
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id, quelle) values
    (99222, date '2026-10-01', 420, 32, 'G2', 'pruef-0122-p1', 'journal-import'),
    (99222, date '2026-10-01', 410, 32, 'G2', 'pruef-0122-p2', 'journal-import');
  select id into v_p from palette where extern_id = 'pruef-0122-p1';
  insert into palette_zuordnung (palette_id, von_charge_nr, nach_charge_nr, art, stand, grund, geaendert_ts, geaendert_von)
  values (v_p, 99222, 99221, 'zettel', 'angewandt', 'Prüfung 0122', now(), v_u);
  perform set_config('kuerbis.zuordnung', 'an', true);
  update palette set charge_nr = charge_nr where id = v_p;
  perform set_config('kuerbis.zuordnung', '', true);
  select to_jsonb(s) into v_ist from v_charge_spur s where charge_nr = 99222;
  assert (v_ist->>'journal_paletten')::int = 2 and (v_ist->>'paletten')::int = 1
     and v_ist->'weg'->0->>'charge_nr' = '99221' and v_ist->'weg'->0->>'stand' = 'angewandt' and (v_ist->'weg'->0->>'paletten')::int = 1,
    format('0122 (f1): der Weg von 99222 stimmt nicht: %s', v_ist);
  select to_jsonb(s) into v_ist from v_charge_spur s where charge_nr = 99221;
  assert (v_ist->>'journal_paletten')::int = 0 and (v_ist->>'paletten')::int = 1
     and v_ist->'her'->0->>'charge_nr' = '99222' and (v_ist->>'lieferscheine')::int = 1
     and v_ist->'nachgeordnet'->0->>'weg' = 'produzent' and (v_ist->'nachgeordnet'->0->>'n')::int = 1,
    format('0122 (f2): der Weg nach 99221 stimmt nicht: %s', v_ist);

  -- (g) Kandidaten: genau die Regel, in ihrer Reihenfolge, für jede Charge mit Eingang
  -- Als Grenze der eigene erste Eingang: so fallen spätere Chargen heraus, und die Datumsregel wird geprüft.
  for v_x in select b.charge_nr, b.eingang_von as bis from erg_charge b where b.eingang_kg > 0 loop
    v_ist := coalesce((select jsonb_agg((k->>'charge_nr')::int order by o) from jsonb_array_elements(ungereimt_kandidaten(v_x.charge_nr, v_x.bis)) with ordinality t(k, o)), '[]'::jsonb);
    select coalesce(jsonb_agg(q.nr order by q.rang), '[]'::jsonb) into v_soll from (
      select x.charge_nr as nr, row_number() over (order by (x.schlag = c.schlag) desc, (x.sorte = c.sorte) desc, x.n_rest_paletten desc, x.charge_nr) as rang
        from charge c join sorte_kaliber sk on sk.sorte = c.sorte, erg_charge x join sorte_kaliber sx on sx.sorte = x.sorte
       where c.nr = v_x.charge_nr and x.charge_nr <> c.nr and sx.artikelgruppe = sk.artikelgruppe
         and x.n_rest_paletten >= 1 and x.eingang_kg > 0 and coalesce(x.geliefert_kg, 0) <= 0.5 * x.eingang_kg
         and x.eingang_von <= v_x.bis) q where q.rang <= 4;
    assert v_ist = v_soll, format('0122 (g1): Kandidaten für %s sind %s, nach der Regel %s', v_x.charge_nr, v_ist, v_soll);
    v_n := v_n + jsonb_array_length(v_ist);
  end loop;
  assert v_n > 0, '0122 (g2): bei keiner Charge gab es einen Kandidaten — die Prüfung prüft nichts';

  -- (i) das Chargenregister
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_charge, produzent)
  values (v_quelle, 9912211, '991219', 1, 'pruef-0122-11', date '2026-10-10', 'P0122', 'Bio Kürbis Butternut lose', 100, 'Fremdhof');
  insert into charge (nr, schlag, sorte, saison) values (99225, 'Trüb', 'Amoro', 2026);
  select mehr into v_ist from v_stammdaten_pruefung where pruefung = 'perigon_doppelt' and schluessel = '991220';
  assert v_ist is not null and v_ist->'chargen' @> '[{"charge_nr": 99221}, {"charge_nr": 99222}]'::jsonb
     and (v_ist->>'zeilen_mit_nummer')::int = 0,
    format('0122 (i1): die Perigon-Nummer an 99221 und 99222 fällt nicht auf: %s', v_ist);
  select jsonb_agg(v->>'nummer' order by v->>'nummer') into v_soll from jsonb_array_elements(v_ist->'verwandte') v;
  assert v_soll = '["991219", "991221", "991222", "991225", "991226"]'::jsonb,
    format('0122 (i2): verwandte Nummern sind %s — erwartet die nah daneben (991219, 991221, 991222) und die vom selben Produzenten (991225, 991226)', v_soll);
  assert exists (select 1 from v_ungereimtheit where art = 'stammdaten' and mehr->>'pruefung' = 'perigon_doppelt'
                    and mehr->'chargen_nr' @> '[99221, 99222]'::jsonb),
    '0122 (i3): die doppelte Perigon-Nummer steht nicht unter den Ungereimtheiten';
  -- (i4) Bis zur berichtigten Liste stand hier: 198976 an 1649 und 1650 fällt auf.
  -- Seither trägt 1650 die 198977 — und dort fällt nichts mehr auf.
  assert not exists (select 1 from v_stammdaten_pruefung where pruefung = 'perigon_doppelt' and chargen && array[1649, 1650]),
    '0122 (i4): an 1649 oder 1650 steht nach der berichtigten Liste noch eine doppelte Perigon-Nummer';
  assert exists (select 1 from v_stammdaten_pruefung where pruefung = 'ohne_perigon_nr' and chargen = array[99224]),
    '0122 (i5): eine Charge mit Lieferscheinen, aber ohne Perigon-Nummer fällt nicht auf';
  assert not exists (select 1 from v_stammdaten_pruefung where pruefung = 'ohne_perigon_nr' and chargen && array[99221, 99222, 99223]),
    '0122 (i6): eine Charge mit Perigon-Nummer oder ohne Ware steht als „ohne Perigon-Nummer" da';
  assert exists (select 1 from v_stammdaten_pruefung where pruefung = 'schlag_zweimal' and chargen = array[99225] and mehr->>'gemeint' = 'Trüeb'),
    '0122 (i7): der Schlag „Trüb" neben „Trüeb" fällt nicht auf';
  assert not exists (select 1 from v_stammdaten_pruefung where pruefung = 'schlag_zweimal' and chargen && array[99221, 99222, 99224]),
    '0122 (i8): ein Schlag mit einem einzigen Namen steht als zweimal da';

  -- aufräumen
  delete from palette_zuordnung where palette_id in (select id from palette where extern_id like 'pruef-0122-%');
  delete from palette where extern_id like 'pruef-0122-%';
  delete from lieferung where id in (select li.lieferung_id from lieferung_import li join ausgang_zeile z on z.id = li.zeile_id where z.fingerabdruck like 'pruef-0122-%');
  delete from ausgang_zeile where fingerabdruck like 'pruef-0122-%';
  delete from charge where nr in (99221, 99222, 99223, 99224, 99225);
  update auswertung_stand set rechnet_seit = null where id = 1;
  perform auswertung_schritt_intern(1, false);
  if v_gerechnet then
    for v_s in 2..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  end if;
  update auswertung_stand set rechnet_seit = null where id = 1;
  if v_geladen then perform demo_daten_entfernen(); end if;

  -- (h) Stand
  assert schema_stand() >= 122, format('0122 (h1): schema_stand() = %s', schema_stand());

  delete from profil where id in (v_u, v_w); delete from auth.users where id in (v_u, v_w);
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0122 — Inauen ist Oettli, Trüb ist Trüeb; die Liste vom 23. Oktober steht; ein Lieferschein mit unbekannter Nummer bekommt seine Charge über Produzent und Artikel, wenn das eindeutig ist, mit Grund; gelernt wird nur Eindeutiges; der Weg der Ware je Charge; Kandidaten nach der Regel; das Chargenregister wird geprüft';
end $$;

select '——— 0122 Wer im Perigon wie heisst ———' as ergebnis;
