-- sicht: v_schimmel_punkte
-- Die Punkte des Verderbsmodells: aus der Verarbeitung (Palox) und aus Lagerkontrollen. Fax-Faules fehlt hier absichtlich — es hängt nicht an der Lagerdauer (v_fax_beobachtung).

 WITH sortier_lauf_anteil AS MATERIALIZED (
         SELECT b.charge_nr,
            b.start_ts,
            b.schimmel_kg,
            b.basis_jetzt_kg
           FROM v_schimmel_beobachtung b
          WHERE b.station = 'sortieren'::station AND b.plausibel AND b.anteil IS NOT NULL
        ), gemischt AS (
         SELECT v_auftrag_angabe.auftrag_id
           FROM v_auftrag_angabe
          WHERE v_auftrag_angabe.schluessel = 'eine_charge'::text AND v_auftrag_angabe.wert = 'false'::text
        )
 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lagertage,
    b.schimmel_kg,
    b.basis_jetzt_kg,
    b.anteil,
    b.plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    b.auftrag_id
   FROM v_schimmel_beobachtung b
     LEFT JOIN gemischt g ON g.auftrag_id = b.auftrag_id
  WHERE b.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])
UNION ALL
 SELECT a.charge_nr,
    a.sorte,
    a.schlag,
    a.lagertage,
    s.kg AS schimmel_kg,
    a.eingang_netto_kg + s.kg AS basis_jetzt_kg,
    k.f2 AS anteil,
    anteil_plausibel(k.f2) AS plausibel,
        CASE
            WHEN g.auftrag_id IS NOT NULL THEN 'verarbeitung_gemischt'::text
            ELSE 'verarbeitung'::text
        END AS quelle,
    a.auftrag_id
   FROM v_auftrag_masse a
     JOIN v_schimmel_menge s ON s.auftrag_id = a.auftrag_id
     LEFT JOIN gemischt g ON g.auftrag_id = a.auftrag_id
     LEFT JOIN LATERAL ( SELECT sum(sl.schimmel_kg) / NULLIF(sum(sl.basis_jetzt_kg), 0::numeric) AS f1
           FROM sortier_lauf_anteil sl
          WHERE sl.charge_nr = a.charge_nr AND sl.start_ts <= a.start_ts) sa ON true
     CROSS JOIN LATERAL ( SELECT s.kg / NULLIF(a.eingang_netto_kg + s.kg, 0::numeric) AS g) x
     CROSS JOIN LATERAL ( SELECT 1::numeric - (1::numeric - LEAST(GREATEST(COALESCE(sa.f1, 0::numeric), 0::numeric), 0.99)) * (1::numeric - LEAST(GREATEST(COALESCE(x.g, 0::numeric), 0::numeric), 0.99)) AS f2) k
  WHERE a.station = 'waschen'::station AND NOT a.ist_fax AND a.lagertage IS NOT NULL AND a.eingang_netto_kg IS NOT NULL AND a.eingang_netto_kg > 0::numeric
UNION ALL
 SELECT w.charge_nr,
    w.sorte,
    w.schlag,
    w.lagertage,
    v.faul_kg AS schimmel_kg,
    w.netto_jetzt_kg AS basis_jetzt_kg,
    v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric) AS anteil,
    anteil_plausibel(v.faul_kg / NULLIF(w.netto_jetzt_kg, 0::numeric)) AS plausibel,
    'lager'::text AS quelle,
    NULL::bigint AS auftrag_id
   FROM v_verdunstung_messung w
     JOIN verdunstung_wiegung v ON v.id = w.id
  WHERE v.faul_kg IS NOT NULL AND v.gemessen AND w.netto_jetzt_kg > 0::numeric AND w.lagertage > 0;
