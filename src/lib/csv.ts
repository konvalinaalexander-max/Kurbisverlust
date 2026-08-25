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
