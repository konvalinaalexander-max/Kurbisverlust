-- sicht: v_ausgang_pruef
-- Kürbis-Positionen, deren übernommene Lieferungen nicht die Masse der Datei ergeben. Leer ist der Normalfall; jede Zeile hier ist ein Kilo zu viel oder zu wenig. Eine vergessene Position steht hier mit ihrer vollen Masse.

 WITH urteil AS (
         SELECT v_ausgang_artikel_vorschlag.artikel_id,
            v_ausgang_artikel_vorschlag.artikel,
            COALESCE(v_ausgang_artikel_vorschlag.bestaetigt_kuerbis, v_ausgang_artikel_vorschlag.vorschlag_kuerbis) AS kuerbis
           FROM v_ausgang_artikel_vorschlag
        ), pos AS (
         SELECT DISTINCT ON (z.quelle, z.pos_id) z.quelle,
            z.pos_id,
            z.datum,
            z.artikel_id,
            z.artikel,
            z.kunde,
            z.kg_position
           FROM ausgang_zeile z
          ORDER BY z.quelle, z.pos_id, z.lauf_nr
        ), geliefert AS (
         SELECT i.quelle,
            NULLIF(split_part(i.extern_id, ':'::text, 2), ''::text)::bigint AS pos_id,
            sum(l.kg) AS kg
           FROM lieferung_import i
             JOIN lieferung l ON l.id = i.lieferung_id
          GROUP BY i.quelle, (NULLIF(split_part(i.extern_id, ':'::text, 2), ''::text)::bigint)
        )
 SELECT p.quelle,
    p.pos_id,
    p.datum,
    p.artikel,
    p.kunde,
    zahl(p.kg_position, 2, '1000000000000'::numeric)::numeric(14,2) AS kg_datei,
    zahl(COALESCE(g.kg, 0::numeric), 2, '1000000000000'::numeric)::numeric(14,2) AS kg_lieferung,
    zahl(COALESCE(g.kg, 0::numeric) - p.kg_position, 2, '1000000000000'::numeric)::numeric(14,2) AS abweichung_kg
   FROM pos p
     JOIN urteil u ON u.artikel_id = p.artikel_id AND u.artikel = p.artikel AND u.kuerbis
     LEFT JOIN geliefert g ON g.quelle = p.quelle AND g.pos_id = p.pos_id
  WHERE abs(COALESCE(g.kg, 0::numeric) - p.kg_position) > 0.05 AND p.kg_position > 0::numeric;
