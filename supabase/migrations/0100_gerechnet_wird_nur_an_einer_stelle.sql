-- =====================================================================
-- 0100 — Gerechnet wird nur an einer Stelle
--
-- 28. September, 12:45: Der Chip sagte „Zeitplan rechnet nicht" (bis 0098
-- zu Unrecht), also rechnete die App bei jedem Öffnen selbst — mit den
-- echten Daten gut zwei Minuten je Lauf. Der Betriebsleiter lud die Seite
-- mehrmals neu, dazu lief der Zeitplan nach einer Bereinigung: mehrere
-- Rechnungen zugleich, alle auf denselben Ansichten, und die Datenbank
-- antwortete eine halbe Stunde lang niemandem mehr (522/504).
--
-- Darum: Schritt 1 besetzt den Platz (rechnet_seit), und ein zweiter Aufruf
-- bekommt „wartet" zurück statt mitzurechnen — die App zeigt dann „wird
-- gerade erneuert" und lädt nach, wenn der Stand steht. Je Schritt zusätzlich
-- eine Sperre für die Dauer des Aufrufs. Ein Rest, der älter als 15 Minuten
-- ist, gilt als abgebrochener Lauf und wird übernommen (0095: länger rechnet
-- kein Lauf). Der Zeitplan-Weg (auswertung_wenn_veraltet) hört auf „wartet"
-- und meldet, dass nichts zu tun war — der nächste Takt sieht nach.
-- =====================================================================

create or replace function auswertung_schritt_intern(p_schritt integer, p_nebenlaeufig boolean)
returns jsonb language plpgsql security definer set search_path = public set jit = off as $$
declare
  v_start timestamptz := clock_timestamp();
  v_namen text[];
  v_name text;
  v_titel text;
  v_ausdruck text;
  v_eindeutig boolean;
  v_gefuellt boolean;
  v_seit timestamptz;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- 0100: Gerechnet wird nur an einer Stelle. Schritt 1 besetzt den Platz
  -- (rechnet_seit), und wer ihn besetzt findet — jünger als die Zeitgrenze —,
  -- rechnet nicht mit, sondern bekommt „wartet" zurück. Am 28. September
  -- rechneten mehrere Fenster und der Zeitplan gleichzeitig, jede Rechnung
  -- gut zwei Minuten, und die Datenbank antwortete eine halbe Stunde niemandem.
  -- Ein Rest, der älter als 15 Minuten ist (0095: länger rechnet kein Lauf),
  -- ist ein abgebrochener Lauf und wird übernommen.
  if p_schritt = 1 then
    update auswertung_stand
       set rechnet_seit = clock_timestamp()
     where id = 1 and (rechnet_seit is null or rechnet_seit < clock_timestamp() - interval '15 minutes')
    returning rechnet_seit into v_seit;
    if v_seit is null then
      select rechnet_seit into v_seit from auswertung_stand where id = 1;
      return jsonb_build_object('schritt', 1, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                                'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true, 'rechnet_seit', v_seit);
    end if;
  end if;
  -- Und je Schritt eine Sperre für die Dauer des Aufrufs: zwei Erneuerungen
  -- derselben Ansicht zur selben Sekunde gibt es nicht — wer sie trifft, wartet.
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                              'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true,
                              'rechnet_seit', (select rechnet_seit from auswertung_stand where id = 1));
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
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
    when 4 then
      v_titel := 'Ergebnis';
      v_namen := array['erg_verlust', 'erg_prognose', 'erg_wohin', 'erg_verlauf', 'erg_bilanz',
                       'erg_marge', 'erg_massenbilanz', 'erg_naechste_charge', 'erg_datenlage',
                       'erg_marge_wiegung', 'erg_marge_charge'];
    when 5 then
      v_titel := 'Befunde';
      v_namen := array['erg_plausibilitaet', 'erg_datenqualitaet'];
    else
      raise exception 'auswertung_schritt: Schritt % gibt es nicht (1 bis 5).', p_schritt;
  end case;

  if p_schritt = 1 then
    for v_name in
      select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname
    loop
      execute format('analyze %I', v_name);
    end loop;
  end if;

  foreach v_name in array v_namen loop
    v_eindeutig := false;
    if p_nebenlaeufig then
      -- Nebenläufig geht nur mit eindeutigem Index und nur, wenn die Ansicht
      -- schon einmal gefüllt wurde. Den Index legt der Lauf bei Bedarf an;
      -- gelingt das nicht (eine doppelte Zeile), bleibt es beim normalen Weg.
      select s.ausdruck into v_ausdruck from auswertung_schluessel() s where s.sicht = v_name;
      select c.relispopulated into v_gefuellt from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_name;
      if v_ausdruck is not null and coalesce(v_gefuellt, false) then
        begin
          -- Ein Index aus Spalten muss es sein: Die Ausdrucksindizes älterer
          -- Migrationen (coalesce …) zählen für Postgres hier nicht.
          if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indrelid
                          where c.relname = v_name and i.indisunique and i.indexprs is null and i.indpred is null) then
            execute format('create unique index %I on %I (%s) nulls not distinct', v_name || '_eindeutig', v_name, v_ausdruck);
          end if;
          v_eindeutig := true;
        exception when others then
          raise notice 'auswertung_schritt: % bekommt keinen eindeutigen Index (%) — wird normal erneuert', v_name, sqlerrm;
        end;
      end if;
    end if;
    if v_eindeutig then
      begin
        execute format('refresh materialized view concurrently %I', v_name);
      exception when others then
        raise notice 'auswertung_schritt: % nicht nebenläufig erneuert (%) — normal erneuert', v_name, sqlerrm;
        execute format('refresh materialized view %I', v_name);
      end;
    else
      execute format('refresh materialized view %I', v_name);
    end if;
    execute format('analyze %I', v_name);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           rechnet_seit = null,
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
    'fertig', p_schritt = 5, 'nebenlaeufig', p_nebenlaeufig, 'wartet', false);
end $$;
comment on function auswertung_schritt_intern(integer, boolean) is
  'Ein Schritt des Neurechnens (0078), wahlweise nebenläufig (0095): dann bleibt jede '
  'Ansicht lesbar, bis ihre neue Fassung steht. Seit 0100 rechnet nur einer: ein zweiter '
  'Aufruf bekommt wartet = true. Nur für den Betriebsleiter oder ohne Anmeldung.';
revoke execute on function auswertung_schritt_intern(integer, boolean) from public;
grant execute on function auswertung_schritt_intern(integer, boolean) to authenticated;

create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand; i int; v_erg jsonb;
begin
  update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;
  select * into v_stand from auswertung_stand where id = 1;
  if v_stand.berechnet_ts is not null and v_stand.geaendert_ts <= v_stand.berechnet_ts then
    return false;
  end if;
  -- 0100: rechnet schon jemand, tut der Zeitplan nichts — der nächste Takt sieht nach.
  v_erg := auswertung_schritt_intern(1, true);
  if (v_erg ->> 'wartet') = 'true' then
    return false;
  end if;
  for i in 2..5 loop
    perform auswertung_schritt_intern(i, true);
  end loop;
  return true;
end $$;
comment on function auswertung_wenn_veraltet() is
  'Rechnet neu, wenn seit der letzten Berechnung etwas geschrieben wurde — sonst nichts. '
  'Für den Zeitplan (pg_cron, 0061); seit 0095 nebenläufig; seit 0098 mit eigener Notiz '
  'des Aufrufs; seit 0100 nie neben einer laufenden Rechnung.';
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 100 $$;
