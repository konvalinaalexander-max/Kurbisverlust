-- gespeichert: erg_kohorte
-- v_charge_kohorte, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT charge_nr,
    eingangsdatum,
    n_paletten,
    n_verarbeitet,
    n_rest,
    netto_je_palette,
    rest_kg,
    alter_heute,
    eingang_kg
   FROM v_charge_kohorte;
