/**
 * Die Achse — reine Regeln, ohne Browser, ohne React.
 *
 * Der Anlass: Auf dem Betrieb zeigte „Palox: Faules im Lager" eine x-Achse
 * bis −1000 Lagertage, und alle Messungen sassen als ein Strich ganz rechts.
 * Ein einziger Punkt (ein Zettel mit dem Jahr 2029) hatte die Achse an sich
 * gerissen, und das Diagramm hat es zugelassen: `Math.min(...alleX)` ist der
 * ganze Achsenanfang (src/components/Diagramm.tsx, `xMinAlle`).
 *
 * Hier stehen die Regeln, die eine Achse erfüllen muss — prüfbar an Zahlen,
 * bevor irgendetwas gezeichnet wird, und prüfbar am gezeichneten SVG (der
 * Bildschirm-Prüfstand liest die Striche zurück). Dazu `achsenBereich()`,
 * der Bereich, den ein Diagramm nehmen **sollte**: Er kennt die Einheit und
 * lässt sich nicht von einem einzelnen Punkt herumreissen.
 */

export type Einheit = 'tage' | 'prozent' | 'kg' | 'stueck' | 'datum' | 'frei'

export interface Achse { von: number; bis: number; ticks: number[] }

export interface Befund { regel: string; text: string }

export interface Optionen {
  einheit?: Einheit
  /** Wie ein Strich beschriftet wird — zwei Striche mit gleicher Beschriftung sind ein Fehler. */
  format?: (x: number) => string
  /** Anteil der Achse, den die Daten mindestens füllen müssen (0 … 1). */
  mindestFuellung?: number
}

/** Was eine Einheit an ihrer Achse verbietet. */
export function einheitsGrenzen(einheit: Einheit): { von?: number; bis?: number } {
  switch (einheit) {
    case 'tage':    return { von: 0 }
    case 'prozent': return { von: 0, bis: 100 }
    case 'kg':      return { von: 0 }
    case 'stueck':  return { von: 0 }
    default:        return {}
  }
}

/**
 * A1–A6: die Regeln, an denen jede Achse gemessen wird.
 *  A1 endlich und geordnet         von < bis, alles Zahlen
 *  A2 Daten im Bild                 jeder Punkt liegt zwischen von und bis
 *  A3 nicht leer                    die Daten füllen mindestens `mindestFuellung` der Achse (Vorgabe 0.3)
 *  A4 Einheit                       Lagertage nie negativ, Prozent 0 … 100, Kilo nie negativ
 *  A5 kein Alleinherrscher          nimmt man den äussersten Punkt weg, schrumpft die Datenspanne nicht auf unter ein Drittel
 *  A6 Striche                       mindestens zwei, gleichmässig, im Bereich, jede Beschriftung nur einmal
 */
export function pruefeAchse(achse: Achse, punkte: number[], o: Optionen = {}): Befund[] {
  const b: Befund[] = []
  const einheit = o.einheit ?? 'frei'
  const format = o.format ?? String
  if (![achse.von, achse.bis, ...achse.ticks].every(Number.isFinite)) b.push({ regel: 'A1', text: 'Achse enthält NaN oder ∞' })
  if (!(achse.von < achse.bis)) b.push({ regel: 'A1', text: `Achse ohne Weite: von ${achse.von} bis ${achse.bis}` })
  const drin = punkte.filter(Number.isFinite)
  if (drin.length !== punkte.length) b.push({ regel: 'A1', text: `${punkte.length - drin.length} Punkt(e) sind NaN oder ∞` })
  const luft = (achse.bis - achse.von) * 1e-9
  const draussen = drin.filter(x => x < achse.von - luft || x > achse.bis + luft)
  if (draussen.length) b.push({ regel: 'A2', text: `${draussen.length} Punkt(e) ausserhalb der Achse, z. B. ${draussen[0]}` })
  if (drin.length >= 2 && achse.bis > achse.von) {
    const spanne = Math.max(...drin) - Math.min(...drin)
    const fuellung = spanne / (achse.bis - achse.von)
    if (fuellung < (o.mindestFuellung ?? 0.3)) b.push({ regel: 'A3', text: `Daten füllen nur ${Math.round(fuellung * 100)} % der Achse` })
  }
  const g = einheitsGrenzen(einheit)
  if (g.von != null && achse.von < g.von) b.push({ regel: 'A4', text: `${einheit}: Achse beginnt bei ${achse.von}, unter ${g.von}` })
  if (g.bis != null && achse.bis > g.bis * 1.05) b.push({ regel: 'A4', text: `${einheit}: Achse endet bei ${achse.bis}, über ${g.bis}` })
  const herrscher = alleinherrscher(drin)
  if (herrscher != null) b.push({ regel: 'A5', text: `ein einzelner Punkt (${herrscher}) bestimmt die Achse` })
  if (achse.ticks.length < 2) b.push({ regel: 'A6', text: `nur ${achse.ticks.length} Strich(e)` })
  else {
    const schritte = achse.ticks.slice(1).map((t, i) => t - achse.ticks[i])
    const s0 = schritte[0]
    if (!schritte.every(s => Math.abs(s - s0) <= Math.abs(s0) * 1e-6)) b.push({ regel: 'A6', text: 'Striche nicht gleichmässig' })
    if (achse.ticks.some(t => t < achse.von - luft || t > achse.bis + luft)) b.push({ regel: 'A6', text: 'Strich ausserhalb der Achse' })
    const texte = achse.ticks.map(format)
    const doppelt = texte.filter((t, i) => texte.indexOf(t) !== i)
    if (doppelt.length) b.push({ regel: 'A6', text: `Beschriftung mehrfach: „${doppelt[0]}"` })
  }
  return b
}

/**
 * A5 als Zahl: Der äusserste Punkt, der die Spanne der übrigen um mehr als das
 * Doppelte verlängert — oder null, wenn keiner das tut. Bei 2 Punkten gibt es
 * keinen Alleinherrscher (jeder wäre einer).
 */
export function alleinherrscher(werte: number[]): number | null {
  const w = [...werte].filter(Number.isFinite).sort((a, b) => a - b)
  if (w.length < 3) return null
  const ohneErsten = w[w.length - 1] - w[1], ohneLetzten = w[w.length - 2] - w[0], ganze = w[w.length - 1] - w[0]
  if (ganze === 0) return null
  if (ohneErsten < ganze / 3) return w[0]
  if (ohneLetzten < ganze / 3) return w[w.length - 1]
  return null
}

export interface Bereich {
  von: number
  bis: number
  /** Punkte, die das Diagramm **nicht** in die Achse nehmen soll — es zeigt sie als Hinweis („1 Messung ausserhalb: −1001 Tage"). */
  ausgeschlossen: number[]
  /** Warum — für den Hinweis am Diagramm. */
  gruende: string[]
}

/**
 * Der Bereich, den ein Diagramm nehmen sollte:
 *   1. Punkte, die die Einheit verbietet, fliegen raus (Lagertage < 0, Prozent > 100).
 *   2. Ein Alleinherrscher fliegt raus — höchstens zweimal, sonst ist es keiner.
 *   3. Der Rest bestimmt von/bis, mit Untergrenze der Einheit (Lagertage ab 0).
 * Ein Diagramm, das diesen Bereich nimmt, besteht A1–A5 für jede Punktmenge,
 * die mindestens drei brauchbare Werte hat.
 */
export function achsenBereich(werte: number[], einheit: Einheit = 'frei', vorgabe: { von?: number; bis?: number } = {}): Bereich {
  const g = einheitsGrenzen(einheit)
  const gruende: string[] = []
  const ausgeschlossen: number[] = []
  let rest = werte.filter(x => {
    if (!Number.isFinite(x)) { ausgeschlossen.push(x); return false }
    if (g.von != null && x < g.von) { ausgeschlossen.push(x); return false }
    if (g.bis != null && x > g.bis) { ausgeschlossen.push(x); return false }
    return true
  })
  if (ausgeschlossen.length) gruende.push(`${ausgeschlossen.length} Wert(e) ausserhalb dessen, was ${einheit} sein kann`)
  for (let i = 0; i < 2; i++) {
    const h = alleinherrscher(rest)
    if (h == null) break
    rest = rest.filter(x => x !== h)
    ausgeschlossen.push(h)
    gruende.push(`ein einzelner Wert (${h}) hätte die Achse bestimmt`)
  }
  const von = vorgabe.von ?? (rest.length ? Math.min(g.von ?? -Infinity, Math.min(...rest)) === g.von ? g.von : Math.min(...rest) : g.von ?? 0)
  const bis = vorgabe.bis ?? (rest.length ? Math.max(...rest) : (g.bis ?? 1))
  return { von: rest.length && g.von != null ? Math.max(Math.min(...rest, g.von), g.von) === g.von && Math.min(...rest) >= g.von ? (vorgabe.von ?? g.von) : von : von,
           bis: bis > von ? bis : von + 1, ausgeschlossen, gruende }
}

/**
 * Die Striche, die ein Diagramm setzt — bewusst dieselbe Regel wie in
 * Diagramm.tsx (`schoen`), aber unabhängig geschrieben: 1-2-5-Schritte.
 * Wer beide nebeneinander hält, sieht, ob die App abweicht.
 */
export function striche(von: number, bis: number, n = 5): number[] {
  if (!(bis > von)) return [von]
  const roh = (bis - von) / n
  const p = 10 ** Math.floor(Math.log10(roh))
  const f = roh / p
  const schritt = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p
  const start = Math.floor(von / schritt) * schritt
  const t: number[] = []
  for (let x = start; x <= bis + schritt * 1e-3; x += schritt) t.push(Number(x.toFixed(10)))
  return t
}
