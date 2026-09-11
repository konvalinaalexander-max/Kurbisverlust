-- gespeichert: erg_naechste_charge
-- v_naechste_charge, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT charge_nr,
    sorte,
    schlag,
    lager_kg,
    alter_tage,
    masse_jetzt_kg,
    verdunstung_14_kg,
    schimmel_14_kg,
    prognose_verlust_14_kg,
    hochgerechnet,
    modell_gilt,
    alter_von,
    alter_bis,
    n_kohorten
   FROM v_naechste_charge;
