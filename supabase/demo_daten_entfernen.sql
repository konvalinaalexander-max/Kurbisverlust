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

select demo_daten_entfernen() as ergebnis;
