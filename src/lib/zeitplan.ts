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
