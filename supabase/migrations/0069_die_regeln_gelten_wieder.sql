-- =====================================================================
-- 0069 — Die fünf Sichten geben die Zeilenregeln wieder weiter
--
-- 0067 hat fünf Sichten neu geschrieben, damit sie den Betriebstag statt
-- `current_date` verwenden. Dabei ist eine Klausel verlorengegangen, die in
-- keiner der Zeilen stand, die ich geändert habe:
--
--     with (security_invoker = true)
--
-- `create or replace view` **löscht** die Einstellungen einer Sicht, wenn die
-- neue Fassung keine mitbringt. Seit 0067 laufen `v_auftrag_masse`,
-- `v_auftrag_wasch_paletten`, `v_verarbeitung_alter`, `v_verdunstung_messung`
-- und `v_wiegung_kennzahl` deshalb mit den Rechten ihres Eigentümers, und die
-- Zeilenregeln der Tabellen darunter gelten beim Lesen durch sie nicht mehr.
-- Die übrigen achtundfünfzig Sichten setzen die Klausel — seit 0005, wo neben
-- ihr der Satz steht: „die RLS der Tabellen gilt weiter".
--
-- WAS ES HEUTE KOSTET
--
-- Nichts. Jede Leseregel dieses Programms lautet `true` — es darf ohnehin
-- jeder Angemeldete jede Zeile lesen —, und `anon` hat auf keine dieser
-- Sichten ein Leserecht. Der Befund beschreibt eine abgeschaltete Sicherung
-- an einer Tür, die heute offen steht.
--
-- WAS ES KOSTEN WÜRDE
--
-- Nachgestellt auf einer Kopie der Demodatenbank: Wird die Leseregel von
-- `auftrag` auf den Betriebsleiter verengt — genau der Schritt, den der
-- Betrieb tun würde, wenn er sagt „ein Arbeiter soll nur seine eigenen
-- Aufträge sehen" —, dann sieht ein angemeldeter Arbeiter in `auftrag`
-- **0 Zeilen** und durch `v_auftrag_masse` weiterhin **308**. Ohne
-- Fehlermeldung, ohne Hinweis, und ohne dass eine Prüfung anschlägt.
--
-- WARUM ES KEINE PRÜFUNG GEMERKT HAT
--
-- Der Abgleich in `supabase/test/run.sh` vergleicht die Datenbank aus den
-- Migrationen mit der aus setup.sql. Beide Wege haben denselben Fehler, also
-- sind beide deckungsgleich — 2 636 Objekte, kein Unterschied. Ein Vergleich
-- zweier Wege findet nur, was die Wege trennt, nie das, was sie teilen.
-- Deshalb steht in `supabase/test/pruefung.sql` ab jetzt eine Zusicherung,
-- die keinen Vergleich braucht: **jede** Sicht in `public` hat
-- `security_invoker = true`. Sie hätte 0067 sofort angehalten.
--
-- WIE ES REPARIERT WIRD
--
-- Mit denselben fünf Definitionen aus 0067, Zeichen für Zeichen, nur mit der
-- Klausel davor. Nicht mit `alter view … set (…)`: Der Verdichter versteht
-- eine solche Anweisung nicht als Bauanweisung, liesse sie in Teil A stehen
-- und bräche dann ab, weil Teil A auf etwas zeigt, das nach Teil B gewandert
-- ist. Die ganze Definition noch einmal hinzuschreiben ist länger und richtig.
--
-- Die Reihenfolge ist dieselbe wie in 0067 (`v_auftrag_wasch_paletten` vor
-- `v_auftrag_masse`, das darauf liest), und wieder ohne
-- `-- verdichter: baut …`: Das sind gewöhnliche Sichten, der Verdichter
-- erkennt und sortiert sie selbst.
-- =====================================================================

create or replace view v_auftrag_wasch_paletten with (security_invoker = true) as
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
    count(*)::integer AS n_paletten,
    sum(ap.kisten)::integer AS kisten,
    zahl(sum(ap.kisten)::numeric * max(k.kg_je_gebinde), 2, '10000000000'::numeric)::numeric(12,2) AS kg,
    max(k.n) AS n_messungen,
    zahl(sum((ap.kisten * (betriebstag(a.start_ts) - ap.sortierdatum))::numeric) FILTER (WHERE ap.sortierdatum IS NOT NULL) / NULLIF(sum(ap.kisten) FILTER (WHERE ap.sortierdatum IS NOT NULL), 0)::numeric, 1, '100000'::numeric)::numeric(8,1) AS zwischenlager_tage,
    count(*) FILTER (WHERE ap.sortierdatum IS NOT NULL)::integer AS n_mit_sortierdatum
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     JOIN auftrag_palette ap ON ap.auftrag_id = a.id AND ap.kisten IS NOT NULL
     LEFT JOIN LATERAL ( SELECT b.kaliber_idx
           FROM band b
          WHERE a.kaliber_idx IS NULL AND b.sorte = c.sorte AND b.von = a.kaliber_von_g AND b.bis = a.kaliber_bis_g
          ORDER BY b.kaliber_idx
         LIMIT 1) e ON true
     LEFT JOIN v_koeff_gebinde k ON k.sorte = c.sorte AND k.kaliber_idx = COALESCE(a.kaliber_idx, e.kaliber_idx)
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL
  GROUP BY a.id;
grant select on v_auftrag_wasch_paletten to authenticated;
comment on view v_auftrag_wasch_paletten is
  'Beim Waschen gezählte Paletten: Kisten gesamt, Masse = Kisten × gemessenes Kistengewicht des Kalibers, Tage im Zwischenlager aus dem Sortierdatum (0061).';

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
    COALESCE(m.eingang_netto_kg, wp.kg, gb.kg, fp.kg) AS eingang_netto_kg,
        CASE
            WHEN m.masse_quelle <> 'fehlt'::text THEN m.masse_quelle
            WHEN wp.kg IS NOT NULL THEN 'wasch_paletten'::text
            WHEN gb.kg IS NOT NULL THEN 'gebinde'::text
            WHEN fp.kg IS NOT NULL THEN 'fax_paletten'::text
            ELSE 'fehlt'::text
        END AS masse_quelle,
    zahl(COALESCE(m.lagertage,
        CASE
            WHEN m.station = 'waschen'::station THEN (betriebstag(m.start_ts) - '2000-01-01'::date)::numeric - COALESCE(se.tage_seit_epoche, (r.eingangsdatum_mittel - '2000-01-01'::date)::numeric)
            ELSE NULL::numeric
        END), 1, '1000000000'::numeric)::numeric(10,1) AS lagertage,
    a.ist_fax,
    wp.zwischenlager_tage
   FROM mv_auftrag_masse m
     JOIN auftrag a ON a.id = m.auftrag_id
     LEFT JOIN mv_sortier_eingang se ON se.charge_nr = m.charge_nr
     LEFT JOIN v_charge_rueckgrat r ON r.charge_nr = m.charge_nr
     LEFT JOIN v_auftrag_wasch_paletten wp ON wp.auftrag_id = m.auftrag_id
     LEFT JOIN ( SELECT v_auftrag_gebinde_masse.auftrag_id,
            sum(v_auftrag_gebinde_masse.kg) AS kg
           FROM v_auftrag_gebinde_masse
          GROUP BY v_auftrag_gebinde_masse.auftrag_id) gb ON gb.auftrag_id = m.auftrag_id
     LEFT JOIN LATERAL ( SELECT zahl(a.paletten_gesamt::numeric * p.netto_kg, 2, '10000000000'::numeric)::numeric(12,2) AS kg
           FROM v_koeff_palette_netto p
          WHERE a.ist_fax AND a.paletten_gesamt > 0 AND p.sorte = m.sorte AND (p.kistensystem = a.kistensystem OR p.kistensystem IS NULL AND a.kistensystem IS DISTINCT FROM 'anderes'::text)
          ORDER BY (p.kistensystem = a.kistensystem) DESC NULLS LAST
         LIMIT 1) fp ON true;
grant select on v_auftrag_masse to authenticated;
comment on view v_auftrag_masse is
  'Masse je Arbeit: gewogene Paletten oder Zettel, beim Waschen gezählte Paletten (Kisten × Kistengewicht, 0061), sonst gezählte Kisten, beim Fax die Palettenzahl mal gemessener Palettenmasse. ist_fax: kein Waschgang.';

create or replace view v_verarbeitung_alter with (security_invoker = true) as
WITH gezaehlt AS (
         SELECT ap.auftrag_id,
            count(*)::integer AS n_paletten,
            zahl(avg(betriebstag(a_1.start_ts) - ap.eingangsdatum), 1, '1000000000'::numeric)::numeric(10,1) AS alter_verarbeitet
           FROM auftrag_palette ap
             JOIN auftrag a_1 ON a_1.id = ap.auftrag_id
          WHERE ap.eingangsdatum IS NOT NULL AND a_1.abgebrochen_ts IS NULL
          GROUP BY ap.auftrag_id
        ), charge_am_tag AS (
         SELECT a_1.id AS auftrag_id,
            zahl(avg(betriebstag(a_1.start_ts) - p.eingangsdatum), 1, '1000000000'::numeric)::numeric(10,1) AS alter_charge
           FROM auftrag a_1
             JOIN palette p ON p.charge_nr = a_1.charge_nr AND p.eingangsdatum <= betriebstag(a_1.start_ts)
          WHERE a_1.abgebrochen_ts IS NULL
          GROUP BY a_1.id
        )
 SELECT a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    c.schlag,
    a.station,
    a.weg,
    betriebstag(a.start_ts) AS tag,
    g.n_paletten,
    g.alter_verarbeitet,
    l.alter_charge,
    zahl(g.alter_verarbeitet - l.alter_charge, 1, '1000000000'::numeric)::numeric(10,1) AS differenz
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gezaehlt g ON g.auftrag_id = a.id
     LEFT JOIN charge_am_tag l ON l.auftrag_id = a.id
  WHERE a.abgebrochen_ts IS NULL AND a.station <> 'waschen'::station;
grant select on v_verarbeitung_alter to authenticated;
comment on view v_verarbeitung_alter is
  'Je Arbeit mit gezählten, datierten Paletten: mittleres Alter der verarbeiteten Ware gegen das mittlere Alter aller Paletten der Charge an dem Tag. differenz > 0: älter als der Durchschnitt verarbeitet.';

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
    betriebstag(w.wiege_ts) - w.eingangsdatum AS lagertage,
    zahl(
        CASE
            WHEN n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (betriebstag(w.wiege_ts) - w.eingangsdatum) > 0 THEN 1::numeric - power(n.netto_jetzt_kg / n.netto_damals_kg, 1.0 / (betriebstag(w.wiege_ts) - w.eingangsdatum)::numeric)
            ELSE NULL::numeric
        END, 6, '10000'::numeric)::numeric(10,6) AS rate_pro_tag,
    w.gemessen AND NOT w.sichtbar_schimmel AND n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (betriebstag(w.wiege_ts) - w.eingangsdatum) > 0 AND n.netto_jetzt_kg <= (n.netto_damals_kg * 1.01) AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AS verwendbar
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_damals_kg,
            w.brutto_jetzt_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_jetzt_kg) n;
grant select on v_verdunstung_messung to authenticated;
comment on view v_verdunstung_messung is
  'Jede Verdunstungswägung mit Netto damals und jetzt, Lagertagen und Tagesrate. verwendbar: gemessen, ohne sichtbaren Schimmel, positive Nettos, Wiegedatum nach dem Eingang, Arbeit nicht abgebrochen — und die Palette höchstens 1 % schwerer als beim Eingang (0056). Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto und damit keine Rate (0064). Was nicht verwendbar ist, steht in v_plausibilitaet.';

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
    zahl(n.netto_damals_kg - n.netto_jetzt_kg, 2, '100000000'::numeric)::numeric(10,2) AS verdunstung_kg
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT zahl(w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, '100000000'::numeric)::numeric(10,2) AS netto_damals_kg,
            zahl(w.brutto_jetzt_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, '100000000'::numeric)::numeric(10,2) AS netto_jetzt_kg) n
  WHERE w.gemessen AND (a.id IS NULL OR a.abgebrochen_ts IS NULL);
grant select on v_wiegung_kennzahl to authenticated;
comment on view v_wiegung_kennzahl is
  'Je gewogener Palette: Netto damals und jetzt, die Verdunstung dazwischen (0062 — vorher verlust_kg), kg je Kiste und je Kürbis. Ohne Kistenzahl oder hinterlegte Tara gibt es kein Netto (0064).';

-- ---------- Stand der Datenbank -----------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 69 $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;
