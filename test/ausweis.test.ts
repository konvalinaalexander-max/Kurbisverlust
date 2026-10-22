import { test } from 'node:test'
import assert from 'node:assert/strict'
import { schritte, summiere } from '../src/auswertung/ausweis.ts'
import type { LagerAusweis } from '../src/auswertung/daten.ts'

// 0121 — der Betrieb: „wie viele Kilo im Lager sind, als Paletten … und daneben
// davon verkaufsfähig: minus Verdunstung (mit Lagerdauer und täglicher Rate),
// minus Palox, minus zu klein, zu gross … und vielleicht minus verschenkte Marge."

const a = (nr: number, x: Partial<LagerAusweis> = {}): LagerAusweis => ({
  charge_nr: nr, sorte: 'Amoro', schlag: 'S', paletten: 5, eingang_kg: 2000, alter_tage: 50,
  verdunstet_kg: 100, verdunstet_je_tag_kg: 2, faul_kg: 150, unique_kg: 0, hagel_anteil: null,
  zu_klein_kg: 40, zu_gross_kg: 60, fax_kg: 0, verkaufsfaehig_kg: 1650,
  marge_anteil: 0.05, marge_quelle: 'gewogen', marge_kg: 78.57, verrechenbar_kg: 1571.43, hagel_bis_heute_kg: 0,
  r_bekannt: true, f_bekannt: true, kanal_bekannt: true, fax_bekannt: true, ...x })

test('summiere: die Kette geht auf; Paletten zusammengezählt; die Rate je Tag aus Lagerdauer und Verdunstung', () => {
  const s = summiere([a(1), a(2, { eingang_kg: 1000, paletten: 2, verdunstet_kg: 40, faul_kg: 60, zu_klein_kg: 20, zu_gross_kg: 30, verkaufsfaehig_kg: 850, alter_tage: 20, marge_kg: 40 })])
  assert.equal(s.paletten, 7)
  assert.equal(s.eingang, 3000)
  assert.equal(s.eingang, s.verdunstet + s.faul + s.unique + s.klein + s.gross + s.fax + s.verkaufsfaehig)
  assert.equal(Math.round(s.alterTage!), 40, 'Alter nach Masse gewichtet: (50·2000 + 20·1000) / 3000')
  assert.equal(s.rateJeTag!.toFixed(5), (140 / 3000 / 40).toFixed(5))
})

test('Leer ist nicht null: eine Charge ohne Rate fehlt in den Abzügen und wird gezählt; ohne Marge keine Marge', () => {
  const s = summiere([a(1), a(2, { verkaufsfaehig_kg: null, faul_kg: null }), a(3, { marge_kg: null })])
  assert.equal(s.luecken, 1)
  assert.equal(s.verkaufsfaehig, 3300)
  assert.equal(s.margeBekannt, false)
  assert.equal(schritte(s).some(x => x.name === 'verrechenbar'), false)
})

test('schritte: Unique nur, wo Hagel ist; die Reihenfolge wie im Lager', () => {
  const ohne = schritte(summiere([a(1)]))
  assert.deepEqual(ohne.map(x => x.name), ['auf den Paletten, wie eingegangen', 'verdunstet', 'Faules im Palox', 'zu klein', 'zu gross', 'verkaufsfähig',
    'davon Überfüllung in den Kisten', 'verrechenbar'])
  const mit = schritte(summiere([a(1, { unique_kg: 300, verkaufsfaehig_kg: 1350 })]))
  assert.ok(mit.some(x => x.name === 'Unique (Hagel)' && x.kg === 300))
  assert.match(mit.find(x => x.name === 'verdunstet')!.wie!, /50 Tage gelagert, rund 0\.1 % je Tag/)
})
