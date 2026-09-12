import { useState, type CSSProperties, type ReactNode, useLayoutEffect, useRef } from 'react'
import { ZChevron, ZHaken, ZInfo, ZWarnung } from './Zeichen'

/* =========================================================================
   Die Bausteine — jede Fläche der App ist aus ihnen gebaut.

   Die Klassen sind Verträge mit den Prüfständen: `.karte`, `.karte-kopf h2`,
   `.kennzahl` mit `.titel` / `.gross-zahl` / `.unter`, `.zahlenzeile > div`
   mit `.wert`, `.herkunft` — daran erntet pruefstand/beschriftung.mjs, ob
   jede Zahl sagt, was sie ist. Wer eine Klasse umbenennt, erntet nichts mehr
   und der Prüfstand wird blind, ohne rot zu werden.
   ========================================================================= */

/** Der Ladezustand: ein Skelett in der Form der kommenden Karte, kein Spinner. */
export function Lade({ text = 'Lädt …', zeilen = 3 }: { text?: string; zeilen?: number }) {
  return (
    <div className="lade" role="status" aria-label={text}>
      <div className="karte skelett-karte" aria-hidden="true">
        <div className="skelett" style={{ width: '38%', height: '1.1rem' }} />
        {Array.from({ length: zeilen }, (_, i) => (
          <div key={i} className="skelett" style={{ width: `${88 - i * 14}%`, height: '.85rem', marginTop: '.7rem' }} />
        ))}
      </div>
    </div>
  )
}

export function Hinweis({ art = 'info', children }: { art?: 'info' | 'warnung' | 'gut'; children: ReactNode }) {
  return (
    <div className={`hinweis ${art === 'info' ? '' : art}`} role={art === 'warnung' ? 'alert' : undefined}>
      <span className="hinweis-zeichen" aria-hidden="true">
        {art === 'warnung' ? <ZWarnung size={18} /> : art === 'gut' ? <ZHaken size={18} /> : <ZInfo size={18} />}
      </span>
      <div className="hinweis-text">{children}</div>
    </div>
  )
}

/**
 * Die Karte. `titel` und `aktion` bilden den Kopf; `unter` ist die eine Zeile
 * darunter, die sagt, was die Karte zeigt. Erklärender Text gehört nicht in
 * die Karte, sondern in eine `Erklaerung` — zu, bis man sie will.
 */
export function Karte({ titel, unter, aktion, klickbar, id, className, style, children }: {
  titel?: ReactNode; unter?: ReactNode; aktion?: ReactNode; klickbar?: boolean; id?: string; className?: string
  style?: CSSProperties; children: ReactNode
}) {
  return (
    <section id={id} className={`karte${klickbar ? ' klickbar' : ''}${className ? ` ${className}` : ''}`} style={style}>
      {(titel || aktion) && (
        <div className="karte-kopf">
          <div className="karte-titel">
            {titel && <h2>{titel}</h2>}
            {unter && <p className="karte-unter">{unter}</p>}
          </div>
          {aktion && <div className="aktion">{aktion}</div>}
        </div>
      )}
      {children}
    </section>
  )
}

/** Eine Kennzahl: Titel, grosse Zahl, ein Satz darunter. Als Kachel in einer Reihe. */
export function Kennzahl({ titel, wert, unter, ton }: { titel: ReactNode; wert: ReactNode; unter?: ReactNode; ton?: 'rot' | 'gruen' | 'kuerbis' }) {
  return (
    <div className={`kennzahl${ton ? ` ton-${ton}` : ''}`}>
      <div className="titel">{titel}</div>
      <div className="gross-zahl">{wert}</div>
      {unter && <div className="unter">{unter}</div>}
    </div>
  )
}

/**
 * Die Erklärung zu einer Karte — der Text, der sagt, wie die Zahlen
 * entstehen. Zu, bis jemand ihn will; der Prüfstand liest ihn trotzdem, denn
 * die Herkunft einer Zahl steht damit in ihrer Karte.
 */
export function Erklaerung({ titel = 'Wie diese Zahlen entstehen', children }: { titel?: string; children: ReactNode }) {
  return (
    <details className="erklaerung">
      <summary><ZInfo size={16} />{titel}</summary>
      <div className="erklaerung-text">{children}</div>
    </details>
  )
}

/** Der aufklappbare Rechenweg: jede Zahl im Dashboard sagt, woher sie kommt. */
export function Rechenweg({ zeilen }: { zeilen: [string, ReactNode][] }) {
  return (
    <details className="rechenweg">
      <summary><ZChevron size={14} />Rechenweg</summary>
      <dl>
        {zeilen.map(([k, v], i) => (
          <div key={i} style={{ display: 'contents' }}><dt>{k}</dt><dd>{v}</dd></div>
        ))}
      </dl>
    </details>
  )
}

export function Marke({ art, children, punkt = true }: { art?: 'offen' | 'fertig' | 'warnung' | 'neutral'; children: ReactNode; punkt?: boolean }) {
  return <span className={`marke-klein ${art ?? ''}${punkt ? '' : ' ohne-punkt'}`}>{children}</span>
}

/**
 * Die Herkunft einer Zahl, an jeder Zahl: gemessen (aus einer vollständigen
 * Liste), gerechnet (aus Stichproben hochgerechnet, bis heute) oder Prognose
 * (über heute hinaus). Wer das nicht sieht, hält eine Rechnung für eine Messung.
 */
export function Herkunft({ art, text }: { art: 'gemessen' | 'gerechnet' | 'prognose'; text?: string }) {
  // Mit Wortabstand davor: Wer den Text vorliest oder erntet, liest
  // „9.9 t gemessen" und nicht „9.9 tgemessen".
  return (
    <>{' '}<span className={`herkunft ${art}`}
          title={text ?? (art === 'gemessen' ? 'aus einer vollständigen Liste' : art === 'gerechnet' ? 'aus Stichproben hochgerechnet, bis heute' : 'über heute hinaus gerechnet')}>
      {art}
    </span></>
  )
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
      <summary><span className="chevron" aria-hidden="true"><ZChevron size={16} /></span><span className="aufklapp-titel">{titel}</span></summary>
      <div className="aufklapp-inhalt">{children}</div>
    </details>
  )
}

/**
 * Der Umschalter: gleich breite Segmente, der aktive gleitet. Ein Bedienelement,
 * nicht drei Knöpfe.
 */
export function Segmente<T extends string>({ wahl, setzen, teile, gross = false, id }: {
  wahl: T; setzen: (t: T) => void; teile: [T, ReactNode][]; gross?: boolean; id?: string
}) {
  const rahmen = useRef<HTMLDivElement>(null)
  // Der Schieber legt sich unter den aktiven Knopf — gemessen, nicht geraten:
  // die Knöpfe sind so breit wie ihr Wort, und „abgebrochen" ist länger als „alle".
  useLayoutEffect(() => {
    const el = rahmen.current
    if (!el) return
    const messen = () => {
      const aktiv = el.querySelector<HTMLButtonElement>('button.aktiv')
      if (!aktiv) return
      el.style.setProperty('--links', `${aktiv.offsetLeft}px`)
      el.style.setProperty('--breite', `${aktiv.offsetWidth}px`)
    }
    messen()
    window.addEventListener('resize', messen)
    return () => window.removeEventListener('resize', messen)
  }, [wahl, teile.length])
  return (
    <div id={id} ref={rahmen} className={`umschalter gleitend${gross ? ' gross' : ''}`} role="tablist">
      {teile.map(([t, name]) => (
        <button key={t} type="button" role="tab" aria-selected={wahl === t} className={wahl === t ? 'aktiv' : ''} onClick={() => setzen(t)}>{name}</button>
      ))}
    </div>
  )
}

/** Der leere Zustand: was fehlt und was der nächste Schritt ist. */
export function Leer({ titel, children, zeichen }: { titel: ReactNode; children?: ReactNode; zeichen?: ReactNode }) {
  return (
    <div className="leer">
      {zeichen && <div className="leer-zeichen" aria-hidden="true">{zeichen}</div>}
      <div className="leer-titel">{titel}</div>
      {children && <div className="leer-text">{children}</div>}
    </div>
  )
}

/** Der Farbpunkt einer Reihe oder eines Stroms. */
export function Punkt({ farbe }: { farbe: string }) {
  return <span className="chip" style={{ background: farbe }} aria-hidden="true" />
}

/** Ein Kreis mit Initialen — die Person an einer Arbeit. */
export function Avatar({ name, klein = false }: { name: string; klein?: boolean }) {
  const initialen = name.trim().split(/\s+/).slice(0, 2).map(t => t[0]?.toUpperCase() ?? '').join('')
  return <span className={`avatar${klein ? ' klein' : ''}`} title={name} aria-label={name}>{initialen || '?'}</span>
}

/** Ein Knopf, der kopiert, und kurz sagt, dass er es getan hat. */
export function useKurzMeldung(dauer = 1600): [string | null, (t: string) => void] {
  const [m, setM] = useState<string | null>(null)
  return [m, (t: string) => { setM(t); window.setTimeout(() => setM(null), dauer) }]
}
