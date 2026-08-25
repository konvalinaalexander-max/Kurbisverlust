import type { ReactNode } from 'react'

export function Lade({ text = 'Lädt …' }: { text?: string }) {
  return <div className="lade">{text}</div>
}

export function Hinweis({ art = 'info', children }: { art?: 'info' | 'warnung' | 'gut'; children: ReactNode }) {
  return <div className={`hinweis ${art === 'info' ? '' : art}`}>{children}</div>
}

export function Karte({ titel, aktion, children }: { titel?: ReactNode; aktion?: ReactNode; children: ReactNode }) {
  return (
    <section className="karte">
      {(titel || aktion) && (
        <div className="reihe" style={{ marginBottom: '.75rem' }}>
          {titel && <h2 style={{ margin: 0 }}>{titel}</h2>}
          {aktion && <div style={{ marginLeft: 'auto' }}>{aktion}</div>}
        </div>
      )}
      {children}
    </section>
  )
}

export function Kennzahl({ titel, wert, unter }: { titel: string; wert: ReactNode; unter?: ReactNode }) {
  return (
    <div>
      <div className="leise">{titel}</div>
      <div className="gross-zahl">{wert}</div>
      {unter && <div className="leise">{unter}</div>}
    </div>
  )
}

/**
 * Ein Verlustbalken mit dem Unsicherheitsbereich als Fehlerbalken darüber.
 * Der schraffierte Teil ist projiziert, der volle beobachtet — der Unterschied
 * zwischen „das haben wir gesehen" und „das rechnen wir hoch" muss sichtbar
 * bleiben, sonst wird aus einer Schätzung stillschweigend eine Messung.
 */
export function Balken({ wert, unten, oben, maximum, beobachtet }: {
  wert: number | null; unten: number | null; oben: number | null
  maximum: number; beobachtet?: number | null
}) {
  if (wert === null || maximum <= 0) return <div className="balken-spur" />
  const p = (n: number) => `${Math.max(0, Math.min(100, (n / maximum) * 100))}%`
  const beob = beobachtet ?? 0
  return (
    <div className="balken-spur">
      <div className="balken-fuellung projiziert" style={{ width: p(wert) }} />
      {beob > 0 && <div className="balken-fuellung" style={{ width: p(beob) }} />}
      {unten !== null && oben !== null && oben > unten && (
        <div className="balken-bereich"
             style={{ left: p(unten), width: `calc(${p(oben)} - ${p(unten)})` }} />
      )}
    </div>
  )
}

/**
 * Der aufklappbare Rechenweg (Spec §11, Ebene 3). Jede Zahl im Dashboard muss
 * sagen können, woher sie kommt — sonst ist das Werkzeug eine Blackbox und
 * der Betriebsleiter kann ihm nicht widersprechen.
 */
export function Rechenweg({ zeilen }: { zeilen: [string, ReactNode][] }) {
  return (
    <details className="rechenweg">
      <summary>Rechenweg</summary>
      <dl>
        {zeilen.map(([k, v], i) => (
          <div key={i} style={{ display: 'contents' }}>
            <dt>{k}</dt><dd>{v}</dd>
          </div>
        ))}
      </dl>
    </details>
  )
}

export function Marke({ art, children }: { art?: 'offen' | 'fertig' | 'warnung'; children: ReactNode }) {
  return <span className={`marke-klein ${art ?? ''}`}>{children}</span>
}
