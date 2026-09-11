-- sicht: v_schimmel_kurve
-- Die gemessenen Schimmelanteile nach Altersklassen: je Klasse Mittelwert, Streuung und Bereich. anteil_mono ist derselbe Wert monoton gemacht — Kürbisse werden mit der Zeit nicht wieder gesund.

 WITH klassen(von, bis) AS (
         VALUES (0,14), (15,30), (31,60), (61,90), (91,120), (121,180), (181,100000)
        ), je_klasse AS (
         SELECT k.von,
            k.bis,
            count(b.anteil)::integer AS n,
            sum(b.schimmel_kg) / NULLIF(sum(b.basis_jetzt_kg), 0::numeric) AS anteil,
            stddev_samp(b.anteil) AS sd
           FROM klassen k
             LEFT JOIN mv_schimmel_punkte b ON b.lagertage >= k.von::numeric AND b.lagertage <= k.bis::numeric AND b.anteil IS NOT NULL AND b.plausibel AND (b.quelle = ANY (ARRAY['verarbeitung'::text, 'lager'::text]))
          GROUP BY k.von, k.bis
        )
 SELECT von,
    bis,
    n,
    anteil,
    sd,
    LEAST(GREATEST(max(anteil) OVER (ORDER BY von ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0::numeric), 1::numeric) AS anteil_mono,
        CASE
            WHEN n >= 2 THEN GREATEST(anteil::double precision - (1.96 * sd)::double precision / sqrt(n::double precision), 0::double precision)
            ELSE NULL::double precision
        END AS unten,
        CASE
            WHEN n >= 2 THEN LEAST(anteil::double precision + (1.96 * sd)::double precision / sqrt(n::double precision), 1::double precision)
            ELSE NULL::double precision
        END AS oben
   FROM je_klasse;
