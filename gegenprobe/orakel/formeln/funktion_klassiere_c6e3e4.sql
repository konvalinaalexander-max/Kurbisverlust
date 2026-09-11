-- funktion: klassiere(p_sorte text, p_gewicht_g integer)
-- < Verlust-Grenze = VERLUST (weggeworfen) · in einem Band = HAUPTKANAL · >= kanal_ab = NEBENKANAL (kein Verlust, separat auszuweisen).

CREATE OR REPLACE FUNCTION public.klassiere(p_sorte text, p_gewicht_g integer)
 RETURNS TABLE(klasse kuerbis_klasse, kaliber_idx integer)
 LANGUAGE sql
 STABLE
AS $function$
  select * from public.klassiere(public.sortierschema_fuer(p_sorte, null, current_date), p_gewicht_g);
$function$
