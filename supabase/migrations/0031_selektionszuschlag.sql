-- =====================================================================
-- 0031 — Was sich nicht wegrechnen lässt, gehört in den Bereich
--
-- Wird zuerst verarbeitet, was schlecht aussieht, dann misst man die
-- schlechtere Hälfte der Ernte. In der Simulation, mitten in der Saison:
--
--   verarbeitete Paletten   mittlere Anfälligkeit  1.52
--   noch im Lager stehende  mittlere Anfälligkeit  0.80
--
-- Ich habe versucht, das zu korrigieren — die Kurve für stehende Ware um den
-- gemessenen Unterschied zu verschieben. Es hat nicht funktioniert, und der
-- Grund ist lehrreich genug, um ihn festzuhalten:
--
--   ohne Lagerkontrollen, ohne Korrektur   +13.3 %
--   mit Lagerkontrollen, ohne Korrektur    +14.3 %
--   mit Lagerkontrollen und Korrektur      −15.2 %
--
-- Der Versatz dreht das Vorzeichen, ohne den Betrag zu verkleinern. Die
-- Selektion verbiegt nämlich nicht die *Höhe* der Kurve, sondern ihre
-- *Steigung*: Anfällige Paletten werden früh gemessen, robuste spät, und die
-- angepasste Steigung k fiel dabei von wahren 1.6 auf 1.14. Einen falschen
-- Anstieg repariert kein Niveau-Versatz. Die Korrektur ist deshalb wieder
-- entfernt worden, statt Komplexität zu behalten, die nichts einbringt.
--
-- Was bleibt, ist die ehrliche Konsequenz: Wenn beide Quellen Verschiedenes
-- sagen, wissen wir, dass die Schimmelzahl für die stehende Ware daneben liegt
-- — nur nicht, in welche Richtung. Genau das ist ein Fall für den Bereich.
-- Der Zuschlag beträgt den gemessenen Unterschied, angewandt auf den Teil des
-- Schimmels, der auf noch stehende Ware entfällt.
--
-- Ohne Lagerkontrollen bleibt der Zuschlag 0 — dann ist die Selektion nicht
-- einmal prüfbar, und das Dashboard sagt genau das (v_selektionsverdacht).
-- =====================================================================

create or replace view v_schimmel_modell with (security_invoker = true) as
WITH beob AS (
         SELECT b.charge_nr,
            b.lagertage AS t,
            b.anteil AS f,
            b.basis_jetzt_kg AS gewicht
           FROM mv_schimmel_punkte b
          WHERE b.plausibel AND b.anteil > 0::numeric AND b.anteil < 1::numeric AND b.lagertage > 0::numeric
        ), punkte AS (
         SELECT beob.charge_nr,
            ln(beob.t) AS x,
            ln(- ln(1::numeric - beob.f)) AS y,
            beob.gewicht AS w,
            beob.t
           FROM beob
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
        ), fit AS (
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
           FROM fit f
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
    -- Wie weit sagen zufällig gegriffene und nach Aussehen ausgewählte Ware
    -- Verschiedenes? Im Log-Raum, erst ab fünf Kontrollen.
    ( SELECT CASE WHEN count(*) FILTER (WHERE p.quelle = 'lager') >= 5
                  -- Der blosse Betrag einer verrauschten Differenz ist immer
                  -- grösser als null, auch wenn gar kein Unterschied besteht.
                  -- Deshalb wird der eigene Standardfehler abgezogen: Es bleibt
                  -- nur, was sich nicht durch Zufall erklären lässt.
                  THEN greatest(
                    abs(sum(p.w * p.e) FILTER (WHERE p.quelle = 'lager')
                          / NULLIF(sum(p.w) FILTER (WHERE p.quelle = 'lager'), 0)
                      - sum(p.w * p.e) FILTER (WHERE p.quelle = 'verarbeitung')
                          / NULLIF(sum(p.w) FILTER (WHERE p.quelle = 'verarbeitung'), 0))
                    - 1.96 * stddev_samp(p.e) FILTER (WHERE p.quelle = 'lager')
                             / sqrt(count(*) FILTER (WHERE p.quelle = 'lager')), 0)::numeric
             END
        FROM ( SELECT b.quelle, b.basis_jetzt_kg::numeric AS w,
                      ln(-ln(1::numeric - b.anteil::numeric))
                        - (gruppen.ln_lambda + gruppen.k * ln(b.lagertage::numeric)) AS e
                 FROM mv_schimmel_punkte b
                WHERE b.plausibel AND b.anteil > 0::numeric AND b.anteil < 1::numeric
                  AND b.lagertage > 0::numeric) p) AS selektions_versatz
   FROM gruppen;;

comment on view v_schimmel_modell is
  'Verderbsmodell F(t) = 1 − exp(−λ·S·t^k), chargen-robust gefehlert. '
  'selektions_versatz ist der gemessene Unterschied zwischen zufällig '
  'gegriffener und nach Aussehen ausgewählter Ware — er lässt sich nicht '
  'herausrechnen, geht aber in den ausgewiesenen Bereich ein.';

CREATE OR REPLACE FUNCTION public.verlust_ranking(p_sorte text DEFAULT NULL::text, p_schlag text DEFAULT NULL::text, p_min_lagertage numeric DEFAULT NULL::numeric)
 RETURNS TABLE(strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric, kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric, koeff_n_min integer, streuung_kg numeric, df integer)
 LANGUAGE sql
 STABLE
AS $function$
with zeilen as materialized (
  select * from v_hochrechnung
   where buch in ('verlust', 'marge')
     and (p_sorte is null or sorte = p_sorte)
     and (p_schlag is null or schlag = p_schlag)
     and (p_min_lagertage is null or alter_tage >= p_min_lagertage)
),
je_sorte as (
  select z.strom, z.buch, z.sorte, max(z.koeff_art) as koeff_art,
         sum(z.d_r) as g_r, sum(z.d_a) as g_a
    from zeilen z group by z.strom, z.buch, z.sorte
),
je_strom_modell as (
  select z.strom, z.buch,
         sum(z.d_eta)       as g_achse,
         sum(z.d_eta * z.u) as g_steigung
    from zeilen z group by z.strom, z.buch
),
varianz_r as (
  select s.strom, s.buch,
         sum(power(s.g_r, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_r * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = 'verdunstung' and u.sorte is not distinct from s.sorte
   group by s.strom, s.buch
),
varianz_a as (
  select s.strom, s.buch,
         sum(power(s.g_a, 2) * coalesce(u.varianz_eigen, 0))
           + power(sum(s.g_a * coalesce(u.gewicht_gesamt, 1)), 2)
             * max(coalesce(u.varianz_gesamt, 0))               as varianz,
         min(coalesce(u.df, 1))                                 as df
    from je_sorte s
    left join v_koeff_unsicherheit u
           on u.art = s.koeff_art and u.sorte is not distinct from s.sorte
   where s.koeff_art is not null
   group by s.strom, s.buch
),
varianz_f as (
  select m.strom, m.buch,
         power(m.g_achse, 2) * coalesce(sm.var_achse, 0)
         + 2 * m.g_achse * m.g_steigung * coalesce(sm.kov_achse_k, 0)
         + power(m.g_steigung, 2) * coalesce(sm.var_k, 0)       as varianz,
         coalesce(sm.c_chargen - 1, 1)                          as df
    from je_strom_modell m cross join v_schimmel_modell sm
),
summe as (
  select z.strom, z.buch,
         sum(z.kg)                                                as kg,
         sum(z.kg) filter (where z.portion = 'ausgelagert')       as kg_beobachtet,
         sum(z.kg) filter (where z.portion = 'lager')             as kg_projiziert,
         sum(z.kg) filter (where z.f_extrapoliert)                as kg_extrapoliert,
         min(z.koeff_n)                                           as koeff_n_min
    from zeilen z group by z.strom, z.buch
)
select s.strom, s.buch, s.kg,
       greatest(s.kg - g.t * g.streuung - zu.zuschlag, 0)::numeric(14,2),
       (s.kg + g.t * g.streuung + zu.zuschlag)::numeric(14,2),
       s.kg_beobachtet, s.kg_projiziert, s.kg_extrapoliert, s.koeff_n_min,
       g.streuung::numeric(14,2), g.df
  from summe s
  left join varianz_r vr on vr.strom = s.strom and vr.buch = s.buch
  left join varianz_a va on va.strom = s.strom and va.buch = s.buch
  left join varianz_f vf on vf.strom = s.strom and vf.buch = s.buch
  cross join lateral (select coalesce(sm2.selektions_versatz, 0) as versatz
                       from v_schimmel_modell sm2) sel
  cross join lateral (
    select sqrt(greatest(coalesce(vr.varianz, 0) + coalesce(va.varianz, 0)
                         + coalesce(vf.varianz, 0), 0))       as streuung,
           least(coalesce(vr.df, 999), coalesce(va.df, 999),
                 coalesce(vf.df, 999))                        as df
  ) g0
  cross join lateral (select g0.streuung, g0.df, t_quantil_95(g0.df) as t) g
  -- Der Zuschlag ist keine Streuung, sondern eine Verzerrung unbekannter
  -- Richtung: Er wird nicht mit t multipliziert, sondern schlicht auf beide
  -- Grenzen gelegt. Er trifft nur den Teil des Schimmels, der auf noch
  -- stehende Ware entfällt — bei bereits verarbeiteter ist er gemessen.
  cross join lateral (
    select case when s.strom = 'Schimmel/Fäulnis'
                then coalesce(s.kg_projiziert, 0) * abs(exp(sel.versatz) - 1)
                else 0 end                                    as zuschlag) zu
 order by s.kg desc nulls last;
$function$;

create or replace view v_verlust_ranking with (security_invoker = true) as
select * from verlust_ranking();

grant select on v_schimmel_modell, v_verlust_ranking to authenticated;
grant execute on function verlust_ranking(text, text, numeric) to authenticated;
