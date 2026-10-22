import { test } from 'node:test'
import assert from 'node:assert/strict'
import { imLagerBei, imLagerCharge, palettenIm, palettenText } from '../src/auswertung/lager.ts'
import type { Bestand, Prognose } from '../src/auswertung/daten.ts'

// 22. Oktober: „Wenn du jetzt ins Lager gehst — so viele Paletten wirst du wohl
// noch antreffen — und in Kilo: so viel kannst du tatsächlich noch verkaufen."
// Im Lager ist überall dieselbe Zahl: die gute Ware der Kaskade, ohne das
// Verdunstete und das Faule (src/auswertung/lager.ts).

const p = (gruppe: Prognose['gruppe'], schluessel: string, h: number, gute: number, r = true, f = true) =>
  ({ gruppe, schluessel, h, lager_kg: 26834, verdunstet_kg: 2243, faul_kg: 2717, gute_ware_kg: gute, r_bekannt: r, f_bekannt: f } as unknown as Prognose)
const b = (nr: number, lager: number, im_haus: number, kanal_ausgelagert: number | null, paletten: number | null) =>
  ({ charge_nr: nr, lager_kg: lager, im_haus_heute_kg: im_haus, kanal_ausgelagert_kg: kanal_ausgelagert, n_rest_paletten: paletten } as unknown as Bestand)

test('imLagerBei: die gute Ware beim Horizont — höchstens, solange Verdunstung oder Faules nicht gemessen ist', () => {
  const prognose = [p('gesamt', '', 0, 21874), p('gesamt', '', 28, 20100), p('sorte', 'Amoro', 0, 900, true, false)]
  assert.deepEqual(imLagerBei(prognose, 'gesamt', '', 0), { kg: 21874, hoechstens: false })
  assert.deepEqual(imLagerBei(prognose, 'gesamt', 'egal', 28), { kg: 20100, hoechstens: false }, 'gesamt hat keinen Schlüssel')
  assert.deepEqual(imLagerBei(prognose, 'sorte', 'Amoro', 0), { kg: 900, hoechstens: true })
  assert.deepEqual(imLagerBei(prognose, 'sorte', 'Tiana', 0), { kg: null, hoechstens: false }, 'ohne Zeile leer, nicht 0')
})

test('imLagerCharge: aus der Prognose der Charge; ohne sie im Haus weniger das schon Aussortierte', () => {
  const prognose = [p('charge', '1632', 0, 21874)]
  assert.equal(imLagerCharge(b(1632, 26834, 22335, 461, 68), prognose), 21874)
  assert.equal(imLagerCharge(b(1611, 25977, 21884, 704, 65), prognose), 21180)
  assert.equal(imLagerCharge(b(1625, 1600, 1300, null, 4), prognose), 1300, 'ein ungemessener Kanal steht nicht im Haus')
})

test('palettenIm: die Paletten der Chargen, die noch liegen — leer, wenn keine eine Zahl hat', () => {
  assert.equal(palettenIm([b(1, 100, 90, 0, 3), b(2, 0, 0, 0, 5), b(3, 50, 40, 0, null)]), 3, 'eine ausgelieferte Charge zählt nicht')
  assert.equal(palettenIm([b(3, 50, 40, 0, null)]), null)
  assert.equal(palettenText(1), '≈ 1 Palette')
  assert.equal(palettenText(68), '≈ 68 Paletten')
  assert.equal(palettenText(null), '')
  assert.equal(palettenText(0), '< 1 Palette', 'Ware da, aber keine ganze Palette — nicht „≈ 0"')
})
