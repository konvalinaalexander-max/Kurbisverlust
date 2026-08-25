-- =====================================================================
-- 0009 — Arbeiter ohne Konto (anonyme Anmeldung)
--
-- Arbeiter sollen per QR-Code in die App kommen und sofort loslegen —
-- ohne Mail, ohne Passwort. Sie tippen einmal ihren Namen, mehr nicht.
-- Der Betriebsleiter behält seinen echten Login fürs Dashboard.
--
-- Technisch nutzen wir Supabase "Anonymous sign-ins": Auch ein anonymer
-- Nutzer bekommt eine echte, gerätefeste Identität (auth.uid()). Damit
-- funktioniert die gesamte Rechte- und Erfasser-Logik unverändert weiter —
-- eine anonyme Anmeldung ist trotzdem an genau eine Person (den Namen) und
-- ein Gerät gebunden.
--
-- WICHTIG, EINMALIG IM SUPABASE-DASHBOARD: Authentication → Sign In / Providers
-- → Anonymous sign-ins aktivieren. Sonst lehnt Supabase die Anmeldung ab.
--
-- Diese Datei ist gefahrlos einzeln einspielbar (alles "if not exists" bzw.
-- "create or replace").
-- =====================================================================

-- Kennzeichnet Geräte-Anmeldungen ohne Konto — nur zur Anzeige für den
-- Betriebsleiter und für eine spätere Aufräum-Möglichkeit.
alter table profil add column if not exists anonym boolean not null default false;

-- Beim Anlegen eines neuen Nutzers das Profil füllen. Neu gegenüber 0001:
--   * anonyme Nutzer haben keine E-Mail → als anonym markieren
--   * leerer Metadaten-Name zählt wie kein Name
--   * letzte Rückfallebene "Gast", damit die Anmeldung nie an einem
--     fehlenden Namen scheitert (NOT NULL)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profil (id, name, anonym)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'name', ''),
             nullif(split_part(new.email, '@', 1), ''),
             'Gast'),
    new.email is null
  )
  on conflict (id) do nothing;
  return new;
end $$;
