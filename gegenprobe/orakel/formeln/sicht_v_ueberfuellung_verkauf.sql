-- sicht: v_ueberfuellung_verkauf
-- Je Sorte (gruppe sorte) und je Charge (gruppe charge), je Kistensystem: verkaufte Kisten und Kilo aus der Verkaufsdatei, gewogene Kisten und Kilo je Kiste aus den fertigen Paletten. verschenkt_kg = Überschuss je gewogener Kiste × verkaufte Kisten, nur bei „Kiste ab x kg" und nur, wo beides gemessen ist. Stück-Kisten: gemessenes Stückgewicht neben dem Nenngewicht, keine Marge (0061).

 WITH verkauft AS (
         SELECT
                CASE
                    WHEN GROUPING(v_1.charge_nr) = 1 THEN 'sorte'::text
                    ELSE 'charge'::text
                END AS gruppe,
            v_1.sorte,
            v_1.charge_nr,
            v_1.kistensystem,
            v_1.soll_kg_pro_kiste,
            v_1.stueck_je_kiste,
            v_1.kaliber_idx,
            count(*)::integer AS n_lieferungen,
            sum(v_1.kg) AS kg_verkauft,
            sum(v_1.kisten) AS kisten_verkauft,
            count(*) FILTER (WHERE v_1.kisten_quelle = 'anteil'::text)::integer AS n_anteilig,
            sum(v_1.stueck) AS stueck_verkauft,
            sum(v_1.stueck * v_1.nenn_g::numeric) / NULLIF(sum(v_1.stueck), 0::numeric) AS nenn_g,
            min(v_1.datum) AS von,
            max(v_1.datum) AS bis
           FROM v_verkauf_lieferung v_1
          WHERE v_1.sorte IS NOT NULL
          GROUP BY GROUPING SETS ((v_1.sorte, v_1.kistensystem, v_1.soll_kg_pro_kiste, v_1.stueck_je_kiste, v_1.kaliber_idx), (v_1.sorte, v_1.charge_nr, v_1.kistensystem, v_1.soll_kg_pro_kiste, v_1.stueck_je_kiste, v_1.kaliber_idx))
        ), gewogen AS (
         SELECT
                CASE
                    WHEN GROUPING(k.charge_nr) = 1 THEN 'sorte'::text
                    ELSE 'charge'::text
                END AS gruppe,
            k.sorte,
            k.charge_nr,
            k.kistensystem,
            k.soll_kg_pro_kiste,
            k.stueck_je_kiste,
                CASE
                    WHEN k.kistensystem = 'stueck'::text THEN k.kaliber_idx
                    ELSE NULL::integer
                END AS kaliber_idx,
            count(*)::integer AS n_wiegungen,
            sum(k.kisten) AS kisten_gewogen,
            sum(k.netto_kg) / NULLIF(sum(k.kisten), 0)::numeric AS kg_je_kiste,
            stddev_samp(k.kg_pro_kiste) AS sd_je_kiste,
            sum(k.ueberfuellung_kg) AS zuviel_gewogen_kg,
            sum(k.netto_kg) / NULLIF(sum(k.kisten * k.stueck_je_kiste), 0)::numeric * 1000::numeric AS g_je_kuerbis,
            max(k.band_mittel_g) AS band_mittel_g
           FROM v_ausgang_kennzahl k
          WHERE (k.kistensystem = ANY (ARRAY['kiste_ab'::text, 'stueck'::text])) AND (k.kistensystem <> 'kiste_ab'::text OR k.soll_kg_pro_kiste IS NOT NULL) AND (k.kistensystem <> 'stueck'::text OR k.stueck_je_kiste IS NOT NULL)
          GROUP BY GROUPING SETS ((k.sorte, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste, (
                CASE
                    WHEN k.kistensystem = 'stueck'::text THEN k.kaliber_idx
                    ELSE NULL::integer
                END)), (k.sorte, k.charge_nr, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste, (
                CASE
                    WHEN k.kistensystem = 'stueck'::text THEN k.kaliber_idx
                    ELSE NULL::integer
                END)))
        ), band AS (
         SELECT DISTINCT ON (s.sorte, i.idx) s.sorte,
            i.idx AS kaliber_idx,
            ((s.kaliber_baender -> i.idx) ->> 0)::integer AS von,
            ((s.kaliber_baender -> i.idx) ->> 1)::integer AS bis
           FROM sortierschema s
             CROSS JOIN LATERAL generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) i(idx)
          WHERE s.art = 'kaliber'::text AND s.kaliber_baender IS NOT NULL AND s.kaeufer IS NULL AND s.gilt_ab <= heute()
          ORDER BY s.sorte, i.idx, s.gilt_ab DESC
        )
 SELECT COALESCE(v.gruppe, g.gruppe) AS gruppe,
    COALESCE(v.sorte, g.sorte) AS sorte,
    COALESCE(v.charge_nr, g.charge_nr) AS charge_nr,
    COALESCE(v.kistensystem, g.kistensystem) AS kistensystem,
    COALESCE(v.soll_kg_pro_kiste, g.soll_kg_pro_kiste) AS soll_kg_pro_kiste,
    COALESCE(v.stueck_je_kiste, g.stueck_je_kiste) AS stueck_je_kiste,
    COALESCE(v.kaliber_idx, g.kaliber_idx) AS kaliber_idx,
    b.von AS band_von_g,
    b.bis AS band_bis_g,
    zahl(v.nenn_g, 0, '1000000'::numeric)::numeric(8,0) AS nenn_g,
    COALESCE(v.n_lieferungen, 0) AS n_lieferungen,
    zahl(v.kg_verkauft, 1, '100000000000'::numeric)::numeric(12,1) AS kg_verkauft,
    zahl(v.kisten_verkauft, 0, '1000000000'::numeric)::numeric(12,0) AS kisten_verkauft,
    COALESCE(v.n_anteilig, 0) AS n_anteilig,
    zahl(v.stueck_verkauft, 0, '1000000000'::numeric)::numeric(12,0) AS stueck_verkauft,
    v.von,
    v.bis,
    COALESCE(g.n_wiegungen, 0) AS n_wiegungen,
    g.kisten_gewogen,
    zahl(g.kg_je_kiste, 3, '10000000'::numeric)::numeric(10,3) AS kg_je_kiste,
    zahl(g.sd_je_kiste, 3, '10000000'::numeric)::numeric(10,3) AS sd_je_kiste,
    zahl(g.kg_je_kiste - g.soll_kg_pro_kiste, 3, '10000000'::numeric)::numeric(10,3) AS zuviel_je_kiste,
    zahl(g.zuviel_gewogen_kg, 1, '100000000000'::numeric)::numeric(12,1) AS zuviel_gewogen_kg,
    zahl(
        CASE
            WHEN g.n_wiegungen > 0 AND v.kisten_verkauft IS NOT NULL AND g.kistensystem = 'kiste_ab'::text THEN GREATEST(g.kg_je_kiste - g.soll_kg_pro_kiste, 0::numeric) * v.kisten_verkauft
            ELSE NULL::numeric
        END, 1, '100000000000'::numeric)::numeric(12,1) AS verschenkt_kg,
    zahl(
        CASE
            WHEN g.n_wiegungen >= 2 AND v.kisten_verkauft IS NOT NULL AND g.kistensystem = 'kiste_ab'::text THEN (t_quantil_95(g.n_wiegungen - 1) * g.sd_je_kiste)::double precision / sqrt(g.n_wiegungen::double precision) * v.kisten_verkauft::double precision
            ELSE NULL::double precision
        END, 1, '100000000000'::numeric)::numeric(12,1) AS verschenkt_fehler_kg,
    zahl(g.g_je_kuerbis, 0, '1000000'::numeric)::numeric(8,0) AS g_je_kuerbis,
    zahl(g.band_mittel_g, 0, '1000000'::numeric)::numeric(8,0) AS band_mittel_g
   FROM verkauft v
     FULL JOIN gewogen g ON g.gruppe = v.gruppe AND g.sorte = v.sorte AND NOT g.charge_nr IS DISTINCT FROM v.charge_nr AND g.kistensystem = v.kistensystem AND NOT g.soll_kg_pro_kiste IS DISTINCT FROM v.soll_kg_pro_kiste AND NOT g.stueck_je_kiste IS DISTINCT FROM v.stueck_je_kiste AND NOT g.kaliber_idx IS DISTINCT FROM v.kaliber_idx
     LEFT JOIN band b ON b.sorte = COALESCE(v.sorte, g.sorte) AND b.kaliber_idx = COALESCE(v.kaliber_idx, g.kaliber_idx);
