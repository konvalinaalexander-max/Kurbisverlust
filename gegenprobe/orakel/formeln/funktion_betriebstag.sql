-- funktion: betriebstag(p_ts timestamp with time zone)
-- Der Kalendertag eines Zeitpunkts in der Zone des Betriebs — nicht der in UTC. Überall dort zu benutzen, wo aus einem Zeitstempel ein Tag wird, der mit einem abgetippten Datum verrechnet wird.

CREATE OR REPLACE FUNCTION public.betriebstag(p_ts timestamp with time zone)
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select (p_ts at time zone public.betriebszone())::date
$function$
