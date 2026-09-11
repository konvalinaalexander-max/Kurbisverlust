-- funktion: anteil_plausibel(p_anteil numeric)

CREATE OR REPLACE FUNCTION public.anteil_plausibel(p_anteil numeric)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select p_anteil is not null and p_anteil >= 0 and p_anteil <= 0.5;
$function$
