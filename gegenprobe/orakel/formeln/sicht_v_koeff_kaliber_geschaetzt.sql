-- sicht: v_koeff_kaliber_geschaetzt
-- Massegewichteter Anteil je Sorte, chargen-robust gefehlert und per empirischem Bayes zum Gesamtwert gezogen. b = 1 heisst: die Sorte trägt sich selbst, b = 0: es gilt der Gesamtwert.

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
