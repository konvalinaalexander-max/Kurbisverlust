-- sicht: v_selektionsverdacht
-- Prüft, ob beim Messen unbewusst ausgewählt wurde: Bleibt bei Chargen, die gerade verarbeitet werden, systematisch anderes übrig als bei denen im Lager? unterschied und befund sagen, ob der Verdacht trägt.

 WITH rest AS (
         SELECT p.quelle,
            p.basis_jetzt_kg AS w,
            ln(- ln(1::numeric - x.fs)) - (m.ln_lambda + m.k * ln(p.lagertage)) AS e
           FROM mv_schimmel_punkte p
             CROSS JOIN v_schimmel_modell m
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN p.quelle = 'verarbeitung'::text THEN (p.anteil - m.sockel) / (1::numeric - m.sockel)
                            ELSE p.anteil
                        END AS fs) x
          WHERE m.brauchbar AND p.plausibel AND x.fs > 0::numeric AND x.fs < 1::numeric AND p.lagertage > 0::numeric
        ), je_quelle AS (
         SELECT rest.quelle,
            count(*)::integer AS n,
            sum(rest.w * rest.e) / NULLIF(sum(rest.w), 0::numeric) AS mittel
           FROM rest
          GROUP BY rest.quelle
        )
 SELECT ( SELECT je_quelle.n
           FROM je_quelle
          WHERE je_quelle.quelle = 'verarbeitung'::text) AS n_verarbeitung,
    ( SELECT je_quelle.n
           FROM je_quelle
          WHERE je_quelle.quelle = 'lager'::text) AS n_lager,
    ( SELECT je_quelle.mittel
           FROM je_quelle
          WHERE je_quelle.quelle = 'verarbeitung'::text) AS rest_verarbeitung,
    ( SELECT je_quelle.mittel
           FROM je_quelle
          WHERE je_quelle.quelle = 'lager'::text) AS rest_lager,
    (( SELECT je_quelle.mittel
           FROM je_quelle
          WHERE je_quelle.quelle = 'lager'::text)) - (( SELECT je_quelle.mittel
           FROM je_quelle
          WHERE je_quelle.quelle = 'verarbeitung'::text)) AS unterschied,
        CASE
            WHEN (( SELECT je_quelle.n
               FROM je_quelle
              WHERE je_quelle.quelle = 'lager'::text)) IS NULL THEN 'keine Lagerkontrollen — Selektion nicht prüfbar'::text
            WHEN (( SELECT je_quelle.n
               FROM je_quelle
              WHERE je_quelle.quelle = 'lager'::text)) < 5 THEN 'zu wenige Lagerkontrollen für eine Aussage'::text
            WHEN abs((( SELECT je_quelle.mittel
               FROM je_quelle
              WHERE je_quelle.quelle = 'lager'::text)) - (( SELECT je_quelle.mittel
               FROM je_quelle
              WHERE je_quelle.quelle = 'verarbeitung'::text))) > 0.2 THEN ((('verarbeitete und zufällig gegriffene Paletten sagen Verschiedenes — '::text || 'es wird nach Aussehen ausgewählt. Bei gleichem Alter sind die '::text) || 'verarbeiteten fauler, dafür bleibt am Ende die robustere Ware '::text) || 'liegen: der Verlauf wird zu flach und die Hochrechnung auf lange '::text) || 'Lagerdauern zu niedrig. Mehr Lagerkontrollen beheben das.'::text
            ELSE 'beide Quellen sagen dasselbe — kein Hinweis auf Selektion'::text
        END AS befund;
