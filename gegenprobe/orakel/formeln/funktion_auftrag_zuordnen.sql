-- funktion: auftrag_zuordnen(p_lauf_id bigint)

CREATE OR REPLACE FUNCTION public.auftrag_zuordnen(p_lauf_id bigint)
 RETURNS zuordnung_status
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_lauf   sortier_lauf%rowtype;
  v_fenster interval;
  v_treffer bigint[];
begin
  select * into v_lauf from sortier_lauf where id = p_lauf_id;
  if v_lauf.charge_nr is null or v_lauf.datei_zeit is null then
    update sortier_lauf set zuordnung = 'offen' where id = p_lauf_id;
    return 'offen';
  end if;

  select make_interval(hours => (wert #>> '{}')::int) into v_fenster
    from einstellung where schluessel = 'zuordnung_fenster_h';
  v_fenster := coalesce(v_fenster, interval '12 hours');

  -- 1) Dateizeit liegt innerhalb eines Auftragsintervalls.
  --    Ein nicht abgeschlossener Auftrag endet spätestens dann, wenn der
  --    nächste Auftrag derselben Charge beginnt — sonst würde ein vergessener
  --    Abschluss alle späteren Dateien an sich ziehen.
  with grenzen as (
    select a.id, a.start_ts,
           coalesce(a.ende_ts,
                    least(lead(a.start_ts) over (order by a.start_ts),
                          a.start_ts + interval '24 hours')) as bis
      from auftrag a
     where a.charge_nr = v_lauf.charge_nr
       and a.weg = 'maschine' and a.station = 'sortieren'
  )
  select array_agg(g.id) into v_treffer
    from grenzen g
   where v_lauf.datei_zeit >= g.start_ts and v_lauf.datei_zeit <= g.bis;

  -- 2) sonst: Aufträge, deren Start im Fenster um die Dateizeit liegt
  if coalesce(array_length(v_treffer, 1), 0) = 0 then
    select array_agg(a.id) into v_treffer
      from auftrag a
     where a.charge_nr = v_lauf.charge_nr
       and a.weg = 'maschine' and a.station = 'sortieren'
       and a.start_ts between v_lauf.datei_zeit - v_fenster and v_lauf.datei_zeit + v_fenster;
  end if;

  if coalesce(array_length(v_treffer, 1), 0) = 1 then
    update sortier_lauf set auftrag_id = v_treffer[1], zuordnung = 'auto' where id = p_lauf_id;
    return 'auto';
  elsif coalesce(array_length(v_treffer, 1), 0) > 1 then
    update sortier_lauf set auftrag_id = null, zuordnung = 'mehrdeutig' where id = p_lauf_id;
    return 'mehrdeutig';
  else
    update sortier_lauf set auftrag_id = null, zuordnung = 'offen' where id = p_lauf_id;
    return 'offen';
  end if;
end $function$
