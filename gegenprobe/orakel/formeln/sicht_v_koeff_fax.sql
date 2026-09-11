-- sicht: v_koeff_fax
-- Anteil Faules beim Abpacken (Fax), je Sorte — bezogen auf die Masse, die durch das Fax ging. NULL, solange keine Fax-Arbeit Faules gewogen hat: unbekannt, nicht 0.

 SELECT sk.sorte,
    k.mittel,
        CASE
            WHEN COALESCE(k.varianz, 0::numeric) = 0::numeric THEN k.mittel
            ELSE GREATEST(k.mittel - k.t * sqrt(k.varianz), 0::numeric)
        END::double precision AS unten,
        CASE
            WHEN COALESCE(k.varianz, 0::numeric) = 0::numeric THEN k.mittel
            ELSE LEAST(k.mittel + k.t * sqrt(k.varianz), 1::numeric)
        END::double precision AS oben,
    COALESCE(k.n, 0) AS n,
        CASE
            WHEN COALESCE(k.n_gesamt, 0) = 0 THEN 'keine Fax-Arbeit mit gewogenem Faulem'::text
            WHEN k.b >= 0.67 THEN 'Fax-Arbeiten dieser Sorte'::text
            WHEN k.b >= 0.33 THEN 'eigene Fax-Arbeiten, zum Gesamtwert gezogen'::text
            ELSE 'alle Sorten (zu wenige eigene Chargen)'::text
        END AS basis
   FROM sorte_kaliber sk
     LEFT JOIN LATERAL ( SELECT g.art,
            g.sorte,
            g.n,
            g.c_chargen,
            g.mittel_roh,
            g.varianz_roh,
            g.mittel_gesamt,
            g.tau2,
            g.b,
            g.mittel,
            g.varianz,
            g.df,
            g.n_gesamt,
            g.varianz_eigen,
            g.gewicht_gesamt,
            g.varianz_gesamt,
            t_quantil_95(g.df) AS t
           FROM v_koeff_kaliber_geschaetzt g
          WHERE g.art = 'fax'::text AND NOT g.sorte IS DISTINCT FROM sk.sorte) k ON true;
