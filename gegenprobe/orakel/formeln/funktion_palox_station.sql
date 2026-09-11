-- funktion: palox_station(p_station station)
-- Welcher Palox zu einer Station gehört: die Waschstrasse (waschen und waschen_sortieren) teilt sich einen, die Sortiermaschine hat ihren eigenen (0060).

CREATE OR REPLACE FUNCTION public.palox_station(p_station station)
 RETURNS station
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  -- voll qualifiziert: die Funktion wird in Sichten eingebettet und muss auch
  -- mit leerem Suchpfad rechnen (Prüfblock „Suchpfad")
  select case when p_station = 'waschen_sortieren'::public.station then 'waschen'::public.station else p_station end
$function$
