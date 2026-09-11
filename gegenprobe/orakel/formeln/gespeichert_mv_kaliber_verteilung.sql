-- gespeichert: mv_kaliber_verteilung
-- v_kaliber_verteilung, gespeichert. Inhaltlich gleich; erneuert von auswertung_schritt(2).

 SELECT l.charge_nr,
    c.sorte,
    g.klasse,
    g.kaliber_idx,
    ((s.kaliber_baender -> g.kaliber_idx) ->> 0)::integer AS band_von,
    ((s.kaliber_baender -> g.kaliber_idx) ->> 1)::integer AS band_bis,
    sum(g.anzahl) AS n_kuerbis,
    (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2) AS masse_kg
   FROM sortier_gewicht g
     JOIN sortier_lauf l ON l.id = g.lauf_id
     JOIN charge c ON c.nr = l.charge_nr
     LEFT JOIN sortierschema s ON s.id = l.sortierschema_id
  GROUP BY l.charge_nr, c.sorte, g.klasse, g.kaliber_idx, (((s.kaliber_baender -> g.kaliber_idx) ->> 0)::integer), (((s.kaliber_baender -> g.kaliber_idx) ->> 1)::integer);
