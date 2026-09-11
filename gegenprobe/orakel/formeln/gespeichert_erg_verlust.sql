-- gespeichert: erg_verlust
-- v_verlust_je_gruppe, gespeichert für die App (0062). Erneuert mit auswertung_schritt().

 SELECT gruppe,
    schluessel,
    strom,
    buch,
    kg,
    kg_unten,
    kg_oben,
    kg_beobachtet,
    kg_projiziert,
    kg_extrapoliert,
    kg_erwartet,
    koeff_n_min,
    streuung_kg,
    df,
    basis_kg,
    koeff_basis,
    koeff_art,
    formel,
    bekannt,
    eingang_kg,
    n_chargen
   FROM v_verlust_je_gruppe;
