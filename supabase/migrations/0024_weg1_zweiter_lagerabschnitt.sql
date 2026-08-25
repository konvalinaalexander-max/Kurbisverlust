-- =====================================================================
-- 0024 — Weg 1 hat zwei Lagerabschnitte, das Modell kannte nur einen
--
-- Spec §3 beschreibt Weg 1 als: Lager → Sortieren → **Lager** → Waschen →
-- Warenausgang. Zwischen Sortieren und Waschen liegen Wochen bis Monate, und
-- die Ware liegt in dieser Zeit in Kaliber-Kisten wieder in derselben Halle.
-- Der Betrieb bestätigt: **alles**, was sortiert wurde, wird später gewaschen.
--
-- Das Modell kannte diesen zweiten Abschnitt nicht. Zwei Folgen, beide belegt.
--
-- ---------- 1. Schimmel #2 verschwand spurlos ----------------------------
-- Beim Waschen wird nochmals Faules aussortiert — Spec §3 nennt das
-- ausdrücklich „Schimmel #2, zeitaufgelöst". Der Arbeiter trägt es ein, die
-- Datenbank speichert es, und das Modell hat es weggeworfen:
--
--   Wasch-Auftrag mit 900 kg Schimmel  →  0 Zeilen in v_schimmel_punkte
--
-- Der Grund: v_schimmel_beobachtung verlangt eine Lagerdauer, und die kam aus
-- den gezählten Paletten. Beim Waschen gibt es keine zu zählen — die
-- Original-Paletten haben sich beim Sortieren in Kaliber-Kisten aufgelöst.
-- Also blieb lagertage NULL und die Messung fiel heraus.
--
-- Behoben: Ein Wasch-Auftrag erbt die Lagerdauer aus dem, was beim Sortieren
-- derselben Charge gezählt wurde — massegewichtet über die Eingangsdaten.
-- Damit steht Schimmel #2 dort in der Kurve, wo er hingehört: bei einer
-- deutlich längeren Lagerdauer als Schimmel #1. Genau diese Punkte fehlten
-- dem Verderbsmodell am rechten Rand.
--
-- ---------- 2. Sortierte Ware galt als aus dem Haus -----------------------
-- ausgelagert_kg zählte Sortieren und Waschen+Sortieren. Sortierte Ware war
-- damit „raus", obwohl sie physisch in derselben Halle steht und weiter
-- verdunstet und verdirbt. Ihr Alter blieb beim Sortiertag stehen.
--
-- Jetzt gilt: Aus dem Lager ist, was den *letzten* Schritt hinter sich hat —
-- Weg 2 nach Waschen+Sortieren, Weg 1 erst nach dem Waschen. Was sortiert
-- ist und auf das Waschen wartet, zählt weiter zum Bestand und altert weiter.
--
-- Der zweite Abschnitt wird dabei nicht als eigene Kaskadenstufe gerechnet,
-- sondern über das Alter: Verdunstung und Schimmel sind kumulativ, es genügt
-- also, das *Endalter* einzusetzen statt des Sortieralters. Der Ausschuss
-- wurde beim Sortieren entnommen und wird hier auf die etwas kleinere Masse
-- am Ende bezogen — ein Fehler in der Grössenordnung 0.1 % des Stroms, gegen
-- den es sich nicht lohnt, eine zweite Stufe zu bauen.
-- =====================================================================

-- ---------- Lagerdauer auch ohne gezählte Paletten ------------------------
create or replace view v_auftrag_masse with (security_invoker = true) as
with sortier_eingang as (
  -- Wann kam die Ware herein, die diese Charge beim Sortieren durchlaufen hat?
  -- Massegewichtet, in Tagen seit einer festen Epoche (Datumsarithmetik lässt
  -- sich nicht mitteln).
  select a.charge_nr,
         sum((m.eingangsdatum - date '2000-01-01')::numeric * m.netto_kg)
           / nullif(sum(m.netto_kg), 0)                        as tage_seit_epoche
    from auftrag a
    join v_auftrag_palette_masse m on m.auftrag_id = a.id
   where a.station = 'sortieren' and a.abgebrochen_ts is null
   group by a.charge_nr
), charge_eingang as (
  -- Rückfall, falls zur Charge kein Sortier-Auftrag erfasst ist
  select charge_nr, (eingangsdatum_mittel - date '2000-01-01')::numeric as tage_seit_epoche
    from v_charge_rueckgrat
)
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten, m.eingang_netto_kg,
       m.masse_quelle,
       (coalesce(
         m.lagertage,
         -- Beim Waschen auf Weg 1 gibt es nichts zu zählen. Die Lagerdauer
         -- ist trotzdem bekannt: sie läuft ab dem Wareneingang, nicht ab dem
         -- Sortiertag. Ohne das fiel Schimmel #2 aus dem Modell.
         case when m.station = 'waschen'
              then ((m.start_ts::date - date '2000-01-01')::numeric
                    - coalesce(se.tage_seit_epoche, ce.tage_seit_epoche))
         end
       ))::numeric(10,1)                                       as lagertage
  from mv_auftrag_masse m
  left join sortier_eingang se on se.charge_nr = m.charge_nr
  left join charge_eingang  ce on ce.charge_nr = m.charge_nr;

comment on view v_auftrag_masse is
  'Masse und Lagerdauer je Arbeit. Wasch-Aufträge auf Weg 1 zählen keine '
  'Paletten — ihre Lagerdauer wird aus dem Wareneingang der sortierten Ware '
  'abgeleitet, sonst fiele Schimmel #2 aus der Auswertung.';

-- ---------- Aus dem Lager ist, was den letzten Schritt hinter sich hat ----
create or replace view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung
                    where schluessel = 'saison_ende'), current_date) as bis
), je_station as (
  select charge_nr,
         sum(eingang_netto_kg) filter (where station = 'sortieren')          as sortiert_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen')            as gewaschen_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren')  as hand_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren'
                                         and weg = 'hand')                   as kg_hand,
         -- Endverarbeitungsalter: massegewichtet über die Schritte, nach denen
         -- die Ware wirklich draussen ist.
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('waschen', 'waschen_sortieren') and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('waschen', 'waschen_sortieren') and lagertage is not null), 0)
                                                                             as alter_ende,
         -- Rückfall, solange noch nichts gewaschen ist
         sum(eingang_netto_kg * lagertage) filter (where lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (where lagertage is not null), 0)
                                                                             as alter_irgendwas
    from v_auftrag_masse
   where eingang_netto_kg is not null
   group by charge_nr
), anteil as (
  select s.*,
         -- Welcher Teil der sortierten Ware ist schon gewaschen? gewaschen_kg
         -- ist beim Waschen gemessen, also nach den Verlusten des ersten
         -- Abschnitts — der Anteil fällt dadurch etwas zu klein aus und die
         -- wartende Menge etwas zu gross. Das liegt auf der vorsichtigen Seite.
         least(coalesce(s.gewaschen_kg, 0) / nullif(s.sortiert_kg, 0), 1)     as anteil_gewaschen
    from je_station s
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       -- Draussen ist: Weg 2 komplett, Weg 1 nur der gewaschene Teil.
       (coalesce(a.hand_kg, 0)
        + coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0))       as ausgelagert_kg,
       coalesce(a.alter_ende, a.alter_irgendwas)                              as alter_ausgelagert,
       -- Im Haus ist: was nie angefasst wurde, plus was sortiert ist und auf
       -- das Waschen wartet. Beides altert bis zum Stichtag weiter, beides
       -- rechnet die Kaskade mit demselben Alter — deshalb eine Portion.
       greatest(r.eingang_netto_kg
                - coalesce(a.hand_kg, 0)
                - coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0), 0)
                                                                              as lager_kg,
       (s.bis - r.eingangsdatum_mittel)::numeric                              as alter_lager,
       (current_date - r.eingangsdatum_mittel)::numeric                       as alter_lager_heute,
       coalesce(a.kg_hand / nullif(coalesce(a.hand_kg, 0)
                                   + coalesce(a.sortiert_kg, 0), 0), 0)       as weg2_anteil,
       s.bis                                                                  as stichtag,
       r.n_paletten_mit_netto,
       greatest(coalesce(a.hand_kg, 0) + coalesce(a.sortiert_kg, 0)
                - r.eingang_netto_kg, 0)                                      as ueberzaehlung_kg,
       coalesce(a.sortiert_kg, 0)                                             as sortiert_kg,
       coalesce(a.gewaschen_kg, 0)                                            as gewaschen_kg,
       -- Sortiert, aber noch nicht gewaschen: steht in Kaliber-Kisten in der
       -- Halle. Für den Betriebsleiter die Menge, die als nächstes ans
       -- Waschbecken muss.
       (coalesce(a.sortiert_kg, 0) * (1 - coalesce(a.anteil_gewaschen, 0)))    as wartet_kg,
       coalesce(a.anteil_gewaschen, 0)                                        as anteil_gewaschen
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
 where r.eingang_netto_kg is not null;

comment on view v_hochrechnung_basis is
  'ausgelagert_kg ist die Masse, die den letzten Verarbeitungsschritt hinter '
  'sich hat — auf Weg 1 also erst nach dem Waschen. wartet_kg steht sortiert '
  'in Kaliber-Kisten und altert weiter. ueberzaehlung_kg > 0 heisst: mehr '
  'ausgelagert als je eingelagert, also Paletten doppelt gezählt.';

grant select on v_auftrag_masse, v_hochrechnung_basis to authenticated;
