-- funktion: lauf_neu_klassieren(p_lauf_id bigint)

CREATE OR REPLACE FUNCTION public.lauf_neu_klassieren(p_lauf_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_schema bigint; v_n int;
begin
  -- Die Fassung: vom Auftrag, sonst vom Lauf, sonst der Standard der Sorte
  -- zum Dateidatum.
  select coalesce(a.sortierschema_id, l.sortierschema_id,
                  sortierschema_fuer(c.sorte, null, coalesce(l.datei_zeit, l.gelesen_ts)::date))
    into v_schema
    from sortier_lauf l
    join charge c on c.nr = l.charge_nr
    left join auftrag a on a.id = l.auftrag_id
   where l.id = p_lauf_id;

  update sortier_lauf set sortierschema_id = v_schema where id = p_lauf_id;

  -- Fund beim Prüfen: Die Fassung aus 0004 schrieb „from klassiere(v_sorte,
  -- g.gewicht_g)" — ein Verweis auf die Zieltabelle in der FROM-Liste, den
  -- Postgres ablehnt („invalid reference to FROM-clause entry"). Die Funktion
  -- wurde nie aufgerufen, kein Test hat sie je ausgeführt, und das README
  -- empfahl sie dem Betriebsleiter nach jeder Grenzen-Änderung. Sie hätte
  -- jedes Mal mit einem Fehler geendet.
  with neu as (
    select sg.gewicht_g, k.klasse, k.kaliber_idx
      from sortier_gewicht sg
      cross join lateral klassiere(v_schema, sg.gewicht_g) k
     where sg.lauf_id = p_lauf_id
  )
  update sortier_gewicht g
     set klasse = neu.klasse, kaliber_idx = neu.kaliber_idx
    from neu
   where g.lauf_id = p_lauf_id and g.gewicht_g = neu.gewicht_g;

  get diagnostics v_n = row_count;
  return v_n;
end $function$
