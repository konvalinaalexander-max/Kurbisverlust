-- sicht: v_schimmel_beobachtung
-- Schimmel je Arbeit gegen die Masse, die am Tag der Arbeit noch da war: Eingang abzüglich Verdunstung mit der gedeckelten Rate (0056). Fax-Faules bleibt beobachtbar, geht aber nicht in die Verderbskurve.

 SELECT am.auftrag_id,
    am.charge_nr,
    am.sorte,
    am.schlag,
    am.weg,
    am.station,
    am.start_ts,
    am.lagertage,
    am.masse_quelle,
    s.kg AS schimmel_kg,
    am.eingang_netto_kg AS eingang_kg,
    zahl(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 2, '10000000000'::numeric)::numeric(12,2) AS basis_jetzt_kg,
    s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric) AS anteil,
    anteil_plausibel(s.kg / NULLIF(am.eingang_netto_kg * power(1::numeric - x.r, x.tage), 0::numeric)) AND am.lagertage >= 0::numeric AS plausibel,
    am.ist_fax
   FROM v_auftrag_masse am
     JOIN v_schimmel_menge s ON s.auftrag_id = am.auftrag_id
     LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = am.sorte
     CROSS JOIN LATERAL ( SELECT LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05) AS r,
            GREATEST(am.lagertage, 0::numeric) AS tage) x
  WHERE am.eingang_netto_kg IS NOT NULL AND am.lagertage IS NOT NULL;
