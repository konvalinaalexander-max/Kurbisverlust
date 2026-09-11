-- sicht: v_koeff_verdunstung
-- Verdunstungsrate je Tag und Sorte, gepoolt über die verwendbaren Wägungen und bei wenigen eigenen Chargen zum Gesamtwert gezogen. Nie negativ (0056); NULL, solange keine Wägung vorliegt.

 SELECT sk.sorte,
        CASE
            WHEN k.mittel < 0::numeric THEN 0::numeric
            ELSE k.mittel
        END AS mittel,
        CASE
            WHEN COALESCE(k.varianz, 0::numeric) = 0::numeric THEN
            CASE
                WHEN k.mittel < 0::numeric THEN 0::numeric
                ELSE k.mittel
            END
            ELSE GREATEST(k.mittel - k.t * sqrt(k.varianz), 0::numeric)
        END::double precision AS unten,
        CASE
            WHEN COALESCE(k.varianz, 0::numeric) = 0::numeric THEN
            CASE
                WHEN k.mittel < 0::numeric THEN 0::numeric
                ELSE k.mittel
            END
            ELSE GREATEST(k.mittel + k.t * sqrt(k.varianz), 0::numeric)
        END::double precision AS oben,
    COALESCE(k.n, 0) AS n,
        CASE
            WHEN COALESCE(k.n_gesamt, 0) = 0 THEN 'keine Wiegung vorhanden'::text
            WHEN k.b >= 0.67 THEN 'Wiegungen dieser Sorte'::text
            WHEN k.b >= 0.33 THEN 'Wiegungen dieser Sorte, zum Gesamtwert gezogen'::text
            ELSE 'Wiegungen aller Sorten (zu wenige eigene Chargen)'::text
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
           FROM v_koeff_verdunstung_geschaetzt g
          WHERE g.art = 'verdunstung'::text AND NOT g.sorte IS DISTINCT FROM sk.sorte) k ON true;
