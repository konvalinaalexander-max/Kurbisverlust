-- gespeichert: mv_auftrag_masse
-- Je Arbeit die Eingangsmasse und woher sie kommt (masse_quelle: gewogen, aus Paletten gerechnet oder geschätzt), dazu Station, Dauer und Lagertage. Erneuert von auswertung_schritt(1).

 SELECT a.id AS auftrag_id,
    a.charge_nr,
    c.sorte,
    c.schlag,
    a.weg,
    a.station,
    a.start_ts,
    a.ende_ts,
    a.status,
    count(m.id) AS n_paletten,
    COALESCE(sum(m.netto_kg), a.durchsatz_kg) AS eingang_netto_kg,
        CASE
            WHEN sum(m.netto_kg) IS NOT NULL THEN 'paletten'::text
            WHEN a.durchsatz_kg IS NOT NULL THEN 'durchsatz'::text
            ELSE 'fehlt'::text
        END AS masse_quelle,
    (sum((a.start_ts::date - m.eingangsdatum)::numeric * m.netto_kg) / NULLIF(sum(m.netto_kg), 0::numeric))::numeric(10,1) AS lagertage
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     LEFT JOIN v_auftrag_palette_masse m ON m.auftrag_id = a.id
  WHERE a.abgebrochen_ts IS NULL
  GROUP BY a.id, a.charge_nr, c.sorte, c.schlag, a.weg, a.station, a.start_ts, a.ende_ts, a.status, a.durchsatz_kg;
