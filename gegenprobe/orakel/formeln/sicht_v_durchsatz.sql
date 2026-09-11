-- sicht: v_durchsatz
-- Abgeschlossene Arbeiten mit Dauer, Masse und Kilo je Stunde. kg_pro_h ist NULL, wenn die Masse unbekannt ist oder die Arbeit kürzer als eine Viertelstunde war.

 SELECT a.id AS auftrag_id,
    a.charge_nr,
    m.sorte,
    a.station,
    a.weg,
    a.ist_fax,
    a.start_ts,
    a.ende_ts,
    zahl(EXTRACT(epoch FROM a.ende_ts - a.start_ts) / 3600::numeric, 2, '100000000'::numeric)::numeric(10,2) AS dauer_h,
    m.eingang_netto_kg AS masse_kg,
    m.masse_quelle,
    m.n_paletten,
    zahl(
        CASE
            WHEN m.eingang_netto_kg IS NOT NULL AND (a.ende_ts - a.start_ts) >= '00:15:00'::interval THEN m.eingang_netto_kg / (EXTRACT(epoch FROM a.ende_ts - a.start_ts) / 3600::numeric)
            ELSE NULL::numeric
        END, 1, '1000000000'::numeric)::numeric(10,1) AS kg_pro_h,
    (( SELECT count(*) AS count
           FROM auftrag_teilnehmer t
          WHERE t.auftrag_id = a.id))::integer AS n_teilnehmer
   FROM auftrag a
     JOIN v_auftrag_masse m ON m.auftrag_id = a.id
  WHERE a.status = 'abgeschlossen'::auftrag_status AND a.abgebrochen_ts IS NULL AND a.ende_ts IS NOT NULL;
