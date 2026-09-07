-- =====================================================================
-- 0057 — Die Datenbank sagt, auf welchem Stand sie ist
-- Kürbis-Verlust-Tracking
--
-- WOZU DAS DA IST
--
-- Nach 0056 stand der Überblick auf dem Hof weiter mit „numeric field
-- overflow" — obwohl die Korrektur gebaut, geprüft und gepusht war. Die App
-- kann nicht sehen, ob die Datenbank sie schon hat: Sie ruft Sichten, und
-- die antworten mit den Formeln, die *dort* stehen. Ein Betriebsleiter sieht
-- eine rohe Fehlermeldung und kann nicht wissen, dass der Weg heraus drei
-- Handgriffe lang ist (README, Schritt 3: setup.sql noch einmal einfügen).
--
-- Deshalb trägt die Datenbank ab jetzt ihren Stand: schema_stand() nennt
-- die Nummer der jüngsten Migration. Die App vergleicht sie beim Laden der
-- Auswertung mit der Nummer, die sie selbst erwartet (src/lib/version.ts),
-- und sagt im Klartext „Datenbank auf älterem Stand — setup.sql ausführen",
-- statt an alten Formeln zu scheitern. Fehlt die Funktion ganz, ist die
-- Datenbank älter als 0057 — dieselbe Meldung.
--
-- REGEL FÜR JEDE WEITERE MIGRATION: schema_stand() auf die eigene Nummer
-- setzen und SCHEMA_ERWARTET in src/lib/version.ts nachziehen. run.sh
-- (Stufe 1) bricht ab, wenn die höchste Migrationsnummer und schema_stand()
-- auseinanderliegen; npm test prüft die Frontend-Seite.
--
-- Dazu, klein: v_ausschuss_beobachtung rechnet die Basis der Hand-Messung
-- mit derselben gedeckelten Rate und Lagertagen ≥ 0 wie 0056 — die letzte
-- Sicht, die (1 − Rate)^Lagertage noch roh ausrechnete.
-- =====================================================================

create or replace function schema_stand() returns int
language sql immutable parallel safe
as $$ select 57 $$;
comment on function schema_stand is
  'Nummer der jüngsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET (src/lib/version.ts) und verlangt bei Abweichung, setup.sql '
  'erneut auszuführen. Jede Migration setzt sie auf ihre eigene Nummer.';
revoke all on function schema_stand() from public;
grant execute on function schema_stand() to anon, authenticated;

-- ---------- v_ausschuss_beobachtung: Basis gedeckelt wie in 0056 ----------
create or replace view v_ausschuss_beobachtung with (security_invoker = true) as
select 'maschine'::verarbeitungsweg as weg, lm.charge_nr, lm.sorte, lm.auftrag_id,
       lm.masse_kg                                  as basis_kg,
       lm.masse_klein_kg                            as klein_kg,
       lm.masse_nebenkanal_kg                       as gross_kg,
       true                                         as plausibel
  from v_sortier_lauf_masse lm
 where lm.masse_kg > 0
union all
select 'hand'::verarbeitungsweg, am.charge_nr, am.sorte, am.auftrag_id,
       n.basis, h.klein_kg, h.gross_kg,
       anteil_plausibel((h.klein_kg  / nullif(n.basis, 0))::numeric)
         and anteil_plausibel((coalesce(h.gross_kg, 0) / nullif(n.basis, 0))::numeric)
  from v_auftrag_masse am
  join (select auftrag_id,
               sum(kg) filter (where art = 'zu_klein')::numeric as klein_kg,
               sum(kg) filter (where art = 'zu_gross')::numeric as gross_kg
          from ausschuss_messung where gemessen group by auftrag_id) h
       on h.auftrag_id = am.auftrag_id
  left join v_schimmel_menge sm on sm.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
  cross join lateral (
        -- 0057: dieselbe Deckelung wie Kaskade, Bestand und Schimmelbasis
        -- (0 … 5 % je Tag, Lagertage ≥ 0); die Basis ist höchstens der Eingang.
        select greatest(am.eingang_netto_kg
                          * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05),
                                  greatest(am.lagertage, 0))
                        - coalesce(sm.kg, 0), 0)::numeric(12,2) as basis
       ) n
 where am.weg = 'hand' and am.eingang_netto_kg is not null and am.lagertage is not null;
comment on view v_ausschuss_beobachtung is
  'Zu klein und zu gross je Arbeit gegen ihre Basis: am Band die CSV-Masse, von '
  'Hand der Eingang abzüglich Verdunstung (gedeckelte Rate, 0057) und Schimmel.';
grant select on v_ausschuss_beobachtung to authenticated;
