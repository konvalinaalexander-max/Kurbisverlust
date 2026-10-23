-- 0124 — Was der Lager-Ausweis nicht wissen kann, sagt er; die Durchsicht
--        der Runde AZ an der Datenbank
--
-- WARUM
--
-- Runde AZ hat das ganze Programm durchgesehen — „make it all one final
-- sensible product". An der Datenbank blieben fünf Stellen, an denen eine
-- Zahl mehr behauptete, als sie wusste, oder an denen eine Regel fehlte:
--
-- 1. v_lager_ausweis (0123) zog „Sorte ohne Artikel" (artikel_lager_teile:
--    groesse = 'lose') als „passt in keinen Artikel" ab. Das war eine
--    Annahme: Eine Sorte ohne Artikelgruppe in den Stammdaten (Bolp 5110 in
--    der Demo) sagt nicht, dass ihre Ware lose geht — sie sagt, dass niemand
--    eingetragen hat, als was sie verkauft wird. Jetzt ist das offen:
--    gruppe_offen_kg nennt die Masse, verkaufbar_kg zieht sie nicht ab und
--    ist eine obere Schranke, verkaufbar_offen sagt „Artikelgruppe fehlt
--    (Stammdaten → Sorten)". Eine Artikelgruppe, die Gewichte hat, teilt wie
--    bisher; eine ohne Gewichte ist ein Artikel ohne Grösse (lose, wie
--    Mandarin je Stück) und zählt als verkaufbar.
--
-- 2. Ohne Sortier-CSV stand keinen_artikel_kg auf 0. Leer ist nicht null:
--    Ob etwas in kein Artikelgewicht passt, ist ohne Verteilung unbekannt —
--    keinen_artikel_kg bleibt leer, verkaufbar_kg rechnet ohne den Abzug und
--    ist eine obere Schranke (das sagte verkaufbar_offen schon). Ohne
--    Verkaufsfähiges sind auch groesse_offen_kg und gruppe_offen_kg leer.
--
-- 3. Hagel 100 % (charge.hagel_anteil = 1): Die Kaskade kann Unique und
--    Faules dann nicht trennen (hagel_f gibt 1, alles liegt im selben Topf).
--    faul_kg stand trotzdem auf der ganzen Masse, unique_kg leer, verkaufbar
--    auf 0. Jetzt sind faul_kg, unique_kg, hagel_bis_heute_kg und
--    verkaufbar_kg leer, und verkaufbar_offen sagt „Hagel 100 %: Unique und
--    Faules nicht trennbar".
--
-- 4. „Überfüllung nicht gewogen" stand auch da, wenn Paletten gewogen waren,
--    aber die Arbeit kein Kistensystem oder kein Sollgewicht hatte (also keine
--    Überfüllung zu rechnen war). marge_quelle und verkaufbar_offen sagen
--    jetzt, was wirklich fehlt — und wo es nachzutragen ist.
--
-- 5. v_charge_spur (0122) teilte den Ausgang nach Artikel nur über die
--    Perigon-Zeilen; eine von Hand erfasste Lieferung fehlte in nach_artikel,
--    und die Teile gingen nicht auf geliefert_kg auf. Jetzt steht der Rest
--    als eigener Teil „ohne Perigon-Zeile".
--
-- Dazu: Sieben Funktionen in PL/pgSQL hatten keinen festen Suchpfad
--    (search_path) — die anderen schon (0109 (b6) prüft es für die
--    Planungsgrenzen). Jetzt alle; der Prüfblock hält es fest. Die 19
--    Funktionen in SQL ohne SET bleiben so: Postgres setzt sie in die
--    Abfragen der Kaskade ein (inlining), und eine Funktion mit SET wird nie
--    eingesetzt — 0110 (b2) verlangt das für palox_f_nach() ausdrücklich,
--    und 0110 (a1) prüft, dass jede gespeicherte Ansicht mit dem Suchpfad von
--    PostgreSQL 17 rechnet, also jede dieser Funktionen ihre Tabellen mit
--    Schema nennt. Ein erster Entwurf dieser Migration setzte den Suchpfad
--    auch dort; run.sh hat ihn an 0110 (b2) abgefangen.
--    Die Beschreibung von v_koeff_kaliber_geschaetzt sagte noch „per
--    empirischem Bayes zum Gesamtwert gezogen" — das ist seit 0111 nicht
--    mehr so (v_koeff_verdunstung sagte es richtig).
--    Die Liste der Perigon-Nummern (0122) läuft nur noch einmal: Sie trägt
--    sich in einstellung ein; ohne die Marke hätte jedes Einspielen von
--    setup.sql eine Nummer, die der Betriebsleiter unter Stammdaten bewusst
--    gelöscht hat, wieder eingetragen (Änderung direkt in 0122).
--
-- Nichts wird gelöscht; v_lager_ausweis bekommt eine Spalte am Ende
-- (gruppe_offen_kg), alle anderen bleiben, wie sie sind.
-- =====================================================================

-- =====================================================================
-- 1. v_lager_ausweis: leer, wo es leer ist; der Grund, wo einer fehlt
-- =====================================================================
create or replace view v_lager_ausweis with (security_invoker = true) as
with hagel_lager as (
  select k.charge_nr, max(k.hagel) filter (where k.portion = 'lager' and k.m0 > 0) as h,
         sum(case when k.portion <> 'lager' and k.hagel > 0 and k.hagel < 1 then k.m2 * k.hagel / (1 - k.hagel) else 0 end) as hagel_ausgelagert
    from mv_kaskade k group by k.charge_nr
), marge_charge as (
  select m.charge_nr,
         sum(m.zuviel_je_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)
           / nullif(sum(m.soll_kg_pro_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null), 0) as a,
         sum(m.n_wiegungen) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)::int as n_kg,
         bool_or(m.kistensystem = 'stueck') as stueck
    from erg_marge_charge m group by m.charge_nr
), marge_sorte as (
  select m.sorte,
         sum(m.zuviel_je_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)
           / nullif(sum(m.soll_kg_pro_kiste * m.kisten) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null), 0) as a,
         sum(m.n_wiegungen) filter (where m.soll_kg_pro_kiste > 0 and m.zuviel_je_kiste is not null)::int as n_kg,
         bool_or(m.kistensystem = 'stueck') as stueck
    from erg_marge_charge m group by m.sorte
), ohne_system as (
  -- 0124: gewogene Paletten, deren Arbeit kein Kistensystem oder (bei „Kiste
  -- ab") kein Sollgewicht hat — so, wie v_ausgang_kennzahl es ableitet, mit
  -- der Fassung der Arbeit als Rückfall. erg_marge_charge kennt sie nicht;
  -- „nicht gewogen" wäre die falsche Auskunft.
  select k.charge_nr, count(*)::int as n
    from v_ausgang_kennzahl k
   where k.kistensystem is null
      or (k.kistensystem = 'kiste_ab' and coalesce(k.soll_kg_pro_kiste, 0) <= 0)
   group by k.charge_nr
), basis as (
  select c.charge_nr, c.sorte, c.schlag, c.n_rest_paletten as paletten, c.lager_kg as liegend_kg,
         p.lager_kg, p.alter_tage, p.verdunstet_kg, p.verdunstet_je_tag_kg, p.faul_kg as faul_mit_hagel_kg,
         p.gute_ware_kg, p.klein_kg, p.gross_kg, p.fax_kg, p.verkaufsfaehig_kg,
         p.r_bekannt, p.f_bekannt, p.kanal_bekannt, p.fax_bekannt,
         coalesce(hl.h, 0) as h, coalesce(hl.hagel_ausgelagert, 0) as hagel_ausgelagert,
         c.verlust_heute_kg,
         case when mc.a is not null then mc.a
              when mc.stueck then 0
              when ms.a is not null then ms.a
              when ms.stueck then 0 end as marge_anteil,
         case when mc.a is not null then format('gewogen: %s %s dieser Charge', mc.n_kg, case when mc.n_kg = 1 then 'Palette' else 'Paletten' end)
              when mc.stueck then 'Stück-Kisten: ohne Sollgewicht keine Überfüllung'
              when ms.a is not null then format('Sorte %s: %s gewogene %s', c.sorte, ms.n_kg, case when ms.n_kg = 1 then 'Palette' else 'Paletten' end)
              when ms.stueck then 'Stück-Kisten: ohne Sollgewicht keine Überfüllung'
              when os.n > 0 then format('%s gewogene %s, aber die Arbeit hat kein Kistensystem oder kein Sollgewicht — keine Überfüllung zu rechnen (Messungen → Arbeiten → korrigieren)',
                                        os.n, case when os.n = 1 then 'Palette' else 'Paletten' end)
              else 'nicht gewogen' end as marge_quelle,
         coalesce(os.n, 0) as n_ohne_system
    from erg_charge c
    left join erg_prognose p on p.gruppe = 'charge' and p.schluessel = c.charge_nr::text and p.h = 0
    left join hagel_lager hl on hl.charge_nr = c.charge_nr
    left join marge_charge mc on mc.charge_nr = c.charge_nr
    left join marge_sorte ms on ms.sorte = c.sorte
    left join ohne_system os on os.charge_nr = c.charge_nr
), mit_hagel as (
  select b.*,
         case when b.gute_ware_kg is null then null
              when b.h <= 0 then 0::numeric
              when b.h >= 1 then null
              else b.gute_ware_kg * b.h / (1 - b.h) end as unique_kg
    from basis b
), artikel as (
  -- 0123: das Verkaufsfähige der Sortiermaschine auf die Gewichte der Artikel
  -- geteilt (artikel_lager_teile, heute). 0124: „lose" ohne Artikelgruppe ist
  -- offen, nicht „passt in keinen Artikel"; lose mit Artikelgruppe (eine
  -- Gruppe ohne Gewichte) ist ein Artikel ohne Grösse.
  select t.charge_nr,
         sum(t.kg) filter (where t.groesse in ('darunter', 'darueber', 'dazwischen')) as keinen_artikel_kg,
         sum(t.kg) filter (where t.groesse = 'lose' and t.artikelgruppe is null) as gruppe_offen_kg,
         sum(t.kg) filter (where t.groesse = 'ohne Verteilung') as groesse_offen_kg
    from artikel_lager_teile(0) t
   group by t.charge_nr
), verkaufbar as (
  select m.*,
         -- 0124: ohne Sortier-CSV ist unbekannt, was in kein Artikelgewicht passt — leer, nicht 0
         case when m.verkaufsfaehig_kg is null then null
              when m.verkaufsfaehig_kg <= 0 then 0::numeric
              when coalesce(a.groesse_offen_kg, 0) > 0 then null
              else coalesce(a.keinen_artikel_kg, 0) end as keinen_artikel_kg,
         case when m.verkaufsfaehig_kg is null then null
              when m.verkaufsfaehig_kg > 0 then coalesce(a.groesse_offen_kg, 0) else 0::numeric end as groesse_offen_kg,
         case when m.verkaufsfaehig_kg is null then null
              when m.verkaufsfaehig_kg > 0 then coalesce(a.gruppe_offen_kg, 0) else 0::numeric end as gruppe_offen_kg
    from mit_hagel m
    left join artikel a on a.charge_nr = m.charge_nr
), netto as (
  select v.*,
         v.verkaufsfaehig_kg - coalesce(v.keinen_artikel_kg, 0) as als_artikel_kg,
         (v.verkaufsfaehig_kg - coalesce(v.keinen_artikel_kg, 0)) * v.marge_anteil / (1 + v.marge_anteil) as ueberfuellung_kg
    from verkaufbar v
)
select m.charge_nr, m.sorte, m.schlag,
       m.paletten,
       zahl(coalesce(m.lager_kg, m.liegend_kg), 2, 1e12)::numeric(14,2) as eingang_kg,
       m.alter_tage,
       zahl(m.verdunstet_kg, 2, 1e12)::numeric(14,2) as verdunstet_kg,
       zahl(m.verdunstet_je_tag_kg, 2, 1e12)::numeric(14,2) as verdunstet_je_tag_kg,
       -- 0124: bei Hagel 100 % sind Unique und Faules nicht zu trennen — leer, nicht die ganze Masse
       zahl(case when m.h >= 1 then null else m.faul_mit_hagel_kg - coalesce(m.unique_kg, 0) end, 2, 1e12)::numeric(14,2) as faul_kg,
       zahl(m.unique_kg, 2, 1e12)::numeric(14,2) as unique_kg,
       zahl(nullif(m.h, 0), 4, 1e1)::numeric(5,4) as hagel_anteil,
       zahl(m.klein_kg, 2, 1e12)::numeric(14,2) as zu_klein_kg,
       zahl(m.gross_kg, 2, 1e12)::numeric(14,2) as zu_gross_kg,
       zahl(m.fax_kg, 2, 1e12)::numeric(14,2) as fax_kg,
       zahl(m.verkaufsfaehig_kg, 2, 1e12)::numeric(14,2) as verkaufsfaehig_kg,
       zahl(m.marge_anteil, 5, 1e3)::numeric(8,5) as marge_anteil,
       m.marge_quelle,
       zahl(m.verkaufsfaehig_kg * m.marge_anteil / (1 + m.marge_anteil), 2, 1e12)::numeric(14,2) as marge_kg,
       zahl(m.verkaufsfaehig_kg / (1 + m.marge_anteil), 2, 1e12)::numeric(14,2) as verrechenbar_kg,
       zahl(case when m.h >= 1 then null else m.hagel_ausgelagert + coalesce(m.unique_kg, 0) end, 2, 1e12)::numeric(14,2) as hagel_bis_heute_kg,
       coalesce(m.r_bekannt, false) as r_bekannt, coalesce(m.f_bekannt, false) as f_bekannt,
       coalesce(m.kanal_bekannt, false) as kanal_bekannt, coalesce(m.fax_bekannt, false) as fax_bekannt,
       -- 0123: was wir als Artikel tatsächlich verkaufen können
       zahl(m.keinen_artikel_kg, 2, 1e12)::numeric(14,2) as keinen_artikel_kg,
       zahl(m.groesse_offen_kg, 2, 1e12)::numeric(14,2) as groesse_offen_kg,
       zahl(m.ueberfuellung_kg, 2, 1e12)::numeric(14,2) as ueberfuellung_kg,
       zahl(case when m.h >= 1 then null
                 else m.als_artikel_kg - coalesce(m.ueberfuellung_kg, 0) + coalesce(m.unique_kg, 0) end, 2, 1e12)::numeric(14,2) as verkaufbar_kg,
       nullif(concat_ws(', ',
         case when m.h >= 1 then 'Hagel 100 %: Unique und Faules nicht trennbar' end,
         case when m.verkaufsfaehig_kg > 0 and m.marge_anteil is null then
                case when m.n_ohne_system > 0 then 'Überfüllung offen: Paletten gewogen, aber die Arbeit hat kein Kistensystem oder kein Sollgewicht'
                     else 'Überfüllung nicht gewogen' end end,
         case when m.groesse_offen_kg > 0 then 'Grösse offen (keine Sortier-CSV)' end,
         case when m.gruppe_offen_kg > 0 then 'Artikelgruppe fehlt (Stammdaten → Sorten)' end), '') as verkaufbar_offen,
       -- 0124: Ware einer Sorte ohne Artikelgruppe — als was sie verkauft wird, ist offen
       zahl(m.gruppe_offen_kg, 2, 1e12)::numeric(14,2) as gruppe_offen_kg
  from netto m;

comment on view v_lager_ausweis is
  'Was im Lager liegt, Schritt für Schritt, je Charge heute (0121, 0123, 0124): eingang_kg (Eingangsmasse auf den Paletten, die noch stehen — „im Lager") − verdunstet − faul (Palox, ohne Hagel) − unique (Hagel, wird als Knospe verkauft) − zu klein − zu gross (Sortiermaschine) − Faules beim Abpacken = verkaufsfaehig_kg (nach der Sortiermaschine); davon marge_kg Überfüllung (marge_anteil = zu viel ÷ Soll, gewogen je Charge, sonst je Sorte; Stück-Kisten 0), verrechenbar_kg der Rest. verkaufbar_kg = verkaufsfaehig_kg − keinen_artikel_kg (leichter oder schwerer als die Artikelgewichte, artikel_lager_teile; leer ohne Sortier-CSV) − ueberfuellung_kg (auf dem Teil, der als Artikel geht) + unique_kg — was als Artikel tatsächlich verkauft werden kann. groesse_offen_kg: ohne Sortier-CSV; gruppe_offen_kg: Sorte ohne Artikelgruppe (0124) — beides nicht abgezogen, verkaufbar_kg ist dann eine obere Schranke, und verkaufbar_offen sagt, was fehlt. Hagel 100 %: faul_kg, unique_kg und verkaufbar_kg leer (nicht trennbar). hagel_bis_heute_kg: der Hagel-Teil im Faulen bis heute, kein Verlust. Aus erg_prognose (h = 0), erg_charge, mv_kaskade, erg_marge_charge, v_ausgang_kennzahl, artikel_lager_teile(0).';
grant select on v_lager_ausweis to authenticated;

-- =====================================================================
-- 2. v_charge_spur: der Ausgang nach Artikel geht auf
-- =====================================================================
create or replace view v_charge_spur with (security_invoker = true) as
with journal as (
  select coalesce(p.charge_nr_journal, p.charge_nr) as nr, count(*)::int as n,
         sum(vp.netto_kg) as kg, min(p.eingangsdatum) as von, max(p.eingangsdatum) as bis
    from palette p join v_palette vp on vp.id = p.id
   group by 1
), jetzt as (
  select p.charge_nr as nr, count(*)::int as n, sum(vp.netto_kg) as kg
    from palette p join v_palette vp on vp.id = p.id
   group by 1
), zuordnung as (
  select z.von_charge_nr, z.nach_charge_nr, z.stand, count(*)::int as n, sum(vp.netto_kg) as kg
    from palette_zuordnung z join v_palette vp on vp.id = z.palette_id
   where z.stand in ('angewandt', 'vorschlag')
   group by 1, 2, 3
), arbeit as (
  select a.charge_nr as nr, count(*)::int as n,
         min((a.start_ts at time zone 'Europe/Zurich')::date) as von,
         max((a.start_ts at time zone 'Europe/Zurich')::date) as bis,
         jsonb_agg(jsonb_build_object('id', a.id, 'datum', (a.start_ts at time zone 'Europe/Zurich')::date,
                                      'station', a.station, 'zettel', (select count(*) from auftrag_palette ap where ap.auftrag_id = a.id))
                   order by a.start_ts) as liste
    from auftrag a
   where a.abgebrochen_ts is null
   group by a.charge_nr
), lief as (
  select l.charge_nr as nr, count(*)::int as n, sum(l.masse_kg) as kg, min(l.datum) as von, max(l.datum) as bis
    from v_lieferung_masse l
   where l.charge_nr is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge') and l.datum <= heute()
   group by l.charge_nr
), artikel as (
  select l.charge_nr as nr, (artikel_einordnen(z.artikel, z.preisgruppe)).gruppe as gruppe, sum(l.masse_kg) as kg
    from v_lieferung_masse l
    join lieferung_import li on li.lieferung_id = l.id
    join ausgang_zeile z on z.id = li.zeile_id
   where l.charge_nr is not null and l.masse_kg > 0 and l.buch in ('verkauf', 'marge') and l.datum <= heute()
   group by 1, 2
), nach_artikel as (
  -- 0124: was keine Perigon-Zeile hat (von Hand erfasst), steht als eigener
  -- Teil — so gehen die Teile auf geliefert_kg auf.
  select x.nr, coalesce(x.gruppe, 'andere') as gruppe, x.kg from artikel x
  union all
  select f.nr, 'ohne Perigon-Zeile', f.kg - coalesce(a.kg, 0)
    from lief f
    left join (select x.nr, sum(x.kg) as kg from artikel x group by x.nr) a on a.nr = f.nr
   where f.kg - coalesce(a.kg, 0) > 0.5
), nach as (
  select n.charge_nr as nr, n.weg, count(*)::int as n, sum(l.masse_kg) as kg
    from lieferung_nachordnung n join v_lieferung_masse l on l.id = n.lieferung_id
   group by 1, 2
)
select c.nr as charge_nr, c.schlag, c.sorte, sk.artikelgruppe,
       coalesce(j.n, 0) as journal_paletten, zahl(j.kg, 2, 1e12)::numeric(14,2) as journal_kg, j.von as journal_von, j.bis as journal_bis,
       coalesce(t.n, 0) as paletten, zahl(t.kg, 2, 1e12)::numeric(14,2) as eingang_kg,
       (select jsonb_agg(jsonb_build_object('charge_nr', z.nach_charge_nr, 'stand', z.stand, 'paletten', z.n, 'kg', round(z.kg))
                         order by z.stand, z.nach_charge_nr)
          from zuordnung z where z.von_charge_nr = c.nr) as weg,
       (select jsonb_agg(jsonb_build_object('charge_nr', z.von_charge_nr, 'stand', z.stand, 'paletten', z.n, 'kg', round(z.kg))
                         order by z.stand, z.von_charge_nr)
          from zuordnung z where z.nach_charge_nr = c.nr) as her,
       coalesce(a.n, 0) as arbeiten, a.von as arbeit_von, a.bis as arbeit_bis, a.liste as arbeit_liste,
       coalesce(f.n, 0) as lieferscheine, zahl(f.kg, 2, 1e12)::numeric(14,2) as geliefert_kg, f.von as lief_von, f.bis as lief_bis,
       (select jsonb_agg(jsonb_build_object('gruppe', x.gruppe, 'kg', round(x.kg)) order by x.kg desc)
          from nach_artikel x where x.nr = c.nr) as nach_artikel,
       (select jsonb_agg(jsonb_build_object('weg', x.weg, 'n', x.n, 'kg', round(x.kg)) order by x.weg)
          from nach x where x.nr = c.nr) as nachgeordnet,
       zahl(b.n_rest_paletten, 1, 1e6)::numeric(7,1) as rest_paletten
  from charge c
  left join sorte_kaliber sk on sk.sorte = c.sorte
  left join journal j on j.nr = c.nr
  left join jetzt t on t.nr = c.nr
  left join arbeit a on a.nr = c.nr
  left join lief f on f.nr = c.nr
  left join erg_charge b on b.charge_nr = c.nr
 where j.n is not null or t.n is not null or a.n is not null or f.n is not null;
comment on view v_charge_spur is
  'Der Weg der Ware je Charge (0122): herein laut Erntejournal (journal_*: die Charge, die das Journal nennt) und wie die App jetzt zählt (paletten, eingang_kg), was umgebucht ist oder vorgeschlagen (weg: von hier weg, her: hierher), bearbeitet in der Halle (Arbeiten, mit Zahl der Zettel), hinaus laut Lieferscheinen (Lieferscheine; nach_artikel: je Artikelgruppe aus den Perigon-Zeilen, der Rest als „ohne Perigon-Zeile" — die Teile gehen auf geliefert_kg auf (0124); davon nachgeordnet), und was laut App noch da ist (rest_paletten).';
grant select on v_charge_spur to authenticated;

-- =====================================================================
-- 3. Beschreibungen, die seit 0111 nicht mehr stimmten
-- =====================================================================
comment on view v_koeff_kaliber_geschaetzt_formel is
  'Zu klein (ausschuss), zu gross (nebenkanal) und Fax je Sorte: seit 0111 das massegewichtete Mittel der eigenen Messungen ab anteil_mindest_messungen() Messungen, sonst das Mittel aller Sorten (b = 0, geliehen); b = 1 heisst: die Sorte trägt sich selbst. Kein Zug zum Gesamtwert mehr; tau2 bleibt leer. — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
comment on view v_koeff_kaliber_geschaetzt is
  'Zu klein (ausschuss), zu gross (nebenkanal) und Fax je Sorte: seit 0111 das massegewichtete Mittel der eigenen Messungen ab anteil_mindest_messungen() Messungen, sonst das Mittel aller Sorten (b = 0, geliehen); b = 1 heisst: die Sorte trägt sich selbst. Seit 0109 über die Planungsgrenze v_koeff_kaliber_geschaetzt_zaun(); die Formel steht in v_koeff_kaliber_geschaetzt_formel.';

-- =====================================================================
-- 4. Ein fester Suchpfad für jede Funktion in PL/pgSQL
-- =====================================================================
-- Die sieben, die bis hier keinen hatten. Wer eine Funktion in PL/pgSQL neu
-- anlegt, gibt ihr „set search_path = public" mit — der Prüfblock 0124 (a)
-- hält es fest. Eine Funktion in SQL bekommt kein SET: Sie soll eingesetzt
-- werden (0110) und nennt ihre Tabellen mit Schema.
alter function auftrag_schema_setzen() set search_path = public;
alter function ausschuss_netto_setzen() set search_path = public;
alter function csv_lauf_speichern(int, text, text, text, timestamptz, text, jsonb, int, int, int, int, jsonb) set search_path = public;
alter function csv_sammel_speichern(int, text, text, text, jsonb, int, int, int, int, jsonb, timestamptz, timestamptz) set search_path = public;
alter function lauf_neu_klassieren(bigint) set search_path = public;
alter function lesung_als_sammel(bigint, timestamptz, timestamptz) set search_path = public;
alter function schimmel_netto_setzen() set search_path = public;

-- =====================================================================
-- Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 124 $$;
