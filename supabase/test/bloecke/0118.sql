-- =====================================================================
-- 0118 — Ein Rest ohne Charge ist keine unbekannte Charge
--
-- (a) ein Rest (die Datei schreibt der Charge weniger zu, als die Position
--     geliefert hat) steht als „Teil ohne Charge" mit seiner Masse, nicht als
--     „Charge nicht zugeordnet"; (b) eine Nummer, die an keiner Charge steht,
--     bleibt „Charge nicht zugeordnet" und sagt, was zu tun ist; (c) steht die
--     Perigon-Nummer an genau einer Charge, nennt der Satz sie und verlangt
--     nur das neue Einlesen; (d) ein Rest meldet „Demeter verkauft, Knospe
--     geliefert" nicht noch einmal; (e) Stand 118.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false;
  v_u uuid := '00000000-0118-0000-0000-000000000001';
  v_c int; v_sorte text; v_c2 int; v_alt int; v_txt text;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0118"}');
  update profil set rolle = 'admin' where id = v_u;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from charge) then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  select c.nr, c.sorte into v_c, v_sorte from charge c order by c.nr limit 1;
  -- eine zweite Charge ohne Perigon-Nummer, für (c)
  select c.nr, c.perigon_nr into v_c2, v_alt from charge c where c.nr <> v_c order by c.nr limit 1;
  -- (c0) der Betriebsleiter trägt die Perigon-Nummer selbst ein (Stammdaten → Chargen)
  set local role authenticated;
  begin update charge set perigon_nr = 991180 where nr = v_c2; exception when insufficient_privilege then null; end;
  reset role;
  assert (select perigon_nr = 991180 from charge where nr = v_c2),
    '0118 (c0): der Betriebsleiter konnte die Perigon-Nummer einer Charge nicht eintragen';

  insert into ausgang_quelle (code, name, dateiname_muster) values ('PRUEF118', 'Prüffirma 0118', 'PRUEF118')
  on conflict (code) do nothing;
  -- 801: 50 kg geliefert, der Charge v_c nur 40 zugeschrieben → 10 kg Rest, verkauft als Demeter, geliefert als Knospe
  -- 802: eine Nummer, die an keiner Charge steht
  -- 803: die Perigon-Nummer 991180 steht an Charge v_c2, die Lieferung trägt sie (noch) nicht
  perform ausgang_uebernehmen('PRUEF118', 'Prüffirma 0118', '{"dateiname": "p118.xlsx", "pruefsumme": "p118"}'::jsonb,
    jsonb_build_array(
      jsonb_build_object('pos_id', 801, 'charge_extern', v_c::text, 'lauf_nr', 1, 'fingerabdruck', 'p118-801',
        'datum', heute(), 'journal', 'A', 'kunde', 'Prüfkunde 118', 'artikel_id', 'kürbp118x', 'artikel', 'Bio Kürbis Prüf',
        'einheit', 'kg', 'menge', 50, 'gewicht_je_artikel', 1, 'batch_menge', 40, 'kg_position', 50, 'kg_charge', 40,
        'liefer_label', 'K', 'preisgruppe', 'D'),
      jsonb_build_object('pos_id', 802, 'charge_extern', '991181', 'lauf_nr', 1, 'fingerabdruck', 'p118-802',
        'datum', heute(), 'journal', 'A', 'kunde', 'Prüfkunde 118', 'artikel_id', 'kürbp118x', 'artikel', 'Bio Kürbis Prüf',
        'einheit', 'kg', 'menge', 20, 'gewicht_je_artikel', 1, 'batch_menge', 20, 'kg_position', 20, 'kg_charge', 20),
      jsonb_build_object('pos_id', 803, 'charge_extern', '991180', 'lauf_nr', 1, 'fingerabdruck', 'p118-803',
        'datum', heute(), 'journal', 'A', 'kunde', 'Prüfkunde 118', 'artikel_id', 'kürbp118x', 'artikel', 'Bio Kürbis Prüf',
        'einheit', 'kg', 'menge', 30, 'gewicht_je_artikel', 1, 'batch_menge', 30, 'kg_position', 30, 'kg_charge', 30)),
    jsonb_build_array(
      jsonb_build_object('extern_id', format('PRUEF118:801:%s:1', v_c), 'datum', heute(), 'charge_nr', v_c, 'sorte', v_sorte, 'kg', 40, 'kunde', 'Prüfkunde 118'),
      jsonb_build_object('extern_id', 'PRUEF118:801:rest', 'datum', heute(), 'charge_nr', null, 'sorte', v_sorte, 'kg', 10, 'kunde', 'Prüfkunde 118'),
      jsonb_build_object('extern_id', 'PRUEF118:802:991181:1', 'datum', heute(), 'charge_nr', null, 'sorte', v_sorte, 'kg', 20, 'kunde', 'Prüfkunde 118'),
      jsonb_build_object('extern_id', 'PRUEF118:803:991180:1', 'datum', heute(), 'charge_nr', null, 'sorte', v_sorte, 'kg', 30, 'kunde', 'Prüfkunde 118')));
  perform ausgang_historie_uebernehmen('PRUEF118', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('pos_id', 801, 'charge_extern', v_c::text, 'lauf_nr', 1, 'liefer_label', 'K', 'preisgruppe', 'D')));
  assert (select count(*) from lieferung_import where quelle = 'PRUEF118' and zeile_id is not null) = 4,
    format('0118 (vorab): %s von 4 Lieferungen hängen an ihrer Zeile', (select count(*) from lieferung_import where quelle = 'PRUEF118' and zeile_id is not null));

  -- (a) der Rest
  assert not exists (select 1 from v_perigon_pruefung where quelle = 'PRUEF118' and pos_id = 801 and art = 'Charge nicht zugeordnet'),
    '0118 (a1): der Rest einer Position steht als „Charge nicht zugeordnet" da, obwohl ihre Charge bekannt ist';
  select befund into v_txt from v_perigon_pruefung where quelle = 'PRUEF118' and pos_id = 801 and art = 'Teil ohne Charge' and kg = 10;
  assert v_txt like '10.0 kg der Position%' and v_txt like format('%%Charge %s weniger zu%%', v_c),
    format('0118 (a2): der Rest steht nicht als „Teil ohne Charge" mit 10 kg und seiner Charge: %s',
           coalesce(v_txt, (select string_agg(format('%s %s kg', art, kg), '; ') from v_perigon_pruefung where quelle = 'PRUEF118' and pos_id = 801)));
  -- (b) die unbekannte Nummer
  assert (select befund like '%steht an keiner Charge%unter Stammdaten%' from v_perigon_pruefung
           where quelle = 'PRUEF118' and pos_id = 802 and art = 'Charge nicht zugeordnet'),
    '0118 (b1): eine Nummer, die an keiner Charge steht, fällt nicht auf oder sagt nicht, was zu tun ist';
  -- (c) die Perigon-Nummer an genau einer Charge
  assert (select befund like format('%%steht an Charge %s;%%neu einlesen', v_c2) from v_perigon_pruefung
           where quelle = 'PRUEF118' and pos_id = 803 and art = 'Charge nicht zugeordnet'),
    format('0118 (c1): die Nummer an genau einer Charge sagt „%s"',
           (select befund from v_perigon_pruefung where quelle = 'PRUEF118' and pos_id = 803));
  -- (d) Demeter/Knospe einmal, nicht noch einmal für den Rest
  assert (select count(*) from v_perigon_pruefung where quelle = 'PRUEF118' and pos_id = 801
           and art = 'Als Demeter verkauft, als Knospe geliefert') = 1,
    format('0118 (d1): „Demeter verkauft, Knospe geliefert" steht %s-mal für eine Position mit Rest',
           (select count(*) from v_perigon_pruefung where quelle = 'PRUEF118' and pos_id = 801 and art = 'Als Demeter verkauft, als Knospe geliefert'));

  delete from lieferung where id in (select lieferung_id from lieferung_import where quelle = 'PRUEF118');
  delete from ausgang_zeile where quelle = 'PRUEF118';
  delete from ausgang_datei where quelle = 'PRUEF118';
  delete from ausgang_position where quelle = 'PRUEF118';
  delete from ausgang_quelle where code = 'PRUEF118';
  update charge set perigon_nr = v_alt where nr = v_c2;
  if v_geladen then perform demo_daten_entfernen(); end if;

  -- (e) Stand
  assert schema_stand() >= 118, format('0118 (e1): schema_stand() = %s', schema_stand());

  delete from profil where id = v_u; delete from auth.users where id = v_u;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0118 — ein Rest ohne Charge steht als „Teil ohne Charge", nicht als unbekannte Charge; eine Nummer an keiner Charge sagt, was zu tun ist; eine Perigon-Nummer an genau einer Charge nennt sie; Demeter/Knospe nicht doppelt';
end $$;

select '——— 0118 Ein Rest ohne Charge ist keine unbekannte Charge ———' as ergebnis;
