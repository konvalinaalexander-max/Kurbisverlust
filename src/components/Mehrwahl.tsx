import { useEffect, useRef, useState, type ReactNode } from 'react'
import { ZChevron } from './Zeichen'

/**
 * Ein Auswahlfeld, in dem man mehreres anklickt (Runde BL, für die
 * KW-Planung): „dass man ganze Kategorien anklicken kann oder nur einzelne
 * Kunden innerhalb der Kategorien — dass man da völlige Freiheit hat."
 *
 * Ein Knopf, der sagt, was gewählt ist; darunter die Liste mit Häkchen. Eine
 * Gruppe hat eine Überschrift — ist sie selbst wählbar (`wahl`), meint ihr
 * Häkchen die ganze Gruppe als eine Sache, unabhängig von den Häkchen
 * darunter. Schliesst mit Escape und mit einem Klick daneben.
 */
export interface MehrwahlEintrag { schluessel: string; name: ReactNode; unter?: ReactNode }
export interface MehrwahlGruppe {
  titel?: string
  /** Der Schlüssel, wenn die Überschrift selbst wählbar ist; `wahlText` sagt daneben, was sie meint. */
  wahl?: string; wahlText?: ReactNode
  eintraege: MehrwahlEintrag[]
}

export function Mehrwahl({ id, name, text, gewaehlt, setzen, gruppen, kurzwahl }: {
  id: string
  /** wofür das Feld ist — für Vorleser und als Titel der Liste */
  name: string
  /** was auf dem Knopf steht: die Auswahl in Worten */
  text: ReactNode
  gewaehlt: ReadonlySet<string>
  setzen: (neu: Set<string>) => void
  gruppen: MehrwahlGruppe[]
  /** Knöpfe über der Liste: „alle", „keine", „die letzten vier" */
  kurzwahl?: { name: string; wahl: () => Iterable<string>; id?: string }[]
}) {
  const [offen, setOffen] = useState(false)
  const rahmen = useRef<HTMLDivElement>(null)
  const knopf = useRef<HTMLButtonElement>(null)
  useEffect(() => {
    if (!offen) return
    const daneben = (e: PointerEvent) => { if (rahmen.current && !rahmen.current.contains(e.target as Node)) setOffen(false) }
    const taste = (e: KeyboardEvent) => { if (e.key === 'Escape') { setOffen(false); knopf.current?.focus() } }
    document.addEventListener('pointerdown', daneben)
    document.addEventListener('keydown', taste)
    return () => { document.removeEventListener('pointerdown', daneben); document.removeEventListener('keydown', taste) }
  }, [offen])
  const umschalten = (s: string) => { const n = new Set(gewaehlt); if (n.has(s)) n.delete(s); else n.add(s); setzen(n) }
  return (
    <div className={`mehrwahl${offen ? ' offen' : ''}`} ref={rahmen}>
      <button type="button" ref={knopf} id={id} className="mehrwahl-knopf" aria-haspopup="true" aria-expanded={offen}
              aria-controls={`${id}-liste`} onClick={() => setOffen(o => !o)}>
        <span className="mehrwahl-text">{text}</span>
        <ZChevron />
      </button>
      {offen && (
        <div className="mehrwahl-feld" id={`${id}-liste`} role="group" aria-label={name}>
          {kurzwahl && kurzwahl.length > 0 && (
            <div className="mehrwahl-kurz">
              {kurzwahl.map(k => (
                <button key={k.name} type="button" className="klein" id={k.id} onClick={() => setzen(new Set(k.wahl()))}>{k.name}</button>
              ))}
            </div>
          )}
          <div className="mehrwahl-liste">
            {gruppen.map((g, i) => (
              <div key={g.titel ?? i} className="mehrwahl-gruppe">
                {g.titel && (g.wahl
                  ? <label className="mehrwahl-zeile mehrwahl-kopf">
                      <input type="checkbox" checked={gewaehlt.has(g.wahl)} onChange={() => umschalten(g.wahl!)} />
                      <span className="mehrwahl-name">{g.titel}</span>
                      {g.wahlText && <span className="mehrwahl-unter">{g.wahlText}</span>}
                    </label>
                  : <p className="mehrwahl-kopf mehrwahl-titel">{g.titel}</p>)}
                {g.eintraege.map(e => (
                  <label key={e.schluessel} className={`mehrwahl-zeile${g.titel ? ' eingerueckt' : ''}`}>
                    <input type="checkbox" checked={gewaehlt.has(e.schluessel)} onChange={() => umschalten(e.schluessel)} />
                    <span className="mehrwahl-name">{e.name}</span>
                    {e.unter && <span className="mehrwahl-unter">{e.unter}</span>}
                  </label>
                ))}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
