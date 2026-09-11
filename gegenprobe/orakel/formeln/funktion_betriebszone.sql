-- funktion: betriebszone()
-- Die Zeitzone, in der der Betrieb steht. Einstellung „zeitzone", Rückfall Europe/Zurich.

CREATE OR REPLACE FUNCTION public.betriebszone()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(nullif((select wert #>> '{}' from public.einstellung
                           where schluessel = 'zeitzone'), ''), 'Europe/Zurich')
$function$
