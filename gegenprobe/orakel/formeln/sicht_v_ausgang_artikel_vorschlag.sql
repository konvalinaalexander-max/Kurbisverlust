-- sicht: v_ausgang_artikel_vorschlag
-- Jeder Artikel aus den Importzeilen mit Vorschlag und Bestätigung. Die vorgeschlagene Sorte stammt aus den Zeilen, die eine eigene Chargennummer tragen — beobachtet, nicht geraten.

 WITH zeile_charge AS (
         SELECT z.id,
            z.artikel_id,
            z.artikel,
            z.datum,
            z.kg_charge,
            c.nr AS charge_nr,
            c.sorte
           FROM ausgang_zeile z
             CROSS JOIN LATERAL ( SELECT NULLIF(regexp_replace(z.charge_extern, '\D'::text, ''::text, 'g'::text), ''::text)::bigint AS nummer) x
             LEFT JOIN LATERAL ( SELECT c_1.nr,
                    c_1.sorte
                   FROM charge c_1
                  WHERE x.nummer IS NOT NULL AND (c_1.nr = x.nummer OR c_1.perigon_nr = x.nummer)
                  ORDER BY (c_1.nr = x.nummer) DESC, c_1.nr
                 LIMIT 1) c ON true
        ), beobachtet AS (
         SELECT zeile_charge.artikel_id,
            zeile_charge.artikel,
            count(*)::integer AS zeilen,
            min(zeile_charge.datum) AS von,
            max(zeile_charge.datum) AS bis,
            sum(zeile_charge.kg_charge) AS kg,
            count(*) FILTER (WHERE zeile_charge.charge_nr IS NOT NULL)::integer AS zeilen_mit_charge
           FROM zeile_charge
          GROUP BY zeile_charge.artikel_id, zeile_charge.artikel
        ), sorte_je_artikel AS (
         SELECT DISTINCT ON (zeile_charge.artikel_id, zeile_charge.artikel) zeile_charge.artikel_id,
            zeile_charge.artikel,
            zeile_charge.sorte,
            count(*)::integer AS n
           FROM zeile_charge
          WHERE zeile_charge.charge_nr IS NOT NULL
          GROUP BY zeile_charge.artikel_id, zeile_charge.artikel, zeile_charge.sorte
          ORDER BY zeile_charge.artikel_id, zeile_charge.artikel, (count(*)) DESC, zeile_charge.sorte
        )
 SELECT b.artikel_id,
    b.artikel,
    b.zeilen,
    b.von,
    b.bis,
    zahl(b.kg, 1, '10000000000000'::numeric)::numeric(14,1) AS kg,
    b.zeilen_mit_charge,
    a.ist_kuerbis AS bestaetigt_kuerbis,
    a.sorte AS bestaetigte_sorte,
    a.artikel_id IS NOT NULL AS bestaetigt,
    lower((b.artikel_id || ' '::text) || b.artikel) ~ 'k(ü|u|ue)rb'::text AND lower((b.artikel_id || ' '::text) || b.artikel) !~ '(verrechnung|arbeit|lohn|transport|miete)'::text AS vorschlag_kuerbis,
    s.sorte AS vorschlag_sorte,
    s.n AS vorschlag_belege
   FROM beobachtet b
     LEFT JOIN ausgang_artikel a ON a.artikel_id = b.artikel_id AND a.artikel = b.artikel
     LEFT JOIN sorte_je_artikel s ON s.artikel_id = b.artikel_id AND s.artikel = b.artikel;
