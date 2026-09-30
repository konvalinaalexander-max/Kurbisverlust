-- 0110 — Rechnen auf PostgreSQL 17
--
-- WARUM
--
-- Nach dem Einspielen von Stand 109 (30. September, 06:14) scheiterte der
-- erste Lauf im Betrieb nach acht Sekunden: „function palox_f(numeric,
-- numeric, numeric, numeric, numeric) does not exist". Die Funktion gibt es.
-- Aber der Betrieb läuft auf PostgreSQL 17, und seit 17 frischt Postgres
-- gespeicherte Ansichten mit dem Suchpfad „pg_catalog, pg_temp" auf, nicht
-- mehr mit dem des Aufrufers. Eine SQL-Funktion ohne eigenen Suchpfad findet
-- dann nur, was sie mit Schema nennt. palox_f_nach() (0106) nennt palox_f()
-- ohne „public." — erg_prognose und alles, was die Stationswerte
-- fortschreibt, scheitert daran; seit 0106 ist im Betrieb keine Rechnung
-- mehr durchgelaufen (die letzte stammt vom 29.9., 17:09, Stand 105). Die
-- Prüfstände liefen auf PostgreSQL 16 und sahen es nicht; seit dieser Runde
-- laufen sie (CI) auf 17, und der Prüfblock stellt den Suchpfad von 17 nach.
--
-- WAS 0110 TUT
--
-- palox_f_nach() nennt palox_f() mit Schema, wie palox_tara_kg() und
-- sortierschema_fuer() es schon tun. Die Formel ist dieselbe; die Funktion
-- bleibt eine SQL-Funktion ohne SET, damit der Planer sie weiter einsetzen
-- kann. Die übrigen Funktionen ohne festen Suchpfad, die public-Objekte ohne
-- Schema nennen (csv_lauf_speichern, csv_sammel_speichern,
-- lauf_neu_klassieren, lesung_als_sammel), ruft nur die App auf, mit dem
-- Suchpfad der Schnittstelle — beim Auffrischen kommen sie nicht vor.

create or replace function palox_f_nach(p_hand numeric, p_wasch numeric, f_ws numeric, f_s numeric, g_w numeric,
                                        b_ws numeric, b_s numeric, g_b numeric, d_tage numeric)
returns numeric language sql immutable as $$
  select public.palox_f(p_hand, p_wasch,
                 case when f_ws is null then null else least(greatest(f_ws + coalesce(b_ws, 0) * d_tage / 7.0, 0), 1) end,
                 case when f_s  is null then null else least(greatest(f_s  + coalesce(b_s,  0) * d_tage / 7.0, 0), 1) end,
                 case when g_w  is null then null else least(greatest(g_w  + coalesce(g_b,  0) * d_tage / 7.0, 0), 1) end)
$$;
comment on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) is
  'palox_f() d Tage später: jede Station um ihren Zuwachs je Woche (Kennzahl 0105) fortgeschrieben (0106). '
  'Nennt palox_f mit Schema, weil PostgreSQL 17 beim Auffrischen nur pg_catalog sucht (0110).';
revoke all on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) from public;
grant execute on function palox_f_nach(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) to authenticated;

create or replace function schema_stand() returns int
language sql immutable set search_path = public as $$ select 110 $$;
