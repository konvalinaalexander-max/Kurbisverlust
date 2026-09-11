-- gespeichert: mv_schimmel_punkte
-- Die gespeicherte Fassung von v_schimmel_punkte. Alles, was rechnet, liest diese hier; v_schimmel_punkte selbst rechnet neu und wird nur beim Neuberechnen gebraucht.

 SELECT charge_nr,
    sorte,
    schlag,
    lagertage,
    schimmel_kg,
    basis_jetzt_kg,
    anteil,
    plausibel,
    quelle,
    auftrag_id
   FROM v_schimmel_punkte;
