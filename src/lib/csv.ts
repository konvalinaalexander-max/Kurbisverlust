/**
 * Reinigung der Sortier-CSV (Spec §4).
 *
 * Die Datei enthält eine Zahl je Zeile — das Gewicht eines Kürbisses in Gramm,
 * ohne Kopfzeile, ohne Charge, ohne Datum. Die Maschine liefert 2-g-Auflösung.
 *
 * Die Reinigung ist bewusst eine eigene Schicht: die Rohdatei wird unverändert
 * im Storage abgelegt, und `ReinigungsParameter` macht jede Regel abschaltbar.
 * Was sie entfernt hat, zeigt die App als Trichter an — keine stillen Abzüge.
 *
 * Warum hier im Browser und nicht in SQL: die Dubletten-Regel braucht die
 * Zeilenreihenfolge. Sobald sie angewandt ist, ist die Reihenfolge bedeutungslos
 * und es genügt, das Histogramm an die Datenbank zu schicken.
 */

export interface ReinigungsParameter {
  /** Ab hier liegt ein 16-Bit-Unterlauf vor (Leerband-Rauschen). */
  overflow_ab: number
  /** Darunter ist es kein Kürbis, sondern ein Bruchstück. */
  min_gramm: number
  /** Aufeinanderfolgende gleiche Werte zu einem zusammenfassen. */
  dubletten_zusammenfassen: boolean
}

export const REINIGUNG_STANDARD: ReinigungsParameter = {
  overflow_ab: 60000,
  min_gramm: 100,
  dubletten_zusammenfassen: true,
}

export interface Reinigungsergebnis {
  n_roh: number
  n_overflow: number
  n_klein: number
  n_dubletten: number
  n_gueltig: number
  /** Zeilen, die keine Zahl waren — sollten 0 sein, sonst stimmt die Datei nicht. */
  n_unlesbar: number
  /** [gewicht_g, anzahl] — verlustfrei, weil die Reihenfolge nicht mehr zählt. */
  histogramm: [number, number][]
  parameter: ReinigungsParameter
}

/** Liest die Rohwerte. Leerzeilen zählen nicht, alles andere schon. */
export function werteLesen(text: string): { werte: number[]; unlesbar: number } {
  const werte: number[] = []
  let unlesbar = 0
  for (const zeile of text.split(/\r?\n/)) {
    const roh = zeile.trim()
    if (roh === '') continue
    // Dezimalkomma tolerieren, falls die Maschine je anders exportiert
    const zahl = Number(roh.replace(',', '.'))
    if (Number.isFinite(zahl)) werte.push(Math.round(zahl))
    else unlesbar++
  }
  return { werte, unlesbar }
}

/**
 * Wendet die drei Regeln in der Reihenfolge aus §4 an und zählt mit.
 *
 * Der Trichter ist per Konstruktion widerspruchsfrei:
 * n_roh − n_overflow − n_klein − n_dubletten = n_gueltig. (Das Beispiel in der
 * Spezifikation — 11 370 → −5 → −11 → −3 204 → 8 161 — geht um 11 nicht auf;
 * vermutlich waren die 11 Werte unter 100 g selbst Teil von Dubletten-Serien
 * und damit doppelt gezählt. Hier wird jede Zeile genau einer Stufe zugeschlagen.)
 */
export function reinigen(
  werte: number[],
  parameter: ReinigungsParameter = REINIGUNG_STANDARD,
): Omit<Reinigungsergebnis, 'n_unlesbar'> {
  const n_roh = werte.length
  let n_overflow = 0
  let n_klein = 0
  let n_dubletten = 0

  const behalten: number[] = []
  for (const wert of werte) {
    // Regel 1: Werte ab 60000 sind ein 16-Bit-Unterlauf. Als negative Zahl
    // gelesen ergeben sie −2 … −130 g — das Rauschen des leeren Bands.
    if (wert >= parameter.overflow_ab) { n_overflow++; continue }
    // Regel 2: unter 100 g liegt kein Kürbis auf dem Band.
    if (wert < parameter.min_gramm) { n_klein++; continue }
    // Regel 3: Die Maschine löst gelegentlich zweimal für denselben Kürbis aus.
    // Belegt durch die Nachbar-Gleichheit von 12–28 % (Zufall wäre < 0.2 %),
    // ohne Größenkorrelation und nur als Paare oder Dreier.
    if (parameter.dubletten_zusammenfassen && behalten.length > 0
        && behalten[behalten.length - 1] === wert) {
      n_dubletten++
      continue
    }
    behalten.push(wert)
  }

  const zaehler = new Map<number, number>()
  for (const wert of behalten) zaehler.set(wert, (zaehler.get(wert) ?? 0) + 1)
  const histogramm = [...zaehler.entries()].sort((a, b) => a[0] - b[0]) as [number, number][]

  return { n_roh, n_overflow, n_klein, n_dubletten, n_gueltig: behalten.length,
           histogramm, parameter }
}

export function csvReinigen(
  text: string,
  parameter: ReinigungsParameter = REINIGUNG_STANDARD,
): Reinigungsergebnis {
  const { werte, unlesbar } = werteLesen(text)
  return { ...reinigen(werte, parameter), n_unlesbar: unlesbar }
}

/** „11 370 gelesen → −5 Overflow → −11 unter 100 g → −3 204 Dubletten → 8 161 Kürbisse" */
export function trichter(e: Reinigungsergebnis): string {
  const z = (n: number) => n.toLocaleString('de-CH')
  const teile = [`${z(e.n_roh)} gelesen`]
  if (e.n_overflow) teile.push(`−${z(e.n_overflow)} Overflow`)
  if (e.n_klein) teile.push(`−${z(e.n_klein)} unter ${e.parameter.min_gramm} g`)
  if (e.n_dubletten) teile.push(`−${z(e.n_dubletten)} Dubletten`)
  if (e.n_unlesbar) teile.push(`${z(e.n_unlesbar)} unlesbar`)
  teile.push(`${z(e.n_gueltig)} Kürbisse`)
  return teile.join(' → ')
}

/** Gesamtmasse des gereinigten Laufs in kg — zur Plausibilitätsanzeige. */
export function masseKg(histogramm: [number, number][]): number {
  return histogramm.reduce((s, [g, n]) => s + g * n, 0) / 1000
}

/** SHA-256 der Rohdatei, damit dieselbe Datei nicht zweimal hochgeladen wird. */
export async function pruefsumme(datei: ArrayBuffer): Promise<string> {
  const hash = await crypto.subtle.digest('SHA-256', datei)
  return [...new Uint8Array(hash)].map(b => b.toString(16).padStart(2, '0')).join('')
}

/* ---------------------------------------------------------------------- *
 * Die Sammeldatei: was ist daran neu?
 * ---------------------------------------------------------------------- */

/**
 * Das Delta zweier Histogramme — was in `voll` steht und in `bekannt` noch
 * nicht.
 *
 * Gebraucht für die **Sammeldatei**: Die Maschine hängt bei jedem weiteren
 * Sortieren derselben Charge unten an dieselbe Datei an. Der zweite Upload
 * enthält damit alle Kürbisse des ersten noch einmal. Wer beide als eigene
 * Läufe speichert, zählt die alten doppelt — still, ohne Fehlermeldung, und
 * die Charge hat am Ende mehr sortiert, als sie je gewogen hat.
 *
 * Warum eine schlichte Subtraktion genügt: Die Reinigung ist **präfixstabil**.
 * `reinigen` entscheidet je Zeile nur anhand der Zeile selbst und des zuletzt
 * behaltenen Werts; die ersten N Eingaben werden in `P + S` also genauso
 * behandelt wie in `P` allein. Damit ist das Histogramm der ganzen Datei
 * punktweise nie kleiner als das des Präfixes. Gemessen an 700 Zeilen:
 * `reinigen(P+S).n_gueltig − reinigen(P).n_gueltig = reinigen(S).n_gueltig`,
 * und keine Stufe wird negativ (test/csv.test.ts).
 *
 * Genau daraus wird die Probe: **Wird eine Stufe negativ, ist die Datei keine
 * reine Erweiterung.** Dann wurde mittendrin geändert, gelöscht oder eine
 * fremde Datei erwischt — und nichts darf übernommen werden, bevor ein Mensch
 * hingesehen hat.
 *
 * Dieselbe Regel steht in SQL in `csv_sammel_speichern` (0082); dort ist sie
 * massgeblich, weil nur die Datenbank sicher weiss, was schon gespeichert ist.
 * Hier läuft sie für die Vorschau, damit der Betriebsleiter vor dem Drücken
 * sieht, was dazukommt.
 */
export interface DeltaErgebnis {
  /** Was neu ist — dieselbe Form wie ein Histogramm. */
  delta: [number, number][]
  /** Summe der neuen Kürbisse. */
  n_neu: number
  /** Summe der schon bekannten. */
  n_bekannt: number
  /**
   * Stufen, die negativ wurden: [gewicht_g, fehlende_anzahl]. Leer, solange
   * die Datei eine echte Erweiterung ist. Nicht leer heisst: nicht übernehmen.
   */
  negativ: [number, number][]
}

export function histogrammAbziehen(
  voll: readonly [number, number][],
  bekannt: readonly [number, number][],
): DeltaErgebnis {
  const rest = new Map<number, number>(bekannt.map(([g, n]) => [g, n]))
  const delta: [number, number][] = []
  const negativ: [number, number][] = []
  let n_neu = 0

  for (const [g, n] of voll) {
    const schon = rest.get(g) ?? 0
    const d = n - schon
    rest.delete(g)
    if (d > 0) { delta.push([g, d]); n_neu += d }
    else if (d < 0) negativ.push([g, -d])
  }
  // Was in `bekannt` steht und in `voll` gar nicht mehr vorkommt, fehlt
  // vollständig — derselbe Befund, nur deutlicher.
  for (const [g, n] of rest) if (n > 0) negativ.push([g, n])

  delta.sort((a, b) => a[0] - b[0])
  negativ.sort((a, b) => a[0] - b[0])
  return {
    delta, n_neu, negativ,
    n_bekannt: bekannt.reduce((s, [, n]) => s + n, 0),
  }
}

/** „8 161 in der Datei → 5 940 schon bekannt → 2 221 neu" */
export function deltaTrichter(e: DeltaErgebnis): string {
  const z = (n: number) => n.toLocaleString('de-CH')
  return `${z(e.n_bekannt + e.n_neu)} in der Datei → ${z(e.n_bekannt)} schon bekannt → ${z(e.n_neu)} neu`
}
