-- sicht: v_prognose
-- Was aus der heute liegenden Ware wird, wenn sie liegen bleibt — je Gruppe (gesamt, Sorte, Schlag, Charge) und je Horizont h Tage, von heute bis zum Saisonende in Wochenschritten (7/14/28 immer dabei). Es ist die Kaskade (mv_kaskade, Portion „lager") bei alter_tage + h, mit denselben Formeln: bei h = 0 stehen deshalb genau die Zahlen von erg_charge. Der Nenner ist lager_kg, die liegende Eingangsware — er ändert sich über den Horizont nicht. verkaufsfaehig_unten/oben ist eine Hülle (alle Koeffizienten gleichzeitig am ungünstigsten Rand), kein gemeinsames 95-%%-Intervall. Fehlt ein Koeffizient, bleiben Anteil und Hülle leer — die Massen sind dann eine obere Schranke (0064).

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
        ), kurve AS MATERIALIZED (
         SELECT v_schimmel_kurve.von,
            v_schimmel_kurve.anteil_mono,
            v_schimmel_kurve.unten AS anteil_unten,
            v_schimmel_kurve.oben AS anteil_oben
           FROM v_schimmel_kurve
          WHERE v_schimmel_kurve.n > 0
        ), tag AS MATERIALIZED (
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
            k.a0,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
            k.r_bekannt,
            k.f_bekannt,
            k.a0_bekannt,
            k.a_klein_bekannt,
            k.a_gross_bekannt,
            k.a_fax_bekannt,
            k.modell_gilt,
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
        ), tage AS (
         SELECT DISTINCT (l.alter_tage + h.h::numeric)::integer AS t
           FROM lager l
             CROSS JOIN horizonte h
        ), f_je_tag AS MATERIALIZED (
         SELECT t.t,
                CASE
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(t.t::numeric, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 1::numeric)
                    ELSE LEAST(GREATEST(COALESCE(( SELECT c.anteil_mono
                       FROM kurve c
                      WHERE c.von <= t.t
                      ORDER BY c.von DESC
                     LIMIT 1), 0::numeric), 0::numeric), 1::numeric)
                END AS f,
                CASE
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(t.t::numeric, 1::numeric)) - m.t_faktor * sqrt(GREATEST(m.var_achse + power(ln(GREATEST(t.t::numeric, 1::numeric)) - m.x_mittel, 2::numeric) * m.var_k + 2::numeric * (ln(GREATEST(t.t::numeric, 1::numeric)) - m.x_mittel) * m.kov_achse_k, 0::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 1::numeric)::double precision
                    ELSE LEAST(GREATEST(COALESCE(( SELECT COALESCE(c.anteil_unten, c.anteil_mono::double precision) AS "coalesce"
                       FROM kurve c
                      WHERE c.von <= t.t
                      ORDER BY c.von DESC
                     LIMIT 1), 0::double precision), 0::double precision), 1::double precision)
                END AS f_unten,
                CASE
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(t.t::numeric, 1::numeric)) + m.t_faktor * sqrt(GREATEST(m.var_achse + power(ln(GREATEST(t.t::numeric, 1::numeric)) - m.x_mittel, 2::numeric) * m.var_k + 2::numeric * (ln(GREATEST(t.t::numeric, 1::numeric)) - m.x_mittel) * m.kov_achse_k, 0::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 1::numeric)::double precision
                    ELSE LEAST(GREATEST(COALESCE(( SELECT COALESCE(c.anteil_oben, c.anteil_mono::double precision) AS "coalesce"
                       FROM kurve c
                      WHERE c.von <= t.t
                      ORDER BY c.von DESC
                     LIMIT 1), 0::double precision), 0::double precision), 1::double precision)
                END AS f_oben
           FROM tage t
             CROSS JOIN modell m
        ), je_portion AS (
         SELECT l.charge_nr,
            l.sorte,
            l.schlag,
            l.kohorte,
            l.alter_tage,
            l.m0,
            l.r,
            l.a0,
            l.a_klein_n,
            l.a_gross_n,
            l.a_fax,
            l.r_bekannt,
            l.f_bekannt,
            l.a0_bekannt,
            l.a_klein_bekannt,
            l.a_gross_bekannt,
            l.a_fax_bekannt,
            l.modell_gilt,
            l.r_unten,
            l.r_oben,
            l.klein_unten,
            l.klein_oben,
            l.gross_unten,
            l.gross_oben,
            l.fax_unten,
            l.fax_oben,
            l.wa,
            l.wa_unten,
            l.wa_oben,
            h.h,
            (l.alter_tage + h.h::numeric)::integer AS t,
            f.f,
            f.f_unten,
            f.f_oben,
            f0.f AS f_heute,
            w.wh,
            w.wh_unten,
            w.wh_oben,
                CASE
                    WHEN m.brauchbar THEN COALESCE(m.sockel_unten, m.sockel, 0::numeric)
                    ELSE 0::numeric
                END AS a0_unten,
                CASE
                    WHEN m.brauchbar THEN COALESCE(m.sockel_oben, m.sockel, 0::numeric)
                    ELSE 0::numeric
                END AS a0_oben,
            m.t_max,
            d.heute + h.h AS datum
           FROM lager l
             CROSS JOIN horizonte h
             CROSS JOIN modell m
             CROSS JOIN tag d
             JOIN faktor_h w ON w.charge_nr = l.charge_nr AND w.h = h.h
             JOIN f_je_tag f ON f.t = (l.alter_tage + h.h::numeric)::integer
             JOIN f_je_tag f0 ON f0.t = l.alter_tage::integer
        ), stroeme AS (
         SELECT p.charge_nr,
            p.h,
            p.datum,
            p.t,
            p.m0,
            p.m0 - x.m1 AS verdunstet_kg,
            x.m1 * p.a0 AS sockel_kg,
            x.m1 * (1::numeric - p.a0) * p.f AS faul_kg,
            y.m2 - z.rest AS kanal_kg,
            z.rest * p.a_fax AS fax_kg,
            z.rest * (1::numeric - p.a_fax) AS verkaufsfaehig_kg,
            y.m2 AS gute_ware_kg,
            (p.m0 * p.wa_oben * p.wh_oben * (1::numeric - p.a0_oben))::double precision * (1::double precision - p.f_oben) * (1::numeric - LEAST(p.klein_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric) + p.gross_oben / GREATEST(p.klein_oben + p.gross_oben, 1::numeric), 1::numeric))::double precision * (1::numeric - p.fax_oben)::double precision AS vf_unten,
            (p.m0 * p.wa_unten * p.wh_unten * (1::numeric - p.a0_unten))::double precision * (1::double precision - p.f_unten) * (1::numeric - LEAST(p.klein_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric) + p.gross_unten / GREATEST(p.klein_unten + p.gross_unten, 1::numeric), 1::numeric))::double precision * (1::numeric - p.fax_unten)::double precision AS vf_oben,
            b.basis * (1::numeric - p.f_heute) * (1::numeric - p.wh) AS verlust_wasser,
            b.basis * p.wh * GREATEST(p.f - p.f_heute, 0::numeric) AS verlust_faeulnis,
            p.m0 * p.t::numeric AS m0_mal_t,
            p.r_bekannt,
            p.f_bekannt,
            p.a0_bekannt,
            p.a_klein_bekannt,
            p.a_gross_bekannt,
            p.a_fax_bekannt,
            p.modell_gilt,
            p.modell_gilt AND p.t::numeric > p.t_max AS ueber_t_max
           FROM je_portion p
             CROSS JOIN LATERAL ( SELECT p.m0 * p.wa * p.wh AS m1) x
             CROSS JOIN LATERAL ( SELECT x.m1 * (1::numeric - p.a0) * (1::numeric - p.f) AS m2) y
             CROSS JOIN LATERAL ( SELECT y.m2 * (1::numeric - p.a_klein_n - p.a_gross_n) AS rest) z
             CROSS JOIN LATERAL ( SELECT p.m0 * (1::numeric - p.a0) * (1::numeric - p.a_klein_n - p.a_gross_n) * (1::numeric - p.a_fax) * p.wa AS basis) b
        ), gruppen AS (
         SELECT 'gesamt'::text AS gruppe,
            ''::text AS schluessel,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'sorte'::text,
            v_kaskade_basis.sorte,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'schlag'::text,
            v_kaskade_basis.schlag,
            v_kaskade_basis.charge_nr
           FROM v_kaskade_basis
        UNION ALL
         SELECT 'charge'::text,
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
            sum(s_1.sockel_kg) AS sockel_kg,
            sum(s_1.faul_kg) AS faul_kg,
            sum(s_1.kanal_kg) AS kanal_kg,
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
            bool_and(s_1.a0_bekannt) AS sockel_bekannt,
            bool_and(s_1.a_klein_bekannt AND s_1.a_gross_bekannt) AS kanal_bekannt,
            bool_and(s_1.a_fax_bekannt) AS fax_bekannt,
            bool_and(s_1.modell_gilt) AS modell_gilt,
            bool_or(s_1.ueber_t_max) AS hochgerechnet,
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
            sum(j.sockel_kg) AS sockel_kg,
            sum(j.faul_kg) AS faul_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg,
            sum(j.gute_ware_kg) AS gute_ware_kg,
            sum(j.vf_unten_kg) AS vf_unten_kg,
            sum(j.vf_oben_kg) AS vf_oben_kg,
            sum(j.verlust_wasser_kg) AS verlust_wasser_kg,
            sum(j.verlust_faeulnis_kg) AS verlust_faeulnis_kg,
            bool_and(j.r_bekannt) AS r_bekannt,
            bool_and(j.f_bekannt) AS f_bekannt,
            bool_and(j.sockel_bekannt) AS sockel_bekannt,
            bool_and(j.kanal_bekannt) AS kanal_bekannt,
            bool_and(j.fax_bekannt) AS fax_bekannt,
            bool_and(j.modell_gilt) AS modell_gilt,
            bool_or(j.hochgerechnet) AS hochgerechnet,
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
            s1.verlust_faeulnis_kg / s1.h::numeric AS faul_je_tag_kg
           FROM summe s0
             JOIN LATERAL ( SELECT x.gruppe,
                    x.schluessel,
                    x.h,
                    x.datum,
                    x.n_chargen,
                    x.n_kohorten,
                    x.lager_kg,
                    x.verdunstet_kg,
                    x.sockel_kg,
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
                    x.sockel_bekannt,
                    x.kanal_bekannt,
                    x.fax_bekannt,
                    x.modell_gilt,
                    x.hochgerechnet,
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
    zahl(s.sockel_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS sockel_kg,
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
    s.sockel_bekannt,
    s.kanal_bekannt,
    s.fax_bekannt,
    v.vollstaendig,
    s.modell_gilt,
    s.hochgerechnet,
    round(s.alter_tage)::integer AS alter_tage,
    s.alter_von,
    s.alter_bis
   FROM summe s
     CROSS JOIN LATERAL ( SELECT s.r_bekannt AND s.f_bekannt AND s.sockel_bekannt AND s.kanal_bekannt AND s.fax_bekannt AS vollstaendig) v
     LEFT JOIN rate r ON r.gruppe = s.gruppe AND r.schluessel = s.schluessel;
