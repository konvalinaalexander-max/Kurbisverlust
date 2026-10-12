-- =====================================================================
-- 0113 — Demeter, wenn je als Demeter geliefert; das Lager je Charge und
--        Artikel; der Anstieg gilt erst, wenn er sicher ist
--
-- Geprüft auf der Demo und an gebauten Fällen:
-- (a) Preisgruppen: CH-K, KAdR, Kz sind Knospe, D und DU Demeter; SG sagt
--     nichts, dann gilt der Name;
-- (b) das Label je Charge: ein Demeter genügt, auch gegen viele Knospe; als
--     Demeter verkauft, aber als Knospe geliefert, bleibt Knospe und zählt
--     als Widerspruch; ohne Lieferlabel zählt der Verkauf; ohne Perigon der
--     Produzent (gleicher Schlag); ohne alles Knospe, angenommen; die
--     Stammdaten vor allem;
-- (c) artikel_lager_charge: dieselben Teile wie artikel_lager (je Artikel
--     nachgezählt), je Charge das ganze Verkaufsfähige, das Label der Charge,
--     Stück und Kisten;
-- (d) der Anstieg des Palox-Anteils: die Regel an gebauten Fällen, und in
--     Zeitfenstern der Demo, wo er mal sicher ist und mal nicht — sicher
--     gilt er, unsicher ist er 0 und der Grundausschuss das Mittel;
-- (e) Stand 113.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false; v_n int; v_ab int; v_x int;
  v_u uuid := '00000000-0113-0000-0000-000000000001';
  v_charge int; v_zeile bigint; v_ohne int; v_schlag text; v_l text; v_bis date;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0113"}');
  update profil set rolle = 'admin' where id = v_u;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from auftrag where station = 'waschen_sortieren' and bemerkung = 'DEMO') then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform demo_vorjahre_laden();
  perform auswertung_aktualisieren();

  -- (a) Preisgruppen, wie Perigon sie schreibt
  select count(*) filter (where e.label is distinct from f.label) into v_ab
    from (values ('Bio Kürbis Knirps Klein', 'CH-K', 'K'),
                 ('Bio Kürbis Butternut lose', 'CH-K', 'K'),
                 ('Bio Kürbis Butternut lose', 'KAdR', 'K'),
                 ('Bio-Kürbis Butterkin', 'Kz', 'K'),
                 ('Bio-Kürbis Butterkin Demeter', 'K', 'K'),
                 ('Bio Kürbis Butternut lose', 'D', 'D'),
                 ('Bio Kürbis Butternut lose', 'DU', 'D'),
                 ('Bio Kürbis Butternut', 'SG', null),
                 ('Bio Kürbis Mandarin Dem', 'SG', 'D'),
                 ('Bio-Kürbis roter Knirps Knospe', null, 'K')) f(artikel, pg, label)
   cross join lateral artikel_einordnen(f.artikel, f.pg) e;
  assert v_ab = 0, format('0113 (a1): %s Preisgruppen falsch gelesen', v_ab);

  -- (b) Das Label je Charge, an einer Demo-Charge mit mindestens drei
  -- Lieferungen. Was (b) verändert, steht vorher in t113_zeile und
  -- t113_charge und kommt danach genau so zurück.
  create temp table t113_zeile on commit drop as select z.id, z.liefer_label, z.preisgruppe from ausgang_zeile z;
  create temp table t113_charge on commit drop as select c.nr, c.label, c.schlag from charge c;
  select l.charge_nr into v_charge from lieferung l join lieferung_import li on li.lieferung_id = l.id
   where l.charge_nr is not null and l.bemerkung = 'DEMO'
   group by l.charge_nr having count(*) >= 3 order by l.charge_nr limit 1;
  assert v_charge is not null, '0113 (b0): die Demo hat keine Charge mit drei Lieferungen — (b1)–(b5) wären blind';
  select min(z.id) into v_zeile from ausgang_zeile z join lieferung_import li on li.zeile_id = z.id
    join lieferung l on l.id = li.lieferung_id where l.charge_nr = v_charge;
  -- alles als Knospe geliefert und verkauft
  update ausgang_zeile z set liefer_label = 'CH-K', preisgruppe = 'CH-K'
    from lieferung_import li join lieferung l on l.id = li.lieferung_id
   where z.id = li.zeile_id and l.charge_nr = v_charge;
  assert (select label || '|' || quelle || '|' || n_widerspruch from v_charge_label where charge_nr = v_charge) = 'K|Perigon|0',
    '0113 (b1): als Knospe geliefert und verkauft ist nicht Knospe aus Perigon';
  -- eine einzige Zeile als Demeter geliefert: Demeter, gegen die Mehrheit
  update ausgang_zeile set liefer_label = 'D' where id = v_zeile;
  assert (select label || '|' || quelle || '|' || gemischt from v_charge_label where charge_nr = v_charge) = 'D|Perigon|true',
    format('0113 (b2): einmal als Demeter geliefert ist nicht Demeter (%s)',
           (select label || '|' || quelle || '|' || gemischt from v_charge_label where charge_nr = v_charge));
  -- als Demeter verkauft, aber als Knospe geliefert: bleibt Knospe, ein Widerspruch
  update ausgang_zeile set liefer_label = 'CH-K', preisgruppe = 'D' where id = v_zeile;
  assert (select label || '|' || n_widerspruch from v_charge_label where charge_nr = v_charge) = 'K|1',
    format('0113 (b3): als Demeter verkauft, als Knospe geliefert — nicht Knospe mit einem Widerspruch (%s)',
           (select label || '|' || n_widerspruch from v_charge_label where charge_nr = v_charge));
  -- ohne Lieferlabel zählt, als was verkauft wurde: der eine Demeter-Verkauf
  update ausgang_zeile z set liefer_label = null
    from lieferung_import li join lieferung l on l.id = li.lieferung_id
   where z.id = li.zeile_id and l.charge_nr = v_charge;
  assert (select label || '|' || quelle from v_charge_label where charge_nr = v_charge) = 'D|Perigon',
    '0113 (b4): ohne Lieferlabel zählt der Verkauf als Demeter nicht';
  -- die Stammdaten vor allem
  update charge set label = 'K' where nr = v_charge;
  assert (select label || '|' || quelle from v_charge_label where charge_nr = v_charge) = 'K|Stammdaten',
    '0113 (b5): das Label der Stammdaten gilt nicht';
  update ausgang_zeile z set liefer_label = v.liefer_label, preisgruppe = v.preisgruppe
    from t113_zeile v where v.id = z.id and (z.liefer_label, z.preisgruppe) is distinct from (v.liefer_label, v.preisgruppe);
  update charge c set label = v.label from t113_charge v where v.nr = c.nr and c.label is distinct from v.label;

  -- Ohne Perigon: der Produzent (derselbe Schlag) — eine unverkaufte Charge
  -- eines Produzenten mit mindestens zwei anderen Chargen.
  select c.nr, c.schlag into v_ohne, v_schlag from charge c
   where not exists (select 1 from lieferung l join lieferung_import li on li.lieferung_id = l.id where l.charge_nr = c.nr)
     and (select count(*) from charge c2 where c2.schlag = c.schlag and c2.nr <> c.nr) >= 2
   order by c.nr limit 1;
  assert v_ohne is not null, '0113 (b6): die Demo hat keine unverkaufte Charge eines Produzenten mit zwei anderen Chargen — (b7) wäre blind';
  -- alle anderen Chargen des Produzenten Knospe: die unverkaufte auch
  update charge set label = 'K' where schlag = v_schlag and nr <> v_ohne;
  assert (select label || '|' || quelle from v_charge_label where charge_nr = v_ohne) = 'K|Produzent',
    format('0113 (b7): die unverkaufte Charge eines Knospe-Produzenten ist nicht Knospe vom Produzenten (%s)',
           (select label || '|' || quelle from v_charge_label where charge_nr = v_ohne));
  -- eine einzige davon Demeter: ein Demeter-Betrieb, gegen die Mehrheit
  update charge set label = 'D' where nr = (select min(nr) from charge where schlag = v_schlag and nr <> v_ohne);
  assert (select label || '|' || quelle from v_charge_label where charge_nr = v_ohne) = 'D|Produzent',
    format('0113 (b7b): eine Demeter-Charge des Produzenten macht die unverkaufte nicht zu Demeter (%s)',
           (select label || '|' || quelle from v_charge_label where charge_nr = v_ohne));
  -- ohne Perigon und ohne Produzent: Knospe, angenommen
  update charge set schlag = 'Prüfschlag 0113' where nr = v_ohne;
  assert (select label || '|' || quelle from v_charge_label where charge_nr = v_ohne) = 'K|angenommen',
    '0113 (b8): ohne Perigon und ohne Produzent nicht Knospe, angenommen';
  update charge c set label = v.label, schlag = v.schlag
    from t113_charge v where v.nr = c.nr and (c.label, c.schlag) is distinct from (v.label, v.schlag);

  -- (c) artikel_lager_charge
  select count(*) into v_n from artikel_lager_charge(0);
  assert v_n > 0, '0113 (c0): artikel_lager_charge(0) ist leer — die Demo trägt die Prüfung nicht';
  -- je Artikel dieselbe Summe wie artikel_lager, aus genauso vielen Chargen
  select count(*), count(*) filter (where abs(a.kg - x.kg) > 0.01 * x.n + 0.01 or a.n_chargen <> x.n)
    into v_n, v_ab
    from artikel_lager(0) a
    join lateral (select coalesce(sum(c.kg), 0) as kg, count(distinct c.charge_nr)::int as n
                    from artikel_lager_charge(0) c
                   where c.artikelgruppe is not distinct from a.artikelgruppe
                     and c.label is not distinct from a.label and c.groesse = a.groesse) x on true;
  assert v_n > 0 and v_ab = 0, format('0113 (c1): bei %s von %s Artikeln weicht die Summe der Chargen ab', v_ab, v_n);
  -- je Charge das ganze Verkaufsfähige: kein Kilo zweimal, keins verloren
  select count(*), count(*) filter (where abs(coalesce(x.kg, 0) - p.verkaufsfaehig_kg) > 0.05)
    into v_n, v_ab
    from erg_prognose p
    left join lateral (select sum(c.kg) as kg from artikel_lager_charge(0) c where c.charge_nr = p.schluessel::int) x on true
   where p.gruppe = 'charge' and p.h = 0 and p.verkaufsfaehig_kg > 0;
  assert v_n > 0 and v_ab = 0, format('0113 (c2): bei %s von %s Chargen ergeben die Artikel nicht das Verkaufsfähige', v_ab, v_n);
  -- das Label im Lager ist das der Charge
  assert not exists (select 1 from artikel_lager_charge(0) c join v_charge_label v on v.charge_nr = c.charge_nr
                      where c.label is distinct from v.label),
    '0113 (c3): eine Charge trägt im Lager ein anderes Label als ihre Charge';
  -- Stück und Kisten je Charge
  assert not exists (select 1 from artikel_lager_charge(0)
                      where groesse in ('klein', 'gross', 'stueck') and g_mittel > 0
                        and (abs(stueck - kg * 1000 / g_mittel) > greatest(0.01 * stueck, 2)
                             or (stueck_je_kiste > 0 and abs(kisten - stueck / stueck_je_kiste) > 1))),
    '0113 (c4): Stück oder Kisten je Charge nicht aus kg und Gewicht je Kürbis';

  -- (d) Der Anstieg gilt erst, wenn er sicher ist
  assert palox_anstieg(0.012, 5, 21, 0.001) = 0.012, '0113 (d1): ein sicherer Anstieg gilt nicht';
  assert palox_anstieg(0.012, 5, 21, -0.001) = 0, '0113 (d2): ein unsicherer Anstieg ist nicht 0';
  assert palox_anstieg(0.012, 5, 21, null) = 0, '0113 (d3): ohne Bereich ist ein Anstieg nicht unsicher';
  assert palox_anstieg(-0.008, 5, 21, -0.02) = 0, '0113 (d4): ein negativer Anstieg ist nicht 0';
  assert palox_anstieg(0.012, 4, 60, 0.005) is null, '0113 (d5): unter fünf Arbeiten ist der Anstieg nicht unbekannt';
  -- in Zeitfenstern der Demo (vier Längen, je Woche verschoben), am letzten Messtag verankert
  select max(e.messtag) into v_bis from erg_punkte e
   where e.messtag <= heute() and e.quelle in ('verarbeitung', 'verarbeitung_gemischt')
     and e.station in ('sortieren', 'waschen', 'waschen_sortieren');
  create temp table t113_fenster on commit drop as
    select w.laenge, f.i, k.*
      from (values (27), (34), (41), (55)) w(laenge)
      cross join generate_series(0, 25) f(i)
      cross join lateral palox_station_kennzahl(v_bis - f.i * 7, v_bis - f.i * 7 - w.laenge) k
     where palox_anstieg(k.anstieg_roh, k.n_paar, k.spanne_tage) is not null
       and abs(coalesce(k.anstieg_unten, -1)) >= 0.00002;   -- nicht auf der Rundungskante
  select count(*) filter (where anstieg_roh > 0 and anstieg_unten < 0),
         count(*) filter (where anstieg_roh > 0 and anstieg_unten > 0)
    into v_n, v_x from t113_fenster;
  assert v_n >= 3 and v_x >= 3,
    format('0113 (d6): die Demo hat zu wenig unsichere (%s) oder sichere (%s) Anstiege in den Fenstern — (d7) wäre blind', v_n, v_x);
  select count(*) filter (where zuwachs_je_woche is distinct from
                                 case when anstieg_roh > 0 and anstieg_unten > 0 then anstieg_roh else 0 end
                             or abs(grund - greatest(anteil_mittel - zuwachs_je_woche * lager_mittel / 7.0, 0)) > 0.0002)
    into v_ab from t113_fenster;
  assert v_ab = 0, format('0113 (d7): in %s Fenstern gilt der Anstieg nicht nach der Regel (sicher: gemessen; unsicher: 0, Grundausschuss = Mittel)', v_ab);
  assert not exists (select 1 from t113_fenster
                      where anstieg_roh > 0 and anstieg_unten < 0 and coalesce(zuwachs_text, '') !~ '^Anstieg noch nicht sicher'),
    '0113 (d8): ein unsicherer Anstieg sagt nicht, dass er noch nicht sicher ist';

  -- (e) Stand
  assert schema_stand() >= 113, format('0113 (e1): schema_stand() = %s', schema_stand());

  if v_geladen then perform demo_daten_entfernen(); end if;
  delete from profil where id = v_u; delete from auth.users where id = v_u;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0113 — einmal als Demeter geliefert ist Demeter, sonst Knospe (aus Perigon, vom Produzenten, sonst angenommen); CH-K ist Knospe; das Lager je Charge und Artikel ergibt dieselben Zahlen; der Palox-Anstieg gilt erst, wenn er sicher ist';
end $$;

select '——— 0113 Demeter, wenn je Demeter; Lager je Charge und Artikel; Anstieg erst sicher ———' as ergebnis;
