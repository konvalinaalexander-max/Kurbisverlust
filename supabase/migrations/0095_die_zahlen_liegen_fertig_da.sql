-- =====================================================================
-- 0095 — Die Zahlen liegen fertig da, wenn man die Seite öffnet
--
-- Der Betrieb: „warum wird alles gerechnet, wenn ich die Seite öffne …
-- der Server soll automatisch rechnen … und wenn ich genau in diesem
-- Zeitpunkt auf die Webseite gehe, möchte ich die Daten bis zu dem
-- Zeitpunkt, wie er begonnen hat zu rechnen."
--
-- Den Zeitplan gibt es seit 0061 (pg_cron: alle zehn Minuten nachrechnen,
-- wenn etwas veraltet ist). Was fehlte, in drei Teilen:
--
-- 1. Die App muss wissen, ob der Zeitplan läuft — dann rechnet sie beim
--    Öffnen nicht mehr selbst, sondern zeigt den letzten Stand und sagt,
--    dass er erneuert wird. auswertung_zeitplan() sagt es ihr; die Spalte
--    rechnet_seit sagt, ob gerade gerechnet wird.
-- 2. Wer während des Rechnens liest, soll die alten Zahlen sehen, nicht
--    warten. Postgres kann eine gespeicherte Ansicht *nebenläufig* erneuern
--    (die alte bleibt lesbar, bis die neue steht) — mit einem eindeutigen
--    Index je Ansicht. Die Schlüssel stehen in auswertung_schluessel(); der
--    Zeitplan legt die Indizes bei Bedarf selbst an und erneuert nebenläufig.
--    Geht das bei einer Ansicht nicht (doppelte Zeilen, noch nie gefüllt),
--    wird sie wie bisher erneuert, mit einer Notiz — nie bricht der Lauf ab.
--    Die App selbst („Neu rechnen") erneuert weiter wie bisher: schneller,
--    und dort wartet der, der es ausgelöst hat, ohnehin.
-- 3. Der Zeitplan läuft nicht unter der Acht-Sekunden-Grenze der API, aber
--    unter der Zeitgrenze seiner Rolle. Die wird hier grosszügig gesetzt,
--    wo die Datenbank es zulässt.
--
-- Warum die Indizes nicht als Anweisungen hier stehen: setup.sql baut die
-- Ansichten am Ende neu — mal leer, mal gefüllt. Ein eindeutiger Index auf
-- einer gefüllten Ansicht mit einer doppelten Zeile liesse setup.sql
-- scheitern, und zwar beim Betrieb, nicht hier. Ein Index, den der
-- Zeitplan im Lauf anlegt und bei Misserfolg nur notiert, kann das nicht.
-- =====================================================================

alter table auswertung_stand add column if not exists rechnet_seit timestamptz;
comment on column auswertung_stand.rechnet_seit is
  'Seit wann gerade gerechnet wird (Schritt 1 setzt, Schritt 5 löscht). Die App zeigt '
  'dann „wird gerade erneuert" und lädt nach, sobald berechnet_ts weiterrückt (0095).';

-- ---------------------------------------------------------------------
-- 1. Der eindeutige Schlüssel je gespeicherter Ansicht
-- ---------------------------------------------------------------------
-- Eine Zeile je Ansicht, die die App liest (erg_…) oder die im Lauf
-- zwischen zwei App-Ansichten steht (mv_…): die Spalten, unter denen ihre
-- Zeilen eindeutig sind. Nur Spaltennamen — Postgres erneuert nebenläufig
-- nicht mit einem Ausdrucksindex —, und Leerwerte zählen als gleich
-- (nulls not distinct), damit „kein Kaliber" nur einmal vorkommen darf.
-- Einzeilige Ansichten nehmen ihre erste Spalte. Der Prüfblock hält fest,
-- dass jede erg_-Ansicht hier steht — wer eine neue anlegt, trägt ihren
-- Schlüssel ein.
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
    ('erg_kurve',              'altersklasse'),
    ('erg_lieferung',          'id'),
    ('erg_marge',              'posten'),
    ('erg_marge_charge',       'charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_marge_wiegung',      'sorte, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_massenbilanz',       'charge_nr'),
    ('erg_modell',             'n'),
    ('erg_naechste_charge',    'charge_nr'),
    ('erg_plausibilitaet',     'art, charge_nr, auftrag_id, befund'),
    ('erg_prognose',           'gruppe, schluessel, h'),
    ('erg_punkte',             'charge_nr, auftrag_id, quelle, messtag, lagertage'),
    ('erg_selektion',          'n_verarbeitung'),
    ('erg_ueberfuellung',      'gruppe, sorte, charge_nr, kistensystem, soll_kg_pro_kiste, kaliber_idx, stueck_je_kiste'),
    ('erg_verarbeitung_alter', 'auftrag_id'),
    ('erg_verlauf',            'woche, bis, gruppe, schluessel'),
    ('erg_verlust',            'gruppe, schluessel, strom, buch'),
    ('erg_wiegung',            'id'),
    ('erg_wohin',              'gruppe, schluessel'),
    ('mv_hochrechnung',        'charge_nr, portion, strom, buch, kohorte'),
    ('mv_schimmel_modell',     'n'),
    ('mv_schimmel_punkte',     'charge_nr, auftrag_id, quelle, lagertage')
$$;
comment on function auswertung_schluessel() is
  'Je gespeicherter Ansicht die Spalten, unter denen ihre Zeilen eindeutig sind — der '
  'Schlüssel des Index, mit dem der Zeitplan sie nebenläufig erneuert (0095). Jede '
  'erg_-Ansicht steht hier; der Prüfblock verlangt es.';
revoke execute on function auswertung_schluessel() from public;
grant execute on function auswertung_schluessel() to authenticated;

-- ---------------------------------------------------------------------
-- 2. Ein Schritt — wahlweise nebenläufig
-- ---------------------------------------------------------------------
-- Der Rumpf ist der aus 0086 (0078 plus erg_marge_charge in Schritt 4); neu
-- sind p_nebenlaeufig und rechnet_seit. Der Prüfblock 0095 (b2) hält fest,
-- dass jede Ansicht mit Schlüssel auch erneuert wird.
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
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception 'Neu rechnen darf nur der Betriebsleiter.' using errcode = '42501';
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
    update auswertung_stand set rechnet_seit = clock_timestamp() where id = 1;
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
    'fertig', p_schritt = 5, 'nebenlaeufig', p_nebenlaeufig);
end $$;
comment on function auswertung_schritt_intern(integer, boolean) is
  'Ein Schritt des Neurechnens (0078), wahlweise nebenläufig (0095): dann bleibt jede '
  'Ansicht lesbar, bis ihre neue Fassung steht. Nur für den Betriebsleiter oder ohne Anmeldung.';
revoke execute on function auswertung_schritt_intern(integer, boolean) from public;
grant execute on function auswertung_schritt_intern(integer, boolean) to authenticated;

-- Die App ruft weiter auswertung_schritt(p_schritt) — nicht nebenläufig, wie
-- bisher: schneller, und wer „Neu rechnen" drückt, wartet ohnehin.
create or replace function auswertung_schritt(p_schritt integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return auswertung_schritt_intern(p_schritt, false);
end $$;
comment on function auswertung_schritt(integer) is
  'Ein Schritt des Neurechnens aus der App (0078) — nicht nebenläufig. Der Zeitplan '
  'nimmt auswertung_schritt_intern(…, true) (0095).';
revoke execute on function auswertung_schritt(integer) from public;
grant execute on function auswertung_schritt(integer) to authenticated;

-- Der Zeitplan rechnet nebenläufig: Wer währenddessen liest, sieht die alten Zahlen.
create or replace function auswertung_wenn_veraltet()
returns boolean language plpgsql security definer
set search_path = public set jit = off as $$
declare v_stand auswertung_stand; i int;
begin
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
  'Für den Zeitplan (pg_cron, 0061); seit 0095 nebenläufig, damit die App während des '
  'Rechnens die alten Zahlen liest statt zu warten.';
revoke all on function auswertung_wenn_veraltet() from public;
grant execute on function auswertung_wenn_veraltet() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Die App fragt: läuft ein Zeitplan?
-- ---------------------------------------------------------------------
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
                          'geaendert_ts', v_st.geaendert_ts);
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      execute $q$
        select jsonb_build_object('aktiv', j.active, 'takt', j.schedule,
                                  'letzter_start', d.start_time, 'letzter_status', d.status,
                                  'letzte_dauer_s', round(extract(epoch from d.end_time - d.start_time)::numeric, 1),
                                  'letzte_meldung', left(d.return_message, 200))
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
  return v;
end $$;
comment on function auswertung_zeitplan() is
  'Läuft der Zeitplan (pg_cron-Job auswertung_wenn_veraltet)? Mit Takt, letztem Lauf, '
  'Status, Dauer — und ob gerade gerechnet wird (rechnet_seit). Läuft er, rechnet die App '
  'beim Öffnen nicht mehr selbst (0095).';
revoke execute on function auswertung_zeitplan() from public;
grant execute on function auswertung_zeitplan() to authenticated;

-- ---------------------------------------------------------------------
-- 4. Die Zeitgrenze der Rolle, die den Zeitplan ausführt
-- ---------------------------------------------------------------------
-- Ein Lauf braucht auf Supabase bis zu einer Minute — mehr, wenn die Saison
-- gross ist. Die Grenze der API (acht Sekunden) gilt hier nicht; die der
-- Rolle wird gesetzt, wo die Datenbank es erlaubt, sonst nur notiert.
do $$
begin
  execute 'alter role postgres set statement_timeout = ''15min''';
  raise notice 'Zeitgrenze der Rolle postgres: 15 Minuten (für den Zeitplan).';
exception when others then
  raise notice 'Zeitgrenze der Rolle nicht gesetzt (%): der Zeitplan läuft mit der Vorgabe der Datenbank.', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- Der Stand der Datenbank
-- ---------------------------------------------------------------------
create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 95 $$;
comment on function schema_stand() is
  'Die Nummer der höchsten eingespielten Migration. Die App vergleicht sie mit '
  'SCHEMA_ERWARTET und verlangt setup.sql, wenn sie auseinanderliegen (0057).';
