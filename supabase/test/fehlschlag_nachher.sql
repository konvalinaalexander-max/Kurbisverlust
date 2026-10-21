-- run.sh 3c, zweiter Teil: nach setup.sql (mit Zeitplan). Erst der Zustand, den
-- die App liest, dann der Lauf des Zeitplans — er muss mit der neuen Fassung
-- durchrechnen, und der zweite legt den Index mit den Bandgrenzen an.
set client_min_messages = warning;
do $$
declare v_ok boolean;
begin
  -- Was die App nach dem Einspielen sieht: leere Ansichten, der alte Fehler
  -- jünger als der Stand — und eine Anforderung, jünger als beide. Daran
  -- erkennt bauZustand (src/lib/zeitplan.ts) „wird gebaut" statt „gescheitert".
  assert (select not relispopulated from pg_class where oid = 'erg_kaliber'::regclass),
    '3c (a1): erg_kaliber ist nach setup.sql schon gefüllt — der Zustand „wird gebaut" ist nicht nachgestellt';
  assert (select fehler_ts > coalesce(berechnet_ts, '-infinity') and angefordert_ts > fehler_ts
            from auswertung_stand where id = 1),
    format('3c (a2): setup.sql hat nach dem Fehlschlag nicht neu angefordert: %s',
           (select format('berechnet %s, gescheitert %s, angefordert %s', berechnet_ts, fehler_ts, angefordert_ts)
              from auswertung_stand where id = 1));
  -- (b) der Zeitplan rechnet durch
  select auswertung_wenn_veraltet() into v_ok;
  assert v_ok and (select fehler is null and berechnet_ts > angefordert_ts from auswertung_stand where id = 1),
    format('3c (b1): der Zeitplan rechnet nach setup.sql nicht durch: %s',
           (select coalesce(fehler, 'kein Fehler, aber kein Stand') from auswertung_stand where id = 1));
  -- (c) der nächste Lauf legt den Index mit den Bandgrenzen an, ohne etwas zu entfernen
  update auswertung_stand set angefordert_ts = clock_timestamp() where id = 1;
  select auswertung_wenn_veraltet() into v_ok;
  assert v_ok and (select fehler is null from auswertung_stand where id = 1),
    format('3c (c1): der zweite Lauf scheitert: %s', (select fehler from auswertung_stand where id = 1));
  assert coalesce((select pg_get_indexdef(indexrelid) like '%(charge_nr, klasse, kaliber_idx, band_von, band_bis)%'
                     from pg_index where indexrelid = to_regclass('erg_kaliber_eindeutig')), false)
     and not exists (select 1 from auswertung_index_entfernt),
    '3c (c2): erg_kaliber hat nach dem zweiten Lauf keinen Index mit den Bandgrenzen, oder einer musste weg';
end $$;
