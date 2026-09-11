-- sicht: v_lieferung_kohorte
-- Gelieferte Masse je Charge, Eingangstag und Buch (verkauf, marge, verlust), mit dem massegewichteten Alter am Liefertag; nur Lieferungen bis heute(). Grundlage der Rückrechnung in der Kaskade. 0065: das dritte Buch ist dabei — was in den Kompost ging, hat den Betrieb verlassen und gehört aus dem Lager.

 WITH lief AS (
         SELECT l.id,
            l.datum,
            l.buch,
            l.masse_kg,
            c.charge_nr,
            c.anteil
           FROM v_lieferung_masse l
             CROSS JOIN LATERAL ( SELECT l.charge_nr,
                    1::numeric AS anteil
                  WHERE l.charge_nr IS NOT NULL
                UNION ALL
                 SELECT r.charge_nr,
                    r.eingang_netto_kg / sum(r.eingang_netto_kg) OVER ()
                   FROM v_charge_rueckgrat r
                  WHERE l.charge_nr IS NULL AND r.sorte = l.sorte AND r.eingang_netto_kg > 0::numeric) c
          WHERE l.masse_kg IS NOT NULL AND l.masse_kg > 0::numeric AND (l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text, 'verlust'::text])) AND l.datum <= heute()
        UNION ALL
         SELECT - cv.charge_nr,
            COALESCE(( SELECT NULLIF(einstellung.wert #>> '{}'::text[], ''::text)::date AS "nullif"
                   FROM einstellung
                  WHERE einstellung.schluessel = 'erfassungsbeginn'::text), r.letzter_eingang) AS "coalesce",
            'verkauf'::text,
            cv.ausgang_vor_app_kg,
            cv.charge_nr,
            1
           FROM charge_vorlauf cv
             JOIN v_charge_rueckgrat r ON r.charge_nr = cv.charge_nr
          WHERE cv.ausgang_vor_app_kg > 0::numeric
        )
 SELECT f.charge_nr,
    k.eingangsdatum AS kohorte,
    f.buch,
    zahl(sum(f.masse_kg * f.anteil * k.anteil), 2, '1000000000000'::numeric)::numeric(14,2) AS masse_kg,
    zahl(sum(f.masse_kg * f.anteil * k.anteil * GREATEST(f.datum - k.eingangsdatum, 0)::numeric) / NULLIF(sum(f.masse_kg * f.anteil * k.anteil), 0::numeric), 1, '100000'::numeric)::numeric(8,1) AS alter_tage,
    count(DISTINCT f.id)::integer AS n_lieferungen,
    min(f.datum) AS von,
    max(f.datum) AS bis
   FROM lief f
     JOIN v_kohorte_anteil k ON k.charge_nr = f.charge_nr
  GROUP BY f.charge_nr, k.eingangsdatum, f.buch;
