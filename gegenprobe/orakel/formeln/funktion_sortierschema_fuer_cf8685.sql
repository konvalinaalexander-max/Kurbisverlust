-- funktion: sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date, p_art text)
-- Die Fassung einer bestimmten Art (kaliber oder kiste), die für Sorte und Käufer an einem Tag galt. Die Art wählt der Arbeiter beim Eröffnen.

CREATE OR REPLACE FUNCTION public.sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date, p_art text)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(
    -- die Fassung dieses Käufers in dieser Art, die am Stichtag galt
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is not distinct from p_kaeufer
        and art = p_art and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst die Standard-Fassung dieser Art
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is null and art = p_art and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst irgendeine Standard-Fassung dieser Art
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is null and art = p_art
      order by gilt_ab limit 1));
$function$
