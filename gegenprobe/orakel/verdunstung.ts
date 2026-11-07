/**
 * Orakel 2 — die Verdunstung.
 *
 * Eine Palette wird beim Eingang gewogen (Zettel) und später noch einmal.
 * Aus dem Verhältnis der Nettos und den Lagertagen folgt die Tagesrate:
 *
 *   rate = 1 − (netto_jetzt / netto_damals)^(1 / lagertage)
 *
 * Schneller als `rateMax` je Tag (einstellung verdunstung_rate_max_pro_tag,
 * Vorgabe 1 %, 0089) ist keine Verdunstung, sondern ein Fehler im Zettel oder
 * an der Waage — nicht verwendbar.
 *
 * Gegenstücke: `v_verdunstung_messung`, `v_koeff_roh_verdunstung`,
 * `v_koeff_verdunstung` (der Schätzer je Sorte steht in varianz.ts).
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
  /** 0135: ein zweites Mal gespeichert (derselbe Zettel, dieselbe Wägung innert Sekunden) — zählt nicht. */
  doppelt?: boolean
}

/** 0135: wie die Paletten einer Charge aussehen — die volle Palette und das Netto je Kiste (Median). */
export interface PalettenBild { kistenVoll: number; nettoJeKiste: number }

/**
 * Je Charge die häufigste Kistenzahl (bei Gleichstand die grössere) und der Median des Nettos je Kiste —
 * aus den Paletten mit mehr als einer Kiste, ohne Palox, mit positivem Netto (`v_charge_palettenbild`).
 */
export function palettenBild(paletten: { chargeNr: number; kisten: number | null; nettoKg: number | null; gebindeart: string | null }[]): Map<number, PalettenBild> {
  const je = new Map<number, { kisten: number; jeKiste: number }[]>()
  for (const p of paletten) {
    if (p.kisten == null || p.kisten <= 1 || p.nettoKg == null || !(p.nettoKg > 0) || /palox/i.test(p.gebindeart ?? '')) continue
    const l = je.get(p.chargeNr) ?? []
    l.push({ kisten: p.kisten, jeKiste: p.nettoKg / p.kisten })
    je.set(p.chargeNr, l)
  }
  const bild = new Map<number, PalettenBild>()
  for (const [c, l] of je) {
    const n = new Map<number, number>()
    for (const x of l) n.set(x.kisten, (n.get(x.kisten) ?? 0) + 1)
    const kistenVoll = [...n.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0][0]
    const s = l.map(x => x.jeKiste).sort((a, b) => a - b)
    const m = s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2
    bild.set(c, { kistenVoll, nettoJeKiste: Math.round(m * 1000) / 1000 })
  }
  return bild
}

/**
 * 0135: Ist die Wägung eine Teilpalette, gewogen mit dem Zettel der ganzen Palette? Dann die volle
 * Kistenzahl, sonst null: mehr als zwei Kisten weniger als die volle Palette, kein Palox, und das
 * Zettelgewicht näher bei einer vollen Palette als bei den gewogenen Kisten.
 */
export function teilpaletteVoll(w: Pick<Waegung, 'kisten' | 'gebindeart' | 'bruttoDamalsKg'>, bild: PalettenBild | undefined, tara: Tara | null): number | null {
  if (!bild || w.kisten == null || w.kisten <= 1 || /palox/i.test(w.gebindeart ?? '') || w.bruttoDamalsKg == null) return null
  if (tara?.kistenKg == null || tara.paletteKg == null || !(bild.nettoJeKiste > 0) || !(w.kisten < bild.kistenVoll - 2)) return null
  const voll = bild.kistenVoll * (tara.kistenKg + bild.nettoJeKiste) + tara.paletteKg
  const teil = w.kisten * (tara.kistenKg + bild.nettoJeKiste) + tara.paletteKg
  return Math.abs(w.bruttoDamalsKg - voll) < Math.abs(w.bruttoDamalsKg - teil) ? bild.kistenVoll : null
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

export function messung(w: Waegung, gebinde: Map<string, Tara>, rateMax = 0.01, bild?: Map<number, PalettenBild>): Messung {
  const tara = w.gebindeart ? gebinde.get(w.gebindeart) ?? null : null
  // 0135: eine Teilpalette mit dem Zettel der ganzen Palette — damals anteilig auf die gewogenen Kisten
  const voll = teilpaletteVoll(w, bild?.get(w.chargeNr), tara)
  const nVoll = voll === null ? null : netto(w.bruttoDamalsKg, voll, tara)
  const damals = voll === null ? netto(w.bruttoDamalsKg, w.kisten, tara) : nVoll === null ? null : zahl(nVoll * (w.kisten as number) / voll, 2, 1e8)
  const jetzt = netto(w.bruttoJetztKg, w.kisten, tara)
  const lagertage = tageZwischen(w.eingangsdatum, w.wiegeTag)
  const rechenbar = damals != null && jetzt != null && damals > 0 && jetzt > 0 && lagertage > 0
  const rate = rechenbar ? zahl(1 - Math.pow((jetzt as number) / (damals as number), 1 / lagertage), 6, 1e4) : null
  const gruende: string[] = []
  if (!w.gemessen) gruende.push('nicht gemessen')
  if (w.doppelt) gruende.push('doppelt gespeichert')
  if (w.sichtbarSchimmel) gruende.push('sichtbar Schimmel')
  if (damals == null || jetzt == null) gruende.push('kein Netto (Kisten oder Tara fehlt)')
  else {
    if (!(damals > 0 && jetzt > 0)) gruende.push('Netto nicht positiv')
    else if (jetzt > damals * 1.01) gruende.push('Palette mehr als 1 % schwerer als beim Eingang')
    else if (jetzt === damals) gruende.push('kein Gramm verloren — Eingangsgewicht wohl kopiert (sortierte Palette ohne echtes Zettelgewicht)')
    else if (rate != null && rate > rateMax) gruende.push(`zu schnell — ${(rate * 100).toFixed(2)} % je Tag ist keine Verdunstung`)
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
