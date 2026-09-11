-- sicht: v_fax_beobachtung
-- Je Fax-Arbeit: die Masse (Paletten × gemessene Palettenmasse, oder gezählte Kisten), das gewogene Faule und sein Anteil an dem, was durch die Hände ging. Dazu die Tage seit dem Waschen, wenn der Vorarbeiter sie kannte (0060).

 SELECT a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    c.schlag,
    a.kaeufer,
    a.start_ts,
    a.ende_ts,
    a.status,
    a.abgebrochen_ts,
    m.eingang_netto_kg AS masse_kg,
    m.masse_quelle,
    COALESCE(g.kisten, 0) AS kisten,
    COALESCE(s.kg, 0::numeric) AS faul_kg,
    s.auftrag_id IS NOT NULL AS faul_erfasst,
    zahl(COALESCE(s.kg, 0::numeric) / NULLIF(m.eingang_netto_kg + COALESCE(s.kg, 0::numeric), 0::numeric), 5, '100000'::numeric)::numeric(10,5) AS anteil,
    anteil_plausibel(COALESCE(s.kg, 0::numeric) / NULLIF(m.eingang_netto_kg + COALESCE(s.kg, 0::numeric), 0::numeric)) AS plausibel,
    a.paletten_gesamt,
    a.tage_seit_waschen,
    a.kistensystem
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_masse m ON m.auftrag_id = a.id
     LEFT JOIN v_schimmel_menge s ON s.auftrag_id = a.id
     LEFT JOIN ( SELECT auftrag_gebinde.auftrag_id,
            sum(auftrag_gebinde.anzahl)::integer AS kisten
           FROM auftrag_gebinde
          GROUP BY auftrag_gebinde.auftrag_id) g ON g.auftrag_id = a.id
  WHERE a.ist_fax AND a.abgebrochen_ts IS NULL;
