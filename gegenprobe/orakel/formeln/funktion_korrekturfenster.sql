-- funktion: korrekturfenster()

CREATE OR REPLACE FUNCTION public.korrekturfenster()
 RETURNS interval
 LANGUAGE sql
 IMMUTABLE
AS $function$ select interval '12 hours' $function$
