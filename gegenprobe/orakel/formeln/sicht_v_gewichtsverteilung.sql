-- sicht: v_gewichtsverteilung
-- Kürbisse je 25-g-Stufe aus den Sortier-CSVs, je Charge (mit Sorte und Schlag). Eine Aussage über den Anbau, nicht über das Lager.

 SELECT c.sorte,
    c.schlag,
    l.charge_nr,
    g.gewicht_g / 25 * 25 AS stufe_g,
    sum(g.anzahl) AS n
   FROM sortier_gewicht g
     JOIN sortier_lauf l ON l.id = g.lauf_id
     JOIN charge c ON c.nr = l.charge_nr
     LEFT JOIN auftrag a ON a.id = l.auftrag_id
  WHERE a.id IS NULL OR a.abgebrochen_ts IS NULL
  GROUP BY c.sorte, c.schlag, l.charge_nr, (g.gewicht_g / 25 * 25);
