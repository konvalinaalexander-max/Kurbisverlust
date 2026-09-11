-- sicht: v_sortier_lauf_masse
-- Je Sortierlauf aus der Waage-Datei: wie viele Kürbisse mit welcher Masse in welchen Kanal gingen — Kaliber (verkaufsfähig), zu klein, Nebenkanal. Alle Massen in kg, gewogen, nicht gerechnet.

 SELECT lauf_id,
    charge_nr,
    sorte,
    schlag,
    auftrag_id,
    datei_name,
    datei_zeit,
    zuordnung,
    n_kuerbis,
    masse_kg,
    n_klein,
    masse_klein_kg,
    n_nebenkanal,
    masse_nebenkanal_kg,
    n_kaliber,
    masse_kaliber_kg
   FROM mv_sortier_lauf_masse;
