-- funktion: rolle_schuetzen()

CREATE OR REPLACE FUNCTION public.rolle_schuetzen()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- auth.uid() ist NULL, wenn direkt per SQL gearbeitet wird (Supabase-SQL-Editor,
  -- Migration). Das ist der vorgesehene Weg, den allerersten Betriebsleiter zu
  -- ernennen. Über die App liegt immer ein Login vor, dort greift die Prüfung.
  if new.rolle is distinct from old.rolle and auth.uid() is not null and not ist_admin() then
    raise exception 'Die Rolle darf nur der Betriebsleiter ändern.';
  end if;
  return new;
end $function$
