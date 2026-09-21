import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { einstellung, fehlerText } from '../lib/db'
import { datum, zahl } from '../lib/format'
import { SCHRITTE, auswertungVergessen } from '../auswertung/daten'
import { Hinweis, Karte, Lade } from './Bausteine'

/**
 * Tabula rasa: alles Erfasste weg, die Stammdaten bleiben.
 *
 * Der Betrieb hat es für den Testtag verlangt: „alle aktuelen arbeiten die
 * noch laufen zu löschen - und auch die gespeicherten daten zu löschen - so
 * dass wir eine tabula rasa haben und heute damit testen können". An so
 * einem Tag wird in der Halle ausprobiert, vertippt und abgebrochen — und
 * nichts davon darf am Abend in den Zahlen stehen. Ohne diesen Knopf führte
 * der Weg zurück auf Null über den SQL-Editor des Anbieters, Tabelle für
 * Tabelle, in der richtigen Reihenfolge. Das macht niemand mitten in einer
 * Schicht, und wer es doch tut, vergisst eine Tabelle.
 *
 * Vier Dinge machen den Knopf verantwortbar, und alle vier stehen auf dem
 * Bildschirm — ein Knopf, der mehr verspricht, als er hält, ist gefährlicher
 * als gar keiner:
 *
 *   · Er sagt VORHER, was er trifft. Nicht „alles", sondern „309 Arbeiten,
 *     844 Eingangspaletten, 187 Lieferungen" — frisch aus erfassung_umfang()
 *     bei jedem Öffnen, dazu die Zahl der Arbeiten, die gerade laufen.
 *   · Er sagt VORHER, was stehen bleibt. Chargen, Sorten, Gebinde, Käufer,
 *     Schemata, Konten, Einstellungen: die App ist danach sofort wieder
 *     arbeitsfähig, so wie am Tag der Einrichtung.
 *   · Er verlangt ein getipptes Wort. Ein Knopf, der mit einem Tipper eine
 *     Saison wegnimmt, wird irgendwann versehentlich getroffen — am ehesten
 *     von dem, der ihn am besten kennt.
 *   · Was er löscht, bleibt im erfassung_journal nachlesbar, mit einer
 *     Ausnahme, die hier ausdrücklich dasteht: die eingelesenen
 *     Warenausgangszeilen tragen den Journal-Auslöser nicht.
 *
 * Gelöscht wird nichts hier — das tut die Datenbank in einer Transaktion
 * (erfassung_leeren, 0080); hier steht nur die Frage davor. Die Auswertung
 * rechnet die Funktion aus demselben Grund nicht selbst, aus dem es
 * demo_daten_laden() nicht tut: ein API-Aufruf hat sein eigenes Zeitlimit,
 * und das Rechnen ist der teuerste Teil. Deshalb danach dieselben fünf
 * Schritte, die auch hinter „Neu rechnen" stehen — und
 * `auswertungVergessen()`, damit der nächste Bildschirm nicht die
 * gemerkten Zahlen von vorhin zeigt.
 */

/** Das Wort, das die Datenbank verlangt (erfassung_leeren, 0080). */
const WORT = 'ALLES LOESCHEN'

/**
 * Getippt werden muss das Wort; woran es nicht scheitern soll, ist die
 * Umschalttaste oder die Frage, ob man „LÖSCHEN" oder „LOESCHEN" schreibt.
 * Was an die Datenbank geht, ist immer die eine Schreibweise, die sie kennt.
 */
function wortStimmt(getippt: string): boolean {
  return getippt.trim().toUpperCase().replace(/Ö/g, 'OE') === WORT
}

interface Umfang { tabelle: string; was: string; zeilen: number }

export default function ErfassungLeeren({ nachAenderung }: { nachAenderung?: () => void }) {
  const [umfang, setUmfang] = useState<Umfang[] | null>(null)
  const [offene, setOffene] = useState(0)
  const [journal, setJournal] = useState<number | null>(null)
  const [scharf, setScharf] = useState(false)
  const [sicherung, setSicherung] = useState<string | null>(null)
  const [getippt, setGetippt] = useState('')
  const [laeuft, setLaeuft] = useState<'leeren' | 'rechnen' | null>(null)
  const [schritt, setSchritt] = useState(0)
  const [meldung, setMeldung] = useState<string | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)

  /** Der Stand, bevor etwas passiert — und nach dem Leeren noch einmal. */
  const laden = useCallback(async () => {
    const [u, o, j, s, w] = await Promise.all([
      supabase.rpc('erfassung_umfang'),
      supabase.from('auftrag').select('id', { count: 'exact', head: true })
        .eq('status', 'offen').is('abgebrochen_ts', null),
      supabase.from('erfassung_journal').select('id', { count: 'exact', head: true }),
      einstellung<boolean>('erfassung_scharf', false),
      einstellung<string | null>('letzte_sicherung', null),
    ])
    if (u.error) { setFehler(fehlerText(u.error)); setUmfang([]) } else setUmfang((u.data ?? []) as Umfang[])
    setOffene(o.count ?? 0)
    setJournal(j.count ?? null)
    setScharf(s === true)
    setSicherung(w ?? null)
  }, [])
  useEffect(() => { void laden() }, [laden])

  const zeilen = umfang ?? []
  const gesamt = zeilen.reduce((a, u) => a + Number(u.zeilen), 0)
  const bereit = wortStimmt(getippt)

  async function leeren() {
    if (!bereit || laeuft) return
    setLaeuft('leeren'); setSchritt(0); setFehler(null); setMeldung(null)
    const { data, error } = await supabase.rpc('erfassung_leeren', { p_bestaetigung: WORT })
    // Scheitert es, ist nichts gelöscht — alles hing in einer Transaktion.
    // Das getippte Wort bleibt stehen, damit ein zweiter Versuch ein Klick ist.
    if (error) { setLaeuft(null); setFehler(fehlerText(error)); return }
    const bericht = data as string

    // Die fünf Schritte, die auch hinter „Neu rechnen" stehen: einzeln, damit
    // keiner ins Zeitlimit läuft, und sichtbar, weil es einige Sekunden sind.
    setLaeuft('rechnen')
    let rechenfehler: string | null = null
    for (let i = 1; i <= SCHRITTE.length; i++) {
      setSchritt(i)
      const r = await supabase.rpc('auswertung_schritt', { p_schritt: i })
      if (r.error) {
        rechenfehler = `Schritt ${i} von ${SCHRITTE.length} (${SCHRITTE[i - 1]}): ${fehlerText(r.error)}`
        break
      }
    }
    // Der gemerkte Stand der Sitzung ist jetzt falsch, egal ob gerechnet
    // wurde oder nicht. Lieber ein Bildschirm, der neu lädt, als einer, der
    // Tonnen aus gelöschten Zeilen zeigt.
    auswertungVergessen()
    setLaeuft(null); setSchritt(0); setGetippt('')
    if (rechenfehler) {
      setFehler(`${bericht} Die Auswertung liess sich danach nicht neu rechnen — ${rechenfehler} `
        + 'Oben rechts auf dem Überblick „Neu rechnen" drücken.')
    } else {
      setMeldung(`${bericht} Die Auswertung ist neu gerechnet: alle Zahlen stehen wieder auf null.`)
    }
    await laden()
    nachAenderung?.()
  }

  if (umfang === null) return <Lade text="Zählt, was erfasst ist …" zeilen={4} />

  return (
    <Karte titel="Alles löschen"
           unter="Zurück auf den Stand nach der Einrichtung: alles Erfasste weg, die Grundlagen bleiben.">
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {meldung && <Hinweis art="gut">{meldung}</Hinweis>}

      <p>
        Für den Testtag gedacht. In der Halle wird ausprobiert, vertippt und
        abgebrochen — am Abend soll nichts davon in den Zahlen stehen. Dieser
        Knopf nimmt alles weg, was erfasst wurde, auch die Arbeiten, die gerade
        noch laufen. Was der Betrieb einmal eingerichtet hat, bleibt: die App
        ist danach sofort wieder benutzbar, nur leer.
      </p>

      {gesamt === 0 ? (
        <>
          <Hinweis>Es ist nichts erfasst. Hier gibt es gerade nichts zu löschen.</Hinweis>
          <p className="leise">
            {journal !== null && <>Im Journal stehen {zahl(journal)} Zeilen — jede Erfassung, die es je
            gab, mit ihrem ganzen Inhalt. </>}
            <Link to="/dashboard">Zum Überblick</Link>
          </p>
        </>
      ) : (
        <>
          {offene > 0 && (
            <Hinweis art="warnung">
              Gerade {offene === 1 ? 'läuft eine Arbeit' : `laufen ${zahl(offene)} Arbeiten`}. Wer sie
              auf dem Handy offen hat, findet sie nach dem Löschen nicht mehr und muss neu
              anfangen. Vorher kurz in der Halle durchsagen.
            </Hinweis>
          )}

          <p className="leise" style={{ marginBottom: '.3rem' }}>Das ist erfasst und wäre danach weg:</p>
          <div className="rollbar">
            <table className="dicht" id="leeren-umfang">
              <thead><tr><th>Was</th><th className="zahl">Zeilen</th></tr></thead>
              <tbody>
                {zeilen.map(u => (
                  <tr key={u.tabelle}>
                    <td>{u.was}</td>
                    <td className="zahl">{zahl(Number(u.zeilen))}</td>
                  </tr>
                ))}
                <tr>
                  <td><strong>zusammen</strong></td>
                  <td className="zahl"><strong>{zahl(gesamt)}</strong></td>
                </tr>
              </tbody>
            </table>
          </div>

          <p className="leise">
            <strong>Das bleibt stehen:</strong> die Chargen der Anbauplanung, die Sorten mit
            ihren Kaliber-Grenzen, die Gebinde mit ihrer Tara, die Käufer, die datierten
            Sortierschemata, die Benutzerkonten, die Einstellungen samt dem Datum des
            Erfassungsbeginns und die bestätigten Artikel-Zuordnungen des Warenausgangs.
            Die Kilo-Angaben je Charge unter „Erfassungsbeginn" gehören dagegen zum
            Erfassten und gehen mit.
          </p>

          <p className="leise">
            <strong>Nachlesbar bleibt es auch:</strong> Jede gelöschte Zeile einer
            Erfassungstabelle wandert mit ihrem ganzen Inhalt ins Journal
            {journal !== null && <> — dort stehen heute schon {zahl(journal)} Zeilen</>}. Eine
            Ausnahme gehört dazu: die Zeilen aus hochgeladenen Warenausgangsdateien tragen
            den Journal-Auslöser nicht. Verloren sind sie trotzdem nicht — sie stehen in
            der Excel-Datei, die sich erneut hochladen lässt.
          </p>

          {scharf && (
            <Hinweis art="warnung">
              Diese Datenbank ist als <strong>scharf</strong> markiert: Auf ihr liegen echte
              Erfassungsdaten aus dem Betrieb, keine Übung. Letzte vermerkte Sicherung:{' '}
              {sicherung ? datum(sicherung) : 'noch keine'}. Wenn heute kein Testtag ist,
              zieh vorher eine Sicherung (Betrieb → Arbeiten, Karte „Sicherung").
            </Hinweis>
          )}

          <div className="feld" style={{ maxWidth: '24rem', marginTop: '1rem' }}>
            <label htmlFor="leeren-wort">Zum Bestätigen <code>{WORT}</code> eintippen</label>
            <input id="leeren-wort" type="text" value={getippt} disabled={laeuft !== null}
                   autoComplete="off" autoCorrect="off" spellCheck={false}
                   onChange={e => setGetippt(e.target.value)} />
            <p className="hilfe">
              Die getippte Zeile ist Absicht. Ein Knopf, der mit einem Tipper eine Saison
              wegnimmt, wird irgendwann versehentlich getroffen.
            </p>
          </div>

          <button type="button" id="leeren-jetzt" className="gefahr"
                  disabled={!bereit || laeuft !== null} onClick={() => void leeren()}>
            {laeuft === 'leeren' ? 'Wird gelöscht …'
              : laeuft === 'rechnen'
                ? `Auswertung wird gerechnet … Schritt ${schritt} von ${SCHRITTE.length} · ${SCHRITTE[schritt - 1] ?? ''}`
                : `Ja, ${zahl(gesamt)} Zeilen löschen`}
          </button>
        </>
      )}
    </Karte>
  )
}
