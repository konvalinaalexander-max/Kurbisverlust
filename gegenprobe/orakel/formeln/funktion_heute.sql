-- funktion: heute()
-- Der Tag, bis zu dem gerechnet wird — current_date, im Test die Einstellung heute_test (0061).

CREATE OR REPLACE FUNCTION public.heute()
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce((select nullif(wert #>> '{}', '')::date from public.einstellung
                    where schluessel = 'heute_test'),
                  public.betriebstag(now()))
$function$
