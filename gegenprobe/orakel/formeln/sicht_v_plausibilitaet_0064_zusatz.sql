-- sicht: v_plausibilitaet_0064_zusatz
-- Drei Auffälligkeiten aus Runde L: eine Gebindeart ohne hinterlegte Tara (die Paletten fehlen im Eingang), eine Charge mit mehr Ausgang als Eingang, und ein Zettelgewicht, das zur Charge passt, aber nicht zum Eingangstag.

 SELECT 'Tara fehlt'::text AS art,
    NULL::bigint AS auftrag_id,
    p.charge_nr,
    c.sorte,
    min(p.eingangsdatum)::timestamp with time zone AS start_ts,
    format('%s von %s Paletten der Charge haben kein Nettogewicht (%s kg brutto): %s. %s'::text, count(*), r.n_paletten, round(sum(p.brutto_kg)),
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'die Gebindeart steht nicht auf der Palette'::text
            WHEN bool_or(g.art IS NULL) THEN 'diese Gebindeart steht nicht in den Stammdaten'::text
            WHEN bool_or(g.tara_kg_pro_kiste IS NULL) THEN 'für die Gebindeart ist kein Kistengewicht hinterlegt'::text
            WHEN bool_or(g.tara_kg_palette IS NULL) THEN 'für die Gebindeart ist kein Palettengewicht hinterlegt'::text
            ELSE 'die Kistenzahl fehlt'::text
        END,
        CASE
            WHEN r.n_paletten_mit_netto = 0 THEN 'Damit hat die Charge gar keinen Eingang — sie fehlt in der ganzen Bilanz.'::text
            ELSE format('Für sie rechnet der Eingang mit dem Mittel der übrigen: %s der %s kg '::text || 'Eingang sind hochgerechnet, nicht gewogen.'::text, round(r.eingang_netto_kg - r.eingang_netto_gemessen_kg), round(r.eingang_netto_kg))
        END) AS befund,
        CASE
            WHEN bool_or(p.gebindeart IS NULL) THEN 'Gebindeart am Wareneingang nachtragen.'::text
            WHEN bool_or(g.art IS NULL) OR bool_or(g.tara_kg_pro_kiste IS NULL) OR bool_or(g.tara_kg_palette IS NULL) THEN 'Unter Betrieb → Stammdaten die Tara dieser Gebindeart eintragen. '::text || 'Die Zahlen rechnen sich danach von selbst neu.'::text
            ELSE 'Kistenzahl der Palette im Wareneingang nachtragen.'::text
        END AS rat
   FROM palette p
     LEFT JOIN gebinde g ON g.art = p.gebindeart
     JOIN charge c ON c.nr = p.charge_nr
     JOIN v_charge_rueckgrat r ON r.charge_nr = p.charge_nr
  WHERE (p.brutto_kg - p.kisten::numeric * g.tara_kg_pro_kiste - g.tara_kg_palette) IS NULL
  GROUP BY p.charge_nr, c.sorte, r.n_paletten, r.n_paletten_mit_netto, r.eingang_netto_kg, r.eingang_netto_gemessen_kg
UNION ALL
 SELECT 'Überzählung'::text AS art,
    NULL::bigint AS auftrag_id,
    h.charge_nr,
    h.sorte,
    h.eingangsdatum_mittel::timestamp with time zone AS start_ts,
    format('%s kg mehr ausgeliefert, als für diese Charge je als Eingang erfasst wurde '::text || '(%s kg Eingang, %s kg geliefert) — das sind %s %% des Eingangs'::text, round(h.ueberzaehlung_kg), round(h.eingang_kg), round(h.geliefert_kg), round(100::numeric * h.ueberzaehlung_kg / NULLIF(h.eingang_kg, 0::numeric))) AS befund,
    ('Fehlt im Erntejournal eine Palette dieser Charge? Oder ist ein Lieferschein auf '::text || 'die falsche Chargennummer gebucht? Beides lässt sich nachtragen; bis dahin ist '::text) || 'die Verlustquote dieser Charge zu hoch, weil ihr Eingang zu klein ist.'::text AS rat
   FROM v_hochrechnung_basis h
  WHERE h.ueberzaehlung_kg > 0::numeric
UNION ALL
 SELECT 'Zettelgewicht'::text AS art,
    ap.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format(('%s Palette(n) mit %s kg vom Zettel und Eingangsdatum %s gezählt. Eine Palette '::text || 'dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet '::text) || 'wird deshalb mit der mittleren Tara der Charge, nicht mit ihrer eigenen.'::text, count(*), ap.brutto_zettel_kg, to_char(ap.eingangsdatum::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'::text AS rat
   FROM auftrag_palette ap
     JOIN auftrag a ON a.id = ap.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE ap.brutto_zettel_kg IS NOT NULL AND ap.eingangsdatum IS NOT NULL AND a.abgebrochen_ts IS NULL AND (EXISTS ( SELECT 1
           FROM palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg)) AND NOT (EXISTS ( SELECT 1
           FROM v_palette p
          WHERE p.charge_nr = a.charge_nr AND p.brutto_kg = ap.brutto_zettel_kg AND p.eingangsdatum = ap.eingangsdatum AND p.netto_kg IS NOT NULL))
  GROUP BY ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.brutto_zettel_kg, ap.eingangsdatum;
