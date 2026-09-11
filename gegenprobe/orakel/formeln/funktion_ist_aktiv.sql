-- funktion: ist_aktiv()

CREATE OR REPLACE FUNCTION public.ist_aktiv()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from profil where id = auth.uid() and aktiv);
$function$
