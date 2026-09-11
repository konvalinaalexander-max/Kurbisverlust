-- funktion: palox_letzter_stand(p_station station)
-- Was zuletzt auf der Palox-Waage DIESER Station stand. Die Eingabemaske zieht das vom neuen Stand ab, damit niemand im Kopf rechnen muss.

CREATE OR REPLACE FUNCTION public.palox_letzter_stand(p_station station)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select s.palox_stand_kg
    from public.schimmel_messung s
    join public.auftrag a on a.id = s.auftrag_id
   where s.palox_stand_kg is not null and s.gemessen
     and public.palox_station(a.station) = public.palox_station(p_station)
   order by s.ts desc, s.id desc limit 1;
$function$
