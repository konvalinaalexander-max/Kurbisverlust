import { test } from 'node:test'
import assert from 'node:assert/strict'
import { imLagerBei, imLagerCharge, palettenIm, palettenText } from '../src/auswertung/lager.ts'
import type { Bestand, Prognose } from '../src/auswertung/daten.ts'

// 22. Oktober: „Wenn du jetzt ins Lager gehst — so viele Paletten wirst du wohl
// noch antreffen — und in Kilo: so viel kannst du tatsächlich noch verkaufen."
// Im Lager ist überall dieselbe Zahl: die gute Ware der Kaskade, ohne das
// Verdunstete und das Faule (src/auswertung/lager.ts).
// 23. Oktober, die Regel hat sich geändert und die Tests mit ihr: „Im Lager
// will ich, was wirklich steht — Paletten, bevor wir etwas in den Palox
// schmeissen … und vor der Verdunstung." Im Lager ist jetzt die Eingangsmasse
// auf den Paletten, die noch stehen (lager_kg), ohne Abzug; was abgeht, steht
// im Verkaufsfähigen (test/ausweis.test.ts).

const p = (gruppe: Prognose['gruppe'], schluessel: string, h: number, gute: number, r = true, f = true) =>
  ({ gruppe, schluessel, h, lager_kg: 26834, verdunstet_kg: 2243, faul_kg: 2717, gute_ware_kg: gute, r_bekannt: r, f_bekannt: f } as unknown as Prognose)
const b = (nr: number, lager: number, im_haus: number, kanal_ausgelagert: number | null, paletten: number | null) =>
  ({ charge_nr: nr, lager_kg: lager, im_haus_heute_kg: im_haus, kanal_ausgelagert_kg: kanal_ausgelagert, n_rest_paletten: paletten } as unknown as Bestand)

test('imLagerBei: die Eingangsmasse auf den Paletten beim Horizont — ohne Abzug, auch wenn eine Rate nicht gemessen ist', () => {
  const prognose = [p('gesamt', '', 0, 21874), { ...p('gesamt', '', 28, 20100), lager_kg: 25000 } as Prognose, p('sorte', 'Amoro', 0, 900, true, false)]
  assert.deepEqual(imLagerBei(prognose, 'gesamt', '', 0), { kg: 26834, hoechstens: false }, 'lager_kg, nicht die gute Ware 21874')
  assert.deepEqual(imLagerBei(prognose, 'gesamt', 'egal', 28), { kg: 25000, hoechstens: false }, 'gesamt hat keinen Schlüssel')
  assert.deepEqual(imLagerBei(prognose, 'sorte', 'Amoro', 0), { kg: 26834, hoechstens: false }, 'die Eingangsmasse hängt an keiner Rate')
  assert.deepEqual(imLagerBei(prognose, 'sorte', 'Tiana', 0), { kg: null, hoechstens: false }, 'ohne Zeile leer, nicht 0')
})

test('imLagerCharge: die Eingangsmasse der Paletten, die noch stehen — nicht die gute Ware, nicht das Haus ohne Aussortiertes', () => {
  const prognose = [p('charge', '1632', 0, 21874)]
  assert.equal(imLagerCharge(b(1632, 26834, 22335, 461, 68), prognose), 26834)
  assert.equal(imLagerCharge(b(1611, 25977, 21884, 704, 65), prognose), 25977)
  assert.equal(imLagerCharge(b(1625, 1600, 1300, null, 4)), 1600, 'ohne Prognose dasselbe')
})

test('palettenIm: die Paletten der Chargen, die noch liegen — leer, wenn keine eine Zahl hat', () => {
  assert.equal(palettenIm([b(1, 100, 90, 0, 3), b(2, 0, 0, 0, 5), b(3, 50, 40, 0, null)]), 3, 'eine ausgelieferte Charge zählt nicht')
  assert.equal(palettenIm([b(3, 50, 40, 0, null)]), null)
  assert.equal(palettenText(1), '≈ 1 Palette')
  assert.equal(palettenText(68), '≈ 68 Paletten')
  assert.equal(palettenText(null), '')
  assert.equal(palettenText(0), '< 1 Palette', 'Ware da, aber keine ganze Palette — nicht „≈ 0"')
})
