-- funktion: schimmelanteil(p_lagertage numeric, p_szenario text)

CREATE OR REPLACE FUNCTION public.schimmelanteil(p_lagertage numeric, p_szenario text DEFAULT 'mittel'::text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  with m as (select * from public.v_schimmel_modell),
  u as (select m.*, ln(greatest(p_lagertage, 1)) - m.x_mittel as u from m)
  select coalesce(
    (select least(greatest(1 - exp(-exp(least(greatest(
       u.ln_lambda_korrigiert + u.k * ln(greatest(p_lagertage, 1))
       + case p_szenario when 'unten' then -1 when 'oben' then 1 else 0 end
         * u.t_faktor * sqrt(greatest(
             u.var_achse + power(u.u, 2) * u.var_k + 2 * u.u * u.kov_achse_k, 0))
       , -40), 3))), 0), 1)
       from u where u.brauchbar and u.var_achse is not null),
    (select least(greatest(coalesce(
       case p_szenario when 'unten' then coalesce(k.unten, k.anteil_mono)
                       when 'oben'  then coalesce(k.oben,  k.anteil_mono)
                       else k.anteil_mono end, 0), 0), 1)
       from public.v_schimmel_kurve k
      where k.von <= p_lagertage and k.n > 0
      order by k.von desc limit 1),
    0)::numeric;
$function$
