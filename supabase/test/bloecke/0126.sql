-- =====================================================================
-- 0126 — Ein Reiter für Perigon: jeder Fall nachvollziehbar und mitverfolgt
--
-- (a) Ein gebauter Fall je Art auf einer eigenen Prüf-Firma: Chargen
--     genannt und Spalte S = 0 (mit Masse, und ohne Menge in Q), dieselbe
--     Zeile dreimal (zu viel), Rest, keine Nummer, Stück ohne Gewicht,
--     Rücknahme, Lieferungen ≠ Datei, Artikelname gegen Preisgruppe,
--     unbekannte, inzwischen bekannte und mehrdeutige Nummer, Artikel gegen
--     Sorte, Demeter verkauft / Knospe geliefert, Mix, vor dem Eingang — je
--     mit Schlüssel, Kilo (nie 0 statt unbekannt), Satz, Was tun, Wo,
--     Schwere; eine richtige Position (am Tag des ersten Eingangs) steht nicht
--     da; jeder Schlüssel einmal; keine Position trägt eine Art, die nicht zu
--     ihr gehört.
-- (b) Der Stand je Firma: Zeilen, Positionen, ohne ganze Zeile, offene Fälle.
-- (c) Das Protokoll: der Betriebsleiter hängt an; die Halle nicht; niemand
--     ändert oder löscht; kein Vermerk im Namen eines anderen; nur die vier
--     Stände.
-- (d) Der Verlauf: der letzte Vermerk zählt, mit Anzahl und Notiz.
-- (e) Das Merken: neu mit erst_gesehen, verschwunden mit weg_seit, wieder da
--     ohne weg_seit und mit dem ersten erst_gesehen; die Sachen je Charge
--     mit demselben Schlüssel wie in der App; was zu einer entfernten Firma
--     gehört, vergisst sie, ausser es hat einen Vermerk.
-- (f) Nach jedem fertigen Rechenlauf (berechnet_ts) merkt die App von
--     selbst; ein anderes Nachführen von auswertung_stand nicht.
-- (g) Rechte: lesen ja, Spur schreiben nein, ohne Anmeldung nichts.
-- (h) Stand 126.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false;
  v_u uuid := '00000000-0126-0000-0000-000000000001';
  v_w uuid := '00000000-0126-0000-0000-000000000002';
  q text := 'PRUEF126'; v_k int; v_sorte text; v_e date; v_tag date; v_x record; v_n int; v_ok boolean;
  v_l bigint; v_z bigint; v_erst timestamptz; v_zuletzt timestamptz; v_berechnet timestamptz;
  v_art text[];
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0126"}');
  update profil set rolle = 'admin' where id = v_u;
  insert into auth.users (id, email, raw_user_meta_data) values (v_w, null, '{"name":"Prüf-0126 Halle"}');
  update profil set rolle = 'arbeiter' where id = v_w;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  -- Eine Knirps-Charge mit Eingang braucht es (Artikel gegen Sorte, vor dem Eingang) — sonst die Demo.
  if not exists (select 1 from charge c join sorte_kaliber sk on sk.sorte = c.sorte
                  where sk.artikelgruppe = 'Knirps' and exists (select 1 from palette p where p.charge_nr = c.nr)) then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  select c.nr, c.sorte, (select min(p.eingangsdatum) from palette p where p.charge_nr = c.nr)
    into v_k, v_sorte, v_e
    from charge c join sorte_kaliber sk on sk.sorte = c.sorte
   where sk.artikelgruppe = 'Knirps' and exists (select 1 from palette p where p.charge_nr = c.nr)
   order by c.nr limit 1;
  assert v_k is not null and v_e is not null, '0126: keine Knirps-Charge mit Eingang zum Bauen der Fälle';
  v_tag := v_e + 5;
  insert into ausgang_quelle (code, name, dateiname_muster) values (q, 'Prüf-0126', q);
  insert into charge (nr, schlag, sorte, saison, perigon_nr) values
    (99261, 'Prüf-0126 A', v_sorte, 2026, 992613), (99262, 'Prüf-0126 B', v_sorte, 2026, 992613);

  -- (a) die Fälle — gebaut wie das Einlesen sie schreibt: je Chargenzeile mit Menge eine
  -- Lieferung (Firma:Position:Nummer:Lauf), der Rest einer Position eine ohne Charge (…:rest).
  create temp table t126 (pos bigint, nr text, lauf int, datum date, artikel text, preis text, label text,
                          menge numeric, einheit text, gewicht numeric, kg_pos numeric, s numeric, kg_s numeric,
                          lief_kg numeric, lief_charge int, rest_kg numeric) on commit drop;
  insert into t126 values
    -- a1 zwei Chargen genannt, Spalte S = 0; 600 kg ohne Charge
    (99260001, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 600, 'kg', 0, 600, 0, 0, null, null, 600),
    (99260001, '99261', 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 600, 'kg', 0, 600, 0, 0, null, null, null),
    -- a2 Charge genannt, Menge 0 in Q und S
    (99260002, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 0, 'kg', 0, 0, 0, 0, null, null, null),
    -- a3 dieselbe Zeile dreimal: 768 kg auf eine Position von 256 kg
    (99260003, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 256, 'kg', 0, 256, 256, 256, 256, v_k, null),
    (99260003, v_k::text, 2, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 256, 'kg', 0, 256, 256, 256, null, null, null),
    (99260003, v_k::text, 3, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 256, 'kg', 0, 256, 256, 256, null, null, null),
    -- a4 Spalte S 987 von 1002 kg
    (99260004, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 1002, 'kg', 0, 1002, 987, 987, 987, v_k, 15),
    -- a5 Spalte W leer
    (99260005, '', 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 8, 'kg', 0, 8, null, null, null, null, 8),
    -- a6 12 Stück ohne Gewicht je Artikel
    (99260006, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 12, 'Stk', 0, null, 12, null, null, null, null),
    -- a7 Rücknahme
    (99260007, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', -50, 'kg', 0, -50, -50, -50, null, null, null),
    -- a8 die Lieferung von Hand auf 80 kg geändert, die Datei sagt 100
    (99260008, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 100, 'kg', 0, 100, 100, 100, 80, v_k, null),
    -- a9 „Demeter" im Namen, Preisgruppe K
    (99260009, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Demeter', 'K', 'K', 40, 'kg', 0, 40, 40, 40, 40, v_k, null),
    -- a10 eine Nummer an keiner Charge
    (99260010, '991267', 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 110, 'kg', 0, 110, 110, 110, 110, null, null),
    -- a11 die eigene Nummer, beim Einlesen nicht aufgelöst
    (99260011, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 111, 'kg', 0, 111, 111, 111, 111, null, null),
    -- a12 eine Perigon-Nummer an zwei Chargen
    (99260012, '992613', 1, v_tag, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 112, 'kg', 0, 112, 112, 112, 112, null, null),
    -- a13 als Mandarin verkauft, geliefert aus einer Knirps-Charge
    (99260013, v_k::text, 1, v_tag, 'Bio Kürbis Mandarin Dem', 'D', 'D', 72, 'kg', 0, 72, 72, 72, 72, v_k, null),
    -- a14 Demeter-Preis, Lieferlabel Knospe
    (99260014, v_k::text, 1, v_tag, 'Bio Kürbis Kaori Kuri Dem', 'D', 'K', 40, 'kg', 0, 40, 40, 40, 40, v_k, null),
    -- a15 Kürbis Mix auf einer Charge
    (99260015, v_k::text, 1, v_tag, 'Bio Kürbis Mix', 'K', 'K', 288, 'kg', 0, 288, 288, 288, 288, v_k, null),
    -- a16 drei Tage vor dem ersten Eingang
    (99260016, v_k::text, 1, v_e - 3, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 176, 'kg', 0, 176, 176, 176, 176, v_k, null),
    -- a17 richtig: am Tag des ersten Eingangs, Menge und Charge stimmen, Label auch
    (99260017, v_k::text, 1, v_e, 'Bio Kürbis Kaori Kuri Knospe', 'K', 'K', 500, 'kg', 0, 500, 500, 500, 500, v_k, null);
  for v_x in select * from t126 order by pos, nr, lauf loop
    insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, kunde, artikel_id, artikel, einheit,
                               menge, gewicht_je_artikel, batch_menge, kg_position, kg_charge, preisgruppe, liefer_label)
    values (q, v_x.pos, v_x.nr, v_x.lauf, format('pruef-0126-%s-%s-%s', v_x.pos, v_x.nr, v_x.lauf), v_x.datum, 'Prüfkunde 0126',
            'P0126', v_x.artikel, v_x.einheit, v_x.menge, v_x.gewicht, v_x.s, v_x.kg_pos, v_x.kg_s, v_x.preis, v_x.label)
    returning id into v_z;
    if v_x.lief_kg is not null then
      insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung) values (v_x.datum, v_x.lief_charge, v_sorte, v_x.lief_kg, 'verkauf', 'Prüf-0126')
      returning id into v_l;
      insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, q, format('%s:%s:%s:%s', q, v_x.pos, v_x.nr, v_x.lauf), v_z);
    end if;
    if v_x.rest_kg is not null then
      insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung) values (v_x.datum, null, v_sorte, v_x.rest_kg, 'verkauf', 'ohne Chargenbezug')
      returning id into v_l;
      insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, q, format('%s:%s:rest', q, v_x.pos), v_z);
    end if;
  end loop;

  -- (a) prüfen
  select * into v_x from v_perigon_befund where schluessel = format('menge_null:%s:99260001', q);
  assert v_x.art = 'menge_null' and v_x.kg = 600 and v_x.schwere = 'rot' and v_x.wo = 'perigon'
     and v_x.satz like format('%%die Chargen %s, 99261%%', least(v_k::text, '99261')) and v_x.satz like '%Spalte S%' and v_x.satz like '%600 kg%'
     and v_x.nummern is not null and v_x.kg_position = 600 and v_x.kg_zugeteilt = 0 and v_x.sorte = v_sorte,
    format('0126 (a1): Chargen genannt, Spalte S = 0: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('menge_null:%s:99260002', q);
  assert v_x.kg is null and v_x.satz like '%keine Menge%Spalte Q und Spalte S%' and v_x.schwere = 'gelb',
    format('0126 (a2): eine Position ohne Menge (Q und S = 0) heisst nicht so oder hat 0 kg statt unbekannt: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('zu_viel:%s:99260003', q);
  assert v_x.kg = 512 and v_x.satz like '%768 kg%' and v_x.satz like '%256 kg%' and v_x.satz like format('%%Charge %s dreimal%%', v_k)
     and v_x.satz like '%höchstens die Position%',
    format('0126 (a3): dieselbe Zeile dreimal: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('rest:%s:99260004', q);
  assert v_x.kg = 15 and v_x.satz like '%nur 987 von 1002 kg%' and v_x.satz like '%15.0 kg bleiben ohne Charge%' and v_x.kg_ohne_charge = 15,
    format('0126 (a4): der Rest: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('keine_nummer:%s:99260005', q);
  assert v_x.kg = 8 and v_x.satz like '%Spalte W%' and v_x.charge_nr is null and v_x.sorte = v_sorte,
    format('0126 (a5): Spalte W leer: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('ohne_gewicht:%s:99260006', q);
  assert v_x.kg is null and v_x.satz like '%12 Stk ohne Gewicht%unbekannt%',
    format('0126 (a6): Stück ohne Gewicht — die Masse muss unbekannt sein, nicht 0: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('ruecknahme:%s:99260007', q);
  assert v_x.schwere = 'info' and v_x.kg = 50 and v_x.wo = 'nichts',
    format('0126 (a7): Rücknahme: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('masse_abweichung:%s:99260008', q);
  assert v_x.kg = -20 and v_x.kg_rechnung = 80 and v_x.satz like '%80.0 kg%100 kg%zu wenig%' and v_x.wo = 'einlesen',
    format('0126 (a8): Lieferungen ≠ Datei: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('label_name:%s:99260009', q);
  assert v_x.kg = 40 and v_x.satz like '%(Demeter)%Preisgruppe K (Knospe)%',
    format('0126 (a9): Artikelname gegen Preisgruppe: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('unbekannt:%s:99260010:991267:1', q);
  assert v_x.kg = 110 and v_x.nummer = '991267' and v_x.wo = 'stammdaten' and v_x.satz like '%991267%keiner Charge%',
    format('0126 (a10): unbekannte Nummer: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('nachholen:%s:99260011:%s:1', q, v_k);
  assert v_x.schwere = 'info' and v_x.wo = 'nichts' and v_x.satz like format('%%an Charge %s%%', v_k),
    format('0126 (a11): inzwischen bekannte Nummer: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('mehrdeutig:%s:99260012:992613:1', q);
  assert v_x.satz like '%(99261, 99262)%' and v_x.wo = 'stammdaten',
    format('0126 (a12): Perigon-Nr. an zwei Chargen: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('artikel_sorte:%s:99260013:%s:1', q, v_k);
  assert v_x.kg = 72 and v_x.charge_nr = v_k and v_x.satz like '%Mandarin%Knirps%',
    format('0126 (a13): Artikel gegen Sorte: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('demeter_knospe:%s:99260014:%s:1', q, v_k);
  assert v_x.kg = 40 and v_x.satz like '%Preisgruppe D%Lieferlabel K%',
    format('0126 (a14): Demeter verkauft, Knospe geliefert: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('mix:%s:99260015:%s:1', q, v_k);
  assert v_x.kg = 288 and v_x.wo = 'firma' and v_x.satz like format('%%Mix%%%s%%', v_k),
    format('0126 (a15): Mix auf einer Charge: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_befund where schluessel = format('vor_eingang:%s:99260016:%s:1', q, v_k);
  assert v_x.kg = 176 and v_x.satz like '%3 Tage später%',
    format('0126 (a16): vor dem Eingang: %s', to_jsonb(v_x));
  assert not exists (select 1 from v_perigon_befund where quelle = q and pos_id = 99260017),
    format('0126 (a17): eine richtige Position steht als Fall da: %s',
           (select jsonb_agg(art) from v_perigon_befund where quelle = q and pos_id = 99260017));
  -- jede Position trägt genau die Arten, die zu ihr gehören
  for v_x in select * from (values (99260001::bigint, array['menge_null']), (99260002, array['menge_null']), (99260003, array['zu_viel']),
                                   (99260004, array['rest']), (99260005, array['keine_nummer']), (99260006, array['ohne_gewicht']),
                                   (99260007, array['ruecknahme']), (99260008, array['masse_abweichung']), (99260009, array['label_name']),
                                   (99260010, array['unbekannt']), (99260011, array['nachholen']), (99260012, array['mehrdeutig']),
                                   (99260013, array['artikel_sorte']), (99260014, array['demeter_knospe']), (99260015, array['mix']),
                                   (99260016, array['vor_eingang'])) s(pos, arten) loop
    select array_agg(art order by art) into v_art from v_perigon_befund where quelle = q and pos_id = v_x.pos;
    assert v_art = v_x.arten, format('0126 (a18): Position %s trägt %s statt %s', v_x.pos, v_art, v_x.arten);
  end loop;
  select count(*) into v_n from (select schluessel from v_perigon_befund group by 1 having count(*) > 1) d;
  assert v_n = 0, format('0126 (a19): %s Schlüssel stehen mehrfach da', v_n);
  assert not exists (select 1 from v_perigon_befund where satz is null or tun is null or wo is null or schwere is null or kg = 0),
    '0126 (a20): ein Fall ohne Satz, Was tun, Wo oder Schwere — oder mit 0 kg statt unbekannt';

  -- (b) der Stand der Prüf-Firma
  select * into v_x from v_perigon_stand where quelle = q;
  assert v_x.zeilen = 20 and v_x.positionen = 17 and v_x.ohne_roh = 17
     and v_x.faelle = (select count(*) from v_perigon_befund where quelle = q and schwere <> 'info') and v_x.faelle = 14,
    format('0126 (b1): Stand der Firma: %s', to_jsonb(v_x));

  -- (c) das Protokoll
  assert (select relrowsecurity from pg_class where oid = 'perigon_vermerk'::regclass)
     and (select relrowsecurity from pg_class where oid = 'perigon_fall_spur'::regclass),
    '0126 (c1): Protokoll oder Spur ohne Zeilenschutz';
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  insert into perigon_vermerk (schluessel, stand, notiz, schnappschuss)
  values (format('menge_null:%s:99260001', q), 'in_abklaerung', 'Büro fragt nach', '{"art":"menge_null"}');
  insert into perigon_vermerk (schluessel, stand, notiz) values (format('menge_null:%s:99260001', q), 'erledigt', 'in Perigon S gefüllt');
  v_ok := false;
  begin insert into perigon_vermerk (schluessel, stand, wer) values (format('mix:%s:99260015:%s:1', q, v_k), 'offen', v_w);
  exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0126 (c2): ein Vermerk liess sich im Namen eines anderen schreiben';
  v_ok := false;
  begin insert into perigon_vermerk (schluessel, stand) values (format('mix:%s:99260015:%s:1', q, v_k), 'vergessen');
  exception when check_violation then v_ok := true; end;
  assert v_ok, '0126 (c3): ein Stand, den es nicht gibt, liess sich vermerken';
  v_ok := false;
  begin update perigon_vermerk set notiz = 'umgeschrieben' where schluessel = format('menge_null:%s:99260001', q);
  exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0126 (c4): ein Vermerk liess sich nachträglich ändern';
  v_ok := false;
  begin delete from perigon_vermerk where schluessel = format('menge_null:%s:99260001', q);
  exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0126 (c5): ein Vermerk liess sich löschen';
  perform set_config('request.jwt.claim.sub', v_w::text, true);
  v_ok := false;
  begin insert into perigon_vermerk (schluessel, stand) values (format('mix:%s:99260015:%s:1', q, v_k), 'erledigt');
  exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0126 (c6): die Halle konnte einen Perigon-Fall abhaken';
  assert (select count(*) from perigon_vermerk where schluessel = format('menge_null:%s:99260001', q)) = 2,
    '0126 (c7): die Halle sieht die Vermerke nicht';
  v_ok := false;
  begin insert into perigon_fall_spur (schluessel, ebene, art, erst_gesehen, zuletzt_gesehen, schnappschuss)
        values ('x:y:z', 'zeile', 'x', now(), now(), '{}');
  exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0126 (c8): die Spur liess sich von Hand schreiben';
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  reset role;
  -- c10: Supabase gibt neuen Tabellen von sich aus weitere Rechte. Auch dann ändert und löscht die
  -- Zeilenregel nichts — es gibt für Ändern und Löschen keine.
  grant update, delete on perigon_vermerk to authenticated;
  set local role authenticated;
  update perigon_vermerk set notiz = 'umgeschrieben' where schluessel = format('menge_null:%s:99260001', q);
  get diagnostics v_n = row_count;
  assert v_n = 0, format('0126 (c10): mit Recht, aber ohne Regel liessen sich %s Vermerke ändern', v_n);
  delete from perigon_vermerk where schluessel = format('menge_null:%s:99260001', q);
  get diagnostics v_n = row_count;
  assert v_n = 0, format('0126 (c10): mit Recht, aber ohne Regel liessen sich %s Vermerke löschen', v_n);
  reset role;
  revoke update, delete on perigon_vermerk from authenticated;
  assert (select wer from perigon_vermerk where schluessel = format('menge_null:%s:99260001', q) order by ts desc, id desc limit 1) = v_u,
    '0126 (c9): der Vermerk weiss nicht, wer ihn schrieb';

  -- (e) das Merken
  perform perigon_faelle_merken();
  select * into v_x from perigon_fall_spur where schluessel = format('rest:%s:99260004', q);
  assert v_x.ebene = 'zeile' and v_x.weg_seit is null and v_x.erst_gesehen = v_x.zuletzt_gesehen and v_x.schnappschuss ->> 'satz' like '%987 von 1002%',
    format('0126 (e1): ein neuer Fall ist nicht gemerkt: %s', to_jsonb(v_x));
  assert (select count(*) from perigon_fall_spur where schluessel like '%:' || q || ':%' and weg_seit is null)
       = (select count(*) from v_perigon_befund where quelle = q),
    '0126 (e2): nicht jeder Fall der Prüf-Firma ist gemerkt';
  assert (select count(*) from perigon_fall_spur s where s.ebene = 'charge' and s.weg_seit is null)
       = (select count(distinct ungereimt_schluessel(u.art, u.charge_nr, u.sorte, u.mehr)) from v_ungereimtheit u),
    '0126 (e3): die Sachen je Charge sind nicht mit ihrem Schlüssel gemerkt';
  v_erst := v_x.erst_gesehen;
  -- in Perigon berichtigt und neu eingelesen: Spalte W gefüllt
  update ausgang_zeile set charge_extern = v_k::text, batch_menge = 8, kg_charge = 8 where quelle = q and pos_id = 99260005;
  update ausgang_zeile set kg_charge = 1002, batch_menge = 1002 where quelle = q and pos_id = 99260004;
  perform perigon_faelle_merken();
  select * into v_x from perigon_fall_spur where schluessel = format('rest:%s:99260004', q);
  assert v_x.weg_seit is not null and v_x.erst_gesehen = v_erst,
    format('0126 (e4): ein behobener Fall steht nicht als „nicht mehr in den Daten": %s', to_jsonb(v_x));
  assert (select weg_seit is null and zuletzt_gesehen > v_erst from perigon_fall_spur where schluessel = format('zu_viel:%s:99260003', q)),
    '0126 (e5): ein Fall, der noch da ist, ist nicht nachgeführt';
  -- wieder wie vorher
  update ausgang_zeile set kg_charge = 987, batch_menge = 987 where quelle = q and pos_id = 99260004;
  perform perigon_faelle_merken();
  select * into v_x from perigon_fall_spur where schluessel = format('rest:%s:99260004', q);
  assert v_x.weg_seit is null and v_x.erst_gesehen = v_erst and v_x.zuletzt_gesehen > v_erst,
    format('0126 (e6): ein Fall, der wiederkommt, ist nicht derselbe: %s', to_jsonb(v_x));
  assert ungereimt_schluessel('ueberzaehlung', 1630, 'Kaori Kuri', '{"kandidaten":[]}') = 'ueberzaehlung:1630:'
     and ungereimt_schluessel('umgebucht', 1627, 'Fictor', '{"auftrag_id":1602}') = 'umgebucht:1627:1602'
     and ungereimt_schluessel('ohne_charge', null, 'Tiana', '{}') = 'ohne_charge:Tiana:'
     and ungereimt_schluessel('stammdaten', 1649, null, '{"pruefung":"perigon_doppelt"}') = 'stammdaten:1649:perigon_doppelt',
    '0126 (e7): der Schlüssel einer Sache je Charge ist nicht der der App';

  -- (d) der Verlauf
  select * into v_x from v_perigon_verlauf where schluessel = format('menge_null:%s:99260001', q);
  assert v_x.stand = 'erledigt' and v_x.notiz = 'in Perigon S gefüllt' and v_x.n_vermerke = 2 and v_x.vermerk_von = 'Prüf-0126'
     and v_x.erst_gesehen is not null and v_x.weg_seit is null and v_x.art = 'menge_null',
    format('0126 (d1): der letzte Vermerk zählt nicht: %s', to_jsonb(v_x));
  select * into v_x from v_perigon_verlauf where schluessel = format('keine_nummer:%s:99260005', q);
  assert v_x.stand = 'offen' and v_x.n_vermerke = 0 and v_x.weg_seit is not null and v_x.schnappschuss ->> 'art' = 'keine_nummer',
    format('0126 (d2): ein verschwundener Fall ohne Vermerk: %s', to_jsonb(v_x));

  -- (f) nach jedem fertigen Rechenlauf
  select berechnet_ts into v_berechnet from auswertung_stand where id = 1;
  select zuletzt_gesehen into v_zuletzt from perigon_fall_spur where schluessel = format('zu_viel:%s:99260003', q);
  update auswertung_stand set rechnet_seit = clock_timestamp() where id = 1;
  assert (select zuletzt_gesehen from perigon_fall_spur where schluessel = format('zu_viel:%s:99260003', q)) = v_zuletzt,
    '0126 (f1): ein Nachführen ohne neues berechnet_ts hat gemerkt';
  update auswertung_stand set rechnet_seit = null, berechnet_ts = clock_timestamp() where id = 1;
  assert (select zuletzt_gesehen from perigon_fall_spur where schluessel = format('zu_viel:%s:99260003', q)) > v_zuletzt,
    '0126 (f2): nach einem fertigen Rechenlauf hat die App sich die Fälle nicht gemerkt';
  update auswertung_stand set berechnet_ts = v_berechnet where id = 1;

  -- (g) Rechte
  assert has_table_privilege('authenticated', 'v_perigon_befund', 'select') and has_table_privilege('authenticated', 'v_perigon_stand', 'select')
     and has_table_privilege('authenticated', 'v_perigon_verlauf', 'select') and has_table_privilege('authenticated', 'perigon_fall_spur', 'select'),
    '0126 (g1): Angemeldete können die Perigon-Sichten nicht lesen';
  assert not has_table_privilege('anon', 'v_perigon_befund', 'select') and not has_table_privilege('anon', 'perigon_vermerk', 'select')
     and not has_table_privilege('anon', 'v_perigon_verlauf', 'select'),
    '0126 (g2): Perigon-Fälle sind ohne Anmeldung lesbar';
  assert not has_table_privilege('authenticated', 'perigon_vermerk', 'update') and not has_table_privilege('authenticated', 'perigon_vermerk', 'delete'),
    '0126 (g3): Vermerke lassen sich ändern oder löschen';

  -- aufräumen — und dabei (e8): die Fälle einer entfernten Firma vergisst die Spur, ausser sie haben einen Vermerk
  delete from lieferung where bemerkung in ('Prüf-0126', 'ohne Chargenbezug') and id in (select lieferung_id from lieferung_import where quelle = q);
  delete from lieferung_import where quelle = q;
  delete from ausgang_zeile where quelle = q;
  delete from ausgang_quelle where code = q;
  perform perigon_faelle_merken();
  assert (select count(*) from perigon_fall_spur where schluessel like '%:' || q || ':%') = 1
     and (select weg_seit is not null from perigon_fall_spur where schluessel = format('menge_null:%s:99260001', q)),
    format('0126 (e8): nach dem Entfernen der Firma stehen %s ihrer Fälle in der Spur (erwartet: nur der mit Vermerk, als verschwunden)',
           (select count(*) from perigon_fall_spur where schluessel like '%:' || q || ':%'));
  delete from perigon_vermerk where schluessel like '%:' || q || ':%';
  delete from perigon_fall_spur where schluessel like '%:' || q || ':%';
  delete from charge where nr in (99261, 99262);
  update auswertung_stand set rechnet_seit = null where id = 1;
  if v_geladen then perform demo_daten_entfernen(); end if;
  delete from profil where id in (v_u, v_w); delete from auth.users where id in (v_u, v_w);
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';

  -- (h) Stand
  assert schema_stand() >= 126, format('0126 (h1): schema_stand() = %s', schema_stand());
  raise notice 'OK  0126 — jeder Perigon-Fall steht mit Schlüssel, Zahlen der Datei, Satz und Wo da (S = 0, zu viel, Rest, keine Nummer, ohne Gewicht, Rücknahme, Lieferungen ≠ Datei, Name gegen Preisgruppe, Nummern, Artikel, Label, Mix, vor dem Eingang); der Betriebsleiter vermerkt, niemand ändert; die App merkt sich nach jedem Rechnen, was neu ist und was verschwand';
end $$;

select '——— 0126 Perigon-Reiter: jeder Fall nachvollziehbar und mitverfolgt ———' as ergebnis;
