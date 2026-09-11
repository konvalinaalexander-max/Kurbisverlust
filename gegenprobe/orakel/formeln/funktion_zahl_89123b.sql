-- funktion: zahl(p_wert double precision, p_stellen integer, p_grenze numeric)

CREATE OR REPLACE FUNCTION public.zahl(p_wert double precision, p_stellen integer DEFAULT 2, p_grenze numeric DEFAULT '100000000000'::numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$ select zahl(p_wert::numeric, p_stellen, p_grenze) $function$
