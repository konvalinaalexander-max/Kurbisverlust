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

/* ---------- Kalenderstriche (Runde AQ) ------------------------------------- */

const MONATE = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez']
const TAG_MS = 86400000

export interface Kalenderstrich { x: number; text: string }

/**
 * Die Striche einer Zeitachse, wie man einen Kalender liest — nicht „schöne
 * Zahlen" von Tagen. Der Betrieb, 12. Oktober: „mach es professioneller";
 * die Achse des Verlaufs stand bei 27.05 · 04.09 · 13.12 · 23.03, je hundert
 * Tage, mitten in den Monaten.
 *
 *   - über zweieinhalb Monate: Monatsanfänge („Jul", „Aug", … im Januar mit
 *     Jahr, „Jan 27"), bei langen Spannen jeder zweite, dritte oder sechste;
 *   - kürzer (hineingezoomt): Montage, je eine oder zwei Wochen („7.9."),
 *     ganz kurz einzelne Tage.
 *
 * x ist in Tagen; ursprungMs ist der Zeitpunkt von x = 0 (UTC) — 0 für
 * „Tage seit 1970", Date.UTC(saison, 6, 1) für „Tage seit dem 1. Juli".
 * Es kommen nur Striche im Bereich [x0, x1] zurück.
 */
export function kalenderStriche(x0: number, x1: number, ursprungMs = 0, hoechstens = 8): Kalenderstrich[] {
  const spanne = x1 - x0
  if (!(spanne > 0) || !Number.isFinite(spanne)) return []
  const zuX = (ms: number) => (ms - ursprungMs) / TAG_MS
  const start = new Date(ursprungMs + x0 * TAG_MS)
  const striche: Kalenderstrich[] = []
  if (spanne >= 75) {
    // Monatsnamen sind kurz: bis zu vier mehr als Datumsstriche haben Platz.
    const monate = spanne / 30.44
    const schritt = [1, 2, 3, 6, 12].find(s => monate / s <= hoechstens + 4) ?? 12
    let j = start.getUTCFullYear(), m = start.getUTCMonth()
    if (zuX(Date.UTC(j, m, 1)) < x0) m += 1
    while (((m % 12) + 12) % 12 % schritt !== 0) m += 1
    for (let ms = Date.UTC(j, m, 1); zuX(ms) <= x1; m += schritt, ms = Date.UTC(j, m, 1)) {
      const d = new Date(ms)
      const mi = d.getUTCMonth()
      striche.push({ x: zuX(ms), text: mi === 0 ? `${MONATE[0]} ${String(d.getUTCFullYear()).slice(2)}` : MONATE[mi] })
    }
    return striche
  }
  const schritt = [1, 2, 7, 14].find(s => spanne / s <= hoechstens) ?? 28
  let ms = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate())
  if (zuX(ms) < x0) ms += TAG_MS
  if (schritt >= 7) while (new Date(ms).getUTCDay() !== 1) ms += TAG_MS
  for (; zuX(ms) <= x1; ms += schritt * TAG_MS) {
    const d = new Date(ms)
    striche.push({ x: zuX(ms), text: `${d.getUTCDate()}.${d.getUTCMonth() + 1}.` })
  }
  return striche
}
