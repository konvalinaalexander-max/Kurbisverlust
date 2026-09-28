-- =====================================================================
-- 0098 — Der Zeitplan notiert sich selbst (Nachtrag zu Runde AD, 28. September)
--
-- Am ersten Tag in der echten Datenbank sagte der Chip den ganzen Tag
-- „Zeitplan rechnet nicht" — und die Runde glaubte es: Der Job stand in
-- cron.job, aber cron.job_run_details blieb leer, also galt er als nie
-- gelaufen (0095: „eingetragen heisst nicht laufend"). Um 11:21:56 stand
-- dann ein neuer Stand da, Dauer 116.5 s — Start 11:20:00.3, genau der
-- Takt. Der Zeitplan hatte gerechnet. pg_cron auf diesem Projekt schreibt
-- nur keine Laufgeschichte; die Frage der App las an der falschen Stelle.
--
-- Darum notiert die Datenbank ab jetzt selbst, wann der Zeitplan sie
-- gerufen hat: auswertung_wenn_veraltet() stempelt zeitplan_gerufen_ts,
-- bei jedem Aufruf, auch wenn nichts veraltet ist. auswertung_zeitplan()
-- nimmt zuerst die Laufgeschichte von pg_cron (sie sagt mehr: Status,
-- Meldung) und sonst diese Notiz. Der Chip urteilt weiter nach dem letzten
-- Lauf, nicht nach dem Eintrag — nur kennt er den Lauf jetzt auch dort, wo
-- pg_cron schweigt. Die Notiz steht als „quelle" in der Antwort.
-- =====================================================================

alter table auswertung_stand add column if not exists zeitplan_gerufen_ts timestamptz;
comment on column auswertung_stand.zeitplan_gerufen_ts is
  'Wann der Zeitplan (auswertung_wenn_veraltet) zuletzt gerufen wurde — auch ohne Rechnung. '
  'Eigene Notiz der Datenbank, weil pg_cron nicht überall eine Laufgeschichte schreibt (0098).';

-- Der Stempel steht vor der Prüfung „veraltet?": Gerufen ist gerufen.
create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand; i int;
begin
  update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;
  select * into v_stand from auswertung_stand where id = 1;
  if v_stand.berechnet_ts is not null and v_stand.geaendert_ts <= v_stand.berechnet_ts then
    return false;
  end if;
  for i in 1..5 loop
    perform auswertung_schritt_intern(i, true);
  end loop;
  return true;
end $$;
comment on function auswertung_wenn_veraltet() is
  'Rechnet neu, wenn seit der letzten Berechnung etwas geschrieben wurde — sonst nichts. '
  'Für den Zeitplan (pg_cron, 0061); seit 0095 nebenläufig; seit 0098 mit eigener Notiz '
  'des Aufrufs (auswertung_stand.zeitplan_gerufen_ts).';
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

create or replace function auswertung_zeitplan()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v jsonb;
  v_st auswertung_stand;
  v_j jsonb;
begin
  select * into v_st from auswertung_stand where id = 1;
  v := jsonb_build_object('aktiv', false,
                          'rechnet_seit', v_st.rechnet_seit,
                          'berechnet_ts', v_st.berechnet_ts,
                          'geaendert_ts', v_st.geaendert_ts,
                          'gerufen_ts', v_st.zeitplan_gerufen_ts);
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
    exception when others then
      v := v || jsonb_build_object('fehler', sqlerrm);
    end;
  end if;
  -- 0098: Schweigt pg_cron, gilt die eigene Notiz. Ein Lauf, der noch rechnet,
  -- ist „running"; einer, dessen Stand danach steht, „succeeded". Kein Erraten:
  -- ohne Notiz bleibt letzter_start leer, und der Chip sagt „rechnet nicht".
  if (v ->> 'letzter_start') is null and v_st.zeitplan_gerufen_ts is not null then
    v := v || jsonb_build_object(
      'letzter_start', v_st.zeitplan_gerufen_ts,
      'letzter_status', case when v_st.rechnet_seit is not null and v_st.rechnet_seit >= v_st.zeitplan_gerufen_ts - interval '1 minute'
                               then 'running' else 'succeeded' end,
      'quelle', 'eigene_notiz');
  end if;
  return v;
end $$;
comment on function auswertung_zeitplan() is
  'Läuft der Zeitplan (pg_cron-Job auswertung_wenn_veraltet)? Mit Takt, letztem Lauf, '
  'Status, Dauer — und ob gerade gerechnet wird (rechnet_seit). Läuft er, rechnet die App '
  'beim Öffnen nicht mehr selbst (0095). Seit 0098 kennt sie den letzten Lauf auch aus der '
  'eigenen Notiz der Datenbank (quelle: pg_cron oder eigene_notiz).';
revoke execute on function auswertung_zeitplan() from public;
grant execute on function auswertung_zeitplan() to authenticated;

create or replace function schema_stand() returns integer
language sql immutable set search_path = public as $$ select 98 $$;
