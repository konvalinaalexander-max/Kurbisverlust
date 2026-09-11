-- funktion: auftrag_ende_setzen()

CREATE OR REPLACE FUNCTION public.auftrag_ende_setzen()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'abgeschlossen' and old.status is distinct from 'abgeschlossen' then
    if new.ende_ts is null or new.ende_ts < new.start_ts then
      new.ende_ts := greatest(now(), new.start_ts);
    end if;
  end if;
  return new;
end $function$
