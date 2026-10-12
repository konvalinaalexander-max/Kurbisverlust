/**
 * Der Palox-Hinweis, dreimal je Person (Runde AO).
 *
 * Der Betrieb: „dass jede Person, die sich einloggt, noch dreimal die Infos
 * kriegt, dass sie das eintragen müssen während der Arbeit, wenn sie Palox
 * leeren". Ein geleerter Palox ohne die zwei Ablesungen ist Faules, das
 * niemand mehr kennt (Auffälligkeit „Palox geleert", Charge 1650) — und die
 * Person, die ihn leert, ist oft nicht die, die den Plan gelesen hat.
 *
 * Gezählt wird je Person in verschiedenen Arbeiten: In einer Arbeit steht
 * der Hinweis, bis sie ihn mit „Verstanden" wegtippt; nach drei Arbeiten
 * kommt er nicht wieder. Gemerkt wird das auf dem Gerät, je Profil — wer auf
 * einem anderen Handy arbeitet, sieht ihn dort noch einmal. Ein Hinweis zu
 * viel kostet einen Tipp, einer zu wenig das Faule einer Arbeit.
 */
export const PALOX_HINWEIS_MAL = 3

export const paloxHinweisSchluessel = (profilId: string) => `palox_hinweis_${profilId}`

/** Was auf dem Gerät steht, als Liste von Arbeiten — Unlesbares zählt als nichts gesehen. */
export function gesehenLesen(roh: string | null): number[] {
  try {
    const v: unknown = JSON.parse(roh ?? '[]')
    return Array.isArray(v) ? v.filter((x): x is number => Number.isInteger(x)) : []
  } catch { return [] }
}

/** Steht der Hinweis in dieser Arbeit? */
export function paloxHinweisZeigen(gesehen: number[], auftragId: number): boolean {
  return !gesehen.includes(auftragId) && gesehen.length < PALOX_HINWEIS_MAL
}

/** Nach „Verstanden": diese Arbeit dazu, jede nur einmal. */
export function paloxHinweisGesehen(gesehen: number[], auftragId: number): number[] {
  return gesehen.includes(auftragId) ? gesehen : [...gesehen, auftragId]
}
