-- gespeichert: erg_massenbilanz
-- v_massenbilanz, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT charge_nr,
    sorte,
    schlag,
    eingang_kg,
    ausgelagert_kg,
    lager_kg,
    n_paletten,
    alter_ausgelagert,
    alter_lager,
    stichtag,
    modell_am_band_kg,
    csv_gemessen_kg,
    abweichung_kg,
    abweichung_anteil,
    restbestand_kg,
    alter_band
   FROM v_massenbilanz;
