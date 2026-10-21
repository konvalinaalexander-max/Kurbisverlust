-- run.sh 3c, erster Teil: der Stand des Betriebs am 21. Oktober vor dem Einspielen.
-- Stand 118 mit Daten; zwei Nächte (die zweite legt die eindeutigen Indizes an);
-- dann Sortierläufe einer Charge in zwei weiteren Schemata; dann „Neu rechnen"
-- über den Zeitplan — und der scheitert, wie beim Betrieb.
set client_min_messages = error;   -- die Warnung des scheiternden Laufs ist hier gewollt
do $$
declare v_s int; v_lauf bigint; v_sorte text; v_k text;
begin
  update auswertung_stand set rechnet_seit = null where id = 1;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, true); end loop;
  for v_s in 1..5 loop perform auswertung_schritt_intern(v_s, true); end loop;
  assert to_regclass('erg_kaliber_eindeutig') is not null, '3c (vorab): nach zwei Nächten kein eindeutiger Index auf erg_kaliber';
  select l.id, c.sorte into v_lauf, v_sorte
    from sortier_lauf l join charge c on c.nr = l.charge_nr
   where l.auftrag_id is not null
     and exists (select 1 from sortier_gewicht g where g.lauf_id = l.id and g.klasse = 'kaliber' and g.kaliber_idx = 0)
   order by l.id limit 1;
  select code into v_k from kaeufer order by code limit 1;
  insert into sortierschema (id, sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender, kanal_ab) values
    (911901, v_sorte, v_k, date '2001-01-01', 'kaliber', 300, '[[411, 911], [911, 2000]]'::jsonb, 2000),
    (911902, v_sorte, v_k, date '2001-01-02', 'kaliber', 300, '[[411, 999], [999, 2000]]'::jsonb, 2000);
  insert into sortier_lauf
  select (jsonb_populate_record(null::sortier_lauf, to_jsonb(l) || jsonb_build_object(
            'id', 911900 + n, 'sortierschema_id', 911900 + n, 'datei_name', format('pruef-3c-%s.csv', n),
            'roh_pruefsumme', format('pruef-3c-%s', n), 'vorgaenger_id', null))).*
    from sortier_lauf l cross join generate_series(1, 2) n where l.id = v_lauf;
  insert into sortier_gewicht (lauf_id, gewicht_g, anzahl, klasse, kaliber_idx)
  select 911900 + n, g, 4, 'kaliber', i from generate_series(1, 2) n, (values (700, 0), (1200, 1)) x(g, i);
end $$;
set kuerbis.zeitplan_test = 'an';
select auswertung_anfordern() \g /dev/null
select auswertung_wenn_veraltet() \g /dev/null
do $$
begin
  assert (select fehler like 'could not create unique index%' and fehler_ts > coalesce(berechnet_ts, '-infinity')
            from auswertung_stand where id = 1),
    format('3c (vorab): die Rechnung auf Stand 118 scheitert nicht wie beim Betrieb: %s',
           (select coalesce(fehler, 'kein Fehler') from auswertung_stand where id = 1));
end $$;
