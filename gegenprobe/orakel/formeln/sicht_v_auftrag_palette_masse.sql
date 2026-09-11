-- sicht: v_auftrag_palette_masse
-- Netto je gezählter Eingangspalette: gewogen, vom Zettel, aus dem Wareneingang, oder das Mittel des Eingangstags / der Charge; masse_quelle sagt, welcher Weg es war. Beim Waschen gezählte Paletten (mit Kisten) stehen nicht hier — ihre Masse rechnet v_auftrag_wasch_paletten (0061). Ohne Kistenzahl kein gewogenes Netto (0064).

 WITH wiegung AS MATERIALIZED (
         SELECT vw.id,
            zahl(vw.brutto_damals_kg - vw.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, '100000000'::numeric)::numeric(10,2) AS netto_damals_kg,
            vw.eingangsdatum
           FROM verdunstung_wiegung vw
             LEFT JOIN gebinde g ON g.art = vw.gebindeart
        ), datum_mittel AS MATERIALIZED (
         SELECT v_palette.charge_nr,
            v_palette.eingangsdatum,
            avg(v_palette.netto_kg) AS netto_mittel
           FROM v_palette
          GROUP BY v_palette.charge_nr, v_palette.eingangsdatum
        ), charge_mittel AS MATERIALIZED (
         SELECT v_palette.charge_nr,
            avg(v_palette.netto_kg) AS netto_mittel,
            avg(v_palette.brutto_kg - v_palette.netto_kg) FILTER (WHERE v_palette.netto_kg IS NOT NULL) AS tara_mittel
           FROM v_palette
          GROUP BY v_palette.charge_nr
        ), charge_datum AS MATERIALIZED (
         SELECT v_charge_rueckgrat.charge_nr,
            v_charge_rueckgrat.eingangsdatum_mittel
           FROM v_charge_rueckgrat
        ), zettel AS MATERIALIZED (
         SELECT ap_1.id,
            COALESCE(pe.netto_kg, zahl(ap_1.brutto_zettel_kg - cm_1.tara_mittel, 2, '100000000'::numeric)::numeric(10,2)) AS netto_kg,
            pe.id IS NOT NULL AS exakt
           FROM auftrag_palette ap_1
             JOIN auftrag a_1 ON a_1.id = ap_1.auftrag_id
             LEFT JOIN LATERAL ( SELECT p_1.id,
                    p_1.netto_kg
                   FROM v_palette p_1
                  WHERE p_1.charge_nr = a_1.charge_nr AND p_1.eingangsdatum = ap_1.eingangsdatum AND p_1.brutto_kg = ap_1.brutto_zettel_kg AND p_1.netto_kg IS NOT NULL
                  ORDER BY p_1.id
                 LIMIT 1) pe ON true
             LEFT JOIN charge_mittel cm_1 ON cm_1.charge_nr = a_1.charge_nr
          WHERE ap_1.brutto_zettel_kg IS NOT NULL
        )
 SELECT ap.id,
    ap.auftrag_id,
    a.charge_nr,
    a.start_ts,
    COALESCE(w.netto_damals_kg, z.netto_kg, p.netto_kg, d.netto_mittel, cm.netto_mittel) AS netto_kg,
    COALESCE(w.eingangsdatum, p.eingangsdatum, ap.eingangsdatum, cd.eingangsdatum_mittel) AS eingangsdatum,
        CASE
            WHEN w.netto_damals_kg IS NOT NULL THEN 'gewogen'::text
            WHEN z.netto_kg IS NOT NULL AND z.exakt THEN 'zettel'::text
            WHEN z.netto_kg IS NOT NULL THEN 'zettel-charge-tara'::text
            WHEN p.netto_kg IS NOT NULL THEN 'palette'::text
            WHEN d.netto_mittel IS NOT NULL THEN 'datum-mittel'::text
            WHEN cm.netto_mittel IS NOT NULL THEN 'charge-mittel'::text
            ELSE 'unbekannt'::text
        END AS masse_quelle
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     LEFT JOIN wiegung w ON w.id = ap.wiegung_id
     LEFT JOIN zettel z ON z.id = ap.id
     LEFT JOIN v_palette p ON p.id = ap.palette_id
     LEFT JOIN datum_mittel d ON d.charge_nr = a.charge_nr AND d.eingangsdatum = ap.eingangsdatum
     LEFT JOIN charge_mittel cm ON cm.charge_nr = a.charge_nr
     LEFT JOIN charge_datum cd ON cd.charge_nr = a.charge_nr
  WHERE ap.kisten IS NULL;
