/**
 * Läuft der Zeitplan wirklich? (Nachtrag zu 0095, 28. September)
 *
 * Eingetragen heisst nicht laufend. Am ersten Tag in der echten Datenbank war
 * der Job `auswertung_wenn_veraltet` eingetragen und eingeschaltet, hatte
 * aber eine Stunde nach dem Einspielen noch kein einziges Mal gerechnet. Die
 * App glaubte dem Eintrag, rechnete beim Öffnen nicht mehr selbst und sagte
 * im Chip „neu bis 11:20" — eine Zeit, zu der nichts geschehen würde. Das ist
 * genau die erfundene Zahl, die die App nie sagen soll.
 *
 * Darum zählt der letzte Lauf, nicht der Eintrag: Nur wenn der Zeitplan
 * innerhalb dreier Takte gelaufen ist und der letzte Lauf nicht
 * fehlgeschlagen ist, überlässt die App ihm das Rechnen. Sonst rechnet sie
 * beim Öffnen selbst, wie vor 0095, und sagt „Zeitplan rechnet nicht".
 *
 * Dieselbe Regel steht im Betriebsabzug (pruefstand/betrieb_abzug.mjs), dort
 * ohne Typen, weil der Abzug kein TypeScript lädt.
 */

export type ZeitplanZustand = 'laeuft' | 'rechnet_nicht' | 'fehlt'

/** Wie viele Takte ohne Lauf, bis der Zeitplan als „rechnet nicht" gilt. */
export const TAKTE_OHNE_LAUF = 3

/** Ein Takt, der nicht „alle N Minuten" heisst, gilt als stündlich — lieber zu nachsichtig als zu streng. */
export const TAKT_UNBEKANNT_MIN = 60

/** „*\/10 * * * *" → 10. Alles andere → null. */
export function taktMinuten(takt: string | null | undefined): number | null {
  const m = /^\*\/(\d+) \* \* \* \*$/.exec(takt ?? '')
  return m ? Number(m[1]) : null
}

export function zeitplanZustand(
  z: { aktiv: boolean; takt: string | null; letzterStart: string | null; letzterStatus: string | null },
  jetzt: Date = new Date(),
): ZeitplanZustand {
  if (!z.aktiv) return 'fehlt'
  if (!z.letzterStart) return 'rechnet_nicht'
  if (z.letzterStatus === 'failed') return 'rechnet_nicht'
  const start = Date.parse(z.letzterStart)
  if (Number.isNaN(start)) return 'rechnet_nicht'
  const takt = taktMinuten(z.takt) ?? TAKT_UNBEKANNT_MIN
  const alterMin = (jetzt.getTime() - start) / 60000
  return alterMin <= TAKTE_OHNE_LAUF * takt ? 'laeuft' : 'rechnet_nicht'
}

/**
 * Sind die Zahlen aktuell? Ja, wenn seit der letzten Rechnung nichts Neues
 * erfasst wurde — egal, wie lange die Rechnung her ist. Der Zeitplan rechnet
 * nur, wenn es Neues gibt; „Stand vor 1 h" heisst dann nicht „alt". Der
 * Betrieb las es am 28. September so, darum sagt der Chip „aktuell".
 */
export function istAktuell(berechnetTs: string | null | undefined, geaendertTs: string | null | undefined): boolean {
  if (!berechnetTs) return false
  const b = Date.parse(berechnetTs)
  if (Number.isNaN(b)) return false
  if (!geaendertTs) return true
  const g = Date.parse(geaendertTs)
  if (Number.isNaN(g)) return false
  return g <= b
}

/** Länger rechnet kein Lauf: die Zeitgrenze des Zeitplans (0095). */
export const RECHNEN_HOECHSTENS_MIN = 15

/**
 * Wird gerade gerechnet? rechnet_seit bleibt stehen, wenn ein Lauf abbricht
 * (am 28. September: „Neu rechnen" um 11:18, nach Schritt 2 abgebrochen).
 * Ein Zeitpunkt, der älter ist als die Zeitgrenze, ist darum kein Rechnen,
 * sondern ein Rest.
 */
export function rechnetGerade(rechnetSeit: string | null | undefined, jetzt: Date = new Date()): boolean {
  if (!rechnetSeit) return false
  const t = Date.parse(rechnetSeit)
  if (Number.isNaN(t)) return false
  const min = (jetzt.getTime() - t) / 60000
  return min >= -1 && min <= RECHNEN_HOECHSTENS_MIN
}
