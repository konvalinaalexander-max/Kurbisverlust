-- =====================================================================
-- 0121 — Die Palette geht mit ihrer Arbeit; was im Lager liegt; Ware ohne Charge
--
-- Nachgestellt wie bei Rüegg (1625/1627): Charge A hat am 23.9. fünf
-- G2-Paletten und am 10.9. eine; Charge B (selber Schlag) hat keinen
-- Eingang, aber eine Arbeit, deren Zettel aufs Kilo zu vier der fünf passen,
-- und 1.5 t Lieferungen. Dazu Charge C (selber Schlag) mit einer Arbeit, bei
-- der nur die Hälfte der Zettel passt, und Charge D mit eigenem Eingang, die
-- nicht mehr lieferte, als sie bekam.
-- (a) Der Rechenlauf (Schritt 1) bucht die vier Paletten mit Zettel und die
--     fünfte der Fuhre zu B; das Journal bleibt bei A (charge_nr_journal).
-- (b) Die Palette vom 10.9., die eine Arbeit von A selbst gezählt hat, geht
--     nirgends hin, obwohl auch ein Zettel von B auf sie passt.
-- (c) Halber Beleg (C) bleibt Vorschlag; nichts umgebucht.
-- (d) Eine Charge, die nicht überliefert ist (D), bekommt nichts — Vorschlag.
-- (e) Ein Abgleich mit dem Journal überschreibt die Umbuchung nicht; nennt
--     das Journal eine andere Charge, gilt das Journal.
-- (f) Zurückgenommen bleibt zurückgenommen, auch nach dem nächsten Lauf;
--     die Halle darf nicht umbuchen.
-- (g) v_lager_ausweis: die Kette geht auf; mit Hagel h ist Unique =
--     gute Ware · h/(1−h) und Faules + Unique = Faules der Kaskade.
-- (h) v_ohne_charge: die Summe stimmt, vor dem Eingang wird erkannt.
-- (j) Ein Lieferschein, dessen Nummer die App beim Einlesen nicht kannte,
--     bekommt seine Charge beim nächsten Rechenlauf — über die eigene Nummer
--     oder eine Perigon-Nummer an genau einer Charge; an zweien bleibt er
--     ohne, und der Rest ohne Charge auch.
-- (i) Stand 121.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false;
  v_u uuid := '00000000-0121-0000-0000-000000000001';
  v_w uuid := '00000000-0121-0000-0000-000000000002';
  v_sorte text; v_sorten text[]; v_s int; v_n int; v_x record; v_fehler text; v_hc int; v_h_alt numeric;
  v_a int := 99121; v_b int := 99122; v_c int := 99123; v_d int := 99124;
  v_w0 bigint; v_w1 bigint; v_w2 bigint; v_w4 bigint; v_l bigint; v_z bigint; v_quelle text;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0121"}');
  update profil set rolle = 'admin' where id = v_u;
  insert into auth.users (id, email, raw_user_meta_data) values (v_w, null, '{"name":"Prüf-0121 Halle"}');
  update profil set rolle = 'arbeiter' where id = v_w;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from sortier_lauf) then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  -- Ein Schlag, vier Sorten (eine Charge je Schlag, Sorte und Saison)
  select array_agg(sorte order by sorte) into v_sorten from (select sorte from sorte_kaliber order by sorte limit 4) x;
  v_sorte := v_sorten[1];

  insert into charge (nr, schlag, sorte, saison) values
    (v_a, 'Prüf-0121', v_sorten[1], 2026), (v_b, 'Prüf-0121', v_sorten[2], 2026),
    (v_c, 'Prüf-0121', v_sorten[3], 2026), (v_d, 'Prüf-0121', v_sorten[4], 2026);
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id, quelle) values
    (v_a, date '2026-09-23', 448, 32, 'G2', 'pruef-0121-a1', 'journal-import'),
    (v_a, date '2026-09-23', 444, 32, 'G2', 'pruef-0121-a2', 'journal-import'),
    (v_a, date '2026-09-23', 433, 32, 'G2', 'pruef-0121-a3', 'journal-import'),
    (v_a, date '2026-09-23', 380, 30, 'G2', 'pruef-0121-a4', 'journal-import'),
    (v_a, date '2026-09-23', 340, 30, 'G2', 'pruef-0121-a5', 'journal-import'),
    (v_a, date '2026-09-10', 501, 32, 'G2', 'pruef-0121-a6', 'journal-import'),
    (v_a, date '2026-09-15', 611, 32, 'G2', 'pruef-0121-a7', 'journal-import'),
    (v_a, date '2026-09-15', 622, 32, 'G2', 'pruef-0121-a8', 'journal-import'),
    (v_a, date '2026-09-01', 701, 32, 'G2', 'pruef-0121-a9', 'journal-import'),
    (v_a, date '2026-09-01', 712, 32, 'G2', 'pruef-0121-a10', 'journal-import'),
    (v_a, date '2026-09-01', 723, 32, 'G2', 'pruef-0121-a11', 'journal-import'),
    (v_d, date '2026-09-01', 905, 32, 'G2', 'pruef-0121-d1', 'journal-import'),
    (v_d, date '2026-09-01', 906, 32, 'G2', 'pruef-0121-d2', 'journal-import');
  -- Die Arbeit von A selbst, die die Palette vom 10.9. zählt
  insert into auftrag (weg, station, charge_nr, start_ts, status) values ('hand', 'waschen_sortieren', v_a, timestamptz '2026-09-20 08:00+02', 'abgeschlossen') returning id into v_w0;
  insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg, kisten, gebindeart) values (v_w0, date '2026-09-10', 501, 32, 'G2');
  -- Die Arbeit auf B: vier Zettel passen zu A vom 23.9. (einen Tag früher datiert), einer zur Palette vom 10.9.
  insert into auftrag (weg, station, charge_nr, start_ts, status) values ('hand', 'waschen_sortieren', v_b, timestamptz '2026-10-01 13:00+02', 'abgeschlossen') returning id into v_w1;
  insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg, kisten, gebindeart) values
    (v_w1, date '2026-09-22', 448, 36, 'G2'), (v_w1, date '2026-09-22', 444, 36, 'G2'),
    (v_w1, date '2026-09-22', 433, 36, 'G2'), (v_w1, date '2026-09-22', 380, 33, 'G2'),
    (v_w1, date '2026-09-10', 501, 32, 'G2');
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (date '2026-10-02', v_b, v_sorten[2], 1500, 'verkauf');
  -- Die Arbeit auf C: zwei von vier Zetteln passen
  insert into auftrag (weg, station, charge_nr, start_ts, status) values ('hand', 'waschen_sortieren', v_c, timestamptz '2026-10-03 13:00+02', 'abgeschlossen') returning id into v_w2;
  insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg, kisten, gebindeart) values
    (v_w2, date '2026-09-15', 611, 32, 'G2'), (v_w2, date '2026-09-15', 622, 32, 'G2'),
    (v_w2, date '2026-09-15', 997, 32, 'G2'), (v_w2, date '2026-09-15', 998, 32, 'G2');
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (date '2026-10-04', v_c, v_sorten[3], 900, 'verkauf');
  -- Die Arbeit auf D: alle drei Zettel passen zu A, aber D lieferte nichts
  insert into auftrag (weg, station, charge_nr, start_ts, status) values ('hand', 'waschen_sortieren', v_d, timestamptz '2026-10-05 13:00+02', 'abgeschlossen') returning id into v_w4;
  insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg, kisten, gebindeart) values
    (v_w4, date '2026-09-01', 701, 32, 'G2'), (v_w4, date '2026-09-01', 712, 32, 'G2'), (v_w4, date '2026-09-01', 723, 32, 'G2');

  -- (a) Schritt 1 des Rechenlaufs ordnet zu
  update auswertung_stand set rechnet_seit = null where id = 1;
  perform auswertung_schritt_intern(1, false);
  update auswertung_stand set rechnet_seit = null where id = 1;
  select count(*) into v_n from palette where extern_id in ('pruef-0121-a1', 'pruef-0121-a2', 'pruef-0121-a3', 'pruef-0121-a4') and charge_nr = v_b and charge_nr_journal = v_a;
  assert v_n = 4, format('0121 (a1): %s von 4 Paletten mit passendem Zettel liegen bei B (Journal A)', v_n);
  assert (select charge_nr from palette where extern_id = 'pruef-0121-a5') = v_b
     and (select art from palette_zuordnung z join palette p on p.id = z.palette_id where p.extern_id = 'pruef-0121-a5') = 'fuhre',
    '0121 (a2): die fünfte Palette der Fuhre (80 % in der Arbeit) ging nicht mit';
  assert (select count(*) from palette_zuordnung z join palette p on p.id = z.palette_id where p.charge_nr_journal = v_a and z.nach_charge_nr = v_b and z.stand = 'angewandt' and z.auftrag_id = v_w1) = 5,
    '0121 (a3): die Umbuchung steht nicht fünfmal als angewandt mit ihrer Arbeit da';
  -- (b) die eigene Palette bleibt
  assert (select charge_nr from palette where extern_id = 'pruef-0121-a6') = v_a
     and not exists (select 1 from palette_zuordnung z join palette p on p.id = z.palette_id where p.extern_id = 'pruef-0121-a6'),
    '0121 (b1): die Palette, die eine Arbeit ihrer eigenen Charge gezählt hat, wurde umgebucht';
  -- (c) halber Beleg: Vorschlag
  assert (select count(*) from palette_zuordnung z join palette p on p.id = z.palette_id where z.nach_charge_nr = v_c and z.stand = 'vorschlag') = 2
     and (select count(*) from palette where extern_id in ('pruef-0121-a7', 'pruef-0121-a8') and charge_nr = v_a) = 2,
    '0121 (c1): zwei von vier Zetteln haben umgebucht oder stehen nicht als Vorschlag da';
  -- (d) nicht überliefert: Vorschlag
  assert (select count(*) from palette_zuordnung z where z.nach_charge_nr = v_d and z.stand = 'vorschlag') = 3
     and (select count(*) from palette where extern_id in ('pruef-0121-a9', 'pruef-0121-a10', 'pruef-0121-a11') and charge_nr = v_a) = 3,
    '0121 (d1): eine Charge, die nicht mehr lieferte, als sie bekam, hat Paletten bekommen';
  -- noch einmal: nichts ändert sich
  select paletten_zuordnen() into v_n;
  assert v_n = 0, format('0121 (a4): ein zweiter Lauf ändert %s Paletten', v_n);

  -- (e) Abgleich mit dem Journal (Upsert wie unter Stammdaten)
  insert into palette (charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart, extern_id, quelle)
  values (v_a, date '2026-09-23', 448, 32, 'G2', 'pruef-0121-a1', 'journal-import')
  on conflict (extern_id) do update set charge_nr = excluded.charge_nr, brutto_kg = excluded.brutto_kg, kisten = excluded.kisten;
  assert (select (charge_nr, charge_nr_journal) = (v_b, v_a) from palette where extern_id = 'pruef-0121-a1'),
    '0121 (e1): der Abgleich mit dem Journal hat die Umbuchung überschrieben';
  update palette set charge_nr = v_d where extern_id = 'pruef-0121-a1';
  assert (select (charge_nr, charge_nr_journal) = (v_d, v_d) from palette where extern_id = 'pruef-0121-a1'),
    '0121 (e2): das Journal nennt eine andere Charge, gerechnet wird aber weiter mit der Umbuchung';
  update palette set charge_nr = v_a where extern_id = 'pruef-0121-a1';
  assert (select charge_nr from palette where extern_id = 'pruef-0121-a1') = v_b,
    '0121 (e3): zurück auf die alte Charge im Journal, und die Umbuchung gilt nicht mehr';

  -- (f) zurücknehmen — nur der Betriebsleiter, und es bleibt
  perform set_config('request.jwt.claim.sub', v_w::text, true);
  begin
    perform palette_zuordnung_setzen(array(select palette_id from palette_zuordnung where nach_charge_nr = v_b), 'zurueckgenommen');
  exception when insufficient_privilege then v_fehler := 'verweigert';
  end;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  assert v_fehler = 'verweigert', '0121 (f1): die Halle durfte eine Umbuchung zurücknehmen';
  perform palette_zuordnung_setzen(array(select palette_id from palette_zuordnung where nach_charge_nr = v_b), 'zurueckgenommen');
  assert (select count(*) from palette where extern_id like 'pruef-0121-a%' and charge_nr = v_b) = 0,
    '0121 (f2): zurückgenommen, aber die Paletten liegen noch bei B';
  perform paletten_zuordnen();
  assert (select count(*) from palette where extern_id like 'pruef-0121-a%' and charge_nr = v_b) = 0
     and (select count(*) from palette_zuordnung where nach_charge_nr = v_b and stand = 'zurueckgenommen') = 5,
    '0121 (f3): die Regel hat eine zurückgenommene Umbuchung wieder angelegt';

  -- (g) der Lager-Ausweis geht auf — und mit Hagel
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  for v_x in select * from v_lager_ausweis where eingang_kg > 0 and verkaufsfaehig_kg is not null and faul_kg is not null loop
    assert abs(v_x.eingang_kg - (v_x.verdunstet_kg + v_x.faul_kg + coalesce(v_x.unique_kg, 0) + v_x.zu_klein_kg + v_x.zu_gross_kg
                                  + coalesce(v_x.fax_kg, 0) + v_x.verkaufsfaehig_kg)) < 0.1,
      format('0121 (g1): bei Charge %s geht die Kette nicht auf: %s', v_x.charge_nr, row_to_json(v_x));
  end loop;
  select k.charge_nr into v_hc from mv_kaskade k
   where k.portion = 'lager' and k.m0 > 0 and not k.f_eigen
     and exists (select 1 from erg_prognose p where p.gruppe = 'charge' and p.schluessel = k.charge_nr::text and p.h = 0 and p.gute_ware_kg > 0)
   order by k.charge_nr limit 1;
  assert v_hc is not null, '0121 (g2, vorab): keine Charge mit Ware ohne eigene Palox-Messung';
  select hagel_anteil into v_h_alt from charge where nr = v_hc;
  update charge set hagel_anteil = 0.25 where nr = v_hc;
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  select a.unique_kg, a.faul_kg, p.gute_ware_kg, p.faul_kg as faul_kaskade into v_x
    from v_lager_ausweis a join erg_prognose p on p.gruppe = 'charge' and p.schluessel = a.charge_nr::text and p.h = 0
   where a.charge_nr = v_hc;
  assert abs(v_x.unique_kg - v_x.gute_ware_kg * 0.25 / 0.75) < 0.05 and v_x.unique_kg > 0,
    format('0121 (g2): Unique ist nicht gute Ware · h/(1−h): %s', row_to_json(v_x));
  assert abs(v_x.faul_kg + v_x.unique_kg - v_x.faul_kaskade) < 0.05,
    format('0121 (g3): Faules + Unique ist nicht das Faule der Kaskade: %s', row_to_json(v_x));
  update charge set hagel_anteil = v_h_alt where nr = v_hc;

  -- (h) Ware ohne Charge
  insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (date '2026-01-05', null, v_sorte, 300, 'verkauf');
  select * into v_x from v_ohne_charge where sorte = v_sorte;
  assert v_x.kg >= 300 and abs(v_x.kg - v_x.kg_ohne_ziel - coalesce((select sum((e->>'kg')::numeric) from jsonb_array_elements(v_x.verteilt_auf) e), 0)) < 1,
    format('0121 (h1): verteilt + ohne Ziel ist nicht die Masse ohne Charge: %s', row_to_json(v_x));
  assert v_x.kg_vor_eingang >= 299,
    format('0121 (h2): eine Lieferung vom 5.1. ging vor jedem Eingang hinaus, aber kg_vor_eingang = %s', v_x.kg_vor_eingang);

  -- (j) Nummern, die die App beim Einlesen nicht kannte
  select code into v_quelle from ausgang_quelle order by code limit 1;
  for v_x in select * from (values (1, '99125', false), (2, 'Ch. 991260', false), (3, '991270', false), (4, '99125', true)) t(n, nummer, rest) loop
    insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, artikel_id, artikel, kg_charge)
    values (v_quelle, 9912100 + v_x.n, v_x.nummer, 1, format('pruef-0121-%s', v_x.n), date '2026-10-10', 'P0121', 'Prüfartikel', 100)
    returning id into v_z;
    insert into lieferung (datum, charge_nr, sorte, kg, ziel) values (date '2026-10-10', null, v_sorten[4], 100, 'verkauf') returning id into v_l;
    insert into lieferung_import (lieferung_id, quelle, extern_id, zeile_id)
    values (v_l, v_quelle, format('%s:%s:pruef-0121%s', v_quelle, 9912100 + v_x.n, case when v_x.rest then ':rest' else '' end), v_z);
  end loop;
  -- erst jetzt kommen die Chargen ins Register
  insert into charge (nr, schlag, sorte, saison, perigon_nr) values
    (99125, 'Prüf-0121 j', v_sorten[1], 2026, null), (99126, 'Prüf-0121 j', v_sorten[2], 2026, 991260),
    (99127, 'Prüf-0121 j', v_sorten[3], 2026, 991270), (99128, 'Prüf-0121 j', v_sorten[4], 2026, 991270);
  update auswertung_stand set rechnet_seit = null where id = 1;
  perform auswertung_schritt_intern(1, false);
  update auswertung_stand set rechnet_seit = null where id = 1;
  select string_agg(format('%s→%s', z.charge_extern || case when li.extern_id like '%:rest' then ' (Rest)' else '' end, coalesce(l.charge_nr::text, '–')), ', ' order by z.pos_id)
    into v_fehler
    from lieferung_import li join lieferung l on l.id = li.lieferung_id join ausgang_zeile z on z.id = li.zeile_id
   where z.fingerabdruck like 'pruef-0121-%';
  assert v_fehler = '99125→99125, Ch. 991260→99126, 991270→–, 99125 (Rest)→–',
    format('0121 (j1): nachgeordnet wurde %s', v_fehler);
  assert (select sorte from lieferung l join lieferung_import li on li.lieferung_id = l.id join ausgang_zeile z on z.id = li.zeile_id
           where z.fingerabdruck = 'pruef-0121-2') = v_sorten[2],
    '0121 (j2): der nachgeordnete Lieferschein trägt nicht die Sorte seiner Charge';
  delete from lieferung where id in (select li.lieferung_id from lieferung_import li join ausgang_zeile z on z.id = li.zeile_id where z.fingerabdruck like 'pruef-0121-%');
  delete from ausgang_zeile where fingerabdruck like 'pruef-0121-%';
  delete from charge where nr in (99125, 99126, 99127, 99128);

  -- aufräumen und den Stand ohne Prüfdaten wieder rechnen
  delete from lieferung where charge_nr in (v_a, v_b, v_c, v_d) or (charge_nr is null and datum = date '2026-01-05' and kg = 300);
  delete from auftrag_palette where auftrag_id in (v_w0, v_w1, v_w2, v_w4);
  delete from auftrag where id in (v_w0, v_w1, v_w2, v_w4);
  delete from palette where extern_id like 'pruef-0121-%';
  delete from charge where nr in (v_a, v_b, v_c, v_d);
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  if v_geladen then perform demo_daten_entfernen(); end if;

  -- (i) Stand
  assert schema_stand() >= 121, format('0121 (i1): schema_stand() = %s', schema_stand());

  delete from profil where id in (v_u, v_w); delete from auth.users where id in (v_u, v_w);
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0121 — eine Palette geht mit Beleg zur Charge ihrer Arbeit (Zettel aufs Kilo, 80 %%, die Charge der Arbeit überliefert; der Rest einer Fuhre mit), sonst bleibt es Vorschlag; das Journal bleibt stehen und gilt, wenn es berichtigt wird; zurückgenommen bleibt zurückgenommen; der Lager-Ausweis geht auf und trennt den Hagel als Unique ab; Ware ohne Charge zeigt, was vor dem Eingang hinausging; ein Lieferschein bekommt seine Charge, sobald die App sie kennt';
end $$;

select '——— 0121 Die Palette geht mit ihrer Arbeit ———' as ergebnis;
