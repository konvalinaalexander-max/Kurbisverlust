-- =====================================================================
-- 0059 — Keine harte Zahlenschranke mehr in einer Auswertungssicht
-- Kürbis-Verlust-Tracking
--
-- WARUM ES 0058 NICHT GETAN HAT
--
-- 0058 hat vier Sichten abgesichert — die, an denen es gerade klemmte.
-- Danach meldete der Betrieb `v_massenbilanz: numeric field overflow`. Das
-- war vorhersehbar und mein Fehler: Ich habe Sicht für Sicht geflickt,
-- statt die Ursache zu beseitigen. Es gibt im Schema **26 Sichten mit
-- zusammen 89 harten Casts** auf berechnete Grössen. Jeder einzelne kann
-- eine Sicht sprengen, und welcher es trifft, hängt an den Daten des
-- Betriebs. Sie einzeln abzuwarten hiesse, den Betriebsleiter jedes Mal
-- erneut vor einen leeren Bildschirm zu stellen.
--
-- WAS EIN HARTER CAST IST
--
-- `x::numeric(14,2)` ist eine *Behauptung*: „dieser Wert bleibt unter
-- 10^12". Bei einer gespeicherten Spalte ist das eine Zusage über die
-- Daten und richtig. Bei einer berechneten Grösse ist es eine Wette — und
-- wenn sie nicht aufgeht, fällt nicht die eine Zahl weg, sondern die ganze
-- Sicht. Das ist die schlechteste aller Ausfallarten.
--
-- WAS SICH ÄNDERT
--
-- Jeder dieser 89 Casts läuft jetzt durch `zahl(wert, stellen, grenze)`
-- (0058): Passt der Wert, wird er wie bisher gerundet; passt er nicht, ist
-- er NULL — im ganzen Projekt die Schreibweise für „unbekannt". Die App
-- zeigt dann „—", und der Rest des Bildschirms steht.
--
-- Die Spaltentypen bleiben **unverändert** (777 Spalten nachgeprüft), und
-- die Werte ebenfalls: Auf der Demo-Saison liefern alle 25 umgeschriebenen
-- Sichten Zeile für Zeile dasselbe wie vorher. Es ändert sich nur, was
-- passiert, wenn eine Zahl nicht darstellbar ist.
--
-- Gegen Rückfall prüft `pruefung.sql`: Kein `::numeric(p,s)` in irgendeiner
-- Sicht darf ohne `zahl(…, s, 1e^(p−s))` davor stehen. Wer künftig einen
-- harten Cast einbaut, hört es beim nächsten Testlauf.
--
-- Erzeugt mit einem Umschreiber über `pg_get_viewdef` — deshalb die
-- Grossschreibung der Schlüsselwörter; die Definitionen sind sonst
-- unverändert.
-- =====================================================================

-- v_auftrag_gebinde_masse: 3 Cast(s)
create or replace view v_auftrag_gebinde_masse with (security_invoker = true) as
 WITH band AS (
         SELECT DISTINCT s.sorte,
            i.idx AS kaliber_idx,
            ((s.kaliber_baender -> i.idx) ->> 0)::integer AS von,
            ((s.kaliber_baender -> i.idx) ->> 1)::integer AS bis
           FROM sortierschema s
             CROSS JOIN LATERAL generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) i(idx)
          WHERE s.art = 'kaliber'::text AND s.kaliber_baender IS NOT NULL
        )
 SELECT a.id AS auftrag_id,
    g.kaliber_idx,
    g.anzahl,
    zahl((g.anzahl::numeric * k.kg_je_gebinde), 2, 1e10)::numeric(12,2) AS kg,
    zahl((g.anzahl::numeric * k.unten), 2, 1e10)::numeric(12,2) AS kg_unten,
    zahl((g.anzahl::numeric * k.oben), 2, 1e10)::numeric(12,2) AS kg_oben,
    k.n AS n_messungen
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     JOIN auftrag_gebinde g ON g.auftrag_id = a.id
     LEFT JOIN LATERAL ( SELECT b.kaliber_idx
           FROM band b
          WHERE g.kaliber_idx = '-2'::integer AND b.sorte = c.sorte AND b.von = a.kaliber_von_g AND b.bis = a.kaliber_bis_g
          ORDER BY b.kaliber_idx
         LIMIT 1) e ON true
     LEFT JOIN v_koeff_gebinde k ON k.sorte = c.sorte AND k.kaliber_idx =
        CASE
            WHEN g.kaliber_idx = '-2'::integer THEN e.kaliber_idx
            ELSE g.kaliber_idx
        END
  WHERE a.station = 'waschen'::station AND a.abgebrochen_ts IS NULL;
comment on view v_auftrag_gebinde_masse is 'Verarbeitete Menge einer Wascharbeit aus gezählten Kisten mal gemessenem Kistengewicht. kg ist NULL, solange das Kaliber nie am Sortieren gezählt wurde — dann fehlt der Nenner weiterhin. Index −2 (eigenes Kaliber) findet sein Gewicht über die Bandgrenzen in einer Fassung der Sorte (0054).';
grant select on v_auftrag_gebinde_masse to authenticated;

-- v_auftrag_masse: 1 Cast(s)
create or replace view v_auftrag_masse with (security_invoker = true) as
 SELECT m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.schlag,
    m.weg,
    m.station,
    m.start_ts,
    m.ende_ts,
    m.status,
    m.n_paletten,
    COALESCE(m.eingang_netto_kg, gb.kg) AS eingang_netto_kg,
        CASE
            WHEN m.masse_quelle <> 'fehlt'::text THEN m.masse_quelle
            WHEN gb.kg IS NOT NULL THEN 'gebinde'::text
            ELSE 'fehlt'::text
        END AS masse_quelle,
    zahl(COALESCE(m.lagertage,
        CASE
            WHEN m.station = 'waschen'::station THEN (m.start_ts::date - '2000-01-01'::date)::numeric - COALESCE(se.tage_seit_epoche, (r.eingangsdatum_mittel - '2000-01-01'::date)::numeric)
            ELSE NULL::numeric
        END), 1, 1e9)::numeric(10,1) AS lagertage,
    a.ist_fax
   FROM mv_auftrag_masse m
     JOIN auftrag a ON a.id = m.auftrag_id
     LEFT JOIN mv_sortier_eingang se ON se.charge_nr = m.charge_nr
     LEFT JOIN v_charge_rueckgrat r ON r.charge_nr = m.charge_nr
     LEFT JOIN ( SELECT v_auftrag_gebinde_masse.auftrag_id,
            sum(v_auftrag_gebinde_masse.kg) AS kg
           FROM v_auftrag_gebinde_masse
          GROUP BY v_auftrag_gebinde_masse.auftrag_id) gb ON gb.auftrag_id = m.auftrag_id;
comment on view v_auftrag_masse is 'Masse je Arbeit aus drei Quellen: gewogene Paletten, eingetippter Durchsatz, gezählte Kisten mal gemessenem Kistengewicht. ist_fax: die Arbeit ist ein Fax (Abpacken), kein Waschgang — sie zählt nicht als gewaschen.';
grant select on v_auftrag_masse to authenticated;

-- v_auftrag_palette_masse: 1 Cast(s)
create or replace view v_auftrag_palette_masse with (security_invoker = true) as
 WITH wiegung AS MATERIALIZED (
         SELECT vw.id,
            zahl((vw.brutto_damals_kg - COALESCE(vw.kisten, 0)::numeric * g.tara_kg_pro_kiste - COALESCE(g.tara_kg_palette, 0::numeric)), 2, 1e8)::numeric(10,2) AS netto_damals_kg,
            vw.eingangsdatum
           FROM verdunstung_wiegung vw
             LEFT JOIN gebinde g ON g.art = vw.gebindeart
        ), datum_mittel AS MATERIALIZED (
         SELECT v_palette.charge_nr,
            v_palette.eingangsdatum,
            avg(v_palette.netto_kg) AS netto_mittel
           FROM v_palette
          GROUP BY v_palette.charge_nr, v_palette.eingangsdatum
        ), charge_mittel AS MATERIALIZED (
         SELECT v_palette.charge_nr,
            avg(v_palette.netto_kg) AS netto_mittel
           FROM v_palette
          GROUP BY v_palette.charge_nr
        ), charge_datum AS MATERIALIZED (
         SELECT v_charge_rueckgrat.charge_nr,
            v_charge_rueckgrat.eingangsdatum_mittel
           FROM v_charge_rueckgrat
        )
 SELECT ap.id,
    ap.auftrag_id,
    a.charge_nr,
    a.start_ts,
    COALESCE(w.netto_damals_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) AS netto_kg,
    COALESCE(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) AS eingangsdatum,
        CASE
            WHEN w.netto_damals_kg IS NOT NULL THEN 'gewogen'::text
            WHEN p.netto_kg IS NOT NULL THEN 'palette'::text
            WHEN d.netto_mittel IS NOT NULL THEN 'datum-mittel'::text
            WHEN cm.netto_mittel IS NOT NULL THEN 'charge-mittel'::text
            ELSE 'unbekannt'::text
        END AS masse_quelle
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     LEFT JOIN wiegung w ON w.id = ap.wiegung_id
     LEFT JOIN v_palette p ON p.id = ap.palette_id
     LEFT JOIN datum_mittel d ON d.charge_nr = a.charge_nr AND d.eingangsdatum = ap.eingangsdatum
     LEFT JOIN charge_mittel cm ON cm.charge_nr = a.charge_nr
     LEFT JOIN charge_datum cd ON cd.charge_nr = a.charge_nr;
grant select on v_auftrag_palette_masse to authenticated;

-- v_ausgang_artikel_vorschlag: 1 Cast(s)
create or replace view v_ausgang_artikel_vorschlag with (security_invoker = true) as
 WITH zeile_charge AS (
         SELECT z.id,
            z.artikel_id,
            z.artikel,
            z.datum,
            z.kg_charge,
            c.nr AS charge_nr,
            c.sorte
           FROM ausgang_zeile z
             CROSS JOIN LATERAL ( SELECT NULLIF(regexp_replace(z.charge_extern, '\D'::text, ''::text, 'g'::text), ''::text)::bigint AS nummer) x
             LEFT JOIN LATERAL ( SELECT c_1.nr,
                    c_1.sorte
                   FROM charge c_1
                  WHERE x.nummer IS NOT NULL AND (c_1.nr = x.nummer OR c_1.perigon_nr = x.nummer)
                  ORDER BY (c_1.nr = x.nummer) DESC, c_1.nr
                 LIMIT 1) c ON true
        ), beobachtet AS (
         SELECT zeile_charge.artikel_id,
            zeile_charge.artikel,
            count(*)::integer AS zeilen,
            min(zeile_charge.datum) AS von,
            max(zeile_charge.datum) AS bis,
            sum(zeile_charge.kg_charge) AS kg,
            count(*) FILTER (WHERE zeile_charge.charge_nr IS NOT NULL)::integer AS zeilen_mit_charge
           FROM zeile_charge
          GROUP BY zeile_charge.artikel_id, zeile_charge.artikel
        ), sorte_je_artikel AS (
         SELECT DISTINCT ON (zeile_charge.artikel_id, zeile_charge.artikel) zeile_charge.artikel_id,
            zeile_charge.artikel,
            zeile_charge.sorte,
            count(*)::integer AS n
           FROM zeile_charge
          WHERE zeile_charge.charge_nr IS NOT NULL
          GROUP BY zeile_charge.artikel_id, zeile_charge.artikel, zeile_charge.sorte
          ORDER BY zeile_charge.artikel_id, zeile_charge.artikel, (count(*)) DESC, zeile_charge.sorte
        )
 SELECT b.artikel_id,
    b.artikel,
    b.zeilen,
    b.von,
    b.bis,
    zahl(b.kg, 1, 1e13)::numeric(14,1) AS kg,
    b.zeilen_mit_charge,
    a.ist_kuerbis AS bestaetigt_kuerbis,
    a.sorte AS bestaetigte_sorte,
    a.artikel_id IS NOT NULL AS bestaetigt,
    lower((b.artikel_id || ' '::text) || b.artikel) ~ 'k(ü|u|ue)rb'::text AND lower((b.artikel_id || ' '::text) || b.artikel) !~ '(verrechnung|arbeit|lohn|transport|miete)'::text AS vorschlag_kuerbis,
    s.sorte AS vorschlag_sorte,
    s.n AS vorschlag_belege
   FROM beobachtet b
     LEFT JOIN ausgang_artikel a ON a.artikel_id = b.artikel_id AND a.artikel = b.artikel
     LEFT JOIN sorte_je_artikel s ON s.artikel_id = b.artikel_id AND s.artikel = b.artikel;
comment on view v_ausgang_artikel_vorschlag is 'Jeder Artikel aus den Importzeilen mit Vorschlag und Bestätigung. Die vorgeschlagene Sorte stammt aus den Zeilen, die eine eigene Chargennummer tragen — beobachtet, nicht geraten.';
grant select on v_ausgang_artikel_vorschlag to authenticated;

-- v_ausgang_kennzahl: 5 Cast(s)
create or replace view v_ausgang_kennzahl with (security_invoker = true) as
 SELECT w.id,
    w.auftrag_id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.ts,
    w.brutto_kg,
    w.kisten,
    w.gebindeart,
    w.kuerbisse_pro_kiste,
    n.netto_kg,
    zahl((n.netto_kg / w.kisten::numeric), 3, 1e7)::numeric(10,3) AS kg_pro_kiste,
    zahl((n.netto_kg / NULLIF(w.kisten * w.kuerbisse_pro_kiste, 0)::numeric), 3, 1e7)::numeric(10,3) AS kg_pro_kuerbis,
    s.soll AS soll_kg_pro_kiste,
        zahl(CASE
            WHEN s.soll IS NOT NULL THEN n.netto_kg / w.kisten::numeric - s.soll
            ELSE NULL::numeric
        END, 3, 1e7)::numeric(10,3) AS ueberfuellung_je_kiste,
        zahl(CASE
            WHEN s.soll IS NOT NULL THEN n.netto_kg - w.kisten::numeric * s.soll
            ELSE NULL::numeric
        END, 2, 1e8)::numeric(10,2) AS ueberfuellung_kg
   FROM ausgang_wiegung w
     JOIN auftrag a ON a.id = w.auftrag_id
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     LEFT JOIN sortierschema ss ON ss.id = a.sortierschema_id
     CROSS JOIN LATERAL ( SELECT zahl((w.brutto_kg - w.kisten::numeric * g.tara_kg_pro_kiste - COALESCE(g.tara_kg_palette, 0::numeric)), 2, 1e8)::numeric(10,2) AS netto_kg) n
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN ss.art = 'kiste'::text THEN ss.soll_kg_pro_kiste
                    ELSE NULL::numeric
                END AS soll) s
  WHERE w.gemessen AND a.abgebrochen_ts IS NULL AND n.netto_kg > 0::numeric;
comment on view v_ausgang_kennzahl is 'Je fertiger Palette: tatsächliche Kilo je Kiste und der Überschuss über das Sollgewicht. Der Überschuss ist NULL, wenn die Arbeit nach Kaliber lief — dann gibt es kein Sollgewicht und nichts zu verschenken.';
grant select on v_ausgang_kennzahl to authenticated;

-- v_ausgang_lage: 1 Cast(s)
create or replace view v_ausgang_lage with (security_invoker = true) as
 SELECT code AS quelle,
    name,
    (( SELECT count(*) AS count
           FROM ausgang_zeile z
          WHERE z.quelle = q.code))::integer AS zeilen,
    ( SELECT min(z.datum) AS min
           FROM ausgang_zeile z
          WHERE z.quelle = q.code) AS von,
    ( SELECT max(z.datum) AS max
           FROM ausgang_zeile z
          WHERE z.quelle = q.code) AS bis,
    ( SELECT max(d.ts) AS max
           FROM ausgang_datei d
          WHERE d.quelle = q.code) AS zuletzt_geladen,
    (( SELECT count(*) AS count
           FROM ausgang_datei d
          WHERE d.quelle = q.code))::integer AS dateien,
    (( SELECT count(*) AS count
           FROM lieferung_import i
          WHERE i.quelle = q.code))::integer AS lieferungen,
    zahl((( SELECT COALESCE(sum(l.kg), 0::numeric) AS "coalesce"
           FROM lieferung_import i
             JOIN lieferung l ON l.id = i.lieferung_id
          WHERE i.quelle = q.code)), 1, 1e13)::numeric(14,1) AS kg,
    (( SELECT count(*) AS count
           FROM v_ausgang_artikel_vorschlag v
          WHERE NOT v.bestaetigt AND v.vorschlag_kuerbis AND (EXISTS ( SELECT 1
                   FROM ausgang_zeile z
                  WHERE z.quelle = q.code AND z.artikel_id = v.artikel_id AND z.artikel = v.artikel))))::integer AS artikel_offen
   FROM ausgang_quelle q;
comment on view v_ausgang_lage is 'Je Quelle: wie viel eingelesen ist, bis wann, und wie viele Artikel noch auf ihre Bestätigung warten.';
grant select on v_ausgang_lage to authenticated;

-- v_ausgang_pruef: 3 Cast(s)
create or replace view v_ausgang_pruef with (security_invoker = true) as
 WITH urteil AS (
         SELECT v_ausgang_artikel_vorschlag.artikel_id,
            v_ausgang_artikel_vorschlag.artikel,
            COALESCE(v_ausgang_artikel_vorschlag.bestaetigt_kuerbis, v_ausgang_artikel_vorschlag.vorschlag_kuerbis) AS kuerbis
           FROM v_ausgang_artikel_vorschlag
        ), pos AS (
         SELECT DISTINCT ON (z.quelle, z.pos_id) z.quelle,
            z.pos_id,
            z.datum,
            z.artikel_id,
            z.artikel,
            z.kunde,
            z.kg_position
           FROM ausgang_zeile z
          ORDER BY z.quelle, z.pos_id, z.lauf_nr
        ), geliefert AS (
         SELECT i.quelle,
            NULLIF(split_part(i.extern_id, ':'::text, 2), ''::text)::bigint AS pos_id,
            sum(l.kg) AS kg
           FROM lieferung_import i
             JOIN lieferung l ON l.id = i.lieferung_id
          GROUP BY i.quelle, (NULLIF(split_part(i.extern_id, ':'::text, 2), ''::text)::bigint)
        )
 SELECT p.quelle,
    p.pos_id,
    p.datum,
    p.artikel,
    p.kunde,
    zahl(p.kg_position, 2, 1e12)::numeric(14,2) AS kg_datei,
    zahl(COALESCE(g.kg, 0::numeric), 2, 1e12)::numeric(14,2) AS kg_lieferung,
    zahl((COALESCE(g.kg, 0::numeric) - p.kg_position), 2, 1e12)::numeric(14,2) AS abweichung_kg
   FROM pos p
     JOIN urteil u ON u.artikel_id = p.artikel_id AND u.artikel = p.artikel AND u.kuerbis
     LEFT JOIN geliefert g ON g.quelle = p.quelle AND g.pos_id = p.pos_id
  WHERE abs(COALESCE(g.kg, 0::numeric) - p.kg_position) > 0.05 AND p.kg_position > 0::numeric;
comment on view v_ausgang_pruef is 'Kürbis-Positionen, deren übernommene Lieferungen nicht die Masse der Datei ergeben. Leer ist der Normalfall; jede Zeile hier ist ein Kilo zu viel oder zu wenig. Eine vergessene Position steht hier mit ihrer vollen Masse.';
grant select on v_ausgang_pruef to authenticated;

-- v_ausschuss_beobachtung: 1 Cast(s)
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
    anteil_plausibel(h.klein_kg / NULLIF(n.basis, 0::numeric)) AND anteil_plausibel(COALESCE(h.gross_kg, 0::numeric) / NULLIF(n.basis, 0::numeric)) AS plausibel
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
comment on view v_ausschuss_beobachtung is 'Zu klein und zu gross je Arbeit gegen ihre Basis: am Band die CSV-Masse, von Hand der Eingang abzüglich Verdunstung (gedeckelte Rate, 0057) und Schimmel.';
grant select on v_ausschuss_beobachtung to authenticated;

-- v_charge_kohorte: 2 Cast(s)
create or replace view v_charge_kohorte with (security_invoker = true) as
 WITH gezaehlt AS (
         SELECT a.charge_nr,
            COALESCE(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum) AS eingangsdatum,
            count(*)::integer AS n
           FROM auftrag_palette ap
             JOIN auftrag a ON a.id = ap.auftrag_id
             LEFT JOIN palette p ON p.id = ap.palette_id
             LEFT JOIN verdunstung_wiegung w ON w.id = ap.wiegung_id
          WHERE a.abgebrochen_ts IS NULL AND (a.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station]))
          GROUP BY a.charge_nr, (COALESCE(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum))
        ), je_datum AS (
         SELECT p.charge_nr,
            p.eingangsdatum,
            count(*)::integer AS n,
            avg(p.netto_kg) AS netto_mittel
           FROM v_palette p
          GROUP BY p.charge_nr, p.eingangsdatum
        ), charge_netto AS (
         SELECT v_palette.charge_nr,
            avg(v_palette.netto_kg) AS netto
           FROM v_palette
          GROUP BY v_palette.charge_nr
        )
 SELECT d.charge_nr,
    d.eingangsdatum,
    d.n AS n_paletten,
    COALESCE(g.n, 0) AS n_verarbeitet,
    GREATEST(d.n - COALESCE(g.n, 0), 0) AS n_rest,
    zahl(COALESCE(d.netto_mittel, cn.netto), 2, 1e8)::numeric(10,2) AS netto_je_palette,
    zahl((GREATEST(d.n - COALESCE(g.n, 0), 0)::numeric * COALESCE(d.netto_mittel, cn.netto)), 2, 1e10)::numeric(12,2) AS rest_kg,
    CURRENT_DATE - d.eingangsdatum AS alter_heute
   FROM je_datum d
     JOIN charge_netto cn ON cn.charge_nr = d.charge_nr
     LEFT JOIN gezaehlt g ON g.charge_nr = d.charge_nr AND g.eingangsdatum = d.eingangsdatum;
comment on view v_charge_kohorte is 'Je Charge und Eingangstag: wie viele Paletten kamen, wie viele davon wurden seither mit diesem Zetteldatum gezählt, wie viele liegen also noch. Kein FIFO — die gezählten Daten sagen, welche Paletten weg sind.';
grant select on v_charge_kohorte to authenticated;

-- v_durchsatz: 2 Cast(s)
create or replace view v_durchsatz with (security_invoker = true) as
 SELECT a.id AS auftrag_id,
    a.charge_nr,
    m.sorte,
    a.station,
    a.weg,
    a.ist_fax,
    a.start_ts,
    a.ende_ts,
    zahl((EXTRACT(epoch FROM a.ende_ts - a.start_ts) / 3600::numeric), 2, 1e8)::numeric(10,2) AS dauer_h,
    m.eingang_netto_kg AS masse_kg,
    m.masse_quelle,
    m.n_paletten,
        zahl(CASE
            WHEN m.eingang_netto_kg IS NOT NULL AND (a.ende_ts - a.start_ts) >= '00:15:00'::interval THEN m.eingang_netto_kg / (EXTRACT(epoch FROM a.ende_ts - a.start_ts) / 3600::numeric)
            ELSE NULL::numeric
        END, 1, 1e9)::numeric(10,1) AS kg_pro_h,
    (( SELECT count(*) AS count
           FROM auftrag_teilnehmer t
          WHERE t.auftrag_id = a.id))::integer AS n_teilnehmer
   FROM auftrag a
     JOIN v_auftrag_masse m ON m.auftrag_id = a.id
  WHERE a.status = 'abgeschlossen'::auftrag_status AND a.abgebrochen_ts IS NULL AND a.ende_ts IS NOT NULL;
comment on view v_durchsatz is 'Abgeschlossene Arbeiten mit Dauer, Masse und Kilo je Stunde. kg_pro_h ist NULL, wenn die Masse unbekannt ist oder die Arbeit kürzer als eine Viertelstunde war.';
grant select on v_durchsatz to authenticated;

-- v_fax_beobachtung: 1 Cast(s)
create or replace view v_fax_beobachtung with (security_invoker = true) as
 SELECT a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    c.schlag,
    a.kaeufer,
    a.start_ts,
    a.ende_ts,
    a.status,
    a.abgebrochen_ts,
    m.eingang_netto_kg AS masse_kg,
    m.masse_quelle,
    COALESCE(g.kisten, 0) AS kisten,
    COALESCE(s.kg, 0::numeric) AS faul_kg,
    s.auftrag_id IS NOT NULL AS faul_erfasst,
    zahl((COALESCE(s.kg, 0::numeric) / NULLIF(m.eingang_netto_kg + COALESCE(s.kg, 0::numeric), 0::numeric)), 5, 1e5)::numeric(10,5) AS anteil,
    anteil_plausibel(COALESCE(s.kg, 0::numeric) / NULLIF(m.eingang_netto_kg + COALESCE(s.kg, 0::numeric), 0::numeric)) AS plausibel
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_masse m ON m.auftrag_id = a.id
     LEFT JOIN v_schimmel_menge s ON s.auftrag_id = a.id
     LEFT JOIN ( SELECT auftrag_gebinde.auftrag_id,
            sum(auftrag_gebinde.anzahl)::integer AS kisten
           FROM auftrag_gebinde
          GROUP BY auftrag_gebinde.auftrag_id) g ON g.auftrag_id = a.id
  WHERE a.ist_fax AND a.abgebrochen_ts IS NULL;
comment on view v_fax_beobachtung is 'Je Fax-Arbeit: gemachte Kisten, daraus die Masse, das gewogene Faule und sein Anteil an dem, was durch die Hände ging (Masse + Faules). Grundlage des Stroms „Faul beim Abpacken".';
grant select on v_fax_beobachtung to authenticated;

-- v_hochrechnung: 2 Cast(s)
create or replace view v_hochrechnung with (security_invoker = true) as
 SELECT k.charge_nr,
    k.sorte,
    k.schlag,
    k.portion,
    k.alter_tage,
    k.eingang_kg,
    zahl(c.m0)::numeric(14,2) AS portion_kg,
    k.f_extrapoliert,
    k.u,
    s.strom,
    s.buch,
        zahl(CASE
            WHEN s.bekannt THEN s.kg
            ELSE NULL::numeric
        END, 2, 1e12)::numeric(14,2) AS kg,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
        zahl(CASE
            WHEN s.bekannt THEN s.koeffizient
            ELSE NULL::numeric
        END, 6, 1e6)::numeric(12,6) AS koeffizient,
    s.koeff_n,
    s.koeff_basis,
    s.formel,
    s.d_r,
    s.d_f * k.d_f_eta AS d_eta,
    s.d_a,
    s.d_a0,
    s.koeff_art,
    s.bekannt AS koeff_bekannt,
    k.kohorte
   FROM v_kaskade k
     CROSS JOIN LATERAL ( SELECT GREATEST(k.m0, 0::numeric) AS m0,
            GREATEST(k.m1, 0::numeric) AS m1,
            GREATEST(k.m2, 0::numeric) AS m2,
            GREATEST(k.verkaufsfaehig_kg, 0::numeric) AS verkaufsfaehig_kg,
            LEAST(GREATEST(k.r, 0::numeric), 1::numeric) AS r,
            LEAST(GREATEST(k.f, 0::numeric), 1::numeric) AS f,
            LEAST(GREATEST(k.a0, 0::numeric), 1::numeric) AS a0,
            LEAST(GREATEST(k.a_klein_n, 0::numeric), 1::numeric) AS a_klein_n,
            LEAST(GREATEST(k.a_gross_n, 0::numeric), 1::numeric) AS a_gross_n,
            LEAST(GREATEST(k.a_fax, 0::numeric), 1::numeric) AS a_fax) c
     CROSS JOIN LATERAL ( VALUES ('Verdunstung'::text,'verlust'::text,c.m0 - c.m1,c.m0,c.r,k.r_n,k.r_basis,'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'::text,- k.d_m1_r,0::numeric,0::numeric,0::numeric,NULL::text,k.r_bekannt), ('Nicht lagerbedingt'::text,'feld'::text,c.m1 * c.a0,c.m1,c.a0,k.f_n,'Grundaussortierung a₀ aus dem Verderbsmodell: was bei Lagerdauer null schon im Palox läge'::text,'Masse nach Verdunstung × a₀ — Erde, Hagelnarben, Schnittfehler; kein Lagerverlust'::text,k.d_m1_r * c.a0,0::numeric,0::numeric,c.m1,NULL::text,k.a0_bekannt), ('Schimmel/Fäulnis'::text,'verlust'::text,c.m1 * (1::numeric - c.a0) * c.f,c.m1 * (1::numeric - c.a0),c.f,k.f_n,'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen'::text,'Masse nach Verdunstung und Sockel × Schimmelanteil bei dieser Lagerdauer'::text,k.d_m1_r * (1::numeric - c.a0) * c.f,c.m1 * (1::numeric - c.a0),0::numeric,(- c.m1) * c.f,NULL::text,k.f_bekannt), ('Zu klein (Tierfutter)'::text,'marge'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_klein_n,c.m2,c.a_klein_n,k.klein_n,k.klein_basis,'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_klein_n,(- c.m1) * (1::numeric - c.a0) * c.a_klein_n,c.m2,(- c.m1) * (1::numeric - c.f) * c.a_klein_n,'ausschuss'::text,k.a_klein_bekannt), ('Nebenkanal zu gross'::text,'marge'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_gross_n,c.m2,c.a_gross_n,k.gross_n,k.gross_basis,'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * c.a_gross_n,(- c.m1) * (1::numeric - c.a0) * c.a_gross_n,c.m2,(- c.m1) * (1::numeric - c.f) * c.a_gross_n,'nebenkanal'::text,k.a_gross_bekannt), ('Faul beim Abpacken (Fax)'::text,'verlust'::text,c.m1 * (1::numeric - c.a0) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),c.a_fax,k.fax_n,k.fax_basis,'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer'::text,k.d_m1_r * (1::numeric - c.a0) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,(- c.m1) * (1::numeric - c.a0) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,c.m2 * (1::numeric - c.a_klein_n - c.a_gross_n),(- c.m1) * (1::numeric - c.f) * (1::numeric - c.a_klein_n - c.a_gross_n) * c.a_fax,'fax'::text,k.a_fax_bekannt), ('Verkaufsfähig'::text,'bilanz'::text,c.verkaufsfaehig_kg,c.m2,NULL::numeric,NULL::integer,NULL::text,'Rest der Kaskade'::text,0::numeric,0::numeric,0::numeric,0::numeric,NULL::text,true)) s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel, d_r, d_f, d_a, d_a0, koeff_art, bekannt);
comment on view v_hochrechnung is 'Ein Strom je Charge, Portion und (im Lager) Eingangstag. kg ist NULL, wenn der Koeffizient dahinter nie gemessen wurde — koeff_bekannt sagt es. Jeder Koeffizient ist ein Anteil (0 … 1), jede Masse ist nie negativ (0058).';
grant select on v_hochrechnung to authenticated;

-- v_koeff_gebinde: 4 Cast(s)
create or replace view v_koeff_gebinde with (security_invoker = true) as
 WITH je_arbeit AS (
         SELECT a.id AS auftrag_id,
            c.sorte,
            g.kaliber_idx,
            g.anzahl,
            sum(sg.anzahl::bigint * sg.gewicht_g) / 1000.0 AS kg
           FROM auftrag_gebinde g
             JOIN auftrag a ON a.id = g.auftrag_id AND a.abgebrochen_ts IS NULL
             JOIN charge c ON c.nr = a.charge_nr
             JOIN sortier_lauf l ON l.auftrag_id = a.id
             JOIN sortier_gewicht sg ON sg.lauf_id = l.id AND sg.klasse = 'kaliber'::kuerbis_klasse AND sg.kaliber_idx = g.kaliber_idx
          WHERE (a.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND g.anzahl > 0
          GROUP BY a.id, c.sorte, g.kaliber_idx, g.anzahl
        ), s AS (
         SELECT je_arbeit.sorte,
            je_arbeit.kaliber_idx,
            count(*)::integer AS n,
            sum(je_arbeit.kg) / NULLIF(sum(je_arbeit.anzahl), 0)::numeric AS kg_je_gebinde,
            stddev_samp(je_arbeit.kg / je_arbeit.anzahl::numeric) AS sd
           FROM je_arbeit
          GROUP BY je_arbeit.sorte, je_arbeit.kaliber_idx
        UNION ALL
         SELECT k.sorte,
            '-1'::integer,
            count(*)::integer AS count,
            sum(k.netto_kg) / NULLIF(sum(k.kisten), 0)::numeric,
            stddev_samp(k.kg_pro_kiste) AS stddev_samp
           FROM v_ausgang_kennzahl k
          WHERE k.soll_kg_pro_kiste IS NOT NULL
          GROUP BY k.sorte
        )
 SELECT sorte,
    kaliber_idx,
    n,
    zahl(kg_je_gebinde, 3, 1e7)::numeric(10,3) AS kg_je_gebinde,
    zahl(sd, 3, 1e7)::numeric(10,3) AS sd,
        zahl(CASE
            WHEN sd IS NULL OR n < 2 THEN kg_je_gebinde::double precision
            ELSE GREATEST(kg_je_gebinde::double precision - (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision), 0::double precision)
        END, 3, 1e7)::numeric(10,3) AS unten,
        zahl(CASE
            WHEN sd IS NULL OR n < 2 THEN kg_je_gebinde::double precision
            ELSE kg_je_gebinde::double precision + (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision)
        END, 3, 1e7)::numeric(10,3) AS oben
   FROM s
  WHERE kg_je_gebinde IS NOT NULL;
comment on view v_koeff_gebinde is 'Wie viel eine Kiste wiegt, je Sorte und Kaliber — gemessen am Sortieren aus CSV-Masse und gezählten Kisten. Kaliber −1: Kisten nach Sollgewicht, gemessen an den gewogenen fertigen Paletten. Ohne Messung steht hier keine Zeile.';
grant select on v_koeff_gebinde to authenticated;

-- v_koeff_roh_kaliber: 1 Cast(s)
create or replace view v_koeff_roh_kaliber with (security_invoker = true) as
 SELECT 'ausschuss'::text AS art,
    b.sorte,
    b.charge_nr,
    b.klein_kg / b.basis_kg AS anteil,
    b.basis_kg AS gewicht
   FROM v_ausschuss_beobachtung b
  WHERE b.plausibel AND b.basis_kg > 0::numeric AND b.klein_kg IS NOT NULL
UNION ALL
 SELECT 'nebenkanal'::text AS art,
    b.sorte,
    b.charge_nr,
    b.gross_kg / b.basis_kg AS anteil,
    b.basis_kg AS gewicht
   FROM v_ausschuss_beobachtung b
  WHERE b.plausibel AND b.basis_kg > 0::numeric AND b.gross_kg IS NOT NULL
UNION ALL
 SELECT 'fax'::text AS art,
    f.sorte,
    f.charge_nr,
    f.anteil::numeric AS anteil,
    zahl((f.masse_kg + f.faul_kg), 2, 1e10)::numeric(12,2) AS gewicht
   FROM v_fax_beobachtung f
  WHERE f.plausibel AND f.masse_kg > 0::numeric AND f.faul_erfasst AND f.status = 'abgeschlossen'::auftrag_status;
comment on view v_koeff_roh_kaliber is 'Koeffizienten-Rohwerte in einheitlicher Form: Anteil, die Masse, die er vertritt, und die Charge, aus der er stammt. ausschuss, nebenkanal, fax.';
grant select on v_koeff_roh_kaliber to authenticated;

-- v_koeff_ueberfuellung: 4 Cast(s)
create or replace view v_koeff_ueberfuellung with (security_invoker = true) as
 WITH roh AS (
         SELECT k.ueberfuellung_kg AS wert,
            k.kisten AS n_kisten,
            k.ueberfuellung_je_kiste AS je_kiste
           FROM v_ausgang_kennzahl k
          WHERE k.ueberfuellung_je_kiste IS NOT NULL
        ), s AS (
         SELECT count(*)::integer AS n,
            sum(roh.wert) / NULLIF(sum(roh.n_kisten), 0)::numeric AS kg_pro_kiste,
            stddev_samp(roh.je_kiste) AS sd
           FROM roh
        )
 SELECT n,
    zahl(kg_pro_kiste, 3, 1e7)::numeric(10,3) AS kg_pro_kiste,
    zahl(sd, 3, 1e7)::numeric(10,3) AS sd,
        zahl(CASE
            WHEN sd IS NULL OR n < 2 THEN kg_pro_kiste::double precision
            ELSE GREATEST(kg_pro_kiste::double precision - (1.96 * sd)::double precision / sqrt(n::double precision), 0::double precision)
        END, 3, 1e7)::numeric(10,3) AS unten,
        zahl(CASE
            WHEN sd IS NULL OR n < 2 THEN kg_pro_kiste::double precision
            ELSE kg_pro_kiste::double precision + (1.96 * sd)::double precision / sqrt(n::double precision)
        END, 3, 1e7)::numeric(10,3) AS oben
   FROM s;
comment on view v_koeff_ueberfuellung is 'Überschuss je Kiste über dem Sollgewicht, aus den Wägungen fertiger Paletten. Gezählt werden nur Wägungen, aus denen sich überhaupt ein Überschuss ergibt — Arbeiten nach Kaliber haben kein Sollgewicht und zählen nicht mit.';
grant select on v_koeff_ueberfuellung to authenticated;

-- v_kohorte_anteil: 1 Cast(s)
create or replace view v_kohorte_anteil with (security_invoker = true) as
 SELECT charge_nr,
    eingangsdatum,
    n_rest,
    rest_kg,
    zahl((rest_kg / sum(rest_kg) OVER (PARTITION BY charge_nr)), 6, 1e4)::numeric(10,6) AS anteil
   FROM v_charge_kohorte
  WHERE rest_kg > 0::numeric;
grant select on v_kohorte_anteil to authenticated;

-- v_massenbilanz: 4 Cast(s)
create or replace view v_massenbilanz with (security_invoker = true) as
 WITH csv_anteil AS MATERIALIZED (
         SELECT am.charge_nr,
            COALESCE(sum(am.eingang_netto_kg) FILTER (WHERE (EXISTS ( SELECT 1
                   FROM sortier_lauf l
                  WHERE l.auftrag_id = am.auftrag_id))) / NULLIF(sum(am.eingang_netto_kg), 0::numeric), 0::numeric) AS anteil_mit_csv
           FROM v_auftrag_masse am
          WHERE (am.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND am.eingang_netto_kg IS NOT NULL
          GROUP BY am.charge_nr
        ), gemessen AS MATERIALIZED (
         SELECT v_sortier_lauf_masse.charge_nr,
            sum(v_sortier_lauf_masse.masse_kg) AS gemessen_kg
           FROM v_sortier_lauf_masse
          GROUP BY v_sortier_lauf_masse.charge_nr
        ), rest AS MATERIALIZED (
         SELECT v_kaskade.charge_nr,
            sum(v_kaskade.m2) FILTER (WHERE v_kaskade.portion = 'lager'::text) AS restbestand_kg
           FROM v_kaskade
          GROUP BY v_kaskade.charge_nr
        ), modell AS MATERIALIZED (
         SELECT b_1.charge_nr,
            b_1.am_band_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), COALESCE(b_1.alter_band, 0::numeric)) * (1::numeric - sockel_anteil()) * (1::numeric - schimmelanteil(COALESCE(b_1.alter_band, 0::numeric))) * q.anteil_mit_csv AS am_band_modell_kg
           FROM v_hochrechnung_basis b_1
             LEFT JOIN csv_anteil q ON q.charge_nr = b_1.charge_nr
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b_1.sorte
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.eingang_kg,
    b.ausgelagert_kg,
    b.lager_kg,
    b.n_paletten,
    b.alter_ausgelagert,
    b.alter_lager,
    b.stichtag,
    zahl(m.am_band_modell_kg, 2, 1e12)::numeric(14,2) AS modell_am_band_kg,
    c.gemessen_kg AS csv_gemessen_kg,
    zahl((c.gemessen_kg - m.am_band_modell_kg), 2, 1e12)::numeric(14,2) AS abweichung_kg,
        CASE
            WHEN m.am_band_modell_kg > 0::numeric THEN zahl(((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg), 4, 1e6)::numeric(10,4)
            ELSE NULL::numeric
        END AS abweichung_anteil,
    zahl(r.restbestand_kg, 2, 1e12)::numeric(14,2) AS restbestand_kg,
    b.alter_band
   FROM v_hochrechnung_basis b
     LEFT JOIN modell m ON m.charge_nr = b.charge_nr
     LEFT JOIN gemessen c ON c.charge_nr = b.charge_nr
     LEFT JOIN rest r ON r.charge_nr = b.charge_nr;
comment on view v_massenbilanz is 'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. restbestand_kg ist die Masse, die nach Verdunstung und Verderb noch im Haus liegt — über alle Eingangstage summiert.';
grant select on v_massenbilanz to authenticated;

-- v_naechste_charge: 6 Cast(s)
create or replace view v_naechste_charge with (security_invoker = true) as
 WITH modell AS MATERIALIZED (
         SELECT v_schimmel_modell.n,
            v_schimmel_modell.c_chargen,
            v_schimmel_modell.t_min,
            v_schimmel_modell.t_max,
            v_schimmel_modell.k,
            v_schimmel_modell.ln_lambda,
            v_schimmel_modell.lambda,
            v_schimmel_modell.x_mittel,
            v_schimmel_modell.sxx,
            v_schimmel_modell.smearing,
            v_schimmel_modell.ln_lambda_korrigiert,
            v_schimmel_modell.sigma2,
            v_schimmel_modell.var_achse,
            v_schimmel_modell.var_k,
            v_schimmel_modell.kov_achse_k,
            v_schimmel_modell.t_faktor,
            v_schimmel_modell.brauchbar,
            v_schimmel_modell.selektions_versatz,
            v_schimmel_modell.sockel,
            v_schimmel_modell.sockel_unten,
            v_schimmel_modell.sockel_oben,
            v_schimmel_modell.sockel_nachweis,
            v_schimmel_modell.sockel_schwelle,
            v_schimmel_modell.sockel_var
           FROM v_schimmel_modell
        ), kohorten AS MATERIALIZED (
         SELECT v_kohorte_anteil.charge_nr,
            v_kohorte_anteil.eingangsdatum,
            v_kohorte_anteil.anteil
           FROM v_kohorte_anteil
        ), bestand AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.lager_kg,
            LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            t.m0,
            t.alter_tage
           FROM v_hochrechnung_basis b
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b.sorte
             CROSS JOIN LATERAL ( SELECT b.lager_kg * c.anteil AS m0,
                    GREATEST((CURRENT_DATE - c.eingangsdatum)::numeric, 0::numeric) AS alter_tage
                   FROM kohorten c
                  WHERE c.charge_nr = b.charge_nr
                UNION ALL
                 SELECT b.lager_kg,
                    GREATEST(b.alter_lager_heute, 0::numeric) AS "greatest"
                  WHERE NOT (EXISTS ( SELECT 1
                           FROM kohorten c
                          WHERE c.charge_nr = b.charge_nr))) t
          WHERE b.lager_kg > 0::numeric
        ), mit_f AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.lager_kg,
            b.r,
            b.m0,
            b.alter_tage,
            b.m0 * power(1::numeric - b.r, b.alter_tage) AS masse_jetzt_kg,
                CASE
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(b.alter_tage, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 0.99)
                    ELSE NULL::numeric
                END AS f_jetzt,
                CASE
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(b.alter_tage + 14::numeric, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 0.99)
                    ELSE NULL::numeric
                END AS f_dann,
            m.brauchbar AND b.alter_tage > m.t_max AS hochgerechnet,
            m.brauchbar AS modell_gilt
           FROM bestand b
             CROSS JOIN modell m
        ), je_charge AS (
         SELECT mit_f.charge_nr,
            mit_f.sorte,
            mit_f.schlag,
            mit_f.lager_kg,
            mit_f.modell_gilt,
            bool_or(mit_f.hochgerechnet) AS hochgerechnet,
            sum(mit_f.masse_jetzt_kg) AS masse_jetzt_kg,
            sum(mit_f.masse_jetzt_kg * mit_f.alter_tage) / NULLIF(sum(mit_f.masse_jetzt_kg), 0::numeric) AS alter_tage,
            min(mit_f.alter_tage) AS alter_von,
            max(mit_f.alter_tage) AS alter_bis,
            count(*)::integer AS n_kohorten,
            sum(mit_f.masse_jetzt_kg * (1::numeric - power(1::numeric - mit_f.r, 14::numeric))) AS verdunstung_14_kg,
                CASE
                    WHEN mit_f.modell_gilt THEN sum(mit_f.masse_jetzt_kg * (mit_f.f_dann - mit_f.f_jetzt) / NULLIF(1::numeric - mit_f.f_jetzt, 0::numeric))
                    ELSE NULL::numeric
                END AS schimmel_14_kg
           FROM mit_f
          GROUP BY mit_f.charge_nr, mit_f.sorte, mit_f.schlag, mit_f.lager_kg, mit_f.modell_gilt
        )
 SELECT charge_nr,
    sorte,
    schlag,
    zahl(lager_kg, 2, 1e12)::numeric(14,2) AS lager_kg,
    round(alter_tage)::integer AS alter_tage,
    zahl(masse_jetzt_kg, 2, 1e12)::numeric(14,2) AS masse_jetzt_kg,
    zahl(verdunstung_14_kg, 1, 1e11)::numeric(12,1) AS verdunstung_14_kg,
    zahl(schimmel_14_kg, 1, 1e11)::numeric(12,1) AS schimmel_14_kg,
    zahl((verdunstung_14_kg + COALESCE(schimmel_14_kg, 0::numeric)), 1, 1e11)::numeric(12,1) AS verlust_14_kg,
    hochgerechnet,
    modell_gilt,
    round(alter_von)::integer AS alter_von,
    round(alter_bis)::integer AS alter_bis,
    n_kohorten
   FROM je_charge
  ORDER BY (zahl((verdunstung_14_kg + COALESCE(schimmel_14_kg, 0::numeric)), 1, 1e11)::numeric(12,1)) DESC NULLS LAST;
comment on view v_naechste_charge is 'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag gerechnet und je Charge summiert. alter_tage ist das massegewichtete Mittel, alter_von/bis die Spanne der liegenden Kohorten.';
grant select on v_naechste_charge to authenticated;

-- v_saisonverlauf: 5 Cast(s)
create or replace view v_saisonverlauf with (security_invoker = true) as
 WITH ein AS (
         SELECT date_trunc('week'::text, p.eingangsdatum::timestamp with time zone)::date AS woche,
            sum(p.netto_kg) AS kg
           FROM v_palette p
          WHERE p.netto_kg IS NOT NULL AND p.eingangsdatum IS NOT NULL
          GROUP BY (date_trunc('week'::text, p.eingangsdatum::timestamp with time zone)::date)
        ), aus AS (
         SELECT date_trunc('week'::text, l.datum::timestamp with time zone)::date AS woche,
            sum(l.masse_kg) AS kg
           FROM v_lieferung_masse l
          WHERE l.masse_kg IS NOT NULL
          GROUP BY (date_trunc('week'::text, l.datum::timestamp with time zone)::date)
        ), grenzen AS (
         SELECT LEAST(( SELECT min(ein.woche) AS min
                   FROM ein), ( SELECT min(aus.woche) AS min
                   FROM aus)) AS von,
            GREATEST(( SELECT max(ein.woche) AS max
                   FROM ein), ( SELECT max(aus.woche) AS max
                   FROM aus), date_trunc('week'::text, CURRENT_DATE::timestamp with time zone)::date) AS bis
        ), wochen AS (
         SELECT generate_series(g.von::timestamp with time zone, g.bis::timestamp with time zone, '7 days'::interval)::date AS woche
           FROM grenzen g
          WHERE g.von IS NOT NULL
        ), vorlauf AS (
         SELECT COALESCE(sum(charge_vorlauf.ausgang_vor_app_kg), 0::numeric) AS kg
           FROM charge_vorlauf
        )
 SELECT w.woche,
    zahl(COALESCE(e.kg, 0::numeric), 1, 1e11)::numeric(12,1) AS eingang_kg,
    zahl(COALESCE(a.kg, 0::numeric), 1, 1e11)::numeric(12,1) AS ausgang_kg,
    zahl(sum(COALESCE(e.kg, 0::numeric)) OVER (ORDER BY w.woche), 1, 1e11)::numeric(12,1) AS eingang_kumuliert_kg,
    zahl((sum(COALESCE(a.kg, 0::numeric)) OVER (ORDER BY w.woche) + v.kg), 1, 1e11)::numeric(12,1) AS ausgang_kumuliert_kg,
    zahl(v.kg, 1, 1e11)::numeric(12,1) AS vorlauf_kg
   FROM wochen w
     CROSS JOIN vorlauf v
     LEFT JOIN ein e ON e.woche = w.woche
     LEFT JOIN aus a ON a.woche = w.woche;
comment on view v_saisonverlauf is 'Wareneingang und Warenausgang je Woche und kumuliert. Der Verlust fehlt bewusst — er ist modelliert, nicht datiert; die Differenz der Linien ist „im Haus, ohne Verlust".';
grant select on v_saisonverlauf to authenticated;

-- v_schimmel_beobachtung: 1 Cast(s)
create or replace view v_schimmel_beobachtung with (security_invoker = true) as
 SELECT am.auftrag_id,
    am.charge_nr,
    am.sorte,
    am.schlag,
    am.weg,
    am.station,
    am.start_ts,
    am.lagertage,
    am.masse_quelle,
    s.kg AS schimmel_kg,
    am.eingang_netto_kg AS eingang_kg,
    zahl((am.eingang_netto_kg * power(1::numeric - x.r, x.tage)), 2, 1e10)::numeric(12,2) AS basis_jetzt_kg,
    s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric) AS anteil,
    anteil_plausibel(s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric)) AS plausibel,
    am.ist_fax
   FROM v_auftrag_masse am
     JOIN v_schimmel_menge s ON s.auftrag_id = am.auftrag_id
     LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = am.sorte
     CROSS JOIN LATERAL ( SELECT LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            GREATEST(am.lagertage, 0::numeric) AS tage) x
  WHERE am.eingang_netto_kg IS NOT NULL AND am.lagertage IS NOT NULL;
comment on view v_schimmel_beobachtung is 'Schimmel je Arbeit gegen die Masse, die am Tag der Arbeit noch da war: Eingang abzüglich Verdunstung mit der gedeckelten Rate (0056). Fax-Faules bleibt beobachtbar, geht aber nicht in die Verderbskurve.';
grant select on v_schimmel_beobachtung to authenticated;

-- v_schimmel_kurve_anzeige: 4 Cast(s)
create or replace view v_schimmel_kurve_anzeige with (security_invoker = true) as
 SELECT von,
    bis,
        CASE
            WHEN bis > 9999 THEN von || '+ Tage'::text
            ELSE ((von || '–'::text) || bis) || ' Tage'::text
        END AS altersklasse,
    n AS messungen,
    zahl(anteil, 4, 1e6)::numeric(10,4) AS gemessen,
    zahl(schimmelanteil((von + LEAST(bis, von + 60))::numeric / 2.0), 4, 1e6)::numeric(10,4) AS verwendet,
    zahl(schimmelanteil((von + LEAST(bis, von + 60))::numeric / 2.0, 'unten'::text), 4, 1e6)::numeric(10,4) AS unten,
    zahl(schimmelanteil((von + LEAST(bis, von + 60))::numeric / 2.0, 'oben'::text), 4, 1e6)::numeric(10,4) AS oben,
        CASE
            WHEN NOT ( SELECT v_schimmel_modell.brauchbar
               FROM v_schimmel_modell) THEN 'Modell noch nicht anpassbar — es gilt die Treppenfunktion'::text
            WHEN von::numeric > (( SELECT v_schimmel_modell.t_max
               FROM v_schimmel_modell)) THEN 'über die längste gemessene Lagerdauer hinaus — hochgerechnet, '::text || 'daher der breitere Bereich'::text
            WHEN n = 0 THEN 'keine eigene Messung — aus dem Verlauf interpoliert'::text
            ELSE 'durch Messungen dieser Altersklasse gestützt'::text
        END ||
        CASE
            WHEN (( SELECT v_schimmel_modell.sockel
               FROM v_schimmel_modell)) > 0::numeric THEN format('; „gemessen" enthält den Sockel von %s %% (Erde, Hagel, Schnitt), '::text || '„verwendet" ist der reine Verderb'::text, round((( SELECT v_schimmel_modell.sockel
               FROM v_schimmel_modell)) * 100::numeric, 2))
            ELSE ''::text
        END AS erlaeuterung
   FROM v_schimmel_kurve k
  ORDER BY von;
grant select on v_schimmel_kurve_anzeige to authenticated;

-- v_schimmel_modell_rechnen: 2 Cast(s)
create or replace view v_schimmel_modell_rechnen with (security_invoker = true) as
 WITH roh AS (
         SELECT b.charge_nr,
            b.lagertage AS t,
            b.anteil AS f,
            b.basis_jetzt_kg AS w,
            b.quelle = 'verarbeitung'::text AS mit_sockel
           FROM mv_schimmel_punkte b
          WHERE b.plausibel AND b.anteil > 0::numeric AND b.anteil < 1::numeric AND b.lagertage > 0::numeric AND (b.quelle = ANY (ARRAY['verarbeitung'::text, 'lager'::text]))
        ), chargen AS (
         SELECT count(DISTINCT roh.charge_nr)::integer AS c
           FROM roh
        ), gitter AS (
         SELECT i.i::numeric * 0.0025 AS a0
           FROM generate_series(0, 40) i(i)
        ), kand AS (
         SELECT g.a0,
            r.charge_nr,
            r.t,
            r.f,
            r.w,
            r.mit_sockel,
            ln(r.t) AS x,
                CASE
                    WHEN r.mit_sockel THEN (r.f - g.a0) / (1::numeric - g.a0)
                    ELSE r.f
                END AS fs
           FROM gitter g
             CROSS JOIN roh r
        ), fit AS (
         SELECT q.a0,
            count(*)::integer AS n,
            count(DISTINCT q.charge_nr)::integer AS c_chargen,
            sum(q.w) AS sw,
            sum(q.w * q.x) AS swx,
            sum(q.w * q.y) AS swy,
            sum(q.w * q.x * q.x) AS swxx,
            sum(q.w * q.x * q.y) AS swxy
           FROM ( SELECT kand.a0,
                    kand.charge_nr,
                    kand.w,
                    kand.x,
                    ln(- ln(1::numeric - kand.fs)) AS y
                   FROM kand
                  WHERE kand.fs > 0::numeric AND kand.fs < 1::numeric) q
          GROUP BY q.a0
        ), param AS (
         SELECT f.a0,
            f.n,
            f.c_chargen,
            f.sw,
            f.swx,
            f.swy,
            f.swxx,
            f.swxy,
                CASE
                    WHEN (f.sw * f.swxx - f.swx * f.swx) <> 0::numeric THEN (f.sw * f.swxy - f.swx * f.swy) / (f.sw * f.swxx - f.swx * f.swx)
                    ELSE NULL::numeric
                END AS k
           FROM fit f
        ), param2 AS (
         SELECT p.a0,
            p.n,
            p.c_chargen,
            p.sw,
            p.swx,
            p.swy,
            p.swxx,
            p.swxy,
            p.k,
                CASE
                    WHEN p.k IS NOT NULL THEN (p.swy - p.k * p.swx) / p.sw
                    ELSE NULL::numeric
                END AS ln_lambda
           FROM param p
        ), smear AS (
         SELECT p.a0,
            sum(k.w * exp(ln(- ln(1::numeric - k.fs)) - (p.ln_lambda + p.k * k.x))) / NULLIF(sum(k.w), 0::numeric) AS s
           FROM param2 p
             JOIN kand k ON k.a0 = p.a0
          WHERE k.fs > 0::numeric AND k.fs < 1::numeric AND p.k IS NOT NULL
          GROUP BY p.a0
        ), guete AS (
         SELECT p.a0,
            p.n,
            p.c_chargen,
            p.k,
            p.ln_lambda,
            s.s AS smearing,
            sum(k.w * power(k.f - (
                CASE
                    WHEN k.mit_sockel THEN p.a0
                    ELSE 0::numeric
                END + (1::numeric -
                CASE
                    WHEN k.mit_sockel THEN p.a0
                    ELSE 0::numeric
                END) * (1::numeric - exp(- exp(LEAST(GREATEST(p.ln_lambda + ln(GREATEST(s.s, 0.01)) + p.k * k.x, '-40'::integer::numeric), 3::numeric))))), 2::numeric)) AS sse
           FROM param2 p
             JOIN smear s ON s.a0 = p.a0
             JOIN kand k ON k.a0 = p.a0
          WHERE p.k IS NOT NULL AND p.k > 0::numeric AND p.n >= 3
          GROUP BY p.a0, p.n, p.c_chargen, p.k, p.ln_lambda, s.s
        ), schwelle AS (
         SELECT 1::numeric + power(t_quantil_95(GREATEST(c.c - 3, 1)), 2::numeric) / GREATEST(c.c - 3, 1)::numeric AS faktor
           FROM chargen c
        ), wahl AS (
         SELECT g.a0,
            g.n,
            g.c_chargen,
            g.k,
            g.ln_lambda,
            g.smearing,
            g.sse
           FROM guete g
          WHERE g.sse <= ((( SELECT min(guete.sse) AS min
                   FROM guete)) * 1.01) AND (( SELECT guete.sse
                   FROM guete
                  WHERE guete.a0 = 0::numeric)) > ((( SELECT min(guete.sse) AS min
                   FROM guete)) * (( SELECT schwelle.faktor
                   FROM schwelle)))
          ORDER BY g.a0
         LIMIT 1
        ), gewaehlt AS (
         SELECT COALESCE(( SELECT wahl.a0
                   FROM wahl), 0::numeric) AS a0,
            COALESCE(( SELECT wahl.sse
                   FROM wahl), ( SELECT guete.sse
                   FROM guete
                  WHERE guete.a0 = 0::numeric)) AS sse,
            COALESCE(( SELECT wahl.n
                   FROM wahl), ( SELECT guete.n
                   FROM guete
                  WHERE guete.a0 = 0::numeric)) AS n_wahl
        ), grenzen AS (
         SELECT COALESCE(min(g.a0), w.a0) AS a0_unten,
            COALESCE(max(g.a0), w.a0) AS a0_oben
           FROM gewaehlt w
             LEFT JOIN guete g ON g.sse <= (w.sse * (( SELECT schwelle.faktor
                   FROM schwelle)))
          GROUP BY w.a0
        ), punkte AS (
         SELECT k.charge_nr,
            k.x,
            ln(- ln(1::numeric - k.fs)) AS y,
            k.w,
            k.t
           FROM kand k,
            gewaehlt g
          WHERE k.a0 = g.a0 AND k.fs > 0::numeric AND k.fs < 1::numeric
        ), summen AS (
         SELECT count(*)::integer AS n,
            count(DISTINCT punkte.charge_nr)::integer AS c_chargen,
            min(punkte.t) AS t_min,
            max(punkte.t) AS t_max,
            sum(punkte.w) AS sw,
            sum(punkte.w * punkte.x) AS swx,
            sum(punkte.w * punkte.y) AS swy,
            sum(punkte.w * punkte.x * punkte.x) AS swxx,
            sum(punkte.w * punkte.x * punkte.y) AS swxy
           FROM punkte
        ), fit2 AS (
         SELECT s.n,
            s.c_chargen,
            s.t_min,
            s.t_max,
            s.sw,
            s.swx,
            s.swy,
            s.swxx,
            s.swxy,
                CASE
                    WHEN (s.sw * s.swxx - s.swx * s.swx) <> 0::numeric THEN (s.sw * s.swxy - s.swx * s.swy) / (s.sw * s.swxx - s.swx * s.swx)
                    ELSE NULL::numeric
                END AS k,
            s.swx / NULLIF(s.sw, 0::numeric) AS x_mittel
           FROM summen s
        ), mit_achse AS (
         SELECT f.n,
            f.c_chargen,
            f.t_min,
            f.t_max,
            f.sw,
            f.swx,
            f.swy,
            f.swxx,
            f.swxy,
            f.k,
            f.x_mittel,
                CASE
                    WHEN f.k IS NOT NULL THEN (f.swy - f.k * f.swx) / f.sw
                    ELSE NULL::numeric
                END AS ln_lambda
           FROM fit2 f
        ), rest AS (
         SELECT m.n,
            m.c_chargen,
            m.t_min,
            m.t_max,
            m.sw,
            m.swx,
            m.swy,
            m.swxx,
            m.swxy,
            m.k,
            m.x_mittel,
            m.ln_lambda,
            ( SELECT sum(p.w * power(p.x - m.x_mittel, 2::numeric)) AS sum
                   FROM punkte p) AS sxx,
            ( SELECT sum(p.w * power(p.y - (m.ln_lambda + m.k * p.x), 2::numeric)) AS sum
                   FROM punkte p) AS sse,
            ( SELECT sum(p.w * exp(p.y - (m.ln_lambda + m.k * p.x))) / NULLIF(sum(p.w), 0::numeric)
                   FROM punkte p) AS smearing
           FROM mit_achse m
        ), gruppen AS (
         SELECT r.n,
            r.c_chargen,
            r.t_min,
            r.t_max,
            r.sw,
            r.swx,
            r.swy,
            r.swxx,
            r.swxy,
            r.k,
            r.x_mittel,
            r.ln_lambda,
            r.sxx,
            r.sse,
            r.smearing,
            g.saa,
            g.skk,
            g.sak
           FROM rest r
             CROSS JOIN LATERAL ( SELECT sum(power(c.ga, 2::numeric)) AS saa,
                    sum(power(c.gk, 2::numeric)) AS skk,
                    sum(c.ga * c.gk) AS sak
                   FROM ( SELECT p.charge_nr,
                            sum(p.w * (p.y - (r.ln_lambda + r.k * p.x))) AS ga,
                            sum(p.w * (p.x - r.x_mittel) * (p.y - (r.ln_lambda + r.k * p.x))) AS gk
                           FROM punkte p
                          GROUP BY p.charge_nr) c) g
        )
 SELECT n,
    c_chargen,
    t_min,
    t_max,
    k,
    ln_lambda,
    exp(ln_lambda) AS lambda,
    x_mittel,
    sxx,
    smearing,
    ln_lambda + ln(GREATEST(smearing, 0.01)) AS ln_lambda_korrigiert,
        CASE
            WHEN n > 2 THEN sse / (n - 2)::numeric * n::numeric / NULLIF(sw, 0::numeric)
            ELSE NULL::numeric
        END AS sigma2,
        CASE
            WHEN c_chargen > 1 THEN saa / power(sw, 2::numeric) * c_chargen::numeric / (c_chargen - 1)::numeric
            ELSE NULL::numeric
        END AS var_achse,
        CASE
            WHEN c_chargen > 1 AND sxx <> 0::numeric THEN skk / power(sxx, 2::numeric) * c_chargen::numeric / (c_chargen - 1)::numeric
            ELSE NULL::numeric
        END AS var_k,
        CASE
            WHEN c_chargen > 1 AND sxx <> 0::numeric THEN sak / (sw * sxx) * c_chargen::numeric / (c_chargen - 1)::numeric
            ELSE NULL::numeric
        END AS kov_achse_k,
    t_quantil_95(c_chargen - 1) AS t_faktor,
    n >= 3 AND c_chargen >= 3 AND k IS NOT NULL AND k > 0::numeric AND t_max > (t_min * 1.5) AS brauchbar,
    ( SELECT
                CASE
                    WHEN count(*) FILTER (WHERE p.mit_sockel = false) >= 5 THEN GREATEST(abs(sum(p.w * p.e) FILTER (WHERE NOT p.mit_sockel) / NULLIF(sum(p.w) FILTER (WHERE NOT p.mit_sockel), 0::numeric) - sum(p.w * p.e) FILTER (WHERE p.mit_sockel) / NULLIF(sum(p.w) FILTER (WHERE p.mit_sockel), 0::numeric))::double precision - (1.96 * stddev_samp(p.e) FILTER (WHERE NOT p.mit_sockel))::double precision / sqrt(count(*) FILTER (WHERE NOT p.mit_sockel)::double precision), 0::double precision)::numeric
                    ELSE NULL::numeric
                END AS "case"
           FROM ( SELECT k.mit_sockel,
                    k.w,
                    ln(- ln(1::numeric - k.fs)) - (gruppen.ln_lambda + gruppen.k * k.x) AS e
                   FROM kand k,
                    gewaehlt g
                  WHERE k.a0 = g.a0 AND k.fs > 0::numeric AND k.fs < 1::numeric) p) AS selektions_versatz,
    ( SELECT gewaehlt.a0
           FROM gewaehlt) AS sockel,
    ( SELECT grenzen.a0_unten
           FROM grenzen) AS sockel_unten,
    ( SELECT grenzen.a0_oben
           FROM grenzen) AS sockel_oben,
    zahl(((( SELECT guete.sse
           FROM guete
          WHERE guete.a0 = 0::numeric)) / NULLIF(( SELECT min(guete.sse) AS min
           FROM guete), 0::numeric)), 3, 1e7)::numeric(10,3) AS sockel_nachweis,
    zahl((( SELECT schwelle.faktor
           FROM schwelle)), 3, 1e7)::numeric(10,3) AS sockel_schwelle,
    power(((( SELECT grenzen.a0_oben
           FROM grenzen)) - (( SELECT grenzen.a0_unten
           FROM grenzen))) / 2.0 / NULLIF(t_quantil_95(c_chargen - 1), 0::numeric), 2::numeric) AS sockel_var
   FROM gruppen;
grant select on v_schimmel_modell_rechnen to authenticated;

-- v_ueberfuellung_kaeufer: 4 Cast(s)
create or replace view v_ueberfuellung_kaeufer with (security_invoker = true) as
 SELECT COALESCE(a.kaeufer, ''::text) AS kaeufer,
    COALESCE(k.name, 'ohne Käufer'::text) AS kaeufer_name,
    x.sorte,
    count(*)::integer AS n_wiegungen,
    sum(x.kisten)::integer AS kisten,
    zahl(avg(x.kg_pro_kiste), 3, 1e7)::numeric(10,3) AS kg_pro_kiste,
    zahl(avg(x.soll_kg_pro_kiste), 2, 1e8)::numeric(10,2) AS soll_kg_pro_kiste,
    zahl(avg(x.ueberfuellung_je_kiste), 3, 1e7)::numeric(10,3) AS ueberfuellung_je_kiste,
    zahl(sum(x.ueberfuellung_kg), 1, 1e11)::numeric(12,1) AS ueberfuellung_kg
   FROM v_ausgang_kennzahl x
     JOIN auftrag a ON a.id = x.auftrag_id
     LEFT JOIN kaeufer k ON k.code = a.kaeufer
  WHERE x.ueberfuellung_je_kiste IS NOT NULL AND a.abgebrochen_ts IS NULL
  GROUP BY (COALESCE(a.kaeufer, ''::text)), (COALESCE(k.name, 'ohne Käufer'::text)), x.sorte;
comment on view v_ueberfuellung_kaeufer is 'Gewogene fertige Paletten je Käufer und Sorte: Kilo je Kiste, Überschuss über das Soll. Nur Arbeiten nach „Kiste ab x kg" — nach Kaliber gibt es kein Soll.';
grant select on v_ueberfuellung_kaeufer to authenticated;

-- v_verarbeitung_alter: 3 Cast(s)
create or replace view v_verarbeitung_alter with (security_invoker = true) as
 WITH gezaehlt AS (
         SELECT ap.auftrag_id,
            count(*)::integer AS n_paletten,
            zahl(avg(a_1.start_ts::date - ap.eingangsdatum), 1, 1e9)::numeric(10,1) AS alter_verarbeitet
           FROM auftrag_palette ap
             JOIN auftrag a_1 ON a_1.id = ap.auftrag_id
          WHERE ap.eingangsdatum IS NOT NULL AND a_1.abgebrochen_ts IS NULL
          GROUP BY ap.auftrag_id
        ), charge_am_tag AS (
         SELECT a_1.id AS auftrag_id,
            zahl(avg(a_1.start_ts::date - p.eingangsdatum), 1, 1e9)::numeric(10,1) AS alter_charge
           FROM auftrag a_1
             JOIN palette p ON p.charge_nr = a_1.charge_nr AND p.eingangsdatum <= a_1.start_ts::date
          WHERE a_1.abgebrochen_ts IS NULL
          GROUP BY a_1.id
        )
 SELECT a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    c.schlag,
    a.station,
    a.weg,
    a.start_ts::date AS tag,
    g.n_paletten,
    g.alter_verarbeitet,
    l.alter_charge,
    zahl((g.alter_verarbeitet - l.alter_charge), 1, 1e9)::numeric(10,1) AS differenz
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gezaehlt g ON g.auftrag_id = a.id
     LEFT JOIN charge_am_tag l ON l.auftrag_id = a.id
  WHERE a.abgebrochen_ts IS NULL AND a.station <> 'waschen'::station;
comment on view v_verarbeitung_alter is 'Je Arbeit mit gezählten, datierten Paletten: mittleres Alter der verarbeiteten Ware gegen das mittlere Alter aller Paletten der Charge an dem Tag. differenz > 0: älter als der Durchschnitt verarbeitet.';
grant select on v_verarbeitung_alter to authenticated;

-- v_verdunstung_messung: 1 Cast(s)
create or replace view v_verdunstung_messung with (security_invoker = true) as
 SELECT w.id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.palette_id,
    w.eingangsdatum,
    w.wiege_ts,
    w.sichtbar_schimmel,
    w.erfasser,
    w.auftrag_id,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    w.wiege_ts::date - w.eingangsdatum AS lagertage,
        zahl(CASE
            WHEN n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (w.wiege_ts::date - w.eingangsdatum) > 0 THEN 1::numeric - power(n.netto_jetzt_kg / n.netto_damals_kg, 1.0 / (w.wiege_ts::date - w.eingangsdatum)::numeric)
            ELSE NULL::numeric
        END, 6, 1e4)::numeric(10,6) AS rate_pro_tag,
    w.gemessen AND NOT w.sichtbar_schimmel AND n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (w.wiege_ts::date - w.eingangsdatum) > 0 AND n.netto_jetzt_kg <= (n.netto_damals_kg * 1.01) AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AS verwendbar
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT w.brutto_damals_kg - COALESCE(w.kisten, 0)::numeric * g.tara_kg_pro_kiste - COALESCE(g.tara_kg_palette, 0::numeric) AS netto_damals_kg,
            w.brutto_jetzt_kg - COALESCE(w.kisten, 0)::numeric * g.tara_kg_pro_kiste - COALESCE(g.tara_kg_palette, 0::numeric) AS netto_jetzt_kg) n;
comment on view v_verdunstung_messung is 'Jede Verdunstungswägung mit Netto damals und jetzt, Lagertagen und Tagesrate. verwendbar: gemessen, ohne sichtbaren Schimmel, positive Nettos, Wiegedatum nach dem Eingang, Arbeit nicht abgebrochen — und die Palette höchstens 1 % schwerer als beim Eingang (0056). Was nicht verwendbar ist, steht in v_plausibilitaet.';
grant select on v_verdunstung_messung to authenticated;

-- v_wiegung_kennzahl: 5 Cast(s)
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
    w.wiege_ts::date - w.eingangsdatum AS lagertage,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    zahl((n.netto_jetzt_kg / NULLIF(w.kisten, 0)::numeric), 3, 1e7)::numeric(10,3) AS kg_pro_kiste,
    zahl((n.netto_jetzt_kg / NULLIF(w.kisten * w.kuerbisse_pro_kiste, 0)::numeric), 3, 1e7)::numeric(10,3) AS kg_pro_kuerbis,
    zahl((n.netto_damals_kg - n.netto_jetzt_kg), 2, 1e8)::numeric(10,2) AS verlust_kg
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT zahl((w.brutto_damals_kg - COALESCE(w.kisten, 0)::numeric * g.tara_kg_pro_kiste - COALESCE(g.tara_kg_palette, 0::numeric)), 2, 1e8)::numeric(10,2) AS netto_damals_kg,
            zahl((w.brutto_jetzt_kg - COALESCE(w.kisten, 0)::numeric * g.tara_kg_pro_kiste - COALESCE(g.tara_kg_palette, 0::numeric)), 2, 1e8)::numeric(10,2) AS netto_jetzt_kg) n
  WHERE w.gemessen AND (a.id IS NULL OR a.abgebrochen_ts IS NULL);
comment on view v_wiegung_kennzahl is 'Je gewogener Palette: Netto damals und jetzt, Gewichtsverlust, kg je Kiste und — falls die Kürbisse je Kiste erfasst wurden — kg je Kürbis.';
grant select on v_wiegung_kennzahl to authenticated;


-- ---------- Stand der Datenbank ------------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 59 $$;
