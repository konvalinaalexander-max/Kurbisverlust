-- =====================================================================
-- 0042 — Funktionen dürfen sich nicht auf den Suchpfad verlassen
--
-- Beim Einrichten in Supabase brach setup.sql ab:
--
--   ERROR: relation "einstellung" does not exist
--   QUERY: select coalesce((select (wert #>> '{}')::numeric from einstellung …
--   CONTEXT: SQL function "palox_tara_kg" during inlining
--
-- Der Grund ist eine Eigenheit von Postgres, die man leicht übersieht. Der
-- Rumpf einer SQL-Funktion ist Text. Beim Planen einer Abfrage setzt Postgres
-- ihn ein („inlining") und löst die Namen darin **in diesem Moment** auf, mit
-- dem Suchpfad der aufrufenden Sitzung. In einer Ansicht steht der Verweis auf
-- die Funktion dagegen als feste Kennung — die Ansicht findet die Funktion
-- also immer, und erst der Rumpf fällt auf die Nase.
--
-- Läuft das Skript in einer Sitzung, deren Suchpfad `public` nicht enthält —
-- und der SQL-Editor mancher Anbieter tut genau das —, dann kennt der Rumpf
-- die Tabelle nicht, obwohl sie zwei Bildschirmseiten weiter oben angelegt
-- wurde. Lokal fiel das nie auf, weil psql `public` im Pfad hat.
--
-- Zwei Antworten darauf, je nachdem, was die Funktion kostet:
--
--   * Wo die Funktion je Zeile eingesetzt wird (palox_tara_kg in v_palox_stand,
--     klassiere je Gewichtsstufe, schimmelanteil in den Kaskaden-Ansichten),
--     stehen die Tabellen jetzt mit `public.` davor. Das Einsetzen bleibt
--     erlaubt, das Tempo also auch.
--   * Alle übrigen bekommen einen festen Suchpfad. Das verhindert das
--     Einsetzen — bei einer Funktion, die einmal je Abfrage läuft, ist das
--     kein Verlust, und es macht sie ein für alle Mal unabhängig davon, wer
--     sie aufruft.
--
-- Der Prüflauf fährt seither die ganze Kaskade einmal mit leerem Suchpfad
-- durch. Wäre das früher dagewesen, hätte der Fehler den Betrieb nie erreicht.
-- =====================================================================

do $$
declare z record;
begin
  for z in
    select p.oid::regprocedure::text as sig, p.prokind
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
       -- Schon gesetzt? Dann nichts zu tun.
       and (p.proconfig is null
            or not exists (select 1 from unnest(p.proconfig) c where c like 'search\_path=%'))
       -- Diese sollen eingesetzt werden dürfen: ihre Rümpfe nennen die
       -- Tabellen ausdrücklich mit Schema, oder sie fassen gar keine an.
       and p.proname not in ('palox_tara_kg', 'palox_letzter_stand', 'klassiere',
                             'schimmelanteil', 'schimmel_n', 'sockel_anteil',
                             'sortierschema_fuer', 't_quantil_95',
                             'anteil_plausibel', 'korrekturfenster')
  loop
    execute format('alter %s %s set search_path = public',
                   case z.prokind when 'p' then 'procedure' else 'function' end, z.sig);
  end loop;
end $$;
