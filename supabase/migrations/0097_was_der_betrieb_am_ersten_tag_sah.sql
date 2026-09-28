-- =====================================================================
-- 0097 — Was der Betrieb am ersten Tag mit echten Zahlen sah (Runde AD)
--
-- Am 28. September lagen zum ersten Mal echte Zahlen im Dashboard, und der
-- Betrieb hat sie gelesen. Fünf Dinge davon gehören der Datenbank:
--
-- 1. „Kaori Kuri K1 · 500–600 g · Mitte 878 g" — das Kaliber hiess nach der
--    neuesten Fassung, die Mitte war nach der Fassung des Auftrags gerechnet
--    (K1 = 600–1100 g). Jede Wägung trägt jetzt die Grenzen ihres Bandes aus
--    der Fassung des Auftrags (band_von_g, band_bis_g), und die Bandmitte ist
--    der Schwerpunkt der Kürbisse INNERHALB dieser Grenzen aus den
--    Sortierläufen der Sorte — nicht das Mittel je Index über alle Fassungen.
--    Die Marge-Ansichten gruppieren nach den Grenzen.
-- 2. „halbe Palette — zählt nicht in der Marge?" — 43 statt 44 Kisten ändern
--    das Gewicht je Kiste nicht. Jede gewogene Palette zählt je Kiste; ob sie
--    voll war, steht dabei (n_voll). Für die Palettenmasse (Nenner des
--    Waschens) zählen weiter nur volle.
-- 3. „0 kg zu klein / 22 kg zu gross — stimmt nicht" — die Arbeiterin hat
--    „zu gross" gewogen und „zu klein" ausgelassen. Eine Art ohne Messung ist
--    unbekannt, nicht 0: keine Auffälligkeit, und die gemessene Art zählt.
-- 4. „Verlust bis heute —" bei jeder Charge, obwohl Verdunstung und Faules
--    gerechnet waren: Der Sockel a₀ galt als unbekannt, solange das
--    Verderbsmodell nicht brauchbar war. Der Sockel ist ein Zuschlag, den es
--    nur mit Nachweis gibt; ohne Nachweis ist er 0.
-- 5. Der Zeitplan-Eintrag (0061) wird beim Einspielen nicht mehr gelöscht und
--    neu angelegt — siehe die Änderung im Block von 0061: Der Starter von
--    pg_cron hat einen neu angelegten Eintrag zweimal am selben Tag nicht
--    übernommen; einen bestehenden führt er weiter.
-- 6. Abbrechen mit Erlaubnis: Eine Arbeiterin darf laufende Arbeiten
--    abbrechen, auch fremde, wenn der Betriebsleiter es ihr erlaubt hat
--    (profil.darf_abbrechen). Die Funktion prüft es selbst.
--
-- Keine Tabelle, keine Spalte wird gelöscht. Die zwei Marge-Ansichten werden
-- als gespeicherte Ansichten neu angelegt, weil sie Spalten dazubekommen
-- (wie 0078 und 0086).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Jede gewogene fertige Palette kennt die Grenzen ihres Bandes
-- ---------------------------------------------------------------------
create or replace view v_ausgang_kennzahl with (security_invoker = true) as
with grenzen as (
  -- 0097: jedes Band, das es gibt — aus allen Fassungen der Sortierschemata
  -- und aus den eigenen Bändern der Wasch-Arbeiten (kaliber_von_g/bis_g, 0054).
  select distinct s.sorte, (e.band ->> 0)::int as von, (e.band ->> 1)::int as bis
    from sortierschema s
    cross join lateral jsonb_array_elements(s.kaliber_baender) as e(band)
   where s.art = 'kaliber' and s.kaliber_baender is not null
  union
  select distinct c.sorte, a.kaliber_von_g, a.kaliber_bis_g
    from auftrag a join charge c on c.nr = a.charge_nr
   where a.kaliber_von_g is not null and a.kaliber_bis_g is not null
), band_mittel as (
  -- Mittleres Stückgewicht der Kürbisse dieser Sorte INNERHALB der Grenzen,
  -- aus allen Sortierläufen der Sorte — gleich, mit welcher Fassung der Lauf
  -- klassiert hat. Bis 0096 stand hier das Mittel je kaliber_idx, und ein
  -- Index heisst je Fassung etwas anderes: Kaori Kuri bekam am 23. September
  -- ein Band 500–600 g vorne dran, K1 rutschte von 600–1100 auf 500–600 —
  -- die Marge-Karte zeigte „K1 · 500–600 g · Mitte 878 g".
  select g.sorte, g.von, g.bis,
         sum(sg.anzahl::bigint * sg.gewicht_g)::numeric / nullif(sum(sg.anzahl), 0) as gramm
    from grenzen g
    join charge c on c.sorte = g.sorte
    join sortier_lauf l on l.charge_nr = c.nr
    join sortier_gewicht sg on sg.lauf_id = l.id and sg.gewicht_g >= g.von and sg.gewicht_g < g.bis
   group by g.sorte, g.von, g.bis
)
select w.id, w.auftrag_id, w.charge_nr, c.sorte, c.schlag, w.ts, w.brutto_kg, w.kisten,
       w.gebindeart, w.kuerbisse_pro_kiste, n.netto_kg,
       zahl(n.netto_kg / w.kisten, 3, 1e7)::numeric(10,3)                          as kg_pro_kiste,
       zahl(n.netto_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0), 3, 1e7)::numeric(10,3) as kg_pro_kuerbis,
       s.soll::numeric                                                              as soll_kg_pro_kiste,
       zahl(case when s.soll is not null then n.netto_kg / w.kisten - s.soll end, 3, 1e7)::numeric(10,3)
                                                                                    as ueberfuellung_je_kiste,
       zahl(case when s.soll is not null then n.netto_kg - w.kisten * s.soll end, 2, 1e8)::numeric(10,2)
                                                                                    as ueberfuellung_kg,
       -- neu (0060)
       coalesce(a.kistensystem, case when ss.art = 'kiste' then 'kiste_ab' end)::text as kistensystem,
       w.kaliber_idx,
       e.stueck                                                                     as stueck_je_kiste,
       zahl(e.stueck * bm.gramm / 1000.0, 3, 1e7)::numeric(10,3)                    as erwartet_kg_pro_kiste,
       zahl(n.netto_kg / w.kisten - e.stueck * bm.gramm / 1000.0, 3, 1e7)::numeric(10,3)
                                                                                    as abweichung_je_kiste,
       zahl(bm.gramm, 0, 1e6)::numeric(8,0)                                         as band_mittel_g,
       -- 0097: die Grenzen des Bandes, wie die Fassung des Auftrags sie kennt
       bd.von                                                                       as band_von_g,
       bd.bis                                                                       as band_bis_g
  from ausgang_wiegung w
  join auftrag a on a.id = w.auftrag_id
  join charge c on c.nr = w.charge_nr
  left join gebinde g on g.art = w.gebindeart
  left join sortierschema ss on ss.id = a.sortierschema_id
  cross join lateral (
    select zahl(w.brutto_kg - w.kisten * g.tara_kg_pro_kiste - coalesce(g.tara_kg_palette, 0), 2, 1e8)::numeric(10,2) as netto_kg) n
  cross join lateral (
    select case when a.kistensystem = 'kiste_ab' then a.soll_kg_pro_kiste
                when a.kistensystem is null and ss.art = 'kiste' then ss.soll_kg_pro_kiste end as soll) s
  cross join lateral (
    select case when a.kistensystem = 'stueck' then coalesce(w.kuerbisse_pro_kiste, a.stueck_je_kiste) end as stueck) e
  cross join lateral (
    select case when w.kaliber_idx = -2 then null else coalesce(w.kaliber_idx, a.kaliber_idx) end as idx) i
  cross join lateral (
    -- Die Grenzen des Bandes, wie die Fassung DES AUFTRAGS sie kennt; beim
    -- eigenen Band (Waschen, 0054) die des Auftrags selbst. Trägt der Auftrag
    -- keine Fassung: die heute gültige Standardfassung der Sorte.
    select case when i.idx is null then a.kaliber_von_g else (f.baender -> i.idx ->> 0)::int end as von,
           case when i.idx is null then a.kaliber_bis_g else (f.baender -> i.idx ->> 1)::int end as bis
      from (select coalesce(ss.kaliber_baender,
                            (select x.kaliber_baender from sortierschema x
                              where x.sorte = c.sorte and x.art = 'kaliber' and x.kaeufer is null
                                and x.kaliber_baender is not null
                              order by x.gilt_ab desc limit 1)) as baender) f) bd
  left join band_mittel bm on bm.sorte = c.sorte and bm.von = bd.von and bm.bis = bd.bis
 where w.gemessen and a.abgebrochen_ts is null and n.netto_kg > 0;

-- Die schlanke Sicht darüber (0089) neu angelegt, damit sie die zwei neuen
-- Spalten trägt.
create or replace view v_ausgang_voll with (security_invoker = true) as
select k.id, k.auftrag_id, k.charge_nr, k.sorte, k.schlag, k.ts, k.brutto_kg, k.kisten,
       k.gebindeart, k.kuerbisse_pro_kiste, k.netto_kg, k.kg_pro_kiste, k.kg_pro_kuerbis,
       k.soll_kg_pro_kiste, k.ueberfuellung_je_kiste, k.ueberfuellung_kg, k.kistensystem,
       k.kaliber_idx, k.stueck_je_kiste, k.erwartet_kg_pro_kiste, k.abweichung_je_kiste,
       k.band_mittel_g,
       w.voll,
       -- 0097: die zwei neuen Spalten HINTER voll — eine bestehende Sicht darf
       -- Spalten nur am Ende dazubekommen, und k.* hätte sie davor gestellt.
       k.band_von_g, k.band_bis_g
  from v_ausgang_kennzahl k
  join ausgang_wiegung w on w.id = k.id;

-- ---------------------------------------------------------------------
-- 2. Die Marge je Sorte und je Charge: nach Bandgrenzen, jede Palette je Kiste
-- ---------------------------------------------------------------------
drop materialized view if exists erg_marge_wiegung;
drop materialized view if exists erg_marge_charge;
-- erg_ausgang (0089) ebenso: die Arbeitsfenster lesen daraus je Wägung, und
-- sie sollen dieselben Grenzen zeigen wie die Marge. Gebaut wie in 0089 —
-- als angemeldeter Block, denn 0089 hat die Sicht so angemeldet, und der
-- Verdichter kennt je Sicht nur einen Bauplatz: stünde hier ein nacktes
-- create, baute setup.sql erg_ausgang zweimal (run.sh, Schritt 2, hat es
-- gezeigt: „relation erg_ausgang already exists").
-- verdichter: baut erg_ausgang
do $$
begin
  execute 'drop materialized view if exists erg_ausgang cascade';
  execute 'create materialized view erg_ausgang as select * from v_ausgang_voll with no data';
  execute 'grant select on erg_ausgang to authenticated';
  execute format('comment on materialized view erg_ausgang is %L',
                 'Gespeichert: jede gewogene fertige Palette mit ihren Kennzahlen (v_ausgang_voll) — seit 0089 mit voll, seit 0097 mit den Grenzen ihres Bandes (band_von_g, band_bis_g).');
end $$;
create index if not exists erg_ausgang_ts on erg_ausgang (ts);
comment on materialized view erg_ausgang is
  'Gespeichert: jede gewogene fertige Palette mit ihren Kennzahlen (v_ausgang_voll) — seit 0089 mit voll, seit 0097 mit den Grenzen ihres Bandes (band_von_g, band_bis_g).';

create or replace view v_marge_wiegung with (security_invoker = true) as
with w as (
  -- 0097: jede gewogene Palette zählt je Kiste. „Nicht voll" heisst: weniger
  -- Kisten auf der Palette, nicht weniger in der Kiste — 43 statt 44 Kisten
  -- ändern das Gewicht je Kiste nicht (Arbeit 1586: 11.76 gegen 11.90 kg).
  -- Bis 0096 zählten sie nicht; n_voll sagt, wie viele voll waren.
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
       betriebstag(max(w.ts))                                              as bis,
       -- 0097: die Grenzen des Bandes aus der Fassung des Auftrags — dazu
       -- gruppiert, weil derselbe Index in zwei Fassungen zwei Bänder sein kann.
       case when w.kistensystem = 'stueck'   then w.band_von_g end         as band_von_g,
       case when w.kistensystem = 'stueck'   then w.band_bis_g end         as band_bis_g,
       count(*) filter (where w.voll)::int                                 as n_voll
  from w
 group by w.sorte, w.kistensystem,
          case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end,
          case when w.kistensystem = 'stueck'   then w.kaliber_idx end,
          case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end,
          case when w.kistensystem = 'stueck'   then w.band_mittel_g end,
          case when w.kistensystem = 'stueck'   then w.band_von_g end,
          case when w.kistensystem = 'stueck'   then w.band_bis_g end,
          w.band_mittel_g;

create or replace view v_marge_charge with (security_invoker = true) as
with w as (
  select k.*
    from v_ausgang_voll k
   where k.kisten > 0 and k.netto_kg is not null and k.kistensystem is not null
)
select w.charge_nr,
       w.sorte,
       w.schlag,
       w.kistensystem,
       case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end   as soll_kg_pro_kiste,
       case when w.kistensystem = 'stueck'   then w.kaliber_idx end         as kaliber_idx,
       case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end     as stueck_je_kiste,
       case when w.kistensystem = 'stueck'   then w.band_mittel_g end       as band_mittel_g,
       count(*)::int                                                       as n_wiegungen,
       sum(w.kisten)::int                                                  as kisten,
       zahl(avg(w.kg_pro_kiste), 3, 10000)::numeric(10,3)                  as kg_je_kiste,
       zahl(stddev_samp(w.kg_pro_kiste), 3, 10000)::numeric(10,3)          as sd_je_kiste,
       zahl(avg(w.ueberfuellung_je_kiste), 3, 10000)::numeric(10,3)        as zuviel_je_kiste,
       zahl(avg(w.kg_pro_kuerbis) * 1000, 0, 1000000)::numeric(8,0)        as g_je_kuerbis,
       zahl(avg(w.kg_pro_kuerbis) * 1000 - w.band_mittel_g, 0, 1000000)::numeric(8,0)
                                                                           as g_ueber_bandmitte,
       betriebstag(min(w.ts))                                              as von,
       betriebstag(max(w.ts))                                              as bis,
       case when w.kistensystem = 'stueck'   then w.band_von_g end         as band_von_g,
       case when w.kistensystem = 'stueck'   then w.band_bis_g end         as band_bis_g,
       count(*) filter (where w.voll)::int                                 as n_voll
  from w
 group by w.charge_nr, w.sorte, w.schlag, w.kistensystem,
          case when w.kistensystem = 'kiste_ab' then w.soll_kg_pro_kiste end,
          case when w.kistensystem = 'stueck'   then w.kaliber_idx end,
          case when w.kistensystem = 'stueck'   then w.stueck_je_kiste end,
          case when w.kistensystem = 'stueck'   then w.band_mittel_g end,
          case when w.kistensystem = 'stueck'   then w.band_von_g end,
          case when w.kistensystem = 'stueck'   then w.band_bis_g end,
          w.band_mittel_g;

create materialized view erg_marge_wiegung as select * from v_marge_wiegung with no data;
grant select on erg_marge_wiegung to authenticated;
comment on materialized view erg_marge_wiegung is
  'Gespeichert: die verschenkte Marge je Sorte, Kistensystem und Band (0078) — seit 0097 mit den '
  'Grenzen des Bandes aus der Fassung des Auftrags und mit jeder gewogenen Palette je Kiste (n_voll sagt, wie viele voll waren).';

create materialized view erg_marge_charge as select * from v_marge_charge with no data;
grant select on erg_marge_charge to authenticated;
comment on materialized view erg_marge_charge is
  'Gespeichert: die verschenkte Marge je Charge (0086) — seit 0097 mit den Grenzen des Bandes '
  'aus der Fassung des Auftrags und mit jeder gewogenen Palette je Kiste.';

-- ---------------------------------------------------------------------
-- 3. Zu klein / zu gross: eine Art ohne Messung ist unbekannt
-- ---------------------------------------------------------------------
create or replace view v_ausschuss_beobachtung with (security_invoker = true) as
 SELECT 'maschine'::verarbeitungsweg AS weg,
    lm.charge_nr,
    lm.sorte,
    lm.auftrag_id,
    lm.masse_kg AS basis_kg,
    lm.masse_klein_kg AS klein_kg,
    lm.masse_nebenkanal_kg AS gross_kg,
    true AS plausibel
   FROM v_sortier_lauf_masse lm
  WHERE lm.masse_kg > 0::numeric
UNION ALL
 SELECT 'hand'::verarbeitungsweg AS weg,
    am.charge_nr,
    am.sorte,
    am.auftrag_id,
    n.basis AS basis_kg,
    h.klein_kg,
    h.gross_kg,
    -- 0097: Eine Art ohne Messung ist unbekannt, nicht 0. Sechs Arbeiten der
    -- Saison 2026 hatten „zu gross" gewogen und „zu klein" ausgelassen — die
    -- Auffälligkeit sagte „0 kg zu klein … stimmt nicht", und der Koeffizient
    -- verlor auch die gemessene Art. Was gemessen ist, wird geprüft; was
    -- fehlt, bleibt leer (v_koeff_roh_kaliber nimmt je Art nur Messungen).
    (h.klein_kg IS NULL OR anteil_plausibel(h.klein_kg / NULLIF(n.basis, 0::numeric)))
      AND (h.gross_kg IS NULL OR anteil_plausibel(h.gross_kg / NULLIF(n.basis, 0::numeric))) AS plausibel
   FROM v_auftrag_masse am
     JOIN ( SELECT ausschuss_messung.auftrag_id,
            sum(ausschuss_messung.kg) FILTER (WHERE ausschuss_messung.art = 'zu_klein'::ausschuss_art)::numeric AS klein_kg,
            sum(ausschuss_messung.kg) FILTER (WHERE ausschuss_messung.art = 'zu_gross'::ausschuss_art)::numeric AS gross_kg
           FROM ausschuss_messung
          WHERE ausschuss_messung.gemessen
          GROUP BY ausschuss_messung.auftrag_id) h ON h.auftrag_id = am.auftrag_id
     LEFT JOIN v_schimmel_menge sm ON sm.auftrag_id = am.auftrag_id
     LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = am.sorte
     CROSS JOIN LATERAL ( SELECT zahl(GREATEST(am.eingang_netto_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), GREATEST(am.lagertage, 0::numeric)) - COALESCE(sm.kg, 0::numeric), 0::numeric), 2, 1e10)::numeric(12,2) AS basis) n
  WHERE am.weg = 'hand'::verarbeitungsweg AND am.eingang_netto_kg IS NOT NULL AND am.lagertage IS NOT NULL;

-- ---------------------------------------------------------------------
-- 4. Der Sockel ohne Nachweis ist 0, nicht unbekannt
-- ---------------------------------------------------------------------
-- Die Sicht als Ganzes, wie 0064 sie gebaut hat; geändert sind zwei Zeilen
-- in je_charge (sockel_heute_kg, verlust_bekannt). sockel_nachgewiesen bleibt
-- der Nachweis. erg_charge, erg_bilanz und erg_massenbilanz lesen sie beim
-- nächsten Erneuern.
create or replace view v_hochrechnung_basis with (security_invoker = true) as
with je_charge as (
  select charge_nr,
         sum(m0) filter (where portion = 'ausgelagert')                       as ausgelagert_kg,
         sum(m0 * alter_tage) filter (where portion = 'ausgelagert')
           / nullif(sum(m0) filter (where portion = 'ausgelagert'), 0)        as alter_ausgelagert,
         sum(m0) filter (where portion = 'lager')                             as lager_kg,
         sum(m0 * alter_tage) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as alter_lager,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager')              as verkaufsfaehig_lager_kg,
         sum(geliefert_kg)                                                    as geliefert_kg,
         sum(ueberzaehlung_kg)                                                as ueberzaehlung_kg,
         sum(n_lieferungen)::int                                              as n_lieferungen,
         min(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_von,
         max(kohorte) filter (where portion = 'lager' and m0 > 0)             as rest_bis,
         count(*) filter (where portion = 'lager' and m0 > 0)::int            as n_rest_kohorten,
         sum(m0 * (kohorte - date '2000-01-01')) filter (where portion = 'lager')
           / nullif(sum(m0) filter (where portion = 'lager'), 0)              as rest_tage_seit_epoche,
         -- 0064: jede Stromsumme nur, wenn ihr Koeffizient gemessen ist.
         -- Das `coalesce` innerhalb der Bedingung trennt zwei Sorten NULL:
         -- „der Koeffizient ist unbekannt" (dann bleibt die ganze Summe NULL)
         -- von „diese Portion gibt es nicht" — eine Charge ohne Lieferung hat
         -- keine Zeile mit portion = 'ausgelagert', und dort ist 0 richtig.
         case when bool_and(r_bekannt)  then coalesce(sum(verdunstung_kg), 0) end as verdunstung_heute_kg,
         case when bool_and(f_bekannt)  then coalesce(sum(schimmel_kg), 0)    end as schimmel_heute_kg,
         -- 0097: Der Sockel a₀ ist der Anteil, der schon am ersten Tag faul
         -- war — er gilt nur, wenn die Daten ihn belegen (sockel_nachweis).
         -- Solange sie es nicht tun, ist er 0, nicht unbekannt: mv_kaskade
         -- rechnet ihn dann mit 0. Bis 0096 hing hier a0_bekannt, und weil
         -- das Verderbsmodell mit zwölf Punkten noch nicht brauchbar war,
         -- stand am ersten Tag mit echten Zahlen überall „Verlust bis heute —".
         case when bool_and(f_bekannt)  then coalesce(sum(sockel_kg), 0)      end as sockel_heute_kg,
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'ausgelagert'), 0)
              end                                                             as kanal_ausgelagert_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'ausgelagert'), 0) end as fax_heute_kg,
         case when bool_and(a_fax_bekannt)
              then coalesce(sum(fax_kg) filter (where portion = 'lager'), 0) end       as fax_erwartet_kg,
         sum(m2) filter (where portion = 'lager')                             as im_haus_heute_kg,
         case when bool_and(a_klein_bekannt and a_gross_bekannt)
              then coalesce(sum(klein_kg + nebenkanal_kg) filter (where portion = 'lager'), 0)
              end                                                             as kanal_im_haus_kg,
         bool_and(r_bekannt and f_bekannt and a_fax_bekannt
                  and a_klein_bekannt and a_gross_bekannt)                     as verlust_bekannt,
         bool_and(r_bekannt)                                                   as verdunstung_bekannt,
         bool_and(f_bekannt)                                                   as schimmel_bekannt,
         bool_and(a0_bekannt)                                                  as sockel_nachgewiesen,
         bool_and(a_fax_bekannt)                                               as fax_bekannt,
         bool_and(a_klein_bekannt and a_gross_bekannt)                         as kanal_bekannt,
         max(a0_var)                                                           as a0_var,
         -- 0064: gab es zu dieser Charge überhaupt eine Kaskadenzeile?
         count(*) > 0                                                          as gerechnet,
         count(*) filter (where portion = 'lager') > 0                         as hat_lager
    from mv_kaskade
   group by charge_nr
)
select b.charge_nr, b.schlag, b.sorte,
       b.eingang_kg,
       b.n_paletten,
       b.eingangsdatum_mittel,
       zahl(coalesce(k.ausgelagert_kg, 0), 2, 1e12)::numeric(14,2)             as ausgelagert_kg,
       zahl(k.alter_ausgelagert, 1, 1e5)::numeric(8,1)                         as alter_ausgelagert,
       -- 0064: keine Kaskadenzeile → es liegt noch alles. Zeilen, aber keine
       -- Portion „lager" → es liegt nichts mehr. Bisher hiess beides „alles".
       zahl(case when k.gerechnet is not true then b.eingang_kg
                 else coalesce(k.lager_kg, 0) end, 2, 1e12)::numeric(14,2)     as lager_kg,
       zahl(coalesce(k.alter_lager, (b.stichtag - b.eingangsdatum_mittel)), 1, 1e5)::numeric(8,1)
                                                                              as alter_lager,
       zahl((heute() - x.rest_datum), 1, 1e5)::numeric(8,1)                    as alter_lager_heute,
       b.weg2_anteil,
       b.stichtag,
       b.n_paletten_mit_netto,
       zahl(coalesce(k.ueberzaehlung_kg, 0), 2, 1e12)::numeric(14,2)           as ueberzaehlung_kg,
       b.sortiert_kg, b.gewaschen_kg, b.wartet_kg, b.anteil_gewaschen, b.alter_band, b.am_band_kg,
       x.rest_datum                                                           as eingangsdatum_rest,
       (coalesce(k.n_lieferungen, 0) > 0)                                     as rest_alter_aus_zaehlung,
       b.eingang_von, b.eingang_bis, b.n_eingangstage,
       coalesce(k.rest_von, b.eingang_von)                                    as rest_von,
       coalesce(k.rest_bis, b.eingang_bis)                                    as rest_bis,
       round(case when k.gerechnet is not true then b.eingang_kg else coalesce(k.lager_kg, 0) end
             / nullif(b.eingang_kg / nullif(b.n_paletten, 0), 0))::int        as n_rest_paletten,
       coalesce(k.n_rest_kohorten, b.n_eingangstage)                          as n_rest_kohorten,
       (heute() - coalesce(k.rest_bis, b.eingang_bis))::int                   as alter_lager_von,
       (heute() - coalesce(k.rest_von, b.eingang_von))::int                   as alter_lager_bis,
       zahl(coalesce(k.geliefert_kg, 0), 2, 1e12)::numeric(14,2)              as geliefert_kg,
       zahl(k.verkaufsfaehig_lager_kg, 2, 1e12)::numeric(14,2)                 as verkaufsfaehig_lager_kg,
       coalesce(k.n_lieferungen, 0)                                           as n_lieferungen,
       zahl(k.verdunstung_heute_kg, 2, 1e12)::numeric(14,2)                   as verdunstung_heute_kg,
       zahl(k.schimmel_heute_kg, 2, 1e12)::numeric(14,2)                      as schimmel_heute_kg,
       zahl(k.sockel_heute_kg, 2, 1e12)::numeric(14,2)                        as sockel_heute_kg,
       zahl(k.fax_heute_kg, 2, 1e12)::numeric(14,2)                           as fax_heute_kg,
       -- Der Verlust ist die Summe von vier Strömen. Fehlt einer, ist die
       -- Summe unbekannt — nicht die Summe der übrigen.
       zahl(k.verdunstung_heute_kg + k.schimmel_heute_kg + k.sockel_heute_kg + k.fax_heute_kg,
            2, 1e12)::numeric(14,2)                                           as verlust_heute_kg,
       zahl(k.kanal_ausgelagert_kg, 2, 1e12)::numeric(14,2)                   as kanal_ausgelagert_kg,
       zahl(k.fax_erwartet_kg, 2, 1e12)::numeric(14,2)                        as fax_erwartet_kg,
       zahl(case when k.gerechnet is not true then b.eingang_kg
                 else coalesce(k.im_haus_heute_kg, 0) end, 2, 1e12)::numeric(14,2) as im_haus_heute_kg,
       zahl(k.kanal_im_haus_kg, 2, 1e12)::numeric(14,2)                       as kanal_im_haus_kg,
       coalesce(k.verlust_bekannt, false)                                     as verlust_bekannt,
       coalesce(k.verdunstung_bekannt, false)                                 as verdunstung_bekannt,
       coalesce(k.schimmel_bekannt, false)                                    as schimmel_bekannt,
       coalesce(k.sockel_nachgewiesen, false)                                 as sockel_nachgewiesen,
       coalesce(k.fax_bekannt, false)                                         as fax_bekannt,
       coalesce(k.kanal_bekannt, false)                                       as kanal_bekannt,
       zahl(coalesce(k.lager_kg, 0) * 1.96 * sqrt(greatest(coalesce(k.a0_var, 0), 0)), 2, 1e12)::numeric(14,2)
                                                                              as sockel_oben_kg,
       heute()                                                                as heute
  from v_kaskade_basis b
  left join je_charge k on k.charge_nr = b.charge_nr
  cross join lateral (
    select case when k.rest_tage_seit_epoche is not null
                then date '2000-01-01' + round(k.rest_tage_seit_epoche)::int
                else b.eingangsdatum_mittel end as rest_datum
  ) x
 where b.eingang_kg is not null;

-- ---------------------------------------------------------------------
-- 5. Die Schlüssel der Marge-Ansichten kennen die Grenzen (0095)
-- ---------------------------------------------------------------------
create or replace function auswertung_schluessel()
returns table (sicht text, ausdruck text) language sql immutable set search_path = public as $$
  values
    ('erg_ausgang',            'id'),
    ('erg_ausschuss',          'weg, charge_nr, auftrag_id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_kurve',              'altersklasse'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_modell',             'n'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_plausibilitaet',     'art, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_selektion',          'n_verarbeitung'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte'),
    ('mv_schimmel_modell',     'n'),
    ('mv_schimmel_punkte',     'charge_nr, auftrag_id, quelle, lagertage')
$$;

revoke execute on function auswertung_schluessel() from public;
grant execute on function auswertung_schluessel() to authenticated;

-- ---------------------------------------------------------------------
-- 6. Abbrechen mit Erlaubnis
-- ---------------------------------------------------------------------
-- Der Betrieb: „Seraina soll die Möglichkeit haben, Aufträge, die gerade
-- noch laufen, zu löschen — auch wenn sie nicht die ist, die den Auftrag
-- gestartet hat." Löschen im Sinn der App ist Abbrechen (0013): Die Zeile
-- bleibt als Spur, zählt aber nirgends mehr. Bis 0096 durfte das, wer an
-- der Arbeit beteiligt war, und der Betriebsleiter — über die Zeilenregel
-- von auftrag. Jetzt auch, wer die Erlaubnis dazu hat: eine Spalte am
-- Profil, die der Betriebsleiter unter Betrieb → Stammdaten → Benutzer
-- setzt. Kein Name im Quelltext — Namen wechseln, Erlaubnisse werden erteilt.
-- Die Funktion prüft selbst und läuft als Eigentümer (security definer),
-- weil die Zeilenregel die Erlaubnis nicht kennt. Wer nicht Betriebsleiter
-- ist, bricht nur ab, was läuft.
alter table profil add column if not exists darf_abbrechen boolean not null default false;
comment on column profil.darf_abbrechen is
  'Darf laufende Arbeiten abbrechen, auch fremde (0097). Setzt der Betriebsleiter unter Benutzer.';

create or replace function public.darf_abbrechen()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profil where id = auth.uid() and darf_abbrechen and aktiv);
$$;
revoke execute on function public.darf_abbrechen() from public;
grant execute on function public.darf_abbrechen() to authenticated;

create or replace function auftrag_abbrechen(p_auftrag_id bigint, p_grund text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_status auftrag_status;
begin
  if not (ist_admin() or ist_beteiligt(p_auftrag_id) or darf_abbrechen()) then
    raise exception 'Abbrechen darf, wer an der Arbeit beteiligt ist, der Betriebsleiter — oder wer die Erlaubnis dazu hat.'
      using errcode = '42501';
  end if;
  select status into v_status from auftrag where id = p_auftrag_id;
  if not ist_admin() and v_status is distinct from 'offen' then
    raise exception 'Nur eine laufende Arbeit lässt sich abbrechen.' using errcode = '42501';
  end if;

  update auftrag
     set abgebrochen_ts = now(),
         abbruch_grund  = p_grund,
         status         = 'abgeschlossen',
         -- greatest, nicht einfach now(): Die Prüfregel verlangt ende_ts >= start_ts.
         -- Ein Abbruch darf nie an einer Zeitverschiebung scheitern.
         ende_ts        = greatest(coalesce(ende_ts, now()), start_ts)
   where id = p_auftrag_id and abgebrochen_ts is null;

  update sortier_lauf
     set auftrag_id = null, zuordnung = 'offen'
   where auftrag_id = p_auftrag_id;
end $$;
comment on function auftrag_abbrechen is
  'Verwirft eine Arbeit. Die Erfassungen bleiben als Spur stehen, zählen aber '
  'nirgends mehr mit; zugeordnete Sortier-CSVs gehen zurück in die Warteschlange. '
  'Seit 0097 mit eigener Prüfung: Beteiligte, Betriebsleiter, oder wer die Erlaubnis hat (profil.darf_abbrechen).';
revoke execute on function auftrag_abbrechen(bigint, text) from public;
grant execute on function auftrag_abbrechen(bigint, text) to authenticated;

-- ---------------------------------------------------------------------
-- Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 97 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
