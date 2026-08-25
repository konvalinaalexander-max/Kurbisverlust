-- =====================================================================
-- 0021 — Zwei stille Verzerrungen der Eingangsmasse
--
-- ---------- 1. Fehlende Tara macht die Charge kleiner ---------------------
-- v_palette rechnet netto = brutto − Kisten·Tara − Palettentara. Fehlt die
-- Gebindeart, ist die Tara NULL, also auch netto — und sum() überspringt NULL
-- stillschweigend. Die Charge wird dadurch leichter, als sie ist, und jeder
-- Verlust in Prozent der Charge entsprechend grösser.
--
-- Nachgemessen an einer Charge mit 44 Paletten, bei der 4 keine Gebindeart
-- haben (9 % der Paletten):
--
--   so gerechnet    34 494 kg
--   hochgerechnet   37 943 kg
--   Fehlbetrag        10.0 %
--
-- Zehn Prozent auf der Bezugsgrösse verschieben jede Verlustquote um zehn
-- Prozent — mehr, als die meisten Unterschiede, die hier rangiert werden
-- sollen. In der Oberfläche wurde bisher gewarnt, die Zahl selbst blieb falsch.
--
-- Behoben durch Hochrechnung innerhalb der Charge: Paletten ohne bekannte
-- Tara bekommen das mittlere Nettogewicht der übrigen Paletten derselben
-- Charge. Sie stehen im selben Lager und stammen von derselben Ernte; das ist
-- die naheliegendste Annahme, die man treffen kann — und allemal besser als
-- so zu tun, als gäbe es sie nicht.
--
-- ---------- 2. Mehr ausgelagert als eingelagert --------------------------
-- lager_kg = greatest(eingang − ausgelagert, 0). Übersteigt die ausgelagerte
-- Masse die eingelagerte — weil eine Charge mehrfach über das Band lief und
-- Paletten doppelt gezählt wurden, oder weil oben Tara fehlte —, wird der
-- Rest still auf 0 gesetzt und niemand erfährt davon. Der Betrag, um den
-- gekappt wurde, wird jetzt mitgeführt: er ist die einzige Spur, die eine
-- Doppelzählung im System hinterlässt.
-- =====================================================================

create or replace view v_charge_rueckgrat with (security_invoker = true) as
select c.nr as charge_nr, c.schlag, c.sorte, c.saison,
       count(p.id)                                     as n_paletten,
       count(p.netto_kg)                               as n_paletten_mit_netto,
       -- Auf alle Paletten der Charge hochgerechnet, nicht nur auf die mit
       -- bekannter Tara. Sind alle bekannt, ändert sich nichts.
       (sum(p.netto_kg) / nullif(count(p.netto_kg), 0) * count(p.id))
                                                       as eingang_netto_kg,
       sum(p.brutto_kg)                                as eingang_brutto_kg,
       min(p.eingangsdatum)                            as erster_eingang,
       max(p.eingangsdatum)                            as letzter_eingang,
       '2000-01-01'::date + (sum((p.eingangsdatum - '2000-01-01'::date)::numeric
              * coalesce(p.netto_kg, 1)) / nullif(sum(coalesce(p.netto_kg, 1)), 0))::int
                                                       as eingangsdatum_mittel,
       sum(p.netto_kg)                                 as eingang_netto_gemessen_kg
  from charge c
  left join v_palette p on p.charge_nr = c.nr
 group by c.nr, c.schlag, c.sorte, c.saison;

comment on view v_charge_rueckgrat is
  'eingang_netto_kg ist auf alle Paletten der Charge hochgerechnet; '
  'eingang_netto_gemessen_kg ist die Summe der Paletten mit bekannter Tara. '
  'Weichen die beiden ab, fehlt bei n_paletten − n_paletten_mit_netto '
  'Paletten die Gebindeart.';

create or replace view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung
                    where schluessel = 'saison_ende'), current_date) as bis
), ausgang as (
  select charge_nr,
         sum(eingang_netto_kg) as kg,
         sum(eingang_netto_kg * lagertage) / nullif(sum(eingang_netto_kg), 0) as lagertage,
         sum(eingang_netto_kg) filter (where weg = 'hand') as kg_hand
    from v_auftrag_masse
   where station in ('sortieren', 'waschen_sortieren') and eingang_netto_kg is not null
   group by charge_nr
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       coalesce(a.kg, 0)                                            as ausgelagert_kg,
       a.lagertage                                                  as alter_ausgelagert,
       greatest(r.eingang_netto_kg - coalesce(a.kg, 0), 0)          as lager_kg,
       (s.bis - r.eingangsdatum_mittel)::numeric                    as alter_lager,
       (current_date - r.eingangsdatum_mittel)::numeric             as alter_lager_heute,
       coalesce(a.kg_hand / nullif(a.kg, 0), 0)                     as weg2_anteil,
       s.bis                                                        as stichtag,
       r.n_paletten_mit_netto,
       -- Wie viel musste weggekappt werden, damit der Lagerbestand nicht
       -- negativ wird? Grösser als 0 heisst: es wurde mehr ausgelagert als je
       -- eingelagert — Paletten doppelt gezählt oder Tara fehlt.
       greatest(coalesce(a.kg, 0) - r.eingang_netto_kg, 0)          as ueberzaehlung_kg
  from v_charge_rueckgrat r
  cross join stichtag s
  left join ausgang a on a.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

comment on view v_hochrechnung_basis is
  'ueberzaehlung_kg > 0 heisst: es wurde mehr Masse ausgelagert als je '
  'eingelagert. Der Lagerbestand wird dann auf 0 gekappt — die Zahl hier ist '
  'die einzige Spur, die eine Doppelzählung hinterlässt.';

grant select on v_charge_rueckgrat, v_hochrechnung_basis to authenticated;
