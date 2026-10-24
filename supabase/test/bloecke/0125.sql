-- =====================================================================
-- 0125 — Jeder Lieferschein ohne Charge, mit dem Grund
--
-- (a) Ein gebauter Fall je Grund: von Hand; aus Perigon, aber ohne
--     Verknüpfung (Bemerkung des Einlesens) oder ohne Zeile; keine Nummer
--     (Spalte W leer); Menge null (Chargen genannt, Spalte S = 0); Rest
--     (S kleiner als die Position); Nummer inzwischen bekannt (die eigene
--     und eine Perigon-Nr.); mehrdeutig; unbekannt — je mit Satz, Zahlen,
--     Firma, Position und Artikel.
-- (b) Dieselben Lieferscheine wie v_ohne_charge: Anzahl und Summe je Sorte
--     stimmen; ein Lieferschein mit Charge, einer nach heute und einer, der
--     nicht verkauft ist (Eigenbedarf), stehen nicht da.
-- (c) Lesbar für Angemeldete, nicht für Unangemeldete.
-- (d) Stand 125.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false;
  v_u uuid := '00000000-0125-0000-0000-000000000001';
  v_quelle text; v_tag date := heute() - 14; v_z bigint; v_l bigint; v_x record;
  v_sorte text; v_nr int; v_pnr bigint; v_pnr_charge int;
  v_id jsonb := '{}'::jsonb; v_aus bigint[] := '{}'; v_n int;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0125"}');
  update profil set rolle = 'admin' where id = v_u;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  -- Ohne Demo gibt es keine Perigon-Firma (ausgang_quelle) — dann die Demo laden, wie 0122.
  if not exists (select 1 from ausgang_quelle) or not exists (select 1 from charge c where c.perigon_nr is not null) then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  select code into v_quelle from ausgang_quelle order by code limit 1;
  -- eine Charge mit eigener Nummer und eine mit einer Perigon-Nr., die nur an ihr steht
  select c.nr, c.sorte into v_nr, v_sorte from charge c order by c.nr limit 1;
  select c.perigon_nr, c.nr into v_pnr, v_pnr_charge from charge c
   where c.perigon_nr is not null and (select count(*) from charge x where x.perigon_nr = c.perigon_nr) = 1
   order by c.nr limit 1;
  assert v_quelle is not null and v_nr is not null and v_pnr is not null, '0125: keine Firma, Charge oder Perigon-Nr. zum Bauen der Fälle';
  insert into charge (nr, schlag, sorte, saison, perigon_nr) values
    (99251, 'Prüf-0125 A', v_sorte, 2026, 991253), (99252, 'Prüf-0125 B', v_sorte, 2026, 991253);

  -- (a) die Fälle
  -- a1 von Hand
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung) values (v_tag, null, v_sorte, 101, 'verkauf', 'Prüf-0125') returning id into v_l;
  v_id := v_id || jsonb_build_object('von_hand', v_l);
  -- a2 aus Perigon (Bemerkung des Einlesens), die Verknüpfung fehlt
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung) values (v_tag, null, v_sorte, 102, 'verkauf', 'ohne Chargenbezug') returning id into v_l;
  v_id := v_id || jsonb_build_object('bemerkung_rest', v_l);
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, bemerkung) values (v_tag, null, v_sorte, 112, 'verkauf', 'Charge 991259 (extern)') returning id into v_l;
  v_id := v_id || jsonb_build_object('bemerkung_extern', v_l);
  -- a3 eingelesen, aber keine Zeile der Datei mehr
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, null, v_sorte, 103, 'verkauf') returning id into v_l;
  insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, v_quelle, format('%s:9912503:rest', v_quelle), null);
  v_id := v_id || jsonb_build_object('ohne_zeile', v_l);
  -- a4 keine Nummer (Spalte W leer)
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_position, kg_charge)
  values (v_quelle, 9912504, '', 1, 'pruef-0125-4', v_tag, 'P0125', 'Bio Kürbis Prüf-0125 lose', 104, null) returning id into v_z;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, null, v_sorte, 104, 'verkauf') returning id into v_l;
  insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, v_quelle, format('%s:9912504:rest', v_quelle), v_z);
  v_id := v_id || jsonb_build_object('keine_nummer', v_l);
  -- a5 zwei Chargen genannt, Spalte S = 0
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_position, kg_charge)
  values (v_quelle, 9912505, '991251', 1, 'pruef-0125-5a', v_tag, 'P0125', 'Bio Kürbis Prüf-0125 lose', 105, 0) returning id into v_z;
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_position, kg_charge)
  values (v_quelle, 9912505, '991252', 1, 'pruef-0125-5b', v_tag, 'P0125', 'Bio Kürbis Prüf-0125 lose', 105, 0);
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, null, v_sorte, 105, 'verkauf') returning id into v_l;
  insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, v_quelle, format('%s:9912505:rest', v_quelle), v_z);
  v_id := v_id || jsonb_build_object('menge_null', v_l);
  -- a6 Spalte S teilt 60 von 106 kg zu; der Rest
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_position, kg_charge)
  values (v_quelle, 9912506, v_nr::text, 1, 'pruef-0125-6', v_tag, 'P0125', 'Bio Kürbis Prüf-0125 lose', 106, 60) returning id into v_z;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, null, v_sorte, 46, 'verkauf') returning id into v_l;
  insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, v_quelle, format('%s:9912506:rest', v_quelle), v_z);
  v_id := v_id || jsonb_build_object('rest', v_l);
  -- a7 die eigene Nummer, beim Einlesen nicht aufgelöst
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_position, kg_charge)
  values (v_quelle, 9912507, v_nr::text, 1, 'pruef-0125-7', v_tag, 'P0125', 'Bio Kürbis Prüf-0125 lose', 107, 107) returning id into v_z;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, null, v_sorte, 107, 'verkauf') returning id into v_l;
  insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, v_quelle, format('%s:9912507:%s:1', v_quelle, v_nr), v_z);
  v_id := v_id || jsonb_build_object('nachholen_eigene', v_l);
  -- a8 eine Perigon-Nr., die inzwischen an genau einer Charge steht
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_position, kg_charge)
  values (v_quelle, 9912508, v_pnr::text, 1, 'pruef-0125-8', v_tag, 'P0125', 'Bio Kürbis Prüf-0125 lose', 108, 108) returning id into v_z;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, null, v_sorte, 108, 'verkauf') returning id into v_l;
  insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, v_quelle, format('%s:9912508:%s:1', v_quelle, v_pnr), v_z);
  v_id := v_id || jsonb_build_object('nachholen_perigon', v_l);
  -- a9 eine Perigon-Nr. an zwei Chargen
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_position, kg_charge)
  values (v_quelle, 9912509, '991253', 1, 'pruef-0125-9', v_tag, 'P0125', 'Bio Kürbis Prüf-0125 lose', 109, 109) returning id into v_z;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, null, v_sorte, 109, 'verkauf') returning id into v_l;
  insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, v_quelle, format('%s:9912509:991253:1', v_quelle), v_z);
  v_id := v_id || jsonb_build_object('mehrdeutig', v_l);
  -- a10 eine Nummer, die an keiner Charge steht
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_position, kg_charge)
  values (v_quelle, 9912510, '991254', 1, 'pruef-0125-10', v_tag, 'P0125', 'Bio Kürbis Prüf-0125 lose', 110, 110) returning id into v_z;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, null, v_sorte, 110, 'verkauf') returning id into v_l;
  insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id) values (v_l, v_quelle, format('%s:9912510:991254:1', v_quelle), v_z);
  v_id := v_id || jsonb_build_object('unbekannt', v_l);
  -- (b) was nicht dastehen darf: mit Charge, nach heute, nicht verkauft
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, v_nr, v_sorte, 113, 'verkauf') returning id into v_l; v_aus := v_aus || v_l;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (heute() + 3, null, v_sorte, 114, 'verkauf') returning id into v_l; v_aus := v_aus || v_l;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (v_tag, null, v_sorte, 115, 'eigenbedarf') returning id into v_l; v_aus := v_aus || v_l;

  -- (a) prüfen
  for v_x in select k, (v_id->>k)::bigint as id from jsonb_object_keys(v_id) k loop
    assert exists (select 1 from v_lieferung_ohne_charge where id = v_x.id),
      format('0125 (a0): der Lieferschein „%s" fehlt in v_lieferung_ohne_charge', v_x.k);
  end loop;
  assert (select grund from v_lieferung_ohne_charge where id = (v_id->>'von_hand')::bigint) = 'von_hand'
     and (select quelle from v_lieferung_ohne_charge where id = (v_id->>'von_hand')::bigint) is null,
    '0125 (a1): ein von Hand erfasster Lieferschein ohne Charge heisst nicht „von_hand"';
  assert (select grund from v_lieferung_ohne_charge where id = (v_id->>'bemerkung_rest')::bigint) = 'ohne_zeile'
     and (select grund from v_lieferung_ohne_charge where id = (v_id->>'bemerkung_extern')::bigint) = 'ohne_zeile',
    '0125 (a2): ein eingelesener Lieferschein ohne Verknüpfung (Bemerkung des Einlesens) steht als „von Hand" da';
  select * into v_x from v_lieferung_ohne_charge where id = (v_id->>'ohne_zeile')::bigint;
  assert v_x.grund = 'ohne_zeile' and v_x.quelle = v_quelle and v_x.pos_id = 9912503 and v_x.tun like '%neu einlesen%',
    format('0125 (a3): eingelesen ohne Zeile: %s', to_jsonb(v_x));
  select * into v_x from v_lieferung_ohne_charge where id = (v_id->>'keine_nummer')::bigint;
  assert v_x.grund = 'keine_nummer' and v_x.pos_id = 9912504 and v_x.artikel = 'Bio Kürbis Prüf-0125 lose' and v_x.nummer is null
     and v_x.satz like '%Spalte W%' and v_x.kg = 104,
    format('0125 (a4): Spalte W leer: %s', to_jsonb(v_x));
  select * into v_x from v_lieferung_ohne_charge where id = (v_id->>'menge_null')::bigint;
  assert v_x.grund = 'menge_null' and v_x.nummer = '991251, 991252' and v_x.satz like '%die Chargen 991251, 991252%' and v_x.satz like '%Spalte S%',
    format('0125 (a5): Chargen genannt, Spalte S = 0: %s', to_jsonb(v_x));
  select * into v_x from v_lieferung_ohne_charge where id = (v_id->>'rest')::bigint;
  assert v_x.grund = 'rest' and v_x.satz like format('%%die Charge %s nur 60 von 106 kg%%', v_nr) and v_x.kg = 46,
    format('0125 (a6): der Rest einer Position: %s', to_jsonb(v_x));
  select * into v_x from v_lieferung_ohne_charge where id = (v_id->>'nachholen_eigene')::bigint;
  assert v_x.grund = 'nachholen' and v_x.satz like format('%%an Charge %s%%', v_nr) and v_x.tun like '%nächsten Rechnen%',
    format('0125 (a7): die eigene Nummer, inzwischen bekannt: %s', to_jsonb(v_x));
  select * into v_x from v_lieferung_ohne_charge where id = (v_id->>'nachholen_perigon')::bigint;
  assert v_x.grund = 'nachholen' and v_x.satz like format('%%an Charge %s%%', v_pnr_charge),
    format('0125 (a8): eine Perigon-Nr. an genau einer Charge: %s', to_jsonb(v_x));
  select * into v_x from v_lieferung_ohne_charge where id = (v_id->>'mehrdeutig')::bigint;
  assert v_x.grund = 'mehrdeutig' and v_x.satz like '%(99251, 99252)%',
    format('0125 (a9): eine Perigon-Nr. an zwei Chargen: %s', to_jsonb(v_x));
  select * into v_x from v_lieferung_ohne_charge where id = (v_id->>'unbekannt')::bigint;
  assert v_x.grund = 'unbekannt' and v_x.nummer = '991254' and v_x.satz like '%991254%keiner Charge%' and v_x.tun like '%Stammdaten%',
    format('0125 (a10): eine Nummer an keiner Charge: %s', to_jsonb(v_x));
  assert not exists (select 1 from v_lieferung_ohne_charge where satz is null or tun is null or grund is null),
    '0125 (a11): ein Lieferschein ohne Charge steht ohne Grund, Satz oder Was tun da';

  -- (b) dieselben wie v_ohne_charge
  assert not exists (select 1 from v_lieferung_ohne_charge where id = any(v_aus)),
    '0125 (b1): ein Lieferschein mit Charge, nach heute oder nicht verkauft steht unter „ohne Charge"';
  select count(*) into v_n from (
    select coalesce(a.sorte, b.sorte) as sorte
      from (select sorte, count(*)::int as n, sum(kg) as kg from v_lieferung_ohne_charge group by sorte) a
      full join v_ohne_charge b on coalesce(b.sorte, '') = coalesce(a.sorte, '')
     where a.n is distinct from b.n_lieferungen or abs(coalesce(a.kg, 0) - coalesce(b.kg, 0)) > 0.05) d;
  assert v_n = 0, format('0125 (b2): bei %s Sorten passen Anzahl oder Summe nicht zu v_ohne_charge', v_n);

  -- (c) wer lesen darf
  assert has_table_privilege('authenticated', 'v_lieferung_ohne_charge', 'select'),
    '0125 (c1): Angemeldete können v_lieferung_ohne_charge nicht lesen';
  assert not has_table_privilege('anon', 'v_lieferung_ohne_charge', 'select'),
    '0125 (c2): v_lieferung_ohne_charge ist ohne Anmeldung lesbar';

  -- aufräumen
  delete from lieferung where id in (select (value)::bigint from jsonb_each_text(v_id)) or id = any(v_aus);
  delete from ausgang_zeile where fingerabdruck like 'pruef-0125-%';
  delete from charge where nr in (99251, 99252);
  update auswertung_stand set rechnet_seit = null where id = 1;
  if v_geladen then perform demo_daten_entfernen(); end if;
  delete from profil where id = v_u; delete from auth.users where id = v_u;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';

  -- (d) Stand
  assert schema_stand() >= 125, format('0125 (d1): schema_stand() = %s', schema_stand());
  raise notice 'OK  0125 — jeder Lieferschein ohne Charge steht einzeln da, mit Firma, Position und dem Grund (von Hand, ohne Zeile, keine Nummer, Spalte S = 0, Rest, nachholen, mehrdeutig, unbekannt) — dieselben wie in der Summe je Sorte';
end $$;

select '——— 0125 Lieferscheine ohne Charge, mit Grund ———' as ergebnis;
