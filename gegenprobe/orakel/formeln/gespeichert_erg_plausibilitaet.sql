-- gespeichert: erg_plausibilitaet
-- v_plausibilitaet, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT art,
    auftrag_id,
    charge_nr,
    sorte,
    start_ts,
    befund,
    rat
   FROM v_plausibilitaet;
