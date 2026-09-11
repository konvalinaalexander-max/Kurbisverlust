-- gespeichert: erg_datenlage
-- v_datenlage, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT charge_nr,
    sorte,
    schlag,
    n_paletten,
    n_paletten_mit_netto,
    eingang_kg,
    n_wiegungen,
    n_schimmel,
    n_sortierlaeufe,
    n_auftraege
   FROM v_datenlage;
