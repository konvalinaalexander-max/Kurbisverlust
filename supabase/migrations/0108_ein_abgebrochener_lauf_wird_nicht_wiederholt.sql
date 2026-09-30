-- =====================================================================
-- 0108 — Ein abgebrochener Lauf wird nicht wiederholt
--
-- 29./30. September, nachts: Die Datenbank des Betriebs blieb auch nach dem
-- Neustart „unhealthy". Der Grund, den die Gegenprüfung von 0107 fand: Wird
-- ein Lauf von aussen abgebrochen — Neustart, Absturz, beendete Sitzung —,
-- rollt er ganz zurück, auch das, was er über sich selbst notieren wollte.
-- Der nächste Takt findet dieselbe Anforderung (oder dieselbe Nacht, oder
-- „noch nie gerechnet") und beginnt von vorn: Neustart → Rechnung →
-- Plattenlast → Neustart. 0107 merkte sich nur Fehler, die es fangen konnte.
--
-- Ab 0108 zählt ein Lauf, sobald er anfängt: Er zieht eine Nummer aus der
-- Folge auswertung_versuch. Eine Folge rollt nicht zurück — auch nicht bei
-- einem Absturz. Endet der Lauf (gelungen oder gefangen), schreibt er seine
-- Nummer in auswertung_stand.versuch_fertig. Findet der nächste Takt eine
-- gezogene Nummer, die nie fertig wurde, notiert er den Abbruch als
-- Fehlschlag und rechnet nicht: wieder erst auf „Neu rechnen" oder in der
-- nächsten Nacht.
--
-- Dazu, aus derselben Gegenprüfung, alles klein:
--   * Die Nacht beginnt um Mitternacht, nicht um zwei Uhr — in der Nacht der
--     Umstellung auf Winterzeit (25.10.) gibt es zwei Uhr zweimal, und ein
--     gescheiterter Nachtlauf wäre bis zur zweiten Stunde wiederholt worden.
--   * berechnet_ts ist der Beginn des Laufs, nicht sein Ende: Was während
--     des Laufs erfasst wird, gilt nicht als gerechnet.
--   * „Neu rechnen" schaltet einen abgeschalteten Zeitplan nicht wieder ein
--     (ein Notaus hält); der Browser rechnet nie, wo pg_cron da ist.
--   * Ein Lauf darf höchstens 15 Minuten dauern (statt 60).
--   * Das Protokoll von pg_cron wird stündlich gekürzt (sieben Tage).
-- =====================================================================

-- ---------- 1. Jeder Lauf zieht eine Nummer ------------------------------
create sequence if not exists auswertung_versuch;
comment on sequence auswertung_versuch is
  'Je Lauf des Zeitplans eine Nummer, gezogen beim Anfang (0108). Eine Folge rollt nicht zurück: Eine Nummer über '
  'auswertung_stand.versuch_fertig heisst, ein Lauf hat angefangen und nie aufgehört.';
alter table auswertung_stand add column if not exists versuch_fertig bigint;
comment on column auswertung_stand.versuch_fertig is
  'Die Nummer (auswertung_versuch) des letzten Laufs, der zu Ende kam — gelungen oder mit gefangenem Fehler (0108).';

-- ---------- 2. Die Nacht beginnt um Mitternacht --------------------------
create or replace function auswertung_grund(p_jetzt timestamptz, p_berechnet timestamptz, p_geaendert timestamptz,
                                            p_angefordert timestamptz, p_fehler timestamptz)
returns text language sql stable set search_path = public as $$
  with z as (
    select (p_jetzt at time zone betriebszone())                                        as lokal,
           (date_trunc('day', p_jetzt at time zone betriebszone()) at time zone betriebszone()) as mitternacht
  )
  select case
    -- „Neu rechnen": jünger als der Stand und als der letzte Fehlschlag
    when p_angefordert is not null
         and p_angefordert > coalesce(p_berechnet, '-infinity')
         and p_angefordert > coalesce(p_fehler, '-infinity')                           then 'angefordert'
    -- frisch eingespielt: noch nie gerechnet, noch nie gescheitert
    when p_berechnet is null and p_fehler is null                                      then 'erstmals'
    -- nachts einmal: 2 bis 5 Uhr Ortszeit, tagsüber etwas erfasst, seit
    -- Mitternacht weder gerechnet noch gescheitert (Mitternacht gibt es in
    -- Europe/Zurich nie zweimal, zwei Uhr in der Umstellungsnacht schon)
    when extract(hour from z.lokal) >= 2 and extract(hour from z.lokal) < 5
         and p_geaendert > coalesce(p_berechnet, '-infinity')
         and coalesce(p_berechnet, '-infinity') < z.mitternacht
         and coalesce(p_fehler, '-infinity') < z.mitternacht                           then 'nachts'
  end
  from z
$$;
comment on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) is
  'Warum jetzt gerechnet wird (0107, 0108) — ''angefordert'', ''erstmals'', ''nachts'' — oder null: dann nicht. '
  'Die eine Regel des Zeitplans; tagsüber löst die Halle nie eine Rechnung aus.';
revoke all on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) from public;
grant execute on function auswertung_grund(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) to authenticated;

-- ---------- 3. Ist pg_cron da? -------------------------------------------
-- Wo pg_cron da ist, rechnet der Browser nie — auch nicht, wenn der
-- Zeitplan abgeschaltet ist (Notaus). Für die Prüfung vortäuschbar.
create or replace function auswertung_cron_da() returns boolean
language sql stable set search_path = public as $$
  select current_setting('kuerbis.zeitplan_test', true) = 'an'
      or exists (select 1 from pg_extension where extname = 'pg_cron')
$$;
comment on function auswertung_cron_da() is
  'Ob pg_cron installiert ist (0108) — dann rechnet nur der Zeitplan, nie der Browser. In der Prüfung: kuerbis.zeitplan_test = ''an''.';
revoke all on function auswertung_cron_da() from public;
grant execute on function auswertung_cron_da() to authenticated;

-- ---------- 4. Der Lauf des Zeitplans ------------------------------------
create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand; i int; v_erg jsonb; v_start timestamptz := clock_timestamp(); v_grund text;
  v_letzter bigint; v_versuch bigint;
begin
  -- Die Sperre vor allem anderen: nie zwei Läufe. Wer sie hält, lebt —
  -- darum wird ein Abbruch erst hinter der Sperre festgestellt.
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return false;
  end if;
  select * into v_stand from auswertung_stand where id = 1;
  -- Ein Lauf hat angefangen und ist nie fertig geworden: abgebrochen
  -- (Neustart, Absturz, beendet). Gemerkt wie ein Fehlschlag, nicht wiederholt.
  select case when is_called then last_value else 0 end into v_letzter from auswertung_versuch;
  if v_letzter > coalesce(v_stand.versuch_fertig, 0) then
    update auswertung_stand
       set fehler_ts = clock_timestamp(),
           fehler = 'Lauf abgebrochen (Neustart, Absturz oder beendet) — nicht wiederholt',
           versuch_fertig = v_letzter, zeitplan_gerufen_ts = now()
     where id = 1;
    raise warning 'Auswertung: der letzte Lauf wurde abgebrochen — nicht wiederholt';
    return false;
  end if;
  v_grund := auswertung_grund(auswertung_jetzt(), v_stand.berechnet_ts, v_stand.geaendert_ts,
                              v_stand.angefordert_ts, v_stand.fehler_ts);
  if v_grund is null then
    update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;   -- nur die Notiz (0098)
    -- Einmal je Stunde das Protokoll von pg_cron kürzen (eine Zeile je Minute).
    if extract(minute from clock_timestamp()) = 0 then
      begin
        execute $q$delete from cron.job_run_details where end_time < now() - interval '7 days'$q$;
      exception when others then
        null;
      end;
    end if;
    return false;
  end if;
  -- Ab hier zählt der Lauf: Die Nummer bleibt gezogen, was auch geschieht.
  v_versuch := nextval('auswertung_versuch');
  perform set_config('lock_timeout', '30s', true);
  begin
    for i in 1..5 loop
      v_erg := auswertung_schritt_intern(i, true);
      if (v_erg ->> 'wartet') = 'true' then
        raise exception 'Schritt % wartet auf eine Sperre', i;
      end if;
    end loop;
  exception when query_canceled or others then
    update auswertung_stand
       set fehler_ts = clock_timestamp(), fehler = left(sqlerrm, 500), zeitplan_gerufen_ts = now(),
           versuch_fertig = v_versuch
     where id = 1;
    raise warning 'Auswertung (%) nicht gerechnet: %', v_grund, sqlerrm;
    return false;
  end;
  -- Der Stand ist der Beginn des Laufs: Was währenddessen erfasst wurde,
  -- zählt als neu (nachts wird es nachgeholt, der Chip sagt es).
  update auswertung_stand
     set berechnet_ts = v_start, zeitplan_gerufen_ts = now(), fehler_ts = null, fehler = null,
         versuch_fertig = v_versuch,
         dauer_ms = (extract(epoch from clock_timestamp() - v_start) * 1000)::int
   where id = 1;
  return true;
end $$;
comment on function auswertung_wenn_veraltet() is
  'Der Lauf des Zeitplans (pg_cron, jede Minute): rechnet nur, wenn auswertung_grund() es sagt — „Neu rechnen", nachts '
  'einmal, oder noch nie gerechnet (0107). Jeder Lauf zieht beim Anfang eine Nummer (auswertung_versuch, 0108); ein '
  'Lauf, der nie fertig wurde, gilt als Fehlschlag und wird nicht wiederholt. Der Stand ist der Beginn des Laufs.';
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

-- ---------- 5. „Neu rechnen" und der Notaus -----------------------------
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
      -- Fehlt der Eintrag ganz (ausgetragen), trägt „Neu rechnen" ihn ein.
      execute $q$select cron.schedule('auswertung_wenn_veraltet', '*/1 * * * *', 'select public.auswertung_wenn_veraltet()')$q$;
      v_takt := '*/1 * * * *';
    elsif not v_aktiv then
      -- Abgeschaltet (Notaus): bleibt abgeschaltet. Die Anforderung steht und
      -- wird gerechnet, sobald jemand den Zeitplan wieder einschaltet.
      return jsonb_build_object('weg', 'aus', 'angefordert_ts', v_ts,
        'hinweis', 'Der Zeitplan der Datenbank ist abgeschaltet (Notaus) — gerechnet wird, sobald er wieder eingeschaltet ist');
    end if;
  exception when others then
    return jsonb_build_object('weg', 'aus', 'angefordert_ts', v_ts, 'hinweis', 'Zeitplan nicht lesbar: ' || sqlerrm);
  end;
  return jsonb_build_object('weg', 'zeitplan', 'takt', coalesce(v_takt, '*/1 * * * *'), 'angefordert_ts', v_ts);
end $$;
comment on function auswertung_anfordern() is
  '„Neu rechnen" (0102, 0107, 0108): merkt die Anforderung; wo pg_cron da ist, rechnet der Zeitplan sie beim nächsten '
  'Takt. Fehlt der Eintrag, wird er angelegt; ist er abgeschaltet (Notaus), bleibt er es (weg: aus). Ohne pg_cron '
  '(Prüfung, Demo) weg: app. Nur für den Betriebsleiter oder ohne Anmeldung.';
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
  -- Aus dem Browser (angemeldet), wo pg_cron da ist: nur anfordern (0107, 0108).
  if auth.uid() is not null and auswertung_cron_da() then
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
  'Aus dem Browser fordert sie nur an, wo pg_cron da ist (0107, 0108). Nur für den Betriebsleiter.';
revoke all on function auswertung_aktualisieren() from public;
grant execute on function auswertung_aktualisieren() to authenticated;

create or replace function auswertung_schritt(p_schritt integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and auswertung_cron_da() then
    if p_schritt = 1 then
      perform auswertung_anfordern();
    end if;
    return jsonb_build_object('schritt', p_schritt, 'schritte', 5, 'titel', 'angefordert', 'dauer_ms', 0,
                              'fertig', p_schritt = 5, 'nebenlaeufig', true, 'wartet', false, 'angefordert', true);
  end if;
  return auswertung_schritt_intern(p_schritt, false);
end $$;
comment on function auswertung_schritt(integer) is
  'Ein Schritt des Neurechnens aus der App — nur ohne pg_cron (Demo ohne Zeitplan, Prüfung). Wo pg_cron da ist, fordert '
  'Schritt 1 an und alle Schritte melden sich sofort zurück (0107, 0108); gerechnet wird im Hintergrund.';
revoke execute on function auswertung_schritt(integer) from public;
grant execute on function auswertung_schritt(integer) to authenticated;

drop function if exists auswertung_zeitplan_aktiv();

-- ---------- 6. Ein Lauf dauert höchstens 15 Minuten ---------------------
-- Normal sind 89 s (Betrieb, Stand 102). Was länger dauert, scheitert
-- sichtbar, statt eine Stunde lang die Platte zu belegen; seit 0108 wird es
-- nicht wiederholt. Gilt auch im SQL-Editor — setup.sql braucht Sekunden.
do $$
begin
  execute 'alter role postgres set statement_timeout = ''15min''';
  raise notice 'Zeitgrenze der Rolle postgres: 15 Minuten (0108).';
exception when others then
  raise notice 'Zeitgrenze der Rolle nicht gesetzt (%)', sqlerrm;
end $$;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 108 $$;
