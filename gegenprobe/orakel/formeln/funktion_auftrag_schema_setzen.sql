-- funktion: auftrag_schema_setzen()

CREATE OR REPLACE FUNCTION public.auftrag_schema_setzen()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.sortierschema_id is null and new.station = 'waschen' then
    select l.sortierschema_id into new.sortierschema_id
      from public.sortier_lauf l
      join public.auftrag a on a.id = l.auftrag_id
     where l.charge_nr = new.charge_nr and l.sortierschema_id is not null
     order by coalesce(l.datei_zeit, l.gelesen_ts) desc limit 1;
  end if;
  if new.sortierschema_id is null then
    select public.sortierschema_fuer(c.sorte, new.kaeufer, new.start_ts::date, 'kaliber')
      into new.sortierschema_id
      from public.charge c where c.nr = new.charge_nr;
  end if;
  return new;
end $function$
