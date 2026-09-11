-- gespeichert: erg_punkte
-- v_schimmel_punkte, gespeichert für die App Erneuert mit auswertung_schritt(). Seit 0068 eine Kopie von mv_schimmel_punkte statt einer zweiten Rechnung — gemessen 103 ms und 120 kB je Neurechnen.

 SELECT charge_nr,
    sorte,
    schlag,
    lagertage,
    schimmel_kg,
    basis_jetzt_kg,
    anteil,
    plausibel,
    quelle,
    auftrag_id
   FROM mv_schimmel_punkte;
