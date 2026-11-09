-- 0139 — Jeder Faktor wird je Zeile einmal gerechnet (Runde BK)
--
-- Die Prüfung auf GitHub war am 9. November zweimal rot: im Lasttest
-- (dreifache Saison) brauchte Schritt 4 der Auswertung 6.3 s, erlaubt sind
-- 6 s (Supabase bricht eine Abfrage nach 8 s ab). Es lag nicht an 0136–0138:
-- auf derselben Maschine frisch gebaut braucht Schritt 4 auf Stand 135
-- 4.5 s und auf Stand 138 ebenso. Der Prüfrechner war an diesem Tag rund
-- doppelt so langsam wie zwei Tage zuvor, auch bei den Prüfblöcken, deren
-- Code sich nicht geändert hat. Die Grenze bleibt; der Schritt wird kürzer.
--
-- Zwei Sichten tragen den Schritt: erg_verlauf (2.0 s) und erg_prognose
-- (1.7 s). In beiden faltet Postgres kleine Teilabfragen in die Summen
-- hinein und rechnet darum dieselbe Potenz (power) und denselben
-- Palox-Anteil (palox_f_nach) je Zeile mehrmals — in jeder Spalte, die sie
-- braucht, bei 44'000 bis 58'000 Zeilen. Jetzt je Zeile einmal:
--   - erg_verlauf: die seitlichen Teilabfragen n (die Masse nach der
--     Verdunstung) und f (der Palox-Anteil) mit OFFSET 0 — so faltet
--     Postgres sie nicht in die Summen;
--   - v_prognose (und damit erg_prognose): je_portion, wo f_h steht,
--     AS MATERIALIZED.
-- Die Zahlen bleiben dieselben, Zeile für Zeile (except all gegen die
-- Fassung 0138, auf dem Lasttest und der Demo). Lasttest lokal: erg_verlauf
-- 2.0 → 1.1 s, erg_prognose 1.7 → 1.1 s.
--
-- Was bewusst nicht gemacht wurde:
-- - Die Grenze von 6 s nicht erhöht und die Sichten nicht auf Schritt 5
--   verschoben: Schritt 4 wäre so nicht schneller, nur anders verteilt, und
--   die Summe (Regressionsmelder 12 s) bliebe.
-- - Nicht gerundet. Die Zwischenwerte tragen bis 142 Nachkommastellen
--   (numeric multipliziert genau); auf 12 Stellen gerundet wäre es noch
--   schneller, aber die Zahlen wären nicht mehr dieselben.

-- ---------- v_prognose: je_portion einmal ----------
create or replace view v_prognose with (security_invoker=true) as
 WITH tag AS MATERIALIZED (
         SELECT heute() AS heute,
            stichtag() AS stichtag
        ), ende AS (
         SELECT GREATEST(LEAST(t.stichtag - t.heute, 400), 28) AS tage
           FROM tag t
        ), horizonte AS (
         SELECT g.h
           FROM ende e,
            LATERAL generate_series(0, e.tage, 7) g(h)
        UNION
         SELECT 7
        UNION
         SELECT 14
        UNION
         SELECT 28
        UNION
         SELECT ende.tage
           FROM ende
        ), grenzen AS (
         SELECT mv_koeff_rand.sorte,
            mv_koeff_rand.r_unten,
            mv_koeff_rand.r_oben,
            mv_koeff_rand.klein_unten,
            mv_koeff_rand.klein_oben,
            mv_koeff_rand.gross_unten,
            mv_koeff_rand.gross_oben,
            mv_koeff_rand.fax_unten,
            mv_koeff_rand.fax_oben
           FROM mv_koeff_rand
        ), lager AS MATERIALIZED (
         SELECT k.charge_nr,
            k.sorte,
            k.schlag,
            k.kohorte,
            k.alter_tage,
            k.m0,
            k.r,
            k.f,
            k.f_unten,
            k.f_oben,
            k.f_ws,
            k.f_s,
            k.g_w,
            k.p_hand,
            k.p_wasch,
            k.b_ws,
            k.b_s,
            k.b_w,
            k.zuwachs_bekannt,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
            k.hagel,
            k.r_bekannt,
            k.f_bekannt,
            k.a_klein_bekannt,
            k.a_gross_bekannt,
            k.a_fax_bekannt,
            k.f_geliehen,
            COALESCE(g.r_unten, 0::numeric) AS r_unten,
            COALESCE(g.r_oben, 0::numeric) AS r_oben,
            COALESCE(g.klein_unten, 0::numeric) AS klein_unten,
            COALESCE(g.klein_oben, 0::numeric) AS klein_oben,
            COALESCE(g.gross_unten, 0::numeric) AS gross_unten,
            COALESCE(g.gross_oben, 0::numeric) AS gross_oben,
            COALESCE(g.fax_unten, 0::numeric) AS fax_unten,
            COALESCE(g.fax_oben, 0::numeric) AS fax_oben,
            power(1::numeric - k.r, k.alter_tage) AS wa,
            power(1::numeric - GREATEST(COALESCE(g.r_unten, 0::numeric), 0::numeric), k.alter_tage) AS wa_unten,
            power(1::numeric - GREATEST(COALESCE(g.r_oben, 0::numeric), 0::numeric), k.alter_tage) AS wa_oben
           FROM mv_kaskade k
             LEFT JOIN grenzen g ON g.sorte = k.sorte
          WHERE k.portion = 'lager'::text AND k.m0 > 0::numeric AND k.alter_tage >= 0::numeric
        ), faktor_h AS MATERIALIZED (
         SELECT c.charge_nr,
            h.h,
            power(1::numeric - c.r, h.h::numeric) AS wh,
            power(1::numeric - GREATEST(c.r_unten, 0::numeric), h.h::numeric) AS wh_unten,
            power(1::numeric - GREATEST(c.r_oben, 0::numeric), h.h::numeric) AS wh_oben
           FROM ( SELECT DISTINCT lager.charge_nr,
                    lager.r,
                    lager.r_unten,
                    lager.r_oben
                   FROM lager) c
             CROSS JOIN horizonte h
        ), je_portion AS MATERIALIZED (
         SELECT l.charge_nr,
            l.sorte,
            l.schlag,
            l.kohorte,
            l.alter_tage,
            l.m0,
            l.r,
            l.f,
            l.f_unten,
            l.f_oben,
            l.f_ws,
            l.f_s,
            l.g_w,
            l.p_hand,
            l.p_wasch,
            l.b_ws,
            l.b_s,
            l.b_w,
            l.zuwachs_bekannt,
            COALESCE(kh.klein, l.a_klein_n) AS a_klein_n,
            COALESCE(kh.gross, l.a_gross_n) AS a_gross_n,
            l.a_klein_n AS a_klein_0,
            l.a_gross_n AS a_gross_0,
            l.a_fax,
            l.r_bekannt,
            l.f_bekannt,
            l.a_klein_bekannt,
            l.a_gross_bekannt,
            l.a_fax_bekannt,
            l.f_geliehen,
            l.r_unten,
            l.r_oben,
            COALESCE(kh.klein, l.klein_unten) AS klein_unten,
            COALESCE(kh.klein, l.klein_oben) AS klein_oben,
            COALESCE(kh.gross, l.gross_unten) AS gross_unten,
            COALESCE(kh.gross, l.gross_oben) AS gross_oben,
            l.fax_unten,
            l.fax_oben,
            l.wa,
            l.wa_unten,
            l.wa_oben,
            h.h,
            (l.alter_tage + h.h::numeric)::integer AS t,
                CASE
                    WHEN l.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(l.p_hand, l.p_wasch, l.f_ws, l.f_s, l.g_w, l.b_ws, l.b_s, l.b_w, h.h::numeric), l.hagel), l.f)
                    ELSE l.f
                END AS f_h,
            w.wh,
            w.wh_unten,
            w.wh_oben,
            d.heute + h.h AS datum
           FROM lager l
             CROSS JOIN horizonte h
             CROSS JOIN tag d
             JOIN faktor_h w ON w.charge_nr = l.charge_nr AND w.h = h.h
             LEFT JOIN mv_kaliber_quelle kq ON kq.charge_nr = l.charge_nr AND NOT (l.charge_nr IN ( SELECT hc.nr
                   FROM charge hc
                  WHERE hc.hagel_anteil > 0::numeric))
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - l.r, l.alter_tage + h.h::numeric)) kh(klein, gross) ON true
        ), mit_band AS (
         SELECT p.charge_nr,
            p.sorte,
            p.schlag,
            p.kohorte,
            p.alter_tage,
            p.m0,
            p.r,
            p.f,
            p.f_unten,
            p.f_oben,
            p.f_ws,
            p.f_s,
            p.g_w,
            p.p_hand,
            p.p_wasch,
            p.b_ws,
            p.b_s,
            p.b_w,
            p.zuwachs_bekannt,
            p.a_klein_n,
            p.a_gross_n,
            p.a_klein_0,
            p.a_gross_0,
            p.a_fax,
            p.r_bekannt,
            p.f_bekannt,
            p.a_klein_bekannt,
            p.a_gross_bekannt,
            p.a_fax_bekannt,
            p.f_geliehen,
            p.r_unten,
            p.r_oben,
            p.klein_unten,
            p.klein_oben,
            p.gross_unten,
            p.gross_oben,
            p.fax_unten,
            p.fax_oben,
            p.wa,
            p.wa_unten,
            p.wa_oben,
            p.h,
            p.t,
            p.f_h,
            p.wh,
            p.wh_unten,
            p.wh_oben,
            p.datum,
            LEAST(GREATEST(p.f_unten + (p.f_h - p.f), 0::numeric), 1::numeric) AS f_unten_h,
            LEAST(GREATEST(p.f_oben + (p.f_h - p.f), 0::numeric), 1::numeric) AS f_oben_h
           FROM je_portion p
        ), stroeme AS (
         SELECT p.charge_nr,
            p.h,
            p.datum,
            p.t,
            p.m0,
            p.m0 - x.m1 AS verdunstet_kg,
            x.m1 * p.f_h AS faul_kg,
            y.m2 - z.rest AS kanal_kg,
            y.m2 * p.a_klein_n AS klein_kg,
            y.m2 * p.a_gross_n AS gross_kg,
            z.rest * p.a_fax AS fax_kg,
            z.rest * (1::numeric - p.a_fax) AS verkaufsfaehig_kg,
            y.m2 AS gute_ware_kg,
            p.m0 * p.wa_oben * p.wh_oben * (1::numeric - p.f_oben_h) * (1::numeric - LEAST(p.klein_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric) + p.gross_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric), 1::numeric)) * (1::numeric - p.fax_oben) AS vf_unten,
            p.m0 * p.wa_unten * p.wh_unten * (1::numeric - p.f_unten_h) * (1::numeric - LEAST(p.klein_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric) + p.gross_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric), 1::numeric)) * (1::numeric - p.fax_unten) AS vf_oben,
            (1::numeric - p.f) * (b0.basis - b.basis * p.wh) AS verlust_wasser,
            b.basis * p.wh * GREATEST(p.f_h - p.f, 0::numeric) AS verlust_faeulnis,
            p.m0 * p.t::numeric AS m0_mal_t,
            p.r_bekannt,
            p.f_bekannt,
            p.a_klein_bekannt,
            p.a_gross_bekannt,
            p.a_fax_bekannt,
            p.f_geliehen,
            p.zuwachs_bekannt
           FROM mit_band p
             CROSS JOIN LATERAL ( SELECT p.m0 * p.wa * p.wh AS m1) x
             CROSS JOIN LATERAL ( SELECT x.m1 * (1::numeric - p.f_h) AS m2) y
             CROSS JOIN LATERAL ( SELECT y.m2 * (1::numeric - p.a_klein_n - p.a_gross_n) AS rest) z
             CROSS JOIN LATERAL ( SELECT p.m0 * (1::numeric - p.a_klein_n - p.a_gross_n) * (1::numeric - p.a_fax) * p.wa AS basis) b
             CROSS JOIN LATERAL ( SELECT p.m0 * (1::numeric - p.a_klein_0 - p.a_gross_0) * (1::numeric - p.a_fax) * p.wa AS basis) b0
        ), gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text AS text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text AS text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text AS text,
            v_kaskade_basis.charge_nr::text AS charge_nr,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        ), je_charge AS MATERIALIZED (
         SELECT s_1.charge_nr,
            s_1.h,
            max(s_1.datum) AS datum,
            count(*)::integer AS n_kohorten,
            sum(s_1.m0) AS lager_kg,
            sum(s_1.verdunstet_kg) AS verdunstet_kg,
            sum(s_1.faul_kg) AS faul_kg,
            sum(s_1.kanal_kg) AS kanal_kg,
            sum(s_1.klein_kg) AS klein_kg,
            sum(s_1.gross_kg) AS gross_kg,
            sum(s_1.fax_kg) AS fax_kg,
            sum(s_1.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(s_1.gute_ware_kg) AS gute_ware_kg,
            sum(s_1.vf_unten) AS vf_unten_kg,
            sum(s_1.vf_oben) AS vf_oben_kg,
            sum(s_1.verlust_wasser) AS verlust_wasser_kg,
            sum(s_1.verlust_faeulnis) AS verlust_faeulnis_kg,
            sum(s_1.m0_mal_t) AS m0_mal_t,
            bool_and(s_1.r_bekannt) AS r_bekannt,
            bool_and(s_1.f_bekannt) AS f_bekannt,
            bool_and(s_1.a_klein_bekannt AND s_1.a_gross_bekannt) AS kanal_bekannt,
            bool_and(s_1.a_fax_bekannt) AS fax_bekannt,
            bool_or(s_1.f_geliehen) AS f_geliehen,
            bool_and(s_1.zuwachs_bekannt) AS zuwachs_bekannt,
            min(s_1.t) AS alter_von,
            max(s_1.t) AS alter_bis
           FROM stroeme s_1
          GROUP BY s_1.charge_nr, s_1.h
        ), summe AS MATERIALIZED (
         SELECT g.gruppe,
            g.schluessel,
            j.h,
            max(j.datum) AS datum,
            count(*)::integer AS n_chargen,
            sum(j.n_kohorten)::integer AS n_kohorten,
            sum(j.lager_kg) AS lager_kg,
            sum(j.verdunstet_kg) AS verdunstet_kg,
            sum(j.faul_kg) AS faul_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.klein_kg) AS klein_kg,
            sum(j.gross_kg) AS gross_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(j.gute_ware_kg) AS gute_ware_kg,
            sum(j.vf_unten_kg) AS vf_unten_kg,
            sum(j.vf_oben_kg) AS vf_oben_kg,
            sum(j.verlust_wasser_kg) AS verlust_wasser_kg,
            sum(j.verlust_faeulnis_kg) AS verlust_faeulnis_kg,
            bool_and(j.r_bekannt) AS r_bekannt,
            bool_and(j.f_bekannt) AS f_bekannt,
            bool_and(j.kanal_bekannt) AS kanal_bekannt,
            bool_and(j.fax_bekannt) AS fax_bekannt,
            bool_or(j.f_geliehen) AS f_geliehen,
            bool_and(j.zuwachs_bekannt) AS zuwachs_bekannt,
            sum(j.m0_mal_t) / NULLIF(sum(j.lager_kg), 0::numeric) AS alter_tage,
            min(j.alter_von) AS alter_von,
            max(j.alter_bis) AS alter_bis
           FROM je_charge j
             JOIN gruppen g ON g.charge_nr = j.charge_nr
          GROUP BY g.gruppe, g.schluessel, j.h
        ), rate AS (
         SELECT s0.gruppe,
            s0.schluessel,
            (s1.verlust_wasser_kg + s1.verlust_faeulnis_kg) / s1.h::numeric AS vf_je_tag_kg,
            s1.verlust_wasser_kg / s1.h::numeric AS verdunstet_je_tag_kg,
                CASE
                    WHEN s1.zuwachs_bekannt THEN s1.verlust_faeulnis_kg / s1.h::numeric
                    ELSE NULL::numeric
                END AS faul_je_tag_kg
           FROM summe s0
             JOIN LATERAL ( SELECT x.gruppe,
                    x.schluessel,
                    x.h,
                    x.datum,
                    x.n_chargen,
                    x.n_kohorten,
                    x.lager_kg,
                    x.verdunstet_kg,
                    x.faul_kg,
                    x.kanal_kg,
                    x.fax_kg,
                    x.verkaufsfaehig_kg,
                    x.gute_ware_kg,
                    x.vf_unten_kg,
                    x.vf_oben_kg,
                    x.verlust_wasser_kg,
                    x.verlust_faeulnis_kg,
                    x.r_bekannt,
                    x.f_bekannt,
                    x.kanal_bekannt,
                    x.fax_bekannt,
                    x.f_geliehen,
                    x.zuwachs_bekannt,
                    x.alter_tage,
                    x.alter_von,
                    x.alter_bis
                   FROM summe x
                  WHERE x.gruppe = s0.gruppe AND x.schluessel = s0.schluessel AND x.h > 0
                  ORDER BY x.h
                 LIMIT 1) s1 ON true
          WHERE s0.h = 0
        )
 SELECT s.gruppe,
    s.schluessel,
    s.h,
    s.datum,
    s.n_chargen,
    s.n_kohorten,
    zahl(s.lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(s.verdunstet_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstet_kg,
    zahl(s.faul_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS faul_kg,
    zahl(s.kanal_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_kg,
    zahl(s.fax_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kg,
    zahl(s.verkaufsfaehig_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(s.gute_ware_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS gute_ware_kg,
    zahl(s.verlust_wasser_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_wasser_kg,
    zahl(s.verlust_faeulnis_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_faeulnis_kg,
    zahl(s.verlust_wasser_kg + s.verlust_faeulnis_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_verkaufsfaehig_kg,
        CASE
            WHEN v.vollstaendig AND s.lager_kg > 0::numeric THEN zahl(s.verkaufsfaehig_kg / s.lager_kg, 4, 1::numeric)
            ELSE NULL::numeric
        END::numeric(6,4) AS verkaufsfaehig_anteil,
        CASE
            WHEN v.vollstaendig THEN zahl(s.vf_unten_kg, 2, '1000000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(14,2) AS verkaufsfaehig_unten_kg,
        CASE
            WHEN v.vollstaendig THEN zahl(s.vf_oben_kg, 2, '1000000000000'::numeric)
            ELSE NULL::numeric
        END::numeric(14,2) AS verkaufsfaehig_oben_kg,
    zahl(r.vf_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS verkaufsfaehig_je_tag_kg,
    zahl(r.verdunstet_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS verdunstet_je_tag_kg,
    zahl(r.faul_je_tag_kg, 1, '1000000000'::numeric)::numeric(12,1) AS faul_je_tag_kg,
    s.r_bekannt,
    s.f_bekannt,
    s.kanal_bekannt,
    s.fax_bekannt,
    v.vollstaendig,
    s.f_geliehen,
    s.zuwachs_bekannt,
    round(s.alter_tage)::integer AS alter_tage,
    s.alter_von,
    s.alter_bis,
    zahl(s.klein_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS klein_kg,
    zahl(s.gross_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS gross_kg
   FROM summe s
     CROSS JOIN LATERAL ( SELECT s.r_bekannt AND s.f_bekannt AND s.kanal_bekannt AND s.fax_bekannt AS vollstaendig) v
     LEFT JOIN rate r ON r.gruppe = s.gruppe AND r.schluessel = s.schluessel;
comment on view v_prognose is 'Was aus der heute liegenden Ware wird, wenn sie liegen bleibt — je Gruppe (gesamt, Sorte, Schlag, Charge) und je Horizont h Tage, von heute bis zum Saisonende in Wochenschritten (7/14/28 immer dabei). Es ist die Kaskade (mv_kaskade, Portion „lager") bei alter_tage + h, mit denselben Formeln: bei h = 0 stehen deshalb genau die Zahlen von erg_charge. Der Palox-Anteil wächst je Station um ihren Anstieg je Woche Lagerdauer (0111) — nur wenn zuwachs_bekannt; sonst bleibt der Anteil von heute stehen und faul_je_tag_kg ist leer. kanal_kg = klein_kg + gross_kg (zu klein, zu gross; getrennt seit 0111). f_geliehen: ein Anteil aus allen Sorten. Der Nenner ist lager_kg, die Eingangsware, die noch nicht hinter einer Lieferung steckt; vollstaendig heisst: Verdunstung, Palox, Ausschuss und Fax gemessen. Seit 0139 ist je_portion MATERIALIZED: der Palox-Anteil f_h wird je Zeile einmal gerechnet, nicht in jeder Spalte, die ihn braucht — dieselben Zahlen, schneller.';
grant select on v_prognose to authenticated;

-- ---------- erg_verlauf: Verdunstung und Palox-Anteil je Zeile einmal ----------
drop materialized view if exists erg_verlauf;
create materialized view erg_verlauf as
 WITH tag AS MATERIALIZED (
         SELECT heute() AS heute,
            stichtag() AS stichtag
        ), wochen AS MATERIALIZED (
         SELECT w_1.w::date AS woche,
            (w_1.w + '6 days'::interval)::date AS bis
           FROM tag t,
            LATERAL generate_series(date_trunc('week'::text, COALESCE(( SELECT min(palette.eingangsdatum) AS min
                   FROM palette), t.heute)::timestamp with time zone)::date::timestamp with time zone, date_trunc('week'::text, GREATEST(t.stichtag, t.heute + 84)::timestamp with time zone)::date::timestamp with time zone, '7 days'::interval) w_1(w)
        UNION
         SELECT date_trunc('week'::text, t.heute::timestamp with time zone)::date AS date_trunc,
            t.heute
           FROM tag t
        ), gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text AS text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text AS text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text AS text,
            v_kaskade_basis.charge_nr::text AS charge_nr,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        ), portionen AS MATERIALIZED (
         SELECT k.charge_nr,
            k.portion,
            k.kohorte,
            k.m0,
            k.r,
            k.f,
            k.f_ws,
            k.f_s,
            k.g_w,
            k.p_hand,
            k.p_wasch,
            k.b_ws,
            k.b_s,
            k.b_w,
            k.zuwachs_bekannt,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
            k.hagel,
            k.alter_tage,
                CASE
                    WHEN k.portion = 'ausgelagert'::text THEN k.kohorte + round(k.alter_tage)::integer
                    ELSE NULL::date
                END AS liefertag,
                CASE
                    WHEN k.portion = 'ausgelagert'::text THEN k.fax_kg
                    ELSE 0::numeric
                END AS fax_kg
           FROM mv_kaskade k
          WHERE k.m0 > 0::numeric AND k.kohorte IS NOT NULL
        ), lieferanteil AS MATERIALIZED (
         SELECT w_1.bis,
            l.charge_nr,
            sum(l.masse_kg) FILTER (WHERE l.datum <= w_1.bis) / NULLIF(sum(l.masse_kg), 0::numeric) AS q
           FROM wochen w_1
             CROSS JOIN v_lieferung_charge_tag l
          WHERE l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])
          GROUP BY w_1.bis, l.charge_nr
        ), je_woche AS (
         SELECT w_1.woche,
            w_1.bis,
            p.charge_nr,
            q.q * (p.m0 - n.d) + (1::numeric - q.q) * (p.m0 - n.u) AS verdunstung_kg,
            q.q * n.d * f.d + (1::numeric - q.q) * n.u * f.u AS schimmel_kg,
            q.q * p.fax_kg AS fax_kg,
            (1::numeric - q.q) * p.m0 AS lager_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) AS gute_ware_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * ku.kn AS kanal_lager_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * (1::numeric - ku.kn) * p.a_fax AS fax_lager_kg,
            q.q * n.d * (1::numeric - f.d) * (p.a_klein_n + p.a_gross_n) AS aussortiert_kg,
            (1::numeric - q.q) * n.u * (1::numeric - f.u) * (1::numeric - ku.kn) * (1::numeric - p.a_fax) AS verkaufsfaehig_kg
           FROM wochen w_1
             JOIN portionen p ON p.kohorte <= w_1.bis
             CROSS JOIN tag d_1
             LEFT JOIN lieferanteil la ON la.bis = w_1.bis AND la.charge_nr = p.charge_nr
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.liefertag IS NULL THEN 0::numeric
                            ELSE LEAST(GREATEST(COALESCE(la.q,
                            CASE
                                WHEN p.liefertag <= w_1.bis THEN 1::numeric
                                ELSE 0::numeric
                            END), 0::numeric), 1::numeric)
                        END AS q) q
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.liefertag IS NULL THEN GREATEST(w_1.bis - p.kohorte, 0)::numeric
                            ELSE LEAST(GREATEST(w_1.bis - p.kohorte, 0)::numeric, p.alter_tage)
                        END AS u) t
             CROSS JOIN LATERAL ( SELECT p.m0 * power(1::numeric - p.r, COALESCE(p.alter_tage, 0::numeric)) AS d,
                    p.m0 * power(1::numeric - p.r, t.u) AS u
                 OFFSET 0) n
             LEFT JOIN mv_kaliber_quelle kq ON kq.charge_nr = p.charge_nr AND NOT (p.charge_nr IN ( SELECT hc.nr
                   FROM charge hc
                  WHERE hc.hagel_anteil > 0::numeric))
             LEFT JOIN LATERAL kaliber_anteil(kq.ebene, kq.schluessel, kq.lo::numeric, kq.hi::numeric, power(1::numeric - p.r, t.u)) kl(klein, gross) ON true
             CROSS JOIN LATERAL ( SELECT COALESCE(kl.klein + kl.gross, p.a_klein_n + p.a_gross_n) AS kn) ku
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w, 0::numeric), p.hagel), p.f)
                            ELSE p.f
                        END AS d,
                        CASE
                            WHEN p.zuwachs_bekannt THEN COALESCE(hagel_f(palox_f_nach(p.p_hand, p.p_wasch, p.f_ws, p.f_s, p.g_w, p.b_ws, p.b_s, p.b_w, (LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - COALESCE(p.liefertag, d_1.heute))::numeric), p.hagel), p.f)
                            ELSE p.f
                        END AS u
                 OFFSET 0) f
        ), je_charge AS MATERIALIZED (
         SELECT je_woche.woche,
            je_woche.bis,
            je_woche.charge_nr,
            sum(je_woche.verdunstung_kg) AS verdunstung_kg,
            sum(je_woche.schimmel_kg) AS schimmel_kg,
            sum(je_woche.fax_kg) AS fax_kg,
            sum(je_woche.gute_ware_kg) AS im_haus_kg,
            sum(je_woche.lager_kg) AS lager_kg,
            sum(je_woche.kanal_lager_kg) AS kanal_kg,
            sum(je_woche.fax_lager_kg) AS fax_lager_kg,
            sum(je_woche.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(je_woche.aussortiert_kg) AS aussortiert_kg
           FROM je_woche
          GROUP BY je_woche.woche, je_woche.bis, je_woche.charge_nr
        ), verlust AS (
         SELECT j.woche,
            j.bis,
            g.gruppe,
            g.schluessel,
            sum(j.verdunstung_kg) AS verdunstung_kg,
            sum(j.schimmel_kg) AS schimmel_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.im_haus_kg) AS im_haus_kg,
            sum(j.lager_kg) AS lager_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.fax_lager_kg) AS fax_lager_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(j.aussortiert_kg) AS aussortiert_kg
           FROM je_charge j
             JOIN gruppen g ON g.charge_nr = j.charge_nr
          GROUP BY j.woche, j.bis, g.gruppe, g.schluessel
        ), eingang_charge AS MATERIALIZED (
         SELECT w_1.woche,
            w_1.bis,
            k.charge_nr,
            sum(k.eingang_kg) AS kg
           FROM wochen w_1
             JOIN v_charge_kohorte k ON k.eingangsdatum <= w_1.bis
          GROUP BY w_1.woche, w_1.bis, k.charge_nr
        ), eingang AS (
         SELECT e_1.woche,
            e_1.bis,
            g.gruppe,
            g.schluessel,
            sum(e_1.kg) AS kg
           FROM eingang_charge e_1
             JOIN gruppen g ON g.charge_nr = e_1.charge_nr
          GROUP BY e_1.woche, e_1.bis, g.gruppe, g.schluessel
        ), ausgang_charge AS MATERIALIZED (
         SELECT w_1.woche,
            w_1.bis,
            l.charge_nr,
            sum(l.masse_kg) AS kg
           FROM wochen w_1
             JOIN v_lieferung_charge_tag l ON l.datum <= w_1.bis
          GROUP BY w_1.woche, w_1.bis, l.charge_nr
        ), ausgang AS (
         SELECT a_1.woche,
            a_1.bis,
            g.gruppe,
            g.schluessel,
            sum(a_1.kg) AS kg
           FROM ausgang_charge a_1
             JOIN gruppen g ON g.charge_nr = a_1.charge_nr
          GROUP BY a_1.woche, a_1.bis, g.gruppe, g.schluessel
        ), liste AS (
         SELECT DISTINCT gruppen.gruppe,
            gruppen.schluessel
           FROM gruppen
        )
 SELECT w.woche,
    w.bis,
    w.bis > d.heute AS prognose,
    s.gruppe,
    s.schluessel,
    zahl(COALESCE(e.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kum_kg,
    zahl(COALESCE(a.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgang_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_kum_kg,
    zahl(COALESCE(v.schimmel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_kum_kg,
    zahl(COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric) + COALESCE(v.schimmel_kg, 0::numeric) + COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_kum_kg,
    zahl(COALESCE(v.im_haus_kg, 0::numeric) + COALESCE(v.aussortiert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_kg,
    zahl(COALESCE(v.lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(COALESCE(v.verkaufsfaehig_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(COALESCE(v.kanal_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_kg,
    zahl(COALESCE(v.fax_lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_lager_kg,
    zahl(COALESCE(v.aussortiert_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS aussortiert_kg
   FROM wochen w
     CROSS JOIN liste s
     CROSS JOIN tag d
     LEFT JOIN verlust v ON v.bis = w.bis AND v.gruppe = s.gruppe AND v.schluessel = s.schluessel
     LEFT JOIN eingang e ON e.bis = w.bis AND e.gruppe = s.gruppe AND e.schluessel = s.schluessel
     LEFT JOIN ausgang a ON a.bis = w.bis AND a.gruppe = s.gruppe AND a.schluessel = s.schluessel
with no data;
create index if not exists erg_verlauf_gruppe on public.erg_verlauf USING btree (gruppe, schluessel, bis);
create unique index if not exists erg_verlauf_pk on public.erg_verlauf USING btree (woche, bis, gruppe, schluessel);
create index if not exists erg_verlauf_woche on public.erg_verlauf USING btree (woche);
comment on materialized view erg_verlauf is 'Je Woche und Gruppe (gesamt, Sorte, Schlag, Charge): Eingang und Ausgang kumuliert (gemessen), im Lager (Eingangsware, die noch nicht hinter einer Lieferung steckt) und davon verkaufsfähig (gerechnet) — ab heute als Prognose bis zum Saisonende (prognose = true). Der Verlust ist der Abstand zwischen im Lager und verkaufsfähig; seine Teile stehen weiter als eigene Spalten (0071). Seit 0106 ohne Sockel: das Faule ist der Palox-Anteil der Stationen, mit dem Zuwachs je Woche zurück und voraus verschoben, wo die Kennzahl ihn ausweist. Seit 0114 fällt „im Lager" mit den Lieferungen: je Woche der Teil, den die Lieferungen der Charge bis dahin ausmachen, nicht alles am mittleren Liefertag. Seit 0139 stehen die seitlichen Teilabfragen n (Masse nach Verdunstung) und f (Palox-Anteil) hinter OFFSET 0: je Zeile einmal gerechnet, nicht in jeder Summe — dieselben Zahlen, schneller.';
grant select on erg_verlauf to authenticated;

-- ---------- Stand ----------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 139 $$;
