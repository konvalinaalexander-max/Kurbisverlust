// Runde AO: Der Palox-Hinweis kommt je Person in drei verschiedenen Arbeiten —
// „dass jede Person, die sich einloggt, noch dreimal die Infos kriegt".
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { PALOX_HINWEIS_MAL, SORTIERDATUM_HINWEIS_MAL, gesehenLesen, hinweisZeigen, paloxHinweisGesehen, paloxHinweisZeigen,
         paloxHinweisSchluessel, sortierdatumHinweisBei, sortierdatumHinweisSchluessel } from '../src/arbeit/erinnerung.ts'
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

// Runde AP: „beim Sortieren musst du das Sortierdatum nicht mehr aufschreiben" —
// „die ersten drei Mal oder die ersten fünf Mal vielleicht sogar, bis das
// wirklich im Kopf drin ist". Fünfmal, beim Waschen und beim Sortieren.
test('Sortierdatum-Hinweis: fünfmal je Person, in fünf verschiedenen Arbeiten', () => {
  assert.equal(SORTIERDATUM_HINWEIS_MAL, 5)
  let g: number[] = []
  for (const arbeit of [21, 22, 23, 24, 25]) {
    assert.ok(hinweisZeigen(g, arbeit, SORTIERDATUM_HINWEIS_MAL), `Arbeit ${arbeit}: der Hinweis steht da`)
    g = paloxHinweisGesehen(g, arbeit)
  }
  assert.ok(!hinweisZeigen(g, 26, SORTIERDATUM_HINWEIS_MAL), 'die sechste Arbeit kommt ohne Hinweis')
  // eigener Zähler: wer den Palox-Hinweis dreimal gesehen hat, sieht diesen trotzdem
  assert.notEqual(sortierdatumHinweisSchluessel('p1'), paloxHinweisSchluessel('p1'))
})

test('Sortierdatum-Hinweis: beim Waschen und beim Sortieren, nicht bei W+S und nicht beim Fax', () => {
  assert.ok(sortierdatumHinweisBei('waschen', false))
  assert.ok(sortierdatumHinweisBei('sortieren', false))
  assert.ok(!sortierdatumHinweisBei('waschen_sortieren', false))
  assert.ok(!sortierdatumHinweisBei('waschen', true))
})

test('der Sortierdatum-Hinweis steht in allen sechs Sprachen', () => {
  for (const { code } of SPRACHEN) {
    const wb = WOERTERBUCH[code] as Record<string, string>
    for (const id of ['sortierdatumHinweisTitel', 'sortierdatumHinweisText']) assert.ok(wb[id], `${code}.${id} fehlt`)
  }
})
