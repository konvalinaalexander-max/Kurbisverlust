import { useEffect, useState } from 'react'
import { datum } from '../lib/format'

/** Wie weit „in X Wochen" reicht — die Prognose geht bis zum Saisonende. */
export const WOCHEN_MAX = 28

/** Das Feld „in X Wochen" — ein Zustand, zwei Felder (Tabelle und Glocke). */
export function WochenFeld({ id, wochen, setzen, datum: stichtag }: {
  id: string; wochen: number; setzen: (n: number) => void; datum?: string | null
}) {
  const [text, setText] = useState(String(wochen))
  useEffect(() => { setText(String(wochen)) }, [wochen])
  // Erst nach einer kurzen Pause übernehmen: Wer „12" tippt, soll nicht bei
  // „1" einen Aufruf auslösen.
  useEffect(() => {
    const n = Number(text)
    if (!Number.isFinite(n) || n < 0 || n > WOCHEN_MAX || n === wochen) return
    const uhr = setTimeout(() => setzen(Math.round(n)), 300)
    return () => clearTimeout(uhr)
  }, [text, wochen, setzen])
  // Runde AD: 0 ist erlaubt und die Grundeinstellung — „heute".
  const gueltig = Number(text) >= 0 && Number(text) <= WOCHEN_MAX
  return (
    <span className="wochenfeld">
      <label htmlFor={id}>in</label>
      <input id={id} type="number" inputMode="numeric" min={0} max={WOCHEN_MAX} step={1}
             value={text} aria-invalid={!gueltig} onChange={e => setText(e.target.value)} />
      <span>Wochen{wochen === 0 ? <span className="leise"> · heute</span> : stichtag ? <span className="leise"> · {datum(stichtag).slice(0, 6)}</span> : null}</span>
    </span>
  )
}

