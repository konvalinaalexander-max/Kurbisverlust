-- funktion: auswertung_schritt(p_schritt integer)
-- Ein Schritt des Neurechnens. Nur für den Betriebsleiter — oder ohne Anmeldung, also für die Prüfstände als Eigentümer. Ein Lauf sperrt jede gespeicherte Ansicht für rund drei Sekunden (0068).

CREATE OR REPLACE FUNCTION public.auswertung_schritt(p_schritt integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
begin
  -- Wer ohne Anmeldung kommt, ist der Eigentümer der Datenbank: die
  -- Prüfstände, die Simulation, das Einspielen der Demodaten. Wer angemeldet
  -- ist, muss Betriebsleiter sein — ein Lauf sperrt für rund drei Sekunden
  -- jede gespeicherte Ansicht.
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.'
      using errcode = '42501';
  end if;
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'mv_schimmel_punkte', 'mv_schimmel_modell',
                       'erg_punkte', 'erg_modell', 'erg_kurve', 'erg_selektion',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_ueberfuellung', 'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_verlauf', 'erg_bilanz', 'erg_marge',
                       'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  -- Schritt 1 bringt zuerst die Statistik der Rohtabellen auf Stand. Nach
  -- einem grossen Import (Saisonstart, Warenausgang, Demo) schätzt der Planer
  -- sonst mit Zahlen von vorher und wählt Pläne, die um Grössenordnungen
  -- danebenliegen: gemessen 33 Sekunden für Schritt 2, wo er mit frischer
  -- Statistik 1.1 braucht. Das Analysieren aller Rohtabellen kostet auf der
  -- Demo 0.2 Sekunden — der beste Handel im ganzen Rechenwerk.
  if p_schritt = 1 then
    for v_name in
      select c.relname
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r'
       order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
  end if;

  foreach v_name in array v_namen loop
    execute format('refresh materialized view %I', v_name);
    execute format('analyze %I', v_name);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),   -- nicht now(): das wäre der Beginn der Transaktion
           dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif p_schritt = 1 then
    update auswertung_stand
       set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  else
    update auswertung_stand
       set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5);
end $function$
