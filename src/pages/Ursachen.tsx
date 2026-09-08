import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Aufklapp, Herkunft, Hinweis, Karte, Marke, Rechenweg, Zahlen } from '../components/Bausteine'
import { Glocke, Linien } from '../components/Diagramm'
import { STROMFARBE, kaliberJe, stroemeVon, useAuswertung, type Auswertung, type Bestand, type Gruppe, type SortenK, type StromSumme, type Ueberfuellung } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf, rechenweg } from '../auswertung/Karten'

/** Kennfarben für Reihen ohne festen Strom (Sorten im Verdunstungsbild). */
const REIHENFARBEN = ['var(--strom-verdunstung)', 'var(--strom-schimmel)', 'var(--strom-feld)',
                      'var(--strom-ausschuss)', 'var(--strom-nebenkanal)', 'var(--strom-fax)']

/** Der Filter der Seite: alles, eine Sorte, ein Schlag oder eine Charge. */
interface Filter { gruppe: Gruppe; schluessel: string }

/**
 * Ursachen: jede Ursache mit ihren Zahlen zuerst, dann der Blick dahinter.
 * Ganz oben ein leiser Filter (Sorte oder Charge) für die ganze Seite und
 * drei Zahlen: was hereinkam, was bisher hinausging, was noch im Lager
 * liegt. Dann je Ursache ein Block — Palox, Verdunstung, Sortierung, Fax,
 * Überfüllung. Alles bis heute; nur, was gemessen ist.
 */
export default function Ursachen() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const [params, setParams] = useSearchParams()
  const filter: Filter = params.get('charge') ? { gruppe: 'charge', schluessel: params.get('charge')! }
    : params.get('sorte') ? { gruppe: 'sorte', schluessel: params.get('sorte')! }
    : params.get('schlag') ? { gruppe: 'schlag', schluessel: params.get('schlag')! }
    : { gruppe: 'gesamt', schluessel: '' }
  const setzen = (wert: string) => {
    const [g, k] = wert.split('|')
    setParams(g && k ? { [g]: k } : {}, { replace: true })
  }

  const stroeme = useMemo(() => daten ? stroemeVon(daten.verlust, filter.gruppe, filter.schluessel) : [], [daten, filter.gruppe, filter.schluessel])
  const chargen = useMemo(() => daten ? chargenIm(daten.bestand, filter) : [], [daten, filter])

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null

  const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort((a, b) => a.localeCompare(b, 'de'))
  const schlaege = [...new Set(daten.bestand.map(b => b.schlag))].sort((a, b) => a.localeCompare(b, 'de'))
  const chargenListe = [...daten.bestand].sort((a, b) => a.charge_nr - b.charge_nr)
  const summe = (f: (b: Bestand) => number) => chargen.reduce((a, b) => a + f(b), 0)
  const eingang = summe(b => b.eingang_kg)
  const geliefert = summe(b => b.geliefert_kg)
  const imHaus = summe(b => b.im_haus_heute_kg)
  const lager = summe(b => b.lager_kg)
  const verlust = summe(b => b.verlust_heute_kg)
  const strom = (name: string) => stroeme.find(s => s.strom === name)
  const filterSorte = filter.gruppe === 'sorte' ? filter.schluessel : filter.gruppe === 'charge' ? (chargen[0]?.sorte ?? '') : ''
  const chargenSet = new Set(chargen.map(c => c.charge_nr))
  const name = filter.gruppe === 'gesamt' ? 'Alle Chargen' : filter.gruppe === 'charge' ? `Charge ${filter.schluessel} · ${chargen[0]?.sorte ?? ''} · ${chargen[0]?.schlag ?? ''}` : filter.schluessel

  return (
    <>
      <Reiterkopf titel="Ursachen" zweck="Jede Ursache mit ihren Zahlen bis heute — und dahinter die Messungen, aus denen sie kommen."
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} />
      <Probleme liste={daten.probleme} />

      <div className="filterleiste">
        <label htmlFor="uf" style={{ margin: 0 }}>Ansicht</label>
        <select id="uf" value={filter.gruppe === 'gesamt' ? '' : `${filter.gruppe}|${filter.schluessel}`} onChange={e => setzen(e.target.value)}>
          <option value="">alle Chargen</option>
          <optgroup label="Sorte">{sorten.map(s => <option key={s} value={`sorte|${s}`}>{s}</option>)}</optgroup>
          <optgroup label="Charge">{chargenListe.map(c => <option key={c.charge_nr} value={`charge|${c.charge_nr}`}>{c.charge_nr} · {c.sorte} · {c.schlag}</option>)}</optgroup>
          <optgroup label="Schlag">{schlaege.map(s => <option key={s} value={`schlag|${s}`}>{s}</option>)}</optgroup>
        </select>
        {filter.gruppe !== 'gesamt' && <span className="aktiv-filter">{name}</span>}
        <span>{chargen.length} Chargen</span>
      </div>

      <Karte>
        <Zahlen zeilen={[
          { titel: 'Hereingekommen', wert: <>{tonnen(eingang)} <Herkunft art="gemessen" /></>, unter: `${zahl(summe(b => b.n_paletten))} Paletten` },
          { titel: 'Bisher hinaus', wert: <>{tonnen(geliefert)} <Herkunft art="gemessen" /></>, unter: `${zahl(summe(b => b.n_lieferungen))} Lieferungen` },
          { titel: 'Verlust bis heute', wert: <>{tonnen(verlust)} <Herkunft art="gerechnet" /></>, unter: `${prozent(eingang > 0 ? verlust / eingang : null)} des Eingangs` },
          { titel: 'Noch im Lager', wert: <>{tonnen(imHaus)} <Herkunft art="gerechnet" /></>, unter: `${tonnen(lager)} Eingangsware liegt noch` },
        ]} />
      </Karte>

      <Verderb daten={daten} strom={strom('Schimmel/Fäulnis')} feld={strom('Nicht lagerbedingt')} eingang={eingang} lager={lager} sorte={filterSorte} chargen={chargenSet} filter={filter} />
      <Verdunstung daten={daten} strom={strom('Verdunstung')} eingang={eingang} lager={lager} sorte={filterSorte} chargen={chargenSet} filter={filter} />
      <Sortierung daten={daten} klein={strom('Zu klein (Tierfutter)')} gross={strom('Nebenkanal zu gross')} eingang={eingang} sorte={filterSorte} chargen={chargen} filter={filter} />
      <Fax daten={daten} strom={strom('Faul beim Abpacken (Fax)')} eingang={eingang} chargen={chargenSet} />
      <Ueberfuellungsblock daten={daten} filter={filter} sorte={filterSorte} />
    </>
  )
}

/** Die Chargen im Filter. */
function chargenIm(bestand: Bestand[], f: Filter): Bestand[] {
  return bestand.filter(b => f.gruppe === 'gesamt' || (f.gruppe === 'sorte' ? b.sorte === f.schluessel : f.gruppe === 'schlag' ? b.schlag === f.schluessel : String(b.charge_nr) === f.schluessel))
}

/** Die Zeile mit den Zahlen eines Stroms: bis heute, Anteil, Bereich, Warnungen. */
function Stromzahl({ v, eingang, titel }: { v: StromSumme | undefined; eingang: number; titel: string }) {
  if (!v) return { titel, wert: '—', unter: 'für diesen Filter keine Zeile' }
  if (!v.bekannt) return { titel, wert: <Marke art="warnung">nicht gemessen</Marke>, unter: 'unbekannt, nicht null' }
  return {
    titel, wert: <>{tonnen(v.mittel)} <Herkunft art="gerechnet" /></>,
    unter: <>{prozent(eingang > 0 ? v.mittel / eingang : null)} des Eingangs{v.bereichBekannt ? ` · Bereich ${tonnen(v.unten)}–${tonnen(v.oben)}` : ''}{(v.koeffN ?? 0) < 3 ? ' · dünne Datenlage' : ''}</>,
  }
}

/* ---------- Palox: Verderb im Lager ------------------------------------------ */

function Verderb({ daten, strom, feld, eingang, lager, sorte, chargen, filter }: {
  daten: Auswertung; strom?: StromSumme; feld?: StromSumme; eingang: number; lager: number; sorte: string; chargen: Set<number>; filter: Filter
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
  const imLager = (strom?.bekannt ? strom.projiziert : 0) + (feld?.bekannt ? feld.projiziert : 0)
  const bisHeute = (strom?.bekannt ? strom.mittel : 0) + (feld?.bekannt ? feld.mittel : 0)
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
    <Karte titel="Palox: Faules im Lager">
      <Zahlen zeilen={[
        Stromzahl({ v: strom, eingang, titel: 'Faules bis heute' }),
        { titel: 'Vermutet noch im Lager', wert: strom?.bekannt ? <>{kg(imLager, 0)} <Herkunft art="gerechnet" /></> : '—',
          unter: strom?.bekannt ? `${prozent(lager > 0 ? imLager / lager : null)} der liegenden Eingangsware — verdorben, noch nicht aussortiert` : 'nicht gemessen' },
        ...(feld?.bekannt && feld.mittel > 0 ? [{ titel: 'davon nicht lagerbedingt', wert: <>{kg(feld.mittel, 0)}</>, unter: 'Erde, Hagelnarben, Schnittfehler — vom Feld, ohne Lagerdauer' }] : []),
      ]} />
      <p className="leise">
        Gemessen wird der Palox, wenn eine Palette an die Sortiermaschine oder an die Waschstrasse kommt — bezogen auf die Masse, die an dem Tag aus dem Lager kam, aufgetragen über der Lagerdauer. Daraus die Kurve, mit der für alle Ware gerechnet wird: für die ausgelieferte beim Alter am Liefertag, für die liegende bis heute.
        {bisHeute > 0 && strom?.bekannt && <> Zusammen {tonnen(bisHeute)} im Palox bis heute.</>}
      </p>
      <Linien
        reihen={[
          { name: 'Kurve (Modell)', farbe: 'var(--strom-schimmel)', linie: true, marker: false,
            punkte: kurveReihe.map(k => ({ x: k.x, y: k.y, text: k.text })),
            band: kurveReihe.map(k => ({ x: k.x, unten: k.unten, oben: k.oben })) },
          { name: 'Messung am Band / Waschbecken', farbe: 'var(--strom-verdunstung)',
            punkte: punkte.filter(p => p.quelle === 'verarbeitung').map(p => ({ x: p.lagertage, y: (p.anteil ?? 0) * 100, text: `Charge ${p.charge_nr} · ${p.sorte}` })) },
          { name: 'Messung bei der Lagerkontrolle', farbe: 'var(--strom-feld)',
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
        </p>
      )}
      {jeCharge.length > 0 && filter.gruppe !== 'charge' && (
        <Aufklapp titel={<>Je Charge: gemessen gegen Modell <span className="leise">({jeCharge.length} Chargen mit Messung)</span></>}>
          <p className="leise" style={{ margin: '.3rem 0 .4rem' }}>Gemessen = alles Faule dieser Charge (Kilo im Palox) zu allem, was von ihr aus dem Lager kam. Lagertage = wann gemessen wurde. Modell = die Kurve beim mittleren Alter dieser Messungen. Eine Charge deutlich über der Kurve verdirbt schneller als ihre Sorte — eine Beobachtung, keine Erklärung.</p>
          <div className="rollbar"><table>
            <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">Messungen</th><th className="zahl">Lagertage</th><th className="zahl">Faules im Palox</th><th className="zahl">Gemessen</th><th className="zahl">Modell</th><th className="zahl">Abweichung</th></tr></thead>
            <tbody>{jeCharge.map(e => (
              <tr key={e.charge_nr}>
                <td><Link to={`/ursachen?charge=${e.charge_nr}`}>{e.charge_nr}</Link></td><td>{e.sorte}</td>
                <td className="zahl">{e.n}</td>
                <td className="zahl">{Math.round(e.tMin) === Math.round(e.tMax) ? Math.round(e.tMin) : `${Math.round(e.tMin)}–${Math.round(e.tMax)}`}</td>
                <td className="zahl">{kg(e.faul, 0)}</td>
                <td className="zahl"><strong>{prozent(e.gemessen)}</strong></td>
                <td className="zahl">{prozent(e.modell)}</td>
                <td className="zahl">{e.abweichung === null ? '—' : <span style={{ color: e.abweichung > 0.02 ? 'var(--rot)' : e.abweichung < -0.02 ? 'var(--strom-rest)' : undefined }}>{e.abweichung > 0 ? '+' : ''}{(e.abweichung * 100).toFixed(1)} Pkt.</span>}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </Aufklapp>
      )}
      {strom && <Rechenweg zeilen={rechenweg(strom, eingang)} />}
    </Karte>
  )
}

/* ---------- Verdunstung ------------------------------------------------------- */

function Verdunstung({ daten, strom, eingang, lager, sorte, chargen, filter }: {
  daten: Auswertung; strom?: StromSumme; eingang: number; lager: number; sorte: string; chargen: Set<number>; filter: Filter
}) {
  const wiegungen = daten.wiegungen
    .filter(w => !w.sichtbar_schimmel && w.netto_damals_kg && w.lagertage > 0 && w.verlust_kg !== null)
    .filter(w => chargen.has(w.charge_nr) && (!sorte || w.sorte === sorte))
  const sorten = [...new Set(wiegungen.map(w => w.sorte))].sort()
  const tMax = Math.max(...wiegungen.map(w => w.lagertage), 30)
  const rate = (s: string) => daten.sorten.verdunstung.find(k => k.sorte === s)
  const punktReihen = sorten.map((s, i) => ({
    name: `${s} — gewogene Paletten`, farbe: REIHENFARBEN[i % REIHENFARBEN.length],
    punkte: wiegungen.filter(w => w.sorte === s)
      .map(w => ({ x: w.lagertage, y: (w.verlust_kg! / w.netto_damals_kg!) * 100, text: `Charge ${w.charge_nr} · ${datum(w.wiege_ts)}` })),
  }))
  // Die Erwartung je Sorte: 1 − (1 − r)^t mit dem Bereich der Rate als Streifen.
  // Sorten ohne eigene Messreihe rechnen mit dem Gesamtwert — die teilen sich eine Linie.
  const linien = (() => {
    const gruppen = new Map<string, { k: SortenK; sorten: string[]; farbe: string }>()
    const kandidaten = sorten.length ? sorten : (sorte ? [sorte] : daten.sorten.verdunstung.filter(k => k.n > 0).map(k => k.sorte))
    kandidaten.forEach((s, i) => {
      const k = rate(s)
      if (k?.mittel == null) return
      const key = k.mittel.toFixed(6)
      const g = gruppen.get(key)
      if (g) g.sorten.push(s); else gruppen.set(key, { k, sorten: [s], farbe: REIHENFARBEN[i % REIHENFARBEN.length] })
    })
    const schritte = 16
    const ts = Array.from({ length: schritte + 1 }, (_, i) => (tMax * i) / schritte)
    return [...gruppen.values()].map(g => ({
      name: g.sorten.length > 1 ? `Erwartung: ${g.sorten.length} Sorten mit dem Gesamtwert` : `${g.sorten[0]} — Erwartung`,
      farbe: g.sorten.length > 1 ? 'var(--text-leise)' : g.farbe, linie: true, marker: false, gestrichelt: true,
      punkte: ts.map(t => ({ x: t, y: (1 - Math.pow(1 - (g.k.mittel ?? 0), t)) * 100 })),
      band: g.k.unten != null && g.k.oben != null ? ts.map(t => ({ x: t, unten: (1 - Math.pow(1 - g.k.unten!, t)) * 100, oben: (1 - Math.pow(1 - g.k.oben!, t)) * 100 })) : undefined,
    }))
  })()
  const eigene = (k: SortenK) => k.basis?.includes('dieser Sorte')
  const tabelle = daten.sorten.verdunstung.filter(k => k.n > 0 && (!sorte || k.sorte === sorte)).sort((a, b) => (a.mittel ?? 0) - (b.mittel ?? 0))
  return (
    <Karte titel="Verdunstung">
      <Zahlen zeilen={[
        Stromzahl({ v: strom, eingang, titel: 'Verdunstet bis heute' }),
        { titel: 'Vermutet vom aktuellen Lager', wert: strom?.bekannt ? <>{kg(strom.projiziert, 0)} <Herkunft art="gerechnet" /></> : '—',
          unter: strom?.bekannt ? `${prozent(lager > 0 ? strom.projiziert / lager : null)} von dem, was ohne Verdunstung läge` : 'nicht gemessen' },
        ...(strom?.bekannt ? [{ titel: 'An der ausgelieferten Ware', wert: kg(strom.beobachtet, 0), unter: 'bis zum jeweiligen Liefertag' }] : []),
      ]} />
      <p className="leise">Jede gewogene Palette: wie viel Prozent ihres Eingangsgewichts sie bis zum Wiegen verloren hat, über der Lagerdauer. Die gestrichelte Linie ist die Erwartung der Sorte, der Streifen ihr Bereich — liegen die Punkte darin, trägt die Rate; liegen sie systematisch darüber oder darunter, stimmt sie nicht. Paletten mit sichtbar Faulem zählen nicht, sonst würde Fäulnis als Wasser verbucht.</p>
      <Linien reihen={[...linien, ...punktReihen]}
              xFormat={x => `${Math.round(x)}`} yFormat={y => `${y.toFixed(1)} %`} xTitel="Lagertage beim Wiegen" yTitel="Gewicht verloren" yVon={0}
              leer="noch keine Palette gewogen" />
      {tabelle.length > 0 && filter.gruppe !== 'charge' && (
        <Aufklapp titel={<>Je Sorte: die Rate <span className="leise">({tabelle.length} Sorten)</span></>}>
          <p className="leise" style={{ margin: '.3rem 0 .4rem' }}>Nach Rate sortiert — oben hält am besten. Grau: zu wenige eigene Messungen, es gilt der Gesamtwert aller Sorten.</p>
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
        </Aufklapp>
      )}
      {strom && <Rechenweg zeilen={rechenweg(strom, eingang)} />}
    </Karte>
  )
}

/* ---------- Sortierung: zu klein, zu gross ---------------------------------- */

function Sortierung({ daten, klein, gross, eingang, sorte, chargen, filter }: {
  daten: Auswertung; klein?: StromSumme; gross?: StromSumme; eingang: number; sorte: string; chargen: Bestand[]; filter: Filter
}) {
  const kleinS = (s: string) => daten.sorten.ausschuss.find(k => k.sorte === s)
  const grossS = (s: string) => daten.sorten.nebenkanal.find(k => k.sorte === s)
  const eigene = (k?: SortenK) => k?.basis?.includes('dieser Sorte')
  const sortenImFilter = [...new Set(chargen.map(c => c.sorte))].sort()
  // Der Durchschnitt der Sorte, prominent: bei einer Sorte (oder Charge) ihre Rate, sonst je Sorte in der Tabelle
  const s1 = sortenImFilter.length === 1 ? sortenImFilter[0] : ''
  const ks = s1 ? kleinS(s1) : undefined, gs = s1 ? grossS(s1) : undefined
  // Je Charge aus den vorgerechneten Gruppen
  const jeCharge = chargen.map(c => {
    const st = stroemeVon(daten.verlust, 'charge', String(c.charge_nr))
    const k = st.find(x => x.strom === 'Zu klein (Tierfutter)'), g = st.find(x => x.strom === 'Nebenkanal zu gross')
    return { c, klein: k, gross: g }
  }).sort((a, b) => ((b.klein?.mittel ?? 0) + (b.gross?.mittel ?? 0)) - ((a.klein?.mittel ?? 0) + (a.gross?.mittel ?? 0)))
  const anteil = (v: StromSumme | undefined, e: number) => v?.bekannt && e > 0 ? v.mittel / e : null
  return (
    <Karte titel="Sortierung: zu klein, zu gross">
      <Zahlen zeilen={[
        Stromzahl({ v: klein, eingang, titel: 'Zu klein — an die Tiere' }),
        Stromzahl({ v: gross, eingang, titel: 'Zu gross — Nebenkanal' }),
        ...(s1 ? [{ titel: `Durchschnitt ${s1}`, wert: <>{ks?.mittel == null ? '—' : prozent(ks.mittel)} <span className="leise" style={{ fontSize: '.9rem' }}>zu klein</span> · {gs?.mittel == null ? '—' : prozent(gs.mittel)} <span className="leise" style={{ fontSize: '.9rem' }}>zu gross</span></>,
                      unter: eigene(ks) || eigene(gs) ? `${Math.max(ks?.n ?? 0, gs?.n ?? 0)} Sortierläufe dieser Sorte` : 'zu wenige eigene Messungen — der Gesamtwert aller Sorten' }] : []),
      ]} />
      <p className="leise">Kein echter Verlust: die Ware verlässt den Betrieb, nur nicht zum besten Preis. Gemessen an der Sortier-CSV (jeder Kürbis gewogen) — der Anteil der Sorte gilt für ihre ganze Ware, an der Waschstrasse wird nichts mehr gewogen.</p>

      {filter.gruppe !== 'charge' && sortenImFilter.length > 1 && (
        <>
          <h3 style={{ margin: '.5rem 0 .4rem' }}>Je Sorte</h3>
          <div className="rollbar"><table>
            <thead><tr><th>Sorte</th><th className="zahl">zu klein</th><th className="zahl">Bereich</th><th className="zahl">zu gross</th><th className="zahl">Bereich</th><th className="zahl">Sortierläufe</th></tr></thead>
            <tbody>{sortenImFilter.map(s => { const k = kleinS(s), g = grossS(s); return (
              <tr key={s} className={eigene(k) || eigene(g) ? '' : 'leise'}>
                <td><Link to={`/ursachen?sorte=${encodeURIComponent(s)}`}>{s}</Link></td>
                <td className="zahl"><strong>{k?.mittel == null ? '—' : prozent(k.mittel)}</strong></td>
                <td className="zahl">{k?.unten != null && k.oben != null ? `${prozent(k.unten)}–${prozent(k.oben)}` : '—'}</td>
                <td className="zahl"><strong>{g?.mittel == null ? '—' : prozent(g.mittel)}</strong></td>
                <td className="zahl">{g?.unten != null && g.oben != null ? `${prozent(g.unten)}–${prozent(g.oben)}` : '—'}</td>
                <td className="zahl">{Math.max(k?.n ?? 0, g?.n ?? 0)}</td>
              </tr>
            ) })}</tbody>
          </table></div>
        </>
      )}

      {jeCharge.length > 0 && (
        <>
          <h3 style={{ margin: '1rem 0 .4rem' }}>{filter.gruppe === 'charge' ? 'Die Charge gegen ihre Sorte' : 'Je Charge'}</h3>
          <div className="rollbar"><table>
            <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">Eingang</th><th className="zahl">Zu klein</th><th className="zahl">Anteil</th><th className="zahl">Zu gross</th><th className="zahl">Anteil</th><th className="zahl">Sorte: zu klein · zu gross</th></tr></thead>
            <tbody>{jeCharge.slice(0, filter.gruppe === 'gesamt' ? 15 : 200).map(({ c, klein: k, gross: g }) => (
              <tr key={c.charge_nr}>
                <td>{filter.gruppe === 'charge' ? c.charge_nr : <Link to={`/ursachen?charge=${c.charge_nr}`}>{c.charge_nr}</Link>}</td><td>{c.sorte}</td>
                <td className="zahl">{kg(c.eingang_kg, 0)}</td>
                <td className="zahl">{k?.bekannt ? kg(k.mittel, 0) : '—'}</td><td className="zahl"><strong>{prozent(anteil(k, c.eingang_kg))}</strong></td>
                <td className="zahl">{g?.bekannt ? kg(g.mittel, 0) : '—'}</td><td className="zahl"><strong>{prozent(anteil(g, c.eingang_kg))}</strong></td>
                <td className="zahl leise">{prozent(kleinS(c.sorte)?.mittel)} · {prozent(grossS(c.sorte)?.mittel)}</td>
              </tr>
            ))}</tbody>
          </table></div>
          {filter.gruppe === 'gesamt' && jeCharge.length > 15 && <p className="leise">Die 15 grössten von {jeCharge.length} Chargen — eine Sorte wählen zeigt alle ihre Chargen.</p>}
        </>
      )}

      <Gewichtsverteilung daten={daten} filter={filter} sorte={sorte} />
      {klein && <Rechenweg zeilen={rechenweg(klein, eingang)} />}
    </Karte>
  )
}

/** Die Glocke — aufklappbar, für die Sorte oder Charge des Filters. */
function Gewichtsverteilung({ daten, filter, sorte }: { daten: Auswertung; filter: Filter; sorte: string }) {
  const [wahl, setWahl] = useState('')
  const [breite, setBreite] = useState(50)
  const nach = filter.gruppe === 'charge' ? 'charge' : 'sorte'
  const gruppen = useMemo(() => kaliberJe(daten.kaliber, nach), [daten.kaliber, nach])
  const werte = filter.gruppe === 'charge' ? [filter.schluessel] : sorte ? [sorte] : [...new Set(gruppen.map(g => g.schluessel))]
  const aktiv = wahl && werte.includes(wahl) ? wahl : werte[0] ?? ''
  const gewichte = daten.gewichte.filter(g => nach === 'sorte' ? g.sorte === aktiv : String(g.charge_nr) === aktiv)
  if (gewichte.length === 0) return null
  const gruppe = gruppen.find(g => g.schluessel === aktiv)
  const sorteAktiv = gruppe?.sorte ?? gewichte[0]?.sorte
  const stufenMap = new Map<number, number>()
  for (const g of gewichte) { const x = Math.floor(g.stufe_g / breite) * breite; stufenMap.set(x, (stufenMap.get(x) ?? 0) + g.n) }
  const stufen = [...stufenMap.entries()].map(([x, n]) => ({ x, n })).sort((a, b) => a.x - b.x)
  const schema = daten.schemata.find(s => s.sorte === sorteAktiv && s.art === 'kaliber' && s.kaeufer === null)
    ?? daten.schemata.find(s => s.sorte === sorteAktiv && s.art === 'kaliber')
  const grenzen: { x: number; text: string }[] = []
  if (schema?.verlust_unter != null) grenzen.push({ x: schema.verlust_unter, text: 'zu klein <' })
  ;(schema?.kaliber_baender ?? []).forEach(([a], i) => { if (i > 0) grenzen.push({ x: a, text: `K${i + 1}` }) })
  if (schema?.kanal_ab != null) grenzen.push({ x: schema.kanal_ab, text: 'zu gross ≥' })
  const gesamt = gewichte.reduce((a, g) => a + g.n, 0)
  const mittel = gesamt > 0 ? gewichte.reduce((a, g) => a + (g.stufe_g + 12.5) * g.n, 0) / gesamt : null
  const klassenfarbe = (x: number) => schema?.verlust_unter != null && x + breite <= schema.verlust_unter ? 'var(--strom-ausschuss)'
    : schema?.kanal_ab != null && x >= schema.kanal_ab ? 'var(--strom-nebenkanal)' : 'var(--kuerbis)'
  return (
    <Aufklapp titel={<>Die Glocke: wie schwer sind die Kürbisse? <span className="leise">{aktiv}{nach === 'charge' ? ` · ${sorteAktiv}` : ''} · {zahl(gesamt)} gewogen{mittel !== null ? ` · Schwerpunkt ${Math.round(mittel)} g` : ''}</span></>}>
      <div className="filterleiste">
        {werte.length > 1 && (
          <>
            <label htmlFor="gv-wahl" style={{ margin: 0 }}>Sorte</label>
            <select id="gv-wahl" value={aktiv} onChange={e => setWahl(e.target.value)}>{werte.map(w => <option key={w}>{w}</option>)}</select>
          </>
        )}
        <label htmlFor="gv-breite" style={{ margin: 0 }}>Stufe</label>
        <select id="gv-breite" value={breite} onChange={e => setBreite(Number(e.target.value))}>
          <option value={25}>25 g</option><option value={50}>50 g</option><option value={100}>100 g</option>
        </select>
        {schema && <span>Grenzen: Fassung vom {datum(schema.gilt_ab)}</span>}
      </div>
      <Glocke stufen={stufen} breite={breite} grenzen={grenzen} xFormat={x => `${x}`} klassenfarbe={klassenfarbe} mittel={mittel} hoehe={200} />
      {gruppe && (
        <div className="rollbar"><table className="kurz"><tbody>
          <tr><th>Kaliber</th>{gruppe.klassen.map(k => <th key={k.name}>{k.name}</th>)}</tr>
          <tr><td>Anteil</td>{gruppe.klassen.map(k => <td key={k.name}><strong>{prozent(gruppe.n > 0 ? k.n / gruppe.n : null, 0)}</strong></td>)}</tr>
          <tr><td>Masse</td>{gruppe.klassen.map(k => <td key={k.name}>{kg(k.kg, 0)}</td>)}</tr>
        </tbody></table></div>
      )}
      <p className="leise" style={{ margin: '.4rem 0 0' }}>Glockenförmig oder zweigipflig, und wo liegt der Schwerpunkt zu den Kalibergrenzen? Eine Aussage über den Anbau, nicht über das Lager.</p>
    </Aufklapp>
  )
}

/* ---------- Fax: Faules beim Abpacken — eine Zahl --------------------------- */

function Fax({ daten, strom, eingang, chargen }: { daten: Auswertung; strom?: StromSumme; eingang: number; chargen: Set<number> }) {
  const fax = daten.fax.filter(f => f.status === 'abgeschlossen' && f.plausibel && f.masse_kg != null && chargen.has(f.charge_nr))
  const masse = fax.reduce((s, f) => s + (f.masse_kg ?? 0) + f.faul_kg, 0)
  const faul = fax.reduce((s, f) => s + f.faul_kg, 0)
  return (
    <Karte titel="Faules beim Abpacken (Fax)">
      <Zahlen zeilen={[
        Stromzahl({ v: strom, eingang, titel: 'Faules beim Abpacken bis heute' }),
        { titel: 'Gemessen', wert: fax.length ? <>{prozent(masse > 0 ? faul / masse : null)} <Herkunft art="gemessen" /></> : '—',
          unter: fax.length ? `${kg(faul, 0)} von ${tonnen(masse)} in ${fax.length} Fax-Arbeiten — die Stichprobe` : 'noch keine Fax-Arbeit mit gewogenem Faulem' },
        ...(strom?.bekannt && strom.erwartet > 0 ? [{ titel: 'Erwartung für die Ware im Haus', wert: <>{kg(strom.erwartet, 0)} <Herkunft art="prognose" /></>, unter: 'was beim Abpacken noch anfallen dürfte — nicht im Verlust bis heute' }] : []),
      ]} />
      <p className="leise" style={{ margin: 0 }}>Nach dem Waschen steht die Ware ein bis drei Tage in Kisten, bis sie abgepackt wird; dabei wird nochmals aussortiert, was faul ist. Das kommt vom Waschen und vom Stehen danach, nicht von der Lagerdauer — darum eine eigene Ursache, gerechnet an der abgepackten Ware.</p>
      {strom && <Rechenweg zeilen={rechenweg(strom, eingang)} />}
    </Karte>
  )
}

/* ---------- Überfüllung: verschenkte Marge ------------------------------------ */

function Ueberfuellungsblock({ daten, filter, sorte }: { daten: Auswertung; filter: Filter; sorte: string }) {
  const zeilen = daten.ueberfuellung.filter(u => filter.gruppe === 'charge' ? (u.gruppe === 'charge' && String(u.charge_nr) === filter.schluessel)
    : (u.gruppe === 'sorte' && (!sorte || u.sorte === sorte)))
  const alleKisten = zeilen.filter(u => u.kistensystem === 'kiste_ab' && (u.n_lieferungen > 0 || u.n_wiegungen > 0)).sort((a, b) => (b.verschenkt_kg ?? 0) - (a.verschenkt_kg ?? 0) || (b.kisten_verkauft ?? 0) - (a.kisten_verkauft ?? 0))
  const alleStueck = zeilen.filter(u => u.kistensystem === 'stueck' && (u.n_lieferungen > 0 || u.n_wiegungen > 0)).sort((a, b) => (b.stueck_verkauft ?? 0) - (a.stueck_verkauft ?? 0))
  // Gezeigt wird, was verkauft ist; gewogen ohne Verkauf steht aufklappbar darunter
  const kisten = alleKisten.filter(u => u.n_lieferungen > 0), kistenOhne = alleKisten.filter(u => u.n_lieferungen === 0)
  const stueck = alleStueck.filter(u => u.n_lieferungen > 0), stueckOhne = alleStueck.filter(u => u.n_lieferungen === 0)
  const unbekannt = zeilen.filter(u => u.kistensystem === 'unbekannt' && u.n_lieferungen > 0)
  const marge = daten.marge.find(m => m.posten.startsWith('Überfüllung'))
  const verschenkt = kisten.reduce((s, u) => s + (u.verschenkt_kg ?? 0), 0)
  const gerechnet = kisten.filter(u => u.verschenkt_kg != null)
  const verkauftOhne = kisten.filter(u => u.n_wiegungen === 0).reduce((s, u) => s + (u.kisten_verkauft ?? 0), 0)
  const datei = daten.ueberfuellung.some(u => u.n_lieferungen > 0)
  const band = (u: Ueberfuellung) => u.band_von_g != null && u.band_bis_g != null ? `${u.band_von_g}–${u.band_bis_g} g` : u.kaliber_idx != null ? `K${u.kaliber_idx + 1}` : '—'
  return (
    <Karte titel="Überfüllung: verschenkte Marge">
      <Zahlen zeilen={[
        { titel: 'Verschenkt bis heute', wert: gerechnet.length ? <>{kg(verschenkt, 0)} <Herkunft art="gerechnet" /></> : '—',
          unter: gerechnet.length ? `aus ${zahl(gerechnet.reduce((s, u) => s + (u.kisten_verkauft ?? 0), 0))} verkauften Kisten „ab x kg" mit gewogenem Gegenstück` : !datei ? 'keine Verkaufsdatei eingelesen — die verkauften Kisten sind unbekannt' : 'keine gewogene Palette dieses Systems' },
        { titel: 'Gewogene Paletten', wert: zahl(alleKisten.reduce((s, u) => s + u.n_wiegungen, 0)), unter: `${zahl(alleKisten.reduce((s, u) => s + (u.kisten_gewogen ?? 0), 0))} Kisten „ab x kg" auf der Waage` },
        ...(verkauftOhne > 0 ? [{ titel: 'Nicht gerechnet', wert: `${zahl(verkauftOhne)} Kisten`, unter: 'verkauft, aber kein gewogenes Gegenstück (Sorte oder Soll ohne Wägung)' }] : []),
      ]} />
      <p className="leise">
        Zwei Kistensysteme, zwei Rechnungen. <strong>Kiste ab x kg:</strong> Was die gewogene Kiste über dem Soll hat, ist geschenkt — mal die verkauften Kisten aus der Verkaufsdatei <Herkunft art="gemessen" />, nicht hochgerechnet; wo keine Wägung zum verkauften System passt, steht nichts.
        {' '}<strong>Stück je Kiste:</strong> kein Soll, keine verschenkte Marge — aber die Waage sagt, wie schwer die Stücke wirklich sind, und die Datei, was als Nenngewicht verkauft wurde.
        {marge && !marge.gemessen && <> {marge.erlaeuterung}</>}
      </p>

      {kisten.length > 0 && (
        <>
          <h3 style={{ margin: '.75rem 0 .4rem' }}>Kiste ab x kg</h3>
          <div className="rollbar"><table>
            <thead><tr>{filter.gruppe !== 'charge' && <th>Sorte</th>}<th className="zahl">Soll je Kiste</th><th className="zahl">Gewogen je Kiste</th><th className="zahl">Zu viel je Kiste</th><th className="zahl">Wägungen</th><th className="zahl">Verkaufte Kisten</th><th className="zahl">Verschenkt</th></tr></thead>
            <tbody>{kisten.map((u, i) => (
              <tr key={i}>
                {filter.gruppe !== 'charge' && <td>{u.sorte}</td>}
                <td className="zahl">{u.soll_kg_pro_kiste != null ? `${u.soll_kg_pro_kiste.toFixed(1)} kg` : '—'}</td>
                <td className="zahl">{u.kg_je_kiste != null ? `${u.kg_je_kiste.toFixed(2)} kg` : <span className="leise">nicht gewogen</span>}</td>
                <td className="zahl">{u.zuviel_je_kiste != null ? <strong>{u.zuviel_je_kiste > 0 ? '+' : ''}{u.zuviel_je_kiste.toFixed(2)} kg</strong> : '—'}</td>
                <td className="zahl">{u.n_wiegungen}{u.kisten_gewogen ? <span className="leise"> · {zahl(u.kisten_gewogen)} Kisten</span> : ''}</td>
                <td className="zahl">{u.kisten_verkauft != null ? <>{zahl(u.kisten_verkauft)}{u.n_anteilig > 0 ? <span className="leise" title="bei einem Teil der Lieferungen anteilig aus der Position"> ~</span> : ''}</> : <span className="leise">nicht verkauft</span>}</td>
                <td className="zahl">{u.verschenkt_kg != null ? <strong>{kg(u.verschenkt_kg, 0)}</strong> : <span className="leise">—</span>}{u.verschenkt_fehler_kg != null && u.verschenkt_kg != null && <span className="leise"> ± {kg(u.verschenkt_fehler_kg, 0)}</span>}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </>
      )}

      {stueck.length > 0 && (
        <>
          <h3 style={{ margin: '1rem 0 .4rem' }}>Stück je Kiste</h3>
          <div className="rollbar"><table>
            <thead><tr>{filter.gruppe !== 'charge' && <th>Sorte</th>}<th className="zahl">Stück je Kiste</th><th>Kaliber</th><th className="zahl">Gewogen je Stück</th><th className="zahl">Nenngewicht (Datei)</th><th className="zahl">Bandmittel (CSV)</th><th className="zahl">Wägungen</th><th className="zahl">Verkaufte Stück</th></tr></thead>
            <tbody>{stueck.map((u, i) => (
              <tr key={i}>
                {filter.gruppe !== 'charge' && <td>{u.sorte}</td>}
                <td className="zahl">{u.stueck_je_kiste ?? '—'}</td>
                <td>{band(u)}</td>
                <td className="zahl">{u.g_je_kuerbis != null ? <strong>{zahl(u.g_je_kuerbis)} g</strong> : <span className="leise">nicht gewogen</span>}</td>
                <td className="zahl">{u.nenn_g != null ? `${zahl(u.nenn_g)} g` : <span className="leise">—</span>}</td>
                <td className="zahl">{u.band_mittel_g != null ? `${zahl(u.band_mittel_g)} g` : '—'}</td>
                <td className="zahl">{u.n_wiegungen}</td>
                <td className="zahl">{u.stueck_verkauft != null ? zahl(u.stueck_verkauft) : <span className="leise">nicht verkauft</span>}</td>
              </tr>
            ))}</tbody>
          </table></div>
          <p className="leise" style={{ margin: '.4rem 0 0' }}>Liegt das gewogene Stück tief im Band, liesse sich ein engeres Band liefern — eine Beobachtung, kein Verlust.</p>
        </>
      )}
      {(kistenOhne.length > 0 || stueckOhne.length > 0) && (
        <Aufklapp titel={<>Gewogen, aber nicht verkauft <span className="leise">({kistenOhne.length + stueckOhne.length} Kistensysteme — Wägungen ohne Gegenstück in der Verkaufsdatei)</span></>}>
          <div className="rollbar"><table>
            <thead><tr>{filter.gruppe !== 'charge' && <th>Sorte</th>}<th>System</th><th>Kaliber</th><th className="zahl">Gewogen je Kiste</th><th className="zahl">Gewogen je Stück</th><th className="zahl">Wägungen</th></tr></thead>
            <tbody>{[...kistenOhne, ...stueckOhne].map((u, i) => (
              <tr key={i}>
                {filter.gruppe !== 'charge' && <td>{u.sorte}</td>}
                <td>{u.kistensystem === 'kiste_ab' ? `Kiste ab ${u.soll_kg_pro_kiste?.toFixed(1) ?? '?'} kg` : `${u.stueck_je_kiste ?? '?'} Stück`}</td>
                <td>{u.kistensystem === 'stueck' ? band(u) : '—'}</td>
                <td className="zahl">{u.kg_je_kiste != null ? `${u.kg_je_kiste.toFixed(2)} kg` : '—'}</td>
                <td className="zahl">{u.g_je_kuerbis != null ? `${zahl(u.g_je_kuerbis)} g` : '—'}</td>
                <td className="zahl">{u.n_wiegungen}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </Aufklapp>
      )}
      {unbekannt.length > 0 && (
        <p className="leise" style={{ margin: '.6rem 0 0' }}>Dazu {tonnen(unbekannt.reduce((s, u) => s + (u.kg_verkauft ?? 0), 0))} verkauft, deren Kistensystem die Datei nicht nennt (Einheit kg ohne Gebindeinhalt) — nichts gerechnet.</p>
      )}
      {kisten.length === 0 && stueck.length === 0 && <p className="leise" style={{ margin: 0 }}>{datei ? 'Für diesen Filter nichts verkauft und nichts gewogen.' : 'Verkaufte Kisten kennt die App erst mit einer eingelesenen Verkaufsdatei — Betrieb → Warenausgang.'}</p>}
    </Karte>
  )
}

// Für Erweiterungen erreichbar.
void STROMFARBE
