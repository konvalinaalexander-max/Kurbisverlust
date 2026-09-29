/**
 * Orakel 5 — die Stationswerte (seit 0106; bis 0105 stand hier das
 * Verderbsmodell F(t) = 1 − exp(−λ·t^k) mit Sockel, Smearing und Band).
 *
 * Die Kaskade rechnet das Faule einer Charge als Zusammensetzung der
 * Stationen auf ihrem Weg:
 *
 *   f = p_hand · f_W+S + (1 − p_hand) · (f_S + (1 − f_S) · p_wasch · g_W)
 *
 * Jeder Stationswert ist das nach Masse gewichtete Mittel der plausiblen
 * Palox-Punkte dieser Station — zuerst die letzten vier Wochen der Sorte
 * (ab drei Arbeiten), sonst ihre ganze Saison, sonst alle Sorten (vier
 * Wochen, dann Saison ab einer Arbeit). Der Weg kommt aus den eigenen
 * Arbeiten der Charge, sonst denen der Sorte, sonst allen.
 *
 * Gegenstücke: `v_palox_erwartung`, `v_charge_weg`, `palox_f()`,
 * `palox_f_nach()`, `v_charge_palox`.
 */
import { klemm, tQuantil95 } from './zahlen.ts'

export type Station = 'waschen_sortieren' | 'sortieren' | 'waschen'
export const STATIONEN: Station[] = ['waschen_sortieren', 'sortieren', 'waschen']

export interface Punkt {
  sorte: string
  station: Station
  chargeNr: number
  /** Der Betriebstag der Messung (ISO-Datum). */
  messtag: string
  /** Masse hinter dem Punkt (basis_jetzt_kg). */
  w: number
  /** Der eigene Anteil des Auges (anteil_station). */
  y: number
}

export interface Stationswert {
  anteil: number | null
  unten: number | null
  oben: number | null
  nArbeiten: number
  nChargen: number
}

/** Das nach Masse gewichtete Mittel, mit dem Band ± t · sd / √n über die Arbeiten. */
export function stationswert(punkte: Punkt[]): Stationswert {
  const n = punkte.length
  if (n === 0) return { anteil: null, unten: null, oben: null, nArbeiten: 0, nChargen: 0 }
  const sw = punkte.reduce((s, p) => s + p.w, 0)
  const anteil = punkte.reduce((s, p) => s + p.w * p.y, 0) / sw
  const mittel = punkte.reduce((s, p) => s + p.y, 0) / n
  const sd = n >= 2 ? Math.sqrt(punkte.reduce((s, p) => s + (p.y - mittel) ** 2, 0) / (n - 1)) : null
  const halb = sd == null ? 0 : tQuantil95(n - 1) * sd / Math.sqrt(n)
  return { anteil, unten: klemm(anteil - halb, 0, 1), oben: klemm(anteil + halb, 0, 1),
           nArbeiten: n, nChargen: new Set(punkte.map(p => p.chargeNr)).size }
}

export type Ebene = 'sorte_4w' | 'sorte_saison' | 'alle_4w' | 'alle_saison'

export interface Erwartung extends Stationswert {
  sorte: string
  station: Station
  ebene: Ebene
  geliehen: boolean
}

const tag = (s: string) => Math.round(Date.parse(s + 'T00:00:00Z') / 86400000)

/**
 * Je Sorte und Station die Erwartung — die erste Ebene, die genug Arbeiten
 * hat (Sorte: mindest, alle Sorten in vier Wochen: mindest, alle Sorten in
 * der Saison: eine). Sorten ohne Punkte an einer Station bekommen den Wert
 * aller Sorten (geliehen), oder keinen.
 */
export function erwartung(punkte: Punkt[], sorten: string[], heute: string, mindest = 3): Erwartung[] {
  const h = tag(heute)
  const alleSorten = [...new Set([...sorten, ...punkte.map(p => p.sorte)])]
  const aus: Erwartung[] = []
  for (const sorte of alleSorten) for (const station of STATIONEN) {
    const st = punkte.filter(p => p.station === station)
    const ebenen: [Ebene, Punkt[], number][] = [
      ['sorte_4w',     st.filter(p => p.sorte === sorte && tag(p.messtag) > h - 28), mindest],
      ['sorte_saison', st.filter(p => p.sorte === sorte), mindest],
      ['alle_4w',      st.filter(p => tag(p.messtag) > h - 28), mindest],
      ['alle_saison',  st, 1],
    ]
    for (const [ebene, drin, min] of ebenen) {
      if (drin.length < min) continue
      aus.push({ sorte, station, ebene, geliehen: ebene.startsWith('alle'), ...stationswert(drin) })
      break
    }
  }
  return aus
}

/** Die Zusammensetzung über den Weg — NULL, sobald eine Station auf dem Weg keinen Wert hat. */
export function paloxF(pHand: number | null, pWasch: number | null, fWs: number | null, fS: number | null, gW: number | null): number | null {
  if (pHand == null) return null
  if (pHand > 0 && fWs == null) return null
  if (pHand < 1 && fS == null) return null
  if (pHand < 1 && (pWasch ?? 0) > 0 && gW == null) return null
  const f = pHand * (fWs ?? 0) + (1 - pHand) * ((fS ?? 0) + (1 - (fS ?? 0)) * (pWasch ?? 0) * (gW ?? 0))
  return klemm(f, 0, 1)
}

/** Derselbe Anteil d Tage später: jede Station um ihren Zuwachs je Woche fortgeschrieben, dann zusammengesetzt. */
export function paloxFNach(pHand: number | null, pWasch: number | null, fWs: number | null, fS: number | null, gW: number | null,
                           bWs: number | null, bS: number | null, bW: number | null, dTage: number): number | null {
  const fort = (f: number | null, b: number | null) => f == null ? null : klemm(f + (b ?? 0) * dTage / 7, 0, 1)
  return paloxF(pHand, pWasch, fort(fWs, bWs), fort(fS, bS), fort(gW, bW))
}

export interface Arbeit { chargeNr: number; sorte: string; station: string; kg: number; istFax: boolean }
export interface Weg { pHand: number | null; pWasch: number | null; quelle: string | null }

/** Der Weg je Charge aus den Arbeiten: eigene, sonst die der Sorte, sonst alle. */
export function weg(arbeiten: Arbeit[], chargen: { chargeNr: number; sorte: string }[]): Map<number, Weg> {
  const summe = (as: Arbeit[]) => ({
    hand: as.filter(a => a.station === 'waschen_sortieren').reduce((s, a) => s + a.kg, 0),
    band: as.filter(a => a.station === 'sortieren').reduce((s, a) => s + a.kg, 0),
    wasch: as.filter(a => a.station === 'waschen' && !a.istFax).reduce((s, a) => s + a.kg, 0),
  })
  const gueltig = arbeiten.filter(a => a.kg > 0)
  const alle = summe(gueltig)
  return new Map(chargen.map(c => {
    const eigen = summe(gueltig.filter(a => a.chargeNr === c.chargeNr))
    const sorte = summe(gueltig.filter(a => a.sorte === c.sorte))
    const pHand = eigen.hand + eigen.band > 0 ? eigen.hand / (eigen.hand + eigen.band)
      : sorte.hand + sorte.band > 0 ? sorte.hand / (sorte.hand + sorte.band)
      : alle.hand + alle.band > 0 ? alle.hand / (alle.hand + alle.band) : null
    const pWasch = eigen.wasch > 0 || sorte.wasch > 0 ? 1
      : sorte.hand + sorte.band > 0 ? 0
      : alle.wasch > 0 ? 1 : alle.hand + alle.band > 0 ? 0 : null
    const quelle = eigen.hand + eigen.band > 0 ? 'eigenen Arbeiten'
      : sorte.hand + sorte.band > 0 ? 'Arbeiten der Sorte'
      : alle.hand + alle.band > 0 ? 'Arbeiten aller Sorten' : null
    return [c.chargeNr, { pHand, pWasch, quelle }]
  }))
}
