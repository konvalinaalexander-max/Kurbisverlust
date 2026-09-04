import { useMemo, useState } from 'react'
import { kg, prozent, tonnen, zahl } from '../lib/format'
import { Balken, Hinweis, Karte, Marke, Rechenweg } from '../components/Bausteine'
import { Diagramm, Histogramm } from '../components/Diagramm'
import { stroemeSummieren, useAuswertung, useRanking, type Auswertung, type Kaliberzeile } from '../auswertung/daten'
import { Reiterkopf, Sortenvergleich, WartetAufsWaschen, rechenweg } from '../auswertung/Karten'
import { Lade } from '../components/Bausteine'

/**
 * Ursachen: Warum verliere ich — und wie sicher ist das? Jeder Strom mit
 * Balken, Bereich und Rechenweg; die Kurven mit ihren Messpunkten; Buch B
 * getrennt; zum Schluss, was die Sortier-CSV über den Anbau sagt.
 */
export default function Ursachen() {
  const { daten, laedt, fehler, neuRechnen } = useAuswertung()
  const [sorte, setSorte] = useState('')
  const [schlag, setSchlag] = useState('')
  const [minLagertage, setMinLagertage] = useState('')
  const ranking = useRanking(sorte, schlag, minLagertage, daten?.stand ?? null)

  const zeilen = daten?.hochrechnung ?? []
  const sorten = useMemo(() => [...new Set(zeilen.map(z => z.sorte))].sort(), [zeilen])
  const schlaege = useMemo(() => [...new Set(zeilen.map(z => z.schlag))].sort(), [zeilen])
  const gefiltert = useMemo(() => zeilen.filter(z =>
    (!sorte || z.sorte === sorte) && (!schlag || z.schlag === schlag)
    && (!minLagertage || z.alter_tage >= Number(minLagertage))), [zeilen, sorte, schlag, minLagertage])
  const stroeme = useMemo(() => stroemeSummieren(gefiltert, ranking), [gefiltert, ranking])

  if (laedt && !daten) return <Lade text="Auswertung wird gerechnet …" />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null

  const verluste = stroeme.filter(s => s.buch === 'verlust').sort((a, b) => Number(b.bekannt) - Number(a.bekannt) || b.mittel - a.mittel)
  const feld = stroeme.find(s => s.buch === 'feld')
  const proCharge = new Map<number, number>()
  for (const z of gefiltert) proCharge.set(z.charge_nr, z.eingang_kg)
  const eingang = [...proCharge.values()].reduce((a, b) => a + b, 0)
  const maximum = Math.max(...verluste.map(v => Math.max(v.mittel, v.oben)), 1)
  const m = daten.modell

  // Verderbskurve: die Messpunkte nach Herkunft, die verwendete Kurve mit Bereich
  const punkte = daten.punkte.filter(p => p.plausibel && p.anteil !== null)
  const kurveReihe = daten.kurve.filter(k => k.verwendet !== null).map(k => {
    const mitte = (k.von + Math.min(k.bis, k.von + 60)) / 2
    return { x: mitte, y: (k.verwendet ?? 0) * 100, unten: (k.unten ?? k.verwendet ?? 0) * 100, oben: (k.oben ?? k.verwendet ?? 0) * 100, text: k.altersklasse }
  })
  // Verdunstung: je Wägung die Rate je Tag
  const raten = daten.wiegungen
    .filter(w => !w.sichtbar_schimmel && w.netto_damals_kg && w.lagertage > 0 && w.verlust_kg !== null)
    .map(w => ({ x: w.lagertage, y: (w.verlust_kg! / (w.netto_damals_kg! * w.lagertage)) * 100, text: `Charge ${w.charge_nr} · ${w.sorte}` }))

  return (
    <>
      <Reiterkopf titel="Ursachen" zweck="Warum verliere ich — und wie sicher ist das? Jede Zahl mit Bereich und Rechenweg."
                  stand={daten.stand} neuRechnen={() => void neuRechnen()} />

      <Karte titel="Filter">
        <div className="spalten">
          <div className="feld"><label htmlFor="fs">Sorte</label>
            <select id="fs" value={sorte} onChange={e => setSorte(e.target.value)}><option value="">alle</option>{sorten.map(s => <option key={s}>{s}</option>)}</select></div>
          <div className="feld"><label htmlFor="fl">Schlag</label>
            <select id="fl" value={schlag} onChange={e => setSchlag(e.target.value)}><option value="">alle</option>{schlaege.map(s => <option key={s}>{s}</option>)}</select></div>
          <div className="feld"><label htmlFor="ft">Ab Lagerdauer (Tage)</label>
            <input id="ft" type="number" min={0} value={minLagertage} onChange={e => setMinLagertage(e.target.value)} /></div>
        </div>
        {(sorte || schlag || minLagertage) && (
          <p className="leise" style={{ margin: 0 }}>Gefiltert: {[sorte, schlag, minLagertage && `ab ${minLagertage} Lagertagen`].filter(Boolean).join(' · ')}
            {' '}<button className="klein" onClick={() => { setSorte(''); setSchlag(''); setMinLagertage('') }}>zurücksetzen</button></p>
        )}
      </Karte>

      <Karte titel="Buch A — Lagerverlust">
        {verluste.map(v => (
          <div key={v.strom} style={{ marginBottom: '1.25rem' }}>
            <div className="reihe">
              <strong>{v.strom}</strong>
              {!v.bekannt && <Marke art="warnung">nicht gemessen</Marke>}
              <span style={{ marginLeft: 'auto' }}>{v.bekannt ? tonnen(v.mittel) : '—'}</span>
            </div>
            <Balken wert={v.bekannt ? v.mittel : null} unten={v.unten} oben={v.oben} maximum={maximum} beobachtet={v.beobachtet} />
            <p className="leise" style={{ margin: '.25rem 0 0' }}>
              {v.bekannt
                ? <>{tonnen(v.beobachtet)} beobachtet · {tonnen(v.projiziert)} projiziert · Bereich {tonnen(v.unten)} – {tonnen(v.oben)}</>
                : <>{v.koeffBasis ?? 'keine Messung'} — der Strom ist unbekannt, nicht null.</>}
            </p>
            <Rechenweg zeilen={rechenweg(v, eingang)} />
          </div>
        ))}
      </Karte>

      <Karte titel="Verderb mit der Lagerdauer">
        <p className="leise">Jeder Punkt eine Wägung des Faulen: Anteil der Masse, die an dem Tag aus dem Lager kam. Die Linie ist die Kurve, die die Auswertung verwendet, der Streifen ihr Bereich. Rechts der letzten Messung ist alles Hochrechnung.</p>
        <Diagramm
          reihen={[
            { name: 'Modell (verwendet)', farbe: 'var(--strom-schimmel)', linie: true, marker: false,
              punkte: kurveReihe.map(k => ({ x: k.x, y: k.y, text: k.text })),
              band: kurveReihe.map(k => ({ x: k.x, unten: k.unten, oben: k.oben })) },
            { name: 'Verarbeitung (Palox)', farbe: 'var(--strom-verdunstung)',
              punkte: punkte.filter(p => p.quelle === 'verarbeitung').map(p => ({ x: p.lagertage, y: (p.anteil ?? 0) * 100, text: `Charge ${p.charge_nr} · ${p.sorte}` })) },
            { name: 'Lagerkontrolle (zufällig gegriffen)', farbe: 'var(--strom-feld)',
              punkte: punkte.filter(p => p.quelle === 'lager').map(p => ({ x: p.lagertage, y: (p.anteil ?? 0) * 100, text: `Charge ${p.charge_nr} · ${p.sorte}` })) },
          ].filter(r => r.punkte.length > 0)}
          xFormat={x => `${Math.round(x)}`} yFormat={y => `${y.toFixed(1)} %`} xTitel="Lagertage" yTitel="Anteil faul" yVon={0}
          leer="noch keine Schimmelmessung" />
        {m && (
          <p className="leise" style={{ margin: '.5rem 0 0' }}>
            {m.brauchbar
              ? <>Kurve F(t) = 1 − exp(−λ·t<sup>k</sup>), k = {m.k?.toFixed(2)}, angepasst an {m.n} Messungen aus {m.c_chargen} Chargen über {Math.round(m.t_min)}–{Math.round(m.t_max)} Lagertage. Darüber hinaus wird gerechnet, nicht gemessen.</>
              : <>Für eine Kurve reicht es noch nicht — nötig sind Messungen aus mindestens drei Chargen über deutlich verschiedene Lagerdauern. Solange gilt der zuletzt gemessene Wert.</>}
            {daten.selektion && <> {daten.selektion.befund}</>}
          </p>
        )}
      </Karte>

      {feld && (
        <Karte titel="Nicht lagerbedingt — vom Feld mitgebracht">
          <p className="leise">Erde, Blätter, Hagelnarben, Schnittfehler landen im selben Palox wie das Faule, haben mit der Lagerung aber nichts zu tun. Das Modell trennt sie als Sockel ab, damit sie die Verderbskurve nicht aufblähen.</p>
          <div className="reihe">
            <strong>{feld.strom}</strong>
            {!feld.bekannt && <Marke art="warnung">noch nicht schätzbar</Marke>}
            {feld.bekannt && feld.mittel <= 0 && <Marke art="offen">nicht belegt</Marke>}
            <span style={{ marginLeft: 'auto' }}>{feld.bekannt && feld.mittel > 0 ? tonnen(feld.mittel) : '—'}</span>
          </div>
          {feld.bekannt && feld.mittel > 0 && <p className="leise" style={{ margin: '.25rem 0 0' }}>Bereich {tonnen(feld.unten)} – {tonnen(feld.oben)} · {prozent(eingang > 0 ? feld.mittel / eingang : null)} des Eingangs</p>}
          {feld.bekannt && feld.mittel <= 0 && (
            <p className="leise" style={{ margin: '.25rem 0 0' }}>
              Die Messungen verlangen keinen Sockel: Der Fehler ohne Sockel ist ×{m?.sockel_nachweis?.toFixed(3) ?? '—'} des besten Fehlers mit Sockel, die Schwelle liegt bei ×{m?.sockel_schwelle?.toFixed(3) ?? '—'}. Darum steht a₀ auf 0 — nicht „kein Feldanteil", sondern „mit diesen Daten nicht von der Verderbskurve zu trennen".
            </p>
          )}
          <Rechenweg zeilen={rechenweg(feld, eingang)} />
        </Karte>
      )}

      <Karte titel="Verdunstung">
        <p className="leise">Jede gewogene Palette als Rate: Gewichtsverlust je Tag, bezogen auf das Eingangsgewicht. Paletten mit sichtbar Faulem zählen nicht — sonst würde Fäulnis als Wasserverlust verbucht.</p>
        <Diagramm reihen={[{ name: 'Palettenwägung', farbe: 'var(--strom-verdunstung)', punkte: raten }]}
                  xFormat={x => `${Math.round(x)}`} yFormat={y => `${y.toFixed(3)} %`} xTitel="Lagertage" yTitel="Verlust je Tag" yVon={0}
                  leer="noch keine Palette gewogen" />
      </Karte>

      <Sortenvergleich koeff={daten.sorten} />
      <WartetAufsWaschen bestand={daten.bestand} />

      <Karte titel="Buch B — anderer Kanal, verschenkte Marge">
        <p className="leise">Kein Lagerverlust: die Ware verlässt den Betrieb, nur nicht zum besten Preis — zu Kleine an die Tiere, zu Grosse in einen anderen Kanal, Überfüllung als Geschenk an den Kunden. Wird nie mit Buch A vermischt.</p>
        {daten.marge.length === 0 ? <p className="leise">Noch nichts gemessen.</p> : daten.marge.map(x => (
          <div key={x.posten} style={{ marginBottom: '1rem' }}>
            <div className="reihe"><strong>{x.posten}</strong><span style={{ marginLeft: 'auto' }}>{tonnen(x.kg)}</span></div>
            <p className="leise" style={{ margin: 0 }}>{x.erlaeuterung}</p>
          </div>
        ))}
        {daten.ueberfuellung.length > 0 && (
          <>
            <h3 style={{ marginTop: '1rem' }}>Überfüllung je Käufer</h3>
            <div className="rollbar">
              <table>
                <thead><tr><th>Käufer</th><th>Sorte</th><th className="zahl">Wägungen</th><th className="zahl">Kisten</th><th className="zahl">kg je Kiste</th><th className="zahl">Soll</th><th className="zahl">zu viel je Kiste</th><th className="zahl">verschenkt</th></tr></thead>
                <tbody>
                  {daten.ueberfuellung.slice().sort((a, b) => b.ueberfuellung_kg - a.ueberfuellung_kg).map(u => (
                    <tr key={`${u.kaeufer}${u.sorte}`}>
                      <td>{u.kaeufer_name}</td><td>{u.sorte}</td><td className="zahl">{u.n_wiegungen}</td><td className="zahl">{zahl(u.kisten)}</td>
                      <td className="zahl">{u.kg_pro_kiste.toFixed(2)}</td><td className="zahl">{u.soll_kg_pro_kiste.toFixed(1)}</td>
                      <td className="zahl">{u.ueberfuellung_je_kiste > 0 ? `+${u.ueberfuellung_je_kiste.toFixed(2)}` : '—'}</td>
                      <td className="zahl"><strong>{kg(u.ueberfuellung_kg, 0)}</strong></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </Karte>

      {daten.kaliber.length > 0 && <Kaliber zeilen={daten.kaliber} />}
      <Gewichtsverteilung daten={daten} />
    </>
  )
}

/** Wie sich die sortierten Kürbisse über die Kaliber verteilen — je Stück bezahlt. */
function Kaliber({ zeilen }: { zeilen: Kaliberzeile[] }) {
  const [sorte, setSorte] = useState('')
  const sorten = [...new Set(zeilen.map(z => z.sorte))].sort()
  const gezeigt = sorte ? sorten.filter(s => s === sorte) : sorten
  return (
    <Karte titel="Kaliber-Verteilung"
           aktion={<select value={sorte} onChange={e => setSorte(e.target.value)} style={{ width: 'auto', minHeight: 36 }}>
             <option value="">alle Sorten</option>{sorten.map(s => <option key={s}>{s}</option>)}</select>}>
      <p className="leise">Bezahlt wird je Stück innerhalb eines Kalibers — wer weiss, wo eine Sorte liegt, kann ein engeres Band liefern.</p>
      {gezeigt.map(s => {
        const eigene = zeilen.filter(z => z.sorte === s)
        const gesamt = eigene.reduce((a, z) => a + z.n_kuerbis, 0)
        const maximum = Math.max(...eigene.map(z => z.n_kuerbis), 1)
        const sortiert = [...eigene].sort((a, b) => (a.band_von ?? -1) - (b.band_von ?? -1))
        return (
          <div key={s} style={{ marginBottom: '1.5rem' }}>
            <div className="reihe"><strong>{s}</strong><span className="leise" style={{ marginLeft: 'auto' }}>{zahl(gesamt)} Kürbisse</span></div>
            {sortiert.map((z, i) => {
              const name = z.klasse === 'verlust_klein' ? 'zu klein (Tierfutter)' : z.klasse === 'nebenkanal' ? 'ab Grenze (anderer Kanal)' : `${z.band_von}–${z.band_bis} g`
              const farbe = z.klasse === 'verlust_klein' ? 'var(--strom-ausschuss)' : z.klasse === 'nebenkanal' ? 'var(--strom-nebenkanal)' : 'var(--kuerbis)'
              return (
                <div key={i} style={{ marginTop: '.4rem' }}>
                  <div className="reihe" style={{ fontSize: '.85rem' }}><span>{name}</span>
                    <span className="leise" style={{ marginLeft: 'auto' }}>{zahl(z.n_kuerbis)} · {prozent(gesamt > 0 ? z.n_kuerbis / gesamt : null)}</span></div>
                  <div className="balken-spur" style={{ height: 18 }}><div className="balken-fuellung" style={{ width: `${(z.n_kuerbis / maximum) * 100}%`, background: farbe }} /></div>
                </div>
              )
            })}
          </div>
        )
      })}
    </Karte>
  )
}

/** Die Gewichtsverteilung aus der CSV, mit den Kalibergrenzen darübergelegt (ABLAUF.md). */
function Gewichtsverteilung({ daten }: { daten: Auswertung }) {
  const [nach, setNach] = useState<'sorte' | 'schlag' | 'charge_nr'>('sorte')
  const [wahl, setWahl] = useState('')
  const [breite, setBreite] = useState(50)
  const werte = [...new Set(daten.gewichte.map(g => String(g[nach])))].sort()
  const aktiv = wahl && werte.includes(wahl) ? wahl : werte[0] ?? ''
  const auswahl = daten.gewichte.filter(g => String(g[nach]) === aktiv)
  const stufenMap = new Map<number, number>()
  for (const g of auswahl) { const x = Math.floor(g.stufe_g / breite) * breite; stufenMap.set(x, (stufenMap.get(x) ?? 0) + g.n) }
  const stufen = [...stufenMap.entries()].map(([x, n]) => ({ x, n })).sort((a, b) => a.x - b.x)
  const sorte = auswahl[0]?.sorte
  const schema = daten.schemata.find(s => s.sorte === sorte && s.art === 'kaliber' && s.kaeufer === null)
    ?? daten.schemata.find(s => s.sorte === sorte && s.art === 'kaliber')
  const grenzen: { x: number; text: string }[] = []
  if (schema?.verlust_unter != null) grenzen.push({ x: schema.verlust_unter, text: 'zu klein <' })
  ;(schema?.kaliber_baender ?? []).forEach(([a], i) => { if (i > 0) grenzen.push({ x: a, text: `K${i + 1}` }) })
  if (schema?.kanal_ab != null) grenzen.push({ x: schema.kanal_ab, text: 'zu gross ≥' })
  if (daten.gewichte.length === 0) return null
  return (
    <Karte titel="Gewichtsverteilung aus der Sortier-CSV">
      <p className="leise">Glockenförmig oder zweigipflig? Wo liegt der Schwerpunkt zu den Kalibergrenzen? Das ist eine Aussage über den Anbau, nicht über das Lager — nach Sorte, Schlag oder Charge.</p>
      <div className="reihe" style={{ marginBottom: '.5rem' }}>
        <select value={nach} onChange={e => { setNach(e.target.value as typeof nach); setWahl('') }} style={{ width: 'auto', minHeight: 36 }}>
          <option value="sorte">nach Sorte</option><option value="schlag">nach Schlag</option><option value="charge_nr">nach Charge</option>
        </select>
        <select value={aktiv} onChange={e => setWahl(e.target.value)} style={{ width: 'auto', minHeight: 36 }}>
          {werte.map(w => <option key={w}>{w}</option>)}
        </select>
        <select value={breite} onChange={e => setBreite(Number(e.target.value))} style={{ width: 'auto', minHeight: 36 }}>
          <option value={25}>25 g</option><option value={50}>50 g</option><option value={100}>100 g</option>
        </select>
      </div>
      <Histogramm stufen={stufen} breite={breite} grenzen={grenzen} xFormat={x => `${x}`}
                  titel={<>{aktiv}{sorte && nach !== 'sorte' ? ` · ${sorte}` : ''} · {zahl(auswahl.reduce((a, g) => a + g.n, 0))} Kürbisse{schema ? ` · Grenzen: Fassung vom ${schema.gilt_ab}` : ''}</>} />
    </Karte>
  )
}
