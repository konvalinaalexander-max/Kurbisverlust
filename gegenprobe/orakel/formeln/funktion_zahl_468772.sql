-- funktion: zahl(p_wert numeric, p_stellen integer, p_grenze numeric)
-- Rundet und lässt alles über der Grenze weg. Seit 0068 wird der **gerundete** Wert gegen die Grenze gehalten: vorher konnte ein Wert knapp darunter die Prüfung bestehen und beim Runden darüber gehoben werden, worauf numeric(14,2) ihn abwies und das ganze Neurechnen abbrach. Das Fenster war 0.005 kg breit bei 10^12 kg.

CREATE OR REPLACE FUNCTION public.zahl(p_wert numeric, p_stellen integer DEFAULT 2, p_grenze numeric DEFAULT '100000000000'::bigint)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$
  select case when p_wert is not null and abs(round(p_wert, p_stellen)) < p_grenze
              then round(p_wert, p_stellen) end
$function$
