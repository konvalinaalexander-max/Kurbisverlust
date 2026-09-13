-- =====================================================================
-- 0071 — Was liegt, und was davon verkauft sich
--
-- Der Betrieb hat gesagt, was er wirklich wissen will, und es sind zwei
-- Fragen:
--
--   1. „Wie viel kam rein, wie viel ging raus, wie viel liegt noch — und
--      wie viel von dem, was noch liegt, ist verkaufsfähig?"  Dazu die
--      Zeitfrage, die ihn im Oktober beschäftigt, wenn der letzte Kürbis
--      vom Feld kommt: „Wenn ich im März noch so viel im Lager habe, muss
--      ich dann davon ausgehen, dass 15 % faul oder verdunstet sind?"
--   2. „Wohin ging der Kürbis, und was war am schlimmsten?"
--
-- Beide Fragen beantwortet diese Migration — **ohne eine zweite Mathematik**.
-- Jede Zahl über die Zukunft ist die Kaskade (`mv_kaskade`, Portion „lager")
-- an einem späteren Tag ausgewertet, mit denselben Formeln und denselben
-- Klammern. Bei Horizont 0 ist sie deshalb auf den Rappen die Zahl von
-- heute; `supabase/test/pruefung.sql` (Block 0071) hält genau das fest.
--
-- WAS NEU IST
--
--   · v_prognose / erg_prognose — je Gruppe (gesamt, Sorte, Schlag, Charge)
--     und je Horizont von heute bis zum Saisonende in Wochenschritten: was
--     aus der heute liegenden Ware wird, wenn sie liegen bleibt. Mit einer
--     Hülle (nicht einem gemeinsamen 95-%-Intervall) und der Rate je Tag.
--
--   · v_wohin / erg_wohin — der ganze Eingang je Gruppe aufgeteilt:
--     ausgeliefert, anderer Kanal, verdunstet, faul, Fax, und was liegt
--     (davon verkaufsfähig). Zwei Identitäten, die nicht von selbst
--     aufgehen: jede doppelt gezählte Portion bleibt als Rest stehen.
--
--   · erg_verlauf je Gruppe statt nur je Sorte, mit „im Lager" und
--     „verkaufsfähig" als eigenen Linien. Der Verlust ist damit keine Linie
--     mehr, sondern der Abstand zwischen beiden — und das ist die Form, in
--     der der Betriebsleiter ihn liest.
--
--   · v_naechste_charge rechnet „zwei Wochen länger liegen" aus v_prognose.
--     Vorher war es eine eigene Formel (F bis 0.99 geklammert, Verderb
--     bedingt auf die gute Masse); sie sagte für Charge 1632 466 kg, wo die
--     Kaskade 388 kg sagt. Ab jetzt gibt es im ganzen Programm genau **eine**
--     Zwei-Wochen-Zahl je Charge.
--
--   · v_fax_wartezeit / erg_fax_wartezeit — das Faule beim Abpacken nach
--     Tagen zwischen Waschen und Fax. Keine neue Frage an den Arbeiter: die
--     Angabe gibt es seit 0060, sie wurde nur nie ausgewertet.
--
--   · v_ueberfuellung_verkauf bekommt „Lage im Band" und „Spielraum" für
--     Stück-Kisten. Bezahlt wird je Stück; jedes Gramm über der Unterkante
--     des Kalibers geht unbezahlt mit. Das heisst **Spielraum**, nicht
--     „verschenkt" — niemand sortiert auf die Kante.
--
-- WAS SICH NICHT ÄNDERT
--
--   Keine Tabelle, keine Spalte wird gelöscht. Die Kaskade selbst bleibt
--   unangetastet — sie ist die Quelle, nicht der Gegenstand dieser Runde.
--   Die Gegenprobe (`gegenprobe/orakel/`) rechnet sie weiter unabhängig nach.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Der fehlende gespeicherte Koeffizient
--
-- Verdunstung, Ausschuss, Nebenkanal und Überfüllung haben seit 0061 je
-- eine gespeicherte Fassung; der Fax-Koeffizient nicht. Die Prognose
-- braucht alle vier Ränder, und vier Schätzer-Sichten nebeneinander neu zu
-- rechnen kostet je Lauf eine knappe Minute. Also bekommt auch dieser einen.
-- ---------------------------------------------------------------------
drop materialized view if exists erg_koeff_fax cascade;
create materialized view erg_koeff_fax as select * from v_koeff_fax with no data;
create unique index if not exists erg_koeff_fax_pk on erg_koeff_fax (sorte);
grant select on erg_koeff_fax to authenticated;
comment on materialized view erg_koeff_fax is
  'v_koeff_fax, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';

-- ---------------------------------------------------------------------
-- 0b. Die Ränder der Koeffizienten je Sorte — einmal je Neurechnen
--
-- Die Mittelwerte der Koeffizienten trägt mv_kaskade schon. Die **Ränder**
-- braucht nur die Prognose, für die Hülle. Sie stehen hier und nicht als
-- CTE in v_prognose, aus zwei Gründen:
--
--   · Tempo. Die vier Schätzer-Sichten lesen dieselbe teure Grundlage und
--     kosten zusammen gemessen 0.84 s. In v_prognose lief das bei jedem
--     Neurechnen mit und machte ein Drittel von Schritt 4 aus.
--   · Ordnung. Die naheliegende Abkürzung — v_prognose liest die
--     gespeicherten erg_koeff_… — geht nicht: erg_naechste_charge entsteht
--     in derselben Anweisung wie erg_koeff_…, und v_naechste_charge liest
--     erg_prognose. setup.sql liesse sich dann nicht mehr ordnen (ein
--     Kreis). Eine eigene gespeicherte Ansicht steht ausserhalb dieser
--     Anweisung und bricht ihn.
--
-- Geklammert wird hier wie in der Kaskade; die Normierung von „zu klein"
-- und „zu gross" (sie dürfen zusammen nicht über 1) gilt an jedem Rand für
-- sich und steht in v_prognose.
-- ---------------------------------------------------------------------
drop materialized view if exists mv_koeff_rand cascade;
create materialized view mv_koeff_rand as
  select b.sorte,
         least(greatest(coalesce(kv.unten::numeric, 0), 0), 0.05)   as r_unten,
         least(greatest(coalesce(kv.oben::numeric,  0), 0), 0.05)   as r_oben,
         least(greatest(coalesce(ka.unten::numeric, 0), 0), 1)      as klein_unten,
         least(greatest(coalesce(ka.oben::numeric,  0), 0), 1)      as klein_oben,
         least(greatest(coalesce(kn.unten::numeric, 0), 0), 1)      as gross_unten,
         least(greatest(coalesce(kn.oben::numeric,  0), 0), 1)      as gross_oben,
         least(greatest(coalesce(kf.unten::numeric, 0), 0), 1)      as fax_unten,
         least(greatest(coalesce(kf.oben::numeric,  0), 0), 1)      as fax_oben
    from (select distinct sorte from v_kaskade_basis) b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
    left join v_koeff_fax         kf on kf.sorte = b.sorte
with no data;
create unique index if not exists mv_koeff_rand_pk on mv_koeff_rand (sorte);
grant select on mv_koeff_rand to authenticated;
comment on materialized view mv_koeff_rand is
  'Die Ränder der Koeffizienten je Sorte (Verdunstung, zu klein, zu gross, '
  'Fax), geklammert wie in der Kaskade — die Grundlage der Hülle in '
  'v_prognose. Erneuert mit auswertung_schritt(2) (0071).';


-- ---------------------------------------------------------------------
-- 1. Die Prognose: die Kaskade an einem späteren Tag
--
-- Der Nenner ist die **liegende Eingangsware** (`lager_kg` = Σ m0 der
-- Portion „lager"), und er bleibt über den ganzen Horizont gleich. Nur
-- deshalb heisst ein fallender Prozentsatz wirklich „es wird weniger
-- verkaufsfähig": Beim Nenner „gute Ware" schrumpften Zähler und Nenner
-- gemeinsam, und der Anteil bliebe fast konstant, während Ware verdirbt.
--
-- Der Horizont reicht von heute bis zum Saisonende (`stichtag()`), in
-- Wochenschritten, dazu 7/14/28 Tage fest — damit „in zwei Wochen" und
-- „in vier Wochen" immer eine Stützstelle haben, auch kurz vor Saisonende.
-- Weiter als bis zum Saisonende reicht die Frage des Betriebs nicht:
-- geerntet wird August bis Oktober, verkauft August bis März.
--
-- Die Hülle (`verkaufsfaehig_unten_kg` / `_oben_kg`) ist **kein**
-- gemeinsames 95-%-Intervall. Sie entsteht, indem jeder Koeffizient an
-- seinen ungünstigsten Rand gesetzt wird — alle gleichzeitig. Das ist
-- bewusst konservativ: Sie sagt „schlimmer als das wird es nicht, besser
-- als jenes auch nicht", nicht „mit 95 % Wahrscheinlichkeit dazwischen".
-- ---------------------------------------------------------------------
create or replace view v_prognose with (security_invoker = true) as
with modell as materialized (
  select * from v_schimmel_modell
), kurve as materialized (
  select von, anteil_mono, unten as anteil_unten, oben as anteil_oben
    from v_schimmel_kurve where n > 0
), tag as materialized (
  -- heute() **einmal**. Die Funktion trägt `set search_path`, und das
  -- verhindert, dass Postgres sie in die Abfrage einsetzt: Jeder Aufruf ist
  -- ein echter Funktionsaufruf mit Sichern und Zurücksetzen der Einstellung,
  -- gemessen 47 µs. Stand sie — wie in der ersten Fassung — im Ausdruck
  -- `heute() + h` je Portion und Horizont, waren das im Lasttest 56 700
  -- Aufrufe und 2.7 s, mehr als die halbe Laufzeit der ganzen Sicht.
  select heute() as heute, stichtag() as stichtag
), ende as (
  -- Bis zum Saisonende, aber nie weiter als ein Jahr und nie kürzer als
  -- vier Wochen: „in zwei Wochen" muss auch am 20. März noch dastehen.
  select greatest(least(t.stichtag - t.heute, 400), 28) as tage from tag t
), horizonte as (
  select h from ende e, generate_series(0, e.tage, 7) g(h)
  union select 7 union select 14 union select 28
  union select tage from ende
), grenzen as (
  -- Die Ränder je Sorte, fertig gerechnet in Schritt 2 (mv_koeff_rand).
  select * from mv_koeff_rand
), lager as materialized (
  -- Die liegende Portion der Kaskade, unverändert übernommen. alter_tage
  -- ist dort schon auf 0 geklammert (0070: die Zeit läuft vorwärts).
  --
  -- Dazu die Verdunstung **bis heute** als fertiger Faktor: (1−r)^alter,
  -- einmal je Portion. Warum das hier steht und nicht unten in der Formel,
  -- steht bei `faktor_h`.
  select k.charge_nr, k.sorte, k.schlag, k.kohorte, k.alter_tage, k.m0,
         k.r, k.a0, k.a_klein_n, k.a_gross_n, k.a_fax,
         k.r_bekannt, k.f_bekannt, k.a0_bekannt,
         k.a_klein_bekannt, k.a_gross_bekannt, k.a_fax_bekannt,
         k.modell_gilt,
         coalesce(g.r_unten, 0) as r_unten, coalesce(g.r_oben, 0) as r_oben,
         coalesce(g.klein_unten, 0) as klein_unten, coalesce(g.klein_oben, 0) as klein_oben,
         coalesce(g.gross_unten, 0) as gross_unten, coalesce(g.gross_oben, 0) as gross_oben,
         coalesce(g.fax_unten, 0) as fax_unten, coalesce(g.fax_oben, 0) as fax_oben,
         power(1 - k.r, k.alter_tage)                            as wa,
         power(1 - greatest(coalesce(g.r_unten, 0), 0), k.alter_tage) as wa_unten,
         power(1 - greatest(coalesce(g.r_oben,  0), 0), k.alter_tage) as wa_oben
    from mv_kaskade k
    left join grenzen g on g.sorte = k.sorte
   where k.portion = 'lager' and k.m0 > 0 and k.alter_tage >= 0
), faktor_h as materialized (
  -- Warum es diese Tabelle gibt: `power()` auf numeric ist teuer — Postgres
  -- rechnet sie über Logarithmus und Exponent in voller Genauigkeit. In der
  -- ersten Fassung stand sie achtmal in der Formel und wurde für jede
  -- Portion mal jeden Horizont neu ausgeführt: beim Lasttest 1890 × 30 × 8 =
  -- 453 600 Aufrufe, gemessen 7.7 s für erg_prognose allein.
  --
  -- Dabei gilt (1−r)^(alter+h) = (1−r)^alter · (1−r)^h, und r hängt nur an
  -- der Charge. Der erste Teil steht darum oben je Portion (1890 Aufrufe),
  -- der zweite hier je Charge und Horizont (1260). Zusammen rund neuntausend
  -- statt einer halben Million — und in der Formel unten kommt kein
  -- `power()` mehr vor.
  select c.charge_nr, h.h,
         power(1 - c.r, h.h)                              as wh,
         power(1 - greatest(c.r_unten, 0), h.h)           as wh_unten,
         power(1 - greatest(c.r_oben,  0), h.h)           as wh_oben
    from (select distinct charge_nr, r, r_unten, r_oben from lager) c
   cross join horizonte h
), tage as (
  select distinct (l.alter_tage + h.h)::int as t from lager l cross join horizonte h
), f_je_tag as materialized (
  -- F(t) hängt nur vom Alter ab, nicht von der Portion — einmal je Tag
  -- gerechnet. Mittelwert und Ränder mit derselben Formel wie
  -- schimmelanteil(); der Rand ist η ± t·√(Var), nicht ein Zuschlag auf F.
  select t.t,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                     m.ln_lambda_korrigiert + m.k * ln(greatest(t.t::numeric, 1)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select c.anteil_mono from kurve c
                                              where c.von <= t.t order by c.von desc limit 1), 0), 0), 1)
         end as f,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                     m.ln_lambda_korrigiert + m.k * ln(greatest(t.t::numeric, 1))
                     - m.t_faktor * sqrt(greatest(m.var_achse
                         + power(ln(greatest(t.t::numeric, 1)) - m.x_mittel, 2) * m.var_k
                         + 2 * (ln(greatest(t.t::numeric, 1)) - m.x_mittel) * m.kov_achse_k, 0)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select coalesce(c.anteil_unten, c.anteil_mono) from kurve c
                                              where c.von <= t.t order by c.von desc limit 1), 0), 0), 1)
         end as f_unten,
         case when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                     m.ln_lambda_korrigiert + m.k * ln(greatest(t.t::numeric, 1))
                     + m.t_faktor * sqrt(greatest(m.var_achse
                         + power(ln(greatest(t.t::numeric, 1)) - m.x_mittel, 2) * m.var_k
                         + 2 * (ln(greatest(t.t::numeric, 1)) - m.x_mittel) * m.kov_achse_k, 0)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select coalesce(c.anteil_oben, c.anteil_mono) from kurve c
                                              where c.von <= t.t order by c.von desc limit 1), 0), 0), 1)
         end as f_oben
    from tage t cross join modell m
), je_portion as (
  select l.*, h.h, (l.alter_tage + h.h)::int as t,
         f.f, f.f_unten, f.f_oben, f0.f as f_heute,
         w.wh, w.wh_unten, w.wh_oben,
         case when m.brauchbar then coalesce(m.sockel_unten, m.sockel, 0) else 0 end as a0_unten,
         case when m.brauchbar then coalesce(m.sockel_oben,  m.sockel, 0) else 0 end as a0_oben,
         m.t_max,
         d.heute + h.h as datum
    from lager l
    cross join horizonte h
    cross join modell m
    cross join tag d
    join faktor_h w  on w.charge_nr = l.charge_nr and w.h = h.h
    join f_je_tag f  on f.t  = (l.alter_tage + h.h)::int
    join f_je_tag f0 on f0.t = l.alter_tage::int
), stroeme as (
  -- Die Ströme je Portion und Horizont — und zwar **fertig**, nicht als
  -- Zwischenwerte, aus denen die Summe unten noch einmal rechnet.
  --
  -- Warum das so aussieht: Vorher standen hier m1 und m2, und die Summe
  -- setzte daraus fünfzehnmal Ausdrücke zusammen (`sum(m2 * (1 − klein −
  -- gross) * fax)` und so fort). Postgres rechnet jeden dieser Ausdrücke je
  -- Zeile neu; bei 56 700 Zeilen im Lasttest waren das Sekunden. Jetzt
  -- stehen m1, m2 und „Rest nach Kanal" **einmal** da (die drei seitlichen
  -- Verbunde), jede Stromgrösse einmal, und die Summe unten addiert nur noch.
  --
  -- Auch kein `power()` mehr: (1−r)^(alter+h) ist das Produkt der zwei
  -- fertigen Faktoren wa (bis heute) und wh (der Horizont).
  select p.charge_nr, p.h, p.datum, p.t, p.m0,
         p.m0 - x.m1                                                           as verdunstet_kg,
         x.m1 * p.a0                                                           as sockel_kg,
         x.m1 * (1 - p.a0) * p.f                                               as faul_kg,
         y.m2 - z.rest                                                         as kanal_kg,
         z.rest * p.a_fax                                                      as fax_kg,
         z.rest * (1 - p.a_fax)                                                as verkaufsfaehig_kg,
         y.m2                                                                  as gute_ware_kg,
         -- Die Ränder: alle Koeffizienten gleichzeitig am ungünstigsten Rand.
         p.m0 * p.wa_oben * p.wh_oben * (1 - p.a0_oben) * (1 - p.f_oben)
              * (1 - least(p.klein_oben / greatest(p.klein_oben + p.gross_oben, 1)
                         + p.gross_oben / greatest(p.klein_oben + p.gross_oben, 1), 1))
              * (1 - p.fax_oben)                                               as vf_unten,
         p.m0 * p.wa_unten * p.wh_unten * (1 - p.a0_unten) * (1 - p.f_unten)
              * (1 - least(p.klein_unten / greatest(p.klein_unten + p.gross_unten, 1)
                         + p.gross_unten / greatest(p.klein_unten + p.gross_unten, 1), 1))
              * (1 - p.fax_unten)                                              as vf_oben,
         -- Was das Liegen ab heute an **verkaufsfähiger** Ware kostet, exakt
         -- in zwei Teile zerlegt. Sei B = m0·(1−a0)·(1−klein−gross)·(1−fax)
         -- die verkaufsfähige Grundmasse, t₀ das heutige Alter und h der
         -- Horizont; dann ist
         --   Wasser  = B·(1−r)^t₀·(1−F(t₀))·(1 − (1−r)^h)
         --   Fäulnis = B·(1−r)^t₀·(1−r)^h·(F(t₀+h) − F(t₀))
         -- und beide zusammen sind auf den Rappen VF(0) − VF(h). Beide sind
         -- nie negativ: (1−r)^h ≤ 1, und F wächst mit der Zeit. Die naive
         -- Differenz „faul nachher minus faul vorher" hätte das nicht — bei
         -- einer Charge, deren Verderb schon gesättigt ist, verliert auch das
         -- Faule Wasser, und die Differenz würde negativ.
         b.basis * (1 - p.f_heute) * (1 - p.wh)                                as verlust_wasser,
         b.basis * p.wh * greatest(p.f - p.f_heute, 0)                         as verlust_faeulnis,
         p.m0 * p.t                                                            as m0_mal_t,
         p.r_bekannt, p.f_bekannt, p.a0_bekannt,
         p.a_klein_bekannt, p.a_gross_bekannt, p.a_fax_bekannt, p.modell_gilt,
         (p.modell_gilt and p.t > p.t_max)                                     as ueber_t_max
    from je_portion p
    cross join lateral (select p.m0 * p.wa * p.wh as m1) x
    cross join lateral (select x.m1 * (1 - p.a0) * (1 - p.f) as m2) y
    cross join lateral (select y.m2 * (1 - p.a_klein_n - p.a_gross_n) as rest) z
    cross join lateral (select p.m0 * (1 - p.a0) * (1 - p.a_klein_n - p.a_gross_n)
                             * (1 - p.a_fax) * p.wa as basis) b
), gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from v_kaskade_basis
  union all select 'sorte',  sorte,           charge_nr from v_kaskade_basis
  union all select 'schlag', schlag,          charge_nr from v_kaskade_basis
  union all select 'charge', charge_nr::text, charge_nr from v_kaskade_basis
), je_charge as materialized (
  -- Erst je Charge verdichten, dann auf die Gruppen hochrollen: Die teure
  -- Arbeit (Kohorten mal Horizonte) passiert einmal, nicht viermal.
  select s.charge_nr, s.h, max(s.datum) as datum,
         count(*)::int                                                         as n_kohorten,
         sum(s.m0)                                                             as lager_kg,
         sum(s.verdunstet_kg)                                                  as verdunstet_kg,
         sum(s.sockel_kg)                                                      as sockel_kg,
         sum(s.faul_kg)                                                        as faul_kg,
         sum(s.kanal_kg)                                                       as kanal_kg,
         sum(s.fax_kg)                                                         as fax_kg,
         sum(s.verkaufsfaehig_kg)                                              as verkaufsfaehig_kg,
         sum(s.gute_ware_kg)                                                   as gute_ware_kg,
         sum(s.vf_unten)                                                       as vf_unten_kg,
         sum(s.vf_oben)                                                        as vf_oben_kg,
         sum(s.verlust_wasser)                                                 as verlust_wasser_kg,
         sum(s.verlust_faeulnis)                                               as verlust_faeulnis_kg,
         sum(s.m0_mal_t)                                                       as m0_mal_t,
         bool_and(s.r_bekannt)                                                 as r_bekannt,
         bool_and(s.f_bekannt)                                                 as f_bekannt,
         bool_and(s.a0_bekannt)                                                as sockel_bekannt,
         bool_and(s.a_klein_bekannt and s.a_gross_bekannt)                     as kanal_bekannt,
         bool_and(s.a_fax_bekannt)                                             as fax_bekannt,
         bool_and(s.modell_gilt)                                               as modell_gilt,
         bool_or(s.ueber_t_max)                                                as hochgerechnet,
         min(s.t)                                                              as alter_von,
         max(s.t)                                                              as alter_bis
    from stroeme s
   group by s.charge_nr, s.h
), summe as materialized (
  select g.gruppe, g.schluessel, j.h, max(j.datum) as datum,
         count(*)::int                                                         as n_chargen,
         sum(j.n_kohorten)::int                                                as n_kohorten,
         sum(j.lager_kg)                                                       as lager_kg,
         sum(j.verdunstet_kg)                                                  as verdunstet_kg,
         sum(j.sockel_kg)                                                      as sockel_kg,
         sum(j.faul_kg)                                                        as faul_kg,
         sum(j.kanal_kg)                                                       as kanal_kg,
         sum(j.fax_kg)                                                         as fax_kg,
         sum(j.verkaufsfaehig_kg)                                              as verkaufsfaehig_kg,
         sum(j.gute_ware_kg)                                                   as gute_ware_kg,
         sum(j.vf_unten_kg)                                                    as vf_unten_kg,
         sum(j.vf_oben_kg)                                                     as vf_oben_kg,
         sum(j.verlust_wasser_kg)                                              as verlust_wasser_kg,
         sum(j.verlust_faeulnis_kg)                                            as verlust_faeulnis_kg,
         bool_and(j.r_bekannt)                                                 as r_bekannt,
         bool_and(j.f_bekannt)                                                 as f_bekannt,
         bool_and(j.sockel_bekannt)                                            as sockel_bekannt,
         bool_and(j.kanal_bekannt)                                             as kanal_bekannt,
         bool_and(j.fax_bekannt)                                               as fax_bekannt,
         bool_and(j.modell_gilt)                                               as modell_gilt,
         bool_or(j.hochgerechnet)                                              as hochgerechnet,
         sum(j.m0_mal_t) / nullif(sum(j.lager_kg), 0)                          as alter_tage,
         min(j.alter_von)                                                      as alter_von,
         max(j.alter_bis)                                                      as alter_bis
    from je_charge j join gruppen g on g.charge_nr = j.charge_nr
   group by g.gruppe, g.schluessel, j.h
), rate as (
  -- Was die liegende Ware zurzeit je Tag kostet: der Schritt von heute auf
  -- die nächste Stützstelle, durch ihre Tage geteilt.
  select s0.gruppe, s0.schluessel,
         (s1.verlust_wasser_kg + s1.verlust_faeulnis_kg) / s1.h          as vf_je_tag_kg,
         s1.verlust_wasser_kg / s1.h                                     as verdunstet_je_tag_kg,
         s1.verlust_faeulnis_kg / s1.h                                   as faul_je_tag_kg
    from summe s0
    join lateral (select x.* from summe x
                   where x.gruppe = s0.gruppe and x.schluessel = s0.schluessel and x.h > 0
                   order by x.h limit 1) s1 on true
   where s0.h = 0
)
select s.gruppe, s.schluessel, s.h, s.datum, s.n_chargen, s.n_kohorten,
       zahl(s.lager_kg,          2, 1e12)::numeric(14,2)            as lager_kg,
       zahl(s.verdunstet_kg,     2, 1e12)::numeric(14,2)            as verdunstet_kg,
       zahl(s.sockel_kg,         2, 1e12)::numeric(14,2)            as sockel_kg,
       zahl(s.faul_kg,           2, 1e12)::numeric(14,2)            as faul_kg,
       zahl(s.kanal_kg,          2, 1e12)::numeric(14,2)            as kanal_kg,
       zahl(s.fax_kg,            2, 1e12)::numeric(14,2)            as fax_kg,
       zahl(s.verkaufsfaehig_kg, 2, 1e12)::numeric(14,2)            as verkaufsfaehig_kg,
       zahl(s.gute_ware_kg,      2, 1e12)::numeric(14,2)            as gute_ware_kg,
       -- Was das Liegen ab heute bis zu diesem Horizont kostet, in zwei
       -- Teilen, die exakt zusammen den Verlust an verkaufsfähiger Ware
       -- ergeben (bei h = 0 sind alle drei null).
       zahl(s.verlust_wasser_kg,    2, 1e12)::numeric(14,2)         as verlust_wasser_kg,
       zahl(s.verlust_faeulnis_kg,  2, 1e12)::numeric(14,2)         as verlust_faeulnis_kg,
       zahl(s.verlust_wasser_kg + s.verlust_faeulnis_kg, 2, 1e12)::numeric(14,2)
                                                                    as verlust_verkaufsfaehig_kg,
       -- Leer ist nicht null (0064): Fehlt ein Koeffizient, sind die Massen
       -- oben eine obere Schranke — der **Anteil**, den der Betriebsleiter
       -- liest, ist dann unbekannt und bleibt leer. Ebenso die Hülle.
       (case when v.vollstaendig and s.lager_kg > 0
             then zahl(s.verkaufsfaehig_kg / s.lager_kg, 4, 1) end)::numeric(6,4) as verkaufsfaehig_anteil,
       (case when v.vollstaendig then zahl(s.vf_unten_kg, 2, 1e12) end)::numeric(14,2) as verkaufsfaehig_unten_kg,
       (case when v.vollstaendig then zahl(s.vf_oben_kg,  2, 1e12) end)::numeric(14,2) as verkaufsfaehig_oben_kg,
       zahl(r.vf_je_tag_kg,         1, 1e9)::numeric(12,1)          as verkaufsfaehig_je_tag_kg,
       zahl(r.verdunstet_je_tag_kg, 1, 1e9)::numeric(12,1)          as verdunstet_je_tag_kg,
       zahl(r.faul_je_tag_kg,       1, 1e9)::numeric(12,1)          as faul_je_tag_kg,
       s.r_bekannt, s.f_bekannt, s.sockel_bekannt, s.kanal_bekannt, s.fax_bekannt,
       v.vollstaendig, s.modell_gilt, s.hochgerechnet,
       round(s.alter_tage)::int as alter_tage, s.alter_von, s.alter_bis
  from summe s
  cross join lateral (select (s.r_bekannt and s.f_bekannt and s.sockel_bekannt
                              and s.kanal_bekannt and s.fax_bekannt) as vollstaendig) v
  left join rate r on r.gruppe = s.gruppe and r.schluessel = s.schluessel;

comment on view v_prognose is
  'Was aus der heute liegenden Ware wird, wenn sie liegen bleibt — je Gruppe '
  '(gesamt, Sorte, Schlag, Charge) und je Horizont h Tage, von heute bis zum '
  'Saisonende in Wochenschritten (7/14/28 immer dabei). Es ist die Kaskade '
  '(mv_kaskade, Portion „lager") bei alter_tage + h, mit denselben Formeln: '
  'bei h = 0 stehen deshalb genau die Zahlen von erg_charge. Der Nenner ist '
  'lager_kg, die liegende Eingangsware — er ändert sich über den Horizont '
  'nicht. verkaufsfaehig_unten/oben ist eine Hülle (alle Koeffizienten '
  'gleichzeitig am ungünstigsten Rand), kein gemeinsames 95-%%-Intervall. '
  'Fehlt ein Koeffizient, bleiben Anteil und Hülle leer — die Massen sind '
  'dann eine obere Schranke (0064).';
grant select on v_prognose to authenticated;

drop materialized view if exists erg_prognose cascade;
create materialized view erg_prognose as select * from v_prognose with no data;
create unique index if not exists erg_prognose_pk on erg_prognose (gruppe, schluessel, h);
create index if not exists erg_prognose_gruppe on erg_prognose (gruppe, h);
grant select on erg_prognose to authenticated;
comment on materialized view erg_prognose is
  'v_prognose, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';


-- ---------------------------------------------------------------------
-- 2. Wohin ging der Kürbis — der Eingang, vollständig aufgeteilt
--
-- Zwei Identitäten, und beide gehen **nicht** von selbst auf:
--
--   Eingang + Überzählung = ausgeliefert + anderer Kanal (ausgeliefert)
--                         + verdunstet + faul + Fax + im Lager
--   im Lager = verkaufsfähig + Kanal + Fax erwartet + faul + verdunstet
--
-- `rest_kg` und `lager_rest_kg` stehen als Spalten da, damit eine doppelt
-- gezählte oder vergessene Portion nicht unsichtbar bleibt, sondern als
-- Zahl. Block 0071 der Prüfung lässt für beide 0.1 kg zu — das ist die
-- Rundung von numeric(14,2) über sechzig Gruppen, nichts weiter.
-- ---------------------------------------------------------------------
create or replace view v_wohin with (security_invoker = true) as
with gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from erg_charge
  union all select 'sorte',  sorte,           charge_nr from erg_charge
  union all select 'schlag', schlag,          charge_nr from erg_charge
  union all select 'charge', charge_nr::text, charge_nr from erg_charge
), charge as (
  select g.gruppe, g.schluessel,
         count(*)::int                          as n_chargen,
         sum(c.eingang_kg)                      as eingang_kg,
         sum(c.ueberzaehlung_kg)                as ueberzaehlung_kg,
         sum(c.geliefert_kg)                    as geliefert_kg,
         sum(c.kanal_ausgelagert_kg)            as kanal_ausgelagert_kg,
         sum(c.fax_heute_kg)                    as fax_kg,
         sum(c.im_haus_heute_kg)                as lager_gute_ware_kg,
         sum(c.verkaufsfaehig_lager_kg)         as lager_verkaufsfaehig_kg,
         sum(c.kanal_im_haus_kg)                as lager_kanal_kg,
         sum(c.fax_erwartet_kg)                 as lager_fax_kg,
         sum(c.lager_kg)                        as lager_kg,
         bool_and(c.verlust_bekannt)            as vollstaendig
    from gruppen g join erg_charge c on c.charge_nr = g.charge_nr
   group by g.gruppe, g.schluessel
), stroeme as (
  -- kg_beobachtet ist der Teil an der ausgelieferten Ware (schon passiert),
  -- kg_projiziert der Teil an der liegenden Ware (bis heute gerechnet).
  select gruppe, schluessel,
         sum(kg_beobachtet) filter (where strom = 'Verdunstung')           as verdunstet_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Verdunstung')           as lager_verdunstet_kg,
         sum(kg_beobachtet) filter (where strom = 'Schimmel/Fäulnis')      as faul_roh_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Schimmel/Fäulnis')      as lager_faul_roh_kg,
         sum(kg_beobachtet) filter (where strom = 'Nicht lagerbedingt')    as sockel_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Nicht lagerbedingt')    as lager_sockel_kg,
         sum(kg_beobachtet) filter (where strom = 'Zu klein (Tierfutter)') as klein_ausgelagert_kg,
         sum(kg_beobachtet) filter (where strom = 'Nebenkanal zu gross')   as gross_ausgelagert_kg,
         sum(kg_projiziert) filter (where strom = 'Zu klein (Tierfutter)') as lager_klein_kg,
         sum(kg_projiziert) filter (where strom = 'Nebenkanal zu gross')   as lager_gross_kg
    from erg_verlust
   group by gruppe, schluessel
)
select c.gruppe, c.schluessel, c.n_chargen,
       zahl(c.eingang_kg)::numeric(14,2)                            as eingang_kg,
       zahl(c.ueberzaehlung_kg)::numeric(14,2)                      as ueberzaehlung_kg,
       zahl(c.geliefert_kg)::numeric(14,2)                          as geliefert_kg,
       zahl(c.kanal_ausgelagert_kg)::numeric(14,2)                  as kanal_ausgelagert_kg,
       zahl(s.klein_ausgelagert_kg)::numeric(14,2)                  as klein_ausgelagert_kg,
       zahl(s.gross_ausgelagert_kg)::numeric(14,2)                  as gross_ausgelagert_kg,
       zahl(s.verdunstet_ausgelagert_kg)::numeric(14,2)             as verdunstet_ausgelagert_kg,
       -- „faul" enthält den Sockel (nicht lagerbedingt); er steht daneben
       -- noch einmal für sich, weil er nie im Lager entstanden ist.
       zahl(s.faul_roh_ausgelagert_kg + coalesce(s.sockel_ausgelagert_kg, 0))::numeric(14,2)
                                                                    as faul_ausgelagert_kg,
       zahl(s.sockel_ausgelagert_kg)::numeric(14,2)                 as sockel_ausgelagert_kg,
       zahl(c.fax_kg)::numeric(14,2)                                as fax_kg,
       zahl(c.lager_kg)::numeric(14,2)                              as lager_kg,
       zahl(c.lager_gute_ware_kg)::numeric(14,2)                    as lager_gute_ware_kg,
       zahl(c.lager_verkaufsfaehig_kg)::numeric(14,2)               as lager_verkaufsfaehig_kg,
       zahl(c.lager_kanal_kg)::numeric(14,2)                        as lager_kanal_kg,
       zahl(s.lager_klein_kg)::numeric(14,2)                        as lager_klein_kg,
       zahl(s.lager_gross_kg)::numeric(14,2)                        as lager_gross_kg,
       zahl(c.lager_fax_kg)::numeric(14,2)                          as lager_fax_kg,
       zahl(s.lager_faul_roh_kg + coalesce(s.lager_sockel_kg, 0))::numeric(14,2)
                                                                    as lager_faul_kg,
       zahl(s.lager_sockel_kg)::numeric(14,2)                       as lager_sockel_kg,
       zahl(s.lager_verdunstet_kg)::numeric(14,2)                   as lager_verdunstet_kg,
       zahl(c.eingang_kg + c.ueberzaehlung_kg - c.geliefert_kg - c.kanal_ausgelagert_kg
            - s.verdunstet_ausgelagert_kg - s.faul_roh_ausgelagert_kg
            - coalesce(s.sockel_ausgelagert_kg, 0) - c.fax_kg - c.lager_kg)::numeric(14,2) as rest_kg,
       zahl(c.lager_kg - c.lager_verkaufsfaehig_kg - c.lager_kanal_kg - c.lager_fax_kg
            - s.lager_faul_roh_kg - coalesce(s.lager_sockel_kg, 0)
            - s.lager_verdunstet_kg)::numeric(14,2)                 as lager_rest_kg,
       c.vollstaendig
  from charge c
  left join stroeme s on s.gruppe = c.gruppe and s.schluessel = c.schluessel;

comment on view v_wohin is
  'Wohin ging der Kürbis — je Gruppe (gesamt, Sorte, Schlag, Charge) der ganze '
  'Eingang aufgeteilt: ausgeliefert, anderer Kanal, verdunstet und faul an der '
  'ausgelieferten Ware, Faules beim Abpacken, und was noch liegt (davon '
  'verkaufsfähig, Kanal, Fax erwartet, faul, verdunstet). rest_kg und '
  'lager_rest_kg sind die zwei Identitäten: beide haben den Erwartungswert '
  'null, und eine doppelt gezählte Portion bleibt darin stehen (0071).';
grant select on v_wohin to authenticated;

-- ---------------------------------------------------------------------
-- 3. Lieferungen je Charge und Tag — eine Regel, an einer Stelle
--
-- Eine Lieferung ohne Chargennummer wird nach dem Eingangsanteil auf die
-- Chargen ihrer Sorte verteilt. Diese Regel steckte bisher nur in
-- `v_lieferung_kohorte`; der Verlauf je Schlag und Charge braucht sie auch.
-- Damit es sie nicht zweimal gibt, steht sie jetzt hier — und
-- `v_lieferung_kohorte` rechnet darauf weiter.
-- ---------------------------------------------------------------------
create or replace view v_lieferung_charge_tag with (security_invoker = true) as
with lief as (
  select l.id, l.datum, l.buch, l.masse_kg, c.charge_nr, c.anteil
    from (select heute() as heute) d
    cross join v_lieferung_masse l
    cross join lateral (
      select l.charge_nr, 1::numeric as anteil where l.charge_nr is not null
      union all
      select r.charge_nr, r.eingang_netto_kg / sum(r.eingang_netto_kg) over ()
        from v_charge_rueckgrat r
       where l.charge_nr is null and r.sorte = l.sorte and r.eingang_netto_kg > 0
    ) c
   where l.masse_kg is not null and l.masse_kg > 0
     and l.buch in ('verkauf', 'marge', 'verlust') and l.datum <= d.heute
  union all
  -- Was vor dem Erfassungsbeginn rausging: eine Angabe des Betriebs je
  -- Charge, gebucht am Erfassungsbeginn.
  select -cv.charge_nr,
         coalesce((select nullif(wert #>> '{}', '')::date from einstellung where schluessel = 'erfassungsbeginn'),
                  r.letzter_eingang),
         'verkauf', cv.ausgang_vor_app_kg, cv.charge_nr, 1
    from charge_vorlauf cv join v_charge_rueckgrat r on r.charge_nr = cv.charge_nr
   where cv.ausgang_vor_app_kg > 0
)
select charge_nr, datum, buch,
       zahl(sum(masse_kg * anteil), 2, 1e12)::numeric(14,2) as masse_kg,
       count(distinct id)::int                              as n_lieferungen
  from lief
 group by charge_nr, datum, buch;

comment on view v_lieferung_charge_tag is
  'Gelieferte Masse je Charge, Tag und Buch — nur Lieferungen bis heute(). '
  'Eine Lieferung ohne Chargennummer wird nach dem Eingangsanteil auf die '
  'Chargen ihrer Sorte verteilt; der Vorlauf zählt am Erfassungsbeginn. '
  'Diese Regel gibt es nur hier: v_lieferung_kohorte rechnet darauf (0071).';
grant select on v_lieferung_charge_tag to authenticated;

-- v_lieferung_kohorte auf dieselbe Regel stellen. Spalten und Reihenfolge
-- bleiben unverändert — mv_kaskade hängt daran und wird nicht angefasst.
create or replace view v_lieferung_kohorte with (security_invoker = true) as
select f.charge_nr,
       k.eingangsdatum as kohorte,
       f.buch,
       zahl(sum(f.masse_kg * k.anteil), 2, 1e12)::numeric(14,2) as masse_kg,
       zahl(sum(f.masse_kg * k.anteil * greatest(f.datum - k.eingangsdatum, 0)::numeric)
            / nullif(sum(f.masse_kg * k.anteil), 0), 1, 1e5)::numeric(8,1) as alter_tage,
       sum(f.n_lieferungen)::int as n_lieferungen,
       min(f.datum) as von,
       max(f.datum) as bis
  from v_lieferung_charge_tag f
  join v_kohorte_anteil k on k.charge_nr = f.charge_nr
 group by f.charge_nr, k.eingangsdatum, f.buch;

-- ---------------------------------------------------------------------
-- 4. Der Verlauf je Gruppe, mit „im Lager" und „verkaufsfähig"
--
-- Bisher gab es je Woche eine Zeile je Sorte (und eine für alles). Der
-- Betrieb will den Verlauf aber auch je Schlag und je Charge sehen — und
-- vor allem nicht mehr den Verlust als Linie, sondern **was liegt** und
-- **was davon verkaufsfähig ist**. Der Verlust ist dann der Abstand
-- zwischen beiden Linien; so liest ihn der Betriebsleiter ohnehin.
--
-- Der Horizont reicht bis zum Saisonende, mindestens aber zwölf Wochen.
-- ---------------------------------------------------------------------
drop materialized view if exists erg_verlauf cascade;
create materialized view erg_verlauf as
with tag as materialized (
  -- heute() und stichtag() **einmal** — siehe die Erklärung bei v_prognose:
  -- Beide tragen `set search_path`, werden darum nicht in die Abfrage
  -- eingesetzt und kosten je Aufruf rund 47 µs. In der Endauswahl unten
  -- stünde heute() sonst je Woche und Gruppe da, also tausendfach.
  select heute() as heute, stichtag() as stichtag
), modell as materialized (
  select * from v_schimmel_modell
), kurve as materialized (
  select von, anteil_mono from v_schimmel_kurve where n > 0
), wochen as materialized (
  select w::date as woche, (w + interval '6 days')::date as bis
    from tag t, generate_series(
      date_trunc('week', coalesce((select min(eingangsdatum) from palette), t.heute))::date,
      date_trunc('week', greatest(t.stichtag, t.heute + 84))::date, interval '7 days') w
  union
  select date_trunc('week', t.heute)::date, t.heute from tag t
), gruppen as (
  select 'gesamt'::text as gruppe, ''::text as schluessel, charge_nr from v_kaskade_basis
  union all select 'sorte',  sorte,           charge_nr from v_kaskade_basis
  union all select 'schlag', schlag,          charge_nr from v_kaskade_basis
  union all select 'charge', charge_nr::text, charge_nr from v_kaskade_basis
), portionen as materialized (
  select k.charge_nr, k.portion, k.kohorte, k.m0, k.r, k.a0,
         k.a_klein_n, k.a_gross_n, k.a_fax,
         case when k.portion = 'ausgelagert' then k.kohorte + round(k.alter_tage)::int end as liefertag,
         case when k.portion = 'ausgelagert' then k.fax_kg else 0 end                      as fax_kg
    from mv_kaskade k
   where k.m0 > 0 and k.kohorte is not null
), f_je_tag as materialized (
  select gs.t,
         case when gs.t <= 0 then 0
              when m.brauchbar then least(greatest(1 - exp(-exp(least(greatest(
                     m.ln_lambda_korrigiert + m.k * ln(greatest(gs.t::numeric, 1)), -40), 3))), 0), 1)
              else least(greatest(coalesce((select c.anteil_mono from kurve c
                                              where c.von <= gs.t order by c.von desc limit 1), 0), 0), 1)
         end as f
    from generate_series(0, greatest(coalesce(
           (select max(w.bis) from wochen w) - (select min(p.kohorte) from portionen p), 0), 0)) gs(t)
   cross join modell m
), je_woche as (
  -- Erst je Charge und Woche verdichten: Die teure Arbeit (Portionen mal
  -- Wochen) passiert einmal statt viermal, und die vier Gruppenebenen sind
  -- danach ein billiges Hochrollen über sechsunddreissig Chargen.
  select w.woche, w.bis, p.charge_nr,
         p.m0 * (1 - power(1 - p.r, x.t))                                     as verdunstung_kg,
         p.m0 * power(1 - p.r, x.t) * p.a0                                    as sockel_kg,
         p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * f.f                        as schimmel_kg,
         case when p.liefertag is not null and p.liefertag <= w.bis then p.fax_kg else 0 end as fax_kg,
         -- Was am Wochenende noch liegt: die Portion, solange sie nicht
         -- ausgeliefert ist. „im Lager" ist die Eingangsware (m0), „gute
         -- Ware" das, was nach Verdunstung und Verderb davon übrig ist,
         -- „verkaufsfähig" davon noch ohne zu klein/zu gross und ohne das
         -- Faule, das beim Abpacken noch anfällt.
         case when p.liefertag is null or p.liefertag > w.bis then p.m0 else 0 end as lager_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * (1 - f.f) else 0 end as gute_ware_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * (1 - f.f)
                   * (p.a_klein_n + p.a_gross_n) else 0 end                        as kanal_lager_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * (1 - f.f)
                   * (1 - p.a_klein_n - p.a_gross_n) * p.a_fax else 0 end          as fax_lager_kg,
         case when p.liefertag is null or p.liefertag > w.bis
              then p.m0 * power(1 - p.r, x.t) * (1 - p.a0) * (1 - f.f)
                   * (1 - p.a_klein_n - p.a_gross_n) * (1 - p.a_fax) else 0 end    as verkaufsfaehig_kg
    from wochen w
    join portionen p on p.kohorte <= w.bis
    cross join lateral (
      select greatest(least(w.bis, coalesce(p.liefertag, w.bis)) - p.kohorte, 0) as t
    ) x
    join f_je_tag f on f.t = x.t
), je_charge as materialized (
  select woche, bis, charge_nr,
         sum(verdunstung_kg) as verdunstung_kg, sum(sockel_kg) as sockel_kg,
         sum(schimmel_kg) as schimmel_kg, sum(fax_kg) as fax_kg,
         sum(gute_ware_kg) as im_haus_kg, sum(lager_kg) as lager_kg,
         sum(kanal_lager_kg) as kanal_kg, sum(fax_lager_kg) as fax_lager_kg,
         sum(verkaufsfaehig_kg) as verkaufsfaehig_kg
    from je_woche
   group by woche, bis, charge_nr
), verlust as (
  select j.woche, j.bis, g.gruppe, g.schluessel,
         sum(j.verdunstung_kg) as verdunstung_kg, sum(j.sockel_kg) as sockel_kg,
         sum(j.schimmel_kg) as schimmel_kg, sum(j.fax_kg) as fax_kg,
         sum(j.im_haus_kg) as im_haus_kg, sum(j.lager_kg) as lager_kg,
         sum(j.kanal_kg) as kanal_kg, sum(j.fax_lager_kg) as fax_lager_kg,
         sum(j.verkaufsfaehig_kg) as verkaufsfaehig_kg
    from je_charge j join gruppen g on g.charge_nr = j.charge_nr
   group by j.woche, j.bis, g.gruppe, g.schluessel
), eingang_charge as materialized (
  -- Gelesen wird v_charge_kohorte, nicht v_palette. Der Unterschied sind die
  -- Paletten ohne Nettogewicht (fehlende Tara oder Kistenzahl): v_palette
  -- lässt sie weg, v_charge_kohorte rechnet sie mit dem Mittel der übrigen
  -- hoch — so wie die Kaskade und die Saisonbilanz es tun (0064). Vorher
  -- stand im Verlauf darum ein kleinerer Eingang als in der Bilanz; auf der
  -- bösen Saison 432 237 kg gegen 432 667 kg, und die Kurve „im Haus" fing
  -- 430 kg zu tief an. Gefunden hat das K10 der Gegenprobe.
  select w.woche, w.bis, k.charge_nr, sum(k.eingang_kg) as kg
    from wochen w join v_charge_kohorte k on k.eingangsdatum <= w.bis
   group by w.woche, w.bis, k.charge_nr
), eingang as (
  select e.woche, e.bis, g.gruppe, g.schluessel, sum(e.kg) as kg
    from eingang_charge e join gruppen g on g.charge_nr = e.charge_nr
   group by e.woche, e.bis, g.gruppe, g.schluessel
), ausgang_charge as materialized (
  select w.woche, w.bis, l.charge_nr, sum(l.masse_kg) as kg
    from wochen w join v_lieferung_charge_tag l on l.datum <= w.bis
   group by w.woche, w.bis, l.charge_nr
), ausgang as (
  select a.woche, a.bis, g.gruppe, g.schluessel, sum(a.kg) as kg
    from ausgang_charge a join gruppen g on g.charge_nr = a.charge_nr
   group by a.woche, a.bis, g.gruppe, g.schluessel
), liste as (
  select distinct gruppe, schluessel from gruppen
)
select w.woche, w.bis, (w.bis > d.heute)                                      as prognose,
       s.gruppe, s.schluessel,
       zahl(coalesce(e.kg, 0), 2, 1e12)::numeric(14,2)                         as eingang_kum_kg,
       zahl(coalesce(a.kg, 0), 2, 1e12)::numeric(14,2)                         as ausgang_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0), 2, 1e12)::numeric(14,2)             as verdunstung_kum_kg,
       zahl(coalesce(v.schimmel_kg, 0), 2, 1e12)::numeric(14,2)                as schimmel_kum_kg,
       zahl(coalesce(v.sockel_kg, 0), 2, 1e12)::numeric(14,2)                  as sockel_kum_kg,
       zahl(coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)                     as fax_kum_kg,
       zahl(coalesce(v.verdunstung_kg, 0) + coalesce(v.schimmel_kg, 0)
            + coalesce(v.sockel_kg, 0) + coalesce(v.fax_kg, 0), 2, 1e12)::numeric(14,2)
                                                                              as verlust_kum_kg,
       zahl(coalesce(v.im_haus_kg, 0), 2, 1e12)::numeric(14,2)                 as im_haus_kg,
       zahl(coalesce(v.lager_kg, 0), 2, 1e12)::numeric(14,2)                   as lager_kg,
       zahl(coalesce(v.verkaufsfaehig_kg, 0), 2, 1e12)::numeric(14,2)          as verkaufsfaehig_kg,
       zahl(coalesce(v.kanal_kg, 0), 2, 1e12)::numeric(14,2)                   as kanal_kg,
       zahl(coalesce(v.fax_lager_kg, 0), 2, 1e12)::numeric(14,2)               as fax_lager_kg
  from wochen w
  cross join liste s
  cross join tag d
  left join verlust v on v.bis = w.bis and v.gruppe = s.gruppe and v.schluessel = s.schluessel
  left join eingang e on e.bis = w.bis and e.gruppe = s.gruppe and e.schluessel = s.schluessel
  left join ausgang a on a.bis = w.bis and a.gruppe = s.gruppe and a.schluessel = s.schluessel
 with no data;
create unique index if not exists erg_verlauf_pk on erg_verlauf (woche, bis, gruppe, schluessel);
create index if not exists erg_verlauf_gruppe on erg_verlauf (gruppe, schluessel, bis);
-- erg_verlauf_woche steht seit 0061 auf dieser Ansicht. „drop … cascade"
-- oben nimmt ihn mit — in setup.sql aber nicht: Der Verdichter trägt
-- Index-Zeilen aus alten Migrationen weiter, und dann hätte die eine Art,
-- die Datenbank einzurichten, einen Index mehr als die andere. Genau das
-- meldet Stufe 4 von supabase/test/run.sh. Also steht er hier wieder.
create index if not exists erg_verlauf_woche on erg_verlauf (woche);
grant select on erg_verlauf to authenticated;
comment on materialized view erg_verlauf is
  'Je Woche und Gruppe (gesamt, Sorte, Schlag, Charge): Eingang und Ausgang '
  'kumuliert (gemessen), im Lager (Eingangsware, die noch nicht hinter einer '
  'Lieferung steckt) und davon verkaufsfähig (gerechnet) — ab heute als '
  'Prognose bis zum Saisonende (prognose = true). Der Verlust ist der Abstand '
  'zwischen im Lager und verkaufsfähig; seine Teile stehen weiter als eigene '
  'Spalten (0071).';

-- ---------------------------------------------------------------------
-- 5. „Zwei Wochen länger liegen" — dieselbe Formel wie überall
--
-- Bisher rechnete diese Sicht eigenständig: F bis 0.99 geklammert und der
-- Verderb bedingt auf die gute Masse. Für Charge 1632 kam dabei 466 kg
-- heraus, wo die Kaskade 388 kg sagt — zwei Zahlen für dieselbe Frage, auf
-- zwei Bildschirmen. Ab jetzt liest sie v_prognose.
--
-- prognose_verlust_14_kg heisst deshalb genau, was es ist: **was zwei
-- weitere Wochen an verkaufsfähiger Ware kosten**. Das ist etwas weniger
-- als Verdunstung + Verderb zusammen, weil mit der Masse auch der Anteil
-- schrumpft, der ohnehin zu klein, zu gross oder Fax-Ausschuss gewesen wäre.
-- ---------------------------------------------------------------------
create or replace view v_naechste_charge with (security_invoker = true) as
select p0.schluessel::int                                        as charge_nr,
       b.sorte, b.schlag,
       p0.lager_kg,
       p0.alter_tage,
       p0.gute_ware_kg                                           as masse_jetzt_kg,
       zahl(p14.verlust_wasser_kg, 1, 1e11)::numeric(12,1)                       as verdunstung_14_kg,
       (case when p0.modell_gilt
             then zahl(p14.verlust_faeulnis_kg, 1, 1e11) end)::numeric(12,1)     as schimmel_14_kg,
       (case when p0.modell_gilt
             then zahl(p14.verlust_verkaufsfaehig_kg, 1, 1e11) end)::numeric(12,1)
                                                                 as prognose_verlust_14_kg,
       p0.hochgerechnet, p0.modell_gilt,
       p0.alter_von, p0.alter_bis, p0.n_kohorten
  from erg_prognose p0
  join erg_prognose p14 on p14.gruppe = 'charge' and p14.schluessel = p0.schluessel and p14.h = 14
  join v_kaskade_basis b on b.charge_nr = p0.schluessel::int
 where p0.gruppe = 'charge' and p0.h = 0 and p0.lager_kg > 0
 order by (case when p0.modell_gilt
                then zahl(p14.verlust_verkaufsfaehig_kg, 1, 1e11) end)::numeric(12,1)
          desc nulls last;

comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Gerechnet '
  'aus v_prognose (Horizont 14 gegen Horizont 0) — dieselbe Formel wie die '
  'Kaskade, damit es im ganzen Programm nur eine Zwei-Wochen-Zahl gibt. '
  'prognose_verlust_14_kg ist, was an **verkaufsfähiger** Ware verloren geht, '
  'und verdunstung_14_kg + schimmel_14_kg ergeben es auf den Rappen: die '
  'Zerlegung ist multiplikativ exakt und beide Teile sind nie negativ (0071).';

-- ---------------------------------------------------------------------
-- 6. Faules beim Abpacken nach Wartezeit
--
-- Beim Fax wird nochmals Faules aussortiert — und der Verdacht des Betriebs
-- ist, dass die Tage zwischen Waschen und Abpacken daran schuld sind. Die
-- Angabe gibt es seit 0060 (`auftrag.tage_seit_waschen`, freiwillig); sie
-- wurde nur nie ausgewertet. Der Anteil ist massegewichtet — eine kleine
-- Arbeit soll nicht so viel zählen wie eine grosse.
-- ---------------------------------------------------------------------
create or replace view v_fax_wartezeit with (security_invoker = true) as
with roh as (
  select case when f.tage_seit_waschen is null then 'unbekannt'
              when f.tage_seit_waschen <= 1    then '0–1 Tage'
              when f.tage_seit_waschen <= 3    then '2–3 Tage'
              else '4 und mehr' end                              as klasse,
         f.sorte, f.masse_kg, f.faul_kg, f.anteil
    from v_fax_beobachtung f
   where f.status = 'abgeschlossen' and f.masse_kg is not null
), je as (
  -- Zweimal dieselben Arbeiten: einmal über alle Sorten, einmal je Sorte.
  select g.gruppe,
         (case when g.gruppe = 'sorte' then roh.sorte end) as sorte,
         roh.klasse,
         count(*)::int as n, sum(roh.masse_kg) as masse_kg, sum(roh.faul_kg) as faul_kg,
         sum(roh.faul_kg) / nullif(sum(roh.masse_kg + roh.faul_kg), 0) as anteil,
         stddev_samp(roh.anteil) as sd
    from roh cross join lateral (select unnest(array['alle', 'sorte']) as gruppe) g
   group by g.gruppe, (case when g.gruppe = 'sorte' then roh.sorte end), roh.klasse
)
select gruppe,
       sorte,
       klasse,
       case klasse when '0–1 Tage' then 1 when '2–3 Tage' then 2
                   when '4 und mehr' then 3 else 4 end          as reihenfolge,
       n,
       zahl(masse_kg, 1, 1e11)::numeric(12,1)                    as masse_kg,
       zahl(faul_kg,  1, 1e11)::numeric(12,1)                    as faul_kg,
       zahl(anteil, 5, 1e5)::numeric(10,5)                       as anteil,
       case when n >= 2 and sd is not null
            then zahl(greatest(anteil - t_quantil_95(n - 1) * sd / sqrt(n), 0), 5, 1e5)::numeric(10,5)
            else zahl(anteil, 5, 1e5)::numeric(10,5) end         as unten,
       case when n >= 2 and sd is not null
            then zahl(least(anteil + t_quantil_95(n - 1) * sd / sqrt(n), 1), 5, 1e5)::numeric(10,5)
            else zahl(anteil, 5, 1e5)::numeric(10,5) end         as oben
  from je;

comment on view v_fax_wartezeit is
  'Faules beim Abpacken nach Tagen zwischen Waschen und Fax — je Klasse '
  '(0–1 Tage, 2–3 Tage, 4 und mehr, unbekannt), einmal über alle Sorten und '
  'einmal je Sorte. Der Anteil ist massegewichtet (Faules ÷ durchgegangene '
  'Masse + Faules), der Bereich aus der Streuung zwischen den Arbeiten. '
  'Grundlage: auftrag.tage_seit_waschen, freiwillig seit 0060 (0071).';
grant select on v_fax_wartezeit to authenticated;

-- ---------------------------------------------------------------------
-- 7. Überfüllung: die Lage im Band
--
-- Bei „Kiste ab x kg" ist zu viel in der Kiste verschenkte Ware — das
-- rechnet die Sicht schon. Bei „x Stück je Kaliber" ist es anders: bezahlt
-- wird je Stück innerhalb eines Bandes, das Gewicht ist dem Käufer egal.
-- Wer nahe an der Unterkante des Bandes liefert, verkauft dieselbe Zahl
-- Kürbisse mit weniger Kilo. „Lage im Band" sagt, wo die gewogene Ware
-- liegt: 0 % ist die Unterkante, 100 % die Oberkante.
--
-- Die Lage wird **nicht** geklammert. Ein Wert über 100 % heisst, dass die
-- gewogene Kiste schwerer ist als die Oberkante ihres Kalibers — dann passt
-- die Kaliberangabe der Wägung nicht zur Ware, und das gehört gesehen und
-- nicht wegformatiert.
--
-- „Spielraum" heisst die Masse über der Unterkante ausdrücklich nicht
-- „verschenkt": Niemand sortiert auf die Kante, und eine Kiste an der
-- Unterkante wäre ein Reklamationsrisiko. Es ist der Rahmen, in dem sich
-- überhaupt etwas holen liesse.
-- ---------------------------------------------------------------------
create or replace view v_ueberfuellung_verkauf with (security_invoker = true) as
with verkauft as (
  select case when grouping(v.charge_nr) = 1 then 'sorte' else 'charge' end as gruppe,
         v.sorte, v.charge_nr, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx,
         count(*)::int as n_lieferungen, sum(v.kg) as kg_verkauft, sum(v.kisten) as kisten_verkauft,
         count(*) filter (where v.kisten_quelle = 'anteil')::int as n_anteilig,
         sum(v.stueck) as stueck_verkauft,
         sum(v.stueck * v.nenn_g::numeric) / nullif(sum(v.stueck), 0) as nenn_g,
         min(v.datum) as von, max(v.datum) as bis
    from v_verkauf_lieferung v
   where v.sorte is not null
   group by grouping sets ((v.sorte, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx),
                           (v.sorte, v.charge_nr, v.kistensystem, v.soll_kg_pro_kiste, v.stueck_je_kiste, v.kaliber_idx))
), gewogen as (
  select case when grouping(k.charge_nr) = 1 then 'sorte' else 'charge' end as gruppe,
         k.sorte, k.charge_nr, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
         case when k.kistensystem = 'stueck' then k.kaliber_idx end as kaliber_idx,
         count(*)::int as n_wiegungen, sum(k.kisten) as kisten_gewogen,
         sum(k.netto_kg) / nullif(sum(k.kisten), 0)::numeric as kg_je_kiste,
         stddev_samp(k.kg_pro_kiste) as sd_je_kiste,
         sum(k.ueberfuellung_kg) as zuviel_gewogen_kg,
         sum(k.netto_kg) / nullif(sum(k.kisten * k.stueck_je_kiste), 0)::numeric * 1000 as g_je_kuerbis,
         max(k.band_mittel_g) as band_mittel_g
    from v_ausgang_kennzahl k
   where k.kistensystem in ('kiste_ab', 'stueck')
     and (k.kistensystem <> 'kiste_ab' or k.soll_kg_pro_kiste is not null)
     and (k.kistensystem <> 'stueck'   or k.stueck_je_kiste  is not null)
   group by grouping sets ((k.sorte, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
                            (case when k.kistensystem = 'stueck' then k.kaliber_idx end)),
                           (k.sorte, k.charge_nr, k.kistensystem, k.soll_kg_pro_kiste, k.stueck_je_kiste,
                            (case when k.kistensystem = 'stueck' then k.kaliber_idx end)))
), band as (
  select distinct on (s.sorte, i.idx) s.sorte, i.idx as kaliber_idx,
         ((s.kaliber_baender -> i.idx) ->> 0)::int as von,
         ((s.kaliber_baender -> i.idx) ->> 1)::int as bis
    from sortierschema s
    cross join lateral generate_series(0, jsonb_array_length(s.kaliber_baender) - 1) i(idx)
   where s.art = 'kaliber' and s.kaliber_baender is not null and s.kaeufer is null and s.gilt_ab <= heute()
   order by s.sorte, i.idx, s.gilt_ab desc
)
select coalesce(v.gruppe, g.gruppe)                       as gruppe,
       coalesce(v.sorte, g.sorte)                         as sorte,
       coalesce(v.charge_nr, g.charge_nr)                 as charge_nr,
       coalesce(v.kistensystem, g.kistensystem)           as kistensystem,
       coalesce(v.soll_kg_pro_kiste, g.soll_kg_pro_kiste) as soll_kg_pro_kiste,
       coalesce(v.stueck_je_kiste, g.stueck_je_kiste)     as stueck_je_kiste,
       coalesce(v.kaliber_idx, g.kaliber_idx)             as kaliber_idx,
       b.von as band_von_g, b.bis as band_bis_g,
       zahl(v.nenn_g, 0, 1e6)::numeric(8,0)               as nenn_g,
       coalesce(v.n_lieferungen, 0)                       as n_lieferungen,
       zahl(v.kg_verkauft, 1, 1e11)::numeric(12,1)        as kg_verkauft,
       zahl(v.kisten_verkauft, 0, 1e9)::numeric(12,0)     as kisten_verkauft,
       coalesce(v.n_anteilig, 0)                          as n_anteilig,
       zahl(v.stueck_verkauft, 0, 1e9)::numeric(12,0)     as stueck_verkauft,
       v.von, v.bis,
       coalesce(g.n_wiegungen, 0)                         as n_wiegungen,
       g.kisten_gewogen,
       zahl(g.kg_je_kiste, 3, 1e7)::numeric(10,3)         as kg_je_kiste,
       zahl(g.sd_je_kiste, 3, 1e7)::numeric(10,3)         as sd_je_kiste,
       zahl(g.kg_je_kiste - g.soll_kg_pro_kiste, 3, 1e7)::numeric(10,3) as zuviel_je_kiste,
       zahl(g.zuviel_gewogen_kg, 1, 1e11)::numeric(12,1)  as zuviel_gewogen_kg,
       zahl(case when g.n_wiegungen > 0 and v.kisten_verkauft is not null and g.kistensystem = 'kiste_ab'
                 then greatest(g.kg_je_kiste - g.soll_kg_pro_kiste, 0) * v.kisten_verkauft
                 else null::numeric end,
            1, 1e11)::numeric(12,1)                       as verschenkt_kg,
       zahl(case when g.n_wiegungen >= 2 and v.kisten_verkauft is not null and g.kistensystem = 'kiste_ab'
                 then (t_quantil_95(g.n_wiegungen - 1) * g.sd_je_kiste)::double precision
                      / sqrt(g.n_wiegungen::double precision) * v.kisten_verkauft::double precision end,
            1, 1e11)::numeric(12,1)                       as verschenkt_fehler_kg,
       zahl(g.g_je_kuerbis, 0, 1e6)::numeric(8,0)         as g_je_kuerbis,
       zahl(g.band_mittel_g, 0, 1e6)::numeric(8,0)        as band_mittel_g,
       -- Neu (0071): wo im Kaliberband liegt die gewogene Ware, und wie viel
       -- Masse geht über der Unterkante unbezahlt mit?
       zahl(case when b.von is not null and b.bis is not null and b.bis > b.von and g.g_je_kuerbis is not null
                 then (g.g_je_kuerbis - b.von) / (b.bis - b.von)::numeric end,
            4, 1e4)::numeric(8,4)                         as lage_im_band,
       zahl(case when g.g_je_kuerbis is not null and b.von is not null and v.stueck_verkauft is not null
                 then (g.g_je_kuerbis - b.von) / 1000.0 * v.stueck_verkauft end,
            1, 1e11)::numeric(12,1)                       as spielraum_kg
  from verkauft v
  full join gewogen g
    on g.gruppe = v.gruppe and g.sorte = v.sorte and g.charge_nr is not distinct from v.charge_nr
   and g.kistensystem = v.kistensystem
   and g.soll_kg_pro_kiste is not distinct from v.soll_kg_pro_kiste
   and g.stueck_je_kiste is not distinct from v.stueck_je_kiste
   and g.kaliber_idx is not distinct from v.kaliber_idx
  left join band b on b.sorte = coalesce(v.sorte, g.sorte)
                  and b.kaliber_idx = coalesce(v.kaliber_idx, g.kaliber_idx);

comment on view v_ueberfuellung_verkauf is
  'Je Sorte und je Charge, je Kistensystem: verkaufte Kisten und Kilo aus der '
  'Verkaufsdatei, gewogene Kisten und Kilo je Kiste aus den fertigen Paletten. '
  'Bei „Kiste ab x kg" ist der Überschuss verschenkte Ware (verschenkt_kg). '
  'Bei „x Stück je Kaliber" zählt die Lage im Band: 0 = Unterkante, 1 = '
  'Oberkante, über 1 heisst, die Wägung passt nicht zu ihrem Kaliber. '
  'spielraum_kg ist die Masse über der Unterkante, die unbezahlt mitgeht — '
  'Rahmen, nicht Verlust: niemand sortiert auf die Kante (0061, 0071).';

-- ---------------------------------------------------------------------
-- 8. Die gespeicherten Ansichten und das Rechenwerk
--
-- erg_ueberfuellung muss neu gebaut werden, damit die zwei neuen Spalten
-- ankommen: Eine gespeicherte Ansicht hält die Spaltenliste von damals fest.
--
-- Daran hing bisher v_marge_buch — es las die **gespeicherte** Fassung. Das
-- hatte zwei Kosten, und beide fallen hier weg. Erstens riss jedes Neubauen
-- von erg_ueberfuellung v_marge_buch und erg_marge mit („drop … cascade"),
-- und diese Migration musste beide wörtlich wiederherstellen — eine Kopie,
-- die beim nächsten Mal wieder abweichen kann. Zweitens hing die Marge
-- daran, wann zuletzt gerechnet wurde. Ab jetzt liest v_marge_buch die
-- Sicht selbst. Dann genügt „create or replace" (die Spaltenliste bleibt
-- gleich), erg_marge bleibt stehen, und erg_ueberfuellung lässt sich ohne
-- „cascade" neu bauen. Gemessen kostet das Neurechnen dadurch nichts
-- Nennenswertes: v_ueberfuellung_verkauf läuft einmal je Lauf mehr.
-- ---------------------------------------------------------------------
create or replace view v_marge_buch with (security_invoker = true) as
WITH verkauf AS (
         SELECT sum(v_ueberfuellung_verkauf.verschenkt_kg) AS verschenkt_kg,
            sum(
                CASE
                    WHEN v_ueberfuellung_verkauf.verschenkt_kg IS NULL THEN NULL::numeric
                    ELSE GREATEST(v_ueberfuellung_verkauf.verschenkt_kg - COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric), 0::numeric)
                END) AS verschenkt_unten_kg,
            sum(v_ueberfuellung_verkauf.verschenkt_kg + COALESCE(v_ueberfuellung_verkauf.verschenkt_fehler_kg, 0::numeric)) AS verschenkt_oben_kg,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen > 0) AS kisten_gerechnet,
            sum(v_ueberfuellung_verkauf.kisten_verkauft) FILTER (WHERE v_ueberfuellung_verkauf.n_wiegungen = 0) AS kisten_ungewogen,
            sum(v_ueberfuellung_verkauf.n_wiegungen) AS n_wiegungen,
            sum(v_ueberfuellung_verkauf.kisten_gewogen) AS kisten_gewogen,
            sum(v_ueberfuellung_verkauf.zuviel_je_kiste * v_ueberfuellung_verkauf.kisten_gewogen::numeric) / NULLIF(sum(v_ueberfuellung_verkauf.kisten_gewogen) FILTER (WHERE v_ueberfuellung_verkauf.zuviel_je_kiste IS NOT NULL), 0::numeric) AS zuviel_je_kiste,
            count(*) FILTER (WHERE v_ueberfuellung_verkauf.n_lieferungen > 0)::integer AS n_gruppen_verkauft
           FROM v_ueberfuellung_verkauf
          WHERE v_ueberfuellung_verkauf.gruppe = 'sorte'::text AND v_ueberfuellung_verkauf.kistensystem = 'kiste_ab'::text
        ), datei AS (
         SELECT count(*)::integer AS n
           FROM lieferung_import
        )
 SELECT r.strom AS posten,
    r.kg,
    r.kg_unten,
    r.kg_oben,
        CASE r.strom
            WHEN 'Nebenkanal zu gross'::text THEN 'Ware über der oberen Kalibergrenze geht in einen anderen Verkaufskanal — nicht weg, nur nicht zum besten Preis'::text
            WHEN 'Zu klein (Tierfutter)'::text THEN 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'::text
            ELSE ''::text
        END AS erlaeuterung,
    r.kg IS NOT NULL AS gemessen
   FROM erg_verlust r
  WHERE r.gruppe = 'gesamt'::text AND r.buch = 'marge'::text
UNION ALL
 SELECT 'Überfüllung der Kisten'::text AS posten,
    zahl(v.verschenkt_kg)::numeric(14,2) AS kg,
    zahl(v.verschenkt_unten_kg)::numeric(14,2) AS kg_unten,
    zahl(v.verschenkt_oben_kg)::numeric(14,2) AS kg_oben,
        CASE
            WHEN d.n = 0 THEN 'Keine Verkaufsdatei eingelesen — wie viele Kisten „ab x kg" verkauft wurden, weiss die App nicht. Nichts gerechnet.'::text
            WHEN COALESCE(v.n_wiegungen, 0::bigint) = 0 THEN format('%s Kisten „ab x kg" laut Verkaufsdatei verkauft, aber keine fertige Palette dieses Systems gewogen — nichts gerechnet.'::text, round(COALESCE(v.kisten_ungewogen, 0::numeric)))
            ELSE format(('%s gewogene Paletten (%s Kisten): im Schnitt %s kg je Kiste über dem Soll. '::text || 'Verkauft laut Verkaufsdatei: %s Kisten desselben Systems — daraus die Zahl. '::text) || '%s'::text, v.n_wiegungen, round(COALESCE(v.kisten_gewogen, 0::numeric)), round(COALESCE(v.zuviel_je_kiste, 0::numeric), 3), round(COALESCE(v.kisten_gerechnet, 0::numeric)),
            CASE
                WHEN COALESCE(v.kisten_ungewogen, 0::numeric) > 0::numeric THEN format('Weitere %s verkaufte Kisten haben kein gewogenes Gegenstück (Sorte oder Soll ohne Wägung) und sind nicht gerechnet.'::text, round(v.kisten_ungewogen))
                ELSE 'Kisten nach Stück haben kein Sollgewicht und damit keine Überfüllung.'::text
            END)
        END AS erlaeuterung,
    v.verschenkt_kg IS NOT NULL AS gemessen
   FROM verkauf v
     CROSS JOIN datei d;
grant select on v_marge_buch to authenticated;
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb verlassen hat, ohne verkaufsfähig zu sein — zu '
  'klein, Nebenkanal, Überfüllung. Kein Verlust im Sinne von verdorben, sondern '
  'Masse in einem anderen Kanal. kg_unten und kg_oben spannen den Bereich auf, '
  'gemessen sagt, ob dahinter Messungen oder Schätzungen stehen.';

-- erg_marge wird hier **nicht** angefasst: Es steht auf v_marge_buch, dessen
-- Spaltenliste gleich bleibt, und gebaut wird es von der Liste aus 0068.
-- Stünde hier noch eine Bauanweisung, gäbe es in setup.sql zwei für denselben
-- Namen — und die zweite bräche mit „relation erg_marge already exists" ab.

-- Jetzt lässt sich erg_ueberfuellung neu bauen, ohne etwas mitzureissen.
drop materialized view if exists erg_ueberfuellung;
create materialized view erg_ueberfuellung as select * from v_ueberfuellung_verkauf with no data;
create index if not exists erg_ueberfuellung_gruppe on erg_ueberfuellung (gruppe, sorte, charge_nr);
grant select on erg_ueberfuellung to authenticated;
comment on materialized view erg_ueberfuellung is
  'v_ueberfuellung_verkauf, gespeichert für die App (0061, 0071). Erneuert mit auswertung_schritt().';


-- Die neuen gespeicherten Ansichten
drop materialized view if exists erg_wohin cascade;
create materialized view erg_wohin as select * from v_wohin with no data;
create unique index if not exists erg_wohin_pk on erg_wohin (gruppe, schluessel);
grant select on erg_wohin to authenticated;
comment on materialized view erg_wohin is
  'v_wohin, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';

drop materialized view if exists erg_fax_wartezeit cascade;
create materialized view erg_fax_wartezeit as select * from v_fax_wartezeit with no data;
create unique index if not exists erg_fax_wartezeit_pk on erg_fax_wartezeit (gruppe, coalesce(sorte, ''), klasse);
grant select on erg_fax_wartezeit to authenticated;
comment on materialized view erg_fax_wartezeit is
  'v_fax_wartezeit, gespeichert für die App (0071). Erneuert mit auswertung_schritt().';

-- ---------------------------------------------------------------------
-- 8b. Warum Schritt 2 vier Sekunden verlor
--
-- Mit den zwei neuen gespeicherten Ansichten (erg_koeff_fax,
-- erg_fax_wartezeit, zusammen gemessen 0.43 s) stiess Schritt 2 im Lasttest
-- über die Sechs-Sekunden-Marke von supabase/test/run.sh. Gesucht und
-- gefunden wurde nicht bei den Neuen, sondern bei erg_verarbeitung_alter:
-- 3.96 s von 6.5 s.
--
-- Der Grund ist eine Zeile, nicht die Datenmenge. `betriebstag(a.start_ts)`
-- steht in der Verbundbedingung zwischen Auftrag und Palette und wird darum
-- für **jedes Paar** ausgerechnet — bei 840 Aufträgen und 5040 Paletten
-- millionenfach, obwohl es je Auftrag genau einen Wert gibt. Steht der Tag
-- vorher einmal je Auftrag da (`tage as materialized`), bleibt alles andere
-- gleich: dieselben Spalten, dieselben 840 Zeilen, keine Zeile anders
-- (nachgerechnet mit `except` in beide Richtungen). Gemessen 3963 ms → 69 ms.
-- ---------------------------------------------------------------------
create or replace view v_verarbeitung_alter with (security_invoker = true) as
with tage as materialized (
  select a.id, a.charge_nr, a.station, a.weg, betriebstag(a.start_ts) as tag
    from auftrag a
   where a.abgebrochen_ts is null
), gezaehlt as (
  select t.id as auftrag_id, count(*)::int as n_paletten,
         zahl(avg(t.tag - ap.eingangsdatum), 1, 1e9)::numeric(10,1) as alter_verarbeitet
    from tage t
    join auftrag_palette ap on ap.auftrag_id = t.id
   where ap.eingangsdatum is not null
   group by t.id
), charge_am_tag as (
  select t.id as auftrag_id,
         zahl(avg(t.tag - p.eingangsdatum), 1, 1e9)::numeric(10,1) as alter_charge
    from tage t
    join palette p on p.charge_nr = t.charge_nr and p.eingangsdatum <= t.tag
   group by t.id
)
select t.id as auftrag_id, t.charge_nr, c.sorte, c.schlag, t.station, t.weg, t.tag,
       g.n_paletten, g.alter_verarbeitet, l.alter_charge,
       zahl(g.alter_verarbeitet - l.alter_charge, 1, 1e9)::numeric(10,1) as differenz
  from tage t
  join charge c on c.nr = t.charge_nr
  join gezaehlt g on g.auftrag_id = t.id
  left join charge_am_tag l on l.auftrag_id = t.id
 where t.station <> 'waschen'::station;


-- ---------------------------------------------------------------------
-- 9. Das Rechenwerk: die neuen Ansichten in Schritt 4
--
-- Reihenfolge zählt: erg_wohin liest erg_verlust und erg_charge, also nach
-- erg_verlust. erg_prognose und erg_verlauf lesen nur mv_kaskade (Schritt 3).
-- ---------------------------------------------------------------------
create or replace function auswertung_schritt(p_schritt integer)
returns jsonb language plpgsql security definer set search_path = public set jit = off as $$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'mv_schimmel_punkte', 'mv_schimmel_modell',
                       'erg_punkte', 'erg_modell', 'erg_kurve', 'erg_selektion',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_prognose', 'erg_wohin', 'erg_verlauf', 'erg_bilanz',
                       'erg_marge', 'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  if p_schritt = 1 then
    for v_name in
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
  end if;

  foreach v_name in array v_namen loop
    execute format('refresh materialized view %I', v_name);
    execute format('analyze %I', v_name);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif p_schritt = 1 then
    update auswertung_stand
       set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  else
    update auswertung_stand
       set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5);
end $$;
comment on function auswertung_schritt(integer) is
  'Ein Schritt des Neurechnens. Nur für den Betriebsleiter — oder ohne Anmeldung, '
  'also für die Prüfstände als Eigentümer. Ein Lauf sperrt jede gespeicherte '
  'Ansicht für rund drei Sekunden (0068, 0071).';

-- ---------------------------------------------------------------------
-- 10. Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 71 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
