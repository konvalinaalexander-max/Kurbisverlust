import { useCallback, useMemo, useRef, useState, type ReactNode } from 'react'
import { kg as kgText, prozent, tonnen, zahl } from '../lib/format'

/**
 * Diagramme von Hand als SVG — Linien, Glocke (Verteilung), Anteilsbalken.
 *
 * Regeln (docs/UI-KONZEPT.md, Datenvisualisierung): eine Achse je Grösse,
 * dünne Marken, zurückhaltendes Gitter, Farben nur als Kennung der Reihe
 * (die Strom-Farben aus index.css), Text immer in Textfarbe. Jedes Diagramm
 * hat seine Tabelle — wer die Zahl will, bekommt sie.
 *
 * Runde H: interaktiv. Der Zeiger zeigt an der Stelle x *alle* Reihen
 * (Fadenkreuz), die Legende blendet Reihen aus, ein gezogener Rahmen
 * vergrössert einen Ausschnitt (Doppelklick oder Knopf: zurück), eine Reihe
 * kann ab einem Punkt gestrichelt weiterlaufen (Prognose), und eine
 * senkrechte Marke zeigt „heute".
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
  /** Ganze Linie gestrichelt (ein Modell, keine Messung). */
  gestrichelt?: boolean
  /** Ab diesem x läuft die Linie gestrichelt weiter: Prognose statt Rechnung bis heute. */
  prognoseAb?: number
  /** In der Legende zunächst ausgeblendet. */
  ausgeblendet?: boolean
}

const B = 720, L = 56, R = 16, O = 16, U = 36

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

/** Wie schoen(), aber der letzte Strich liegt *über* dem Maximum: ein Punkt am
 *  oberen Rand sass sonst genau auf der Rahmenlinie und war nicht zu sehen. */
function schoenMitLuft(min: number, max: number, n = 5): number[] {
  const ticks = schoen(min, max, n)
  if (ticks.length >= 2 && ticks[ticks.length - 1] <= max) {
    ticks.push(Number((ticks[ticks.length - 1] + (ticks[1] - ticks[0])).toFixed(10)))
  }
  return ticks
}

/** Beschriftungen nahe beieinanderliegender Bezugslinien staffeln. */
function beschriftungenVersetzt<T extends { py: number }>(zeilen: T[]): (T & { ty: number })[] {
  const sortiert = [...zeilen].sort((a, b) => b.py - a.py)
  let letzte = Infinity
  return sortiert.map(z => {
    const ty = Math.min(z.py - 4, letzte - 11)
    letzte = ty
    return { ...z, ty }
  })
}

/* ---------- Der schwebende Hinweis ----------------------------------------- */

interface Schweb { x: number; y: number; inhalt: ReactNode }

/** Ein Hinweis, der dem Zeiger folgt — innerhalb des Rahmens, nie darüber hinaus. */
function Schwebend({ s, rahmen }: { s: Schweb | null; rahmen: React.RefObject<HTMLDivElement | null> }) {
  if (!s) return null
  const breite = rahmen.current?.clientWidth ?? 600
  const links = s.x > breite * 0.62
  return (
    <div className="schweb" style={{ left: links ? undefined : s.x + 14, right: links ? breite - s.x + 14 : undefined, top: Math.max(s.y - 12, 0) }}
         role="tooltip">
      {s.inhalt}
    </div>
  )
}

function useZeiger() {
  const rahmen = useRef<HTMLDivElement | null>(null)
  const ort = useCallback((e: React.MouseEvent) => {
    const box = rahmen.current?.getBoundingClientRect()
    return box ? { x: e.clientX - box.left, y: e.clientY - box.top } : { x: 0, y: 0 }
  }, [])
  return { rahmen, ort }
}

/* ---------- Linien -------------------------------------------------------- */

export function Linien({ reihen, hoehe = 280, xFormat = String, yFormat = String, xTitel, yTitel,
                         yVon, yBis, xVon, xBis, senkrechte = [], waagrechte = [], heute, leer = 'keine Messung',
                         zoom = true, tabelle: tabelleErlaubt = true, kompakt = false }: {
  reihen: Reihe[]; hoehe?: number
  xFormat?: (x: number) => string; yFormat?: (y: number) => string
  xTitel?: string; yTitel?: string
  yVon?: number; yBis?: number; xVon?: number; xBis?: number
  /** Senkrechte Hilfslinien mit Beschriftung (etwa Kalibergrenzen). */
  senkrechte?: { x: number; text: string }[]
  /** Waagrechte Bezugslinien (etwa der Mittelwert einer Sorte). */
  waagrechte?: { y: number; text: string; farbe?: string }[]
  /** Die Marke „heute": links davon gerechnet, rechts Prognose. */
  heute?: { x: number; text?: string }
  leer?: string
  zoom?: boolean
  tabelle?: boolean
  kompakt?: boolean
}) {
  const { rahmen, ort } = useZeiger()
  const [aus, setAus] = useState<Set<string>>(() => new Set(reihen.filter(r => r.ausgeblendet).map(r => r.name)))
  const [sicht, setSicht] = useState<[number, number] | null>(null)
  const [zieh, setZieh] = useState<{ von: number; bis: number } | null>(null)
  const [hover, setHover] = useState<{ x: number; px: number; my: number; werte: { reihe: Reihe; p: Punkt }[] } | null>(null)
  const [zeigerOrt, setZeigerOrt] = useState<{ x: number; y: number } | null>(null)
  const [tabelle, setTabelle] = useState(false)
  const clipId = useMemo(() => `clip${Math.random().toString(36).slice(2, 8)}`, [])

  const sichtbar = reihen.filter(r => !aus.has(r.name))
  const alle = sichtbar.flatMap(r => r.punkte)
  const bandwerte = sichtbar.flatMap(r => r.band ?? [])
  const oben = yTitel ? O + 12 : O

  const m = useMemo(() => {
    const xsAlle = reihen.flatMap(r => r.punkte.map(p => p.x)).concat(senkrechte.map(s => s.x), heute ? [heute.x] : [])
    const xMinAlle = xVon ?? Math.min(...xsAlle), xMaxAlle = xBis ?? Math.max(...xsAlle)
    const x0 = sicht ? sicht[0] : xMinAlle, x1 = sicht ? sicht[1] : xMaxAlle
    const imFenster = (x: number) => x >= x0 && x <= x1
    const ys = alle.filter(p => imFenster(p.x)).map(p => p.y)
      .concat(bandwerte.filter(b => imFenster(b.x)).flatMap(b => [b.unten, b.oben]), waagrechte.map(w => w.y))
    const yMinRoh = ys.length ? Math.min(...ys) : 0, yMaxRoh = ys.length ? Math.max(...ys) : 1
    // Ohne Vorgabe beginnt die y-Achse bei 0 — ausser die Werte liegen so eng
    // beieinander, dass sie an der Null zu einem Strich würden.
    const engBeisammen = yMinRoh > 0 && (yMaxRoh - yMinRoh) < yMaxRoh * 0.4
    const y0 = yVon ?? (engBeisammen ? yMinRoh - (yMaxRoh - yMinRoh) * 0.25 : Math.min(0, yMinRoh))
    const y1 = yBis ?? yMaxRoh
    const yt = yBis === undefined ? schoenMitLuft(y0, y1) : schoen(y0, y1)
    const yMax = Math.max(y1, yt[yt.length - 1]), yMin = Math.min(y0, yt[0])
    const xt = schoen(x0, x1, kompakt ? 4 : 6).filter(t => t >= x0 && t <= x1)
    const sx = (x: number) => L + (x1 > x0 ? (x - x0) / (x1 - x0) : 0.5) * (B - L - R)
    const sy = (y: number) => hoehe - U - (yMax > yMin ? (y - yMin) / (yMax - yMin) : 0.5) * (hoehe - oben - U)
    const xVonPx = (px: number) => x0 + ((px - L) / (B - L - R)) * (x1 - x0)
    return { x0, x1, xMinAlle, xMaxAlle, yMin, yMax, sx, sy, xt, yt, xVonPx }
  }, [reihen, alle, bandwerte, senkrechte, waagrechte, heute, xVon, xBis, yVon, yBis, hoehe, oben, sicht, kompakt])

  if (reihen.every(r => r.punkte.length === 0)) return <p className="leise">{leer}</p>

  const { x0, x1, sx, sy, xt, yt, yMin, xVonPx } = m

  // Zeigerposition im SVG-Raster (B × hoehe), aus der Bildschirmposition
  const raster = (e: React.MouseEvent<SVGSVGElement>) => {
    const box = e.currentTarget.getBoundingClientRect()
    return { mx: ((e.clientX - box.left) / box.width) * B, my: ((e.clientY - box.top) / box.height) * hoehe }
  }

  function bewegung(e: React.MouseEvent<SVGSVGElement>) {
    const { mx, my } = raster(e)
    if (zieh) { setZieh({ von: zieh.von, bis: Math.max(L, Math.min(B - R, mx)) }); return }
    // Die nächste x-Stelle über alle sichtbaren Reihen — dann je Reihe der Punkt dort.
    let bestX: number | null = null, bestD = 1e12
    for (const r of sichtbar) for (const p of r.punkte) {
      if (p.x < x0 || p.x > x1) continue
      const d = Math.abs(sx(p.x) - mx)
      if (d < bestD) { bestD = d; bestX = p.x }
    }
    if (bestX === null || bestD > 40) { setHover(null); return }
    const werte: { reihe: Reihe; p: Punkt }[] = []
    for (const r of sichtbar) {
      let naechster: Punkt | null = null, dd = 1e12
      for (const p of r.punkte) {
        const d = Math.abs(p.x - bestX)
        if (d < dd) { dd = d; naechster = p }
      }
      // Nur, wenn die Reihe wirklich an dieser Stelle einen Punkt hat (Toleranz: ein Rasterpixel)
      if (naechster && Math.abs(sx(naechster.x) - sx(bestX)) < 3) werte.push({ reihe: r, p: naechster })
    }
    setHover({ x: bestX, px: sx(bestX), my, werte })
    setZeigerOrt(ort(e))
  }

  function druecken(e: React.MouseEvent<SVGSVGElement>) {
    if (!zoom || e.button !== 0) return
    const { mx } = raster(e)
    if (mx < L || mx > B - R) return
    setZieh({ von: mx, bis: mx })
  }
  function loslassen() {
    if (!zieh) return
    const a = Math.min(zieh.von, zieh.bis), b = Math.max(zieh.von, zieh.bis)
    setZieh(null)
    if (b - a < 8) return
    setSicht([xVonPx(a), xVonPx(b)])
    setHover(null)
  }
  function rad(e: React.WheelEvent<SVGSVGElement>) {
    // Rad allein rollt die Seite; mit Ctrl/⌘ vergrössert es um den Zeiger.
    if (!zoom || !(e.ctrlKey || e.metaKey)) return
    e.preventDefault()
    const { mx } = raster(e)
    const xm = xVonPx(Math.max(L, Math.min(B - R, mx)))
    const f = e.deltaY < 0 ? 0.8 : 1.25
    let a = xm - (xm - x0) * f, b = xm + (x1 - xm) * f
    a = Math.max(a, m.xMinAlle); b = Math.min(b, m.xMaxAlle)
    if (b - a <= 0) return
    setSicht(a <= m.xMinAlle && b >= m.xMaxAlle ? null : [a, b])
  }

  const imFenster = (p: { x: number }) => p.x >= x0 && p.x <= x1
  // Für Linien zählen auch die Nachbarpunkte ausserhalb, sonst reisst die Linie am Rand
  const fensterPunkte = (ps: Punkt[]) => {
    const s = ps.slice().sort((a, b) => a.x - b.x)
    const i0 = Math.max(s.findIndex(p => p.x >= x0) - 1, 0)
    let i1 = s.findIndex(p => p.x > x1); if (i1 < 0) i1 = s.length - 1
    return s.slice(i0, i1 + 1)
  }
  const pfadVon = (ps: Punkt[]) => ps.map((p, i) => `${i ? 'L' : 'M'} ${sx(p.x).toFixed(1)} ${sy(p.y).toFixed(1)}`).join(' ')
  const bandPfad = (r: Reihe) => {
    const b = (r.band ?? []).slice().sort((a, c) => a.x - c.x).filter(q => q.x >= x0 - (x1 - x0) * 0.1 && q.x <= x1 + (x1 - x0) * 0.1)
    if (b.length < 2) return ''
    return b.map((q, i) => `${i ? 'L' : 'M'} ${sx(q.x).toFixed(1)} ${sy(q.oben).toFixed(1)}`).join(' ')
      + ' ' + b.slice().reverse().map(q => `L ${sx(q.x).toFixed(1)} ${sy(q.unten).toFixed(1)}`).join(' ') + ' Z'
  }
  const linienTeile = (r: Reihe) => {
    const ps = fensterPunkte(r.punkte)
    if (ps.length < 2) return null
    if (r.prognoseAb === undefined) return <path d={pfadVon(ps)} fill="none" stroke={r.farbe} strokeWidth="2" strokeLinejoin="round" strokeDasharray={r.gestrichelt ? '5 5' : undefined} />
    const fest = ps.filter(p => p.x <= r.prognoseAb!)
    const rest = ps.filter(p => p.x >= r.prognoseAb!)
    // Der letzte feste Punkt gehört auch zur Prognose, damit die Linie nicht abreisst
    if (fest.length && rest[0]?.x !== fest[fest.length - 1].x) rest.unshift(fest[fest.length - 1])
    return (
      <>
        {fest.length > 1 && <path d={pfadVon(fest)} fill="none" stroke={r.farbe} strokeWidth="2" strokeLinejoin="round" />}
        {rest.length > 1 && <path d={pfadVon(rest)} fill="none" stroke={r.farbe} strokeWidth="2" strokeLinejoin="round" strokeDasharray="5 5" opacity=".85" />}
      </>
    )
  }

  const hoverTeile = hover?.werte ?? []
  return (
    <div className="diagramm" ref={rahmen}>
      <div className="rollbar" style={{ position: 'relative' }}>
        <svg viewBox={`0 0 ${B} ${hoehe}`} style={{ width: '100%', minWidth: kompakt ? 320 : 420, height: 'auto', display: 'block', cursor: zieh ? 'col-resize' : zoom ? 'crosshair' : 'default' }}
             role="img" aria-label={yTitel ?? ''}
             onMouseMove={bewegung} onMouseLeave={() => { setHover(null); setZieh(null) }}
             onMouseDown={druecken} onMouseUp={loslassen} onDoubleClick={() => setSicht(null)} onWheel={rad}>
          <defs><clipPath id={clipId}><rect x={L} y={oben - 6} width={B - L - R} height={hoehe - oben - U + 6} /></clipPath></defs>
          {yt.map(t => (
            <g key={`y${t}`}>
              <line x1={L} x2={B - R} y1={sy(t)} y2={sy(t)} stroke="var(--rand-leise)" strokeWidth="1" />
              <text x={L - 6} y={sy(t) + 4} fontSize="11" textAnchor="end" fill="var(--text-leise)">{yFormat(t)}</text>
            </g>
          ))}
          {xt.map(t => (
            <text key={`x${t}`} x={sx(t)} y={hoehe - U + 16} fontSize="11" textAnchor="middle" fill="var(--text-leise)">{xFormat(t)}</text>
          ))}
          <line x1={L} x2={B - R} y1={sy(Math.max(yMin, 0))} y2={sy(Math.max(yMin, 0))} stroke="var(--rand)" strokeWidth="1" />
          {xTitel && <text x={B - R} y={hoehe - 4} fontSize="11" textAnchor="end" fill="var(--text-leise)">{xTitel}</text>}
          {yTitel && <text x={L} y={10} fontSize="11" fill="var(--text-leise)">{yTitel}</text>}
          <g clipPath={`url(#${clipId})`}>
            {senkrechte.filter(imFenster).map(s => (
              <g key={`s${s.x}`}>
                <line x1={sx(s.x)} x2={sx(s.x)} y1={oben} y2={hoehe - U} stroke="var(--text-leise)" strokeWidth="1" strokeDasharray="3 4" opacity=".7" />
                <text x={sx(s.x) + 3} y={oben + 10} fontSize="10" fill="var(--text-leise)">{s.text}</text>
              </g>
            ))}
            {heute && imFenster(heute) && (
              <g>
                <rect x={sx(heute.x)} y={oben} width={Math.max(sx(x1) - sx(heute.x), 0)} height={hoehe - oben - U} fill="var(--flaeche-2)" opacity=".55" />
                <line x1={sx(heute.x)} x2={sx(heute.x)} y1={oben} y2={hoehe - U} stroke="var(--kuerbis)" strokeWidth="1.5" />
                <text x={sx(heute.x) + 4} y={oben + 10} fontSize="10.5" fontWeight="600" fill="var(--kuerbis)">{heute.text ?? 'heute'}</text>
                {sx(x1) - sx(heute.x) > 70 && <text x={sx(x1) - 4} y={oben + 10} fontSize="10" textAnchor="end" fill="var(--text-leise)">Prognose</text>}
              </g>
            )}
            {beschriftungenVersetzt(waagrechte.map(w => ({ ...w, py: sy(w.y) }))).map(w => (
              <g key={`w${w.text}`}>
                <line x1={L} x2={B - R} y1={w.py} y2={w.py} stroke={w.farbe ?? 'var(--text-leise)'} strokeWidth="1.5" strokeDasharray="6 4" opacity=".8" />
                <text x={B - R - 3} y={w.ty} fontSize="10" textAnchor="end" fill={w.farbe ?? 'var(--text-leise)'}>{w.text}</text>
              </g>
            ))}
            {sichtbar.map(r => r.band && r.band.length > 1 && (
              <path key={`b${r.name}`} d={bandPfad(r)} fill={r.farbe} opacity=".14" />
            ))}
            {sichtbar.map(r => r.linie && <g key={`l${r.name}`}>{linienTeile(r)}</g>)}
            {sichtbar.map(r => (r.marker ?? !r.linie) && r.punkte.filter(imFenster).map((p, i) => (
              <circle key={`${r.name}${i}`} cx={sx(p.x)} cy={sy(p.y)} r={kompakt ? 3 : 4} fill={r.farbe}
                      stroke="var(--flaeche)" strokeWidth="1.5" />
            )))}
            {hover && (
              <g>
                <line x1={hover.px} x2={hover.px} y1={oben} y2={hoehe - U} stroke="var(--text)" strokeWidth="1" opacity=".4" />
                {hoverTeile.map(({ reihe, p }) => (
                  <circle key={reihe.name} cx={sx(p.x)} cy={sy(p.y)} r="5.5" fill="var(--flaeche)" stroke={reihe.farbe} strokeWidth="2.5" />
                ))}
              </g>
            )}
            {zieh && (
              <rect x={Math.min(zieh.von, zieh.bis)} y={oben} width={Math.abs(zieh.bis - zieh.von)} height={hoehe - oben - U}
                    fill="var(--kuerbis)" opacity=".12" stroke="var(--kuerbis)" strokeWidth="1" />
            )}
          </g>
        </svg>
        <Schwebend rahmen={rahmen} s={hover && zeigerOrt && hoverTeile.length ? { x: zeigerOrt.x, y: zeigerOrt.y, inhalt: (
          <>
            <div className="schweb-kopf">{xFormat(hover.x)}{xTitel ? ` ${xTitel}` : ''}{heute && hover.x > heute.x ? ' · Prognose' : ''}</div>
            {hoverTeile.map(({ reihe, p }) => (
              <div key={reihe.name} className="schweb-zeile">
                <span className="chip" style={{ background: reihe.farbe }} />
                <span>{reihe.name}</span>
                <strong>{yFormat(p.y)}</strong>
                {p.text && <span className="leise" style={{ gridColumn: '2 / span 2' }}>{p.text}</span>}
              </div>
            ))}
          </>
        ) } : null} />
      </div>
      <div className="diagramm-fuss">
        {reihen.length > 1 && (
          <div className="legende" role="group" aria-label="Reihen ein- und ausblenden">
            {reihen.map(r => (
              <button key={r.name} type="button" className={`legende-knopf${aus.has(r.name) ? ' aus' : ''}`}
                      aria-pressed={!aus.has(r.name)}
                      onClick={() => setAus(s => { const n = new Set(s); if (n.has(r.name)) n.delete(r.name); else n.add(r.name); return n })}>
                <span className="chip" style={{ background: r.farbe }} />{r.name}
              </button>
            ))}
          </div>
        )}
        <span className="diagramm-werkzeuge">
          {sicht && <button type="button" className="blank klein" onClick={() => setSicht(null)}>Ausschnitt zurück</button>}
          {zoom && !sicht && !kompakt && <span className="leise" style={{ fontSize: '.76rem' }}>Ausschnitt: Bereich ziehen · Ctrl + Rad</span>}
          {tabelleErlaubt && <button type="button" className="blank klein" onClick={() => setTabelle(t => !t)}>{tabelle ? 'Tabelle ausblenden' : 'Als Tabelle'}</button>}
        </span>
      </div>
      {tabelle && (
        <div className="rollbar">
          <table>
            <thead><tr><th>Reihe</th><th className="zahl">{xTitel ?? 'x'}</th><th className="zahl">{yTitel ?? 'y'}</th><th></th></tr></thead>
            <tbody>
              {sichtbar.flatMap(r => r.punkte.slice().sort((a, b) => a.x - b.x).map((p, i) => (
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

/** Die alte Signatur bleibt lesbar — Diagramm ist Linien. */

/* ---------- Glocke: die Verteilung ---------------------------------------- */

export interface Stufe { x: number; n: number }

/**
 * Histogramm mit Hilfslinien — die Gewichtsverteilung mit ihren
 * Kalibergrenzen. Jeder Balken zeigt beim Zeigen seine Zahl und seinen
 * Anteil; die Grenzen färben die Balken nach Klasse (zu klein, Kaliber, zu
 * gross), damit die Glocke selbst sagt, wo die Ware liegt.
 */
export function Glocke({ stufen, breite, grenzen = [], farbe = 'var(--kuerbis)', hoehe = 220,
                         xFormat = String, titel, klassenfarbe, mittel, kompakt = false }: {
  stufen: Stufe[]; breite: number
  grenzen?: { x: number; text: string }[]; farbe?: string; hoehe?: number
  xFormat?: (x: number) => string; titel?: ReactNode
  /** Die Farbe einer Stufe nach ihrem x (etwa: unter der Verlustgrenze gelb). */
  klassenfarbe?: (x: number) => string
  /** Der Schwerpunkt, als Marke. */
  mittel?: number | null
  kompakt?: boolean
}) {
  const { rahmen, ort } = useZeiger()
  const [hover, setHover] = useState<{ s: Stufe; ort: { x: number; y: number } } | null>(null)
  if (stufen.length === 0) return <p className="leise">keine Sortier-CSV eingelesen</p>
  const x0 = Math.min(...stufen.map(s => s.x)), x1 = Math.max(...stufen.map(s => s.x)) + breite
  const nMax = Math.max(...stufen.map(s => s.n), 1)
  const gesamt = stufen.reduce((a, s) => a + s.n, 0)
  const sx = (x: number) => L + ((x - x0) / (x1 - x0)) * (B - L - R)
  const oben = O + 12
  const sy = (n: number) => hoehe - U - (n / nMax) * (hoehe - oben - U)
  const xt = schoen(x0, x1, kompakt ? 4 : 6).filter(t => t >= x0 && t <= x1)
  return (
    <div className="diagramm" ref={rahmen}>
      {titel && <div className="leise" style={{ marginBottom: '.3rem' }}>{titel}</div>}
      <div className="rollbar" style={{ position: 'relative' }}>
        <svg viewBox={`0 0 ${B} ${hoehe}`} style={{ width: '100%', minWidth: kompakt ? 300 : 420, height: 'auto', display: 'block' }} role="img"
             onMouseLeave={() => setHover(null)}>
          {schoen(0, nMax, 4).map(t => (
            <g key={t}>
              <line x1={L} x2={B - R} y1={sy(t)} y2={sy(t)} stroke="var(--rand-leise)" />
              <text x={L - 6} y={sy(t) + 4} fontSize="11" textAnchor="end" fill="var(--text-leise)">{zahl(t)}</text>
            </g>
          ))}
          {xt.map(t => <text key={t} x={sx(t)} y={hoehe - U + 16} fontSize="11" textAnchor="middle" fill="var(--text-leise)">{xFormat(t)}</text>)}
          <text x={L} y={10} fontSize="11" fill="var(--text-leise)">Kürbisse je Stufe</text>
          <text x={B - R} y={hoehe - 4} fontSize="11" textAnchor="end" fill="var(--text-leise)">Gramm je Kürbis</text>
          {stufen.map(s => (
            <rect key={s.x} x={sx(s.x) + 1} y={sy(s.n)} width={Math.max(sx(s.x + breite) - sx(s.x) - 2, 1)}
                  height={hoehe - U - sy(s.n)} rx="2" fill={klassenfarbe ? klassenfarbe(s.x) : farbe} opacity={hover && hover.s.x === s.x ? 1 : .8}
                  onMouseEnter={e => setHover({ s, ort: ort(e) })} onMouseMove={e => setHover({ s, ort: ort(e) })} />
          ))}
          {grenzen.map(g => (
            <g key={g.x}>
              <line x1={sx(g.x)} x2={sx(g.x)} y1={oben} y2={hoehe - U} stroke="var(--text)" strokeWidth="1" strokeDasharray="3 4" opacity=".6" />
              <text x={sx(g.x) + 3} y={oben + 10} fontSize="10" fill="var(--text-leise)">{g.text}</text>
            </g>
          ))}
          {mittel != null && mittel >= x0 && mittel <= x1 && (
            <g>
              <line x1={sx(mittel)} x2={sx(mittel)} y1={oben + 14} y2={hoehe - U} stroke="var(--kuerbis)" strokeWidth="1.5" />
              <text x={sx(mittel) + 3} y={oben + 24} fontSize="10" fill="var(--kuerbis)" fontWeight="600">Ø {xFormat(Math.round(mittel))} g</text>
            </g>
          )}
          <line x1={L} x2={B - R} y1={hoehe - U} y2={hoehe - U} stroke="var(--rand)" />
        </svg>
        <Schwebend rahmen={rahmen} s={hover ? { x: hover.ort.x, y: hover.ort.y, inhalt: (
          <>
            <div className="schweb-kopf">{xFormat(hover.s.x)}–{xFormat(hover.s.x + breite)} g</div>
            <div className="schweb-zeile"><span>Kürbisse</span><strong>{zahl(hover.s.n)}</strong></div>
            <div className="schweb-zeile"><span>Anteil</span><strong>{prozent(gesamt > 0 ? hover.s.n / gesamt : null)}</strong></div>
          </>
        ) } : null} />
      </div>
    </div>
  )
}

/** Die alte Signatur bleibt lesbar. */

/* ---------- Anteilsbalken: 100 % je Zeile ----------------------------------- */

export interface Anteil { name: string; kg: number; farbe: string; hinweis?: string }
export interface Anteilszeile {
  name: string
  untertitel?: string
  /** Die Bezugsmasse (Eingang) — der ganze Balken. */
  bezug: number
  teile: Anteil[]
  /** Wohin ein Klick führt. */
  ziel?: string
  /** Was rechts steht, wenn nicht der Anteil der Teile. */
  rechts?: string
}

/**
 * Gestapelte Anteile je Zeile — alle Balken gleich lang (100 % = Eingang der
 * Zeile), die Teile als Farbsegmente, der Rest neutral. Links der Name,
 * rechts der Anteil aller Teile; beim Zeigen auf ein Segment: Ursache,
 * Prozent und Tonnen. So sieht man, wem anteilig am meisten fehlt — nicht,
 * wer am grössten ist.
 */
export function Anteilsbalken({ zeilen, oeffnen, legende = true }: {
  zeilen: Anteilszeile[]; oeffnen?: (z: Anteilszeile) => void; legende?: boolean
}) {
  const { rahmen, ort } = useZeiger()
  const [hover, setHover] = useState<{ z: Anteilszeile; t: Anteil; ort: { x: number; y: number } } | null>(null)
  if (zeilen.length === 0) return <p className="leise">nichts</p>
  const namen = [...new Map(zeilen.flatMap(z => z.teile).map(t => [t.name, t.farbe])).entries()]
  return (
    <div className="anteile" ref={rahmen}>
      {zeilen.map(z => {
        const summe = z.teile.reduce((s, t) => s + t.kg, 0)
        const anteil = z.bezug > 0 ? summe / z.bezug : 0
        return (
          <div key={z.name} className={`anteil-zeile${oeffnen ? ' klickbar' : ''}`}
               onClick={oeffnen ? () => oeffnen(z) : undefined} role={oeffnen ? 'button' : undefined}
               tabIndex={oeffnen ? 0 : undefined}
               onKeyDown={oeffnen ? e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); oeffnen(z) } } : undefined}>
            <div className="anteil-name">
              <strong>{z.name}</strong>
              {z.untertitel && <span className="leise">{z.untertitel}</span>}
            </div>
            <div className="anteil-spur">
              {z.teile.filter(t => t.kg > 0 && z.bezug > 0).map(t => (
                <div key={t.name} className="anteil-teil" style={{ width: `${Math.min((t.kg / z.bezug) * 100, 100)}%`, background: t.farbe }}
                     onMouseEnter={e => setHover({ z, t, ort: ort(e) })} onMouseMove={e => setHover({ z, t, ort: ort(e) })}
                     onMouseLeave={() => setHover(null)} />
              ))}
            </div>
            <div className="anteil-wert">{z.rechts ?? prozent(z.bezug > 0 ? anteil : null)}</div>
          </div>
        )
      })}
      {legende && (
        <div className="legende" style={{ marginTop: '.5rem' }}>
          {namen.map(([name, farbe]) => <span key={name}><span className="chip" style={{ background: farbe }} />{name}</span>)}
        </div>
      )}
      <Schwebend rahmen={rahmen} s={hover ? { x: hover.ort.x, y: hover.ort.y, inhalt: (
        <>
          <div className="schweb-kopf">{hover.z.name} · {hover.t.name}</div>
          <div className="schweb-zeile"><span>Anteil am Eingang</span><strong>{prozent(hover.z.bezug > 0 ? hover.t.kg / hover.z.bezug : null)}</strong></div>
          <div className="schweb-zeile"><span>Masse</span><strong>{tonnen(hover.t.kg)}</strong></div>
          {hover.t.hinweis && <div className="leise" style={{ marginTop: '.15rem' }}>{hover.t.hinweis}</div>}
        </>
      ) } : null} />
    </div>
  )
}

/** Die Zahl als Text für Achsen: Tonnen ab 1000 kg. */
export const tonnenAchse = (y: number) => (Math.abs(y) >= 1000 ? tonnen(y) : kgText(y, 0))
