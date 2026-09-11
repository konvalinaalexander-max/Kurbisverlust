-- gespeichert: erg_fax
-- v_fax_beobachtung, gespeichert für die App Erneuert mit auswertung_schritt().

 SELECT auftrag_id,
    charge_nr,
    sorte,
    schlag,
    kaeufer,
    start_ts,
    ende_ts,
    status,
    abgebrochen_ts,
    masse_kg,
    masse_quelle,
    kisten,
    faul_kg,
    faul_erfasst,
    anteil,
    plausibel,
    paletten_gesamt,
    tage_seit_waschen,
    kistensystem
   FROM v_fax_beobachtung;
