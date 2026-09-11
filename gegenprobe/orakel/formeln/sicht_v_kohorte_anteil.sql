-- sicht: v_kohorte_anteil
-- Der Anteil jedes Eingangstags am Eingang der Charge — und damit am Bestand und an jeder Lieferung: es gibt kein Zuerst-rein-zuerst-raus, und die App weiss nicht, welche Palette gegangen ist (0060).

 SELECT charge_nr,
    eingangsdatum,
    n_rest,
    rest_kg,
    zahl(eingang_kg / NULLIF(sum(eingang_kg) OVER (PARTITION BY charge_nr), 0::numeric), 6, '10000'::numeric)::numeric(10,6) AS anteil
   FROM v_charge_kohorte
  WHERE eingang_kg > 0::numeric;
