-- 0109 — Die Rechnung plant klein
--
-- WARUM
--
-- Die Betriebsdatenbank lief in der Nacht auf den 30. September stundenlang
-- im IO-Wait und war für Supabase „unhealthy". Die volle Rechnung dauerte dort
-- 250 bis 370 Sekunden — mit 25 Arbeiten und 1650 Paletten, weniger Daten als
-- die Demo. Lokal braucht dieselbe Rechnung auf denselben Daten 4 Sekunden.
--
-- Die Zeit geht nicht ins Rechnen, sondern ins Planen: Einzeln gemessen
-- plant jede grosse Auswertung drei- bis viermal so lange, wie sie rechnet
-- (mv_kaskade: 1,0 s Planen, 0,3 s Rechnen). Und das Planen braucht Speicher:
-- mv_kaskade 1 GB, mv_koeff_rand 590 MB, erg_massenbilanz 520 MB, jede
-- weitere grosse Auswertung 80 bis 300 MB (Spitze des Arbeitsspeichers eines
-- Postgres-Prozesses, der nur plant). Eine kleine Supabase-Maschine hat 0,5
-- bis 1 GB für alles zusammen. Reicht er nicht, lagert sie auf die Platte
-- aus — das passt zu dem IO-Wait, das der Betrieb gesehen hat.
--
-- Der Grund ist die Schichtung. Postgres setzt jede Sicht dort ein, wo sie
-- gelesen wird, und die Sichten lesen einander: v_auftrag_masse steckt in
-- neun Sichten, die wieder in anderen stecken. Im Plan von mv_kaskade stand
-- sie so dutzendfach, samt allem, was unter ihr liegt — 6915 Planknoten.
--
-- WAS 0109 TUT
--
-- Vier Knoten-Sichten, auf denen fast alles steht, bekommen eine
-- Planungsgrenze: Ihre Formel wandert unverändert in <sicht>_formel, eine
-- kleine Funktion <sicht>_zaun() liest sie, und die Sicht selbst liest die
-- Funktion. Eine Funktion in PL/pgSQL setzt der Planer nie in die Abfrage
-- darüber ein; er plant sie einmal für sich, und der Plan bleibt in der
-- Sitzung liegen. Name, Spalten, Zeilen und Rechte der Sicht bleiben, wie
-- sie sind; wer sie liest, merkt nichts. Gespeichert wird nichts: Die Sicht
-- rechnet weiterhin bei jedem Lesen aus den heutigen Rohdaten.
--
-- Die Funktionen laufen ohne JIT, wie die Rechnung selbst: Die Übersetzung
-- kostete beim ersten Aufruf in einer frischen Sitzung drei Sekunden, für
-- eine Sicht mit 42 Zeilen — für die Masken, die v_koeff_gebinde und v_auftrag_masse live
-- lesen, wäre das ein Hänger gewesen.
--
-- Gemessen, lokal, alle 41 gespeicherten Ergebnisse Zeile für Zeile gleich
-- (Fingerabdruck je Sicht):
--
--                     Rechnung          Planungsspeicher je Auswertung
--   Betriebsdaten     4,3 s → 1,6 s     bis 1 GB → höchstens 67 MB
--   Demo (Saison)     6,9 s → 6,3 s     bis 1 GB → höchstens 104 MB
--   Planknoten        mv_kaskade 6915 → 351, die grösste 516
--
-- Warum nur vier: Eine Grenze kostet, dass die Sicht bei jedem Lesen ganz
-- gerechnet wird — der Planer kann nichts mehr weglassen, was die Abfrage
-- darüber nicht braucht. v_kaskade_basis wird in einer Auswertung bis zu
-- fünfmal gelesen; mit Grenze war die Demo 10 % langsamer, ohne sie
-- schneller als vorher, und ihr Plan ist klein, seit v_auftrag_masse unter
-- ihr eine Grenze hat.
--
-- Die Formeln sind so abgedruckt, wie PostgreSQL sie nach 0108 hält
-- (pg_get_viewdef) — nicht neu geschrieben. Ihre Herleitung steht in den
-- Migrationen, die sie gebaut haben: v_koeff_gebinde 0092/0104,
-- v_auftrag_masse 0079/0104, v_schimmel_punkte 0079/0105,
-- v_koeff_kaliber_geschaetzt 0018.
--
-- Wer eine dieser Formeln ändert, ändert <sicht>_formel (create or replace
-- view) und lässt <sicht> stehen. Der Prüfblock 0109 schlägt an, wenn eine
-- der vier Sichten ihre Formel wieder selbst trägt oder eine Auswertung mehr
-- als 1000 Planknoten braucht.

-- ---------- v_koeff_gebinde ----------
-- Kistengewicht je Sorte und Band. Die Arbeitsmaske liest es live (Kisten
-- ohne Waage), die Masse der Waschgänge und die Plausibilität rechnen damit.
create or replace view v_koeff_gebinde_formel with (security_invoker = true) as
 WITH gezaehlt AS (
         SELECT auftrag_gebinde.auftrag_id,
            auftrag_gebinde.kaliber_idx,
            sum(auftrag_gebinde.anzahl)::integer AS anzahl
           FROM auftrag_gebinde
          GROUP BY auftrag_gebinde.auftrag_id, auftrag_gebinde.kaliber_idx
        ), je_arbeit AS (
         SELECT a.id AS auftrag_id,
            c.sorte,
            g.kaliber_idx,
            g.anzahl,
            sum(sg.anzahl::bigint * sg.gewicht_g) / 1000.0 AS kg
           FROM gezaehlt g
             JOIN auftrag a ON a.id = g.auftrag_id AND a.abgebrochen_ts IS NULL
             JOIN charge c ON c.nr = a.charge_nr
             JOIN sortier_lauf l ON l.auftrag_id = a.id
             JOIN sortier_gewicht sg ON sg.lauf_id = l.id AND sg.klasse = 'kaliber'::kuerbis_klasse AND sg.kaliber_idx = g.kaliber_idx
          WHERE (a.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND g.anzahl > 0
          GROUP BY a.id, c.sorte, g.kaliber_idx, g.anzahl
        ), band AS (
         SELECT DISTINCT s_1.sorte,
            i.idx AS kaliber_idx,
            ((s_1.kaliber_baender -> i.idx) ->> 0)::integer AS von,
            ((s_1.kaliber_baender -> i.idx) ->> 1)::integer AS bis
           FROM sortierschema s_1
             CROSS JOIN LATERAL generate_series(0, jsonb_array_length(s_1.kaliber_baender) - 1) i(idx)
          WHERE s_1.art = 'kaliber'::text AND s_1.kaliber_baender IS NOT NULL
        ), je_wasch AS (
         SELECT a.id AS auftrag_id,
            c.sorte,
            COALESCE(a.kaliber_idx, e.kaliber_idx) AS kaliber_idx,
            sum(ap.kisten)::integer AS anzahl,
            a.fertige_paletten_gesamt::numeric * eig.netto_kg AS kg
           FROM auftrag a
             JOIN charge c ON c.nr = a.charge_nr
             JOIN auftrag_palette ap ON ap.auftrag_id = a.id AND ap.kisten IS NOT NULL
             JOIN ( SELECT v.auftrag_id,
                    avg(v.netto_kg) AS netto_kg
                   FROM v_ausgang_voll v
                  WHERE COALESCE(v.voll, true) AND v.netto_kg > 0::numeric
                  GROUP BY v.auftrag_id) eig ON eig.auftrag_id = a.id
             LEFT JOIN LATERAL ( SELECT b.kaliber_idx
                   FROM band b
                  WHERE a.kaliber_idx IS NULL AND b.sorte = c.sorte AND b.von = a.kaliber_von_g AND b.bis = a.kaliber_bis_g
                  ORDER BY b.kaliber_idx
                 LIMIT 1) e ON true
          WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL AND COALESCE(a.fertige_paletten_gesamt, 0) > 0
          GROUP BY a.id, c.sorte, (COALESCE(a.kaliber_idx, e.kaliber_idx)), a.fertige_paletten_gesamt, eig.netto_kg
         HAVING sum(ap.kisten) > 0 AND COALESCE(a.kaliber_idx, e.kaliber_idx) IS NOT NULL
        ), je_wasch_gewogen AS (
         SELECT a.id AS auftrag_id,
            c.sorte,
            COALESCE(a.kaliber_idx, e.kaliber_idx) AS kaliber_idx,
            wg.kisten_gewogen AS anzahl,
            wg.kg_je_kiste * wg.kisten_gewogen::numeric AS kg
           FROM v_auftrag_wasch_gewogen wg
             JOIN auftrag a ON a.id = wg.auftrag_id AND a.abgebrochen_ts IS NULL
             JOIN charge c ON c.nr = a.charge_nr
             LEFT JOIN LATERAL ( SELECT b.kaliber_idx
                   FROM band b
                  WHERE a.kaliber_idx IS NULL AND b.sorte = c.sorte AND b.von = a.kaliber_von_g AND b.bis = a.kaliber_bis_g
                  ORDER BY b.kaliber_idx
                 LIMIT 1) e ON true
          WHERE wg.kisten_gewogen > 0 AND COALESCE(a.kaliber_idx, e.kaliber_idx) IS NOT NULL
        ), s AS (
         SELECT q.sorte,
            q.kaliber_idx,
            count(*)::integer AS n,
            sum(q.kg) / NULLIF(sum(q.anzahl), 0)::numeric AS kg_je_gebinde,
            stddev_samp(q.kg / q.anzahl::numeric) AS sd
           FROM ( SELECT je_arbeit.sorte,
                    je_arbeit.kaliber_idx,
                    je_arbeit.anzahl,
                    je_arbeit.kg
                   FROM je_arbeit
                UNION ALL
                 SELECT je_wasch.sorte,
                    je_wasch.kaliber_idx,
                    je_wasch.anzahl,
                    je_wasch.kg
                   FROM je_wasch
                UNION ALL
                 SELECT je_wasch_gewogen.sorte,
                    je_wasch_gewogen.kaliber_idx,
                    je_wasch_gewogen.anzahl,
                    je_wasch_gewogen.kg
                   FROM je_wasch_gewogen) q
          GROUP BY q.sorte, q.kaliber_idx
        UNION ALL
         SELECT k.sorte,
            '-1'::integer,
            count(*)::integer AS count,
            sum(k.netto_kg) / NULLIF(sum(k.kisten), 0)::numeric,
            stddev_samp(k.kg_pro_kiste) AS stddev_samp
           FROM v_ausgang_kennzahl k
          WHERE k.soll_kg_pro_kiste IS NOT NULL OR k.kistensystem = 'kiste_ab'::text
          GROUP BY k.sorte
        )
 SELECT sorte,
    kaliber_idx,
    n,
    zahl(kg_je_gebinde, 3, 10000000::numeric)::numeric(10,3) AS kg_je_gebinde,
    zahl(sd, 3, 10000000::numeric)::numeric(10,3) AS sd,
    zahl(
        CASE
            WHEN sd IS NULL OR n < 2 THEN kg_je_gebinde::double precision
            ELSE GREATEST(kg_je_gebinde::double precision - (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision), 0::double precision)
        END, 3, 10000000::numeric)::numeric(10,3) AS unten,
    zahl(
        CASE
            WHEN sd IS NULL OR n < 2 THEN kg_je_gebinde::double precision
            ELSE kg_je_gebinde::double precision + (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision)
        END, 3, 10000000::numeric)::numeric(10,3) AS oben
   FROM s
  WHERE kg_je_gebinde IS NOT NULL;
comment on view v_koeff_gebinde_formel is
  'Das Kistengewicht je Sorte und Kaliberband: aus Wasch-Arbeiten, die hinein gezählt und heraus gewogen haben (0092), und aus Sortierläufen mit gezählten Kisten (0060). kaliber_idx −1: Sollgewicht-Kisten aus gewogenen fertigen Paletten. — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_koeff_gebinde_formel to authenticated;

create or replace function v_koeff_gebinde_zaun() returns setof v_koeff_gebinde_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_koeff_gebinde_formel;
end $$;
comment on function v_koeff_gebinde_zaun() is
  'Planungsgrenze (0109): liest v_koeff_gebinde_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_koeff_gebinde_zaun() from public;
grant execute on function v_koeff_gebinde_zaun() to authenticated;

create or replace view v_koeff_gebinde with (security_invoker = true) as
select * from v_koeff_gebinde_zaun();
comment on view v_koeff_gebinde is
  'Das Kistengewicht je Sorte und Kaliberband: aus Wasch-Arbeiten, die hinein gezählt und heraus gewogen haben (0092), und aus Sortierläufen mit gezählten Kisten (0060). kaliber_idx −1: Sollgewicht-Kisten aus gewogenen fertigen Paletten. Seit 0109 über die Planungsgrenze v_koeff_gebinde_zaun(); die Formel steht in v_koeff_gebinde_formel.';

-- ---------- v_auftrag_masse ----------
-- Masse und Alter jeder Arbeit; fast jede Auswertung steht auf ihr.
create or replace view v_auftrag_masse_formel with (security_invoker = true) as
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
    COALESCE(m.eingang_netto_kg, wg.kg, fpg.kg, wp.kg, gb.kg, fp.kg) AS eingang_netto_kg,
        CASE
            WHEN m.masse_quelle <> 'fehlt'::text THEN m.masse_quelle
            WHEN wg.kg IS NOT NULL THEN wg.quelle
            WHEN fpg.kg IS NOT NULL THEN 'fertige_paletten'::text
            WHEN wp.kg IS NOT NULL THEN 'wasch_paletten'::text
            WHEN gb.kg IS NOT NULL THEN 'gebinde'::text
            WHEN fp.kg IS NOT NULL THEN 'fax_paletten'::text
            ELSE 'fehlt'::text
        END AS masse_quelle,
    zahl(COALESCE(m.lagertage,
        CASE
            WHEN m.station = 'waschen'::station THEN (betriebstag(m.start_ts) - '2000-01-01'::date)::numeric - COALESCE(se.tage_seit_epoche, (r.eingangsdatum_mittel - '2000-01-01'::date)::numeric)
            ELSE NULL::numeric
        END), 1, 1000000000::numeric)::numeric(10,1) AS lagertage,
    a.ist_fax,
    wp.zwischenlager_tage,
        CASE
            WHEN m.lagertage IS NOT NULL THEN 'gemessen'::text
            WHEN m.station <> 'waschen'::station THEN NULL::text
            WHEN se.tage_seit_epoche IS NOT NULL THEN 'sortiermittel'::text
            WHEN r.eingangsdatum_mittel IS NOT NULL THEN 'chargenmittel'::text
            ELSE NULL::text
        END AS alter_quelle,
        CASE
            WHEN m.lagertage IS NOT NULL THEN NULL::numeric
            ELSE es.streuung_tage
        END AS alter_spanne_tage,
    COALESCE(es.ernte_fertig, false) AS ernte_fertig
   FROM mv_auftrag_masse m
     JOIN auftrag a ON a.id = m.auftrag_id
     LEFT JOIN mv_sortier_eingang se ON se.charge_nr = m.charge_nr
     LEFT JOIN v_charge_rueckgrat r ON r.charge_nr = m.charge_nr
     LEFT JOIN v_charge_erntespanne es ON es.charge_nr = m.charge_nr
     LEFT JOIN v_auftrag_wasch_paletten wp ON wp.auftrag_id = m.auftrag_id
     LEFT JOIN v_auftrag_wasch_gewogen wg ON wg.auftrag_id = m.auftrag_id
     LEFT JOIN ( SELECT v_auftrag_gebinde_masse.auftrag_id,
            sum(v_auftrag_gebinde_masse.kg) AS kg
           FROM v_auftrag_gebinde_masse
          GROUP BY v_auftrag_gebinde_masse.auftrag_id) gb ON gb.auftrag_id = m.auftrag_id
     LEFT JOIN v_auftrag_fertige_masse fpg ON fpg.auftrag_id = m.auftrag_id
     LEFT JOIN LATERAL ( SELECT zahl(a.paletten_gesamt::numeric * p.netto_kg, 2, '10000000000'::bigint::numeric)::numeric(12,2) AS kg
           FROM v_koeff_palette_netto p
          WHERE a.ist_fax AND a.paletten_gesamt > 0 AND p.sorte = m.sorte AND (p.kistensystem = a.kistensystem OR p.kistensystem IS NULL AND a.kistensystem IS DISTINCT FROM 'anderes'::text)
          ORDER BY (p.kistensystem = a.kistensystem) DESC NULLS LAST
         LIMIT 1) fp ON true;
comment on view v_auftrag_masse_formel is
  'Die Masse einer Arbeit und ihr Alter. Die Masse in dieser Reihenfolge: gewogene oder vom Zettel gelesene Eingangspaletten; beim Waschen die fertigen Paletten dieser Arbeit (0079, „fertige_paletten"); die gezählten Kisten der Kaliber-Paletten („wasch_paletten"); gezählte Gebinde; bei Fax die Palettenzahl. Fehlt alles, ist die Masse unbekannt — nicht null. — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_auftrag_masse_formel to authenticated;

create or replace function v_auftrag_masse_zaun() returns setof v_auftrag_masse_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_auftrag_masse_formel;
end $$;
comment on function v_auftrag_masse_zaun() is
  'Planungsgrenze (0109): liest v_auftrag_masse_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_auftrag_masse_zaun() from public;
grant execute on function v_auftrag_masse_zaun() to authenticated;

create or replace view v_auftrag_masse with (security_invoker = true) as
select * from v_auftrag_masse_zaun();
comment on view v_auftrag_masse is
  'Die Masse einer Arbeit und ihr Alter. Die Masse in dieser Reihenfolge: gewogene oder vom Zettel gelesene Eingangspaletten; beim Waschen die fertigen Paletten dieser Arbeit (0079, „fertige_paletten"); die gezählten Kisten der Kaliber-Paletten („wasch_paletten"); gezählte Gebinde; bei Fax die Palettenzahl. Fehlt alles, ist die Masse unbekannt — nicht null. Seit 0109 über die Planungsgrenze v_auftrag_masse_zaun(); die Formel steht in v_auftrag_masse_formel.';

-- ---------- v_schimmel_punkte ----------
-- Jede Faul-Messung als Punkt; Palox-Erwartung, Stationswerte und die Kaskade stehen auf ihr.
create or replace view v_schimmel_punkte_formel with (security_invoker = true) as
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
    betriebstag(b.start_ts) AS messtag,
    b.station::text AS station,
    b.anteil AS anteil_station,
    b.plausibel AS plausibel_station
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
    betriebstag(a.start_ts) AS messtag,
    'waschen'::text AS station,
    x.g AS anteil_station,
    anteil_plausibel(x.g) AND a.lagertage >= 0::numeric AS plausibel_station
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
    betriebstag(w.wiege_ts) AS messtag,
    'lager'::text AS station,
    v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric) AS anteil_station,
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AS plausibel_station
   FROM v_verdunstung_messung w
     JOIN verdunstung_wiegung v ON v.id = w.id
  WHERE v.faul_kg IS NOT NULL AND v.gemessen AND w.netto_jetzt_kg > 0::numeric AND w.lagertage > 0;
comment on view v_schimmel_punkte_formel is
  'Jede Faul-Messung als Punkt: die Lagerdauer (wie lange lag die Ware?) und seit 0079 der Messtag (wann wurde gemessen?). Zwei Achsen für zwei Fragen — „faulen sie nach N Wochen" und „ab wann ging es los". Der Messtag ist der Betriebstag, nie ts::date (0067/0070). — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_schimmel_punkte_formel to authenticated;

create or replace function v_schimmel_punkte_zaun() returns setof v_schimmel_punkte_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_schimmel_punkte_formel;
end $$;
comment on function v_schimmel_punkte_zaun() is
  'Planungsgrenze (0109): liest v_schimmel_punkte_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_schimmel_punkte_zaun() from public;
grant execute on function v_schimmel_punkte_zaun() to authenticated;

create or replace view v_schimmel_punkte with (security_invoker = true) as
select * from v_schimmel_punkte_zaun();
comment on view v_schimmel_punkte is
  'Jede Faul-Messung als Punkt: die Lagerdauer (wie lange lag die Ware?) und seit 0079 der Messtag (wann wurde gemessen?). Zwei Achsen für zwei Fragen — „faulen sie nach N Wochen" und „ab wann ging es los". Der Messtag ist der Betriebstag, nie ts::date (0067/0070). Seit 0109 über die Planungsgrenze v_schimmel_punkte_zaun(); die Formel steht in v_schimmel_punkte_formel.';

-- ---------- v_koeff_kaliber_geschaetzt ----------
-- Die gepoolten Ausschuss-, Nebenkanal- und Fax-Anteile; die drei Koeffizienten und die Unsicherheit stehen auf ihr.
create or replace view v_koeff_kaliber_geschaetzt_formel with (security_invoker = true) as
 WITH roh AS MATERIALIZED (
         SELECT v_koeff_roh_kaliber.art,
            v_koeff_roh_kaliber.sorte,
            v_koeff_roh_kaliber.charge_nr,
            v_koeff_roh_kaliber.anteil,
            v_koeff_roh_kaliber.gewicht
           FROM v_koeff_roh_kaliber
          WHERE v_koeff_roh_kaliber.anteil IS NOT NULL AND v_koeff_roh_kaliber.gewicht > 0::numeric
        ), je_charge AS (
         SELECT roh.art,
            roh.sorte,
            roh.charge_nr,
            sum(roh.gewicht) AS sw_c,
            sum(roh.anteil * roh.gewicht) AS swa_c,
            count(*) AS n_c
           FROM roh
          GROUP BY roh.art, roh.sorte, roh.charge_nr
        ), ebene AS (
         SELECT je_charge.art,
            je_charge.sorte,
            sum(je_charge.sw_c) AS sw,
            sum(je_charge.swa_c) AS swa,
            sum(je_charge.n_c)::integer AS n,
            count(DISTINCT je_charge.charge_nr)::integer AS c_chargen
           FROM je_charge
          GROUP BY GROUPING SETS ((je_charge.art, je_charge.sorte), (je_charge.art))
        ), mittelwert AS (
         SELECT e.art,
            e.sorte,
            e.sw,
            e.swa,
            e.n,
            e.c_chargen,
            e.swa / NULLIF(e.sw, 0::numeric) AS mittel
           FROM ebene e
        ), varianz AS (
         SELECT m.art,
            m.sorte,
            m.sw,
            m.swa,
            m.n,
            m.c_chargen,
            m.mittel,
            v_1.varianz
           FROM mittelwert m
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN m.c_chargen > 1 AND m.sw > 0::numeric THEN sum(power(j.swa_c - m.mittel * j.sw_c, 2::numeric)) / power(m.sw, 2::numeric) * m.c_chargen::numeric / (m.c_chargen - 1)::numeric
                            ELSE NULL::numeric
                        END AS varianz
                   FROM je_charge j
                  WHERE j.art = m.art AND (m.sorte IS NULL OR j.sorte = m.sorte)) v_1
        ), gesamt AS (
         SELECT varianz.art,
            varianz.mittel,
            varianz.varianz,
            varianz.c_chargen,
            varianz.n,
            varianz.sw
           FROM varianz
          WHERE varianz.sorte IS NULL
        ), tau AS (
         SELECT v_1.art,
            GREATEST(sum(v_1.sw * power(v_1.mittel - g_1.mittel, 2::numeric)) / NULLIF(sum(v_1.sw), 0::numeric) - COALESCE(avg(v_1.varianz), 0::numeric), 0::numeric) AS tau2
           FROM varianz v_1
             JOIN gesamt g_1 ON g_1.art = v_1.art
          WHERE v_1.sorte IS NOT NULL
          GROUP BY v_1.art
        ), gitter AS (
         SELECT a.art,
            sk.sorte
           FROM ( SELECT DISTINCT roh.art
                   FROM roh) a
             CROSS JOIN sorte_kaliber sk
        UNION ALL
         SELECT a.art,
            NULL::text AS text
           FROM ( SELECT DISTINCT roh.art
                   FROM roh) a
        )
 SELECT gi.art,
    gi.sorte,
    COALESCE(v.n, 0) AS n,
    COALESCE(v.c_chargen, 0) AS c_chargen,
    v.mittel AS mittel_roh,
    v.varianz AS varianz_roh,
    g.mittel AS mittel_gesamt,
    t.tau2,
    b.gewicht AS b,
    b.gewicht * COALESCE(v.mittel, g.mittel) + (1::numeric - b.gewicht) * g.mittel AS mittel,
    b.gewicht * COALESCE(v.varianz, 0::numeric) + power(1::numeric - b.gewicht, 2::numeric) * COALESCE(g.varianz, 0::numeric) AS varianz,
    GREATEST(round(b.gewicht * COALESCE(v.c_chargen, 0)::numeric + (1::numeric - b.gewicht) * g.c_chargen::numeric)::integer - 1, 1) AS df,
    g.n AS n_gesamt,
    power(b.gewicht, 2::numeric) * COALESCE(v.varianz, 0::numeric) AS varianz_eigen,
    1::numeric - b.gewicht AS gewicht_gesamt,
    COALESCE(g.varianz, 0::numeric) AS varianz_gesamt
   FROM gitter gi
     JOIN gesamt g ON g.art = gi.art
     LEFT JOIN varianz v ON v.art = gi.art AND NOT v.sorte IS DISTINCT FROM gi.sorte
     LEFT JOIN tau t ON t.art = gi.art
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN gi.sorte IS NULL THEN 1.0
                    WHEN v.varianz IS NULL OR v.mittel IS NULL OR COALESCE(t.tau2, 0::numeric) = 0::numeric THEN 0.0
                    ELSE t.tau2 / (t.tau2 + v.varianz)
                END AS gewicht) b;
comment on view v_koeff_kaliber_geschaetzt_formel is
  'Massegewichteter Anteil je Sorte, chargen-robust gefehlert und per empirischem Bayes zum Gesamtwert gezogen. b = 1 heisst: die Sorte trägt sich selbst, b = 0: es gilt der Gesamtwert. — Die Formel (0109); gelesen wird sie über die gleichnamige Sicht ohne _formel.';
grant select on v_koeff_kaliber_geschaetzt_formel to authenticated;

create or replace function v_koeff_kaliber_geschaetzt_zaun() returns setof v_koeff_kaliber_geschaetzt_formel
language plpgsql stable set search_path = public set jit = off as $$
begin
  return query select * from v_koeff_kaliber_geschaetzt_formel;
end $$;
comment on function v_koeff_kaliber_geschaetzt_zaun() is
  'Planungsgrenze (0109): liest v_koeff_kaliber_geschaetzt_formel. Der Planer setzt eine PL/pgSQL-Funktion nicht in die Abfrage darüber ein.';
revoke all on function v_koeff_kaliber_geschaetzt_zaun() from public;
grant execute on function v_koeff_kaliber_geschaetzt_zaun() to authenticated;

create or replace view v_koeff_kaliber_geschaetzt with (security_invoker = true) as
select * from v_koeff_kaliber_geschaetzt_zaun();
comment on view v_koeff_kaliber_geschaetzt is
  'Massegewichteter Anteil je Sorte, chargen-robust gefehlert und per empirischem Bayes zum Gesamtwert gezogen. b = 1 heisst: die Sorte trägt sich selbst, b = 0: es gilt der Gesamtwert. Seit 0109 über die Planungsgrenze v_koeff_kaliber_geschaetzt_zaun(); die Formel steht in v_koeff_kaliber_geschaetzt_formel.';

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 109 $$;
