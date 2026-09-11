-- gespeichert: erg_ausschuss
-- v_ausschuss_beobachtung, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT weg,
    charge_nr,
    sorte,
    auftrag_id,
    basis_kg,
    klein_kg,
    gross_kg,
    plausibel
   FROM v_ausschuss_beobachtung;
