-- =====================================================================
-- 0091 — Die Rückmeldung hat zwei Arten und ein Transkript
--
-- Der Betrieb: „es soll zwei Möglichkeiten geben … ist es Feedback über
-- die App oder ist es ein Kommentar zur Charge". Und: „wenn du das nächste
-- Mal daran arbeitest, dass du die Audiodateien holst und probierst zu
-- analysieren. Kannst du Audiodateien hören?"
--
-- Nein — ich lese. Darum schreibt das Handy beim Aufnehmen mit (die
-- Spracherkennung des Browsers, auf Hochdeutsch eingestellt), und das
-- Transkript steht neben der Aufnahme: `transkript`, mit `transkript_quelle`
-- 'handy' (automatisch mitgeschrieben) oder 'hand' (vom Menschen geprüft
-- oder getippt). Was der Betrieb liest, was ich lese, ist derselbe Text.
--
-- Die Art trennt, wofür die Rückmeldung ist:
--   'app'   Feedback zur App — „was hat nicht funktioniert, was fehlt" —
--           für die nächste Runde am Programm.
--   'ware'  Kommentar zur Ware dieser Arbeit — „Hagelschaden", „viel
--           Faules" — für den Betriebsleiter, an den Messungen im Dashboard.
-- Bestehende Zeilen sind 'app': Bis hierher gab es nur die eine Frage.
-- =====================================================================

alter table auftrag_rueckmeldung
  add column if not exists art text not null default 'app'
    constraint auftrag_rueckmeldung_art check (art in ('app', 'ware')),
  add column if not exists transkript text,
  add column if not exists transkript_quelle text
    constraint auftrag_rueckmeldung_transkript_quelle check (transkript_quelle is null or transkript_quelle in ('handy', 'hand'));
comment on column auftrag_rueckmeldung.art is
  'app: Feedback zur App (für die nächste Runde am Programm). ware: Kommentar zur '
  'Ware dieser Arbeit (für den Betriebsleiter, steht an den Messungen). 0091.';
comment on column auftrag_rueckmeldung.transkript is
  'Was das Handy beim Aufnehmen mitgeschrieben hat (Spracherkennung des Browsers, '
  'Hochdeutsch) — oder was der Mensch daraus gemacht hat. Der Text, den man liest, '
  'wenn man die Aufnahme nicht hören kann (0091).';
comment on column auftrag_rueckmeldung.transkript_quelle is
  'handy: automatisch mitgeschrieben, ungeprüft. hand: vom Menschen geprüft oder getippt.';
-- Ein Transkript ohne Aufnahme gibt es nicht; ein Transkript ohne Quelle auch nicht.
alter table auftrag_rueckmeldung drop constraint if exists auftrag_rueckmeldung_transkript_passt;
alter table auftrag_rueckmeldung add constraint auftrag_rueckmeldung_transkript_passt
  check ((transkript is null) = (transkript_quelle is null) and (transkript is null or audio_ref is not null));
create index if not exists auftrag_rueckmeldung_art on auftrag_rueckmeldung (art, ts desc);

-- Der Kommentar zur Ware, so wie das Dashboard ihn an die Messung hängt:
-- je Arbeit ein Text — geschrieben, sonst das Transkript.
create or replace view v_arbeit_kommentar with (security_invoker = true) as
select r.auftrag_id,
       a.charge_nr,
       string_agg(coalesce(nullif(btrim(r.text), ''), r.transkript), ' · ' order by r.ts) as text,
       bool_or(r.audio_ref is not null) as mit_aufnahme,
       max(r.ts) as ts
  from auftrag_rueckmeldung r
  join auftrag a on a.id = r.auftrag_id
 where r.art = 'ware'
   and (nullif(btrim(coalesce(r.text, '')), '') is not null or r.transkript is not null)
 group by r.auftrag_id, a.charge_nr;
comment on view v_arbeit_kommentar is
  'Je Arbeit der Kommentar zur Ware (art = ware): der geschriebene Text, sonst das '
  'Transkript der Aufnahme. Das Dashboard hängt ihn an die Messungen dieser Arbeit (0091).';
grant select on v_arbeit_kommentar to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 91 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
