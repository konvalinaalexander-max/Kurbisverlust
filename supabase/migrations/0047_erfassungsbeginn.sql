-- =====================================================================
-- 0047 — Erfassungsbeginn: was vor der App schon rausging
--
-- Der Betrieb (1. September): Die Saison lief bereits, als die App kam — ein
-- Teil der Ernte lag schon, ein Teil war schon ausgeliefert, ohne dass die App
-- es gesehen hat. Ohne diese Angabe behauptet die Massenbilanz eine Lücke, die
-- keine ist: Der Eingang zählt die ganze Charge, der Ausgang aber nur, was seit
-- dem Erfassungsbeginn erfasst wurde.
--
-- Deshalb:
--   * einstellung 'erfassungsbeginn' — ab wann die App mitzählt. Nur zur
--     Anzeige und als Erinnerung; die Bilanz rechnet mit der Zahl unten.
--   * charge_vorlauf — je Charge, wie viel Masse vor dem Erfassungsbeginn schon
--     ausgeliefert wurde. Eine grobe Angabe des Betriebsleiters, kein Messwert
--     aus der App; sie steht getrennt und wird als solche ausgewiesen.
--
-- Die Massenbilanz zählt diesen Vorlauf zum erfassten Ausgang. Damit misst die
-- Lücke wieder das Modell und die Erfassung, nicht den Umstand, dass die App
-- mitten in der Saison dazukam.
-- =====================================================================

insert into einstellung (schluessel, wert, bemerkung) values
  ('erfassungsbeginn', 'null'::jsonb,
   'Ab wann die App mitzählt (JJJJ-MM-TT). Vor diesem Tag ausgelieferte Masse '
   'steht je Charge in charge_vorlauf und geht als Ausgang in die Bilanz ein.')
on conflict (schluessel) do nothing;

create table if not exists charge_vorlauf (
  charge_nr           int primary key references charge(nr) on delete cascade,
  ausgang_vor_app_kg  numeric(14,2) not null check (ausgang_vor_app_kg >= 0),
  bemerkung           text,
  erfasser            uuid not null default auth.uid() references profil(id),
  ts                  timestamptz not null default now()
);
comment on table charge_vorlauf is
  'Grobe Angabe des Betriebsleiters: wie viel einer Charge vor dem '
  'Erfassungsbeginn schon ausgeliefert war. Kein Messwert der App — geht als '
  'bekannter Ausgang in die Bilanz, damit die Lücke nicht den späten Start '
  'der Erfassung als fehlende Masse ausweist.';

alter table charge_vorlauf enable row level security;
drop policy if exists vorlauf_lesen on charge_vorlauf;
drop policy if exists vorlauf_pflegen on charge_vorlauf;
create policy vorlauf_lesen on charge_vorlauf for select to authenticated using (true);
create policy vorlauf_pflegen on charge_vorlauf for all to authenticated
  using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on charge_vorlauf to authenticated;

drop trigger if exists charge_vorlauf_veraltet on charge_vorlauf;
create trigger charge_vorlauf_veraltet after insert or update or delete on charge_vorlauf
  for each statement execute function auswertung_veraltet();

-- Die Bilanz zählt den Vorlauf zum erfassten Ausgang. Die Spaltenliste
-- ändert sich (vorlauf_kg kommt dazu), darum neu bauen statt ersetzen.
drop view if exists v_saisonbilanz cascade;
create view v_saisonbilanz with (security_invoker = true) as
with eingang as (
  select sum(eingang_kg) as kg, sum(lager_kg) as im_lager_kg, sum(wartet_kg) as wartet_kg
    from v_hochrechnung_basis
), verlust as (
  select sum(kg) as kg, sum(kg_unten) as kg_unten, sum(kg_oben) as kg_oben,
         sum(kg) filter (where buch = 'verlust') as lager_kg,
         sum(kg) filter (where buch = 'feld')    as feld_kg,
         bool_and(kg is not null) filter (where buch = 'verlust') as bekannt
    from v_verlust_ranking where buch in ('verlust', 'feld')
), rest as (
  select sum(m2) as kg from v_kaskade where portion = 'lager'
), vorlauf as (
  select coalesce(sum(ausgang_vor_app_kg), 0) as kg from charge_vorlauf
), ausgang as (
  select coalesce(sum(masse_kg), 0)                                as kg,
         coalesce(sum(masse_kg) filter (where buch = 'verkauf'), 0) as verkauf_kg,
         coalesce(sum(masse_kg) filter (where buch = 'marge'), 0)   as marge_kg,
         coalesce(sum(masse_kg) filter (where buch = 'verlust'), 0) as entsorgt_kg,
         coalesce(sum(masse_fehler_kg), 0)                          as fehler_kg,
         count(*)::int                                             as n_lieferungen
    from v_lieferung_masse
)
select e.kg::numeric(14,2)                                 as eingang_kg,
       v.kg::numeric(14,2)                                 as verlust_modell_kg,
       v.kg_unten::numeric(14,2)                           as verlust_unten_kg,
       v.kg_oben::numeric(14,2)                            as verlust_oben_kg,
       (a.kg + vl.kg)::numeric(14,2)                       as ausgang_kg,
       a.verkauf_kg::numeric(14,2) as verkauf_kg, a.marge_kg::numeric(14,2) as marge_kg,
       a.entsorgt_kg::numeric(14,2) as entsorgt_kg,
       a.fehler_kg::numeric(14,2)                          as ausgang_fehler_kg,
       a.n_lieferungen,
       vl.kg::numeric(14,2)                                as vorlauf_kg,
       r.kg::numeric(14,2)                                 as restbestand_modell_kg,
       e.im_lager_kg::numeric(14,2) as im_lager_kg, e.wartet_kg::numeric(14,2) as wartet_kg,
       (e.kg - v.kg - a.kg - vl.kg - r.kg)::numeric(14,2)  as luecke_kg,
       (case when e.kg > 0 then (e.kg - v.kg - a.kg - vl.kg - r.kg) / e.kg end)::numeric(10,4)
                                                           as luecke_anteil,
       (case when e.kg > 0 then (a.kg + vl.kg) / e.kg end)::numeric(10,4) as ausgang_deckung,
       case
         when not coalesce(v.bekannt, false)
           then 'Ein Verluststrom ist noch nicht gemessen — die Bilanz kann erst '
                || 'schliessen, wenn jeder Koeffizient mindestens eine Messung hat.'
         when a.n_lieferungen = 0 and vl.kg = 0
           then 'Kein Warenausgang erfasst — die Bilanz kann nichts prüfen. '
                || 'Der Restbestand ist eine Hochrechnung, kein Inventar.'
         when (a.kg + vl.kg) / nullif(e.kg, 0) < 0.2
           then 'Erst ein Bruchteil des Ausgangs ist erfasst — die Lücke sagt '
                || 'bislang mehr über die Erfassung als über das Modell.'
         when abs(e.kg - v.kg - a.kg - vl.kg - r.kg) / nullif(e.kg, 0) < 0.05
           then 'Die Bilanz geht auf: Eingang, Verlust, Ausgang und Bestand '
                || 'passen auf wenige Prozent zusammen.'
         when (e.kg - v.kg - a.kg - vl.kg - r.kg) > 0
           then 'Es fehlt Masse: mehr eingelagert, als sich durch Verlust, '
                || 'Ausgang und Bestand erklären lässt. Entweder ist ein '
                || 'Abgang nicht erfasst, oder ein Verlust wird unterschätzt.'
         else 'Es ist zu viel Masse da: mehr ausgeliefert und übrig, als je '
              || 'eingelagert wurde. Meist doppelt gezählte Paletten oder '
              || 'fehlende Tara im Wareneingang.'
       end                                                 as befund,
       v.lager_kg::numeric(14,2)                           as lagerverlust_kg,
       v.feld_kg::numeric(14,2)                            as feld_kg
  from eingang e cross join verlust v cross join rest r
       cross join ausgang a cross join vorlauf vl;

comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand. Der '
  'Ausgang enthält den vor dem Erfassungsbeginn ausgelieferten Vorlauf '
  '(charge_vorlauf), damit die Lücke nicht den späten Start der App misst.';
grant select on v_saisonbilanz to authenticated;
