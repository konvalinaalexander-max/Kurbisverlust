// Runde T: der Plan vor der Arbeit — vor, während, nach. Eine reine Funktion,
// also hier geprüft, nicht im Browser: Was der Plan verspricht, muss es in
// der App auch geben, und jeder Text muss in allen Sprachen stehen.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { arbeitsplan } from '../src/arbeit/plan.ts'
import { WOERTERBUCH, SPRACHEN } from '../src/lib/i18n.ts'
import { ZAEHLBLATT } from '../src/lib/taetigkeit.ts'

const texte = (p: ReturnType<typeof arbeitsplan>) => [...p.vorher, ...p.waehrend, ...p.nachher].map(x => x.text)

test('Waschen + Sortieren: Palox zweimal, drei Wägungen vorher, drei fertige Paletten nachher — alles vor dem ersten Schritt sichtbar', () => {
  const p = arbeitsplan('waschen_sortieren', false, null)
  assert.deepEqual(p.vorher.map(x => x.text), ['planPaloxStart'])
  assert.ok(p.waehrend.some(x => x.text === 'planDreiWiegen'), 'die drei Wägungen stehen im Block „während"')
  assert.ok(p.nachher.some(x => x.text === 'planDreiFertige'), 'die drei fertigen Paletten stehen im Block „nachher"')
  assert.ok(p.nachher.some(x => x.text === 'planPaloxEnde'))
  assert.equal(p.nachher[p.nachher.length - 1].text, 'planFrage', 'die Frage nach der Charge ist der letzte Punkt')
  assert.ok(p.mitZettel)
  assert.ok(texte(p).every(id => !p.vorher.concat(p.waehrend, p.nachher).find(x => x.text === id)?.freiwillig), 'an der Waschstrasse mit Sortieren ist nichts freiwillig')
})

test('Waschen: der Palox ist freiwillig — und steht trotzdem im Plan, als freiwillig beschriftet', () => {
  const p = arbeitsplan('waschen', false, null)
  const start = p.vorher.find(x => x.text === 'planPaloxStart')
  const ende = p.nachher.find(x => x.text === 'planPaloxEnde')
  assert.ok(start?.freiwillig && ende?.freiwillig)
  assert.ok(p.waehrend.some(x => x.text === 'planZaehlenWasch'))
  assert.ok(!texte(p).includes('planAusschuss'), 'zu klein / zu gross gibt es nur von Hand')
})

test('Sortieren: das Sortierdatum auf den Zettel steht im Plan — sonst fragt das Waschen später ins Leere', () => {
  const p = arbeitsplan('sortieren', false, null)
  assert.ok(p.waehrend.some(x => x.text === 'planSortierdatum'))
  assert.ok(!texte(p).includes('planDreiFertige'), 'beim Sortieren werden keine fertigen Paletten gewogen')
})

test('Kistensystem „anderes": die fertigen Paletten verschwinden aus dem Plan — wie aus der Checkliste', () => {
  const mit = arbeitsplan('waschen', false, null)
  const ohne = arbeitsplan('waschen', false, false)
  assert.ok(texte(mit).includes('planDreiFertige') && texte(mit).includes('planFertigeGesamt'))
  assert.ok(!texte(ohne).includes('planDreiFertige') && !texte(ohne).includes('planFertigeGesamt'))
})

test('Fax: kein Zählblatt, kein Palox — Faules und die Palettenzahl', () => {
  const p = arbeitsplan('waschen', true, null)
  assert.equal(p.mitZettel, false)
  assert.deepEqual(p.vorher, [])
  assert.deepEqual(texte(p), ['planFaule', 'planFaxPaletten', 'planFrage'])
})

test('jeder Text des Plans steht in allen sechs Sprachen, und der Zettel-Satz trägt den Platzhalter', () => {
  const alle = new Set<string>()
  for (const station of ['sortieren', 'waschen', 'waschen_sortieren'] as const) {
    for (const rechenbar of [null, true, false]) texte(arbeitsplan(station, false, rechenbar)).forEach(t => alle.add(t))
  }
  texte(arbeitsplan('waschen', true, null)).forEach(t => alle.add(t))
  for (const { code } of SPRACHEN) {
    const wb = WOERTERBUCH[code] as Record<string, string>
    for (const id of alle) assert.ok(wb[id], `${code}.${id} fehlt`)
    assert.ok(wb.planZettel.includes('{blatt}'), `${code}.planZettel ohne {blatt}`)
  }
})

test('solange das Kistensystem offen ist, verspricht der Plan die fertigen Paletten nicht', () => {
  // Der Betrieb: „bei anders muss man ja keine fertigen paletten wiegen".
  // Der Plan steht aber vor der Frage nach dem Kistensystem. Also steht die
  // Bedingung dabei, statt etwas anzukündigen, das später nicht verlangt wird.
  for (const station of ['waschen', 'waschen_sortieren'] as const) {
    const offen = arbeitsplan(station, false, null)
    const p = offen.nachher.find(x => x.text === 'planDreiFertige')
    assert.ok(p, `${station}: die fertigen Paletten gehören in den Plan`)
    assert.equal(p!.bedingt, true, `${station}: und zwar mit ihrer Bedingung`)
  }
})

test('sobald das Kistensystem gewählt ist, steht der Plan endgültig da', () => {
  for (const station of ['waschen', 'waschen_sortieren'] as const) {
    const ja = arbeitsplan(station, false, true)
    assert.equal(ja.nachher.find(x => x.text === 'planDreiFertige')?.bedingt, undefined,
      `${station}: rechenbar — kein Wenn und Aber`)
    const nein = arbeitsplan(station, false, false)
    assert.ok(!texte(nein).includes('planDreiFertige'),
      `${station}: „anderes" — die fertigen Paletten stehen gar nicht erst da`)
    assert.ok(!texte(nein).includes('planFertigeGesamt'))
  }
})

test('beim Sortieren ist der Plan von der ersten Sekunde an vollständig', () => {
  // Dort fragt die App nie nach dem Kistensystem, und fertige Paletten gibt
  // es nicht — also darf auch nichts als „bedingt" dastehen.
  const p = arbeitsplan('sortieren', false, null)
  const alle = [...p.vorher, ...p.waehrend, ...p.nachher]
  assert.ok(alle.every(x => !x.bedingt), 'beim Sortieren ist nichts bedingt')
  assert.ok(!texte(p).includes('planDreiFertige'))
})

test('jede Station hat ein Zählblatt mit Namen', () => {
  for (const station of ['sortieren', 'waschen', 'waschen_sortieren'] as const) {
    assert.match(ZAEHLBLATT[station], /\S/)
  }
})
