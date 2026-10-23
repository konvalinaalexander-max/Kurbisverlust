/**
 * Was „im Lager" heisst — an jeder Stelle dasselbe (23. Oktober, 0123).
 *
 * Der Betrieb: „Im Lager will ich eigentlich, was wirklich steht — Paletten,
 * bevor wir etwas in den Palox schmeissen, bevor es Arbeiten erlebt, und vor
 * der Verdunstung: wie viele Paletten vom Eingang noch im Lager stehen. Und
 * verkaufsfähig wirklich das, was wir verkaufen können — minus allem."
 *
 * Darum ist „im Lager" die Eingangsmasse auf den Paletten, die noch dastehen
 * (`lager_kg`: Eingang minus die Eingangsware hinter den Lieferungen), ohne
 * Abzug — und alles, was abgeht (Verdunstung, Palox, zu klein / zu gross,
 * passt in keinen Artikel, Überfüllung), steht im Verkaufsfähigen
 * (src/auswertung/ausweis.ts, v_lager_ausweis). Die gute Ware der Kaskade
 * (`gute_ware_kg`, am 22. Oktober einen Tag lang „im Lager") heisst nicht mehr
 * so. Weil die Eingangsmasse an keiner gemessenen Rate hängt, gibt es hier
 * kein „höchstens".
 *
 * Die Paletten: `n_rest_paletten` je Charge — die Eingangsmasse, die nicht
 * ausgeliefert ist, geteilt durch die mittlere Eingangspalette der Charge.
 * Verdunstung und Faules leeren keine Palette, darum rechnet sie mit der
 * Eingangsmasse; und ohne Lieferung bleibt sie auch in ein paar Wochen gleich.
 */
// Nur Typen aus daten.ts — wie artikel.ts, damit test/lager.test.ts ohne Datenbank läuft.
import type { Bestand, Gruppe, Prognose } from './daten'

/** Im Lager einer Gruppe beim Horizont h (Tage ab heute), aus der Prognose — null, wenn die Zeile fehlt (nie 0). */
export function imLagerBei(prognose: Prognose[], gruppe: Gruppe, schluessel: string, h: number): number | null {
  // Wie `prognoseBei` in daten.ts: „gesamt" hat keinen Schlüssel.
  const k = gruppe === 'gesamt' ? '' : schluessel
  const p = prognose.find(z => z.gruppe === gruppe && z.schluessel === k && z.h === h)
  return p ? Number(p.lager_kg) : null
}

/** Im Lager einer Charge heute: die Eingangsmasse auf den Paletten, die noch stehen. */
export function imLagerCharge(b: Bestand): number {
  return Math.max(Number(b.lager_kg), 0)
}

/** Wie viele Paletten die Chargen noch haben — null, wenn keine eine Zahl hat. */
export function palettenIm(chargen: Bestand[]): number | null {
  let n: number | null = null
  for (const b of chargen) if (b.lager_kg > 0 && b.n_rest_paletten != null) n = (n ?? 0) + Number(b.n_rest_paletten)
  return n
}

/** „≈ 12 Paletten" — oder nichts, wenn die Zahl fehlt. Gerundet 0 heisst: Ware da, aber keine ganze Palette mehr. */
export function palettenText(n: number | null): string {
  if (n === null) return ''
  if (n === 0) return '< 1 Palette'
  return `≈ ${n} ${n === 1 ? 'Palette' : 'Paletten'}`
}

/** Was „im Lager" heisst, in einem Satz — für Kopf, Kachel und Zeiger. */
export const IM_LAGER_TEXT =
  'was an Paletten vom Eingang noch dasteht, mit dem Gewicht beim Eingang — vor Verdunstung, Palox und Arbeit'
