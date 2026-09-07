import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Balken, Hinweis, Karte, Kennzahl, Lade, Marke, Rechenweg } from '../components/Bausteine'
import { Diagramm, Histogramm } from '../components/Diagramm'
import { STROMFARBE, kaliberJeSorte, stroemeSummieren, useAuswertung, useRanking, type Auswertung, type SortenK, type StromSumme } from '../auswertung/daten'
import { Reiterkopf, rechenweg } from '../auswertung/Karten'
import type { Hochrechnung } from '../lib/typen'

/** Kennfarben für Reihen ohne festen Strom (Sorten im Verdunstungsbild). */
const REIHENFARBEN = ['var(--strom-verdunstung)', 'var(--strom-schimmel)', 'var(--strom-feld)',
                      'var(--strom-ausschuss)', 'var(--strom-nebenkanal)', 'var(--strom-fax)']

/**
 * Ursachen: vier Ursachen, jede in der Tiefe — je Sorte und je Charge, mit
 * den Messpunkten dahinter. Nur, was gemessen ist: Raten aus Stichproben,
 * hochgerechnet auf die gemessene Eingangsmasse. Keine Ratschläge für die
 * Saison, keine Mengen, die niemand gezählt hat.
 */
export default function Ursachen() {
  const { daten, laedt, fehler, neuRechnen } = useAuswertung()
  const [params, setParams] = useSearchParams()
  const sorte = params.get('sorte') ?? ''
  const schlag = params.get('schlag') ?? ''
  const filterSetzen = (k: 'sorte' | 'schlag', v: string) => {
    const p = new URLSearchParams(params)
    if (v) p.set(k, v); else p.delete(k)
    setParams(p, { replace: true })
  }
  const ranking = useRanking(sorte, schlag, '', daten?.stand ?? null)

  const zeilen = daten?.hochrechnung ?? []
  const sorten = useMemo(() => [...new Set(zeilen.map(z => z.sorte))].sort(), [zeilen])
  const schlaege = useMemo(() => [...new Set(zeilen.map(z => z.schlag))].sort(), [zeilen])
  const gefiltert = useMemo(() => zeilen.filter(z => (!sorte || z.sorte === sorte) && (!schlag || z.schlag === schlag)), [zeilen, sorte, schlag])
  const stroeme = useMemo(() => stroemeSummieren(gefiltert, ranking), [gefiltert, ranking])

  if (laedt && !daten) return <Lade text="Auswertung wird gerechnet …" />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null

  const proCharge = new Map<number, number>()
  for (const z of gefiltert) proCharge.set(z.charge_nr, z.eingang_kg)
  const eingang = [...proCharge.values()].reduce((a, b) => a + b, 0)
  const chargenImFilter = new Set(proCharge.keys())
  const strom = (name: string) => stroeme.find(s => s.strom === name)
  const maximum = Math.max(...stroeme.filter(s => s.bekannt).map(s => Math.max(s.mittel, s.oben)), 1)

  return (
    <>
      <Reiterkopf titel="Ursachen" zweck="Vier Ursachen, jede in der Tiefe: je Sorte, je Charge, und die Messungen dahinter."
                  stand={daten.stand} neuRechnen={() => void neuRechnen()} />

      <Karte>
        <div className="spalten" style={{ alignItems: 'end' }}>
          <div className="feld" style={{ margin: 0 }}><label htmlFor="fs">Sorte</label>
            <select id="fs" value={sorte} onChange={e => filterSetzen('sorte', e.target.value)}><option value="">alle</option>{sorten.map(s => <option key={s}>{s}</option>)}</select></div>
          <div className="feld" style={{ margin: 0 }}><label htmlFor="fl">Schlag</label>
            <select id="fl" value={schlag} onChange={e => filterSetzen('schlag', e.target.value)}><option value="">alle</option>{schlaege.map(s => <option key={s}>{s}</option>)}</select></div>
          <p className="leise" style={{ margin: 0 }}>
            {sorte || schlag
              ? <>Gefiltert: {[sorte, schlag].filter(Boolean).join(' · ')} — {tonnen(eingang)} Eingang in {chargenImFilter.size} Chargen.{' '}
                  <button className="klein" onClick={() => setParams({}, { replace: true })}>alles zeigen</button></>
              : <>Alle Sorten und Schläge — {tonnen(eingang)} Eingang in {chargenImFilter.size} Chargen.</>}
          </p>
        </div>
      </Karte>

      <Verderb daten={daten} strom={strom('Schimmel/Fäulnis')} feld={strom('Nicht lagerbedingt')} eingang={eingang} maximum={maximum} sorte={sorte} chargen={chargenImFilter} />
      <Verdunstung daten={daten} strom={strom('Verdunstung')} eingang={eingang} maximum={maximum} sorte={sorte} chargen={chargenImFilter} />
      <Sortierung daten={daten} gefiltert={gefiltert} klein={strom('Zu klein (Tierfutter)')} gross={strom('Nebenkanal zu gross')} eingang={eingang} maximum={maximum} sorte={sorte} />
      <Fax daten={daten} strom={strom('Faul beim Abpacken (Fax)')} eingang={eingang} maximum={maximum} sorte={sorte} chargen={chargenImFilter} />
    </>
  )
}

/* ---------- Bausteine der vier Ursachen ----------------------------------- */

/** Kopf einer Ursache: Tonnen, Anteil, Bereich als Balken, Rechenweg. */
function Ursachenkopf({ v, eingang, maximum }: { v: StromSumme | undefined; eingang: number; maximum: number }) {
  if (!v) return <p className="leise">Für diesen Filter gibt es keine Zeile.</p>
  return (
    <div style={{ marginBottom: '.75rem' }}>
      <div className="reihe">
        <span aria-hidden="true" style={{ width: 10, height: 10, borderRadius: 2, background: STROMFARBE[v.strom], display: 'inline-block' }} />
        <strong style={{ fontSize: '1.2rem' }}>{v.bekannt ? tonnen(v.mittel) : '—'}</strong>
        {v.bekannt && <span className="leise">{prozent(eingang > 0 ? v.mittel / eingang : null)} des Eingangs · Bereich {tonnen(v.unten)} – {tonnen(v.oben)}</span>}
        {!v.bekannt && <Marke art="warnung">nicht gemessen — unbekannt, nicht null</Marke>}
        {v.bekannt && (v.koeffN ?? 0) < 3 && <Marke art="warnung">dünne Datenlage</Marke>}
      </div>
      <Balken wert={v.bekannt ? v.mittel : null} unten={v.unten} oben={v.oben} maximum={maximum} beobachtet={v.beobachtet} />
      <Rechenweg zeilen={rechenweg(v, eingang)} />
    </div>
  )
}

/** Verderb im Lager: die Kurve, ihre Punkte, und je Charge gemessen gegen Modell. */
function Verderb({ daten, strom, feld, eingang, maximum, sorte, chargen }: {
  daten: Auswertung; strom?: StromSumme; feld?: StromSumme; eingang: number; maximum: number; sorte: string; chargen: Set<number>
}) {
  const m = daten.modell
  const punkte = daten.punkte.filter(p => p.plausibel && p.anteil !== null && chargen.has(p.charge_nr) && (!sorte || p.sorte === sorte))
  const kurveReihe = daten.kurve.filter(k => k.verwendet !== null).map(k => {
    const mitte = (k.von + Math.min(k.bis, k.von + 60)) / 2
    return { x: mitte, y: (k.verwendet ?? 0) * 100, unten: (k.unten ?? k.verwendet ?? 0) * 100, oben: (k.oben ?? k.verwendet ?? 0) * 100, text: k.altersklasse }
  })
  const modellBei = (t: number) => {
    const k = daten.kurve.find(x => t >= x.von && t < x.bis) ?? daten.kurve[daten.kurve.length - 1]
    return k?.verwendet ?? null
  }
  // Je Charge: gemessen (massegewichtet) gegen das Modell beim mittleren Alter der Messungen
  const jeCharge = (() => {
    const map = new Map<number, { charge_nr: number; sorte: string; n: number; tMin: number; tMax: number; tSumme: number; faul: number; basis: number }>()
    for (const p of punkte) {
      if (p.quelle === 'verarbeitung_gemischt') continue
      let e = map.get(p.charge_nr)
      if (!e) { e = { charge_nr: p.charge_nr, sorte: p.sorte, n: 0, tMin: p.lagertage, tMax: p.lagertage, tSumme: 0, faul: 0, basis: 0 }; map.set(p.charge_nr, e) }
      e.n++; e.tMin = Math.min(e.tMin, p.lagertage); e.tMax = Math.max(e.tMax, p.lagertage); e.tSumme += p.lagertage
      e.faul += p.schimmel_kg; e.basis += p.basis_jetzt_kg
    }
    return [...map.values()].map(e => {
      const gemessen = e.basis > 0 ? e.faul / e.basis : null
      const modell = modellBei(e.tSumme / e.n)
      return { ...e, gemessen, modell, abweichung: gemessen !== null && modell !== null ? gemessen - modell : null }
    }).sort((a, b) => b.n - a.n || b.basis - a.basis)
  })()
  return (
    <Karte titel="Verderb im Lager (Schimmel, Fäulnis)">
      <p className="leise">Was im Palox landet, wenn eine Palette ans Band oder ans Waschbecken kommt — bezogen auf die Masse, die an dem Tag aus dem Lager kam, und aufgetragen über der Lagerdauer. Daraus die Kurve, mit der für alle Ware gerechnet wird.</p>
      <Ursachenkopf v={strom} eingang={eingang} maximum={maximum} />
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
            ? <>Kurve F(t) = 1 − exp(−λ·t<sup>k</sup>), k = {m.k?.toFixed(2)}, angepasst an {m.n} Messungen aus {m.c_chargen} Chargen über {Math.round(m.t_min)}–{Math.round(m.t_max)} Lagertage. Rechts davon ist alles Hochrechnung, und der Streifen wird breiter.</>
            : <>Für eine Kurve reicht es noch nicht — nötig sind Messungen aus mindestens drei Chargen über deutlich verschiedene Lagerdauern. Solange gilt der zuletzt gemessene Wert.</>}
          {daten.selektion && <> {daten.selektion.befund}</>}
          {feld?.bekannt && feld.mittel > 0 && <> Dazu <strong>{tonnen(feld.mittel)}</strong> nicht lagerbedingt (Erde, Hagelnarben, Schnittfehler) — im selben Palox, aber nicht von der Lagerdauer; das Modell trennt sie als Sockel ab.</>}
        </p>
      )}
      {jeCharge.length > 0 && (
        <>
          <h3 style={{ margin: '1rem 0 .4rem' }}>Je Charge: gemessen gegen Modell</h3>
          <p className="leise" style={{ margin: '0 0 .4rem' }}>Gemessen = alles Faule dieser Charge zu allem, was von ihr aus dem Lager kam. Modell = die Kurve beim mittleren Alter dieser Messungen. Eine Charge deutlich über der Kurve verdirbt schneller als ihre Sorte — das ist eine Beobachtung, keine Erklärung.</p>
          <div className="rollbar"><table>
            <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">Messungen</th><th className="zahl">Lagertage</th><th className="zahl">Gemessen</th><th className="zahl">Modell</th><th className="zahl">Abweichung</th></tr></thead>
            <tbody>{jeCharge.slice(0, 20).map(e => (
              <tr key={e.charge_nr}>
                <td><Link to={`/chargen?charge=${e.charge_nr}`}>{e.charge_nr}</Link></td><td>{e.sorte}</td>
                <td className="zahl">{e.n}</td>
                <td className="zahl">{Math.round(e.tMin) === Math.round(e.tMax) ? Math.round(e.tMin) : `${Math.round(e.tMin)}–${Math.round(e.tMax)}`}</td>
                <td className="zahl"><strong>{prozent(e.gemessen)}</strong></td>
                <td className="zahl">{prozent(e.modell)}</td>
                <td className="zahl">{e.abweichung === null ? '—' : <span style={{ color: e.abweichung > 0.02 ? 'var(--rot)' : e.abweichung < -0.02 ? 'var(--strom-rest)' : undefined }}>{e.abweichung > 0 ? '+' : ''}{(e.abweichung * 100).toFixed(1)} Pkt.</span>}</td>
              </tr>
            ))}</tbody>
          </table></div>
          {jeCharge.length > 20 && <p className="leise">Die 20 meistgemessenen von {jeCharge.length} Chargen.</p>}
        </>
      )}
    </Karte>
  )
}

/** Verdunstung: gewogene Paletten als kumulierter Verlust über der Lagerdauer, die Sortenrate als Linie. */
function Verdunstung({ daten, strom, eingang, maximum, sorte, chargen }: {
  daten: Auswertung; strom?: StromSumme; eingang: number; maximum: number; sorte: string; chargen: Set<number>
}) {
  const wiegungen = daten.wiegungen
    .filter(w => !w.sichtbar_schimmel && w.netto_damals_kg && w.lagertage > 0 && w.verlust_kg !== null)
    .filter(w => chargen.has(w.charge_nr) && (!sorte || w.sorte === sorte))
  const sorten = [...new Set(wiegungen.map(w => w.sorte))].sort()
  const tMax = Math.max(...wiegungen.map(w => w.lagertage), 30)
  const rate = (s: string) => daten.sorten.verdunstung.find(k => k.sorte === s)
  const punktReihen = sorten.map((s, i) => ({
    name: s, farbe: REIHENFARBEN[i % REIHENFARBEN.length],
    punkte: wiegungen.filter(w => w.sorte === s)
      .map(w => ({ x: w.lagertage, y: (w.verlust_kg! / w.netto_damals_kg!) * 100, text: `Charge ${w.charge_nr} · ${datum(w.wiege_ts)}` })),
  }))
  // Die Modelllinie je Sorte: 1 − (1 − r)^t — was die Auswertung für diese Sorte rechnet
  // Sorten ohne eigene Messreihe rechnen mit dem Gesamtwert — die teilen
  // sich eine Linie, sonst lägen fünf gestrichelte Linien übereinander.
  const linien = (() => {
    const gruppen = new Map<string, { r: number; sorten: string[]; farbe: string }>()
    sorten.forEach((s, i) => {
      const r = rate(s)?.mittel
      if (r == null) return
      const key = r.toFixed(6)
      const g = gruppen.get(key)
      if (g) g.sorten.push(s); else gruppen.set(key, { r, sorten: [s], farbe: REIHENFARBEN[i % REIHENFARBEN.length] })
    })
    const schritte = 12
    return [...gruppen.values()].map(g => ({
      name: g.sorten.length > 1 ? `Modell: ${g.sorten.length} Sorten mit dem Gesamtwert` : `${g.sorten[0]} (Modell)`,
      farbe: g.sorten.length > 1 ? 'var(--text-leise)' : g.farbe, linie: true, marker: false, gestrichelt: true,
      punkte: Array.from({ length: schritte + 1 }, (_, k) => { const t = (tMax * k) / schritte; return { x: t, y: (1 - Math.pow(1 - g.r, t)) * 100 } }),
    }))
  })()
  const eigene = (k: SortenK) => k.basis?.includes('dieser Sorte')
  const tabelle = daten.sorten.verdunstung.filter(k => k.n > 0 && (!sorte || k.sorte === sorte)).sort((a, b) => (a.mittel ?? 0) - (b.mittel ?? 0))
  return (
    <Karte titel="Verdunstung">
      <p className="leise">Jede gewogene Palette: wie viel Prozent ihres Eingangsgewichts sie bis zum Wiegen verloren hat, über der Lagerdauer. Die gestrichelte Linie ist, was die Auswertung für die Sorte rechnet — liegen die Punkte um sie herum, trägt die Rate; liegen sie systematisch darüber oder darunter, stimmt sie nicht. Paletten mit sichtbar Faulem zählen nicht, sonst würde Fäulnis als Wasser verbucht.</p>
      <Ursachenkopf v={strom} eingang={eingang} maximum={maximum} />
      <Diagramm reihen={[...linien, ...punktReihen]}
                xFormat={x => `${Math.round(x)}`} yFormat={y => `${y.toFixed(1)} %`} xTitel="Lagertage beim Wiegen" yTitel="Gewicht verloren" yVon={0}
                leer="noch keine Palette gewogen" />
      {tabelle.length > 0 && (
        <>
          <h3 style={{ margin: '1rem 0 .4rem' }}>Je Sorte</h3>
          <p className="leise" style={{ margin: '0 0 .4rem' }}>Nach Rate sortiert — oben hält am besten. Grau: zu wenige eigene Messungen, es gilt der Gesamtwert aller Sorten.</p>
          <div className="rollbar"><table>
            <thead><tr><th>Sorte</th><th className="zahl">je Tag</th><th className="zahl">nach 100 Tagen</th><th className="zahl">Bereich je Tag</th><th className="zahl">gewogene Paletten</th></tr></thead>
            <tbody>{tabelle.map(k => (
              <tr key={k.sorte} className={eigene(k) ? '' : 'leise'}>
                <td>{k.sorte}</td>
                <td className="zahl">{k.mittel == null ? '—' : `${(k.mittel * 100).toFixed(3)} %`}</td>
                <td className="zahl"><strong>{k.mittel == null ? '—' : prozent(1 - Math.pow(1 - k.mittel, 100))}</strong></td>
                <td className="zahl">{k.unten != null && k.oben != null ? `${(k.unten * 100).toFixed(3)}–${(k.oben * 100).toFixed(3)} %` : '—'}</td>
                <td className="zahl">{k.n}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </>
      )}
    </Karte>
  )
}

/** Sortierung: zu klein und zu gross je Sorte und Charge, die Kaliber, die Gewichtsverteilung, die Überfüllung. */
function Sortierung({ daten, gefiltert, klein, gross, eingang, maximum, sorte }: {
  daten: Auswertung; gefiltert: Hochrechnung[]; klein?: StromSumme; gross?: StromSumme; eingang: number; maximum: number; sorte: string
}) {
  const nachCharge = gruppieren(gefiltert.filter(z => z.buch === 'marge'), z => `${z.charge_nr}`)
  const jeSorte = [...new Set(gefiltert.map(z => z.sorte))].sort().map(s => ({
    sorte: s,
    klein: daten.sorten.ausschuss.find(k => k.sorte === s),
    gross: daten.sorten.nebenkanal.find(k => k.sorte === s),
  })).filter(x => x.klein || x.gross)
  const eigene = (k?: SortenK) => k?.basis?.includes('dieser Sorte')
  const kaliber = kaliberJeSorte(daten.kaliber.filter(z => !sorte || z.sorte === sorte))
  return (
    <Karte titel="Sortierung: zu klein, zu gross, Kaliber">
      <p className="leise">Kein Lagerverlust — die Ware verlässt den Betrieb, nur nicht zum besten Preis: zu Kleine an die Tiere, zu Grosse in den Nebenkanal, Überfüllung als Geschenk an den Kunden. Gemessen an der Sortier-CSV (jeder Kürbis gewogen) und an den gewogenen Ausschuss-Paletten der Hand-Linie.</p>
      <div className="spalten">
        <div><div className="leise">Zu klein (Tierfutter)</div><Ursachenkopf v={klein} eingang={eingang} maximum={maximum} /></div>
        <div><div className="leise">Zu gross (Nebenkanal)</div><Ursachenkopf v={gross} eingang={eingang} maximum={maximum} /></div>
      </div>

      {jeSorte.length > 0 && (
        <>
          <h3 style={{ margin: '.5rem 0 .4rem' }}>Je Sorte: Anteil der Masse am Band</h3>
          <div className="rollbar"><table>
            <thead><tr><th>Sorte</th><th className="zahl">zu klein</th><th className="zahl">Bereich</th><th className="zahl">zu gross</th><th className="zahl">Bereich</th><th className="zahl">Messungen</th></tr></thead>
            <tbody>{jeSorte.map(x => (
              <tr key={x.sorte} className={eigene(x.klein) || eigene(x.gross) ? '' : 'leise'}>
                <td>{x.sorte}</td>
                <td className="zahl"><strong>{x.klein?.mittel == null ? '—' : prozent(x.klein.mittel)}</strong></td>
                <td className="zahl">{x.klein?.unten != null && x.klein.oben != null ? `${prozent(x.klein.unten)}–${prozent(x.klein.oben)}` : '—'}</td>
                <td className="zahl"><strong>{x.gross?.mittel == null ? '—' : prozent(x.gross.mittel)}</strong></td>
                <td className="zahl">{x.gross?.unten != null && x.gross.oben != null ? `${prozent(x.gross.unten)}–${prozent(x.gross.oben)}` : '—'}</td>
                <td className="zahl">{Math.max(x.klein?.n ?? 0, x.gross?.n ?? 0)}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </>
      )}

      {nachCharge.length > 0 && (
        <>
          <h3 style={{ margin: '1rem 0 .4rem' }}>Je Charge</h3>
          <p className="leise" style={{ margin: '0 0 .4rem' }}>Beobachtet = an verarbeiteter Ware gemessen; der Rest ist mit dem Sortenanteil für die Ware im Lager gerechnet.</p>
          <div className="rollbar"><table>
            <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">Zu klein</th><th className="zahl">davon beobachtet</th><th className="zahl">Zu gross</th><th className="zahl">davon beobachtet</th><th className="zahl">Anteil am Eingang</th></tr></thead>
            <tbody>{nachCharge.slice(0, 15).map(g => (
              <tr key={g.name}>
                <td><Link to={`/chargen?charge=${g.name}`}>{g.name}</Link></td><td>{g.sorte}</td>
                <td className="zahl">{kg(g.klein, 0)}</td><td className="zahl leise">{kg(g.kleinBeob, 0)}</td>
                <td className="zahl">{kg(g.gross, 0)}</td><td className="zahl leise">{kg(g.grossBeob, 0)}</td>
                <td className="zahl"><strong>{prozent(g.eingang > 0 ? (g.klein + g.gross) / g.eingang : null)}</strong></td>
              </tr>
            ))}</tbody>
          </table></div>
          {nachCharge.length > 15 && <p className="leise">Die 15 grössten von {nachCharge.length} Chargen.</p>}
        </>
      )}

      {kaliber.length > 0 && (
        <>
          <h3 style={{ margin: '1rem 0 .4rem' }}>Kaliber-Verteilung</h3>
          <p className="leise" style={{ margin: '0 0 .4rem' }}>Bezahlt wird je Stück innerhalb eines Kalibers — wer weiss, wo eine Sorte liegt, kann ein engeres Band liefern. Je Sorte über alle Sortierläufe gebündelt, von klein nach gross.</p>
          {kaliber.map(s => {
            const maxN = Math.max(...s.klassen.map(k => k.n), 1)
            return (
              <div key={`${s.sorte}|${s.baender}`} style={{ marginBottom: '1rem' }}>
                <div className="reihe"><strong>{s.sorte}</strong>{s.mehrere && <span className="leise">Bänder {s.baender}</span>}<span className="leise" style={{ marginLeft: 'auto' }}>{zahl(s.n)} Kürbisse · {tonnen(s.kg)}</span></div>
                {s.klassen.map(k => (
                  <div key={k.name} style={{ marginTop: '.3rem' }}>
                    <div className="reihe" style={{ fontSize: '.85rem' }}>
                      <span className={k.klasse === 'kaliber' ? '' : 'leise'}>{k.klasse === 'verlust_klein' ? 'zu klein (Tierfutter)' : k.klasse === 'nebenkanal' ? 'zu gross (anderer Kanal)' : k.name}</span>
                      <span className="leise" style={{ marginLeft: 'auto' }}>{zahl(k.n)} · {prozent(s.n > 0 ? k.n / s.n : null)} · {kg(k.kg, 0)}</span>
                    </div>
                    <div className="balken-spur" style={{ height: 14 }}>
                      <div className="balken-fuellung" style={{ width: `${(k.n / maxN) * 100}%`, background: k.klasse === 'verlust_klein' ? 'var(--strom-ausschuss)' : k.klasse === 'nebenkanal' ? 'var(--strom-nebenkanal)' : 'var(--kuerbis)' }} />
                    </div>
                  </div>
                ))}
              </div>
            )
          })}
        </>
      )}

      <Gewichtsverteilung daten={daten} sorteFilter={sorte} />

      {daten.ueberfuellung.length > 0 && (
        <>
          <h3 style={{ margin: '1rem 0 .4rem' }}>Überfüllung je Käufer</h3>
          <p className="leise" style={{ margin: '0 0 .4rem' }}>Nur Arbeiten nach „Kiste ab x kg" — nach Kaliber gibt es kein Sollgewicht und nichts zu verschenken. Gemessen an den gewogenen fertigen Paletten.</p>
          <div className="rollbar">
            <table>
              <thead><tr><th>Käufer</th><th>Sorte</th><th className="zahl">Wägungen</th><th className="zahl">Kisten</th><th className="zahl">kg je Kiste</th><th className="zahl">Soll</th><th className="zahl">zu viel je Kiste</th><th className="zahl">verschenkt</th></tr></thead>
              <tbody>
                {daten.ueberfuellung.filter(u => !sorte || u.sorte === sorte).slice().sort((a, b) => b.ueberfuellung_kg - a.ueberfuellung_kg).map(u => (
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
  )
}

/** Faul beim Abpacken: die Rate je Sorte und je Charge — gebündelt, nicht als Liste der Arbeiten. */
function Fax({ daten, strom, eingang, maximum, sorte, chargen }: {
  daten: Auswertung; strom?: StromSumme; eingang: number; maximum: number; sorte: string; chargen: Set<number>
}) {
  const fax = daten.fax.filter(f => f.status === 'abgeschlossen' && f.plausibel && f.masse_kg != null && chargen.has(f.charge_nr) && (!sorte || f.sorte === sorte))
  const buendeln = <K,>(schluessel: (f: typeof fax[number]) => K, name: (f: typeof fax[number]) => string) => {
    const map = new Map<K, { name: string; sorte: string; n: number; masse: number; faul: number }>()
    for (const f of fax) {
      const k = schluessel(f)
      const e = map.get(k) ?? { name: name(f), sorte: f.sorte, n: 0, masse: 0, faul: 0 }
      e.n++; e.masse += (f.masse_kg ?? 0) + f.faul_kg; e.faul += f.faul_kg
      map.set(k, e)
    }
    return [...map.values()].sort((a, b) => b.masse - a.masse)
  }
  const jeSorte = buendeln(f => f.sorte, f => f.sorte)
  const jeCharge = buendeln(f => f.charge_nr, f => String(f.charge_nr))
  return (
    <Karte titel="Faul beim Abpacken (Fax)">
      <p className="leise">Nach dem Waschen steht die Ware in Kisten, bis eine Bestellung kommt. Beim Etikettieren wird nochmals aussortiert, was faul ist — das kommt vom Waschen und vom Stehen danach, nicht von der Lagerdauer, und ist darum eine eigene Ursache: Faules je Masse, die durchs Fax ging.</p>
      <Ursachenkopf v={strom} eingang={eingang} maximum={maximum} />
      {fax.length === 0 ? (
        <Hinweis art="info">Noch keine abgeschlossene Fax-Arbeit mit gezählten Kisten und gewogenem Faulem. Die Ursache ist unbekannt — nicht null.</Hinweis>
      ) : (
        <>
          <p className="leise" style={{ margin: '0 0 .4rem' }}>Gemessen an {fax.length} Fax-Arbeiten mit {tonnen(fax.reduce((s, f) => s + (f.masse_kg ?? 0) + f.faul_kg, 0))} — das ist die Stichprobe, nicht alles, was je abgepackt wurde.</p>
          <div className="spalten" style={{ alignItems: 'start' }}>
            <div>
              <h3 style={{ margin: '.5rem 0 .4rem' }}>Je Sorte</h3>
              <div className="rollbar"><table>
                <thead><tr><th>Sorte</th><th className="zahl">Arbeiten</th><th className="zahl">durchs Fax</th><th className="zahl">faul</th><th className="zahl">Anteil</th></tr></thead>
                <tbody>{jeSorte.map(x => (
                  <tr key={x.name}><td>{x.name}</td><td className="zahl">{x.n}</td><td className="zahl">{kg(x.masse, 0)}</td><td className="zahl">{kg(x.faul, 0)}</td><td className="zahl"><strong>{prozent(x.masse > 0 ? x.faul / x.masse : null)}</strong></td></tr>
                ))}</tbody>
              </table></div>
            </div>
            <div>
              <h3 style={{ margin: '.5rem 0 .4rem' }}>Je Charge</h3>
              <div className="rollbar"><table>
                <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">Arbeiten</th><th className="zahl">durchs Fax</th><th className="zahl">Anteil faul</th></tr></thead>
                <tbody>{jeCharge.slice(0, 15).map(x => (
                  <tr key={x.name}><td><Link to={`/chargen?charge=${x.name}`}>{x.name}</Link></td><td>{x.sorte}</td><td className="zahl">{x.n}</td><td className="zahl">{kg(x.masse, 0)}</td><td className="zahl"><strong>{prozent(x.masse > 0 ? x.faul / x.masse : null)}</strong></td></tr>
                ))}</tbody>
              </table></div>
              {jeCharge.length > 15 && <p className="leise">Die 15 grössten von {jeCharge.length} Chargen.</p>}
            </div>
          </div>
        </>
      )}
    </Karte>
  )
}

/* ---------- Helfer -------------------------------------------------------- */

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

/** Die Gewichtsverteilung aus der CSV, mit den Kalibergrenzen darübergelegt (ABLAUF.md). */
function Gewichtsverteilung({ daten, sorteFilter }: { daten: Auswertung; sorteFilter: string }) {
  const [nach, setNach] = useState<'sorte' | 'schlag' | 'charge_nr'>('sorte')
  const [wahl, setWahl] = useState('')
  const [breite, setBreite] = useState(50)
  const gewichte = daten.gewichte.filter(g => !sorteFilter || g.sorte === sorteFilter)
  const werte = [...new Set(gewichte.map(g => String(g[nach])))].sort()
  const aktiv = wahl && werte.includes(wahl) ? wahl : werte[0] ?? ''
  const auswahl = gewichte.filter(g => String(g[nach]) === aktiv)
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
  if (gewichte.length === 0) return null
  const gesamt = auswahl.reduce((a, g) => a + g.n, 0)
  const mittel = gesamt > 0 ? auswahl.reduce((a, g) => a + (g.stufe_g + 12.5) * g.n, 0) / gesamt : null
  return (
    <>
      <h3 style={{ margin: '1rem 0 .4rem' }}>Gewichtsverteilung aus der Sortier-CSV</h3>
      <p className="leise" style={{ margin: '0 0 .4rem' }}>Wie schwer sind die Kürbisse, die die Maschine gewogen hat? Glockenförmig oder zweigipflig, und wo liegt der Schwerpunkt zu den Kalibergrenzen (gestrichelt)? Das ist eine Aussage über den Anbau, nicht über das Lager — nach Sorte, Schlag oder Charge.</p>
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
        <strong>Stufenbreite</strong> heisst: wie viele Gramm ein Balken zusammenfasst. Bei 25 g steht jede Stufe für sich, bei 100 g werden vier Stufen zu einem Balken. Es sind immer dieselben {zahl(gesamt)} Kürbisse.
      </p>
    </>
  )
}

// Kennzahl wird in der Sortierung nicht mehr gebraucht — bleibt importierbar für Erweiterungen.
void Kennzahl
