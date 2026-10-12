// Runde AO: Die Maske prüft den Zettel gegen den Wareneingang, solange die
// Palette noch vor einem steht — mit denselben Regeln wie die Auffälligkeiten
// im Büro (Zetteldatum, Zettelgewicht, Wägung, Verdunstung). Die Fälle unten
// sind die aus dem Abzug vom 11. Oktober.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { tageZwischen, wiegungBefund, zettelBefund, type EingangPalette } from '../src/arbeit/zettel.ts'
import { WOERTERBUCH, SPRACHEN } from '../src/lib/i18n.ts'

const eigen: EingangPalette[] = [
  { eingangsdatum: '2026-09-12', brutto_kg: 432 },
  { eingangsdatum: '2026-09-12', brutto_kg: 437 },
  { eingangsdatum: '2026-09-14', brutto_kg: 466 },
  { eingangsdatum: '2026-09-16', brutto_kg: null },   // ohne Gewicht im Journal
]

test('Datum und Gewicht stehen so im Wareneingang: passt', () => {
  assert.deepEqual(zettelBefund(eigen, [], '2026-09-12', 432), { art: 'passt' })
  assert.deepEqual(zettelBefund(eigen, [], '2026-09-12', 432.0001), { art: 'passt' }, 'Fliesskomma verschmiert nichts')
})

test('ohne Datum sagt die Prüfung nichts — und ohne Gewicht prüft sie nur den Tag', () => {
  assert.equal(zettelBefund(eigen, [], '', 432), null)
  assert.equal(zettelBefund(eigen, [], '2026-09-12', null), null, 'der Tag stimmt, das Gewicht ist noch nicht getippt')
  assert.deepEqual(zettelBefund(eigen, [], '2026-09-15', null), { art: 'kein_tag' }, 'Zetteldatum: an dem Tag kam keine Palette dieser Charge')
  assert.deepEqual(zettelBefund(eigen, [], '2026-09-15', 0), { art: 'kein_tag' }, '0 kg ist kein Gewicht, sondern ein leeres Feld')
})

test('Datum und Gewicht passen, die Kisten nicht: die Vorbelegung 36 bei einer Palette mit 40 (1616, Arbeit 1623)', () => {
  const mitKisten: EingangPalette[] = [
    { eingangsdatum: '2026-07-30', brutto_kg: 485, kisten: 40 },
    { eingangsdatum: '2026-07-30', brutto_kg: 483, kisten: 40 },
    { eingangsdatum: '2026-07-30', brutto_kg: 483, kisten: 36 },
  ]
  assert.deepEqual(zettelBefund(mitKisten, [], '2026-07-30', 485, 36), { art: 'kisten_anders', kisten: 40 })
  assert.deepEqual(zettelBefund(mitKisten, [], '2026-07-30', 485, 40), { art: 'passt' })
  assert.deepEqual(zettelBefund(mitKisten, [], '2026-07-30', 483, 36), { art: 'passt' }, 'eine der gleich schweren Paletten hat 36 Kisten')
  assert.deepEqual(zettelBefund(mitKisten, [], '2026-07-30', 485, null), { art: 'passt' }, 'ohne Kistenzahl auf der Maske nur Datum und Gewicht')
  assert.deepEqual(zettelBefund([{ eingangsdatum: '2026-07-30', brutto_kg: 485, kisten: null }], [], '2026-07-30', 485, 36), { art: 'passt' }, 'kennt der Wareneingang die Kisten nicht, gibt es nichts zu vergleichen')
})

test('Zettel der Nachbarcharge (1626/1623): Datum und Gewicht passen genau zu einer anderen Charge', () => {
  const fremd = [{ charge_nr: 1623, brutto_kg: 428 }, { charge_nr: 1623, brutto_kg: 430 }]
  assert.deepEqual(zettelBefund(eigen, fremd, '2026-09-12', 428), { art: 'fremde_charge', charge_nr: 1623 })
  // Gibt es die Palette auch in der eigenen Charge, gewinnt die eigene.
  assert.deepEqual(zettelBefund(eigen, [{ charge_nr: 1623, brutto_kg: 432 }], '2026-09-12', 432), { art: 'passt' })
})

test('Gewicht da, aber an einem anderen Tag (1632: 466 kg am 11.9. gezählt, eingegangen am 14.9.)', () => {
  assert.deepEqual(zettelBefund(eigen, [], '2026-09-11', 466), { art: 'anderer_tag', tage: ['2026-09-14'] })
  assert.deepEqual(zettelBefund(eigen, [], '2026-09-14', 432), { art: 'anderer_tag', tage: ['2026-09-12'] })
})

test('Tag da, Gewicht nicht (Zahlendreher 423 statt 432): kein_gewicht — Tag und Gewicht fremd: kein_tag', () => {
  assert.deepEqual(zettelBefund(eigen, [], '2026-09-12', 423), { art: 'kein_gewicht' })
  assert.deepEqual(zettelBefund(eigen, [], '2026-09-20', 423), { art: 'kein_tag' })
})

test('eine Charge ohne Wareneingang (1627): nichts zu vergleichen, und das wird gesagt', () => {
  assert.deepEqual(zettelBefund([], [{ charge_nr: 1626, brutto_kg: 300 }], '2026-09-12', 300), { art: 'ohne_eingang' })
})

test('Wägung: schwerer als beim Eingang (1648: 58 kg mehr) — wie die Auffälligkeit, ab 1 %', () => {
  const g2 = { kisten: 32, taraKiste: 1.5, taraPalette: 25, tage: 20, grenzeJeTag: 0.01 }
  assert.deepEqual(wiegungBefund({ ...g2, damals: 400, jetzt: 458 }), { art: 'schwerer', kg: 58 })
  assert.equal(wiegungBefund({ ...g2, damals: 400, jetzt: 403 }), null, 'unter 1 % schwerer: Waage, keine Auffälligkeit')
})

test('Wägung: zu schnell leichter — dieselbe Rate wie die Auswertung (1 − (jetzt/damals)^(1/Tage))', () => {
  // 1651: 424 kg → 151 kg netto in 21 Tagen = 4.80 % je Tag. Ohne Tara (0/0), damit netto = brutto.
  const b = wiegungBefund({ damals: 424, jetzt: 151, kisten: 30, taraKiste: 0, taraPalette: 0, tage: 21, grenzeJeTag: 0.01 })
  assert.deepEqual(b, { art: 'zu_schnell', prozentJeTag: 4.8 })
  // 1623: 58 → 38 kg in 34 Tagen = 1.24 % (linear wären es 1.01 %)
  assert.deepEqual(wiegungBefund({ damals: 58, jetzt: 38, kisten: 2, taraKiste: 0, taraPalette: 0, tage: 34, grenzeJeTag: 0.01 }), { art: 'zu_schnell', prozentJeTag: 1.2 })
  // 0.3 % je Tag ist Verdunstung
  assert.equal(wiegungBefund({ damals: 400, jetzt: 376, kisten: 2, taraKiste: 0, taraPalette: 0, tage: 20, grenzeJeTag: 0.01 }), null)
})

test('Wägung: gleich schwer, Datum heute, Netto weg, Tara fehlt', () => {
  const g = { kisten: 32, taraKiste: 1.5, taraPalette: 25, grenzeJeTag: 0.01 }
  assert.deepEqual(wiegungBefund({ ...g, damals: 400, jetzt: 400, tage: 10 }), { art: 'gleich' })
  assert.deepEqual(wiegungBefund({ ...g, damals: 400, jetzt: 390, tage: 0 }), { art: 'datum' })
  assert.deepEqual(wiegungBefund({ ...g, damals: 60, jetzt: 55, tage: 10 }), { art: 'netto' })
  assert.equal(wiegungBefund({ ...g, taraKiste: null, damals: 400, jetzt: 500, tage: 10 }), null, 'ohne Tara sagt die Maske „Tara fehlt", nicht mehr')
  assert.equal(wiegungBefund({ ...g, damals: 400, jetzt: 0, tage: 10 }), null, 'ein leeres Feld ist keine Wägung')
})

test('Tage zwischen zwei Daten', () => {
  assert.equal(tageZwischen('2026-09-12', '2026-10-12'), 30)
  assert.equal(tageZwischen('2026-10-12', '2026-10-12'), 0)
  assert.equal(tageZwischen('', '2026-10-12'), 0)
})

test('jeder Text der Prüfung steht in allen sechs Sprachen, mit seinen Platzhaltern', () => {
  const platzhalter: Record<string, string[]> = {
    zettelPasst: [], zettelOhneEingang: [], zettelFremdeCharge: ['{charge}'], zettelAndererTag: ['{kg}', '{tage}'],
    zettelKistenAnders: ['{n}', '{hier}'], zettelKistenUebernehmen: ['{n}'],
    zettelKeinTag: ['{datum}'], zettelKeinGewicht: ['{datum}', '{kg}'],
    wiegungDatum: [], wiegungNetto: [], wiegungSchwerer: ['{kg}'], wiegungGleich: [], wiegungZuSchnell: ['{prozent}'],
  }
  for (const { code } of SPRACHEN) {
    const wb = WOERTERBUCH[code] as Record<string, string>
    for (const [id, ph] of Object.entries(platzhalter)) {
      assert.ok(wb[id], `${code}.${id} fehlt`)
      for (const p of ph) assert.ok(wb[id].includes(p), `${code}.${id} ohne ${p}`)
    }
  }
})
