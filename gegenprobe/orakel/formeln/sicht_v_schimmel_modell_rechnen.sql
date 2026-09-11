-- sicht: v_schimmel_modell_rechnen
-- Die Anpassung des Verderbsmodells f(t) = 1 - exp(-lambda*t^k), Schritt für Schritt: Steigung, Achsenabschnitt, Streuungen, Kovarianz, t-Faktor. brauchbar sagt, ob genug Messungen dahinterstehen.

 WITH roh AS (
         SELECT b.charge_nr,
            b.lagertage AS t,
            b.anteil AS f,
            b.basis_jetzt_kg AS w,
            b.quelle = 'verarbeitung'::text AS mit_sockel
           FROM mv_schimmel_punkte b
          WHERE b.plausibel AND b.anteil > 0::numeric AND b.anteil < 1::numeric AND b.lagertage > 0::numeric AND (b.quelle = ANY (ARRAY['verarbeitung'::text, 'lager'::text]))
        ), chargen AS (
         SELECT count(DISTINCT roh.charge_nr)::integer AS c
           FROM roh
        ), gitter AS (
         SELECT i.i::numeric * 0.0025 AS a0
           FROM generate_series(0, 40) i(i)
        ), kand AS (
         SELECT g.a0,
            r.charge_nr,
            r.t,
            r.f,
            r.w,
            r.mit_sockel,
            ln(r.t) AS x,
                CASE
                    WHEN r.mit_sockel THEN (r.f - g.a0) / (1::numeric - g.a0)
                    ELSE r.f
                END AS fs
           FROM gitter g
             CROSS JOIN roh r
        ), fit AS (
         SELECT q.a0,
            count(*)::integer AS n,
            count(DISTINCT q.charge_nr)::integer AS c_chargen,
            sum(q.w) AS sw,
            sum(q.w * q.x) AS swx,
            sum(q.w * q.y) AS swy,
            sum(q.w * q.x * q.x) AS swxx,
            sum(q.w * q.x * q.y) AS swxy
           FROM ( SELECT kand.a0,
                    kand.charge_nr,
                    kand.w,
                    kand.x,
                    ln(- ln(1::numeric - kand.fs)) AS y
                   FROM kand
                  WHERE kand.fs > 0::numeric AND kand.fs < 1::numeric) q
          GROUP BY q.a0
        ), param AS (
         SELECT f.a0,
            f.n,
            f.c_chargen,
            f.sw,
            f.swx,
            f.swy,
            f.swxx,
            f.swxy,
                CASE
                    WHEN (f.sw * f.swxx - f.swx * f.swx) <> 0::numeric THEN (f.sw * f.swxy - f.swx * f.swy) / (f.sw * f.swxx - f.swx * f.swx)
                    ELSE NULL::numeric
                END AS k
           FROM fit f
        ), param2 AS (
         SELECT p.a0,
            p.n,
            p.c_chargen,
            p.sw,
            p.swx,
            p.swy,
            p.swxx,
            p.swxy,
            p.k,
                CASE
                    WHEN p.k IS NOT NULL THEN (p.swy - p.k * p.swx) / p.sw
                    ELSE NULL::numeric
                END AS ln_lambda
           FROM param p
        ), smear AS (
         SELECT p.a0,
            sum(k.w * exp(ln(- ln(1::numeric - k.fs)) - (p.ln_lambda + p.k * k.x))) / NULLIF(sum(k.w), 0::numeric) AS s
           FROM param2 p
             JOIN kand k ON k.a0 = p.a0
          WHERE k.fs > 0::numeric AND k.fs < 1::numeric AND p.k IS NOT NULL
          GROUP BY p.a0
        ), guete AS (
         SELECT p.a0,
            p.n,
            p.c_chargen,
            p.k,
            p.ln_lambda,
            s.s AS smearing,
            sum(k.w * power(k.f - (
                CASE
                    WHEN k.mit_sockel THEN p.a0
                    ELSE 0::numeric
                END + (1::numeric -
                CASE
                    WHEN k.mit_sockel THEN p.a0
                    ELSE 0::numeric
                END) * (1::numeric - exp(- exp(LEAST(GREATEST(p.ln_lambda + ln(GREATEST(s.s, 0.01)) + p.k * k.x, '-40'::integer::numeric), 3::numeric))))), 2::numeric)) AS sse
           FROM param2 p
             JOIN smear s ON s.a0 = p.a0
             JOIN kand k ON k.a0 = p.a0
          WHERE p.k IS NOT NULL AND p.k > 0::numeric AND p.n >= 3
          GROUP BY p.a0, p.n, p.c_chargen, p.k, p.ln_lambda, s.s
        ), schwelle AS (
         SELECT 1::numeric + power(t_quantil_95(GREATEST(c.c - 3, 1)), 2::numeric) / GREATEST(c.c - 3, 1)::numeric AS faktor
           FROM chargen c
        ), wahl AS (
         SELECT g.a0,
            g.n,
            g.c_chargen,
            g.k,
            g.ln_lambda,
            g.smearing,
            g.sse
           FROM guete g
          WHERE g.sse <= ((( SELECT min(guete.sse) AS min
                   FROM guete)) * 1.01) AND (( SELECT guete.sse
                   FROM guete
                  WHERE guete.a0 = 0::numeric)) > ((( SELECT min(guete.sse) AS min
                   FROM guete)) * (( SELECT schwelle.faktor
                   FROM schwelle)))
          ORDER BY g.a0
         LIMIT 1
        ), gewaehlt AS (
         SELECT COALESCE(( SELECT wahl.a0
                   FROM wahl), 0::numeric) AS a0,
            COALESCE(( SELECT wahl.sse
                   FROM wahl), ( SELECT guete.sse
                   FROM guete
                  WHERE guete.a0 = 0::numeric)) AS sse,
            COALESCE(( SELECT wahl.n
                   FROM wahl), ( SELECT guete.n
                   FROM guete
                  WHERE guete.a0 = 0::numeric)) AS n_wahl
        ), grenzen AS (
         SELECT COALESCE(min(g.a0), w.a0) AS a0_unten,
            COALESCE(max(g.a0), w.a0) AS a0_oben
           FROM gewaehlt w
             LEFT JOIN guete g ON g.sse <= (w.sse * (( SELECT schwelle.faktor
                   FROM schwelle)))
          GROUP BY w.a0
        ), punkte AS (
         SELECT k.charge_nr,
            k.x,
            ln(- ln(1::numeric - k.fs)) AS y,
            k.w,
            k.t
           FROM kand k,
            gewaehlt g
          WHERE k.a0 = g.a0 AND k.fs > 0::numeric AND k.fs < 1::numeric
        ), summen AS (
         SELECT count(*)::integer AS n,
            count(DISTINCT punkte.charge_nr)::integer AS c_chargen,
            min(punkte.t) AS t_min,
            max(punkte.t) AS t_max,
            sum(punkte.w) AS sw,
            sum(punkte.w * punkte.x) AS swx,
            sum(punkte.w * punkte.y) AS swy,
            sum(punkte.w * punkte.x * punkte.x) AS swxx,
            sum(punkte.w * punkte.x * punkte.y) AS swxy
           FROM punkte
        ), fit2 AS (
         SELECT s.n,
            s.c_chargen,
            s.t_min,
            s.t_max,
            s.sw,
            s.swx,
            s.swy,
            s.swxx,
            s.swxy,
                CASE
                    WHEN (s.sw * s.swxx - s.swx * s.swx) <> 0::numeric THEN (s.sw * s.swxy - s.swx * s.swy) / (s.sw * s.swxx - s.swx * s.swx)
                    ELSE NULL::numeric
                END AS k,
            s.swx / NULLIF(s.sw, 0::numeric) AS x_mittel
           FROM summen s
        ), mit_achse AS (
         SELECT f.n,
            f.c_chargen,
            f.t_min,
            f.t_max,
            f.sw,
            f.swx,
            f.swy,
            f.swxx,
            f.swxy,
            f.k,
            f.x_mittel,
                CASE
                    WHEN f.k IS NOT NULL THEN (f.swy - f.k * f.swx) / f.sw
                    ELSE NULL::numeric
                END AS ln_lambda
           FROM fit2 f
        ), rest AS (
         SELECT m.n,
            m.c_chargen,
            m.t_min,
            m.t_max,
            m.sw,
            m.swx,
            m.swy,
            m.swxx,
            m.swxy,
            m.k,
            m.x_mittel,
            m.ln_lambda,
            ( SELECT sum(p.w * power(p.x - m.x_mittel, 2::numeric)) AS sum
                   FROM punkte p) AS sxx,
            ( SELECT sum(p.w * power(p.y - (m.ln_lambda + m.k * p.x), 2::numeric)) AS sum
                   FROM punkte p) AS sse,
            ( SELECT sum(p.w * exp(p.y - (m.ln_lambda + m.k * p.x))) / NULLIF(sum(p.w), 0::numeric)
                   FROM punkte p) AS smearing
           FROM mit_achse m
        ), gruppen AS (
         SELECT r.n,
            r.c_chargen,
            r.t_min,
            r.t_max,
            r.sw,
            r.swx,
            r.swy,
            r.swxx,
            r.swxy,
            r.k,
            r.x_mittel,
            r.ln_lambda,
            r.sxx,
            r.sse,
            r.smearing,
            g.saa,
            g.skk,
            g.sak
           FROM rest r
             CROSS JOIN LATERAL ( SELECT sum(power(c.ga, 2::numeric)) AS saa,
                    sum(power(c.gk, 2::numeric)) AS skk,
                    sum(c.ga * c.gk) AS sak
                   FROM ( SELECT p.charge_nr,
                            sum(p.w * (p.y - (r.ln_lambda + r.k * p.x))) AS ga,
                            sum(p.w * (p.x - r.x_mittel) * (p.y - (r.ln_lambda + r.k * p.x))) AS gk
                           FROM punkte p
                          GROUP BY p.charge_nr) c) g
        )
 SELECT n,
    c_chargen,
    t_min,
    t_max,
    k,
    ln_lambda,
    exp(ln_lambda) AS lambda,
    x_mittel,
    sxx,
    smearing,
    ln_lambda + ln(GREATEST(smearing, 0.01)) AS ln_lambda_korrigiert,
        CASE
            WHEN n > 2 THEN sse / (n - 2)::numeric * n::numeric / NULLIF(sw, 0::numeric)
            ELSE NULL::numeric
        END AS sigma2,
        CASE
            WHEN c_chargen > 1 THEN saa / power(sw, 2::numeric) * c_chargen::numeric / (c_chargen - 1)::numeric
            ELSE NULL::numeric
        END AS var_achse,
        CASE
            WHEN c_chargen > 1 AND sxx <> 0::numeric THEN skk / power(sxx, 2::numeric) * c_chargen::numeric / (c_chargen - 1)::numeric
            ELSE NULL::numeric
        END AS var_k,
        CASE
            WHEN c_chargen > 1 AND sxx <> 0::numeric THEN sak / (sw * sxx) * c_chargen::numeric / (c_chargen - 1)::numeric
            ELSE NULL::numeric
        END AS kov_achse_k,
    t_quantil_95(c_chargen - 1) AS t_faktor,
    n >= 3 AND c_chargen >= 3 AND k IS NOT NULL AND k > 0::numeric AND t_max > (t_min * 1.5) AS brauchbar,
    ( SELECT
                CASE
                    WHEN count(*) FILTER (WHERE p.mit_sockel = false) >= 5 THEN GREATEST(abs(sum(p.w * p.e) FILTER (WHERE NOT p.mit_sockel) / NULLIF(sum(p.w) FILTER (WHERE NOT p.mit_sockel), 0::numeric) - sum(p.w * p.e) FILTER (WHERE p.mit_sockel) / NULLIF(sum(p.w) FILTER (WHERE p.mit_sockel), 0::numeric))::double precision - (1.96 * stddev_samp(p.e) FILTER (WHERE NOT p.mit_sockel))::double precision / sqrt(count(*) FILTER (WHERE NOT p.mit_sockel)::double precision), 0::double precision)::numeric
                    ELSE NULL::numeric
                END AS "case"
           FROM ( SELECT k.mit_sockel,
                    k.w,
                    ln(- ln(1::numeric - k.fs)) - (gruppen.ln_lambda + gruppen.k * k.x) AS e
                   FROM kand k,
                    gewaehlt g
                  WHERE k.a0 = g.a0 AND k.fs > 0::numeric AND k.fs < 1::numeric) p) AS selektions_versatz,
    ( SELECT gewaehlt.a0
           FROM gewaehlt) AS sockel,
    ( SELECT grenzen.a0_unten
           FROM grenzen) AS sockel_unten,
    ( SELECT grenzen.a0_oben
           FROM grenzen) AS sockel_oben,
    zahl((( SELECT guete.sse
           FROM guete
          WHERE guete.a0 = 0::numeric)) / NULLIF(( SELECT min(guete.sse) AS min
           FROM guete), 0::numeric), 3, '10000000'::numeric)::numeric(10,3) AS sockel_nachweis,
    zahl(( SELECT schwelle.faktor
           FROM schwelle), 3, '10000000'::numeric)::numeric(10,3) AS sockel_schwelle,
    power(((( SELECT grenzen.a0_oben
           FROM grenzen)) - (( SELECT grenzen.a0_unten
           FROM grenzen))) / 2.0 / NULLIF(t_quantil_95(c_chargen - 1), 0::numeric), 2::numeric) AS sockel_var
   FROM gruppen;
