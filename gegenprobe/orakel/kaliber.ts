/**
 * Orakel — zu klein und zu gross aus der Sortierdatei (seit 0116), und der
 * Hagel auf dem Palox-Anteil.
 *
 * Der Betrieb: „anhand vom Sortier-CSV weisst du, wie Chargen ungefähr sind
 * … durch Verdunstungsrate und mit dem Wissen, wie lange die schon gelagert
 * sind, herausfinden, wie beim Eingangstag die Aufteilung nach Gewicht war."
 *
 * Jeder Kürbis eines Sortierlaufs wird um die Verdunstung seiner Sorte über
 * das Alter der Ware beim Sortieren zurückgerechnet:
 *
 *   g0 = round(g / (1 − r)^Alter)                         (ganze Gramm)
 *
 * Das Alter: aus den Zetteldaten der Arbeit, nach Netto gewichtet (ohne
 * Netto zählt eine Palette 1); ohne Arbeit aus den Paletten der Charge, die
 * am Sortiertag schon da waren, nach Netto (sonst Brutto) gewichtet.
 *
 * Bei einem Alter a ist jeder Kürbis um q = (1 − r)^a geschrumpft; zu klein
 * ist, was unter der ersten Bandgrenze lo liegt (g0 < lo / q), zu gross, was
 * über der letzten hi (g0 > hi / q) — je als Anteil der Masse beim Eingang.
 * Je Charge aus ihren eigenen Läufen, sonst aus denen ihrer Sorte; ohne
 * beides gilt der gemessene Anteil der Sorte.
 *
 *   Hagel: f = 1 − (1 − f) · (1 − h); 100 % Hagel macht f = 1, auch wenn f
 *   selbst unbekannt ist; sonst bleibt ein unbekanntes f unbekannt.
 *
 * Gegenstücke: `v_kaliber_fassung`, `v_kaliber_lauf`, `mv_kaliber_eingang`,
 * `mv_kaliber_quelle`, `kaliber_anteil()`, `hagel_f()`.
 */
import { klemm } from './zahlen.ts'

/** Gegenstück zu `hagel_f`. */
export function hagelF(f: number | null, hagel: number | null): number | null {
  if (hagel == null || hagel <= 0) return f
  if (hagel >= 1) return 1
  if (f == null) return null
  return 1 - (1 - klemm(f, 0, 1)) * (1 - hagel)
}

export interface Lauf { laufId: number; chargeNr: number; sorte: string; alterTage: number; r: number }
export interface Gewicht { laufId: number; gewichtG: number; anzahl: number }

/** Eine Stufe der Verteilung beim Eingang: alle Kürbisse mit g0 Gramm, ihre Masse beim Eingang. */
export interface Stufe { g0: number; masse: number }

/** Die Verteilung beim Eingang aus den gewählten Läufen, nach g0 aufsteigend. */
export function verteilungBeimEingang(laeufe: Lauf[], gewichte: Gewicht[]): Stufe[] {
  const q = new Map(laeufe.filter(l => l.alterTage >= 0).map(l => [l.laufId, Math.pow(1 - l.r, l.alterTage)]))
  const je = new Map<number, number>()
  for (const g of gewichte) {
    const ql = q.get(g.laufId)
    if (ql == null || g.anzahl <= 0 || g.gewichtG <= 0) continue
    const roh = g.gewichtG / ql
    // round(numeric, 0) rundet halb weg von null; alle Gewichte sind positiv
    const g0 = Math.floor(roh + 0.5)
    je.set(g0, (je.get(g0) ?? 0) + roh * g.anzahl / 1000)
  }
  return [...je].sort((a, b) => a[0] - b[0]).map(([g0, masse]) => ({ g0, masse }))
}

/** Der Massenanteil bis und mit g0 — Gegenstück zu `mv_kaliber_eingang.anteil_bis`. */
export function anteilBis(v: Stufe[]): { g0: number; anteilBis: number }[] {
  const summe = v.reduce((a, s) => a + s.masse, 0)
  let bis = 0
  return v.map(s => { bis += s.masse; return { g0: s.g0, anteilBis: bis / summe } })
}

/** Zu klein und zu gross beim Schrumpffaktor q — Gegenstück zu `kaliber_anteil`. Leer ohne Verteilung. */
export function anteilBeimAlter(v: Stufe[], lo: number | null, hi: number | null, q: number):
    { klein: number | null; gross: number | null } {
  const summe = v.reduce((a, s) => a + s.masse, 0)
  if (!(summe > 0) || !(q > 0)) return { klein: null, gross: null }
  return {
    klein: lo == null ? null : v.filter(s => s.g0 < lo / q).reduce((a, s) => a + s.masse, 0) / summe,
    gross: hi == null ? null : v.filter(s => s.g0 > hi / q).reduce((a, s) => a + s.masse, 0) / summe,
  }
}

/** Das Alter beim Sortieren, nach Masse gewichtet: Σ m · (Sortiertag − Eingang) / Σ m. */
export function alterBeimSortieren(sortiertag: number, paletten: { tag: number; masse: number }[]): number | null {
  const da = paletten.filter(p => p.tag <= sortiertag)
  const m = da.reduce((a, p) => a + p.masse, 0)
  return m > 0 ? da.reduce((a, p) => a + p.masse * (sortiertag - p.tag), 0) / m : null
}
