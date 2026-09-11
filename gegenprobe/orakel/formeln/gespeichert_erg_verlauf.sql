-- gespeichert: erg_verlauf
-- Je Woche (und je Sorte; sorte NULL = alles), mit einer Stützstelle genau auf heute() (0062): Eingang und Ausgang kumuliert (gemessen, Ausgang: alle Lieferungen), der Verlust kumuliert (gerechnet, bis heute), danach als Prognose bis zum Saisonende (prognose = true). im_haus_kg: je Portion, was nach Verdunstung und Verderb noch da ist, solange sie nicht ausgeliefert ist. schimmel_kum_kg und sockel_kum_kg stehen getrennt: der Sockel war nie faul (0062).

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
            v_schimmel_kurve.anteil_mono
           FROM v_schimmel_kurve
          WHERE v_schimmel_kurve.n > 0
        ), wochen AS MATERIALIZED (
         SELECT x.woche,
            x.bis
           FROM ( SELECT w_1.w::date AS woche,
                    (w_1.w + '6 days'::interval)::date AS bis
                   FROM generate_series(date_trunc('week'::text, COALESCE(( SELECT min(palette.eingangsdatum) AS min
                           FROM palette), heute())::timestamp with time zone)::date::timestamp with time zone, date_trunc('week'::text, stichtag()::timestamp with time zone)::date::timestamp with time zone, '7 days'::interval) w_1(w)
                UNION
                 SELECT date_trunc('week'::text, heute()::timestamp with time zone)::date AS date_trunc,
                    heute() AS heute) x
        ), portionen AS MATERIALIZED (
         SELECT k.charge_nr,
            k.sorte,
            k.portion,
            k.kohorte,
            k.m0,
            k.r,
            k.a0,
            k.modell_gilt,
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
            p.sorte,
            p.m0 * (1::numeric - power(1::numeric - p.r, x.t::numeric)) AS verdunstung_kg,
            p.m0 * power(1::numeric - p.r, x.t::numeric) * p.a0 AS sockel_kg,
            p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0) * f.f AS schimmel_kg,
                CASE
                    WHEN p.liefertag IS NOT NULL AND p.liefertag <= w_1.bis THEN p.fax_kg
                    ELSE 0::numeric
                END AS fax_kg,
                CASE
                    WHEN p.liefertag IS NULL OR p.liefertag > w_1.bis THEN p.m0 * power(1::numeric - p.r, x.t::numeric) * (1::numeric - p.a0 - (1::numeric - p.a0) * f.f)
                    ELSE 0::numeric
                END AS im_haus_kg
           FROM wochen w_1
             JOIN portionen p ON p.kohorte <= w_1.bis
             CROSS JOIN LATERAL ( SELECT GREATEST(LEAST(w_1.bis, COALESCE(p.liefertag, w_1.bis)) - p.kohorte, 0) AS t) x
             JOIN f_je_tag f ON f.t = x.t
        ), verlust AS (
         SELECT je_woche.woche,
            je_woche.bis,
            je_woche.sorte,
            sum(je_woche.verdunstung_kg) AS verdunstung_kg,
            sum(je_woche.sockel_kg) AS sockel_kg,
            sum(je_woche.schimmel_kg) AS schimmel_kg,
            sum(je_woche.fax_kg) AS fax_kg,
            sum(je_woche.im_haus_kg) AS im_haus_kg
           FROM je_woche
          GROUP BY GROUPING SETS ((je_woche.woche, je_woche.bis, je_woche.sorte), (je_woche.woche, je_woche.bis))
        ), eingang AS (
         SELECT w_1.woche,
            w_1.bis,
            p.sorte,
            sum(p.netto_kg) AS kg
           FROM wochen w_1
             JOIN ( SELECT v_1.eingangsdatum,
                    c.sorte,
                    v_1.netto_kg
                   FROM v_palette v_1
                     JOIN charge c ON c.nr = v_1.charge_nr) p ON p.eingangsdatum <= w_1.bis
          GROUP BY GROUPING SETS ((w_1.woche, w_1.bis, p.sorte), (w_1.woche, w_1.bis))
        ), ausgang AS (
         SELECT w_1.woche,
            w_1.bis,
            l.sorte,
            sum(l.masse_kg) AS kg
           FROM wochen w_1
             JOIN ( SELECT l_1.datum,
                    COALESCE(l_1.sorte, c.sorte) AS sorte,
                    l_1.masse_kg
                   FROM v_lieferung_masse l_1
                     LEFT JOIN charge c ON c.nr = l_1.charge_nr
                  WHERE l_1.masse_kg IS NOT NULL
                UNION ALL
                 SELECT COALESCE(( SELECT NULLIF(einstellung.wert #>> '{}'::text[], ''::text)::date AS "nullif"
                           FROM einstellung
                          WHERE einstellung.schluessel = 'erfassungsbeginn'::text), r.letzter_eingang) AS "coalesce",
                    r.sorte,
                    cv.ausgang_vor_app_kg
                   FROM charge_vorlauf cv
                     JOIN v_charge_rueckgrat r ON r.charge_nr = cv.charge_nr
                  WHERE cv.ausgang_vor_app_kg > 0::numeric) l ON l.datum <= w_1.bis
          GROUP BY GROUPING SETS ((w_1.woche, w_1.bis, l.sorte), (w_1.woche, w_1.bis))
        )
 SELECT w.woche,
    w.bis,
    w.bis > heute() AS prognose,
    s.sorte,
    zahl(COALESCE(e.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS eingang_kum_kg,
    zahl(COALESCE(a.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS ausgang_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verdunstung_kum_kg,
    zahl(COALESCE(v.schimmel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS schimmel_kum_kg,
    zahl(COALESCE(v.sockel_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS sockel_kum_kg,
    zahl(COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS fax_kum_kg,
    zahl(COALESCE(v.verdunstung_kg, 0::numeric) + COALESCE(v.schimmel_kg, 0::numeric) + COALESCE(v.sockel_kg, 0::numeric) + COALESCE(v.fax_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS verlust_kum_kg,
    zahl(COALESCE(v.im_haus_kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS im_haus_kg
   FROM wochen w
     CROSS JOIN ( SELECT DISTINCT verlust.sorte
           FROM verlust) s
     LEFT JOIN verlust v ON v.bis = w.bis AND NOT v.sorte IS DISTINCT FROM s.sorte
     LEFT JOIN eingang e ON e.bis = w.bis AND NOT e.sorte IS DISTINCT FROM s.sorte
     LEFT JOIN ausgang a ON a.bis = w.bis AND NOT a.sorte IS DISTINCT FROM s.sorte;
