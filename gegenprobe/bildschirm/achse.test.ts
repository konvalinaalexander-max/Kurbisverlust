/**
 * Die Achsenregeln an dem Fall, der sie nötig gemacht hat — und an ein paar
 * Nachbarn, die genauso schiefgehen könnten.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { achsenBereich, alleinherrscher, pruefeAchse, striche } from './achse.ts'

/** Lagertage der Demo-Saison (8 … 195.5) plus der eine Zettel mit dem Jahr 2029. */
const FAUL_LAGERTAGE = [8, 14, 21, 33, 47, 61, 88, 102, 130, 151, 177, 195.5]
const MIT_2029 = [...FAUL_LAGERTAGE, -1001]

test('Der Fall vom Betrieb: rohes Min/Max als Achse verletzt A3, A4 und A5', () => {
  // So rechnet Diagramm.tsx heute: xMinAlle = Math.min(...xs)
  const roh = { von: Math.min(...MIT_2029), bis: Math.max(...MIT_2029), ticks: striche(-1001, 195.5, 6) }
  const b = pruefeAchse(roh, MIT_2029, { einheit: 'tage', format: x => `${Math.round(x)}` })
  const regeln = new Set(b.map(x => x.regel))
  assert.ok(regeln.has('A4'), 'Lagertage unter null müssen A4 auslösen')
  assert.ok(regeln.has('A5'), 'der eine Punkt bestimmt die Achse — A5')
  assert.ok(!regeln.has('A2'), 'die Punkte sind alle im Bild — das war ja das Problem')
})

test('achsenBereich wirft den Zettel raus und nennt ihn', () => {
  const b = achsenBereich(MIT_2029, 'tage')
  assert.deepEqual(b.ausgeschlossen, [-1001])
  assert.equal(b.von, 0)
  assert.equal(b.bis, 195.5)
  assert.match(b.gruende[0], /ausserhalb dessen, was tage sein kann/)
  const gut = { von: b.von, bis: b.bis, ticks: striche(b.von, b.bis, 6) }
  assert.deepEqual(pruefeAchse(gut, FAUL_LAGERTAGE, { einheit: 'tage', format: x => `${Math.round(x)}` }), [])
})

test('Ein Ausreisser, den die Einheit erlaubt, ist trotzdem ein Alleinherrscher', () => {
  // 900 Lagertage sind möglich (Ware vom Vorjahr), aber ein einzelner Punkt dort drückt alle anderen zusammen
  assert.equal(alleinherrscher([...FAUL_LAGERTAGE, 900]), 900)
  assert.equal(alleinherrscher(FAUL_LAGERTAGE), null)
  assert.equal(alleinherrscher([1, 1000]), null)        // zwei Punkte: keiner ist allein
  assert.equal(alleinherrscher([5, 5, 5]), null)        // keine Spanne
  const b = achsenBereich([...FAUL_LAGERTAGE, 900], 'tage')
  assert.deepEqual(b.ausgeschlossen, [900])
  assert.match(b.gruende[0], /einzelner Wert \(900\)/)
})

test('Prozent über 100: ein Anteil aus einer falschen Bezugsmasse darf die y-Achse nicht auf 2500 % ziehen', () => {
  const y = [1.2, 3.4, 5.1, 2500]
  const roh = { von: 0, bis: 2500, ticks: striche(0, 2500) }
  assert.ok(pruefeAchse(roh, y, { einheit: 'prozent' }).some(b => b.regel === 'A4'))
  const b = achsenBereich(y, 'prozent', { von: 0 })
  assert.deepEqual(b.ausgeschlossen, [2500])
  assert.equal(b.bis, 5.1)
})

test('Gleiche Beschriftung zweier Striche ist ein Fehler — Runden frisst die Auflösung', () => {
  const a = { von: 0, bis: 1, ticks: [0, 0.2, 0.4, 0.6, 0.8, 1] }
  const b = pruefeAchse(a, [0.1, 0.5, 0.9], { format: x => `${Math.round(x)}` })
  assert.ok(b.some(x => x.regel === 'A6' && /mehrfach/.test(x.text)))
  assert.deepEqual(pruefeAchse(a, [0.1, 0.5, 0.9], { format: x => x.toFixed(1) }), [])
})

test('Leere und einpunktige Reihen: kein Fehler, aber eine Achse mit Weite', () => {
  assert.equal(achsenBereich([], 'tage').bis > achsenBereich([], 'tage').von, true)
  const einer = achsenBereich([42], 'tage')
  assert.equal(einer.von, 0); assert.ok(einer.bis >= 42)
  assert.deepEqual(pruefeAchse({ von: 0, bis: 50, ticks: striche(0, 50) }, [42], { einheit: 'tage' }), [])
})

test('NaN im Datensatz fällt auf, statt die Achse still zu NaN zu machen', () => {
  const b = pruefeAchse({ von: NaN, bis: NaN, ticks: [] }, [1, NaN, 3])
  assert.ok(b.some(x => x.regel === 'A1'))
  assert.deepEqual(achsenBereich([1, NaN, 3]).ausgeschlossen, [NaN])
})

test('striche: 1-2-5-Schritte, erster Strich unter oder auf dem Anfang', () => {
  assert.deepEqual(striche(0, 195.5, 6), [0, 50, 100, 150])
  assert.deepEqual(striche(0, 1), [0, 0.2, 0.4, 0.6, 0.8, 1])
  assert.deepEqual(striche(3, 3), [3])
})
