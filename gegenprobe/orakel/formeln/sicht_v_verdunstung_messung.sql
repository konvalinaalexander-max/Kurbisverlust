-- sicht: v_verdunstung_messung
-- Jede Verdunstungswägung mit Netto damals und jetzt, Lagertagen und Tagesrate. verwendbar: gemessen, ohne sichtbaren Schimmel, positive Nettos, Wiegedatum nach dem Eingang, Arbeit nicht abgebrochen — und die Palette höchstens 1 % schwerer als beim Eingang (0056). Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto und damit keine Rate (0064). Was nicht verwendbar ist, steht in v_plausibilitaet.

 SELECT w.id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.palette_id,
    w.eingangsdatum,
    w.wiege_ts,
    w.sichtbar_schimmel,
    w.erfasser,
    w.auftrag_id,
    n.netto_damals_kg,
    n.netto_jetzt_kg,
    betriebstag(w.wiege_ts) - w.eingangsdatum AS lagertage,
    zahl(
        CASE
            WHEN n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (betriebstag(w.wiege_ts) - w.eingangsdatum) > 0 THEN 1::numeric - power(n.netto_jetzt_kg / n.netto_damals_kg, 1.0 / (betriebstag(w.wiege_ts) - w.eingangsdatum)::numeric)
            ELSE NULL::numeric
        END, 6, '10000'::numeric)::numeric(10,6) AS rate_pro_tag,
    w.gemessen AND NOT w.sichtbar_schimmel AND n.netto_damals_kg > 0::numeric AND n.netto_jetzt_kg > 0::numeric AND (betriebstag(w.wiege_ts) - w.eingangsdatum) > 0 AND n.netto_jetzt_kg < n.netto_damals_kg AND (a.id IS NULL OR a.abgebrochen_ts IS NULL) AS verwendbar
   FROM verdunstung_wiegung w
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN auftrag a ON a.id = w.auftrag_id
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     CROSS JOIN LATERAL ( SELECT w.brutto_damals_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_damals_kg,
            w.brutto_jetzt_kg - w.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette AS netto_jetzt_kg) n;
