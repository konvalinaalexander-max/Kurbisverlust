import { test } from 'node:test'
import assert from 'node:assert/strict'
import { importErkennen, tabelleLesen, datumLesen, gebindeNormalisieren } from '../src/lib/import.ts'

// Ausschnitt der echten Charge-Registry (§7)
const CHARGEN = [
  { nr: 1613, schlag: 'Slowgrow Uster', sorte: 'Tiana' },
  { nr: 1616, schlag: 'Slowgrow Uster', sorte: 'Lekor' },
  { nr: 1606, schlag: 'Illnau Gross', sorte: 'Lekor' },
]

// So kommt der Tab „Ertragsjournal" aus dem Sheet: Zeile 1 Hinweis, Zeile 2 Köpfe.
const JOURNAL = [
  'Saisonstart: Journal ab Zeile 3 befüllen — diese Zeile nicht löschen',
  'Datum;Person;Schlag;Sorte;Gewicht brutto [kg];Anzahl Gebinde;Gebindeart (leer = G2);Bemerkung;Netto pro Palette [kg];Netto pro Kiste [kg];ID (App);Uhrzeit',
  '01.09.2026;Hans;Slowgrow Uster;Tiana;950;40;;;865;21.6;abc-1;08:12',
  '02.09.2026;Hans;Slowgrow Uster;Lekor;600;36;IFCO 6410;schön;526.04;14.6;abc-2;09:03',
  '03.09.2026;Eva;Illnau Gross;Lekor;500;36;;;426;11.8;abc-3;10:00',
].join('\n')

test('liest das Erntejournal, überspringt Hinweis- und Kopfzeile', () => {
  const b = importErkennen(JOURNAL, CHARGEN)
  assert.equal(b.quelle, 'schlag-sorte')
  assert.equal(b.paletten.length, 3)
  assert.equal(b.probleme.length, 0)
})

test('ordnet über Schlag + Sorte der richtigen Charge zu', () => {
  const b = importErkennen(JOURNAL, CHARGEN)
  assert.equal(b.paletten[0].charge_nr, 1613) // Slowgrow Uster · Tiana
  assert.equal(b.paletten[1].charge_nr, 1616) // Slowgrow Uster · Lekor
  assert.equal(b.paletten[2].charge_nr, 1606) // Illnau Gross · Lekor
})

test('leere Gebindeart wird zu G2, gefüllte bleibt', () => {
  const b = importErkennen(JOURNAL, CHARGEN)
  assert.equal(b.paletten[0].gebindeart, 'G2')
  assert.equal(b.paletten[1].gebindeart, 'IFCO 6410')
})

test('nimmt die App-ID aus Spalte K als stabile Kennung', () => {
  const b = importErkennen(JOURNAL, CHARGEN)
  assert.equal(b.paletten[0].extern_id, 'journal:abc-1')
})

test('wandelt das deutsche Datum in ISO', () => {
  const b = importErkennen(JOURNAL, CHARGEN)
  assert.equal(b.paletten[0].eingangsdatum, '2026-09-01')
})

test('meldet unbekannte Schlag-Sorte-Kombinationen, statt sie zu verschlucken', () => {
  const mit = JOURNAL + '\n04.09.2026;Eva;Unbekannt;Tiana;800;36;;;;;abc-4;11:00'
  const b = importErkennen(mit, CHARGEN)
  assert.equal(b.paletten.length, 3)
  assert.equal(b.probleme.length, 1)
  assert.match(b.probleme[0], /Unbekannt · Tiana/)
})

test('überspringt Summen-/Leerzeilen ohne Bruttogewicht', () => {
  const mit = JOURNAL + '\n;;;;;;;;;;;\nSumme;;;;;;;;;;;'
  const b = importErkennen(mit, CHARGEN)
  assert.equal(b.paletten.length, 3)
})

test('versteht auch die alte Kopie-Vorlage mit Chargennummer-Spalte', () => {
  const alt = [
    'Charge\tDatum\tBrutto\tKisten\tGebinde',
    '1613\t01.09.2026\t950\t40\tG2',
    '9999\t02.09.2026\t900\t40\tG2',
  ].join('\n')
  const b = importErkennen(alt, CHARGEN)
  assert.equal(b.quelle, 'chargennummer')
  assert.equal(b.paletten.length, 1)
  assert.equal(b.paletten[0].charge_nr, 1613)
  assert.equal(b.probleme.length, 1) // 9999 unbekannt
})

test('erkennt Semikolon, Tab und Komma als Trenner', () => {
  assert.equal(tabelleLesen('a;b;c')[0].length, 3)
  assert.equal(tabelleLesen('a\tb\tc')[0].length, 3)
  assert.equal(tabelleLesen('a,b,c')[0].length, 3)
})

test('Komma-CSV mit Anführungszeichen um ein Feld mit Komma', () => {
  const z = tabelleLesen('1,"Böhler, Daniel",3')
  assert.deepEqual(z[0], ['1', 'Böhler, Daniel', '3'])
})

test('datumLesen akzeptiert deutsch und ISO, weist Unsinn ab', () => {
  assert.equal(datumLesen('01.09.2026'), '2026-09-01')
  assert.equal(datumLesen('2026-09-01'), '2026-09-01')
  assert.equal(datumLesen('1.9.26'), '2026-09-01')
  assert.equal(datumLesen('Quatsch'), null)
})

test('gebindeNormalisieren macht aus leer G2', () => {
  assert.equal(gebindeNormalisieren(''), 'G2')
  assert.equal(gebindeNormalisieren('  '), 'G2')
  assert.equal(gebindeNormalisieren('IFCO 6416'), 'IFCO 6416')
})
