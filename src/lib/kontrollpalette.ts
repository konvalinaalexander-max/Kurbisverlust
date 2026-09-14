import { tagVon } from './format.ts'

/**
 * Die Kontrollpalette und ihre Fälligkeit.
 *
 * Heute rechnet die App mit einer Verdunstungsrate je Sorte über die ganze
 * Saison, und die Wägungen, aus denen sie kommt, sind nach Augenschein
 * ausgewählt — der Betrieb: „an sich werden schon die schlechter aussehenden
 * palette ausgewählt". Beides verzerrt: die Auswahl nach oben, die eine Rate
 * über alles nach innen.
 *
 * Eine markierte Palette je Charge, nie verarbeitet, regelmässig gewogen,
 * beseitigt beides. Zwei Wägungen derselben Palette geben eine Rate **für den
 * Zeitraum dazwischen** — und damit die Antwort auf die Frage, die heute
 * niemand beantworten kann: „ich weiss nicht ob verdunstungsrate konstant ist
 * - ich denke nicht - weil am anfang haben sie sicher schock von draussen
 * feld in halle zu kommen".
 *
 * Deshalb wird am Anfang dichter gemessen als später: die ersten vier Wochen
 * alle zwei Wochen, danach monatlich. Wäre der Abstand überall gleich, liesse
 * sich ein Schock am Anfang gar nicht von einer konstanten Rate trennen.
 *
 * Der Bezugspunkt für die vier Wochen ist bewusst das Anlegen der
 * Kontrollpalette, nicht das Eingangsdatum der Ware: `palette_id` ist
 * nullable und in der Praxis leer — ein Eingangsdatum der konkreten Palette
 * kennt die App also nicht. Wer das „verbessert", baut eine Zahl ein, die
 * niemand gemessen hat.
 */
export interface Abstand { anfang: number; spaeter: number }

/** Vorgabe, falls die Einstellungen nicht gelesen werden konnten (0072). */
export const ABSTAND_VORGABE: Abstand = { anfang: 14, spaeter: 30 }

/** Nach vier Wochen wird seltener gewogen — der Schock ist dann vorbei. */
export const SCHOCKFENSTER_TAGE = 28

/**
 * Ganze Kalendertage zwischen zwei Zeitpunkten, in der Zone des Betrachters.
 * Über `tagVon` und nicht über `toISOString()`: das rechnet in UTC und
 * verschiebt in der Schweiz jeden Abend um einen Tag.
 */
export function tageZwischen(von: string | Date, bis: string | Date): number {
  const tag = (x: string | Date) => {
    const d = typeof x === 'string' ? new Date(x) : x
    if (Number.isNaN(d.getTime())) return null
    return Date.parse(`${tagVon(d)}T00:00:00Z`) / 86_400_000
  }
  const a = tag(von), b = tag(bis)
  if (a === null || b === null) return 0
  return Math.round(b - a)
}

export interface Faelligkeit {
  /** Tage seit der letzten Wägung — oder seit dem Anlegen, wenn es keine gibt. */
  tageSeit: number
  /** Welcher Abstand jetzt gilt: 14 in den ersten vier Wochen, sonst 30. */
  sollAbstand: number
  nieGewogen: boolean
  ueberfaellig: boolean
}

export function faelligkeit(
  angelegtTs: string,
  letzteTs: string | null,
  abstand: Abstand = ABSTAND_VORGABE,
  jetzt: Date = new Date(),
): Faelligkeit {
  const alter = tageZwischen(angelegtTs, jetzt)
  const sollAbstand = alter < SCHOCKFENSTER_TAGE ? abstand.anfang : abstand.spaeter
  const tageSeit = tageZwischen(letzteTs ?? angelegtTs, jetzt)
  return { tageSeit, sollAbstand, nieGewogen: letzteTs === null, ueberfaellig: tageSeit >= sollAbstand }
}
