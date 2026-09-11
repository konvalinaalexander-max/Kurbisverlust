-- sicht: v_wiegung_kennzahl
-- Je gewogener Palette: Netto damals und jetzt, die Verdunstung dazwischen (0062 — vorher verlust_kg), kg je Kiste und je Kürbis. Ohne Kistenzahl oder hinterlegte Tara gibt es kein Netto (0064).

 SELECT w.id,
    w.auftrag_id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.eingangsdatum,
    w.wiege_ts,
    w.kisten,
    w.gebindeart,
    w.sichtbar_schimmel,
    w.kuerbisse_pro_kiste,
    betriebstag(w.wiege_ts) - w.eingangsdatum AS lagertage,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    zahl(n.netto_jetzt_kg / NULLIF(w.kisten, 0)::numeric, 3, '10000000'::numeric)::numeric(10,3) AS kg_pro_kiste,
    zahl(n.netto_jetzt_kg / NULLIF(w.kisten * w.kuerbisse_pro_kiste, 0)::numeric, 3, '10000000'::numeric)::numeric(10,3) AS kg_pro_kuerbis,
    zahl(n.netto_damals_kg - n.netto_jetzt_kg, 2, '100000000'::numeric)::numeric(10,2) AS verdunstung_kg
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT zahl(w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, '100000000'::numeric)::numeric(10,2) AS netto_damals_kg,
            zahl(w.brutto_jetzt_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette, 2, '100000000'::numeric)::numeric(10,2) AS netto_jetzt_kg) n
  WHERE w.gemessen AND (a.id IS NULL OR a.abgebrochen_ts IS NULL);
