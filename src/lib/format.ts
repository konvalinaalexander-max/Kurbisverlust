const ORT = 'de-CH'

export function kg(wert: number | null | undefined, stellen = 0): string {
  if (wert === null || wert === undefined || Number.isNaN(wert)) return '—'
  return `${wert.toLocaleString(ORT, { minimumFractionDigits: stellen, maximumFractionDigits: stellen })} kg`
}

export function tonnen(wert: number | null | undefined): string {
  if (wert === null || wert === undefined) return '—'
  return Math.abs(wert) >= 1000
    ? `${(wert / 1000).toLocaleString(ORT, { maximumFractionDigits: 1 })} t`
    : kg(wert)
}

export function zahl(wert: number | null | undefined, stellen = 0): string {
  if (wert === null || wert === undefined || Number.isNaN(wert)) return '—'
  return wert.toLocaleString(ORT, { minimumFractionDigits: stellen, maximumFractionDigits: stellen })
}

export function prozent(anteil: number | null | undefined, stellen = 1): string {
  if (anteil === null || anteil === undefined || Number.isNaN(anteil)) return '—'
  return `${(anteil * 100).toLocaleString(ORT, { minimumFractionDigits: stellen, maximumFractionDigits: stellen })} %`
}

/**
 * Der heutige Kalendertag, wie ihn der Arbeiter in der Halle sieht.
 *
 * `new Date().toISOString().slice(0, 10)` wäre der Tag **in UTC**, nicht der
 * Tag des Arbeiters. Zwischen Mitternacht und zwei Uhr Ortszeit (Schweiz ist
 * UTC+1, im Sommer UTC+2) liegt der UTC-Tag noch auf gestern — die Maske böte
 * dann **gestern** als Vorgabe an, und wer sie übernimmt, datiert die Palette
 * um einen Tag zurück. Aus dem Tag wird eine Lagerdauer, aus der Lagerdauer
 * eine Verdunstungsrate; bei der kürzesten Lagerung der Demosaison (acht Tage)
 * verschiebt ein Tag sie um mehr als ein Achtel.
 *
 * Deshalb: lokale Mitternacht, und die Zahlen von Hand zusammensetzen.
 * `toISOString()` darf hier nicht vorkommen, denn es rechnet immer nach UTC um.
 */
export function heute(): string {
  return tagVon(new Date())
}

/**
 * Der Kalendertag eines Zeitpunkts in der Zone des Betrachters.
 *
 * Eigene Funktion, damit sie prüfbar ist: `heute()` hängt an der Uhr und lässt
 * sich nicht festhalten, `tagVon()` schon. Der Test in `test/format.test.ts`
 * setzt `TZ=Europe/Zurich` und gibt einen Zeitpunkt vor, an dem der Schweizer
 * und der UTC-Kalendertag auseinanderfallen.
 */
export function tagVon(d: Date): string {
  const zwei = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${zwei(d.getMonth() + 1)}-${zwei(d.getDate())}`
}

export function datum(wert: string | Date | null | undefined): string {
  if (!wert) return '—'
  const d = typeof wert === 'string' ? new Date(wert) : wert
  return d.toLocaleDateString(ORT, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export function zeitpunkt(wert: string | Date | null | undefined): string {
  if (!wert) return '—'
  const d = typeof wert === 'string' ? new Date(wert) : wert
  return d.toLocaleString(ORT, {
    day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}

/** Für <input type="datetime-local"> — der Browser will lokale Zeit ohne Zone. */
export function lokalFuerInput(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
}

export const WEG_NAME: Record<string, string> = {
  maschine: 'Weg 1 — Maschine',
  hand: 'Weg 2 — Hand',
}

export const STATION_NAME: Record<string, string> = {
  sortieren: 'Sortieren',
  waschen: 'Waschen',
  waschen_sortieren: 'Waschen + Sortieren',
}
