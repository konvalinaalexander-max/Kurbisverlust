-- =====================================================================
-- 0102 — Gerechnet wird auf Anforderung, im Hintergrund
--
-- 28. September, abends. Die Seite des Betriebs blieb im Ladezustand, und
-- setup.sql endete im SQL-Editor wieder mit „Load failed". Die Datenbank
-- stand noch auf 97: Keine der Einspielungen des Tages war durchgekommen.
--
-- Was dahintersteckt: Mit der vollen Saison dauert das Neurechnen am Ende
-- von setup.sql länger, als der SQL-Editor auf eine Antwort wartet. Der
-- Editor gibt auf, die Anweisung wird abgebrochen, die ganze Transaktion
-- zurückgerollt — und solange sie lief, hielt sie Sperren auf allem, was
-- die App liest. Der Zeitplan lief dagegen auf, die App dagegen, die API
-- antwortete niemandem mehr. Zweimal an diesem Tag.
--
-- Der Betrieb: „Schau einfach, dass nur beim aktiven Neuladen neu geladen
-- wird, und dass die Resultate zwischengespeichert sind — dass mein Chef,
-- wenn er sich alle fünf Tage einloggt, gleich etwas präsentiert kriegt."
--
-- Genau so:
--   · Öffnen rechnet nie. Die App zeigt den gespeicherten Stand (erg_…).
--   · „Neu rechnen" ist eine Anforderung: auswertung_anfordern() markiert
--     die Auswertung als veraltet und trägt — wo pg_cron da ist — einen
--     Sofort-Lauf ein, der alle 15 Sekunden nachsieht, rechnet (mit der
--     Sperre aus 0100, nie doppelt) und sich austrägt, sobald der Stand
--     steht. Der Zeitplan rechnet im Hintergrund, unter seiner Zeitgrenze
--     von 15 Minuten, nicht unter der einer Browser-Anfrage.
--   · Ohne pg_cron sagt die Anforderung „weg: app", und die App rechnet
--     wie bisher Schritt für Schritt — der Weg der Tests und der Demo.
--   · setup.sql (Kopf und Ende, supabase/setup_bauen.mjs) rechnet am Ende
--     nicht mehr selbst, wenn ein Zeitplan da ist: Es fordert an. So ist
--     die Datei in Sekunden durch, und der Editor wartet nie auf die Saison.
-- =====================================================================

alter table auswertung_stand add column if not exists angefordert_ts timestamptz;
comment on column auswertung_stand.angefordert_ts is
  'Wann zuletzt „Neu rechnen" angefordert wurde (auswertung_anfordern, 0102). Steht die Anforderung '
  'jünger als berechnet_ts, ist sie erledigt.';

-- ---------------------------------------------------------------------
-- 1. Der Sofort-Lauf: was der Eintrag „auswertung_sofort" bei jedem Tick tut
-- ---------------------------------------------------------------------
create or replace function auswertung_sofort_lauf() returns text
language plpgsql security definer set search_path = public set jit = off as $$
declare v_st auswertung_stand; v_cron boolean; v_erg boolean;
begin
  v_cron := exists (select 1 from pg_extension where extname = 'pg_cron');
  select * into v_st from auswertung_stand where id = 1;
  -- Erledigt: nichts ist mehr veraltet. Der Eintrag trägt sich aus.
  if v_st.berechnet_ts is not null and v_st.geaendert_ts <= v_st.berechnet_ts then
    if v_cron then execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'auswertung_sofort'$q$; end if;
    return 'nichts zu tun';
  end if;
  -- Verfallen: eine Anforderung, die nach 30 Minuten noch offen ist, hält der
  -- Sofort-Lauf nicht länger am Leben — der Zehn-Minuten-Takt übernimmt.
  if v_st.angefordert_ts is null or v_st.angefordert_ts < clock_timestamp() - interval '30 minutes' then
    if v_cron then execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'auswertung_sofort'$q$; end if;
    return 'verfallen';
  end if;
  -- Rechnen — mit der Sperre aus 0100: rechnet schon jemand, wartet dieser Tick.
  v_erg := auswertung_wenn_veraltet();
  return case when v_erg then 'gerechnet' else 'gewartet' end;
end $$;
comment on function auswertung_sofort_lauf() is
  'Ein Tick des Sofort-Laufs (0102): rechnet, wenn etwas veraltet ist (auswertung_wenn_veraltet, '
  'mit der Sperre aus 0100), und trägt den Eintrag „auswertung_sofort" aus, sobald der Stand steht '
  'oder die Anforderung 30 Minuten alt ist.';
revoke all on function auswertung_sofort_lauf() from public;
grant execute on function auswertung_sofort_lauf() to authenticated;

-- ---------------------------------------------------------------------
-- 2. Die Anforderung: „Neu rechnen" aus der App und aus setup.sql
-- ---------------------------------------------------------------------
create or replace function auswertung_anfordern() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cron boolean; v_id bigint; v_takt text; v_ts timestamptz;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  -- Veraltet ab jetzt — auch wenn seit der letzten Rechnung nichts erfasst
  -- wurde: Wer „Neu rechnen" drückt, will rechnen lassen.
  update auswertung_stand
     set geaendert_ts = clock_timestamp(), angefordert_ts = clock_timestamp()
   where id = 1
  returning angefordert_ts into v_ts;
  v_cron := exists (select 1 from pg_extension where extname = 'pg_cron');
  if not v_cron then
    return jsonb_build_object('weg', 'app', 'angefordert_ts', v_ts);
  end if;
  begin
    execute $q$select jobid from cron.job where jobname = 'auswertung_sofort' limit 1$q$ into v_id;
    if v_id is null then
      -- Alle 15 Sekunden (pg_cron ab 1.5); kennt die Erweiterung das nicht: jede Minute.
      begin
        execute $q$select cron.schedule('auswertung_sofort', '15 seconds', 'select public.auswertung_sofort_lauf()')$q$;
        v_takt := '15 seconds';
      exception when others then
        execute $q$select cron.schedule('auswertung_sofort', '* * * * *', 'select public.auswertung_sofort_lauf()')$q$;
        v_takt := '* * * * *';
      end;
    else
      v_takt := 'schon eingetragen';
    end if;
  exception when others then
    -- Der Zeitplan lässt sich nicht rufen (Rechte, Erweiterung): dann rechnet
    -- die App selbst, Schritt für Schritt — und sagt warum.
    return jsonb_build_object('weg', 'app', 'angefordert_ts', v_ts, 'hinweis', sqlerrm);
  end;
  return jsonb_build_object('weg', 'zeitplan', 'takt', v_takt, 'angefordert_ts', v_ts);
end $$;
comment on function auswertung_anfordern() is
  '„Neu rechnen" (0102): markiert die Auswertung als veraltet und trägt, wo pg_cron da ist, den '
  'Sofort-Lauf „auswertung_sofort" ein (weg: zeitplan). Ohne pg_cron antwortet sie weg: app — dann '
  'rechnet die App selbst mit auswertung_schritt. Nur für den Betriebsleiter oder ohne Anmeldung.';
revoke all on function auswertung_anfordern() from public;
grant execute on function auswertung_anfordern() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Der Zeitplan sagt der App auch, ob eine Anforderung offen ist
-- ---------------------------------------------------------------------
create or replace function auswertung_zeitplan()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v jsonb;
  v_st auswertung_stand;
  v_j jsonb;
  v_sofort boolean := false;
begin
  select * into v_st from auswertung_stand where id = 1;
  v := jsonb_build_object('aktiv', false,
                          'rechnet_seit', v_st.rechnet_seit,
                          'berechnet_ts', v_st.berechnet_ts,
                          'geaendert_ts', v_st.geaendert_ts,
                          'gerufen_ts', v_st.zeitplan_gerufen_ts,
                          'angefordert_ts', v_st.angefordert_ts);
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      execute $q$
        select jsonb_build_object('aktiv', j.active, 'takt', j.schedule,
                                  'letzter_start', d.start_time, 'letzter_status', d.status,
                                  'letzte_dauer_s', round(extract(epoch from d.end_time - d.start_time)::numeric, 1),
                                  'letzte_meldung', left(d.return_message, 200),
                                  'quelle', case when d.start_time is null then null else 'pg_cron' end)
          from cron.job j
          left join lateral (select r.* from cron.job_run_details r
                              where r.jobid = j.jobid order by r.start_time desc limit 1) d on true
         where j.jobname = 'auswertung_wenn_veraltet'
      $q$ into v_j;
      if v_j is not null then v := v || v_j; end if;
      execute $q$select exists (select 1 from cron.job where jobname = 'auswertung_sofort')$q$ into v_sofort;
    exception when others then
      v := v || jsonb_build_object('fehler', sqlerrm);
    end;
  end if;
  -- 0098: Schweigt pg_cron, gilt die eigene Notiz.
  if (v ->> 'letzter_start') is null and v_st.zeitplan_gerufen_ts is not null then
    v := v || jsonb_build_object(
      'letzter_start', v_st.zeitplan_gerufen_ts,
      'letzter_status', case when v_st.rechnet_seit is not null and v_st.rechnet_seit >= v_st.zeitplan_gerufen_ts - interval '1 minute'
                               then 'running' else 'succeeded' end,
      'quelle', 'eigene_notiz');
  end if;
  -- 0102: Ist der Sofort-Lauf eingetragen (eine Anforderung in Arbeit)?
  v := v || jsonb_build_object('sofort', v_sofort);
  return v;
end $$;
comment on function auswertung_zeitplan() is
  'Läuft der Zeitplan (pg_cron-Job auswertung_wenn_veraltet)? Mit Takt, letztem Lauf, Status, Dauer, '
  'ob gerade gerechnet wird (rechnet_seit), seit 0098 auch aus der eigenen Notiz der Datenbank '
  '(quelle), seit 0102 mit angefordert_ts und sofort (Sofort-Lauf eingetragen).';
revoke execute on function auswertung_zeitplan() from public;
grant execute on function auswertung_zeitplan() to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 102 $$;
