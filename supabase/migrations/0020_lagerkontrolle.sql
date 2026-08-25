-- =====================================================================
-- 0020 — Die eine Messung, die das Modell wirklich braucht
--
-- Nach 0017–0019 trifft die Auswertung in fast allen Lagen. Ein Fall bleibt,
-- und es ist der realistischste (25 Saisons, 50 % im Lager, „Schlechtes
-- zuerst" verarbeitet):
--
--   Schimmel/Fäulnis   Verzerrung −13.0 %   Überdeckung 8 %
--
-- Das ist die Selektionsverzerrung aus Punkt 7 der Überprüfung, und sie ist
-- strukturell: Wer schlecht aussieht, kommt zuerst dran. Anfällige Paletten
-- werden also bei *kurzer* Lagerdauer gemessen, robuste erst spät. Der
-- gemessene Verlauf wird dadurch flacher als der wahre — und je weiter
-- extrapoliert wird, desto stärker schlägt das durch.
--
-- Aus Schimmelmessungen an verarbeiteter Ware allein ist das nicht zu
-- beheben: Alter und Anfälligkeit sind durch die Verarbeitungsreihenfolge
-- vermengt, und keine Statistik trennt, was die Daten nicht trennen. Was hilft,
-- ist eine Messung, deren Auswahl *nicht* am Zustand hängt:
--
--   Ab und zu eine zufällig gegriffene Palette im Lager aufmachen und
--   notieren, wie viel davon faul ist.
--
-- Dafür braucht es keinen neuen Bildschirm. Paletten werden ohnehin
-- gelegentlich gewogen; die Wägung bekommt ein zusätzliches Feld „davon
-- faul (kg)". Ein Wert mehr auf einer Maske, die es schon gibt.
--
-- Diese Punkte gehen mit demselben Gewicht in dieselbe Regression wie die
-- Messungen aus der Verarbeitung — nur sind sie nicht danach ausgewählt, wie
-- die Palette aussah.
-- =====================================================================

alter table verdunstung_wiegung
  add column if not exists faul_kg numeric(8,2)
    check (faul_kg is null or faul_kg >= 0);

comment on column verdunstung_wiegung.faul_kg is
  'Wie viel der gewogenen Palette faul ist. Freiwillig — aber der einzige '
  'Schimmelwert, dessen Palette nicht danach ausgewählt wurde, wie sie aussah.';

-- ---------- Alle Schimmelpunkte, egal woher --------------------------------
create or replace view v_schimmel_punkte with (security_invoker = true) as
-- Aus der Verarbeitung: Summe je Arbeit, bezogen auf die Masse nach Verdunstung
select b.charge_nr, b.sorte, b.schlag, b.lagertage, b.schimmel_kg,
       b.basis_jetzt_kg, b.anteil, b.plausibel,
       'verarbeitung'::text as quelle, b.auftrag_id
  from v_schimmel_beobachtung b
union all
-- Aus dem Lager: eine gewogene Palette, bei der jemand nachgesehen hat
select w.charge_nr, w.sorte, w.schlag, w.lagertage,
       v.faul_kg, w.netto_jetzt_kg,
       v.faul_kg / nullif(w.netto_jetzt_kg, 0),
       anteil_plausibel(v.faul_kg / nullif(w.netto_jetzt_kg, 0)),
       'lager', null::bigint
  from v_verdunstung_messung w
  join verdunstung_wiegung v on v.id = w.id
 where v.faul_kg is not null and v.gemessen
   and w.netto_jetzt_kg > 0 and w.lagertage > 0;

comment on view v_schimmel_punkte is
  'Alle Schimmelbeobachtungen. quelle = lager heisst: die Palette wurde nicht '
  'danach ausgewählt, wie sie aussah — nur diese Punkte sind frei von der '
  'Selektionsverzerrung der Verarbeitungsreihenfolge.';

-- ---------- Modell und Treppe lesen jetzt beide Quellen -------------------
create or replace view v_schimmel_modell with (security_invoker = true) as
with beob as (
  select b.charge_nr,
         b.lagertage::numeric                   as t,
         b.anteil::numeric                      as f,
         b.basis_jetzt_kg::numeric              as gewicht
    from v_schimmel_punkte b
   where b.plausibel and b.anteil > 0 and b.anteil < 1 and b.lagertage > 0
), punkte as (
  select charge_nr, ln(t) as x, ln(-ln(1 - f)) as y, gewicht as w, t from beob
), summen as (
  select count(*)::int as n, count(distinct charge_nr)::int as c_chargen,
         min(t) as t_min, max(t) as t_max,
         sum(w) as sw, sum(w * x) as swx, sum(w * y) as swy,
         sum(w * x * x) as swxx, sum(w * x * y) as swxy
    from punkte
), fit as (
  select s.*,
         case when s.sw * s.swxx - s.swx * s.swx <> 0
              then (s.sw * s.swxy - s.swx * s.swy)
                   / (s.sw * s.swxx - s.swx * s.swx) end              as k,
         s.swx / nullif(s.sw, 0)                                      as x_mittel
    from summen s
), mit_achse as (
  select f.*, case when f.k is not null then (f.swy - f.k * f.swx) / f.sw end as ln_lambda
    from fit f
), rest as (
  select m.*,
         (select sum(p.w * power(p.x - m.x_mittel, 2)) from punkte p)              as sxx,
         (select sum(p.w * power(p.y - (m.ln_lambda + m.k * p.x), 2)) from punkte p) as sse,
         (select sum(p.w * exp(p.y - (m.ln_lambda + m.k * p.x))) / nullif(sum(p.w), 0)
            from punkte p)                                                        as smearing
    from mit_achse m
), gruppen as (
  select r.*, g.saa, g.skk, g.sak
    from rest r
    cross join lateral (
      select sum(power(c.ga, 2)) as saa, sum(power(c.gk, 2)) as skk,
             sum(c.ga * c.gk)    as sak
        from (select p.charge_nr,
                     sum(p.w * (p.y - (r.ln_lambda + r.k * p.x)))                      as ga,
                     sum(p.w * (p.x - r.x_mittel) * (p.y - (r.ln_lambda + r.k * p.x))) as gk
                from punkte p group by p.charge_nr) c
    ) g
)
select n, c_chargen, t_min, t_max, k, ln_lambda, exp(ln_lambda) as lambda,
       x_mittel, sxx, smearing,
       ln_lambda + ln(greatest(smearing, 0.01))                      as ln_lambda_korrigiert,
       case when n > 2 then sse / (n - 2) * n / nullif(sw, 0) end    as sigma2,
       case when c_chargen > 1
            then saa / power(sw, 2) * c_chargen::numeric / (c_chargen - 1) end  as var_achse,
       case when c_chargen > 1 and sxx <> 0
            then skk / power(sxx, 2) * c_chargen::numeric / (c_chargen - 1) end as var_k,
       case when c_chargen > 1 and sxx <> 0
            then sak / (sw * sxx) * c_chargen::numeric / (c_chargen - 1) end    as kov_achse_k,
       t_quantil_95(c_chargen - 1)                                              as t_faktor,
       (n >= 3 and c_chargen >= 3 and k is not null and k > 0
        and t_max > t_min * 1.5)                                                as brauchbar
  from gruppen;

create or replace view v_schimmel_kurve with (security_invoker = true) as
with klassen(von, bis) as (
  values (0,14), (15,30), (31,60), (61,90), (91,120), (121,180), (181,100000)
), je_klasse as (
  select k.von, k.bis,
         count(b.anteil)::int as n,
         sum(b.schimmel_kg) / nullif(sum(b.basis_jetzt_kg), 0) as anteil,
         stddev_samp(b.anteil) as sd
    from klassen k
    left join v_schimmel_punkte b
           on b.lagertage >= k.von and b.lagertage <= k.bis
          and b.anteil is not null and b.plausibel
   group by k.von, k.bis
)
select von, bis, n, anteil, sd,
       least(greatest(max(anteil) over (order by von
             rows between unbounded preceding and current row), 0), 1) as anteil_mono,
       case when n >= 2 then greatest(anteil - 1.96 * sd / sqrt(n), 0) end as unten,
       case when n >= 2 then least(anteil + 1.96 * sd / sqrt(n), 1) end   as oben
  from je_klasse;

-- ---------- Wie stark verzerrt die Verarbeitungsreihenfolge? --------------
-- Der naheliegende Test — hängen die Abweichungen vom Verlauf mit der
-- Verarbeitungsreihenfolge zusammen? — funktioniert nicht: innerhalb einer
-- Charge *ist* die Reihenfolge die Lagerdauer, und die steckt schon im
-- Modell. Die Regression hat den Zusammenhang bereits aufgebraucht.
--
-- Was wirklich trägt, ist der Vergleich der beiden Quellen. Lagerkontrollen
-- werden zufällig gegriffen, Verarbeitungsmessungen nach Aussehen sortiert.
-- Sagen beide dasselbe, gibt es keine Selektion. Liegen die Lagerkontrollen
-- systematisch höher, wurde nach Zustand ausgewählt und der aus der
-- Verarbeitung geschätzte Verlauf ist zu flach.
create or replace view v_selektionsverdacht with (security_invoker = true) as
with rest as (
  select p.quelle, p.basis_jetzt_kg::numeric as w,
         ln(-ln(1 - p.anteil::numeric)) - (m.ln_lambda + m.k * ln(p.lagertage::numeric)) as e
    from v_schimmel_punkte p cross join v_schimmel_modell m
   where m.brauchbar and p.plausibel
     and p.anteil > 0 and p.anteil < 1 and p.lagertage > 0
), je_quelle as (
  select quelle, count(*)::int as n, sum(w * e) / nullif(sum(w), 0) as mittel
    from rest group by quelle
)
select (select n from je_quelle where quelle = 'verarbeitung')      as n_verarbeitung,
       (select n from je_quelle where quelle = 'lager')             as n_lager,
       (select mittel from je_quelle where quelle = 'verarbeitung') as rest_verarbeitung,
       (select mittel from je_quelle where quelle = 'lager')        as rest_lager,
       -- Der Unterschied im Log-Raum; exp() davon ist der Faktor, um den
       -- die zufällig gegriffene Ware fauler ist als die ausgewählte.
       (select mittel from je_quelle where quelle = 'lager')
         - (select mittel from je_quelle where quelle = 'verarbeitung') as unterschied,
       case
         when (select n from je_quelle where quelle = 'lager') is null
           then 'keine Lagerkontrollen — Selektion nicht prüfbar'
         when (select n from je_quelle where quelle = 'lager') < 5
           then 'zu wenige Lagerkontrollen für eine Aussage'
         when abs((select mittel from je_quelle where quelle = 'lager')
                  - (select mittel from je_quelle where quelle = 'verarbeitung')) > 0.2
           then 'verarbeitete und zufällig gegriffene Paletten sagen Verschiedenes — '
                || 'es wird nach Aussehen ausgewählt. Bei gleichem Alter sind die '
                || 'verarbeiteten fauler, dafür bleibt am Ende die robustere Ware '
                || 'liegen: der Verlauf wird zu flach und die Hochrechnung auf lange '
                || 'Lagerdauern zu niedrig. Mehr Lagerkontrollen beheben das.'
         else 'beide Quellen sagen dasselbe — kein Hinweis auf Selektion'
       end                                                          as befund;

comment on view v_selektionsverdacht is
  'Vergleicht zufällig gegriffene Lagerkontrollen mit den nach Aussehen '
  'ausgewählten Verarbeitungsmessungen. Ohne Lagerkontrollen ist die '
  'Selektionsverzerrung grundsätzlich nicht prüfbar.';

grant select on v_schimmel_punkte, v_selektionsverdacht to authenticated;
