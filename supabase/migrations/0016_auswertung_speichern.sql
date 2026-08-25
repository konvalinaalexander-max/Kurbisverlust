-- =====================================================================
-- 0016 — Die Auswertung einmal rechnen, nicht bei jedem Hinschauen
--
-- Das Feilen an einzelnen Abfragen (0015) hat das Symptom verschoben, nicht
-- die Ursache beseitigt. Gemessen an einem Lasttest mit 5 040 Paletten,
-- 840 Arbeiten und 255 300 Gewichtsstufen — rund dem Dreifachen einer echten
-- Saison — brauchten die zwölf Dashboard-Ansichten zusammen 4.1 Sekunden.
-- Auf Supabases geteilter CPU wäre das ein Abbruch, und mit jeder weiteren
-- Palette würde es schlimmer.
--
-- Der Grund ist die Bauart: Die Auswertung ist ein tiefer Baum, der bei jedem
-- Lesen von den Rohdaten aufwärts komplett neu gerechnet wird. v_kaskade
-- allein steckt in drei Dashboard-Ansichten und wurde dreimal gerechnet.
--
-- Eine Saisonauswertung ist aber keine Live-Anzeige. Sie darf ein paar Minuten
-- alt sein. Deshalb werden die drei teuren Knoten jetzt als materialisierte
-- Ansichten gespeichert und auf Knopfdruck neu berechnet:
--
--   mv_sortier_lauf_masse   verdichtet 255 000 Gewichtsstufen auf 300 Zeilen
--   mv_auftrag_masse        verdichtet die Palettenzählungen auf 840 Zeilen
--   mv_kaskade              die eigentliche Hochrechnung
--
-- Die gewohnten Namen (v_…) bleiben und zeigen jetzt auf die gespeicherten
-- Daten. Damit gibt es weiterhin genau eine Wahrheit: App, SQL-Editor und
-- Prüfabfragen sehen dasselbe.
--
-- Nebenwirkung, die man kennen muss: Nach einer Erfassung ist die Auswertung
-- erst nach dem nächsten Berechnen aktuell. Die App zeigt den Stand an und
-- meldet, wenn seither etwas erfasst wurde.
-- =====================================================================

-- ---------- Stand der Auswertung -----------------------------------------
create table if not exists auswertung_stand (
  id            int primary key default 1 check (id = 1),
  berechnet_ts  timestamptz,
  dauer_ms      int,
  geaendert_ts  timestamptz not null default now()
);
insert into auswertung_stand (id) values (1) on conflict (id) do nothing;

alter table auswertung_stand enable row level security;
drop policy if exists stand_lesen on auswertung_stand;
create policy stand_lesen on auswertung_stand for select to authenticated using (true);
grant select on auswertung_stand to authenticated;

comment on table auswertung_stand is
  'Wann wurde die Auswertung zuletzt gerechnet, und hat sich seither etwas '
  'geändert? geaendert_ts setzen die Erfassungstabellen selbst.';

-- Jede Erfassung meldet, dass die Auswertung veraltet ist. Auf Anweisungsebene
-- statt je Zeile: Ein Import mit 500 Paletten löst so einen Aufruf aus, nicht 500.
create or replace function auswertung_veraltet()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update auswertung_stand set geaendert_ts = now() where id = 1;
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['palette', 'auftrag', 'auftrag_palette', 'schimmel_messung',
                           'ausschuss_messung', 'verdunstung_wiegung', 'marge_messung',
                           'ausgang_wiegung', 'sortier_lauf', 'sortier_gewicht',
                           'gebinde', 'sorte_kaliber', 'einstellung'] loop
    execute format('drop trigger if exists %I on %I', t || '_veraltet', t);
    execute format('create trigger %I after insert or update or delete on %I '
                   'for each statement execute function auswertung_veraltet()',
                   t || '_veraltet', t);
  end loop;
end $$;

-- ---------- 1. Sortierläufe: 255 000 Zeilen → 300 -------------------------
-- Kein "drop cascade": Der Wrapper hat exakt dieselben Spalten und Typen wie
-- vorher, also genügt ein Ersetzen — die ganze Auswertung darüber bleibt stehen.
create materialized view if not exists mv_sortier_lauf_masse as
select l.id as lauf_id, l.charge_nr, c.sorte, c.schlag, l.auftrag_id,
       l.datei_name, l.datei_zeit, l.zuordnung,
       sum(g.anzahl)                                                    as n_kuerbis,
       (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2)    as masse_kg,
       sum(g.anzahl) filter (where g.klasse = 'verlust_klein')          as n_klein,
       (sum(g.anzahl::bigint * g.gewicht_g) filter (where g.klasse = 'verlust_klein')
        / 1000.0)::numeric(12,2)                                        as masse_klein_kg,
       sum(g.anzahl) filter (where g.klasse = 'nebenkanal')             as n_nebenkanal,
       (sum(g.anzahl::bigint * g.gewicht_g) filter (where g.klasse = 'nebenkanal')
        / 1000.0)::numeric(12,2)                                        as masse_nebenkanal_kg,
       sum(g.anzahl) filter (where g.klasse = 'kaliber')                as n_kaliber,
       (sum(g.anzahl::bigint * g.gewicht_g) filter (where g.klasse = 'kaliber')
        / 1000.0)::numeric(12,2)                                        as masse_kaliber_kg
  from sortier_lauf l
  join charge c on c.nr = l.charge_nr
  join sortier_gewicht g on g.lauf_id = l.id
 group by l.id, l.charge_nr, c.sorte, c.schlag, l.auftrag_id, l.datei_name,
          l.datei_zeit, l.zuordnung;

create unique index if not exists mv_sortier_lauf_masse_pk on mv_sortier_lauf_masse (lauf_id);
create index if not exists mv_sortier_lauf_masse_charge on mv_sortier_lauf_masse (charge_nr);

create or replace view v_sortier_lauf_masse with (security_invoker = true) as
select * from mv_sortier_lauf_masse;

-- ---------- 2. Masse je Arbeit --------------------------------------------
create materialized view if not exists mv_auftrag_masse as
select a.id as auftrag_id, a.charge_nr, c.sorte, c.schlag, a.weg, a.station,
       a.start_ts, a.ende_ts, a.status,
       count(m.id)                                     as n_paletten,
       coalesce(sum(m.netto_kg), a.durchsatz_kg)        as eingang_netto_kg,
       case when sum(m.netto_kg) is not null then 'paletten'
            when a.durchsatz_kg  is not null then 'durchsatz'
            else 'fehlt' end                            as masse_quelle,
       (sum((a.start_ts::date - m.eingangsdatum) * m.netto_kg)
        / nullif(sum(m.netto_kg), 0))::numeric(10,1)    as lagertage
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_auftrag_palette_masse m on m.auftrag_id = a.id
 where a.abgebrochen_ts is null
 group by a.id, a.charge_nr, c.sorte, c.schlag, a.weg, a.station,
          a.start_ts, a.ende_ts, a.status, a.durchsatz_kg;

create unique index if not exists mv_auftrag_masse_pk on mv_auftrag_masse (auftrag_id);
create index if not exists mv_auftrag_masse_charge on mv_auftrag_masse (charge_nr);
create index if not exists mv_auftrag_masse_station on mv_auftrag_masse (station) where eingang_netto_kg is not null;

create or replace view v_auftrag_masse with (security_invoker = true) as
select * from mv_auftrag_masse;

-- ---------- 3. Die Hochrechnung selbst ------------------------------------
-- Derselbe Rumpf wie bisher in v_kaskade — nur liest er jetzt die beiden
-- gespeicherten Ansichten von oben und wird selbst gespeichert. v_kaskade
-- steckte in drei Dashboard-Ansichten und wurde dabei dreimal gerechnet.
create materialized view if not exists mv_kaskade as
with sz(szenario) as (values ('unten'), ('mittel'), ('oben')),
kurve as materialized (
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
         least(greatest(coalesce(
           case k.szenario when 'unten' then coalesce(s.unten, s.anteil_mono)
                           when 'oben'  then coalesce(s.oben,  s.anteil_mono)
                           else s.anteil_mono end, 0), 0), 1)          as f,
         s.n                                                           as f_n
    from koeff_norm k
    cross join lateral (values
        ('ausgelagert', k.ausgelagert_kg, coalesce(k.alter_ausgelagert, 0)),
        ('lager',       k.lager_kg,       greatest(k.alter_lager, 0))
      ) as t(portion, m0, alter_tage)
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

-- ---------- 4. Kaliber-Verteilung -----------------------------------------
-- Scannt ebenfalls alle Gewichtsstufen und wächst mit jeder eingelesenen CSV.
create materialized view if not exists mv_kaliber_verteilung as
select l.charge_nr, c.sorte, g.klasse, g.kaliber_idx,
       (s.kaliber_baender -> g.kaliber_idx ->> 0)::int as band_von,
       (s.kaliber_baender -> g.kaliber_idx ->> 1)::int as band_bis,
       sum(g.anzahl)                                                 as n_kuerbis,
       (sum(g.anzahl::bigint * g.gewicht_g) / 1000.0)::numeric(12,2) as masse_kg
  from sortier_gewicht g
  join sortier_lauf l on l.id = g.lauf_id
  join charge c on c.nr = l.charge_nr
  join sorte_kaliber s on s.sorte = c.sorte
 group by l.charge_nr, c.sorte, g.klasse, g.kaliber_idx, s.kaliber_baender;

create unique index if not exists mv_kaliber_pk
  on mv_kaliber_verteilung (charge_nr, klasse, coalesce(kaliber_idx, -1));

create or replace view v_kaliber_verteilung with (security_invoker = true) as
select * from mv_kaliber_verteilung;

-- ---------- Neu berechnen -------------------------------------------------
-- Reihenfolge zählt: mv_kaskade liest die beiden anderen. Würde sie zuerst
-- erneuert, rechnete sie mit den alten Zahlen.
create or replace function auswertung_aktualisieren()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v_start timestamptz := clock_timestamp();
begin
  refresh materialized view mv_sortier_lauf_masse;
  refresh materialized view mv_auftrag_masse;
  refresh materialized view mv_kaskade;
  refresh materialized view mv_kaliber_verteilung;

  update auswertung_stand
     set berechnet_ts = now(),
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;

  return now();
end $$;

comment on function auswertung_aktualisieren is
  'Rechnet die Auswertung neu. Dauert je nach Datenmenge einige Sekunden — '
  'währenddessen sind die drei gespeicherten Ansichten kurz gesperrt.';

grant execute on function auswertung_aktualisieren() to authenticated;
grant select on mv_sortier_lauf_masse, mv_auftrag_masse, mv_kaskade,
                mv_kaliber_verteilung to authenticated;

-- Beim Einspielen einmal füllen, damit das Dashboard sofort etwas zeigt.
select auswertung_aktualisieren();
