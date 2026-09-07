-- =====================================================================
-- 0050 — Warenausgang aus dem Warenwirtschaftssystem einlesen
--
-- Der Betrieb führt seine Lieferscheine in Perigon. Zweimal im Jahr — oder
-- wöchentlich — zieht er dort die Auswertung „Abgleich Rückverfolgbarkeit"
-- als Excel-Datei und lädt sie hier hoch. **Immer die ganze Datei**, nie nur
-- die neuen Zeilen: die App muss selbst erkennen, was sie schon kennt.
--
-- Und es sind zwei Dateien, weil der Betrieb zwei Firmen hat (docs/
-- WARENAUSGANG_BEFUND.md): eine liefert an Coop und Migros, die andere an den
-- Grosshandel. Beide führen Kürbis, beide zählen in dieselbe Bilanz, ihre
-- Positionsnummern sind aber je Firma vergeben — deshalb hängt alles hier an
-- einer *Quelle*.
--
-- AUFBAU
--
--   ausgang_quelle   Die Firma (Mandant), aus deren Perigon die Datei kommt.
--   ausgang_datei    Eine hochgeladene Datei, mit Prüfsumme: dieselbe Datei
--                    zweimal hochzuladen ist erlaubt und folgenlos.
--   ausgang_zeile    Die Rohzeilen, wie sie in der Datei standen — eine Zeile
--                    je Charge-Zuordnung einer Lieferscheinposition. Das ist
--                    die Wahrheit, aus der alles Weitere folgt.
--   ausgang_artikel  Welcher Artikel ist Kürbis, und welche Sorte ist er?
--                    Vom Betriebsleiter bestätigt, nicht geraten.
--   lieferung_import Welche Lieferung aus welcher Importzeile stammt. Die
--                    Lieferungen selbst landen in `lieferung`, wo die
--                    Auswertung sie ohnehin sucht.
--
-- WARUM DIE ROHZEILEN BLEIBEN
--
-- Ohne sie liesse sich beim nächsten Hochladen nicht sagen, was neu ist — die
-- Datei enthält jedes Mal alles. Und eine Zeile, die der Betrieb im Perigon
-- korrigiert, muss hier als Änderung sichtbar werden und nicht als zweite
-- Lieferung. Der Fingerabdruck macht das billig: gleicher Schlüssel, gleicher
-- Fingerabdruck heisst „schon gesehen, nichts zu tun".
-- =====================================================================

-- ---------- 1. Woher die Datei kommt --------------------------------------
create table if not exists ausgang_quelle (
  code              text primary key,
  name              text not null,
  -- Woran die App die Datei wiedererkennt (Kleinschreibung, Teilzeichenkette).
  dateiname_muster  text,
  aktiv             boolean not null default true,
  bemerkung         text,
  erfasser          uuid references profil(id) default auth.uid(),
  ts                timestamptz not null default now()
);

comment on table ausgang_quelle is
  'Die Firma, aus deren Warenwirtschaft eine Warenausgangsdatei kommt. '
  'Positionsnummern sind nur innerhalb einer Quelle eindeutig.';

-- ---------- 2. Eine hochgeladene Datei ------------------------------------
create table if not exists ausgang_datei (
  id                bigserial primary key,
  quelle            text not null references ausgang_quelle(code) on update cascade,
  dateiname         text not null,
  pruefsumme        text not null,             -- SHA-256 der Rohdatei
  n_zeilen          int  not null default 0,
  n_kuerbis         int  not null default 0,
  n_neu             int  not null default 0,
  n_geaendert       int  not null default 0,
  n_unveraendert    int  not null default 0,
  von_datum         date,
  bis_datum         date,
  bemerkung         text,
  hochgeladen_von   uuid not null references profil(id) default auth.uid(),
  ts                timestamptz not null default now()
);

-- Dieselbe Datei nochmals: erkannt und folgenlos, nicht doppelt verarbeitet.
create unique index if not exists ausgang_datei_pruefsumme
  on ausgang_datei (quelle, pruefsumme);

comment on table ausgang_datei is
  'Jedes Hochladen mit Prüfsumme und Bilanz. Dieselbe Datei zweimal hochladen '
  'ist erlaubt: die Prüfsumme erkennt sie wieder.';

-- ---------- 3. Die Rohzeilen ----------------------------------------------
create table if not exists ausgang_zeile (
  id                 bigserial primary key,
  quelle             text   not null references ausgang_quelle(code) on update cascade,
  pos_id             bigint not null,          -- AufPosId: die Lieferscheinposition
  charge_extern      text   not null default '',
  -- Dieselbe Position kann dieselbe Charge zweimal nennen (kommt in den echten
  -- Dateien vor). Ohne Laufnummer verlöre eine der beiden Zeilen ihren Platz.
  lauf_nr            int    not null default 1,
  fingerabdruck      text   not null,
  datei_id           bigint references ausgang_datei(id) on delete set null,
  datum              date   not null,
  journal            text,
  auftragsnr         text,
  kunde              text,
  artikel_id         text   not null,
  artikel            text   not null,
  einheit            text,
  menge              numeric(14,3),
  gewicht_je_artikel numeric(10,4),
  batch_menge        numeric(14,3),
  kg_position        numeric(14,3),
  kg_charge          numeric(14,3),
  gebindeart         text,
  gebinde_menge      int,
  gebinde_inhalt     int,
  produzent          text,
  erloes             numeric(14,2),
  erfasser           uuid not null references profil(id) default auth.uid(),
  ts                 timestamptz not null default now(),
  geaendert_ts       timestamptz,
  constraint ausgang_zeile_eindeutig unique (quelle, pos_id, charge_extern, lauf_nr)
);

create index if not exists ausgang_zeile_datum on ausgang_zeile (datum);
create index if not exists ausgang_zeile_artikel on ausgang_zeile (artikel_id, artikel);
create index if not exists ausgang_zeile_charge on ausgang_zeile (charge_extern);

comment on table ausgang_zeile is
  'Eine Zeile der Warenausgangsdatei: welcher Teil einer Lieferscheinposition '
  'aus welcher Charge kam. kg_position gilt für die ganze Position und steht '
  'auf jeder ihrer Zeilen — beim Summieren je Position nur einmal zählen.';
comment on column ausgang_zeile.kg_position is
  'Masse der ganzen Position (Menge × Gewicht je Artikel). Auf allen Zeilen '
  'derselben Position gleich; je Position einmal zählen, sonst Doppelzählung.';
comment on column ausgang_zeile.kg_charge is
  'Der dieser Charge zugeordnete Teil (Batchmenge × Gewicht je Artikel).';

-- ---------- 4. Welcher Artikel ist Kürbis, und welche Sorte? --------------
-- Die Datei kennt Verkaufsartikel („Bio Kürbis Butternut Dem gross"), die
-- Auswertung kennt Sorten („Tiana"). Dazwischen liegt eine Übersetzung, die
-- nur der Betrieb kennt. Sie wird deshalb bestätigt und nicht geraten — die
-- App darf einen Vorschlag machen, aber sie schreibt ihn nicht als Wahrheit.
create table if not exists ausgang_artikel (
  artikel_id    text not null,
  artikel       text not null,
  ist_kuerbis   boolean not null,
  sorte         text references sorte_kaliber(sorte) on update cascade,
  bestaetigt_von uuid references profil(id) default auth.uid(),
  ts            timestamptz not null default now(),
  bemerkung     text,
  primary key (artikel_id, artikel)
);

comment on table ausgang_artikel is
  'Bestätigte Zuordnung eines Verkaufsartikels: Kürbis ja/nein und welche '
  'Sorte. Dieselbe Artikelkennung trug im Zeitverlauf verschiedene Artikel, '
  'darum gehört der Name zum Schlüssel.';

-- ---------- 5. Die Lieferung weiss, woher sie kommt ------------------------
-- Zwei Spalten an `lieferung` wären der kürzere Weg gewesen — und der falsche:
-- v_lieferung_masse liest die Tabelle mit `l.*`, und neue Spalten landen dort
-- mitten in der Sicht. Beim ersten Einrichten entstand sie vor der Spalte, beim
-- zweiten danach; der Fingerabdruck-Vergleich in run.sh fiel darüber, und
-- „create or replace" konnte es nicht richten (eine Sichtspalte lässt sich nicht
-- umbenennen). Gefunden von der Stufe, die genau dafür da ist.
--
-- Also eine Beitabelle: Woher eine Lieferung kommt, ist etwas *über* sie und
-- nicht Teil von ihr. Die Auswertung merkt davon nichts.
create table if not exists lieferung_import (
  lieferung_id bigint primary key references lieferung(id) on delete cascade,
  quelle       text   not null references ausgang_quelle(code) on update cascade,
  -- Quelle:Position:Charge:Lauf — dieselbe Datei nochmals hochladen trifft
  -- dieselbe Zeile und legt keine zweite Lieferung an.
  extern_id    text   not null unique,
  zeile_id     bigint references ausgang_zeile(id) on delete set null,
  ts           timestamptz not null default now()
);

create index if not exists lieferung_import_quelle on lieferung_import (quelle);

comment on table lieferung_import is
  'Welche Lieferung aus welcher Importzeile stammt. Von Hand erfasste '
  'Lieferungen stehen hier nicht — sie haben keine Kennung aus dem Perigon.';

-- ---------- 6. Rechte ------------------------------------------------------
alter table ausgang_quelle  enable row level security;
alter table ausgang_datei   enable row level security;
alter table ausgang_zeile   enable row level security;
alter table ausgang_artikel enable row level security;
alter table lieferung_import enable row level security;

do $$
declare t text;
begin
  foreach t in array array['ausgang_quelle', 'ausgang_datei', 'ausgang_zeile',
                           'ausgang_artikel', 'lieferung_import'] loop
    execute format('drop policy if exists %I on %I', t || '_lesen', t);
    execute format('drop policy if exists %I on %I', t || '_admin', t);
    -- Lesen darf jeder Angemeldete (die Auswertung zeigt die Zahlen ohnehin),
    -- schreiben nur der Betriebsleiter: der Import ist seine Arbeit.
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_lesen', t);
    execute format('create policy %I on %I for all to authenticated using (ist_admin()) with check (ist_admin())',
                   t || '_admin', t);
  end loop;
end $$;

grant select on ausgang_quelle, ausgang_datei, ausgang_zeile, ausgang_artikel,
  lieferung_import to authenticated;
grant insert, update, delete on ausgang_quelle, ausgang_datei, ausgang_zeile,
  ausgang_artikel, lieferung_import to authenticated;
grant usage on sequence ausgang_datei_id_seq, ausgang_zeile_id_seq to authenticated;

-- ---------- 7. Was die Datei über die Artikel sagt -------------------------
-- Der Vorschlag für die Zuordnung, aus den Daten selbst: Wo eine Zeile eine
-- eigene Chargennummer trägt, ist die Sorte der Charge die Sorte des Artikels.
-- Das ist eine Beobachtung, keine Vermutung — und sie wird als Vorschlag
-- ausgewiesen, bis der Betriebsleiter sie bestätigt.
create or replace view v_ausgang_artikel_vorschlag with (security_invoker = true) as
with beobachtet as (
  select z.artikel_id, z.artikel,
         count(*)::int                                   as zeilen,
         min(z.datum)                                    as von,
         max(z.datum)                                    as bis,
         sum(z.kg_charge)                                as kg,
         count(*) filter (where c.nr is not null)::int   as zeilen_mit_charge
    from ausgang_zeile z
    left join charge c on c.nr = nullif(regexp_replace(z.charge_extern, '\D', '', 'g'), '')::bigint
   group by z.artikel_id, z.artikel
), sorte_je_artikel as (
  select distinct on (z.artikel_id, z.artikel)
         z.artikel_id, z.artikel, c.sorte, count(*)::int as n
    from ausgang_zeile z
    join charge c on c.nr = nullif(regexp_replace(z.charge_extern, '\D', '', 'g'), '')::bigint
   group by z.artikel_id, z.artikel, c.sorte
   order by z.artikel_id, z.artikel, count(*) desc, c.sorte
)
select b.artikel_id, b.artikel, b.zeilen, b.von, b.bis,
       b.kg::numeric(14,1)                               as kg,
       b.zeilen_mit_charge,
       a.ist_kuerbis                                     as bestaetigt_kuerbis,
       a.sorte                                           as bestaetigte_sorte,
       (a.artikel_id is not null)                        as bestaetigt,
       -- Der Vorschlag: „Kürbis" im Namen, aber keine Verrechnung oder Arbeit.
       (lower(b.artikel_id || ' ' || b.artikel) ~ 'k(ü|u|ue)rb'
        and lower(b.artikel_id || ' ' || b.artikel) !~ '(verrechnung|arbeit|lohn|transport|miete)')
                                                         as vorschlag_kuerbis,
       s.sorte                                           as vorschlag_sorte,
       s.n                                               as vorschlag_belege
  from beobachtet b
  left join ausgang_artikel a on a.artikel_id = b.artikel_id and a.artikel = b.artikel
  left join sorte_je_artikel s on s.artikel_id = b.artikel_id and s.artikel = b.artikel;

comment on view v_ausgang_artikel_vorschlag is
  'Jeder Artikel aus den Importzeilen mit Vorschlag und Bestätigung. Die '
  'vorgeschlagene Sorte stammt aus den Zeilen, die eine eigene Chargennummer '
  'tragen — beobachtet, nicht geraten.';
grant select on v_ausgang_artikel_vorschlag to authenticated;

-- ---------- 8. Die Probe: kommt jedes Kilo genau einmal an? ---------------
-- Der Import rechnet im Browser. Diese Sicht rechnet dieselbe Grösse in der
-- Datenbank nach: Was die Position wog, muss als Lieferung wieder auftauchen —
-- einmal, nicht zweimal. Weicht es ab, ist die Ableitung auseinandergelaufen.
create or replace view v_ausgang_pruef with (security_invoker = true) as
with urteil as (
  -- Geprüft wird nur, was auch übernommen werden soll. Eine Position mit
  -- Karotten hat keine Lieferung und ist trotzdem in Ordnung.
  select artikel_id, artikel, coalesce(bestaetigt_kuerbis, vorschlag_kuerbis) as kuerbis
    from v_ausgang_artikel_vorschlag
), pos as (
  select distinct on (z.quelle, z.pos_id)
         z.quelle, z.pos_id, z.datum, z.artikel_id, z.artikel, z.kunde, z.kg_position
    from ausgang_zeile z
   order by z.quelle, z.pos_id, z.lauf_nr
), geliefert as (
  select i.quelle,
         nullif(split_part(i.extern_id, ':', 2), '')::bigint as pos_id,
         sum(l.kg) as kg
    from lieferung_import i
    join lieferung l on l.id = i.lieferung_id
   group by 1, 2
)
select p.quelle, p.pos_id, p.datum, p.artikel, p.kunde,
       p.kg_position::numeric(14,2)                        as kg_datei,
       coalesce(g.kg, 0)::numeric(14,2)                     as kg_lieferung,
       (coalesce(g.kg, 0) - p.kg_position)::numeric(14,2)   as abweichung_kg
  from pos p
  join urteil u on u.artikel_id = p.artikel_id and u.artikel = p.artikel and u.kuerbis
  left join geliefert g on g.quelle = p.quelle and g.pos_id = p.pos_id
 where abs(coalesce(g.kg, 0) - p.kg_position) > 0.05
   and p.kg_position > 0;

comment on view v_ausgang_pruef is
  'Kürbis-Positionen, deren übernommene Lieferungen nicht die Masse der Datei '
  'ergeben. Leer ist der Normalfall; jede Zeile hier ist ein Kilo zu viel oder '
  'zu wenig. Eine vergessene Position steht hier mit ihrer vollen Masse.';
grant select on v_ausgang_pruef to authenticated;

-- ---------- 9. Der Stand je Quelle ----------------------------------------
create or replace view v_ausgang_lage with (security_invoker = true) as
select q.code                                              as quelle,
       q.name,
       (select count(*) from ausgang_zeile z where z.quelle = q.code)::int          as zeilen,
       (select min(z.datum) from ausgang_zeile z where z.quelle = q.code)           as von,
       (select max(z.datum) from ausgang_zeile z where z.quelle = q.code)           as bis,
       (select max(d.ts) from ausgang_datei d where d.quelle = q.code)              as zuletzt_geladen,
       (select count(*) from ausgang_datei d where d.quelle = q.code)::int          as dateien,
       (select count(*) from lieferung_import i where i.quelle = q.code)::int      as lieferungen,
       (select coalesce(sum(l.kg), 0) from lieferung_import i
          join lieferung l on l.id = i.lieferung_id
         where i.quelle = q.code)::numeric(14,1)                                    as kg,
       (select count(*) from v_ausgang_artikel_vorschlag v
         where not v.bestaetigt and v.vorschlag_kuerbis
           and exists (select 1 from ausgang_zeile z
                        where z.quelle = q.code and z.artikel_id = v.artikel_id
                          and z.artikel = v.artikel))::int                          as artikel_offen
  from ausgang_quelle q;

comment on view v_ausgang_lage is
  'Je Quelle: wie viel eingelesen ist, bis wann, und wie viele Artikel noch '
  'auf ihre Bestätigung warten.';
grant select on v_ausgang_lage to authenticated;

-- ---------- 10. Die Auswertung merkt, dass neue Lieferungen da sind -------
-- lieferung hängt schon am Auslöser aus 0028; die Rohzeilen brauchen keinen:
-- aus ihnen rechnet keine gespeicherte Ansicht.
