/**
 * Der Lager-Ausweis als Bild und als Rechnung (0121) — an jeder Stelle
 * dasselbe: eine schmale Leiste (so lang wie die Ware auf den Paletten, wie
 * sie einging; rechts, was wegging; links, was verkaufsfähig bleibt) und
 * darunter die Rechnung Schritt für Schritt, wie ein Kassenzettel.
 */
import { Fragment, type ReactNode } from 'react'
import { kg, prozent } from '../lib/format'
import { palettenText } from './lager'
import type { AusweisSumme, Schritt } from './ausweis'
import { schritte } from './ausweis'

/** Die Leiste: verkaufsfähig links, dann Unique, zu klein / zu gross, Faules, Verdunstetes. */
export function LagerLeiste({ s, dick = false, titel }: { s: AusweisSumme; dick?: boolean; titel?: string }) {
  const st = schritte(s, false)
  if (st.length < 2) return null
  const teile = [...st.filter(x => x.art === 'ergebnis'), ...st.filter(x => x.art !== 'start' && x.art !== 'ergebnis' && x.art !== 'davon')]
  const ganz = Math.max(s.eingang, 1)
  return (
    <span className={`lager-leiste${dick ? ' dick' : ''}`} role="img"
          aria-label={titel ?? teile.map(t => `${t.name} ${kg(t.kg, 0)}`).join(', ')}
          title={titel ?? teile.map(t => `${t.name}: ${kg(t.kg, 0)}`).join(' · ')}>
      {teile.filter(t => t.kg > 0).map(t => (
        <span key={t.name} style={{ width: `${(t.kg / ganz) * 100}%`, background: t.farbe }} />
      ))}
    </span>
  )
}

const ZEICHEN: Record<Schritt['art'], string> = { start: '', weg: '−', aussortiert: '−', unique: '−', ergebnis: '=', davon: '' }

/**
 * Die Rechnung: auf den Paletten − … = verkaufsfähig, mit einem Halbsatz je
 * Schritt. Eine Begriffsliste, kein Tabellenraster: Jede Zahl gehört zu
 * ihrem Namen (dt), der Halbsatz darunter auch — so liest es ein Mensch, ein
 * Screenreader und pruefstand/beschriftung.mjs. Das Rechenzeichen steht nur
 * im Bild (CSS), nicht im Text.
 */
export function LagerRechnung({ s, kopf, fuss }: { s: AusweisSumme; kopf?: ReactNode; fuss?: ReactNode }) {
  const st = schritte(s)
  if (st.length === 0) return null
  return (
    <div className="lager-rechnung">
      {kopf}
      <LagerLeiste s={s} dick />
      <dl className="kette">
        {st.map(x => (
          <Fragment key={x.name}>
            <dt className={`kette-${x.art}`} data-zeichen={ZEICHEN[x.art]}>
              {x.art !== 'start' && x.art !== 'davon' && <span className="chip" style={{ background: x.farbe }} />}
              {x.art === 'start' ? <>{palettenText(s.paletten) || 'Paletten'} im Lager — darauf lagen beim Eingang</> : x.name}
            </dt>
            <dd className={`kette-${x.art} kette-kg`}>{kg(x.kg, 0)}</dd>
            <dd className={`kette-${x.art} kette-anteil`}>{x.art === 'ergebnis' && s.eingang > 0 ? prozent(x.kg / s.eingang, 0) : ''}</dd>
            {x.wie && <dd className={`kette-${x.art} kette-wie`}>{x.wie}</dd>}
          </Fragment>
        ))}
      </dl>
      {s.luecken > 0 && (
        <p className="leise unten-0">{s.luecken === s.n ? 'Verkaufsfähig ist noch unbekannt' : `${s.luecken} von ${s.n} Chargen fehlen in den Abzügen`} —
          eine Rate ist nicht gemessen (Messungen → Ausstehend).</p>
      )}
      {!s.margeBekannt && s.luecken < s.n && <p className="leise unten-0">Die Überfüllung in den Kisten ist nicht für alle Chargen gewogen — darum ohne Marge.</p>}
      {fuss}
    </div>
  )
}
