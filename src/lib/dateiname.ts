/**
 * Toleranter Parser für die CSV-Dateinamen.
 *
 * Es gibt **zwei Arten** von Sortierdateien, und die App muss sie
 * auseinanderhalten, weil sie Verschiedenes bedeuten:
 *
 *  **Lauf-Datei** — ein Sortierlauf, das Datum steht im Namen. Das ist das
 *  Format ab Oktober 2026: `Charge_Tag_Monat_Jahr`, z. B. `1614_07_10_26`.
 *  Getippt wird der Name an der Maschine, also kommt hier alles an:
 *  `1614.07.10.26`, `1616 7 10 26`, `1614-07-10-2026`, mit `.csv` oder ohne.
 *  Ältere Läufe tragen `Charge-Tag-Monat-Stunde-Minute` (`1614-25-08-11-10`);
 *  auch die bleiben lesbar.
 *
 *  **Sammeldatei** — eine Datei je Charge, benannt nur nach der Charge
 *  (`1614.csv`). Die Maschine hängt bei jedem weiteren Sortieren derselben
 *  Charge unten an. Sie enthält also **alles bisher Sortierte** dieser
 *  Charge und trägt **kein Datum** — weder im Namen noch im Inhalt.
 *
 * Warum das hier entschieden wird und nicht später: Der Unterschied ist am
 * Namen erkennbar und sonst nirgends. Eine Sammeldatei, die als Lauf gelesen
 * wird, bekommt ein erfundenes Datum und zählt beim zweiten Hochladen alles
 * doppelt — beides still, beides falsch.
 *
 * Der Zeitstempel des Dateisystems ist **keine** Datumsquelle mehr. Bei einer
 * Sammeldatei ist er der Zeitpunkt des letzten Anhängens, bei einer
 * Lauf-Datei der des Kopierens — in beiden Fällen nicht der Sortierzeitpunkt.
 * Er wird nur noch als **obere Schranke** zurückgegeben: Später als da kann
 * nichts in der Datei sortiert worden sein.
 *
 * Die Chargennummer wird nicht geraten, sondern gegen die bekannte Liste
 * geprüft — das ist der einzige harte Anker im Namen.
 */

/** Ein Sortierlauf mit Datum, oder die kumulative Datei einer ganzen Charge. */
export type Dateiart = 'lauf' | 'sammel'

export interface DateinameErgebnis {
  chargeNr: number | null
  /** Der Sortierzeitpunkt aus dem Namen. Nur bei `art: 'lauf'` gesetzt. */
  zeit: Date | null
  art: Dateiart
  quelle: 'dateiname' | null
  /**
   * Späteste Zeit, zu der in dieser Datei etwas sortiert worden sein kann —
   * der Zeitstempel des Dateisystems. Kein Sortierdatum, aber eine echte
   * Schranke für das Zeitfenster einer Sammeldatei.
   */
  spaetestens: Date | null
  /** Was nicht gelesen werden konnte — für die Anzeige beim Einlesen. */
  hinweis: string | null
}

/**
 * Ein Erntejahr läuft über den Jahreswechsel: die Ernte beginnt im Spätsommer,
 * verarbeitet wird bis ins Frühjahr. Ein Datum im Januar gehört deshalb zur
 * Saison des Vorjahres. Gebraucht nur noch, wenn im Namen kein Jahr steht.
 */
const ERSTER_ERNTEMONAT = 7

export function jahrFuerMonat(monat: number, saison: number): number {
  return monat >= ERSTER_ERNTEMONAT ? saison : saison + 1
}

/** Wie weit darf ein Jahr im Namen von der Saison abweichen, bevor es ein
 *  Tippfehler ist? Fünf Jahre — grosszügig, aber nicht beliebig. */
const JAHR_SPANNE = 5

const ganz = (x: number | undefined): x is number => Number.isInteger(x)
const tagOk = (t: number | undefined) => ganz(t) && t >= 1 && t <= 31
const monatOk = (m: number | undefined) => ganz(m) && m >= 1 && m <= 12
const stundeOk = (h: number | undefined) => ganz(h) && h >= 0 && h <= 23
const minuteOk = (m: number | undefined) => ganz(m) && m >= 0 && m <= 59

/** Zwei Stellen sind ein Jahrhundert-Kürzel, vier Stellen das Jahr selbst. */
function jahrLesen(roh: string): number | null {
  const n = Number(roh)
  if (!Number.isInteger(n)) return null
  if (roh.length <= 2) return 2000 + n
  if (roh.length === 4) return n
  return null
}

export function dateinamenLesen(
  dateiname: string,
  bekannteChargen: readonly number[],
  saison: number,
  lastModified?: number,
): DateinameErgebnis {
  // Nicht am Pfadtrenner zerlegen: `/` ist selbst einer der erlaubten Trenner
  // im Dateinamen (`1614/07/10/26`), und aus dem Datei-Dialog kommt ohnehin
  // nur der reine Name. Nur die Endung fällt weg — und eine Endung beginnt
  // mit einem Buchstaben. Vorher stand hier `\.[a-z0-9]+$`, und das frass
  // aus `1614 25.08 11.10` die Minuten als vermeintliche Endung; aus vier
  // Zahlen wurden drei, aus der Uhrzeit ein Jahr 2011.
  const ohneEndung = dateiname.replace(/\.[a-z][a-z0-9]*$/i, '')
  const gruppen = ohneEndung.match(/\d+/g) ?? []
  const spaetestens = lastModified ? new Date(lastModified) : null

  const chargen = new Set(bekannteChargen)
  const index = gruppen.findIndex(g => g.length === 4 && chargen.has(Number(g)))

  if (index === -1) {
    return {
      chargeNr: null, zeit: null, art: 'sammel', quelle: null, spaetestens,
      hinweis: gruppen.length
        ? `Keine bekannte Chargennummer im Namen (gefunden: ${gruppen.join(', ')})`
        : 'Keine Zahlen im Dateinamen',
    }
  }

  const chargeNr = Number(gruppen[index])
  const roh = gruppen.slice(index + 1)
  const sammel = (hinweis: string | null): DateinameErgebnis =>
    ({ chargeNr, zeit: null, art: 'sammel', quelle: null, spaetestens, hinweis })

  // Nur die Chargennummer: die Sammeldatei. Das ist kein Mangel, den man
  // melden müsste — das ist die zweite, gültige Art.
  if (roh.length === 0) return sammel(null)

  const z = roh.map(Number)
  const [tag, monat] = z
  if (!tagOk(tag) || !monatOk(monat)) {
    return sammel(`Kein lesbares Datum im Namen (nach der Charge: ${roh.join(', ')})`)
  }

  /*
   * Wie viele Zahlen nach der Charge stehen, sagt, was sie bedeuten:
   *
   *   2   Tag, Monat                       — Jahr aus der Saison
   *   3   Tag, Monat, Jahr                 — das Format ab Oktober 2026
   *   4   Tag, Monat, Stunde, Minute       — das alte Format
   *   5   Tag, Monat, Jahr, Stunde, Minute — beides zusammen
   *
   * Drei Zahlen sind eindeutig ein Jahr und keine Uhrzeit: Für eine Uhrzeit
   * bräuchte es Stunde *und* Minute, also vier.
   */
  let jahr: number | null = null
  let stunde: number | undefined
  let minute: number | undefined
  let hinweis: string | null = null

  if (roh.length === 2) {
    jahr = jahrFuerMonat(monat, saison)
  } else if (roh.length === 3) {
    jahr = jahrLesen(roh[2])
    if (jahr === null) return sammel(`Jahr im Namen nicht lesbar („${roh[2]}")`)
  } else if (roh.length === 4) {
    jahr = jahrFuerMonat(monat, saison)
    stunde = z[2]; minute = z[3]
  } else {
    jahr = jahrLesen(roh[2])
    if (jahr === null) return sammel(`Jahr im Namen nicht lesbar („${roh[2]}")`)
    stunde = z[3]; minute = z[4]
    if (roh.length > 5) hinweis = `Zahlen nach der Uhrzeit übergangen: ${roh.slice(5).join(', ')}`
  }

  // Ein Jahr weit weg von der Saison ist ein Tippfehler, keine Angabe. Lieber
  // ohne Datum weiter, als mit einem falschen zu rechnen.
  if (Math.abs(jahr - saison) > JAHR_SPANNE) {
    return sammel(`Das Jahr ${jahr} im Namen passt nicht zur Saison ${saison}`)
  }

  const h = stundeOk(stunde) ? stunde : 12
  const m = minuteOk(minute) ? minute : 0
  if (stunde !== undefined && !stundeOk(stunde)) hinweis = 'Uhrzeit im Namen nicht lesbar — 12:00 angenommen'
  else if (minute !== undefined && !minuteOk(minute)) hinweis = 'Uhrzeit im Namen nicht lesbar — 12:00 angenommen'

  const zeit = new Date(jahr, monat - 1, tag, h, m)
  // Der 31. Februar wird von Date still zum 3. März. Das wäre ein erfundenes
  // Datum — also lieber ohne.
  if (zeit.getMonth() !== monat - 1 || zeit.getDate() !== tag) {
    return sammel(`Den ${tag}.${monat}.${jahr} gibt es nicht`)
  }

  return { chargeNr, zeit, art: 'lauf', quelle: 'dateiname', spaetestens, hinweis }
}
