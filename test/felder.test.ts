import { test } from 'node:test'
import assert from 'node:assert/strict'
import { chargenNachFeld } from '../src/lib/felder.ts'

test('Chargen nach Feld, darin nach Sorte, dann nach Nummer', () => {
  const g = chargenNachFeld([
    { charge_nr: 1632, sorte: 'Tiana', schlag: 'Andi Ball' },
    { charge_nr: 1613, sorte: 'Tiana', schlag: 'Slowgrow Uster' },
    { charge_nr: 1612, sorte: 'Butterkin', schlag: 'Slowgrow Uster' },
    { charge_nr: 1614, sorte: 'Kaori Kuri', schlag: 'Slowgrow Uster' },
    { charge_nr: 1611, sorte: 'Tiana', schlag: 'Slowgrow Uster' },
  ])
  assert.deepEqual(g.map(x => x.feld), ['Andi Ball', 'Slowgrow Uster'])
  assert.deepEqual(g[1].chargen.map(c => `${c.sorte} ${c.charge_nr}`), ['Butterkin 1612', 'Kaori Kuri 1614', 'Tiana 1611', 'Tiana 1613'])
})

test('ohne Chargen keine Gruppe', () => {
  assert.deepEqual(chargenNachFeld([]), [])
})
