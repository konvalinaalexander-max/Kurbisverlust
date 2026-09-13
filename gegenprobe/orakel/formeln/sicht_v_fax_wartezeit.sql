-- sicht: v_fax_wartezeit
-- Faules beim Abpacken nach Tagen zwischen Waschen und Fax — je Klasse (0–1 Tage, 2–3 Tage, 4 und mehr, unbekannt), einmal über alle Sorten und einmal je Sorte. Der Anteil ist massegewichtet (Faules ÷ durchgegangene Masse + Faules), der Bereich aus der Streuung zwischen den Arbeiten. Grundlage: auftrag.tage_seit_waschen, freiwillig seit 0060 (0071).

 WITH roh AS (
         SELECT
                CASE
                    WHEN f.tage_seit_waschen IS NULL THEN 'unbekannt'::text
                    WHEN f.tage_seit_waschen <= 1 THEN '0–1 Tage'::text
                    WHEN f.tage_seit_waschen <= 3 THEN '2–3 Tage'::text
                    ELSE '4 und mehr'::text
                END AS klasse,
            f.sorte,
            f.masse_kg,
            f.faul_kg,
            f.anteil
           FROM v_fax_beobachtung f
          WHERE f.status = 'abgeschlossen'::auftrag_status AND f.masse_kg IS NOT NULL
        ), je AS (
         SELECT g.gruppe,
                CASE
                    WHEN g.gruppe = 'sorte'::text THEN roh.sorte
                    ELSE NULL::text
                END AS sorte,
            roh.klasse,
            count(*)::integer AS n,
            sum(roh.masse_kg) AS masse_kg,
            sum(roh.faul_kg) AS faul_kg,
            sum(roh.faul_kg) / NULLIF(sum(roh.masse_kg + roh.faul_kg), 0::numeric) AS anteil,
            stddev_samp(roh.anteil) AS sd
           FROM roh
             CROSS JOIN LATERAL ( SELECT unnest(ARRAY['alle'::text, 'sorte'::text]) AS gruppe) g
          GROUP BY g.gruppe, (
                CASE
                    WHEN g.gruppe = 'sorte'::text THEN roh.sorte
                    ELSE NULL::text
                END), roh.klasse
        )
 SELECT gruppe,
    sorte,
    klasse,
        CASE klasse
            WHEN '0–1 Tage'::text THEN 1
            WHEN '2–3 Tage'::text THEN 2
            WHEN '4 und mehr'::text THEN 3
            ELSE 4
        END AS reihenfolge,
    n,
    zahl(masse_kg, 1, '100000000000'::numeric)::numeric(12,1) AS masse_kg,
    zahl(faul_kg, 1, '100000000000'::numeric)::numeric(12,1) AS faul_kg,
    zahl(anteil, 5, '100000'::numeric)::numeric(10,5) AS anteil,
        CASE
            WHEN n >= 2 AND sd IS NOT NULL THEN zahl(GREATEST(anteil::double precision - (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision), 0::double precision), 5, '100000'::numeric)::numeric(10,5)
            ELSE zahl(anteil, 5, '100000'::numeric)::numeric(10,5)
        END AS unten,
        CASE
            WHEN n >= 2 AND sd IS NOT NULL THEN zahl(LEAST(anteil::double precision + (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision), 1::double precision), 5, '100000'::numeric)::numeric(10,5)
            ELSE zahl(anteil, 5, '100000'::numeric)::numeric(10,5)
        END AS oben
   FROM je;
