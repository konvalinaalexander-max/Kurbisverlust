/**
 * Toleranter Parser für die CSV-Dateinamen (Spec §5).
 *
 * Die Maschine erzeugt bei jedem Chargenwechsel eine neue Datei, benannt
 * `Charge-TT-MM-HH-MM`, z. B. `1614-25-08-11-10`. Das Jahr fehlt — es ist
 * immer die laufende Saison. Getippt wird der Name an der Maschine, also
 * kommt hier alles an: `1614_25_08_11_10`, `1614 25.08 11.10`, `.csv` dran
 * oder nicht, führende Pfade.
 *
 * Die Chargennummer wird nicht geraten, sondern gegen die bekannte Liste
 * geprüft — das ist der einzige harte Anker im Namen.
 */

export interface DateinameErgebnis {
  chargeNr: number | null
  zeit: Date | null
  quelle: 'dateiname' | 'lastModified' | null
  /** Was nicht gelesen werden konnte — für die Anzeige in der Warteschlange. */
  hinweis: string | null
}

/**
 * Ein Erntejahr läuft über den Jahreswechsel: die Ernte beginnt im Spätsommer,
 * verarbeitet wird bis ins Frühjahr. Ein Datum im Januar gehört deshalb zur
 * Saison des Vorjahres.
 */
const ERSTER_ERNTEMONAT = 7

export function jahrFuerMonat(monat: number, saison: number): number {
  return monat >= ERSTER_ERNTEMONAT ? saison : saison + 1
}

export function dateinamenLesen(
  dateiname: string,
  bekannteChargen: readonly number[],
  saison: number,
  lastModified?: number,
): DateinameErgebnis {
  // Nicht am Pfadtrenner zerlegen: `/` ist selbst einer der erlaubten Trenner
  // im Dateinamen (`1614/25/08/11/10`), und aus dem Datei-Dialog kommt ohnehin
  // nur der reine Name. Nur die Endung fällt weg.
  const ohneEndung = dateiname.replace(/\.[a-z0-9]+$/i, '')
  const gruppen = ohneEndung.match(/\d+/g) ?? []

  const chargen = new Set(bekannteChargen)
  const index = gruppen.findIndex(g => g.length === 4 && chargen.has(Number(g)))

  if (index === -1) {
    return {
      chargeNr: null,
      zeit: ersatzZeit(lastModified),
      quelle: lastModified ? 'lastModified' : null,
      hinweis: gruppen.length
        ? `Keine bekannte Chargennummer im Namen (gefunden: ${gruppen.join(', ')})`
        : 'Keine Zahlen im Dateinamen',
    }
  }

  const chargeNr = Number(gruppen[index])
  const rest = gruppen.slice(index + 1).map(Number)
  const [tag, monat, stunde, minute] = rest

  const datumOk = Number.isInteger(tag) && Number.isInteger(monat)
    && tag >= 1 && tag <= 31 && monat >= 1 && monat <= 12
  if (!datumOk) {
    return {
      chargeNr,
      zeit: ersatzZeit(lastModified),
      quelle: lastModified ? 'lastModified' : null,
      hinweis: 'Datum im Namen nicht lesbar — Zeitstempel der Datei verwendet',
    }
  }

  const h = Number.isInteger(stunde) && stunde >= 0 && stunde <= 23 ? stunde : 12
  const m = Number.isInteger(minute) && minute >= 0 && minute <= 59 ? minute : 0
  const zeit = new Date(jahrFuerMonat(monat, saison), monat - 1, tag, h, m)

  return {
    chargeNr,
    zeit,
    quelle: 'dateiname',
    hinweis: Number.isInteger(stunde) && Number.isInteger(minute)
      ? null
      : 'Uhrzeit im Namen nicht lesbar — 12:00 angenommen',
  }
}

function ersatzZeit(lastModified?: number): Date | null {
  return lastModified ? new Date(lastModified) : null
}
