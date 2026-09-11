-- sicht: v_ausgang_kennzahl
-- Je fertiger Palette: Kilo je Kiste, der Überschuss über das Sollgewicht (nur Kiste ab x kg — sonst NULL) und bei Stück-Kisten die Erwartung je Kiste aus dem mittleren Stückgewicht des Kalibers in der Sortier-CSV (0060).

 WITH band_mittel AS (
         SELECT c_1.sorte,
            sg.kaliber_idx,
            sum(sg.anzahl::bigint * sg.gewicht_g) / NULLIF(sum(sg.anzahl), 0)::numeric AS gramm
           FROM sortier_gewicht sg
             JOIN sortier_lauf l ON l.id = sg.lauf_id
             JOIN charge c_1 ON c_1.nr = l.charge_nr
          WHERE sg.klasse = 'kaliber'::kuerbis_klasse AND sg.kaliber_idx IS NOT NULL
          GROUP BY c_1.sorte, sg.kaliber_idx
        )
 SELECT w.id,
    w.auftrag_id,
    w.charge_nr,
    c.sorte,
    c.schlag,
    w.ts,
    w.brutto_kg,
    w.kisten,
    w.gebindeart,
    w.kuerbisse_pro_kiste,
    n.netto_kg,
    zahl(n.netto_kg / w.kisten::numeric, 3, '10000000'::numeric)::numeric(10,3) AS kg_pro_kiste,
    zahl(n.netto_kg / NULLIF(w.kisten * w.kuerbisse_pro_kiste, 0)::numeric, 3, '10000000'::numeric)::numeric(10,3) AS kg_pro_kuerbis,
    s.soll AS soll_kg_pro_kiste,
    zahl(
        CASE
            WHEN s.soll IS NOT NULL THEN n.netto_kg / w.kisten::numeric - s.soll
            ELSE NULL::numeric
        END, 3, '10000000'::numeric)::numeric(10,3) AS ueberfuellung_je_kiste,
    zahl(
        CASE
            WHEN s.soll IS NOT NULL THEN n.netto_kg - w.kisten::numeric * s.soll
            ELSE NULL::numeric
        END, 2, '100000000'::numeric)::numeric(10,2) AS ueberfuellung_kg,
    COALESCE(a.kistensystem,
        CASE
            WHEN ss.art = 'kiste'::text THEN 'kiste_ab'::text
            ELSE NULL::text
        END) AS kistensystem,
    w.kaliber_idx,
    e.stueck AS stueck_je_kiste,
    zahl(e.stueck::numeric * bm.gramm / 1000.0, 3, '10000000'::numeric)::numeric(10,3) AS erwartet_kg_pro_kiste,
    zahl(n.netto_kg / w.kisten::numeric - e.stueck::numeric * bm.gramm / 1000.0, 3, '10000000'::numeric)::numeric(10,3) AS abweichung_je_kiste,
    zahl(bm.gramm, 0, '1000000'::numeric)::numeric(8,0) AS band_mittel_g
   FROM ausgang_wiegung w
     JOIN auftrag a ON a.id = w.auftrag_id
     JOIN charge c ON c.nr = w.charge_nr
     LEFT JOIN gebinde g ON g.art = w.gebindeart
     LEFT JOIN sortierschema ss ON ss.id = a.sortierschema_id
     CROSS JOIN LATERAL ( SELECT zahl(w.brutto_kg - w.kisten::numeric * g.tara_kg_pro_kiste - COALESCE(g.tara_kg_palette, 0::numeric), 2, '100000000'::numeric)::numeric(10,2) AS netto_kg) n
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN a.kistensystem = 'kiste_ab'::text THEN a.soll_kg_pro_kiste
                    WHEN a.kistensystem IS NULL AND ss.art = 'kiste'::text THEN ss.soll_kg_pro_kiste
                    ELSE NULL::numeric
                END AS soll) s
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN a.kistensystem = 'stueck'::text THEN COALESCE(w.kuerbisse_pro_kiste, a.stueck_je_kiste)
                    ELSE NULL::integer
                END AS stueck) e
     LEFT JOIN band_mittel bm ON bm.sorte = c.sorte AND bm.kaliber_idx =
        CASE
            WHEN w.kaliber_idx = '-2'::integer THEN NULL::integer
            ELSE COALESCE(w.kaliber_idx, a.kaliber_idx)
        END
  WHERE w.gemessen AND a.abgebrochen_ts IS NULL AND n.netto_kg > 0::numeric;
