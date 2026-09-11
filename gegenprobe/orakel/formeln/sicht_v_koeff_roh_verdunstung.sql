-- sicht: v_koeff_roh_verdunstung
-- Die einzelnen Verdunstungsmessungen, bevor gemittelt wird: je Charge ein Anteil und sein Gewicht in der Mittelung. Die Rohdaten zu v_koeff_verdunstung — hier steht, worauf der Koeffizient beruht.

 SELECT 'verdunstung'::text AS art,
    sorte,
    charge_nr,
    rate_pro_tag::numeric AS anteil,
    netto_jetzt_kg AS gewicht
   FROM v_verdunstung_messung m
  WHERE verwendbar AND netto_jetzt_kg > 0::numeric;
