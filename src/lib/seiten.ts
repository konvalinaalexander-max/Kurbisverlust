/**
 * Alle Zeilen einer Tabelle oder Sicht — wirklich alle (Runde BL).
 *
 * Der Betrieb: „Stelle sicher, dass das Programm wirklich die ganze
 * Perigon-Datei voll parat hat. Nicht, dass das Programm faul ist und nur die
 * ersten 100 anzeigt."
 *
 * Die Schnittstelle der Datenbank gibt je Anfrage höchstens tausend Zeilen.
 * Wer mehr braucht, holt seitenweise — und dabei gab es zwei stille Fehler:
 *
 *   1. Seiten ohne feste Reihenfolge. Sortiert man nur nach dem Datum, ist die
 *      Reihenfolge innerhalb eines Tages bei jeder Anfrage eine andere; an der
 *      Seitengrenze kommt dann eine Zeile doppelt und eine andere gar nicht.
 *      Am 12. November im Betrieb gemessen: von 7790 Zeilen „geliefert je
 *      Kunde und Tag" kamen 8 doppelt und 8 fehlten (974 kg daneben).
 *   2. Eine Obergrenze (`.limit(500)`), die niemand sah: was darüber lag,
 *      fehlte, ohne dass die Seite es sagte.
 *
 * Darum hier, an einer Stelle: Passt alles in eine Anfrage, ist es eine
 * Anfrage. Braucht es mehr als eine Seite, wird gezählt, wie viele Zeilen es
 * sind, und nach *allen* Spalten geordnet (zuerst die gewünschten, dann der
 * Rest) — die Reihenfolge ist damit bei jeder Anfrage dieselbe —, und am Ende
 * muss die Zahl der geholten Zeilen die gezählte sein. Stimmt sie nicht (während des Holens kam etwas dazu), wird
 * einmal von vorn geholt; stimmt sie wieder nicht, ist das ein Fehler, den
 * die Seite zeigt — nie eine stille Lücke.
 *
 * Reine Funktion, kein Netz — das Holen einer Seite kommt von aussen, damit
 * die Regel prüfbar bleibt (test/seiten.test.ts).
 */

export const SEITE = 1000
/** So viele Seiten werden gleichzeitig geholt, wenn ihre Zahl bekannt ist. */
const GLEICHZEITIG = 6

/** Eine Spalte, aufsteigend — oder [Spalte, aufsteigend?]. */
export type Ordnung = string | [string, boolean]

export interface SeitenFehler { message: string; code?: string }

export interface Seite<T> {
  data: T[] | null
  error: SeitenFehler | null
  /** Wie viele Zeilen es insgesamt sind — nur verlangt, wenn es mehr als eine Seite braucht. */
  count?: number | null
}

/** Holt die Zeilen von..bis (beide eingeschlossen) in dieser Ordnung; `zaehlen`: die Gesamtzahl mitgeben. */
export type SeiteHolen<T> = (von: number, bis: number, ordnung: [string, boolean][], zaehlen: boolean) => PromiseLike<Seite<T>>

const paar = (o: Ordnung): [string, boolean] => typeof o === 'string' ? [o, true] : o

/**
 * Die volle Ordnung: zuerst die gewünschten Spalten, dann alle übrigen
 * einfachen Spalten der Zeile (ohne Listen und Objekte — nach denen ordnet die
 * Datenbank nicht verlässlich). Zwei Zeilen, die in allen Spalten gleich sind,
 * sind dieselbe Auskunft; welche von beiden zuerst kommt, ändert nichts.
 */
export function volleOrdnung(ordnung: Ordnung[], zeile: object | undefined): [string, boolean][] {
  const voll = ordnung.map(paar)
  const schon = new Set(voll.map(o => o[0]))
  for (const [spalte, wert] of Object.entries(zeile ?? {}).sort((a, b) => a[0].localeCompare(b[0]))) {
    if (schon.has(spalte) || (wert !== null && typeof wert === 'object')) continue
    voll.push([spalte, true])
  }
  return voll
}

export class Unvollstaendig extends Error {
  geholt: number
  gezaehlt: number
  constructor(geholt: number, gezaehlt: number) {
    super(`Unvollständig geladen: ${geholt} von ${gezaehlt} Zeilen. Bitte neu laden.`)
    this.name = 'Unvollstaendig'
    this.geholt = geholt
    this.gezaehlt = gezaehlt
  }
}

/**
 * Alle Zeilen, seitenweise. Wirft den Fehler der Datenbank, wie er ist (die
 * Aufrufer lesen seinen Code), oder `Unvollstaendig`.
 */
export async function alleSeiten<T extends object>(holen: SeiteHolen<T>, ordnung: Ordnung[] = [], seite = SEITE): Promise<T[]> {
  const gewuenscht = ordnung.map(paar)
  let letzte: Unvollstaendig | null = null
  for (let versuch = 0; versuch < 2; versuch++) {
    // Zuerst ohne Zählung: Die meisten Tabellen passen in eine Anfrage, und das Zählen rechnet eine Sicht ein zweites Mal.
    const erste = await holen(0, seite - 1, gewuenscht, false)
    if (erste.error) throw erste.error
    const zeilen = erste.data ?? []
    // Eine Anfrage, alles da: Hier gibt es keine Seitengrenze, an der etwas verloren gehen könnte.
    if (zeilen.length < seite) return zeilen
    // Mehr als eine Seite: von vorn, in voller Ordnung und gezählt.
    const voll = volleOrdnung(ordnung, zeilen[0])
    const anfang = await holen(0, seite - 1, voll, true)
    if (anfang.error) throw anfang.error
    const alle: T[] = [...(anfang.data ?? [])]
    const gezaehlt = anfang.count ?? null
    if (gezaehlt !== null) {
      // Die Zahl ist bekannt: die übrigen Seiten gleichzeitig holen (je sechs) — bei einer Sicht, die für jede
      // Seite neu gerechnet wird, sind das Sekunden (v_kunde_tag im Betrieb: fünf statt zehn).
      const anfaenge = Array.from({ length: Math.max(0, Math.ceil(gezaehlt / seite) - 1) }, (_, i) => (i + 1) * seite)
      for (let i = 0; i < anfaenge.length; i += GLEICHZEITIG) {
        const teile = await Promise.all(anfaenge.slice(i, i + GLEICHZEITIG).map(von => holen(von, von + seite - 1, voll, false)))
        for (const r of teile) { if (r.error) throw r.error; alle.push(...(r.data ?? [])) }
      }
    } else {
      // Eine Schnittstelle, die nicht zählt: Seite um Seite, bis eine nicht mehr voll ist.
      for (let von = seite; alle.length === von; von += seite) {
        const r = await holen(von, von + seite - 1, voll, false)
        if (r.error) throw r.error
        alle.push(...(r.data ?? []))
      }
    }
    if (gezaehlt === null || alle.length === gezaehlt) return alle
    letzte = new Unvollstaendig(alle.length, gezaehlt)
  }
  throw letzte ?? new Unvollstaendig(0, 0)
}
