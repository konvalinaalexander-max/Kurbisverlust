-- =====================================================================
-- 0033 — Welche Charge sollte als nächstes verarbeitet werden?
--
-- Die Frage stellt sich der Betriebsleiter jede Woche, und die Daten geben
-- sie her: Für jede Charge mit Bestand lässt sich beziffern, was zwei
-- weitere Wochen Liegenlassen voraussichtlich kosten — Verdunstung nach der
-- Sortenrate, Verderb nach dem angepassten Verlaufsmodell. Die Reihenfolge
-- dieser Zahlen ist die Antwort.
--
-- Zwei Ehrlichkeiten gehören dazu:
--
-- * Der Verderbszuwachs ist bedingt gerechnet — auf die Ware, die bis heute
--   durchgehalten hat: (F(t+14) − F(t)) / (1 − F(t)). Ohne die Bedingung
--   würde bereits verdorbene Masse ein zweites Mal verderben.
-- * Wo das Alter der Charge jenseits der längsten gemessenen Lagerdauer
--   liegt, ist die Zahl hochgerechnet, nicht gemessen — die Spalte
--   hochgerechnet sagt es, und das Dashboard zeigt es an.
--
-- Das Verlaufsmodell wird einmal je Abfrage gerechnet (materialisierte CTE),
-- nicht einmal je Charge — sonst stünden hier 40 Regressionen je Aufruf.
-- =====================================================================

create or replace view v_naechste_charge with (security_invoker = true) as
with modell as materialized (
  select * from v_schimmel_modell
),
bestand as (
  select b.charge_nr, b.sorte, b.schlag, b.lager_kg,
         -- Nie negativ: eine Demo- oder Testsaison kann in der Zukunft
         -- liegen, und ein negatives Alter ergäbe negative Verluste.
         greatest(b.alter_lager_heute, 0)                      as alter_tage,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05)      as r
    from v_hochrechnung_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
   where b.lager_kg > 0
),
mit_f as (
  select b.*,
         -- Masse heute: Eingang der liegenden Ware, um die Verdunstung bis
         -- heute vermindert.
         b.lager_kg * power(1 - b.r, greatest(b.alter_tage, 0)) as masse_jetzt_kg,
         case when m.brauchbar then least(greatest(
           1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage, 1))
           , -40), 3))), 0), 0.99) end                          as f_jetzt,
         case when m.brauchbar then least(greatest(
           1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage + 14, 1))
           , -40), 3))), 0), 0.99) end                          as f_dann,
         (m.brauchbar and b.alter_tage > m.t_max)               as hochgerechnet,
         m.brauchbar                                            as modell_gilt
    from bestand b cross join modell m
)
select charge_nr, sorte, schlag,
       lager_kg::numeric(14,2),
       round(alter_tage)::int                                   as alter_tage,
       masse_jetzt_kg::numeric(14,2),
       (masse_jetzt_kg * (1 - power(1 - r, 14)))::numeric(12,1) as verdunstung_14_kg,
       (case when modell_gilt
             then masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0)
             else null end)::numeric(12,1)                      as schimmel_14_kg,
       (masse_jetzt_kg * (1 - power(1 - r, 14))
        + coalesce(masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0), 0)
       )::numeric(12,1)                                         as verlust_14_kg,
       hochgerechnet, modell_gilt
  from mit_f
 order by verlust_14_kg desc nulls last;

comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Die '
  'Reihenfolge beantwortet, was als nächstes verarbeitet gehört. '
  'schimmel_14_kg ist NULL, solange das Verlaufsmodell nicht trägt — dann '
  'steht die Antwort nur auf der Verdunstung.';

grant select on v_naechste_charge to authenticated;
