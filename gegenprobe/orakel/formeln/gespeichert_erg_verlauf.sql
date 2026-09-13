-- gespeichert: erg_verlauf

 WITH tag AS MATERIALIZED (
         SELECT heute() AS heute,
            stichtag() AS stichtag
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
        ), kurve AS MATERIALIZED (
         SELECT v_schimmel_kurve.von,
            v_schimmel_kurve.anteil_mono
           FROM v_schimmel_kurve
          WHERE v_schimmel_kurve.n > 0
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
        ), portionen AS MATERIALIZED (
         SELECT k.charge_nr,
            k.portion,
            k.kohorte,
            k.m0,
            k.r,
            k.a0,
            k.a_klein_n,
            k.a_gross_n,
            k.a_fax,
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
        ), f_je_tag AS MATERIALIZED (
         SELECT gs.t,
                CASE
                    WHEN gs.t <= 0 THEN 0::numeric
                    WHEN m.brauchbar THEN LEAST(GREATEST(1::numeric - exp(- exp(LEAST(GREATEST(m.ln_lambda_korrigiert + m.k * ln(GREATEST(gs.t::numeric, 1::numeric)), '-40'::integer::numeric), 3::numeric))), 0::numeric), 1::numeric)
                    ELSE LEAST(GREATEST(COALESCE(( SELECT c.anteil_mono
                       FROM kurve c
                      WHERE c.von <= gs.t
                      ORDER BY c.von DESC
                     LIMIT 1), 0::numeric), 0::numeric), 1::numeric)
                END AS f
           FROM generate_series(0, GREATEST(COALESCE((( SELECT max(w_1.bis) AS max
                   FROM wochen w_1)) - (( SELECT min(p.kohorte) AS min
                   FROM portionen p)), 0), 0)) gs(t)
             CROSS JOIN modell m
        ), je_woche AS (
         SELECT w_1.woche,
            w_1.bis,
            p.charge_nr,
            p.m0 * (1::numeric - power(1::numeric - p.r, x.t::numeric)) AS verdunstung_kg,
            p.m0 * power(1::numeric - p.r, x.t::numeric) * p.a0 AS sockel_kg,
            p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0) * f.f AS schimmel_kg,
                CASE
                    WHEN p.liefertag IS NOT NULL AND p.liefertag <= w_1.bis THEN p.fax_kg
                    ELSE 0::numeric
                END AS fax_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0
                    ELSE 0::numeric
                END AS lager_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0) * (1::numeric - f.f)
                    ELSE 0::numeric
                END AS gute_ware_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0) * (1::numeric - f.f) * (p.a_klein_n + p.a_gross_n)
                    ELSE 0::numeric
                END AS kanal_lager_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0) * (1::numeric - f.f) * (1::numeric - p.a_klein_n - p.a_gross_n) * p.a_fax
                    ELSE 0::numeric
                END AS fax_lager_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0) * (1::numeric - f.f) * (1::numeric - p.a_klein_n - p.a_gross_n) * (1::numeric - p.a_fax)
                    ELSE 0::numeric
                END AS verkaufsfaehig_kg
           FROM wochen w_1
             JOIN portionen p ON p.kohorte <= w_1.bis
             CROSS JOIN LATERAL ( SELECT GREATEST(LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - p.kohorte, 0) AS t) x
             JOIN f_je_tag f ON f.t = x.t
        ), je_charge AS MATERIALIZED (
         SELECT je_woche.woche,
            je_woche.bis,
            je_woche.charge_nr,
            sum(je_woche.verdunstung_kg) AS verdunstung_kg,
            sum(je_woche.sockel_kg) AS sockel_kg,
            sum(je_woche.schimmel_kg) AS schimmel_kg,
            sum(je_woche.fax_kg) AS fax_kg,
            sum(je_woche.gute_ware_kg) AS im_haus_kg,
            sum(je_woche.lager_kg) AS lager_kg,
            sum(je_woche.kanal_lager_kg) AS kanal_kg,
            sum(je_woche.fax_lager_kg) AS fax_lager_kg,
            sum(je_woche.verkaufsfaehig_kg) AS verkaufsfaehig_kg
           FROM je_woche
          GROUP BY je_woche.woche, je_woche.bis, je_woche.charge_nr
        ), verlust AS (
         SELECT j.woche,
            j.bis,
            g.gruppe,
            g.schluessel,
            sum(j.verdunstung_kg) AS verdunstung_kg,
            sum(j.sockel_kg) AS sockel_kg,
            sum(j.schimmel_kg) AS schimmel_kg,
            sum(j.fax_kg) AS fax_kg,
            sum(j.im_haus_kg) AS im_haus_kg,
            sum(j.lager_kg) AS lager_kg,
            sum(j.kanal_kg) AS kanal_kg,
            sum(j.fax_lager_kg) AS fax_lager_kg,
            sum(j.verkaufsfaehig_kg) AS verkaufsfaehig_kg
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
    zahl(COALESCE(v.sockel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS sockel_kum_kg,
    zahl(COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric) + COALESCE(v.schimmel_kg, 0::numeric) + COALESCE(v.sockel_kg, 0::numeric) + COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_kum_kg,
    zahl(COALESCE(v.im_haus_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_kg,
    zahl(COALESCE(v.lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    zahl(COALESCE(v.verkaufsfaehig_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verkaufsfaehig_kg,
    zahl(COALESCE(v.kanal_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS kanal_kg,
    zahl(COALESCE(v.fax_lager_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_lager_kg
   FROM wochen w
     CROSS JOIN liste s
     CROSS JOIN tag d
     LEFT JOIN verlust v ON v.bis = w.bis AND v.gruppe = s.gruppe AND v.schluessel = s.schluessel
     LEFT JOIN eingang e ON e.bis = w.bis AND e.gruppe = s.gruppe AND e.schluessel = s.schluessel
     LEFT JOIN ausgang a ON a.bis = w.bis AND a.gruppe = s.gruppe AND a.schluessel = s.schluessel;
