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
