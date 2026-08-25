-- =====================================================================
-- 0018 — Koeffizienten massegewichtet, chargen-robust und teilgebündelt
--
-- Nach 0017 trifft der Schimmel. Was übrig bleibt, misst der Harness so
-- (25 Saisons, 50 % im Lager):
--
--   Ausschuss zu klein   Verzerrung −0.1 %   Bereich 0.8 % breit   Überdeckung 44 %
--
-- Der Punktwert stimmt, der Bereich ist eine Behauptung. Vier Gründe, alle
-- im Code nachweisbar, alle hier behoben.
--
-- ---------- 1. Gewichteter Mittelwert, ungewichtete Streuung --------------
-- v_koeff_ausschuss bildete den Mittelwert massegewichtet
--   sum(anteil * basis_kg) / sum(basis_kg)
-- die Streuung daneben aber ungewichtet
--   stddev_samp(anteil)
-- Das sind zwei verschiedene Grössen; die zweite beschreibt die erste nicht.
--
-- ---------- 2. n zählt Messungen, nicht unabhängige Gruppen ---------------
-- Auf dem Testbestand:
--
--   Sorte        Messungen   Chargen
--   Kaori Kuri       51         2
--   Tiana            36         1
--   Fictor           35         1
--
-- Mit n = 51 in mittel ± 1.96·sd/√n kommt ein Bereich von 0.8 % Breite
-- heraus. Tatsächlich stammen die 51 Messungen aus zwei Chargen — gleicher
-- Schlag, gleiche Ernte, gleiche Sortiereinstellung. Sie sind keine 51
-- unabhängigen Ziehungen. Bei Tiana ist es *eine* Charge: daraus lässt sich
-- die Streuung zwischen Chargen gar nicht schätzen.
--
-- ---------- 3. Verdunstung war massenungewichtet --------------------------
-- v_verdunstung_stichprobe nahm avg(rate_pro_tag): eine 400-kg-Palette zählte
-- so viel wie eine 900-kg-Palette, obwohl sie halb so viel Masse vertritt.
--
-- ---------- 4. Harte Schwelle statt Teilbündelung -------------------------
-- „eigene Sorte ab n ≥ 3, sonst global" springt: bei n = 2 gilt der globale
-- Wert voll, bei n = 3 der eigene voll — obwohl sich zwischen den beiden
-- Fällen fast nichts geändert hat. Ersetzt durch empirisches Bayes: der
-- Sortenwert wird mit dem Gewicht
--
--   B = τ² / (τ² + Fehler²)
--
-- zum Gesamtwert gezogen, wobei τ² die geschätzte echte Streuung zwischen
-- den Sorten ist. Viele verlässliche eigene Messungen → B nahe 1, der eigene
-- Wert zählt. Wenige oder aus nur einer Charge → B nahe 0, der Gesamtwert
-- trägt. Kein Sprung, und keine Sorte behauptet mehr Sicherheit als sie hat.
--
-- Alle drei Koeffizienten sind derselbe Schätzer — ein massegewichteter
-- Anteil — und werden deshalb hier einmal gemeinsam gerechnet statt dreimal
-- fast gleich.
-- =====================================================================

-- ---------- Die Rohbeobachtungen -----------------------------------------
-- Zwei getrennte Quellen, und zwar zwingend: v_ausschuss_beobachtung rechnet
-- die Basismasse der Handmessungen um die Verdunstung herunter und liest dazu
-- v_koeff_verdunstung. Läge alles in einer Ansicht, hinge der
-- Verdunstungskoeffizient über den Umweg an sich selbst — Postgres bricht das
-- mit „infinite recursion in rules" ab, und zu Recht.
create or replace view v_koeff_roh_verdunstung with (security_invoker = true) as
-- Tagesrate je gewogener Palette, gewichtet mit der Masse, die sie vertritt.
select 'verdunstung'::text as art, m.sorte, m.charge_nr,
       m.rate_pro_tag::numeric as anteil, m.netto_jetzt_kg::numeric as gewicht
  from v_verdunstung_messung m
 where m.verwendbar and m.netto_jetzt_kg > 0;

create or replace view v_koeff_roh_kaliber with (security_invoker = true) as
-- Massenanteil je Sortierlauf bzw. Handmessung, gewichtet mit der sortierten
-- Masse. Beide Kaliber-Koeffizienten stammen aus derselben Beobachtung.
select 'ausschuss'::text as art, b.sorte, b.charge_nr,
       b.klein_kg / b.basis_kg as anteil, b.basis_kg as gewicht
  from v_ausschuss_beobachtung b
 where b.plausibel and b.basis_kg > 0 and b.klein_kg is not null
union all
select 'nebenkanal', b.sorte, b.charge_nr,
       b.gross_kg / b.basis_kg, b.basis_kg
  from v_ausschuss_beobachtung b
 where b.plausibel and b.basis_kg > 0 and b.gross_kg is not null;

comment on view v_koeff_roh_kaliber is
  'Koeffizienten-Rohwerte in einheitlicher Form: Anteil, die Masse, die er '
  'vertritt, und die Charge, aus der er stammt.';

-- Derselbe Schätzer zweimal — er kann nicht über beide Quellen laufen, ohne
-- den Zyklus oben wieder aufzumachen. Änderungen gehören in beide.

-- ---------- Schätzer: Verdunstung ----------
create or replace view v_koeff_verdunstung_geschaetzt with (security_invoker = true) as
with roh as materialized (
  select art, sorte, charge_nr, anteil, gewicht from v_koeff_roh_verdunstung
   where anteil is not null and gewicht > 0
),
je_charge as (
  -- Ein Durchgang. Alles Weitere braucht nur noch diese Summen je Charge:
  -- Σw·Anteil und Σw. Frühere Fassungen scannten die Beobachtungen einmal je
  -- Sorte und brauchten 3.2 s allein für v_koeff_ausschuss.
  select art, sorte, charge_nr,
         sum(gewicht)          as sw_c,
         sum(anteil * gewicht) as swa_c,
         count(*)              as n_c
    from roh group by art, sorte, charge_nr
),
ebene as (
  -- Sortenebene und Gesamtebene (sorte = NULL) in einem Durchgang
  select art, sorte, sum(sw_c) as sw, sum(swa_c) as swa,
         sum(n_c)::int as n, count(distinct charge_nr)::int as c_chargen
    from je_charge
   group by grouping sets ((art, sorte), (art))
),
mittelwert as (
  select e.*, e.swa / nullif(e.sw, 0) as mittel from ebene e
),
varianz as (
  -- Chargen-robuste Varianz des massegewichteten Anteils. Die gewichtete
  -- Abweichungssumme einer Charge ist Σw·Anteil − Mittel·Σw, also direkt aus
  -- den Chargensummen zu haben. Die Streuung *dieser Summen* ist der Fehler;
  -- mit einer einzigen Charge gibt es nichts zu streuen und sie bleibt NULL.
  select m.*, v.varianz
    from mittelwert m
    cross join lateral (
      select case when m.c_chargen > 1 and m.sw > 0
                  then sum(power(j.swa_c - m.mittel * j.sw_c, 2)) / power(m.sw, 2)
                       * m.c_chargen::numeric / (m.c_chargen - 1) end as varianz
        from je_charge j
       where j.art = m.art and (m.sorte is null or j.sorte = m.sorte)
    ) v
),
gesamt as (
  select art, mittel, varianz, c_chargen, n, sw from varianz where sorte is null
),
tau as (
  -- τ²: wie stark sich die Sorten *wirklich* unterscheiden. Die beobachtete
  -- Streuung der Sortenmittel enthält auch den eigenen Schätzfehler; der wird
  -- abgezogen (Momentenschätzer). Bleibt nichts übrig, unterscheiden sich die
  -- Sorten nicht nachweisbar und es wird voll gebündelt.
  select v.art,
         greatest(
           sum(v.sw * power(v.mittel - g.mittel, 2)) / nullif(sum(v.sw), 0)
           - coalesce(avg(v.varianz), 0), 0) as tau2
    from varianz v join gesamt g on g.art = v.art
   where v.sorte is not null
   group by v.art
),
gitter as (
  -- Jede Sorte des Stammdatensatzes bekommt eine Zeile, auch die ungemessene.
  -- Sonst fiele sie ganz heraus und ihr Koeffizient stünde auf 0 — also „kein
  -- Verlust", was schlicht falsch ist.
  select a.art, sk.sorte from (select distinct art from roh) a cross join sorte_kaliber sk
  union all
  select art, null::text from (select distinct art from roh) a
)
select gi.art, gi.sorte, coalesce(v.n, 0) as n, coalesce(v.c_chargen, 0) as c_chargen,
       v.mittel                                            as mittel_roh,
       v.varianz                                           as varianz_roh,
       g.mittel                                            as mittel_gesamt,
       t.tau2,
       -- Bündelungsgewicht: 0 = ganz der Gesamtwert, 1 = ganz der eigene
       b.gewicht                                           as b,
       -- coalesce, weil eine Sorte ohne eigene Messung kein v.mittel hat;
       -- b ist dann 0 und es bleibt genau der Gesamtwert stehen.
       (b.gewicht * coalesce(v.mittel, g.mittel)
        + (1 - b.gewicht) * g.mittel)                      as mittel,
       -- Fehler des gebündelten Werts: der eigene, um B geschrumpft, plus
       -- der Rest-Anteil am Fehler des Gesamtwerts.
       (b.gewicht * coalesce(v.varianz, 0)
        + power(1 - b.gewicht, 2) * coalesce(g.varianz, 0)) as varianz,
       -- Freiheitsgrade: so viele unabhängige Chargen, wie tatsächlich
       -- eingehen — zwischen der eigenen Zahl und der des Gesamtwerts.
       greatest(round(b.gewicht * coalesce(v.c_chargen, 0)
                      + (1 - b.gewicht) * g.c_chargen)::int - 1, 1) as df,
       g.n                                                 as n_gesamt,
       -- Für die Fehlerfortpflanzung: der eigene, unabhängige Anteil am
       -- Fehler und das Gewicht, mit dem der (allen Sorten gemeinsame)
       -- Gesamtwert eingeht. Die beiden dürfen nicht wie unabhängige Fehler
       -- addiert werden — der Gesamtwert ist derselbe für jede Sorte.
       power(b.gewicht, 2) * coalesce(v.varianz, 0)        as varianz_eigen,
       (1 - b.gewicht)                                     as gewicht_gesamt,
       coalesce(g.varianz, 0)                              as varianz_gesamt
  from gitter gi
  join gesamt g on g.art = gi.art
  left join varianz v on v.art = gi.art and v.sorte is not distinct from gi.sorte
  left join tau t on t.art = gi.art
  cross join lateral (
    select case when gi.sorte is null then 1.0
                when v.varianz is null or v.mittel is null
                     or coalesce(t.tau2, 0) = 0 then 0.0
                else t.tau2 / (t.tau2 + v.varianz) end as gewicht
  ) b;

-- ---------- Schätzer: Ausschuss zu klein und Nebenkanal zu gross ----------
create or replace view v_koeff_kaliber_geschaetzt with (security_invoker = true) as
with roh as materialized (
  select art, sorte, charge_nr, anteil, gewicht from v_koeff_roh_kaliber
   where anteil is not null and gewicht > 0
),
je_charge as (
  -- Ein Durchgang. Alles Weitere braucht nur noch diese Summen je Charge:
  -- Σw·Anteil und Σw. Frühere Fassungen scannten die Beobachtungen einmal je
  -- Sorte und brauchten 3.2 s allein für v_koeff_ausschuss.
  select art, sorte, charge_nr,
         sum(gewicht)          as sw_c,
         sum(anteil * gewicht) as swa_c,
         count(*)              as n_c
    from roh group by art, sorte, charge_nr
),
ebene as (
  -- Sortenebene und Gesamtebene (sorte = NULL) in einem Durchgang
  select art, sorte, sum(sw_c) as sw, sum(swa_c) as swa,
         sum(n_c)::int as n, count(distinct charge_nr)::int as c_chargen
    from je_charge
   group by grouping sets ((art, sorte), (art))
),
mittelwert as (
  select e.*, e.swa / nullif(e.sw, 0) as mittel from ebene e
),
varianz as (
  -- Chargen-robuste Varianz des massegewichteten Anteils. Die gewichtete
  -- Abweichungssumme einer Charge ist Σw·Anteil − Mittel·Σw, also direkt aus
  -- den Chargensummen zu haben. Die Streuung *dieser Summen* ist der Fehler;
  -- mit einer einzigen Charge gibt es nichts zu streuen und sie bleibt NULL.
  select m.*, v.varianz
    from mittelwert m
    cross join lateral (
      select case when m.c_chargen > 1 and m.sw > 0
                  then sum(power(j.swa_c - m.mittel * j.sw_c, 2)) / power(m.sw, 2)
                       * m.c_chargen::numeric / (m.c_chargen - 1) end as varianz
        from je_charge j
       where j.art = m.art and (m.sorte is null or j.sorte = m.sorte)
    ) v
),
gesamt as (
  select art, mittel, varianz, c_chargen, n, sw from varianz where sorte is null
),
tau as (
  -- τ²: wie stark sich die Sorten *wirklich* unterscheiden. Die beobachtete
  -- Streuung der Sortenmittel enthält auch den eigenen Schätzfehler; der wird
  -- abgezogen (Momentenschätzer). Bleibt nichts übrig, unterscheiden sich die
  -- Sorten nicht nachweisbar und es wird voll gebündelt.
  select v.art,
         greatest(
           sum(v.sw * power(v.mittel - g.mittel, 2)) / nullif(sum(v.sw), 0)
           - coalesce(avg(v.varianz), 0), 0) as tau2
    from varianz v join gesamt g on g.art = v.art
   where v.sorte is not null
   group by v.art
),
gitter as (
  -- Jede Sorte des Stammdatensatzes bekommt eine Zeile, auch die ungemessene.
  -- Sonst fiele sie ganz heraus und ihr Koeffizient stünde auf 0 — also „kein
  -- Verlust", was schlicht falsch ist.
  select a.art, sk.sorte from (select distinct art from roh) a cross join sorte_kaliber sk
  union all
  select art, null::text from (select distinct art from roh) a
)
select gi.art, gi.sorte, coalesce(v.n, 0) as n, coalesce(v.c_chargen, 0) as c_chargen,
       v.mittel                                            as mittel_roh,
       v.varianz                                           as varianz_roh,
       g.mittel                                            as mittel_gesamt,
       t.tau2,
       -- Bündelungsgewicht: 0 = ganz der Gesamtwert, 1 = ganz der eigene
       b.gewicht                                           as b,
       -- coalesce, weil eine Sorte ohne eigene Messung kein v.mittel hat;
       -- b ist dann 0 und es bleibt genau der Gesamtwert stehen.
       (b.gewicht * coalesce(v.mittel, g.mittel)
        + (1 - b.gewicht) * g.mittel)                      as mittel,
       -- Fehler des gebündelten Werts: der eigene, um B geschrumpft, plus
       -- der Rest-Anteil am Fehler des Gesamtwerts.
       (b.gewicht * coalesce(v.varianz, 0)
        + power(1 - b.gewicht, 2) * coalesce(g.varianz, 0)) as varianz,
       -- Freiheitsgrade: so viele unabhängige Chargen, wie tatsächlich
       -- eingehen — zwischen der eigenen Zahl und der des Gesamtwerts.
       greatest(round(b.gewicht * coalesce(v.c_chargen, 0)
                      + (1 - b.gewicht) * g.c_chargen)::int - 1, 1) as df,
       g.n                                                 as n_gesamt,
       -- Für die Fehlerfortpflanzung: der eigene, unabhängige Anteil am
       -- Fehler und das Gewicht, mit dem der (allen Sorten gemeinsame)
       -- Gesamtwert eingeht. Die beiden dürfen nicht wie unabhängige Fehler
       -- addiert werden — der Gesamtwert ist derselbe für jede Sorte.
       power(b.gewicht, 2) * coalesce(v.varianz, 0)        as varianz_eigen,
       (1 - b.gewicht)                                     as gewicht_gesamt,
       coalesce(g.varianz, 0)                              as varianz_gesamt
  from gitter gi
  join gesamt g on g.art = gi.art
  left join varianz v on v.art = gi.art and v.sorte is not distinct from gi.sorte
  left join tau t on t.art = gi.art
  cross join lateral (
    select case when gi.sorte is null then 1.0
                when v.varianz is null or v.mittel is null
                     or coalesce(t.tau2, 0) = 0 then 0.0
                else t.tau2 / (t.tau2 + v.varianz) end as gewicht
  ) b;

comment on view v_koeff_kaliber_geschaetzt is
  'Massegewichteter Anteil je Sorte, chargen-robust gefehlert und per '
  'empirischem Bayes zum Gesamtwert gezogen. b = 1 heisst: die Sorte trägt '
  'sich selbst, b = 0: es gilt der Gesamtwert.';

-- ---------- Die drei benannten Koeffizienten ------------------------------
-- Gleiche Spalten wie bisher, damit Kaskade und Dashboard unverändert lesen.
create or replace view v_koeff_verdunstung with (security_invoker = true) as
select sk.sorte,
       coalesce(k.mittel, 0)::numeric                                  as mittel,
       -- Ist die Varianz 0, gab es nichts zu streuen (eine einzige Charge).
       -- Dann steht der Punktwert dreimal da — das ist ehrlicher als ein
       -- erfundener Bereich, und basis/n sagen, warum.
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                         as unten,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else k.mittel + k.t * sqrt(k.varianz)
        end)::double precision                                         as oben,
       coalesce(k.n, 0)                                                as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Wiegung vorhanden'
            when k.b >= 0.67        then 'Wiegungen dieser Sorte'
            when k.b >= 0.33        then 'Wiegungen dieser Sorte, zum Gesamtwert gezogen'
            else 'Wiegungen aller Sorten (zu wenige eigene Chargen)' end as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_verdunstung_geschaetzt g
     where g.art = 'verdunstung' and g.sorte is not distinct from sk.sorte
  ) k on true;

create or replace view v_koeff_ausschuss with (security_invoker = true) as
select sk.sorte,
       coalesce(k.mittel, 0)::numeric                                       as mittel,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else least(k.mittel + k.t * sqrt(k.varianz), 1)
        end)::double precision                                              as oben,
       coalesce(k.n, 0)                                                     as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b >= 0.67     then 'Sortierläufe/Handmessungen dieser Sorte'
            when k.b >= 0.33     then 'eigene Messungen, zum Gesamtwert gezogen'
            else 'alle Sorten (zu wenige eigene Chargen)' end               as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'ausschuss' and g.sorte is not distinct from sk.sorte
  ) k on true;

create or replace view v_koeff_nebenkanal with (security_invoker = true) as
select sk.sorte,
       coalesce(k.mittel, 0)::numeric                                       as mittel,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then coalesce(k.mittel, 0)
             else least(k.mittel + k.t * sqrt(k.varianz), 1)
        end)::double precision                                              as oben,
       coalesce(k.n, 0)                                                     as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Messung vorhanden'
            when k.b >= 0.67     then 'Sortierläufe/Handmessungen dieser Sorte'
            when k.b >= 0.33     then 'eigene Messungen, zum Gesamtwert gezogen'
            else 'alle Sorten (zu wenige eigene Chargen)' end               as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'nebenkanal' and g.sorte is not distinct from sk.sorte
  ) k on true;

grant select on v_koeff_roh_verdunstung, v_koeff_roh_kaliber,
               v_koeff_verdunstung_geschaetzt, v_koeff_kaliber_geschaetzt to authenticated;

-- ---------- Unsicherheit aller Koeffizienten an einer Stelle --------------
-- Wird nur von der Fehlerfortpflanzung gelesen, nie von den Koeffizienten
-- selbst — sonst wäre der Zyklus von oben wieder da.
create or replace view v_koeff_unsicherheit with (security_invoker = true) as
select art, sorte, b, varianz_eigen, gewicht_gesamt, varianz_gesamt, df
  from v_koeff_verdunstung_geschaetzt
union all
select art, sorte, b, varianz_eigen, gewicht_gesamt, varianz_gesamt, df
  from v_koeff_kaliber_geschaetzt;

comment on view v_koeff_unsicherheit is
  'Je Koeffizient und Sorte: der eigene Fehleranteil, das Gewicht auf dem '
  'gemeinsamen Gesamtwert und dessen Fehler. Getrennt, weil der Gesamtwert '
  'für alle Sorten derselbe ist und seine Fehler sich nicht wegmitteln.';

grant select on v_koeff_unsicherheit to authenticated;
