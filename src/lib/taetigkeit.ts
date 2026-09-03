import type { TextId } from './i18n'
import type { Station, Weg } from './typen'

/**
 * Was der Arbeiter tatsächlich tut — das ist die einzige Auswahl, die er trifft.
 *
 * Intern unterscheidet die Auswertung „Weg 1" (Maschine) und „Weg 2" (Hand),
 * weil sich die beiden fachlich völlig unterschiedlich verhalten. Für den
 * Arbeiter ist das bedeutungslos: Er sortiert, wäscht, oder macht beides
 * zugleich. Die Zuordnung passiert hier, einmal, an einer Stelle.
 */
export interface Taetigkeit {
  id: string
  text: TextId
  zeichen: string
  weg: Weg
  station: Station
  /** Fax: fachlich ein Waschgang, für die Erfassung getrennt (AB-08). */
  fax?: boolean
}

export const TAETIGKEITEN: Taetigkeit[] = [
  { id: 'sortieren',         text: 'sortieren',        zeichen: '⚙️', weg: 'maschine', station: 'sortieren' },
  { id: 'waschen',           text: 'waschen',          zeichen: '💧', weg: 'maschine', station: 'waschen' },
  { id: 'waschen_sortieren', text: 'waschenSortieren', zeichen: '🧺', weg: 'hand',     station: 'waschen_sortieren' },
  { id: 'fax',               text: 'fax',              zeichen: '📠', weg: 'maschine', station: 'waschen', fax: true },
]

export function taetigkeitVon(weg: Weg, station: Station, istFax = false): Taetigkeit | undefined {
  // Fax teilt Weg und Station mit dem Waschgang; die Markierung entscheidet.
  return TAETIGKEITEN.find(a => a.weg === weg && a.station === station && (a.fax ?? false) === istFax)
      ?? TAETIGKEITEN.find(a => a.weg === weg && a.station === station)
}
