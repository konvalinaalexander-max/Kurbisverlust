-- gespeichert: erg_ausgang
-- v_ausgang_kennzahl, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT id,
    auftrag_id,
    charge_nr,
    sorte,
    schlag,
    ts,
    brutto_kg,
    kisten,
    gebindeart,
    kuerbisse_pro_kiste,
    netto_kg,
    kg_pro_kiste,
    kg_pro_kuerbis,
    soll_kg_pro_kiste,
    ueberfuellung_je_kiste,
    ueberfuellung_kg,
    kistensystem,
    kaliber_idx,
    stueck_je_kiste,
    erwartet_kg_pro_kiste,
    abweichung_je_kiste,
    band_mittel_g
   FROM v_ausgang_kennzahl;
