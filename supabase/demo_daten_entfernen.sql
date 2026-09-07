-- =====================================================================
-- DEMO-DATEN ENTFERNEN
--
-- Löscht restlos alles, was demo_daten.sql angelegt hat, und rührt echte
-- Daten nicht an. Erkennungsmerkmale: Aufträge mit bemerkung = 'DEMO',
-- Paletten mit extern_id 'demo-…', Sortierdateien 'DEMO-…'.
--
-- In der App geht dasselbe mit einem Klick:
-- Stammdaten → Demo-Daten → "Demo-Daten entfernen".
-- =====================================================================

-- Zwei Schritte in einer Abfrage: erst demo_daten_entfernen(), dann die Auswertung neu
-- rechnen. Das Rechnen steckt nicht in der Funktion, weil ein API-Aufruf bei
-- Supabase nach acht Sekunden abbricht — die App ruft es getrennt auf. Hier
-- erzwingt LATERAL die Reihenfolge: das Rechnen sieht das Ergebnis des Ladens
-- und läuft deshalb danach.
select a.ergebnis
  from (select demo_daten_entfernen() as ergebnis) a
  cross join lateral (select auswertung_aktualisieren() where a.ergebnis is not null) b;
