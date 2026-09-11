-- funktion: auswertung_aktualisieren()
-- Alle fünf Schritte des Neurechnens nacheinander. Nur für den Betriebsleiter — oder ohne Anmeldung, also für die Prüfstände als Eigentümer (0068).

CREATE OR REPLACE FUNCTION public.auswertung_aktualisieren()
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
declare i int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.'
      using errcode = '42501';
  end if;
  for i in 1..5 loop
    perform auswertung_schritt(i);
  end loop;
  return now();
end $function$
