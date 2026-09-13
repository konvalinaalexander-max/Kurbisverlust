-- sicht: v_lieferung_charge_tag
-- Gelieferte Masse je Charge, Tag und Buch — nur Lieferungen bis heute(). Eine Lieferung ohne Chargennummer wird nach dem Eingangsanteil auf die Chargen ihrer Sorte verteilt; der Vorlauf zählt am Erfassungsbeginn. Diese Regel gibt es nur hier: v_lieferung_kohorte rechnet darauf (0071).

 WITH lief AS (
         SELECT l.id,
            l.datum,
            l.buch,
            l.masse_kg,
            c.charge_nr,
            c.anteil
           FROM ( SELECT heute() AS heute) d
             CROSS JOIN v_lieferung_masse l
             CROSS JOIN LATERAL ( SELECT l.charge_nr,
                    1::numeric AS anteil
                  WHERE l.charge_nr IS NOT NULL
                UNION ALL
                 SELECT r.charge_nr,
                    r.eingang_netto_kg / sum(r.eingang_netto_kg) OVER ()
                   FROM v_charge_rueckgrat r
                  WHERE l.charge_nr IS NULL AND r.sorte = l.sorte AND r.eingang_netto_kg > 0::numeric) c
          WHERE l.masse_kg IS NOT NULL AND l.masse_kg > 0::numeric AND (l.buch = ANY (ARRAY['verkauf'::text, 'marge'::text, 'verlust'::text])) AND l.datum <= d.heute
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
 SELECT charge_nr,
    datum,
    buch,
    zahl(sum(masse_kg * anteil), 2, '1000000000000'::numeric)::numeric(14,2) AS masse_kg,
    count(DISTINCT id)::integer AS n_lieferungen
   FROM lief
  GROUP BY charge_nr, datum, buch;
