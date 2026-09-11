-- sicht: v_koeff_gebinde
-- Wie viel eine Kiste wiegt, je Sorte und Kaliber — gemessen am Sortieren aus CSV-Masse und gezählten Kisten. Kaliber −1: Kisten nach Sollgewicht, gemessen an den gewogenen fertigen Paletten. Ohne Messung steht hier keine Zeile.

 WITH gezaehlt AS (
         SELECT auftrag_gebinde.auftrag_id,
            auftrag_gebinde.kaliber_idx,
            sum(auftrag_gebinde.anzahl)::integer AS anzahl
           FROM auftrag_gebinde
          GROUP BY auftrag_gebinde.auftrag_id, auftrag_gebinde.kaliber_idx
        ), je_arbeit AS (
         SELECT a.id AS auftrag_id,
            c.sorte,
            g.kaliber_idx,
            g.anzahl,
            sum(sg.anzahl::bigint * sg.gewicht_g) / 1000.0 AS kg
           FROM gezaehlt g
             JOIN auftrag a ON a.id = g.auftrag_id AND a.abgebrochen_ts IS NULL
             JOIN charge c ON c.nr = a.charge_nr
             JOIN sortier_lauf l ON l.auftrag_id = a.id
             JOIN sortier_gewicht sg ON sg.lauf_id = l.id AND sg.klasse = 'kaliber'::kuerbis_klasse AND sg.kaliber_idx = g.kaliber_idx
          WHERE (a.station = ANY (ARRAY['sortieren'::station, 'waschen_sortieren'::station])) AND g.anzahl > 0
          GROUP BY a.id, c.sorte, g.kaliber_idx, g.anzahl
        ), s AS (
         SELECT je_arbeit.sorte,
            je_arbeit.kaliber_idx,
            count(*)::integer AS n,
            sum(je_arbeit.kg) / NULLIF(sum(je_arbeit.anzahl), 0)::numeric AS kg_je_gebinde,
            stddev_samp(je_arbeit.kg / je_arbeit.anzahl::numeric) AS sd
           FROM je_arbeit
          GROUP BY je_arbeit.sorte, je_arbeit.kaliber_idx
        UNION ALL
         SELECT k.sorte,
            '-1'::integer,
            count(*)::integer AS count,
            sum(k.netto_kg) / NULLIF(sum(k.kisten), 0)::numeric,
            stddev_samp(k.kg_pro_kiste) AS stddev_samp
           FROM v_ausgang_kennzahl k
          WHERE k.soll_kg_pro_kiste IS NOT NULL OR k.kistensystem = 'kiste_ab'::text
          GROUP BY k.sorte
        )
 SELECT sorte,
    kaliber_idx,
    n,
    zahl(kg_je_gebinde, 3, '10000000'::numeric)::numeric(10,3) AS kg_je_gebinde,
    zahl(sd, 3, '10000000'::numeric)::numeric(10,3) AS sd,
    zahl(
        CASE
            WHEN sd IS NULL OR n < 2 THEN kg_je_gebinde::double precision
            ELSE GREATEST(kg_je_gebinde::double precision - (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision), 0::double precision)
        END, 3, '10000000'::numeric)::numeric(10,3) AS unten,
    zahl(
        CASE
            WHEN sd IS NULL OR n < 2 THEN kg_je_gebinde::double precision
            ELSE kg_je_gebinde::double precision + (t_quantil_95(n - 1) * sd)::double precision / sqrt(n::double precision)
        END, 3, '10000000'::numeric)::numeric(10,3) AS oben
   FROM s
  WHERE kg_je_gebinde IS NOT NULL;
