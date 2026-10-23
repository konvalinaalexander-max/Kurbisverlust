-- =====================================================================
-- 0124 — Was der Lager-Ausweis nicht wissen kann, sagt er
--
-- (a) Jede Funktion in PL/pgSQL hat einen festen Suchpfad — auch die sieben,
--     die bis 0124 keinen hatten; eine Funktion in SQL hat kein SET, damit
--     Postgres sie einsetzen kann (0110 b2).
-- (b) Lager-Ausweis:
--     (b1) eine Sorte ohne Artikelgruppe ist offen (gruppe_offen_kg, Grund),
--          nicht „passt in keinen Artikel", und wird nicht abgezogen;
--     (b2) eine Artikelgruppe ohne Gewichte ist ein Artikel (lose) — gebaut,
--          indem die Kabocha-Gewichte vorübergehend fehlen;
--     (b3) Hagel 100 %: Faules, Unique, Hagel bis heute und Verkaufbares
--          leer, mit Grund;
--     (b4) ohne Sortier-CSV ist keinen_artikel_kg leer, nicht 0 — verkaufbar
--          rechnet ohne den Abzug;
--     (b5) ohne Verkaufsfähiges sind die drei Teile leer, nicht 0;
--     (b6) gewogene Paletten einer Arbeit ohne Kistensystem oder Sollgewicht:
--          marge_quelle und verkaufbar_offen sagen es, nicht „nicht gewogen".
-- (c) v_charge_spur: nach_artikel geht auf geliefert_kg auf; Lieferungen
--     ohne Perigon-Zeile stehen als eigener Teil.
-- (d) Die Liste vom 23. Oktober hat ihre Marke (0122).
-- (e) Stand 124.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false;
  v_s int; v_n int; v_x record; v_vorher numeric;
begin
  -- (a) Suchpfad: PL/pgSQL mit festem Suchpfad; SQL ohne SET (einsetzbar, 0110)
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
   where n.nspname = 'public' and p.prokind <> 'a' and l.lanname = 'plpgsql'
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  assert v_n = 0, format('0124 (a1): %s Funktionen in PL/pgSQL ohne festen Suchpfad (search_path): %s', v_n,
    (select string_agg(p.oid::regprocedure::text, ', ' order by 1)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
      where n.nspname = 'public' and p.prokind <> 'a' and l.lanname = 'plpgsql'
        and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')));
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
   where n.nspname = 'public' and p.prokind <> 'a' and l.lanname = 'sql' and not p.prosecdef
     and p.proname not in ('schema_stand')
     and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  -- Bis 0124 hatten 36 Funktionen in SQL schon ein SET (Planungsgrenzen, Rechte, Stand);
  -- die 19 der Kaskade und der Klassierung bleiben ohne — nicht mehr werden es nicht.
  assert v_n <= 36, format('0124 (a2): %s Funktionen in SQL mit SET — eine Funktion in SQL soll einsetzbar bleiben (0110 b2)', v_n);

  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  if not exists (select 1 from sortier_lauf) then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  if not exists (select 1 from erg_charge) then
    update auswertung_stand set rechnet_seit = null where id = 1;
    for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  end if;

  -- (b1) Sorte ohne Artikelgruppe: offen, nicht „passt in keinen Artikel"
  assert exists (select 1 from v_lager_ausweis a join v_sorte_artikelgruppe g on g.sorte = a.sorte
                  where a.verkaufsfaehig_kg > 0 and g.artikelgruppe is null),
    '0124 (b0): keine Sorte ohne Artikelgruppe mit Ware in der Demo — (b1) prüft nichts';
  select count(*) into v_n
    from v_lager_ausweis a join v_sorte_artikelgruppe g on g.sorte = a.sorte
   where a.verkaufsfaehig_kg > 0 and g.artikelgruppe is null
     and not (a.gruppe_offen_kg > 0.5 and coalesce(a.verkaufbar_offen, '') like '%Artikelgruppe fehlt%');
  assert v_n = 0, format('0124 (b1): %s Chargen einer Sorte ohne Artikelgruppe nennen die Gruppe nicht als offen', v_n);
  -- die Teile stimmen mit artikel_lager_teile(0) überein — lose ohne Gruppe zählt nicht als „passt in keinen Artikel"
  select count(*) into v_n
    from v_lager_ausweis a
    left join (select t.charge_nr,
                      sum(t.kg) filter (where t.groesse in ('darunter', 'darueber', 'dazwischen')) as kein,
                      sum(t.kg) filter (where t.groesse = 'lose' and t.artikelgruppe is null) as gruppe
                 from artikel_lager_teile(0) t group by t.charge_nr) t on t.charge_nr = a.charge_nr
   where a.verkaufsfaehig_kg > 0 and coalesce(a.groesse_offen_kg, 0) = 0
     and (abs(a.keinen_artikel_kg - coalesce(t.kein, 0)) > 0.05 or abs(a.gruppe_offen_kg - coalesce(t.gruppe, 0)) > 0.05);
  assert v_n = 0, format('0124 (b1): bei %s Chargen passen keinen_artikel_kg oder gruppe_offen_kg nicht zu artikel_lager_teile(0)', v_n);
  select count(*) into v_n from v_lager_ausweis a
   where a.gruppe_offen_kg > 0.5
     and abs(a.verkaufbar_kg - (a.verkaufsfaehig_kg - a.keinen_artikel_kg - coalesce(a.ueberfuellung_kg, 0) + coalesce(a.unique_kg, 0))) > 0.05;
  assert v_n = 0, format('0124 (b1): bei %s Chargen wird die offene Artikelgruppe vom Verkaufbaren abgezogen', v_n);

  -- (b2) eine Artikelgruppe ohne Gewichte ist ein Artikel ohne Grösse
  assert exists (select 1 from v_lager_ausweis a join v_sorte_artikelgruppe g on g.sorte = a.sorte
                  where g.artikelgruppe = 'Kabocha' and a.keinen_artikel_kg > 0.5),
    '0124 (b2): keine Kabocha-Charge mit Ware ausserhalb der Artikelgewichte — der Fall ist nicht gebaut';
  create temp table pruef_0124_kaliber on commit drop as select * from artikel_kaliber where gruppe = 'Kabocha';
  delete from artikel_kaliber where gruppe = 'Kabocha';
  select count(*) into v_n
    from v_lager_ausweis a join v_sorte_artikelgruppe g on g.sorte = a.sorte
   where g.artikelgruppe = 'Kabocha' and a.verkaufsfaehig_kg > 0
     and not (a.keinen_artikel_kg = 0 and a.gruppe_offen_kg = 0
              and coalesce(a.verkaufbar_offen, '') not like '%Artikelgruppe%'
              and abs(a.verkaufbar_kg - (a.verkaufsfaehig_kg - coalesce(a.ueberfuellung_kg, 0) + coalesce(a.unique_kg, 0))) <= 0.05);
  assert v_n = 0, format('0124 (b2): %s Kabocha-Chargen ohne Gewichte der Gruppe zählen nicht als Artikel', v_n);
  insert into artikel_kaliber select * from pruef_0124_kaliber;

  -- (b3) Hagel 100 %: nicht trennbar — leer, mit Grund
  update charge set hagel_anteil = 1 where nr = 1609;
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  select * into v_x from v_lager_ausweis where charge_nr = 1609;
  assert v_x.eingang_kg > 0, '0124 (b3): 1609 hat keine Ware — der Fall ist nicht gebaut';
  assert v_x.faul_kg is null and v_x.unique_kg is null and v_x.verkaufbar_kg is null and v_x.hagel_bis_heute_kg is null,
    format('0124 (b3): bei Hagel 100 %% steht faul %s, unique %s, verkaufbar %s, Hagel bis heute %s statt leer',
           v_x.faul_kg, v_x.unique_kg, v_x.verkaufbar_kg, v_x.hagel_bis_heute_kg);
  assert position('Hagel 100 %' in coalesce(v_x.verkaufbar_offen, '')) > 0,
    format('0124 (b3): der Grund fehlt: %s', v_x.verkaufbar_offen);
  update charge set hagel_anteil = null where nr = 1609;
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;

  -- (b4) ohne Sortier-CSV: keinen_artikel_kg leer, verkaufbar ohne den Abzug
  assert exists (select 1 from v_lager_ausweis where groesse_offen_kg > 0), '0124 (b4): keine Charge ohne Sortier-CSV — prüft nichts';
  select count(*) into v_n from v_lager_ausweis a
   where a.groesse_offen_kg > 0
     and (a.keinen_artikel_kg is not null or a.verkaufbar_kg is null
          or abs(a.verkaufbar_kg - (a.verkaufsfaehig_kg - coalesce(a.ueberfuellung_kg, 0) + coalesce(a.unique_kg, 0))) > 0.05);
  assert v_n = 0, format('0124 (b4): bei %s Chargen ohne Sortier-CSV ist keinen_artikel_kg nicht leer oder verkaufbar falsch', v_n);

  -- (b5) ohne Verkaufsfähiges: die drei Teile leer, nicht 0
  assert exists (select 1 from v_lager_ausweis where verkaufsfaehig_kg is null), '0124 (b5): keine Charge ohne Verkaufsfähiges — prüft nichts';
  select count(*) into v_n from v_lager_ausweis a
   where a.verkaufsfaehig_kg is null
     and (a.keinen_artikel_kg is not null or a.groesse_offen_kg is not null or a.gruppe_offen_kg is not null);
  assert v_n = 0, format('0124 (b5): bei %s Chargen ohne Verkaufsfähiges steht ein Teil auf 0 statt leer', v_n);

  -- (b6) gewogen, aber die Arbeit hat kein Sollgewicht („Kiste ab" ohne Soll; ohne
  -- Kistensystem fiele die Arbeit auf ihre Fassung zurück, darum so gebaut)
  create temp table pruef_0124_system on commit drop as
    select a.id, a.kistensystem, a.soll_kg_pro_kiste from auftrag a
     where a.id in (select w.auftrag_id from ausgang_wiegung w join charge c on c.nr = w.charge_nr where c.sorte = 'Mieluna');
  assert (select count(*) from pruef_0124_system) > 0, '0124 (b6): keine gewogene Mieluna-Palette — der Fall ist nicht gebaut';
  update auftrag set kistensystem = 'kiste_ab', soll_kg_pro_kiste = null where id in (select id from pruef_0124_system);
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;
  v_n := 0;
  for v_x in select * from v_lager_ausweis a where a.sorte = 'Mieluna' and a.verkaufsfaehig_kg > 0 loop
    v_n := v_n + 1;
    assert v_x.marge_anteil is null, format('0124 (b6): Charge %s hat eine Überfüllung (%s), obwohl keine Arbeit ein Sollgewicht hat', v_x.charge_nr, v_x.marge_anteil);
    assert v_x.marge_quelle like '%kein Kistensystem%' and coalesce(v_x.verkaufbar_offen, '') like '%kein Kistensystem%',
      format('0124 (b6): Charge %s sagt nicht, was fehlt: „%s" / „%s"', v_x.charge_nr, v_x.marge_quelle, v_x.verkaufbar_offen);
  end loop;
  assert v_n > 0, '0124 (b6): keine Mieluna-Charge mit Ware — prüft nichts';
  update auftrag a set kistensystem = s.kistensystem, soll_kg_pro_kiste = s.soll_kg_pro_kiste from pruef_0124_system s where s.id = a.id;
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, false); end loop;

  -- (c) der Weg der Ware geht auf
  assert exists (select 1 from v_charge_spur s, jsonb_array_elements(s.nach_artikel) e
                  where e->>'gruppe' = 'ohne Perigon-Zeile' and (e->>'kg')::numeric > 0),
    '0124 (c0): keine Lieferung ohne Perigon-Zeile in der Demo — (c1) prüft den neuen Teil nicht';
  select count(*) into v_n from v_charge_spur s
   where s.lieferscheine > 0
     and abs(s.geliefert_kg - (select coalesce(sum((e->>'kg')::numeric), 0) from jsonb_array_elements(s.nach_artikel) e))
         > 0.5 * (coalesce(jsonb_array_length(s.nach_artikel), 0) + 1);
  assert v_n = 0, format('0124 (c1): bei %s Chargen geht nach_artikel nicht auf geliefert_kg auf', v_n);

  update auswertung_stand set rechnet_seit = null where id = 1;
  if v_geladen then perform demo_daten_entfernen(); end if;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';

  -- (d) die Liste vom 23. Oktober läuft nur einmal
  assert exists (select 1 from einstellung where schluessel = 'perigon_liste_2026_10_23'),
    '0124 (d1): die Marke der Perigon-Liste vom 23. Oktober fehlt — 0122 liefe bei jedem Einspielen von neuem';

  -- (e) Stand
  assert schema_stand() >= 124, format('0124 (e1): schema_stand() = %s', schema_stand());
  raise notice 'OK  0124 — der Lager-Ausweis sagt, was er nicht weiss (Artikelgruppe, Grösse, Hagel 100 %%, Kistensystem); jede PL/pgSQL-Funktion hat ihren Suchpfad, jede SQL-Funktion bleibt einsetzbar; der Weg der Ware geht auf';
end $$;

select '——— 0124 Was der Ausweis nicht weiss, sagt er ———' as ergebnis;
