import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Balken, Hinweis, Karte, Marke, Rechenweg } from '../components/Bausteine'
import { Diagramm, Histogramm } from '../components/Diagramm'
import { stroemeSummieren, useAuswertung, useRanking, type Auswertung, type Kaliberzeile } from '../auswertung/daten'
import { Reiterkopf, Sortenvergleich, WartetAufsWaschen, rechenweg } from '../auswertung/Karten'
import { Lade } from '../components/Bausteine'
import type { Hochrechnung } from '../lib/typen'

/** Kennfarben für Reihen ohne festen Strom (Sorten im Verdunstungsbild). */
const REIHENFARBEN = ['var(--strom-verdunstung)', 'var(--strom-schimmel)', 'var(--strom-feld)',
                      'var(--strom-ausschuss)', 'var(--strom-nebenkanal)', 'var(--strom-fax)']

/**
 * Ursachen: Warum verliere ich — und wie sicher ist das? Jeder Strom mit
 * Balken, Bereich und Rechenweg; die Kurven mit ihren Messpunkten; das Faule
 * beim Abpacken (Fax) als eigener Strom; Buch B aufgeschlüsselt nach Sorte,
 * Charge und Arbeit; zum Schluss, was die Sortier-CSV über den Anbau sagt.
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

  // Verdunstung: je Wägung die Rate je Tag — eine Reihe je Sorte, dazu die
  // Sortenrate als Bezugslinie. So sieht man, ob die Rate über die Lagerdauer
  // wirklich konstant ist (das nimmt das Modell an) und wie stark sie streut.
  const wiegungen = daten.wiegungen
    .filter(w => !w.sichtbar_schimmel && w.netto_damals_kg && w.lagertage > 0 && w.verlust_kg !== null)
    .filter(w => !sorte || w.sorte === sorte)
  const ratenSorten = [...new Set(wiegungen.map(w => w.sorte))].sort()
  const ratenReihen = ratenSorten.map((s, i) => ({
    name: s, farbe: REIHENFARBEN[i % REIHENFARBEN.length],
    punkte: wiegungen.filter(w => w.sorte === s)
      .map(w => ({ x: w.lagertage, y: (w.verlust_kg! / (w.netto_damals_kg! * w.lagertage)) * 100, text: `Charge ${w.charge_nr} · ${datum(w.wiege_ts)}` })),
  }))
  // Sorten ohne eigene Messreihe rechnen mit dem Gesamtwert — die teilen
  // sich eine Linie, sonst stünden vier Beschriftungen übereinander.
  const ratenLinien = (() => {
    const gruppen = new Map<string, { y: number; sorten: string[]; farbe: string }>()
    ratenSorten.forEach((s, i) => {
      const k = daten.sorten.verdunstung.find(x => x.sorte === s)
      if (k?.mittel == null || k.n <= 0) return
      const y = k.mittel * 100, key = y.toFixed(4)
      const g = gruppen.get(key)
      if (g) g.sorten.push(s)
      else gruppen.set(key, { y, sorten: [s], farbe: REIHENFARBEN[i % REIHENFARBEN.length] })
    })
    return [...gruppen.values()].map(g => ({
      y: g.y, farbe: g.sorten.length > 1 ? 'var(--text-leise)' : g.farbe,
      text: `${g.sorten.length > 2 ? `${g.sorten.length} Sorten` : g.sorten.join(', ')} ${g.y.toFixed(3)} %`,
    }))
  })()

  // Buch B, aufgeschlüsselt: die Marge-Ströme je Sorte und je Charge
  const margeZeilen = gefiltert.filter(z => z.buch === 'marge')
  const nachSorte = gruppieren(margeZeilen, z => z.sorte)
  const nachCharge = gruppieren(margeZeilen, z => `${z.charge_nr}`)
  const sollJeSorte = (s: string) => daten.schemata.find(x => x.sorte === s && x.art === 'kiste' && x.kaeufer === null) ?? daten.schemata.find(x => x.sorte === s && x.art === 'kiste')
  const kisteKg = (s: string) => {
    const g = daten.gebinde.find(x => x.sorte === s && x.kaliber_idx === -1)
    return g?.kg_je_gebinde ?? (sollJeSorte(s) as { soll_kg_pro_kiste?: number | null } | undefined)?.soll_kg_pro_kiste ?? null
  }
  const ausschussZeilen = daten.ausschuss.filter(a => (!sorte || a.sorte === sorte))
    .filter(a => (a.klein_kg ?? 0) + (a.gross_kg ?? 0) > 0)
    .sort((a, b) => ((b.klein_kg ?? 0) + (b.gross_kg ?? 0)) - ((a.klein_kg ?? 0) + (a.gross_kg ?? 0)))

  // Fax: je Arbeit beobachtet
  const fax = daten.fax.filter(f => (!sorte || f.sorte === sorte) && f.status === 'abgeschlossen')
  const faxMasse = fax.reduce((a, f) => a + (f.masse_kg ?? 0), 0)
  const faxFaul = fax.reduce((a, f) => a + f.faul_kg, 0)
  const faxStrom = stroeme.find(s => s.strom === 'Faul beim Abpacken (Fax)')

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
        <p className="leise">Was physisch verschwindet, solange die Ware im Haus ist: Wasser (Verdunstung), Fäulnis im Lager (nach der Lagerdauer), und das Faule, das beim Etikettieren und Abpacken noch herauskommt (nach dem Waschen, nicht nach der Zeit).</p>
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
        <p className="leise">Jeder Punkt eine Wägung des Faulen: Anteil der Masse, die an dem Tag aus dem Lager kam. Die Linie ist die Kurve, die die Auswertung verwendet, der Streifen ihr Bereich. Rechts der letzten Messung ist alles Hochrechnung. Das Faule beim Abpacken (Fax) ist hier absichtlich nicht dabei — es kommt vom Waschen, nicht von der Lagerdauer.</p>
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

      <Karte titel="Faul beim Abpacken (Fax)">
        <p className="leise">Nach dem Waschen steht die Ware in Kisten, bis eine Bestellung kommt. Beim Etikettieren wird nochmals aussortiert, was faul ist — das kommt von der Beanspruchung beim Waschen und vom Stehen danach, nicht von der Lagerdauer. Deshalb ein eigener Strom mit eigenem Koeffizienten: Faules je Masse, die durch das Fax ging. Die Massnahme dagegen ist eine andere als gegen den Lagerschimmel (sanfter waschen, kürzer stehen lassen).</p>
        {fax.length === 0 ? (
          <Hinweis art="info">Noch keine abgeschlossene Fax-Arbeit mit gezählten Kisten und gewogenem Faulem. Der Strom ist unbekannt — nicht null. Er wird beziffert, sobald die erste Fax-Arbeit über die Arbeiter-App läuft.</Hinweis>
        ) : (
          <>
            <div className="spalten" style={{ marginBottom: '.75rem' }}>
              <div><div className="leise">Fax-Arbeiten</div><strong>{fax.length}</strong></div>
              <div><div className="leise">Durchs Fax gegangen</div><strong>{tonnen(faxMasse + faxFaul)}</strong></div>
              <div><div className="leise">Davon faul</div><strong>{kg(faxFaul, 0)}</strong><div className="leise">{prozent(faxMasse + faxFaul > 0 ? faxFaul / (faxMasse + faxFaul) : null)}</div></div>
              {faxStrom?.bekannt && <div><div className="leise">Hochgerechnet auf alle Ware</div><strong>{tonnen(faxStrom.mittel)}</strong><div className="leise">{faxStrom.koeffBasis}</div></div>}
            </div>
            <div className="rollbar">
              <table>
                <thead><tr><th>Datum</th><th>Charge</th><th>Sorte</th><th>Käufer</th><th className="zahl">Kisten</th><th className="zahl">Masse</th><th className="zahl">Faules</th><th className="zahl">Anteil</th></tr></thead>
                <tbody>
                  {fax.slice(0, 40).map(f => (
                    <tr key={f.auftrag_id} className={f.plausibel ? '' : 'leise'}>
                      <td>{datum(f.start_ts)}</td>
                      <td><Link to={`/chargen?charge=${f.charge_nr}`}>{f.charge_nr}</Link></td>
                      <td>{f.sorte}</td><td>{f.kaeufer ?? <span className="leise">—</span>}</td>
                      <td className="zahl">{zahl(f.kisten)}</td>
                      <td className="zahl">{f.masse_kg != null ? kg(f.masse_kg, 0) : <Marke art="warnung">Kistengewicht fehlt</Marke>}</td>
                      <td className="zahl"><strong>{kg(f.faul_kg, 0)}</strong>{!f.faul_erfasst && <span className="leise"> nicht gewogen</span>}</td>
                      <td className="zahl">{f.anteil != null ? prozent(f.anteil) : '—'}{!f.plausibel && <> <Marke art="warnung">unplausibel</Marke></>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {fax.length > 40 && <p className="leise" style={{ margin: '.4rem 0 0' }}>Die jüngsten 40 von {fax.length} Fax-Arbeiten; jede einzelne lässt sich unter Betrieb → Arbeiten öffnen.</p>}
          </>
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
        <p className="leise">Jede gewogene Palette als Rate: Gewichtsverlust je Tag in Prozent des Eingangsgewichts, über der Lagerdauer beim Wiegen. Die gestrichelte Linie ist die Rate, mit der die Auswertung für die Sorte rechnet. Liegen die Punkte waagrecht, ist die Rate über die Lagerdauer konstant — so nimmt es das Modell an; die Streuung um die Linie ist der Messfehler einzelner Paletten. Paletten mit sichtbar Faulem zählen nicht — sonst würde Fäulnis als Wasserverlust verbucht.</p>
        <Diagramm reihen={ratenReihen} waagrechte={ratenLinien}
                  xFormat={x => `${Math.round(x)}`} yFormat={y => `${y.toFixed(3)} %`} xTitel="Lagertage beim Wiegen" yTitel="Verlust je Tag"
                  leer="noch keine Palette gewogen" />
      </Karte>

      <Sortenvergleich koeff={daten.sorten} />
      <WartetAufsWaschen bestand={daten.bestand} />

      <Karte titel="Buch B — anderer Kanal, verschenkte Marge">
        <p className="leise">Kein Lagerverlust: die Ware verlässt den Betrieb, nur nicht zum besten Preis — zu Kleine an die Tiere, zu Grosse in einen anderen Kanal, Überfüllung als Geschenk an den Kunden. Wird nie mit Buch A vermischt. Unten steht, woher jede Zahl kommt: je Sorte, je Charge, je Arbeit.</p>
        {daten.marge.length === 0 ? <p className="leise">Noch nichts gemessen.</p> : daten.marge.map(x => (
          <div key={x.posten} style={{ marginBottom: '1rem' }}>
            <div className="reihe"><strong>{x.posten}</strong><span style={{ marginLeft: 'auto' }}>{tonnen(x.kg)}</span></div>
            <p className="leise" style={{ margin: 0 }}>{x.erlaeuterung}{x.kg_unten != null && x.kg_oben != null && <> · Bereich {tonnen(x.kg_unten)} – {tonnen(x.kg_oben)}</>}</p>
          </div>
        ))}

        {nachSorte.length > 0 && (
          <>
            <h3 style={{ marginTop: '1rem' }}>Je Sorte</h3>
            <p className="leise" style={{ margin: '0 0 .4rem' }}>Beobachtet = an verarbeiteter Ware gemessen; projiziert = für die Ware im Lager mit dem Sorten-Anteil gerechnet. Kisten: die Masse in Kisten zu dem, was eine Kiste dieser Sorte wiegt.</p>
            <div className="rollbar"><table>
              <thead><tr><th>Sorte</th><th className="zahl">Zu klein (Tierfutter)</th><th className="zahl">davon beobachtet</th><th className="zahl">Nebenkanal zu gross</th><th className="zahl">davon beobachtet</th><th className="zahl">zusammen</th><th className="zahl">≈ Kisten</th></tr></thead>
              <tbody>{nachSorte.map(g => {
                const kk = kisteKg(g.name)
                return (
                  <tr key={g.name}>
                    <td>{g.name}</td>
                    <td className="zahl">{kg(g.klein, 0)}</td><td className="zahl leise">{kg(g.kleinBeob, 0)}</td>
                    <td className="zahl">{kg(g.gross, 0)}</td><td className="zahl leise">{kg(g.grossBeob, 0)}</td>
                    <td className="zahl"><strong>{kg(g.klein + g.gross, 0)}</strong></td>
                    <td className="zahl">{kk ? `${zahl(Math.round((g.klein + g.gross) / kk))} à ${kk.toFixed(1)} kg` : <span className="leise">Kistengewicht unbekannt</span>}</td>
                  </tr>
                )
              })}</tbody>
            </table></div>
          </>
        )}

        {nachCharge.length > 0 && (
          <>
            <h3 style={{ marginTop: '1rem' }}>Je Charge</h3>
            <div className="rollbar"><table>
              <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">Zu klein</th><th className="zahl">Nebenkanal</th><th className="zahl">zusammen</th><th className="zahl">Anteil am Eingang</th></tr></thead>
              <tbody>{nachCharge.slice(0, 15).map(g => (
                <tr key={g.name}>
                  <td><Link to={`/chargen?charge=${g.name}`}>{g.name}</Link></td><td>{g.sorte}</td>
                  <td className="zahl">{kg(g.klein, 0)}</td><td className="zahl">{kg(g.gross, 0)}</td>
                  <td className="zahl"><strong>{kg(g.klein + g.gross, 0)}</strong></td>
                  <td className="zahl">{prozent(g.eingang > 0 ? (g.klein + g.gross) / g.eingang : null)}</td>
                </tr>
              ))}</tbody>
            </table></div>
            {nachCharge.length > 15 && <p className="leise">Die 15 grössten von {nachCharge.length} Chargen.</p>}
          </>
        )}

        {ausschussZeilen.length > 0 && (
          <>
            <h3 style={{ marginTop: '1rem' }}>Je Arbeit — die Messungen dahinter</h3>
            <p className="leise" style={{ margin: '0 0 .4rem' }}>Maschine: aus der Sortier-CSV (jeder Kürbis gewogen). Hand: die gewogenen Ausschuss-Paletten der Arbeit. Bezugsmasse ist, was an dem Tag am Band ankam.</p>
            <div className="rollbar"><table>
              <thead><tr><th>Charge</th><th>Sorte</th><th>Woher</th><th className="zahl">Bezugsmasse</th><th className="zahl">Zu klein</th><th className="zahl">Zu gross</th><th className="zahl">Anteil</th></tr></thead>
              <tbody>{ausschussZeilen.slice(0, 20).map((a, i) => (
                <tr key={i} className={a.plausibel ? '' : 'leise'}>
                  <td><Link to={`/chargen?charge=${a.charge_nr}`}>{a.charge_nr}</Link></td><td>{a.sorte}</td>
                  <td>{a.weg === 'maschine' ? 'Sortier-CSV' : 'Hand, gewogen'}{a.auftrag_id && <> · <Link to={`/arbeit/${a.auftrag_id}`}>Arbeit</Link></>}</td>
                  <td className="zahl">{kg(a.basis_kg, 0)}</td>
                  <td className="zahl">{kg(a.klein_kg, 0)}</td><td className="zahl">{kg(a.gross_kg, 0)}</td>
                  <td className="zahl">{prozent(a.basis_kg > 0 ? ((a.klein_kg ?? 0) + (a.gross_kg ?? 0)) / a.basis_kg : null)}{!a.plausibel && <> <Marke art="warnung">unplausibel</Marke></>}</td>
                </tr>
              ))}</tbody>
            </table></div>
          </>
        )}

        {daten.ueberfuellung.length > 0 && (
          <>
            <h3 style={{ marginTop: '1rem' }}>Überfüllung je Käufer</h3>
            <p className="leise" style={{ margin: '0 0 .4rem' }}>Nur Arbeiten nach „Kiste ab x kg" — nach Kaliber gibt es kein Sollgewicht und nichts zu verschenken.</p>
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

interface Gruppe { name: string; sorte: string; eingang: number; klein: number; kleinBeob: number; gross: number; grossBeob: number }

/** Die Marge-Ströme nach einem Schlüssel zusammenfassen — beobachtet getrennt von projiziert. */
function gruppieren(zeilen: Hochrechnung[], schluessel: (z: Hochrechnung) => string): Gruppe[] {
  const map = new Map<string, Gruppe & { chargen: Set<number> }>()
  for (const z of zeilen) {
    if (z.kg === null) continue
    const k = schluessel(z)
    let g = map.get(k)
    if (!g) { g = { name: k, sorte: z.sorte, eingang: 0, klein: 0, kleinBeob: 0, gross: 0, grossBeob: 0, chargen: new Set() }; map.set(k, g) }
    if (!g.chargen.has(z.charge_nr)) { g.chargen.add(z.charge_nr); g.eingang += z.eingang_kg }
    const beob = z.portion === 'ausgelagert'
    if (z.strom === 'Zu klein (Tierfutter)') { g.klein += z.kg; if (beob) g.kleinBeob += z.kg }
    else if (z.strom === 'Nebenkanal zu gross') { g.gross += z.kg; if (beob) g.grossBeob += z.kg }
  }
  return [...map.values()].sort((a, b) => (b.klein + b.gross) - (a.klein + a.gross))
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
  const gesamt = auswahl.reduce((a, g) => a + g.n, 0)
  // Schwerpunkt und Spannweite — die zwei Zahlen, die man aus dem Bild ablesen will
  const mittel = gesamt > 0 ? auswahl.reduce((a, g) => a + (g.stufe_g + 12.5) * g.n, 0) / gesamt : null
  return (
    <Karte titel="Gewichtsverteilung aus der Sortier-CSV">
      <p className="leise">Wie schwer sind die Kürbisse, die die Maschine gewogen hat? Glockenförmig oder zweigipflig, und wo liegt der Schwerpunkt zu den Kalibergrenzen (gestrichelt)? Das ist eine Aussage über den Anbau, nicht über das Lager — nach Sorte, Schlag oder Charge.</p>
      <div className="reihe" style={{ marginBottom: '.5rem', alignItems: 'end', flexWrap: 'wrap' }}>
        <div className="feld" style={{ margin: 0 }}><label htmlFor="gv-nach">Ansicht</label>
          <select id="gv-nach" value={nach} onChange={e => { setNach(e.target.value as typeof nach); setWahl('') }} style={{ width: 'auto', minHeight: 36 }}>
            <option value="sorte">nach Sorte</option><option value="schlag">nach Schlag</option><option value="charge_nr">nach Charge</option>
          </select></div>
        <div className="feld" style={{ margin: 0 }}><label htmlFor="gv-wahl">{nach === 'sorte' ? 'Sorte' : nach === 'schlag' ? 'Schlag' : 'Charge'}</label>
          <select id="gv-wahl" value={aktiv} onChange={e => setWahl(e.target.value)} style={{ width: 'auto', minHeight: 36 }}>
            {werte.map(w => <option key={w}>{w}</option>)}
          </select></div>
        <div className="feld" style={{ margin: 0 }}><label htmlFor="gv-breite">Stufenbreite</label>
          <select id="gv-breite" value={breite} onChange={e => setBreite(Number(e.target.value))} style={{ width: 'auto', minHeight: 36 }}>
            <option value={25}>25 g (fein)</option><option value={50}>50 g</option><option value={100}>100 g (grob)</option>
          </select></div>
      </div>
      <Histogramm stufen={stufen} breite={breite} grenzen={grenzen} xFormat={x => `${x}`}
                  titel={<>{aktiv}{sorte && nach !== 'sorte' ? ` · ${sorte}` : ''} · {zahl(gesamt)} Kürbisse{mittel !== null ? ` · Schwerpunkt ${Math.round(mittel)} g` : ''}{schema ? ` · Grenzen: Fassung vom ${schema.gilt_ab}` : ''}</>} />
      <p className="leise" style={{ margin: '.5rem 0 0' }}>
        <strong>Stufenbreite</strong> heisst: wie viele Gramm ein Balken zusammenfasst. Bei 25 g steht jede Stufe für sich — viele schmale Balken, die Form ist fein, aber unruhig. Bei 100 g werden vier Stufen zu einem Balken — weniger Balken, jeder höher, die Form wird glatter. Die Fläche unter den Balken bleibt dieselbe: es sind immer dieselben {zahl(gesamt)} Kürbisse. Ein Kürbis zählt in der Stufe, in der sein Gewicht liegt (450 g → Stufe 450 bei 25 g, Stufe 400 bei 100 g).
      </p>
    </Karte>
  )
}
