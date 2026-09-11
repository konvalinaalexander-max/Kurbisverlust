-- sicht: v_verkauf_lieferung
-- Jede importierte Verkaufslieferung mit dem Kistensystem aus der Datei (Einheit × Gebindeinhalt): Kiste ab x kg, Stück je Kiste mit Nenngewicht, oder unbekannt. kisten aus der Chargenzeile (zeile), dem Rest der Position (rest) oder anteilig an der Position (anteil). Von Hand erfasste Lieferungen stehen nicht hier (0061).

 WITH "position" AS (
         SELECT ausgang_zeile.quelle,
            ausgang_zeile.pos_id,
            max(ausgang_zeile.gebinde_menge) AS gebinde_menge,
            max(ausgang_zeile.kg_position) AS kg_position,
            sum(ausgang_zeile.batch_gebinde) FILTER (WHERE ausgang_zeile.charge_extern <> ''::text) AS batch_gebinde_summe,
            bool_and(ausgang_zeile.batch_gebinde IS NOT NULL) FILTER (WHERE ausgang_zeile.charge_extern <> ''::text) AS alle_gezaehlt
           FROM ausgang_zeile
          GROUP BY ausgang_zeile.quelle, ausgang_zeile.pos_id
        ), band AS (
         SELECT DISTINCT ON (s.sorte, i_1.idx) s.sorte,
            i_1.idx AS kaliber_idx,
            ((s.kaliber_baender -> i_1.idx) ->> 0)::integer AS von,
            ((s.kaliber_baender -> i_1.idx) ->> 1)::integer AS bis
           FROM sortierschema s
             CROSS JOIN LATERAL generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) i_1(idx)
          WHERE s.art = 'kaliber'::text AND s.kaliber_baender IS NOT NULL AND s.kaeufer IS NULL AND s.gilt_ab <= heute()
          ORDER BY s.sorte, i_1.idx, s.gilt_ab DESC
        )
 SELECT l.id AS lieferung_id,
    l.datum,
    l.charge_nr,
    COALESCE(l.sorte, c.sorte) AS sorte,
    l.kg,
    i.quelle,
    z.artikel,
    z.einheit,
    z.gebinde_inhalt,
    z.gewicht_je_artikel,
    ks.kistensystem,
        CASE
            WHEN ks.kistensystem = 'kiste_ab'::text THEN zahl(z.gebinde_inhalt::double precision, 2, '10000'::numeric)::numeric(6,2)
            ELSE NULL::numeric
        END AS soll_kg_pro_kiste,
        CASE
            WHEN ks.kistensystem = 'stueck'::text THEN z.gebinde_inhalt
            ELSE NULL::integer
        END AS stueck_je_kiste,
        CASE
            WHEN ks.kistensystem = 'stueck'::text THEN round(z.gewicht_je_artikel * 1000::numeric)::integer
            ELSE NULL::integer
        END AS nenn_g,
        CASE
            WHEN ks.kistensystem = 'stueck'::text THEN b.kaliber_idx
            ELSE NULL::integer
        END AS kaliber_idx,
    zahl(k.kisten, 1, '10000000'::numeric)::numeric(10,1) AS kisten,
    k.kisten_quelle,
        CASE
            WHEN ks.kistensystem = 'stueck'::text THEN zahl(k.kisten * z.gebinde_inhalt::numeric, 0, '1000000000'::numeric)::numeric(12,0)
            ELSE NULL::numeric
        END AS stueck
   FROM lieferung l
     JOIN lieferung_import i ON i.lieferung_id = l.id
     JOIN ausgang_zeile z ON z.id = i.zeile_id
     JOIN "position" p ON p.quelle = z.quelle AND p.pos_id = z.pos_id
     LEFT JOIN charge c ON c.nr = l.charge_nr
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN z.einheit ~* '^stk'::text AND COALESCE(z.gebinde_inhalt, 0) > 0 AND COALESCE(z.gewicht_je_artikel, 0::numeric) > 0::numeric THEN 'stueck'::text
                    WHEN z.einheit ~* '^kg'::text AND COALESCE(z.gebinde_inhalt, 0) > 1 THEN 'kiste_ab'::text
                    ELSE 'unbekannt'::text
                END AS kistensystem) ks
     LEFT JOIN band b ON ks.kistensystem = 'stueck'::text AND b.sorte = COALESCE(l.sorte, c.sorte) AND round(z.gewicht_je_artikel * 1000::numeric) >= b.von::numeric AND round(z.gewicht_je_artikel * 1000::numeric) < b.bis::numeric
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN i.extern_id !~~ '%:rest'::text AND z.batch_gebinde > 0 THEN z.batch_gebinde::numeric
                    WHEN i.extern_id ~~ '%:rest'::text AND COALESCE(p.alle_gezaehlt, true) AND p.gebinde_menge > 0 THEN GREATEST(p.gebinde_menge - COALESCE(p.batch_gebinde_summe, 0::bigint), 0::bigint)::numeric
                    WHEN p.gebinde_menge > 0 AND p.kg_position > 0::numeric THEN p.gebinde_menge::numeric * l.kg / p.kg_position
                    ELSE NULL::numeric
                END AS kisten,
                CASE
                    WHEN i.extern_id !~~ '%:rest'::text AND z.batch_gebinde > 0 THEN 'zeile'::text
                    WHEN i.extern_id ~~ '%:rest'::text AND COALESCE(p.alle_gezaehlt, true) AND p.gebinde_menge > 0 THEN 'rest'::text
                    WHEN p.gebinde_menge > 0 AND p.kg_position > 0::numeric THEN 'anteil'::text
                    ELSE NULL::text
                END AS kisten_quelle) k
  WHERE l.ziel = 'verkauf'::text AND ks.kistensystem IS NOT NULL;
