/**
 * Orakel 5 — das Verderbsmodell.
 *
 *   F(t) = 1 − exp(−λ · t^k)         (Weibull-Verteilungsfunktion)
 *
 * linearisiert:  ln(−ln(1 − F)) = ln λ + k · ln t   →  gewichtete Gerade
 * in (x, y) = (ln t, ln(−ln(1−f))) mit Gewicht w = Masse hinter dem Punkt.
 *
 * Dazu der Sockel a0: Punkte aus der Verarbeitung (Palox) tragen eine
 * Grundaussortierung, die nichts mit Lagerdauer zu tun hat:
 *   f_beob = a0 + (1 − a0) · F(t)   →   F = (f − a0) / (1 − a0)
 * a0 wird auf einem Gitter 0 … 0.1 (Schritt 0.0025) gesucht; gewählt wird der
 * **kleinste** a0, dessen SSE höchstens 1 % über dem Minimum liegt — und nur,
 * wenn a0 = 0 nachweislich schlechter ist (Schwelle 1 + t²/df).
 *
 * Smearing (Duan): weil die Gerade im log-log-Raum liegt, korrigiert
 * S = Σ w·exp(Residuum) / Σ w den Rücktransport;  ln λ_korr = ln λ + ln max(S, 0.01).
 *
 * Streuung chargen-robust (Sandwich über Chargen-Summen der Residuen):
 *   var_achse = Σ_c ga_c² / sw² · c/(c−1),   var_k = Σ_c gk_c² / sxx² · c/(c−1)
 *   kov       = Σ_c ga_c·gk_c / (sw·sxx) · c/(c−1)
 * mit ga_c = Σ w·e, gk_c = Σ w·(x − x̄)·e je Charge.
 *
 * Gegenstücke: `v_schimmel_modell_rechnen` → `mv_schimmel_modell`,
 * `schimmelanteil(t, szenario)`, Treppe `v_schimmel_kurve`.
 */
import { klemm, tQuantil95, zahl } from './zahlen.ts'

export interface Punkt {
  chargeNr: number
  /** Lagertage — muss > 0 sein, sonst gehört der Punkt nicht in den Fit. */
  t: number
  /** Gemessener Anteil faul, 0 < f < 1. */
  f: number
  /** Masse hinter dem Punkt (basis_jetzt_kg). */
  w: number
  /** Punkt aus der Verarbeitung (mit Sockel) statt aus der Lagerkontrolle. */
  mitSockel: boolean
}

export interface Modell {
  n: number
  cChargen: number
  tMin: number | null
  tMax: number | null
  k: number | null
  lnLambda: number | null
  lambda: number | null
  xMittel: number | null
  sxx: number | null
  smearing: number | null
  lnLambdaKorrigiert: number | null
  sigma2: number | null
  varAchse: number | null
  varK: number | null
  kovAchseK: number | null
  tFaktor: number
  brauchbar: boolean
  sockel: number
  sockelUnten: number
  sockelOben: number
  sockelNachweis: number | null
  sockelSchwelle: number | null
  sockelVar: number | null
}

const GITTER = Array.from({ length: 41 }, (_, i) => i * 0.0025)

interface Gerade { n: number; c: number; sw: number; swx: number; swy: number; swxx: number; swxy: number; k: number | null; lnLambda: number | null }

function gerade(p: { chargeNr: number; x: number; y: number; w: number }[]): Gerade {
  let sw = 0, swx = 0, swy = 0, swxx = 0, swxy = 0
  for (const q of p) { sw += q.w; swx += q.w * q.x; swy += q.w * q.y; swxx += q.w * q.x * q.x; swxy += q.w * q.x * q.y }
  const nenner = sw * swxx - swx * swx
  const k = nenner !== 0 ? (sw * swxy - swx * swy) / nenner : null
  const lnLambda = k != null ? (swy - k * swx) / sw : null
  return { n: p.length, c: new Set(p.map(q => q.chargeNr)).size, sw, swx, swy, swxx, swxy, k, lnLambda }
}

const fsVon = (p: Punkt, a0: number) => p.mitSockel ? (p.f - a0) / (1 - a0) : p.f
const yVon = (fs: number) => Math.log(-Math.log(1 - fs))
const F = (eta: number) => 1 - Math.exp(-Math.exp(klemm(eta, -40, 3)))

/**
 * Das Modell aus den Punkten. Der Aufrufer hat schon gefiltert: plausibel,
 * 0 < f < 1, t > 0, Quelle verarbeitung oder lager (nicht gemischt, nicht Fax).
 */
export function anpassen(punkte: Punkt[]): Modell {
  const c = new Set(punkte.map(p => p.chargeNr)).size
  const leer: Modell = { n: 0, cChargen: 0, tMin: null, tMax: null, k: null, lnLambda: null, lambda: null, xMittel: null,
    sxx: null, smearing: null, lnLambdaKorrigiert: null, sigma2: null, varAchse: null, varK: null, kovAchseK: null,
    tFaktor: tQuantil95(c - 1), brauchbar: false, sockel: 0, sockelUnten: 0, sockelOben: 0,
    sockelNachweis: null, sockelSchwelle: null, sockelVar: null }
  if (punkte.length === 0) return leer

  // 1. Je Gitterpunkt a0: Gerade, Smearing, SSE über **alle** Punkte (auch die, die aus dem Fit fallen).
  const guete: { a0: number; n: number; c: number; k: number; lnLambda: number; s: number; sse: number }[] = []
  for (const a0 of GITTER) {
    const kand = punkte.map(p => ({ p, x: Math.log(p.t), fs: fsVon(p, a0) }))
    const imFit = kand.filter(q => q.fs > 0 && q.fs < 1).map(q => ({ chargeNr: q.p.chargeNr, x: q.x, y: yVon(q.fs), w: q.p.w }))
    const g = gerade(imFit)
    if (g.k == null || g.lnLambda == null) continue
    let sNenner = 0, sZaehler = 0
    for (const q of imFit) { sZaehler += q.w * Math.exp(q.y - (g.lnLambda + g.k * q.x)); sNenner += q.w }
    const s = sNenner > 0 ? sZaehler / sNenner : 0
    if (!(g.k > 0 && g.n >= 3)) continue
    let sse = 0
    for (const q of kand) {
      const sockel = q.p.mitSockel ? a0 : 0
      const eta = g.lnLambda + Math.log(Math.max(s, 0.01)) + g.k * q.x
      sse += q.p.w * (q.p.f - (sockel + (1 - sockel) * F(eta))) ** 2
    }
    guete.push({ a0, n: g.n, c: g.c, k: g.k, lnLambda: g.lnLambda, s, sse })
  }
  const dfS = Math.max(c - 3, 1)
  const faktor = 1 + tQuantil95(dfS) ** 2 / dfS
  const minSse = guete.length ? Math.min(...guete.map(g => g.sse)) : null
  const sse0 = guete.find(g => g.a0 === 0)?.sse ?? null

  // 2. Wahl: kleinster a0 nahe am Minimum, aber nur wenn a0 = 0 nachweislich schlechter ist.
  let gewaehlt = 0, sseGewaehlt = sse0
  if (minSse != null && sse0 != null && sse0 > minSse * faktor) {
    const kandidat = guete.filter(g => g.sse <= minSse * 1.01).sort((a, b) => a.a0 - b.a0)[0]
    if (kandidat) { gewaehlt = kandidat.a0; sseGewaehlt = kandidat.sse }
  }
  const imBereich = sseGewaehlt == null ? [] : guete.filter(g => g.sse <= sseGewaehlt * faktor).map(g => g.a0)
  const sockelUnten = imBereich.length ? Math.min(...imBereich) : gewaehlt
  const sockelOben = imBereich.length ? Math.max(...imBereich) : gewaehlt

  // 3. Der endgültige Fit beim gewählten a0.
  const fitPunkte = punkte.map(p => ({ p, x: Math.log(p.t), fs: fsVon(p, gewaehlt) }))
    .filter(q => q.fs > 0 && q.fs < 1).map(q => ({ chargeNr: q.p.chargeNr, x: q.x, y: yVon(q.fs), w: q.p.w, t: q.p.t }))
  const g = gerade(fitPunkte)
  const n = g.n, cF = g.c
  const tMin = fitPunkte.length ? Math.min(...fitPunkte.map(q => q.t)) : null
  const tMax = fitPunkte.length ? Math.max(...fitPunkte.map(q => q.t)) : null
  const xMittel = g.sw > 0 ? g.swx / g.sw : null
  if (g.k == null || g.lnLambda == null || xMittel == null) {
    return { ...leer, n, cChargen: cF, tMin, tMax, xMittel, tFaktor: tQuantil95(cF - 1),
             sockel: gewaehlt, sockelUnten, sockelOben,
             sockelNachweis: sse0 != null && minSse ? zahl(sse0 / minSse, 3, 1e7) : null,
             sockelSchwelle: zahl(faktor, 3, 1e7) }
  }
  const k = g.k, lnLambda = g.lnLambda
  let sxx = 0, sse = 0, sZ = 0
  const jeCharge = new Map<number, { ga: number; gk: number }>()
  for (const q of fitPunkte) {
    const e = q.y - (lnLambda + k * q.x)
    sxx += q.w * (q.x - xMittel) ** 2
    sse += q.w * e * e
    sZ += q.w * Math.exp(e)
    const ch = jeCharge.get(q.chargeNr) ?? { ga: 0, gk: 0 }
    ch.ga += q.w * e; ch.gk += q.w * (q.x - xMittel) * e
    jeCharge.set(q.chargeNr, ch)
  }
  const smearing = g.sw > 0 ? sZ / g.sw : null
  let saa = 0, skk = 0, sak = 0
  for (const ch of jeCharge.values()) { saa += ch.ga ** 2; skk += ch.gk ** 2; sak += ch.ga * ch.gk }
  const robust = cF > 1 ? cF / (cF - 1) : null
  const tFaktor = tQuantil95(cF - 1)
  const brauchbar = n >= 3 && cF >= 3 && k > 0 && tMax != null && tMin != null && tMax > tMin * 1.5
  return {
    n, cChargen: cF, tMin, tMax, k, lnLambda, lambda: Math.exp(lnLambda), xMittel, sxx, smearing,
    lnLambdaKorrigiert: smearing == null ? null : lnLambda + Math.log(Math.max(smearing, 0.01)),
    sigma2: n > 2 && g.sw > 0 ? sse / (n - 2) * n / g.sw : null,
    varAchse: robust == null ? null : saa / g.sw ** 2 * robust,
    varK: robust == null || sxx === 0 ? null : skk / sxx ** 2 * robust,
    kovAchseK: robust == null || sxx === 0 ? null : sak / (g.sw * sxx) * robust,
    tFaktor, brauchbar,
    sockel: gewaehlt, sockelUnten, sockelOben,
    sockelNachweis: sse0 != null && minSse ? zahl(sse0 / minSse, 3, 1e7) : null,
    sockelSchwelle: zahl(faktor, 3, 1e7),
    sockelVar: tFaktor ? ((sockelOben - sockelUnten) / 2 / tFaktor) ** 2 : null,
  }
}

export type Szenario = 'mittel' | 'unten' | 'oben'

/** Der Anteil faul bei t Lagertagen nach dem Modell — Gegenstück zu `schimmelanteil(t, szenario)`, Modellzweig. */
export function anteilNachModell(m: Modell, t: number, szenario: Szenario = 'mittel'): number | null {
  if (!m.brauchbar || m.varAchse == null || m.k == null || m.lnLambdaKorrigiert == null || m.xMittel == null) return null
  const x = Math.log(Math.max(t, 1))
  const u = x - m.xMittel
  const vorzeichen = szenario === 'unten' ? -1 : szenario === 'oben' ? 1 : 0
  const streuung = Math.sqrt(Math.max(m.varAchse + u * u * (m.varK ?? 0) + 2 * u * (m.kovAchseK ?? 0), 0))
  const eta = m.lnLambdaKorrigiert + m.k * x + vorzeichen * m.tFaktor * streuung
  return klemm(F(eta), 0, 1)
}

/** Die Treppe als Rückfall, wenn kein Modell trägt: je Altersklasse der massegewichtete Anteil, monoton gemacht. */
export const KLASSEN: [number, number][] = [[0, 14], [15, 30], [31, 60], [61, 90], [91, 120], [121, 180], [181, 100000]]

export function treppe(punkte: { t: number; schimmelKg: number; basisKg: number }[]): { von: number; bis: number; n: number; anteilMono: number | null }[] {
  let bisher: number | null = null
  return KLASSEN.map(([von, bis]) => {
    const drin = punkte.filter(p => p.t >= von && p.t <= bis)
    const basis = drin.reduce((s, p) => s + p.basisKg, 0)
    const anteil = drin.length && basis > 0 ? drin.reduce((s, p) => s + p.schimmelKg, 0) / basis : null
    if (anteil != null) bisher = bisher == null ? anteil : Math.max(bisher, anteil)
    return { von, bis, n: drin.length, anteilMono: bisher == null ? null : klemm(bisher, 0, 1) }
  })
}

/** Der Anteil, den die Kaskade nimmt: Modell, sonst Treppe, sonst 0. */
export function anteilFuerKaskade(m: Modell, tr: ReturnType<typeof treppe>, t: number): number {
  const modell = anteilNachModell(m, t)
  if (modell != null) return modell
  const stufe = [...tr].reverse().find(s => s.n > 0 && s.von <= t)
  return klemm(stufe?.anteilMono ?? 0, 0, 1)
}
