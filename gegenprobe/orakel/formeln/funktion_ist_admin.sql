-- funktion: ist_admin()

CREATE OR REPLACE FUNCTION public.ist_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from profil where id = auth.uid() and rolle = 'admin' and aktiv);
$function$
