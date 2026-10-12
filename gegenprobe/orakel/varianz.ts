/**
 * Orakel 3 — der Schätzer je Sorte, seit 0111 schlicht.
 *
 * Bis 0110 zog ein empirischer Bayes den Sortenwert zum Gesamtwert, umso
 * stärker, je weniger Chargen die Sorte hatte — eine Sorte mit 34 Wägungen
 * aus zwei Chargen stand beim Gesamtwert, und niemand konnte es nachrechnen.
 * Der Betrieb (12. Oktober): „die Mathematik simpel halten". Seither:
 *
 *   mittel_s  = Σ w·a / Σ w                            (massegewichtet, je Sorte)
 *   var_s     = Σ w·(a − mittel_s)² / Σ w / (n − 1)    (Unsicherheit des Mittels)
 *   b         = 1, wenn die Sorte mindestens drei Messungen hat, sonst 0
 *   mittel    = b = 1 ? mittel_s : mittel_gesamt     (geliehen, und es heisst so)
 *   varianz   = b = 1 ? var_s    : var_gesamt
 *   df        = n der geltenden Ebene − 1, mindestens 1
 *   Band      = mittel ± t95(df)·√varianz
 *
 * tau² gibt es nicht mehr (leer). Gegenstücke: `v_koeff_kaliber_geschaetzt`
 * (ausschuss, nebenkanal, fax) und `v_koeff_verdunstung_geschaetzt` —
 * beide wortgleich bis auf die Quelle.
 */
import { tQuantil95 } from './zahlen.ts'

/** Ab so vielen eigenen Messungen gilt der Wert der Sorte (anteil_mindest_messungen). */
export const MINDEST_MESSUNGEN = 3

export interface Beobachtung { sorte: string; chargeNr: number; anteil: number; gewicht: number }

export interface Ebene {
  sorte: string | null
  n: number
  cChargen: number
  sw: number
  mittel: number | null
  varianz: number | null
}

export interface Schaetzung {
  sorte: string | null
  n: number
  cChargen: number
  mittelRoh: number | null
  varianzRoh: number | null
  mittelGesamt: number | null
  tau2: null
  b: number
  mittel: number | null
  varianz: number
  df: number
  unten: number | null
  oben: number | null
}

function ebene(sorte: string | null, beob: Beobachtung[]): Ebene {
  const n = beob.length
  const sw = beob.reduce((s, b) => s + b.gewicht, 0)
  const mittel = sw > 0 ? beob.reduce((s, b) => s + b.anteil * b.gewicht, 0) / sw : null
  const varianz = n > 1 && mittel != null
    ? beob.reduce((s, b) => s + b.gewicht * (b.anteil - mittel) ** 2, 0) / sw / (n - 1)
    : null
  return { sorte, n, cChargen: new Set(beob.map(b => b.chargeNr)).size, sw, mittel, varianz }
}

/**
 * Alle Sorten aus `sorten` (das Gitter — auch die ohne Beobachtung) plus die
 * Gesamtebene (sorte = null). Ohne eine einzige Beobachtung gibt es nichts.
 */
export function schaetzung(beob: Beobachtung[], sorten: string[], mindest = MINDEST_MESSUNGEN): Schaetzung[] {
  const gueltig = beob.filter(b => Number.isFinite(b.anteil) && b.gewicht > 0)
  if (gueltig.length === 0) return []
  const gesamt = ebene(null, gueltig)
  const zeile = (sorte: string | null): Schaetzung => {
    const eigene = sorte == null ? gueltig : gueltig.filter(b => b.sorte === sorte)
    const v = eigene.length > 0 ? ebene(sorte, eigene) : null
    const b = sorte == null || (v != null && v.n >= mindest) ? 1 : 0
    const mittel = b === 1 ? (v?.mittel ?? gesamt.mittel) : gesamt.mittel
    const varianz = b === 1 ? (v?.varianz ?? 0) : (gesamt.varianz ?? 0)
    const df = Math.max((b === 1 ? (v?.n ?? 0) : gesamt.n) - 1, 1)
    const t = tQuantil95(df)
    const band = mittel == null ? [null, null] : varianz === 0 ? [mittel, mittel]
               : [mittel - t * Math.sqrt(varianz), mittel + t * Math.sqrt(varianz)]
    return { sorte, n: v?.n ?? 0, cChargen: v?.cChargen ?? 0, mittelRoh: v?.mittel ?? null, varianzRoh: v?.varianz ?? null,
             mittelGesamt: gesamt.mittel, tau2: null, b, mittel, varianz, df, unten: band[0], oben: band[1] }
  }
  return [...sorten.map(s => zeile(s)), zeile(null)]
}

/**
 * Was die Kaskade aus einer Schätzung macht (v_koeff_verdunstung): nie
 * negativ, das Band unten und oben bei null abgeschnitten.
 */
export function bandNichtNegativ(s: Schaetzung): { mittel: number | null; unten: number | null; oben: number | null } {
  if (s.mittel == null) return { mittel: null, unten: null, oben: null }
  const m = Math.max(s.mittel, 0)
  if (s.varianz === 0) return { mittel: m, unten: m, oben: m }
  return { mittel: m, unten: Math.max(s.unten as number, 0), oben: Math.max(s.oben as number, 0) }
}
