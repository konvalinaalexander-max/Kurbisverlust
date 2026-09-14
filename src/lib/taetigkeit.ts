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
  /**
   * Wird die Tätigkeit beim Eröffnen einer Arbeit angeboten? Fehlt der
   * Eintrag, ja. `false` heisst: eingefroren — bestehende Arbeiten bleiben
   * lesbar und bedienbar, neue gibt es nicht.
   *
   * Runde R, Fax: Der Betrieb hat den Nenner in Frage gestellt — „egal ob sie
   * vom waschen oder waschen und sortieren kommt … nirgends weisst du das
   * gewicht" — und entschieden: „streiche das vorläufig komplett … aus dem
   * UI … im hintergrund halt einfach auf eis legen". Ohne das gewogene Faule
   * hätte eine Fax-Arbeit nur noch eine Palettenzahl zu bieten, und ein
   * Feld, das niemand braucht, ist schlimmer als keines. Die Datenbank
   * behält Tabellen, Spalten und Sichten unverändert; dieses eine Wort
   * dreht das Angebot wieder auf.
   */
  angeboten?: boolean
}

export const TAETIGKEITEN: Taetigkeit[] = [
  { id: 'sortieren',         text: 'sortieren',        zeichen: '⚙️', weg: 'maschine', station: 'sortieren' },
  { id: 'waschen',           text: 'waschen',          zeichen: '💧', weg: 'maschine', station: 'waschen' },
  { id: 'waschen_sortieren', text: 'waschenSortieren', zeichen: '🧺', weg: 'hand',     station: 'waschen_sortieren' },
  { id: 'fax',               text: 'fax',              zeichen: '📠', weg: 'maschine', station: 'waschen', fax: true, angeboten: false },
]

export function taetigkeitVon(weg: Weg, station: Station, istFax = false): Taetigkeit | undefined {
  // Fax teilt Weg und Station mit dem Waschgang; die Markierung entscheidet.
  return TAETIGKEITEN.find(a => a.weg === weg && a.station === station && (a.fax ?? false) === istFax)
      ?? TAETIGKEITEN.find(a => a.weg === weg && a.station === station)
}

/**
 * „Tage seit dem Waschen" aus der letzten abgeschlossenen Wasch-Arbeit
 * derselben Charge — der **Vorschlag** für den Fax-Abschluss (Runde P).
 *
 * Warum überhaupt: Die Angabe steht in der Demo-Saison auf 142 von 161
 * Fax-Arbeiten; die übrigen 19 sind leer, weil niemand die Zahl im Kopf
 * hatte. Die App weiss sie meistens — also erinnert sie daran, statt zu
 * fragen. Keine neue Frage an den Arbeiter, ein Feld weniger zu tippen.
 *
 * Warum die Obergrenze: In der ganzen Saison steht die Zahl auf 1, 2 oder 3
 * Tagen (43 / 54 / 44 Arbeiten) — gewaschen wird kurz vor dem Abpacken. Liegt
 * die letzte Wasch-Arbeit dieser Charge länger als zwei Wochen zurück, ist sie
 * mit grosser Wahrscheinlichkeit **nicht** die, aus der diese Paletten kommen;
 * dann ist das Feld leer besser als falsch vorbelegt (leer ist nicht null).
 * Zwei Wochen und nicht drei Tage, damit eine echte, ungewöhnlich lange
 * Wartezeit trotzdem vorgeschlagen wird.
 *
 * In der Zukunft liegende Wasch-Arbeiten geben keinen Vorschlag: Negative
 * Wartezeiten gibt es nicht, und ein Tippfehler im Datum soll sich nicht als
 * Zahl fortpflanzen (0070: die Zeit läuft vorwärts).
 *
 * Gerechnet wird in **Kalendertagen der Ortszeit**, nicht in Stunden: Wer um
 * 23:00 wäscht und am nächsten Morgen um 07:00 abpackt, wartete einen Tag,
 * nicht null.
 *
 * @param ende   Ende der letzten abgeschlossenen Wasch-Arbeit, oder nichts
 * @param heute  der Tag des Abschlusses (Vorgabe: jetzt)
 * @returns die Tage, oder null — dann bleibt das Feld leer
 */
export function vorschlagTageSeitWaschen(ende: string | Date | null | undefined, heute: Date = new Date()): number | null {
  if (ende == null || ende === '') return null
  const tag = (x: string | Date) => {
    const d = new Date(x)
    return Number.isNaN(d.getTime()) ? null : Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000
  }
  const a = tag(ende), b = tag(heute)
  if (a === null || b === null) return null
  const n = Math.round(b - a)
  return n < 0 || n > VORSCHLAG_HOECHSTENS_TAGE ? null : n
}

/** Weiter zurück als zwei Wochen wird nicht mehr vorgeschlagen — siehe oben. */
export const VORSCHLAG_HOECHSTENS_TAGE = 14
