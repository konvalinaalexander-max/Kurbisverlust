-- sicht: v_verlust_je_gruppe
-- Dieselben Ströme, zusammengefasst nach Gruppe (gesamt, Sorte, Schlag, Charge). kg_beobachtet ist gemessen, kg_projiziert auf noch nicht Gemessenes übertragen, kg_extrapoliert über den Messbereich hinaus gerechnet — drei verschiedene Sicherheiten, darum drei Spalten. Ist der Strom gemessen (bekannt), sind alle vier Teilbeträge Zahlen und kg_beobachtet + kg_projiziert = kg; ist er es nicht, sind alle vier NULL (0066).

 WITH gruppen AS (
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
        ), zeilen AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            h.charge_nr,
            h.sorte,
            h.schlag,
            h.portion,
            h.alter_tage,
            h.eingang_kg,
            h.portion_kg,
            h.f_extrapoliert,
            h.u,
            h.strom,
            h.buch,
            h.kg,
            h.basis_kg,
            h.koeffizient,
            h.koeff_n,
            h.koeff_basis,
            h.formel,
            h.d_r,
            h.d_eta,
            h.d_a,
            h.d_a0,
            h.koeff_art,
            h.koeff_bekannt,
            h.kohorte,
            h.strom = 'Faul beim Abpacken (Fax)'::text AND h.portion = 'lager'::text AS erwartet
           FROM mv_hochrechnung h
             JOIN gruppen g_1 ON g_1.charge_nr = h.charge_nr
          WHERE h.buch = ANY (ARRAY['verlust'::text, 'marge'::text, 'feld'::text])
        ), unsicherheit AS MATERIALIZED (
         SELECT v_koeff_unsicherheit.art,
            v_koeff_unsicherheit.sorte,
            v_koeff_unsicherheit.b,
            v_koeff_unsicherheit.varianz_eigen,
            v_koeff_unsicherheit.gewicht_gesamt,
            v_koeff_unsicherheit.varianz_gesamt,
            v_koeff_unsicherheit.df
           FROM v_koeff_unsicherheit
        ), modell AS MATERIALIZED (
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
        ), eingang AS MATERIALIZED (
         SELECT g_1.gruppe,
            g_1.schluessel,
            sum(b.eingang_kg) AS eingang_kg,
            count(*)::integer AS n_chargen
           FROM gruppen g_1
             JOIN v_kaskade_basis b ON b.charge_nr = g_1.charge_nr
          GROUP BY g_1.gruppe, g_1.schluessel
        ), je_sorte AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            z.sorte,
            max(z.koeff_art) AS koeff_art,
            sum(z.d_r) AS g_r,
            sum(z.d_a) AS g_a
           FROM zeilen z
          WHERE NOT z.erwartet
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch, z.sorte
        ), je_strom_modell AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            sum(z.d_eta) AS g_achse,
            sum(z.d_eta * z.u) AS g_steigung,
            sum(z.d_a0) AS g_a0
           FROM zeilen z
          WHERE NOT z.erwartet
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch
        ), varianz_r AS MATERIALIZED (
         SELECT s_1.gruppe,
            s_1.schluessel,
            s_1.strom,
            s_1.buch,
            sum(power(s_1.g_r, 2::numeric) * COALESCE(u.varianz_eigen, 0::numeric)) + power(sum(s_1.g_r * COALESCE(u.gewicht_gesamt, 1::numeric)), 2::numeric) * max(COALESCE(u.varianz_gesamt, 0::numeric)) AS varianz,
            min(COALESCE(u.df, 1)) AS df
           FROM je_sorte s_1
             LEFT JOIN unsicherheit u ON u.art = 'verdunstung'::text AND NOT u.sorte IS DISTINCT FROM s_1.sorte
          GROUP BY s_1.gruppe, s_1.schluessel, s_1.strom, s_1.buch
        ), varianz_a AS MATERIALIZED (
         SELECT s_1.gruppe,
            s_1.schluessel,
            s_1.strom,
            s_1.buch,
            sum(power(s_1.g_a, 2::numeric) * COALESCE(u.varianz_eigen, 0::numeric)) + power(sum(s_1.g_a * COALESCE(u.gewicht_gesamt, 1::numeric)), 2::numeric) * max(COALESCE(u.varianz_gesamt, 0::numeric)) AS varianz,
            min(COALESCE(u.df, 1)) AS df
           FROM je_sorte s_1
             LEFT JOIN unsicherheit u ON u.art = s_1.koeff_art AND NOT u.sorte IS DISTINCT FROM s_1.sorte
          WHERE s_1.koeff_art IS NOT NULL
          GROUP BY s_1.gruppe, s_1.schluessel, s_1.strom, s_1.buch
        ), varianz_f AS MATERIALIZED (
         SELECT m.gruppe,
            m.schluessel,
            m.strom,
            m.buch,
            power(m.g_achse, 2::numeric) * COALESCE(sm.var_achse, 0::numeric) + 2::numeric * m.g_achse * m.g_steigung * COALESCE(sm.kov_achse_k, 0::numeric) + power(m.g_steigung, 2::numeric) * COALESCE(sm.var_k, 0::numeric) + power(m.g_a0, 2::numeric) *
                CASE
                    WHEN sm.brauchbar THEN COALESCE(sm.sockel_var, 0::numeric)
                    ELSE 0::numeric
                END AS varianz,
            COALESCE(sm.c_chargen - 1, 1) AS df
           FROM je_strom_modell m
             CROSS JOIN modell sm
        ), summe AS MATERIALIZED (
         SELECT z.gruppe,
            z.schluessel,
            z.strom,
            z.buch,
            sum(z.kg) FILTER (WHERE NOT z.erwartet) AS kg,
            bool_and(z.koeff_bekannt) AS bekannt,
            sum(z.kg) FILTER (WHERE z.portion = 'ausgelagert'::text) AS kg_beobachtet,
            sum(z.kg) FILTER (WHERE z.portion = 'lager'::text AND NOT z.erwartet) AS kg_projiziert,
            sum(z.kg) FILTER (WHERE z.f_extrapoliert AND NOT z.erwartet) AS kg_extrapoliert,
            sum(z.kg) FILTER (WHERE z.erwartet) AS kg_erwartet,
            min(z.koeff_n) AS koeff_n_min,
            sum(z.basis_kg) AS basis_kg,
            max(z.koeff_basis) AS koeff_basis,
            max(z.koeff_art) AS koeff_art,
            max(z.formel) AS formel
           FROM zeilen z
          GROUP BY z.gruppe, z.schluessel, z.strom, z.buch
        )
 SELECT s.gruppe,
    s.schluessel,
    s.strom,
    s.buch,
        CASE
            WHEN s.bekannt THEN zahl(s.kg)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg,
        CASE
            WHEN s.bekannt THEN zahl(GREATEST(s.kg - g.t * g.streuung - zu.zuschlag, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_unten,
        CASE
            WHEN s.bekannt THEN zahl(s.kg + g.t * g.streuung + zu.zuschlag)
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_oben,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_beobachtet, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_beobachtet,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_projiziert, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_projiziert,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_extrapoliert, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_extrapoliert,
        CASE
            WHEN s.bekannt THEN zahl(COALESCE(s.kg_erwartet, 0::numeric))
            ELSE NULL::numeric
        END::numeric(14,2) AS kg_erwartet,
    s.koeff_n_min,
        CASE
            WHEN s.bekannt THEN zahl(g.streuung)
            ELSE NULL::numeric
        END::numeric(14,2) AS streuung_kg,
    g.df,
    zahl(s.basis_kg)::numeric(14,2) AS basis_kg,
    s.koeff_basis,
    s.koeff_art,
    s.formel,
    s.bekannt,
    zahl(e.eingang_kg)::numeric(14,2) AS eingang_kg,
    e.n_chargen
   FROM summe s
     JOIN eingang e ON e.gruppe = s.gruppe AND e.schluessel = s.schluessel
     LEFT JOIN varianz_r vr ON vr.gruppe = s.gruppe AND vr.schluessel = s.schluessel AND vr.strom = s.strom AND vr.buch = s.buch
     LEFT JOIN varianz_a va ON va.gruppe = s.gruppe AND va.schluessel = s.schluessel AND va.strom = s.strom AND va.buch = s.buch
     LEFT JOIN varianz_f vf ON vf.gruppe = s.gruppe AND vf.schluessel = s.schluessel AND vf.strom = s.strom AND vf.buch = s.buch
     CROSS JOIN LATERAL ( SELECT COALESCE(sm2.selektions_versatz, 0::numeric) AS versatz
           FROM modell sm2) sel
     CROSS JOIN LATERAL ( SELECT sqrt(GREATEST(COALESCE(vr.varianz, 0::numeric) + COALESCE(va.varianz, 0::numeric) + COALESCE(vf.varianz, 0::numeric), 0::numeric)) AS streuung,
            LEAST(COALESCE(vr.df, 999), COALESCE(va.df, 999), COALESCE(vf.df, 999)) AS df) g0
     CROSS JOIN LATERAL ( SELECT g0.streuung,
            g0.df,
            t_quantil_95(g0.df) AS t) g
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN s.strom = 'Schimmel/Fäulnis'::text THEN COALESCE(s.kg_projiziert, 0::numeric) * abs(exp(sel.versatz) - 1::numeric)
                    ELSE 0::numeric
                END AS zuschlag) zu;
