-- gespeichert: erg_lieferung
-- v_lieferung_masse, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT id,
    datum,
    charge_nr,
    sorte,
    kg,
    kisten,
    gebindeart,
    ziel,
    kunde,
    erfasser,
    ts,
    bemerkung,
    ziel_name,
    buch,
    masse_kg,
    masse_quelle,
    masse_fehler_kg,
    kisten_n
   FROM v_lieferung_masse;
