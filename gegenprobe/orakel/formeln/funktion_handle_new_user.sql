-- funktion: handle_new_user()

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profil (id, name, anonym)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'name', ''),
             nullif(split_part(new.email, '@', 1), ''),
             'Gast'),
    new.email is null
  )
  on conflict (id) do nothing;
  return new;
end $function$
