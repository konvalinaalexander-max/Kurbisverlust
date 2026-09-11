-- funktion: stichtag()
-- Bis wohin die Prognose reicht: das Saisonende aus den Einstellungen, mindestens heute (0061).

CREATE OR REPLACE FUNCTION public.stichtag()
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select greatest((select nullif(wert #>> '{}', '')::date from public.einstellung where schluessel = 'saison_ende'),
                  public.heute())
$function$
