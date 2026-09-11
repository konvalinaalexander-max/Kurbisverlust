-- funktion: klassiere(p_schema_id bigint, p_gewicht_g integer)

CREATE OR REPLACE FUNCTION public.klassiere(p_schema_id bigint, p_gewicht_g integer)
 RETURNS TABLE(klasse kuerbis_klasse, kaliber_idx integer)
 LANGUAGE sql
 STABLE
AS $function$
  with k as (select * from public.sortierschema where id = p_schema_id),
       band as (
         select (ord - 1)::int as idx
         from k, jsonb_array_elements(k.kaliber_baender) with ordinality as b(grenzen, ord)
         where k.art = 'kaliber'
           and p_gewicht_g >= (grenzen->>0)::int
           and p_gewicht_g <  (grenzen->>1)::int
         order by ord limit 1
       )
  select case
           when (select count(*) from k) = 0                 then 'unklassiert'::public.kuerbis_klasse
           -- Kiste ab x kg: das Stückgewicht spielt keine Rolle, alles ist
           -- Hauptkanal. Zu klein und zu gross werden dort nach Augenmass
           -- erfasst, nicht aus der CSV.
           when (select art from k) = 'kiste'                then 'kaliber'::public.kuerbis_klasse
           when p_gewicht_g <  (select verlust_unter from k) then 'verlust_klein'::public.kuerbis_klasse
           when p_gewicht_g >= (select kanal_ab       from k) then 'nebenkanal'::public.kuerbis_klasse
           when (select count(*) from band) = 1               then 'kaliber'::public.kuerbis_klasse
           else 'unklassiert'::public.kuerbis_klasse
         end,
         (select idx from band);
$function$
