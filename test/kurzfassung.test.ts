import { test } from 'node:test'
import assert from 'node:assert/strict'
import { eintraegePruefen, patchFuer } from '../pruefstand/kurzfassung.mjs'

const JETZT = '2026-09-27T05:00:00.000Z'
const roh = (x: Record<string, unknown> = {}) => ({
  id: 17, auftrag_id: 120, art: 'ware', text: 'Also am Anfang … Hagel … weggeworfen.',
  kurz: null, kurz_quelle: null, kurz_ts: null, kurz_charge_nr: null, ...x,
})

test('eine ungelesene Rückmeldung bekommt die Kurzfassung der Runde', () => {
  const { patch, grund } = patchFuer(roh(), { id: 17, kurz: ' Hagelschaden ' }, JETZT)
  assert.equal(grund, null)
  assert.deepEqual(patch, { kurz: 'Hagelschaden', kurz_quelle: 'runde', kurz_ts: JETZT })
})

test('was schon so steht, wird nicht noch einmal geschickt', () => {
  const z = roh({ kurz: 'Hagelschaden', kurz_quelle: 'runde', kurz_ts: '2026-09-20T05:00:00Z' })
  assert.deepEqual(patchFuer(z, { id: 17, kurz: 'Hagelschaden' }, JETZT), { patch: null, grund: null })
})

test('die Kurzfassung des Betriebsleiters bleibt — ausser ueberschreiben: true', () => {
  const z = roh({ kurz: 'Hagel', kurz_quelle: 'betriebsleiter', kurz_ts: '2026-09-20T05:00:00Z' })
  const a = patchFuer(z, { id: 17, kurz: 'Hagelschaden' }, JETZT)
  assert.equal(a.patch, null); assert.match(a.grund ?? '', /Betriebsleiter hat selbst gekürzt/)
  const b = patchFuer(z, { id: 17, kurz: 'Hagelschaden', ueberschreiben: true }, JETZT)
  assert.deepEqual(b.patch, { kurz: 'Hagelschaden', kurz_quelle: 'runde', kurz_ts: JETZT })
  // Nur die Arbeit umhängen darf man auch ohne ueberschreiben — die Kurzfassung bleibt seine.
  const c = patchFuer(z, { id: 17, auftrag_id: 121 }, JETZT)
  assert.deepEqual(c.patch, { auftrag_id: 121 })
})

test('kurz: null nimmt die Kurzfassung zurück, samt Quelle, Zeit und Charge', () => {
  const z = roh({ kurz: 'Hagelschaden', kurz_quelle: 'runde', kurz_ts: '2026-09-20T05:00:00Z', kurz_charge_nr: 1628 })
  assert.deepEqual(patchFuer(z, { id: 17, kurz: null }, JETZT).patch, { kurz: null, kurz_quelle: null, kurz_ts: null, kurz_charge_nr: null })
  assert.deepEqual(patchFuer(roh(), { id: 17, kurz: null }, JETZT), { patch: null, grund: null })
})

test('eine andere Charge nur mit Kurzfassung; zur App keine Kurzfassung', () => {
  const a = patchFuer(roh(), { id: 17, charge_nr: 1628 }, JETZT)
  assert.equal(a.patch, null); assert.match(a.grund ?? '', /nur mit Kurzfassung/)
  const b = patchFuer(roh(), { id: 17, kurz: 'Hagelschaden', charge_nr: 1628 }, JETZT)
  assert.deepEqual(b.patch, { kurz: 'Hagelschaden', kurz_quelle: 'runde', kurz_ts: JETZT, kurz_charge_nr: 1628 })
  const c = patchFuer(roh({ art: 'app' }), { id: 17, kurz: 'Knopf' }, JETZT)
  assert.equal(c.patch, null); assert.match(c.grund ?? '', /zur App gibt es keine Kurzfassung/)
  // Umgekehrt: ein Feedback, das eigentlich zur Ware war, wird zur Ware und gekürzt.
  const d = patchFuer(roh({ art: 'app' }), { id: 17, art: 'ware', kurz: 'Hagelschaden' }, JETZT)
  assert.deepEqual(d.patch, { kurz: 'Hagelschaden', kurz_quelle: 'runde', kurz_ts: JETZT, art: 'ware' })
  // Ein gekürztes zur App machen geht nur mit kurz: null dazu — nichts wird
  // stillschweigend weggenommen.
  const e = patchFuer(roh({ kurz: 'Hagel', kurz_quelle: 'runde', kurz_ts: JETZT }), { id: 17, art: 'app' }, JETZT)
  assert.equal(e.patch, null); assert.match(e.grund ?? '', /kurz: null dazu/)
  const f = patchFuer(roh({ kurz: 'Hagel', kurz_quelle: 'runde', kurz_ts: JETZT }), { id: 17, art: 'app', kurz: null }, JETZT)
  assert.deepEqual(f.patch, { kurz: null, kurz_quelle: null, kurz_ts: null, kurz_charge_nr: null, art: 'app' })
})

test('eine Nr., die es nicht gibt, wird genannt, nicht geraten', () => {
  const a = patchFuer(null, { id: 99, kurz: 'x' }, JETZT)
  assert.equal(a.patch, null); assert.match(a.grund ?? '', /Nr\. 99 gibt es nicht/)
})

test('die Datei wird geprüft: id, kurz, charge_nr, art, unbekannte Felder, Doppelte', () => {
  assert.throws(() => eintraegePruefen({}), /erwartet/)
  assert.throws(() => eintraegePruefen({ eintraege: [{ kurz: 'x' }] }), /id fehlt/)
  assert.throws(() => eintraegePruefen({ eintraege: [{ id: 1, kurz: '  ' }] }), /kurz ist weder Text noch null/)
  assert.throws(() => eintraegePruefen({ eintraege: [{ id: 1, art: 'charge' }] }), /art muss ware oder app/)
  assert.throws(() => eintraegePruefen({ eintraege: [{ id: 1, kurz: 'x' }, { id: 1, kurz: 'y' }] }), /doppelt/)
  assert.throws(() => eintraegePruefen({ eintraege: [{ id: 1, text: 'x' }] }), /unbekanntes Feld „text"/)
  assert.equal(eintraegePruefen({ eintraege: [{ id: 1, kurz: 'Hagelschaden', charge_nr: 1628, warum: 'sagt es selbst' }] }).length, 1)
})
