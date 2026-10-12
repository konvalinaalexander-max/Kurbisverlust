// Runde AO: Der Palox-Hinweis kommt je Person in drei verschiedenen Arbeiten —
// „dass jede Person, die sich einloggt, noch dreimal die Infos kriegt".
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { PALOX_HINWEIS_MAL, gesehenLesen, paloxHinweisGesehen, paloxHinweisZeigen } from '../src/arbeit/erinnerung.ts'
import { WOERTERBUCH, SPRACHEN } from '../src/lib/i18n.ts'

test('dreimal, in drei verschiedenen Arbeiten — dann nicht mehr', () => {
  assert.equal(PALOX_HINWEIS_MAL, 3)
  let g: number[] = []
  for (const arbeit of [11, 12, 13]) {
    assert.ok(paloxHinweisZeigen(g, arbeit), `Arbeit ${arbeit}: der Hinweis steht da`)
    g = paloxHinweisGesehen(g, arbeit)
    assert.ok(!paloxHinweisZeigen(g, arbeit), `Arbeit ${arbeit}: nach „Verstanden" ist er weg`)
  }
  assert.ok(!paloxHinweisZeigen(g, 14), 'die vierte Arbeit kommt ohne Hinweis')
})

test('zweimal „Verstanden" in derselben Arbeit zählt einmal', () => {
  const g = paloxHinweisGesehen(paloxHinweisGesehen([], 11), 11)
  assert.deepEqual(g, [11])
  assert.ok(paloxHinweisZeigen(g, 12))
})

test('was auf dem Gerät steht: Unlesbares zählt als nichts gesehen — dann kommt der Hinweis eben noch einmal', () => {
  assert.deepEqual(gesehenLesen(null), [])
  assert.deepEqual(gesehenLesen('kaputt'), [])
  assert.deepEqual(gesehenLesen('{"a":1}'), [])
  assert.deepEqual(gesehenLesen('[11, "12", 13.5, 14]'), [11, 14])
})

test('der Hinweis steht in allen sechs Sprachen', () => {
  for (const { code } of SPRACHEN) {
    const wb = WOERTERBUCH[code] as Record<string, string>
    for (const id of ['paloxHinweisTitel', 'paloxHinweisText', 'paloxHinweisOk', 'planPaloxLeeren']) assert.ok(wb[id], `${code}.${id} fehlt`)
  }
})
