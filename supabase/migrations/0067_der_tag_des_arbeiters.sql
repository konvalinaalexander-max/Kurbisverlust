-- =====================================================================
-- 0067 — Der Tag des Arbeiters
--
-- Das Programm rechnet mit Lagertagen. Ein Lagertag entsteht als
-- Differenz zweier Dinge, die verschiedener Natur sind:
--
--   `eingangsdatum`  ein **Kalendertag**, vom Palettenzettel abgetippt.
--                    Er meint den Tag, an dem der Arbeiter in der Halle
--                    stand — Ortszeit, ohne dass es irgendwo dastünde.
--
--   `wiege_ts`       ein **Zeitpunkt**, von der Datenbank gesetzt
--                    (`now()`). Ein absoluter Augenblick, ohne Ort.
--
-- Aus dem Zeitpunkt wurde mit `::date` wieder ein Kalendertag — **in der
-- Zeitzone der Sitzung**. Die Datenbank läuft auf UTC, der Betrieb liegt
-- in der Schweiz (UTC+1, im Sommer UTC+2). Jeder Zeitpunkt zwischen
-- 22:00 UTC und Mitternacht — also 00:00 bis 02:00 Ortszeit — gehört
-- damit in UTC noch zum Vortag und in Zürich schon zum neuen Tag:
--
--     set time zone 'UTC';            select '2026-07-15 22:30+00'::timestamptz::date  → 2026-07-15
--     set time zone 'Europe/Zurich';  select '2026-07-15 22:30+00'::timestamptz::date  → 2026-07-16
--
-- Dieselbe Zeile, zwei Antworten. Welche das Programm gab, hing an einer
-- Einstellung, die niemand ausgewählt hat und die der Betreiber der
-- Datenbank jederzeit ändern kann.
--
-- WAS ES KOSTET, GEMESSEN
--
-- Dieselbe Auswertung in beiden Zeitzonen gerechnet (werkstatt/b_fundament/
-- b5_zeit.mjs, Demosaison):
--
--     Saisonverlust      52 119.38 kg   →   52 099.70 kg
--     Verdunstung        23 530.19 kg   →   23 525.18 kg
--     Schimmel           26 170.29 kg   →   26 155.61 kg
--     noch im Haus      154 545.37 kg   →  154 563.81 kg
--     Summe Lagertage         3 542     →        3 543
--
-- Wie nah das an der Wirklichkeit liegt, hat sich beim Bauen dieser
-- Migration von selbst gezeigt: Um 22:03 UTC sagte dieselbe Datenbank
--
--     current_date        → 2026-09-09
--     betriebstag(now())  → 2026-09-10
--
-- Der Betrieb war bereits im nächsten Tag, die Datenbank noch im vorigen —
-- und zwei Zwischenstände, die eine Stunde auseinander gerechnet wurden,
-- unterschieden sich um einen ganzen Lagertag je Charge. Das ist keine
-- Randerscheinung um Mitternacht: In der Sommerzeit dauert dieses Fenster
-- zwei Stunden, jede Nacht.
--
-- Ein einziger verschobener Lagertag, 19.68 kg. Klein — aber die
-- Verdunstungsrate einer Wägung ist `1 − (netto_jetzt/netto_damals)^(1/t)`,
-- und ein Tag mehr oder weniger in `t` verschiebt sie um rund `1/t` ihres
-- Werts. Bei der kürzesten Lagerung der Demosaison (acht Tage) sind das
-- 14.4 %. Der Median über alle 41 verwendbaren Wägungen liegt bei 1.2 %.
--
-- WIE ES REPARIERT WIRD
--
-- Nicht mit `alter database … set timezone`. Das verlegt die Entscheidung
-- nur an eine andere Stelle, an der sie ebenso still umkippen kann, und
-- auf Supabase steht sie ohnehin nicht in der Hand dieses Projekts.
-- Stattdessen sagt jede Stelle, die einen Zeitpunkt zu einem Kalendertag
-- macht, ausdrücklich **welchen** Kalendertag sie meint:
--
--     betriebstag(wiege_ts)   statt   wiege_ts::date
--
-- Die Zone selbst steht als Einstellung `zeitzone` in der Datenbank, mit
-- 'Europe/Zurich' als Rückfall. Ein Betrieb, der umzieht, ändert eine
-- Zeile; niemand muss dafür SQL anfassen.
--
-- WAS DIESE MIGRATION NICHT ANFASST — UND WARUM, MIT ZAHL
--
-- `mv_auftrag_masse` enthält dieselbe Verwechslung (`a.start_ts::date`),
-- ist aber eine gespeicherte Sicht: Sie lässt sich nicht ersetzen, nur
-- neu bauen, und `drop materialized view … cascade` nimmt **51 weitere
-- Objekte** mit — praktisch das ganze Rechenwerk.
--
-- Nachgemessen, bevor das als „später" abgetan wird: Von 309 Arbeiten
-- haben 5 einen Startzeitpunkt, dessen UTC-Tag und dessen Schweizer Tag
-- auseinanderfallen. Die gespeicherte Sicht in der Betriebszone neu
-- gefüllt und die ganze Auswertung nachgerechnet ergibt auf der
-- Demosaison **dieselben vier Zahlen bis auf den Rappen** — der Umbau
-- von 51 Objekten bewegt heute nichts. Deshalb bleibt er liegen; er ist
-- in docs/WERKSTATTBERICHT.md als offener Punkt vermerkt, nicht
-- vergessen.
--
-- AUSSERDEM IN DIESER MIGRATION
--
--   Vier Prüfbedingungen standen seit ihrer Einführung mit `NOT VALID`
--   im Schema. Postgres wendet sie auf neue Zeilen an, hat aber nie
--   nachgesehen, ob die vorhandenen sie erfüllen — und darf sie deshalb
--   beim Planen nicht voraussetzen. Nachgerechnet (werkstatt/b_fundament/
--   b4_integritaet.mjs): null Verstösse bei allen vieren. Aus dem
--   Versprechen wird damit eine Zusage.
--
--   Fünf Indexe beantworten nur Fragen, die ein anderer Index auch
--   beantwortet: Ihre Schlüsselspalten sind das Präfix eines anderen,
--   und wo sie eine Teilbedingung tragen, deckt der andere sie ohne
--   Bedingung ab. Zusammen 120 kB, die bei jedem Schreibvorgang
--   mitgepflegt werden, ohne je eine Abfrage zu beantworten.
-- =====================================================================

-- ---------- 1. Die Zone des Betriebs ------------------------------------

create or replace function betriebszone() returns text
language sql stable set search_path = public
as $$
  select coalesce(nullif((select wert #>> '{}' from public.einstellung
                           where schluessel = 'zeitzone'), ''), 'Europe/Zurich')
$$;
comment on function betriebszone() is
  'Die Zeitzone, in der der Betrieb steht. Einstellung „zeitzone", Rückfall Europe/Zurich.';
-- Postgres gibt neuen Funktionen das Ausführungsrecht an `public`, also auch an
-- Nichtangemeldete. Die Prüfung in supabase/test/pruefung.sql hält diese Tür
-- zu — sie hat genau diese beiden Zeilen eingefordert, bevor die Migration
-- durchging.
revoke execute on function betriebszone() from public;
grant  execute on function betriebszone() to authenticated;

create or replace function betriebstag(p_ts timestamptz) returns date
language sql stable set search_path = public
as $$
  select (p_ts at time zone public.betriebszone())::date
$$;
comment on function betriebstag(timestamptz) is
  'Der Kalendertag eines Zeitpunkts in der Zone des Betriebs — nicht der in UTC. '
  'Überall dort zu benutzen, wo aus einem Zeitstempel ein Tag wird, der mit einem '
  'abgetippten Datum verrechnet wird.';
revoke execute on function betriebstag(timestamptz) from public;
grant  execute on function betriebstag(timestamptz) to authenticated;

-- `heute()` liest weiterhin zuerst die Einstellung „heute_test", damit die
-- Prüfstände eine Saison an einem festen Tag betrachten können. Neu ist nur,
-- dass der Rückfall der Tag des Betriebs ist und nicht der von UTC.
create or replace function heute() returns date
language sql stable set search_path = public
as $$
  select coalesce((select nullif(wert #>> '{}', '')::date from public.einstellung
                    where schluessel = 'heute_test'),
                  public.betriebstag(now()))
$$;

insert into einstellung (schluessel, wert)
values ('zeitzone', to_jsonb('Europe/Zurich'::text))
on conflict (schluessel) do nothing;

-- ---------- 2. Jede Sicht, die einen Zeitpunkt zu einem Tag macht -------
--
-- Fünf Sichten machten aus einem Zeitstempel einen Kalendertag. Sie stehen
-- hier vollständig, mit `betriebstag(...)` an der Stelle, an der vorher
-- `...::date` stand — sonst nichts geändert.
--
-- Ausgeschrieben und nicht umgeformt: setup.sql entsteht aus diesen Dateien,
-- indem von jeder Sicht die **zuletzt geschriebene Fassung** übernommen wird
-- (supabase/verdichten.mjs). Eine Migration, die Sichten zur Laufzeit umformt,
-- taucht dort gar nicht auf — setup.sql behielte die alte Fassung, und die
-- Datenbank eines neuen Betriebs hätte den Fehler weiter, während die eines
-- alten ihn nicht mehr hätte. Der Abgleich in supabase/test/run.sh würde es
-- melden; besser ist, es gar nicht erst so zu bauen.

-- verdichter: baut v_auftrag_masse v_auftrag_wasch_paletten v_verarbeitung_alter v_verdunstung_messung v_wiegung_kennzahl

create or replace view v_auftrag_masse as
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

create or replace view v_auftrag_wasch_paletten as
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

create or replace view v_verarbeitung_alter as
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

create or replace view v_verdunstung_messung as
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

create or replace view v_wiegung_kennzahl as
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

-- Gegenprobe: Bleibt eine Sicht stehen, bricht die Migration ab. Eine
-- Reparatur, die die Hälfte erwischt, ist schlimmer als keine — sie sieht
-- erledigt aus. `mv_auftrag_masse` ist ausgenommen; warum, steht oben.
do $$
declare offen text;
begin
  select string_agg(c.relname, ', ') into offen
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and pg_get_viewdef(c.oid, true) ~ '[a-z_][a-z0-9_]*(_ts|_zeit)\s*::\s*date';
  if offen is not null then
    raise exception 'Diese Sichten mischen weiterhin UTC-Tag und Betriebstag: %', offen;
  end if;
end $$;

-- ---------- 3. Vier Zusagen einlösen ------------------------------------

alter table auftrag         validate constraint auftrag_fax_nur_waschen;
alter table auftrag         validate constraint auftrag_kaliber_nur_waschen;
alter table auftrag_palette validate constraint auftrag_palette_datum_pflicht;
alter table lieferung       validate constraint lieferung_hat_menge;

-- ---------- 4. Indexe, die ein anderer schon abdeckt --------------------
--
-- Je Zeile: der überflüssige Index, und der, der ihn deckt.
--   auftrag_palette_auftrag_id_idx      (auftrag_id)
--     ⊂ auftrag_palette_sortierdatum    (auftrag_id, sortierdatum)
--   ausschuss_auftrag                   (auftrag_id, art) wo gemessen
--     ⊂ ausschuss_messung_auftrag_id_art_idx (auftrag_id, art)
--   schimmel_auftrag                    (auftrag_id) wo gemessen
--     ⊂ schimmel_messung_auftrag_id_idx (auftrag_id)
--   palette_charge_nr_eingangsdatum_idx (charge_nr, eingangsdatum)
--     ⊂ palette_charge_netto            (charge_nr, eingangsdatum, gebindeart)
--   auftrag_aktiv                       (charge_nr) wo abgebrochen_ts is null
--     ⊂ auftrag_charge_nr_start_ts_idx  (charge_nr, start_ts)
--
-- Ein Index mit Teilbedingung ist kleiner und liegt eher im Arbeitsspeicher;
-- bei sehr vielen Zeilen kann er neben dem allgemeinen sinnvoll sein. Bei
-- den Zeilenzahlen dieses Betriebs — die grösste Messtabelle hat unter 6000
-- Zeilen — trägt das Argument nicht, und ein Arbeitstag über die Demosaison
-- hat keinen dieser fünf auch nur einmal angefasst.

drop index if exists auftrag_palette_auftrag_id_idx;
drop index if exists ausschuss_auftrag;
drop index if exists schimmel_auftrag;
drop index if exists palette_charge_nr_eingangsdatum_idx;
drop index if exists auftrag_aktiv;

-- ---------- 5. Stand der Datenbank --------------------------------------
create or replace function schema_stand() returns int
language sql immutable parallel safe set search_path = public
as $$ select 67 $$;

do $$
begin
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
exception when others then null;
end $$;
