-- gespeichert: erg_durchsatz
-- v_durchsatz, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT auftrag_id,
    charge_nr,
    sorte,
    station,
    weg,
    ist_fax,
    start_ts,
    ende_ts,
    dauer_h,
    masse_kg,
    masse_quelle,
    n_paletten,
    kg_pro_h,
    n_teilnehmer
   FROM v_durchsatz;
