/**
 * Orakel 7 — die Unsicherheitsbänder.
 *
 * Ein Strom der Kaskade hängt an mehreren geschätzten Koeffizienten (der
 * Verdunstungsrate r, dem Schimmelanteil f über η, dem Sockel a0, den
 * Ausschussanteilen). Jeder hat eine Varianz und sie sind untereinander
 * abhängig. Die Streuung einer Grösse g(θ), die aus ihnen folgt, ist nach der
 * Delta-Methode:
 *
 *   Var(g) ≈ Σ_i Σ_j (∂g/∂θ_i)(∂g/∂θ_j) · Cov(θ_i, θ_j)
 *
 * — die volle quadratische Form mit **allen** Kovarianzen, nicht nur der
 * Diagonale. Genau daran hängen zwei Befunde aus Runde M:
 *
 *   FPF-001: `v_verlust_je_gruppe` nimmt beim Zusammenfassen mehrerer Ströme
 *            `LEAST`/`min(df)` über die Komponenten — das Band wird dadurch
 *            **6.3× zu weit**.
 *   AUF-001: Die Delta-Methode unterschätzt die Streuung des Schimmels um
 *            **3.9×**, weil η nichtlinear in f eingeht.
 *
 * Dieses Orakel rechnet die Delta-Methode unabhängig, mit voller Kovarianz,
 * und ist der Massstab, an dem Phase 2 misst, ob ein Band hält (überdeckt es
 * die Wahrheit in ~95 % der Fälle?) oder lügt (zu weit / zu eng).
 *
 * Es importiert nichts aus `src/` und ruft keine Datenbankfunktion.
 */
import { klemm } from './zahlen.ts'

export type Kovarianz = number[][]

/**
 * Die Delta-Methode: Streuung von g aus den Ableitungen und der vollen
 * Kovarianzmatrix. `ableitungen[i]` ist ∂g/∂θ_i, `kov[i][j]` ist Cov(θ_i, θ_j).
 * Wirft, wenn die Matrix nicht quadratisch zu den Ableitungen passt.
 */
export function deltaVarianz(ableitungen: number[], kov: Kovarianz): number {
  const n = ableitungen.length
  if (kov.length !== n || kov.some(z => z.length !== n)) throw new Error('Kovarianzmatrix passt nicht zu den Ableitungen')
  let v = 0
  for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) v += ableitungen[i] * ableitungen[j] * kov[i][j]
  return Math.max(v, 0)
}

/**
 * Das Band um g: mittel ± t·√Var. `t` ist das t-Quantil zu den Freiheitsgraden
 * (das kleinste df der eingehenden Koeffizienten, nicht ihr Minimum als
 * Verwechslung mit `LEAST` über die Werte — das ist der Kern von FPF-001).
 */
export function band(mittel: number, ableitungen: number[], kov: Kovarianz, t: number): { unten: number; oben: number; sigma: number } {
  const sigma = Math.sqrt(deltaVarianz(ableitungen, kov))
  return { unten: mittel - t * sigma, oben: mittel + t * sigma, sigma }
}

/**
 * Streuung von f = 1 − exp(−exp(η)) aus der Streuung von η — der nichtlineare
 * Schritt, den AUF-001 betrifft. df/dη = (1−f)·exp(η). Wer nur var(η)
 * durchreicht, ohne diese Ableitung, unterschätzt σ(f).
 */
export function schimmelSigma(eta: number, sigmaEta: number): number {
  const f = 1 - Math.exp(-Math.exp(klemm(eta, -40, 3)))
  const dfdeta = (1 - f) * Math.exp(klemm(eta, -40, 3))
  return Math.abs(dfdeta) * sigmaEta
}

/** Überdeckung: liegt die Wahrheit im Band? Für die Coverage-Messung in Phase 2. */
export function deckt(unten: number, oben: number, wahrheit: number): boolean {
  return wahrheit >= unten - 1e-12 && wahrheit <= oben + 1e-12
}
