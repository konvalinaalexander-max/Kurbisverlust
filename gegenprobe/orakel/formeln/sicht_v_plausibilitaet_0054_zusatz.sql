-- sicht: v_plausibilitaet_0054_zusatz
-- Zusatzprüfungen zu v_plausibilitaet, die seit 0054 dazugekommen sind — je Auffälligkeit Art, betroffene Arbeit, Befund und Rat. Wird von v_plausibilitaet mitgelesen; einzeln braucht sie niemand.

 SELECT 'Kistengewicht'::text AS art,
    g.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Kisten zum eigenen Kaliber %s–%s g gezählt, aber ein Band mit diesen '::text || 'Grenzen wurde beim Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt'::text, g.anzahl, a.kaliber_von_g, a.kaliber_bis_g) AS befund,
    'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '::text || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'::text AS rat
   FROM v_auftrag_gebinde_masse g
     JOIN auftrag a ON a.id = g.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE g.kg IS NULL AND g.anzahl > 0 AND g.kaliber_idx = '-2'::integer
UNION ALL
 SELECT 'Kistengewicht'::text AS art,
    wp.auftrag_id,
    a.charge_nr,
    c.sorte,
    a.start_ts,
    format('%s Paletten mit %s Kisten gezählt, aber %s — das Kistengewicht ist unbekannt, '::text || 'die Menge dieser Arbeit damit auch'::text, wp.n_paletten, wp.kisten,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN format('ein Band %s–%s g wurde beim Sortieren noch nie mitgezählt'::text, a.kaliber_von_g, a.kaliber_bis_g)
            ELSE 'für dieses Kaliber wurde beim Sortieren noch nie mitgezählt'::text
        END) AS befund,
        CASE
            WHEN a.kaliber_von_g IS NOT NULL THEN 'Entweder das Band aus der Liste wählen, das dem Etikett entspricht, oder beim '::text || 'nächsten Sortierlauf mit diesem Band die gefüllten Kisten zählen.'::text
            ELSE 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '::text || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.'::text
        END AS rat
   FROM v_auftrag_wasch_paletten wp
     JOIN auftrag a ON a.id = wp.auftrag_id
     JOIN charge c ON c.nr = a.charge_nr
  WHERE wp.kg IS NULL AND wp.kisten > 0
UNION ALL
 SELECT 'Lieferung in der Zukunft'::text AS art,
    NULL::bigint AS auftrag_id,
    l.charge_nr,
    l.sorte,
    l.datum::timestamp with time zone AS start_ts,
    format('Lieferschein über %s kg mit Datum %s — das liegt nach heute (%s). '::text || 'Die Menge zählt erst ab diesem Tag in Ausgang und Bestand.'::text, round(l.masse_kg), to_char(l.datum::timestamp with time zone, 'DD.MM.YYYY'::text), to_char(heute()::timestamp with time zone, 'DD.MM.YYYY'::text)) AS befund,
    'Stimmt das Datum? Ein vordatierter Lieferschein ist in Ordnung — die Zahl '::text || 'erscheint von selbst, sobald der Tag da ist. Ein Zahlendreher gehört korrigiert.'::text AS rat
   FROM v_lieferung_masse l
  WHERE l.datum > heute() AND l.masse_kg IS NOT NULL AND l.masse_kg > 0::numeric
UNION ALL
 SELECT v_plausibilitaet_0064_zusatz.art,
    v_plausibilitaet_0064_zusatz.auftrag_id,
    v_plausibilitaet_0064_zusatz.charge_nr,
    v_plausibilitaet_0064_zusatz.sorte,
    v_plausibilitaet_0064_zusatz.start_ts,
    v_plausibilitaet_0064_zusatz.befund,
    v_plausibilitaet_0064_zusatz.rat
   FROM v_plausibilitaet_0064_zusatz;
