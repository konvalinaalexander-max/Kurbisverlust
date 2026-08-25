-- =====================================================================
-- DEMO-DATEN ENTFERNEN
--
-- Löscht restlos alles, was demo_daten.sql angelegt hat, und rührt echte
-- Daten nicht an. Erkennungsmerkmale: Aufträge mit bemerkung = 'DEMO',
-- Paletten mit extern_id 'demo-…', Sortierdateien 'DEMO-…'.
--
-- Reihenfolge ist wichtig: verdunstung_wiegung und sortier_lauf hängen mit
-- "on delete set null" am Auftrag — würde man den Auftrag zuerst löschen,
-- blieben ihre Zeilen verwaist zurück und zählten weiter mit.
-- =====================================================================

delete from verdunstung_wiegung
 where auftrag_id in (select id from auftrag where bemerkung = 'DEMO');

delete from ausgang_wiegung
 where auftrag_id in (select id from auftrag where bemerkung = 'DEMO');

delete from sortier_gewicht
 where lauf_id in (select id from sortier_lauf where datei_name like 'DEMO-%');
delete from sortier_lauf where datei_name like 'DEMO-%';

-- Der Rest hängt mit "on delete cascade" am Auftrag
delete from lieferung where bemerkung = 'DEMO';
delete from auftrag where bemerkung = 'DEMO';

delete from palette where extern_id like 'demo-%';

select format('Demo-Daten entfernt. Übrig: %s Paletten, %s Arbeiten, %s Sortierläufe.',
              (select count(*) from palette),
              (select count(*) from auftrag),
              (select count(*) from sortier_lauf)) as ergebnis;
