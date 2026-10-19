-- =====================================================================
-- 0117 — Kundengruppen in der Reihenfolge des Betriebs, und ein Plan für die
--        ganze Gruppe
--
-- (a) beide Tabellen tragen Zeilenschutz; (b) die Halle liest, schreibt aber
--     weder Reihenfolge noch Gruppenplan; (c) der Betriebsleiter schreibt,
--     der Erfasser steht da, ein Plan ist je Saison, Gruppe und Wahl einmal
--     da und nie negativ, Grösse und Label nur, was es gibt; (d) Stand 117.
-- =====================================================================
do $$
declare v_modus jsonb;
  v_u uuid := '00000000-0117-0000-0000-000000000001';
  v_w uuid := '00000000-0117-0000-0000-000000000002';
  v_ok boolean;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0117"}');
  update profil set rolle = 'admin' where id = v_u;
  insert into auth.users (id, email, raw_user_meta_data) values (v_w, null, '{"name":"Prüf-0117 Halle"}');
  update profil set rolle = 'arbeiter' where id = v_w;   -- in der Beispieldatenbank wäre jede neue Person Betriebsleiter

  -- (a) Zeilenschutz
  assert (select bool_and(relrowsecurity) from pg_class where oid in ('kunde_gruppe_rang'::regclass, 'gruppe_plan'::regclass)),
    '0117 (a1): eine der neuen Tabellen hat keinen Zeilenschutz';

  -- (c) der Betriebsleiter schreibt
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  insert into kunde_gruppe_rang (gruppe, rang) values ('Prüfgruppe 117', 1), ('Prüfgruppe 117 b', 2);
  insert into gruppe_plan (saison, gruppe, label, kg) values (2026, 'Prüfgruppe 117', 'D', 12000);
  reset role;
  assert (select count(*) from kunde_gruppe_rang where gruppe like 'Prüfgruppe 117%' and erfasser = v_u) = 2
     and (select erfasser = v_u and artikelgruppe = '' and groesse = '' from gruppe_plan where gruppe = 'Prüfgruppe 117'),
    '0117 (c1): der Betriebsleiter konnte nicht schreiben, oder der Erfasser fehlt';
  v_ok := false;
  begin insert into gruppe_plan (saison, gruppe, label, kg) values (2026, 'Prüfgruppe 117', 'D', 1); exception when unique_violation then v_ok := true; end;
  assert v_ok, '0117 (c2): derselbe Plan (Saison, Gruppe, Wahl) liess sich zweimal eintragen';
  v_ok := false;
  begin insert into gruppe_plan (saison, gruppe, kg) values (2026, 'Prüfgruppe 117', -5); exception when check_violation then v_ok := true; end;
  assert v_ok, '0117 (c3): ein negativer Plan liess sich eintragen';
  v_ok := false;
  begin insert into gruppe_plan (saison, gruppe, label, kg) values (2026, 'Prüfgruppe 117', 'X', 5); exception when check_violation then v_ok := true; end;
  assert v_ok, '0117 (c4): ein Label, das es nicht gibt, liess sich eintragen';
  v_ok := false;
  begin insert into kunde_gruppe_rang (gruppe, rang) values ('   ', 3); exception when check_violation then v_ok := true; end;
  assert v_ok, '0117 (c5): eine Gruppe ohne Namen liess sich ordnen';

  -- (b) die Halle liest, schreibt aber nicht
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_w::text, true);
  assert (select count(*) from kunde_gruppe_rang where gruppe like 'Prüfgruppe 117%') = 2
     and (select count(*) from gruppe_plan where gruppe = 'Prüfgruppe 117') = 1,
    '0117 (b1): die Halle sieht die Reihenfolge oder den Gruppenplan nicht';
  v_ok := false;
  begin insert into kunde_gruppe_rang (gruppe, rang) values ('Halle 117', 9); exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0117 (b2): eine Arbeiterin konnte die Reihenfolge der Gruppen setzen';
  v_ok := false;
  begin insert into gruppe_plan (saison, gruppe, kg) values (2026, 'Halle 117', 1); exception when insufficient_privilege then v_ok := true; end;
  assert v_ok, '0117 (b3): eine Arbeiterin konnte einen Gruppenplan setzen';
  reset role;

  delete from kunde_gruppe_rang where gruppe like 'Prüfgruppe 117%';
  delete from gruppe_plan where gruppe = 'Prüfgruppe 117';

  -- (d) Stand
  assert schema_stand() >= 117, format('0117 (d1): schema_stand() = %s', schema_stand());

  delete from profil where id in (v_u, v_w); delete from auth.users where id in (v_u, v_w);
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0117 — die Reihenfolge der Kundengruppen und der Plan einer ganzen Gruppe: Zeilenschutz, die Halle liest, nur der Betriebsleiter schreibt, ein Plan je Saison, Gruppe und Wahl, nie negativ';
end $$;

select '——— 0117 Kundengruppen in Reihe und mit Plan ———' as ergebnis;
