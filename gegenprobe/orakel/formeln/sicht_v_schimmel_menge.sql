-- sicht: v_schimmel_menge
-- Faules je Arbeit. Palox-Ablesungen werden als Differenz gerechnet, Kistenwägungen als Netto. Eine Arbeit, bei der eine Ablesung unbekannt ist (Stand gefallen), hat hier keine Zeile: ihre Menge ist unbekannt (0060).

 SELECT s.auftrag_id,
    sum(
        CASE
            WHEN s.palox_stand_kg IS NULL THEN s.kg::numeric
            ELSE p.differenz
        END) AS kg,
    count(*)::integer AS n_ablesungen
   FROM schimmel_messung s
     LEFT JOIN v_palox_stand p ON p.id = s.id
  WHERE s.gemessen
  GROUP BY s.auftrag_id
 HAVING bool_and(s.palox_stand_kg IS NULL OR p.differenz IS NOT NULL);
