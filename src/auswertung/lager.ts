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
import type { Bestand, Gruppe, Kohorte, Prognose } from './daten'

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

/* ---------- Runde BA: Paletten zum Nachzählen ------------------------------ */

/**
 * Der Betrieb, 23. Oktober: „Warum will ich wissen, wie viel im Lager ist, in
 * Paletten? So dass mir die App sagt: du hast von der Charge noch 7 Paletten
 * — und dann kann ich nachschauen gehen, ob da wirklich 7 Paletten stehen."
 *
 * Die ≈-Paletten (`n_rest_paletten`) sind ein Äquivalent: Eingang minus die
 * Eingangskilo hinter den Lieferscheinen, durch die mittlere Eingangspalette.
 * Was schon sortiert, aber nicht verkauft ist, steht aber in Kisten, nicht
 * mehr auf Eingangspaletten. Die Halle zählt jede Eingangspalette beim
 * Sortieren (auftrag_palette; erg_kohorte.n_rest je Eingangstag = gekommen −
 * gezählt). Also sagt die App beides: unsortierte Eingangspaletten — die
 * stehen wirklich da und lassen sich zählen — und das Äquivalent in Kisten.
 */
export interface PalettenStand {
  /** ≈ Paletten im Lager (Äquivalent); null, wenn nichts liegt oder die Zahl fehlt. */
  aequivalent: number | null
  /** Eingangspaletten, die noch nie beim Sortieren gezählt wurden — nachzählbar; null ohne Eingangstage. */
  unsortiert: number | null
  /** Was vom Äquivalent über die unsortierten Paletten hinausgeht: sortiert, noch da, in Kisten. */
  inKisten: number | null
  /** Mehr unsortierte Paletten gezählt, als laut Lieferscheinen überhaupt noch da sind — ein Zettel oder eine Lieferung stimmt nicht. */
  widerspruch: boolean
}

export function palettenStand(b: Bestand, kohorten: Kohorte[]): PalettenStand {
  const aequivalent = b.lager_kg > 0 && b.n_rest_paletten != null ? Number(b.n_rest_paletten) : null
  const k = kohorten.filter(x => x.charge_nr === b.charge_nr)
  const unsortiert = k.length ? k.reduce((s, x) => s + Number(x.n_rest), 0) : null
  if (aequivalent === null || unsortiert === null) return { aequivalent, unsortiert, inKisten: null, widerspruch: false }
  return { aequivalent, unsortiert, inKisten: Math.max(aequivalent - unsortiert, 0), widerspruch: unsortiert > aequivalent + 0.5 }
}

/** Die Paletten mehrerer Chargen zusammen — nur die, die liegen; leer, wenn keine eine Zahl hat. */
export function palettenStandSumme(chargen: Bestand[], kohorten: Kohorte[]): PalettenStand {
  let aequivalent: number | null = null, unsortiert: number | null = null, inKisten: number | null = null, widerspruch = false
  for (const b of chargen) {
    if (!(b.lager_kg > 0)) continue
    const s = palettenStand(b, kohorten)
    if (s.aequivalent !== null) aequivalent = (aequivalent ?? 0) + s.aequivalent
    if (s.unsortiert !== null) unsortiert = (unsortiert ?? 0) + s.unsortiert
    if (s.inKisten !== null) inKisten = (inKisten ?? 0) + s.inKisten
    widerspruch ||= s.widerspruch
  }
  return { aequivalent, unsortiert, inKisten, widerspruch }
}

/** „5 unsortiert · ≈ 2 in Kisten" — der Satz unter den ≈-Paletten; leer, wenn die Halle nichts gezählt hat. */
export function palettenStandText(s: PalettenStand): string {
  if (s.unsortiert === null || s.inKisten === null) return ''
  const u = `${s.unsortiert} unsortiert`
  // Runde BA: kurz, damit die Zelle im Chargen-Reiter nicht breiter als der Bildschirm wird — was der Widerspruch heisst, steht im Zeiger.
  if (s.widerspruch) return `${u} — laut Lieferscheinen nur ≈ ${s.aequivalent} da`
  if (s.unsortiert === 0) return `alles sortiert · ≈ ${s.inKisten} in Kisten`
  if (s.inKisten === 0) return `alle ${u}`
  return `${u} · ≈ ${s.inKisten} in Kisten`
}

/** Was die zwei Zahlen heissen — für Zeiger und Erklärung. */
export const PALETTEN_STAND_TEXT =
  'unsortiert: Eingangspaletten, die beim Sortieren noch nie gezählt wurden — die stehen wirklich da und lassen sich zählen; in Kisten: was laut Lieferscheinen noch da ist, aber schon sortiert wurde'
