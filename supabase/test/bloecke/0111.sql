
-- =====================================================================
-- 0111 — Palox: Grundausschuss und Anstieg; jeder Anteil schlicht
--
-- Geprüft auf der Demo, jede Zahl ein zweites Mal anders gerechnet:
-- (a) der Schätzer je Sorte — eigenes Mittel ab drei Messungen, sonst das
--     aller Sorten; kein Zug zum Gesamtwert; die Basis sagt die Ebene;
-- (b) die Regel des Anstiegs (palox_anstieg) an gebauten Fällen, auch
--     negativ und knapp unter den Schwellen;
-- (c) der Anstieg je Station, innerhalb der Sorten nachgerechnet, und die
--     Kennzahl hält sich an die Regel;
-- (d) der Grundausschuss je Sorte und Station: das Mittel, um den Anstieg
--     auf null Tage zurückgelegt; geliehen unter drei eigenen Arbeiten;
-- (e) die Kaskade nimmt jeden Stationswert beim Alter seiner Portion,
--     Ausgelagertes mit eigener Messung ohne Anstieg;
-- (f) die Prognose trennt zu klein und zu gross;
-- (g) lager_kaliber: Unterkaliber (zu klein), Bänder, Überkaliber (zu
--     gross) — die Bänder sind das Verkaufsfähige, das Geschrumpfte zählt
--     im kleinsten Band;
-- (h) zwei Läufe derselben Charge: Median und Rate stimmen;
-- (i) Stand 111.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false; v_n int; v_ab int; v_x int;
  v_u uuid := '00000000-0111-0000-0000-000000000001';
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0111"}');
  update profil set rolle = 'admin' where id = v_u;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from auftrag where station = 'waschen_sortieren' and bemerkung = 'DEMO') then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform auswertung_aktualisieren();

  -- (a) Der Schätzer je Sorte: ab drei eigenen Messungen das eigene Mittel
  assert anteil_mindest_messungen() = 3, '0111 (a1): die Schwelle ist nicht mehr drei Messungen';
  -- (a2) b ist 1 genau ab drei eigenen Messungen, sonst 0 — für alle vier Anteile
  select count(*), count(*) filter (where g.b <> case when g.sorte is null or g.n >= 3 then 1 else 0 end)
    into v_n, v_ab
    from (select art, sorte, n, b from v_koeff_verdunstung_geschaetzt
          union all select art, sorte, n, b from v_koeff_kaliber_geschaetzt) g;
  assert v_n > 0 and v_ab = 0, format('0111 (a2): %s von %s Zeilen nehmen die falsche Ebene', v_ab, v_n);
  assert exists (select 1 from v_koeff_kaliber_geschaetzt where n = 2 and b = 0)
     and exists (select 1 from v_koeff_kaliber_geschaetzt where n = 3 and b = 1),
    '0111 (a3): die Demo prüft die Schwelle nicht mehr (zwei Messungen geliehen, drei eigen)';
  -- (a4) das Mittel, nachgerechnet aus den Rohwerten: eigen → Mittel der Sorte, sonst aller Sorten
  select count(*), count(*) filter (where abs(g.mittel - x.soll) > 1e-12)
    into v_n, v_ab
    from (select art, sorte, b, mittel from v_koeff_verdunstung_geschaetzt
          union all select art, sorte, b, mittel from v_koeff_kaliber_geschaetzt) g
    join lateral (
      select sum(r.anteil * r.gewicht) / sum(r.gewicht) as soll
        from (select art, sorte, anteil, gewicht from v_koeff_roh_verdunstung
              union all select art, sorte, anteil, gewicht from v_koeff_roh_kaliber) r
       where r.art = g.art and r.anteil is not null and r.gewicht > 0
         and (g.b = 0 or g.sorte is null or r.sorte = g.sorte)) x on true
   where x.soll is not null;
  assert v_n > 0 and v_ab = 0, format('0111 (a4): %s von %s Mitteln weichen vom nachgerechneten ab', v_ab, v_n);
  -- (a5) die Unsicherheit des eigenen Mittels: Σ w (a − m)² / Σ w / (n − 1)
  select count(*), count(*) filter (where abs(g.varianz - x.soll) > 1e-15)
    into v_n, v_ab
    from v_koeff_kaliber_geschaetzt g
    join lateral (
      select sum(r.gewicht * power(r.anteil - g.mittel, 2)) / sum(r.gewicht) / (count(*) - 1) as soll
        from v_koeff_roh_kaliber r
       where r.art = g.art and r.sorte = g.sorte and r.anteil is not null and r.gewicht > 0) x on true
   where g.b = 1 and g.sorte is not null and g.n >= 3;
  assert v_n > 0 and v_ab = 0, format('0111 (a5): %s von %s Varianzen weichen ab', v_ab, v_n);
  assert not exists (select 1 from v_koeff_verdunstung_geschaetzt where tau2 is not null)
     and not exists (select 1 from v_koeff_kaliber_geschaetzt where tau2 is not null),
    '0111 (a6): es wird wieder zum Gesamtwert gezogen (tau2)';
  -- (a7) die Basis sagt die Ebene — und der Bildschirm erkennt „geliehen" an „alle(r) Sorten"
  select count(*), count(*) filter (where (k.basis ~ 'dieser Sorte') <> (g.b = 1) or (g.b = 0 and k.basis !~ 'alle(r)? Sorten'))
    into v_n, v_ab
    from v_koeff_verdunstung k
    join v_koeff_verdunstung_geschaetzt g on g.art = 'verdunstung' and g.sorte = k.sorte;
  assert v_n > 0 and v_ab = 0, format('0111 (a7): %s von %s Basis-Texten der Verdunstung sagen die falsche Ebene', v_ab, v_n);
  select count(*), count(*) filter (where (k.basis ~ 'dieser Sorte') <> (g.b = 1))
    into v_n, v_ab
    from v_koeff_ausschuss k
    join v_koeff_kaliber_geschaetzt g on g.art = 'ausschuss' and g.sorte = k.sorte
   where g.n_gesamt > 0;
  assert v_n > 0 and v_ab = 0, format('0111 (a8): %s von %s Basis-Texten von zu klein sagen die falsche Ebene', v_ab, v_n);
  assert to_regclass('public.v_koeff_verdunstung_geschaetzt') is not null, '0111 (a9): v_koeff_verdunstung_geschaetzt fehlt';

  -- (b) Die Regel des Anstiegs, an gebauten Fällen
  assert palox_anstieg_mindest_tage() = 21, '0111 (b1): die Spanne ist nicht mehr drei Wochen';
  assert palox_anstieg(0.012, 5, 21) = 0.012, '0111 (b2): fünf Arbeiten und drei Wochen — der Anstieg gilt';
  assert palox_anstieg(-0.008, 5, 21) = 0, '0111 (b3): ein negativer Anstieg gilt als 0, nicht als Heilen';
  assert palox_anstieg(0.012, 4, 60) is null, '0111 (b4): unter fünf Arbeiten ist der Anstieg unbekannt';
  assert palox_anstieg(0.012, 30, 20) is null, '0111 (b5): unter drei Wochen Spanne ist der Anstieg unbekannt';
  assert palox_anstieg(null, 30, 60) is null, '0111 (b6): ohne Steigung kein Anstieg';

  -- (c) Der Anstieg je Station, innerhalb der Sorten nachgerechnet —
  -- anders als die Kennzahl: mit group by statt Fensterfunktionen.
  select count(*), count(*) filter (where abs(k.anstieg_roh - round(x.b * 7, 5)) > 1e-5 or k.n_paar <> x.n_paar or k.spanne_tage <> x.spanne)
    into v_n, v_ab
    from v_palox_station k
    join lateral (
      select sum(p.basis_jetzt_kg * (p.lagertage - m.t) * (p.anteil_station - m.y))
             / nullif(sum(p.basis_jetzt_kg * power(p.lagertage - m.t, 2)), 0) as b,
             count(*) filter (where m.n >= 2)::int as n_paar,
             max(m.spanne)::int as spanne
        from erg_punkte p
        join (select q.sorte, sum(q.basis_jetzt_kg * q.lagertage) / sum(q.basis_jetzt_kg) as t,
                     sum(q.basis_jetzt_kg * q.anteil_station) / sum(q.basis_jetzt_kg) as y,
                     count(*) as n, max(q.lagertage) - min(q.lagertage) as spanne
                from erg_punkte q
               where q.station = k.station and q.plausibel_station and q.anteil_station is not null
                 and q.basis_jetzt_kg > 0 and q.lagertage is not null and q.messtag <= heute()
                 and q.quelle in ('verarbeitung', 'verarbeitung_gemischt')
               group by q.sorte) m on m.sorte = p.sorte
       where p.station = k.station and p.plausibel_station and p.anteil_station is not null
         and p.basis_jetzt_kg > 0 and p.lagertage is not null and p.messtag <= heute()
         and p.quelle in ('verarbeitung', 'verarbeitung_gemischt')) x on true;
  assert v_n = 3 and v_ab = 0, format('0111 (c1): bei %s von %s Stationen weicht der Anstieg vom nachgerechneten ab', v_ab, v_n);
  select count(*), count(*) filter (where k.zuwachs_je_woche is distinct from round(palox_anstieg(k.anstieg_roh, k.n_paar, k.spanne_tage), 5))
    into v_n, v_ab
    from v_palox_station k;
  assert v_n = 3 and v_ab = 0, format('0111 (c2): %s von %s Stationen halten sich nicht an die Regel des Anstiegs', v_ab, v_n);
  assert exists (select 1 from v_palox_station where zuwachs_je_woche > 0 and zuwachs_text is null),
    '0111 (c3): die Demo hat keine Station mit gemessenem Anstieg mehr';
  -- (c4) früh in der Saison: zu wenige Arbeiten — der gemessene Anstieg steht
  -- (anstieg_roh), aber er gilt nicht (zuwachs_je_woche leer), und der Text sagt warum
  select count(*) filter (where k.zuwachs_text like 'Anstieg erst ab fünf Arbeiten%'),
         count(*) filter (where k.zuwachs_text like 'Anstieg erst ab fünf Arbeiten%' and k.zuwachs_je_woche is not null),
         count(*) filter (where k.zuwachs_text like 'Anstieg erst ab fünf Arbeiten%' and k.anstieg_roh is not null)
    into v_n, v_ab, v_x
    from palox_station_kennzahl(date '2026-09-12', date '2026-08-08') k;
  assert v_n >= 1 and v_ab = 0 and v_x >= 1,
    format('0111 (c4): ohne fünf Arbeiten gilt ein gemessener Anstieg (%s von %s Stationen), oder der Text sagt nicht warum', v_ab, v_n);
  -- (c5) der Anstieg wird über die Lagerdauer gemessen, nicht über den Messtag
  assert exists (select 1 from v_palox_station where lager_von is not null and lager_bis > lager_von),
    '0111 (c5): die Kennzahl kennt die Lagerdauern ihrer Arbeiten nicht';
  -- (c6) der Grundausschuss der Station: Mittel − Anstieg × mittlere Lagerdauer / 7
  select count(*), count(*) filter (where abs(k.grund - round(greatest(x.mittel - coalesce(k.zuwachs_je_woche, 0) * x.t / 7.0, 0), 5)) > 2e-5
                                       or abs(k.lager_mittel - round(x.t, 1)) > 0.051)
    into v_n, v_ab
    from v_palox_station k
    join lateral (select sum(p.basis_jetzt_kg * p.anteil_station) / sum(p.basis_jetzt_kg) as mittel,
                         sum(p.basis_jetzt_kg * p.lagertage) / sum(p.basis_jetzt_kg) as t
                    from erg_punkte p
                   where p.station = k.station and p.plausibel_station and p.anteil_station is not null
                     and p.basis_jetzt_kg > 0 and p.lagertage is not null and p.messtag <= heute()
                     and p.quelle in ('verarbeitung', 'verarbeitung_gemischt')) x on true;
  assert v_n = 3 and v_ab = 0, format('0111 (c6): bei %s von %s Stationen ist der Grundausschuss nicht Mittel − Anstieg × Lagerwochen', v_ab, v_n);

  -- (d) Der Grundausschuss je Sorte und Station
  select count(*), count(*) filter (where abs(e.anteil - round(greatest(x.mittel - coalesce(k.zuwachs_je_woche, 0) * x.t / 7.0, 0), 5)) > 1e-5
                                       or abs(e.mittel - round(x.mittel, 5)) > 1e-5)
    into v_n, v_ab
    from erg_palox_erwartung e
    join v_palox_station k on k.station = e.station
    join lateral (
      select sum(p.basis_jetzt_kg * p.anteil_station) / sum(p.basis_jetzt_kg) as mittel,
             sum(p.basis_jetzt_kg * p.lagertage) / sum(p.basis_jetzt_kg) as t
        from v_schimmel_punkte p
       where p.station = e.station and (e.geliehen or p.sorte = e.sorte)
         and p.plausibel_station and p.anteil_station is not null and p.basis_jetzt_kg > 0
         and p.lagertage is not null and p.quelle in ('verarbeitung', 'verarbeitung_gemischt')) x on true;
  assert v_n > 0 and v_ab = 0, format('0111 (d1): %s von %s Grundausschüssen sind nicht Mittel − Anstieg × Lagerwochen', v_ab, v_n);
  select count(*), count(*) filter (where e.geliehen <> (x.n < 3))
    into v_n, v_ab
    from erg_palox_erwartung e
    join lateral (select count(*) as n from v_schimmel_punkte p
                   where p.station = e.station and p.sorte = e.sorte and p.plausibel_station
                     and p.anteil_station is not null and p.basis_jetzt_kg > 0 and p.lagertage is not null
                     and p.quelle in ('verarbeitung', 'verarbeitung_gemischt')) x on true;
  assert v_n > 0 and v_ab = 0, format('0111 (d2): %s von %s Erwartungen leihen falsch (unter drei eigenen Arbeiten: alle Sorten)', v_ab, v_n);
  assert exists (select 1 from erg_palox_erwartung where anstieg_je_woche > 0 and anteil < mittel),
    '0111 (d3): kein Grundausschuss liegt unter dem Mittel, obwohl die Station ansteigt';

  -- (e) Die Kaskade nimmt jeden Stationswert beim Alter seiner Portion
  select count(*), count(*) filter (where abs(k.f_ws - least(greatest(e.anteil + coalesce(z.zuwachs_je_woche, 0) * k.alter_tage / 7.0, 0), 1)) > 1e-9)
    into v_n, v_ab
    from mv_kaskade k
    join erg_palox_erwartung e on e.sorte = k.sorte and e.station = 'waschen_sortieren'
    join v_palox_station z on z.station = 'waschen_sortieren'
   where k.portion = 'lager' and k.f_ws is not null;
  assert v_n > 0 and v_ab = 0, format('0111 (e1): bei %s von %s liegenden Portionen ist W+S nicht Grundausschuss + Anstieg × Alter', v_ab, v_n);
  select count(*), count(*) filter (where abs(k.g_w - least(greatest(e.anteil + coalesce(z.zuwachs_je_woche, 0) * k.alter_tage / 7.0, 0), 1)) > 1e-9)
    into v_n, v_ab
    from mv_kaskade k
    join erg_palox_erwartung e on e.sorte = k.sorte and e.station = 'waschen'
    join v_palox_station z on z.station = 'waschen'
   where k.portion = 'lager' and k.g_w is not null;
  assert v_n > 0 and v_ab = 0, format('0111 (e2): bei %s von %s liegenden Portionen ist Waschen nicht Grundausschuss + Anstieg × Alter', v_ab, v_n);
  -- (e3) Ausgelagertes mit eigener Messung: genau die Messung, kein Anstieg
  select count(*), count(*) filter (where abs(k.f_s - c.anteil) > 1e-9 or k.b_s <> 0)
    into v_n, v_ab
    from mv_kaskade k
    join v_charge_palox c on c.charge_nr = k.charge_nr and c.station = 'sortieren'
   where k.portion = 'ausgelagert';
  assert v_n > 0 and v_ab = 0, format('0111 (e3): %s von %s ausgelagerten Portionen mit eigener Messung schreiben fort', v_ab, v_n);
  -- (e4) und ohne eigene Messung beim Alter am Liefertag
  select count(*), count(*) filter (where abs(k.g_w - least(greatest(e.anteil + coalesce(z.zuwachs_je_woche, 0) * k.alter_tage / 7.0, 0), 1)) > 1e-9
                                       or k.b_w is distinct from z.zuwachs_je_woche)
    into v_n, v_ab
    from mv_kaskade k
    join erg_palox_erwartung e on e.sorte = k.sorte and e.station = 'waschen'
    join v_palox_station z on z.station = 'waschen'
   where k.portion = 'ausgelagert' and k.g_w is not null
     and not exists (select 1 from v_charge_palox c where c.charge_nr = k.charge_nr and c.station = 'waschen');
  assert v_n > 0 and v_ab = 0, format('0111 (e4): %s von %s ausgelagerten Portionen ohne eigene Messung nehmen nicht das Alter am Liefertag', v_ab, v_n);
  -- (e5) f bleibt die Zusammensetzung der Stationswerte über den Weg
  select count(*), count(*) filter (where abs(k.f - palox_f(k.p_hand, k.p_wasch, k.f_ws, k.f_s, k.g_w)) > 1e-9)
    into v_n, v_ab
    from mv_kaskade k where k.f_bekannt and k.portion <> 'entsorgt';
  assert v_n > 0 and v_ab = 0, format('0111 (e5): %s von %s Zeilen: f ist nicht palox_f über die Stationswerte', v_ab, v_n);

  -- (f) Die Prognose trennt zu klein und zu gross
  select count(*), count(*) filter (where abs(klein_kg + gross_kg - kanal_kg) > 0.02)
    into v_n, v_ab from erg_prognose;
  assert v_n > 0 and v_ab = 0, format('0111 (f1): %s von %s Zeilen: zu klein + zu gross ≠ kanal_kg', v_ab, v_n);
  assert exists (select 1 from erg_prognose where klein_kg > 0) and exists (select 1 from erg_prognose where gross_kg > 0),
    '0111 (f2): zu klein oder zu gross ist überall leer';
  select count(*), count(*) filter (where abs(p.klein_kg - x.klein) > 0.02)
    into v_n, v_ab
    from erg_prognose p
    join lateral (select sum(k.m2 * k.a_klein_n) as klein from mv_kaskade k
                   where k.charge_nr = p.schluessel::int and k.portion = 'lager' and k.m0 > 0 and k.alter_tage >= 0) x on true
   where p.gruppe = 'charge' and p.h = 0;
  assert v_n > 0 and v_ab = 0, format('0111 (f3): %s von %s Chargen: zu klein heute ist nicht Masse nach Palox × Anteil zu klein', v_ab, v_n);

  -- (g) lager_kaliber: Unterkaliber = zu klein, Bänder = verkaufsfähig,
  -- Überkaliber = zu gross — dieselben Zahlen wie die Prognose (die Kachel
  -- „davon verkaufsfähig" und die Tabelle dürfen nicht auseinanderlaufen).
  select count(*),
         count(*) filter (where abs(coalesce(b.baender, 0) - c.verkaufsfaehig_kg) > 0.05
                             or abs(u.kg - c.klein_kg) > 0.02
                             or abs(u.kg - p.klein_kg) > 0.02
                             or abs(o.kg - c.gross_kg) > 0.02
                             or abs(c.verkaufsfaehig_kg - p.verkaufsfaehig_kg) > 0.05)
    into v_n, v_ab
    from (select distinct on (schluessel) * from lager_kaliber(0) where gruppe = 'charge') c
    join erg_prognose p on p.gruppe = 'charge' and p.schluessel = c.schluessel and p.h = 0
    left join lateral (select sum(z.kg) as baender from lager_kaliber(0) z
                        where z.gruppe = 'charge' and z.schluessel = c.schluessel and z.klasse = 'kaliber') b on true
    left join lateral (select z.kg from lager_kaliber(0) z where z.gruppe = 'charge' and z.schluessel = c.schluessel and z.klasse = 'unter') u on true
    left join lateral (select z.kg from lager_kaliber(0) z where z.gruppe = 'charge' and z.schluessel = c.schluessel and z.klasse = 'ueber') o on true
   where c.klein_kg is not null;
  assert v_n > 0 and v_ab = 0, format('0111 (g1): %s von %s Chargen: Bänder, Unter- oder Überkaliber gehen nicht auf', v_ab, v_n);
  assert not exists (select 1 from lager_kaliber(0) where klasse = 'kaliber' and kaliber_idx < 0),
    '0111 (g2): eine Band-Zeile unter dem kleinsten Band — das Geschrumpfte gehört ins kleinste Band';
  -- Das Geschrumpfte ist ein Teil des kleinsten Bandes, nie mehr; und es
  -- gibt es (die Demo hat Chargen mit eigener CSV und Verdunstung; ihr
  -- „heute" ist das Saisonende, darum am Stichtag heute).
  select count(*), count(*) filter (where c.geschrumpft_kg > coalesce(k0.kg, 0) + 0.02 or c.geschrumpft_kg < 0)
    into v_n, v_ab
    from (select distinct on (schluessel) * from lager_kaliber(0) where gruppe = 'charge' and basis <> 'keine') c
    left join lateral (select z.kg from lager_kaliber(0) z
                        where z.gruppe = 'charge' and z.schluessel = c.schluessel and z.klasse = 'kaliber' and z.kaliber_idx = 0) k0 on true;
  assert v_n > 0 and v_ab = 0, format('0111 (g2b): bei %s von %s Chargen ist das Geschrumpfte nicht Teil des kleinsten Bandes', v_ab, v_n);
  assert exists (select 1 from lager_kaliber(0) where gruppe = 'charge' and geschrumpft_kg > 0),
    '0111 (g2c): kein einziger Kürbis ist unter das kleinste Band geschrumpft — die Prüfung wäre blind';
  assert exists (select 1 from lager_kaliber(0) where klasse = 'unter' and kg > 0)
     and exists (select 1 from lager_kaliber(0) where klasse = 'ueber' and kg > 0),
    '0111 (g3): Unter- oder Überkaliber fehlt';
  select count(*), count(*) filter (where abs(s.kg - x.kg) > 0.05)
    into v_n, v_ab
    from lager_kaliber(28) s
    join lateral (select sum(z.kg) as kg from lager_kaliber(28) z
                   where z.gruppe = 'charge' and z.sorte = s.schluessel and z.klasse = s.klasse
                     and z.kaliber_idx is not distinct from s.kaliber_idx) x on true
   where s.gruppe = 'sorte';
  assert v_n > 0 and v_ab = 0, format('0111 (g4): %s von %s Sortenzeilen sind nicht die Summe ihrer Chargen', v_ab, v_n);

  -- (h) Zwei Läufe derselben Charge: Median nachgerechnet, Rate aus dem Median
  select count(*), count(*) filter (where v.median_g <> x.median or v.n_kuerbis <> x.n)
    into v_n, v_ab
    from v_lauf_vergleich v
    join lateral (
      select sum(g.anzahl)::int as n,
             (select g2.gewicht_g from sortier_gewicht g2
               where g2.lauf_id = v.lauf_id and g2.klasse <> 'unklassiert' and g2.anzahl > 0 and g2.gewicht_g > 0
                 and (select sum(g3.anzahl) from sortier_gewicht g3
                       where g3.lauf_id = v.lauf_id and g3.klasse <> 'unklassiert' and g3.anzahl > 0 and g3.gewicht_g > 0
                         and g3.gewicht_g <= g2.gewicht_g) >= 0.5 * sum(g.anzahl)
               order by g2.gewicht_g limit 1) as median
        from sortier_gewicht g
       where g.lauf_id = v.lauf_id and g.klasse <> 'unklassiert' and g.anzahl > 0 and g.gewicht_g > 0) x on true;
  assert v_n > 0 and v_ab = 0, format('0111 (h1): %s von %s Läufen: Median oder Stückzahl weichen ab', v_ab, v_n);
  select count(*), count(*) filter (where abs(v.rate_median - (1 - power(v.median_g::numeric / e.median_g, 1.0 / v.tage_seit_erstem))) > 1e-6)
    into v_n, v_ab
    from v_lauf_vergleich v
    join v_lauf_vergleich e on e.lauf_id = v.erster_lauf_id
   where v.tage_seit_erstem >= 7;
  assert v_n > 0 and v_ab = 0, format('0111 (h2): %s von %s Laufpaaren: die Rate ist nicht 1 − (Median/Median)^(1/Tage)', v_ab, v_n);
  assert not exists (select 1 from v_lauf_vergleich where tage_seit_erstem < 7 and rate_median is not null),
    '0111 (h3): unter sieben Tagen Abstand steht eine Rate';

  -- (i) Stand
  assert schema_stand() >= 111, format('0111 (i1): schema_stand() = %s', schema_stand());

  if v_geladen then perform demo_daten_entfernen(); end if;
  delete from profil where id = v_u; delete from auth.users where id = v_u;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0111 — jeder Anteil je Sorte ist das eigene Mittel ab drei Messungen; der Palox ist Grundausschuss + Anstieg je Woche Lagerdauer, beim Alter jeder Portion; zu klein und zu gross getrennt; Unter- und Überkaliber; Läufe derselben Charge nebeneinander';
end $$;

select '——— 0111 Palox: Grundausschuss und Anstieg geprüft ———' as ergebnis;
