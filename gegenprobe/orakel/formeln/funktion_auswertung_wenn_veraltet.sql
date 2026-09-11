-- funktion: auswertung_wenn_veraltet()
-- Rechnet neu, wenn seit der letzten Berechnung etwas geschrieben wurde — sonst nichts. Für einen Zeitplan (pg_cron), damit die App fertige Zahlen vorfindet (0061).

CREATE OR REPLACE FUNCTION public.auswertung_wenn_veraltet()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
declare v_stand auswertung_stand;
begin
  select * into v_stand from auswertung_stand where id = 1;
  if v_stand.berechnet_ts is not null and v_stand.geaendert_ts <= v_stand.berechnet_ts then
    return false;
  end if;
  perform auswertung_aktualisieren();
  return true;
end $function$
