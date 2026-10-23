/**
 * Was „im Lager" heisst — an jeder Stelle dasselbe (22. Oktober, 23. Oktober).
 *
 * Der Betrieb: „Wieso nimmt es die Paloxe noch zum Lager dazu? … vielleicht
 * einfach klarer ausweisen — wie viel ist noch hier, im Lager, Anzahl
 * Paletten, auch ohne Verdunstung und ohne Palox, und dann wie viel ist
 * verkaufsfähig. … Wenn du jetzt ins Lager gehst, so viele Paletten wirst du
 * wohl noch antreffen — und in Kilo: so viel kannst du tatsächlich noch
 * verkaufen."
 *
 * Bis hier war „im Lager" die Eingangsmasse, die noch nicht ausgeliefert ist
 * (`lager_kg`) — darin auch, was seither verdunstet ist und was faul in den
 * Palox geht. Jetzt ist es, was auf den Paletten liegt: die gute Ware der
 * Kaskade (`gute_ware_kg`, das Liegende nach Verdunstung und Faulem). Darin
 * steckt das Verkaufsfähige und, was zu klein oder zu gross ist. Was hinter
 * den Lieferungen schon aussortiert in Paloxen steht, gehört nicht dazu — es
 * ist keine Ware der Paletten mehr (die Bilanz zählt es weiter „im Haus").
 *
 * Die Paletten: `n_rest_paletten` je Charge — die Eingangsmasse, die nicht
 * ausgeliefert ist, geteilt durch die mittlere Eingangspalette der Charge.
 * Verdunstung und Faules leeren keine Palette, darum rechnet sie mit der
 * Eingangsmasse; und ohne Lieferung bleibt sie auch in ein paar Wochen gleich.
 */
/*
 * 23. Oktober, der Betrieb noch einmal: „Im Lager will ich eigentlich, was
 * wirklich steht — Paletten, bevor wir etwas in den Palox schmeissen, bevor es
 * Arbeiten erlebt, und vor der Verdunstung: wie viele Paletten vom Eingang
 * noch im Lager stehen." Darum ist „im Lager" jetzt die Eingangsmasse auf den
 * Paletten, die noch dastehen (`lager_kg`), ohne Abzug — und alles, was abgeht
 * (Verdunstung, Palox, zu klein / zu gross, passt in keinen Artikel,
 * Überfüllung), steht im Verkaufsfähigen (src/auswertung/ausweis.ts, 0123).
 * Die gute Ware der Kaskade (`gute_ware_kg`) heisst nicht mehr „im Lager".
 */
// Nur Typen aus daten.ts — wie artikel.ts, damit test/lager.test.ts ohne Datenbank läuft.
import type { Bestand, Gruppe, Prognose } from './daten'

/** Die Zeile der Prognose — wie `prognoseBei` in daten.ts: „gesamt" hat keinen Schlüssel. */
function zeileBei(prognose: Prognose[], gruppe: Gruppe, schluessel: string, h: number): Prognose | null {
  const k = gruppe === 'gesamt' ? '' : schluessel
  return prognose.find(z => z.gruppe === gruppe && z.schluessel === k && z.h === h) ?? null
}

export interface ImLager {
  /** Kilo auf den Paletten, wie sie eingingen; null, wenn die Rechnung für die Gruppe fehlt. */
  kg: number | null
  /** Seit dem 23. Oktober immer false: Die Eingangsmasse hängt an keiner Rate. Bleibt, damit die Stellen, die es lesen, gleich bleiben. */
  hoechstens: boolean
}

/** Im Lager einer Gruppe beim Horizont h (Tage ab heute), aus der Prognose. */
export function imLagerBei(prognose: Prognose[], gruppe: Gruppe, schluessel: string, h: number): ImLager {
  const p = zeileBei(prognose, gruppe, schluessel, h)
  if (!p) return { kg: null, hoechstens: false }
  return { kg: Number(p.lager_kg), hoechstens: false }
}

/** Im Lager einer Charge heute: die Eingangsmasse auf den Paletten, die noch stehen. */
export function imLagerCharge(b: Bestand, _prognose?: Prognose[]): number {
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
