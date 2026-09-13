-- sicht: v_lieferung_kohorte
-- Gelieferte Masse je Charge, Eingangstag und Buch (verkauf, marge, verlust), mit dem massegewichteten Alter am Liefertag; nur Lieferungen bis heute(). Grundlage der Rückrechnung in der Kaskade. 0065: das dritte Buch ist dabei — was in den Kompost ging, hat den Betrieb verlassen und gehört aus dem Lager.

 SELECT f.charge_nr,
    k.eingangsdatum AS kohorte,
    f.buch,
    zahl(sum(f.masse_kg * k.anteil), 2, '1000000000000'::numeric)::numeric(14,2) AS masse_kg,
    zahl(sum(f.masse_kg * k.anteil * GREATEST(f.datum - k.eingangsdatum, 0)::numeric) / NULLIF(sum(f.masse_kg * k.anteil), 0::numeric), 1, '100000'::numeric)::numeric(8,1) AS alter_tage,
    sum(f.n_lieferungen)::integer AS n_lieferungen,
    min(f.datum) AS von,
    max(f.datum) AS bis
   FROM v_lieferung_charge_tag f
     JOIN v_kohorte_anteil k ON k.charge_nr = f.charge_nr
  GROUP BY f.charge_nr, k.eingangsdatum, f.buch;
