import { test } from 'node:test'
import assert from 'node:assert/strict'
import { achsenBereich, alleinherrscher, einheitsGrenzen } from '../src/lib/achse.ts'

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
