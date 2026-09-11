-- sicht: v_schimmel_kurve_anzeige
-- Die Schimmel-Hochrechnung zum Nachschauen: je Altersklasse, was gemessen wurde, was daraus verwendet wird und warum. Für den Bildschirm "Messungen", nicht zum Weiterrechnen.

 SELECT von,
    bis,
        CASE
            WHEN bis > 9999 THEN von || '+ Tage'::text
            ELSE ((von || '–'::text) || bis) || ' Tage'::text
        END AS altersklasse,
    n AS messungen,
    zahl(anteil, 4, '1000000'::numeric)::numeric(10,4) AS gemessen,
    zahl(schimmelanteil((von + LEAST(bis, von + 60))::numeric / 2.0), 4, '1000000'::numeric)::numeric(10,4) AS verwendet,
    zahl(schimmelanteil((von + LEAST(bis, von + 60))::numeric / 2.0, 'unten'::text), 4, '1000000'::numeric)::numeric(10,4) AS unten,
    zahl(schimmelanteil((von + LEAST(bis, von + 60))::numeric / 2.0, 'oben'::text), 4, '1000000'::numeric)::numeric(10,4) AS oben,
        CASE
            WHEN NOT ( SELECT v_schimmel_modell.brauchbar
               FROM v_schimmel_modell) THEN 'Modell noch nicht anpassbar — es gilt die Treppenfunktion'::text
            WHEN von::numeric > (( SELECT v_schimmel_modell.t_max
               FROM v_schimmel_modell)) THEN 'über die längste gemessene Lagerdauer hinaus — hochgerechnet, '::text || 'daher der breitere Bereich'::text
            WHEN n = 0 THEN 'keine eigene Messung — aus dem Verlauf interpoliert'::text
            ELSE 'durch Messungen dieser Altersklasse gestützt'::text
        END ||
        CASE
            WHEN (( SELECT v_schimmel_modell.sockel
               FROM v_schimmel_modell)) > 0::numeric THEN format('; „gemessen" enthält den Sockel von %s %% (Erde, Hagel, Schnitt), '::text || '„verwendet" ist der reine Verderb'::text, round((( SELECT v_schimmel_modell.sockel
               FROM v_schimmel_modell)) * 100::numeric, 2))
            ELSE ''::text
        END AS erlaeuterung
   FROM v_schimmel_kurve k
  ORDER BY von;
