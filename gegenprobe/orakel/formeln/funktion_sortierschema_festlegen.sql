-- funktion: sortierschema_festlegen(p_sorte text, p_kaeufer text, p_art text, p_baender jsonb, p_soll numeric, p_bemerkung text)
-- Die Fassung, nach der eine Arbeit läuft: Gilt heute schon dasselbe, kommt deren id zurück; sonst entsteht eine neue Fassung ab heute (oder die von heute wird ersetzt). Kaliber: Bänder lückenlos aufsteigend, zu klein = erstes von, zu gross = letztes bis. Kiste: Sollgewicht.

CREATE OR REPLACE FUNCTION public.sortierschema_festlegen(p_sorte text, p_kaeufer text, p_art text, p_baender jsonb DEFAULT NULL::jsonb, p_soll numeric DEFAULT NULL::numeric, p_bemerkung text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_alt  sortierschema%rowtype;
  v_id   bigint;
  v_von  int; v_bis int; v_prev int; v_i int;
  v_gleich boolean;
begin
  if not (ist_aktiv() or ist_admin()) then
    raise exception 'Nur angemeldete Arbeiter dürfen eine Fassung festlegen.';
  end if;
  if p_art not in ('kaliber', 'kiste') then
    raise exception 'Unbekannte Sortierart „%".', p_art;
  end if;
  if not exists (select 1 from sorte_kaliber where sorte = p_sorte) then
    raise exception 'Unbekannte Sorte „%".', p_sorte;
  end if;

  if p_art = 'kaliber' then
    if p_baender is null or jsonb_typeof(p_baender) <> 'array' or jsonb_array_length(p_baender) = 0 then
      raise exception 'Kaliberbänder fehlen.';
    end if;
    v_prev := null;
    for v_i in 0 .. jsonb_array_length(p_baender) - 1 loop
      v_von := (p_baender -> v_i ->> 0)::int;
      v_bis := (p_baender -> v_i ->> 1)::int;
      if v_von is null or v_bis is null or v_von < 0 or v_bis <= v_von then
        raise exception 'Band % ist nicht aufsteigend (%–% g).', v_i + 1, v_von, v_bis;
      end if;
      if v_prev is not null and v_von <> v_prev then
        raise exception 'Band % beginnt bei % g, Band % endet aber bei % g — die Bänder müssen lückenlos anschliessen.',
          v_i + 1, v_von, v_i, v_prev;
      end if;
      v_prev := v_bis;
    end loop;
    v_von := (p_baender -> 0 ->> 0)::int;
    v_bis := v_prev;
  else
    if p_soll is null or p_soll <= 0 then
      raise exception 'Sollgewicht je Kiste fehlt.';
    end if;
  end if;

  -- Gilt heute schon genau das? Dann ist es dieselbe Fassung — auch wenn es
  -- die Standardfassung ohne Käufer ist.
  select * into v_alt from sortierschema
   where id = sortierschema_fuer(p_sorte, p_kaeufer, current_date, p_art);
  if found then
    v_gleich := case when p_art = 'kaliber'
                     then v_alt.kaliber_baender = p_baender
                     else v_alt.soll_kg_pro_kiste = p_soll end;
    if v_gleich then return v_alt.id; end if;
  end if;

  -- Sonst die Fassung von heute für diese Sorte, diesen Käufer, diese Art:
  -- gibt es sie schon, wird sie ersetzt (zweimal am selben Tag ist dieselbe
  -- Einstellung); sonst entsteht sie neu. Ältere Fassungen bleiben unberührt.
  select id into v_id from sortierschema
   where sorte = p_sorte and kaeufer is not distinct from p_kaeufer
     and art = p_art and gilt_ab = current_date;
  if v_id is not null then
    update sortierschema
       set verlust_unter = case when p_art = 'kaliber' then v_von end,
           kaliber_baender = case when p_art = 'kaliber' then p_baender end,
           kanal_ab = case when p_art = 'kaliber' then v_bis end,
           soll_kg_pro_kiste = case when p_art = 'kiste' then p_soll end,
           bemerkung = coalesce(p_bemerkung, bemerkung),
           erfasser = coalesce(auth.uid(), erfasser), ts = now()
     where id = v_id;
  else
    insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender,
                               kanal_ab, soll_kg_pro_kiste, bemerkung, erfasser)
    values (p_sorte, p_kaeufer, current_date, p_art,
            case when p_art = 'kaliber' then v_von end,
            case when p_art = 'kaliber' then p_baender end,
            case when p_art = 'kaliber' then v_bis end,
            case when p_art = 'kiste' then p_soll end,
            coalesce(p_bemerkung, 'Beim Eröffnen einer Arbeit festgelegt'),
            auth.uid())
    returning id into v_id;
  end if;
  return v_id;
end $function$
