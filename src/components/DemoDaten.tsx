import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
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
  const [geladen, setGeladen] = useState<boolean | null>(null)
  const [laeuft, setLaeuft] = useState<'laden' | 'entfernen' | 'neu' | null>(null)
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
    setLaeuft(null)
    if (error) { setFehler(fehlerText(error)); await stand(); return }
    setMeldung(data as string)
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
            Eine erfundene Saison, so gebaut, wie die Daten wirklich kommen: die 36
            Chargen der Anbauplanung mit halber Menge (rund 320 t, 840 Paletten), die
            Ernte je Charge über Tage und Wochen verteilt, gut 300 Arbeiten über beide
            Wege — Sortieren mit Sortier-CSV und gezählten Kisten, Waschen je Kaliber,
            Waschen + Sortieren von Hand mit gewogener Palette und gewogenem Ausschuss,
            Fax mit gezählten Kisten und gewogenem Faulem — dazu Lagerkontrollen,
            Lieferungen über Wochen verschränkt, und die Sonderfälle jeder Saison
            (abgebrochene Arbeit, Zahlendreher, vergessene Ablesung, Zetteldatum ohne
            Palette). Damit füllt sich jeder Bildschirm der App und man sieht, was am
            Ende herauskommt — bevor die erste echte Palette gezählt ist.
          </p>
          <p className="leise">
            Alles Erfundene ist markiert und lässt sich mit einem Klick restlos
            wieder entfernen. Echte Daten werden dabei nie angefasst — auch nicht,
            wenn schon welche da sind.
          </p>
          <button className="haupt" disabled={laeuft !== null}
                  onClick={() => void rufen('laden')}>
            {laeuft === 'laden' ? 'Saison wird angelegt …' : 'Demo-Saison laden'}
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
            {laeuft === 'neu' ? 'Saison wird neu angelegt …' : 'Demo-Saison neu laden'}
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
                {laeuft === 'entfernen' ? 'Wird entfernt …' : 'Ja, Demo-Daten löschen'}
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

  // Im Dashboard geht es nur ums Anbieten: Ist die Demo schon geladen (oder
  // der Stand noch nicht bekannt), soll dort gar nichts stehen — ein leerer
  // Kasten mit einer Überschrift wäre schlimmer als nichts.
  if (kompakt) {
    if (geladen !== false) return null
    return <Karte titel="Erst mal anschauen, wie es aussieht">{inhalt}</Karte>
  }
  return <Karte titel="Demo-Daten">{inhalt}</Karte>
}
