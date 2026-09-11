-- funktion: sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date)
-- Die Fassung, die für Sorte und Käufer an einem Tag galt. Ohne passende Käufer-Fassung gilt der Standard der Sorte.

CREATE OR REPLACE FUNCTION public.sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  select public.sortierschema_fuer(p_sorte, p_kaeufer, p_datum, 'kaliber');
$function$
