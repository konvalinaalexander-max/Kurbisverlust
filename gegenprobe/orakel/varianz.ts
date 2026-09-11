/**
 * Orakel 3 — der Schätzer je Sorte, mit Schrumpfung zum Gesamtwert.
 *
 * Wenige Chargen einer Sorte sollen nicht an einem Ausreisser hängen. Der
 * Schätzer zieht den Sortenwert zum Gesamtwert, und zwar umso stärker, je
 * unsicherer der Sortenwert ist (empirischer Bayes):
 *
 *   mittel_s   = Σ_c swa_c / Σ_c sw_c                       (massegewichtet)
 *   var_s      = Σ_c (swa_c − mittel_s·sw_c)² / sw² · c/(c−1)   (chargen-robust)
 *   tau²       = max( Σ_s sw_s (mittel_s − mittel_g)² / Σ sw_s − ⌀ var_s , 0 )
 *   b          = tau² / (tau² + var_s)          (0 ohne eigene Streuung, 1 für „gesamt")
 *   mittel     = b·mittel_s + (1−b)·mittel_g
 *   varianz    = b·var_s + (1−b)²·var_g
 *   df         = max( round(b·c_s + (1−b)·c_g) − 1 , 1 )
 *   Band       = mittel ± t95(df)·√varianz
 *
 * Gegenstücke: `v_koeff_kaliber_geschaetzt` (ausschuss, nebenkanal, fax) und
 * `v_koeff_verdunstung_geschaetzt` — beide wortgleich bis auf die Quelle.
 *
 * Bekannte Streitpunkte (docs/STATISTIK_BEFUND.md): Ob ⌀ var_s über die
 * Sorten **ungewichtet** gemittelt werden darf, und ob b bei tau² = 0 auf
 * exakt 0 fallen soll. Das Orakel baut nach, was gilt; wer es anders will,
 * ändert erst die Datenbank und dann hier — nie nur eine Seite.
 */
import { runden, tQuantil95 } from './zahlen.ts'

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
  tau2: number | null
  b: number
  mittel: number | null
  varianz: number
  df: number
  unten: number | null
  oben: number | null
}

function ebene(sorte: string | null, beob: Beobachtung[]): Ebene {
  const jeCharge = new Map<number, { sw: number; swa: number; n: number }>()
  for (const b of beob) {
    const c = jeCharge.get(b.chargeNr) ?? { sw: 0, swa: 0, n: 0 }
    c.sw += b.gewicht; c.swa += b.anteil * b.gewicht; c.n++
    jeCharge.set(b.chargeNr, c)
  }
  let sw = 0, swa = 0, n = 0
  for (const c of jeCharge.values()) { sw += c.sw; swa += c.swa; n += c.n }
  const cChargen = jeCharge.size
  const mittel = sw > 0 ? swa / sw : null
  let varianz: number | null = null
  if (cChargen > 1 && sw > 0 && mittel != null) {
    let s = 0
    for (const c of jeCharge.values()) s += (c.swa - mittel * c.sw) ** 2
    varianz = s / sw ** 2 * cChargen / (cChargen - 1)
  }
  return { sorte, n, cChargen, sw, mittel, varianz }
}

/**
 * Alle Sorten aus `sorten` (das Gitter — auch die ohne Beobachtung) plus die
 * Gesamtebene (sorte = null). Ohne eine einzige Beobachtung gibt es nichts.
 */
export function schrumpfung(beob: Beobachtung[], sorten: string[]): Schaetzung[] {
  const gueltig = beob.filter(b => Number.isFinite(b.anteil) && b.gewicht > 0)
  if (gueltig.length === 0) return []
  const gesamt = ebene(null, gueltig)
  const jeSorte = new Map<string, Ebene>()
  for (const s of new Set(gueltig.map(b => b.sorte))) jeSorte.set(s, ebene(s, gueltig.filter(b => b.sorte === s)))

  // tau²: gewichtete Streuung der Sortenmittel um das Gesamtmittel, minus die
  // (ungewichtet gemittelte) Streuung innerhalb der Sorten — SQL: avg() lässt null aus.
  let zw = 0, swSumme = 0, innen = 0, nInnen = 0
  for (const e of jeSorte.values()) {
    if (e.mittel != null && gesamt.mittel != null) { zw += e.sw * (e.mittel - gesamt.mittel) ** 2; swSumme += e.sw }
    if (e.varianz != null) { innen += e.varianz; nInnen++ }
  }
  const tau2 = Math.max((swSumme > 0 ? zw / swSumme : 0) - (nInnen > 0 ? innen / nInnen : 0), 0)

  const zeile = (sorte: string | null): Schaetzung => {
    const v = sorte == null ? gesamt : jeSorte.get(sorte) ?? null
    const b = sorte == null ? 1
            : (v == null || v.varianz == null || v.mittel == null || tau2 === 0) ? 0
            : tau2 / (tau2 + v.varianz)
    const mittel = gesamt.mittel == null ? null : b * (v?.mittel ?? gesamt.mittel) + (1 - b) * gesamt.mittel
    const varianz = b * (v?.varianz ?? 0) + (1 - b) ** 2 * (gesamt.varianz ?? 0)
    const df = Math.max(Math.trunc(runden(b * (v?.cChargen ?? 0) + (1 - b) * gesamt.cChargen, 0)) - 1, 1)
    const t = tQuantil95(df)
    const band = mittel == null ? [null, null] : varianz === 0 ? [mittel, mittel]
               : [mittel - t * Math.sqrt(varianz), mittel + t * Math.sqrt(varianz)]
    return { sorte, n: v?.n ?? 0, cChargen: v?.cChargen ?? 0, mittelRoh: v?.mittel ?? null, varianzRoh: v?.varianz ?? null,
             mittelGesamt: gesamt.mittel, tau2, b, mittel, varianz, df, unten: band[0], oben: band[1] }
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
