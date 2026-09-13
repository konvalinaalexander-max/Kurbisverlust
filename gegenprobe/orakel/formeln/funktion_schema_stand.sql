-- funktion: schema_stand()
-- Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).

CREATE OR REPLACE FUNCTION public.schema_stand()
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$ select 71 $function$
