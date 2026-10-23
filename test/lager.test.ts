import { test } from 'node:test'
import assert from 'node:assert/strict'
import { imLagerBei, imLagerCharge, palettenIm, palettenStand, palettenStandSumme, palettenStandText, palettenText } from '../src/auswertung/lager.ts'
import type { Bestand, Kohorte, Prognose } from '../src/auswertung/daten.ts'

// 22. Oktober: „Wenn du jetzt ins Lager gehst — so viele Paletten wirst du wohl
// noch antreffen — und in Kilo: so viel kannst du tatsächlich noch verkaufen."
// Im Lager ist überall dieselbe Zahl: die gute Ware der Kaskade, ohne das
// Verdunstete und das Faule (src/auswertung/lager.ts).
// 23. Oktober, die Regel hat sich geändert und die Tests mit ihr: „Im Lager
// will ich, was wirklich steht — Paletten, bevor wir etwas in den Palox
// schmeissen … und vor der Verdunstung." Im Lager ist jetzt die Eingangsmasse
// auf den Paletten, die noch stehen (lager_kg), ohne Abzug; was abgeht, steht
// im Verkaufsfähigen (test/ausweis.test.ts).
// Runde AZ: die Form hat sich geändert, nicht die Regel — `hoechstens` war
// seit dem 23. Oktober immer falsch (die Eingangsmasse hängt an keiner Rate)
// und ist weg; imLagerBei gibt die Kilo direkt, imLagerCharge braucht keine
// Prognose mehr.

const p = (gruppe: Prognose['gruppe'], schluessel: string, h: number, gute: number, r = true, f = true) =>
  ({ gruppe, schluessel, h, lager_kg: 26834, verdunstet_kg: 2243, faul_kg: 2717, gute_ware_kg: gute, r_bekannt: r, f_bekannt: f } as unknown as Prognose)
const b = (nr: number, lager: number, im_haus: number, kanal_ausgelagert: number | null, paletten: number | null) =>
  ({ charge_nr: nr, lager_kg: lager, im_haus_heute_kg: im_haus, kanal_ausgelagert_kg: kanal_ausgelagert, n_rest_paletten: paletten } as unknown as Bestand)

test('imLagerBei: die Eingangsmasse auf den Paletten beim Horizont — ohne Abzug, auch wenn eine Rate nicht gemessen ist', () => {
  const prognose = [p('gesamt', '', 0, 21874), { ...p('gesamt', '', 28, 20100), lager_kg: 25000 } as Prognose, p('sorte', 'Amoro', 0, 900, true, false)]
  assert.equal(imLagerBei(prognose, 'gesamt', '', 0), 26834, 'lager_kg, nicht die gute Ware 21874')
  assert.equal(imLagerBei(prognose, 'gesamt', 'egal', 28), 25000, 'gesamt hat keinen Schlüssel')
  assert.equal(imLagerBei(prognose, 'sorte', 'Amoro', 0), 26834, 'die Eingangsmasse hängt an keiner Rate — kein „höchstens"')
  assert.equal(imLagerBei(prognose, 'sorte', 'Tiana', 0), null, 'ohne Zeile leer, nicht 0')
})

test('imLagerCharge: die Eingangsmasse der Paletten, die noch stehen — nicht die gute Ware, nicht das Haus ohne Aussortiertes', () => {
  assert.equal(imLagerCharge(b(1632, 26834, 22335, 461, 68)), 26834)
  assert.equal(imLagerCharge(b(1611, 25977, 21884, 704, 65)), 25977)
  assert.equal(imLagerCharge(b(1625, 1600, 1300, null, 4)), 1600)
  assert.equal(imLagerCharge(b(1, -5, 0, null, null)), 0, 'eine Überzählung macht kein negatives Lager')
})

test('palettenIm: die Paletten der Chargen, die noch liegen — leer, wenn keine eine Zahl hat', () => {
  assert.equal(palettenIm([b(1, 100, 90, 0, 3), b(2, 0, 0, 0, 5), b(3, 50, 40, 0, null)]), 3, 'eine ausgelieferte Charge zählt nicht')
  assert.equal(palettenIm([b(3, 50, 40, 0, null)]), null)
  assert.equal(palettenText(1), '≈ 1 Palette')
  assert.equal(palettenText(68), '≈ 68 Paletten')
  assert.equal(palettenText(null), '')
  assert.equal(palettenText(0), '< 1 Palette', 'Ware da, aber keine ganze Palette — nicht „≈ 0"')
})

// Runde BA — der Betrieb: „du hast von der Charge noch 7 Paletten — dann kann ich
// nachschauen gehen, ob da wirklich 7 Paletten stehen." Die ≈-Paletten sind ein
// Äquivalent aus den Lieferscheinen; was wirklich dasteht, sind die Eingangs-
// paletten, die beim Sortieren noch nie gezählt wurden (erg_kohorte.n_rest).
const ko = (nr: number, tag: string, n: number, verarbeitet: number) =>
  ({ charge_nr: nr, eingangsdatum: tag, n_paletten: n, n_verarbeitet: verarbeitet, n_rest: Math.max(n - verarbeitet, 0) } as Kohorte)
const kohorten = [ko(1611, '2026-04-13', 50, 40), ko(1611, '2026-04-17', 46, 24), ko(1598, '2026-03-31', 4, 4), ko(1598, '2026-04-01', 2, 2),
                  ko(1601, '2026-04-21', 20, 3), ko(1601, '2026-04-22', 6, 2)]

test('Runde BA: palettenStand — unsortierte Eingangspaletten (nachzählbar) und das Äquivalent in Kisten', () => {
  const s = palettenStand(b(1611, 25977, 21884, 704, 65), kohorten)
  assert.deepEqual(s, { aequivalent: 65, unsortiert: 32, inKisten: 33, widerspruch: false })
  assert.equal(palettenStandText(s), '32 unsortiert · ≈ 33 in Kisten')
  const sortiert = palettenStand(b(1598, 774, 600, 0, 2), kohorten)
  assert.deepEqual(sortiert, { aequivalent: 2, unsortiert: 0, inKisten: 2, widerspruch: false })
  assert.equal(palettenStandText(sortiert), 'alles sortiert · ≈ 2 in Kisten')
  const unberuehrt = palettenStand(b(1601, 7262, 6000, 0, 21), kohorten)
  assert.equal(palettenStandText(unberuehrt), 'alle 21 unsortiert', 'nichts in Kisten')
})

test('Runde BA: mehr unsortierte Paletten gezählt, als laut Lieferscheinen noch da wären — gesagt, nicht verrechnet', () => {
  const s = palettenStand(b(1601, 7262, 6000, 0, 19), kohorten)
  assert.equal(s.unsortiert, 21); assert.equal(s.inKisten, 0); assert.equal(s.widerspruch, true)
  // Runde BA: der Satz nennt beide Zahlen, kurz genug für die Zelle im Chargen-Reiter.
  assert.equal(palettenStandText(s), '21 unsortiert — laut Lieferscheinen nur ≈ 19 da')
})

test('Runde BA: ohne Eingangstage oder ohne Ware bleibt der Stand leer, nie 0', () => {
  assert.deepEqual(palettenStand(b(1632, 26834, 22335, 461, 68), kohorten), { aequivalent: 68, unsortiert: null, inKisten: null, widerspruch: false })
  assert.equal(palettenStandText(palettenStand(b(1632, 26834, 22335, 461, 68), kohorten)), '')
  assert.equal(palettenStand(b(1598, 0, 0, 0, 0), kohorten).aequivalent, null, 'nichts im Lager')
  assert.equal(palettenStand(b(1598, 500, 400, 0, null), kohorten).aequivalent, null, 'ohne Palettenzahl')
})

test('Runde BA: palettenStandSumme zählt nur Chargen mit Ware zusammen und trägt einen Widerspruch weiter', () => {
  const liste = [b(1611, 25977, 21884, 704, 65), b(1598, 774, 600, 0, 2), b(1632, 0, 0, 0, 68), b(1601, 7262, 6000, 0, 19)]
  const s = palettenStandSumme(liste, kohorten)
  assert.deepEqual(s, { aequivalent: 86, unsortiert: 53, inKisten: 35, widerspruch: true })
  assert.deepEqual(palettenStandSumme([b(1632, 0, 0, 0, 68)], kohorten), { aequivalent: null, unsortiert: null, inKisten: null, widerspruch: false })
})
