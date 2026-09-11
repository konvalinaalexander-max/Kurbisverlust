/**
 * Orakel 2 — die Verdunstung.
 *
 * Eine Palette wird beim Eingang gewogen (Zettel) und später noch einmal.
 * Aus dem Verhältnis der Nettos und den Lagertagen folgt die Tagesrate:
 *
 *   rate = 1 − (netto_jetzt / netto_damals)^(1 / lagertage)
 *
 * Gegenstücke: `v_verdunstung_messung`, `v_koeff_roh_verdunstung`,
 * `v_koeff_verdunstung` (die Schrumpfung steht in varianz.ts).
 */
import { netto, type Tara } from './masse.ts'
import { tageZwischen, zahl } from './zahlen.ts'

export interface Waegung {
  id: number
  chargeNr: number
  sorte: string
  eingangsdatum: string
  /** Der Betriebstag der Wägung — `betriebstag(wiege_ts)`, nicht der UTC-Tag. */
  wiegeTag: string
  bruttoDamalsKg: number | null
  bruttoJetztKg: number | null
  kisten: number | null
  gebindeart: string | null
  sichtbarSchimmel: boolean
  gemessen: boolean
  /** Die Arbeit, an der gewogen wurde, ist abgebrochen. */
  abgebrochen: boolean
}

export interface Messung {
  id: number
  chargeNr: number
  sorte: string
  nettoDamalsKg: number | null
  nettoJetztKg: number | null
  lagertage: number
  ratePreTag: number | null
  verwendbar: boolean
  /** Warum nicht verwendbar — leer, wenn verwendbar. Für den Bericht, nicht für die Rechnung. */
  gruende: string[]
}

export function messung(w: Waegung, gebinde: Map<string, Tara>): Messung {
  const tara = w.gebindeart ? gebinde.get(w.gebindeart) ?? null : null
  const damals = netto(w.bruttoDamalsKg, w.kisten, tara)
  const jetzt = netto(w.bruttoJetztKg, w.kisten, tara)
  const lagertage = tageZwischen(w.eingangsdatum, w.wiegeTag)
  const rechenbar = damals != null && jetzt != null && damals > 0 && jetzt > 0 && lagertage > 0
  const rate = rechenbar ? zahl(1 - Math.pow((jetzt as number) / (damals as number), 1 / lagertage), 6, 1e4) : null
  const gruende: string[] = []
  if (!w.gemessen) gruende.push('nicht gemessen')
  if (w.sichtbarSchimmel) gruende.push('sichtbar Schimmel')
  if (damals == null || jetzt == null) gruende.push('kein Netto (Kisten oder Tara fehlt)')
  else {
    if (!(damals > 0 && jetzt > 0)) gruende.push('Netto nicht positiv')
    if (jetzt > damals * 1.01) gruende.push('Palette mehr als 1 % schwerer als beim Eingang')
  }
  if (lagertage <= 0) gruende.push(lagertage < 0 ? 'Wiegetag vor dem Eingang (Zettel falsch?)' : 'am Eingangstag gewogen')
  if (w.abgebrochen) gruende.push('Arbeit abgebrochen')
  return { id: w.id, chargeNr: w.chargeNr, sorte: w.sorte, nettoDamalsKg: damals, nettoJetztKg: jetzt,
           lagertage, ratePreTag: rate, verwendbar: gruende.length === 0, gruende }
}

/** Die Rohwerte, die in die Mittelung gehen: Rate und Gewicht (= netto jetzt). */
export function rohwerte(messungen: Messung[]): { sorte: string; chargeNr: number; anteil: number; gewicht: number }[] {
  return messungen
    .filter(m => m.verwendbar && m.ratePreTag != null && m.nettoJetztKg != null && m.nettoJetztKg > 0)
    .map(m => ({ sorte: m.sorte, chargeNr: m.chargeNr, anteil: m.ratePreTag as number, gewicht: m.nettoJetztKg as number }))
}

/** Die Rate im Modell ist nie negativ und nie über 5 % je Tag (Kaskade: `LEAST(GREATEST(r,0),0.05)`). */
export function rateFuerKaskade(mittel: number | null): number {
  return Math.min(Math.max(mittel ?? 0, 0), 0.05)
}
