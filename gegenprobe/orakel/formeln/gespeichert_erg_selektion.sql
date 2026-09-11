-- gespeichert: erg_selektion
-- v_selektionsverdacht, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT n_verarbeitung,
    n_lager,
    rest_verarbeitung,
    rest_lager,
    unterschied,
    befund
   FROM v_selektionsverdacht;
