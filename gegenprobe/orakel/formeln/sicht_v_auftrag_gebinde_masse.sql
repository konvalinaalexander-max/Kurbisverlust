-- sicht: v_auftrag_gebinde_masse
-- Verarbeitete Menge einer Wascharbeit aus gezählten Kisten mal gemessenem Kistengewicht. kg ist NULL, solange das Kaliber nie am Sortieren gezählt wurde — dann fehlt der Nenner weiterhin. Index −2 (eigenes Kaliber) findet sein Gewicht über die Bandgrenzen in einer Fassung der Sorte (0054).

 WITH band AS (
         SELECT DISTINCT s.sorte,
            i.idx AS kaliber_idx,
            ((s.kaliber_baender -> i.idx) ->> 0)::integer AS von,
            ((s.kaliber_baender -> i.idx) ->> 1)::integer AS bis
           FROM sortierschema s
             CROSS JOIN LATERAL generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) i(idx)
          WHERE s.art = 'kaliber'::text AND s.kaliber_baender IS NOT NULL
        ), gezaehlt AS (
         SELECT auftrag_gebinde.auftrag_id,
            auftrag_gebinde.kaliber_idx,
            sum(auftrag_gebinde.anzahl)::integer AS anzahl
           FROM auftrag_gebinde
          GROUP BY auftrag_gebinde.auftrag_id, auftrag_gebinde.kaliber_idx
        )
 SELECT a.id AS auftrag_id,
    g.kaliber_idx,
    g.anzahl,
    zahl(g.anzahl::numeric * k.kg_je_gebinde, 2, '10000000000'::numeric)::numeric(12,2) AS kg,
    zahl(g.anzahl::numeric * k.unten, 2, '10000000000'::numeric)::numeric(12,2) AS kg_unten,
    zahl(g.anzahl::numeric * k.oben, 2, '10000000000'::numeric)::numeric(12,2) AS kg_oben,
    k.n AS n_messungen
   FROM auftrag a
     JOIN charge c ON c.nr = a.charge_nr
     JOIN gezaehlt g ON g.auftrag_id = a.id
     LEFT JOIN LATERAL ( SELECT b.kaliber_idx
           FROM band b
          WHERE g.kaliber_idx = '-2'::integer AND b.sorte = c.sorte AND b.von = a.kaliber_von_g AND b.bis = a.kaliber_bis_g
          ORDER BY b.kaliber_idx
         LIMIT 1) e ON true
     LEFT JOIN v_koeff_gebinde k ON k.sorte = c.sorte AND k.kaliber_idx =
        CASE
            WHEN g.kaliber_idx = '-2'::integer THEN e.kaliber_idx
            ELSE g.kaliber_idx
        END
  WHERE a.station = 'waschen'::station AND a.abgebrochen_ts IS NULL;
