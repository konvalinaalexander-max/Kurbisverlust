import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { useAuth } from '../auth/AuthProvider'

/** Welche Messung von Hand aus der Rechnung genommen werden kann (messung_ausschluss, 0116). */
export interface Ausschluss { art: 'palox' | 'palox_lager' | 'verdunstung'; bezugId: number; aus: boolean }

/**
 * „Benutzen" — ein Kästchen im Fenster einer Messung (Runde AS). Der Betrieb:
 * „ein Feld zum Anklicken, benutzen oder nicht benutzen … damit ich Ausreisser
 * rausnehmen kann." Nicht benutzt heisst: Die Messung steht weiter im Bild,
 * zählt aber in keine Rate — ab der nächsten Rechnung. Nur der Betriebsleiter
 * kann es ändern; alle anderen sehen, wie es steht.
 */
export function Benutzen({ ausschluss }: { ausschluss: Ausschluss }) {
  const { istAdmin } = useAuth()
  const [aus, setAus] = useState(ausschluss.aus)
  const [geaendert, setGeaendert] = useState(false)
  const [laeuft, setLaeuft] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  async function setzen(benutzen: boolean) {
    // Gleich umstellen, bei einem Fehler zurück — das Kästchen soll nicht auf die Antwort warten.
    const vorher = aus
    setAus(!benutzen); setLaeuft(true); setFehler(null)
    const r = benutzen
      ? await supabase.from('messung_ausschluss').delete().match({ art: ausschluss.art, bezug_id: ausschluss.bezugId })
      : await supabase.from('messung_ausschluss').upsert({ art: ausschluss.art, bezug_id: ausschluss.bezugId, grund: 'von Hand ausgeschlossen' },
                                                          { onConflict: 'art,bezug_id' })
    setLaeuft(false)
    if (r.error) { setAus(vorher); setFehler(fehlerText(r.error)); return }
    setGeaendert(true)
  }
  return (
    <div className="benutzen" id="messung-benutzen">
      <label>
        <input type="checkbox" checked={!aus} disabled={!istAdmin} onChange={e => { if (!laeuft) void setzen(e.target.checked) }} />
        {' '}Diese Messung benutzen
      </label>
      {aus && !geaendert && <span className="leise"> — von Hand ausgeschlossen: steht im Bild, zählt in keine Rate.</span>}
      {geaendert && <span className="leise"> — {aus ? 'ausgeschlossen' : 'wieder dabei'}; gilt ab der nächsten Rechnung („Neu rechnen" oben oder heute Nacht).</span>}
      {fehler && <span className="fehler-text"> {fehler}</span>}
    </div>
  )
}
