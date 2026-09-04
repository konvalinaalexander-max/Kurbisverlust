import { useMemo, useState, type ReactNode } from 'react'

/**
 * Diagramme von Hand als SVG — Linien, Punkte, Bereiche, Histogramm.
 *
 * Regeln (docs/UI-KONZEPT.md, Datenvisualisierung): eine Achse je Grösse,
 * dünne Marken (2 px Linien, 8 px Punkte), zurückhaltendes Gitter, Farben nur
 * als Kennung der Reihe (die Strom-Farben aus index.css), Text immer in
 * Textfarbe. Ab zwei Reihen eine Legende, und jedes Diagramm hat seine
 * Tabelle — wer die Zahl will, bekommt sie, wer die Form will, die Form.
 * Hover zeigt den nächsten Punkt mit seinem Wert.
 */
export interface Punkt { x: number; y: number; text?: string }
export interface Reihe {
  name: string
  farbe: string
  punkte: Punkt[]
  /** Linie zwischen den Punkten (Zeitreihe, Kurve) — sonst nur Marker. */
  linie?: boolean
  /** Marker an den Punkten (Messwerte). */
  marker?: boolean
  /** Unsicherheitsband: je Punkt unten/oben. */
  band?: { x: number; unten: number; oben: number }[]
  gestrichelt?: boolean
}

const B = 720, L = 52, R = 14, O = 14, U = 34

function schoen(min: number, max: number, n = 5): number[] {
  if (!(max > min)) return [min]
  const roh = (max - min) / n
  const p = Math.pow(10, Math.floor(Math.log10(roh)))
  const f = roh / p
  const schritt = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p
  const von = Math.floor(min / schritt) * schritt
  const ticks: number[] = []
  for (let t = von; t <= max + schritt * 0.001; t += schritt) ticks.push(Number(t.toFixed(10)))
  return ticks
}

export function Diagramm({ reihen, hoehe = 260, xFormat = String, yFormat = String, xTitel, yTitel,
                           yVon, yBis, xVon, xBis, senkrechte = [], leer = 'keine Messung' }: {
  reihen: Reihe[]; hoehe?: number
  xFormat?: (x: number) => string; yFormat?: (y: number) => string
  xTitel?: string; yTitel?: string
  yVon?: number; yBis?: number; xVon?: number; xBis?: number
  /** Senkrechte Hilfslinien mit Beschriftung (etwa Kalibergrenzen). */
  senkrechte?: { x: number; text: string }[]
  leer?: string
}) {
  const [hover, setHover] = useState<{ reihe: Reihe; p: Punkt; px: number; py: number } | null>(null)
  const [tabelle, setTabelle] = useState(false)
  const alle = reihen.flatMap(r => r.punkte)
  const bandwerte = reihen.flatMap(r => r.band ?? [])

  const { y0, sx, sy, xt, yt } = useMemo(() => {
    const xs = alle.map(p => p.x).concat(senkrechte.map(s => s.x))
    const ys = alle.map(p => p.y).concat(bandwerte.flatMap(b => [b.unten, b.oben]))
    const x0 = xVon ?? Math.min(...xs), x1 = xBis ?? Math.max(...xs)
    const y0 = yVon ?? Math.min(0, ...ys), y1 = yBis ?? Math.max(...ys)
    const yt = schoen(y0, y1)
    const yMax = Math.max(y1, yt[yt.length - 1]), yMin = Math.min(y0, yt[0])
    const xt = schoen(x0, x1, 6).filter(t => t >= x0 && t <= x1)
    const sx = (x: number) => L + (x1 > x0 ? (x - x0) / (x1 - x0) : 0.5) * (B - L - R)
    const sy = (y: number) => hoehe - U - (yMax > yMin ? (y - yMin) / (yMax - yMin) : 0.5) * (hoehe - O - U)
    return { x0, x1, y0: yMin, y1: yMax, sx, sy, xt, yt }
  }, [alle, bandwerte, senkrechte, xVon, xBis, yVon, yBis, hoehe])

  if (alle.length === 0) return <p className="leise">{leer}</p>

  function bewegung(e: React.MouseEvent<SVGSVGElement>) {
    const box = e.currentTarget.getBoundingClientRect()
    const mx = ((e.clientX - box.left) / box.width) * B
    const my = ((e.clientY - box.top) / box.height) * hoehe
    let best: typeof hover = null, bestD = 1e12
    for (const r of reihen) for (const p of r.punkte) {
      const dx = sx(p.x) - mx, dy = sy(p.y) - my
      const d = dx * dx + (r.linie && !r.marker ? 0 : dy * dy)
      if (d < bestD) { bestD = d; best = { reihe: r, p, px: sx(p.x), py: sy(p.y) } }
    }
    setHover(best)
  }

  const pfad = (r: Reihe) => r.punkte.slice().sort((a, b) => a.x - b.x)
    .map((p, i) => `${i ? 'L' : 'M'} ${sx(p.x).toFixed(1)} ${sy(p.y).toFixed(1)}`).join(' ')
  const bandPfad = (r: Reihe) => {
    const b = (r.band ?? []).slice().sort((a, c) => a.x - c.x)
    if (b.length < 2) return ''
    return b.map((q, i) => `${i ? 'L' : 'M'} ${sx(q.x).toFixed(1)} ${sy(q.oben).toFixed(1)}`).join(' ')
      + ' ' + b.slice().reverse().map(q => `L ${sx(q.x).toFixed(1)} ${sy(q.unten).toFixed(1)}`).join(' ') + ' Z'
  }

  return (
    <div className="diagramm">
      <div className="rollbar">
        <svg viewBox={`0 0 ${B} ${hoehe}`} style={{ width: '100%', minWidth: 420, height: 'auto', display: 'block' }}
             role="img" aria-label={yTitel ?? ''} onMouseMove={bewegung} onMouseLeave={() => setHover(null)}>
          {yt.map(t => (
            <g key={`y${t}`}>
              <line x1={L} x2={B - R} y1={sy(t)} y2={sy(t)} stroke="var(--rand-leise)" strokeWidth="1" />
              <text x={L - 6} y={sy(t) + 4} fontSize="11" textAnchor="end" fill="var(--text-leise)">{yFormat(t)}</text>
            </g>
          ))}
          {xt.map(t => (
            <text key={`x${t}`} x={sx(t)} y={hoehe - U + 16} fontSize="11" textAnchor="middle" fill="var(--text-leise)">{xFormat(t)}</text>
          ))}
          <line x1={L} x2={B - R} y1={sy(Math.max(y0, 0))} y2={sy(Math.max(y0, 0))} stroke="var(--rand)" strokeWidth="1" />
          {xTitel && <text x={B - R} y={hoehe - 4} fontSize="11" textAnchor="end" fill="var(--text-leise)">{xTitel}</text>}
          {yTitel && <text x={L} y={10} fontSize="11" fill="var(--text-leise)">{yTitel}</text>}
          {senkrechte.map(s => (
            <g key={`s${s.x}`}>
              <line x1={sx(s.x)} x2={sx(s.x)} y1={O} y2={hoehe - U} stroke="var(--text-leise)" strokeWidth="1" strokeDasharray="3 4" opacity=".7" />
              <text x={sx(s.x) + 3} y={O + 10} fontSize="10" fill="var(--text-leise)">{s.text}</text>
            </g>
          ))}
          {reihen.map(r => r.band && r.band.length > 1 && (
            <path key={`b${r.name}`} d={bandPfad(r)} fill={r.farbe} opacity=".16" />
          ))}
          {reihen.map(r => r.linie && r.punkte.length > 1 && (
            <path key={`l${r.name}`} d={pfad(r)} fill="none" stroke={r.farbe} strokeWidth="2"
                  strokeLinejoin="round" strokeDasharray={r.gestrichelt ? '5 5' : undefined} />
          ))}
          {reihen.map(r => (r.marker ?? !r.linie) && r.punkte.map((p, i) => (
            <circle key={`${r.name}${i}`} cx={sx(p.x)} cy={sy(p.y)} r="4" fill={r.farbe}
                    stroke="var(--flaeche)" strokeWidth="1.5" />
          )))}
          {hover && (
            <g>
              <line x1={hover.px} x2={hover.px} y1={O} y2={hoehe - U} stroke="var(--text)" strokeWidth="1" opacity=".35" />
              <circle cx={hover.px} cy={hover.py} r="6" fill="none" stroke={hover.reihe.farbe} strokeWidth="2" />
            </g>
          )}
        </svg>
      </div>
      {hover && (
        <div className="diagramm-tip">
          <span className="chip" style={{ background: hover.reihe.farbe }} />
          <strong>{hover.reihe.name}</strong> · {xFormat(hover.p.x)}{xTitel ? ` ${xTitel}` : ''} → {yFormat(hover.p.y)}
          {hover.p.text && <span className="leise"> · {hover.p.text}</span>}
        </div>
      )}
      {reihen.length > 1 && (
        <div className="legende">
          {reihen.map(r => <span key={r.name}><span className="chip" style={{ background: r.farbe }} />{r.name}</span>)}
        </div>
      )}
      <button className="blank klein" onClick={() => setTabelle(t => !t)}>{tabelle ? 'Tabelle ausblenden' : 'Als Tabelle'}</button>
      {tabelle && (
        <div className="rollbar">
          <table>
            <thead><tr><th>Reihe</th><th className="zahl">{xTitel ?? 'x'}</th><th className="zahl">{yTitel ?? 'y'}</th><th></th></tr></thead>
            <tbody>
              {reihen.flatMap(r => r.punkte.slice().sort((a, b) => a.x - b.x).map((p, i) => (
                <tr key={`${r.name}${i}`}><td>{r.name}</td><td className="zahl">{xFormat(p.x)}</td>
                  <td className="zahl">{yFormat(p.y)}</td><td className="leise">{p.text ?? ''}</td></tr>
              )))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

/** Histogramm mit Hilfslinien — die Gewichtsverteilung mit ihren Kalibergrenzen. */
export function Histogramm({ stufen, breite, grenzen = [], farbe = 'var(--kuerbis)', hoehe = 220,
                             xFormat = String, titel }: {
  stufen: { x: number; n: number }[]; breite: number
  grenzen?: { x: number; text: string }[]; farbe?: string; hoehe?: number
  xFormat?: (x: number) => string; titel?: ReactNode
}) {
  const [hover, setHover] = useState<{ x: number; n: number } | null>(null)
  if (stufen.length === 0) return <p className="leise">keine Sortier-CSV eingelesen</p>
  const x0 = Math.min(...stufen.map(s => s.x)), x1 = Math.max(...stufen.map(s => s.x)) + breite
  const nMax = Math.max(...stufen.map(s => s.n), 1)
  const gesamt = stufen.reduce((a, s) => a + s.n, 0)
  const sx = (x: number) => L + ((x - x0) / (x1 - x0)) * (B - L - R)
  const sy = (n: number) => hoehe - U - (n / nMax) * (hoehe - O - U)
  const xt = schoen(x0, x1, 6).filter(t => t >= x0 && t <= x1)
  return (
    <div className="diagramm">
      {titel && <div className="leise" style={{ marginBottom: '.3rem' }}>{titel}</div>}
      <div className="rollbar">
        <svg viewBox={`0 0 ${B} ${hoehe}`} style={{ width: '100%', minWidth: 420, height: 'auto', display: 'block' }} role="img"
             onMouseLeave={() => setHover(null)}>
          {schoen(0, nMax, 4).map(t => (
            <g key={t}>
              <line x1={L} x2={B - R} y1={sy(t)} y2={sy(t)} stroke="var(--rand-leise)" />
              <text x={L - 6} y={sy(t) + 4} fontSize="11" textAnchor="end" fill="var(--text-leise)">{t}</text>
            </g>
          ))}
          {xt.map(t => <text key={t} x={sx(t)} y={hoehe - U + 16} fontSize="11" textAnchor="middle" fill="var(--text-leise)">{xFormat(t)}</text>)}
          {stufen.map(s => (
            <rect key={s.x} x={sx(s.x) + 1} y={sy(s.n)} width={Math.max(sx(s.x + breite) - sx(s.x) - 2, 1)}
                  height={hoehe - U - sy(s.n)} rx="2" fill={farbe} opacity={hover && hover.x === s.x ? 1 : .8}
                  onMouseEnter={() => setHover(s)} />
          ))}
          {grenzen.map(g => (
            <g key={g.x}>
              <line x1={sx(g.x)} x2={sx(g.x)} y1={O} y2={hoehe - U} stroke="var(--text)" strokeWidth="1" strokeDasharray="3 4" opacity=".6" />
              <text x={sx(g.x) + 3} y={O + 10} fontSize="10" fill="var(--text-leise)">{g.text}</text>
            </g>
          ))}
          <line x1={L} x2={B - R} y1={hoehe - U} y2={hoehe - U} stroke="var(--rand)" />
        </svg>
      </div>
      {hover && (
        <div className="diagramm-tip">
          <strong>{xFormat(hover.x)}–{xFormat(hover.x + breite)} g</strong> · {hover.n.toLocaleString('de-CH')} Kürbisse
          {' '}({gesamt > 0 ? ((hover.n / gesamt) * 100).toFixed(1) : '0'} %)
        </div>
      )}
    </div>
  )
}
