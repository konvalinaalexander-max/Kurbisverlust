-- =====================================================================
-- 0079 — Der Messtag, der Nenner beim Waschen, die Glocke am Stichtag
--
-- Runde R baut die zwei ersten Betriebsleiter-Reiter neu. Diese Migration
-- legt die drei Zahlen, die ihnen noch fehlen. Sie ändert keine
-- Erfassungstabelle, keine Spalte, keine Regel und keinen Auslöser — die
-- Erfassung ist scharf (0072). Nur Sichten und Funktionen.
--
-- 1. DER MESSTAG AN JEDEM PUNKT DER VERDERBSKURVE
--
-- Der Betrieb: „wann hat fäulnis besonders zugelegt - welche sorte welche
-- charge - z.b. wärs ja spannend zu sehen - plötzlich ab dezember - dieser
-- kürbis wurde faul - fast vollständig auf einen schlag … dass er
-- rückblickend in der saison nachschauen kann". Bisher trägt jeder Punkt
-- nur seine Lagerdauer. Die beantwortet „faulen sie nach N Wochen"; der
-- Kalender beantwortet „ab wann ging es los". Es sind zwei Fragen an
-- dieselbe Messung — und zwei Achsen an demselben Bild. `messtag` ist der
-- Betriebstag der Arbeit (bzw. der Wägung bei der Lagerkontrolle), nie
-- `ts::date`: Wer um 23:00 misst, misst an diesem Betriebstag (0067/0070).
--
-- 2. DER NENNER BEIM WASCHEN: DIE FERTIGEN PALETTEN
--
-- Die Kaliber-Palette aus dem Zwischenlager wird nicht gewogen. Bisher
-- rechnet die Masse einer Wasch-Arbeit über die gezählten Kisten mal einem
-- Kistengewicht aus *anderen* Arbeiten (`v_auftrag_wasch_paletten`) — und
-- quer über den Gebindewechsel: hinein gehen volle G2, heraus kommen
-- lockerer gestapelte IFCO („in den g2 ist voll gestapelt - in den ifcos
-- nicht - also kanns sein dass 3 paletten vorne reingehen und hinten 4
-- rauskommen").
--
-- Seit Runde Q ist `auftrag.fertige_paletten_gesamt` Pflicht, sobald der
-- Palox zweimal abgelesen wurde — und bisher liest die Spalte keine
-- einzige Sicht. Sie gibt den ehrlicheren Nenner: Was herauskam, ist
-- fertige Paletten × der Palettenmasse **dieser Arbeit** (das Mittel ihrer
-- eigenen gewogenen vollen Paletten), hilfsweise der Palettenmasse ihrer
-- Sorte und ihres Kistensystems. Diese Quelle geht der Kistenrechnung vor.
--
-- Zwei Gründe. Erstens die Messung: Die eigenen Wägungen dieser Arbeit
-- sind eine Messung an dieser Ware, der Koeffizient ist ein Mittel über
-- fremde Arbeiten. Zweitens die Bedeutung: Die Verderbsrechnung bildet
-- `basis = eingang_netto_kg + Faules` — also „was herauskam plus was der
-- Palox fing = was hineinging". Für die fertigen Paletten stimmt das
-- genau; für die gezählten Eingangskisten zählt es das Faule ein zweites
-- Mal (rund ein Prozent zu viel Nenner, der Anteil also rund ein Prozent
-- zu klein). Das ist ein alter, kleiner Fehler in der Kistenrechnung; er
-- bleibt hier stehen, weil er die ganze Kurve verschöbe, und steht im
-- Befund der Runde R als Frage an den Betrieb.
--
-- In der Demo-Saison ändert sich dadurch **keine** Zahl: dort trägt keine
-- einzige Wasch-Arbeit eine Palettenzahl (die Spalte gibt es erst seit
-- 0072). Die neue Quelle greift für alles, was ab jetzt erfasst wird.
--
-- 3. DIE GLOCKE AM STICHTAG
--
-- `lager_kaliber(h)` sagt, wie viele Kilo je Band liegen; daneben steht
-- die Glocke. Beide müssen dieselben Kürbisse zeigen, sonst behaupten zwei
-- Bilder zweierlei über dieselbe Ware. Darum steht die gemeinsame
-- Rechnung ab jetzt einmal da — `kuerbis_stichtag(h)`, jeder sortierte
-- Kürbis um (1 − r)^Tage geschrumpft — und beide Bilder lesen sie:
-- `lager_kaliber(h)` legt die Kürbisse in ihre Bänder, `kaliber_glocke(h)`
-- in 50-Gramm-Stufen. `lager_kaliber` rechnet danach Zeichen für Zeichen
-- dasselbe wie vorher; der Prüfblock 0078 ist der Beweis.
-- =====================================================================
set client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Die gemeinsame Rechnung: welcher Schlüssel, welche Kürbisse
-- ---------------------------------------------------------------------
-- Welche Verteilung eine liegende Charge benutzt: ihre eigene Sortier-CSV
-- („charge"), die ihrer Sorte („sorte") oder keine. Dazu die Rate, mit der
-- geschrumpft wird — dieselbe, mit der die Kaskade rechnet.
create or replace function lager_schluessel()
returns table (charge_nr integer, sorte text, basis text, schluessel text, r numeric)
language sql stable set search_path = public as $$
with liegend as (
  select k.charge_nr, k.sorte, sum(k.m0 * k.r) / nullif(sum(k.m0), 0) as r
    from mv_kaskade k where k.portion = 'lager' group by k.charge_nr, k.sorte
), rate_sorte as (
  select sorte, sum(m0 * r) / nullif(sum(m0), 0) as r
    from mv_kaskade where portion = 'lager' group by sorte
), mit_csv as (
  select distinct l.charge_nr, c.sorte
    from sortier_lauf l join charge c on c.nr = l.charge_nr
    join sortier_gewicht g on g.lauf_id = l.id
   where g.klasse = 'kaliber' and g.anzahl > 0 and g.gewicht_g > 0
)
select l.charge_nr, l.sorte,
       case when exists (select 1 from mit_csv m where m.charge_nr = l.charge_nr) then 'charge'
            when exists (select 1 from mit_csv m where m.sorte = l.sorte)         then 'sorte'
            else 'keine' end,
       case when exists (select 1 from mit_csv m where m.charge_nr = l.charge_nr) then l.charge_nr::text
            else l.sorte end,
       case when exists (select 1 from mit_csv m where m.charge_nr = l.charge_nr) then l.r
            else rs.r end
  from liegend l
  left join rate_sorte rs on rs.sorte = l.sorte
$$;
comment on function lager_schluessel() is
  'Je Charge mit liegender Ware: woher ihre Gewichtsverteilung kommt (eigene '
  'Sortier-CSV, die der Sorte, oder keine) und mit welcher Verdunstungsrate '
  'geschrumpft wird. Die gemeinsame Auskunft für lager_kaliber(h) und '
  'kaliber_glocke(h) — beide teilen dieselbe Ware auf (0079).';
revoke all on function lager_schluessel() from public;
grant execute on function lager_schluessel() to authenticated;

-- Jeder sortierte Kürbis, wie er am Stichtag heute + p_h wiegt. Einmal je
-- Verteilungsschlüssel, nicht je Charge: Die Sorte Butterkin rechnet ihre
-- 8 000 Kürbisse sonst für jede ihrer Chargen neu.
create or replace function kuerbis_stichtag(p_h integer)
returns table (basis text, schluessel text, sorte text, h integer, anzahl integer, g double precision)
language sql stable set search_path = public as $$
with stichtag as (
  select heute() as heute
), lauf as materialized (
  -- Der Sortiertag je Lauf — einmal je Lauf gerechnet, nicht je Kürbis:
  -- betriebstag() liest die Zeitzone, und 4 000 Aufrufe kosteten 150 ms.
  select l.id, l.charge_nr, c.sorte, betriebstag(l.datei_zeit) as sortiertag
    from sortier_lauf l join charge c on c.nr = l.charge_nr
), kuerbis as (
  -- Nur die Klasse „kaliber": zu klein und Nebenkanal sind aus der
  -- verkaufsfähigen Masse schon heraus (a_klein_n, a_gross_n).
  select l.charge_nr, l.sorte, l.sortiertag, g.gewicht_g, g.anzahl
    from sortier_gewicht g join lauf l on l.id = g.lauf_id
   where g.klasse = 'kaliber' and g.anzahl > 0 and g.gewicht_g > 0
), schluessel as (
  select 'charge' as basis, s.schluessel, s.sorte, s.charge_nr, s.r
    from lager_schluessel() s where s.basis = 'charge'
  union
  select distinct 'sorte', s.sorte, s.sorte, null::int, s.r
    from lager_schluessel() s where s.basis = 'sorte'
)
-- Zwei getrennte Verbindungen (je Charge, je Sorte), damit die Datenbank
-- sie streuen kann, statt Zeile für Zeile zu suchen.
select v.basis, v.schluessel, v.sorte, p_h, k.anzahl,
       k.gewicht_g * power((1 - coalesce(v.r, 0))::double precision,
                           greatest(t.heute + p_h - k.sortiertag, 0)::double precision)
  from schluessel v
  join kuerbis k on k.charge_nr = v.charge_nr
  cross join stichtag t
 where v.basis = 'charge'
union all
select v.basis, v.schluessel, v.sorte, p_h, k.anzahl,
       k.gewicht_g * power((1 - coalesce(v.r, 0))::double precision,
                           greatest(t.heute + p_h - k.sortiertag, 0)::double precision)
  from schluessel v
  join kuerbis k on k.sorte = v.sorte
  cross join stichtag t
 where v.basis = 'sorte'
$$;
comment on function kuerbis_stichtag(integer) is
  'Jeder sortierte Kürbis (Klasse „kaliber"), wie er am Stichtag heute + p_h '
  'wiegt: g = g_sortiert · (1 − r)^(Stichtag − Sortiertag). Je '
  'Verteilungsschlüssel einmal. Die gemeinsame Grundlage von lager_kaliber(h) '
  'und kaliber_glocke(h) — eine Rechnung, zwei Bilder (0079).';
revoke all on function kuerbis_stichtag(integer) from public;
grant execute on function kuerbis_stichtag(integer) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Das Lager nach Kaliber — neu auf der gemeinsamen Rechnung
-- ---------------------------------------------------------------------
-- Gleiche Signatur, gleiche Zahlen wie 0078: Der Prüfblock 0078 läuft
-- unverändert weiter und ist der Beweis, dass dieser Umbau nichts bewegt.
create or replace function lager_kaliber(p_h integer)
returns table (
  gruppe text, schluessel text, sorte text, h integer, datum date,
  kaliber_idx integer, band_von integer, band_bis integer,
  kg numeric(14,2), anteil numeric(6,4), basis text, n_kuerbis integer,
  verkaufsfaehig_kg numeric(14,2), lager_kg numeric(14,2), n_chargen integer
)
language sql stable security definer set search_path = public as $$
with fassung as (
  -- Die Bänder je Sorte: die jüngste gültige Fassung.
  select distinct on (s.sorte) s.sorte, s.kaliber_baender
    from sortierschema s
   where s.art = 'kaliber' and s.gilt_ab <= heute()
   order by s.sorte, s.gilt_ab desc, s.id desc
), band as (
  select f.sorte, (x.ordinality - 1)::int as kaliber_idx,
         (x.b ->> 0)::int as band_von, (x.b ->> 1)::int as band_bis,
         x.ordinality = jsonb_array_length(f.kaliber_baender) as letztes
    from fassung f
   cross join lateral jsonb_array_elements(f.kaliber_baender) with ordinality as x(b, ordinality)
), schwellen as (
  -- Je Sorte die Bandgrenzen als sortierte Schwellen: von_0, von_1, …, bis_n.
  -- width_bucket findet das Band in O(log n) je Kürbis — kein Verbund mit
  -- Ungleichung über 200 000 Zeilen (der kostete beim Lasttest eine Sekunde).
  select b.sorte,
         array_agg(b.band_von::numeric order by b.kaliber_idx)
           || (select max(x.band_bis)::numeric from band x where x.sorte = b.sorte and x.letztes) as grenzen,
         count(*)::int as n_baender
    from band b
   group by b.sorte
), verteilung_roh as (
  -- Massenanteile je Band. Bucket 0 = unter dem kleinsten Band
  -- (kaliber_idx −1); Bucket n+1 (genau auf der Obergrenze) gehört zum
  -- obersten Band — Klasse „kaliber" heisst, die Maschine hat ihn im Band
  -- gesehen, und schrumpfende Ware wächst nicht darüber hinaus.
  select w.basis, w.schluessel, w.sorte,
         case when sw.grenzen is null then null
              else least(width_bucket(w.g::numeric, sw.grenzen), sw.n_baender) - 1 end as kaliber_idx,
         sum(w.anzahl * w.g)  as masse_g,
         sum(w.anzahl)        as n_kuerbis
    from kuerbis_stichtag(p_h) w
    left join schwellen sw on sw.sorte = w.sorte
   group by w.basis, w.schluessel, w.sorte,
            case when sw.grenzen is null then null
                 else least(width_bucket(w.g::numeric, sw.grenzen), sw.n_baender) - 1 end
), verteilung as (
  select v.basis, v.schluessel, v.sorte,
         coalesce(v.kaliber_idx, -1) as kaliber_idx, b.band_von, b.band_bis,
         v.masse_g / nullif(sum(v.masse_g) over (partition by v.basis, v.schluessel), 0) as anteil,
         sum(v.n_kuerbis) over (partition by v.basis, v.schluessel)                      as n_kuerbis
    from verteilung_roh v
    left join band b on b.sorte = v.sorte and b.kaliber_idx = v.kaliber_idx
), je_charge as (
  select p.schluessel::int as charge_nr, c.sorte, c.schlag, p.h, p.datum,
         q.basis,
         v.kaliber_idx, v.band_von, v.band_bis,
         case when q.basis = 'keine' then null else v.anteil end               as anteil,
         case when q.basis = 'keine' then p.verkaufsfaehig_kg
              else p.verkaufsfaehig_kg * v.anteil end                          as kg,
         v.n_kuerbis,
         p.verkaufsfaehig_kg, p.lager_kg
    from erg_prognose p
    join charge c on c.nr = p.schluessel::int
    join lager_schluessel() q on q.charge_nr = c.nr
    left join verteilung v on v.basis = q.basis and v.schluessel = q.schluessel
   where p.gruppe = 'charge' and p.h = p_h
), zeilen as (
  select 'charge'::text as gruppe, charge_nr::text as schluessel, sorte, h, datum,
         kaliber_idx, band_von, band_bis, kg, anteil, basis, n_kuerbis,
         verkaufsfaehig_kg, lager_kg, 1 as n_chargen
    from je_charge
  union all
  select 'sorte', sorte, sorte, h, datum,
         kaliber_idx, band_von, band_bis,
         sum(kg),
         case when sum(verkaufsfaehig_kg) > 0 and bool_and(basis <> 'keine')
              then sum(kg) / sum(verkaufsfaehig_kg) end,
         case when count(distinct basis) = 1 then min(basis) else 'gemischt' end,
         max(n_kuerbis),
         sum(verkaufsfaehig_kg), sum(lager_kg), count(distinct charge_nr)
    from je_charge
   group by sorte, h, datum, kaliber_idx, band_von, band_bis
)
select gruppe, schluessel, sorte, h, datum,
       kaliber_idx, band_von, band_bis,
       zahl(kg, 2, 1e12)::numeric(14,2)            as kg,
       zahl(anteil, 4, 1)::numeric(6,4)            as anteil,
       basis,
       n_kuerbis::int                              as n_kuerbis,
       zahl(verkaufsfaehig_kg, 2, 1e12)::numeric(14,2) as verkaufsfaehig_kg,
       zahl(lager_kg, 2, 1e12)::numeric(14,2)      as lager_kg,
       n_chargen::int                              as n_chargen
  from zeilen
$$;

-- ---------------------------------------------------------------------
-- 3. Die Glocke am Stichtag
-- ---------------------------------------------------------------------
-- Dieselben Kürbisse wie in lager_kaliber(h), nur in 50-Gramm-Stufen
-- statt in Bändern — und mit derselben Masse: Der Massenanteil einer
-- Stufe mal der verkaufsfähigen Masse der Kaskade. Über alle Stufen einer
-- Gruppe summiert steht wieder genau die Masse ihrer Bänder.
--
-- `n_kuerbis` ist die **gewogene Stückzahl** hinter der Form, nicht die
-- hochgerechnete: Für eine Sorte zählt jeder Verteilungsschlüssel einmal,
-- auch wenn drei ihrer Chargen ihn benutzen. So sagt die Zeile unter dem
-- Bild die Wahrheit („4 238 gewogen"), und die Prozente daneben kommen
-- aus der Masse.
create or replace function kaliber_glocke(p_h integer)
returns table (
  gruppe text, schluessel text, sorte text, h integer, datum date,
  stufe_g integer, n_kuerbis integer, masse_kg numeric(14,2), anteil numeric(6,4),
  basis text, n_chargen integer
)
language sql stable security definer set search_path = public as $$
with stufen as (
  select w.basis, w.schluessel, w.sorte,
         (floor(w.g / 50) * 50)::int as stufe_g,
         sum(w.anzahl * w.g) as masse_g,
         sum(w.anzahl)::int  as n_kuerbis
    from kuerbis_stichtag(p_h) w
   group by w.basis, w.schluessel, w.sorte, (floor(w.g / 50) * 50)::int
), anteile as (
  select s.*, s.masse_g / nullif(sum(s.masse_g) over (partition by s.basis, s.schluessel), 0) as anteil
    from stufen s
), je_charge as (
  select p.schluessel::int as charge_nr, c.sorte, p.h, p.datum,
         q.basis, q.schluessel as key, a.stufe_g, a.n_kuerbis,
         p.verkaufsfaehig_kg * a.anteil as masse_kg
    from erg_prognose p
    join charge c on c.nr = p.schluessel::int
    join lager_schluessel() q on q.charge_nr = c.nr
    join anteile a on a.basis = q.basis and a.schluessel = q.schluessel
   where p.gruppe = 'charge' and p.h = p_h and q.basis <> 'keine'
), schluessel_je_sorte as (
  select distinct sorte, basis, key from je_charge
), stueck_je_sorte as (
  -- Je Sorte die gewogenen Stück: jeder Schlüssel einmal, nicht je Charge.
  select k.sorte, a.stufe_g, sum(a.n_kuerbis)::int as n_kuerbis
    from schluessel_je_sorte k
    join anteile a on a.basis = k.basis and a.schluessel = k.key
   group by k.sorte, a.stufe_g
), zeilen as (
  select 'charge'::text as gruppe, charge_nr::text as schluessel, sorte, h, datum,
         stufe_g, n_kuerbis, masse_kg,
         masse_kg / nullif(sum(masse_kg) over (partition by charge_nr), 0) as anteil,
         basis, 1 as n_chargen
    from je_charge
  union all
  select 'sorte', j.sorte, j.sorte, max(j.h), max(j.datum),
         j.stufe_g, max(s.n_kuerbis), sum(j.masse_kg),
         sum(j.masse_kg) / nullif(sum(sum(j.masse_kg)) over (partition by j.sorte), 0),
         case when count(distinct j.basis) = 1 then min(j.basis) else 'gemischt' end,
         count(distinct j.charge_nr)::int
    from je_charge j
    left join stueck_je_sorte s on s.sorte = j.sorte and s.stufe_g = j.stufe_g
   group by j.sorte, j.stufe_g
)
select gruppe, schluessel, sorte, h, datum, stufe_g,
       n_kuerbis,
       zahl(masse_kg, 2, 1e12)::numeric(14,2) as masse_kg,
       zahl(anteil, 4, 1)::numeric(6,4)       as anteil,
       basis, n_chargen
  from zeilen
$$;
comment on function kaliber_glocke(integer) is
  'Die Gewichtsverteilung der liegenden verkaufsfähigen Ware am Stichtag '
  'heute + p_h, in 50-Gramm-Stufen: dieselben Kürbisse wie lager_kaliber(p_h), '
  'dieselbe Masse. n_kuerbis ist die gewogene Stückzahl hinter der Form (je '
  'Verteilungsschlüssel einmal), masse_kg die verkaufsfähige Masse der Kaskade '
  'in dieser Stufe. Chargen ohne Sortier-CSV stehen nicht darin — für sie gibt '
  'es keine Verteilung (0079).';
revoke all on function kaliber_glocke(integer) from public;
grant execute on function kaliber_glocke(integer) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Der Messtag an jedem Punkt der Verderbskurve
-- ---------------------------------------------------------------------
create or replace view v_schimmel_punkte with (security_invoker = true) as
 WITH sortier_lauf_anteil AS MATERIALIZED (
         SELECT b.charge_nr,
            b.start_ts,
            b.schimmel_kg,
            b.basis_jetzt_kg
           FROM v_schimmel_beobachtung b
          WHERE b.station = 'sortieren'::station AND b.plausibel AND b.anteil IS NOT NULL
        ), gemischt AS (
         SELECT v_auftrag_angabe.auftrag_id
           FROM v_auftrag_angabe
          WHERE v_auftrag_angabe.schluessel = 'eine_charge'::text AND v_auftrag_angabe.wert = 'false'::text
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lagertage,
    b.schimmel_kg,
    b.basis_jetzt_kg,
    b.anteil,
    b.plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    b.auftrag_id,
    betriebstag(b.start_ts) AS messtag
   FROM v_schimmel_beobachtung b
     LEFT JOIN gemischt g ON g.auftrag_id = b.auftrag_id
  WHERE b.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])
UNION ALL
 SELECT a.charge_nr,
    a.sorte,
    a.schlag,
    a.lagertage,
    s.kg AS schimmel_kg,
    a.eingang_netto_kg + s.kg AS basis_jetzt_kg,
    k.f2 AS anteil,
    anteil_plausibel(k.f2) AND a.lagertage >= 0::numeric AS plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    a.auftrag_id,
    betriebstag(a.start_ts) AS messtag
   FROM v_auftrag_masse a
     JOIN v_schimmel_menge s ON s.auftrag_id = a.auftrag_id
     LEFT JOIN gemischt g ON g.auftrag_id = a.auftrag_id
     LEFT JOIN LATERAL ( SELECT sum(sl.schimmel_kg) / NULLIF(sum(sl.basis_jetzt_kg), 0::numeric) AS f1
           FROM sortier_lauf_anteil sl
          WHERE sl.charge_nr = a.charge_nr AND sl.start_ts <= a.start_ts) sa ON true
     CROSS JOIN LATERAL ( SELECT s.kg / NULLIF(a.eingang_netto_kg + s.kg, 0::numeric) AS g) x
     CROSS JOIN LATERAL ( SELECT 1::numeric - (1::numeric - LEAST(GREATEST(COALESCE(sa.f1, 0::numeric), 0::numeric), 0.99)) * (1::numeric - LEAST(GREATEST(COALESCE(x.g, 0::numeric), 0::numeric), 0.99)) AS f2) k
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.lagertage IS NOT NULL AND a.eingang_netto_kg IS NOT NULL AND a.eingang_netto_kg > 0::numeric
UNION ALL
 SELECT w.charge_nr,
    w.sorte,
    w.schlag,
    w.lagertage,
    v.faul_kg AS schimmel_kg,
    w.netto_jetzt_kg AS basis_jetzt_kg,
    v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric) AS anteil,
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AS plausibel,
    'lager'::text AS quelle,
    NULL::bigint AS auftrag_id,
    betriebstag(w.wiege_ts) AS messtag
   FROM v_verdunstung_messung w
     JOIN verdunstung_wiegung v ON v.id = w.id
  WHERE v.faul_kg IS NOT NULL AND v.gemessen AND w.netto_jetzt_kg > 0::numeric AND w.lagertage > 0;
-- messtag steht am Ende: `create or replace view` darf eine Spalte anhängen,
-- nicht einschieben — und die Sicht bleibt dieselbe, die sie war.
comment on view v_schimmel_punkte is
  'Jede Faul-Messung als Punkt: die Lagerdauer (wie lange lag die Ware?) und '
  'seit 0079 der Messtag (wann wurde gemessen?). Zwei Achsen für zwei Fragen — '
  '„faulen sie nach N Wochen" und „ab wann ging es los". Der Messtag ist der '
  'Betriebstag, nie ts::date (0067/0070).';

-- ---- Zwei gespeicherte Fassungen, zwei Aufgaben ----------------------
--
-- `mv_schimmel_punkte` ist die Fassung, auf der die **Auswertung** steht:
-- die Verderbskurve, das Modell, die Kaskade — 34 Objekte hängen an ihr.
-- Sie wurde 2026 als `select * from v_schimmel_punkte` angelegt; der Stern
-- ist seither eingefroren, und eine neue Spalte käme über die Migrationen
-- nicht in sie hinein, über setup.sql (Teil B legt frisch an) schon. Genau
-- diesen Unterschied findet der Fingerabdruck-Vergleich in run.sh.
--
-- Neu anlegen kann man sie nicht: `create or replace` gibt es für
-- gespeicherte Sichten nicht, und ein `drop … cascade` risse die 34
-- Objekte mit — in einer Datenbank, in der echte Erfassungsdaten liegen,
-- ist das keine Option. Also bleibt sie, wie sie ist: Die Spaltenliste
-- steht ab jetzt ausgeschrieben da, damit **beide** Wege dieselben zehn
-- Spalten ergeben. Auf einer bestehenden Datenbank tut die Anweisung
-- nichts (`if not exists`), auf einer frischen legt sie genau diese zehn an.
-- verdichter: baut mv_schimmel_punkte
create materialized view if not exists mv_schimmel_punkte as
select charge_nr, sorte, schlag, lagertage, schimmel_kg, basis_jetzt_kg,
       anteil, plausibel, quelle, auftrag_id
  from v_schimmel_punkte with no data;
-- Ihre Indizes stehen seit 0026 in jener Migration. Weil die Anweisung hier
-- die gespeicherte Sicht **anmeldet** („verdichter: baut"), ersetzt sie die
-- Fassung von 0026 in setup.sql — samt deren Indizes. Also stehen sie hier
-- noch einmal, sonst hätte die Datenbank aus setup.sql zwei weniger als die
-- aus den Migrationen, und der Abgleich in run.sh sagt es sofort.
create index if not exists mv_schimmel_punkte_charge on mv_schimmel_punkte (charge_nr);
create index if not exists mv_schimmel_punkte_quelle on mv_schimmel_punkte (quelle);

-- `erg_punkte` ist die Fassung für die **App**. Sie hing bis hierher als
-- blosse Kopie an mv_schimmel_punkte (0068: 103 ms und 120 kB für nichts).
-- Ab jetzt trägt sie etwas bei, das die Auswertung nicht braucht und der
-- Betriebsleiter sehr wohl: den Messtag. Dafür rechnet sie v_schimmel_punkte
-- ein zweites Mal — das kostet rund ein Zehntel einer Sekunde, und der
-- Prüfblock 0068 misst es, damit es dabei bleibt. Die Auswertung selbst
-- liest sie nicht; sie steht am Ende der Kette, nicht darin.
-- verdichter: baut erg_punkte
do $$
begin
  execute 'drop materialized view if exists erg_punkte cascade';
  execute 'create materialized view erg_punkte as select * from v_schimmel_punkte with no data';
  execute 'grant select on erg_punkte to authenticated';
  execute format('comment on materialized view erg_punkte is %L',
                 'v_schimmel_punkte mit dem Messtag, gespeichert für die App (0079). Die '
                 'Auswertung steht auf mv_schimmel_punkte; diese Fassung liest nur der '
                 'Bildschirm. Erneuert mit auswertung_schritt().');
end $$;
-- „drop … cascade" nimmt den Index mit. 0061, 0065 und 0068 haben ihn nach
-- jedem Neubau wieder ausgeschrieben; 0079 tut dasselbe. Die Beschreibung
-- steht hier ein zweites Mal als einfache Anweisung — die von 0068 („eine
-- Kopie von mv_schimmel_punkte") gilt seit dieser Migration nicht mehr, und
-- in setup.sql muss die jüngere die ältere überschreiben.
create index if not exists erg_punkte_charge on erg_punkte (charge_nr);
comment on materialized view erg_punkte is
  'v_schimmel_punkte mit dem Messtag, gespeichert für die App (0079). Die '
  'Auswertung steht auf mv_schimmel_punkte; diese Fassung liest nur der '
  'Bildschirm. Erneuert mit auswertung_schritt().';

-- ---------------------------------------------------------------------
-- 5. Die gewogene Palette sagt ihre Tagesrate
-- ---------------------------------------------------------------------
-- Auf der Kalenderachse ist die *kumulierte* Verdunstung einer Palette
-- keine Auskunft: Eine alte Palette hat mehr verloren als eine junge, ganz
-- gleich, wann gewogen wurde. Was der Betrieb sehen will — „ich weiss
-- nicht ob verdunstungsrate konstant ist … im dezember wirds kalt sein" —
-- ist die Rate je Tag. Die rechnet `v_verdunstung_messung` längst
-- (rate_pro_tag, verwendbar); sie stand nur nicht in der Fassung, die der
-- Bildschirm liest. Angehängt, nicht neu gerechnet: derselbe Wägungs-
-- schlüssel, ein Verbund über die Id.
create or replace view v_wiegung_kennzahl with (security_invoker = true) as
SELECT w.id,
    w.auftrag_id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.eingangsdatum,
    w.wiege_ts,
    w.kisten,
    w.gebindeart,
    w.sichtbar_schimmel,
    w.kuerbisse_pro_kiste,
    betriebstag(w.wiege_ts) - w.eingangsdatum AS lagertage,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    zahl(n.netto_jetzt_kg / NULLIF(w.kisten, 0)::numeric, 3, '10000000'::numeric)::numeric(10,3) AS kg_pro_kiste,
    zahl(n.netto_jetzt_kg / NULLIF(w.kisten * w.kuerbisse_pro_kiste, 0)::numeric, 3, '10000000'::numeric)::numeric(10,3) AS kg_pro_kuerbis,
    zahl(n.netto_damals_kg - n.netto_jetzt_kg, 2, '100000000'::numeric)::numeric(10,2) AS verdunstung_kg,
    -- 0079: die Tagesrate und ob sie in die Rechnung eingeht
    m.rate_pro_tag,
    m.verwendbar
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     LEFT JOIN v_verdunstung_messung m ON m.id = w.id
     CROSS JOIN LATERAL ( SELECT zahl(w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, '100000000'::numeric)::numeric(10,2) AS netto_damals_kg,
            zahl(w.brutto_jetzt_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, '100000000'::numeric)::numeric(10,2) AS netto_jetzt_kg) n
  WHERE w.gemessen AND (a.id IS NULL OR a.abgebrochen_ts IS NULL);
comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, die Verdunstung dazwischen '
  '(0062 — vorher verlust_kg), kg je Kiste und je Kürbis, und seit 0079 die '
  'Tagesrate aus v_verdunstung_messung samt der Marke, ob sie verwendbar ist. '
  'Ohne Kistenzahl oder hinterlegte Tara gibt es kein Netto (0064).';

-- Dieselbe Geschichte wie bei erg_punkte: der Stern ist beim Anlegen
-- eingefroren (0062). erg_wiegung liest niemand ausser dem Bildschirm —
-- neu anlegen ist hier gefahrlos.
-- verdichter: baut erg_wiegung
do $$
begin
  execute 'drop materialized view if exists erg_wiegung cascade';
  execute 'create materialized view erg_wiegung as select * from v_wiegung_kennzahl with no data';
  execute 'grant select on erg_wiegung to authenticated';
  execute format('comment on materialized view erg_wiegung is %L',
                 'v_wiegung_kennzahl mit der Tagesrate, gespeichert für die App (0079). '
                 'Erneuert mit auswertung_schritt().');
end $$;
create index if not exists erg_wiegung_ts on erg_wiegung (wiege_ts);
comment on materialized view erg_wiegung is
  'v_wiegung_kennzahl mit der Tagesrate, gespeichert für die App (0079). '
  'Erneuert mit auswertung_schritt().';

-- ---------------------------------------------------------------------
-- 6. Der Nenner beim Waschen: die fertigen Paletten
-- ---------------------------------------------------------------------
-- Die Masse, die beim Waschen herauskam: fertige Paletten mal Palettenmasse —
-- dem Mittel der **eigenen** gewogenen vollen Paletten dieser Arbeit,
-- hilfsweise dem ihrer Sorte und ihres Kistensystems. Fehlt die Palettenzahl
-- oder fehlen beide Massen, gibt es keine Zeile: unbekannt, nicht null.
--
-- Warum eine eigene Sicht und keine Unterabfrage in v_auftrag_masse? Gemessen
-- an der dreifachen Saison, über alle fünf Rechenschritte:
--
--   ohne diesen Zweig                                  11 385 ms
--   als Unterabfrage im Lateral (erster Anlauf)        13 260 ms
--   dieselbe Unterabfrage, im `case` bewacht           12 500 ms
--
-- Der Wächter allein genügte nicht. Eine Unterabfrage in der Spaltenliste
-- macht die Sicht für den Planer undurchsichtig: Er kann sie nicht mehr in
-- ihre acht Leser hineinfalten (v_schimmel_beobachtung, v_kaskade_basis,
-- v_massenbilanz, v_plausibilitaet, v_durchsatz, v_fax_beobachtung,
-- v_ausschuss_beobachtung, v_schimmel_punkte), und jeder von ihnen bekommt
-- einen schlechteren Plan — auch wenn die Unterabfrage selbst nie ausgeführt
-- wird. Als flacher Verbund auf eine kleine Sicht bleibt alles beim Alten.
--
-- Hier führt die Bedingung: `where station = 'waschen'` steht an der
-- **treibenden** Tabelle, also fallen die neunzehn von zwanzig Arbeiten weg,
-- bevor irgendetwas gerechnet wird.
create or replace view v_auftrag_fertige_masse with (security_invoker = true) as
select a.id as auftrag_id,
       zahl(a.fertige_paletten_gesamt::numeric * coalesce(eig.netto_kg, kp.netto_kg),
            2, 10000000000)::numeric(12,2) as kg
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join (select v.auftrag_id, avg(v.netto_kg) as netto_kg
               from v_ausgang_voll v
              where coalesce(v.voll, true) and v.netto_kg > 0
              group by v.auftrag_id) eig on eig.auftrag_id = a.id
  left join lateral (
       select p.netto_kg
         from v_koeff_palette_netto p
        where p.sorte = c.sorte
          and (p.kistensystem = a.kistensystem
               or p.kistensystem is null and a.kistensystem is distinct from 'anderes')
        order by (p.kistensystem = a.kistensystem) desc nulls last
        limit 1) kp on true
 where a.station = 'waschen' and not a.ist_fax
   and coalesce(a.fertige_paletten_gesamt, 0) > 0
   and coalesce(eig.netto_kg, kp.netto_kg) is not null;
comment on view v_auftrag_fertige_masse is
  'Beim Waschen die Masse, die herauskam: fertige Paletten gesamt mal der '
  'mittleren Masse der eigenen gewogenen vollen Paletten, hilfsweise der ihrer '
  'Sorte und ihres Kistensystems (0079). Nur Zeilen, für die beides bekannt '
  'ist — fehlt eine Angabe, gibt es keine Zeile: unbekannt, nicht null.';
grant select on v_auftrag_fertige_masse to authenticated;

create or replace view v_auftrag_masse with (security_invoker = true) as
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten,
       coalesce(m.eingang_netto_kg, fpg.kg, wp.kg, gb.kg, fp.kg) as eingang_netto_kg,
       case when m.masse_quelle <> 'fehlt' then m.masse_quelle
            when fpg.kg is not null then 'fertige_paletten'
            when wp.kg is not null then 'wasch_paletten'
            when gb.kg is not null then 'gebinde'
            when fp.kg is not null then 'fax_paletten'
            else 'fehlt' end as masse_quelle,
       zahl(coalesce(m.lagertage,
         case when m.station = 'waschen'
              then (betriebstag(m.start_ts) - date '2000-01-01')::numeric
                   - coalesce(se.tage_seit_epoche, (r.eingangsdatum_mittel - date '2000-01-01')::numeric)
              else null end), 1, 1000000000)::numeric(10,1) as lagertage,
       a.ist_fax,
       wp.zwischenlager_tage,
       case
         when m.lagertage is not null                then 'gemessen'
         when m.station <> 'waschen'                 then null
         when se.tage_seit_epoche is not null        then 'sortiermittel'
         when r.eingangsdatum_mittel is not null     then 'chargenmittel'
         else null
       end as alter_quelle,
       case when m.lagertage is not null then null else es.streuung_tage end as alter_spanne_tage,
       coalesce(es.ernte_fertig, false) as ernte_fertig
  from mv_auftrag_masse m
  join auftrag a on a.id = m.auftrag_id
  left join mv_sortier_eingang se on se.charge_nr = m.charge_nr
  left join v_charge_rueckgrat r on r.charge_nr = m.charge_nr
  left join v_charge_erntespanne es on es.charge_nr = m.charge_nr
  left join v_auftrag_wasch_paletten wp on wp.auftrag_id = m.auftrag_id
  left join (select auftrag_id, sum(kg) as kg from v_auftrag_gebinde_masse group by auftrag_id) gb
         on gb.auftrag_id = m.auftrag_id
  -- 0079: Beim Waschen die Masse, die herauskam — als eigene Sicht daneben,
  -- nicht als Unterabfrage hier drin. Warum das wichtig ist, steht bei
  -- v_auftrag_fertige_masse: Eine Unterabfrage in der Spaltenliste nimmt dem
  -- Planer die Möglichkeit, diese Sicht in ihre acht Leser hineinzufalten.
  left join v_auftrag_fertige_masse fpg on fpg.auftrag_id = m.auftrag_id
  left join lateral (
        select zahl(a.paletten_gesamt::numeric * p.netto_kg, 2, 10000000000)::numeric(12,2) as kg
          from v_koeff_palette_netto p
         where a.ist_fax and a.paletten_gesamt > 0 and p.sorte = m.sorte
           and (p.kistensystem = a.kistensystem
                or p.kistensystem is null and a.kistensystem is distinct from 'anderes')
         order by (p.kistensystem = a.kistensystem) desc nulls last
         limit 1) fp on true;
comment on view v_auftrag_masse is
  'Die Masse einer Arbeit und ihr Alter. Die Masse in dieser Reihenfolge: '
  'gewogene oder vom Zettel gelesene Eingangspaletten; beim Waschen die '
  'fertigen Paletten dieser Arbeit (0079, „fertige_paletten"); die gezählten '
  'Kisten der Kaliber-Paletten („wasch_paletten"); gezählte Gebinde; bei Fax '
  'die Palettenzahl. Fehlt alles, ist die Masse unbekannt — nicht null.';

-- ---------------------------------------------------------------------
-- 7. Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 79 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
