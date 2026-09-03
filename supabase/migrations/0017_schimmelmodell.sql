-- =====================================================================
-- 0017 — Die Schimmelkurve als Verderbsmodell statt als Treppe
--
-- Gemessen mit dem Simulations-Harness (supabase/test/simulation): Saisons
-- mit selbst gesetzter Wahrheit (λ = 1.07e-5, k = 1.6) durchlaufen die
-- Pipeline, danach steht fest, wie weit sie danebenlag (Verzerrung) und wie
-- oft der ausgewiesene Bereich den wahren Wert enthielt (Überdeckung). Ein
-- Bereich, der 95 % heissen soll, muss in rund 95 % der Saisons treffen.
--
--   Lage                              Verzerrung   Überdeckung
--   Saisonende, 25 % im Lager            −6.2 %        70 %
--   mitten in der Saison, 50 % im Lager  −46.3 %         0 %
--
-- Drei Ursachen, alle nachgewiesen, alle hier behoben.
--
-- ---------- 1. Flach fortschreiben ist keine Projektion -------------------
-- Für Lagerdauern ohne Messung schrieb v_schimmel_kurve den letzten
-- bekannten Wert fort. Derselbe Datenstand, Wahrheit daneben gestellt:
--
--   Lagertage   Wahrheit   Treppenfunktion   Modell (dieses hier)
--        30       0.25 %        0.23 %             0.25 %
--        90       1.42 %        1.19 %             1.52 %
--       150       3.19 %        2.03 %             3.48 %
--       210       5.41 %        2.03 %             5.97 %
--                               ↑ flach ab 120 Tagen
--
-- Und genau dort liegt die Masse: mitten in der Saison 341.8 t Lagerbestand
-- mit 167–201 Tagen Alter — jenseits der längsten je gemessenen Lagerdauer
-- (113 Tage). Die Treppe gab dieser Hälfte der Ernte den Schimmelanteil kurz
-- gelagerter Ware. Spec §9 verlangt ausdrücklich, rechts-zensierte Ware zu
-- projizieren; flach fortschreiben ist keine Projektion, sondern eine
-- Weigerung.
--
-- Statt dessen ein Verlaufsmodell:  F(t) = 1 − exp(−λ · t^k)
--
-- Die übliche Weibull-Form für Verderbsprozesse; k > 1 heisst, die Rate
-- steigt mit der Lagerdauer — genau das beobachtet man bei Kürbissen.
-- Logarithmiert wird daraus eine Gerade,
--
--   ln(−ln(1 − F)) = ln λ + k · ln t
--
-- also eine gewichtete lineare Regression, die Postgres selbst rechnet.
-- Gewichtet mit der Masse hinter der Messung: 20 t wiegen schwerer als 800 kg.
--
-- ---------- 2. Rücktransformation aus dem Log-Raum ------------------------
-- exp() des Mittelwerts im Log-Raum ergibt den *geometrischen* Mittelwert,
-- nicht den arithmetischen. Wo die Anfälligkeit der Paletten streut, ist das
-- systematisch zu wenig. Nachgemessen:
--
--   Duans Smearing-Faktor  S = Σ w·exp(Residuum) / Σ w = 1.0781
--   Normal-Näherung        exp(σ²/2)                   = 1.0714
--
-- Beide sagen dasselbe, die Log-Residuen sind also brauchbar normal. +7.8 %
-- gegen die verbliebenen −6.1 % Verzerrung: das ist der fehlende Betrag.
-- Genommen wird Duan, weil er ohne Verteilungsannahme auskommt.
--
-- ---------- 3. 339 Messungen sind nicht 339 -------------------------------
-- Die Beobachtungen liegen in 12 Chargen. Innerhalb einer Charge sind sie
-- ähnlich — gleicher Schlag, gleiche Ernte, gleiches Lager —, zwischen
-- Chargen nicht. Wer sie als unabhängig zählt, rechnet sich die Sicherheit
-- schön. An denselben Daten:
--
--                           naiv    chargen-robust   Faktor
--   Standardfehler von k   0.0016        0.0509        31×
--   Standardfehler Achse   0.0202        0.0241       1.2×
--
-- Die Steigung ist der springende Punkt, denn sie bestimmt genau das, was
-- jenseits des gemessenen Bereichs passiert. 31× zu klein heisst: dort, wo
-- der Bereich am meisten gebraucht wird, war er um mehr als eine
-- Grössenordnung zu eng.
--
-- Ersetzt durch den chargen-robusten Sandwich-Schätzer: die gewichteten
-- Residuen werden je Charge aufsummiert, und die Streuung *dieser Summen*
-- ist der Fehler. Dazu die t-Verteilung mit C−1 Freiheitsgraden statt 1.96 —
-- bei zwölf Gruppen ist die Normalverteilung eine Behauptung, keine Näherung.
-- =====================================================================

-- ---------- t-Quantil, zweiseitig 95 % ------------------------------------
-- Postgres bringt keine t-Verteilung mit. Tabelle für kleine Freiheitsgrade,
-- darüber die Normalverteilung — ab df ≈ 30 ist der Unterschied unter 5 %.
create or replace function t_quantil_95(p_df int)
returns numeric language sql immutable as $$
  select case
    when p_df is null or p_df < 1 then 12.706
    when p_df >= 30 then 1.960
    else (array[12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306,
                2.262, 2.228, 2.201, 2.179, 2.160, 2.145, 2.131, 2.120,
                2.110, 2.101, 2.093, 2.086, 2.080, 2.074, 2.069, 2.064,
                2.060, 2.056, 2.052, 2.048, 2.045])[p_df]
  end::numeric;
$$;

comment on function t_quantil_95(int) is
  'Zweiseitiges 95-%-Quantil der t-Verteilung. Bei wenigen unabhängigen '
  'Gruppen ist 1.96 zu optimistisch.';

-- ---------- Das angepasste Modell -----------------------------------------
-- mv_kaskade hängt daran und muss vorher weichen; es wird unten neu gebaut.
drop materialized view if exists mv_kaskade cascade;
drop view if exists v_schimmel_kurve_anzeige;
drop view if exists v_schimmel_modell;

create view v_schimmel_modell with (security_invoker = true) as
with beob as (
  -- Einzelbeobachtungen statt Altersklassen: mehr Information, und die
  -- Klassengrenzen verfälschen den Verlauf nicht.
  select b.charge_nr,
         b.lagertage::numeric                   as t,
         b.anteil::numeric                      as f,
         b.basis_jetzt_kg::numeric              as gewicht
    from v_schimmel_beobachtung b
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
         -- Zentriert um x_mittel sind Achse und Steigung getrennt schätzbar.
         (select sum(p.w * power(p.x - m.x_mittel, 2)) from punkte p)              as sxx,
         (select sum(p.w * power(p.y - (m.ln_lambda + m.k * p.x), 2)) from punkte p) as sse,
         (select sum(p.w * exp(p.y - (m.ln_lambda + m.k * p.x))) / nullif(sum(p.w), 0)
            from punkte p)                                                        as smearing
    from mit_achse m
), gruppen as (
  -- Je Charge die gewichteten Residuen aufsummieren; die Streuung dieser
  -- Chargensummen ist der Fehler, nicht die der Einzelpunkte.
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
       -- Das ist, was tatsächlich gerechnet wird: Fit plus Smearing
       ln_lambda + ln(greatest(smearing, 0.01))                      as ln_lambda_korrigiert,
       case when n > 2 then sse / (n - 2) * n / nullif(sw, 0) end    as sigma2,
       -- Sandwich-Varianzen, mit der üblichen Korrektur für wenige Gruppen
       case when c_chargen > 1
            then saa / power(sw, 2) * c_chargen::numeric / (c_chargen - 1) end  as var_achse,
       case when c_chargen > 1 and sxx <> 0
            then skk / power(sxx, 2) * c_chargen::numeric / (c_chargen - 1) end as var_k,
       case when c_chargen > 1 and sxx <> 0
            then sak / (sw * sxx) * c_chargen::numeric / (c_chargen - 1) end    as kov_achse_k,
       t_quantil_95(c_chargen - 1)                                              as t_faktor,
       -- Brauchbar heisst auch: genug *unabhängige* Gruppen. Mit ein oder
       -- zwei Chargen lässt sich der Fehler nicht schätzen, und ein Modell
       -- ohne belastbare Fehlerangabe ist hier schlimmer als die Treppe.
       (n >= 3 and c_chargen >= 3 and k is not null and k > 0
        and t_max > t_min * 1.5)                                                as brauchbar
  from gruppen;

comment on view v_schimmel_modell is
  'Verderbsmodell F(t) = 1 − exp(−λ·S·t^k), S = Duan-Smearing. Der Fehler ist '
  'chargen-robust: Messungen aus derselben Charge sind keine unabhängigen '
  'Beobachtungen. brauchbar = false heisst: zu wenige Chargen oder zu '
  'ähnliche Lagerdauern — es gilt die Treppenfunktion.';

-- ---------- Schimmelanteil bei gegebener Lagerdauer -----------------------
-- Für Anzeige und Einzelabfragen. Die Kaskade rechnet die Formel inline,
-- weil ein Funktionsaufruf je Zeile 2 441 ms gekostet hat (siehe 0015).
create or replace function schimmelanteil(p_lagertage numeric, p_szenario text default 'mittel')
returns numeric language sql stable as $$
  with m as (select * from public.v_schimmel_modell),
  u as (select m.*, ln(greatest(p_lagertage, 1)) - m.x_mittel as u from m)
  select coalesce(
    (select least(greatest(1 - exp(-exp(least(greatest(
       u.ln_lambda_korrigiert + u.k * ln(greatest(p_lagertage, 1))
       + case p_szenario when 'unten' then -1 when 'oben' then 1 else 0 end
         * u.t_faktor * sqrt(greatest(
             u.var_achse + power(u.u, 2) * u.var_k + 2 * u.u * u.kov_achse_k, 0))
       , -40), 3))), 0), 1)
       from u where u.brauchbar and u.var_achse is not null),
    -- Rückfall: die Treppenfunktion, solange das Modell nicht trägt
    (select least(greatest(coalesce(
       case p_szenario when 'unten' then coalesce(k.unten, k.anteil_mono)
                       when 'oben'  then coalesce(k.oben,  k.anteil_mono)
                       else k.anteil_mono end, 0), 0), 1)
       from public.v_schimmel_kurve k
      where k.von <= p_lagertage and k.n > 0
      order by k.von desc limit 1),
    0)::numeric;
$$;

-- ---------- Die Kaskade, jetzt mit dem Modell -----------------------------
-- Rumpf wie in 0016; neu ist allein, wie f zustande kommt: das Modell wird
-- einmal als CTE materialisiert und die Formel inline gerechnet — eine
-- ln/exp-Rechnung je Zeile statt einer Abfrage je Zeile.
create materialized view mv_kaskade as
with sz(szenario) as (values ('unten'), ('mittel'), ('oben')),
modell as materialized (
  select * from v_schimmel_modell
),
kurve as materialized (
  -- Rückfall für die Zeit, in der noch zu wenig gemessen wurde, um ein
  -- Modell anzupassen — am Saisonanfang ist das der Normalfall.
  select von, anteil_mono, unten, oben, n from v_schimmel_kurve where n > 0
),
koeff as (
  select b.*, sz.szenario,
         least(greatest(case sz.szenario when 'unten' then kv.unten
                                         when 'oben'  then kv.oben
                                         else kv.mittel end, 0), 0.05) as r,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(case sz.szenario when 'unten' then ka.unten
                                         when 'oben'  then ka.oben
                                         else ka.mittel end, 0), 1) as a_klein,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(case sz.szenario when 'unten' then kn.unten
                                         when 'oben'  then kn.oben
                                         else kn.mittel end, 0), 1) as a_gross,
         kn.n as gross_n, kn.basis as gross_basis
    from v_hochrechnung_basis b
    cross join sz
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
),
koeff_norm as (
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  select k.*, t.portion, t.m0, t.alter_tage,
         case when m.brauchbar and m.var_achse is not null then
           least(greatest(1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(t.alter_tage, 1))
             + case k.szenario when 'unten' then -1 when 'oben' then 1 else 0 end
               * m.t_faktor * e.se
             , -40), 3))), 0), 1)
         else
           least(greatest(coalesce(
             case k.szenario when 'unten' then coalesce(s.unten, s.anteil_mono)
                             when 'oben'  then coalesce(s.oben,  s.anteil_mono)
                             else s.anteil_mono end, 0), 0), 1)
         end                                                          as f,
         case when m.brauchbar and m.var_achse is not null then m.c_chargen else s.n end as f_n,
         -- Wird hier über den gemessenen Bereich hinaus gerechnet? Das gehört
         -- ins Dashboard, nicht in eine Fussnote.
         (m.brauchbar and m.var_achse is not null and t.alter_tage > m.t_max) as f_extrapoliert
    from koeff_norm k
    cross join modell m
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
    -- Vorhersagefehler an dieser Lagerdauer: wächst mit dem Abstand vom
    -- Schwerpunkt der Messungen. Beim Lagerbestand, der länger liegt als
    -- alles je Verarbeitete, wird der Bereich dadurch von selbst breiter —
    -- statt eine Sicherheit vorzutäuschen, die es nicht gibt.
    cross join lateral (
      select sqrt(greatest(coalesce(m.var_achse, 0)
             + power(ln(greatest(t.alter_tage, 1)) - coalesce(m.x_mittel, 0), 2)
               * coalesce(m.var_k, 0)
             + 2 * (ln(greatest(t.alter_tage, 1)) - coalesce(m.x_mittel, 0))
               * coalesce(m.kov_achse_k, 0), 0)) as se) e
    left join lateral (
        select c.anteil_mono, c.unten, c.oben, c.n from kurve c
         where c.von <= t.alter_tage order by c.von desc limit 1
       ) s on true
   where t.m0 > 0
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))::numeric              as m1,
         (t.m0 * power(1 - t.r, t.alter_tage) * (1 - t.f))::numeric  as m2
    from teile t
)
select k.*,
       k.m0 - k.m1                                    as verdunstung_kg,
       k.m1 - k.m2                                    as schimmel_kg,
       k.m2 * k.a_klein_n                             as klein_kg,
       k.m2 * k.a_gross_n                             as nebenkanal_kg,
       k.m2 * (1 - k.a_klein_n - k.a_gross_n)         as verkaufsfaehig_kg
  from kaskade k;

create unique index if not exists mv_kaskade_pk on mv_kaskade (charge_nr, szenario, portion);
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);

create or replace view v_kaskade with (security_invoker = true) as
select * from mv_kaskade;

-- ---------- Die abhängigen Ansichten wieder aufbauen ----------------------
-- Sie hingen an v_kaskade und fielen mit dem cascade-Drop mit. Rumpf wie in
-- 0015; neu ist allein, dass durchgereicht wird, ob hochgerechnet wurde.
create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.szenario, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg, k.f_extrapoliert,
       s.strom, s.buch,
       s.kg::numeric(14,2)          as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       s.koeffizient::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung',      'verlust', k.verdunstung_kg, k.m0, k.r,       k.r_n,     k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen'),
    ('Schimmel/Fäulnis', 'verlust', k.schimmel_kg,    k.m1, k.f,       k.f_n,
     'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen',
     'Masse nach Verdunstung × Schimmelanteil bei dieser Lagerdauer'),
    ('Ausschuss zu klein','verlust', k.klein_kg,      k.m2, k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze'),
    ('Nebenkanal zu gross','marge',  k.nebenkanal_kg, k.m2, k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal'),
    ('Verkaufsfähig',    'bilanz',  k.verkaufsfaehig_kg, k.m2, null::numeric, null::int, null::text,
     'Rest der Kaskade')
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel);

create view v_verlust_ranking with (security_invoker = true) as
select strom, buch,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       sum(kg) filter (where szenario = 'mittel' and portion = 'ausgelagert') as kg_beobachtet,
       sum(kg) filter (where szenario = 'mittel' and portion = 'lager')       as kg_projiziert,
       -- Wie viel des Ergebnisses steht jenseits der längsten gemessenen
       -- Lagerdauer? Eine Zahl, die zu 80 % auf Hochrechnung beruht, darf
       -- nicht aussehen wie eine gemessene.
       sum(kg) filter (where szenario = 'mittel' and f_extrapoliert)          as kg_extrapoliert,
       min(koeff_n)                                                          as koeff_n_min
  from v_hochrechnung
 where buch = 'verlust'
 group by strom, buch
 order by 3 desc nulls last;

create view v_marge_buch with (security_invoker = true) as
with hr as materialized (
  select charge_nr, strom, buch, szenario, kg from v_hochrechnung
), kisten as materialized (
  select sum(h.kg * b.weg2_anteil) / 8.0 as anzahl
    from hr h
    join v_hochrechnung_basis b on b.charge_nr = h.charge_nr
   where h.strom = 'Verkaufsfähig' and h.szenario = 'mittel'
)
select 'Nebenkanal zu gross'::text as posten,
       sum(kg) filter (where szenario = 'mittel') as kg,
       sum(kg) filter (where szenario = 'unten')  as kg_unten,
       sum(kg) filter (where szenario = 'oben')   as kg_oben,
       'Ware über 2000 g geht in einen anderen Verkaufskanal'::text as erlaeuterung
  from hr where buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;

create view v_massenbilanz with (security_invoker = true) as
with modell as materialized (
  select charge_nr,
         sum(m2) filter (where portion = 'ausgelagert') as modell_kg,
         sum(verkaufsfaehig_kg) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade where szenario = 'mittel' group by charge_nr
), csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (
             where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
           / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren')
     and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       (m.modell_kg * q.anteil_mit_csv)::numeric(14,2)      as modell_am_band_kg,
       c.gemessen_kg                                        as csv_gemessen_kg,
       (c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)::numeric(14,2) as abweichung_kg,
       case when m.modell_kg * q.anteil_mit_csv > 0
            then ((c.gemessen_kg - m.modell_kg * q.anteil_mit_csv)
                  / (m.modell_kg * q.anteil_mit_csv))::numeric(10,4) end as abweichung_anteil,
       m.restbestand_kg::numeric(14,2)                      as restbestand_kg
  from v_hochrechnung_basis b
  left join modell m     on m.charge_nr = b.charge_nr
  left join csv_anteil q on q.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr;

comment on view v_massenbilanz is
  'abweichung_anteil nahe 0 heißt: die Koeffizienten treffen die Realität. '
  'Systematisch positiv → Verluste überschätzt, negativ → unterschätzt. '
  'Nur aussagekräftig für Chargen mit Sortier-CSV.';

-- ---------- Anzeige: was das Modell tut und woher es kommt ----------------
drop view if exists v_schimmel_kurve_anzeige;
create view v_schimmel_kurve_anzeige with (security_invoker = true) as
select k.von, k.bis,
       case when k.bis > 9999 then k.von || '+ Tage'
            else k.von || '–' || k.bis || ' Tage' end       as altersklasse,
       k.n                                                  as messungen,
       (k.anteil)::numeric(10,4)                            as gemessen,
       -- Was tatsächlich gerechnet wird: das Modell an der Klassenmitte
       (schimmelanteil((k.von + least(k.bis, k.von + 60)) / 2.0))::numeric(10,4) as verwendet,
       (schimmelanteil((k.von + least(k.bis, k.von + 60)) / 2.0, 'unten'))::numeric(10,4) as unten,
       (schimmelanteil((k.von + least(k.bis, k.von + 60)) / 2.0, 'oben'))::numeric(10,4)  as oben,
       case when not (select brauchbar from v_schimmel_modell)
                 then 'Modell noch nicht anpassbar — es gilt die Treppenfunktion'
            when k.von > (select t_max from v_schimmel_modell)
                 then 'über die längste gemessene Lagerdauer hinaus — hochgerechnet, '
                      || 'daher der breitere Bereich'
            when k.n = 0 then 'keine eigene Messung — aus dem Verlauf interpoliert'
            else 'durch Messungen dieser Altersklasse gestützt' end as erlaeuterung
  from v_schimmel_kurve k
 order by k.von;

grant execute on function t_quantil_95(int) to authenticated;
grant select on v_schimmel_modell, v_schimmel_kurve_anzeige, v_kaskade,
               v_hochrechnung, v_verlust_ranking, v_marge_buch,
               v_massenbilanz to authenticated;
