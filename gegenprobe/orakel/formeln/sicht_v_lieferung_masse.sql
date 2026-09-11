-- sicht: v_lieferung_masse
-- Lieferungen in Kilo. Kistenangaben werden über das gemessene Kilo je Kiste umgerechnet; masse_fehler_kg sagt, wie unsicher diese Umrechnung ist.

 WITH kiste AS (
         SELECT avg(v_ausgang_kennzahl.kg_pro_kiste) AS mittel,
            stddev_samp(v_ausgang_kennzahl.kg_pro_kiste) AS sd,
            count(*)::integer AS n
           FROM v_ausgang_kennzahl
          WHERE v_ausgang_kennzahl.kg_pro_kiste IS NOT NULL
        )
 SELECT l.id,
    l.datum,
    l.charge_nr,
    l.sorte,
    l.kg,
    l.kisten,
    l.gebindeart,
    l.ziel,
    l.kunde,
    l.erfasser,
    l.ts,
    l.bemerkung,
    z.name AS ziel_name,
    z.buch,
    COALESCE(l.kg, l.kisten::numeric * k.mittel) AS masse_kg,
        CASE
            WHEN l.kg IS NOT NULL THEN 'gewogen'::text
            WHEN k.n > 0 THEN 'aus Kisten hochgerechnet'::text
            ELSE 'Kistengewicht unbekannt'::text
        END AS masse_quelle,
        CASE
            WHEN l.kg IS NOT NULL THEN 0::double precision
            WHEN k.n >= 2 THEN (l.kisten::numeric * t_quantil_95(k.n - 1) * k.sd)::double precision / sqrt(k.n::double precision)
            ELSE NULL::double precision
        END AS masse_fehler_kg,
    k.n AS kisten_n
   FROM lieferung l
     JOIN ausgang_ziel z ON z.code = l.ziel
     CROSS JOIN kiste k;
