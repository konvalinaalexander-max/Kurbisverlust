-- =====================================================================
-- 0114 — Eine Lieferung ist eine Lieferung; eine zu schnelle Wägung
--        steht einmal da
--
-- Geprüft auf der Demo, unabhängig nachgezählt aus v_lieferung_masse und
-- v_charge_rueckgrat (nicht aus den neuen Sichten selbst):
-- (a) v_lieferung_charge: dieselben Zahlen je Charge und Tag wie die Regel
--     aus 0071 (hier ausgeschrieben); jede Lieferung ist ganz verteilt; die
--     Demo hat Lieferungen ohne Chargennummer auf mehreren Chargen;
-- (b) erg_charge.n_lieferungen: je Charge die Lieferscheine, die von ihr
--     genommen haben, jeder einmal — auch bei mehreren Eingangstagen (die
--     Summe über die Kohorten zählte jeden einmal je Tag);
-- (c) v_lieferung_gruppe: gesamt, je Sorte und je Charge jede Lieferung
--     einmal; die Summe über die Chargen wäre zu gross; ohne Chargennummer
--     richtig gezählt; der Ausgang vor der App zählt nicht als Lieferschein;
-- (d) eine zu schnell leichter gewordene Wägung steht nur als
--     „Verdunstung" da, eine schwerer gewordene weiter als „Wägung";
-- (f) „im Lager" im Verlauf fällt mit den Lieferungen: je Charge und Woche
--     nachgerechnet aus der Kaskade und den Liefertagen; steht still, wenn
--     weder Ware kommt noch geht; fällt, wenn geliefert wird; heute wie die
--     Saisonbilanz; verkaufsfähig nie über dem Lager, die Verdunstung
--     kumuliert nie rückwärts; die Demo hat Wochen, in denen die alte
--     Umschaltung am Liefertag etwas anderes sagte (der Fax geht mit q wie
--     das Lager, ist aber in der Demo und beim Betrieb überall 0 — geprüft
--     wird er im Orakel, K10);
-- (e) Stand 114.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false; v_n int; v_ab int; v_x int;
  v_u uuid := '00000000-0114-0000-0000-000000000001';
  v_schnell bigint; v_schwer bigint; v_c1 int; v_t1 timestamptz; v_c2 int; v_t2 timestamptz;
  v_a numeric; v_b numeric;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0114"}');
  update profil set rolle = 'admin' where id = v_u;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from auftrag where station = 'waschen_sortieren' and bemerkung = 'DEMO') then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform auswertung_aktualisieren();

  -- Die Lieferscheine bis heute, unabhängig: Verkauf und Marge, mit Masse.
  create temp table t114_lief on commit drop as
    select l.id, l.charge_nr, l.sorte from v_lieferung_masse l
     where l.buch in ('verkauf', 'marge') and l.datum <= heute()
       and l.masse_kg is not null and l.masse_kg > 0;
  -- Wohin jede fällt: die eigene Charge, oder ohne Nummer jede Charge der
  -- Sorte mit Eingang.
  create temp table t114_fall on commit drop as
    select t.id, t.charge_nr, false as ohne from t114_lief t where t.charge_nr is not null
    union all
    select t.id, r.charge_nr, true from t114_lief t
      join v_charge_rueckgrat r on r.sorte = t.sorte and r.eingang_netto_kg > 0
     where t.charge_nr is null;

  -- (a) Die Regel aus 0071, ausgeschrieben, gegen die neue Sicht
  select count(*) into v_ab from (
    (select * from v_lieferung_charge_tag
     except
     select charge_nr, datum, buch, zahl(sum(masse_kg * anteil), 2, 1e12)::numeric(14,2), count(distinct id)::int
       from (select l.id, l.datum, l.buch, l.masse_kg, c.charge_nr, c.anteil
               from v_lieferung_masse l
              cross join lateral (
                select l.charge_nr, 1::numeric as anteil where l.charge_nr is not null
                union all
                select r.charge_nr, r.eingang_netto_kg / sum(r.eingang_netto_kg) over ()
                  from v_charge_rueckgrat r
                 where l.charge_nr is null and r.sorte = l.sorte and r.eingang_netto_kg > 0) c
              where l.masse_kg is not null and l.masse_kg > 0
                and l.buch in ('verkauf', 'marge', 'verlust') and l.datum <= heute()
             union all
             select -cv.charge_nr,
                    coalesce((select nullif(wert #>> '{}', '')::date from einstellung where schluessel = 'erfassungsbeginn'), r.letzter_eingang),
                    'verkauf', cv.ausgang_vor_app_kg, cv.charge_nr, 1
               from charge_vorlauf cv join v_charge_rueckgrat r on r.charge_nr = cv.charge_nr
              where cv.ausgang_vor_app_kg > 0) x
      group by charge_nr, datum, buch)
    union all
    (select charge_nr, datum, buch, zahl(sum(masse_kg * anteil), 2, 1e12)::numeric(14,2), count(distinct id)::int
       from (select l.id, l.datum, l.buch, l.masse_kg, c.charge_nr, c.anteil
               from v_lieferung_masse l
              cross join lateral (
                select l.charge_nr, 1::numeric as anteil where l.charge_nr is not null
                union all
                select r.charge_nr, r.eingang_netto_kg / sum(r.eingang_netto_kg) over ()
                  from v_charge_rueckgrat r
                 where l.charge_nr is null and r.sorte = l.sorte and r.eingang_netto_kg > 0) c
              where l.masse_kg is not null and l.masse_kg > 0
                and l.buch in ('verkauf', 'marge', 'verlust') and l.datum <= heute()
             union all
             select -cv.charge_nr,
                    coalesce((select nullif(wert #>> '{}', '')::date from einstellung where schluessel = 'erfassungsbeginn'), r.letzter_eingang),
                    'verkauf', cv.ausgang_vor_app_kg, cv.charge_nr, 1
               from charge_vorlauf cv join v_charge_rueckgrat r on r.charge_nr = cv.charge_nr
              where cv.ausgang_vor_app_kg > 0) x
      group by charge_nr, datum, buch
     except
     select * from v_lieferung_charge_tag)) d;
  assert v_ab = 0, format('0114 (a1): v_lieferung_charge_tag weicht in %s Zeilen von der Regel aus 0071 ab', v_ab);
  select count(*) into v_ab from (
    select id from v_lieferung_charge where id > 0 group by id having abs(sum(anteil) - 1) > 1e-9) x;
  assert v_ab = 0, format('0114 (a2): %s Lieferungen sind nicht ganz auf ihre Chargen verteilt', v_ab);
  select count(*) into v_n from (select id from t114_fall where ohne group by id having count(*) >= 2) x;
  assert v_n >= 1, '0114 (a3): die Demo hat keine Lieferung ohne Chargennummer auf mehreren Chargen — (c2) und (c3) wären blind';

  -- (b) Je Charge jeder Lieferschein einmal
  select count(*) into v_ab
    from erg_charge c
    left join (select charge_nr, count(distinct id)::int as n from t114_fall group by charge_nr) f on f.charge_nr = c.charge_nr
   where c.n_lieferungen is distinct from coalesce(f.n, 0);
  assert v_ab = 0, format('0114 (b1): bei %s Chargen zählt erg_charge.n_lieferungen nicht jeden Lieferschein einmal', v_ab);
  select count(*) into v_n from erg_charge where n_eingangstage >= 2 and n_lieferungen > 0;
  assert v_n >= 3, format('0114 (b2): nur %s Chargen mit mehreren Eingangstagen und Lieferungen — (b1) wäre blind für die Summe über die Tage', v_n);
  select count(*) into v_ab
    from erg_charge c left join v_lieferung_gruppe g on g.gruppe = 'charge' and g.schluessel = c.charge_nr::text
   where c.n_lieferungen > 0 and c.n_lieferungen is distinct from g.n_lieferungen;
  assert v_ab = 0, format('0114 (b3): bei %s Chargen sagen erg_charge und v_lieferung_gruppe nicht dasselbe', v_ab);

  -- (c) Je Gruppe jede Lieferung einmal
  select count(distinct f.id) into v_n from t114_fall f join erg_charge c on c.charge_nr = f.charge_nr;
  assert (select n_lieferungen from v_lieferung_gruppe where gruppe = 'gesamt') = v_n,
    format('0114 (c1): gesamt %s Lieferscheine, nachgezählt %s',
           (select n_lieferungen from v_lieferung_gruppe where gruppe = 'gesamt'), v_n);
  select count(*) into v_ab
    from (select c.sorte, count(distinct f.id)::int as n
            from t114_fall f join erg_charge c on c.charge_nr = f.charge_nr group by c.sorte) s
    full join (select schluessel, n_lieferungen from v_lieferung_gruppe where gruppe = 'sorte') g on g.schluessel = s.sorte
   where s.n is distinct from g.n_lieferungen;
  assert v_ab = 0, format('0114 (c2): bei %s Sorten zählt v_lieferung_gruppe nicht jede Lieferung einmal', v_ab);
  select count(*) into v_n
    from (select c.sorte, sum(c.n_lieferungen) as summe from erg_charge c group by c.sorte) s
    join v_lieferung_gruppe g on g.gruppe = 'sorte' and g.schluessel = s.sorte
   where g.n_lieferungen < s.summe;
  assert v_n >= 1, '0114 (c2b): keine Sorte, bei der die Summe über die Chargen zu gross wäre — (c2) wäre blind';
  select count(distinct f.id) into v_n from t114_fall f join erg_charge c on c.charge_nr = f.charge_nr where f.ohne;
  assert (select n_ohne_charge from v_lieferung_gruppe where gruppe = 'gesamt') = v_n,
    format('0114 (c3): ohne Chargennummer %s, nachgezählt %s',
           (select n_ohne_charge from v_lieferung_gruppe where gruppe = 'gesamt'), v_n);
  select count(*) into v_n from charge_vorlauf cv join erg_charge c on c.charge_nr = cv.charge_nr where cv.ausgang_vor_app_kg > 0;
  assert v_n >= 1, '0114 (c4): die Demo hat keinen Ausgang vor der App — (b1) und (c1) wären blind dafür, ob er als Lieferschein zählt';

  -- (d) Zwei Wägungen der Demo, eine zu schnell leichter, eine schwerer;
  -- danach kommt alles zurück, wie es war.
  create temp table t114_w on commit drop as select id, brutto_jetzt_kg from verdunstung_wiegung;
  select w.id, w.charge_nr, w.wiege_ts into v_schnell, v_c1, v_t1
    from verdunstung_wiegung w join v_verdunstung_messung m on m.id = w.id
   where w.gemessen and not w.sichtbar_schimmel and m.verwendbar and m.lagertage >= 10
   order by w.id limit 1;
  select w.id, w.charge_nr, w.wiege_ts into v_schwer, v_c2, v_t2
    from verdunstung_wiegung w join v_verdunstung_messung m on m.id = w.id
   where w.gemessen and not w.sichtbar_schimmel and m.verwendbar and w.id <> v_schnell
     and (w.charge_nr, w.wiege_ts) is distinct from (v_c1, v_t1)
   order by w.id desc limit 1;
  assert v_schnell is not null and v_schwer is not null, '0114 (d0): die Demo hat keine zwei verwendbaren Wägungen';
  update verdunstung_wiegung set brutto_jetzt_kg = round(brutto_damals_kg * 0.5, 2) where id = v_schnell;
  update verdunstung_wiegung set brutto_jetzt_kg = brutto_damals_kg + 50 where id = v_schwer;
  assert (select grund from v_verdunstung_messung where id = v_schnell) like 'zu schnell%',
    '0114 (d0b): die halbierte Wägung gilt nicht als zu schnell — (d1) wäre blind';
  select count(*) filter (where art = 'Verdunstung'), count(*) filter (where art = 'Wägung') into v_n, v_x
    from v_plausibilitaet where charge_nr = v_c1 and start_ts = v_t1;
  assert v_n = 1 and v_x = 0,
    format('0114 (d1): die zu schnelle Wägung steht %s-mal als Verdunstung und %s-mal als Wägung da (soll: 1 und 0)', v_n, v_x);
  assert exists (select 1 from v_plausibilitaet where art = 'Wägung' and charge_nr = v_c2 and start_ts = v_t2
                                                  and befund like '%mehr als beim Eingang%'),
    '0114 (d2): die schwerer gewordene Wägung steht nicht mehr als Wägung da';
  select count(*) into v_ab
    from (select charge_nr, start_ts from v_plausibilitaet where art = 'Verdunstung'
          intersect
          select charge_nr, start_ts from v_plausibilitaet where art = 'Wägung') d;
  assert v_ab = 0, format('0114 (d3): %s Wägungen stehen als Verdunstung und als Wägung da', v_ab);
  update verdunstung_wiegung w set brutto_jetzt_kg = t.brutto_jetzt_kg from t114_w t where t.id = w.id and w.id in (v_schnell, v_schwer);

  -- (f) „im Lager" im Verlauf fällt mit den Lieferungen. Die Liefertage der
  -- Chargen (verkauft, mit Marge), und je Charge und Woche nachgerechnet: ein
  -- Eingangstag liegt ganz im Lager, bis auf den Teil seiner gelieferten
  -- Portion, den die Lieferungen der Charge bis zum Wochenende ausmachen.
  create temp table t114_lt on commit drop as
    select charge_nr, datum, sum(masse_kg) as kg from v_lieferung_charge_tag
     where buch in ('verkauf', 'marge') group by charge_nr, datum;
  create temp table t114_soll on commit drop as
    select x.bis, x.charge_nr,
           sum(case when x.portion = 'ausgelagert' then x.m0 * (1 - x.q) else x.m0 end) as lager_kg
      from (select w.bis, k.charge_nr, k.portion, k.m0,
                   (select coalesce(sum(lt.kg) filter (where lt.datum <= w.bis), 0) / sum(lt.kg)
                      from t114_lt lt where lt.charge_nr = k.charge_nr) as q
              from (select distinct bis from erg_verlauf) w
              join mv_kaskade k on k.kohorte <= w.bis and k.m0 > 0 and k.kohorte is not null) x
     group by x.bis, x.charge_nr;
  select count(*) into v_ab
    from erg_verlauf v left join t114_soll s on s.bis = v.bis and s.charge_nr::text = v.schluessel
   where v.gruppe = 'charge' and (s.lager_kg is null and v.lager_kg <> 0 or abs(v.lager_kg - s.lager_kg) > 0.05);
  assert v_ab = 0, format('0114 (f1): „im Lager" weicht in %s Wochen und Chargen von der Nachrechnung ab', v_ab);
  -- Je Charge zwei aufeinanderfolgende Wochen bis heute, ohne neuen Eingang:
  -- was dazwischen geliefert wurde.
  create temp table t114_paar on commit drop as
    select x.*, (select coalesce(sum(lt.kg), 0) from t114_lt lt
                  where lt.charge_nr::text = x.schluessel and lt.datum > x.bis_vor and lt.datum <= x.bis) as geliefert_kg
      from (select v.schluessel, v.bis, v.lager_kg, v.eingang_kum_kg,
                   lag(v.bis) over w as bis_vor, lag(v.lager_kg) over w as lager_vor, lag(v.eingang_kum_kg) over w as eingang_vor
              from erg_verlauf v where v.gruppe = 'charge' and v.bis <= heute()
            window w as (partition by v.schluessel order by v.bis)) x
     where x.bis_vor is not null and x.eingang_kum_kg = x.eingang_vor;
  select count(*) into v_ab from t114_paar where geliefert_kg = 0 and lager_kg <> lager_vor;
  assert v_ab = 0, format('0114 (f2): in %s Wochen ohne Eingang und ohne Lieferung bewegt sich „im Lager"', v_ab);
  select count(*), count(*) filter (where p.lager_kg >= p.lager_vor) into v_n, v_ab
    from t114_paar p
   where p.geliefert_kg >= 10
     and exists (select 1 from mv_kaskade k where k.charge_nr::text = p.schluessel and k.portion = 'ausgelagert'
                                              and k.m0 > 0 and k.kohorte <= p.bis_vor);
  assert v_ab = 0, format('0114 (f3): in %s von %s Wochen mit Lieferungen fällt „im Lager" nicht', v_ab, v_n);
  assert v_n >= 10, format('0114 (f3b): nur %s Wochen mit Lieferungen ohne neuen Eingang — (f3) wäre blind', v_n);
  -- Heute ist alles geliefert, was geliefert ist: wie die Saisonbilanz.
  select v.lager_kg - b.lager_kg, v.verkaufsfaehig_kg - b.verkaufsfaehig_heute_kg into v_a, v_b
    from erg_verlauf v cross join erg_bilanz b where v.gruppe = 'gesamt' and v.bis = b.heute;
  assert abs(v_a) <= 0.05 and abs(v_b) <= 0.05,
    format('0114 (f4): heute sagt der Verlauf %s kg mehr im Lager und %s kg mehr verkaufsfähig als die Saisonbilanz', v_a, v_b);
  select count(*) into v_ab from erg_verlauf where verkaufsfaehig_kg > lager_kg + 0.01;
  assert v_ab = 0, format('0114 (f5): in %s Zeilen ist mehr verkaufsfähig als im Lager', v_ab);
  select count(*) into v_ab
    from (select verdunstung_kum_kg as v, lag(verdunstung_kum_kg) over w as v_vor
            from erg_verlauf window w as (partition by gruppe, schluessel order by bis)) x
   where x.v < x.v_vor - 0.01;
  assert v_ab = 0, format('0114 (f6): in %s Zeilen fällt die Verdunstung kumuliert zurück', v_ab);
  -- Ohne Wochen, in denen ein Teil geliefert ist und ein Teil nicht, sähe
  -- (f1) die alte Umschaltung am Liefertag nicht.
  select count(*) into v_n
    from (select distinct w.bis, k.charge_nr
            from (select distinct bis from erg_verlauf where bis <= heute()) w
            join mv_kaskade k on k.portion = 'ausgelagert' and k.m0 > 0 and k.kohorte <= w.bis
           where (select coalesce(sum(lt.kg) filter (where lt.datum <= w.bis), 0) / sum(lt.kg)
                    from t114_lt lt where lt.charge_nr = k.charge_nr)
                 <> case when k.kohorte + round(k.alter_tage)::int <= w.bis then 1 else 0 end) x;
  assert v_n >= 10, format('0114 (f7): nur %s Wochen und Chargen, in denen die alte Umschaltung anders rechnete — (f1) wäre blind', v_n);

  -- (e) Stand
  assert schema_stand() >= 114, format('0114 (e1): schema_stand() = %s', schema_stand());

  if v_geladen then perform demo_daten_entfernen(); end if;
  delete from profil where id = v_u; delete from auth.users where id = v_u;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0114 — je Charge und je Gruppe zählt jeder Lieferschein einmal (auch ohne Chargennummer, auch über mehrere Eingangstage), der Ausgang vor der App ist Masse und kein Lieferschein; eine zu schnelle Wägung steht nur als Verdunstung da; „im Lager" im Verlauf fällt mit den Lieferungen';
end $$;

select '——— 0114 Eine Lieferung ist eine Lieferung; die zu schnelle Wägung einmal ———' as ergebnis;
