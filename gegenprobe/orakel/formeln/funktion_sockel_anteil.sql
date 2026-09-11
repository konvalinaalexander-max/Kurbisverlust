-- funktion: sockel_anteil()

CREATE OR REPLACE FUNCTION public.sockel_anteil()
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce((select case when brauchbar then sockel else 0 end from public.v_schimmel_modell), 0);
$function$
