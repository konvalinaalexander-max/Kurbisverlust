-- gespeichert: mv_kaskade
-- Die Massenkaskade je Charge, Eingangstag und Portion. Drei Portionen: „ausgelagert" ist die Eingangsmasse hinter den verkauften und in den Nebenkanal gegangenen Lieferungen, „entsorgt" die hinter dem Kompost (0065 — nur um die Verdunstung zurückgerechnet, weil entsorgte Ware selbst das Faule ist), „lager" der Rest, der noch liegt. Je Portion die Ströme Verdunstung, Sockel, Schimmel, zu klein, Nebenkanal, Fax und verkaufsfähig; sie summieren sich zu m0. Ohne Messung ist der Koeffizient 0 und das Kennzeichen daneben falsch — wer die Ströme summiert, muss es lesen.

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
            v_schimmel_kurve.n
           FROM v_schimmel_kurve
          WHERE v_schimmel_kurve.n > 0
        ), kohorten AS MATERIALIZED (
         SELECT k_1.charge_nr,
            k_1.eingangsdatum,
            k_1.anteil,
            b.eingang_kg * k_1.anteil AS eingang_kg
           FROM v_kohorte_anteil k_1
             JOIN v_kaskade_basis b ON b.charge_nr = k_1.charge_nr
        ), lieferungen AS MATERIALIZED (
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            sum(v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, 0::numeric)) / NULLIF(sum(v_lieferung_kohorte.masse_kg), 0::numeric) AS alter_tage,
            sum(v_lieferung_kohorte.n_lieferungen)::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE v_lieferung_kohorte.buch = ANY (ARRAY['verkauf'::text, 'marge'::text])
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), entsorgt_lief AS (
         SELECT v_lieferung_kohorte.charge_nr,
            v_lieferung_kohorte.kohorte,
            sum(v_lieferung_kohorte.masse_kg) AS masse_kg,
            sum(v_lieferung_kohorte.masse_kg * COALESCE(v_lieferung_kohorte.alter_tage, 0::numeric)) / NULLIF(sum(v_lieferung_kohorte.masse_kg), 0::numeric) AS alter_tage,
            sum(v_lieferung_kohorte.n_lieferungen)::integer AS n_lieferungen
           FROM v_lieferung_kohorte
          WHERE v_lieferung_kohorte.buch = 'verlust'::text
          GROUP BY v_lieferung_kohorte.charge_nr, v_lieferung_kohorte.kohorte
        ), koeff AS (
         SELECT b.charge_nr,
            b.sorte,
            b.schlag,
            b.eingang_kg,
            b.stichtag,
            LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            kv.mittel IS NOT NULL AS r_bekannt,
            kv.n AS r_n,
            kv.basis AS r_basis,
            LEAST(GREATEST(COALESCE(ka.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_klein,
            ka.mittel IS NOT NULL AS a_klein_bekannt,
            ka.n AS klein_n,
            ka.basis AS klein_basis,
            LEAST(GREATEST(COALESCE(kn.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_gross,
            kn.mittel IS NOT NULL AS a_gross_bekannt,
            kn.n AS gross_n,
            kn.basis AS gross_basis,
            LEAST(GREATEST(COALESCE(kf.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_fax,
            kf.mittel IS NOT NULL AS a_fax_bekannt,
            kf.n AS fax_n,
            kf.basis AS fax_basis
           FROM v_kaskade_basis b
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b.sorte
             LEFT JOIN v_koeff_ausschuss ka ON ka.sorte = b.sorte
             LEFT JOIN v_koeff_nebenkanal kn ON kn.sorte = b.sorte
             LEFT JOIN v_koeff_fax kf ON kf.sorte = b.sorte
          WHERE b.eingang_kg > 0::numeric
        ), koeff_norm AS (
         SELECT k_1.charge_nr,
            k_1.sorte,
            k_1.schlag,
            k_1.eingang_kg,
            k_1.stichtag,
            k_1.r,
            k_1.r_bekannt,
            k_1.r_n,
            k_1.r_basis,
            k_1.a_klein,
            k_1.a_klein_bekannt,
            k_1.klein_n,
            k_1.klein_basis,
            k_1.a_gross,
            k_1.a_gross_bekannt,
            k_1.gross_n,
            k_1.gross_basis,
            k_1.a_fax,
            k_1.a_fax_bekannt,
            k_1.fax_n,
            k_1.fax_basis,
            k_1.a_klein / n.f AS a_klein_n,
            k_1.a_gross / n.f AS a_gross_n
           FROM koeff k_1
             CROSS JOIN LATERAL ( SELECT GREATEST(COALESCE(k_1.a_klein, 0::numeric) + COALESCE(k_1.a_gross, 0::numeric), 1::numeric) AS f) n
        ), roh AS (
         SELECT k_1.charge_nr,
            'ausgelagert'::text AS portion,
            l.kohorte,
            l.masse_kg AS geliefert_kg,
            COALESCE(l.alter_tage, 0::numeric) AS alter_tage,
            NULL::numeric AS eingang_kohorte_kg,
            l.n_lieferungen
           FROM koeff_norm k_1
             JOIN lieferungen l ON l.charge_nr = k_1.charge_nr
        UNION ALL
         SELECT k_1.charge_nr,
            'entsorgt'::text AS text,
            e.kohorte,
            e.masse_kg,
            COALESCE(e.alter_tage, 0::numeric) AS "coalesce",
            NULL::numeric AS "numeric",
            e.n_lieferungen
           FROM koeff_norm k_1
             JOIN entsorgt_lief e ON e.charge_nr = k_1.charge_nr
        UNION ALL
         SELECT k_1.charge_nr,
            'lager'::text AS text,
            c.eingangsdatum,
            NULL::numeric AS "numeric",
            GREATEST((k_1.stichtag - c.eingangsdatum)::numeric, 0::numeric) AS "greatest",
            c.eingang_kg,
            0
           FROM koeff_norm k_1
             JOIN kohorten c ON c.charge_nr = k_1.charge_nr
        ), teile AS (
         SELECT k_1.charge_nr,
            k_1.sorte,
            k_1.schlag,
            k_1.eingang_kg,
            k_1.stichtag,
            k_1.r,
            k_1.r_bekannt,
            k_1.r_n,
            k_1.r_basis,
            k_1.a_klein,
            k_1.a_klein_bekannt,
            k_1.klein_n,
            k_1.klein_basis,
            k_1.a_gross,
            k_1.a_gross_bekannt,
            k_1.gross_n,
            k_1.gross_basis,
            k_1.a_fax,
            k_1.a_fax_bekannt,
            k_1.fax_n,
            k_1.fax_basis,
            k_1.a_klein_n,
            k_1.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            ln(GREATEST(t.alter_tage, 1::numeric)) - COALESCE(m.x_mittel, 0::numeric) AS u,
                CASE
                    WHEN m.brauchbar THEN m.ln_lambda_korrigiert + m.k * ln(GREATEST(t.alter_tage, 1::numeric))
                    ELSE NULL::numeric
                END AS eta,
            m.brauchbar AS modell_gilt,
            m.brauchbar AND t.alter_tage > m.t_max AS f_extrapoliert,
                CASE
                    WHEN m.brauchbar THEN m.c_chargen
                    ELSE s.n
                END AS f_n,
            s.anteil_mono AS f_treppe,
            m.brauchbar OR (( SELECT count(*) AS count
                   FROM kurve)) > 0 AS f_bekannt,
                CASE
                    WHEN m.brauchbar THEN COALESCE(m.sockel, 0::numeric)
                    ELSE 0::numeric
                END AS a0,
            m.brauchbar AS a0_bekannt,
                CASE
                    WHEN m.brauchbar THEN COALESCE(m.sockel_var, 0::numeric)
                    ELSE 0::numeric
                END AS a0_var
           FROM koeff_norm k_1
             JOIN roh t ON t.charge_nr = k_1.charge_nr
             CROSS JOIN modell m
             LEFT JOIN LATERAL ( SELECT c.anteil_mono,
                    c.n
                   FROM kurve c
                  WHERE c.von::numeric <= t.alter_tage
                  ORDER BY c.von DESC
                 LIMIT 1) s ON true
        ), mit_f AS (
         SELECT t.charge_nr,
            t.sorte,
            t.schlag,
            t.eingang_kg,
            t.stichtag,
            t.r,
            t.r_bekannt,
            t.r_n,
            t.r_basis,
            t.a_klein,
            t.a_klein_bekannt,
            t.klein_n,
            t.klein_basis,
            t.a_gross,
            t.a_gross_bekannt,
            t.gross_n,
            t.gross_basis,
            t.a_fax,
            t.a_fax_bekannt,
            t.fax_n,
            t.fax_basis,
            t.a_klein_n,
            t.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            t.u,
            t.eta,
            t.modell_gilt,
            t.f_extrapoliert,
            t.f_n,
            t.f_treppe,
            t.f_bekannt,
            t.a0,
            t.a0_bekannt,
            t.a0_var,
                CASE
                    WHEN t.modell_gilt THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(t.eta, '-40'::integer::numeric), 3::numeric))), 0::numeric), 1::numeric)
                    ELSE LEAST(GREATEST(COALESCE(t.f_treppe, 0::numeric), 0::numeric), 1::numeric)
                END AS f
           FROM teile t
        ), anteil AS (
         SELECT x.charge_nr,
            x.sorte,
            x.schlag,
            x.eingang_kg,
            x.stichtag,
            x.r,
            x.r_bekannt,
            x.r_n,
            x.r_basis,
            x.a_klein,
            x.a_klein_bekannt,
            x.klein_n,
            x.klein_basis,
            x.a_gross,
            x.a_gross_bekannt,
            x.gross_n,
            x.gross_basis,
            x.a_fax,
            x.a_fax_bekannt,
            x.fax_n,
            x.fax_basis,
            x.a_klein_n,
            x.a_gross_n,
            x.portion,
            x.kohorte,
            x.geliefert_kg,
            x.alter_tage,
            x.eingang_kohorte_kg,
            x.n_lieferungen,
            x.u,
            x.eta,
            x.modell_gilt,
            x.f_extrapoliert,
            x.f_n,
            x.f_treppe,
            x.f_bekannt,
            x.a0,
            x.a0_bekannt,
            x.a0_var,
            x.f,
            GREATEST(power(1::numeric - x.r, x.alter_tage) * (1::numeric - x.a0) * (1::numeric - x.f) * (1::numeric - x.a_klein_n - x.a_gross_n) * (1::numeric - x.a_fax), 0.25) AS verkaufsfaehig_anteil,
            GREATEST(power(1::numeric - x.r, x.alter_tage), 0.25) AS verdunstungs_anteil
           FROM mit_f x
        ), ausgelagert AS (
         SELECT a.charge_nr,
            a.sorte,
            a.schlag,
            a.eingang_kg,
            a.stichtag,
            a.r,
            a.r_bekannt,
            a.r_n,
            a.r_basis,
            a.a_klein,
            a.a_klein_bekannt,
            a.klein_n,
            a.klein_basis,
            a.a_gross,
            a.a_gross_bekannt,
            a.gross_n,
            a.gross_basis,
            a.a_fax,
            a.a_fax_bekannt,
            a.fax_n,
            a.fax_basis,
            a.a_klein_n,
            a.a_gross_n,
            a.portion,
            a.kohorte,
            a.geliefert_kg,
            a.alter_tage,
            a.eingang_kohorte_kg,
            a.n_lieferungen,
            a.u,
            a.eta,
            a.modell_gilt,
            a.f_extrapoliert,
            a.f_n,
            a.f_treppe,
            a.f_bekannt,
            a.a0,
            a.a0_bekannt,
            a.a0_var,
            a.f,
            a.verkaufsfaehig_anteil,
            a.verdunstungs_anteil,
                CASE
                    WHEN a.portion = 'entsorgt'::text THEN a.geliefert_kg / a.verdunstungs_anteil
                    ELSE a.geliefert_kg / a.verkaufsfaehig_anteil
                END AS m0,
            0::numeric AS ueberzaehlung_kg
           FROM anteil a
          WHERE a.portion = ANY (ARRAY['ausgelagert'::text, 'entsorgt'::text])
        ), lager AS (
         SELECT a.charge_nr,
            a.sorte,
            a.schlag,
            a.eingang_kg,
            a.stichtag,
            a.r,
            a.r_bekannt,
            a.r_n,
            a.r_basis,
            a.a_klein,
            a.a_klein_bekannt,
            a.klein_n,
            a.klein_basis,
            a.a_gross,
            a.a_gross_bekannt,
            a.gross_n,
            a.gross_basis,
            a.a_fax,
            a.a_fax_bekannt,
            a.fax_n,
            a.fax_basis,
            a.a_klein_n,
            a.a_gross_n,
            a.portion,
            a.kohorte,
            a.geliefert_kg,
            a.alter_tage,
            a.eingang_kohorte_kg,
            a.n_lieferungen,
            a.u,
            a.eta,
            a.modell_gilt,
            a.f_extrapoliert,
            a.f_n,
            a.f_treppe,
            a.f_bekannt,
            a.a0,
            a.a0_bekannt,
            a.a0_var,
            a.f,
            a.verkaufsfaehig_anteil,
            a.verdunstungs_anteil,
            GREATEST(a.eingang_kohorte_kg - COALESCE(x.m0, 0::numeric), 0::numeric) AS m0,
            GREATEST(COALESCE(x.m0, 0::numeric) - a.eingang_kohorte_kg, 0::numeric) AS ueberzaehlung_kg
           FROM anteil a
             LEFT JOIN ( SELECT ausgelagert.charge_nr,
                    ausgelagert.kohorte,
                    sum(ausgelagert.m0) AS m0
                   FROM ausgelagert
                  GROUP BY ausgelagert.charge_nr, ausgelagert.kohorte) x ON x.charge_nr = a.charge_nr AND x.kohorte = a.kohorte
          WHERE a.portion = 'lager'::text
        ), alle AS (
         SELECT ausgelagert.charge_nr,
            ausgelagert.sorte,
            ausgelagert.schlag,
            ausgelagert.eingang_kg,
            ausgelagert.stichtag,
            ausgelagert.r,
            ausgelagert.r_bekannt,
            ausgelagert.r_n,
            ausgelagert.r_basis,
            ausgelagert.a_klein,
            ausgelagert.a_klein_bekannt,
            ausgelagert.klein_n,
            ausgelagert.klein_basis,
            ausgelagert.a_gross,
            ausgelagert.a_gross_bekannt,
            ausgelagert.gross_n,
            ausgelagert.gross_basis,
            ausgelagert.a_fax,
            ausgelagert.a_fax_bekannt,
            ausgelagert.fax_n,
            ausgelagert.fax_basis,
            ausgelagert.a_klein_n,
            ausgelagert.a_gross_n,
            ausgelagert.portion,
            ausgelagert.kohorte,
            ausgelagert.geliefert_kg,
            ausgelagert.alter_tage,
            ausgelagert.eingang_kohorte_kg,
            ausgelagert.n_lieferungen,
            ausgelagert.u,
            ausgelagert.eta,
            ausgelagert.modell_gilt,
            ausgelagert.f_extrapoliert,
            ausgelagert.f_n,
            ausgelagert.f_treppe,
            ausgelagert.f_bekannt,
            ausgelagert.a0,
            ausgelagert.a0_bekannt,
            ausgelagert.a0_var,
            ausgelagert.f,
            ausgelagert.verkaufsfaehig_anteil,
            ausgelagert.verdunstungs_anteil,
            ausgelagert.m0,
            ausgelagert.ueberzaehlung_kg
           FROM ausgelagert
        UNION ALL
         SELECT lager.charge_nr,
            lager.sorte,
            lager.schlag,
            lager.eingang_kg,
            lager.stichtag,
            lager.r,
            lager.r_bekannt,
            lager.r_n,
            lager.r_basis,
            lager.a_klein,
            lager.a_klein_bekannt,
            lager.klein_n,
            lager.klein_basis,
            lager.a_gross,
            lager.a_gross_bekannt,
            lager.gross_n,
            lager.gross_basis,
            lager.a_fax,
            lager.a_fax_bekannt,
            lager.fax_n,
            lager.fax_basis,
            lager.a_klein_n,
            lager.a_gross_n,
            lager.portion,
            lager.kohorte,
            lager.geliefert_kg,
            lager.alter_tage,
            lager.eingang_kohorte_kg,
            lager.n_lieferungen,
            lager.u,
            lager.eta,
            lager.modell_gilt,
            lager.f_extrapoliert,
            lager.f_n,
            lager.f_treppe,
            lager.f_bekannt,
            lager.a0,
            lager.a0_bekannt,
            lager.a0_var,
            lager.f,
            lager.verkaufsfaehig_anteil,
            lager.verdunstungs_anteil,
            lager.m0,
            lager.ueberzaehlung_kg
           FROM lager
        ), kaskade AS (
         SELECT t.charge_nr,
            t.sorte,
            t.schlag,
            t.eingang_kg,
            t.stichtag,
            t.r,
            t.r_bekannt,
            t.r_n,
            t.r_basis,
            t.a_klein,
            t.a_klein_bekannt,
            t.klein_n,
            t.klein_basis,
            t.a_gross,
            t.a_gross_bekannt,
            t.gross_n,
            t.gross_basis,
            t.a_fax,
            t.a_fax_bekannt,
            t.fax_n,
            t.fax_basis,
            t.a_klein_n,
            t.a_gross_n,
            t.portion,
            t.kohorte,
            t.geliefert_kg,
            t.alter_tage,
            t.eingang_kohorte_kg,
            t.n_lieferungen,
            t.u,
            t.eta,
            t.modell_gilt,
            t.f_extrapoliert,
            t.f_n,
            t.f_treppe,
            t.f_bekannt,
            t.a0,
            t.a0_bekannt,
            t.a0_var,
            t.f,
            t.verkaufsfaehig_anteil,
            t.m0,
            t.ueberzaehlung_kg,
            t.m0 * power(1::numeric - t.r, t.alter_tage) AS m1,
            (- t.m0) * t.alter_tage * power(1::numeric - t.r, GREATEST(t.alter_tage - 1::numeric, 0::numeric)) AS d_m1_r,
                CASE
                    WHEN t.modell_gilt THEN (1::numeric - t.f) * exp(LEAST(GREATEST(t.eta, '-40'::integer::numeric), 3::numeric))
                    ELSE 0::numeric
                END AS d_f_eta
           FROM alle t
          WHERE t.m0 > 0::numeric OR t.ueberzaehlung_kg > 0::numeric
        )
 SELECT charge_nr,
    sorte,
    schlag,
    portion,
    alter_tage,
    eingang_kg,
    m0,
    m1,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - a0) * (1::numeric - f)
        END AS m2,
    r,
    f,
    a0,
    a_klein_n,
    a_gross_n,
    a_fax,
    u,
    d_m1_r,
    d_f_eta,
    modell_gilt,
    f_extrapoliert,
    r_n,
    r_basis,
    klein_n,
    klein_basis,
    gross_n,
    gross_basis,
    f_n,
    fax_n,
    fax_basis,
    r_bekannt,
    f_bekannt,
    a_klein_bekannt,
    a_gross_bekannt,
    a0_bekannt,
    a0_var,
    a_fax_bekannt,
    m0 - m1 AS verdunstung_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * a0
        END AS sockel_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN m1
            ELSE m1 * (1::numeric - a0) * f
        END AS schimmel_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - a0) * (1::numeric - f) * a_klein_n
        END AS klein_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - a0) * (1::numeric - f) * a_gross_n
        END AS nebenkanal_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - a0) * (1::numeric - f) * (1::numeric - a_klein_n - a_gross_n) * a_fax
        END AS fax_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE m1 * (1::numeric - a0) * (1::numeric - f) * (1::numeric - a_klein_n - a_gross_n) * (1::numeric - a_fax)
        END AS verkaufsfaehig_kg,
    kohorte,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0::numeric
            ELSE geliefert_kg
        END AS geliefert_kg,
    ueberzaehlung_kg,
        CASE
            WHEN portion = 'entsorgt'::text THEN 0
            ELSE n_lieferungen
        END AS n_lieferungen,
    verkaufsfaehig_anteil
   FROM kaskade k;
