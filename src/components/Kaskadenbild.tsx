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
  buch: 'verlust' | 'feld' | 'marge' | 'bilanz'
  bereichBekannt: boolean
  extrapoliert: number
}

// Jede Ursache hat im ganzen Werkzeug dieselbe Farbe — als CSS-Variable,
// damit auch der Dunkelmodus stimmt. `var(--rahmen)` stand hier früher als
// Tippfehler für `--rand` und fiel nie auf, weil der Ersatzwert griff — nur
// eben in beiden Themen mit demselben Hellgrau.
const FARBEN: Record<string, string> = {
  Verdunstung: 'var(--strom-verdunstung)',
  'Schimmel/Fäulnis': 'var(--strom-schimmel)',
  'Nicht lagerbedingt': 'var(--strom-feld)',
  'Zu klein (Tierfutter)': 'var(--strom-ausschuss)',
  'Nebenkanal zu gross': 'var(--strom-nebenkanal)',
}

export function Kaskadenbild({ eingang, stroeme, verkaufsfaehig, hoehe = 300 }: {
  eingang: number
  stroeme: Kaskadenstrom[]
  verkaufsfaehig: number
  hoehe?: number
}) {
  if (!(eingang > 0)) return null

  // Alle Masse aus einer Handvoll benannter Höhen — jede Y-Koordinate leitet
  // sich daraus ab. Vorher standen hier Zahlen, die zusammenpassen mussten,
  // und taten es nach der ersten Änderung nicht mehr: Anschlüsse verrutscht,
  // Beschriftung oben und unten abgeschnitten.
  const breite = 720
  const links = 8
  const rechts = breite - 8
  const nutz = rechts - links
  const spur = 24            // Höhe eines Bandes
  const bandY = 24           // Oberkante des Eingangs-Bandes; darüber die Zeile Text
  const zeile = 44           // Höhe einer Abzweigungs-Zeile

  const anteil = (kg: number) => Math.max(kg, 0) / eingang
  const x = (kumuliert: number) => links + nutz * kumuliert

  // Wie viel ist vor diesem Strom schon abgezweigt?
  let kumuliert = 0
  const abschnitte = stroeme.map(s => {
    const von = kumuliert
    kumuliert += anteil(s.kg)
    return { ...s, von, bis: kumuliert }
  })

  const zeilenAnfang = bandY + spur + 12          // erste Abzweigung
  const restY = zeilenAnfang + zeile * abschnitte.length + 6
  const gesamthoehe = restY + spur + 26

  return (
    <div className="rollbar">
      <svg viewBox={`0 0 ${breite} ${Math.max(gesamthoehe, hoehe)}`}
           style={{ width: '100%', minWidth: 460, height: 'auto', display: 'block' }}
           role="img" aria-label="Wo die Masse bleibt">
        {/* Wareneingang: das volle Band */}
        <text x={links} y={bandY - 8} fontSize="12.5" fontWeight="600" fill="currentColor">
          Wareneingang {(eingang / 1000).toFixed(1)} t
        </text>
        <rect x={links} y={bandY} width={nutz} height={spur} rx={4}
              fill="var(--flaeche-2)" stroke="var(--rand)" strokeWidth="1" />

        {abschnitte.map((s, i) => {
          const y = zeilenAnfang + zeile * i + (zeile - spur)
          const x0 = x(s.von)
          const x1 = x(s.bis)
          const farbe = FARBEN[s.name] ?? 'var(--strom-nebenkanal)'
          // Der Bereich als heller Streifen: von wo bis wo könnte die Kante liegen?
          const bu = x(s.von + anteil(s.unten))
          const bo = x(s.von + anteil(s.oben))
          return (
            <g key={s.name}>
              {/* Abzweigung: verbindet das Stück im Eingangs-Band mit seiner Zeile */}
              <path d={`M ${x0} ${bandY + spur} L ${x0} ${y}
                        L ${x1} ${y} L ${x1} ${bandY + spur} Z`}
                    fill={farbe} opacity={0.14} />
              {/* dasselbe Stück oben im Band markieren */}
              <rect x={x0} y={bandY + 1} width={Math.max(x1 - x0, 1.5)} height={spur - 2}
                    fill={farbe} opacity={0.5} />
              {s.bereichBekannt && bo > bu + 1 && (
                <rect x={bu} y={y} width={bo - bu} height={spur} fill={farbe}
                      opacity={0.25} />
              )}
              <rect x={x0} y={y} width={Math.max(x1 - x0, 1.5)} height={spur} rx={3}
                    fill={farbe} />
              {s.extrapoliert > 0 && (
                <rect x={x1 - Math.max((x1 - x0) * (s.extrapoliert / Math.max(s.kg, 1)), 0)}
                      y={y} width={Math.max((x1 - x0) * (s.extrapoliert / Math.max(s.kg, 1)), 0)}
                      height={spur} fill="url(#schraffur)" />
              )}
              <text x={Math.min(Math.max(x1, bo) + 8, rechts - 4)} y={y + spur / 2 + 4.5}
                    fontSize="13" fill="currentColor"
                    textAnchor={Math.max(x1, bo) > breite * 0.72 ? 'end' : 'start'}>
                {s.name} · {(s.kg / 1000).toFixed(1)} t
                <tspan opacity={0.65}> ({(anteil(s.kg) * 100).toFixed(1)} %)</tspan>
              </text>
            </g>
          )
        })}

        {/* Was übrig bleibt */}
        <g>
          <rect x={x(kumuliert)} y={restY} width={Math.max(rechts - x(kumuliert), 1)}
                height={spur} rx={3} fill="var(--strom-rest)" />
          <text x={x(kumuliert) > breite * 0.4 ? x(kumuliert) - 8 : x(kumuliert) + 8}
                y={restY + spur / 2 + 4.5} fontSize="13" fontWeight="600"
                fill={x(kumuliert) > breite * 0.4 ? 'currentColor' : '#fff'}
                textAnchor={x(kumuliert) > breite * 0.4 ? 'end' : 'start'}>
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
    <div style={{ marginBottom: '.8rem' }}>
      <div className="reihe" style={{ justifyContent: 'space-between', gap: '.6rem', marginBottom: '.2rem' }}>
        <span style={{ fontSize: '.9rem', fontWeight: 560 }}>{titel}</span>
        <strong style={{ fontVariantNumeric: 'tabular-nums' }}>{(kg / 1000).toFixed(1)} t</strong>
      </div>
      <div style={{ background: 'var(--flaeche-2)', height: 10, borderRadius: 5 }}>
        <div style={{ width: `${Math.min(anteil * 100, 100)}%`, height: 10,
                      background: farbe, borderRadius: 5 }} />
      </div>
      {erklaerung && (
        <p className="leise" style={{ margin: '.25rem 0 0', fontSize: '.82rem' }}>{erklaerung}</p>
      )}
    </div>
  )
}
