-- =====================================================================
-- 0109 — Die Rechnung plant klein
--
-- Die Nacht vom 29. auf den 30. September, zweiter Teil: Das Planen einer
-- Auswertung brauchte bis zu 1 GB Speicher, weil die Knoten-Sichten in jede
-- Abfrage darüber eingesetzt wurden (mv_kaskade: 6915 Planknoten). Seit 0109
-- stehen vier von ihnen hinter einer Planungsgrenze. Geprüft wird:
-- (a) jede der vier Sichten liest über ihre Grenze — ihr Plan ist ein
--     Function Scan auf <sicht>_zaun, nicht die eingesetzte Formel;
-- (b) die Grenze ist PL/pgSQL (der Planer setzt sie nicht ein), liest mit
--     den Rechten des Lesers wie die Sicht, läuft ohne JIT und mit festem
--     Suchpfad, und nur Angemeldete dürfen sie ausführen;
-- (c) Sicht und Formel liefern dieselben Zeilen, in beide Richtungen; beide
--     lesen mit den Rechten des Lesers (security_invoker);
-- (d) keine gespeicherte Auswertung plant mit mehr als 1000 Knoten;
-- (e) die Grenze speichert nichts: Ändern sich die Rohdaten, zeigt die Sicht
--     es in der nächsten Abfrage, gleich wie die Formel;
-- (f) Stand 109.
-- =====================================================================
do $$
declare v text; v_plan jsonb; v_knoten int; v_mv text; v_n bigint; v_p pg_proc;
  v_modus jsonb; v_lad text; v_geladen boolean := false;
  v_vorher text; v_nachher text; v_formel text;
  c_sichten constant text[] := array['v_koeff_gebinde', 'v_auftrag_masse', 'v_schimmel_punkte', 'v_koeff_kaliber_geschaetzt'];
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  if (select count(*) from palette) = 0 then
    perform demo_daten_entfernen();
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  -- v_auftrag_masse liest mv_auftrag_masse: ohne Rechnung wäre sie nach
  -- frisch geladener Demo leer, und (c) verglich nichts mit nichts.
  perform auswertung_aktualisieren();

  foreach v in array c_sichten loop
    -- (a) Der Plan der Sicht ist die Grenze, nicht die Formel
    execute format('explain (format json) select * from %I', v) into v_plan;
    assert v_plan -> 0 -> 'Plan' ->> 'Node Type' = 'Function Scan'
       and v_plan -> 0 -> 'Plan' ->> 'Function Name' = v || '_zaun',
      format('0109 (a1): %s liest nicht über %s_zaun() — der Planer setzt die Formel wieder ein (%s)',
             v, v, v_plan -> 0 -> 'Plan' ->> 'Node Type');
    assert pg_get_viewdef(v::regclass, true) ~ (v || '_zaun\(\)'),
      format('0109 (a2): %s trägt ihre Formel wieder selbst', v);

    -- (b) Die Grenze: PL/pgSQL, Rechte des Lesers, ohne JIT, fester Suchpfad
    select * into v_p from pg_proc where proname = v || '_zaun' and pronargs = 0;
    assert found, format('0109 (b0): %s_zaun() fehlt', v);
    assert v_p.prolang = (select oid from pg_language where lanname = 'plpgsql'),
      format('0109 (b1): %s_zaun() ist nicht PL/pgSQL — der Planer könnte sie einsetzen', v);
    assert not v_p.prosecdef, format('0109 (b2): %s_zaun() läuft mit den Rechten des Eigentümers statt des Lesers', v);
    assert v_p.provolatile = 's', format('0109 (b3): %s_zaun() ist nicht stable', v);
    assert v_p.proretset, format('0109 (b4): %s_zaun() gibt keine Menge zurück', v);
    assert 'jit=off' = any(v_p.proconfig), format('0109 (b5): %s_zaun() läuft mit JIT', v);
    assert 'search_path=public' = any(v_p.proconfig), format('0109 (b6): %s_zaun() ohne festen Suchpfad', v);
    assert not exists (select 1 from aclexplode(coalesce(v_p.proacl, acldefault('f', v_p.proowner))) a
                        where a.grantee = 0 and a.privilege_type = 'EXECUTE'),
      format('0109 (b7): %s_zaun() ist für jeden ausführbar', v);
    assert not has_function_privilege('anon', v_p.oid, 'execute'), format('0109 (b8): anon darf %s_zaun() ausführen', v);
    assert has_function_privilege('authenticated', v_p.oid, 'execute'), format('0109 (b9): Angemeldete dürfen %s_zaun() nicht ausführen', v);

    -- (c) Dieselben Zeilen, beide mit den Rechten des Lesers
    assert (select coalesce('security_invoker=true' = any(reloptions), false) from pg_class where oid = v::regclass),
      format('0109 (c1): %s liest nicht mit den Rechten des Lesers', v);
    assert (select coalesce('security_invoker=true' = any(reloptions), false) from pg_class where oid = (v || '_formel')::regclass),
      format('0109 (c2): %s_formel liest nicht mit den Rechten des Lesers', v);
    assert has_table_privilege('authenticated', (v || '_formel')::regclass, 'select'),
      format('0109 (c3): Angemeldete dürfen %s_formel nicht lesen', v);
    execute format('select count(*) from (select * from %I except all select * from %I) d', v, v || '_formel') into v_n;
    assert v_n = 0, format('0109 (c4): %s hat %s Zeilen, die %s_formel nicht hat', v, v_n, v);
    execute format('select count(*) from (select * from %I except all select * from %I) d', v || '_formel', v) into v_n;
    assert v_n = 0, format('0109 (c5): %s_formel hat %s Zeilen, die %s nicht hat', v, v_n, v);
    execute format('select count(*) from %I', v) into v_n;
    assert v_n > 0, format('0109 (c6): %s ist leer — der Vergleich prüft nichts', v);
  end loop;

  -- (d) Keine Auswertung plant mit mehr als 1000 Knoten (vor 0109: 6915)
  for v_mv in select matviewname from pg_matviews where schemaname = 'public' order by 1 loop
    execute 'explain (format json) ' || (select definition from pg_matviews where schemaname = 'public' and matviewname = v_mv)
      into v_plan;
    select count(*) into v_knoten from jsonb_path_query(v_plan, 'strict $.**."Node Type"');
    assert v_knoten between 1 and 1000,
      format('0109 (d1): %s plant mit %s Knoten (höchstens 1000) — eine Knoten-Sicht steht wieder ohne Grenze', v_mv, v_knoten);
  end loop;

  -- (e) Die Grenze speichert nichts: Rohdaten ändern, sofort sichtbar
  begin
    select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) into v_vorher from v_koeff_gebinde t;
    delete from auftrag_gebinde;
    select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) into v_nachher from v_koeff_gebinde t;
    select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) into v_formel from v_koeff_gebinde_formel t;
    assert v_nachher is distinct from v_vorher,
      '0109 (e1): v_koeff_gebinde zeigt die gelöschten Kistenzählungen noch — die Grenze liefert einen alten Stand';
    assert v_nachher = v_formel, '0109 (e2): v_koeff_gebinde und ihre Formel sind nach der Änderung verschieden';
    select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) into v_vorher from v_schimmel_punkte t;
    delete from schimmel_messung;
    select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) into v_nachher from v_schimmel_punkte t;
    select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) into v_formel from v_schimmel_punkte_formel t;
    assert v_nachher is distinct from v_vorher,
      '0109 (e3): v_schimmel_punkte zeigt die gelöschten Faul-Messungen noch — die Grenze liefert einen alten Stand';
    assert v_nachher = v_formel, '0109 (e4): v_schimmel_punkte und ihre Formel sind nach der Änderung verschieden';
    raise exception using errcode = 'P0109', message = 'zurück';
  exception when sqlstate 'P0109' then
    null;   -- die Löschungen sind zurückgenommen
  end;
  assert (select count(*) from auftrag_gebinde) > 0 and (select count(*) from schimmel_messung) > 0,
    '0109 (e5): die Probe hat die Rohdaten nicht zurückgegeben';

  -- (f) Stand
  assert schema_stand() >= 109, format('0109 (f1): schema_stand() = %s', schema_stand());

  if v_geladen then perform demo_daten_entfernen(); end if;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0109 — vier Knoten-Sichten lesen über ihre Planungsgrenze (PL/pgSQL, Rechte des Lesers, ohne JIT), liefern dieselben Zeilen wie ihre Formel und speichern nichts; keine Auswertung plant mit mehr als 1000 Knoten';
end $$;

select '——— 0109 Die Rechnung plant klein geprüft ———' as ergebnis;
