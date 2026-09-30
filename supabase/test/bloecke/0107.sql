
-- =====================================================================
-- 0107 — Gerechnet wird nachts und auf Knopfdruck, sonst nie
--
-- Am 29. September lag die Datenbank des Betriebs still: Der Zeitplan
-- rechnete tagsüber alle zehn Minuten die ganze Auswertung (89 s je Lauf),
-- und der Browser rechnete bei Journal-Abgleich und Löschen mit. Geprüft
-- wird ohne pg_cron:
-- (a) tagsüber: veraltet, nichts angefordert — kein Lauf, nur die Notiz,
--     zu keiner Stunde ausserhalb von 2 bis 5 Uhr;
-- (b) angefordert — ein Lauf, danach nichts mehr zu tun;
-- (c) nachts einmal: um 3 Uhr ein Lauf; ein zweiter in derselben Nacht,
--     vor 2 und ab 5 Uhr, ohne Neues keiner; Winterzeit; frisch eingespielt;
--     nach einem nächtlichen Fehlschlag erst in der nächsten Nacht;
-- (d) ein gescheiterter Lauf lässt die alten Zahlen stehen, merkt sich den
--     Fehler und wird nicht wiederholt; erst eine neue Anforderung rechnet
--     und räumt den Fehler weg;
-- (e) aus dem Browser mit Zeitplan wird nur angefordert, nie gerechnet —
--     auch mit der alten App (auswertung_schritt); ohne Zeitplan wie bisher;
-- (f) erg_palox_erwartung ist v_palox_erwartung, gerechnet in Schritt 3;
-- (g) die Drossel ist weg, der Lauf beendet keine fremden Sitzungen;
-- (h) Stand 107.
-- =====================================================================
do $$
declare v_st auswertung_stand; v_vorher timestamptz; v_erg jsonb; v_modus jsonb; v_lad text; v_n int;
  v_geladen boolean := false; v_u uuid := '00000000-0107-0000-0000-000000000001';
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0107"}');
  update profil set rolle = 'admin' where id = v_u;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  -- Ohne Paletten (im Volltest stehen hier Chargen ohne Paletten, ein Rest
  -- früherer Blöcke) die Demo frisch laden und am Ende wieder entfernen.
  if (select count(*) from palette) = 0 then
    perform demo_daten_entfernen();
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  perform auswertung_aktualisieren();
  update auswertung_stand set angefordert_ts = null, fehler_ts = null, fehler = null, rechnet_seit = null where id = 1;
  -- Seit 0108 zählt jeder begonnene Lauf; ein Rest aus einer früheren,
  -- gescheiterten Prüfung darf hier nicht als Abbruch gelten.
  if to_regclass('auswertung_versuch') is not null then
    execute 'update auswertung_stand set versuch_fertig = (select case when is_called then last_value else 0 end from auswertung_versuch) where id = 1';
  end if;
  perform set_config('kuerbis.jetzt_test', '2026-09-29 14:00+02', true);

  -- (a) tagsüber
  update auswertung_stand set geaendert_ts = clock_timestamp(), zeitplan_gerufen_ts = null where id = 1;
  select berechnet_ts into v_vorher from auswertung_stand where id = 1;
  assert not auswertung_wenn_veraltet(), '0107 (a1): tagsüber, etwas erfasst, nichts angefordert — und doch gerechnet';
  select * into v_st from auswertung_stand where id = 1;
  assert v_st.berechnet_ts = v_vorher, '0107 (a2): tagsüber ohne Anforderung wurde der Stand angefasst';
  assert v_st.zeitplan_gerufen_ts is not null, '0107 (a3): der Aufruf wurde nicht notiert (0098)';
  select count(*) into v_n from generate_series(0, 23) h
   where h not in (2, 3, 4)
     and auswertung_grund(('2026-09-29'::timestamp + make_interval(hours => h)) at time zone 'Europe/Zurich',
                          '2026-09-28 20:00+02', '2026-09-29 12:00+02', null, null) is not null;
  assert v_n = 0, format('0107 (a4): %s Stunden ausserhalb von 2 bis 5 Uhr rechnen ohne Anforderung', v_n);

  -- (b) angefordert
  v_erg := auswertung_anfordern();
  assert (v_erg ->> 'weg') = 'app', format('0107 (b0): ohne pg_cron weg app: %s', v_erg);
  assert auswertung_wenn_veraltet(), '0107 (b1): angefordert — und nicht gerechnet';
  select * into v_st from auswertung_stand where id = 1;
  assert v_st.berechnet_ts > v_vorher and v_st.berechnet_ts >= v_st.angefordert_ts, '0107 (b2): nach der Anforderung kein jüngerer Stand';
  assert not auswertung_wenn_veraltet(), '0107 (b3): erledigt — und doch noch einmal gerechnet';

  -- (c) nachts einmal
  perform set_config('kuerbis.jetzt_test', (((current_date + 1)::timestamp + interval '3 hours') at time zone 'Europe/Zurich')::text, true);
  update auswertung_stand set geaendert_ts = clock_timestamp() where id = 1;
  select berechnet_ts into v_vorher from auswertung_stand where id = 1;
  assert auswertung_wenn_veraltet(), '0107 (c1): nachts, tagsüber etwas erfasst — und nicht gerechnet';
  assert (select berechnet_ts from auswertung_stand where id = 1) > v_vorher, '0107 (c2): der nächtliche Lauf brachte keinen neuen Stand';
  perform set_config('kuerbis.jetzt_test', '2026-09-29 14:00+02', true);
  assert auswertung_grund('2026-09-30 03:00+02', '2026-09-29 08:00+02', '2026-09-29 13:00+02', null, null) = 'nachts',
    '0107 (c3): um drei Uhr, tagsüber erfasst — nicht fällig';
  assert auswertung_grund('2026-09-30 03:10+02', '2026-09-30 03:01+02', '2026-09-30 03:05+02', null, null) is null,
    '0107 (c4): ein zweiter Lauf in derselben Nacht';
  assert auswertung_grund('2026-09-30 01:59+02', '2026-09-29 08:00+02', '2026-09-29 13:00+02', null, null) is null,
    '0107 (c5): vor zwei Uhr gerechnet';
  assert auswertung_grund('2026-09-30 05:00+02', '2026-09-29 08:00+02', '2026-09-29 13:00+02', null, null) is null,
    '0107 (c6): ab fünf Uhr gerechnet';
  assert auswertung_grund('2026-09-30 03:00+02', '2026-09-29 20:00+02', '2026-09-29 13:00+02', null, null) is null,
    '0107 (c7): nachts, aber seit dem Stand nichts Neues — und doch fällig';
  assert auswertung_grund('2026-12-01 03:00+01', '2026-11-30 08:00+01', '2026-11-30 13:00+01', null, null) = 'nachts',
    '0107 (c8): in der Winterzeit um drei Uhr nicht fällig';
  assert auswertung_grund('2026-09-29 14:00+02', null, null, null, null) = 'erstmals',
    '0107 (c9): frisch eingespielt, nie gerechnet — nicht fällig';
  assert auswertung_grund('2026-09-29 14:00+02', null, null, null, '2026-09-29 13:00+02') is null,
    '0107 (c10): nie gerechnet und gescheitert — ohne Anforderung gleich wieder versucht';
  assert auswertung_grund('2026-09-30 03:10+02', '2026-09-29 08:00+02', '2026-09-29 13:00+02', null, '2026-09-30 02:30+02') is null,
    '0107 (c11): nachts gescheitert — in derselben Nacht wieder versucht';
  assert auswertung_grund('2026-10-01 03:00+02', '2026-09-29 08:00+02', '2026-09-29 13:00+02', null, '2026-09-30 02:30+02') = 'nachts',
    '0107 (c12): in der nächsten Nacht nicht wieder versucht';

  -- (d) Ein gescheiterter Lauf
  alter materialized view erg_bilanz rename to erg_bilanz_0107;
  update auswertung_stand set angefordert_ts = clock_timestamp(), geaendert_ts = clock_timestamp() where id = 1;
  select berechnet_ts into v_vorher from auswertung_stand where id = 1;
  select count(*) into v_n from auswertung_laufzeit;
  assert not auswertung_wenn_veraltet(), '0107 (d1): der Lauf ist gescheitert, meldet aber gerechnet';
  select * into v_st from auswertung_stand where id = 1;
  assert v_st.fehler_ts is not null and v_st.fehler like '%erg_bilanz%', format('0107 (d2): der Fehlschlag ist nicht gemerkt: %s', v_st.fehler);
  assert v_st.berechnet_ts = v_vorher, '0107 (d3): ein gescheiterter Lauf hat den Stand verschoben';
  -- Was der gescheiterte Lauf schon gerechnet hatte (Schritte 1 bis 3), ist
  -- zurückgerollt — erkennbar an seinen Laufzeit-Notizen, die mit ihm gehen —,
  -- und keine gespeicherte Ansicht ist leer: Die alten Zahlen stehen.
  assert (select count(*) from auswertung_laufzeit) = v_n,
    '0107 (d4): die Teilrechnung des gescheiterten Laufs ist nicht zurückgerollt';
  assert not exists (select 1 from pg_matviews where schemaname = 'public' and not ispopulated),
    '0107 (d4b): nach dem Fehlschlag ist eine gespeicherte Ansicht leer';
  -- Ein zweiter Versuch schlüge wieder fehl und sähe von aussen gleich aus wie
  -- keiner — darum zählt, dass der Fehlschlag nicht neu geschrieben wird.
  assert not auswertung_wenn_veraltet(), '0107 (d5): nach dem Fehlschlag beim nächsten Takt gleich wieder versucht';
  assert (select fehler_ts from auswertung_stand where id = 1) = v_st.fehler_ts,
    '0107 (d5b): nach dem Fehlschlag beim nächsten Takt gleich wieder versucht (der Fehlschlag ist neu geschrieben)';
  alter materialized view erg_bilanz_0107 rename to erg_bilanz;
  update auswertung_stand set angefordert_ts = clock_timestamp() where id = 1;
  assert auswertung_wenn_veraltet(), '0107 (d6): eine neue Anforderung nach dem Fehlschlag — und nicht gerechnet';
  select * into v_st from auswertung_stand where id = 1;
  assert v_st.fehler_ts is null and v_st.fehler is null, '0107 (d7): nach einem gelungenen Lauf steht der Fehler noch da';

  -- (e) Aus dem Browser
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  perform set_config('kuerbis.zeitplan_test', 'an', true);
  select berechnet_ts into v_vorher from auswertung_stand where id = 1;
  perform auswertung_aktualisieren();
  select * into v_st from auswertung_stand where id = 1;
  assert v_st.berechnet_ts = v_vorher, '0107 (e1): aus dem Browser mit Zeitplan wurde gerechnet';
  assert v_st.angefordert_ts > v_st.berechnet_ts, '0107 (e2): aus dem Browser mit Zeitplan wurde nicht angefordert';
  v_erg := auswertung_schritt(1);
  assert (v_erg ->> 'angefordert') = 'true' and (select berechnet_ts from auswertung_stand where id = 1) = v_vorher,
    format('0107 (e3): die alte App rechnete mit auswertung_schritt: %s', v_erg);
  v_erg := auswertung_schritt(5);
  assert (v_erg ->> 'fertig') = 'true' and (select berechnet_ts from auswertung_stand where id = 1) = v_vorher,
    '0107 (e4): Schritt 5 der alten App rechnet oder meldet sich nicht fertig';
  v_erg := auswertung_anfordern();
  assert (v_erg ->> 'weg') = 'zeitplan', format('0107 (e5): mit Zeitplan rechnet die App selbst: %s', v_erg);
  perform set_config('kuerbis.zeitplan_test', '', true);
  perform auswertung_aktualisieren();
  assert (select berechnet_ts from auswertung_stand where id = 1) > v_vorher, '0107 (e6): ohne Zeitplan rechnet auswertung_aktualisieren nicht mehr';
  perform set_config('request.jwt.claim.sub', '', true);

  -- (f) Die Palox-Erwartung gespeichert
  assert (select count(*) from erg_palox_erwartung) > 0
     and (select count(*) from erg_palox_erwartung) = (select count(*) from v_palox_erwartung)
     and not exists (select * from erg_palox_erwartung except select * from v_palox_erwartung),
    '0107 (f1): erg_palox_erwartung ist nicht v_palox_erwartung';
  assert exists (select 1 from auswertung_laufzeit where sicht = 'erg_palox_erwartung' and schritt = 3),
    '0107 (f2): erg_palox_erwartung wird nicht in Schritt 3 gerechnet';
  assert exists (select 1 from auswertung_schluessel() where sicht = 'erg_palox_erwartung'),
    '0107 (f3): erg_palox_erwartung ohne Schlüssel';

  -- (g) Keine Drossel, kein Beenden
  assert to_regprocedure('auswertung_drossel(integer)') is null and to_regprocedure('auswertung_drossel_min()') is null,
    '0107 (g1): die Drossel ist noch da';
  assert (select prosrc from pg_proc where proname = 'auswertung_wenn_veraltet') not like '%pg_terminate_backend%',
    '0107 (g2): der Lauf des Zeitplans beendet fremde Sitzungen';
  assert schema_stand() >= 107, format('0107 (h1): schema_stand() = %s', schema_stand());

  update auswertung_stand set angefordert_ts = null where id = 1;
  if v_geladen then perform demo_daten_entfernen(); end if;
  delete from profil where id = v_u;
  delete from auth.users where id = v_u;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0107 — gerechnet wird nachts einmal und auf „Neu rechnen", sonst nie; ein gescheiterter Lauf wird nicht wiederholt; der Browser rechnet nie, wo der Zeitplan da ist';
end $$;

select '——— 0107 Gerechnet wird nachts und auf Knopfdruck geprüft ———' as ergebnis;
