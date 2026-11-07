/**
 * Orakel 5 — die Stationswerte (seit 0106; bis 0105 stand hier das
 * Verderbsmodell F(t) = 1 − exp(−λ·t^k) mit Sockel, Smearing und Band).
 *
 * Die Kaskade rechnet das Faule einer Charge als Zusammensetzung der
 * Stationen auf ihrem Weg:
 *
 *   f = p_hand · f_W+S + (1 − p_hand) · (f_S + (1 − f_S) · p_wasch · g_W)
 *
 * Seit 0111 ist jeder Stationswert eine Gerade über die Lagerdauer:
 *
 *   Anteil(t) = Grundausschuss der Sorte + Anstieg der Station × t / 7
 *
 * Der Anstieg je Station wird innerhalb der Sorten gemessen (jede Sorte um
 * ihre eigene, nach Masse gewichtete Mitte von Lagerdauer und Anteil) und
 * ist bekannt ab fünf Arbeiten in Sorten mit mindestens zwei Arbeiten und
 * drei Wochen Spanne der Lagerdauern innerhalb einer Sorte; er ist nie
 * negativ. Seit 0113 gilt er erst, wenn er sicher ist — die untere Grenze
 * seines 95-%-Bereichs (Standardfehler der gemeinsamen Steigung, je Sorte
 * eine eigene Höhe) liegt über 0 —, sonst gilt 0.
 * Der Grundausschuss ist das massegewichtete Mittel, um den Anstieg, der
 * gilt, auf null Tage zurückgelegt — gilt keiner, ist er das Mittel selbst.
 * Seit 0132 der der Sorte, gewichtet n ÷ (n + 3) mit dem aller Sorten (je
 * Ebene nie unter 0); ohne Arbeit der Sorte der aller (geliehen). Das Band ist
 * ± t · sd / √(n + 3) mit der Streuung einer Arbeit über alle Sorten der Station.
 * Der Weg kommt aus den eigenen Arbeiten der Charge, sonst denen der Sorte,
 * sonst allen.
 *
 * Gegenstücke: `palox_station_kennzahl`/`v_palox_station`, `palox_anstieg`,
 * `v_palox_erwartung`, `v_charge_weg`, `palox_f()`, `palox_f_nach()`,
 * `v_charge_palox`.
 */
import { klemm, runden, tQuantil95 } from './zahlen.ts'

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
  /** Die Lagertage der verarbeiteten Ware (seit 0111 die Achse des Anstiegs). */
  t: number
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

/** Bis 0131: ab so vielen Arbeiten galt der Wert der Sorte ganz (palox_mindest_arbeiten). Seit 0132 nicht mehr gebraucht. */
export const PALOX_MINDEST_ARBEITEN = 3
/** Seit 0132: alle Sorten zählen wie so viele Arbeiten (vorwissen_messungen) — die Sorte zählt n ÷ (n + 3). */
export const VORWISSEN_MESSUNGEN = 3
/** So weit müssen die Lagerdauern innerhalb einer Sorte auseinanderliegen (palox_anstieg_mindest_tage). */
export const ANSTIEG_MINDEST_TAGE = 21

/** Wann ein gemessener Anstieg bekannt ist (palox_anstieg mit drei Werten, 0111): sonst leer, und nie negativ. */
export function paloxAnstieg(roh: number | null, nPaar: number, spanne: number): number | null {
  return roh != null && nPaar >= 5 && spanne >= ANSTIEG_MINDEST_TAGE ? Math.max(roh, 0) : null
}

/**
 * Was gilt (palox_anstieg mit vier Werten, seit 0113): leer wie oben; sonst
 * der gemessene Anstieg, wenn er positiv und sicher ist (die untere Grenze
 * des 95-%-Bereichs über 0), sonst 0 — auch ohne Bereich.
 */
export function paloxAnstiegSicher(roh: number | null, nPaar: number, spanne: number, unten: number | null): number | null {
  if (paloxAnstieg(roh, nPaar, spanne) == null) return null
  return roh! > 0 && unten != null && unten > 0 ? roh : 0
}

export interface Anstieg {
  /** Die Steigung je Woche, wie gemessen (auch negativ); leer ohne Spanne. */
  roh: number | null
  /** Arbeiten in Sorten mit mindestens zwei Arbeiten an der Station. */
  nPaar: number
  /** Die grösste Spanne der Lagerdauern innerhalb einer Sorte. */
  spanne: number
  /** Die untere Grenze des 95-%-Bereichs je Woche; leer ohne Freiheitsgrad. */
  unten: number | null
  /** Was gilt — auf fünf Stellen gerundet, wie die Kennzahl es weitergibt. */
  gilt: number | null
}

/** Der Anstieg je Woche Lagerdauer an einer Station, innerhalb der Sorten — die Punkte einer Station. */
export function anstieg(punkte: Punkt[]): Anstieg {
  const jeSorte = new Map<string, Punkt[]>()
  for (const p of punkte) jeSorte.set(p.sorte, [...(jeSorte.get(p.sorte) ?? []), p])
  let sxy = 0, sxx = 0, nPaar = 0, nSortenPaar = 0, spanne = 0
  const mitten: { p: Punkt, tm: number, ym: number }[] = []
  for (const ps of jeSorte.values()) {
    const sw = ps.reduce((s, p) => s + p.w, 0)
    const tm = ps.reduce((s, p) => s + p.w * p.t, 0) / sw
    const ym = ps.reduce((s, p) => s + p.w * p.y, 0) / sw
    for (const p of ps) { sxy += p.w * (p.t - tm) * (p.y - ym); sxx += p.w * (p.t - tm) ** 2 }
    if (ps.length >= 2) { nPaar += ps.length; nSortenPaar += 1; for (const p of ps) mitten.push({ p, tm, ym }) }
    spanne = Math.max(spanne, Math.max(...ps.map(p => p.t)) - Math.min(...ps.map(p => p.t)))
  }
  const bTag = sxx > 0 ? sxy / sxx : null
  const roh = bTag == null ? null : bTag * 7
  // Der Standardfehler der gemeinsamen Steigung: die Streuung um die Geraden
  // (je Sorte eine eigene Höhe), nach Masse gewichtet; je Sorte geht ein
  // Freiheitsgrad für die Höhe weg, einer für die Steigung.
  const df = nPaar - nSortenPaar - 1
  let unten: number | null = null
  if (bTag != null && df >= 1) {
    let sse = 0, qxx = 0
    for (const { p, tm, ym } of mitten) { sse += p.w * ((p.y - ym) - bTag * (p.t - tm)) ** 2; qxx += p.w * (p.t - tm) ** 2 }
    if (qxx > 0) unten = (bTag - tQuantil95(df) * Math.sqrt(sse / df / qxx)) * 7
  }
  const gilt = paloxAnstiegSicher(roh, nPaar, spanne, unten)
  return { roh, nPaar, spanne, unten, gilt: gilt == null ? null : runden(gilt, 5) }
}

export type Ebene = 'sorte' | 'alle'

export interface Erwartung extends Stationswert {
  sorte: string
  station: Station
  ebene: Ebene
  geliehen: boolean
  /** Das massegewichtete Mittel, wie gemessen. */
  mittel: number | null
  /** Die mittlere Lagerdauer, nach Masse gewichtet. */
  lagerMittel: number | null
  /** Der Anstieg der Station, mit dem zurückgelegt wurde. */
  anstiegJeWoche: number | null
  /** Seit 0132: derselbe Grundausschuss ungekappt (darf unter 0 liegen). */
  grundRoh: number | null
}

/**
 * Je Sorte und Station der Grundausschuss (seit 0132): je Ebene — die Punkte
 * der Sorte, alle Punkte der Station — das Mittel um den Anstieg der Station
 * auf null Tage zurückgelegt, nie unter 0; hat die Sorte Arbeiten, zählen sie
 * n ÷ (n + k), der Rest ist der Wert aller (k = VORWISSEN_MESSUNGEN); sonst
 * gilt der Wert aller (geliehen). Das Band ± t·sd/√(n + k) (ohne Arbeit der
 * Sorte √n aller) mit der Streuung einer Arbeit über alle Sorten der Station.
 * `bisHeute` begrenzt die Punkte des Anstiegs wie palox_station_kennzahl(heute()).
 */
export function erwartung(punkte: Punkt[], sorten: string[], bisHeute: string, k = VORWISSEN_MESSUNGEN): Erwartung[] {
  const alleSorten = [...new Set([...sorten, ...punkte.map(p => p.sorte)])]
  const aus: Erwartung[] = []
  for (const station of STATIONEN) {
    const st = punkte.filter(p => p.station === station)
    if (st.length === 0) continue
    const b = anstieg(st.filter(p => p.messtag <= bisHeute)).gilt
    const ebene = (drin: Punkt[]) => {
      const sw = drin.reduce((s, p) => s + p.w, 0)
      const mittel = drin.reduce((s, p) => s + p.w * p.y, 0) / sw
      const lagerMittel = drin.reduce((s, p) => s + p.w * p.t, 0) / sw
      const roh = mittel - (b ?? 0) * lagerMittel / 7
      return { mittel, lagerMittel, roh, grund: Math.max(roh, 0), n: drin.length, nChargen: new Set(drin.map(p => p.chargeNr)).size }
    }
    const a = ebene(st)
    const yA = st.reduce((s, p) => s + p.y, 0) / st.length
    const sd = st.length >= 2 ? Math.sqrt(st.reduce((s, p) => s + (p.y - yA) ** 2, 0) / (st.length - 1)) : null
    for (const sorte of alleSorten) {
      const drin = st.filter(p => p.sorte === sorte)
      const s = drin.length > 0 ? ebene(drin) : null
      const anteil = s ? (s.n * s.grund + k * a.grund) / (s.n + k) : a.grund
      const grundRoh = s ? (s.n * s.roh + k * a.roh) / (s.n + k) : a.roh
      const nEff = s ? s.n + k : a.n
      const halb = sd == null || nEff < 2 ? 0 : tQuantil95(nEff - 1) * sd / Math.sqrt(nEff)
      const e = s ?? a
      aus.push({ sorte, station, ebene: s ? 'sorte' : 'alle', geliehen: !s, anteil,
                 unten: klemm(anteil - halb, 0, 1), oben: klemm(anteil + halb, 0, 1),
                 nArbeiten: e.n, nChargen: e.nChargen,
                 mittel: e.mittel, lagerMittel: e.lagerMittel, anstiegJeWoche: b, grundRoh })
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
