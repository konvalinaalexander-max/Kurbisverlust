-- 0112 — Das Lager nach Artikel: Artikelgruppe, Demeter/Knospe, gross/klein
--
-- WARUM
--
-- Der Betrieb am 12. Oktober: „Die Chargen sind wichtig — agronomisch: welche
-- Charge fällt, welche verdunstet. Aber im Verkauf denken wir nach Artikeln.
-- Coop will nicht wissen, ob es ein Hokkaido in diesem Kaliber ist, sondern:
-- gross oder klein. Und dann Demeter oder Knospe." Dazu: „Wie stehen wir im
-- Verhältnis zum letzten Jahr? … [ein Kunde] hat schon so viel wie letztes
-- Jahr, [ein anderer] erst 50 Prozent — dass wir für die noch genug übrig
-- haben." (Kundennamen bleiben draussen.) Und der Auftrag: „Mach diesen
-- zweiten Reiter schon mal."
--
-- Was die Perigon-Dateien (Abgleich Rückverfolgbarkeit, beide Firmen, seit
-- Januar 2024) dazu hergeben — gelesen am 12. Oktober, nicht eingecheckt:
--   * je Position der Artikel („Bio Kürbis Knirps Dem klein", „… Butternut
--     lose"), die Preisgruppe des Auftrags (D, K, …) und je Chargenzeile das
--     Label der gelieferten Charge (LiefPrsGrpName: D, K, CH-K);
--   * welche Sorte als welcher Artikel verkauft wird — beobachtet, nicht
--     vermutet: Kaori Kuri, Ker Madec, Orange Summer, Amoro und Fictor gehen
--     als roter/oranger Knirps, Tiana und Mieluna als Butternut, Butterkin als
--     Butterkin/Muskat, Lekor als Kabocha, Orangita als Mandarin;
--   * Lieferungen der Saisons 2023/24 bis 2026/27 je Kunde.
-- Die Coop-Artikeldaten 2026 sagen, was gross und klein heisst: je Sorte ein
-- Kaliber klein und eins gross, 10 bzw. 8 Stück je Kiste (Mandarin 12).
--
-- WAS 0112 TUT
--
-- 1. sorte_kaliber.artikelgruppe: als welcher Artikel die Sorte verkauft wird
--    (vorbelegt aus den Verkäufen 2026, in den Stammdaten änderbar);
--    v_sorte_artikelgruppe nimmt sie, sonst die meistverkaufte Gruppe der
--    Sorte — und sagt, woher.
-- 2. charge.label: Demeter (D) oder Knospe (K) — leer, solange niemand es
--    sagt; v_charge_label nimmt sonst das Label, mit dem Perigon die Charge
--    geliefert hat (ausgang_zeile.liefer_label, neu).
-- 3. artikel_kaliber: was gross und klein je Artikelgruppe heisst (Coop
--    2026), mit Stück je Kiste.
-- 4. ausgang_position: jede Position der Perigon-Datei, ALLE Saisons — nur
--    für den Vergleich je Kunde; die Lieferungen und die Bilanz bleiben, wie
--    sie sind (ab 1. Juli 2026, ausgang_zeile). Geschrieben von
--    ausgang_historie_uebernehmen() beim Einlesen.
-- 5. artikel_lager(h): das Verkaufsfähige am Stichtag je Artikelgruppe,
--    Label und Grösse — dieselbe Masse wie lager_kaliber(h), nur nach den
--    Artikelkalibern geteilt, mit Stück und Kisten.
-- 6. v_kunde_tag: geliefert je Kunde, Saison und Tag (nur Kürbis, ohne
--    interne Umbuchung).
-- 7. Die Demo bekommt Labels und zwei Vorjahre: demo_vorjahre_laden(),
--    gleich nach demo_daten_laden() aufgerufen; demo_daten_entfernen()
--    räumt es mit der Demo-Firma weg.
-- 8. Zwei Gebinde, um die die Halle gebeten hat (Migros Kiste U, Plastik
--    Palox).
--
-- WAS BEWUSST NICHT
--
-- Kein zweites Rechenwerk: Eingang, ausgeliefert, Verlust und Lager je
-- Artikel sind die Summen der Chargen (erg_charge) — die App zählt sie nach
-- Artikelgruppe und Label zusammen. Die Vorjahre gehen in keine Bilanz ein.
-- Preise werden weder gelesen noch gespeichert. Welcher Kunde zu welcher
-- Kette gehört (Migros, Coop, …), steht nicht hier — die Namen sind die der
-- Datei. Ein Demeter-Kürbis darf als Knospe verkauft werden, nicht umgekehrt:
-- das sagt die App, rechnet es aber nicht um.

-- =====================================================================
-- 1. Artikelgruppe je Sorte
-- =====================================================================
alter table sorte_kaliber add column if not exists artikelgruppe text;
comment on column sorte_kaliber.artikelgruppe is
  'Als welcher Artikel die Sorte verkauft wird (Knirps, Butternut, Butterkin/Muskat, Kabocha, Mandarin, …) — 0112. Leer: v_sorte_artikelgruppe nimmt die meistverkaufte Gruppe der Sorte.';

-- Vorbelegt aus den Verkäufen 2026 (welche Charge als welcher Artikel ging).
update sorte_kaliber s set artikelgruppe = v.gruppe
  from (values ('Kaori Kuri', 'Knirps'), ('Ker Madec', 'Knirps'), ('Orange Summer', 'Knirps'),
               ('Amoro', 'Knirps'), ('Fictor', 'Knirps'),
               ('Tiana', 'Butternut'), ('Mieluna', 'Butternut'),
               ('Butterkin', 'Butterkin/Muskat'), ('Lekor', 'Kabocha'), ('Orangita', 'Mandarin')) v(sorte, gruppe)
 where s.sorte = v.sorte and s.artikelgruppe is null;

-- =====================================================================
-- 2. Demeter oder Knospe je Charge
-- =====================================================================
alter table charge add column if not exists label text;
do $$ begin
  alter table charge add constraint charge_label_dk check (label in ('D', 'K'));
exception when duplicate_object then null; end $$;
comment on column charge.label is
  'Demeter (D) oder Knospe (K) — 0112. Leer: v_charge_label nimmt das Label, mit dem Perigon die Charge geliefert hat.';

alter table ausgang_zeile add column if not exists liefer_label text;
alter table ausgang_zeile add column if not exists preisgruppe text;
comment on column ausgang_zeile.liefer_label is
  'LiefPrsGrpName der Perigon-Datei: das Label der gelieferten Charge (D, K, CH-K, …) — 0112.';
comment on column ausgang_zeile.preisgruppe is
  'AuftragsPrsGrpBez der Perigon-Datei: das Label, als das der Artikel verkauft wurde (D, K, …) — 0112.';

-- =====================================================================
-- 3. Was gross und klein heisst
-- =====================================================================
create table if not exists artikel_kaliber (
  gruppe          text not null,
  groesse         text not null check (groesse in ('klein', 'gross', 'stueck')),
  von_g           int  not null check (von_g >= 0),
  bis_g           int  not null,
  stueck_je_kiste int  check (stueck_je_kiste > 0),
  bemerkung       text,
  erfasser        uuid references profil(id) default auth.uid(),
  ts              timestamptz not null default now(),
  primary key (gruppe, groesse),
  constraint artikel_kaliber_spanne check (bis_g > von_g)
);
comment on table artikel_kaliber is
  'Was ein Artikel gross und klein nennt: je Artikelgruppe das Kaliber in Gramm [von, bis) und die Stück je Kiste (0112). Vorbelegt aus den Coop-Artikeldaten 2026; „stueck" heisst: eine Grösse.';

insert into artikel_kaliber (gruppe, groesse, von_g, bis_g, stueck_je_kiste, bemerkung)
values ('Knirps', 'klein', 600, 1100, 10, 'Coop-Artikeldaten 2026'),
       ('Knirps', 'gross', 1100, 1600, 8, 'Coop-Artikeldaten 2026'),
       ('Butternut', 'klein', 800, 1300, 10, 'Coop-Artikeldaten 2026'),
       ('Butternut', 'gross', 1300, 1800, 8, 'Coop-Artikeldaten 2026'),
       ('Butterkin/Muskat', 'klein', 600, 1200, 10, 'Coop-Artikeldaten 2026'),
       ('Butterkin/Muskat', 'gross', 1200, 1800, 8, 'Coop-Artikeldaten 2026'),
       ('Kabocha', 'klein', 700, 1200, 10, 'Coop-Artikeldaten 2026'),
       ('Kabocha', 'gross', 1200, 1700, 8, 'Coop-Artikeldaten 2026'),
       ('Mandarin', 'stueck', 300, 800, 12, 'Coop-Artikeldaten 2026')
on conflict (gruppe, groesse) do nothing;

alter table artikel_kaliber enable row level security;
drop policy if exists artikel_kaliber_lesen on artikel_kaliber;
drop policy if exists artikel_kaliber_admin on artikel_kaliber;
create policy artikel_kaliber_lesen on artikel_kaliber for select to authenticated using (true);
create policy artikel_kaliber_admin on artikel_kaliber for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on artikel_kaliber to authenticated;

-- =====================================================================
-- 4. Einen Verkaufsartikel einordnen
-- =====================================================================
-- Aus dem Namen und der Preisgruppe: welche Gruppe, welche Grösse, welches
-- Label. Die Namen in Perigon sind nicht einheitlich („Knirps Demeter gros",
-- „Muscat/Butterkin Dem gross", „roter Knirps Knospe klein", „… lose") —
-- darum Muster, nicht Gleichheit. Ohne Grösse im Namen: lose (nach Kilo).
create or replace function artikel_einordnen(p_artikel text, p_preisgruppe text default null)
returns table (gruppe text, groesse text, label text)
language sql immutable set search_path = public as $$
  select case when a ~ '(knirps|potimarron|hokkaido|kuri)' then 'Knirps'
              when a ~ 'butternu' then 'Butternut'
              when a ~ '(butterkin|muskat|muscat)' then 'Butterkin/Muskat'
              when a ~ '(kobocha|kabocha)' then 'Kabocha'
              when a ~ 'mandarin' then 'Mandarin'
              when a ~ '\mmix\M' then 'Mix'
              when a ~ 'k(ü|u|ue)rb' then 'andere'
         end,
         case when a ~ '(gross|\mgros\M|\mgr\.)' then 'gross'
              when a ~ '(klein|\mkl\.)' then 'klein'
              else 'lose' end,
         case when upper(coalesce(p_preisgruppe, '')) in ('D', 'DU') then 'D'
              when upper(coalesce(p_preisgruppe, '')) in ('K', 'KZ') then 'K'
              when a ~ '(demeter|\mdem\M)' then 'D'
              when a ~ 'knospe' then 'K'
         end
    from (select lower(coalesce(p_artikel, '')) as a) t
$$;
comment on function artikel_einordnen(text, text) is
  'Ein Verkaufsartikel aus Perigon eingeordnet: Artikelgruppe, Grösse (gross, klein, lose) und Label (D/K, aus der Preisgruppe, sonst aus dem Namen) — 0112.';
-- Wie jede Funktion seit 0035: nicht für jeden, nur für Angemeldete
-- (pruefung.sql „Diese Funktionen stehen jedem offen").
revoke all on function artikel_einordnen(text, text) from public;
grant execute on function artikel_einordnen(text, text) to authenticated;

-- Ist das Kürbis? Wie die App (istKuerbis, src/lib/warenausgang.ts): die
-- Bestätigung des Betriebsleiters, sonst der Name — ohne Buchungen und Arbeit.
create or replace function ist_kuerbis_vorschlag(p_artikel_id text, p_artikel text)
returns boolean language sql immutable set search_path = public as $$
  select lower(coalesce(p_artikel_id, '') || ' ' || coalesce(p_artikel, '')) ~ 'k(ü|u|ue)rb'
     and lower(coalesce(p_artikel_id, '') || ' ' || coalesce(p_artikel, '')) !~ '(verrechnung|arbeit|lohn|transport|miete|gebühr)'
$$;
revoke all on function ist_kuerbis_vorschlag(text, text) from public;
grant execute on function ist_kuerbis_vorschlag(text, text) to authenticated;

-- Die Saison läuft vom 1. Juli bis zum 30. Juni und heisst nach dem Jahr, in dem sie beginnt.
create or replace function saison_von(p_datum date) returns int
language sql immutable set search_path = public as $$
  select case when extract(month from p_datum) >= 7 then extract(year from p_datum)::int
              else extract(year from p_datum)::int - 1 end
$$;
revoke all on function saison_von(date) from public;
grant execute on function saison_von(date) to authenticated;

-- =====================================================================
-- 5. Alle Positionen aller Saisons — für den Vergleich je Kunde
-- =====================================================================
create table if not exists ausgang_position (
  quelle             text   not null references ausgang_quelle(code) on update cascade on delete cascade,
  pos_id             bigint not null,
  datum              date   not null,
  saison             int    not null,
  journal            text,
  kunde              text,
  artikel_id         text   not null,
  artikel            text   not null,
  preisgruppe        text,
  einheit            text,
  menge              numeric(14,3),
  gewicht_je_artikel numeric(10,4),
  kg                 numeric(14,3),
  gebindeart         text,
  gebinde_menge      int,
  ts                 timestamptz not null default now(),
  primary key (quelle, pos_id)
);
create index if not exists ausgang_position_saison on ausgang_position (saison, kunde);
comment on table ausgang_position is
  'Jede Lieferscheinposition der Perigon-Datei, alle Saisons (0112) — einmal je Position, kg = Menge × Gewicht je Artikel. Nur für den Vergleich je Kunde und Saison; die Bilanz rechnet mit ausgang_zeile und lieferung.';

alter table ausgang_position enable row level security;
drop policy if exists ausgang_position_lesen on ausgang_position;
drop policy if exists ausgang_position_admin on ausgang_position;
create policy ausgang_position_lesen on ausgang_position for select to authenticated using (true);
create policy ausgang_position_admin on ausgang_position for all to authenticated using (ist_admin()) with check (ist_admin());
grant select, insert, update, delete on ausgang_position to authenticated;

create or replace function ausgang_historie_uebernehmen(p_quelle text, p_positionen jsonb, p_lose jsonb default '[]'::jsonb)
returns jsonb language plpgsql security invoker set search_path = public as $fn$
declare
  v_pos  int := 0;
  v_lose int := 0;
  v_saisons jsonb;
begin
  if not ist_admin() then
    raise exception 'Den Warenausgang übernimmt nur der Betriebsleiter.';
  end if;
  if not exists (select 1 from ausgang_quelle where code = p_quelle) then
    raise exception 'Die Firma „%" ist noch nicht angelegt — zuerst den Warenausgang übernehmen.', p_quelle;
  end if;

  with eingang as (
    select * from jsonb_to_recordset(coalesce(p_positionen, '[]'::jsonb)) as x(
      pos_id bigint, datum date, journal text, kunde text, artikel_id text, artikel text,
      preisgruppe text, einheit text, menge numeric, gewicht_je_artikel numeric,
      gebindeart text, gebinde_menge numeric)
  ), geschrieben as (
    insert into ausgang_position (quelle, pos_id, datum, saison, journal, kunde, artikel_id, artikel, preisgruppe,
                                  einheit, menge, gewicht_je_artikel, kg, gebindeart, gebinde_menge)
    select p_quelle, e.pos_id, e.datum, saison_von(e.datum), e.journal, e.kunde, e.artikel_id, e.artikel,
           nullif(e.preisgruppe, ''), e.einheit, e.menge, e.gewicht_je_artikel,
           round(coalesce(e.menge, 0) * coalesce(e.gewicht_je_artikel, 0), 3), nullif(e.gebindeart, ''),
           round(e.gebinde_menge)::int
      from eingang e
     where e.pos_id is not null and e.datum is not null and e.artikel_id is not null and e.artikel is not null
    on conflict (quelle, pos_id) do update
      set datum = excluded.datum, saison = excluded.saison, journal = excluded.journal, kunde = excluded.kunde,
          artikel_id = excluded.artikel_id, artikel = excluded.artikel, preisgruppe = excluded.preisgruppe,
          einheit = excluded.einheit, menge = excluded.menge, gewicht_je_artikel = excluded.gewicht_je_artikel,
          kg = excluded.kg, gebindeart = excluded.gebindeart, gebinde_menge = excluded.gebinde_menge, ts = now()
    returning saison
  )
  select coalesce(jsonb_object_agg(s.saison::text, s.n), '{}'::jsonb), coalesce(sum(s.n), 0)::int
    into v_saisons, v_pos
    from (select saison, count(*)::int as n from geschrieben group by saison) s;

  -- Die Labels an die Zeilen der laufenden Saison (die Bilanz-Zeilen).
  with lose as (
    select * from jsonb_to_recordset(coalesce(p_lose, '[]'::jsonb)) as x(
      pos_id bigint, charge_extern text, lauf_nr int, liefer_label text, preisgruppe text)
  ), gesetzt as (
    update ausgang_zeile z
       set liefer_label = nullif(l.liefer_label, ''), preisgruppe = nullif(l.preisgruppe, '')
      from lose l
     where z.quelle = p_quelle and z.pos_id = l.pos_id
       and z.charge_extern = coalesce(l.charge_extern, '') and z.lauf_nr = coalesce(l.lauf_nr, 1)
       and (z.liefer_label is distinct from nullif(l.liefer_label, '')
            or z.preisgruppe is distinct from nullif(l.preisgruppe, ''))
    returning 1
  )
  select count(*) into v_lose from gesetzt;

  return jsonb_build_object('positionen', v_pos, 'je_saison', v_saisons, 'labels_gesetzt', v_lose);
end $fn$;
comment on function ausgang_historie_uebernehmen(text, jsonb, jsonb) is
  'Schreibt beim Einlesen der Perigon-Datei jede Position aller Saisons nach ausgang_position und die Labels (LiefPrsGrpName, Preisgruppe) an die Zeilen der laufenden Saison (0112). Nur der Betriebsleiter.';
revoke all on function ausgang_historie_uebernehmen(text, jsonb, jsonb) from public;
grant execute on function ausgang_historie_uebernehmen(text, jsonb, jsonb) to authenticated;

-- Die Positionen für den Vergleich: aus ausgang_position, und was dort (noch)
-- fehlt, aus den Zeilen der laufenden Saison — so steht die laufende Saison
-- auch vor dem ersten Einlesen nach 0112 (und in der Demo) schon da.
create or replace view v_verkauf_position with (security_invoker = true) as
select p.quelle, p.pos_id, p.datum, p.saison, p.journal, p.kunde, p.artikel_id, p.artikel, p.preisgruppe,
       p.kg, p.gebindeart, p.gebinde_menge, 'datei'::text as herkunft
  from ausgang_position p
union all
select z.quelle, z.pos_id, z.datum, saison_von(z.datum), z.journal, z.kunde, z.artikel_id, z.artikel, z.preisgruppe,
       z.kg_position, z.gebindeart, z.gebinde_menge, 'zeile'::text
  from (select distinct on (quelle, pos_id) * from ausgang_zeile order by quelle, pos_id, lauf_nr) z
 where not exists (select 1 from ausgang_position p where p.quelle = z.quelle and p.pos_id = z.pos_id);
comment on view v_verkauf_position is
  'Je Lieferscheinposition: Datum, Saison, Kunde, Artikel, kg — aus ausgang_position (alle Saisons), ergänzt um die Positionen der laufenden Saison, die nur in ausgang_zeile stehen (0112).';
grant select on v_verkauf_position to authenticated;

create or replace view v_kunde_tag with (security_invoker = true) as
select v.kunde, v.saison, v.datum, e.gruppe, e.groesse, e.label, sum(v.kg) as kg, count(*)::int as positionen
  from v_verkauf_position v
  left join ausgang_artikel a on a.artikel_id = v.artikel_id and a.artikel = v.artikel
 cross join lateral artikel_einordnen(v.artikel, v.preisgruppe) e
 where coalesce(v.journal, '') <> 'L'
   and coalesce(a.ist_kuerbis, ist_kuerbis_vorschlag(v.artikel_id, v.artikel))
   and v.kunde is not null and v.kunde <> ''
 group by v.kunde, v.saison, v.datum, e.gruppe, e.groesse, e.label;
comment on view v_kunde_tag is
  'Geliefert je Kunde, Saison, Tag und Artikel (Gruppe, Grösse, Label) — nur Kürbis, ohne interne Umbuchung (Journal L). Für den Vergleich mit den Vorjahren (0112).';
grant select on v_kunde_tag to authenticated;

-- =====================================================================
-- 6. Woher Artikelgruppe und Label kommen
-- =====================================================================
create or replace view v_sorte_artikelgruppe with (security_invoker = true) as
with verkauft as (
  select l.sorte, e.gruppe, sum(l.kg) as kg
    from lieferung l
    join lieferung_import li on li.lieferung_id = l.id
    join ausgang_zeile z on z.id = li.zeile_id
   cross join lateral artikel_einordnen(z.artikel, z.preisgruppe) e
   where l.sorte is not null and e.gruppe is not null and e.gruppe not in ('andere', 'Mix')
   group by l.sorte, e.gruppe
), haupt as (
  select distinct on (sorte) sorte, gruppe, kg from verkauft order by sorte, kg desc, gruppe
)
select s.sorte,
       coalesce(s.artikelgruppe, h.gruppe) as artikelgruppe,
       case when s.artikelgruppe is not null then 'Stammdaten'
            when h.gruppe is not null then 'verkauft als' end as quelle,
       h.gruppe as gruppe_verkauft
  from sorte_kaliber s
  left join haupt h on h.sorte = s.sorte;
comment on view v_sorte_artikelgruppe is
  'Je Sorte die Artikelgruppe: aus den Stammdaten, sonst die meistverkaufte Gruppe ihrer Lieferungen; gruppe_verkauft zum Vergleich (0112).';
grant select on v_sorte_artikelgruppe to authenticated;

create or replace view v_charge_label with (security_invoker = true) as
with perigon as (
  select l.charge_nr,
         count(*) filter (where k.label = 'D')::int as n_d,
         count(*) filter (where k.label = 'K')::int as n_k
    from lieferung l
    join lieferung_import li on li.lieferung_id = l.id
    join ausgang_zeile z on z.id = li.zeile_id
   cross join lateral (select case when upper(z.liefer_label) in ('D', 'DU') then 'D'
                                   when upper(z.liefer_label) in ('K', 'CH-K', 'KZ') then 'K' end as label) k
   where l.charge_nr is not null and k.label is not null
   group by l.charge_nr
)
select c.nr as charge_nr,
       coalesce(c.label, case when p.n_d > p.n_k then 'D' when p.n_k > p.n_d then 'K' end) as label,
       case when c.label is not null then 'Stammdaten'
            when p.n_d <> p.n_k then 'Perigon' end as quelle,
       case when p.n_d > 0 and p.n_k > 0 then true else false end as gemischt,
       coalesce(p.n_d, 0) as n_d, coalesce(p.n_k, 0) as n_k
  from charge c
  left join perigon p on p.charge_nr = c.nr;
comment on view v_charge_label is
  'Je Charge Demeter (D) oder Knospe (K): aus den Stammdaten, sonst das Label, mit dem Perigon sie geliefert hat (Mehrheit der Zeilen); gemischt, wenn beide vorkommen (0112).';
grant select on v_charge_label to authenticated;

-- =====================================================================
-- 7. Das Verkaufsfähige je Artikel am Stichtag
-- =====================================================================
-- Dieselbe Masse wie lager_kaliber(h): je Charge das Verkaufsfähige der
-- Prognose, aufgeteilt nach der Gewichtsverteilung ihrer Sortier-CSV (um die
-- Verdunstung bis zum Stichtag geschrumpft). Nur die Grenzen sind andere:
-- die des Artikels (klein/gross), nicht die Bänder der Sortierung. Was in
-- kein Artikelkaliber fällt, steht als 'darunter'/'darueber' (lose
-- verkäuflich), ohne CSV als 'ohne Verteilung', ohne Artikelkaliber der
-- Gruppe als 'lose'. Stück = kg ÷ mittleres Gewicht der Klasse.
create or replace function artikel_lager(p_h integer)
returns table (artikelgruppe text, label text, groesse text, von_g int, bis_g int, stueck_je_kiste int,
               kg numeric, stueck numeric, kisten numeric, g_mittel numeric,
               n_chargen int, chargen int[], h int, datum date)
language sql stable security definer set search_path = public as $$
with prognose as (
  select p.schluessel::int as charge_nr, c.sorte, p.h, p.datum, p.verkaufsfaehig_kg,
         q.basis, q.schluessel as q_schluessel
    from erg_prognose p
    join charge c on c.nr = p.schluessel::int
    left join lager_schluessel() q on q.charge_nr = c.nr
   where p.gruppe = 'charge' and p.h = p_h and p.verkaufsfaehig_kg > 0
), zuordnung as (
  select p.*, g.artikelgruppe, l.label
    from prognose p
    left join v_sorte_artikelgruppe g on g.sorte = p.sorte
    left join v_charge_label l on l.charge_nr = p.charge_nr
), verteilung as (
  select w.basis, w.schluessel, w.sorte, w.anzahl, w.g::numeric as g
    from kuerbis_stichtag(p_h) w
   where exists (select 1 from zuordnung z where z.basis = w.basis and z.q_schluessel = w.schluessel)
), mit_klasse as (
  select v.basis, v.schluessel,
         coalesce(k.groesse, case when ak.n = 0 then 'lose'
                                  when v.g < ak.min_von then 'darunter'
                                  when v.g >= ak.max_bis then 'darueber'
                                  else 'dazwischen' end) as groesse,
         v.anzahl, v.g
    from verteilung v
    left join v_sorte_artikelgruppe sg on sg.sorte = v.sorte
    left join lateral (select count(*) as n, min(a.von_g) as min_von, max(a.bis_g) as max_bis
                         from artikel_kaliber a where a.gruppe = sg.artikelgruppe) ak on true
    left join artikel_kaliber k on k.gruppe = sg.artikelgruppe and v.g >= k.von_g and v.g < k.bis_g
), anteile as (
  select m.basis, m.schluessel, m.groesse,
         sum(m.anzahl * m.g) / nullif(sum(sum(m.anzahl * m.g)) over (partition by m.basis, m.schluessel), 0) as anteil,
         sum(m.anzahl * m.g) / nullif(sum(m.anzahl), 0) as g_mittel
    from mit_klasse m
   group by m.basis, m.schluessel, m.groesse
), je_charge as (
  select z.charge_nr, z.artikelgruppe, z.label, z.h, z.datum,
         coalesce(a.groesse, 'ohne Verteilung') as groesse,
         case when a.anteil is null then z.verkaufsfaehig_kg else z.verkaufsfaehig_kg * a.anteil end as kg,
         a.g_mittel
    from zuordnung z
    left join anteile a on a.basis = z.basis and a.schluessel = z.q_schluessel
)
select j.artikelgruppe, j.label, j.groesse, k.von_g, k.bis_g, k.stueck_je_kiste,
       zahl(sum(j.kg), 2, 1e12)::numeric(14,2),
       zahl(sum(j.kg * 1000 / nullif(j.g_mittel, 0)), 0, 1e12)::numeric(14,0),
       zahl(sum(j.kg * 1000 / nullif(j.g_mittel, 0)) / nullif(max(k.stueck_je_kiste), 0), 0, 1e12)::numeric(14,0),
       zahl(sum(j.kg) * 1000 / nullif(sum(j.kg * 1000 / nullif(j.g_mittel, 0)), 0), 0, 1e6)::numeric(10,0),
       count(distinct j.charge_nr)::int, array_agg(distinct j.charge_nr order by j.charge_nr),
       max(j.h)::int, max(j.datum)
  from je_charge j
  left join artikel_kaliber k on k.gruppe = j.artikelgruppe and k.groesse = j.groesse
 group by j.artikelgruppe, j.label, j.groesse, k.von_g, k.bis_g, k.stueck_je_kiste
$$;
comment on function artikel_lager(integer) is
  'Das Verkaufsfähige in h Tagen je Artikelgruppe, Label (D/K) und Grösse (klein, gross, stueck; darunter/darueber: in keinem Artikelkaliber; lose: Gruppe ohne Kaliber; ohne Verteilung: keine Sortier-CSV) — dieselbe Masse wie lager_kaliber(h), nach den Artikelkalibern geteilt; Stück = kg ÷ mittleres Gewicht der Klasse (0112).';
revoke all on function artikel_lager(integer) from public;
grant execute on function artikel_lager(integer) to authenticated;

-- =====================================================================
-- 8. Die Demo: Labels und zwei Vorjahre
-- =====================================================================
-- Die Demo-Saison (demo_daten_laden, 0104) bleibt, wie sie ist; was 0112
-- braucht, legt demo_vorjahre_laden() dazu — aufgerufen gleich nach
-- demo_daten_laden() (App-Knopf, Prüfstand, Prüfblock): das Label an jeder
-- Demo-Verkaufszeile, wie Perigon es führt, und zwei Vorjahre je Demo-Kunde,
-- eine Saisonkurve über Juli bis Juni, je Kunde und Jahr etwas anders gross.
-- Alles hängt an der Demo-Firma (quelle DEMO): demo_daten_entfernen() räumt
-- es mit ihr weg (ausgang_position folgt ihr per on delete cascade).
-- demo_daten_laden() selbst wird nicht neu geschrieben — tausend Zeilen
-- kopieren, um eine anzuhängen, wäre die grössere Gefahr.
create or replace function demo_vorjahre_laden() returns text
language plpgsql security definer set search_path = public as $fn$
declare
  v_saison int;
  v_erste date;
  v_n int := 0;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Demo-Daten darf nur der Betriebsleiter laden.';
  end if;
  if not exists (select 1 from ausgang_quelle where code = 'DEMO') then
    return 'Keine Demo-Verkaufsdatei — keine Vorjahre.';
  end if;
  -- Das Label der gelieferten Charge, wie Perigon es führt: jede vierte Knospe.
  update ausgang_zeile z
     set liefer_label = case when z.charge_extern ~ '^[0-9]+$' and z.charge_extern::int % 4 = 1 then 'K' else 'D' end,
         preisgruppe  = case when z.charge_extern ~ '^[0-9]+$' and z.charge_extern::int % 4 = 1 then 'K' else 'D' end
   where z.quelle = 'DEMO' and z.liefer_label is null;
  -- Die laufende Saison ist die der jüngsten Demo-Lieferung. Die Demo beginnt
  -- im Frühling davor — was vor ihrer ersten Lieferung liegt, kommt dazu.
  select saison_von(max(datum)), min(datum) into v_saison, v_erste from ausgang_zeile where quelle = 'DEMO';
  if v_saison is null then return 'Keine Demo-Lieferungen — keine Vorjahre.'; end if;
  delete from ausgang_position where quelle = 'DEMO' and saison < v_saison;
  -- Je Kunde und Vorjahr eine Lieferung je Woche, nach einer Glocke über
  -- die Saison (Höhepunkt im Oktober), Grösse je Kunde aus der laufenden Saison.
  insert into ausgang_position (quelle, pos_id, datum, saison, journal, kunde, artikel_id, artikel, preisgruppe,
                                einheit, menge, gewicht_je_artikel, kg, gebindeart, gebinde_menge)
  select 'DEMO', 900000000 + j.jahr * 100000 + k.nr * 1000 + w.woche,
         make_date(v_saison - j.jahr, 7, 1) + (w.woche * 7),
         v_saison - j.jahr, 'Lieferschein', k.kunde, k.artikel_id, k.artikel, 'D', 'kg',
         x.kg, 1, x.kg, 'IFCO', null
    from (select row_number() over (order by z.kunde)::int as nr, z.kunde,
                 min(z.artikel_id) as artikel_id, min(z.artikel) as artikel,
                 greatest(sum(z.kg_position) / greatest(count(distinct date_trunc('week', z.datum)), 1), 50) as je_woche
            from ausgang_zeile z where z.quelle = 'DEMO' and z.kunde is not null group by z.kunde) k
   cross join (values (1, 1.0), (2, 0.8)) j(jahr, faktor)
   cross join generate_series(0, 51) w(woche)
   cross join lateral (select round(k.je_woche * j.faktor * (0.6 + 0.08 * k.nr)
                                    * exp(-power((w.woche - 15) / 9.0, 2))
                                    * (0.8 + 0.4 * ((k.nr * 7 + w.woche * 13 + j.jahr * 5) % 10) / 10.0)) as kg) x
   where x.kg >= 20
     and make_date(v_saison - j.jahr, 7, 1) + (w.woche * 7) < v_erste
  on conflict (quelle, pos_id) do nothing;
  get diagnostics v_n = row_count;
  return format('Demo: %s Lieferungen in zwei Vorjahren, Labels an den Demo-Verkaufszeilen.', v_n);
end $fn$;
comment on function demo_vorjahre_laden() is
  'Ergänzt die Demo um das Perigon-Label je Verkaufszeile und zwei Vorjahre je Demo-Kunde (ausgang_position, quelle DEMO) — für Lager nach Artikel (0112). Gleich nach demo_daten_laden() aufrufen; demo_daten_entfernen() räumt es mit der Demo-Firma weg.';
-- security definer: ohne das „revoke" könnte sie jeder rufen, auch ohne
-- Anmeldung (auth.uid() ist dann leer und die Sperre oben greift nicht).
revoke all on function demo_vorjahre_laden() from public;
grant execute on function demo_vorjahre_laden() to authenticated;

-- =====================================================================
-- 9. Zwei Gebinde, um die die Halle gebeten hat
-- =====================================================================
-- Rückmeldung Nr. 9 (10. Oktober, Waschen + Sortieren): „Es braucht noch:
-- Migros Kisten U 2.43 kg, Plastikpaloxen 35 kg". Eine Palox ist ihr eigenes
-- Gebinde mit Füssen — eine Palox, eine „Kiste", keine Palette darunter.
-- Was schon so heisst, bleibt, wie es ist.
insert into gebinde (art, tara_kg_pro_kiste, tara_kg_palette, bemerkung)
values ('Migros Kiste U', 2.43, 25.0, 'Rückmeldung aus der Halle, 10.10.2026 (0112): Tara 2.43 kg je Kiste'),
       ('Plastik Palox', 35.0, 0, 'Rückmeldung aus der Halle, 10.10.2026 (0112): eine Palox = ein Gebinde, Tara 35 kg, keine Palette')
on conflict (art) do nothing;

-- =====================================================================
-- 10. Stand
-- =====================================================================
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 112 $$;
