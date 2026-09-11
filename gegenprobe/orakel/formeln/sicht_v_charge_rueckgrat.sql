-- sicht: v_charge_rueckgrat
-- eingang_netto_kg ist auf alle Paletten der Charge hochgerechnet; eingang_netto_gemessen_kg ist die Summe der Paletten mit bekannter Tara. Weichen die beiden ab, fehlt bei n_paletten − n_paletten_mit_netto Paletten die Gebindeart.

 SELECT c.nr AS charge_nr,
    c.schlag,
    c.sorte,
    c.saison,
    count(p.id) AS n_paletten,
    count(p.netto_kg) AS n_paletten_mit_netto,
    sum(p.netto_kg) / NULLIF(count(p.netto_kg), 0)::numeric * count(p.id)::numeric AS eingang_netto_kg,
    sum(p.brutto_kg) AS eingang_brutto_kg,
    min(p.eingangsdatum) AS erster_eingang,
    max(p.eingangsdatum) AS letzter_eingang,
    '2000-01-01'::date + (sum((p.eingangsdatum - '2000-01-01'::date)::numeric * COALESCE(p.netto_kg, 1::numeric)) / NULLIF(sum(COALESCE(p.netto_kg, 1::numeric)), 0::numeric))::integer AS eingangsdatum_mittel,
    sum(p.netto_kg) AS eingang_netto_gemessen_kg
   FROM charge c
     LEFT JOIN v_palette p ON p.charge_nr = c.nr
  GROUP BY c.nr, c.schlag, c.sorte, c.saison;
