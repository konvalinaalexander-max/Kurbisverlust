
-- =====================================================================
-- 0108 — Ein abgebrochener Lauf wird nicht wiederholt
--
-- Die Nacht vom 29. auf den 30. September: Die Datenbank blieb nach dem
-- Neustart krank, weil ein abgebrochener Lauf nichts von sich wusste und
-- jede Minute von vorn begann. Geprüft wird:
-- (a) ein Lauf, der seine Nummer gezogen hat und nie fertig wurde, gilt als
--     Fehlschlag — kein Lauf, der Fehler steht, der Stand bleibt; der
--     nächste Takt rechnet auch nicht; erst eine neue Anforderung, und
--     danach rechnet jede weitere Anforderung wieder;
-- (b) der Stand ist der Beginn des Laufs, nicht sein Ende;
-- (c) die Umstellungsnacht (25.10.) wiederholt keinen gescheiterten Lauf,
--     eine gewöhnliche Nacht rechnet weiter;
-- (d) „Neu rechnen" schaltet einen abgeschalteten Zeitplan nicht ein, und
--     der Browser fragt nur noch, ob pg_cron da ist;
-- (e) ein Lauf darf höchstens 15 Minuten dauern; (f) Stand 108.
-- =====================================================================
do $$
declare v_st auswertung_stand; v_vorher timestamptz; v_n int; v_id bigint; v_modus jsonb; v_lad text;
  v_geladen boolean := false; v_fehler timestamptz; v_def text;
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  if (select count(*) from palette) = 0 then
    perform demo_daten_entfernen();
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  perform auswertung_aktualisieren();
  -- Ausgangslage: kein Lauf offen, kein Fehler, nichts angefordert
  update auswertung_stand
     set versuch_fertig = (select case when is_called then last_value else 0 end from auswertung_versuch),
         fehler_ts = null, fehler = null, angefordert_ts = null
   where id = 1;
  perform set_config('kuerbis.jetzt_test', '2026-09-29 14:00+02', true);

  -- (a) Ein abgebrochener Lauf: Nummer gezogen, nie fertig
  perform auswertung_anfordern();
  perform nextval('auswertung_versuch');                  -- der Lauf, der starb
  select berechnet_ts into v_vorher from auswertung_stand where id = 1;
  assert not auswertung_wenn_veraltet(), '0108 (a1): nach einem abgebrochenen Lauf gleich wieder gerechnet';
  select * into v_st from auswertung_stand where id = 1;
  assert v_st.fehler like 'Lauf abgebrochen%' and v_st.fehler_ts is not null,
    format('0108 (a2): der Abbruch ist nicht als Fehlschlag gemerkt: %s', v_st.fehler);
  assert v_st.versuch_fertig = (select last_value from auswertung_versuch), '0108 (a3): der Abbruch ist nicht abgehakt';
  assert v_st.berechnet_ts = v_vorher, '0108 (a4): der Stand hat sich trotz Abbruch verschoben';
  v_fehler := v_st.fehler_ts;
  assert not auswertung_wenn_veraltet(), '0108 (a5): beim nächsten Takt dieselbe Anforderung noch einmal gerechnet';
  assert (select fehler_ts from auswertung_stand where id = 1) = v_fehler, '0108 (a6): beim nächsten Takt versucht (Fehlschlag neu geschrieben)';
  perform auswertung_anfordern();
  assert auswertung_wenn_veraltet(), '0108 (a7): eine neue Anforderung nach dem Abbruch — und nicht gerechnet';
  assert (select fehler_ts is null and fehler is null from auswertung_stand where id = 1), '0108 (a8): nach dem gelungenen Lauf steht der Abbruch noch';
  perform auswertung_anfordern();
  assert auswertung_wenn_veraltet(), '0108 (a9): nach einem gelungenen Lauf rechnet die nächste Anforderung nicht (die Nummer wurde nicht abgehakt)';

  -- (b) Der Stand ist der Beginn des Laufs
  select coalesce(max(id), 0) into v_id from auswertung_laufzeit;
  perform auswertung_anfordern();
  assert auswertung_wenn_veraltet(), '0108 (b0): angefordert — und nicht gerechnet';
  assert (select berechnet_ts from auswertung_stand where id = 1) <= (select min(ts) from auswertung_laufzeit where id > v_id),
    '0108 (b1): der Stand ist das Ende des Laufs, nicht sein Beginn — was währenddessen erfasst wird, gälte als gerechnet';

  -- (c) Die Umstellungsnacht
  assert auswertung_grund('2026-10-25 02:45+02', '2026-10-24 08:00+02', '2026-10-24 13:00+02', null, '2026-10-25 02:30+02') is null,
    '0108 (c1): in der Umstellungsnacht wird ein gescheiterter Nachtlauf wiederholt';
  assert auswertung_grund('2026-10-25 03:30+01', '2026-10-24 08:00+02', '2026-10-24 13:00+02', null, null) = 'nachts',
    '0108 (c2): in der Umstellungsnacht wird gar nicht gerechnet';
  assert auswertung_grund('2026-09-30 02:10+02', '2026-09-29 23:30+02', '2026-09-29 23:45+02', null, null) = 'nachts',
    '0108 (c3): nach einem Lauf am Vorabend wird nachts nicht nachgeholt, was danach erfasst wurde';

  -- (d) Notaus hält, der Browser fragt nur nach pg_cron
  v_def := pg_get_functiondef('auswertung_anfordern()'::regprocedure);
  assert v_def not like '%active => true%', '0108 (d1): „Neu rechnen" schaltet einen abgeschalteten Zeitplan wieder ein';
  assert v_def like '%''weg'', ''aus''%', '0108 (d2): „Neu rechnen" sagt nicht, dass der Zeitplan abgeschaltet ist';
  assert pg_get_functiondef('auswertung_aktualisieren()'::regprocedure) like '%auswertung_cron_da()%'
     and pg_get_functiondef('auswertung_schritt(integer)'::regprocedure) like '%auswertung_cron_da()%',
    '0108 (d3): der Browser rechnet, wenn der Zeitplan abgeschaltet ist';
  assert to_regprocedure('auswertung_zeitplan_aktiv()') is null, '0108 (d4): auswertung_zeitplan_aktiv() steht noch';

  -- (e) Höchstens 15 Minuten
  assert (select array_to_string(setconfig, ',') from pg_db_role_setting
           where setrole = 'postgres'::regrole and setdatabase = 0) like '%statement_timeout=15min%',
    '0108 (e1): die Zeitgrenze der Rolle postgres ist nicht 15 Minuten';
  assert schema_stand() >= 108, format('0108 (f1): schema_stand() = %s', schema_stand());

  update auswertung_stand set angefordert_ts = null where id = 1;
  if v_geladen then perform demo_daten_entfernen(); end if;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0108 — ein abgebrochener Lauf wird gemerkt und nicht wiederholt; der Stand ist der Beginn des Laufs; die Umstellungsnacht rechnet keine Schleife; der Notaus hält; höchstens 15 Minuten';
end $$;

select '——— 0108 Ein abgebrochener Lauf wird nicht wiederholt geprüft ———' as ergebnis;
