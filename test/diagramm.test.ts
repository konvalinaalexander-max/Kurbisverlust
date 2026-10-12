import { test } from 'node:test'
import assert from 'node:assert/strict'
import { achsenBereich, alleinherrscher, einheitsGrenzen, kalenderStriche } from '../src/lib/achse.ts'

/** Der Fall vom Betrieb: Lagertage der Demo (8 … 195) plus ein Zettel mit dem Jahr 2029. */
const FAUL = [8, 14, 21, 33, 47, 61, 88, 102, 130, 151, 177, 195.5]

test('Lagertage: die Achse beginnt bei 0 und wirft den Zettel aus der Zukunft aus', () => {
  const b = achsenBereich([...FAUL, -1051], 'tage')
  assert.deepEqual(b.ausgeschlossen, [-1051])
  assert.equal(b.von, 0)
  assert.equal(b.bis, 195.5)
})

test('Ein Ausreisser, den die Einheit erlaubt, fliegt trotzdem aus der Achse', () => {
  assert.equal(alleinherrscher([...FAUL, 900]), 900)
  assert.equal(alleinherrscher(FAUL), null)
  assert.equal(alleinherrscher([1, 1000]), null)      // zwei Punkte: keiner ist allein
  const b = achsenBereich([...FAUL, 900], 'tage')
  assert.deepEqual(b.ausgeschlossen, [900])
  assert.equal(b.bis, 195.5)
})

test('Prozent über 100 zieht die Achse nicht auf 2500', () => {
  const b = achsenBereich([1.2, 3.4, 5.1, 2500], 'prozent', { von: 0 })
  assert.deepEqual(b.ausgeschlossen, [2500])
  assert.equal(b.von, 0)
  assert.equal(b.bis, 5.1)
})

test('NaN und ∞ fallen aus der Achse', () => {
  const b = achsenBereich([1, NaN, 3, Infinity], 'frei')
  assert.equal(b.ausgeschlossen.filter(Number.isFinite).length, 0)
  assert.equal(b.ausgeschlossen.length, 2)
})

test('Feste Vorgaben gewinnen; leere und einpunktige Reihen geben eine Achse mit Weite', () => {
  assert.equal(achsenBereich([5, 8, 9], 'frei', { von: 0, bis: 100 }).von, 0)
  assert.equal(achsenBereich([5, 8, 9], 'frei', { von: 0, bis: 100 }).bis, 100)
  const leer = achsenBereich([], 'tage')
  assert.ok(leer.bis > leer.von)
  const einer = achsenBereich([42], 'tage')
  assert.equal(einer.von, 0); assert.ok(einer.bis >= 42)
})

test('Einheitsgrenzen: Lagertage und Kilo ab 0, Prozent 0…100, frei ohne Grenze', () => {
  assert.deepEqual(einheitsGrenzen('tage'), { von: 0 })
  assert.deepEqual(einheitsGrenzen('prozent'), { von: 0, bis: 100 })
  assert.deepEqual(einheitsGrenzen('frei'), {})
})

// Runde AQ: die Zeitachse liest sich wie ein Kalender — „mach es professioneller".
const TAG = 86400000
const tage = (iso: string) => Date.parse(iso) / TAG

test('Kalenderstriche: eine Saison zeigt Monatsanfänge, der Januar mit Jahr', () => {
  const s = kalenderStriche(tage('2026-07-03'), tage('2027-03-28'))
  assert.deepEqual(s.map(x => x.text), ['Aug', 'Sep', 'Okt', 'Nov', 'Dez', 'Jan 27', 'Feb', 'Mär'])
  assert.equal(s[0].x, tage('2026-08-01'))
  assert.ok(s.every(x => x.x >= tage('2026-07-03') && x.x <= tage('2027-03-28')))
})

test('Kalenderstriche: über ein Jahr nur jeder zweite oder dritte Monat — Monatsnamen höchstens vier mehr als Datumsstriche', () => {
  const s = kalenderStriche(tage('2025-07-01'), tage('2027-06-30'), 0, 8)
  assert.ok(s.length <= 12 && s.length >= 4, `${s.length} Striche`)
  assert.ok(s.every((x, i) => i === 0 || x.x - s[i - 1].x >= 58), 'mindestens zwei Monate auseinander')
  assert.ok(s.every(x => new Date(x.x * TAG).getUTCDate() === 1), 'jeder Strich auf einem Monatsanfang')
})

test('Kalenderstriche: hineingezoomt Montage, je Woche', () => {
  const s = kalenderStriche(tage('2026-09-02'), tage('2026-10-12'))
  assert.ok(s.length >= 4 && s.length <= 8, `${s.length} Striche`)
  assert.ok(s.every(x => new Date(x.x * TAG).getUTCDay() === 1), 'jeder Strich auf einem Montag')
  assert.equal(s[0].text, '7.9.')
})

test('Kalenderstriche: wenige Tage einzeln; Ursprung 1. Juli für Saisontage', () => {
  const s = kalenderStriche(tage('2026-10-05'), tage('2026-10-09'))
  assert.deepEqual(s.map(x => x.text), ['5.10.', '6.10.', '7.10.', '8.10.', '9.10.'])
  const saison = kalenderStriche(0, 364, Date.UTC(2026, 6, 1))
  assert.equal(saison[0].text, 'Jul'); assert.equal(saison[0].x, 0)
  assert.ok(saison.some(x => x.text === 'Jan 27'))
  assert.deepEqual(kalenderStriche(5, 5), [])
})
