-- funktion: verlust_ranking(p_sorte text, p_schlag text, p_charge integer)
-- Alle Ströme mit Bereich, wahlweise je Charge, Sorte oder Schlag — aus erg_verlust gelesen, nicht gerechnet (0061). Eine Kombination der Filter gibt es nicht mehr.

CREATE OR REPLACE FUNCTION public.verlust_ranking(p_sorte text DEFAULT NULL::text, p_schlag text DEFAULT NULL::text, p_charge integer DEFAULT NULL::integer)
 RETURNS TABLE(strom text, buch text, kg numeric, kg_unten numeric, kg_oben numeric, kg_beobachtet numeric, kg_projiziert numeric, kg_extrapoliert numeric, kg_erwartet numeric, koeff_n_min integer, streuung_kg numeric, df integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select e.strom, e.buch, e.kg, e.kg_unten, e.kg_oben, e.kg_beobachtet, e.kg_projiziert, e.kg_extrapoliert,
         e.kg_erwartet, e.koeff_n_min, e.streuung_kg, e.df
    from public.erg_verlust e
   where e.gruppe = case when p_charge is not null then 'charge'
                         when p_sorte  is not null then 'sorte'
                         when p_schlag is not null then 'schlag'
                         else 'gesamt' end
     and e.schluessel = case when p_charge is not null then p_charge::text
                             when p_sorte  is not null then p_sorte
                             when p_schlag is not null then p_schlag
                             else '' end
   order by e.kg desc nulls last
$function$
