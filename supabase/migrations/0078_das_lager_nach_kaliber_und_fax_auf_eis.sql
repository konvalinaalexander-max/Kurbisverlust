-- =====================================================================
-- 0078 — Das Lager nach Kaliber, die Marge je Wägung, Fax auf Eis
--
-- Runde R richtet die Betriebsleiter-Seiten neu aus: „Lagermanagement"
-- (Vergangenheit – heute – Prognose) und „Ursachen" (bis heute). Diese
-- Migration legt die drei Zahlenquellen, die dafür fehlen. Sie ändert
-- keine Erfassungstabelle und keine Spalte — die Erfassung ist scharf
-- (0072), und die Daten der Arbeiter-App bleiben, wie sie sind.
--
-- 1. DAS LAGER NACH KALIBER — `lager_kaliber(h)` und `v_lager_kaliber`
--
-- Der Betrieb: „von dem kaliber von der charge ist noch so viel da - aber
-- dann vlt auch rechnen - ja aber mit dem aktuellen verdampfung - ist dann
-- nur noch so viel von dem kaliber übrig weil gewisse in eine andere
-- kalibergrösse fallen". Die Kaskade sagt je Charge und Horizont, wie
-- viel verkaufsfähig ist (`erg_prognose`). Diese Sicht teilt genau diese
-- Zahl auf die Kaliberbänder auf — nicht mehr, nicht weniger: Über alle
-- Bänder summiert steht wieder `verkaufsfaehig_kg`. Eine Formel (die
-- Kaskade), eine Aufteilung (die Glocke), keine zweite Mathematik.
--
-- Die Aufteilung kommt aus der Sortier-CSV: jeder sortierte Kürbis der
-- Charge mit seinem Gewicht am Sortiertag (`sortier_gewicht`, Klasse
-- „kaliber"). Am Stichtag heute + h wiegt er noch
--     g(h) = g_sortiert · (1 − r)^(heute + h − sortiertag)
-- mit r der Verdunstungsrate der Charge aus der Kaskade. Dann fällt er in
-- das Band, in dem g(h) liegt — oder unter das kleinste (kaliber_idx −1,
-- „unter Kaliber"): Die Kaskade zählt ihn noch als verkaufsfähig, das
-- Band nicht mehr. Das steht als eigene Spalte da, statt still zu
-- verschwinden. Die Massenanteile der Bänder mal `verkaufsfaehig_kg` sind
-- die Kilo je Kaliber.
--
-- Hat eine Charge keine eigene CSV, nimmt sie die Verteilung ihrer Sorte
-- (alle CSV-Kürbisse der Sorte, mit der Rate der Sorte) — und sagt es:
-- `basis = 'sorte'`. Hat auch die Sorte keine, gibt es keine Aufteilung
-- (`basis = 'keine'`, eine Zeile ohne Band mit der ganzen Masse). Leer ist
-- nicht null: eine fehlende Verteilung ist keine Verteilung von 0 %.
--
-- Zeilen gibt es je Charge (gruppe 'charge') und je Sorte (gruppe 'sorte',
-- die Summe ihrer Chargen). Höhere Ebenen haben keine gemeinsamen Bänder —
-- Kaliber 1 heisst bei Orangita 300–800 g und bei Lekor 700–1200 g.
--
-- 2. DIE MARGE JE WÄGUNG — `v_marge_wiegung` → `erg_marge_wiegung`
--
-- Der Betrieb: „wir können diesen wert ja eh nie einem verkauf zuordnen -
-- die idee ist ja nur pro palette zu wissen - und das halt vlt 10x messen
-- pro saison und dann einen durchschnittswert zu generieren". Und: „bei
-- kaliber 1100 bis 1850 - gebe ich immer durchschnitt 1750 - viel mehr als
-- ich sollte". Also: je Sorte und Kistensystem der Durchschnitt der
-- gewogenen fertigen Paletten — Kiste ab: Ist gegen Soll je Kiste; Stück:
-- Gramm je Kürbis gegen die Bandmitte. Ohne Verkaufsdatei, ohne
-- Hochrechnung auf verkaufte Kisten. `v_ueberfuellung_verkauf` bleibt
-- bestehen; sie beantwortet eine andere Frage (was über die Saison
-- verschenkt wurde) und braucht dafür die Verkäufe.
--
-- 3. FAX AUF EIS
--
-- „streiche das vorläufig komplett - also nicht aus der datenbank … aus
-- dem UI … im hintergrund halt einfach auf eis legen". Die App bietet
-- Fax nicht mehr an (Runde R, `taetigkeit.ts`). Damit bekommt die Kaskade
-- keine Fax-Messung mehr — und würde den Anteil a_fax aus der alten
-- Demo-Saison weiterrechnen oder, ohne Daten, „unbekannt" sagen und die
-- verkaufsfähige Masse für immer als „höchstens" beschriften. Beides
-- ist falsch. Die Entscheidung des Betriebs ist: Fax wird nicht erfasst.
-- Also ist der erwartete Fax-Anteil **null durch Entscheid** — bekannt,
-- nicht unbekannt. Ein Schalter (`einstellung.fax_eingefroren`) macht
-- `v_koeff_fax` zu 0 mit der Basis „eingefroren". Wird Fax je wieder
-- erfasst, dreht der Schalter zurück, und die Sicht rechnet wie vorher.
-- Tabellen, Spalten und die Fax-Sichten bleiben unverändert; gemessenes
-- Faules alter Fax-Arbeiten bleibt in `fax_heute_kg` sichtbar.
-- =====================================================================
set client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Fax auf Eis: der Schalter und der Koeffizient
-- ---------------------------------------------------------------------
insert into einstellung (schluessel, wert, bemerkung) values
  ('fax_eingefroren', 'true'::jsonb,
   'Fax (Faules beim Abpacken) wird nicht erfasst — Entscheid des Betriebs (Runde R). '
   'Solange true, ist der erwartete Fax-Anteil 0 durch Entscheid (bekannt, nicht '
   'unbekannt), und die App bietet keine Fax-Arbeit an. false: wie vor Runde R.')
on conflict (schluessel) do nothing;

-- Dieselben Spalten und Typen wie 0051 — die Kaskade (mv_kaskade, 0065)
-- liest mittel, n und basis.
create or replace view v_koeff_fax with (security_invoker = true) as
with schalter as (
  select coalesce((select (wert #>> '{}')::boolean from einstellung where schluessel = 'fax_eingefroren'), false) as eingefroren
)
select sk.sorte,
       case when s.eingefroren then 0::numeric else k.mittel::numeric end        as mittel,
       case when s.eingefroren then 0::double precision
            when coalesce(k.varianz, 0) = 0 then k.mittel
            else greatest(k.mittel - k.t * sqrt(k.varianz), 0) end::double precision as unten,
       case when s.eingefroren then 0::double precision
            when coalesce(k.varianz, 0) = 0 then k.mittel
            else least(k.mittel + k.t * sqrt(k.varianz), 1) end::double precision   as oben,
       case when s.eingefroren then 0 else coalesce(k.n, 0) end                  as n,
       case when s.eingefroren then 'eingefroren (Runde R): Fax wird nicht erfasst, erwarteter Anteil 0 durch Entscheid'
            when coalesce(k.n_gesamt, 0) = 0 then 'keine Fax-Arbeit mit gewogenem Faulem'
            when k.b >= 0.67     then 'Fax-Arbeiten dieser Sorte'
            when k.b >= 0.33     then 'eigene Fax-Arbeiten, zum Gesamtwert gezogen'
            else 'alle Sorten (zu wenige eigene Chargen)' end                    as basis
  from sorte_kaliber sk
  cross join schalter s
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'fax' and g.sorte is not distinct from sk.sorte
  ) k on true;
comment on view v_koeff_fax is
  'Anteil Faules beim Abpacken (Fax), je Sorte — bezogen auf die Masse, die durch '
  'das Fax ging. NULL, solange keine Fax-Arbeit Faules gewogen hat: unbekannt, nicht 0. '
  'Steht einstellung.fax_eingefroren auf true (Runde R), ist der Anteil 0 durch '
  'Entscheid — bekannt, Basis „eingefroren" (0078).';

-- ---------------------------------------------------------------------
-- 2. Das Lager nach Kaliber
-- ---------------------------------------------------------------------
-- Eine Funktion je Horizont, aufgerufen vom Bildschirm — keine gespeicherte
-- Sicht im Rechenwerk: Die Aufteilung für alle dreissig Horizonte kostete
-- 0.65 s auf der Demo, und selbst „heute" allein kostete beim Lasttest
-- (Prüfdatensatz mit 255 000 CSV-Kürbissen) eine Sekunde — das Neurechnen
-- liegt dort mit 11.6–12.0 s ohnehin an seiner Zwölf-Sekunden-Grenze, jede
-- weitere Sicht in Schritt 1–5 kippt ihn. Der Bildschirm braucht zwei
-- Spalten: „heute" (lager_kaliber(0)) und „in X Wochen" (lager_kaliber(7·X),
-- X tippt der Betriebsleiter). Ein Aufruf: 35 ms auf der Demo. Die Formel
-- steht einmal, hier; v_lager_kaliber (für SQL-Editor und Diagnose) liest
-- dieselbe Funktion.
create or replace function lager_kaliber(p_h integer)
returns table (
  gruppe text, schluessel text, sorte text, h integer, datum date,
  kaliber_idx integer, band_von integer, band_bis integer,
  kg numeric(14,2), anteil numeric(6,4), basis text, n_kuerbis integer,
  verkaufsfaehig_kg numeric(14,2), lager_kg numeric(14,2), n_chargen integer
)
language sql stable security definer set search_path = public as $$
with stichtag as (
  select heute() as heute
), horizont as (
  select p_h as h
), liegend as (
  -- Jede Charge mit liegender Ware: ihre Rate, massegewichtet über die
  -- Kohorten (Eingangstage) — dieselbe Rate, mit der die Kaskade rechnet.
  select k.charge_nr, k.sorte,
         sum(k.m0 * k.r) / nullif(sum(k.m0), 0) as r
    from mv_kaskade k
   where k.portion = 'lager'
   group by k.charge_nr, k.sorte
), rate_sorte as (
  select sorte, sum(m0 * r) / nullif(sum(m0), 0) as r
    from mv_kaskade where portion = 'lager' group by sorte
), lauf as materialized (
  -- Der Sortiertag je Lauf — einmal je Lauf gerechnet, nicht je Kürbis:
  -- betriebstag() liest die Zeitzone, und 4 000 Aufrufe kosteten 150 ms.
  select l.id, l.charge_nr, c.sorte, betriebstag(l.datei_zeit) as sortiertag
    from sortier_lauf l
    join charge c on c.nr = l.charge_nr
), kuerbis as (
  -- Jeder sortierte Kürbis mit dem Tag, an dem er gewogen wurde. Nur die
  -- Klasse „kaliber": zu klein und Nebenkanal sind schon aus der
  -- verkaufsfähigen Masse heraus (a_klein_n, a_gross_n).
  select l.charge_nr, l.sorte, l.sortiertag, g.gewicht_g, g.anzahl
    from sortier_gewicht g
    join lauf l on l.id = g.lauf_id
   where g.klasse = 'kaliber' and g.anzahl > 0 and g.gewicht_g > 0
), fassung as (
  -- Die Bänder je Sorte: die jüngste gültige Fassung.
  select distinct on (s.sorte) s.sorte, s.kaliber_baender
    from sortierschema s, stichtag t
   where s.art = 'kaliber' and s.gilt_ab <= t.heute
   order by s.sorte, s.gilt_ab desc, s.id desc
), band as (
  select f.sorte, (x.ordinality - 1)::int as kaliber_idx,
         (x.b ->> 0)::int as band_von, (x.b ->> 1)::int as band_bis,
         x.ordinality = jsonb_array_length(f.kaliber_baender) as letztes
    from fassung f
   cross join lateral jsonb_array_elements(f.kaliber_baender) with ordinality as x(b, ordinality)
), quelle as (
  -- Woher die Verteilung einer liegenden Charge kommt.
  select l.charge_nr, l.sorte, l.r as r_charge, rs.r as r_sorte,
         case when exists (select 1 from kuerbis q where q.charge_nr = l.charge_nr) then 'charge'
              when exists (select 1 from kuerbis q where q.sorte = l.sorte)         then 'sorte'
              else 'keine' end as basis
    from liegend l
    left join rate_sorte rs on rs.sorte = l.sorte
), schluessel as (
  -- Einmal je Verteilungsschlüssel (Charge oder Sorte) — nicht je liegender
  -- Charge, sonst rechnet die Sorte Butterkin ihre 8 000 Kürbisse für jede
  -- ihrer Chargen neu.
  select 'charge' as basis, q.charge_nr::text as schluessel, q.sorte, q.charge_nr, q.r_charge as r
    from quelle q where q.basis = 'charge'
  union all
  select distinct 'sorte', q.sorte, q.sorte, null::int, q.r_sorte
    from quelle q where q.basis = 'sorte'
), gewicht as (
  -- Jeder Kürbis an jedem Stichtag — zwei getrennte Verbindungen (je Charge,
  -- je Sorte), damit die Datenbank sie streuen kann statt Zeile für Zeile
  -- zu suchen.
  select v.basis, v.schluessel, v.sorte, h.h, k.anzahl,
         k.gewicht_g * power((1 - coalesce(v.r, 0))::double precision,
                             greatest(t.heute + h.h - k.sortiertag, 0)::double precision) as g
    from schluessel v
    join kuerbis k on k.charge_nr = v.charge_nr
    cross join horizont h
    cross join stichtag t
   where v.basis = 'charge'
  union all
  select v.basis, v.schluessel, v.sorte, h.h, k.anzahl,
         k.gewicht_g * power((1 - coalesce(v.r, 0))::double precision,
                             greatest(t.heute + h.h - k.sortiertag, 0)::double precision)
    from schluessel v
    join kuerbis k on k.sorte = v.sorte
    cross join horizont h
    cross join stichtag t
   where v.basis = 'sorte'
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
  -- Massenanteile je Band und Horizont. Bucket 0 = unter dem kleinsten Band
  -- (kaliber_idx −1); Bucket n+1 (genau auf der Obergrenze) gehört zum
  -- obersten Band — Klasse „kaliber" heisst, die Maschine hat ihn im Band
  -- gesehen, und schrumpfende Ware wächst nicht darüber hinaus.
  select w.basis, w.schluessel, w.sorte, w.h,
         case when sw.grenzen is null then null
              else least(width_bucket(w.g::numeric, sw.grenzen), sw.n_baender) - 1 end as kaliber_idx,
         sum(w.anzahl * w.g)  as masse_g,
         sum(w.anzahl)        as n_kuerbis
    from gewicht w
    left join schwellen sw on sw.sorte = w.sorte
   group by w.basis, w.schluessel, w.sorte, w.h,
            case when sw.grenzen is null then null
                 else least(width_bucket(w.g::numeric, sw.grenzen), sw.n_baender) - 1 end
), verteilung as (
  -- Ohne Band (b.kaliber_idx null) heisst: unter dem kleinsten Kaliber
  -- gelandet — oder über dem grössten, was bei schrumpfender Ware nicht
  -- vorkommt. Beides ist Kaliber −1: verkaufsfähig laut Kaskade, aber in
  -- keinem Band.
  select v.basis, v.schluessel, v.sorte, v.h,
         coalesce(v.kaliber_idx, -1) as kaliber_idx, b.band_von, b.band_bis,
         v.masse_g / nullif(sum(v.masse_g) over (partition by v.basis, v.schluessel, v.h), 0) as anteil,
         sum(v.n_kuerbis) over (partition by v.basis, v.schluessel, v.h)                       as n_kuerbis
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
    join horizont hz on hz.h = p.h
    join charge c on c.nr = p.schluessel::int
    join quelle q on q.charge_nr = c.nr
    left join verteilung v on v.h = p.h
                          and ((q.basis = 'charge' and v.basis = 'charge' and v.schluessel = p.schluessel)
                           or  (q.basis = 'sorte'  and v.basis = 'sorte'  and v.schluessel = c.sorte))
   where p.gruppe = 'charge'
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
comment on function lager_kaliber(integer) is
  'Die verkaufsfähige Masse je Charge/Sorte am Horizont p_h (Tage, ein Wert aus '
  'erg_prognose: 0, 7, 14 … 196, 198), aufgeteilt auf die Kaliberbänder der Sorte. '
  'Die Summe über die Bänder ist erg_prognose.verkaufsfaehig_kg — eine Formel, eine '
  'Aufteilung. Die Aufteilung ist die Sortier-CSV der Charge (basis charge) oder der '
  'Sorte (basis sorte), jeder Kürbis um (1 − r)^Tage geschrumpft und neu in sein Band '
  'gelegt; kaliber_idx −1 heisst unter dem kleinsten Band. basis keine: keine CSV, '
  'keine Aufteilung, eine Zeile mit der ganzen Masse und kaliber_idx null (0078).';
revoke all on function lager_kaliber(integer) from public;
grant execute on function lager_kaliber(integer) to authenticated;

-- Für den SQL-Editor und die Diagnose: „heute" als Sicht. Der Bildschirm
-- ruft die Funktion direkt (0 und 7·X); im Rechenwerk steht sie nicht.
create or replace view v_lager_kaliber with (security_invoker = true) as
select gruppe, schluessel, sorte, h, datum, kaliber_idx, band_von, band_bis,
       zahl(kg, 2, 1e12)::numeric(14,2)                as kg,
       zahl(anteil, 4, 1)::numeric(6,4)                as anteil,
       basis, n_kuerbis,
       zahl(verkaufsfaehig_kg, 2, 1e12)::numeric(14,2) as verkaufsfaehig_kg,
       zahl(lager_kg, 2, 1e12)::numeric(14,2)          as lager_kg,
       n_chargen
  from lager_kaliber(0);
comment on view v_lager_kaliber is
  'lager_kaliber(0): das Lager nach Kaliber heute — zum Nachschauen im SQL-Editor. '
  'Der Bildschirm ruft lager_kaliber(0) und lager_kaliber(7·X) direkt; im '
  'Rechenwerk (auswertung_schritt) steht keine gespeicherte Fassung, weil das '
  'Neurechnen bei dreifacher Saison an seiner Zwölf-Sekunden-Grenze liegt (0078).';
grant select on v_lager_kaliber to authenticated;
-- Eine Zwischenfassung dieser Migration hatte „heute" als gespeicherte Sicht;
-- wo sie liegt, geht sie weg (sie stand nie in einer veröffentlichten Datenbank).
drop materialized view if exists erg_lager_kaliber;

-- ---------------------------------------------------------------------
-- 3. Die Marge je Wägung
-- ---------------------------------------------------------------------
create or replace view v_marge_wiegung with (security_invoker = true) as
with w as (
  -- Nur volle Paletten (0072): eine halbe zieht das Kistengewicht nach unten.
  select k.*, coalesce(aw.voll, true) as voll
    from v_ausgang_kennzahl k
    join ausgang_wiegung aw on aw.id = k.id
   where k.kisten > 0 and k.netto_kg is not null and k.kistensystem is not null
)
select w.sorte, w.kistensystem,
       case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end   as soll_kg_pro_kiste,
       case when w.kistensystem = 'stueck'   then w.kaliber_idx end         as kaliber_idx,
       case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end     as stueck_je_kiste,
       case when w.kistensystem = 'stueck'   then w.band_mittel_g end       as band_mittel_g,
       count(*)::int                                                       as n_wiegungen,
       sum(w.kisten)::int                                                  as kisten,
       zahl(avg(w.kg_pro_kiste), 3, 1e4)::numeric(10,3)                    as kg_je_kiste,
       zahl(stddev_samp(w.kg_pro_kiste), 3, 1e4)::numeric(10,3)            as sd_je_kiste,
       -- Kiste ab: Ist − Soll je Kiste, gemittelt über die Wägungen.
       zahl(avg(w.ueberfuellung_je_kiste), 3, 1e4)::numeric(10,3)          as zuviel_je_kiste,
       -- Stück: Gramm je Kürbis und die Abweichung von der Bandmitte.
       zahl(avg(w.kg_pro_kuerbis) * 1000, 0, 1e6)::numeric(8,0)            as g_je_kuerbis,
       zahl(avg(w.kg_pro_kuerbis) * 1000 - w.band_mittel_g, 0, 1e6)::numeric(8,0) as g_ueber_bandmitte,
       betriebstag(min(w.ts))                                              as von,
       betriebstag(max(w.ts))                                              as bis
  from w
 where w.voll
 group by w.sorte, w.kistensystem,
          case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end,
          case when w.kistensystem = 'stueck'   then w.kaliber_idx end,
          case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end,
          case when w.kistensystem = 'stueck'   then w.band_mittel_g end,
          w.band_mittel_g;
comment on view v_marge_wiegung is
  'Die verschenkte Marge je Wägung, ohne Verkaufsdatei: je Sorte und Kistensystem '
  'der Durchschnitt der gewogenen vollen fertigen Paletten. Kiste ab: kg je Kiste '
  'gegen das Soll (zuviel_je_kiste = Ist − Soll). Stück: Gramm je Kürbis gegen die '
  'Bandmitte (g_ueber_bandmitte). Der Betrieb: „pro palette wissen, vlt 10x messen '
  'pro saison, dann einen durchschnittswert" (0078).';

drop materialized view if exists erg_marge_wiegung;
create materialized view erg_marge_wiegung as select * from v_marge_wiegung with no data;
create unique index erg_marge_wiegung_pk
  on erg_marge_wiegung (sorte, kistensystem, coalesce(soll_kg_pro_kiste, -1), coalesce(kaliber_idx, -1),
                        coalesce(stueck_je_kiste, -1));
comment on materialized view erg_marge_wiegung is
  'Gespeichert: die Marge je Wägung (v_marge_wiegung) — je Sorte und Kistensystem '
  'der Durchschnitt der gewogenen vollen fertigen Paletten, ohne Verkaufsdatei. '
  'Schritt 4 des Rechenwerks (0078).';
grant select on v_marge_wiegung to authenticated;
grant select on erg_marge_wiegung to authenticated;

-- ---------------------------------------------------------------------
-- 4. Das Rechenwerk kennt das neue Ergebnis (Schritt 4: erg_marge_wiegung)
-- ---------------------------------------------------------------------
create or replace function auswertung_schritt(p_schritt integer)
returns jsonb language plpgsql security definer set search_path = public set jit = off as $$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'mv_schimmel_punkte', 'mv_schimmel_modell',
                       'erg_punkte', 'erg_modell', 'erg_kurve', 'erg_selektion',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_prognose', 'erg_wohin', 'erg_verlauf', 'erg_bilanz',
                       'erg_marge', 'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage',
                       'erg_marge_wiegung'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  if p_schritt = 1 then
    for v_name in
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
  end if;

  foreach v_name in array v_namen loop
    execute format('refresh materialized view %I', v_name);
    execute format('analyze %I', v_name);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif p_schritt = 1 then
    update auswertung_stand
       set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  else
    update auswertung_stand
       set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5);
end $$;
comment on function auswertung_schritt(integer) is
  'Ein Schritt des Neurechnens. Nur für den Betriebsleiter — oder ohne Anmeldung, '
  'also für die Prüfstände als Eigentümer. Ein Lauf sperrt jede gespeicherte '
  'Ansicht für rund drei Sekunden (0068, 0071, 0078).';

-- ---------------------------------------------------------------------
-- 5. Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 78 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
