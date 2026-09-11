/**
 * Orakel 4 — die Massenkaskade.
 *
 * Von der Eingangsmasse m0 bleibt nach t Lagertagen:
 *
 *   m1 = m0 · (1−r)^t                                      nach der Verdunstung
 *   m2 = m1 · (1−a0) · (1−f)                                nach Sockel und Schimmel
 *   verkaufsfähig = m2 · (1 − a_klein_n − a_gross_n) · (1 − a_fax)
 *
 * und die Ströme sind die Differenzen dazwischen. Sie summieren sich exakt
 * zu m0 — das ist die eine Invariante, die niemals brechen darf.
 *
 * Für die Portion „ausgelagert" ist nur das Gelieferte bekannt; m0 wird
 * **zurückgerechnet**: m0 = geliefert / verkaufsfaehig_anteil, und der Anteil
 * ist nach unten bei 0.25 gedeckelt (sonst macht eine kleine Lieferung eine
 * riesige Eingangsmasse). Für „entsorgt" gilt nur die Verdunstung
 * (0065), für „lager" ist m0 = Eingang der Kohorte − Σ m0 der Lieferungen.
 *
 * Gegenstücke: `mv_kaskade`, `mv_hochrechnung` (Ströme mit Ableitungen).
 */
import { klemm } from './zahlen.ts'

export type Portion = 'ausgelagert' | 'entsorgt' | 'lager'

export interface Koeffizienten {
  /** Tagesrate der Verdunstung, schon geklemmt auf [0, 0.05]. */
  r: number
  /** Grundaussortierung (Sockel) aus dem Verderbsmodell, 0 ohne brauchbares Modell. */
  a0: number
  /** Schimmelanteil bei dieser Lagerdauer, schon in [0, 1]. */
  f: number
  /** Roh: Massenanteil zu klein bzw. zu gross, je in [0, 1]; werden hier normiert. */
  aKlein: number
  aGross: number
  aFax: number
}

/** a_klein + a_gross darf zusammen nicht über 1 — sonst wird beides anteilig gestaucht. */
export function normieren(aKlein: number, aGross: number): { aKleinN: number; aGrossN: number } {
  const nf = Math.max(aKlein + aGross, 1)
  return { aKleinN: aKlein / nf, aGrossN: aGross / nf }
}

export function verdunstungsAnteil(r: number, alterTage: number): number {
  return Math.max(Math.pow(1 - r, alterTage), 0.25)
}

export function verkaufsfaehigAnteil(k: Koeffizienten, alterTage: number): number {
  const { aKleinN, aGrossN } = normieren(k.aKlein, k.aGross)
  const roh = Math.pow(1 - k.r, alterTage) * (1 - k.a0) * (1 - k.f) * (1 - aKleinN - aGrossN) * (1 - k.aFax)
  return Math.max(roh, 0.25)
}

/** m0 aus dem Gelieferten — für „ausgelagert" über den Verkaufsanteil, für „entsorgt" nur über die Verdunstung. */
export function m0Zurueck(geliefertKg: number, portion: Portion, k: Koeffizienten, alterTage: number): number {
  return portion === 'entsorgt' ? geliefertKg / verdunstungsAnteil(k.r, alterTage)
                                 : geliefertKg / verkaufsfaehigAnteil(k, alterTage)
}

/** Die Lager-Portion: was vom Eingang der Kohorte hinter den Lieferungen übrig ist. */
export function lagerPortion(eingangKohorteKg: number, m0Ausgelagert: number): { m0: number; ueberzaehlungKg: number } {
  return { m0: Math.max(eingangKohorteKg - m0Ausgelagert, 0), ueberzaehlungKg: Math.max(m0Ausgelagert - eingangKohorteKg, 0) }
}

export interface Stroeme {
  m0: number; m1: number; m2: number
  verdunstungKg: number; sockelKg: number; schimmelKg: number
  kleinKg: number; nebenkanalKg: number; faxKg: number; verkaufsfaehigKg: number
}

export function stroeme(m0: number, portion: Portion, k: Koeffizienten, alterTage: number): Stroeme {
  const { aKleinN, aGrossN } = normieren(k.aKlein, k.aGross)
  const m1 = m0 * Math.pow(1 - k.r, alterTage)
  if (portion === 'entsorgt') {
    // Entsorgte Ware ist selbst das Faule: nach der Verdunstung ist alles Schimmel.
    return { m0, m1, m2: 0, verdunstungKg: m0 - m1, sockelKg: 0, schimmelKg: m1,
             kleinKg: 0, nebenkanalKg: 0, faxKg: 0, verkaufsfaehigKg: 0 }
  }
  const m2 = m1 * (1 - k.a0) * (1 - k.f)
  const rest = m2 * (1 - aKleinN - aGrossN)
  return {
    m0, m1, m2,
    verdunstungKg: m0 - m1,
    sockelKg: m1 * k.a0,
    schimmelKg: m1 * (1 - k.a0) * k.f,
    kleinKg: m2 * aKleinN,
    nebenkanalKg: m2 * aGrossN,
    faxKg: rest * k.aFax,
    verkaufsfaehigKg: rest * (1 - k.aFax),
  }
}

/** Die Invariante: Σ Ströme = m0, auf ein Millionstel von m0 genau. */
export function summeStimmt(s: Stroeme): boolean {
  const summe = s.verdunstungKg + s.sockelKg + s.schimmelKg + s.kleinKg + s.nebenkanalKg + s.faxKg + s.verkaufsfaehigKg
  return Math.abs(summe - s.m0) <= 1e-6 * Math.max(s.m0, 1)
}

/** Sensitivitäten, wie mv_kaskade sie trägt — für die Unsicherheitsbänder. */
export function ableitungen(m0: number, k: Koeffizienten, alterTage: number, eta: number | null, modellGilt: boolean) {
  const dM1r = -m0 * alterTage * Math.pow(1 - k.r, Math.max(alterTage - 1, 0))
  const dFeta = modellGilt && eta != null ? (1 - k.f) * Math.exp(klemm(eta, -40, 3)) : 0
  return { dM1r, dFeta }
}

/**
 * Was am Deckel 0.25 hängt: Ist der Anteil gedeckelt, dann ist m0 nicht mehr
 * die Umkehrung der Kaskade — die Ströme summieren sich zwar noch zu m0, aber
 * „verkaufsfähig" ist dann **kleiner** als das Gelieferte. Das Orakel meldet
 * diesen Zustand, damit er im Bericht steht und nicht in einer Kennzahl
 * verschwindet.
 */
export function gedeckelt(k: Koeffizienten, alterTage: number): boolean {
  const { aKleinN, aGrossN } = normieren(k.aKlein, k.aGross)
  return Math.pow(1 - k.r, alterTage) * (1 - k.a0) * (1 - k.f) * (1 - aKleinN - aGrossN) * (1 - k.aFax) < 0.25
}
