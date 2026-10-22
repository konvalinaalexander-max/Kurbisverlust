import { test } from 'node:test'
import assert from 'node:assert/strict'
import { abgleichMeldung, importErkennen, tabelleLesen, datumLesen, gebindeNormalisieren } from '../src/lib/import.ts'

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

// Runde AS: „neue Chargen, Ötli 1719 und Trüb 1763 … schau, dass du damit
// umgehen kannst". Steht die Nummer mit Schlag und Sorte im Journal, legt der
// Import die Charge an; sonst sagt er, wo man sie anlegt.
const MIT_NUMMER = [
  'Charge;Datum;Schlag;Sorte;Gewicht brutto [kg];Anzahl Gebinde;Gebindeart (leer = G2);ID (App)',
  '1613;01.09.2026;Slowgrow Uster;Tiana;950;40;;n-1',
  '1719;15.10.2026;Oettli;Butternut;300;1;Holzpalox;n-2',
  '1719;16.10.2026;Oettli;Butternut;310;1;Palox Holz;n-3',
  '1763;16.10.2026;Trüb;Muscade;280;1;Plastik-Palox;n-4',
].join('\n')

test('eine neue Chargennummer mit Schlag und Sorte wird angelegt, einmal, mit der Saison ihres ersten Eingangs', () => {
  const b = importErkennen(MIT_NUMMER, CHARGEN)
  assert.deepEqual(b.probleme, [])
  assert.deepEqual(b.neueChargen, [
    { nr: 1719, schlag: 'Oettli', sorte: 'Butternut', saison: 2026 },
    { nr: 1763, schlag: 'Trüb', sorte: 'Muscade', saison: 2026 }])
  assert.deepEqual(b.paletten.map(p => p.charge_nr), [1613, 1719, 1719, 1763])
})

test('eine falsche Nummer zu bekanntem Schlag und Sorte legt keine zweite Charge an', () => {
  const tipp = 'Charge;Datum;Schlag;Sorte;Gewicht brutto [kg]\n1631;01.09.2026;Slowgrow Uster;Tiana;950'
  const b = importErkennen(tipp, CHARGEN)
  assert.deepEqual(b.neueChargen, [])
  assert.equal(b.paletten[0].charge_nr, 1613, 'wie bisher über Schlag und Sorte')
})

test('eine neue Nummer ohne Sorte bleibt ein Problem mit dem Weg zu den Stammdaten', () => {
  const ohne = 'Charge;Datum;Schlag;Sorte;Gewicht brutto [kg]\n1719;15.10.2026;Oettli;;300'
  const b = importErkennen(ohne, CHARGEN)
  assert.deepEqual(b.neueChargen, [])
  assert.equal(b.paletten.length, 0)
  assert.match(b.probleme[0], /Charge 1719 ist neu.*Stammdaten/)
})

test('Paloxen heissen wie in der Gebinde-Tabelle, gleich wie man sie schreibt', () => {
  for (const roh of ['Holzpalox', 'Holz Palox', 'Palox Holz', 'holz-palox', 'Holzpaloxe'])
    assert.equal(gebindeNormalisieren(roh), 'Holz Palox', roh)
  for (const roh of ['Plastikpalox', 'Plastik-Palox', 'Kunststoff Palox', 'Palox Plastik'])
    assert.equal(gebindeNormalisieren(roh), 'Plastik Palox', roh)
  assert.equal(gebindeNormalisieren('Palox'), 'Palox', 'ohne Holz oder Plastik bleibt es, wie es steht')
  const b = importErkennen(MIT_NUMMER, CHARGEN)
  assert.deepEqual(b.paletten.map(p => p.gebindeart), ['G2', 'Holz Palox', 'Holz Palox', 'Plastik Palox'])
})

// 22. Oktober: „Ötli und Trüeb … im Google Sheet sind sie drin, aber sie kommen
// nicht in der Kürbis-App an." Das Journal hat keine Chargennummer; 0120 trägt
// Oettli · Kaori Kuri = 1719 und Trüeb · Amoro = 1763 ins Register ein,
// geschrieben wie im Journal.
const REGISTER_0120 = [...CHARGEN,
  { nr: 1719, schlag: 'Oettli', sorte: 'Kaori Kuri' },
  { nr: 1763, schlag: 'Trüeb', sorte: 'Amoro' }]
const NEUE_SCHLAEGE = [
  'Datum;Person;Schlag;Sorte;Gewicht brutto [kg];Anzahl Gebinde;Gebindeart (leer = G2);ID (App)',
  '20.10.2026;Hans;Slowgrow Uster;Tiana;950;40;;o-1',
  '20.10.2026;Hans;Oettli;Kaori Kuri;420;1;Holzpalox;o-2',
  '21.10.2026;Eva;Trüeb;Amoro;380;1;Plastik-Palox;o-3',
].join('\n')

test('Oettli und Trüeb finden ihre Charge über Schlag und Sorte, wie im Journal geschrieben', () => {
  const b = importErkennen(NEUE_SCHLAEGE, REGISTER_0120)
  assert.deepEqual(b.probleme, [])
  assert.deepEqual(b.paletten.map(p => p.charge_nr), [1613, 1719, 1763])
  assert.deepEqual(b.neueChargen, [], 'die Chargen stehen im Register, angelegt wird nichts')
})

test('ein ü, das als u + Trema ankommt, ist dasselbe ü', () => {
  const zerlegt = NEUE_SCHLAEGE.replace('Trüeb', 'Tru\u0308eb')
  assert.notEqual(zerlegt, NEUE_SCHLAEGE)
  const b = importErkennen(zerlegt, REGISTER_0120)
  assert.deepEqual(b.probleme, [])
  assert.equal(b.paletten[2].charge_nr, 1763)
  // und ein anderer Umlaut ist ein anderer Schlag
  const anders = importErkennen(NEUE_SCHLAEGE.replace('Trüeb', 'Tröeb'), REGISTER_0120)
  assert.equal(anders.paletten.length, 2)
  assert.match(anders.probleme[0], /Tröeb · Amoro/)
})

test('ohne Register-Eintrag schweigt der Abgleich nicht, auch wenn sonst nichts neu ist', () => {
  const b = importErkennen(NEUE_SCHLAEGE, CHARGEN)
  assert.equal(b.probleme.length, 2)
  const m = abgleichMeldung(0, [], b.probleme)
  assert.equal(m?.art, 'warnung')
  assert.match(m?.text ?? '', /stehen 2 Zeilen, die die App keiner Charge zuordnen kann/)
  assert.match(m?.text ?? '', /Oettli · Kaori Kuri/)
  assert.match(m?.text ?? '', /und ein weiterer Grund/)
  assert.doesNotMatch(m?.text ?? '', /Zeile \d+:/, 'die Zeilennummer gehört nicht in die Meldung beim Öffnen')
  assert.match(m?.text ?? '', /Sie kommen erst an/)
  assert.match(abgleichMeldung(0, [], [b.probleme[0]])?.text ?? '', /steht eine Zeile.*Sie kommt erst an/)
})

test('der Abgleich sagt, was neu ist, und nichts, wenn nichts ist', () => {
  assert.equal(abgleichMeldung(0, [], []), null)
  const gut = abgleichMeldung(3, [1719], [])
  assert.equal(gut?.art, 'gut')
  assert.match(gut?.text ?? '', /^3 neue Paletten aus dem Erntejournal übernommen · eine neue Charge angelegt \(1719\)\./)
  const beides = abgleichMeldung(1, [], ['Zeile 7: keine Charge für „X · Y"'])
  assert.match(beides?.text ?? '', /^1 neue Palette .* · eine Zeile ohne Charge \(keine Charge für „X · Y"\)/)
})
