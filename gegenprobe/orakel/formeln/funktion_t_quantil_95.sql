-- funktion: t_quantil_95(p_df integer)
-- Zweiseitiges 95-%-Quantil der t-Verteilung. Bei wenigen unabhängigen Gruppen ist 1.96 zu optimistisch.

CREATE OR REPLACE FUNCTION public.t_quantil_95(p_df integer)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when p_df is null or p_df < 1 then 12.706
    when p_df >= 30 then 1.960
    else (array[12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306,
                2.262, 2.228, 2.201, 2.179, 2.160, 2.145, 2.131, 2.120,
                2.110, 2.101, 2.093, 2.086, 2.080, 2.074, 2.069, 2.064,
                2.060, 2.056, 2.052, 2.048, 2.045])[p_df]
  end::numeric;
$function$
