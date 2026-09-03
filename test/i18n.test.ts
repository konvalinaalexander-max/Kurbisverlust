import { test } from 'node:test'
import assert from 'node:assert/strict'
import { SPRACHEN, WOERTERBUCH, uebersetze, GEBIETSSCHEMA, type Sprache } from '../src/lib/i18n.ts'
import { TAETIGKEITEN, taetigkeitVon } from '../src/lib/taetigkeit.ts'

const CODES = SPRACHEN.map(s => s.code)

test('alle sechs Sprachen des Betriebs sind da', () => {
  assert.deepEqual([...CODES].sort(), ['de', 'en', 'hu', 'pl', 'pt', 'ro'])
})

test('jede Sprache kennt jeden Text — kein Loch in der Oberfläche', () => {
  const schluessel = Object.keys(WOERTERBUCH.de)
  for (const code of CODES) {
    const fehlend = schluessel.filter(k => !(WOERTERBUCH[code] as Record<string, string>)[k])
    assert.deepEqual(fehlend, [], `${code} fehlen: ${fehlend.join(', ')}`)
  }
})

test('keine Sprache hat unbenutzte Extra-Texte', () => {
  const schluessel = new Set(Object.keys(WOERTERBUCH.de))
  for (const code of CODES) {
    const extra = Object.keys(WOERTERBUCH[code]).filter(k => !schluessel.has(k))
    assert.deepEqual(extra, [], `${code} hat zu viel: ${extra.join(', ')}`)
  }
})

test('kein Text ist versehentlich deutsch geblieben', () => {
  // Stichprobe der Texte, die der Arbeiter zuerst sieht — sie müssen sich
  // zwischen den Sprachen unterscheiden, sonst wurde eine Übersetzung vergessen.
  for (const id of ['deinName', 'losGehts', 'sortieren', 'faule', 'paletten'] as const) {
    const werte = CODES.filter(c => c !== 'de').map(c => WOERTERBUCH[c][id])
    const wieDeutsch = werte.filter(w => w === WOERTERBUCH.de[id])
    assert.equal(wieDeutsch.length, 0, `„${id}" ist in ${wieDeutsch.length} Sprachen deutsch geblieben`)
  }
})

test('das Wort „Weg" kommt in keiner Sprache mehr vor', () => {
  // Fachbegriff aus der Spezifikation — für den Arbeiter bedeutungslos.
  for (const code of CODES) {
    for (const [id, text] of Object.entries(WOERTERBUCH[code])) {
      assert.ok(!/\bWeg\s*[12]\b/i.test(text), `${code}.${id} enthält noch „Weg": ${text}`)
    }
  }
})

test('unbekannte Sprache fällt auf Deutsch zurück, statt leer zu bleiben', () => {
  assert.equal(uebersetze('xx' as Sprache, 'losGehts'), WOERTERBUCH.de.losGehts)
})

test('jede Sprache hat ein Zahlen-/Datumsformat', () => {
  for (const code of CODES) {
    assert.ok(GEBIETSSCHEMA[code], `${code} ohne Gebietsschema`)
    // muss von Intl akzeptiert werden
    assert.doesNotThrow(() => new Intl.NumberFormat(GEBIETSSCHEMA[code]).format(1234.5))
  }
})

test('die Tätigkeiten decken alle Weg-Station-Paare ab (Fax teilt sich Waschen)', () => {
  assert.equal(TAETIGKEITEN.length, 4)
  assert.equal(taetigkeitVon('maschine', 'sortieren')?.id, 'sortieren')
  assert.equal(taetigkeitVon('maschine', 'waschen')?.id, 'waschen')
  assert.equal(taetigkeitVon('hand', 'waschen_sortieren')?.id, 'waschen_sortieren')
  // Fax teilt Weg und Station mit dem Waschgang; die Markierung entscheidet.
  assert.equal(taetigkeitVon('maschine', 'waschen', true)?.id, 'fax')
  assert.equal(taetigkeitVon('maschine', 'waschen', false)?.id, 'waschen')
})

test('jede Tätigkeit hat einen übersetzten Namen in allen Sprachen', () => {
  for (const a of TAETIGKEITEN) {
    for (const code of CODES) {
      assert.ok(WOERTERBUCH[code][a.text], `${code} kennt ${a.text} nicht`)
    }
  }
})
