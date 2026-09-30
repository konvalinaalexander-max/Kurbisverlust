-- =====================================================================
-- 0110 — Rechnen auf PostgreSQL 17
--
-- Der Betrieb läuft auf PostgreSQL 17. Seit 17 frischt Postgres gespeicherte
-- Ansichten mit dem Suchpfad „pg_catalog, pg_temp" auf; eine Funktion, die
-- einen Namen aus public ohne Schema nennt und keinen eigenen Suchpfad hat,
-- scheitert dann (30.9.: palox_f_nach → palox_f). Geprüft wird:
-- (a) jede gespeicherte Ansicht lässt sich mit genau diesem Suchpfad
--     rechnen — so, wie PostgreSQL 17 sie auffrischt, auch wenn die Prüfung
--     auf 16 läuft;
-- (b) palox_f_nach() nennt palox_f() mit Schema und bleibt einsetzbar (SQL,
--     ohne SET);
-- (c) Stand 110.
-- =====================================================================
do $$
declare v_mv text; v_def text; v_n bigint; v_modus jsonb; v_lad text; v_geladen boolean := false;
  v_p pg_proc; v_pfad text := current_setting('search_path');
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  if (select count(*) from palette) = 0 then
    perform demo_daten_entfernen();
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  perform auswertung_aktualisieren();

  -- (a) Jede gespeicherte Ansicht mit dem Suchpfad von PostgreSQL 17. Die
  -- Definition wird unter diesem Suchpfad geholt: dann nennt sie ihre
  -- Tabellen und Ansichten mit Schema, und scheitern kann nur, was eine
  -- Funktion in ihrem Rumpf ohne Schema nennt — wie beim Auffrischen.
  for v_mv in select matviewname from pg_matviews where schemaname = 'public' order by 1 loop
    perform set_config('search_path', 'pg_catalog, pg_temp', true);
    begin
      select pg_get_viewdef(format('public.%I', v_mv)::regclass, true) into v_def;
      execute 'select count(*) from (' || rtrim(v_def, ';') || ') q' into v_n;
    exception when others then
      perform set_config('search_path', v_pfad, true);
      raise exception '0110 (a1): % lässt sich mit dem Suchpfad von PostgreSQL 17 nicht rechnen: %', v_mv, sqlerrm;
    end;
    perform set_config('search_path', v_pfad, true);
  end loop;

  -- (b) palox_f_nach nennt palox_f mit Schema und bleibt einsetzbar
  select * into v_p from pg_proc
   where proname = 'palox_f_nach' and pronamespace = 'public'::regnamespace;
  assert found, '0110 (b0): palox_f_nach() fehlt';
  assert v_p.prosrc ~ 'public\.palox_f\(', '0110 (b1): palox_f_nach() nennt palox_f ohne Schema';
  assert v_p.prolang = (select oid from pg_language where lanname = 'sql') and v_p.proconfig is null,
    '0110 (b2): palox_f_nach() ist keine einsetzbare SQL-Funktion mehr (Sprache oder SET geändert)';
  assert palox_f_nach(0.5, 0.2, 0.1, 0.2, 0.3, 0.01, 0.02, 0.03, 14) = palox_f(0.5, 0.2, 0.12, 0.24, 0.36),
    '0110 (b3): palox_f_nach() schreibt die Stationen nicht mehr um ihren Zuwachs fort';

  -- (c) Stand
  assert schema_stand() >= 110, format('0110 (c1): schema_stand() = %s', schema_stand());

  if v_geladen then perform demo_daten_entfernen(); end if;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0110 — jede gespeicherte Ansicht rechnet mit dem Suchpfad von PostgreSQL 17; palox_f_nach nennt palox_f mit Schema';
end $$;

select '——— 0110 Rechnen auf PostgreSQL 17 geprüft ———' as ergebnis;
