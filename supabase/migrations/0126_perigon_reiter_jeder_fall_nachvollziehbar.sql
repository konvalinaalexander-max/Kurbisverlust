-- 0126 — Ein Reiter für Perigon: jeder Fall nachvollziehbar und mitverfolgt
--
-- WARUM
--
-- Der Betrieb, 24. Oktober: „Perigon nennt die Charge, teilt ihr aber keine
-- Menge zu (Spalte S = 0), oder Chargenzeilen, die zusammen mehr ergeben als
-- die Position — oder weniger —, oder Positionen ganz ohne Charge … mach einen
-- neuen Reiter und behandle dort die Ungereimtheiten mit viel Detail, mit viel
-- Rückverfolgbarkeit, so dass man es nachvollziehen kann — was sind die
-- Fehler —, dass man sie anklicken und dann auch mitverfolgen kann. Das wird
-- für uns als Betrieb immer wichtiger." Und: „alles, was du im PDF hast, dort
-- in den Reiter — das mit 1719 etc. — alles schön nachvollziehbar."
--
-- Bis hier prüfte die App die Perigon-Zeilen in v_perigon_pruefung (0116,
-- 0118, 0121) auf fünf Arten, zeigte sie in einer Karte unter „Lager nach
-- Artikel" und in der Leiste oben. Was der Bericht vom 23. Oktober über die
-- Dateien fand, sah sie nicht: Positionen, die Chargen nennen und ihnen in
-- Spalte S nichts zuteilen; Chargenzeilen, die zusammen mehr ergeben als die
-- Position (dreimal dieselbe Zeile); Positionen ganz ohne Chargennummer; ein
-- Artikelname, der der Preisgruppe widerspricht; „Kürbis Mix" auf einer
-- einzigen Charge; Stück ohne Stückgewicht; Positionen, deren Lieferungen in
-- der Rechnung nicht die Masse der Datei ergeben. Und nichts davon liess sich
-- verfolgen: wer hat es gesehen, wem gemeldet, ist es in Perigon berichtigt?
--
-- 1. v_perigon_befund — jeder Fall einer Perigon-Position, mit einem
--    Schlüssel, der von Rechnen zu Rechnen gleich bleibt (Art, Firma,
--    Position, bei Chargenzeilen Nummer und Lauf), den Zahlen der Datei
--    (Menge Q, Gewicht AE, Masse, den Chargen zugeteilt S × AE, in der
--    Rechnung), dem Satz in Worten, was zu tun ist und wo (Perigon,
--    Stammdaten, Einlesen, Firma fragen, nichts). Die alte Sicht
--    v_perigon_pruefung bleibt stehen; die App liest ab hier die neue.
-- 2. v_perigon_stand — je Firma, was eingelesen ist, bis wann, aus welcher
--    Datei, wie viele Positionen ihre ganze Zeile (roh) noch nicht haben und
--    wie viele Fälle offen sind.
-- 3. perigon_vermerk — der Betriebsleiter hält je Fall fest, wie es steht
--    (offen, in Abklärung, erledigt, kein Fehler) und warum; nur anhängen,
--    nie ändern oder löschen: der Verlauf ist die Spur.
-- 4. perigon_fall_spur — seit wann die App einen Fall sieht und seit wann
--    nicht mehr; gemerkt nach jedem fertigen Rechenlauf
--    (perigon_faelle_merken, ausgelöst von auswertung_stand.berechnet_ts).
--    Ein Fall, der aus den Daten verschwindet, weil Perigon berichtigt und
--    die Datei neu eingelesen ist, steht danach als „nicht mehr in den
--    Daten seit …" im Verlauf — mit dem, was er war (schnappschuss).
-- 5. v_perigon_verlauf — je Schlüssel der letzte Stand, die letzte Notiz,
--    wie viele Vermerke, erst gesehen, weg seit.
--
-- Nichts wird umgebucht, nichts in Perigon geschrieben. Die App sagt, wo.

-- =====================================================================
-- 0. Kilo in einem Satz: ganze Kilo ab 100, sonst eine Stelle
-- =====================================================================
create or replace function kg_wort(p numeric) returns text
language sql immutable parallel safe set search_path = public as $$
  select case when p is null then '?'
              when abs(p) >= 100 then to_char(round(p), 'FM999999990')
              else to_char(round(p, 1), 'FM999990.0') end
$$;
comment on function kg_wort(numeric) is
  'Eine Masse für einen Satz (0126): ganze Kilo ab 100 kg, darunter eine Stelle; ohne Wert ein Fragezeichen, nie 0.';
-- Wie jede Funktion hier: nicht für Nichtangemeldete (pruefung.sql, Funktionsrechte).
revoke all on function kg_wort(numeric) from public;
grant execute on function kg_wort(numeric) to authenticated;

-- =====================================================================
-- 1. Jeder Fall einer Perigon-Position
-- =====================================================================
create or replace view v_perigon_befund with (security_invoker = true) as
with zeile as (
  select z.id, z.quelle, z.pos_id, z.lauf_nr, z.datum, z.kunde, z.artikel_id, z.artikel, z.einheit, z.menge,
         z.gewicht_je_artikel, z.batch_menge, z.kg_position, z.kg_charge, z.preisgruppe, z.liefer_label, z.produzent, z.ts,
         nullif(btrim(z.charge_extern), '') as nummer,
         regexp_replace(coalesce(z.charge_extern, ''), '\D', '', 'g') as ziffern
    from ausgang_zeile z
), lief as (
  -- was die Rechnung aus der Position gemacht hat (ohne Rücknahmen)
  select i.quelle, split_part(i.extern_id, ':', 2)::bigint as pos_id,
         sum(l.kg) as kg, sum(l.kg) filter (where l.charge_nr is null) as kg_ohne,
         count(distinct l.charge_nr)::int as n_chargen, min(l.charge_nr) as charge_nr, min(l.sorte) as sorte
    from lieferung_import i
    join lieferung l on l.id = i.lieferung_id
   where split_part(i.extern_id, ':', 2) ~ '^\d+$' and i.extern_id not like '%:rueckgabe'
   group by 1, 2
), doppelt as (
  -- dieselbe Nummer mehrmals in derselben Position, mit derselben Menge
  select d.quelle, d.pos_id,
         string_agg(format('Charge %s %s', d.nummer, case d.n when 2 then 'zweimal' when 3 then 'dreimal' else d.n || '-mal' end), ', ' order by d.nummer) as text
    from (select quelle, pos_id, nummer, count(*)::int as n from zeile
           where nummer is not null group by 1, 2, 3 having count(*) > 1 and count(distinct batch_menge) = 1) d
   group by 1, 2
), pos as (
  select z.quelle, z.pos_id, min(z.datum) as datum, min(z.kunde) as kunde, min(z.artikel_id) as artikel_id, min(z.artikel) as artikel,
         min(z.einheit) as einheit, max(z.menge) as menge, max(z.gewicht_je_artikel) as gewicht_je_artikel,
         max(z.kg_position) as kg_position, min(z.preisgruppe) as preisgruppe, min(z.liefer_label) as liefer_label,
         min(z.ts) as eingelesen,
         count(*)::int as n_zeilen,
         count(z.nummer)::int as n_nummer,
         count(*) filter (where z.nummer is not null and z.kg_charge > 0)::int as n_menge,
         coalesce(sum(z.kg_charge) filter (where z.nummer is not null and z.kg_charge > 0), 0) as kg_zugeteilt,
         string_agg(distinct z.nummer, ', ' order by z.nummer) as nummern,
         string_agg(distinct z.nummer, ', ' order by z.nummer) filter (where coalesce(z.kg_charge, 0) <= 0) as nummern_ohne_menge
    from zeile z
   group by z.quelle, z.pos_id
), p as (
  select pos.*, f.kg as kg_rechnung, f.kg_ohne,
         case when f.n_chargen = 1 then f.charge_nr end as charge_nr,
         coalesce(f.sorte, aa.sorte) as sorte, d.text as doppelt,
         case when pos.nummern like '%,%' then 'die Chargen ' || pos.nummern else 'die Charge ' || pos.nummern end as chargen_text,
         case when lower(pos.artikel) ~ '(demeter|\mdem\M)' then 'D' when lower(pos.artikel) ~ 'knospe' then 'K' end as label_name,
         case when upper(coalesce(pos.preisgruppe, '')) like 'D%' then 'D'
              when upper(coalesce(pos.preisgruppe, '')) ~ '^(K|CH-K)' then 'K' end as label_preis
    from pos
    left join lief f on f.quelle = pos.quelle and f.pos_id = pos.pos_id
    left join ausgang_artikel aa on aa.artikel_id = pos.artikel_id and aa.artikel = pos.artikel
    left join doppelt d on d.quelle = pos.quelle and d.pos_id = pos.pos_id
), r as (
  -- jede Chargenzeile mit Menge, die eine Lieferung wurde
  select z.*, l.id as lieferung_id, l.charge_nr, l.kg as kg_lieferung, c.sorte, sk.artikelgruppe as gruppe_charge,
         e.gruppe as gruppe_artikel, e.label as label_verkauft,
         case when upper(coalesce(z.liefer_label, '')) like 'D%' then 'D'
              when upper(coalesce(z.liefer_label, '')) ~ '^(K|CH-K)' then 'K' end as label_geliefert,
         (select x.nr from charge x where z.ziffern <> '' and x.nr::text = z.ziffern) as eigene,
         (select array_agg(x.nr order by x.nr) from charge x where z.ziffern <> '' and x.perigon_nr::text = z.ziffern) as an_perigon,
         (select min(pl.eingangsdatum) from palette pl where pl.charge_nr = l.charge_nr) as erster_eingang
    from zeile z
    join lieferung_import i on i.zeile_id = z.id and i.extern_id not like '%:rest' and i.extern_id not like '%:rueckgabe'
    join lieferung l on l.id = i.lieferung_id
    left join charge c on c.nr = l.charge_nr
    left join sorte_kaliber sk on sk.sorte = c.sorte
   -- artikel_einordnen gibt genau eine Zeile; der Planer schätzt sonst 1000 je
   -- Aufruf, hält die Sicht für teuer und übersetzt sie mit JIT (3 s statt 45 ms).
   cross join lateral (select * from artikel_einordnen(z.artikel, z.preisgruppe) limit 1) e
   where z.nummer is not null and coalesce(z.kg_charge, 0) > 0
), fall as (
  -- ---- Position: was die Spalten Q, S, W, AE zusammen sagen ----
  select 'menge_null'::text as art, p.quelle, p.pos_id, null::text as nummer, null::int as lauf_nr, p.charge_nr, p.sorte,
         case when p.kg_position > 0 then p.kg_position end as kg,
         case when p.kg_position > 0
              then format('Perigon nennt %s, teilt aber keine Menge zu: Spalte S („AufPosBatchQuantity Charge") ist 0. Die Position hat %s kg (Spalte Q × AE) — sie bleibt ganz ohne Charge.',
                          p.chargen_text, kg_wort(p.kg_position))
              else format('Perigon nennt %s, aber die Position hat keine Menge — Spalte Q und Spalte S sind 0. Sie zählt nirgends; ging Ware hinaus, fehlt sie im Warenausgang.',
                          p.chargen_text) end as satz,
         'In Perigon bei dieser Position die Menge (Spalte Q) und die Menge je Charge (Spalte S) eintragen, dann die Datei unter Betrieb → Warenausgang neu einlesen.' as tun,
         'perigon' as wo
    from p where p.n_nummer > 0 and p.n_menge = 0
     and (p.kg_position > 0 or (coalesce(p.kg_position, 0) = 0 and coalesce(p.menge, 0) = 0))
  union all
  select 'zu_viel', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, p.kg_zugeteilt - p.kg_position,
         format('Die Chargenzeilen geben zusammen %s kg (Spalte S × AE), die Position nur %s kg (Spalte Q × AE) — %s kg zu viel.%s Die App zählt höchstens die Position: %s.',
                kg_wort(p.kg_zugeteilt), kg_wort(p.kg_position), kg_wort(p.kg_zugeteilt - p.kg_position),
                case when p.doppelt is not null then format(' Dieselbe Zeile steht mehrfach da (%s).', p.doppelt) else '' end,
                case when p.nummern like '%,%' then 'die Chargen bekommen ihre Menge in der Folge der Zeilen, bis die Position voll ist — wie viel welche bekam, sagt die Datei nicht sicher'
                     else format('%s bekommt die %s kg der Position', p.chargen_text, kg_wort(p.kg_position)) end),
         'In Perigon die Menge je Charge (Spalte S) berichtigen — zusammen so viel wie die Position —, eine doppelte Zeile entfernen, dann neu einlesen.',
         'perigon'
    from p where p.kg_position > 0 and p.kg_zugeteilt > p.kg_position + 0.5
  union all
  select 'rest', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, p.kg_position - p.kg_zugeteilt,
         format('Perigon teilt %s nur %s von %s kg zu (Spalte S); %s kg bleiben ohne Charge.%s', p.chargen_text,
                kg_wort(p.kg_zugeteilt), kg_wort(p.kg_position), kg_wort(p.kg_position - p.kg_zugeteilt),
                case when p.nummern_ohne_menge is not null then format(' Ohne Menge genannt: %s.', p.nummern_ohne_menge) else '' end),
         'In Perigon die Menge je Charge (Spalte S) nachtragen, dann neu einlesen. Bis dahin verteilt die App den Rest auf alle Chargen der Sorte.',
         'perigon'
    from p where p.n_menge > 0 and p.kg_position - p.kg_zugeteilt > 0.5
  union all
  select 'keine_nummer', p.quelle, p.pos_id, null, null, null::int, p.sorte, p.kg_position,
         format('In Perigon steht bei dieser Position keine Chargennummer (Spalte W „AuftragsChargeManuell" ist leer) — %s kg ohne Charge.', kg_wort(p.kg_position)),
         'In Perigon die Charge (Spalte W) und die Menge je Charge (Spalte S) eintragen, dann neu einlesen. Bis dahin verteilt die App die Menge auf alle Chargen der Sorte.',
         'perigon'
    from p where p.n_nummer = 0 and p.kg_position > 0
  union all
  select 'ohne_gewicht', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, null::numeric,
         format('%s %s ohne Gewicht je Artikel (Spalte AE ist leer oder 0) — die Masse ist unbekannt; die App zählt die Position nicht, statt 0 kg zu raten.',
                trim(to_char(p.menge, 'FM999999990.###')), coalesce(p.einheit, 'Stück')),
         'In Perigon das Gewicht je Artikel (Spalte AE) eintragen, dann neu einlesen.',
         'perigon'
    from p where p.kg_position is null and coalesce(p.menge, 0) <> 0
  union all
  select 'ruecknahme', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, -p.kg_position,
         format('Negative Menge (%s kg): eine Rücknahme. Die App bucht sie als Rücknahme, nicht als Verkauf.', kg_wort(p.kg_position)),
         'Nichts in der App. Prüfen, ob die Ware wirklich zurückkam.',
         'nichts'
    from p where p.kg_position < 0
  union all
  select 'masse_abweichung', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, coalesce(p.kg_rechnung, 0) - p.kg_position,
         case when p.kg_rechnung is null
              then format('Die Position steht in der Datei (%s kg), aber in der Rechnung gibt es keine Lieferung dazu.', kg_wort(p.kg_position))
              else format('In der Rechnung stehen für diese Position %s kg, die Datei ergibt %s kg — %s kg %s.', kg_wort(p.kg_rechnung), kg_wort(p.kg_position),
                          kg_wort(abs(p.kg_rechnung - p.kg_position)), case when p.kg_rechnung > p.kg_position then 'zu viel' else 'zu wenig' end) end,
         'Die Datei unter Betrieb → Warenausgang neu einlesen: die App legt an, was fehlt, und entfernt, was die Datei nicht mehr ergibt. Eine von Hand geänderte Lieferung bekommt dabei wieder die Masse der Datei.',
         'einlesen'
    from p where p.kg_position > 0 and abs(coalesce(p.kg_rechnung, 0) - p.kg_position) > 0.05
  union all
  select 'label_name', p.quelle, p.pos_id, null, null, p.charge_nr, p.sorte, p.kg_position,
         format('Der Artikel heisst „%s" (%s), verkauft wurde er in der Preisgruppe %s (%s). Die App nimmt die Preisgruppe.', p.artikel,
                case p.label_name when 'D' then 'Demeter' else 'Knospe' end, p.preisgruppe, case p.label_preis when 'D' then 'Demeter' else 'Knospe' end),
         'In Perigon Artikel oder Preisgruppe angleichen — was stimmt, weiss, wer den Auftrag erfasst hat.',
         'perigon'
    from p where p.label_name is not null and p.label_preis is not null and p.label_name <> p.label_preis
  -- ---- Chargenzeile: was die Nummer in Spalte W sagt ----
  union all
  select case when r.eigene is not null or cardinality(r.an_perigon) = 1 then 'nachholen'
              when cardinality(r.an_perigon) > 1 then 'mehrdeutig' else 'unbekannt' end,
         r.quelle, r.pos_id, r.nummer, r.lauf_nr, null::int, null::text, r.kg_lieferung,
         case when r.eigene is not null or cardinality(r.an_perigon) = 1
              then format('Perigon nennt %s; die Nummer steht inzwischen an Charge %s — beim Einlesen kannte die App sie noch nicht.', r.nummer, coalesce(r.eigene, r.an_perigon[1]))
              when cardinality(r.an_perigon) > 1
              then format('Perigon nennt %s; diese Perigon-Nummer steht an mehreren Chargen (%s), und der Artikel sagt nicht, an welcher.', r.nummer, array_to_string(r.an_perigon, ', '))
              else format('Perigon nennt %s — diese Nummer steht an keiner Charge der App.', r.nummer) end,
         case when r.eigene is not null or cardinality(r.an_perigon) = 1
              then 'Nichts — beim nächsten Rechnen („Neu rechnen" oben) bekommt der Lieferschein die Charge von selbst.'
              when cardinality(r.an_perigon) > 1
              then 'Unter Betrieb → Stammdaten → Chargen die Nummer nur bei der richtigen Charge lassen; beim nächsten Rechnen bekommt der Lieferschein sie.'
              else 'Unter Betrieb → Stammdaten → Chargen bei der richtigen Charge als Perigon-Nr. eintragen; beim nächsten Rechnen bekommt der Lieferschein sie von selbst. Ist die Nummer ein Tippfehler, in Perigon berichtigen.' end,
         case when r.eigene is not null or cardinality(r.an_perigon) = 1 then 'nichts' else 'stammdaten' end
    from r where r.charge_nr is null
  union all
  select 'artikel_sorte', r.quelle, r.pos_id, r.nummer, r.lauf_nr, r.charge_nr, r.sorte, r.kg_lieferung,
         format('Verkauft als %s („%s"), aber die Charge %s ist %s — und %s geht als %s. Entweder steht der falsche Artikel oder die falsche Charge auf dem Lieferschein.',
                r.gruppe_artikel, r.artikel, r.charge_nr, r.sorte, r.sorte, r.gruppe_charge),
         'Den Lieferschein ansehen: ist der Artikel falsch, in Perigon den Artikel berichtigen; ist die Charge falsch, die Charge (Spalte W) — dann neu einlesen.',
         'perigon'
    from r where r.charge_nr is not null and r.gruppe_artikel is not null and r.gruppe_charge is not null
     and r.gruppe_artikel not in ('Mix', 'andere') and r.gruppe_artikel <> r.gruppe_charge
  union all
  select 'demeter_knospe', r.quelle, r.pos_id, r.nummer, r.lauf_nr, r.charge_nr, r.sorte, r.kg_lieferung,
         format('Verkauft zum Demeter-Preis (Preisgruppe %s), aber die Ware der Charge %s trägt das Lieferlabel %s — das ist Knospe.', r.preisgruppe, r.charge_nr, r.liefer_label),
         'In Perigon Preisgruppe (Spalte K) und Lieferlabel (Spalte Z) prüfen: wurde Knospe als Demeter verrechnet, oder stimmt das Label nicht?',
         'perigon'
    from r where r.charge_nr is not null and r.label_verkauft = 'D' and r.label_geliefert = 'K'
  union all
  select 'mix', r.quelle, r.pos_id, r.nummer, r.lauf_nr, r.charge_nr, r.sorte, r.kg_lieferung,
         format('Verkauft als „%s" auf Charge %s (%s). Ein Mix ist meist aus mehreren Sorten; die App zieht die ganzen %s kg von %s ab.',
                r.artikel, r.charge_nr, r.sorte, kg_wort(r.kg_lieferung), r.charge_nr),
         'Bei der Firma fragen, woraus der Mix ist. Gehört er zu einer anderen Charge, in Perigon die Charge (Spalte W) berichtigen und neu einlesen; stimmt es, hier „kein Fehler" vermerken.',
         'firma'
    from r where r.charge_nr is not null and r.gruppe_artikel = 'Mix'
  union all
  select 'vor_eingang', r.quelle, r.pos_id, r.nummer, r.lauf_nr, r.charge_nr, r.sorte, r.kg_lieferung,
         format('Geliefert am %s, aber die Charge %s kam laut Erntejournal erst am %s an (%s Tage später) — von ihr kann die Ware nicht sein.',
                to_char(r.datum, 'DD.MM.YYYY'), r.charge_nr, to_char(r.erster_eingang, 'DD.MM.YYYY'), r.erster_eingang - r.datum),
         'Entweder steht die falsche Charge auf dem Lieferschein (in Perigon Spalte W berichtigen) oder das Eingangsdatum im Erntejournal stimmt nicht.',
         'perigon'
    from r where r.charge_nr is not null and r.erster_eingang is not null and r.datum < r.erster_eingang
)
select f.art || ':' || f.quelle || ':' || f.pos_id || coalesce(':' || f.nummer || ':' || f.lauf_nr, '') as schluessel,
       f.art,
       case when f.art in ('nachholen', 'ruecknahme') then 'info'
            when f.art in ('menge_null', 'keine_nummer', 'rest', 'unbekannt', 'mehrdeutig', 'vor_eingang', 'artikel_sorte', 'masse_abweichung')
                 and abs(coalesce(f.kg, 0)) >= 500 then 'rot'
            else 'gelb' end as schwere,
       f.quelle, f.pos_id, p.datum, p.kunde, p.artikel, p.einheit,
       zahl(p.menge, 3, 1e12)::numeric(14,3) as menge,
       zahl(p.gewicht_je_artikel, 4, 1e8)::numeric(12,4) as gewicht_je_artikel,
       p.preisgruppe, p.liefer_label,
       zahl(p.kg_position, 2, 1e12)::numeric(14,2) as kg_position,
       zahl(p.kg_zugeteilt, 2, 1e12)::numeric(14,2) as kg_zugeteilt,
       zahl(p.kg_rechnung, 2, 1e12)::numeric(14,2) as kg_rechnung,
       zahl(p.kg_ohne, 2, 1e12)::numeric(14,2) as kg_ohne_charge,
       zahl(f.kg, 2, 1e12)::numeric(14,2) as kg,
       p.nummern, f.nummer, f.lauf_nr, coalesce(f.charge_nr, p.charge_nr) as charge_nr, coalesce(f.sorte, p.sorte) as sorte,
       p.n_zeilen, f.satz, f.tun, f.wo, p.eingelesen
  from fall f
  join p on p.quelle = f.quelle and p.pos_id = f.pos_id;
comment on view v_perigon_befund is
  'Jeder Fall einer Perigon-Position (0126), je mit einem Schlüssel, der von Rechnen zu Rechnen gleich bleibt (art:quelle:pos_id[:nummer:lauf]). Position: menge_null (Chargen genannt, Spalte S = 0 — auch Q = 0), zu_viel (Chargenzeilen > Position, z.B. dieselbe Zeile mehrfach), rest (Chargenzeilen < Position), keine_nummer (Spalte W leer), ohne_gewicht (Stück ohne Gewicht je Artikel, Masse unbekannt), ruecknahme (negative Menge), masse_abweichung (Lieferungen der Rechnung ≠ Masse der Datei), label_name (Artikelname gegen Preisgruppe). Chargenzeile: nachholen (Nummer inzwischen bekannt), mehrdeutig, unbekannt, artikel_sorte, demeter_knospe, mix (Kürbis Mix auf einer Charge), vor_eingang. kg: die Masse, um die es geht (nie 0 statt unbekannt); satz, tun und wo (perigon, stammdaten, einlesen, firma, nichts). Löst v_perigon_pruefung ab, die stehen bleibt.';
grant select on v_perigon_befund to authenticated;

-- =====================================================================
-- 2. Was von jeder Firma eingelesen ist
-- =====================================================================
create or replace view v_perigon_stand with (security_invoker = true) as
select q.code as quelle, q.name,
       (select count(*) from ausgang_zeile z where z.quelle = q.code)::int as zeilen,
       (select count(distinct z.pos_id) from ausgang_zeile z where z.quelle = q.code)::int as positionen,
       (select min(z.datum) from ausgang_zeile z where z.quelle = q.code) as von,
       (select max(z.datum) from ausgang_zeile z where z.quelle = q.code) as bis,
       d.ts as zuletzt_geladen, d.dateiname as letzte_datei, d.bis_datum as letzte_bis,
       (select count(*) from ausgang_datei x where x.quelle = q.code)::int as dateien,
       -- Positionen ohne ihre ganze Zeile: im Fenster fehlt dann die Excel-Zeile, bis die Datei neu eingelesen ist (0116)
       (select count(*) from (select distinct z.pos_id from ausgang_zeile z where z.quelle = q.code) z
         where not exists (select 1 from ausgang_position ap where ap.quelle = q.code and ap.pos_id = z.pos_id and ap.roh is not null))::int as ohne_roh,
       zahl((select sum(l.kg) from lieferung_import i join lieferung l on l.id = i.lieferung_id
              where i.quelle = q.code and i.extern_id not like '%:rueckgabe'), 1, 1e13)::numeric(14,1) as kg,
       zahl((select sum(l.kg) from lieferung_import i join lieferung l on l.id = i.lieferung_id
              where i.quelle = q.code and l.charge_nr is null and i.extern_id not like '%:rueckgabe'), 1, 1e13)::numeric(14,1) as kg_ohne_charge,
       (select count(*) from v_perigon_befund b where b.quelle = q.code and b.schwere <> 'info')::int as faelle
  from ausgang_quelle q
  left join lateral (select x.ts, x.dateiname, x.bis_datum from ausgang_datei x where x.quelle = q.code order by x.ts desc, x.id desc limit 1) d on true;
comment on view v_perigon_stand is
  'Je Firma (0126): Zeilen und Positionen der laufenden Saison, von–bis, die zuletzt eingelesene Datei (wann, welche, bis wann), wie viele Dateien, wie viele Positionen ihre ganze Zeile noch nicht haben (ohne_roh — dann die Datei neu einlesen), die Masse der Lieferungen, davon ohne Charge, und die offenen Fälle aus v_perigon_befund.';
grant select on v_perigon_stand to authenticated;

-- =====================================================================
-- 3. Was der Betriebsleiter zu einem Fall festhält — nur anhängen
-- =====================================================================
create table if not exists perigon_vermerk (
  id            bigserial primary key,
  schluessel    text not null check (char_length(schluessel) between 3 and 300),
  stand         text not null check (stand in ('offen', 'in_abklaerung', 'erledigt', 'kein_fehler')),
  notiz         text check (notiz is null or char_length(notiz) <= 2000),
  -- was der Fall war, als der Vermerk entstand (Art, Datum, Artikel, Kilo, Satz) — bleibt, auch wenn der Fall verschwindet
  schnappschuss jsonb,
  wer           uuid references profil(id) on delete set null default auth.uid(),
  ts            timestamptz not null default now()
);
create index if not exists perigon_vermerk_schluessel on perigon_vermerk (schluessel, ts desc, id desc);
comment on table perigon_vermerk is
  'Je Perigon-Fall, wie es steht (0126): offen, in_abklaerung (gemeldet, wartet auf Antwort), erledigt (in Perigon berichtigt), kein_fehler (stimmt so) — mit Notiz, wer, wann und dem Fall, wie er war. Nur anhängen: kein Ändern, kein Löschen; der Verlauf ist die Spur.';
alter table perigon_vermerk enable row level security;
drop policy if exists perigon_vermerk_lesen on perigon_vermerk;
drop policy if exists perigon_vermerk_anhaengen on perigon_vermerk;
create policy perigon_vermerk_lesen on perigon_vermerk for select to authenticated using (true);
create policy perigon_vermerk_anhaengen on perigon_vermerk for insert to authenticated
  with check (ist_admin() and wer = auth.uid());
-- Ändern und Löschen bekommt niemand: Angemeldete lesen seit 0008 nur, und hier kommt allein das Anhängen dazu.
grant select, insert on perigon_vermerk to authenticated;
grant usage, select on sequence perigon_vermerk_id_seq to authenticated;

-- =====================================================================
-- 4. Seit wann die App einen Fall sieht — und seit wann nicht mehr
-- =====================================================================
create table if not exists perigon_fall_spur (
  schluessel      text primary key,
  ebene           text not null check (ebene in ('zeile', 'charge')),
  art             text not null,
  erst_gesehen    timestamptz not null,
  zuletzt_gesehen timestamptz not null,
  weg_seit        timestamptz,
  schnappschuss   jsonb not null
);
comment on table perigon_fall_spur is
  'Je Perigon-Fall (Zeile: v_perigon_befund; Charge: v_ungereimtheit), seit wann die App ihn sieht, wann zuletzt, und seit wann nicht mehr (weg_seit) — mit dem Fall, wie er zuletzt war (0126). Geschrieben von perigon_faelle_merken() nach jedem fertigen Rechenlauf.';
alter table perigon_fall_spur enable row level security;
drop policy if exists perigon_fall_spur_lesen on perigon_fall_spur;
create policy perigon_fall_spur_lesen on perigon_fall_spur for select to authenticated using (true);
-- Schreiben tut nur perigon_faelle_merken() (security definer); Angemeldete lesen.
grant select on perigon_fall_spur to authenticated;

-- Der Schlüssel einer Sache aus v_ungereimtheit — gleich gebildet wie in der
-- App (src/auswertung/ungereimt.ts, ausZeile): Art, Charge (sonst Sorte),
-- Arbeit (sonst Prüfung).
create or replace function ungereimt_schluessel(p_art text, p_charge_nr int, p_sorte text, p_mehr jsonb) returns text
language sql immutable parallel safe set search_path = public as $$
  select p_art || ':' || coalesce(p_charge_nr::text, p_sorte, '') || ':' || coalesce(p_mehr ->> 'auftrag_id', p_mehr ->> 'pruefung', '')
$$;
comment on function ungereimt_schluessel(text, int, text, jsonb) is
  'Der Schlüssel einer Sache aus v_ungereimtheit (0126): art:charge|sorte:auftrag|pruefung — derselbe wie in der App (ausZeile).';
revoke all on function ungereimt_schluessel(text, int, text, jsonb) from public;
grant execute on function ungereimt_schluessel(text, int, text, jsonb) to authenticated;

create or replace function perigon_faelle_merken() returns int
language plpgsql security definer set search_path = public set jit = off as $$
declare v_jetzt timestamptz := clock_timestamp(); v_n int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Die Perigon-Fälle merkt sich nur der Betriebsleiter oder der Rechenlauf.' using errcode = '42501';
  end if;
  with jetzt as (
    select distinct on (x.schluessel) x.* from (
      select b.schluessel, 'zeile'::text as ebene, b.art,
             jsonb_build_object('art', b.art, 'schwere', b.schwere, 'quelle', b.quelle, 'pos_id', b.pos_id, 'datum', b.datum,
                                'artikel', b.artikel, 'kunde', b.kunde, 'nummern', b.nummern, 'charge_nr', b.charge_nr,
                                'sorte', b.sorte, 'kg', b.kg, 'satz', b.satz) as schnappschuss
        from v_perigon_befund b
      union all
      select ungereimt_schluessel(u.art, u.charge_nr, u.sorte, u.mehr), 'charge', u.art,
             jsonb_build_object('art', u.art, 'charge_nr', u.charge_nr, 'sorte', u.sorte, 'schlag', u.schlag, 'kg', u.kg,
                                'n', u.n, 'von', u.von, 'bis', u.bis)
        from v_ungereimtheit u
    ) x order by x.schluessel
  ), geschrieben as (
    insert into perigon_fall_spur (schluessel, ebene, art, erst_gesehen, zuletzt_gesehen, weg_seit, schnappschuss)
    select j.schluessel, j.ebene, j.art, v_jetzt, v_jetzt, null, j.schnappschuss from jetzt j
    on conflict (schluessel) do update
      set zuletzt_gesehen = v_jetzt, weg_seit = null, art = excluded.art, ebene = excluded.ebene,
          schnappschuss = excluded.schnappschuss
    returning 1
  )
  select count(*) into v_n from geschrieben;
  update perigon_fall_spur set weg_seit = v_jetzt where weg_seit is null and zuletzt_gesehen < v_jetzt;
  -- Was zu einer entfernten Firma oder Charge gehörte (die Demo, eine doppelt
  -- eingelesene Firma), ist nicht „behoben" — die Spur vergisst es, ausser
  -- jemand hat dazu etwas vermerkt.
  delete from perigon_fall_spur s
   where s.weg_seit is not null
     and not exists (select 1 from perigon_vermerk v where v.schluessel = s.schluessel)
     and ((s.ebene = 'zeile' and not exists (select 1 from ausgang_quelle q where q.code = s.schnappschuss ->> 'quelle'))
       or (s.ebene = 'charge' and s.schnappschuss ->> 'charge_nr' is not null
           and not exists (select 1 from charge c where c.nr::text = s.schnappschuss ->> 'charge_nr')));
  return v_n;
end $$;
comment on function perigon_faelle_merken() is
  'Merkt sich die Perigon-Fälle, die die App jetzt sieht (0126): neue mit erst_gesehen, bekannte mit zuletzt_gesehen; was nicht mehr da ist, bekommt weg_seit; was zu einer entfernten Firma oder Charge gehörte und keinen Vermerk hat, vergisst sie. Läuft nach jedem fertigen Rechenlauf; gibt zurück, wie viele Fälle es jetzt sind.';
revoke all on function perigon_faelle_merken() from public;
grant execute on function perigon_faelle_merken() to authenticated;

-- Nach jedem fertigen Rechenlauf (berechnet_ts neu). Schlägt das Merken fehl,
-- steht der Rechenlauf trotzdem — es fehlt nur die Spur, und der Lauf sagt es.
create or replace function perigon_faelle_nach_lauf() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.berechnet_ts is distinct from old.berechnet_ts and new.berechnet_ts is not null then
    begin
      perform perigon_faelle_merken();
    exception when others then
      raise notice 'perigon_faelle_merken: % — die Spur der Perigon-Fälle ist diesmal nicht nachgeführt', sqlerrm;
    end;
  end if;
  return new;
end $$;
revoke all on function perigon_faelle_nach_lauf() from public;
grant execute on function perigon_faelle_nach_lauf() to authenticated;
drop trigger if exists perigon_faelle_nach_lauf on auswertung_stand;
create trigger perigon_faelle_nach_lauf after update of berechnet_ts on auswertung_stand
  for each row execute function perigon_faelle_nach_lauf();

-- =====================================================================
-- 5. Je Fall: der letzte Stand und die Spur
-- =====================================================================
create or replace view v_perigon_verlauf with (security_invoker = true) as
with letzter as (
  select distinct on (v.schluessel) v.schluessel, v.stand, v.notiz, v.ts, v.wer, v.schnappschuss
    from perigon_vermerk v order by v.schluessel, v.ts desc, v.id desc
), zahl as (
  select v.schluessel, count(*)::int as n from perigon_vermerk v group by v.schluessel
)
select coalesce(s.schluessel, l.schluessel) as schluessel,
       s.ebene, coalesce(s.art, l.schnappschuss ->> 'art') as art,
       s.erst_gesehen, s.zuletzt_gesehen, s.weg_seit,
       coalesce(s.schnappschuss, l.schnappschuss) as schnappschuss,
       coalesce(l.stand, 'offen') as stand, l.notiz, l.ts as vermerk_ts, pr.name as vermerk_von,
       coalesce(z.n, 0) as n_vermerke
  from perigon_fall_spur s
  full join letzter l on l.schluessel = s.schluessel
  left join zahl z on z.schluessel = coalesce(s.schluessel, l.schluessel)
  left join profil pr on pr.id = l.wer;
comment on view v_perigon_verlauf is
  'Je Perigon-Fall (0126): der letzte Stand aus perigon_vermerk (ohne Vermerk: offen), die letzte Notiz, von wem und wann, wie viele Vermerke; dazu aus perigon_fall_spur seit wann die App ihn sieht und seit wann nicht mehr (weg_seit), und was er war (schnappschuss).';
grant select on v_perigon_verlauf to authenticated;

-- =====================================================================
-- Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 126 $$;
