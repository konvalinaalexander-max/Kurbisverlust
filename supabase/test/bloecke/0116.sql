-- =====================================================================
-- 0116 — Die Grösse kommt aus der Sortierdatei; Hagel, Ausreisser, Kunden
--        und Pläne
--
-- Geprüft auf der Demo und an gebauten Fällen (Prüffirma PRUEF116):
-- (a) Holz-Palox 45 kg und Plastik-Palox 35 kg Tara, keine Palette;
-- (b) eine Palette ohne eigenes Gewicht rechnet mit ihren Kisten: ohne Tara
--     des Gebindes die Tara je Kiste der Charge mal die Kisten, ohne Zettel
--     das Netto je Kiste (des Eingangstags, sonst der Charge) mal die
--     Kisten; nur ohne Kistenzahl ein Mittel ganzer Paletten; eine
--     Holz-Palox rechnet mit 45 kg;
-- (c) zu klein / zu gross jeder Kaskadenzeile ist die Sortierdatei der
--     Charge, auf den Eingangstag zurück- und auf das Alter der Portion
--     vorgerechnet — unabhängig aus den Kürbissen der Läufe nachgerechnet;
--     beim Alter des Laufs ist es wieder der Anteil der Datei; ohne eigene
--     Läufe die der Sorte, ohne Datei der gemessene Anteil der Sorte; in der
--     Prognose zählt, was beim Eintrocknen über die Grenze geht, zum Wasser;
-- (d) der Hagel: hagel_f; liegt die Ware noch, oder ist sie ohne eigene
--     Messung ausgelagert, kommt er auf den Palox-Anteil, sonst nicht; eine
--     Charge mit Hagel zählt nicht in die geteilten Anteile; 100 % Hagel
--     lässt nichts Verkaufsfähiges;
-- (e) ein von Hand ausgeschlossener Messpunkt steht noch da, zählt aber in
--     keine Rate (Palox, Kontrollwägung, Verdunstung), und kommt mit dem
--     Löschen der Zeile zurück;
-- (f) die neuen Tabellen: Zeilenschutz, nur der Betriebsleiter schreibt;
-- (g) die ganze Perigon-Zeile (roh) bleibt, wenn eine Datei sie nicht
--     mitschickt; die Positionen je Kunde summieren sich zum Vergleich je
--     Kunde; die Prüfungen der Perigon-Zeilen finden jede ihrer Arten;
-- (h) die Demo zeigt Hagel, Ausreisser, Gruppe und Plan und nimmt sie beim
--     Entfernen mit; (i) Stand 116.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false; v_n int; v_n2 int; v_ab int; v_j jsonb;
  v_u uuid := '00000000-0116-0000-0000-000000000001';
  v_w uuid := '00000000-0116-0000-0000-000000000002';
  v_c int; v_sorte text; v_datum date; v_a bigint; v_kg numeric; v_kg2 numeric; v_txt text;
  v_tara_kiste numeric; v_tara_mittel numeric; v_je_kiste_datum numeric; v_je_kiste_charge numeric;
  v_hagel numeric; v_bezug bigint; v_ok boolean;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0116"}');
  update profil set rolle = 'admin' where id = v_u;
  insert into auth.users (id, email, raw_user_meta_data) values (v_w, null, '{"name":"Prüf-0116 Halle"}');
  update profil set rolle = 'arbeiter' where id = v_w;   -- in der Beispieldatenbank wäre jede neue Person Betriebsleiter
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from auftrag where station = 'waschen_sortieren' and bemerkung = 'DEMO') then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform auswertung_aktualisieren();

  -- (a) Die Gebinde des Betriebs
  assert (select tara_kg_pro_kiste = 45 and tara_kg_palette = 0 from gebinde where art = 'Holz Palox')
     and (select tara_kg_pro_kiste = 35 and tara_kg_palette = 0 from gebinde where art = 'Plastik Palox'),
    format('0116 (a1): Holz-Palox %s + %s kg, Plastik-Palox %s + %s kg — erwartet 45 + 0 und 35 + 0',
           (select tara_kg_pro_kiste from gebinde where art = 'Holz Palox'), (select tara_kg_palette from gebinde where art = 'Holz Palox'),
           (select tara_kg_pro_kiste from gebinde where art = 'Plastik Palox'), (select tara_kg_palette from gebinde where art = 'Plastik Palox'));

  -- (b) Paletten ohne eigenes Gewicht, auf ihre Kisten angepasst. Eine
  --     Charge, deren Paletten Netto und Kisten haben; ein Gebinde ohne Tara.
  select p.charge_nr, p.eingangsdatum into v_c, v_datum
    from v_palette p
   where p.netto_kg is not null and p.kisten > 0
   group by p.charge_nr, p.eingangsdatum
  having count(*) >= 2 and count(distinct p.kisten) >= 1
   order by p.charge_nr, p.eingangsdatum limit 1;
  assert v_c is not null, '0116 (b0): keine Charge mit gewogenen Paletten — (b) wäre blind';
  select avg((brutto_kg - netto_kg) / kisten) filter (where netto_kg is not null and kisten > 0),
         avg(brutto_kg - netto_kg) filter (where netto_kg is not null),
         avg(netto_kg / kisten) filter (where netto_kg is not null and kisten > 0)
    into v_tara_kiste, v_tara_mittel, v_je_kiste_charge
    from v_palette where charge_nr = v_c;
  select avg(netto_kg / kisten) filter (where netto_kg is not null and kisten > 0) into v_je_kiste_datum
    from v_palette where charge_nr = v_c and eingangsdatum = v_datum;
  insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette, bemerkung) values ('Prüf 0116 ohne Tara', null, null, 'Prüf-0116');
  insert into auftrag (weg, station, charge_nr, start_ts, eroeffnet_von)
    values ('hand', 'waschen_sortieren', v_c, now() - interval '2 hours', v_u) returning id into v_a;
  -- Zettelgewichte, die keine Palette der Charge treffen (333.33 kg, 512.5 kg)
  insert into auftrag_palette (auftrag_id, eingangsdatum, brutto_zettel_kg, kisten, gebindeart, erfasser) values
    (v_a, v_datum, 333.33, 10, 'Prüf 0116 ohne Tara', v_u),     -- Zettel, Gebinde ohne Tara, Kisten gezählt
    (v_a, v_datum, 333.33, null, 'Prüf 0116 ohne Tara', v_u),   -- Zettel, Gebinde ohne Tara, Kisten nicht gezählt
    (v_a, v_datum, null, 7, 'G2', v_u),                         -- kein Zettel, Eingangstag bekannt
    (v_a, '2000-01-03', null, 5, 'G2', v_u),                    -- kein Zettel, an diesem Tag keine Palette der Charge
    (v_a, v_datum, 512.5, 1, 'Holz Palox', v_u);                -- eine Holz-Palox
  select count(*) filter (where not ok), string_agg(case when not ok then txt end, '; ') into v_ab, v_txt
    from (select x.nr,
                 m.masse_quelle = x.quelle and abs(m.netto_kg - x.soll) < 0.01 as ok,
                 format('%s: %s kg aus %s, erwartet %s kg aus %s', x.nr, round(m.netto_kg, 2), m.masse_quelle, round(x.soll, 2), x.quelle) as txt
            from (select ap.id, row_number() over (order by ap.id) as nr from auftrag_palette ap where ap.auftrag_id = v_a) ap
            join (values (1, 'zettel-kisten-charge', 333.33 - 10 * v_tara_kiste),
                         (2, 'zettel-charge-tara',   333.33 - v_tara_mittel),
                         (3, 'datum-je-kiste',       7 * v_je_kiste_datum),
                         (4, 'charge-je-kiste',      5 * v_je_kiste_charge),
                         (5, 'zettel-kisten',        512.5 - 45)) x(nr, quelle, soll) on x.nr = ap.nr
            join v_auftrag_palette_masse m on m.id = ap.id) t;
  assert v_ab = 0, format('0116 (b1): %s Paletten nicht auf ihre Kisten angepasst — %s', v_ab, v_txt);
  delete from auftrag where id = v_a;
  delete from gebinde where art = 'Prüf 0116 ohne Tara';

  -- (c) Zu klein und zu gross aus der Sortierdatei
  assert (select count(*) from mv_kaliber_quelle where ebene = 'charge') >= 3,
    '0116 (c0): auf der Demo hat keine Charge eigene Sortierläufe — (c) wäre blind';
  -- (c1) Die Fassung: die erste und die letzte Bandgrenze der gültigen Fassung ohne Käufer
  select count(*) into v_ab
    from v_kaliber_fassung f
    join lateral (select s.kaliber_baender from sortierschema s
                   where s.sorte = f.sorte and s.art = 'kaliber' and s.kaeufer is null and s.gilt_ab <= heute()
                   order by s.gilt_ab desc limit 1) s on true
   where f.lo <> (s.kaliber_baender -> 0 ->> 0)::int
      or f.hi <> (s.kaliber_baender -> (jsonb_array_length(s.kaliber_baender) - 1) ->> 1)::int;
  assert v_ab = 0, format('0116 (c1): bei %s Sorten sind die Grenzen nicht die der gültigen Fassung', v_ab);
  -- (c2) Das Alter beim Sortieren liegt zwischen der jüngsten und der ältesten
  --      Palette der Arbeit (Zetteldaten), sonst der Charge am Sortiertag
  select count(*) filter (where l.alter_tage < x.jung - 1e-9 or l.alter_tage > x.alt + 1e-9 or x.alt is null), count(*)
    into v_ab, v_n
    from v_kaliber_lauf l
    cross join lateral (
      select case when l.alter_quelle = 'zettel'
                  then (select min(l.sortiertag - m.eingangsdatum) from v_auftrag_palette_masse m
                         where m.auftrag_id = l.auftrag_id and m.eingangsdatum <= l.sortiertag)
                  else (select min(l.sortiertag - p.eingangsdatum) from v_palette p
                         where p.charge_nr = l.charge_nr and p.eingangsdatum <= l.sortiertag) end as jung,
             case when l.alter_quelle = 'zettel'
                  then (select max(l.sortiertag - m.eingangsdatum) from v_auftrag_palette_masse m
                         where m.auftrag_id = l.auftrag_id and m.eingangsdatum <= l.sortiertag)
                  else (select max(l.sortiertag - p.eingangsdatum) from v_palette p
                         where p.charge_nr = l.charge_nr and p.eingangsdatum <= l.sortiertag) end as alt) x
   where l.alter_tage is not null;
  assert v_n > 0 and v_ab = 0, format('0116 (c2): bei %s von %s Läufen liegt das Alter beim Sortieren ausserhalb der Paletten', v_ab, v_n);
  assert exists (select 1 from v_kaliber_lauf where alter_quelle = 'zettel'),
    '0116 (c3): kein Lauf nimmt sein Alter aus den Zetteldaten seiner Arbeit';
  assert not exists (select 1 from v_kaliber_lauf l join v_koeff_verdunstung k on k.sorte = l.sorte
                      where l.r <> least(greatest(k.mittel, 0), 0.05))
     and exists (select 1 from v_kaliber_lauf where r > 0),
    '0116 (c4): ein Lauf rechnet nicht mit der Verdunstungsrate seiner Sorte (oder keiner mit einer)';
  -- (c5) Jede Kaskadenzeile einer Charge mit eigenen Läufen: die Kürbisse der
  --      Läufe, jeder um (1 − r)^Alter beim Sortieren zurück, auf ganze Gramm,
  --      und um (1 − r)^Alter der Portion vor, gegen die Grenzen.
  with lauf as (
    select l.lauf_id, l.charge_nr, power(1 - l.r, l.alter_tage) as ql
      from v_kaliber_lauf l where l.alter_tage >= 0
  ), kuerbis as (
    select l.charge_nr, round(g.gewicht_g::numeric / l.ql, 0) as g0, g.gewicht_g::numeric / l.ql * g.anzahl as m
      from lauf l join sortier_gewicht g on g.lauf_id = l.lauf_id
     where g.anzahl > 0 and g.gewicht_g > 0
  ), zeile as (
    select k.charge_nr, k.a_klein_n, k.a_gross_n, q.lo, q.hi, power(1 - k.r, k.alter_tage) as q
      from mv_kaskade k join mv_kaliber_quelle q on q.charge_nr = k.charge_nr
     where q.ebene = 'charge' and k.alter_tage is not null
  )
  select count(*), count(*) filter (where abs(z.a_klein_n - n.klein) > 1e-9 or abs(z.a_gross_n - n.gross) > 1e-9)
    into v_n, v_ab
    from zeile z
   cross join lateral (
     select coalesce(sum(u.m) filter (where u.g0 < z.lo / z.q), 0) / sum(u.m) as klein,
            coalesce(sum(u.m) filter (where u.g0 > z.hi / z.q), 0) / sum(u.m) as gross
       from kuerbis u where u.charge_nr = z.charge_nr) n;
  assert v_n > 0 and v_ab = 0,
    format('0116 (c5): %s von %s Kaskadenzeilen tragen nicht den Anteil der Sortierdatei beim Alter der Portion', v_ab, v_n);
  assert exists (select 1 from mv_kaskade k join mv_kaliber_quelle q on q.charge_nr = k.charge_nr
                  where k.portion = 'lager' and k.a_klein_n > 0)
     and exists (select 1 from mv_kaskade k join mv_kaliber_quelle q on q.charge_nr = k.charge_nr
                  where k.portion = 'lager' and k.a_gross_n > 0),
    '0116 (c6): keine liegende Portion mit zu kleinen oder zu grossen aus der Datei — (c5) prüfte nur Nullen';
  -- (c7) Beim Alter des Laufs ist es wieder der Anteil der Datei: eine Charge
  --      mit einem einzigen Lauf, die Massenanteile unter lo und über hi.
  select count(*), count(*) filter (where not (k.klein between d.unter - 1e-9 and d.bis + 1e-9
                                                and k.gross between d.ueber - 1e-9 and d.ab + 1e-9))
    into v_n, v_ab
    from mv_kaliber_quelle q
    join v_kaliber_lauf l on l.charge_nr = q.charge_nr and l.alter_tage >= 0
    cross join lateral (
      select sum(g.gewicht_g::numeric * g.anzahl) filter (where g.gewicht_g < q.lo) / sum(g.gewicht_g::numeric * g.anzahl) as unter,
             sum(g.gewicht_g::numeric * g.anzahl) filter (where g.gewicht_g <= q.lo) / sum(g.gewicht_g::numeric * g.anzahl) as bis,
             coalesce(sum(g.gewicht_g::numeric * g.anzahl) filter (where g.gewicht_g > q.hi), 0) / sum(g.gewicht_g::numeric * g.anzahl) as ueber,
             coalesce(sum(g.gewicht_g::numeric * g.anzahl) filter (where g.gewicht_g >= q.hi), 0) / sum(g.gewicht_g::numeric * g.anzahl) as ab
        from sortier_gewicht g where g.lauf_id = l.lauf_id and g.anzahl > 0 and g.gewicht_g > 0) d
    cross join lateral kaliber_anteil('charge', q.charge_nr::text, q.lo, q.hi, power(1 - l.r, l.alter_tage)) k
   where q.ebene = 'charge' and q.n_laeufe = 1;
  assert v_n > 0 and v_ab = 0,
    format('0116 (c7): bei %s von %s Chargen mit einem Lauf ist der Anteil beim Alter des Laufs nicht der der Datei', v_ab, v_n);
  -- (c8) Ohne eigene Läufe die der Sorte: die Läufe einer Charge kurz ohne Sortiertag
  select q.charge_nr, q.sorte into v_c, v_sorte
    from mv_kaliber_quelle q
   where q.ebene = 'charge'
     and (select count(distinct charge_nr) from v_kaliber_lauf l where l.sorte = q.sorte) >= 2
   order by q.charge_nr limit 1;
  assert v_c is not null, '0116 (c8a): keine Sorte mit Läufen aus zwei Chargen — (c8) wäre blind';
  create temp table kaliber_116 on commit drop as select id, sortiertag from sortier_lauf where charge_nr = v_c;
  update sortier_lauf set sortiertag = null where id in (select id from kaliber_116);
  refresh materialized view mv_kaliber_eingang;
  refresh materialized view mv_kaliber_quelle;
  assert (select ebene = 'sorte' and schluessel = v_sorte from mv_kaliber_quelle where charge_nr = v_c),
    format('0116 (c8): ohne eigene Läufe nimmt die Charge %s nicht die Verteilung ihrer Sorte %s: %s', v_c, v_sorte,
           (select format('%s / %s', ebene, schluessel) from mv_kaliber_quelle where charge_nr = v_c));
  update sortier_lauf s set sortiertag = k.sortiertag from kaliber_116 k where k.id = s.id;
  refresh materialized view mv_kaliber_eingang;
  refresh materialized view mv_kaliber_quelle;
  -- (c9) Ohne Datei der Sorte der gemessene Anteil der Sorte (Läufe und Handmessungen)
  select count(*), count(*) filter (where abs(k.a_klein_n - least(greatest(coalesce(ka.mittel, 0), 0), 1) / n.f) > 1e-9
                                       or abs(k.a_gross_n - least(greatest(coalesce(kn.mittel, 0), 0), 1) / n.f) > 1e-9)
    into v_n, v_ab
    from mv_kaskade k
    left join v_koeff_ausschuss ka on ka.sorte = k.sorte
    left join v_koeff_nebenkanal kn on kn.sorte = k.sorte
   cross join lateral (select greatest(least(greatest(coalesce(ka.mittel, 0), 0), 1) + least(greatest(coalesce(kn.mittel, 0), 0), 1), 1) as f) n
   where not exists (select 1 from mv_kaliber_quelle q where q.charge_nr = k.charge_nr);
  assert v_n > 0 and v_ab = 0,
    format('0116 (c9): %s von %s Kaskadenzeilen ohne Sortierdatei tragen nicht den gemessenen Anteil der Sorte', v_ab, v_n);
  assert not exists (select 1 from mv_kaskade k join mv_kaliber_quelle q on q.charge_nr = k.charge_nr
                      where k.klein_basis not like 'Sortierdatei%' or k.klein_n <> q.n_laeufe),
    '0116 (c10): eine Zeile aus der Sortierdatei sagt nicht, dass sie von dort kommt';
  -- (c11) Die Prognose: zu klein und zu gross ändern sich mit dem Alter. Was
  --       beim Eintrocknen über die Grenze geht, zählt zum Wasser — Wasser +
  --       Fäulnis ist genau, was der Horizont an verkaufsfähiger Ware kostet
  --       (auf zwei Stellen gerundet: drei Rappen Spiel).
  select count(*), count(*) filter (where abs((p0.verkaufsfaehig_kg - p.verkaufsfaehig_kg)
                                              - (p.verlust_wasser_kg + p.verlust_faeulnis_kg)) > 0.03)
    into v_n, v_ab
    from erg_prognose p
    join erg_prognose p0 on p0.gruppe = p.gruppe and p0.schluessel = p.schluessel and p0.h = 0
   where p.gruppe = 'charge' and p.h > 0
     and exists (select 1 from mv_kaliber_quelle q where q.charge_nr::text = p.schluessel);
  assert v_n > 0 and v_ab = 0,
    format('0116 (c11): bei %s von %s Horizonten ergeben Wasser und Fäulnis nicht den Verlust an verkaufsfähiger Ware', v_ab, v_n);

  -- (d) Der Hagel
  assert hagel_f(0.1, null) = 0.1 and hagel_f(0.1, 0) = 0.1 and abs(hagel_f(0.1, 0.2) - 0.28) < 1e-12
     and hagel_f(null, 1) = 1 and hagel_f(null, 0.5) is null and hagel_f(1.5, 0.2) = 1 and hagel_f(0.3, 1) = 1,
    '0116 (d1): hagel_f rechnet nicht 1 − (1 − f) · (1 − Hagel)';
  select c.nr, c.hagel_anteil into v_c, v_hagel from charge c where c.hagel_anteil > 0 order by c.nr limit 1;
  assert v_c is not null, '0116 (d2): die Demo hat keine Charge mit Hagel';
  assert not exists (select 1 from mv_kaskade k join charge c on c.nr = k.charge_nr
                      where coalesce(k.hagel, 0) <> case when c.hagel_anteil is null or k.portion = 'entsorgt' then 0
                                                         when k.portion = 'lager' then c.hagel_anteil
                                                         when k.f_eigen then 0 else c.hagel_anteil end),
    '0116 (d3): der Hagel trifft eine Portion, die er nicht treffen darf (Gemessenes doppelt), oder fehlt, wo er hingehört';
  assert exists (select 1 from mv_kaskade where charge_nr = v_c and portion = 'lager' and hagel = v_hagel),
    '0116 (d4): die liegende Ware der Hagel-Charge trägt keinen Hagel';
  -- (d5) Die geteilten Anteile ohne Hagel-Chargen: so viele Arbeiten, wie
  --      ohne die Hagel-Chargen gemessen sind
  select count(*) filter (where e.n_arbeiten <> x.n), count(*) into v_ab, v_n
    from v_palox_erwartung e
    cross join lateral (
      select count(*)::int as n from v_schimmel_punkte p
       where p.plausibel_station and p.anteil_station is not null and p.basis_jetzt_kg > 0 and p.lagertage is not null
         and p.station = e.station and p.quelle in ('verarbeitung', 'verarbeitung_gemischt')
         and (e.ebene = 'alle' or p.sorte = e.sorte)
         and not exists (select 1 from charge hc where hc.nr = p.charge_nr and hc.hagel_anteil > 0)) x;
  assert v_n > 0 and v_ab = 0, format('0116 (d5): %s von %s geteilten Palox-Anteilen zählen Arbeiten von Hagel-Chargen mit', v_ab, v_n);
  assert exists (select 1 from v_schimmel_punkte p where p.charge_nr = v_c and p.plausibel_station and p.quelle like 'verarbeitung%'),
    '0116 (d6): die Hagel-Charge der Demo hat keine gemessene Arbeit — (d5) wäre blind';
  -- (d7) 100 % Hagel: nichts von der liegenden Ware ist verkaufsfähig
  update charge set hagel_anteil = 1 where nr = v_c;
  perform auswertung_aktualisieren();
  select count(*), count(*) filter (where f <> 1 or verkaufsfaehig_kg > 1e-9) into v_n, v_ab
    from mv_kaskade where charge_nr = v_c and portion = 'lager';
  assert v_n > 0 and v_ab = 0, format('0116 (d7): mit 100 %% Hagel sind %s von %s liegenden Portionen noch verkaufsfähig', v_ab, v_n);
  update charge set hagel_anteil = v_hagel where nr = v_c;
  perform auswertung_aktualisieren();

  -- (e) Von Hand ausgeschlossen
  -- (e1) Palox: der Punkt der Demo steht noch da, aber nicht plausibel
  select x.bezug_id into v_bezug from messung_ausschluss x where x.art = 'palox' and x.grund like 'DEMO%';
  assert v_bezug is not null, '0116 (e1a): die Demo hat keinen ausgeschlossenen Palox-Punkt';
  select p.sorte, p.station into v_sorte, v_txt from v_schimmel_punkte p where p.auftrag_id = v_bezug and p.quelle like 'verarbeitung%';
  assert v_sorte is not null and not exists (select 1 from v_schimmel_punkte where auftrag_id = v_bezug and (plausibel or plausibel_station)),
    '0116 (e1): der ausgeschlossene Palox-Punkt fehlt im Bild oder zählt noch';
  select n_arbeiten into v_n from v_palox_erwartung where sorte = v_sorte and station = v_txt;
  delete from messung_ausschluss where art = 'palox' and bezug_id = v_bezug;
  assert exists (select 1 from v_schimmel_punkte where auftrag_id = v_bezug and plausibel_station),
    '0116 (e2): ohne Ausschluss zählt der Punkt nicht wieder';
  select n_arbeiten into v_n2 from v_palox_erwartung where sorte = v_sorte and station = v_txt;
  assert v_n2 = v_n + 1, format('0116 (e3): der Anteil %s / %s zählt %s Arbeiten mit und %s ohne Ausschluss', v_sorte, v_txt, v_n2, v_n);
  insert into messung_ausschluss (art, bezug_id, grund, erfasser) values ('palox', v_bezug, 'DEMO — Palox randvoll, viele zu kleine darin: nicht typisch', v_u);
  -- (e4) Kontrollwägung: das Faule im Lager zählt nicht mehr
  select w.id into v_bezug
    from verdunstung_wiegung w join v_verdunstung_messung m on m.id = w.id
   where w.faul_kg is not null and w.gemessen and m.netto_jetzt_kg > 0 and m.lagertage > 0
   order by w.id limit 1;
  assert v_bezug is not null, '0116 (e4a): keine Kontrollwägung mit Faulem — (e4) wäre blind';
  select count(*) filter (where plausibel) into v_n from v_schimmel_punkte_formel where quelle = 'lager';
  insert into messung_ausschluss (art, bezug_id, grund, erfasser) values ('palox_lager', v_bezug, 'Prüf-0116', v_u);
  select count(*) filter (where plausibel) into v_n2 from v_schimmel_punkte_formel where quelle = 'lager';
  assert v_n2 = v_n - 1, format('0116 (e4): eine ausgeschlossene Kontrollwägung zählt noch (%s plausible Lagerpunkte vorher, %s nachher)', v_n, v_n2);
  delete from messung_ausschluss where art = 'palox_lager' and bezug_id = v_bezug;
  -- (e5) Verdunstung: die Wägung der Demo steht da, mit dem Grund, und zählt nicht
  select x.bezug_id into v_bezug from messung_ausschluss x where x.art = 'verdunstung' and x.grund like 'DEMO%';
  assert (select not verwendbar and grund = 'von Hand ausgeschlossen' from v_verdunstung_messung where id = v_bezug),
    '0116 (e5): die ausgeschlossene Verdunstungs-Wägung zählt noch oder sagt nicht, warum nicht';
  select m.sorte into v_sorte from v_verdunstung_messung m where m.id = v_bezug;
  select count(*) filter (where verwendbar) into v_n from v_verdunstung_messung where sorte = v_sorte;
  delete from messung_ausschluss where art = 'verdunstung' and bezug_id = v_bezug;
  select count(*) filter (where verwendbar) into v_n2 from v_verdunstung_messung where sorte = v_sorte;
  assert v_n2 = v_n + case when (select grund is null from v_verdunstung_messung where id = v_bezug) then 1 else 0 end
     and (select coalesce(grund, '') <> 'von Hand ausgeschlossen' from v_verdunstung_messung where id = v_bezug),
    '0116 (e6): ohne Ausschluss kommt die Wägung nicht zurück';
  insert into messung_ausschluss (art, bezug_id, grund, erfasser) values ('verdunstung', v_bezug, 'DEMO — Ausreisser', v_u);

  -- (f) Zeilenschutz: lesen alle, schreiben nur der Betriebsleiter
  assert (select bool_and(relrowsecurity) from pg_class where oid in ('messung_ausschluss'::regclass, 'kunde_gruppe'::regclass, 'kunde_plan'::regclass)),
    '0116 (f1): eine der neuen Tabellen hat keinen Zeilenschutz';
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_w::text, true);
  v_ok := false;
  begin insert into messung_ausschluss (art, bezug_id, grund) values ('verdunstung', -116, 'Halle'); exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0116 (f2): eine Arbeiterin konnte eine Messung ausschliessen';
  v_ok := false;
  begin insert into kunde_gruppe (kunde, gruppe) values ('Prüfkunde 116', 'Halle'); exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0116 (f3): eine Arbeiterin konnte eine Kundengruppe setzen';
  v_ok := false;
  begin insert into kunde_plan (saison, kunde, kg) values (2026, 'Prüfkunde 116', 1); exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0116 (f4): eine Arbeiterin konnte eine Planmenge setzen';
  assert (select count(*) from kunde_gruppe) > 0, '0116 (f5): eine Arbeiterin sieht die Kundengruppen nicht';
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  insert into kunde_gruppe (kunde, gruppe) values ('Prüfkunde 116', 'Prüfgruppe');
  insert into kunde_plan (saison, kunde, label, kg) values (2026, 'Prüfkunde 116', 'D', 1200);
  reset role;
  assert (select erfasser = v_u from kunde_gruppe where kunde = 'Prüfkunde 116')
     and (select erfasser = v_u and groesse = '' and artikelgruppe = '' from kunde_plan where kunde = 'Prüfkunde 116'),
    '0116 (f6): der Betriebsleiter konnte nicht schreiben, oder der Erfasser fehlt';
  delete from kunde_gruppe where kunde = 'Prüfkunde 116';
  delete from kunde_plan where kunde = 'Prüfkunde 116';

  -- (g) Perigon
  insert into ausgang_quelle (code, name, dateiname_muster) values ('PRUEF116', 'Prüffirma 0116', 'PRUEF116')
  on conflict (code) do nothing;
  -- (g1) Die ganze Zeile bleibt, wenn eine Datei sie nicht mitschickt, und wird ersetzt, wenn doch
  -- (dazu ein Artikel, der kein Kürbis ist, und einer, dessen Label nur die Preisgruppe sagt — für (g3))
  perform ausgang_historie_uebernehmen('PRUEF116',
    '[{"pos_id": 1, "datum": "2024-10-01", "journal": "A", "kunde": "Prüfkunde 116", "artikel_id": "kürbp116a", "artikel": "Bio-Kürbis Butternut Prüf", "einheit": "kg", "menge": 30, "gewicht_je_artikel": 1,
       "roh": [{"Kunde": "Prüfkunde 116", "Menge": "30", "Einheit": "kg"}]},
      {"pos_id": 2, "datum": "2024-10-02", "journal": "A", "kunde": "Prüfkunde 116", "artikel_id": "zuchp116", "artikel": "Bio Zucchetti grün Prüf", "einheit": "kg", "menge": 12, "gewicht_je_artikel": 1},
      {"pos_id": 3, "datum": "2024-10-03", "journal": "A", "kunde": "Prüfkunde 116", "artikel_id": "kürbp116a", "artikel": "Bio-Kürbis Butternut Prüf", "preisgruppe": "D", "einheit": "kg", "menge": 20, "gewicht_je_artikel": 1}]'::jsonb);
  perform ausgang_historie_uebernehmen('PRUEF116',
    '[{"pos_id": 1, "datum": "2024-10-01", "journal": "A", "kunde": "Prüfkunde 116", "artikel_id": "kürbp116a", "artikel": "Bio-Kürbis Butternut Prüf", "einheit": "kg", "menge": 30, "gewicht_je_artikel": 1}]'::jsonb);
  assert (select roh -> 0 ->> 'Menge' = '30' from ausgang_position where quelle = 'PRUEF116' and pos_id = 1),
    format('0116 (g1): die ganze Zeile ging beim Einlesen ohne sie verloren: %s', (select roh from ausgang_position where quelle = 'PRUEF116' and pos_id = 1));
  perform ausgang_historie_uebernehmen('PRUEF116',
    '[{"pos_id": 1, "datum": "2024-10-01", "journal": "A", "kunde": "Prüfkunde 116", "artikel_id": "kürbp116a", "artikel": "Bio-Kürbis Butternut Prüf", "einheit": "kg", "menge": 32, "gewicht_je_artikel": 1,
       "roh": [{"Kunde": "Prüfkunde 116", "Menge": "32", "Einheit": "kg"}, {"Kunde": "Prüfkunde 116", "Menge": "32", "Charge": "1"}]}]'::jsonb);
  assert (select jsonb_array_length(roh) = 2 and roh -> 0 ->> 'Menge' = '32' from ausgang_position where quelle = 'PRUEF116' and pos_id = 1),
    '0116 (g2): eine neu eingelesene ganze Zeile ersetzt die alte nicht';
  -- (g3) Die Positionen je Kunde summieren sich zum Vergleich je Kunde
  select count(*) into v_ab
    from (select kunde, saison, coalesce(gruppe, '') as gruppe, groesse, coalesce(label, '') as label, sum(kg) as kg, count(*) as n
            from v_kunde_position group by 1, 2, 3, 4, 5) p
    full join (select kunde, saison, coalesce(gruppe, '') as gruppe, groesse, coalesce(label, '') as label, sum(kg) as kg, sum(positionen) as n
                 from v_kunde_tag group by 1, 2, 3, 4, 5) t
      using (kunde, saison, gruppe, groesse, label)
   where p.n is distinct from t.n or coalesce(p.kg, 0) is distinct from coalesce(t.kg, 0);
  assert v_ab = 0, format('0116 (g3): bei %s Kunden, Saisons und Artikeln weichen die Positionen vom Vergleich je Kunde ab', v_ab);
  assert exists (select 1 from v_kunde_position where kunde = 'Prüfkunde 116' and kg = 32 and gruppe = 'Butternut')
     and exists (select 1 from v_kunde_position where kunde = 'Prüfkunde 116' and pos_id = 3 and label = 'D')
     and not exists (select 1 from v_kunde_position where kunde = 'Prüfkunde 116' and pos_id = 2),
    '0116 (g4): die Liste des Kunden zeigt die Butternut-Positionen nicht (oder ohne das Label der Preisgruppe), oder sie zeigt die Zucchetti';
  -- (g5) Die Prüfungen der Perigon-Zeilen: eine unbekannte Charge, eine
  --      Lieferung vor dem Eingang, Demeter verkauft und Knospe geliefert;
  --      die Demo bringt „Artikel passt nicht zur Sorte" mit.
  select c.nr, c.sorte, (select min(eingangsdatum) from palette p where p.charge_nr = c.nr) into v_c, v_sorte, v_datum
    from charge c join sorte_kaliber s on s.sorte = c.sorte
   where exists (select 1 from palette p where p.charge_nr = c.nr)
   order by c.nr limit 1;
  v_j := ausgang_uebernehmen('PRUEF116', 'Prüffirma 0116', '{"dateiname": "p116-1.xlsx", "pruefsumme": "p116-1"}'::jsonb,
    jsonb_build_array(
      jsonb_build_object('pos_id', 601, 'charge_extern', '99116', 'lauf_nr', 1, 'fingerabdruck', 'p116-601',
        'datum', heute(), 'journal', 'A', 'kunde', 'Prüfkunde 116', 'artikel_id', 'kürbp116x', 'artikel', 'Bio Kürbis Prüf',
        'einheit', 'kg', 'menge', 50, 'gewicht_je_artikel', 1, 'batch_menge', 50, 'kg_position', 50, 'kg_charge', 50),
      jsonb_build_object('pos_id', 602, 'charge_extern', v_c::text, 'lauf_nr', 1, 'fingerabdruck', 'p116-602',
        'datum', v_datum - 3, 'journal', 'A', 'kunde', 'Prüfkunde 116', 'artikel_id', 'kürbp116x', 'artikel', 'Bio Kürbis Prüf',
        'einheit', 'kg', 'menge', 40, 'gewicht_je_artikel', 1, 'batch_menge', 40, 'kg_position', 40, 'kg_charge', 40),
      jsonb_build_object('pos_id', 603, 'charge_extern', v_c::text, 'lauf_nr', 1, 'fingerabdruck', 'p116-603',
        'datum', heute(), 'journal', 'A', 'kunde', 'Prüfkunde 116', 'artikel_id', 'kürbp116x', 'artikel', 'Bio Kürbis Prüf',
        'einheit', 'kg', 'menge', 30, 'gewicht_je_artikel', 1, 'batch_menge', 30, 'kg_position', 30, 'kg_charge', 30)),
    jsonb_build_array(
      jsonb_build_object('extern_id', 'PRUEF116:601:99116:1', 'datum', heute(), 'charge_nr', 99116, 'sorte', v_sorte, 'kg', 50, 'kunde', 'Prüfkunde 116'),
      jsonb_build_object('extern_id', format('PRUEF116:602:%s:1', v_c), 'datum', v_datum - 3, 'charge_nr', v_c, 'sorte', v_sorte, 'kg', 40, 'kunde', 'Prüfkunde 116'),
      jsonb_build_object('extern_id', format('PRUEF116:603:%s:1', v_c), 'datum', heute(), 'charge_nr', v_c, 'sorte', v_sorte, 'kg', 30, 'kunde', 'Prüfkunde 116')));
  perform ausgang_historie_uebernehmen('PRUEF116', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('pos_id', 603, 'charge_extern', v_c::text, 'lauf_nr', 1, 'liefer_label', 'K', 'preisgruppe', 'D')));
  select count(*) into v_n from (values ('Charge nicht zugeordnet', 601), ('Lieferung vor dem Eingang', 602),
                                        ('Als Demeter verkauft, als Knospe geliefert', 603)) x(art, pos_id)
   where exists (select 1 from v_perigon_pruefung p where p.quelle = 'PRUEF116' and p.art = x.art and p.pos_id = x.pos_id);
  assert v_n = 3, format('0116 (g5): %s von 3 gebauten Fällen gefunden: %s', v_n,
                         (select string_agg(format('%s (%s)', art, pos_id), '; ') from v_perigon_pruefung where quelle = 'PRUEF116'));
  assert (select befund like '%unter Stammdaten%' from v_perigon_pruefung where quelle = 'PRUEF116' and pos_id = 601),
    '0116 (g6): die unbekannte Charge sagt nicht, was zu tun ist';
  assert not exists (select 1 from v_perigon_pruefung where quelle = 'PRUEF116' and pos_id = 603 and art <> 'Als Demeter verkauft, als Knospe geliefert'),
    '0116 (g7): die gewöhnliche Lieferung fällt aus einem anderen Grund auf';
  assert exists (select 1 from v_perigon_pruefung where art = 'Artikel passt nicht zur Sorte' and quelle = 'DEMO'),
    '0116 (g8): die Demo zeigt keinen Artikel, der nicht zur Sorte seiner Charge passt';
  delete from lieferung where id in (select lieferung_id from lieferung_import where quelle = 'PRUEF116');
  delete from ausgang_zeile where quelle = 'PRUEF116';
  delete from ausgang_datei where quelle = 'PRUEF116';
  delete from ausgang_position where quelle = 'PRUEF116';
  delete from ausgang_quelle where code = 'PRUEF116';

  -- (h) Die Demo zeigt, was neu ist, und nimmt es beim Entfernen mit
  assert exists (select 1 from charge where hagel_anteil > 0)
     and (select count(*) from messung_ausschluss where grund like 'DEMO%') = 2
     and (select count(*) from kunde_gruppe) >= 2 and (select count(*) from kunde_plan) >= 1,
    '0116 (h1): die Demo zeigt Hagel, Ausreisser, Kundengruppe oder Plan nicht';
  -- (Nur, wenn der Block die Demo selbst geladen hat — sonst bliebe sie weg.)
  if v_geladen then
    perform demo_daten_entfernen();
    assert not exists (select 1 from charge where hagel_anteil > 0)
       and not exists (select 1 from messung_ausschluss) and not exists (select 1 from kunde_gruppe)
       and not exists (select 1 from kunde_plan),
      format('0116 (h2): nach dem Entfernen bleiben %s Hagel, %s Ausschlüsse, %s Gruppen, %s Pläne',
             (select count(*) from charge where hagel_anteil > 0), (select count(*) from messung_ausschluss),
             (select count(*) from kunde_gruppe), (select count(*) from kunde_plan));
  end if;

  -- (i) Stand
  assert schema_stand() >= 116, format('0116 (i1): schema_stand() = %s', schema_stand());

  delete from profil where id in (v_u, v_w); delete from auth.users where id in (v_u, v_w);
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0116 — zu klein und zu gross aus der Sortierdatei, auf den Eingangstag zurück und auf jedes Alter vor; Hagel nur, wo keine Messung ihn schon enthält, und nicht in den geteilten Anteilen; ausgeschlossene Messungen stehen da und zählen nicht; Paletten ohne Gewicht rechnen mit ihren Kisten; Palox 45 / 35 kg; die ganze Perigon-Zeile; nur der Betriebsleiter schreibt';
end $$;

select '——— 0116 Die Grösse kommt aus der Sortierdatei; Hagel, Ausreisser, Kunden und Pläne ———' as ergebnis;
