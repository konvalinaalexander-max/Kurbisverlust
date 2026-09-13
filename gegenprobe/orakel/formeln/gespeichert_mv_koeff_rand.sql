-- gespeichert: mv_koeff_rand
-- Die Ränder der Koeffizienten je Sorte (Verdunstung, zu klein, zu gross, Fax), geklammert wie in der Kaskade — die Grundlage der Hülle in v_prognose. Erneuert mit auswertung_schritt(2) (0071).

 SELECT b.sorte,
    LEAST(GREATEST(COALESCE(kv.unten::numeric, 0::numeric), 0::numeric), 0.05) AS r_unten,
    LEAST(GREATEST(COALESCE(kv.oben::numeric, 0::numeric), 0::numeric), 0.05) AS r_oben,
    LEAST(GREATEST(COALESCE(ka.unten::numeric, 0::numeric), 0::numeric), 1::numeric) AS klein_unten,
    LEAST(GREATEST(COALESCE(ka.oben::numeric, 0::numeric), 0::numeric), 1::numeric) AS klein_oben,
    LEAST(GREATEST(COALESCE(kn.unten::numeric, 0::numeric), 0::numeric), 1::numeric) AS gross_unten,
    LEAST(GREATEST(COALESCE(kn.oben::numeric, 0::numeric), 0::numeric), 1::numeric) AS gross_oben,
    LEAST(GREATEST(COALESCE(kf.unten::numeric, 0::numeric), 0::numeric), 1::numeric) AS fax_unten,
    LEAST(GREATEST(COALESCE(kf.oben::numeric, 0::numeric), 0::numeric), 1::numeric) AS fax_oben
   FROM ( SELECT DISTINCT v_kaskade_basis.sorte
           FROM v_kaskade_basis) b
     LEFT JOIN v_koeff_verdunstung kv ON kv.sorte = b.sorte
     LEFT JOIN v_koeff_ausschuss ka ON ka.sorte = b.sorte
     LEFT JOIN v_koeff_nebenkanal kn ON kn.sorte = b.sorte
     LEFT JOIN v_koeff_fax kf ON kf.sorte = b.sorte;
