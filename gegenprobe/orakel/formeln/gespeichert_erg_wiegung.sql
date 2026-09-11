-- gespeichert: erg_wiegung
-- v_wiegung_kennzahl, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT id,
    auftrag_id,
    charge_nr,
    sorte,
    schlag,
    eingangsdatum,
    wiege_ts,
    kisten,
    gebindeart,
    sichtbar_schimmel,
    kuerbisse_pro_kiste,
    lagertage,
    netto_damals_kg,
    netto_jetzt_kg,
    kg_pro_kiste,
    kg_pro_kuerbis,
    verdunstung_kg
   FROM v_wiegung_kennzahl;
