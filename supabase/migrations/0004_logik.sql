-- =====================================================================
-- 0004 — Klassierung, CSV-Aufnahme, Auftrags-Zuordnung
--
-- Arbeitsteilung (Spec §12): Parsen und Reinigen der CSV laufen im Browser
-- (die Dubletten-Regel braucht die Zeilenreihenfolge). Klassiert wird hier
-- in der Datenbank — so gibt es genau eine Wahrheit für die Kaliber-Grenzen,
-- und eine Änderung der Grenzen lässt sich auf alte Läufe neu anwenden.
-- =====================================================================

-- ---------- Klassierung eines Einzelgewichts (Spec §6) -------------------
create or replace function klassiere(p_sorte text, p_gewicht_g int)
returns table (klasse kuerbis_klasse, kaliber_idx int)
language sql stable as $$
  with k as (select * from public.sorte_kaliber where sorte = p_sorte),
       band as (
         select (ord - 1)::int as idx
         from k, jsonb_array_elements(k.kaliber_baender) with ordinality as b(grenzen, ord)
         where p_gewicht_g >= (grenzen->>0)::int
           and p_gewicht_g <  (grenzen->>1)::int
         order by ord limit 1
       )
  select case
           when (select count(*) from k) = 0            then 'unklassiert'::public.kuerbis_klasse
           when p_gewicht_g <  (select verlust_unter from k) then 'verlust_klein'::public.kuerbis_klasse
           when p_gewicht_g >= (select kanal_ab       from k) then 'nebenkanal'::public.kuerbis_klasse
           when (select count(*) from band) = 1          then 'kaliber'::public.kuerbis_klasse
           else 'unklassiert'::public.kuerbis_klasse
         end,
         (select idx from band);
$$;

comment on function klassiere is
  '< Verlust-Grenze = VERLUST (weggeworfen) · in einem Band = HAUPTKANAL · '
  '>= kanal_ab = NEBENKANAL (kein Verlust, separat auszuweisen).';

-- ---------- Einen Lauf neu klassieren (nach Grenzen-Änderung) -------------
create or replace function lauf_neu_klassieren(p_lauf_id bigint)
returns int language plpgsql as $$
declare v_sorte text; v_n int;
begin
  select c.sorte into v_sorte
    from sortier_lauf l join charge c on c.nr = l.charge_nr
   where l.id = p_lauf_id;

  update sortier_gewicht g
     set klasse = k.klasse, kaliber_idx = k.kaliber_idx
    from klassiere(v_sorte, g.gewicht_g) k
   where g.lauf_id = p_lauf_id;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------- Zuordnung CSV-Lauf → Auftrag (Spec §5) ------------------------
-- Zuerst über Zeit-Enthaltensein im Auftragsintervall, sonst über die
-- nächstliegende Startzeit innerhalb des Fensters. Nur eindeutige Treffer
-- werden automatisch gesetzt; alles andere landet in der Admin-Warteschlange.
create or replace function auftrag_zuordnen(p_lauf_id bigint)
returns zuordnung_status language plpgsql as $$
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
end $$;

create or replace function auftrag_manuell_zuordnen(p_lauf_id bigint, p_auftrag_id bigint)
returns void language sql as $$
  update sortier_lauf
     set auftrag_id = p_auftrag_id,
         zuordnung  = case when p_auftrag_id is null then 'offen'::zuordnung_status
                            else 'manuell'::zuordnung_status end
   where id = p_lauf_id;
$$;

-- ---------- CSV-Lauf aufnehmen -------------------------------------------
-- Der Browser liefert das bereits gereinigte Histogramm [[gewicht_g, anzahl], …]
-- plus die Reinigungs-Kennzahlen. Hier wird klassiert und zugeordnet.
-- Läuft als Invoker → die RLS-Policy „nur Betriebsleiter" greift.
create or replace function csv_lauf_speichern(
  p_charge_nr         int,
  p_datei_name        text,
  p_roh_datei_ref     text,
  p_roh_pruefsumme    text,
  p_datei_zeit        timestamptz,
  p_datei_zeit_quelle text,
  p_reinigung         jsonb,
  p_n_roh             int,
  p_n_overflow        int,
  p_n_klein           int,
  p_n_dubletten       int,
  p_histogramm        jsonb
) returns bigint language plpgsql as $$
declare
  v_lauf_id bigint;
  v_sorte   text;
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

  select sorte into v_sorte from charge where nr = p_charge_nr;

  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  select v_lauf_id, (e->>0)::int, (e->>1)::int, k.klasse, k.kaliber_idx
    from jsonb_array_elements(p_histogramm) e
    cross join lateral klassiere(v_sorte, (e->>0)::int) k;

  perform auftrag_zuordnen(v_lauf_id);
  return v_lauf_id;
end $$;

comment on function csv_lauf_speichern is
  'Nimmt einen gereinigten Sortierlauf auf. Die Rohdatei liegt unverändert im '
  'Storage-Bucket "rohdaten"; p_reinigung hält fest, mit welchen Parametern '
  'gereinigt wurde, damit das Ergebnis reproduzierbar bleibt.';
