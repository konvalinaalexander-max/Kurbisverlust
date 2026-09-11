-- sicht: v_auftrag_wasch_paletten
-- Beim Waschen gezählte Paletten: Kisten gesamt, Masse = Kisten × gemessenes Kistengewicht des Kalibers, Tage im Zwischenlager aus dem Sortierdatum (0061).

 WITH band AS (
         SELECT DISTINCT s.sorte,
            i.idx AS kaliber_idx,
            ((s.kaliber_baender -> i.idx) ->> 0)::integer AS von,
            ((s.kaliber_baender -> i.idx) ->> 1)::integer AS bis
           FROM sortierschema s
             CROSS JOIN LATERAL generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) i(idx)
          WHERE s.art = 'kaliber'::text AND s.kaliber_baender IS NOT NULL
        )
 SELECT a.id AS auftrag_id,
    count(*)::integer AS n_paletten,
    sum(ap.kisten)::integer AS kisten,
    zahl(sum(ap.kisten)::numeric * max(k.kg_je_gebinde), 2, '10000000000'::numeric)::numeric(12,2) AS kg,
    max(k.n) AS n_messungen,
    zahl(sum((ap.kisten * (betriebstag(a.start_ts) - ap.sortierdatum))::numeric) FILTER (WHERE ap.sortierdatum IS NOT NULL) / NULLIF(sum(ap.kisten) FILTER (WHERE ap.sortierdatum IS NOT NULL), 0)::numeric, 1, '100000'::numeric)::numeric(8,1) AS zwischenlager_tage,
    count(*) FILTER (WHERE ap.sortierdatum IS NOT NULL)::integer AS n_mit_sortierdatum
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     JOIN auftrag_palette ap ON ap.auftrag_id = a.id AND ap.kisten IS NOT NULL
     LEFT JOIN LATERAL ( SELECT b.kaliber_idx
           FROM band b
          WHERE a.kaliber_idx IS NULL AND b.sorte = c.sorte AND b.von = a.kaliber_von_g AND b.bis = a.kaliber_bis_g
          ORDER BY b.kaliber_idx
         LIMIT 1) e ON true
     LEFT JOIN v_koeff_gebinde k ON k.sorte = c.sorte AND k.kaliber_idx = COALESCE(a.kaliber_idx, e.kaliber_idx)
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.abgebrochen_ts IS NULL
  GROUP BY a.id;
