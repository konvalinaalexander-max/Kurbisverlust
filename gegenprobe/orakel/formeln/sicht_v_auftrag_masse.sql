-- sicht: v_auftrag_masse
-- Masse je Arbeit: gewogene Paletten oder Zettel, beim Waschen gezählte Paletten (Kisten × Kistengewicht, 0061), sonst gezählte Kisten, beim Fax die Palettenzahl mal gemessener Palettenmasse. ist_fax: kein Waschgang.

 SELECT m.auftrag_id,
    m.charge_nr,
    m.sorte,
    m.schlag,
    m.weg,
    m.station,
    m.start_ts,
    m.ende_ts,
    m.status,
    m.n_paletten,
    COALESCE(m.eingang_netto_kg, wp.kg, gb.kg, fp.kg) AS eingang_netto_kg,
        CASE
            WHEN m.masse_quelle <> 'fehlt'::text THEN m.masse_quelle
            WHEN wp.kg IS NOT NULL THEN 'wasch_paletten'::text
            WHEN gb.kg IS NOT NULL THEN 'gebinde'::text
            WHEN fp.kg IS NOT NULL THEN 'fax_paletten'::text
            ELSE 'fehlt'::text
        END AS masse_quelle,
    zahl(COALESCE(m.lagertage,
        CASE
            WHEN m.station = 'waschen'::station THEN (betriebstag(m.start_ts) - '2000-01-01'::date)::numeric - COALESCE(se.tage_seit_epoche, (r.eingangsdatum_mittel - '2000-01-01'::date)::numeric)
            ELSE NULL::numeric
        END), 1, '1000000000'::numeric)::numeric(10,1) AS lagertage,
    a.ist_fax,
    wp.zwischenlager_tage
   FROM mv_auftrag_masse m
     JOIN auftrag a ON a.id = m.auftrag_id
     LEFT JOIN mv_sortier_eingang se ON se.charge_nr = m.charge_nr
     LEFT JOIN v_charge_rueckgrat r ON r.charge_nr = m.charge_nr
     LEFT JOIN v_auftrag_wasch_paletten wp ON wp.auftrag_id = m.auftrag_id
     LEFT JOIN ( SELECT v_auftrag_gebinde_masse.auftrag_id,
            sum(v_auftrag_gebinde_masse.kg) AS kg
           FROM v_auftrag_gebinde_masse
          GROUP BY v_auftrag_gebinde_masse.auftrag_id) gb ON gb.auftrag_id = m.auftrag_id
     LEFT JOIN LATERAL ( SELECT zahl(a.paletten_gesamt::numeric * p.netto_kg, 2, '10000000000'::numeric)::numeric(12,2) AS kg
           FROM v_koeff_palette_netto p
          WHERE a.ist_fax AND a.paletten_gesamt > 0 AND p.sorte = m.sorte AND (p.kistensystem = a.kistensystem OR p.kistensystem IS NULL AND a.kistensystem IS DISTINCT FROM 'anderes'::text)
          ORDER BY (p.kistensystem = a.kistensystem) DESC NULLS LAST
         LIMIT 1) fp ON true;
