-- sicht: v_ausschuss_beobachtung
-- Zu klein und zu gross je Arbeit gegen ihre Basis: am Band die CSV-Masse, von Hand der Eingang abzüglich Verdunstung (gedeckelte Rate, 0057) und Schimmel.

 SELECT 'maschine'::verarbeitungsweg AS weg,
    lm.charge_nr,
    lm.sorte,
    lm.auftrag_id,
    lm.masse_kg AS basis_kg,
    lm.masse_klein_kg AS klein_kg,
    lm.masse_nebenkanal_kg AS gross_kg,
    true AS plausibel
   FROM v_sortier_lauf_masse lm
  WHERE lm.masse_kg > 0::numeric
UNION ALL
 SELECT 'hand'::verarbeitungsweg AS weg,
    am.charge_nr,
    am.sorte,
    am.auftrag_id,
    n.basis AS basis_kg,
    h.klein_kg,
    h.gross_kg,
    anteil_plausibel(h.klein_kg / NULLIF(n.basis, 0::numeric)) AND anteil_plausibel(COALESCE(h.gross_kg, 0::numeric) / NULLIF(n.basis, 0::numeric)) AS plausibel
   FROM v_auftrag_masse am
     JOIN ( SELECT ausschuss_messung.auftrag_id,
            sum(ausschuss_messung.kg) FILTER (WHERE ausschuss_messung.art = 'zu_klein'::ausschuss_art)::numeric AS klein_kg,
            sum(ausschuss_messung.kg) FILTER (WHERE ausschuss_messung.art = 'zu_gross'::ausschuss_art)::numeric AS gross_kg
           FROM ausschuss_messung
          WHERE ausschuss_messung.gemessen
          GROUP BY ausschuss_messung.auftrag_id) h ON h.auftrag_id = am.auftrag_id
     LEFT JOIN v_schimmel_menge sm ON sm.auftrag_id = am.auftrag_id
     LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = am.sorte
     CROSS JOIN LATERAL ( SELECT zahl(GREATEST(am.eingang_netto_kg * power(1::numeric - LEAST(GREATEST(COALESCE(kv.mittel, 0::numeric), 0::numeric), 0.05), GREATEST(am.lagertage, 0::numeric)) - COALESCE(sm.kg, 0::numeric), 0::numeric), 2, '10000000000'::numeric)::numeric(12,2) AS basis) n
  WHERE am.weg = 'hand'::verarbeitungsweg AND am.eingang_netto_kg IS NOT NULL AND am.lagertage IS NOT NULL;
