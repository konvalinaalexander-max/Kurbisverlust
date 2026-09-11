/**
 * Das kleine Rechenzeug, das jedes Orakel braucht — und **nichts** davon
 * kommt aus `src/` oder aus der Datenbank. Das ist Absicht: Ein Orakel, das
 * die Hilfsfunktionen des Prüflings benutzt, erbt dessen Fehler.
 *
 * Wo die Datenbank eine Regel hat, steht hier dieselbe Regel noch einmal,
 * unabhängig geschrieben, mit dem Namen der Funktion, die sie in der
 * Datenbank trägt. Weichen die beiden ab, ist das ein Befund — für eine der
 * beiden Seiten.
 */

/** Zweiseitiges 95-%-Quantil der t-Verteilung — Gegenstück zu `t_quantil_95`. */
export function tQuantil95(df: number | null | undefined): number {
  if (df == null || !Number.isFinite(df) || df < 1) return 12.706
  if (df >= 30) return 1.960
  const tafel = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306,
                 2.262, 2.228, 2.201, 2.179, 2.160, 2.145, 2.131, 2.120,
                 2.110, 2.101, 2.093, 2.086, 2.080, 2.074, 2.069, 2.064,
                 2.060, 2.056, 2.052, 2.048, 2.045]
  return tafel[Math.trunc(df) - 1]
}

/** Ein Anteil ist plausibel zwischen 0 und 0.5 — Gegenstück zu `anteil_plausibel`. */
export function anteilPlausibel(a: number | null | undefined): boolean {
  return a != null && Number.isFinite(a) && a >= 0 && a <= 0.5
}

/**
 * Runden wie PostgreSQL `round(numeric, n)`: kaufmännisch, halb weg von null.
 * JavaScript rundet `Math.round(-2.5)` zu −2, PostgreSQL zu −3.
 */
export function runden(x: number, stellen = 2): number {
  const p = 10 ** stellen
  const v = Math.abs(x) * p
  // Ein Hauch Luft gegen 2.675 → 2.67499999…; deutlich unter jeder Stelle, die hier zählt.
  const g = Math.floor(v + 0.5 + 1e-9) / p
  return x < 0 ? -g : g
}

/**
 * Gegenstück zu `zahl(p_wert, p_stellen, p_grenze)` (0058, verschärft 0068):
 * gerundet, und was über der Grenze liegt, wird zu null — der **gerundete**
 * Wert wird gegen die Grenze gehalten.
 */
export function zahl(x: number | null | undefined, stellen = 2, grenze = 1e11): number | null {
  if (x == null || !Number.isFinite(x)) return null
  const g = runden(x, stellen)
  return Math.abs(g) < grenze ? g : null
}

export function klemm(x: number, unten: number, oben: number): number {
  return Math.min(Math.max(x, unten), oben)
}

/**
 * Zwei Zahlen gelten als gleich, wenn sie sich um weniger als `abs` **oder**
 * relativ um weniger als `rel` unterscheiden. null ist nur null gleich.
 */
export function nahe(a: number | null | undefined, b: number | null | undefined, rel = 1e-9, abs = 1e-9): boolean {
  if (a == null || b == null) return a == null && b == null
  if (!Number.isFinite(a) || !Number.isFinite(b)) return false
  const d = Math.abs(a - b)
  return d <= abs || d <= rel * Math.max(Math.abs(a), Math.abs(b))
}

/** Σ(wert·gewicht) / Σ gewicht — null ohne Gewicht. */
export function gewichtetesMittel(paare: { wert: number; gewicht: number }[]): number | null {
  let sw = 0, swa = 0
  for (const p of paare) { sw += p.gewicht; swa += p.wert * p.gewicht }
  return sw > 0 ? swa / sw : null
}

/** Kalendertage zwischen zwei ISO-Tagen (b − a), ohne Zeitzonen-Zauber. */
export function tageZwischen(a: string, b: string): number {
  const [ay, am, ad] = a.split('-').map(Number), [by, bm, bd] = b.split('-').map(Number)
  return Math.round((Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86_400_000)
}

/** Ein ISO-Tag plus n Tage. */
export function tagPlus(tag: string, n: number): string {
  const [y, m, d] = tag.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10)
}

/** Gruppieren ohne Bibliothek. */
export function gruppiere<T, K>(liste: T[], schluessel: (t: T) => K): Map<K, T[]> {
  const m = new Map<K, T[]>()
  for (const t of liste) {
    const k = schluessel(t)
    const g = m.get(k)
    if (g) g.push(t); else m.set(k, [t])
  }
  return m
}
