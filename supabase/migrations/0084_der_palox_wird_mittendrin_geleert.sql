-- =====================================================================
-- 0084 — Der Palox wird mittendrin geleert
--
-- Der Betrieb: „man beginnt vlt mit 250kg - dann wird sie viel - im
-- dashboard sagt man - palox leeren - man wird gefragt wie viel es war -
-- dann isses vlt 550kg - dann arbeitet man weiter, schliesst den auftrag
-- ab und wird wieder gefragt und dann isses vlt 150kg".
--
-- Bis hierher war ein Leeren mitten in der Arbeit das Ende jeder Messung:
-- Fiel der Stand, war die Menge der ganzen Arbeit unbekannt (0073,
-- „leer ist nicht null" — richtig, aber schade). Jetzt gibt es den Weg,
-- der die Menge bekannt hält: vor dem Leeren ablesen, leeren, danach die
-- leere Box wieder ablesen. Die zweite Ablesung ist ein NEUER ANFANG —
-- sie trägt keine Menge, sie setzt den Nullpunkt für alles Weitere.
--
--   Start        250      →  Anfang, 0
--   vor Leeren   550      →  +300
--   nach Leeren   45      →  neuer Anfang, 0     (palox_nach_leeren)
--   Ende         150      →  +105
--                               = 405 kg Faules dieser Arbeit
--
-- Das Leergewicht der leeren Box kürzt sich wie bisher in der Differenz
-- heraus — nur dass es jetzt zwei Differenzen sind statt einer.
--
-- Was bleibt: Fällt der Stand OHNE diese Ablesung, weiss niemand, wie
-- viel vor dem Leeren noch dazukam — die Menge ist unbekannt, genau wie
-- seit 0073. Die Maske sagt dann, welchen Knopf man das nächste Mal
-- drückt.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Die Spalte: eine Ablesung, die einen neuen Anfang setzt
-- ---------------------------------------------------------------------

alter table schimmel_messung
  add column if not exists palox_nach_leeren boolean not null default false;
comment on column schimmel_messung.palox_nach_leeren is
  'Die Ablesung der leeren Box direkt nach dem Leeren: keine Menge, sondern '
  'der neue Nullpunkt für die nächste Differenz (0084). palox_geleert '
  'daneben bleibt das Alte: ein gefallener Stand ohne diese Ablesung, also '
  'eine unbekannte Menge.';

-- ---------------------------------------------------------------------
-- 2. Die Differenz je Ablesung — mit Neuanfang
--
-- Dieselbe Sicht wie in 0032/0073, um eine Regel und eine Spalte länger.
-- Die Reihenfolge der Fälle ist die Sache: Der Neuanfang steht VOR dem
-- Vergleich mit dem vorigen Stand, denn nach dem Leeren ist der Stand
-- immer niedriger — das ist kein Widerspruch, das ist der Zweck.
-- ---------------------------------------------------------------------

create or replace view v_palox_stand with (security_invoker = true) as
select s.id,
       s.auftrag_id,
       s.ts,
       s.palox_stand_kg,
       s.kg,
       lag(s.palox_stand_kg) over w                                  as vorher,
       case
         when s.palox_nach_leeren                          then 0
         when lag(s.palox_stand_kg) over w is null         then 0
         when s.palox_geleert                              then null
         when s.palox_stand_kg < lag(s.palox_stand_kg) over w then null
         else s.palox_stand_kg - lag(s.palox_stand_kg) over w
       end                                                          as differenz,
       (s.palox_geleert
        or (lag(s.palox_stand_kg) over w is not null
            and s.palox_stand_kg < lag(s.palox_stand_kg) over w))
       and not s.palox_nach_leeren                                   as zwischendurch_geleert,
       palox_station(a.station)                                      as station,
       s.palox_nach_leeren                                           as nach_leeren
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
 where s.palox_stand_kg is not null and s.gemessen
window w as (partition by s.auftrag_id order by s.ts, s.id)
 order by s.auftrag_id, s.ts, s.id;
comment on view v_palox_stand is
  'Je Palox-Ablesung die Differenz zur vorigen derselben Arbeit. Die erste '
  'Ablesung und die nach dem Leeren (0084) sind Anfänge ohne Menge; ein '
  'gefallener Stand ohne angemeldetes Leeren ist eine unbekannte Differenz, '
  'keine Null (0073).';
grant select on v_palox_stand to authenticated;

-- ---------------------------------------------------------------------
-- 3. Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 84 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
