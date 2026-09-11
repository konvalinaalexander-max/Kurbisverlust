-- funktion: lieferung_import_zeilen_verbinden(p_quelle text)
-- Trägt lieferung_import.zeile_id aus der Kennung nach (Chargenzeile oder erste Zeile der Position). Läuft nach jeder Übernahme; einmal für alles Bestehende (0061).

CREATE OR REPLACE FUNCTION public.lieferung_import_zeilen_verbinden(p_quelle text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  with charge_zeilen as (
    update lieferung_import i
       set zeile_id = z.id
      from ausgang_zeile z
     where i.zeile_id is null
       and (p_quelle is null or i.quelle = p_quelle)
       and z.quelle = i.quelle
       and i.extern_id = z.quelle || ':' || z.pos_id || ':' || z.charge_extern || ':' || z.lauf_nr
     returning 1
  ), rest_zeilen as (
    update lieferung_import i
       set zeile_id = z.id
      from (select distinct on (quelle, pos_id) id, quelle, pos_id
              from ausgang_zeile order by quelle, pos_id, lauf_nr, id) z
     where i.zeile_id is null
       and (p_quelle is null or i.quelle = p_quelle)
       and z.quelle = i.quelle
       and i.extern_id = z.quelle || ':' || z.pos_id || ':rest'
     returning 1
  )
  select (select count(*) from charge_zeilen) + (select count(*) from rest_zeilen)
$function$
