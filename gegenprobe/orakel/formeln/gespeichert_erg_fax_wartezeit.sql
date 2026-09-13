-- gespeichert: erg_fax_wartezeit
-- v_fax_wartezeit, gespeichert für die App (0071). Erneuert mit auswertung_schritt().

 SELECT gruppe,
    sorte,
    klasse,
    reihenfolge,
    n,
    masse_kg,
    faul_kg,
    anteil,
    unten,
    oben
   FROM v_fax_wartezeit;
