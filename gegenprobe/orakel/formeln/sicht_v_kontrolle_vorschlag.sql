-- sicht: v_kontrolle_vorschlag
-- Welche Charge als Nächstes kontrolliert werden sollte. informationswert gewichtet, wie viel noch im Haus liegt, wie lange die letzte Wiegung her ist und wie unsicher die Charge bisher ist — eine Reihenfolge, kein Befehl.

 SELECT b.charge_nr,
    b.sorte,
    b.schlag,
    b.lager_kg,
    b.alter_lager_von,
    b.alter_lager_bis,
    b.eingang_von,
    b.eingang_bis,
    COALESCE(k.n_kontrollen, 0) AS n_kontrollen,
    k.zuletzt,
    b.im_haus_heute_kg,
    heute() - COALESCE(k.zuletzt, b.eingang_von) AS tage_seit_wiegung,
    zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0) AS informationswert
   FROM erg_charge b
     LEFT JOIN ( SELECT verdunstung_wiegung.charge_nr,
            count(*) FILTER (WHERE verdunstung_wiegung.auftrag_id IS NULL)::integer AS n_kontrollen,
            max(verdunstung_wiegung.wiege_ts)::date AS zuletzt
           FROM verdunstung_wiegung
          WHERE verdunstung_wiegung.gemessen
          GROUP BY verdunstung_wiegung.charge_nr) k ON k.charge_nr = b.charge_nr
  WHERE b.im_haus_heute_kg > 0::numeric
  ORDER BY (zahl(b.im_haus_heute_kg * GREATEST(heute() - COALESCE(k.zuletzt, b.eingang_von), 1)::numeric, 0, '10000000000000'::numeric)::numeric(14,0)) DESC NULLS LAST, b.im_haus_heute_kg DESC
 LIMIT 3;
