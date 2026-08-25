-- =====================================================================
-- 0029 — Aus der Massenbilanz wird eine Bilanz
--
-- Bisher verglich v_massenbilanz das Modell mit der Sortier-CSV, und das auch
-- nur für den Teil einer Charge, der überhaupt eine CSV hat. Das prüft die
-- Koeffizienten — mehr nicht. Über die Verluste sagt es nichts, denn die CSV
-- wiegt, was *ankommt*, nicht was verschwand.
--
-- Mit dem Warenausgang (0028) geht die eigentliche Gegenprobe:
--
--   Eingang = Verlust + Ausgang + Restbestand
--
-- Was übrig bleibt, ist die Lücke. Sie ist die einzige Zahl im ganzen System,
-- die misst, was das Modell *nicht* sieht — nicht geschätzt, sondern als
-- Differenz zweier unabhängig erhobener Grössen.
--
-- Ehrlich bleibt sie nur mit einer Angabe daneben: wie vollständig der
-- Warenausgang überhaupt erfasst ist. Sind erst drei Lieferscheine drin, ist
-- die Lücke riesig und sagt nichts über das Modell — nur über die Erfassung.
-- Deshalb steht die Deckung immer dabei.
-- =====================================================================

create or replace view v_saisonbilanz with (security_invoker = true) as
with eingang as (
  select sum(eingang_kg)          as kg,
         sum(lager_kg)            as im_lager_kg,
         sum(wartet_kg)           as wartet_kg
    from v_hochrechnung_basis
), verlust as (
  select sum(kg)                  as kg,
         sum(kg_unten)            as kg_unten,
         sum(kg_oben)             as kg_oben
    from v_verlust_ranking where buch = 'verlust'
), rest as (
  -- Was das Modell für den Lagerbestand als verkaufsfähig übrig lässt
  select sum(verkaufsfaehig_kg)   as kg
    from v_kaskade where portion = 'lager'
), ausgang as (
  select coalesce(sum(masse_kg), 0)                                as kg,
         coalesce(sum(masse_kg) filter (where buch = 'verkauf'), 0) as verkauf_kg,
         coalesce(sum(masse_kg) filter (where buch = 'marge'), 0)   as marge_kg,
         coalesce(sum(masse_kg) filter (where buch = 'verlust'), 0) as entsorgt_kg,
         coalesce(sum(masse_fehler_kg), 0)                          as fehler_kg,
         count(*)::int                                             as n_lieferungen
    from v_lieferung_masse
)
select e.kg                                                as eingang_kg,
       v.kg                                                as verlust_modell_kg,
       v.kg_unten                                          as verlust_unten_kg,
       v.kg_oben                                           as verlust_oben_kg,
       a.kg                                                as ausgang_kg,
       a.verkauf_kg, a.marge_kg, a.entsorgt_kg,
       a.fehler_kg                                         as ausgang_fehler_kg,
       a.n_lieferungen,
       r.kg                                                as restbestand_modell_kg,
       e.im_lager_kg, e.wartet_kg,
       -- Die Lücke: was weder als Verlust erklärt noch als Ausgang gebucht
       -- noch als Bestand übrig ist.
       (e.kg - v.kg - a.kg - r.kg)                         as luecke_kg,
       case when e.kg > 0 then (e.kg - v.kg - a.kg - r.kg) / e.kg end
                                                           as luecke_anteil,
       -- Wie viel der Ernte ist durch Lieferscheine gedeckt? Ohne das ist die
       -- Lücke keine Aussage über das Modell.
       case when e.kg > 0 then a.kg / e.kg end             as ausgang_deckung,
       case
         when a.n_lieferungen = 0
           then 'Kein Warenausgang erfasst — die Bilanz kann nichts prüfen. '
                || 'Der Restbestand ist eine Hochrechnung, kein Inventar.'
         when a.kg / nullif(e.kg, 0) < 0.2
           then 'Erst ein Bruchteil des Ausgangs ist erfasst — die Lücke sagt '
                || 'bislang mehr über die Erfassung als über das Modell.'
         when abs(e.kg - v.kg - a.kg - r.kg) / nullif(e.kg, 0) < 0.05
           then 'Die Bilanz geht auf: Eingang, Verlust, Ausgang und Bestand '
                || 'passen auf wenige Prozent zusammen.'
         when (e.kg - v.kg - a.kg - r.kg) > 0
           then 'Es fehlt Masse: mehr eingelagert, als sich durch Verlust, '
                || 'Ausgang und Bestand erklären lässt. Entweder ist ein '
                || 'Abgang nicht erfasst, oder ein Verlust wird unterschätzt.'
         else 'Es ist zu viel Masse da: mehr ausgeliefert und übrig, als je '
              || 'eingelagert wurde. Meist doppelt gezählte Paletten oder '
              || 'fehlende Tara im Wareneingang.'
       end                                                 as befund
  from eingang e cross join verlust v cross join rest r cross join ausgang a;

comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand. '
  'luecke_kg ist die einzige Grösse im System, die misst, was das Modell '
  'nicht sieht. Nur aussagekräftig, soweit der Ausgang erfasst ist — '
  'ausgang_deckung sagt, wie weit das ist.';

grant select on v_saisonbilanz to authenticated;
