-- funktion: schimmel_netto_setzen()
-- Setzt kg auf das Netto aus Brutto, Kistenzahl und hinterlegter Tara (die Palettentara nur, wenn die Palette mitgewogen wurde). Fehlt eine nötige Angabe, gibt es kein Netto: die Zeile bleibt stehen und gemessen wird false — v_schimmel_menge liest nur Gemessenes (0066).

CREATE OR REPLACE FUNCTION public.schimmel_netto_setzen()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare v_tara_kiste numeric; v_tara_palette numeric; v_netto numeric;
begin
  if new.brutto_kg is not null then
    if new.palox_stand_kg is not null then
      raise exception 'Eine Messung ist entweder eine Palox-Ablesung oder eine Kistenwägung, nicht beides.';
    end if;
    select g.tara_kg_pro_kiste, g.tara_kg_palette
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    -- Ohne Palette braucht es die Palettentara nicht — dann ist sie 0 und
    -- nicht unbekannt. Die Kistentara braucht es immer.
    v_netto := new.brutto_kg - new.kisten * v_tara_kiste
             - case when new.mit_palette then v_tara_palette else 0 end;
    if v_netto is null then
      new.gemessen := false;
    else
      new.kg := greatest(round(v_netto), 0);
      new.gemessen := true;
    end if;
  end if;
  return new;
end $function$
