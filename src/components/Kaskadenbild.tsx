import type { ReactNode } from 'react'
import { Herkunft } from './Bausteine'

/**
 * Bilanzzeile: Name, Zahl, Balken, Erklärung — die Zeilen der Karte „Geht die
 * Rechnung auf?" (Messungen). Jede Zeile trägt ihre Herkunft: gemessen oder
 * gerechnet. Die Klasse `.bilanzzeile` mit `.name` ist der Vertrag mit
 * pruefstand/beschriftung.mjs.
 */
export function Bilanzzeile({ titel, kg, eingang, farbe, erklaerung, herkunft }: {
  /** kg = null heisst „nicht gemessen" (0064): kein Balken, kein Anteil, ein „—". */
  titel: string; kg: number | null; eingang: number; farbe: string; erklaerung?: ReactNode
  herkunft?: 'gemessen' | 'gerechnet' | 'prognose'
}) {
  const anteil = kg !== null && eingang > 0 ? Math.max(kg, 0) / eingang : null
  return (
    <div className="bilanzzeile">
      <div className="bilanz-kopf">
        <span className="name">{titel} {herkunft && <Herkunft art={herkunft} />}</span>
        <span className="bilanz-wert">
          {kg === null ? <span className="leise">nicht gemessen</span> : <>{(kg / 1000).toFixed(1)} t</>}
          {anteil !== null && <span className="leise"> · {(anteil * 100).toFixed(1)} %</span>}
        </span>
      </div>
      <div className="balken-spur">
        <div className="balken-fuellung waechst" style={{ width: `${Math.min((anteil ?? 0) * 100, 100)}%`, background: farbe }} />
      </div>
      {erklaerung && <p className="fussnote">{erklaerung}</p>}
    </div>
  )
}
