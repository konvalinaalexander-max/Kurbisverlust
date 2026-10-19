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

/** Steht ein Hinweis in dieser Arbeit? — in höchstens `mal` verschiedenen Arbeiten je Person. */
export function hinweisZeigen(gesehen: number[], auftragId: number, mal: number): boolean {
  return !gesehen.includes(auftragId) && gesehen.length < mal
}

/** Steht der Palox-Hinweis in dieser Arbeit? */
export function paloxHinweisZeigen(gesehen: number[], auftragId: number): boolean {
  return hinweisZeigen(gesehen, auftragId, PALOX_HINWEIS_MAL)
}

/** Nach „Verstanden": diese Arbeit dazu, jede nur einmal. */
export function paloxHinweisGesehen(gesehen: number[], auftragId: number): number[] {
  return gesehen.includes(auftragId) ? gesehen : [...gesehen, auftragId]
}

/**
 * Der Sortierdatum-Hinweis, fünfmal je Person (Runde AP).
 *
 * Der Betrieb: „wenn ein Waschvorgang startet … pro Benutzer die ersten drei
 * Mal oder die ersten fünf Mal vielleicht sogar, bis das wirklich im Kopf
 * drin ist: beim Sortieren musst du das Sortierdatum nicht mehr aufschreiben."
 * Seit Runde AO wird beim Waschen jede Kaliber-Palette gewogen; das Datum auf
 * dem Zettel braucht es dafür nicht mehr. Er steht beim Waschen und beim
 * Sortieren — dort, wo das Datum bisher geschrieben und gelesen wurde —,
 * gezählt wie der Palox-Hinweis: je Person in verschiedenen Arbeiten.
 */
export const SORTIERDATUM_HINWEIS_MAL = 5

export const sortierdatumHinweisSchluessel = (profilId: string) => `sortierdatum_hinweis_${profilId}`

/** An welchen Stationen der Sortierdatum-Hinweis steht. */
export const sortierdatumHinweisBei = (station: string, istFax: boolean) =>
  !istFax && (station === 'waschen' || station === 'sortieren')

/**
 * Der Zetteldatum-Hinweis beim Sortieren, fünfmal je Person (Runde AS).
 *
 * Der Betrieb: „dass am Anfang vor dem Sortieren das Zetteldatum
 * aufgeschrieben wird … vielleicht noch mit einem Info-Pop-up, wenn man zum
 * ersten Mal sortiert". Das Datum ist beim Sortieren schon Pflicht (ohne es
 * zählt keine Palette); der Hinweis sagt, wozu: Mit dem Eingangsdatum und der
 * Sortierdatei rechnet die App die Kürbisgrösse auf den Eingangstag zurück.
 */
export const ZETTELDATUM_HINWEIS_MAL = 5

export const zetteldatumHinweisSchluessel = (profilId: string) => `zetteldatum_hinweis_${profilId}`

/** Nur beim Sortieren — dort entsteht die Sortierdatei. */
export const zetteldatumHinweisBei = (station: string, istFax: boolean) => !istFax && station === 'sortieren'
