-- funktion: palox_tara_kg()

CREATE OR REPLACE FUNCTION public.palox_tara_kg()
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce((select (wert #>> '{}')::numeric from public.einstellung
                    where schluessel = 'palox_tara_kg'), 0);
$function$
