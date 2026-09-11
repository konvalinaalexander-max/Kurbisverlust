/**
 * Die Regeln, nach denen eine Diagramm-Achse ihren Bereich wählt — als reine
 * Funktionen, ohne React, ohne SVG. Prüfbar für sich (test/diagramm.test.ts).
 *
 * Der Anlass: Auf „Ursachen → Palox: Faules im Lager" reichte die x-Achse bis
 * −1000 Lagertage, und alle echten Messungen sassen als ein Strich ganz
 * rechts. Ein einziger Punkt (ein Zettel mit dem Jahr 2029) hatte die Achse an
 * sich gerissen. `Math.min(...alleX)` als Achsenanfang lässt das zu.
 *
 * `achsenBereich()` wählt den Bereich, den ein Diagramm nehmen soll: Es kennt
 * die Einheit (Lagertage sind nie negativ, Prozent liegt zwischen 0 und 100)
 * und lässt sich nicht von einem einzelnen Ausreisser bestimmen.
 *
 * Dieselben Regeln stehen unabhängig noch einmal in
 * gegenprobe/bildschirm/achse.ts — die Gegenprobe prüft die App, ohne aus ihr
 * zu importieren. Wer eine Regel ändert, ändert beide Seiten.
 */

export type Einheit = 'tage' | 'prozent' | 'kg' | 'stueck' | 'frei'

/** Was eine Einheit an ihrer Achse verbietet. */
export function einheitsGrenzen(einheit: Einheit): { von?: number; bis?: number } {
  switch (einheit) {
    case 'tage': return { von: 0 }
    case 'prozent': return { von: 0, bis: 100 }
    case 'kg': return { von: 0 }
    case 'stueck': return { von: 0 }
    default: return {}
  }
}

/**
 * Der äusserste Punkt, der die Spanne der übrigen um mehr als das Doppelte
 * verlängert — oder null, wenn keiner das tut. Bei weniger als drei Punkten
 * gibt es keinen Alleinherrscher (jeder wäre einer).
 */
export function alleinherrscher(werte: number[]): number | null {
  const w = werte.filter(Number.isFinite).slice().sort((a, b) => a - b)
  if (w.length < 3) return null
  const ganze = w[w.length - 1] - w[0]
  if (ganze === 0) return null
  if (w[w.length - 1] - w[1] < ganze / 3) return w[0]
  if (w[w.length - 2] - w[0] < ganze / 3) return w[w.length - 1]
  return null
}

export interface Bereich {
  von: number
  bis: number
  /** Werte, die das Diagramm nicht in die Achse nimmt — als Hinweis nennt es sie. */
  ausgeschlossen: number[]
}

/**
 * Der Bereich, den ein Diagramm nehmen soll:
 *   1. Werte, die die Einheit verbietet (Lagertage < 0, Prozent > 100), fliegen raus.
 *   2. Ein Alleinherrscher fliegt raus — höchstens zweimal, sonst ist es keiner.
 *   3. Der Rest bestimmt von/bis, mit der Untergrenze der Einheit.
 * Feste Vorgaben (`vorgabe.von`/`vorgabe.bis`) gewinnen immer.
 */
export function achsenBereich(werte: number[], einheit: Einheit = 'frei', vorgabe: { von?: number; bis?: number } = {}): Bereich {
  const g = einheitsGrenzen(einheit)
  const ausgeschlossen: number[] = []
  let rest = werte.filter(x => {
    if (!Number.isFinite(x)) { ausgeschlossen.push(x); return false }
    if (g.von != null && x < g.von) { ausgeschlossen.push(x); return false }
    if (g.bis != null && x > g.bis) { ausgeschlossen.push(x); return false }
    return true
  })
  for (let i = 0; i < 2; i++) {
    const h = alleinherrscher(rest)
    if (h == null) break
    rest = rest.filter(x => x !== h)
    ausgeschlossen.push(h)
  }
  const min = rest.length ? Math.min(...rest) : (g.von ?? 0)
  const max = rest.length ? Math.max(...rest) : (g.bis ?? 1)
  // Eine Einheit mit Untergrenze beginnt an ihr (Lagertage und Kilo bei 0) —
  // das gibt dem Blick den Nullpunkt. Ohne Untergrenze folgt die Achse den
  // Daten. Die Obergrenze folgt immer den Daten (ein Prozentwert von 5 % soll
  // die Achse nicht bis 100 aufziehen); die Grenze der Einheit hat oben schon
  // die Ausreisser entfernt. Feste Vorgaben gewinnen.
  const von = vorgabe.von ?? (g.von != null ? g.von : min)
  let bis = vorgabe.bis ?? max
  if (!(bis > von)) bis = von + 1
  return { von, bis, ausgeschlossen }
}
