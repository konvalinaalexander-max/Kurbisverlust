-- funktion: schema_stand()
-- Nummer der jüngsten eingespielten Migration. Die App vergleicht sie mit SCHEMA_ERWARTET (src/lib/version.ts) und verlangt bei Abweichung, setup.sql erneut auszuführen. Jede Migration setzt sie auf ihre eigene Nummer.

CREATE OR REPLACE FUNCTION public.schema_stand()
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$ select 70 $function$
