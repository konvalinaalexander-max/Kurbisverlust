import type { ReactNode } from 'react'

/**
 * Wo bleibt die Masse? Ein Wasserfall von links nach rechts: Der Balken oben
 * ist der Wareneingang, darunter zweigt jeder Strom ab und der Rest läuft
 * weiter. Das ist die eine Grafik, die der Betriebsleiter in zehn Sekunden
 * lesen können muss.
 *
 * Von Hand als SVG. Eine Diagramm-Bibliothek wäre eine Abhängigkeit mehr, die
 * in fünf Jahren nicht mehr baut — und für einen Wasserfall braucht es sie
 * nicht.
 *
 * Bewusst *keine* Zahl ohne Massstab: Jeder Strom trägt seinen Anteil am
 * Eingang, und der Unsicherheitsbereich steht als heller Streifen daneben.
 * Ein Strom, dessen Bereich so breit ist wie er selbst, sieht dann auch so aus.
 */
export interface Kaskadenstrom {
  name: string
  kg: number
  unten: number
  oben: number
  buch: 'verlust' | 'marge' | 'bilanz'
  bereichBekannt: boolean
  extrapoliert: number
}

const FARBEN: Record<string, string> = {
  Verdunstung: '#7aa6c2',
  'Schimmel/Fäulnis': '#b5651d',
  'Ausschuss zu klein': '#c9a227',
  'Nebenkanal zu gross': '#8a8a8a',
}

export function Kaskadenbild({ eingang, stroeme, verkaufsfaehig, hoehe = 300 }: {
  eingang: number
  stroeme: Kaskadenstrom[]
  verkaufsfaehig: number
  hoehe?: number
}) {
  if (!(eingang > 0)) return null

  const breite = 720
  const links = 8
  const rechts = breite - 8
  const nutz = rechts - links
  const spur = 26          // Höhe des laufenden Bandes
  const oben = 34
  const zeile = 46         // Abstand zwischen zwei Abzweigungen

  const anteil = (kg: number) => Math.max(kg, 0) / eingang
  const x = (kumuliert: number) => links + nutz * kumuliert

  // Wie viel ist vor diesem Strom schon abgezweigt?
  let kumuliert = 0
  const abschnitte = stroeme.map(s => {
    const von = kumuliert
    kumuliert += anteil(s.kg)
    return { ...s, von, bis: kumuliert }
  })

  const gesamthoehe = oben + zeile * abschnitte.length + spur + 46

  return (
    <div className="rollbar">
      <svg viewBox={`0 0 ${breite} ${Math.max(gesamthoehe, hoehe)}`}
           style={{ width: '100%', minWidth: 480, height: 'auto' }}
           role="img" aria-label="Wo die Masse bleibt">
        {/* Wareneingang: das volle Band */}
        <rect x={links} y={oben - 24} width={nutz} height={spur} rx={4}
              fill="var(--rahmen, #d8d8d8)" />
        <text x={links} y={oben - 30} fontSize="13" fill="currentColor">
          Wareneingang {(eingang / 1000).toFixed(1)} t
        </text>

        {abschnitte.map((s, i) => {
          const y = oben + zeile * i + spur
          const x0 = x(s.von)
          const x1 = x(s.bis)
          const farbe = FARBEN[s.name] ?? '#999'
          // Der Bereich als heller Streifen: von wo bis wo könnte die Kante liegen?
          const bu = x(s.von + anteil(s.unten))
          const bo = x(s.von + anteil(s.oben))
          return (
            <g key={s.name}>
              {/* Abzweigung nach unten */}
              <path d={`M ${x0} ${oben + spur - 24} L ${x0} ${y + 6}
                        L ${x1} ${y + 6} L ${x1} ${oben + spur - 24} Z`}
                    fill={farbe} opacity={0.18} />
              {s.bereichBekannt && bo > bu + 1 && (
                <rect x={bu} y={y + 6} width={bo - bu} height={spur} fill={farbe}
                      opacity={0.25} />
              )}
              <rect x={x0} y={y + 6} width={Math.max(x1 - x0, 1.5)} height={spur} rx={3}
                    fill={farbe} />
              {s.extrapoliert > 0 && (
                <rect x={x1 - Math.max((x1 - x0) * (s.extrapoliert / Math.max(s.kg, 1)), 0)}
                      y={y + 6} width={Math.max((x1 - x0) * (s.extrapoliert / Math.max(s.kg, 1)), 0)}
                      height={spur} fill="url(#schraffur)" />
              )}
              <text x={Math.min(x1 + 8, rechts - 4)} y={y + 6 + spur / 2 + 4}
                    fontSize="13" fill="currentColor"
                    textAnchor={x1 > breite * 0.72 ? 'end' : 'start'}>
                {s.name} · {(s.kg / 1000).toFixed(1)} t
                <tspan opacity={0.65}> ({(anteil(s.kg) * 100).toFixed(1)} %)</tspan>
              </text>
            </g>
          )
        })}

        {/* Was übrig bleibt */}
        <g>
          <rect x={x(kumuliert)} y={oben + zeile * abschnitte.length + spur + 6}
                width={Math.max(rechts - x(kumuliert), 1)} height={spur} rx={3}
                fill="#4a8c4a" />
          <text x={links} y={oben + zeile * abschnitte.length + spur + spur + 24}
                fontSize="13" fill="currentColor">
            Bleibt verkaufsfähig {(verkaufsfaehig / 1000).toFixed(1)} t
            <tspan opacity={0.65}> ({(anteil(verkaufsfaehig) * 100).toFixed(1)} %)</tspan>
          </text>
        </g>

        <defs>
          <pattern id="schraffur" width="6" height="6" patternTransform="rotate(45)"
                   patternUnits="userSpaceOnUse">
            <rect width="6" height="6" fill="none" />
            <line x1="0" y1="0" x2="0" y2="6" stroke="white" strokeWidth="2" opacity="0.55" />
          </pattern>
        </defs>
      </svg>
      <p className="leise" style={{ marginTop: '.4rem', fontSize: '.82rem' }}>
        Breite = Anteil am Wareneingang. Der hellere Streifen ist der Bereich, in
        dem der Wert liegen kann. Schraffiert: der Teil, der über die längste
        gemessene Lagerdauer hinaus hochgerechnet ist.
      </p>
    </div>
  )
}

/** Eine Zeile der Bilanz: Zahl, Balken, Erklärung — untereinander lesbar. */
export function Bilanzzeile({ titel, kg, eingang, farbe, erklaerung }: {
  titel: string; kg: number; eingang: number; farbe: string; erklaerung?: ReactNode
}) {
  const anteil = eingang > 0 ? Math.max(kg, 0) / eingang : 0
  return (
    <div style={{ marginBottom: '.7rem' }}>
      <div className="reihe" style={{ justifyContent: 'space-between', gap: '.6rem' }}>
        <span>{titel}</span>
        <strong>{(kg / 1000).toFixed(1)} t</strong>
      </div>
      <div style={{ background: 'var(--rahmen, #e6e6e6)', height: 10, borderRadius: 5 }}>
        <div style={{ width: `${Math.min(anteil * 100, 100)}%`, height: 10,
                      background: farbe, borderRadius: 5 }} />
      </div>
      {erklaerung && (
        <p className="leise" style={{ margin: '.25rem 0 0', fontSize: '.82rem' }}>{erklaerung}</p>
      )}
    </div>
  )
}
