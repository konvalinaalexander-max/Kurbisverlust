-- sicht: v_naechste_charge
-- Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag ab heute() gerechnet und je Charge summiert; der Bestand aus erg_charge (0061). prognose_verlust_14_kg ist Verdunstung + Verderb der nächsten 14 Tage — reine Prognose, nicht im Verlust bis heute enthalten, und leer, wo das Modell nicht gilt. Sockel und Fax stecken nicht darin (0062).

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
           FROM erg_charge b
             LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b.sorte
             CROSS JOIN LATERAL ( SELECT b.lager_kg * c.anteil AS m0,
                    GREATEST((heute() - c.eingangsdatum)::numeric, 0::numeric) AS alter_tage
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
    zahl(lager_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS lager_kg,
    round(alter_tage)::integer AS alter_tage,
    zahl(masse_jetzt_kg, 2, '1000000000000'::numeric)::numeric(14,2) AS masse_jetzt_kg,
    zahl(verdunstung_14_kg, 1, '100000000000'::numeric)::numeric(12,1) AS verdunstung_14_kg,
    zahl(schimmel_14_kg, 1, '100000000000'::numeric)::numeric(12,1) AS schimmel_14_kg,
    zahl(verdunstung_14_kg + schimmel_14_kg, 1, '100000000000'::numeric)::numeric(12,1) AS prognose_verlust_14_kg,
    hochgerechnet,
    modell_gilt,
    round(alter_von)::integer AS alter_von,
    round(alter_bis)::integer AS alter_bis,
    n_kohorten
   FROM je_charge
  ORDER BY (zahl(verdunstung_14_kg + COALESCE(schimmel_14_kg, 0::numeric), 1, '100000000000'::numeric)::numeric(12,1)) DESC NULLS LAST;
