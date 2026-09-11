-- funktion: auswertung_veraltet()

CREATE OR REPLACE FUNCTION public.auswertung_veraltet()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update auswertung_stand set geaendert_ts = now() where id = 1;
  return null;
end $function$
