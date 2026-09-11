-- funktion: ist_beteiligt(p_auftrag_id bigint)

CREATE OR REPLACE FUNCTION public.ist_beteiligt(p_auftrag_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from auftrag a
                  where a.id = p_auftrag_id and a.eroeffnet_von = auth.uid())
      or exists (select 1 from auftrag_teilnehmer t
                  where t.auftrag_id = p_auftrag_id and t.profil_id = auth.uid());
$function$
