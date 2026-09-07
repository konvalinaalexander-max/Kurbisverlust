import { kg, prozent, tonnen } from '../lib/format'

export interface Stapelteil { name: string; kg: number; farbe: string }
export interface Stapelzeile {
  name: string
  /** Bezugsmasse (Eingang) — für den Massstab „Prozent" und den Untertitel. */
  bezug: number
  teile: Stapelteil[]
  untertitel?: string
  /** Wohin ein Klick auf die Zeile führt (Link). */
  ziel?: string
}

/**
 * Gestapelte Balken je Zeile: eine Zeile je Sorte, Schlag oder Charge, die
 * Ursachen als Farbsegmente. Im Massstab „kg" sind alle Balken auf den
 * grössten bezogen; in „Prozent" auf die Bezugsmasse der Zeile — dann sieht
 * man, welche Sorte anteilig am meisten verliert, unabhängig von ihrer Grösse.
 * Reines HTML: kein Diagramm-Code, dafür überall lesbar und mit Tooltip.
 */
export function Stapelbalken({ zeilen, masstab, oeffnen }: {
  zeilen: Stapelzeile[]; masstab: 'kg' | 'prozent'; oeffnen?: (z: Stapelzeile) => void
}) {
  const summe = (z: Stapelzeile) => z.teile.reduce((s, t) => s + t.kg, 0)
  const maximum = Math.max(...zeilen.map(z => masstab === 'kg' ? summe(z) : (z.bezug > 0 ? summe(z) / z.bezug : 0)), 1e-9)
  if (zeilen.length === 0) return <p className="leise">nichts</p>
  return (
    <div className="stapel">
      {zeilen.map(z => {
        const ganz = summe(z)
        const breite = masstab === 'kg' ? ganz / maximum : (z.bezug > 0 ? (ganz / z.bezug) / maximum : 0)
        return (
          <div key={z.name} className={`stapel-zeile${oeffnen ? ' klickbar' : ''}`}
               onClick={oeffnen ? () => oeffnen(z) : undefined} role={oeffnen ? 'button' : undefined}
               tabIndex={oeffnen ? 0 : undefined}
               onKeyDown={oeffnen ? e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); oeffnen(z) } } : undefined}>
            <div className="reihe" style={{ fontSize: '.88rem', gap: '.4rem' }}>
              <strong>{z.name}</strong>
              {z.untertitel && <span className="leise">{z.untertitel}</span>}
              <span style={{ marginLeft: 'auto' }}>
                {masstab === 'kg' ? tonnen(ganz) : prozent(z.bezug > 0 ? ganz / z.bezug : null)}
                {masstab === 'kg' && z.bezug > 0 && <span className="leise"> · {prozent(ganz / z.bezug)}</span>}
              </span>
            </div>
            <div className="stapel-spur" style={{ width: `${Math.max(breite * 100, 0.5)}%` }}>
              {z.teile.filter(t => t.kg > 0).map(t => (
                <div key={t.name} className="stapel-teil" style={{ flex: t.kg, background: t.farbe }}
                     title={`${t.name}: ${kg(t.kg, 0)}${z.bezug > 0 ? ` (${prozent(t.kg / z.bezug)} des Eingangs)` : ''}`} />
              ))}
            </div>
          </div>
        )
      })}
    </div>
  )
}

/** Die Legende zu den Farben — einmal je Karte, nicht je Zeile. */
export function Stapellegende({ teile }: { teile: { name: string; farbe: string }[] }) {
  return (
    <div className="reihe" style={{ gap: '.9rem', fontSize: '.82rem', marginTop: '.4rem' }}>
      {teile.map(t => (
        <span key={t.name} className="reihe" style={{ gap: '.3rem' }}>
          <span aria-hidden="true" style={{ width: 10, height: 10, borderRadius: 2, background: t.farbe, display: 'inline-block' }} />
          {t.name}
        </span>
      ))}
    </div>
  )
}
