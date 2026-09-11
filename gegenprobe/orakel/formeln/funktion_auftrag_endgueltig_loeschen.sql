-- funktion: auftrag_endgueltig_loeschen(p_auftrag_id bigint)

CREATE OR REPLACE FUNCTION public.auftrag_endgueltig_loeschen(p_auftrag_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if not ist_admin() then
    raise exception 'Endgültig löschen darf nur der Betriebsleiter.';
  end if;

  delete from verdunstung_wiegung where auftrag_id = p_auftrag_id;
  delete from ausgang_wiegung      where auftrag_id = p_auftrag_id;
  update sortier_lauf set auftrag_id = null, zuordnung = 'offen'
   where auftrag_id = p_auftrag_id;
  delete from auftrag where id = p_auftrag_id;
end $function$
