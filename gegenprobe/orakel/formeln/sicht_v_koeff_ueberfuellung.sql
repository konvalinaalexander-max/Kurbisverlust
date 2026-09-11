-- sicht: v_koeff_ueberfuellung
-- Überschuss je Kiste über dem Sollgewicht, aus den Wägungen fertiger Paletten. Gezählt werden nur Wägungen, aus denen sich überhaupt ein Überschuss ergibt — Arbeiten nach Kaliber haben kein Sollgewicht und zählen nicht mit.

 WITH roh AS (
         SELECT k.ueberfuellung_kg AS wert,
            k.kisten AS n_kisten,
            k.ueberfuellung_je_kiste AS je_kiste
           FROM v_ausgang_kennzahl k
          WHERE k.ueberfuellung_je_kiste IS NOT NULL
        ), s AS (
         SELECT count(*)::integer AS n,
            sum(roh.wert) / NULLIF(sum(roh.n_kisten), 0)::numeric AS kg_pro_kiste,
            stddev_samp(roh.je_kiste) AS sd
           FROM roh
        )
 SELECT n,
    zahl(kg_pro_kiste, 3, '10000000'::numeric)::numeric(10,3) AS kg_pro_kiste,
    zahl(sd, 3, '10000000'::numeric)::numeric(10,3) AS sd,
    zahl(
        CASE
            WHEN sd IS NULL OR n < 2 THEN kg_pro_kiste::double precision
            ELSE GREATEST(kg_pro_kiste::double precision - (1.96 * sd)::double precision / sqrt(n::double precision), 0::double precision)
        END, 3, '10000000'::numeric)::numeric(10,3) AS unten,
    zahl(
        CASE
            WHEN sd IS NULL OR n < 2 THEN kg_pro_kiste::double precision
            ELSE kg_pro_kiste::double precision + (1.96 * sd)::double precision / sqrt(n::double precision)
        END, 3, '10000000'::numeric)::numeric(10,3) AS oben
   FROM s;
