-- funktion: ausschuss_netto_setzen()
-- Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara. Fehlt eine der drei Angaben, gibt es kein Netto: die Zeile bleibt stehen, gemessen wird false, und v_plausibilitaet meldet „Ausschuss ohne Tara" (0066).

CREATE OR REPLACE FUNCTION public.ausschuss_netto_setzen()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric;
begin
  if new.brutto_kg is not null then
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    v_netto := new.brutto_kg - new.kisten * v_tara_kiste - v_tara_palette;
    if v_netto is null then
      -- Ohne Kistenzahl oder ohne hinterlegte Tara gibt es kein Netto (0066).
      new.gemessen := false;
    else
      new.kg := greatest(round(v_netto), 0);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $function$
