-- gespeichert: erg_kaliber
-- v_kaliber_verteilung, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT charge_nr,
    sorte,
    klasse,
    kaliber_idx,
    band_von,
    band_bis,
    n_kuerbis,
    masse_kg
   FROM v_kaliber_verteilung;
