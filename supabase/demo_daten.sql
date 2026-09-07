-- =====================================================================
-- DEMO-DATEN — eine erfundene, aber realistische Saison zum Durchklicken
--
-- Zweck: Das Dashboard zeigt ohne Daten nichts. Diese Datei füllt die
-- Datenbank mit einer vollständigen Saison, damit man sieht, was am Ende
-- herauskommt — bevor die erste echte Palette gezählt ist.
--
-- DER BEQUEMERE WEG
--   In der App: Stammdaten → Demo-Daten → "Demo-Saison laden". Ein Klick,
--   dasselbe Ergebnis. Diese Datei ist nur da, wenn man lieber im
--   SQL-Editor arbeitet.
--
-- SO WIRD SIE BENUTZT
--   1. Inhalt kopieren, im Supabase-SQL-Editor einfügen, Run.
--   2. In der App als Betriebsleiter anmelden und durch die Auswertung klicken.
--   3. Wenn die echten Daten kommen: supabase/demo_daten_entfernen.sql
--      einspielen — dann ist alles Erfundene wieder weg.
--
-- Alles Erfundene ist markiert: Aufträge tragen bemerkung = 'DEMO',
-- Paletten haben extern_id 'demo-…', Sortierdateien beginnen mit 'DEMO-'.
-- Echte Daten werden nicht angefasst.
--
-- Die Zahlen sind so gewählt, dass realistische Koeffizienten entstehen:
-- rund 0.06 % Verdunstung je Tag, 1–5 % Schimmel je nach Lagerdauer,
-- ~3 % Ausschuss, ~1.5 % Nebenkanal, ~0.3 kg Überfüllung je Kiste.
--
-- Die Saison selbst steht in supabase/migrations/0034_demo_knopf.sql, damit
-- App-Knopf und SQL-Datei nicht zwei Fassungen derselben Sache werden, die
-- mit der Zeit auseinanderlaufen.
-- =====================================================================

-- Zwei Schritte in einer Abfrage: erst demo_daten_laden(), dann die Auswertung neu
-- rechnen. Das Rechnen steckt nicht in der Funktion, weil ein API-Aufruf bei
-- Supabase nach acht Sekunden abbricht — die App ruft es getrennt auf. Hier
-- erzwingt LATERAL die Reihenfolge: das Rechnen sieht das Ergebnis des Ladens
-- und läuft deshalb danach.
select a.ergebnis
  from (select demo_daten_laden() as ergebnis) a
  cross join lateral (select auswertung_aktualisieren() where a.ergebnis is not null) b;
