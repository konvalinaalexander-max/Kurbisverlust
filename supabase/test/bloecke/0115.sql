-- =====================================================================
-- 0115 — Das Kilo kommt aus der Menge; was Perigon nicht mehr sagt, ist
--        keine Lieferung mehr
--
-- Geprüft an gebauten Fällen (Prüffirmen PRUEF115, PRUEF115B) und auf den
-- Daten, die da sind:
-- (a) perigon_kg: Menge × Gewicht je Artikel; bei kg ohne Gewicht die
--     Menge, in jeder Schreibweise; Stück ohne Stückgewicht leer, nie 0;
--     eine Rücknahme bleibt negativ;
-- (b) ausgang_historie_uebernehmen rechnet so; v_kunde_tag zählt nur die
--     bekannte Masse und nennt die Stück ohne Gewicht; die Demo hat solche
--     Stück im Vorjahr (sonst sähe die Bildschirmprüfung den Hinweis nie);
-- (c) ausgang_uebernehmen: trägt Perigon die Charge nach, ersetzt die neue
--     Lieferung die alte „rest", statt neben ihr zu stehen; die Datei prüft
--     danach ohne Abweichung; Positionen ausserhalb der Datei, eine andere
--     Firma mit derselben Positionsnummer und Lieferungen von Hand bleiben;
--     ein zweites Einlesen ersetzt nichts mehr; ergibt eine Position keine
--     Lieferung mehr, geht auch ihre alte;
-- (d) die gespeicherten Zeilen und Positionen halten die Regel (die Demo
--     hat keine kg-Zeilen ohne Gewicht — auf den Daten des Betriebs geprüft:
--     443 Positionen, 13 Zeilen);
-- (e) Stand 115.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false; v_n int; v_ab int; v_j jsonb;
  v_u uuid := '00000000-0115-0000-0000-000000000001';
  v_charge int; v_sorte text; v_hand bigint; v_fremd bigint; v_andere int; v_k text;
  v_zeile_rest jsonb; v_zeile_502 jsonb; v_zeile_501 jsonb;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0115"}');
  update profil set rolle = 'admin' where id = v_u;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from auftrag where station = 'waschen_sortieren' and bemerkung = 'DEMO') then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform demo_vorjahre_laden();

  -- (a) Die Regel
  assert perigon_kg(160, 1.5, 'Stk.') = 240 and perigon_kg(5, 1, 'kg') = 5
     and perigon_kg(3, 10, 'kg') = 30 and perigon_kg(-344, 1, 'kg') = -344,
    '0115 (a1): Menge × Gewicht je Artikel stimmt nicht mehr';
  assert perigon_kg(256, 0, 'kg') = 256 and perigon_kg(256, null, ' KG ') = 256
     and perigon_kg(-12, 0, 'kg') = -12,
    format('0115 (a2): ein kg-Artikel ohne Gewicht je Artikel zählt %s (Einheit „kg") und %s (Einheit „ KG ") statt seiner Menge 256',
           perigon_kg(256, 0, 'kg'), perigon_kg(256, null, ' KG '));
  assert perigon_kg(7, 0, 'Stk.') is null and perigon_kg(12, null, '') is null and perigon_kg(null, 1, 'kg') is null,
    format('0115 (a3): Stück ohne Stückgewicht ist %s statt unbekannt', perigon_kg(7, 0, 'Stk.'));

  -- (b) Die Positionen aller Saisons
  insert into ausgang_quelle (code, name, dateiname_muster) values ('PRUEF115', 'Prüffirma 0115', 'PRUEF115')
  on conflict (code) do nothing;
  v_j := ausgang_historie_uebernehmen('PRUEF115',
    '[{"pos_id": 1, "datum": "2024-10-01", "journal": "A", "kunde": "Prüfkunde 115", "artikel_id": "kürbp115a", "artikel": "Bio-Kürbis Butternut Prüf", "einheit": "kg", "menge": 256, "gewicht_je_artikel": 0},
      {"pos_id": 2, "datum": "2024-10-02", "journal": "A", "kunde": "Prüfkunde 115", "artikel_id": "kürbp115b", "artikel": "Bio Kürbis Muscade Prüf klein", "einheit": "Stk.", "menge": 120, "gewicht_je_artikel": 0},
      {"pos_id": 3, "datum": "2024-10-03", "journal": "A", "kunde": "Prüfkunde 115", "artikel_id": "kürbp115c", "artikel": "Bio Kürbis Knirps Prüf", "einheit": "Stk.", "menge": 10, "gewicht_je_artikel": 0.85},
      {"pos_id": 4, "datum": "2024-10-04", "journal": "A", "kunde": "Prüfkunde 115", "artikel_id": "kürbp115a", "artikel": "Bio-Kürbis Butternut Prüf", "einheit": "KG", "menge": 50}]'::jsonb);
  assert (v_j ->> 'positionen')::int = 4, format('0115 (b1): vier Positionen erwartet: %s', v_j);
  select count(*) filter (where p.pos_id is null or p.kg is distinct from x.kg) into v_ab
    from (values (1, 256.0), (2, null), (3, 8.5), (4, 50.0)) x(pos_id, kg)
    left join ausgang_position p on p.quelle = 'PRUEF115' and p.pos_id = x.pos_id;
  assert v_ab = 0,
    format('0115 (b2): %s Positionen falsch — Butternut kg ohne Gewicht %s (soll 256), Muscade Stück ohne Gewicht %s (soll leer), Knirps %s (soll 8.5), Butternut ohne Feld %s (soll 50)',
           v_ab, (select kg from ausgang_position where quelle = 'PRUEF115' and pos_id = 1),
           coalesce((select kg from ausgang_position where quelle = 'PRUEF115' and pos_id = 2)::text, 'leer'),
           (select kg from ausgang_position where quelle = 'PRUEF115' and pos_id = 3),
           (select kg from ausgang_position where quelle = 'PRUEF115' and pos_id = 4));
  -- der Vergleich je Kunde: bekannte Masse, und die Stück ohne Gewicht stehen da
  assert (select sum(kg) from v_kunde_tag where kunde = 'Prüfkunde 115' and saison = 2024) = 314.5
     and (select sum(stueck_ohne_gewicht) from v_kunde_tag where kunde = 'Prüfkunde 115' and saison = 2024) = 120
     and (select sum(positionen_ohne_gewicht) from v_kunde_tag where kunde = 'Prüfkunde 115' and saison = 2024) = 1
     and (select sum(positionen) from v_kunde_tag where kunde = 'Prüfkunde 115' and saison = 2024) = 4,
    format('0115 (b3): Prüfkunde 115 hat 2024 %s kg, %s Stück ohne Gewicht in %s Positionen von %s — erwartet 314.5 kg, 120 Stück, 1 von 4',
           (select sum(kg) from v_kunde_tag where kunde = 'Prüfkunde 115' and saison = 2024),
           (select sum(stueck_ohne_gewicht) from v_kunde_tag where kunde = 'Prüfkunde 115' and saison = 2024),
           (select sum(positionen_ohne_gewicht) from v_kunde_tag where kunde = 'Prüfkunde 115' and saison = 2024),
           (select sum(positionen) from v_kunde_tag where kunde = 'Prüfkunde 115' and saison = 2024));
  -- wo es kein Stück ohne Gewicht gibt, steht auch keins
  assert not exists (select 1 from v_kunde_tag where (stueck_ohne_gewicht is null) <> (positionen_ohne_gewicht = 0)),
    '0115 (b4): Stück ohne Gewicht und Positionen ohne Gewicht sagen Verschiedenes';
  -- die Demo: ein Kunde mit Stück ohne Gewicht im Vorjahr, kg leer, nicht 0
  select count(*) into v_n from ausgang_position where quelle = 'DEMO' and einheit = 'Stk.' and coalesce(gewicht_je_artikel, 0) = 0;
  assert v_n >= 3 and not exists (select 1 from ausgang_position where quelle = 'DEMO' and einheit = 'Stk.'
                                                                    and coalesce(gewicht_je_artikel, 0) = 0 and kg is not null)
     and (select sum(stueck_ohne_gewicht) from v_kunde_tag where saison < saison_von(heute())) > 0,
    format('0115 (b5): die Demo hat %s Stück-Positionen ohne Gewicht im Vorjahr (mindestens 3, kg leer) — die Bildschirmprüfung sähe den Hinweis nicht', v_n);

  -- (c) Charge nachgetragen: die neue Lieferung ersetzt die alte
  select c.nr, c.sorte into v_charge, v_sorte
    from charge c join sorte_kaliber s on s.sorte = c.sorte order by c.nr limit 1;
  assert v_charge is not null, '0115 (c0): keine Charge mit bestätigter Sorte — (c) wäre blind';
  v_zeile_rest := jsonb_build_object('pos_id', 501, 'charge_extern', '', 'lauf_nr', 1, 'fingerabdruck', 'p115-501-a',
    'datum', '2026-10-01', 'journal', 'A', 'kunde', 'Prüfkunde 115', 'artikel_id', 'kürbp115a', 'artikel', 'Bio-Kürbis Butternut Prüf',
    'einheit', 'kg', 'menge', 300, 'gewicht_je_artikel', 0, 'batch_menge', 0, 'kg_position', 300, 'kg_charge', 0);
  v_zeile_502 := jsonb_build_object('pos_id', 502, 'charge_extern', v_charge::text, 'lauf_nr', 1, 'fingerabdruck', 'p115-502-a',
    'datum', '2026-10-01', 'journal', 'A', 'kunde', 'Prüfkunde 115', 'artikel_id', 'kürbp115a', 'artikel', 'Bio-Kürbis Butternut Prüf',
    'einheit', 'kg', 'menge', 100, 'gewicht_je_artikel', 1, 'batch_menge', 100, 'kg_position', 100, 'kg_charge', 100);
  v_j := ausgang_uebernehmen('PRUEF115', 'Prüffirma 0115', '{"dateiname": "p115-1.xlsx", "pruefsumme": "p115-1"}'::jsonb,
    jsonb_build_array(v_zeile_rest, v_zeile_502),
    jsonb_build_array(
      jsonb_build_object('extern_id', 'PRUEF115:501:rest', 'datum', '2026-10-01', 'charge_nr', null, 'sorte', v_sorte, 'kg', 300, 'kunde', 'Prüfkunde 115'),
      jsonb_build_object('extern_id', format('PRUEF115:502:%s:1', v_charge), 'datum', '2026-10-01', 'charge_nr', v_charge, 'sorte', v_sorte, 'kg', 100, 'kunde', 'Prüfkunde 115')));
  assert (v_j ->> 'lieferungen_neu')::int = 2 and (v_j ->> 'lieferungen_ersetzt')::int = 0,
    format('0115 (c1): das erste Einlesen soll zwei Lieferungen anlegen und nichts ersetzen: %s', v_j);
  -- daneben: eine andere Firma mit derselben Positionsnummer, eine Lieferung von Hand
  insert into ausgang_quelle (code, name, dateiname_muster) values ('PRUEF115B', 'Prüffirma 0115 B', 'PRUEF115B')
  on conflict (code) do nothing;
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde) values ('2026-10-01', null, v_sorte, 70, 'verkauf', 'Prüfkunde 115')
  returning id into v_fremd;
  insert into lieferung_import (lieferung_id, quelle, extern_id) values (v_fremd, 'PRUEF115B', 'PRUEF115B:501:rest');
  insert into lieferung (datum, charge_nr, sorte, kg, ziel, kunde, bemerkung)
  values ('2026-10-01', v_charge, v_sorte, 40, 'verkauf', 'Prüfkunde 115', 'Prüf-0115 von Hand')
  returning id into v_hand;
  select count(*) into v_andere from lieferung l
   where not exists (select 1 from lieferung_import i where i.lieferung_id = l.id and i.quelle = 'PRUEF115');

  -- Perigon trägt die Charge nach: Position 501 hat jetzt eine Chargenzeile;
  -- Position 502 steht in dieser Datei nicht.
  v_zeile_501 := jsonb_build_object('pos_id', 501, 'charge_extern', v_charge::text, 'lauf_nr', 1, 'fingerabdruck', 'p115-501-b',
    'datum', '2026-10-01', 'journal', 'A', 'kunde', 'Prüfkunde 115', 'artikel_id', 'kürbp115a', 'artikel', 'Bio-Kürbis Butternut Prüf',
    'einheit', 'kg', 'menge', 300, 'gewicht_je_artikel', 0, 'batch_menge', 300, 'kg_position', 300, 'kg_charge', 300);
  for v_n in 1 .. 2 loop
    v_j := ausgang_uebernehmen('PRUEF115', 'Prüffirma 0115', jsonb_build_object('dateiname', 'p115-2.xlsx', 'pruefsumme', 'p115-2'),
      jsonb_build_array(v_zeile_501),
      jsonb_build_array(jsonb_build_object('extern_id', format('PRUEF115:501:%s:1', v_charge), 'datum', '2026-10-01',
                                           'charge_nr', v_charge, 'sorte', v_sorte, 'kg', 300, 'kunde', 'Prüfkunde 115')));
    if v_n = 1 then
      assert (v_j ->> 'lieferungen_neu')::int = 1 and (v_j ->> 'lieferungen_ersetzt')::int = 1,
        format('0115 (c2): die nachgetragene Charge soll eine Lieferung anlegen und die alte „rest" ersetzen: %s', v_j);
    else
      assert (v_j ->> 'lieferungen_neu')::int = 0 and (v_j ->> 'lieferungen_aktualisiert')::int = 1
         and (v_j ->> 'lieferungen_ersetzt')::int = 0,
        format('0115 (c3): dieselbe Datei ein zweites Mal soll nichts ersetzen: %s', v_j);
    end if;
  end loop;
  assert not exists (select 1 from lieferung_import where extern_id = 'PRUEF115:501:rest')
     and exists (select 1 from lieferung_import where extern_id = format('PRUEF115:501:%s:1', v_charge))
     and (select sum(l.kg) from lieferung l join lieferung_import i on i.lieferung_id = l.id
           where i.quelle = 'PRUEF115' and split_part(i.extern_id, ':', 2) = '501') = 300,
    format('0115 (c4): Position 501 hat %s kg Lieferungen statt 300 — die alte ohne Charge steht noch daneben',
           (select sum(l.kg) from lieferung l join lieferung_import i on i.lieferung_id = l.id
             where i.quelle = 'PRUEF115' and split_part(i.extern_id, ':', 2) = '501'));
  assert not exists (select 1 from v_ausgang_pruef where quelle = 'PRUEF115'),
    format('0115 (c5): nach dem zweiten Einlesen prüft die Datei mit Abweichung: %s',
           (select string_agg(format('Pos. %s: Datei %s kg, Lieferungen %s kg', pos_id, kg_datei, kg_lieferung), '; ')
              from v_ausgang_pruef where quelle = 'PRUEF115'));
  assert exists (select 1 from lieferung_import where extern_id = format('PRUEF115:502:%s:1', v_charge)),
    '0115 (c6): eine Position, die nicht in der Datei steht, verlor ihre Lieferung';
  assert exists (select 1 from lieferung where id = v_fremd) and exists (select 1 from lieferung where id = v_hand)
     and (select count(*) from lieferung l
           where not exists (select 1 from lieferung_import i where i.lieferung_id = l.id and i.quelle = 'PRUEF115')) = v_andere,
    '0115 (c7): das Einlesen einer Firma hat Lieferungen einer anderen Firma oder von Hand entfernt';
  -- Position 502 steht wieder in der Datei, ergibt aber keine Lieferung mehr
  -- (etwa: Gewicht im Artikelstamm entfernt) — dann geht auch die alte.
  v_j := ausgang_uebernehmen('PRUEF115', 'Prüffirma 0115', '{"dateiname": "p115-3.xlsx", "pruefsumme": "p115-3"}'::jsonb,
    jsonb_build_array(v_zeile_502), '[]'::jsonb);
  assert (v_j ->> 'lieferungen_ersetzt')::int = 1
     and not exists (select 1 from lieferung_import where extern_id = format('PRUEF115:502:%s:1', v_charge))
     and exists (select 1 from lieferung_import where extern_id = format('PRUEF115:501:%s:1', v_charge)),
    format('0115 (c8): eine Position ohne Lieferung in der Datei behielt ihre alte, oder eine andere ging mit: %s', v_j);

  -- (d) Was gespeichert ist, hält die Regel
  select count(*) into v_ab from ausgang_zeile
   where coalesce(gewicht_je_artikel, 0) = 0
     and (kg_position is distinct from perigon_kg(coalesce(menge, 0), gewicht_je_artikel, einheit)
          or kg_charge is distinct from perigon_kg(coalesce(batch_menge, 0), gewicht_je_artikel, einheit));
  select count(*) into v_n from ausgang_position
   where coalesce(gewicht_je_artikel, 0) = 0 and kg is distinct from perigon_kg(coalesce(menge, 0), gewicht_je_artikel, einheit);
  assert v_ab = 0 and v_n = 0,
    format('0115 (d1): %s Zeilen und %s Positionen ohne Gewicht je Artikel tragen eine Masse, die nicht der Regel folgt (0 statt der Menge?)', v_ab, v_n);

  -- (e) Stand
  assert schema_stand() >= 115, format('0115 (e1): schema_stand() = %s', schema_stand());

  -- aufräumen
  delete from lieferung where id in (select lieferung_id from lieferung_import where quelle in ('PRUEF115', 'PRUEF115B'));
  delete from lieferung where id = v_hand;
  delete from ausgang_zeile where quelle = 'PRUEF115';
  delete from ausgang_datei where quelle = 'PRUEF115';
  delete from ausgang_quelle where code in ('PRUEF115', 'PRUEF115B');
  if v_geladen then perform demo_daten_entfernen(); end if;
  delete from profil where id = v_u; delete from auth.users where id = v_u;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0115 — kg-Artikel ohne Gewicht je Artikel zählen ihre Menge, Stück ohne Stückgewicht sind unbekannt (nicht 0) und stehen im Vergleich je Kunde da; trägt Perigon eine Charge nach, ersetzt die neue Lieferung die alte, statt doppelt zu zählen';
end $$;

select '——— 0115 Das Kilo kommt aus der Menge; was Perigon nicht mehr sagt, ist keine Lieferung mehr ———' as ergebnis;
