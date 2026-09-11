-- funktion: auftrag_abbrechen(p_auftrag_id bigint, p_grund text)
-- Verwirft eine Arbeit. Die Erfassungen bleiben als Spur stehen, zählen aber nirgends mehr mit; zugeordnete Sortier-CSVs gehen zurück in die Warteschlange.

CREATE OR REPLACE FUNCTION public.auftrag_abbrechen(p_auftrag_id bigint, p_grund text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  update auftrag
     set abgebrochen_ts = now(),
         abbruch_grund  = p_grund,
         status         = 'abgeschlossen',
         -- greatest, nicht einfach now(): Die Prüfregel verlangt ende_ts >= start_ts.
         -- Ein Abbruch darf nie an einer Zeitverschiebung scheitern.
         ende_ts        = greatest(coalesce(ende_ts, now()), start_ts)
   where id = p_auftrag_id and abgebrochen_ts is null;

  update sortier_lauf
     set auftrag_id = null, zuordnung = 'offen'
   where auftrag_id = p_auftrag_id;
end $function$
