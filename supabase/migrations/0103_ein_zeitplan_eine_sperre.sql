-- =====================================================================
-- 0103 — Ein Zeitplan, eine Sperre, kein Konvoi
--
-- 28. September, 22:00. Die Datenbank des Betriebs hat seit 11:52 keinen
-- einzigen Lauf mehr fertig gerechnet. Was seither geschah, war ein Konvoi:
-- Auf Stand 97 startete alle zehn Minuten ein Lauf, ohne Sperre. Sobald
-- zwei überlappten (nach einem abgebrochenen setup.sql, nach dem Rechnen
-- der App beim Öffnen), wartete der jüngere auf die Sperren des älteren,
-- der ältere auf die des noch älteren — bis jeden nach 15 Minuten die
-- Zeitgrenze abschoss, ohne dass einer fertig war. Ein Lauf brach um 21:41
-- beim Erneuern von mv_koeff_rand ab, einer Sicht mit elf Zeilen: Er hatte
-- nicht gerechnet, er hatte gewartet. Und solange sie warteten, hielten
-- die Läufe die Ansichten fest, die die App liest — die Seite hing.
--
-- Dann 0102: ein Sofort-Lauf alle 15 Sekunden. Der erste Tick rechnete,
-- jeder weitere blieb an der Zeilensperre von auswertung_stand hängen (die
-- Sperre aus 0100 ist ein Update — in einer Transaktion für andere
-- unsichtbar, aber die Zeile ist gesperrt), und die wartenden Ticks
-- besetzten die Arbeiter von pg_cron: „job startup timeout" für den
-- Zehn-Minuten-Lauf um 21:50. Ein zweiter Konvoi.
--
-- Darum jetzt, endgültig:
--   · Ein einziger Eintrag im Zeitplan, jede Minute. Er rechnet nur, wenn
--     etwas veraltet ist UND (jemand „Neu rechnen" gedrückt hat ODER der
--     letzte Stand älter als zehn Minuten ist). „Neu rechnen" wirkt binnen
--     einer Minute, die Halle löst höchstens alle zehn Minuten einen Lauf
--     aus, und ein Tick, der nichts zu tun hat, kostet eine Millisekunde.
--   · Die Sperre ist eine Beratungssperre (pg_try_advisory_xact_lock),
--     genommen, bevor der Lauf irgendetwas anfasst. Wer sie nicht bekommt,
--     geht sofort — er wartet auf keine Zeile, hält keinen Arbeiter. Stirbt
--     die Sitzung, ist die Sperre weg: kein Rest, der 15 Minuten blockiert.
--   · Der Lauf des Zeitplans hält während des Rechnens keine Zeile von
--     auswertung_stand: Alles Buchhalterische passiert am Ende, in einem
--     Update. So blockiert „Neu rechnen" (ein Update dieser Zeile) nie.
--   · Bevor er rechnet, beendet der Lauf jede fremde Sitzung, die noch an
--     einer Rechnung hängt (ein Konvoi-Rest, ein Schritt aus der App), und
--     wartet auf keine Sperre länger als 30 Sekunden (lock_timeout). Lieber
--     ein Lauf, der nach 30 Sekunden abbricht und in einer Minute wieder
--     kommt, als einer, der 15 Minuten wartet und dabei alles festhält.
--   · Die Zeitgrenze der Rolle steigt von 15 auf 60 Minuten: Ein Lauf, der
--     wirklich rechnet, wird nicht abgeschossen; einer, der wartet, bricht
--     durch lock_timeout viel früher ab.
--   · Kein Sofort-Lauf mehr. auswertung_anfordern() markiert nur noch und
--     trägt einen Rest davon aus.
--   · auswertung_diagnose(): was die Datenbank gerade tut — aktive
--     Sitzungen, die letzten Läufe aller Einträge, welche Ansichten gefüllt
--     sind, die Grenzen. Für den Betriebsleiter und für den, der von aussen
--     nachsieht, ohne einen SQL-Editor.
--
-- Um 22:00 (00:00 Uhr Betrieb) wurde dann doch ein Lauf fertig: 690
-- Sekunden. Mit der Demo sind es acht. Das ist der Kern dessen, was „anders"
-- ist: Ein Lauf dauert mit der Saison länger als der Zehn-Minuten-Takt —
-- also begann der nächste, bevor der eine fertig war, jedes Mal. Zwei Folgen
-- hier: Die Drossel richtet sich nach der letzten Laufdauer (mindestens
-- zehn Minuten, mindestens das Dreifache des letzten Laufs — die Datenbank
-- rechnet höchstens ein Viertel der Zeit für die Halle, „Neu rechnen" wirkt
-- immer sofort), und jeder Lauf schreibt je Ansicht auf, wie lange sie
-- gebraucht hat (auswertung_laufzeit) — damit die nächste Runde die 690
-- Sekunden dort sucht, wo sie sind, statt zu raten.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Die Laufzeit je Ansicht: wo die Minuten hingehen
-- ---------------------------------------------------------------------
create table if not exists auswertung_laufzeit (
  id           bigint generated always as identity primary key,
  ts           timestamptz not null default clock_timestamp(),
  schritt      int not null,
  sicht        text not null,
  nebenlaeufig boolean not null,
  dauer_ms     int not null
);
comment on table auswertung_laufzeit is
  'Je Erneuerung einer gespeicherten Ansicht ihre Dauer (0103), sieben Tage lang. '
  'auswertung_diagnose() nennt die langsamsten des letzten Laufs.';
alter table auswertung_laufzeit enable row level security;
drop policy if exists laufzeit_lesen on auswertung_laufzeit;
create policy laufzeit_lesen on auswertung_laufzeit for select to authenticated using (ist_admin());
grant select on auswertung_laufzeit to authenticated;

-- ---------------------------------------------------------------------
-- 1. Der Schritt: im Zeitplan-Weg keine Buchhaltung bis zum Ende
-- ---------------------------------------------------------------------
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
end $$;
comment on function auswertung_schritt_intern(integer, boolean) is
  'Ein Schritt des Neurechnens (0078), wahlweise nebenläufig (0095). Beratungssperre je Aufruf '
  '(0100); der App-Weg merkt sich rechnet_seit, der Zeitplan-Weg fasst auswertung_stand erst am '
  'Ende an; je Ansicht wird die Dauer notiert (auswertung_laufzeit, 0103). Nur für den '
  'Betriebsleiter oder ohne Anmeldung.';
revoke execute on function auswertung_schritt_intern(integer, boolean) from public;
grant execute on function auswertung_schritt_intern(integer, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Der Lauf des Zeitplans: Sperre zuerst, Drossel, fremde Reste beenden
-- ---------------------------------------------------------------------
-- Wie lange ein Stand mindestens alt sein muss, bevor die Halle (ohne
-- Anforderung) einen neuen Lauf auslöst: die Entprellung aus 0061. Dazu
-- kommt die Laufdauer: mindestens das Dreifache des letzten Laufs — ein Lauf
-- von zwölf Minuten kommt so höchstens alle 36 Minuten, nicht Rücken an
-- Rücken. „Neu rechnen" wartet auf nichts davon.
create or replace function auswertung_drossel_min() returns int
language sql immutable set search_path = public as $$ select 10 $$;

create or replace function auswertung_drossel(p_dauer_ms int) returns interval
language sql immutable set search_path = public as $$
  select greatest(make_interval(mins => auswertung_drossel_min()),
                  3 * make_interval(secs => (coalesce(p_dauer_ms, 0) / 1000.0)::double precision))
$$;
comment on function auswertung_drossel(int) is
  'Wie lange nach einem Lauf die Halle keinen neuen auslöst (0103): zehn Minuten, mindestens aber '
  'das Dreifache seiner Dauer. Eine Anforderung („Neu rechnen") wartet nicht.';
-- Kein Ausführungsrecht für Nichtangemeldete (0035 hält die Tür zu).
revoke all on function auswertung_drossel_min() from public;
grant execute on function auswertung_drossel_min() to authenticated;
revoke all on function auswertung_drossel(int) from public;
grant execute on function auswertung_drossel(int) to authenticated;

create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand; i int; v_erg jsonb; v_dauer timestamptz := clock_timestamp(); r record; v_n int := 0;
begin
  -- 1. Die Sperre — vor allem anderen. Wer sie nicht bekommt, geht sofort:
  --    keine Zeile angefasst, kein Arbeiter besetzt, kein Konvoi.
  if not pg_try_advisory_xact_lock(hashtext('auswertung_schritt')) then
    return false;
  end if;
  select * into v_stand from auswertung_stand where id = 1;
  -- 2. Nichts veraltet, oder veraltet, aber weder angefordert noch älter als
  --    die Drossel: nur den Aufruf notieren (0098) und gehen.
  if v_stand.berechnet_ts is not null and v_stand.geaendert_ts <= v_stand.berechnet_ts then
    update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;
    return false;
  end if;
  if v_stand.berechnet_ts is not null
     and not (v_stand.angefordert_ts is not null and v_stand.angefordert_ts > v_stand.berechnet_ts)
     and v_stand.berechnet_ts > clock_timestamp() - auswertung_drossel(v_stand.dauer_ms) then
    update auswertung_stand set zeitplan_gerufen_ts = now() where id = 1;
    return false;
  end if;
  -- 3. Fremde Reste beenden: eine Sitzung, die noch an einer Rechnung hängt
  --    (ein Konvoi von vor 0103, ein Schritt aus der App), hält Sperren, auf
  --    die dieser Lauf sonst wartete. Eine Erneuerung ist eine Transaktion —
  --    beendet heisst zurückgerollt, nichts geht verloren. Gemeint sind nur
  --    Rechnungen: nicht das Lesen des Standes durch die App (Millisekunden,
  --    aber „auswertung_stand" im Text) und nie setup.sql (Zeile 2 nennt
  --    sich, und ihre Einspielung hält die Sperre ohnehin selbst).
  begin
    for r in select pid from pg_stat_activity
              where datname = current_database() and pid <> pg_backend_pid()
                and state <> 'idle'
                and (query ~* 'auswertung_(schritt|wenn_veraltet|aktualisieren|sofort_lauf)'
                     or query ilike '%refresh materialized view%')
                and query not ilike '%setup.sql%'
    loop
      begin
        if pg_terminate_backend(r.pid) then v_n := v_n + 1; end if;
      exception when others then
        raise notice 'auswertung_wenn_veraltet: Sitzung % nicht beendet (%)', r.pid, sqlerrm;
      end;
    end loop;
    if v_n > 0 then raise notice 'auswertung_wenn_veraltet: % fremde Rechnung(en) beendet', v_n; end if;
  exception when others then
    raise notice 'auswertung_wenn_veraltet: fremde Rechnungen nicht prüfbar (%)', sqlerrm;
  end;
  -- 4. Auf keine Sperre länger als 30 Sekunden warten: Ein Lauf, der wartet,
  --    soll abbrechen und in einer Minute wiederkommen — nicht 15 Minuten
  --    lang alles festhalten, was er schon hat.
  perform set_config('lock_timeout', '30s', true);
  -- 5. Rechnen. Die Buchhaltung (berechnet_ts, dauer_ms, gerufen_ts) macht
  --    Schritt 5 am Ende, in einem Update — bis dahin bleibt die Zeile frei.
  for i in 1..5 loop
    v_erg := auswertung_schritt_intern(i, true);
    if (v_erg ->> 'wartet') = 'true' then
      return false;
    end if;
  end loop;
  update auswertung_stand
     set zeitplan_gerufen_ts = now(),
         dauer_ms = (extract(epoch from clock_timestamp() - v_dauer) * 1000)::int
   where id = 1;
  return true;
end $$;
comment on function auswertung_wenn_veraltet() is
  'Der Lauf des Zeitplans (pg_cron, jede Minute seit 0103): rechnet, wenn etwas veraltet ist und '
  'entweder „Neu rechnen" angefordert wurde oder der Stand älter als auswertung_drossel() ist. '
  'Beratungssperre vor allem anderen (nie ein zweiter Lauf, nie ein Konvoi), beendet fremde '
  'Rechnungsreste, wartet auf keine Sperre länger als 30 s, fasst auswertung_stand erst am Ende an.';
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Die Anforderung: nur markieren; den Sofort-Lauf gibt es nicht mehr
-- ---------------------------------------------------------------------
create or replace function auswertung_anfordern() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cron boolean; v_ts timestamptz; v_aktiv boolean := false; v_takt text;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
  end if;
  update auswertung_stand
     set geaendert_ts = clock_timestamp(), angefordert_ts = clock_timestamp()
   where id = 1
  returning angefordert_ts into v_ts;
  v_cron := exists (select 1 from pg_extension where extname = 'pg_cron');
  if not v_cron then
    return jsonb_build_object('weg', 'app', 'angefordert_ts', v_ts);
  end if;
  begin
    -- Ein Rest des Sofort-Laufs aus 0102: austragen.
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'auswertung_sofort'$q$;
    execute $q$select active, schedule from cron.job where jobname = 'auswertung_wenn_veraltet' order by jobid limit 1$q$
       into v_aktiv, v_takt;
  exception when others then
    return jsonb_build_object('weg', 'app', 'angefordert_ts', v_ts, 'hinweis', sqlerrm);
  end;
  if not coalesce(v_aktiv, false) then
    return jsonb_build_object('weg', 'app', 'angefordert_ts', v_ts, 'hinweis', 'kein aktiver Zeitplan-Eintrag');
  end if;
  return jsonb_build_object('weg', 'zeitplan', 'takt', v_takt, 'angefordert_ts', v_ts);
end $$;
comment on function auswertung_anfordern() is
  '„Neu rechnen" (0102/0103): markiert die Auswertung als veraltet und angefordert; der Zeitplan '
  '(jede Minute) rechnet beim nächsten Tick (weg: zeitplan). Ohne pg_cron oder ohne aktiven Eintrag '
  'antwortet sie weg: app — dann rechnet die App selbst. Nur für den Betriebsleiter oder ohne Anmeldung.';
revoke all on function auswertung_anfordern() from public;
grant execute on function auswertung_anfordern() to authenticated;

-- Der Sofort-Lauf aus 0102 bleibt als Funktion stehen (nie etwas wegnehmen),
-- tut aber nur noch, was der Zeitplan tut — und trägt seinen Eintrag aus.
create or replace function auswertung_sofort_lauf() returns text
language plpgsql security definer set search_path = public set jit = off as $$
declare v_erg boolean;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'auswertung_sofort'$q$;
  end if;
  v_erg := auswertung_wenn_veraltet();
  return case when v_erg then 'gerechnet' else 'nichts zu tun' end;
end $$;
comment on function auswertung_sofort_lauf() is
  'Seit 0103 ohne eigenen Eintrag: ruft den Lauf des Zeitplans und trägt einen Rest von „auswertung_sofort" aus.';

-- ---------------------------------------------------------------------
-- 4. Der Zeitplan: jede Minute; die Zeitgrenze der Rolle: 60 Minuten
-- ---------------------------------------------------------------------
do $$
declare v_id bigint; v_takt text;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'auswertung_sofort';
    select jobid, schedule into v_id, v_takt from cron.job where jobname = 'auswertung_wenn_veraltet' order by jobid limit 1;
    if v_id is not null and v_takt is distinct from '*/1 * * * *' then
      perform cron.alter_job(job_id => v_id, schedule => '*/1 * * * *',
                             command => 'select public.auswertung_wenn_veraltet()', active => true);
      raise notice 'Zeitplan: auswertung_wenn_veraltet() jede Minute (0103) — angepasst.';
    elsif v_id is null then
      perform cron.schedule('auswertung_wenn_veraltet', '*/1 * * * *', 'select public.auswertung_wenn_veraltet()');
      raise notice 'Zeitplan: auswertung_wenn_veraltet() jede Minute (0103) — neu angelegt.';
    end if;
  end if;
exception when others then
  raise notice 'Zeitplan nicht angepasst (%)', sqlerrm;
end $$;

do $$
begin
  execute 'alter role postgres set statement_timeout = ''60min''';
exception when others then
  raise notice 'Zeitgrenze der Rolle postgres nicht gesetzt (%)', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- 5. Die Diagnose: was die Datenbank gerade tut
-- ---------------------------------------------------------------------
create or replace function auswertung_diagnose() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb; v_aktiv jsonb; v_laeufe jsonb; v_ansichten jsonb; v_grenzen jsonb;
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Die Diagnose sieht nur der Betriebsleiter.' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'pid', pid, 'rolle', usename, 'programm', left(application_name, 40), 'zustand', state,
           'wartet_auf', case when wait_event_type is null then null else wait_event_type || ': ' || coalesce(wait_event, '') end,
           'seit_s', round(extract(epoch from clock_timestamp() - coalesce(query_start, backend_start))::numeric, 1),
           'abfrage', left(query, 120)) order by query_start), '[]'::jsonb)
    into v_aktiv
    from pg_stat_activity
   where datname = current_database() and pid <> pg_backend_pid() and state <> 'idle' and backend_type = 'client backend';
  v_laeufe := '[]'::jsonb;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      execute $q$
        select coalesce(jsonb_agg(jsonb_build_object(
                 'job', j.jobname, 'takt', j.schedule, 'aktiv', j.active, 'status', d.status,
                 'start', d.start_time, 'dauer_s', round(extract(epoch from d.end_time - d.start_time)::numeric, 1),
                 'meldung', left(d.return_message, 200)) order by d.start_time desc), '[]'::jsonb)
          from (select * from cron.job_run_details order by start_time desc limit 20) d
          join cron.job j using (jobid)
      $q$ into v_laeufe;
    exception when others then
      v_laeufe := jsonb_build_array(jsonb_build_object('fehler', sqlerrm));
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', c.relname, 'gefuellt', c.relispopulated,
                                               'zeilen', c.reltuples::bigint) order by c.relname), '[]'::jsonb)
    into v_ansichten
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'm';
  v_grenzen := jsonb_build_object(
    'statement_timeout_postgres', (select array_to_string(rolconfig, ',') from pg_roles where rolname = 'postgres'),
    'statement_timeout_authenticated', (select array_to_string(rolconfig, ',') from pg_roles where rolname = 'authenticated'),
    'max_worker_processes', current_setting('max_worker_processes', true),
    'max_connections', current_setting('max_connections', true),
    'cron_max_running_jobs', current_setting('cron.max_running_jobs', true));
  v := jsonb_build_object('jetzt', clock_timestamp(), 'aktiv', v_aktiv, 'laeufe', v_laeufe,
                          'langsamste', (select coalesce(jsonb_agg(jsonb_build_object('sicht', l.sicht, 'dauer_s', round(l.dauer_ms / 1000.0, 1),
                                                                                       'nebenlaeufig', l.nebenlaeufig, 'ts', l.ts)
                                                                    order by l.dauer_ms desc), '[]'::jsonb)
                                           from (select * from auswertung_laufzeit order by ts desc limit 60) l),
                          'ansichten_ungefuellt', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                                   where n.nspname = 'public' and c.relkind = 'm' and not c.relispopulated),
                          'ansichten', v_ansichten, 'grenzen', v_grenzen,
                          'stand', (select to_jsonb(s) from auswertung_stand s where id = 1));
  return v;
end $$;
comment on function auswertung_diagnose() is
  'Was die Datenbank gerade tut (0103): aktive Sitzungen, die letzten zwanzig Läufe des Zeitplans, '
  'die langsamsten Ansichten des letzten Laufs, welche gespeicherten Ansichten gefüllt sind, die '
  'Zeitgrenzen. Nur für den Betriebsleiter.';
revoke all on function auswertung_diagnose() from public;
grant execute on function auswertung_diagnose() to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 103 $$;
