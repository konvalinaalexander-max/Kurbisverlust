-- =====================================================================
-- 0119 — Zwei Sortierschemata für eine Charge halten die Rechnung nicht an
--
-- Nachgestellt, was der Betrieb sah: Eine Nacht rechnet nebenläufig und legt
-- die eindeutigen Indizes an; danach bekommt eine Charge Sortierläufe mit
-- zwei anderen Schemata (andere untere Grenze; gleiche untere, andere obere)
-- und eine Arbeit eine zweite Datei; dann „Neu rechnen".
-- (a) „Neu rechnen" läuft durch; (b) erg_kaliber zeigt jedes Band für sich;
-- (c) die nächste Nacht legt den Index von erg_kaliber mit den Bandgrenzen
--     an, erg_ausschuss bekommt keinen; (d) ein Index, den die Daten nicht
--     hergeben, hält die Rechnung nicht an — er geht weg und steht in
--     auswertung_index_entfernt; (e) das liest nur der Betriebsleiter;
--     (f) Stand 119.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false;
  v_u uuid := '00000000-0119-0000-0000-000000000001';
  v_w uuid := '00000000-0119-0000-0000-000000000002';
  v_c int; v_sorte text; v_lauf bigint; v_auftrag bigint; v_k text; v_s int; v_fehler text; v_n int;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0119"}');
  update profil set rolle = 'admin' where id = v_u;
  insert into auth.users (id, email, raw_user_meta_data) values (v_w, null, '{"name":"Prüf-0119 Halle"}');
  update profil set rolle = 'arbeiter' where id = v_w;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from sortier_lauf) then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;

  -- Zwei Nächte: nebenläufig; die erste füllt, was leer ist, die zweite legt die eindeutigen Indizes an
  --   (so stand es beim Betrieb, bevor die neuen Dateien kamen)
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, true); end loop;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, true); end loop;
  assert to_regclass('erg_kaliber_eindeutig') is not null, '0119 (vorab): nach zwei Nächten hat erg_kaliber keinen eindeutigen Index';

  -- Die Sortierdateien mit Datum: eine Charge mit Läufen in zwei weiteren Schemata, eine Arbeit mit zwei Dateien
  select l.id, l.charge_nr, c.sorte, l.auftrag_id into v_lauf, v_c, v_sorte, v_auftrag
    from sortier_lauf l join charge c on c.nr = l.charge_nr
   where l.auftrag_id is not null and exists (select 1 from sortier_gewicht g where g.lauf_id = l.id and g.klasse = 'kaliber' and g.kaliber_idx = 0)
   order by l.id limit 1;
  select code into v_k from kaeufer order by code limit 1;
  insert into sortierschema (id, sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab) values
    (911901, v_sorte, v_k, date '2001-01-01', 'kaliber', 300, '[[411, 911], [911, 2000]]'::jsonb, 2000),
    (911902, v_sorte, v_k, date '2001-01-02', 'kaliber', 300, '[[411, 999], [999, 2000]]'::jsonb, 2000);
  insert into sortier_lauf
  select (jsonb_populate_record(null::sortier_lauf, to_jsonb(l) || jsonb_build_object(
            'id', 911900 + n, 'sortierschema_id', 911900 + n, 'datei_name', format('pruef-0119-%s.csv', n),
            'roh_pruefsumme', format('pruef-0119-%s', n), 'vorgaenger_id', null))).*
    from sortier_lauf l cross join generate_series(1, 2) n where l.id = v_lauf;
  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  select 911900 + n, g, 4, 'kaliber', i from generate_series(1, 2) n, (values (700, 0), (1200, 1)) x(g, i);

  -- (a) „Neu rechnen" — der Weg aus der App, fünf Schritte, nicht nebenläufig
  begin
    for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  exception when others then v_fehler := sqlerrm;
  end;
  assert v_fehler is null, format('0119 (a1): „Neu rechnen" bricht ab: %s', v_fehler);
  -- (b) jedes Band für sich
  assert (select count(*) from erg_kaliber where charge_nr = v_c and klasse = 'kaliber' and kaliber_idx = 0) >= 3
     and exists (select 1 from erg_kaliber where charge_nr = v_c and kaliber_idx = 0 and band_von = 411 and band_bis = 911)
     and exists (select 1 from erg_kaliber where charge_nr = v_c and kaliber_idx = 0 and band_von = 411 and band_bis = 999),
    format('0119 (b1): erg_kaliber zeigt die Bänder der Charge %s nicht getrennt: %s', v_c,
           (select string_agg(format('%s–%s', band_von, band_bis), ', ') from erg_kaliber where charge_nr = v_c and kaliber_idx = 0));
  assert not exists (select 1 from auswertung_index_entfernt where sicht in ('erg_kaliber', 'erg_ausschuss', 'mv_kaliber_verteilung')),
    format('0119 (a2): der Lauf musste einen Index entfernen, den der Schlüssel hätte tragen sollen: %s',
           (select string_agg(sicht, ', ') from auswertung_index_entfernt));

  -- (c) die nächste Nacht
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, true); end loop;
  assert coalesce((select pg_get_indexdef(indexrelid) like '%(charge_nr, klasse, kaliber_idx, band_von, band_bis)%'
                     from pg_index where indexrelid = to_regclass('erg_kaliber_eindeutig')), false),
    '0119 (c1): erg_kaliber bekommt nachts keinen Index mit den Bandgrenzen';
  assert to_regclass('erg_ausschuss_eindeutig') is null,
    '0119 (c2): erg_ausschuss bekommt wieder einen Schlüssel, den es nicht hat (Weg, Charge, Arbeit)';
  assert coalesce((select pg_get_indexdef(indexrelid) like '%band_bis%' from pg_index where indexrelid = to_regclass('mv_kaliber_pk')), false),
    '0119 (c3): der Index von mv_kaliber_verteilung kennt die obere Bandgrenze nicht';

  -- (d) ein Index, den die Daten nicht hergeben: heute passt er (je Band eine obere Grenze),
  --     nach der nächsten Datei nicht mehr (zwei Bänder enden bei 911 g)
  delete from auswertung_index_entfernt;
  execute 'create unique index erg_kaliber_falsch on erg_kaliber (charge_nr, klasse, kaliber_idx, band_bis) nulls not distinct where kaliber_idx = 0';
  update sortierschema set kaliber_baender = '[[500, 911], [911, 2000]]'::jsonb where id = 911902;
  v_fehler := null;
  begin
    for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  exception when others then v_fehler := sqlerrm;
  end;
  assert v_fehler is null, format('0119 (d1): ein Index, den die Daten nicht hergeben, hält die Rechnung an: %s', v_fehler);
  assert to_regclass('erg_kaliber_falsch') is null
     and exists (select 1 from auswertung_index_entfernt where sicht = 'erg_kaliber' and grund like '%erg_kaliber_falsch%'),
    format('0119 (d2): der Index blieb stehen oder ist nicht notiert: %s',
           (select string_agg(sicht || ': ' || grund, '; ') from auswertung_index_entfernt));

  -- (e) das liest nur der Betriebsleiter
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_w::text, true);
  select count(*) into v_n from auswertung_index_entfernt;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  reset role;
  assert v_n = 0, '0119 (e1): die Halle liest, welche Indizes die Rechnung entfernt hat';

  -- aufräumen und den Stand ohne Prüfdaten wieder rechnen
  delete from sortier_gewicht where lauf_id in (911901, 911902);
  delete from sortier_lauf where id in (911901, 911902);
  delete from sortierschema where id in (911901, 911902);
  delete from auswertung_index_entfernt;
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  if v_geladen then perform demo_daten_entfernen(); end if;

  -- (f) Stand
  assert schema_stand() >= 119, format('0119 (f1): schema_stand() = %s', schema_stand());

  delete from profil where id in (v_u, v_w); delete from auth.users where id in (v_u, v_w);
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0119 — eine Charge mit Läufen in mehreren Sortierschemata rechnet durch, jedes Band für sich; erg_kaliber trägt die Bandgrenzen im Schlüssel, erg_ausschuss keinen falschen; ein Index, den die Daten nicht hergeben, wird entfernt und notiert, statt die Rechnung anzuhalten';
end $$;

select '——— 0119 Zwei Sortierschemata für eine Charge halten die Rechnung nicht an ———' as ergebnis;
