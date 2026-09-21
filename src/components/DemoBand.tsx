import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { demoVerlassen } from '../lib/demo'
import { SCHRITTE, auswertungVergessen } from '../auswertung/daten'

/**
 * Das Band, das in der Demo immer oben steht.
 *
 * Es hat drei Aufgaben, und zwar in dieser Reihenfolge:
 *
 *   1. Sagen, wo man ist. Die Demo sieht aus wie der Betrieb — das ist ja
 *      der Sinn. Genau deshalb muss auf jedem Bildschirm stehen, dass diese
 *      Zahlen erfunden sind. Nicht als Hinweis, den man wegklickt.
 *   2. Zurück lassen. Wer die Demo angeschaut hat, will zur Anmeldung des
 *      Betriebs zurück, ohne zu wissen, was ein localStorage ist.
 *   3. Aufräumen lassen. In der Demo darf jeder alles anfassen. Nach ein paar
 *      Besuchern steht dort Unsinn. „Demo zurücksetzen" baut die Saison neu
 *      auf — dieselbe wie am ersten Tag, denn sie ist reproduzierbar (0081).
 *
 * Gerechnet wird nach dem Neuaufbau in denselben fünf Schritten wie überall
 * sonst: ein einzelner API-Aufruf hat bei Supabase acht Sekunden, und das
 * Rechnen ist der teuerste Teil.
 */
export default function DemoBand() {
  const [frage, setFrage] = useState(false)
  const [schritt, setSchritt] = useState<number | null>(null)
  const [laeuft, setLaeuft] = useState<'bauen' | 'rechnen' | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)

  async function zuruecksetzen() {
    setFrage(false); setFehler(null); setLaeuft('bauen'); setSchritt(null)
    const weg = await supabase.rpc('demo_daten_entfernen')
    if (weg.error) { setLaeuft(null); setFehler(fehlerText(weg.error)); return }
    const neu = await supabase.rpc('demo_daten_laden')
    if (neu.error) { setLaeuft(null); setFehler(fehlerText(neu.error)); return }
    setLaeuft('rechnen')
    for (let i = 1; i <= SCHRITTE.length; i++) {
      setSchritt(i)
      const r = await supabase.rpc('auswertung_schritt', { p_schritt: i })
      if (r.error) {
        setLaeuft(null); setSchritt(null)
        setFehler(`Schritt ${i} von ${SCHRITTE.length} (${SCHRITTE[i - 1]}): ${fehlerText(r.error)}`)
        return
      }
    }
    auswertungVergessen()
    // Neu laden statt Zustand einsammeln: Nach einem kompletten Neuaufbau
    // zeigt jede offene Liste im Speicher auf Zeilen, die es nicht mehr gibt.
    window.location.assign('/')
  }

  if (laeuft) {
    return (
      <div className="beispiel-band demo kein-druck" role="status">
        {laeuft === 'bauen'
          ? 'Demo wird neu aufgebaut …'
          : `Auswertung wird gerechnet … Schritt ${schritt ?? 1} von ${SCHRITTE.length}`}
      </div>
    )
  }

  return (
    <div className="beispiel-band demo kein-druck" role="status">
      {fehler
        ? <span>Das Zurücksetzen ging schief: {fehler}</span>
        : <span>Demo — erfundene Daten, nicht der Betrieb</span>}
      {frage ? (
        <>
          <button type="button" className="band-knopf" onClick={() => void zuruecksetzen()}>
            Ja, neu aufbauen
          </button>
          <button type="button" className="band-knopf" onClick={() => setFrage(false)}>
            doch nicht
          </button>
        </>
      ) : (
        <button type="button" className="band-knopf" onClick={() => setFrage(true)}>
          Demo zurücksetzen
        </button>
      )}
      <button type="button" className="band-knopf" onClick={demoVerlassen}>
        Demo verlassen
      </button>
    </div>
  )
}
