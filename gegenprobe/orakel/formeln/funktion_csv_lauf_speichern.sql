-- funktion: csv_lauf_speichern(p_charge_nr integer, p_datei_name text, p_roh_datei_ref text, p_roh_pruefsumme text, p_datei_zeit timestamp with time zone, p_datei_zeit_quelle text, p_reinigung jsonb, p_n_roh integer, p_n_overflow integer, p_n_klein integer, p_n_dubletten integer, p_histogramm jsonb)
-- Nimmt einen gereinigten Sortierlauf auf. Die Rohdatei liegt unverändert im Storage-Bucket "rohdaten"; p_reinigung hält fest, mit welchen Parametern gereinigt wurde, damit das Ergebnis reproduzierbar bleibt.

CREATE OR REPLACE FUNCTION public.csv_lauf_speichern(p_charge_nr integer, p_datei_name text, p_roh_datei_ref text, p_roh_pruefsumme text, p_datei_zeit timestamp with time zone, p_datei_zeit_quelle text, p_reinigung jsonb, p_n_roh integer, p_n_overflow integer, p_n_klein integer, p_n_dubletten integer, p_histogramm jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_lauf_id bigint;
  v_gueltig int;
begin
  select coalesce(sum((e->>1)::int), 0) into v_gueltig
    from jsonb_array_elements(p_histogramm) e;

  insert into sortier_lauf (charge_nr, datei_name, roh_datei_ref, roh_pruefsumme,
                            datei_zeit, datei_zeit_quelle, reinigung,
                            n_roh, n_overflow, n_klein, n_dubletten, n_gueltig)
  values (p_charge_nr, p_datei_name, p_roh_datei_ref, p_roh_pruefsumme,
          p_datei_zeit, p_datei_zeit_quelle, p_reinigung,
          p_n_roh, p_n_overflow, p_n_klein, p_n_dubletten, v_gueltig)
  returning id into v_lauf_id;

  -- Das Histogramm zunächst unklassiert ablegen; die Klasse folgt der Fassung,
  -- und die hängt am Auftrag — also erst zuordnen.
  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  select v_lauf_id, (e->>0)::int, (e->>1)::int, 'unklassiert', null
    from jsonb_array_elements(p_histogramm) e;

  perform auftrag_zuordnen(v_lauf_id);
  perform lauf_neu_klassieren(v_lauf_id);
  return v_lauf_id;
end $function$
