-- funktion: auftrag_manuell_zuordnen(p_lauf_id bigint, p_auftrag_id bigint)

CREATE OR REPLACE FUNCTION public.auftrag_manuell_zuordnen(p_lauf_id bigint, p_auftrag_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update sortier_lauf
     set auftrag_id = p_auftrag_id,
         zuordnung  = case when p_auftrag_id is null then 'offen'::zuordnung_status
                            else 'manuell'::zuordnung_status end,
         sortierschema_id = null
   where id = p_lauf_id;
  perform lauf_neu_klassieren(p_lauf_id);
end $function$
