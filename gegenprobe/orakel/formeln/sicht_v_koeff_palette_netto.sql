-- sicht: v_koeff_palette_netto
-- Nettomasse einer fertigen Palette je Sorte und Kistensystem (kistensystem NULL: alle Systeme der Sorte). Daraus die Masse einer Fax-Arbeit: Paletten × Netto (0060).

 SELECT sorte,
    kistensystem,
    count(*)::integer AS n,
    zahl(avg(netto_kg), 2, '100000000'::numeric)::numeric(10,2) AS netto_kg,
    zahl(stddev_samp(netto_kg), 2, '100000000'::numeric)::numeric(10,2) AS sd,
    zahl(avg(kisten), 1, '1000000'::numeric)::numeric(8,1) AS kisten
   FROM v_ausgang_kennzahl k
  GROUP BY GROUPING SETS ((sorte, kistensystem), (sorte));
