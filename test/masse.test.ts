import { test } from 'node:test'
import assert from 'node:assert/strict'
import { nettoKg, taraFehlt } from '../src/lib/masse.ts'

const P = { tara_kg_pro_kiste: 1.5, tara_kg_palette: 25 }

test('Netto ist brutto minus Kistentara minus Palettentara', () => {
  assert.equal(nettoKg(1000, 30, P), 1000 - 45 - 25)
})

test('ohne Palette darunter zählt nur die Kistentara', () => {
  assert.equal(nettoKg(1000, 30, P, false), 955)
})

test('fehlt die Kistenzahl, gibt es kein Netto — nicht null Kisten', () => {
  assert.equal(nettoKg(1000, null, P), null)
  assert.notEqual(nettoKg(1000, 0, P), null)      // null Kisten ist eine Angabe
})

test('fehlt eine Tara, gibt es kein Netto', () => {
  assert.equal(nettoKg(1000, 30, { tara_kg_pro_kiste: null, tara_kg_palette: 25 }), null)
  assert.equal(nettoKg(1000, 30, { tara_kg_pro_kiste: 1.5, tara_kg_palette: null }), null)
  assert.equal(nettoKg(1000, 30, null), null)
  // ohne Palette darunter ist die fehlende Palettentara egal
  assert.equal(nettoKg(1000, 30, { tara_kg_pro_kiste: 1.5, tara_kg_palette: null }, false), 955)
})

test('sagt, was fehlt', () => {
  assert.equal(taraFehlt(P), null)
  assert.match(taraFehlt({ tara_kg_pro_kiste: null, tara_kg_palette: 25 })!, /Kistengewicht/)
  assert.match(taraFehlt({ tara_kg_pro_kiste: 1.5, tara_kg_palette: null })!, /Palettengewicht/)
  assert.equal(taraFehlt({ tara_kg_pro_kiste: 1.5, tara_kg_palette: null }, false), null)
})
