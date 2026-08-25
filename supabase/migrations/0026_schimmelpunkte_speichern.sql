-- =====================================================================
-- 0026 — Die Schimmelpunkte einmal rechnen statt viermal
--
-- v_schimmel_punkte ist mit 0025 teuer geworden: Für jeden Waschgang wird
-- nachgeschlagen, was bis dahin beim Sortieren derselben Charge gemessen
-- wurde. Das ist richtig so, aber die Ansicht hängt an vier Stellen in der
-- Kette und wurde dabei jedes Mal neu gerechnet. Dazu kam, dass
-- v_auftrag_masse seit 0024 bei jeder Referenz den Wareneingang der
-- sortierten Ware neu aggregiert — und v_auftrag_masse steckt in einem
-- Dutzend Ansichten. Die Neuberechnung stieg dadurch von 226 ms auf 2 639 ms.
--
-- Dasselbe Mittel wie in 0016: einmal rechnen, speichern, alle lesen von der
-- gespeicherten Fassung. Reihenfolge im Neuberechnen ist Pflicht — jede Stufe
-- liest die vorige.
--
-- Nicht per Umbenennung: Postgres merkt sich Abhängigkeiten über die Objekt-ID,
-- eine umbenannte Ansicht nehmen ihre Leser einfach mit. Wer den schnellen Weg
-- will, muss die Leser umhängen. Genau das passiert hier.
-- =====================================================================

-- ---------- Der Wareneingang der sortierten Ware, einmal gerechnet ---------
create materialized view if not exists mv_sortier_eingang as
select a.charge_nr,
       sum((m.eingangsdatum - date '2000-01-01')::numeric * m.netto_kg)
         / nullif(sum(m.netto_kg), 0)                        as tage_seit_epoche
  from auftrag a
  join v_auftrag_palette_masse m on m.auftrag_id = a.id
 where a.station = 'sortieren' and a.abgebrochen_ts is null
 group by a.charge_nr;

create unique index if not exists mv_sortier_eingang_pk on mv_sortier_eingang (charge_nr);

create or replace view v_auftrag_masse with (security_invoker = true) as
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten, m.eingang_netto_kg,
       m.masse_quelle,
       (coalesce(
         m.lagertage,
         -- Beim Waschen auf Weg 1 gibt es nichts zu zählen. Die Lagerdauer
         -- läuft trotzdem ab dem Wareneingang, nicht ab dem Sortiertag.
         case when m.station = 'waschen'
              then ((m.start_ts::date - date '2000-01-01')::numeric
                    - coalesce(se.tage_seit_epoche,
                               (r.eingangsdatum_mittel - date '2000-01-01')::numeric))
         end
       ))::numeric(10,1)                                     as lagertage
  from mv_auftrag_masse m
  left join mv_sortier_eingang se on se.charge_nr = m.charge_nr
  left join v_charge_rueckgrat  r  on r.charge_nr = m.charge_nr;

-- ---------- Die Schimmelpunkte speichern ----------------------------------
create materialized view if not exists mv_schimmel_punkte as
select * from v_schimmel_punkte;

create index if not exists mv_schimmel_punkte_charge on mv_schimmel_punkte (charge_nr);
create index if not exists mv_schimmel_punkte_quelle on mv_schimmel_punkte (quelle);

comment on materialized view mv_schimmel_punkte is
  'Die gespeicherte Fassung von v_schimmel_punkte. Alles, was rechnet, liest '
  'diese hier; v_schimmel_punkte selbst rechnet neu und wird nur beim '
  'Neuberechnen gebraucht.';

-- ---------- Die Leser auf die gespeicherte Fassung umhängen ----------------

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
    n >= 3 AND c_chargen >= 3 AND k IS NOT NULL AND k > 0::numeric AND t_max > (t_min * 1.5) AS brauchbar
   FROM gruppen;

create or replace view v_schimmel_kurve with (security_invoker = true) as
WITH klassen(von, bis) AS (
         VALUES (0,14), (15,30), (31,60), (61,90), (91,120), (121,180), (181,100000)
        ), je_klasse AS (
         SELECT k.von,
            k.bis,
            count(b.anteil)::integer AS n,
            sum(b.schimmel_kg) / NULLIF(sum(b.basis_jetzt_kg), 0::numeric) AS anteil,
            stddev_samp(b.anteil) AS sd
           FROM klassen k
             LEFT JOIN mv_schimmel_punkte b ON b.lagertage >= k.von::numeric AND b.lagertage <= k.bis::numeric AND b.anteil IS NOT NULL AND b.plausibel
          GROUP BY k.von, k.bis
        )
 SELECT von,
    bis,
    n,
    anteil,
    sd,
    LEAST(GREATEST(max(anteil) OVER (ORDER BY von ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0::numeric), 1::numeric) AS anteil_mono,
        CASE
            WHEN n >= 2 THEN GREATEST(anteil::double precision - (1.96 * sd)::double precision / sqrt(n::double precision), 0::double precision)
            ELSE NULL::double precision
        END AS unten,
        CASE
            WHEN n >= 2 THEN LEAST(anteil::double precision + (1.96 * sd)::double precision / sqrt(n::double precision), 1::double precision)
            ELSE NULL::double precision
        END AS oben
   FROM je_klasse;

create or replace view v_selektionsverdacht with (security_invoker = true) as
WITH rest AS (
         SELECT p.quelle,
            p.basis_jetzt_kg AS w,
            ln(- ln(1::numeric - p.anteil)) - (m.ln_lambda + m.k * ln(p.lagertage)) AS e
           FROM mv_schimmel_punkte p
             CROSS JOIN v_schimmel_modell m
          WHERE m.brauchbar AND p.plausibel AND p.anteil > 0::numeric AND p.anteil < 1::numeric AND p.lagertage > 0::numeric
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

create or replace view v_schlag_effekt with (security_invoker = true) as
WITH punkte AS (
         SELECT p.schlag,
            p.charge_nr,
            p.basis_jetzt_kg AS w,
            ln(- ln(1::numeric - p.anteil)) - (m.ln_lambda + m.k * ln(p.lagertage)) AS e
           FROM mv_schimmel_punkte p
             CROSS JOIN v_schimmel_modell m
          WHERE m.brauchbar AND p.plausibel AND p.anteil > 0::numeric AND p.anteil < 1::numeric AND p.lagertage > 0::numeric
        ), je_schlag AS (
         SELECT punkte.schlag,
            count(*)::integer AS n,
            count(DISTINCT punkte.charge_nr)::integer AS c,
            sum(punkte.w) AS sw,
            sum(punkte.w * punkte.e) / NULLIF(sum(punkte.w), 0::numeric) AS mittel
           FROM punkte
          GROUP BY punkte.schlag
        ), streuung AS (
         SELECT count(*)::integer AS n_schlaege,
            sum(je_schlag.sw * power(je_schlag.mittel, 2::numeric)) / NULLIF(sum(je_schlag.sw), 0::numeric) AS beobachtet,
            (( SELECT sum(punkte.w * power(punkte.e, 2::numeric)) / NULLIF(sum(punkte.w), 0::numeric)
                   FROM punkte)) / NULLIF(avg(je_schlag.n), 0::numeric) AS erwartet_durch_zufall
           FROM je_schlag
          WHERE je_schlag.n >= 2
        )
 SELECT n_schlaege,
    beobachtet,
    erwartet_durch_zufall,
    GREATEST(beobachtet - erwartet_durch_zufall, 0::numeric) AS tau2_schlag,
        CASE
            WHEN n_schlaege IS NULL OR n_schlaege < 3 THEN 'zu wenige Schläge mit Messungen'::text
            WHEN GREATEST(beobachtet - erwartet_durch_zufall, 0::numeric) <= 0::numeric THEN 'die Unterschiede zwischen Schlägen sind nicht grösser als '::text || 'Stichprobenrauschen — eine eigene Schlag-Schätzung brächte nichts'::text
            WHEN beobachtet > (2::numeric * erwartet_durch_zufall) THEN 'die Schläge unterscheiden sich deutlich — eine eigene '::text || 'Schlag-Stratifizierung wäre begründet'::text
            ELSE 'schwacher Hinweis auf Schlag-Unterschiede, für eine eigene '::text || 'Schätzung reicht es noch nicht'::text
        END AS befund
   FROM streuung;


create or replace function auswertung_aktualisieren()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v_start timestamptz := clock_timestamp();
begin
  -- Reihenfolge ist Pflicht: jede Stufe liest die vorige.
  refresh materialized view mv_sortier_lauf_masse;
  refresh materialized view mv_sortier_eingang;
  refresh materialized view mv_auftrag_masse;
  refresh materialized view mv_schimmel_punkte;
  refresh materialized view mv_kaskade;
  refresh materialized view mv_kaliber_verteilung;

  update auswertung_stand
     set berechnet_ts = now(),
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;

  return now();
end $$;

grant select on mv_schimmel_punkte, mv_sortier_eingang, v_auftrag_masse,
                v_schimmel_modell, v_schimmel_kurve, v_selektionsverdacht,
                v_schlag_effekt to authenticated;
