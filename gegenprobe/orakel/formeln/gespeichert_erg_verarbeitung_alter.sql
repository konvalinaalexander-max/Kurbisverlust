-- gespeichert: erg_verarbeitung_alter
-- v_verarbeitung_alter, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT auftrag_id,
    charge_nr,
    sorte,
    schlag,
    station,
    weg,
    tag,
    n_paletten,
    alter_verarbeitet,
    alter_charge,
    differenz
   FROM v_verarbeitung_alter;
