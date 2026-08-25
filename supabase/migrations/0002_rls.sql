-- =====================================================================
-- 0002 — Rollen & Row Level Security
--
-- Zwei Rollen (Spec §10): Betriebsleiter (admin) und Arbeiter.
-- Leitlinie: Arbeiter dürfen alles sehen, was sie für ihre Arbeit brauchen,
-- und Messungen erfassen. Korrigieren/Löschen darf man die eigene frische
-- Zeile; alles andere macht der Betriebsleiter.
-- =====================================================================

create or replace function public.ist_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profil where id = auth.uid() and rolle = 'admin' and aktiv);
$$;

-- Wie lange darf ein Arbeiter eine eigene Erfassung noch korrigieren?
create or replace function public.korrekturfenster()
returns interval language sql immutable as $$ select interval '12 hours' $$;

-- Ist der angemeldete Benutzer an diesem Auftrag beteiligt (Eröffner oder Beigetretener)?
-- security definer, damit die Policy auf auftrag nicht rekursiv auf sich selbst prüft.
create or replace function public.ist_beteiligt(p_auftrag_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from auftrag a
                  where a.id = p_auftrag_id and a.eroeffnet_von = auth.uid())
      or exists (select 1 from auftrag_teilnehmer t
                  where t.auftrag_id = p_auftrag_id and t.profil_id = auth.uid());
$$;

alter table profil              enable row level security;
alter table gebinde             enable row level security;
alter table sorte_kaliber       enable row level security;
alter table charge              enable row level security;
alter table palette             enable row level security;
alter table auftrag             enable row level security;
alter table auftrag_teilnehmer  enable row level security;
alter table auftrag_palette     enable row level security;
alter table schimmel_messung    enable row level security;
alter table ausschuss_messung   enable row level security;
alter table verdunstung_wiegung enable row level security;
alter table marge_messung       enable row level security;
alter table sortier_lauf        enable row level security;
alter table sortier_gewicht     enable row level security;
alter table einstellung         enable row level security;

-- ---------- Profil ----------------------------------------------------
create policy profil_lesen  on profil for select to authenticated using (true);
create policy profil_eigen  on profil for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profil_admin  on profil for all to authenticated
  using (ist_admin()) with check (ist_admin());

-- Die Rolle darf nur der Betriebsleiter ändern. Als Trigger statt in der Policy:
-- eine Unterabfrage auf profil innerhalb einer profil-Policy wäre rekursiv.
create or replace function public.rolle_schuetzen()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- auth.uid() ist NULL, wenn direkt per SQL gearbeitet wird (Supabase-SQL-Editor,
  -- Migration). Das ist der vorgesehene Weg, den allerersten Betriebsleiter zu
  -- ernennen. Über die App liegt immer ein Login vor, dort greift die Prüfung.
  if new.rolle is distinct from old.rolle and auth.uid() is not null and not ist_admin() then
    raise exception 'Die Rolle darf nur der Betriebsleiter ändern.';
  end if;
  return new;
end $$;

create trigger profil_rolle_schuetzen
  before update on profil
  for each row execute function public.rolle_schuetzen();

-- ---------- Stammdaten: lesen alle, schreiben nur Admin ----------------
do $$
declare t text;
begin
  foreach t in array array['gebinde', 'sorte_kaliber', 'charge', 'palette', 'einstellung'] loop
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_lesen', t);
    execute format('create policy %I on %I for all to authenticated using (ist_admin()) with check (ist_admin())',
                   t || '_admin', t);
  end loop;
end $$;

-- ---------- Auftrag ----------------------------------------------------
create policy auftrag_lesen on auftrag for select to authenticated using (true);
create policy auftrag_eroeffnen on auftrag for insert to authenticated
  with check (eroeffnet_von = auth.uid());
-- Beitreten, Zwischenstand ändern, abschließen darf jeder Beteiligte.
-- Ändern/abschließen darf, wer am Auftrag beteiligt ist — solange er offen ist.
create policy auftrag_aendern on auftrag for update to authenticated
  using (ist_admin() or (status = 'offen' and ist_beteiligt(id)))
  with check (ist_admin() or ist_beteiligt(id));
create policy auftrag_loeschen on auftrag for delete to authenticated using (ist_admin());

create policy teilnehmer_lesen on auftrag_teilnehmer for select to authenticated using (true);
create policy teilnehmer_beitreten on auftrag_teilnehmer for insert to authenticated
  with check (profil_id = auth.uid() or ist_admin());
create policy teilnehmer_aendern on auftrag_teilnehmer for update to authenticated
  using (profil_id = auth.uid() or ist_admin());
create policy teilnehmer_admin on auftrag_teilnehmer for delete to authenticated using (ist_admin());

-- ---------- Messungen: erfassen darf jeder Angemeldete -----------------
-- Eigene frische Zeilen korrigierbar, alte nur durch den Betriebsleiter.
do $$
declare t text;
begin
  foreach t in array array['auftrag_palette', 'schimmel_messung', 'ausschuss_messung',
                           'verdunstung_wiegung', 'marge_messung'] loop
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_lesen', t);
    execute format('create policy %I on %I for insert to authenticated with check (erfasser = auth.uid() or ist_admin())',
                   t || '_erfassen', t);
    execute format('create policy %I on %I for update to authenticated using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()))',
                   t || '_korrigieren', t);
    execute format('create policy %I on %I for delete to authenticated using (ist_admin() or (erfasser = auth.uid() and ts > now() - korrekturfenster()))',
                   t || '_zuruecknehmen', t);
  end loop;
end $$;

-- ---------- Sortier-CSV: nur der Betriebsleiter lädt hoch --------------
create policy lauf_lesen on sortier_lauf for select to authenticated using (true);
create policy lauf_admin on sortier_lauf for all to authenticated
  using (ist_admin()) with check (ist_admin());

create policy gewicht_lesen on sortier_gewicht for select to authenticated using (true);
create policy gewicht_admin on sortier_gewicht for all to authenticated
  using (ist_admin()) with check (ist_admin());

-- ---------- Storage: Rohdateien ----------------------------------------
insert into storage.buckets (id, name, public)
values ('rohdaten', 'rohdaten', false)
on conflict (id) do nothing;

-- storage.objects gehört Supabase und überlebt ein Zurücksetzen des
-- public-Schemas. Deshalb hier erst aufräumen, sonst scheitert ein erneutes
-- Setup an einer Policy, die noch von vorhin herumliegt.
drop policy if exists rohdaten_lesen     on storage.objects;
drop policy if exists rohdaten_schreiben on storage.objects;

create policy rohdaten_lesen on storage.objects for select to authenticated
  using (bucket_id = 'rohdaten');
create policy rohdaten_schreiben on storage.objects for insert to authenticated
  with check (bucket_id = 'rohdaten' and ist_admin());
-- Kein update/delete: die Rohdatei bleibt unverändert (Spec §4).
