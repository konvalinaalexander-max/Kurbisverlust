/**
 * Orakel 1 — die Masse: vom Zettel zur Charge zur Kohorte.
 *
 * Was hier steht, ist der Grundsatz „leer ist nicht null" (0064) und die
 * Regel „kein Kilo aus einer Lücke" (0066), unabhängig nachgebaut:
 *
 *   netto = brutto − kisten × kistentara − palettentara
 *   … und unbekannt, sobald eines der drei unbekannt ist.
 *
 * Gegenstücke in der Datenbank: `v_palette`, `v_charge_rueckgrat`,
 * `v_charge_kohorte`, `v_kohorte_anteil`.
 */
import { zahl } from './zahlen.ts'

export interface Tara { kistenKg: number | null; paletteKg: number | null }

export interface Palette {
  id: number
  chargeNr: number
  eingangsdatum: string          // ISO-Tag vom Zettel
  bruttoKg: number | null
  kisten: number | null
  gebindeart: string | null
}

/** Das Netto einer Palette — oder null, wenn eine Angabe fehlt. */
export function netto(brutto: number | null | undefined, kisten: number | null | undefined,
                      tara: Tara | null | undefined, mitPalette = true): number | null {
  if (brutto == null || kisten == null || tara == null) return null
  if (tara.kistenKg == null) return null
  if (mitPalette && tara.paletteKg == null) return null
  return brutto - kisten * tara.kistenKg - (mitPalette ? (tara.paletteKg as number) : 0)
}

export function nettoJePalette(p: Palette, gebinde: Map<string, Tara>): number | null {
  return netto(p.bruttoKg, p.kisten, p.gebindeart ? gebinde.get(p.gebindeart) ?? null : null)
}

export interface Rueckgrat {
  chargeNr: number
  nPaletten: number
  nMitNetto: number
  /** Auf alle Paletten hochgerechnet: Σ netto / n_mit_netto × n. null ohne ein einziges Netto. */
  eingangKg: number | null
  /** Nur die Paletten mit bekannter Tara. */
  eingangGemessenKg: number | null
}

/**
 * Der Eingang je Charge, so wie `v_charge_rueckgrat` ihn rechnet: Paletten
 * ohne Netto bekommen das **Mittel** der Paletten mit Netto — das ist eine
 * bewusste Hochrechnung, keine Lücke. Wer sie nicht will, liest
 * `eingangGemessenKg`.
 */
export function rueckgrat(paletten: Palette[], gebinde: Map<string, Tara>): Map<number, Rueckgrat> {
  const je = new Map<number, Rueckgrat>()
  for (const p of paletten) {
    const r = je.get(p.chargeNr) ?? { chargeNr: p.chargeNr, nPaletten: 0, nMitNetto: 0, eingangKg: null, eingangGemessenKg: null }
    r.nPaletten++
    const n = nettoJePalette(p, gebinde)
    if (n != null) { r.nMitNetto++; r.eingangGemessenKg = (r.eingangGemessenKg ?? 0) + n }
    je.set(p.chargeNr, r)
  }
  for (const r of je.values()) {
    r.eingangKg = r.nMitNetto > 0 ? (r.eingangGemessenKg as number) / r.nMitNetto * r.nPaletten : null
  }
  return je
}

export interface Kohorte {
  chargeNr: number
  eingangsdatum: string
  nPaletten: number
  /** n × Netto-Mittel des Tages (oder der Charge, wenn der Tag kein Netto hat), auf 2 Stellen. */
  eingangKg: number | null
  /** Anteil des Tages am Eingang der Charge, auf 6 Stellen — Gegenstück zu `v_kohorte_anteil`. */
  anteil: number | null
}

/**
 * Die Kohorten einer Charge: je Eingangstag die Masse und ihr Anteil.
 * Es gibt kein Zuerst-rein-zuerst-raus — der Anteil verteilt jede Lieferung
 * und jeden Bestand auf die Eingangstage (0060).
 */
export function kohorten(paletten: Palette[], gebinde: Map<string, Tara>): Kohorte[] {
  const ergebnis: Kohorte[] = []
  const jeCharge = new Map<number, Palette[]>()
  for (const p of paletten) (jeCharge.get(p.chargeNr) ?? jeCharge.set(p.chargeNr, []).get(p.chargeNr)!).push(p)
  for (const [chargeNr, liste] of jeCharge) {
    const nettos = liste.map(p => nettoJePalette(p, gebinde))
    const bekannt = nettos.filter((n): n is number => n != null)
    const chargeMittel = bekannt.length ? bekannt.reduce((a, b) => a + b, 0) / bekannt.length : null
    const tage = new Map<string, { n: number; summe: number; mit: number }>()
    liste.forEach((p, i) => {
      const t = tage.get(p.eingangsdatum) ?? { n: 0, summe: 0, mit: 0 }
      t.n++
      if (nettos[i] != null) { t.summe += nettos[i] as number; t.mit++ }
      tage.set(p.eingangsdatum, t)
    })
    const zeilen: Kohorte[] = []
    for (const [tag, t] of tage) {
      const mittel = t.mit > 0 ? t.summe / t.mit : chargeMittel
      zeilen.push({ chargeNr, eingangsdatum: tag, nPaletten: t.n,
                    eingangKg: mittel == null ? null : zahl(t.n * mittel, 2, 1e10), anteil: null })
    }
    const gesamt = zeilen.reduce((s, z) => s + (z.eingangKg ?? 0), 0)
    for (const z of zeilen) {
      if (z.eingangKg != null && z.eingangKg > 0 && gesamt > 0) z.anteil = zahl(z.eingangKg / gesamt, 6, 1e4)
    }
    ergebnis.push(...zeilen.sort((a, b) => a.eingangsdatum.localeCompare(b.eingangsdatum)))
  }
  return ergebnis
}

/**
 * Die Regel, die nach dem Sortieren gilt (Drehbuch 01): Die Kisten einer
 * sortierten Charge stehen auf **neuen** Paletten mit bekannter Kistenzahl
 * und Gebindeart — aber ohne Eingangsgewicht und ohne Eingangsdatum, weil
 * die Ware mehrerer Eingangstage gemischt ist. Für so eine Palette gibt es:
 *   · ein Netto, wenn sie gewogen wird (brutto − Tara)   → ja
 *   · ein Netto damals                                     → nein
 *   · Lagertage                                            → nein (nur die Spanne der Charge)
 * Eine Verdunstungsmessung an ihr ist deshalb **nicht verwendbar**; ihre
 * Masse zählt aber im Bestand. Das Orakel kennt diesen Zustand ausdrücklich.
 */
export interface SortiertePalette {
  chargeNr: number
  kisten: number
  gebindeart: string
  sortierdatum: string
  kaliberIdx: number | null
}
export function sortierteMasse(p: SortiertePalette, kgJeKiste: number | null): number | null {
  return kgJeKiste == null ? null : p.kisten * kgJeKiste
}
