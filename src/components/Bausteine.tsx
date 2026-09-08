import type { ReactNode } from 'react'

export function Lade({ text = 'Lädt …' }: { text?: string }) {
  return <div className="lade">{text}</div>
}

export function Hinweis({ art = 'info', children }: { art?: 'info' | 'warnung' | 'gut'; children: ReactNode }) {
  return (
    <div className={`hinweis ${art === 'info' ? '' : art}`}
         role={art === 'warnung' ? 'alert' : undefined}>
      {children}
    </div>
  )
}

export function Karte({ titel, aktion, children }: { titel?: ReactNode; aktion?: ReactNode; children: ReactNode }) {
  return (
    <section className="karte">
      {(titel || aktion) && (
        <div className="karte-kopf">
          {titel && <h2>{titel}</h2>}
          {aktion && <div className="aktion">{aktion}</div>}
        </div>
      )}
      {children}
    </section>
  )
}

export function Kennzahl({ titel, wert, unter }: { titel: string; wert: ReactNode; unter?: ReactNode }) {
  return (
    <div className="kennzahl">
      <div className="titel">{titel}</div>
      <div className="gross-zahl">{wert}</div>
      {unter && <div className="unter">{unter}</div>}
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

/**
 * Die Herkunft einer Zahl, an jeder Zahl (Runde H): gemessen (aus einer
 * vollständigen Liste: Erntejournal, Lieferscheine, Verkaufsdatei),
 * gerechnet (aus Stichproben hochgerechnet, bis heute) oder Prognose (über
 * heute hinaus). Wer das nicht sieht, hält eine Rechnung für eine Messung.
 */
export function Herkunft({ art, text }: { art: 'gemessen' | 'gerechnet' | 'prognose'; text?: string }) {
  return <span className={`herkunft ${art}`} title={text ?? (art === 'gemessen' ? 'aus einer vollständigen Liste' : art === 'gerechnet' ? 'aus Stichproben hochgerechnet, bis heute' : 'über heute hinaus gerechnet')}>{art}</span>
}

/** Eine Zeile grosser Zahlen mit Titel und Untertitel — die Kopfzahlen einer Ursache. */
export function Zahlen({ zeilen }: { zeilen: { titel: ReactNode; wert: ReactNode; unter?: ReactNode }[] }) {
  return (
    <div className="zahlenzeile">
      {zeilen.map((z, i) => (
        <div key={i}>
          <div className="titel">{z.titel}</div>
          <div className="wert">{z.wert}</div>
          {z.unter && <div className="unter">{z.unter}</div>}
        </div>
      ))}
    </div>
  )
}

/** Aufklappbar — eine lange Liste, die zu ist, bis man sie will. */
export function Aufklapp({ titel, offen = false, children }: { titel: ReactNode; offen?: boolean; children: ReactNode }) {
  return (
    <details className="aufklapp" open={offen}>
      <summary>{titel}</summary>
      {children}
    </details>
  )
}
