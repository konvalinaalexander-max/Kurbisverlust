-- =====================================================================
-- 0085 — Die Rückmeldung am Ende jeder Arbeit
--
-- Der Betrieb: „am ende eines auftrags - egal welcher … vor dem finalem
-- abschliessen soll die app fragen ob alles gut lief oder
-- verbesserungswünsche - und dann soll es ein textfeld haben - aber auch
-- grosser knopf mit mikrofon symbol".
--
-- Eine Rückmeldung ist Text, eine Sprachaufnahme, oder beides — nie
-- nichts: Wer nichts sagen will, geht weiter, und es entsteht keine Zeile.
-- Die Aufnahme liegt als Datei im Bucket `rueckmeldungen`, die Zeile hier
-- zeigt auf sie. Warum Supabase Storage und nicht das Repository: Ein
-- Repository ist Quelltext, kein Ablageort für Betriebsdaten — und eine
-- Sprachaufnahme über einen Arbeitstag gehört zu den Messungen dieses
-- Tages, nicht zum Programm. Dort, wo auch die Rohdateien der
-- Sortiermaschine liegen, liegt sie richtig.
--
-- Die Rückmeldung wird nicht ausgewertet. Sie ist eine Stimme aus der
-- Halle für den Betriebsleiter, und sie steht dort, wo er die fertigen
-- Arbeiten ansieht.
-- =====================================================================

create table if not exists auftrag_rueckmeldung (
  id             bigserial primary key,
  auftrag_id     bigint not null references auftrag(id) on delete cascade,
  text           text,
  audio_ref      text,
  audio_typ      text,
  audio_sekunden int check (audio_sekunden is null or audio_sekunden >= 0),
  erfasser       uuid not null default auth.uid() references profil(id),
  ts             timestamptz not null default now(),
  -- Eine leere Rückmeldung gibt es nicht — wer nichts sagt, hinterlässt keine Zeile.
  constraint auftrag_rueckmeldung_nicht_leer
    check (nullif(btrim(coalesce(text, '')), '') is not null or audio_ref is not null)
);
comment on table auftrag_rueckmeldung is
  'Was die Person, die eine Arbeit abgeschlossen hat, dazu zu sagen hatte: '
  'geschrieben, gesprochen (Datei im Bucket rueckmeldungen) oder beides. Wird '
  'nicht ausgewertet — gelesen und angehört (0085).';
comment on column auftrag_rueckmeldung.audio_ref is
  'Pfad der Aufnahme im Bucket rueckmeldungen: <auftrag_id>/<zeit>.<endung>.';
comment on column auftrag_rueckmeldung.audio_sekunden is
  'Dauer der Aufnahme, wie die App sie beim Aufnehmen gemessen hat.';
create index if not exists auftrag_rueckmeldung_auftrag on auftrag_rueckmeldung (auftrag_id, ts desc);

alter table auftrag_rueckmeldung enable row level security;
drop policy if exists rueckmeldung_lesen    on auftrag_rueckmeldung;
drop policy if exists rueckmeldung_erfassen on auftrag_rueckmeldung;
drop policy if exists rueckmeldung_aendern  on auftrag_rueckmeldung;
drop policy if exists rueckmeldung_loeschen on auftrag_rueckmeldung;
create policy rueckmeldung_lesen on auftrag_rueckmeldung for select to authenticated using (true);
create policy rueckmeldung_erfassen on auftrag_rueckmeldung for insert to authenticated
  with check ((erfasser = auth.uid() and ist_aktiv()) or ist_admin());
create policy rueckmeldung_aendern on auftrag_rueckmeldung for update to authenticated using (ist_admin());
create policy rueckmeldung_loeschen on auftrag_rueckmeldung for delete to authenticated using (ist_admin());
grant select, insert, update, delete on auftrag_rueckmeldung to authenticated;
grant usage, select on sequence auftrag_rueckmeldung_id_seq to authenticated;

-- Auch die Rückmeldung ist eine Erfassung: jede Änderung ins Journal (0072).
drop trigger if exists auftrag_rueckmeldung_journal on auftrag_rueckmeldung;
create trigger auftrag_rueckmeldung_journal after insert or update or delete on auftrag_rueckmeldung
  for each row execute function erfassung_journal_schreiben();

-- ---------- Storage: die Aufnahmen ---------------------------------------
insert into storage.buckets (id, name, public)
values ('rueckmeldungen', 'rueckmeldungen', false)
on conflict (id) do nothing;

drop policy if exists rueckmeldungen_lesen     on storage.objects;
drop policy if exists rueckmeldungen_schreiben on storage.objects;
-- Lesen darf jeder Angemeldete; schreiben jeder aktive Arbeiter — anders als
-- bei den Rohdaten, die nur der Betriebsleiter hochlädt. Kein update/delete:
-- eine Aufnahme wird nicht überschrieben.
create policy rueckmeldungen_lesen on storage.objects for select to authenticated
  using (bucket_id = 'rueckmeldungen');
create policy rueckmeldungen_schreiben on storage.objects for insert to authenticated
  with check (bucket_id = 'rueckmeldungen' and (ist_aktiv() or ist_admin()));

-- ---------------------------------------------------------------------
-- Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 85 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
