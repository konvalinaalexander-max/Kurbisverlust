-- gespeichert: mv_sortier_eingang
-- Je Charge der früheste Sortiertag als Tage seit 1970 — die Rechengrösse für das Alter beim Verarbeiten. Nur eine Hilfsgrösse, keine Kennzahl.

 SELECT a.charge_nr,
    sum((m.eingangsdatum - '2000-01-01'::date)::numeric * m.netto_kg) / NULLIF(sum(m.netto_kg), 0::numeric) AS tage_seit_epoche
   FROM auftrag a
     JOIN v_auftrag_palette_masse m ON m.auftrag_id = a.id
  WHERE a.station = 'sortieren'::station AND a.abgebrochen_ts IS NULL
  GROUP BY a.charge_nr;
