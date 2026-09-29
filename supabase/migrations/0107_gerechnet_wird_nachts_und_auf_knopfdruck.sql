-- =====================================================================
-- 0107 — Gerechnet wird nachts und auf Knopfdruck, sonst nie
--
-- 29. September, abends: Die Seite war weg, Supabase meldete die Datenbank
-- als ungesund, IO-Wait am Anschlag. Der Betrieb: „seitdem du da irgendwas
-- mit automatischem Neuladen probierst, crasht die Website immer wieder".
--
-- Was die Datenbank tagsüber tat: Seit 0103 fragte der Zeitplan jede
-- Minute, ob in der Halle etwas erfasst wurde — und rechnete dann, sobald die
-- Drossel (zehn Minuten) abgelaufen war, alle gespeicherten Auswertungen neu.
-- Eine Rechnung dauert auf dem Betrieb 89 Sekunden (Abzug vom 29.9.), und
-- in der Halle wird ständig erfasst: Die Datenbank rechnete den ganzen Tag.
-- Auf der kleinen Supabase-Maschine ist das Budget für Plattenzugriffe dann
-- aufgebraucht, jede Rechnung wird langsamer, bis nichts mehr antwortet.
-- Dazu rechneten der Erntejournal-Abgleich beim Öffnen des Dashboards und
-- das Löschen unter Betrieb die ganze Auswertung direkt aus dem Browser —
-- mit der Acht-Sekunden-Grenze der API, also abgebrochen, nachdem sie die
-- gespeicherten Ansichten gesperrt hatten.
--
-- Die Regel ab jetzt, eine einzige (auswertung_grund):
--   * „Neu rechnen" (eine Anforderung, jünger als der Stand) — sofort;
--   * nachts zwischen 2 und 5 Uhr, einmal, wenn tagsüber etwas erfasst wurde;
--   * noch nie gerechnet (frisch eingespielt) — sofort.
--   Sonst nie. Die Halle löst keine Rechnung mehr aus.
-- Scheitert ein Lauf (Fehler, Zeitgrenze, eine Sperre, die nicht kommt),
-- merkt sich der Stand das (fehler_ts, fehler) und versucht es erst wieder
-- auf die nächste Anforderung oder in der nächsten Nacht — nie jede Minute.
-- Der Zeitplan beendet keine fremden Sitzungen mehr.
-- Aus dem Browser wird nicht gerechnet, wo der Zeitplan da ist:
-- auswertung_aktualisieren() und auswertung_schritt() fordern für eine
-- angemeldete Person nur noch an — auch für eine alte App im Zwischenspeicher
-- eines Handys, die sie noch ruft.
-- Die Palox-Erwartung (0106) liest das Dashboard gespeichert
-- (erg_palox_erwartung, Schritt 3) statt sie bei jedem Öffnen live zu rechnen.
-- =====================================================================

-- ---------- 1. Der Stand merkt sich einen Fehlschlag ---------------------
alter table auswertung_stand add column if not exists fehler_ts timestamptz;
alter table auswertung_stand add column if not exists fehler text;
comment on column auswertung_stand.fehler_ts is
  'Wann der letzte Lauf gescheitert ist (0107). Bis zur nächsten Anforderung oder Nacht wird nicht wieder versucht.';
comment on column auswertung_stand.fehler is
  'Warum der letzte Lauf gescheitert ist (0107), gekürzt auf 500 Zeichen. Leer nach einem gelungenen Lauf.';

-- ---------- 2. Die Palox-Erwartung gespeichert ---------------------------
drop materialized view if exists erg_palox_erwartung cascade;
create materialized view erg_palox_erwartung as select * from v_palox_erwartung with no data;
grant select on erg_palox_erwartung to authenticated;
comment on materialized view erg_palox_erwartung is
  'v_palox_erwartung, gespeichert (0107): der erwartete Palox-Anteil je Sorte und Station — das Dashboard und der '
  'Betriebsabzug lesen diese Fassung statt die Kette bei jedem Öffnen live zu rechnen. Schritt 3.';

-- ---------- 3. Wann gerechnet wird ---------------------------------------
-- Die Uhr des Zeitplans. Für die Prüfung lässt sie sich stellen
-- (set_config('kuerbis.jetzt_test', …)), damit „nachts" und „tagsüber"
-- nicht davon abhängen, wann die Prüfung läuft.
create or replace function auswertung_jetzt() returns timestamptz
language sql stable set search_path = public as $$
  select coalesce(nullif(current_setting('kuerbis.jetzt_test', true), '')::timestamptz, clock_timestamp())
$$;
comment on function auswertung_jetzt() is
  'Jetzt für den Zeitplan (0107); in der Prüfung über kuerbis.jetzt_test gestellt.';
revoke all on function auswertung_jetzt() from public;
grant execute on function auswertung_jetzt() to authenticated;

create or replace function auswertung_grund(p_jetzt timestamptz, p_berechnet timestamptz, p_geaendert timestamptz,
                                            p_angefordert timestamptz, p_fehler timestamptz)
returns text language sql stable set search_path = public as $$
  with z as (
    select (p_jetzt at time zone betriebszone())                                        as lokal,
           ((date_trunc('day', p_jetzt at time zone betriebszone()) + interval '2 hours')
              at time zone betriebszone())                                             as heute_nacht
  )
  select case
    -- „Neu rechnen": jünger als der Stand und als der letzte Fehlschlag
    when p_angefordert is not null
         and p_angefordert > coalesce(p_berechnet, '-infinity')
         and p_angefordert > coalesce(p_fehler, '-infinity')                           then 'angefordert'
    -- frisch eingespielt: noch nie gerechnet, noch nie gescheitert
    when p_berechnet is null and p_fehler is null                                      then 'erstmals'
    -- nachts einmal: 2 bis 5 Uhr Ortszeit, tagsüber etwas erfasst, heute Nacht
    -- weder gerechnet noch gescheitert
    when extract(hour from z.lokal) >= 2 and extract(hour from z.lokal) < 5
         and p_geaendert > coalesce(p_berechnet, '-infinity')
         and coalesce(p_berechnet, '-infinity') < z.heute_nacht
         and coalesce(p_fehler, '-infinity') < z.heute_nacht                           then 'nachts'
  end
  from z
$$;
comment on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) is
  'Warum jetzt gerechnet wird (0107) — ''angefordert'', ''erstmals'', ''nachts'' — oder null: dann nicht. '
  'Die eine Regel des Zeitplans; tagsüber löst die Halle nie eine Rechnung aus.';
revoke all on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) from public;
grant execute on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) to authenticated;

-- Ist der Zeitplan da und eingeschaltet? Nur dann rechnet die Datenbank im
-- Hintergrund, und nur dann darf der Browser nicht selbst rechnen. Für die
-- Prüfung (ohne pg_cron) lässt er sich vortäuschen: kuerbis.zeitplan_test = 'an'.
create or replace function auswertung_zeitplan_aktiv() returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v boolean := false;
begin
  if current_setting('kuerbis.zeitplan_test', true) = 'an' then
    return true;
  end if;
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return false;
  end if;
  begin
    execute $q$select coalesce(bool_or(active), false) from cron.job where jobname = 'auswertung_wenn_veraltet'$q$ into v;
  exception when others then
    v := false;
  end;
  return coalesce(v, false);
end $$;
comment on function auswertung_zeitplan_aktiv() is
  'Ob der Zeitplan (pg_cron, auswertung_wenn_veraltet) eingetragen und eingeschaltet ist (0107).';
revoke all on function auswertung_zeitplan_aktiv() from public;
grant execute on function auswertung_zeitplan_aktiv() to authenticated;

-- Der Lauf des Zeitplans. Jede Minute ein Blick auf eine Zeile; gerechnet
-- wird nur, wenn auswertung_grund() es sagt. Kein Beenden fremder
-- Sitzungen, kein Wiederholen nach einem Fehlschlag.
create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand; i int; v_erg jsonb; v_start timestamptz := clock_timestamp(); v_grund text;
begin
  -- Die Sperre vor allem anderen: nie zwei Läufe.
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return false;
  end if;
  select * into v_stand from auswertung_stand where id = 1;
  v_grund := auswertung_grund(auswertung_jetzt(), v_stand.berechnet_ts, v_stand.geaendert_ts,
                              v_stand.angefordert_ts, v_stand.fehler_ts);
  if v_grund is null then
    update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;   -- nur die Notiz (0098)
    return false;
  end if;
  perform set_config('lock_timeout', '30s', true);
  begin
    for i in 1..5 loop
      v_erg := auswertung_schritt_intern(i, true);
      if (v_erg ->> 'wartet') = 'true' then
        raise exception 'Schritt % wartet auf eine Sperre', i;
      end if;
    end loop;
  exception when query_canceled or others then
    -- Zurückgerollt ist, was dieser Lauf gerechnet hatte; die alten Zahlen
    -- bleiben stehen. Gemerkt wird der Fehlschlag — wiederholt wird erst auf
    -- die nächste Anforderung oder in der nächsten Nacht.
    update auswertung_stand
       set fehler_ts = clock_timestamp(), fehler = left(sqlerrm, 500), zeitplan_gerufen_ts = now()
     where id = 1;
    raise warning 'Auswertung (%) nicht gerechnet: %', v_grund, sqlerrm;
    return false;
  end;
  update auswertung_stand
     set zeitplan_gerufen_ts = now(), fehler_ts = null, fehler = null,
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;
  -- Nachts auch das Protokoll von pg_cron kürzen (eine Zeile je Minute).
  if v_grund = 'nachts' then
    begin
      execute $q$delete from cron.job_run_details where end_time < now() - interval '7 days'$q$;
    exception when others then
      null;
    end;
  end if;
  return true;
end $$;
comment on function auswertung_wenn_veraltet() is
  'Der Lauf des Zeitplans (pg_cron, jede Minute): rechnet nur, wenn auswertung_grund() es sagt — '
  '„Neu rechnen", nachts einmal, oder noch nie gerechnet (0107). Scheitert der Lauf, stehen fehler_ts/fehler '
  'im Stand, und es wird erst auf die nächste Anforderung oder in der nächsten Nacht wieder versucht.';
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

-- Die Drossel (0103) gibt es nicht mehr: tagsüber rechnet die Halle nie.
drop function if exists auswertung_drossel(int);
drop function if exists auswertung_drossel_min();

-- ---------- 4. Aus dem Browser wird nicht gerechnet ----------------------
-- „Neu rechnen" fordert an; fehlt der Zeitplan, trägt die Anforderung ihn ein
-- (er rechnet ja nur noch, wenn jemand fragt oder nachts).
create or replace function auswertung_anfordern() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ts timestamptz; v_id bigint; v_aktiv boolean; v_takt text;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  update auswertung_stand
     set geaendert_ts = clock_timestamp(), angefordert_ts = clock_timestamp()
   where id = 1
  returning angefordert_ts into v_ts;
  if current_setting('kuerbis.zeitplan_test', true) = 'an' then
    return jsonb_build_object('weg', 'zeitplan', 'takt', '*/1 * * * *', 'angefordert_ts', v_ts);
  end if;
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return jsonb_build_object('weg', 'app', 'angefordert_ts', v_ts);
  end if;
  begin
    execute $q$select jobid, active, schedule from cron.job where jobname = 'auswertung_wenn_veraltet' order by jobid limit 1$q$
       into v_id, v_aktiv, v_takt;
    if v_id is null then
      execute $q$select cron.schedule('auswertung_wenn_veraltet', '*/1 * * * *', 'select public.auswertung_wenn_veraltet()')$q$;
      v_takt := '*/1 * * * *';
    elsif not v_aktiv then
      execute format($q$select cron.alter_job(job_id => %s, active => true)$q$, v_id);
    end if;
  exception when others then
    return jsonb_build_object('weg', 'app', 'angefordert_ts', v_ts, 'hinweis', sqlerrm);
  end;
  return jsonb_build_object('weg', 'zeitplan', 'takt', coalesce(v_takt, '*/1 * * * *'), 'angefordert_ts', v_ts);
end $$;
comment on function auswertung_anfordern() is
  '„Neu rechnen" (0102, 0107): merkt die Anforderung; wo pg_cron da ist, rechnet der Zeitplan sie beim nächsten '
  'Takt (weg: zeitplan) und wird eingetragen, falls er fehlt. Ohne pg_cron (Prüfung, Demo) weg: app. '
  'Nur für den Betriebsleiter oder ohne Anmeldung.';
revoke all on function auswertung_anfordern() from public;
grant execute on function auswertung_anfordern() to authenticated;

create or replace function auswertung_aktualisieren() returns timestamptz
language plpgsql security definer set search_path = public set jit = 'off'
as $$
declare i int;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.'
      using errcode = '42501';
  end if;
  -- Aus dem Browser (angemeldet) mit Zeitplan: nur anfordern — die volle
  -- Rechnung überschritte die Grenze der API und sperrte die Ansichten (0107).
  if auth.uid() is not null and auswertung_zeitplan_aktiv() then
    perform auswertung_anfordern();
    return now();
  end if;
  for i in 1..5 loop
    perform auswertung_schritt_intern(i, false);
  end loop;
  return now();
end $$;
comment on function auswertung_aktualisieren() is
  'Alle fünf Schritte des Neurechnens nacheinander — für die Prüfstände und Einspielungen ohne Anmeldung. '
  'Aus dem Browser mit Zeitplan fordert sie nur an (0107). Nur für den Betriebsleiter.';
revoke all on function auswertung_aktualisieren() from public;
grant execute on function auswertung_aktualisieren() to authenticated;

create or replace function auswertung_schritt(p_schritt integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and auswertung_zeitplan_aktiv() then
    if p_schritt = 1 then
      perform auswertung_anfordern();
    end if;
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'angefordert', 'dauer_ms', 0,
                              'fertig', p_schritt = 5, 'nebenlaeufig', true, 'wartet', false, 'angefordert', true);
  end if;
  return auswertung_schritt_intern(p_schritt, false);
end $$;
comment on function auswertung_schritt(integer) is
  'Ein Schritt des Neurechnens aus der App — nur ohne Zeitplan (Demo, Prüfung). Mit Zeitplan fordert Schritt 1 '
  'an und alle Schritte melden sich sofort zurück (0107); gerechnet wird im Hintergrund.';
revoke execute on function auswertung_schritt(integer) from public;
grant execute on function auswertung_schritt(integer) to authenticated;

-- ---------- 5. Schritt 3 mit erg_palox_erwartung --------------------------
CREATE OR REPLACE FUNCTION public.auswertung_schritt_intern(p_schritt integer, p_nebenlaeufig boolean)
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
  v_ausdruck text;
  v_eindeutig boolean;
  v_gefuellt boolean;
  v_seit timestamptz;
  v_t timestamptz;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- Je Aufruf eine Beratungssperre (0100): zwei Erneuerungen derselben
  -- Ansicht zur selben Sekunde gibt es nicht. Im Zeitplan-Weg hält der
  -- ganze Lauf sie (eine Transaktion); ein Schritt aus der App, der sie
  -- nicht bekommt, geht sofort mit „wartet".
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'wartet', 'dauer_ms', 0,
                              'fertig', false, 'nebenlaeufig', p_nebenlaeufig, 'wartet', true,
                              'rechnet_seit', (select rechnet_seit from auswertung_stand where id = 1));
  end if;
  -- Der App-Weg (fünf einzelne Aufrufe, je eine Transaktion) merkt sich in
  -- rechnet_seit, dass er läuft (0100). Der Zeitplan-Weg tut das nicht: Ein
  -- Update hier hielte die Zeile bis zum Ende des Laufs gesperrt, und jedes
  -- „Neu rechnen" bliebe daran hängen (0103).
  if p_schritt = 1 and not p_nebenlaeufig then
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
  case p_schritt
    when 1 then
      v_titel := 'Rohdaten';
      v_namen := array['mv_sortier_lauf_masse', 'mv_kaliber_verteilung', 'mv_sortier_eingang',
                       'erg_gewichte', 'erg_kaliber', 'erg_gebinde', 'erg_ausgang',
                       'erg_lieferung', 'erg_kohorte', 'erg_ueberfuellung'];
    when 2 then
      v_titel := 'Arbeiten';
      v_namen := array['mv_auftrag_masse', 'erg_punkte',
                       'erg_koeff_verdunstung', 'erg_koeff_ausschuss', 'erg_koeff_nebenkanal',
                       'erg_koeff_fax', 'erg_koeff_ueberfuellung', 'mv_koeff_rand',
                       'erg_wiegung', 'erg_fax', 'erg_ausschuss',
                       'erg_fax_wartezeit', 'erg_verarbeitung_alter', 'erg_durchsatz'];
    when 3 then
      v_titel := 'Kaskade';
      v_namen := array['erg_palox_erwartung', 'mv_kaskade', 'mv_hochrechnung', 'erg_charge'];
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
    delete from auswertung_laufzeit where ts < clock_timestamp() - interval '7 days';
  end if;

  foreach v_name in array v_namen loop
    v_t := clock_timestamp();
    v_eindeutig := false;
    if p_nebenlaeufig then
      select s.ausdruck into v_ausdruck from auswertung_schluessel() s where s.sicht = v_name;
      select c.relispopulated into v_gefuellt from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_name;
      if v_ausdruck is not null and coalesce(v_gefuellt, false) then
        begin
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
    -- 0103: Wo die Minuten hingehen, sagt jeder Lauf selbst.
    insert into auswertung_laufzeit (schritt, sicht, nebenlaeufig, dauer_ms)
    values (p_schritt, v_name, v_eindeutig, (extract(epoch from clock_timestamp() - v_t) * 1000)::int);
  end loop;

  if p_schritt = 5 then
    update auswertung_stand
       set berechnet_ts = clock_timestamp(),
           rechnet_seit = null,
           dauer_ms = case when p_nebenlaeufig then null else coalesce(dauer_ms, 0) end
                      + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
     where id = 1;
  elsif not p_nebenlaeufig then
    if p_schritt = 1 then
      update auswertung_stand
         set dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    else
      update auswertung_stand
         set dauer_ms = coalesce(dauer_ms, 0) + (extract(epoch from clock_timestamp() - v_start) * 1000)::int
       where id = 1;
    end if;
  end if;

  return jsonb_build_object(
    'schritt', p_schritt, 'schritte', 5, 'titel', v_titel,
    'dauer_ms', (extract(epoch from clock_timestamp() - v_start) * 1000)::int,
    'fertig', p_schritt = 5, 'nebenlaeufig', p_nebenlaeufig, 'wartet', false);
end $function$;

create or replace function auswertung_schluessel()
returns table (sicht text, ausdruck text) language sql immutable set search_path = public as $$
  values
    ('erg_ausgang',            'id'),
    ('erg_ausschuss',          'weg, charge_nr, auftrag_id'),
    ('erg_bilanz',             'heute'),
    ('erg_charge',             'charge_nr'),
    ('erg_datenlage',          'charge_nr'),
    ('erg_datenqualitaet',     'paletten_gezaehlt'),
    ('erg_durchsatz',          'auftrag_id'),
    ('erg_fax',                'auftrag_id'),
    ('erg_fax_wartezeit',      'gruppe, sorte, klasse'),
    ('erg_gebinde',            'sorte, kaliber_idx'),
    ('erg_gewichte',           'charge_nr, stufe_g'),
    ('erg_kaliber',            'charge_nr, klasse, kaliber_idx'),
    ('erg_koeff_ausschuss',    'sorte'),
    ('erg_koeff_fax',          'sorte'),
    ('erg_koeff_nebenkanal',   'sorte'),
    ('erg_koeff_ueberfuellung','n'),
    ('erg_koeff_verdunstung',  'sorte'),
    ('erg_kohorte',            'charge_nr, eingangsdatum'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste, band_von_g, band_bis_g'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_palox_erwartung',    'sorte, station'),
    ('erg_plausibilitaet',     'art, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte')
$$;

-- Die Beschreibung ausdrücklich: Sonst trüge setup.sql (verdichtet) eine
-- ältere als die Migrationen, und der Abgleich in run.sh schlüge an.
comment on function auswertung_schritt_intern(integer, boolean) is
  'Ein Schritt des Neurechnens (0078), wahlweise nebenläufig (0095). Beratungssperre je Aufruf (0100); der App-Weg merkt '
  'sich rechnet_seit, der Zeitplan-Weg fasst auswertung_stand erst am Ende an; je Ansicht wird die Dauer notiert '
  '(auswertung_laufzeit, 0103). Schritt 3 rechnet seit 0107 auch erg_palox_erwartung. Nur für den Betriebsleiter oder ohne Anmeldung.';

-- ---------- 6. Der Zeitplan: jede Minute ein Blick ------------------------
do $$
declare v_id bigint; v_takt text;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'auswertung_sofort';
    select jobid, schedule into v_id, v_takt from cron.job where jobname = 'auswertung_wenn_veraltet' order by jobid limit 1;
    if v_id is null then
      perform cron.schedule('auswertung_wenn_veraltet', '*/1 * * * *', 'select public.auswertung_wenn_veraltet()');
      raise notice 'Zeitplan: jede Minute ein Blick, gerechnet nur nachts und auf „Neu rechnen" (0107) — neu angelegt.';
    else
      perform cron.alter_job(job_id => v_id, schedule => '*/1 * * * *',
                             command => 'select public.auswertung_wenn_veraltet()', active => true);
      raise notice 'Zeitplan: jede Minute ein Blick, gerechnet nur nachts und auf „Neu rechnen" (0107).';
    end if;
  end if;
exception when others then
  raise notice 'Zeitplan nicht angepasst (%)', sqlerrm;
end $$;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 107 $$;
