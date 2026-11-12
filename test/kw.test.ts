/**
 * AB-226: KW-Planung — was in welcher Kalenderwoche an welchen Kunden ging.
 *
 * Runde BL. Der Betrieb: „Erste Spalte Produkt, die nächsten Spalten die KWs,
 * die ausgesucht sind, rechts davon Summe. … schon nur die, die tatsächlich
 * verkauft worden sind. … Wenn ich mehrere Kunden anklicke, zwei Tabellen
 * untereinander. … dass man ganze Kategorien anklicken kann oder nur einzelne
 * Kunden."
 *
 * Geprüft wird die Regel (src/auswertung/kw.ts): die Kalenderwoche nach ISO,
 * die Liste der Wochen der Saison bis heute, und dass die Tabelle nichts
 * weglässt und nichts erfindet — ihre Summe ist die Summe der Positionen.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { gruppeWahl, isoWoche, kundeWahl, kundenDerWahl, kundenGruppen, kwName, kwTabelle, wocheMontag, wochenDerSaison, wochenText }
  from '../src/auswertung/kw.ts'
import type { KundeTag } from '../src/auswertung/daten.ts'

const zeile = (kunde: string, datum: string, gruppe: string | null, groesse: string, label: string | null, kg: number | null, mehr: Partial<KundeTag> = {}): KundeTag =>
  ({ kunde, saison: Number(datum.slice(5, 7)) >= 7 ? Number(datum.slice(0, 4)) : Number(datum.slice(0, 4)) - 1, datum, gruppe, groesse, label, kg,
     positionen: 1, stueck_ohne_gewicht: null, positionen_ohne_gewicht: 0, ...mehr })

test('die Kalenderwoche nach ISO: Montag bis Sonntag, über den Jahreswechsel richtig', () => {
  assert.equal(isoWoche('2026-11-12').schluessel, '2026-W46')
  assert.equal(isoWoche('2026-11-09').schluessel, '2026-W46', 'Montag gehört zur Woche')
  assert.equal(isoWoche('2026-11-15').schluessel, '2026-W46', 'Sonntag auch')
  assert.equal(isoWoche('2026-11-16').schluessel, '2026-W47')
  assert.equal(isoWoche('2026-08-11').schluessel, '2026-W33', 'die erste Lieferung der Saison im Betrieb')
  // 2026 hat 53 Wochen (der 1. Januar ist ein Donnerstag)
  assert.equal(isoWoche('2026-12-31').schluessel, '2026-W53')
  assert.equal(isoWoche('2027-01-03').schluessel, '2026-W53', 'der Sonntag gehört noch zum alten Jahr')
  assert.equal(isoWoche('2027-01-04').schluessel, '2027-W01')
  assert.equal(isoWoche('2026-01-01').schluessel, '2026-W01')
  assert.equal(isoWoche('2025-12-29').schluessel, '2026-W01', 'der Montag der KW 1 liegt im alten Jahr')
})

test('der Montag einer Woche und zurück', () => {
  assert.equal(wocheMontag('2026-W46'), '2026-11-09')
  assert.equal(wocheMontag('2026-W01'), '2025-12-29')
  assert.equal(wocheMontag('2027-W01'), '2027-01-04')
  for (const w of ['2026-W33', '2026-W53', '2027-W01', '2027-W26']) assert.equal(isoWoche(wocheMontag(w)).schluessel, w)
})

test('die Wochen der Saison: von der ersten Lieferung bis zur laufenden Woche, lückenlos — nächste Woche eine mehr', () => {
  const zeilen = [zeile('A', '2026-08-11', 'Knirps', 'klein', 'D', 100), zeile('A', '2026-09-30', 'Knirps', 'klein', 'D', 50),
                  zeile('A', '2025-10-01', 'Knirps', 'klein', 'D', 70)]                       // Vorjahr: zählt nicht
  const w = wochenDerSaison(zeilen, 2026, '2026-11-12')
  assert.equal(w[0], '2026-W33')
  assert.equal(w[w.length - 1], '2026-W46')
  assert.equal(w.length, 14, 'KW 33 bis KW 46, auch die Wochen ohne Lieferung')
  assert.equal(wochenDerSaison(zeilen, 2026, '2026-11-16').length, 15, 'am Montag darauf steht KW 47 in der Liste')
  // über den Jahreswechsel: KW 53 und dann KW 1
  const lang = wochenDerSaison(zeilen, 2026, '2027-01-06')
  assert.deepEqual(lang.slice(-3), ['2026-W52', '2026-W53', '2027-W01'])
  assert.deepEqual(wochenDerSaison(zeilen, 2027, '2027-08-01'), [], 'eine Saison ohne Lieferung hat keine Wochen')
})

const ZEILEN: KundeTag[] = [
  zeile('Laden Nord', '2026-11-02', 'Knirps', 'klein', 'D', 120),      // KW 45
  zeile('Laden Nord', '2026-11-04', 'Knirps', 'klein', 'D', 80),       // KW 45, derselbe Artikel
  zeile('Laden Nord', '2026-11-10', 'Knirps', 'klein', 'D', 60),       // KW 46
  zeile('Laden Nord', '2026-11-10', 'Knirps', 'klein', 'K', 40),       // KW 46, anderes Label: eigene Zeile
  zeile('Laden Nord', '2026-11-11', 'Knirps', 'gross', 'D', 200),      // KW 46
  zeile('Laden Nord', '2026-11-11', 'Butternut', 'lose', null, 30),    // KW 46, Label unbekannt
  zeile('Laden Nord', '2026-10-20', 'Mix', 'lose', 'K', 500),          // KW 43 — nicht gewählt
  zeile('Laden Süd', '2026-11-10', 'Knirps', 'klein', 'D', 1000),      // anderer Kunde
  zeile('Laden Nord', '2025-11-10', 'Knirps', 'klein', 'D', 9999),     // Vorjahr
  zeile('Laden Nord', '2026-11-12', 'Mandarin', 'lose', 'D', null, { positionen: 2, stueck_ohne_gewicht: 48, positionen_ohne_gewicht: 2 }),
]

test('die Tabelle: je Artikel eine Zeile, je gewählter Woche eine Spalte, rechts die Summe', () => {
  const t = kwTabelle(ZEILEN, ['Laden Nord'], ['2026-W45', '2026-W46'], 2026)
  assert.deepEqual(t.artikel.map(a => [a.gruppe, a.groesse, a.label, a.jeWoche.get('2026-W45') ?? null, a.jeWoche.get('2026-W46') ?? null, a.summe]), [
    ['Knirps', 'klein', 'D', 200, 60, 260],
    ['Knirps', 'klein', 'K', null, 40, 40],
    ['Knirps', 'gross', 'D', null, 200, 200],
    ['Butternut', 'lose', null, null, 30, 30],
    ['Mandarin', 'lose', 'D', null, null, 0],       // geliefert, aber ohne Stückgewicht: Zeile ja, Kilos keine
  ])
  assert.equal(t.jeWoche.get('2026-W45'), 200)
  assert.equal(t.jeWoche.get('2026-W46'), 330)
  assert.equal(t.summe, 530)
  assert.equal(t.positionen, 8)
  assert.equal(t.stueckOhneGewicht, 48, 'was Perigon nicht wiegt, steht als Stück da — nie als 0 kg')
  assert.equal(t.positionenOhneGewicht, 2)
})

test('nichts erfunden, nichts weggelassen: die Summe der Tabelle ist die Summe der Positionen', () => {
  const wochen = wochenDerSaison(ZEILEN, 2026, '2026-11-12')
  const t = kwTabelle(ZEILEN, ['Laden Nord', 'Laden Süd'], wochen, 2026)
  const erwartet = ZEILEN.filter(z => z.saison === 2026).reduce((s, z) => s + Number(z.kg ?? 0), 0)
  assert.equal(t.summe, erwartet)
  assert.equal([...t.jeWoche.values()].reduce((s, v) => s + v, 0), erwartet, 'die Wochen ergeben die Summe')
  assert.equal(t.artikel.reduce((s, a) => s + a.summe, 0), erwartet, 'die Artikel ergeben die Summe')
  // Eine Woche ohne Lieferung hat keinen Wert — leer ist nicht null
  assert.equal(t.jeWoche.has('2026-W40'), false)
})

test('nur was verkauft wurde: ohne Lieferung in den gewählten Wochen keine Zeile', () => {
  const t = kwTabelle(ZEILEN, ['Laden Nord'], ['2026-W43'], 2026)
  assert.deepEqual(t.artikel.map(a => a.gruppe), ['Mix'])
  assert.equal(kwTabelle(ZEILEN, ['Laden Nord'], ['2026-W40'], 2026).artikel.length, 0)
  assert.equal(kwTabelle(ZEILEN, [], ['2026-W46'], 2026).artikel.length, 0)
})

test('die Kunden nach Gruppe; eine Gruppe meint alle ihre Kunden, ein Kunde nur sich', () => {
  const gesetzt = new Map([['Laden Nord', 'Läden'], ['Laden Süd', 'Läden']])
  const zeilen = [...ZEILEN, zeile('Hofladen', '2026-11-10', 'Knirps', 'klein', 'D', 5)]
  const g = kundenGruppen(zeilen, 2026, gesetzt, [])
  assert.deepEqual(g.map(x => x.name), ['Läden', 'Kleinkunden'], 'Kleinkunden zuletzt')
  assert.deepEqual(g[0].kunden.map(k => k.name), ['Laden Nord', 'Laden Süd'], 'in der Gruppe nach Menge')
  assert.deepEqual(kundenDerWahl(gruppeWahl('Läden'), g), ['Laden Nord', 'Laden Süd'])
  assert.deepEqual(kundenDerWahl(kundeWahl('Laden Süd'), g), ['Laden Süd'])
  // die ganze Gruppe ist die Summe ihrer Kunden
  const wochen = ['2026-W46']
  const ganze = kwTabelle(zeilen, kundenDerWahl(gruppeWahl('Läden'), g), wochen, 2026).summe
  const einzeln = g[0].kunden.reduce((s, k) => s + kwTabelle(zeilen, [k.name], wochen, 2026).summe, 0)
  assert.equal(ganze, einzeln)
  assert.equal(ganze, 1330)
})

test('die Wochen in Worten', () => {
  const alle = wochenDerSaison(ZEILEN, 2026, '2026-11-12')
  assert.equal(kwName('2026-W46'), 'KW 46')
  assert.equal(wochenText(['2026-W46'], alle), 'KW 46')
  assert.equal(wochenText(['2026-W45', '2026-W43', '2026-W44', '2026-W46'], alle), 'KW 43–46')
  assert.equal(wochenText(['2026-W43', '2026-W46'], alle), 'KW 43, 46')
  assert.equal(wochenText([], alle), 'keine Woche')
  const ueber = ['2026-W52', '2026-W53', '2027-W01']
  assert.equal(wochenText(ueber, ueber), 'KW 52 2026–1 2027')
})
