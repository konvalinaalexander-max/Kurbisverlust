import { useEffect, useRef, useState } from 'react'
import { ZKreuz } from '../components/Zeichen'
import { ChargeFenster } from './ChargeFenster'
import { MessungKasten } from './ArbeitFenster'

/** Was ein Punkt im Diagramm über seine Messung weiss — Zeile für Zeile, und seine Kernzahl. */
export interface PunktInfo { titel: string; name: string; zeilen: string[]; chargeNr?: number; kern?: { wert: string; unter?: string } }

/**
 * Die Messung hinter einem Punkt, der zu keiner Arbeit gehört (Runde Z) —
 * eine Kontrollpalette etwa, die ohne Arbeit gewogen wurde. Der Betrieb:
 * „wenn ich auf einen Punkt klicke, der eine Messung ist, soll im Pop-up
 * die Messung kommen." Hat der Punkt eine Arbeit, öffnet sich statt dessen
 * das Arbeitsfenster mit der Messung voran.
 */
export function MessungFenster({ info, schliessen }: { info: PunktInfo; schliessen: () => void }) {
  const [charge, setCharge] = useState<number | null>(null)
  const kindOffen = useRef(false)
  kindOffen.current = charge !== null
  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape' && !kindOffen.current) schliessen() }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [schliessen])
  return (
    <div className="dialog-hinter" onClick={schliessen}>
      <div className="dialog" role="dialog" aria-modal="true" aria-label="Messung" id="messung-fenster" onClick={e => e.stopPropagation()}>
        <div className="fenster-kopf">
          <div>
            <h2>{info.titel}</h2>
            <p className="leise" style={{ margin: '.2rem 0 0' }}>{info.name}</p>
          </div>
          <button type="button" className="klein schliessen" onClick={schliessen} aria-label="schliessen"><ZKreuz size={16} /></button>
        </div>
        <MessungKasten messung={{ titel: 'Die Messung', name: info.name, zeilen: info.zeilen, kern: info.kern }}
                       fuss={<p className="leise" style={{ margin: '.5rem 0 0' }}>Diese Messung gehört zu keiner Arbeit — eine Kontrollwägung im Lager.</p>} />
        {info.chargeNr != null && (
          <div className="knopf-reihe" style={{ marginTop: 'var(--a-4)' }}>
            <button type="button" className="knopf" onClick={() => setCharge(info.chargeNr!)}>Charge {info.chargeNr} ansehen</button>
          </div>
        )}
      </div>
      {charge !== null && <div onClick={e => e.stopPropagation()}><ChargeFenster chargeNr={charge} schliessen={() => setCharge(null)} /></div>}
    </div>
  )
}
