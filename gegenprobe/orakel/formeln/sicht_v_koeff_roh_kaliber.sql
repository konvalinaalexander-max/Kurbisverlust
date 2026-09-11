-- sicht: v_koeff_roh_kaliber
-- Koeffizienten-Rohwerte in einheitlicher Form: Anteil, die Masse, die er vertritt, und die Charge, aus der er stammt. ausschuss, nebenkanal, fax.

 SELECT 'ausschuss'::text AS art,
    b.sorte,
    b.charge_nr,
    b.klein_kg / b.basis_kg AS anteil,
    b.basis_kg AS gewicht
   FROM v_ausschuss_beobachtung b
  WHERE b.plausibel AND b.basis_kg > 0::numeric AND b.klein_kg IS NOT NULL
UNION ALL
 SELECT 'nebenkanal'::text AS art,
    b.sorte,
    b.charge_nr,
    b.gross_kg / b.basis_kg AS anteil,
    b.basis_kg AS gewicht
   FROM v_ausschuss_beobachtung b
  WHERE b.plausibel AND b.basis_kg > 0::numeric AND b.gross_kg IS NOT NULL
UNION ALL
 SELECT 'fax'::text AS art,
    f.sorte,
    f.charge_nr,
    f.anteil::numeric AS anteil,
    zahl(f.masse_kg + f.faul_kg, 2, '10000000000'::numeric)::numeric(12,2) AS gewicht
   FROM v_fax_beobachtung f
  WHERE f.plausibel AND f.masse_kg > 0::numeric AND f.faul_erfasst AND f.status = 'abgeschlossen'::auftrag_status;
