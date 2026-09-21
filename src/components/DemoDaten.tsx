import { useCallback, useEffect, useState } from 'react'
import { imDemoModus, supabase } from '../lib/supabase'
import { useBetriebsmodus } from '../lib/betriebsmodus'
import { fehlerText } from '../lib/db'
import { Hinweis, Karte } from './Bausteine'

/**
 * Demo-Saison laden und wieder entfernen.
 *
 * Warum das in der App steht und nicht nur als SQL-Datei: Wer das Werkzeug
 * zum ersten Mal öffnet, sieht ein leeres Dashboard — und kann nicht
 * beurteilen, ob es taugt. Der Weg dorthin führte bisher über den SQL-Editor
 * des Datenbank-Anbieters: Datei suchen, kopieren, einfügen, Run. Das macht
 * niemand freiwillig, und schon gar nicht zweimal.
 *
 * Gerechnet wird nichts hier — die Saison entsteht komplett in der Datenbank
 * (demo_daten_laden), damit App-Knopf und SQL-Datei nicht zwei Fassungen
 * derselben Sache werden, die mit der Zeit auseinanderlaufen.
 */
export default function DemoDaten({ kompakt = false, nachAenderung }: {
  kompakt?: boolean
  nachAenderung?: () => void
}) {
  const modus = useBetriebsmodus()
  const [geladen, setGeladen] = useState<boolean | null>(null)
  const [laeuft, setLaeuft] = useState<'laden' | 'entfernen' | 'neu' | 'rechnen' | null>(null)
  const [meldung, setMeldung] = useState<string | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const [sicher, setSicher] = useState(false)

  /** Woran man die Demo erkennt: Paletten mit extern_id 'demo-…'. Dieselbe
      Marke, an der demo_daten_entfernen() sie wieder findet. */
  const stand = useCallback(async () => {
    const { count, error } = await supabase.from('palette')
      .select('extern_id', { count: 'exact', head: true }).like('extern_id', 'demo-%')
    if (error) setFehler(fehlerText(error)); else setGeladen((count ?? 0) > 0)
  }, [])
  useEffect(() => { void stand() }, [stand])

  /** Neu laden heisst: erst entfernen, dann laden. Zwei Aufrufe, ein Knopf —
      denn eine zweite Demo neben der ersten wäre doppelt gezählte Ware. */
  async function rufen(was: 'laden' | 'entfernen' | 'neu') {
    setLaeuft(was); setFehler(null); setMeldung(null); setSicher(false)
    if (was === 'neu') {
      const weg = await supabase.rpc('demo_daten_entfernen')
      if (weg.error) { setLaeuft(null); setFehler(fehlerText(weg.error)); await stand(); return }
    }
    const { data, error } = await supabase.rpc(
      was === 'entfernen' ? 'demo_daten_entfernen' : 'demo_daten_laden')
    if (error) { setLaeuft(null); setFehler(fehlerText(error)); await stand(); return }
    // Die Auswertung rechnet die Funktion nicht selbst — ein API-Aufruf hat bei
    // Supabase acht Sekunden, und das Rechnen ist der teuerste Teil. Darum
    // hier als eigener Aufruf, sonst stünde die Auswertung als veraltet da.
    setLaeuft('rechnen')
    const rechnen = await supabase.rpc('auswertung_aktualisieren')
    setLaeuft(null)
    if (rechnen.error) {
      setFehler(`${data as string} — aber die Auswertung liess sich nicht neu rechnen: ${fehlerText(rechnen.error)}. Oben rechts „Neu rechnen" drücken.`)
    } else {
      setMeldung(data as string)
    }
    await stand()
    nachAenderung?.()
  }

  const inhalt = (
    <>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {meldung && <Hinweis art="gut">{meldung}</Hinweis>}

      {geladen === false && (
        <>
          <p>
            Eine erfundene Saison, so gebaut, wie die Daten wirklich kommen: alle
            42 Chargen der Anbauplanung (rund 362 t, 951 Paletten), die Ernte je
            Charge über Tage und Wochen verteilt, gut 370 Arbeiten über beide
            Wege — Sortieren mit Sortier-CSV und gezählten Kisten, Waschen je Kaliber,
            Waschen + Sortieren von Hand mit gewogener Palette und gewogenem Ausschuss,
            Fax mit gezählten Kisten — dazu Kontrollpaletten, die über Wochen immer
            wieder gewogen werden, monatliche Verkaufsdateien, Lieferungen über Wochen
            verschränkt, und die Sonderfälle jeder Saison (abgebrochene Arbeit,
            Zahlendreher, vergessene Ablesung, Zetteldatum ohne Palette). Damit füllt
            sich jeder Bildschirm der App und man sieht, was am Ende herauskommt —
            bevor die erste echte Palette gezählt ist.
          </p>
          <p className="leise">
            Alles Erfundene ist markiert und lässt sich mit einem Klick restlos
            wieder entfernen. Echte Daten werden dabei nie angefasst — auch nicht,
            wenn schon welche da sind.
          </p>
          <button className="haupt" disabled={laeuft !== null}
                  onClick={() => void rufen('laden')}>
            {laeuft === 'laden' ? 'Saison wird angelegt …' : laeuft === 'rechnen' ? 'Auswertung wird gerechnet …' : 'Demo-Saison laden'}
          </button>
        </>
      )}

      {geladen === true && (
        <>
          <p>
            Die Demo-Saison ist geladen. Alles, was Du gerade siehst, ist erfunden —
            zum Anschauen und Ausprobieren gedacht, nicht zum Entscheiden.
          </p>
          <p className="leise">
            Nach einer Aktualisierung des Werkzeugs lohnt sich <strong>neu
            laden</strong>: Die Demo wächst mit. Sie zeigt dann auch, was seither
            dazugekommen ist — die alte Saison wird zuerst entfernt, damit nicht
            zwei Demos nebeneinander stehen und die Mengen doppelt zählen.
          </p>
          <button className="haupt" disabled={laeuft !== null}
                  style={{ marginBottom: '.75rem' }}
                  onClick={() => void rufen('neu')}>
            {laeuft === 'neu' ? 'Saison wird neu angelegt …' : laeuft === 'rechnen' ? 'Auswertung wird gerechnet …' : 'Demo-Saison neu laden'}
          </button>
          <p className="leise">
            Bevor die echten Daten kommen: hier entfernen. Gelöscht wird nur, was
            zur Demo gehört (Arbeiten mit dem Vermerk „DEMO", Paletten mit
            „demo-…", Sortierdateien „DEMO-…"). Was Du selbst erfasst hast, bleibt.
          </p>
          {sicher ? (
            <div className="reihe">
              <button className="gefahr" disabled={laeuft !== null}
                      onClick={() => void rufen('entfernen')}>
                {laeuft === 'entfernen' ? 'Wird entfernt …' : laeuft === 'rechnen' ? 'Auswertung wird gerechnet …' : 'Ja, Demo-Daten löschen'}
              </button>
              <button onClick={() => setSicher(false)}>Doch nicht</button>
            </div>
          ) : (
            <button className="gefahr" onClick={() => setSicher(true)}>
              Demo-Daten entfernen
            </button>
          )}
        </>
      )}
    </>
  )

  /**
   * Wer über den Demo-Knopf hereinkam, darf nie vor einem leeren Bildschirm
   * ohne Erklärung stehen.
   *
   * Gemeldet aus dem Betrieb, gleich nach dem ersten erfolgreichen Eintritt:
   * „demo ist komplett leer - absolut keine daten - kein eingang - ausgang
   * etc. keine arbeiten? hat überhaupt nicht geklappt". Dort war die Ursache
   * harmlos — der Knopf „Demo-Saison laden" war schlicht noch nicht gedrückt.
   * Beim Nachsehen fiel aber ein zweiter Weg zum selben leeren Bildschirm
   * auf, und der wäre nicht harmlos: Die Karte zum Laden der Saison hing an
   * `betriebsmodus = 'beispiel'`. Fehlt diese eine Zeile in der
   * Demo-Datenbank — oder lief sie im falschen Projekt —, verschwindet die
   * Karte, und zurück bleibt genau nichts. Kein Knopf, kein Hinweis, keine
   * Vermutung, was fehlt.
   *
   * Der Demo-Modus weiss aber unabhängig von jeder Datenbank, dass er der
   * Demo-Modus ist (der Merkzettel im Browser). Also kann er hier immer etwas
   * sagen — auch wenn die Datenbank noch gar nicht antwortet.
   */
  if (imDemoModus && modus !== 'beispiel') {
    return (
      <Karte titel="Die Demo-Datenbank ist noch nicht scharfgeschaltet">
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <p>
          Die Datenbank, mit der diese Seite gerade spricht, sagt von sich, sie
          sei die <strong>echte</strong>. Dann nimmt sie keine Beispieldaten an —
          absichtlich, das ist der Schutz, der verhindert, dass eine erfundene
          Palette zwischen echten Messungen landet.
        </p>
        <p>
          Deshalb steht hier nichts. Es fehlt genau eine Zeile, und zwar im
          <strong> Demo-Projekt</strong> bei Supabase, unter SQL Editor:
        </p>
        <pre style={{ whiteSpace: 'pre-wrap', fontSize: '.85rem' }}>{
`update einstellung set wert = '"beispiel"'::jsonb
 where schluessel = 'betriebsmodus';`}</pre>
        <p className="leise">
          Danach diese Seite neu laden — dann steht hier der Knopf, der die
          Saison hineinlegt. Kommt beim Ausführen ein Fehler wie „relation
          einstellung does not exist", dann fehlt im Demo-Projekt noch die
          <code> setup.sql</code> (Teil B der Anleitung).
        </p>
        <p className="leise">
          Und falls die Zeile schon gelaufen ist: Vermutlich lief sie im
          falschen Projekt. Oben links im Supabase-Fenster steht, in welchem
          Du gerade bist.
        </p>
      </Karte>
    )
  }

  // Im Dashboard geht es nur ums Anbieten: Ist die Demo schon geladen (oder
  // der Stand noch nicht bekannt), soll dort gar nichts stehen — ein leerer
  // Kasten mit einer Überschrift wäre schlimmer als nichts. Im Demo-Modus
  // gilt das nicht: dort ist ein leerer Bildschirm ohne Erklärung das
  // Schlimmste, was passieren kann.
  if (kompakt) {
    if (geladen === false) return <Karte titel="Erst mal anschauen, wie es aussieht">{inhalt}</Karte>
    if (imDemoModus && geladen === null) {
      return (
        <Karte titel="Die Demo lädt noch — oder die Datenbank antwortet nicht">
          {fehler
            ? <Hinweis art="warnung">{fehler}</Hinweis>
            : <p className="leise">Einen Moment …</p>}
          <p className="leise">
            Bleibt das stehen, fehlt im Demo-Projekt die <code>setup.sql</code>
            {' '}(Teil B der Anleitung) — oder die Zugangsdaten zeigen auf ein
            Projekt, in dem noch nichts eingerichtet ist.
          </p>
        </Karte>
      )
    }
    return null
  }
  return <Karte titel="Demo-Daten">{inhalt}</Karte>
}
