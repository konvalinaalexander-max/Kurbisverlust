-- =====================================================================
-- 0112 — Das Lager nach Artikel
--
-- Geprüft auf der Demo (mit ihren zwei Vorjahren) und an gebauten Fällen:
-- (a) einen Verkaufsartikel einordnen (Gruppe, Grösse, Label), Kürbis oder
--     nicht, die Saison vom 1. Juli an;
-- (b) ausgang_historie_uebernehmen: jede Position einmal, alle Saisons,
--     wiederholbar; die Labels an den Zeilen; nur der Betriebsleiter;
--     v_verkauf_position zählt keine Position doppelt;
-- (c) Artikelgruppe je Sorte und Label je Charge: Stammdaten vor Perigon,
--     Perigon nach der Mehrheit, CH-K ist Knospe;
-- (d) artikel_lager(h): dieselbe Masse wie das Verkaufsfähige, je Charge
--     nach den Artikelkalibern geteilt (nachgerechnet), Stück und Kisten;
--     ohne CSV und ohne Artikelgruppe geht nichts verloren;
-- (e) v_kunde_tag: nur Kürbis, ohne Journal L, je Kunde und Saison;
-- (f) die Demo: zwei Vorjahre, Labels, wiederholbar, mit der Demo weg;
-- (g) Stand 112, und die zwei Gebinde aus der Halle.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false; v_n int; v_ab int; v_x int;
  v_j jsonb; v_t text;
  v_u uuid := '00000000-0112-0000-0000-000000000001';
  v_w uuid := '00000000-0112-0000-0000-000000000002';
  v_sorte text; v_charge int; v_alt text;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0112"}');
  insert into auth.users (id, email, raw_user_meta_data) values (v_w, null, '{"name":"Prüf-0112-Halle"}');
  update profil set rolle = 'admin' where id = v_u;
  -- In der Beispieldatenbank wird jedes neue Konto Betriebsleiter (0081) — dieses nicht.
  update profil set rolle = 'arbeiter' where id = v_w;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from auftrag where station = 'waschen_sortieren' and bemerkung = 'DEMO') then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform demo_vorjahre_laden();
  perform auswertung_aktualisieren();

  -- (a) Einordnen
  select count(*) filter (where (e.gruppe, e.groesse, e.label) is distinct from (f.gruppe, f.groesse, f.label))
    into v_ab
    from (values ('Bio Kürbis Knirps Demeter gros', null, 'Knirps', 'gross', 'D'),
                 ('Bio Kürbis Muscat/Butterkin Dem klein', null, 'Butterkin/Muskat', 'klein', 'D'),
                 ('Bio-Kürbis roter Knirps Knospe', 'K', 'Knirps', 'lose', 'K'),
                 ('Bio-Kürbis roter Knirps Knospe klein', 'K', 'Knirps', 'klein', 'K'),
                 ('Bio Kürbis Butternut lose', 'D', 'Butternut', 'lose', 'D'),
                 ('Bio-Kürbis Butterkin', 'Kz', 'Butterkin/Muskat', 'lose', 'K'),
                 ('Bio-Kurbis Muskat Demeter', 'D', 'Butterkin/Muskat', 'lose', 'D'),
                 ('Bio Kürbis Kabocha gross', null, 'Kabocha', 'gross', null),
                 ('Bio Kürbis Mandarin Dem', null, 'Mandarin', 'lose', 'D'),
                 ('Bio Kürbis Mix OS', null, 'Mix', 'lose', null),
                 ('Bio-Kürbis Potimarron', 'D', 'Knirps', 'lose', 'D'),
                 ('Bio-Kürbis ganz', 'SG', 'andere', 'lose', null),
                 ('Tomaten rund', 'D', null, 'lose', 'D')) f(artikel, pg, gruppe, groesse, label)
   cross join lateral artikel_einordnen(f.artikel, f.pg) e;
  assert v_ab = 0, format('0112 (a1): %s Artikel falsch eingeordnet', v_ab);
  assert ist_kuerbis_vorschlag('kürbbu', 'Bio-Kürbis Butternut')
     and not ist_kuerbis_vorschlag('kürbver', 'Kürbisverrechnung')
     and not ist_kuerbis_vorschlag('arb', 'Arbeit Kürbisernte')
     and not ist_kuerbis_vorschlag('tom', 'Tomaten rund'),
    '0112 (a2): Kürbis oder nicht — falsch geraten';
  assert saison_von(date '2026-06-30') = 2025 and saison_von(date '2026-07-01') = 2026 and saison_von(date '2027-01-15') = 2026,
    '0112 (a3): die Saison beginnt nicht am 1. Juli';

  -- (b) Die Positionen aller Saisons
  insert into ausgang_quelle (code, name, dateiname_muster) values ('PRUEF112', 'Prüffirma 0112', 'PRUEF112')
  on conflict (code) do nothing;
  v_j := ausgang_historie_uebernehmen('PRUEF112',
    '[{"pos_id": 1, "datum": "2025-09-01", "journal": "A", "kunde": "Prüfkunde", "artikel_id": "kni", "artikel": "Bio-Kürbis roter Knirps", "preisgruppe": "D", "einheit": "kg", "menge": 100, "gewicht_je_artikel": 1},
      {"pos_id": 2, "datum": "2026-08-01", "journal": "A", "kunde": "Prüfkunde", "artikel_id": "kni", "artikel": "Bio-Kürbis roter Knirps", "preisgruppe": "K", "einheit": "Stk", "menge": 10, "gewicht_je_artikel": 1.25},
      {"pos_id": 3, "datum": "2026-08-02", "journal": "L", "kunde": "Prüfkunde", "artikel_id": "kni", "artikel": "Bio-Kürbis roter Knirps", "einheit": "kg", "menge": 999, "gewicht_je_artikel": 1},
      {"pos_id": 4, "datum": "2026-08-03", "journal": "A", "kunde": "Prüfkunde", "artikel_id": "kürbver", "artikel": "Kürbisverrechnung", "einheit": "kg", "menge": 50, "gewicht_je_artikel": 1}]'::jsonb);
  assert (v_j ->> 'positionen')::int = 4 and (v_j -> 'je_saison' ->> '2025')::int = 1 and (v_j -> 'je_saison' ->> '2026')::int = 3,
    format('0112 (b1): vier Positionen in zwei Saisons erwartet, gekommen: %s', v_j);
  assert (select kg from ausgang_position where quelle = 'PRUEF112' and pos_id = 2) = 12.5,
    '0112 (b2): kg ist nicht Menge × Gewicht je Artikel';
  -- wiederholt: dieselben Positionen, eine geändert — keine doppelt
  v_j := ausgang_historie_uebernehmen('PRUEF112',
    '[{"pos_id": 1, "datum": "2025-09-02", "journal": "A", "kunde": "Prüfkunde", "artikel_id": "kni", "artikel": "Bio-Kürbis roter Knirps", "preisgruppe": "D", "einheit": "kg", "menge": 120, "gewicht_je_artikel": 1}]'::jsonb);
  assert (select count(*) from ausgang_position where quelle = 'PRUEF112') = 4
     and (select kg from ausgang_position where quelle = 'PRUEF112' and pos_id = 1) = 120
     and (select datum from ausgang_position where quelle = 'PRUEF112' and pos_id = 1) = date '2025-09-02',
    '0112 (b3): eine wiederholte Position steht doppelt oder wurde nicht nachgeführt';
  -- die Labels an die Zeilen der laufenden Saison
  insert into ausgang_zeile (quelle, pos_id, charge_extern, lauf_nr, fingerabdruck, datum, journal, kunde, artikel_id, artikel,
                             einheit, menge, gewicht_je_artikel, batch_menge, kg_position, kg_charge)
  values ('PRUEF112', 2, '1999', 1, 'f', '2026-08-01', 'A', 'Prüfkunde', 'kni', 'Bio-Kürbis roter Knirps', 'Stk', 10, 1.25, 10, 12.5, 12.5);
  v_j := ausgang_historie_uebernehmen('PRUEF112', '[]'::jsonb,
    '[{"pos_id": 2, "charge_extern": "1999", "lauf_nr": 1, "liefer_label": "CH-K", "preisgruppe": "K"}]'::jsonb);
  assert (v_j ->> 'labels_gesetzt')::int = 1
     and (select liefer_label from ausgang_zeile where quelle = 'PRUEF112' and pos_id = 2) = 'CH-K',
    format('0112 (b4): das Label kam nicht an die Zeile: %s', v_j);
  -- v_verkauf_position: Position 2 steht in beiden Tabellen und zählt einmal
  assert (select count(*) from v_verkauf_position where quelle = 'PRUEF112' and pos_id = 2) = 1,
    '0112 (b5): eine Position aus ausgang_position und ausgang_zeile steht doppelt';
  -- nur der Betriebsleiter
  perform set_config('request.jwt.claim.sub', v_w::text, true);
  begin
    perform ausgang_historie_uebernehmen('PRUEF112', '[]'::jsonb);
    v_ab := 1;
  exception when others then v_ab := 0;
  end;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  assert v_ab = 0, '0112 (b6): ein Arbeiter darf Positionen übernehmen';

  -- (e) v_kunde_tag: nur Kürbis, ohne Journal L
  assert (select sum(kg) from v_kunde_tag where kunde = 'Prüfkunde' and saison = 2026) = 12.5
     and (select sum(kg) from v_kunde_tag where kunde = 'Prüfkunde' and saison = 2025) = 120,
    format('0112 (e1): Prüfkunde hat 2026 %s kg und 2025 %s kg — erwartet 12.5 und 120 (ohne Journal L, ohne Verrechnung)',
           (select sum(kg) from v_kunde_tag where kunde = 'Prüfkunde' and saison = 2026),
           (select sum(kg) from v_kunde_tag where kunde = 'Prüfkunde' and saison = 2025));
  -- auf der Demo: je Kunde und Saison die Summe der Positionen nachgerechnet
  select count(*), count(*) filter (where abs(t.kg - x.kg) > 0.01)
    into v_n, v_ab
    from (select kunde, saison, sum(kg) as kg from v_kunde_tag where kunde <> 'Prüfkunde' group by 1, 2) t
    join lateral (select sum(p.kg) as kg from v_verkauf_position p
                   where p.kunde = t.kunde and p.saison = t.saison and coalesce(p.journal, '') <> 'L'
                     and ist_kuerbis_vorschlag(p.artikel_id, p.artikel)) x on true;
  assert v_n > 0 and v_ab = 0, format('0112 (e2): bei %s von %s Kunden × Saisons stimmt die Summe nicht', v_ab, v_n);

  -- (c) Artikelgruppe und Label
  -- (an einer Sorte, die auch verkauft wird — sonst prüfte das nichts: Butterkin geht als Butterkin/Muskat)
  v_sorte := 'Butterkin';
  assert (select gruppe_verkauft from v_sorte_artikelgruppe where sorte = v_sorte) is not null,
    '0112 (c0): die Demo verkauft Butterkin nicht mehr unter einem erkennbaren Artikel — (c1) wäre blind';
  select artikelgruppe into v_alt from sorte_kaliber where sorte = v_sorte;
  update sorte_kaliber set artikelgruppe = 'Prüfgruppe' where sorte = v_sorte;
  assert (select artikelgruppe || '|' || quelle from v_sorte_artikelgruppe where sorte = v_sorte) = 'Prüfgruppe|Stammdaten',
    '0112 (c1): die Artikelgruppe der Stammdaten gilt nicht';
  -- ohne Stammdaten: die meistverkaufte Gruppe der Sorte (in der Demo: Kaori Kuri als Knirps)
  update sorte_kaliber set artikelgruppe = null where sorte = 'Kaori Kuri';
  assert (select artikelgruppe || '|' || quelle from v_sorte_artikelgruppe where sorte = 'Kaori Kuri') = 'Knirps|verkauft als',
    format('0112 (c2): ohne Stammdaten nicht die verkaufte Gruppe: %s',
           (select artikelgruppe || '|' || coalesce(quelle, '') from v_sorte_artikelgruppe where sorte = 'Kaori Kuri'));
  update sorte_kaliber set artikelgruppe = 'Knirps' where sorte = 'Kaori Kuri';
  update sorte_kaliber set artikelgruppe = v_alt where sorte = v_sorte;
  -- Label: Perigon nach der Mehrheit; CH-K ist K; Stammdaten gehen vor
  select l.charge_nr into v_charge from lieferung l join lieferung_import li on li.lieferung_id = l.id
   where l.charge_nr is not null and l.bemerkung = 'DEMO'
   group by l.charge_nr having count(*) >= 3 order by l.charge_nr limit 1;
  update ausgang_zeile z set liefer_label = 'CH-K'
    from lieferung_import li join lieferung l on l.id = li.lieferung_id
   where z.id = li.zeile_id and l.charge_nr = v_charge;
  assert (select label || '|' || quelle from v_charge_label where charge_nr = v_charge) = 'K|Perigon',
    '0112 (c3): CH-K aus Perigon ist nicht Knospe';
  update ausgang_zeile z set liefer_label = 'D'
    from lieferung_import li join lieferung l on l.id = li.lieferung_id
   where z.id = li.zeile_id and l.charge_nr = v_charge
     and z.id = (select min(z2.id) from ausgang_zeile z2 join lieferung_import li2 on li2.zeile_id = z2.id
                  join lieferung l2 on l2.id = li2.lieferung_id where l2.charge_nr = v_charge);
  select count(*) into v_n from lieferung_import li join lieferung l on l.id = li.lieferung_id where l.charge_nr = v_charge;
  assert (select gemischt from v_charge_label where charge_nr = v_charge)
     and (select label from v_charge_label where charge_nr = v_charge) = 'K',
    format('0112 (c4): gemischte Labels (1 × D, %s × K) nicht nach der Mehrheit', v_n - 1);
  update charge set label = 'D' where nr = v_charge;
  assert (select label || '|' || quelle from v_charge_label where charge_nr = v_charge) = 'D|Stammdaten',
    '0112 (c5): das Label der Stammdaten gilt nicht';
  update charge set label = null where nr = v_charge;
  update ausgang_zeile set liefer_label = null where quelle = 'DEMO';
  perform demo_vorjahre_laden();   -- setzt die Demo-Labels wieder

  -- (d) artikel_lager
  select count(*) into v_n from artikel_lager(0);
  assert v_n > 0, '0112 (d0): artikel_lager(0) ist leer — die Demo trägt die Prüfung nicht';
  -- dieselbe Masse wie das Verkaufsfähige der Prognose, heute und in vier Wochen
  select count(*) filter (where abs(coalesce(a.kg, 0) - p.kg) > 0.05) into v_ab
    from (values (0), (28)) hh(h)
    cross join lateral (select coalesce(sum(verkaufsfaehig_kg), 0) as kg from erg_prognose
                         where gruppe = 'charge' and h = hh.h and verkaufsfaehig_kg > 0) p
    cross join lateral (select sum(kg) as kg from artikel_lager(hh.h)) a;
  assert v_ab = 0, '0112 (d1): artikel_lager summiert nicht auf das Verkaufsfähige — zweite Rechnung';
  -- je Charge nachgerechnet: der Anteil klein = Kürbismasse der Verteilung in [von, bis) / ganze Masse
  select count(*), count(*) filter (where abs(a.kg - x.kg) > 0.05)
    into v_n, v_ab
    from (select k.gruppe, k.von_g, k.bis_g from artikel_kaliber k where k.groesse = 'klein') k
    join lateral (
      select coalesce(sum(p.verkaufsfaehig_kg * (
               select sum(w.anzahl * w.g) filter (where w.g >= k.von_g and w.g < k.bis_g) / sum(w.anzahl * w.g)
                 from kuerbis_stichtag(0) w
                where w.basis = q.basis and w.schluessel = q.schluessel)), 0) as kg
        from erg_prognose p
        join charge c on c.nr = p.schluessel::int
        join v_sorte_artikelgruppe g on g.sorte = c.sorte and g.artikelgruppe = k.gruppe
        join lager_schluessel() q on q.charge_nr = c.nr and q.basis <> 'keine'
       where p.gruppe = 'charge' and p.h = 0 and p.verkaufsfaehig_kg > 0) x on true
    join lateral (select coalesce(sum(a.kg), 0) as kg from artikel_lager(0) a
                   where a.artikelgruppe = k.gruppe and a.groesse = 'klein') a on true
   where x.kg > 0;
  assert v_n > 0 and v_ab = 0, format('0112 (d2): bei %s von %s Artikelgruppen ist „klein" nicht nachgerechnet', v_ab, v_n);
  -- Stück und Kisten
  assert not exists (select 1 from artikel_lager(0)
                      where groesse in ('klein', 'gross', 'stueck')
                        and (abs(stueck - kg * 1000 / g_mittel) > greatest(0.01 * stueck, 2)
                             or abs(kisten - stueck / stueck_je_kiste) > 1)),
    '0112 (d3): Stück ist nicht kg ÷ mittleres Gewicht, oder Kisten nicht Stück ÷ Stück je Kiste';
  -- ohne Sortier-CSV: die Charge steht ganz unter „ohne Verteilung"
  create temp table t112_lager on commit drop as select * from artikel_lager(0);
  select count(*), count(*) filter (where not exists (select 1 from t112_lager a
                                                       where a.groesse = 'ohne Verteilung' and c.nr = any(a.chargen))
                                       or exists (select 1 from t112_lager a
                                                   where a.groesse <> 'ohne Verteilung' and c.nr = any(a.chargen)))
    into v_n, v_ab
    from erg_prognose p
    join charge c on c.nr = p.schluessel::int
    join lager_schluessel() q on q.charge_nr = c.nr and q.basis = 'keine'
   where p.gruppe = 'charge' and p.h = 0 and p.verkaufsfaehig_kg > 0;
  assert v_n > 0, '0112 (d4): die Demo hat keine Charge ohne Sortier-CSV mehr — die Prüfung wäre blind';
  assert v_ab = 0, format('0112 (d4b): %s von %s Chargen ohne Sortier-CSV stehen nicht ganz unter „ohne Verteilung"', v_ab, v_n);
  -- ohne Artikelgruppe geht nichts verloren (Kaori Kuri wird verkauft — also
  -- auch die verkaufte Gruppe abschalten, über den Namen der Verkaufszeilen)
  update sorte_kaliber set artikelgruppe = null where sorte = 'Kaori Kuri';
  create temp table t112_namen on commit drop as
    select id, artikel from ausgang_zeile where artikel ilike '%kaori%' and quelle = 'DEMO';
  update ausgang_zeile set artikel = 'Bio Kürbis Prüfware' where id in (select id from t112_namen);
  assert exists (select 1 from artikel_lager(0) where artikelgruppe is null and kg > 0),
    '0112 (d5): eine Sorte ohne Artikelgruppe fällt aus artikel_lager heraus';
  select count(*) filter (where abs(coalesce(a.kg, 0) - p.kg) > 0.05) into v_ab
    from (select coalesce(sum(verkaufsfaehig_kg), 0) as kg from erg_prognose where gruppe = 'charge' and h = 0 and verkaufsfaehig_kg > 0) p
    cross join (select sum(kg) as kg from artikel_lager(0)) a;
  assert v_ab = 0, '0112 (d5b): ohne Artikelgruppe stimmt die Summe nicht mehr';
  update ausgang_zeile z set artikel = t.artikel from t112_namen t where z.id = t.id;
  update sorte_kaliber set artikelgruppe = 'Knirps' where sorte = 'Kaori Kuri';

  -- (f) Die Demo
  assert (select count(distinct saison) from ausgang_position where quelle = 'DEMO') = 2,
    '0112 (f1): die Demo hat nicht zwei Vorjahre';
  assert not exists (select 1 from ausgang_zeile where quelle = 'DEMO' and liefer_label is null),
    '0112 (f2): eine Demo-Verkaufszeile ohne Label';
  select count(*) into v_n from ausgang_position where quelle = 'DEMO';
  perform demo_vorjahre_laden();
  assert (select count(*) from ausgang_position where quelle = 'DEMO') = v_n,
    '0112 (f3): demo_vorjahre_laden zweimal gibt mehr Vorjahre';
  -- die Vorjahre überlappen die Demo-Saison nicht
  assert not exists (select 1 from ausgang_position p
                      where p.quelle = 'DEMO' and p.datum >= (select min(datum) from ausgang_zeile where quelle = 'DEMO')),
    '0112 (f4): ein erfundenes Vorjahr liegt im Zeitraum der Demo-Lieferungen';

  -- aufräumen: die Prüffirma
  delete from ausgang_zeile where quelle = 'PRUEF112';
  delete from ausgang_quelle where code = 'PRUEF112';
  assert not exists (select 1 from ausgang_position where quelle = 'PRUEF112'),
    '0112 (f5): Positionen bleiben stehen, wenn die Firma geht';

  -- (g) Stand — und die zwei Gebinde aus der Halle
  assert schema_stand() >= 112, format('0112 (g1): schema_stand() = %s', schema_stand());
  assert (select tara_kg_pro_kiste from gebinde where art = 'Migros Kiste U') = 2.43
     and (select tara_kg_pro_kiste from gebinde where art = 'Plastik Palox') = 35,
    '0112 (g2): die Gebinde Migros Kiste U (2.43 kg) und Plastik Palox (35 kg) fehlen';

  if v_geladen then
    perform demo_daten_entfernen();
    assert not exists (select 1 from ausgang_position where quelle = 'DEMO'),
      '0112 (f6): die Vorjahre der Demo bleiben nach demo_daten_entfernen stehen';
  end if;
  delete from profil where id in (v_u, v_w); delete from auth.users where id in (v_u, v_w);
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0112 — Artikel eingeordnet, alle Saisons einmal je Position, Artikelgruppe und Label mit Herkunft, das Verkaufsfähige je Artikel ohne zweite Rechnung, Kunden je Saison ohne Umbuchungen, die Demo mit zwei Vorjahren';
end $$;

select '——— 0112 Lager nach Artikel geprüft ———' as ergebnis;
