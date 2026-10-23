-- =====================================================================
-- 0123 — Im Lager steht, was vom Eingang noch dasteht; verkaufsfähig ist,
--        was wir als Artikel tatsächlich verkaufen können
--
-- (a) Woher: keinen_artikel_kg und groesse_offen_kg sind je Charge genau die
--     Teile von artikel_lager_teile(0), die in kein Artikelgewicht passen
--     bzw. keine Sortier-CSV haben; die Demo hat beides.
-- (b) Die Rechnung: verkaufbar = verkaufsfähig − passt in keinen Artikel −
--     Überfüllung (auf dem Teil, der als Artikel geht) + Unique; nie mehr,
--     als nach Verdunstung und Faulem noch da ist; eine Charge mit Ware
--     ausserhalb der Artikelgewichte verkauft weniger, als die
--     Sortiermaschine durchlässt.
-- (c) Leer ist nicht null: Ist die Überfüllung einer Sorte nicht gewogen,
--     bleibt sie leer, verkaufbar ist eine obere Schranke, und
--     verkaufbar_offen sagt es. Ohne Sortier-CSV dasselbe.
-- (d) Unique (Hagel) ist ein Artikel und zählt mit.
-- (e) Die Spalten von 0121 sind unverändert (verkaufsfaehig_kg, marge_kg,
--     verrechenbar_kg) — auch bei einer Charge mit Ware ausserhalb der
--     Artikelgewichte und gewogener Überfüllung (eine gebaute Tiana-Charge).
-- (h) Stand 123.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false; v_gerechnet boolean := false;
  v_s int; v_n int; v_x record; v_txt text; v_vorher numeric;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  if not exists (select 1 from sortier_lauf) then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  if not exists (select 1 from erg_charge) then
    update auswertung_stand set rechnet_seit = null where id = 1;
    for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
    v_gerechnet := true;
  end if;

  -- (a) woher
  select count(*) into v_n
    from v_lager_ausweis a
    -- 0124: „lose" ohne Artikelgruppe ist offen (gruppe_offen_kg), nicht „passt in keinen
    -- Artikel"; ohne Sortier-CSV ist keinen_artikel_kg leer — darum coalesce(…, 0).
    left join (select t.charge_nr,
                      sum(t.kg) filter (where t.groesse in ('darunter', 'darueber', 'dazwischen')) as kein,
                      sum(t.kg) filter (where t.groesse = 'ohne Verteilung') as offen
                 from artikel_lager_teile(0) t group by t.charge_nr) t on t.charge_nr = a.charge_nr
   where a.verkaufsfaehig_kg > 0
     and (abs(coalesce(a.keinen_artikel_kg, 0) - coalesce(t.kein, 0)) > 0.05 or abs(a.groesse_offen_kg - coalesce(t.offen, 0)) > 0.05);
  assert v_n = 0, format('0123 (a1): bei %s Chargen passen keinen_artikel_kg oder groesse_offen_kg nicht zu artikel_lager_teile(0)', v_n);
  assert (select sum(keinen_artikel_kg) from v_lager_ausweis) > 0,
    '0123 (a2): in der Demo passt nichts ausserhalb der Artikelgewichte — die Prüfung prüft nichts';
  assert (select sum(groesse_offen_kg) from v_lager_ausweis) > 0,
    '0123 (a3): in der Demo hat jede Charge eine Sortier-CSV — der offene Fall ist nicht geprüft';
  -- (a4) eine Lücke zwischen klein und gross: was hineinfällt, passt in keinen Artikel
  select sum(keinen_artikel_kg) into v_vorher from v_lager_ausweis;
  update artikel_kaliber set von_g = von_g + 100 where gruppe = 'Knirps' and groesse = 'gross';
  assert exists (select 1 from artikel_lager_teile(0) t where t.groesse = 'dazwischen' and t.kg > 0),
    '0123 (a4): die Lücke zwischen den Knirps-Kalibern bleibt leer — die Prüfung prüft nichts';
  assert (select sum(keinen_artikel_kg) from v_lager_ausweis) > v_vorher + 0.5,
    format('0123 (a4): Ware zwischen den Artikelgewichten zählt als Artikel (%s kg vorher, %s kg mit Lücke)',
           v_vorher, (select sum(keinen_artikel_kg) from v_lager_ausweis));
  update artikel_kaliber set von_g = von_g - 100 where gruppe = 'Knirps' and groesse = 'gross';

  -- (b) die Rechnung
  select count(*) into v_n from v_lager_ausweis a
   where a.verkaufsfaehig_kg is not null
     -- 0124: keinen_artikel_kg ist ohne Sortier-CSV leer (kein Abzug); Hagel 100 % lässt verkaufbar leer
     and abs(a.verkaufbar_kg - (a.verkaufsfaehig_kg - coalesce(a.keinen_artikel_kg, 0) - coalesce(a.ueberfuellung_kg, 0) + coalesce(a.unique_kg, 0))) > 0.05;
  assert v_n = 0, format('0123 (b1): bei %s Chargen ist verkaufbar nicht verkaufsfähig − passt in keinen Artikel − Überfüllung + Unique', v_n);
  select count(*) into v_n from v_lager_ausweis a
   where a.marge_anteil is not null and a.verkaufsfaehig_kg is not null
     -- marge_anteil steht auf 5 Stellen gerundet da: bis 0.00001 · verkaufsfähig Spiel
     and abs(a.ueberfuellung_kg - (a.verkaufsfaehig_kg - coalesce(a.keinen_artikel_kg, 0)) * a.marge_anteil / (1 + a.marge_anteil)) > 0.05 + 0.00001 * a.verkaufsfaehig_kg;
  assert v_n = 0, format('0123 (b2): bei %s Chargen ist die Überfüllung nicht die auf dem Teil, der als Artikel geht', v_n);
  select count(*) into v_n from v_lager_ausweis a
   where a.verkaufbar_kg > a.eingang_kg - a.verdunstet_kg - a.faul_kg + 0.05;
  assert v_n = 0, format('0123 (b3): bei %s Chargen ist mehr verkaufbar, als nach Verdunstung und Faulem noch da ist', v_n);
  assert exists (select 1 from v_lager_ausweis a where a.keinen_artikel_kg > 0 and a.verkaufbar_kg < a.verkaufsfaehig_kg - 0.5),
    '0123 (b4): keine Charge verkauft weniger, als die Sortiermaschine durchlässt, obwohl Ware ausserhalb der Artikelgewichte liegt';
  assert exists (select 1 from v_lager_ausweis a where a.ueberfuellung_kg > 0),
    '0123 (b5): in der Demo wird nirgends Überfüllung abgezogen';

  -- (c) und (d): eine Sorte ohne gewogene Palette, eine Charge mit Hagel
  create temp table pruef_0123_wiegung on commit drop as
    select w.* from ausgang_wiegung w join charge c on c.nr = w.charge_nr where c.sorte = 'Mieluna';
  delete from ausgang_wiegung where id in (select id from pruef_0123_wiegung);
  update charge set hagel_anteil = 0.2 where nr = 1609;
  -- (b6) eine Tiana-Charge mit Sortier-CSV und gewogener Überfüllung: 700 g und
  -- 1900 g passen in keinen Butternut-Artikel (800–1800 g)
  insert into sortier_lauf
  select (jsonb_populate_record(null::sortier_lauf, to_jsonb(l) || jsonb_build_object(
            'id', 912301, 'charge_nr', 1611, 'auftrag_id', null, 'datei_name', 'pruef-0123.csv',
            'roh_pruefsumme', 'pruef-0123', 'vorgaenger_id', null))).*
    from sortier_lauf l order by l.id limit 1;
  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  values (912301, 700, 20, 'kaliber', 0), (912301, 1000, 40, 'kaliber', 0), (912301, 1500, 30, 'kaliber', 1),
         (912301, 1900, 10, 'kaliber', 1);
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;

  select * into v_x from v_lager_ausweis where charge_nr = 1611;
  assert v_x.keinen_artikel_kg > 0.5 and v_x.marge_anteil > 0,
    format('0123 (b6): 1611 mit Sortier-CSV hat passt in keinen Artikel %s und Überfüllung %s — der Fall ist nicht gebaut',
           v_x.keinen_artikel_kg, v_x.marge_anteil);
  assert abs(v_x.ueberfuellung_kg - (v_x.verkaufsfaehig_kg - v_x.keinen_artikel_kg) * v_x.marge_anteil / (1 + v_x.marge_anteil))
           <= 0.05 + 0.00001 * v_x.verkaufsfaehig_kg,
    format('0123 (b6): die Überfüllung von 1611 (%s) ist nicht die auf dem Teil, der als Artikel geht', v_x.ueberfuellung_kg);
  assert abs(v_x.marge_kg - v_x.verkaufsfaehig_kg * v_x.marge_anteil / (1 + v_x.marge_anteil)) <= 0.05 + 0.00001 * v_x.verkaufsfaehig_kg
     and abs(v_x.verrechenbar_kg - v_x.verkaufsfaehig_kg / (1 + v_x.marge_anteil)) <= 0.05 + 0.00001 * v_x.verkaufsfaehig_kg,
    format('0123 (e3): marge_kg %s / verrechenbar_kg %s von 1611 beziehen sich nicht mehr aufs ganze Verkaufsfähige wie in 0121',
           v_x.marge_kg, v_x.verrechenbar_kg);

  for v_x in select * from v_lager_ausweis a where a.sorte = 'Mieluna' and a.verkaufsfaehig_kg > 0 loop
    assert v_x.marge_anteil is null and v_x.ueberfuellung_kg is null,
      format('0123 (c1): Charge %s ohne gewogene Palette hat Überfüllung %s statt leer', v_x.charge_nr, v_x.ueberfuellung_kg);
    assert v_x.verkaufbar_offen like '%Überfüllung nicht gewogen%',
      format('0123 (c2): Charge %s sagt nicht, dass die Überfüllung fehlt: %s', v_x.charge_nr, v_x.verkaufbar_offen);
  end loop;
  assert exists (select 1 from v_lager_ausweis a where a.sorte = 'Mieluna' and a.verkaufsfaehig_kg > 0),
    '0123 (c0): keine Mieluna-Charge mit Ware — (c1, c2) prüfen nichts';
  select count(*) into v_n from v_lager_ausweis a
   where a.groesse_offen_kg > 0 and coalesce(a.verkaufbar_offen, '') not like '%Grösse offen%';
  assert v_n = 0, format('0123 (c3): %s Chargen ohne Sortier-CSV sagen nicht, dass die Grösse offen ist', v_n);
  select count(*) into v_n from v_lager_ausweis a
   where a.verkaufbar_offen is not null and a.marge_anteil is not null and coalesce(a.groesse_offen_kg, 0) = 0
     -- 0124: zwei weitere Gründe, die nichts mit dem Messen zu tun haben
     and coalesce(a.gruppe_offen_kg, 0) = 0 and coalesce(a.hagel_anteil, 0) < 1;
  assert v_n = 0, format('0123 (c4): %s Chargen nennen etwas offen, obwohl alles gemessen ist', v_n);

  select * into v_x from v_lager_ausweis where charge_nr = 1609;
  assert v_x.unique_kg > 0, format('0123 (d1): 20 %% Hagel auf 1609 ergibt Unique %s', v_x.unique_kg);
  assert abs(v_x.verkaufbar_kg - (v_x.verkaufsfaehig_kg - v_x.keinen_artikel_kg - coalesce(v_x.ueberfuellung_kg, 0) + v_x.unique_kg)) <= 0.05
     and v_x.verkaufbar_kg > v_x.verkaufsfaehig_kg - v_x.keinen_artikel_kg - coalesce(v_x.ueberfuellung_kg, 0) + 0.5,
    format('0123 (d2): Unique %s zählt nicht im Verkaufbaren %s', v_x.unique_kg, v_x.verkaufbar_kg);

  -- aufräumen
  delete from sortier_lauf where id = 912301;
  insert into ausgang_wiegung select * from pruef_0123_wiegung;
  update charge set hagel_anteil = null where nr = 1609;
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;

  -- (e) die Spalten von 0121
  select count(*) into v_n from v_lager_ausweis a
   where a.verkaufsfaehig_kg is not null and a.marge_anteil is not null
     and (abs(a.marge_kg - a.verkaufsfaehig_kg * a.marge_anteil / (1 + a.marge_anteil)) > 0.05 + 0.00001 * a.verkaufsfaehig_kg
          or abs(a.verrechenbar_kg - a.verkaufsfaehig_kg / (1 + a.marge_anteil)) > 0.05 + 0.00001 * a.verkaufsfaehig_kg);
  assert v_n = 0, format('0123 (e1): bei %s Chargen haben sich marge_kg oder verrechenbar_kg von 0121 verändert', v_n);
  select count(*) into v_n from v_lager_ausweis a
   where a.verkaufsfaehig_kg is not null
     and abs(a.eingang_kg - a.verdunstet_kg - a.faul_kg - coalesce(a.unique_kg, 0) - a.zu_klein_kg - a.zu_gross_kg - a.fax_kg - a.verkaufsfaehig_kg) > 0.05;
  assert v_n = 0, format('0123 (e2): bei %s Chargen geht die Kette von 0121 nicht mehr auf', v_n);

  update auswertung_stand set rechnet_seit = null where id = 1;
  if v_geladen then perform demo_daten_entfernen(); end if;

  -- (h) Stand
  assert schema_stand() >= 123, format('0123 (h1): schema_stand() = %s', schema_stand());

  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0123 — im Lager steht, was vom Eingang noch dasteht; verkaufbar ist verkaufsfähig ohne, was in kein Artikelgewicht passt, und ohne Überfüllung, mit Unique; nicht Gewogenes und Grösse ohne Sortier-CSV bleiben offen und werden genannt';
end $$;

select '——— 0123 Verkaufsfähig ist, was als Artikel geht ———' as ergebnis;
