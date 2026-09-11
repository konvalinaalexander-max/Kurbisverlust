-- gespeichert: mv_sortier_lauf_masse
-- v_sortier_lauf_masse, gespeichert. Inhaltlich gleich; erneuert von auswertung_schritt(1).

 SELECT l.id AS lauf_id,
    l.charge_nr,
    c.sorte,
    c.schlag,
    l.auftrag_id,
    l.datei_name,
    l.datei_zeit,
    l.zuordnung,
    sum(g.anzahl) AS n_kuerbis,
    (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2) AS masse_kg,
    sum(g.anzahl) FILTER (WHERE g.klasse = 'verlust_klein'::kuerbis_klasse) AS n_klein,
    (sum(g.anzahl::bigint * g.gewicht_g) FILTER (WHERE g.klasse = 'verlust_klein'::kuerbis_klasse) / 1000.0)::numeric(12,2) AS masse_klein_kg,
    sum(g.anzahl) FILTER (WHERE g.klasse = 'nebenkanal'::kuerbis_klasse) AS n_nebenkanal,
    (sum(g.anzahl::bigint * g.gewicht_g) FILTER (WHERE g.klasse = 'nebenkanal'::kuerbis_klasse) / 1000.0)::numeric(12,2) AS masse_nebenkanal_kg,
    sum(g.anzahl) FILTER (WHERE g.klasse = 'kaliber'::kuerbis_klasse) AS n_kaliber,
    (sum(g.anzahl::bigint * g.gewicht_g) FILTER (WHERE g.klasse = 'kaliber'::kuerbis_klasse) / 1000.0)::numeric(12,2) AS masse_kaliber_kg
   FROM sortier_lauf l
     JOIN charge c ON c.nr = l.charge_nr
     JOIN sortier_gewicht g ON g.lauf_id = l.id
  GROUP BY l.id, l.charge_nr, c.sorte, c.schlag, l.auftrag_id, l.datei_name, l.datei_zeit, l.zuordnung;
