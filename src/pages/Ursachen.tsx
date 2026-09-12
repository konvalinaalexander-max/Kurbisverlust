import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Aufklapp, Erklaerung, Herkunft, Hinweis, Karte, Marke, Rechenweg, Zahlen } from '../components/Bausteine'
import { Glocke, Linien, type Reihe, type Zone } from '../components/Diagramm'
import { glockeVorbereiten, kaliberJe, lagerstaende, schimmelKurve, stroemeVon, useAuswertung, verdunstungKurve,
         type Auswertung, type Bestand, type Gruppe, type Lagerstand, type SortenK, type StromSumme, type Ueberfuellung } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf, rechenweg } from '../auswertung/Karten'
import { summeBekannt } from '../lib/masse'
import { ZFilter } from '../components/Zeichen'

/** Kennfarben für Reihen ohne festen Strom (Sorten im Verdunstungsbild). */
const REIHENFARBEN = ['var(--strom-verdunstung)', 'var(--strom-schimmel)', 'var(--strom-feld)',
                      'var(--strom-ausschuss)', 'var(--strom-nebenkanal)', 'var(--strom-fax)']
/** Wie weit die Kurven über die Ware hinaus gezeichnet werden: so weit liegt sie noch mindestens. */
const VORAUS_TAGE = 60

/** Der Filter der Seite: alles, eine Sorte, ein Schlag oder eine Charge. */
interface Filter { gruppe: Gruppe; schluessel: string }

/**
 * Ursachen: jede Ursache mit ihren Zahlen zuerst, dann der Blick dahinter —
 * und auf den Kurven die Frage, die der Betriebsleiter wirklich hat: **Wo
 * steht meine Ware heute, und wie geht es weiter?**
 *
 * Auf einer Lagertage-Achse gibt es kein einzelnes „heute": Jede Charge liegt
 * anders lang. Darum stehen die Chargen im Filter als Rauten auf der Kurve —
 * je eine beim Alter ihrer liegenden Paletten, so gross wie ihre Masse im
 * Haus. Ist eine Charge gewählt, wird daraus die eine Marke „heute" mit der
 * Kurve dahinter; ist eine Sorte oder alles gewählt, eine Zone „hier liegt
 * die Ware heute". Die Kurve läuft über die Messungen hinaus gestrichelt
 * weiter — dorthin, wo die Ware in zwei Monaten liegt.
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
  const staende = useMemo(() => daten ? lagerstaende(chargen, daten.naechste) : [], [daten, chargen])

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null

  const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort((a, b) => a.localeCompare(b, 'de'))
  const schlaege = [...new Set(daten.bestand.map(b => b.schlag))].sort((a, b) => a.localeCompare(b, 'de'))
  const chargenListe = [...daten.bestand].sort((a, b) => a.charge_nr - b.charge_nr)
  const summe = (f: (b: Bestand) => number) => chargen.reduce((a, b) => a + f(b), 0)
  /** 0064: unbekannt bleibt unbekannt — eine Summe mit einer Lücke ist keine Zahl. */
  const summeOffen = (f: (b: Bestand) => number | null) => summeBekannt(chargen.map(f))
  const eingang = summe(b => b.eingang_kg)
  const geliefert = summe(b => b.geliefert_kg)
  const imHaus = summe(b => b.im_haus_heute_kg)
  const lager = summe(b => b.lager_kg)
  const verlust = summeOffen(b => b.verlust_heute_kg)
  const strom = (name: string) => stroeme.find(s => s.strom === name)
  const filterSorte = filter.gruppe === 'sorte' ? filter.schluessel : filter.gruppe === 'charge' ? (chargen[0]?.sorte ?? '') : ''
  const chargenSet = new Set(chargen.map(c => c.charge_nr))
  const name = filter.gruppe === 'gesamt' ? 'Alle Chargen' : filter.gruppe === 'charge' ? `Charge ${filter.schluessel} · ${chargen[0]?.sorte ?? ''} · ${chargen[0]?.schlag ?? ''}` : filter.schluessel

  return (
    <>
      <Reiterkopf titel="Ursachen" zweck="Jede Ursache mit ihren Zahlen bis heute — und auf der Kurve, wo die Ware heute steht und wie es weitergeht."
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt} />
      <Probleme liste={daten.probleme} />

      <div className="filterleiste haftend">
        <label htmlFor="uf"><ZFilter size={15} /> Ansicht</label>
        <select id="uf" value={filter.gruppe === 'gesamt' ? '' : `${filter.gruppe}|${filter.schluessel}`} onChange={e => setzen(e.target.value)}>
          <option value="">alle Chargen</option>
          <optgroup label="Sorte">{sorten.map(s => <option key={s} value={`sorte|${s}`}>{s}</option>)}</optgroup>
          <optgroup label="Charge">{chargenListe.map(c => <option key={c.charge_nr} value={`charge|${c.charge_nr}`}>{c.charge_nr} · {c.sorte} · {c.schlag}</option>)}</optgroup>
          <optgroup label="Schlag">{schlaege.map(s => <option key={s} value={`schlag|${s}`}>{s}</option>)}</optgroup>
        </select>
        {filter.gruppe !== 'gesamt' && <span className="aktiv-filter">{name}</span>}
        <span>{chargen.length} Chargen · {staende.length} davon mit Ware im Haus</span>
        {filter.gruppe !== 'gesamt' && <button type="button" className="werkzeug-knopf" onClick={() => setzen('')}>alle zeigen</button>}
      </div>

      <Karte>
        <Zahlen zeilen={[
          { titel: 'Eingang', wert: <>{tonnen(eingang)} <Herkunft art="gemessen" /></>, unter: `${zahl(summe(b => b.n_paletten))} Paletten aus dem Erntejournal` },
          { titel: 'Ausgeliefert', wert: <>{tonnen(geliefert)} <Herkunft art="gemessen" /></>, unter: `${zahl(summe(b => b.n_lieferungen))} Lieferungen` },
          { titel: 'Verlust bis heute',
            wert: verlust === null ? <Marke art="warnung">nicht gemessen</Marke> : <>{tonnen(verlust)} <Herkunft art="gerechnet" /></>,
            unter: verlust === null
              ? 'mindestens eine Ursache hat noch keine Messung — unbekannt, nicht null'
              : `${prozent(eingang > 0 ? verlust / eingang : null)} des Eingangs` },
          { titel: 'Noch im Haus',
            wert: <>{verlust === null ? 'höchstens ' : ''}{tonnen(imHaus)} <Herkunft art="gerechnet" /></>,
            unter: `davon ${tonnen(lager)} Eingangsware, die noch liegt` },
        ]} />
      </Karte>

      <Verderb daten={daten} strom={strom('Schimmel/Fäulnis')} feld={strom('Nicht lagerbedingt')} eingang={eingang} lager={lager} sorte={filterSorte} chargen={chargenSet} filter={filter} staende={staende} />
      <Verdunstung daten={daten} strom={strom('Verdunstung')} eingang={eingang} lager={lager} sorte={filterSorte} chargen={chargenSet} filter={filter} staende={staende} />
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

/** Die Zahl „14 Tage länger liegen" für den Filter — aus erg_naechste_charge, keine eigene Rechnung. */
function Prognose14({ staende, feld, titel }: { staende: Lagerstand[]; feld: 'schimmel_14_kg' | 'verdunstung_14_kg'; titel: string }) {
  const mit = staende.filter(s => s.naechste?.modell_gilt !== false)
  const summe = summeBekannt(mit.map(s => s.naechste?.[feld] ?? null))
  if (summe === null || mit.length === 0) return { titel, wert: '—', unter: 'keine Prognose: die Ware liegt ausserhalb des gemessenen Bereichs' }
  return { titel, wert: <>+{kg(summe, 0)} <Herkunft art="prognose" /></>, unter: `wenn die ${tonnen(mit.reduce((a, s) => a + s.imHaus, 0))} im Haus zwei Wochen länger liegen` }
}

/**
 * Wo die Ware heute steht — das, was auf jeder Lagertage-Kurve dazukommt:
 * je Charge eine Raute beim Alter ihrer liegenden Paletten, und als Achse
 * die „heute"-Marke (eine Charge) oder die Zone (mehrere).
 */
function heuteAufDerKurve(staende: Lagerstand[], filter: Filter, f: (t: number) => number, farbe: string, textVon: (s: Lagerstand, y: number) => string) {
  const punkte = staende.map(s => ({
    x: s.alter, y: f(s.alter), name: `Charge ${s.charge.charge_nr} · ${s.charge.sorte}`,
    groesse: 3.5 + 3 * Math.sqrt(s.imHaus / Math.max(1, staende[0]?.imHaus ?? 1)),
    text: textVon(s, f(s.alter)),
  }))
  const reihe: Reihe = { name: 'Chargen heute im Lager', farbe, form: 'raute', punkte }
  const alter = staende.map(s => s.alter)
  const von = staende.length ? Math.min(...staende.map(s => s.von)) : null
  const bis = staende.length ? Math.max(...staende.map(s => s.bis)) : null
  const heute = filter.gruppe === 'charge' && staende.length === 1
    ? { x: staende[0].alter, text: `heute · ${alterText(staende[0])} Tage im Lager`, rechts: 'wie es weiterginge' }
    : undefined
  const zonen: Zone[] = !heute && von !== null && bis !== null
    ? [{ von, bis, text: staende.length > 1 ? `hier liegt die Ware heute (${Math.round(von)}–${Math.round(bis)} Tage)` : 'hier liegt die Ware heute' }]
    : []
  const xBis = alter.length ? Math.ceil((Math.max(...alter) + VORAUS_TAGE) / 30) * 30 : null
  return { reihe, heute, zonen, xBis }
}
const alterText = (s: Lagerstand) => Math.round(s.von) === Math.round(s.bis) ? `${Math.round(s.alter)}` : `${Math.round(s.von)}–${Math.round(s.bis)}`

/** Die Chargen heute auf der Kurve, als Tabelle — nach Alter, die älteste zuerst. */
function Lagerstandtabelle({ staende, modellAnteil, feld, titel }: {
  staende: Lagerstand[]; modellAnteil: (t: number) => number | null; feld: 'schimmel_14_kg' | 'verdunstung_14_kg'; titel: string
}) {
  if (staende.length === 0) return null
  const sortiert = [...staende].sort((a, b) => b.alter - a.alter)
  const zeilen = sortiert.slice(0, 12)
  return (
    <Aufklapp titel={<><span>{titel}</span> <span className="leise">{staende.length} Chargen mit Ware im Haus, die älteste zuerst</span></>} offen={staende.length <= 6}>
      <div className="rollbar"><table className="dicht">
        <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">Liegt seit</th><th className="zahl">Noch im Haus</th><th className="zahl">Modell-Anteil heute</th><th className="zahl">Prognose: zwei Wochen länger liegen</th></tr></thead>
        <tbody>{zeilen.map(s => {
          const m = modellAnteil(s.alter)
          const p = s.naechste?.modell_gilt !== false ? s.naechste?.[feld] ?? null : null
          return (
            <tr key={s.charge.charge_nr}>
              <td><Link to={`/ursachen?charge=${s.charge.charge_nr}`}>{s.charge.charge_nr}</Link> <span className="leise">{s.charge.schlag}</span></td>
              <td>{s.charge.sorte}</td>
              <td className="zahl">{alterText(s)} d</td>
              <td className="zahl"><strong>{kg(s.imHaus, 0)}</strong></td>
              <td className="zahl">{m === null ? '—' : prozent(m)}</td>
              <td className="zahl">{p === null ? <span className="leise">—</span> : `+${kg(p, 0)}`}</td>
            </tr>
          )
        })}</tbody>
      </table></div>
      {sortiert.length > zeilen.length && <p className="fussnote">Die {zeilen.length} ältesten von {sortiert.length} Chargen — <Link to="/chargen">alle unter Chargen</Link>.</p>}
    </Aufklapp>
  )
}

/* ---------- Palox: Verderb im Lager ------------------------------------------ */

function Verderb({ daten, strom, feld, eingang, lager, sorte, chargen, filter, staende }: {
  daten: Auswertung; strom?: StromSumme; feld?: StromSumme; eingang: number; lager: number; sorte: string; chargen: Set<number>; filter: Filter; staende: Lagerstand[]
}) {
  const m = daten.modell
  const punkte = daten.punkte.filter(p => p.plausibel && p.anteil !== null && chargen.has(p.charge_nr) && (!sorte || p.sorte === sorte))
  const kurve = schimmelKurve(m)
  const tMax = m?.t_max ?? 0
  // Die Kurve: glatt, an vielen Stellen ausgewertet, bis zum gemessenen Rand
  // fest, dahinter gestrichelt — so weit, wie die Ware im Filter liegen wird.
  const heute = heuteAufDerKurve(staende, filter, t => (kurve ? kurve(t).mittel * 100 : 0), 'var(--kuerbis)',
    (s, y) => `liegt seit ${alterText(s)} Tagen · ${kg(s.imHaus, 0)} im Haus · Modell ${y.toFixed(1)} % faul${s.naechste?.schimmel_14_kg != null && s.naechste.modell_gilt !== false ? ` · in 14 Tagen +${kg(s.naechste.schimmel_14_kg, 0)}` : ''}`)
  const xEnde = Math.max(heute.xBis ?? 0, Math.ceil((tMax + 30) / 30) * 30, 60)
  const kurveReihe: Reihe | null = kurve ? (() => {
    const schritte = 48
    const ts = Array.from({ length: schritte + 1 }, (_, i) => (xEnde * i) / schritte)
    return {
      name: 'Kurve des Modells', farbe: 'var(--strom-schimmel)', linie: true, marker: false, dick: true, prognoseAb: tMax,
      punkte: ts.map(t => ({ x: t, y: kurve(t).mittel * 100 })),
      band: ts.map(t => ({ x: t, unten: kurve(t).unten * 100, oben: kurve(t).oben * 100 })),
    }
  })() : null
  // Ohne brauchbares Modell: die Klassen aus der Datenbank, wie bisher.
  const klassenReihe: Reihe | null = !kurve && daten.kurve.length ? {
    name: 'Kurve (je Altersklasse)', farbe: 'var(--strom-schimmel)', linie: true, marker: false,
    punkte: daten.kurve.filter(k => k.verwendet !== null).map(k => ({ x: (k.von + Math.min(k.bis, k.von + 60)) / 2, y: (k.verwendet ?? 0) * 100, text: k.altersklasse })),
  } : null
  const modellBei = (t: number) => {
    if (kurve) return kurve(t).mittel
    const k = daten.kurve.find(x => t >= x.von && t < x.bis) ?? daten.kurve[daten.kurve.length - 1]
    return k?.verwendet ?? null
  }
  // 0066: Was nicht gemessen ist, zählt nicht als 0 mit.
  const imLager = summeBekannt([strom?.bekannt ? strom.projiziert : 0, feld?.bekannt ? feld.projiziert : 0])
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
  const nUnplausibel = daten.punkte.filter(p => (p.quelle === 'verarbeitung' || p.quelle === 'lager') && !p.plausibel && chargen.has(p.charge_nr)).length
  const reihen: Reihe[] = [
    ...(kurveReihe ? [kurveReihe] : klassenReihe ? [klassenReihe] : []),
    { name: 'Messung am Band / Waschbecken', farbe: 'var(--strom-verdunstung)',
      punkte: punkte.filter(p => p.quelle === 'verarbeitung').map(p => ({ x: p.lagertage, y: (p.anteil ?? 0) * 100, text: `Charge ${p.charge_nr} · ${p.sorte}` })) },
    { name: 'Messung bei der Lagerkontrolle', farbe: 'var(--strom-feld)',
      punkte: punkte.filter(p => p.quelle === 'lager').map(p => ({ x: p.lagertage, y: (p.anteil ?? 0) * 100, text: `Charge ${p.charge_nr} · ${p.sorte}` })) },
    ...(kurve && heute.reihe.punkte.length ? [heute.reihe] : []),
  ].filter(r => r.punkte.length > 0)

  return (
    <Karte titel="Palox: Faules im Lager" unter="Wie viel Faules die Ware mit der Lagerdauer ansetzt — die Rauten zeigen, wo die Chargen heute stehen.">
      <Zahlen zeilen={[
        Stromzahl({ v: strom, eingang, titel: 'Faules bis heute' }),
        { titel: 'Vermutet noch im Lager', wert: strom?.bekannt && imLager !== null ? <>{kg(imLager, 0)} <Herkunft art="gerechnet" /></> : '—',
          unter: strom?.bekannt && imLager !== null ? `${prozent(lager > 0 ? imLager / lager : null)} der liegenden Eingangsware — verdorben, noch nicht aussortiert` : 'nicht gemessen' },
        ...(feld?.bekannt && feld.mittel > 0 ? [{ titel: 'davon nicht lagerbedingt', wert: <>{kg(feld.mittel, 0)}</>, unter: 'Erde, Hagelnarben, Schnittfehler — vom Feld, ohne Lagerdauer' }] : []),
        Prognose14({ staende, feld: 'schimmel_14_kg', titel: 'Prognose: zwei Wochen länger liegen' }),
      ]} />
      <Linien
        reihen={reihen}
        xFormat={x => `${Math.round(x)}`} yFormat={y => `${y.toFixed(1)} %`} xTitel="Lagertage" yTitel="Anteil faul"
        xEinheit="tage" yEinheit="prozent" yVon={0} xBis={reihen.length ? xEnde : undefined}
        heute={heute.heute} zonen={heute.zonen}
        senkrechte={kurve && tMax > 0 ? [{ x: tMax, text: 'bis hier gemessen', farbe: 'var(--text-leise)' }] : []}
        ausgeschlossenText={x => `${Math.round(x)} Lagertage`}
        leer="noch keine Schimmelmessung" />
      {nUnplausibel > 0 && (
        <p className="fussnote">
          {nUnplausibel === 1 ? '1 Messung ist nicht plausibel' : `${nUnplausibel} Messungen sind nicht plausibel`} und deshalb nicht im Bild — sie stehen unter <Link to="/messungen">Messungen</Link> mit Grund.
        </p>
      )}
      <Lagerstandtabelle staende={staende} modellAnteil={modellBei} feld="schimmel_14_kg" titel="Welche Charge zuerst? Die Chargen heute auf der Kurve" />
      {jeCharge.length > 0 && filter.gruppe !== 'charge' && (
        <Aufklapp titel={<><span>Je Charge: gemessen gegen Modell</span> <span className="leise">{jeCharge.length} Chargen mit Messung</span></>}>
          <p className="leise-satz" style={{ margin: '0 0 .5rem' }}>Gemessen = alles Faule dieser Charge (Kilo im Palox) zu allem, was von ihr aus dem Lager kam. Modell = die Kurve beim mittleren Alter dieser Messungen. Eine Charge deutlich über der Kurve verdirbt schneller als ihre Sorte — eine Beobachtung, keine Erklärung.</p>
          <div className="rollbar"><table className="dicht">
            <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">Messungen</th><th className="zahl">Lagertage</th><th className="zahl">Faules im Palox</th><th className="zahl">Gemessener Anteil</th><th className="zahl">Modell-Anteil</th><th className="zahl">Abweichung gemessen ↔ Modell</th></tr></thead>
            <tbody>{jeCharge.map(e => (
              <tr key={e.charge_nr}>
                <td><Link to={`/ursachen?charge=${e.charge_nr}`}>{e.charge_nr}</Link></td><td>{e.sorte}</td>
                <td className="zahl">{e.n}</td>
                <td className="zahl">{Math.round(e.tMin) === Math.round(e.tMax) ? Math.round(e.tMin) : `${Math.round(e.tMin)}–${Math.round(e.tMax)}`}</td>
                <td className="zahl">{kg(e.faul, 0)}</td>
                <td className="zahl"><strong>{prozent(e.gemessen)}</strong></td>
                <td className="zahl">{prozent(e.modell)}</td>
                <td className="zahl">{e.abweichung === null ? '—' : <span className={e.abweichung > 0.02 ? 'rot' : e.abweichung < -0.02 ? 'gruen' : ''}><span className="chip" style={{ background: e.abweichung > 0.02 ? 'var(--rot)' : e.abweichung < -0.02 ? 'var(--gruen)' : 'var(--rand)', marginRight: '.4rem' }} />{e.abweichung > 0 ? '+' : ''}{(e.abweichung * 100).toFixed(1)} Pkt.</span>}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </Aufklapp>
      )}
      <Erklaerung>
        <p>Gemessen wird der Palox, wenn eine Palette an die Sortiermaschine oder an die Waschstrasse kommt — bezogen auf die Masse, die an dem Tag aus dem Lager kam, aufgetragen über der Lagerdauer.
        Daraus die Kurve, mit der für alle Ware gerechnet wird: für die ausgelieferte beim Alter am Liefertag, für die liegende bis heute.
        Bis „bis hier gemessen" ist die Kurve durch Messungen gestützt; rechts davon ist sie Hochrechnung und wird gestrichelt gezeichnet, der Streifen wird breiter.</p>
        <p>Die Rauten sind die Chargen mit Ware im Haus, jede beim Alter ihrer liegenden Paletten (die Spanne über die Eingangstage), so gross wie ihre Masse.
        Eine Raute weit rechts auf einer steilen Kurve heisst: Diese Charge verliert jetzt am schnellsten — <Link to="/chargen">Chargen</Link> sagt, was zwei Wochen länger liegen kostet.</p>
        {m && (
          <p>{m.brauchbar
            ? <>Kurve F(t) = 1 − exp(−λ·t<sup>k</sup>), k = {m.k?.toFixed(2)}, angepasst an {m.n} Messungen aus {m.c_chargen} Chargen über {Math.round(m.t_min)}–{Math.round(m.t_max)} Lagertage.</>
            : <>Für eine Kurve reicht es noch nicht — nötig sind Messungen aus mindestens drei Chargen über deutlich verschiedene Lagerdauern. Solange gilt der zuletzt gemessene Wert.</>}
            {daten.selektion && <> {daten.selektion.befund}</>}
          </p>
        )}
      </Erklaerung>
      {strom && <Rechenweg zeilen={rechenweg(strom, eingang)} />}
    </Karte>
  )
}

/* ---------- Verdunstung ------------------------------------------------------- */

function Verdunstung({ daten, strom, eingang, lager, sorte, chargen, filter, staende }: {
  daten: Auswertung; strom?: StromSumme; eingang: number; lager: number; sorte: string; chargen: Set<number>; filter: Filter; staende: Lagerstand[]
}) {
  // Nur echte Verlust-Messungen ins Bild: eine Palette, die schwerer oder
  // gleich schwer geworden ist, hat nichts verloren (Waagenrauschen oder ein
  // kopiertes Eingangsgewicht). Sie zählt im gepoolten Mittel weiter (0056),
  // gehört aber nicht als negativer Punkt auf ein „Gewicht verloren"-Bild.
  const wiegungenAlle = daten.wiegungen
    .filter(w => !w.sichtbar_schimmel && w.netto_damals_kg && w.lagertage > 0 && w.verdunstung_kg !== null)
    .filter(w => chargen.has(w.charge_nr) && (!sorte || w.sorte === sorte))
  const wiegungen = wiegungenAlle.filter(w => (w.verdunstung_kg ?? 0) > 0)
  const ohneVerlust = wiegungenAlle.length - wiegungen.length
  const sorten = [...new Set(wiegungen.map(w => w.sorte))].sort()
  const rate = (s: string) => daten.sorten.verdunstung.find(k => k.sorte === s)
  const gemessenBis = wiegungen.length ? Math.max(...wiegungen.map(w => w.lagertage)) : 0
  const punktReihen: Reihe[] = sorten.map((s, i) => ({
    name: `${s} — gewogene Paletten`, farbe: REIHENFARBEN[i % REIHENFARBEN.length],
    punkte: wiegungen.filter(w => w.sorte === s)
      .map(w => ({ x: w.lagertage, y: (w.verdunstung_kg! / w.netto_damals_kg!) * 100, text: `Charge ${w.charge_nr} · ${datum(w.wiege_ts)}` })),
  }))
  // Die Erwartung je Sorte: 1 − (1 − r)^t mit dem Bereich der Rate als Streifen.
  // Sorten ohne eigene Messreihe rechnen mit dem Gesamtwert — die teilen sich eine Linie.
  const sortenImFilter = [...new Set([...staende.map(s => s.charge.sorte), ...sorten])].sort()
  const kandidaten = sortenImFilter.length ? sortenImFilter : (sorte ? [sorte] : daten.sorten.verdunstung.filter(k => k.n > 0).map(k => k.sorte))
  const farbeVon = (s: string) => REIHENFARBEN[Math.max(0, sorten.indexOf(s)) % REIHENFARBEN.length]
  const kurveVon = (s: string) => verdunstungKurve(rate(s))
  // Wo die Ware heute steht — auf der Linie ihrer Sorte.
  const heute = heuteAufDerKurve(staende, filter, t => t, 'var(--kuerbis)', () => '')
  const heuteReihe: Reihe = {
    ...heute.reihe,
    punkte: staende.map(s => {
      const f = kurveVon(s.charge.sorte)
      const y = f ? f(s.alter).mittel * 100 : null
      return { x: s.alter, y: y ?? 0, name: `Charge ${s.charge.charge_nr} · ${s.charge.sorte}`,
               groesse: 3.5 + 3 * Math.sqrt(s.imHaus / Math.max(1, staende[0]?.imHaus ?? 1)),
               text: `liegt seit ${alterText(s)} Tagen · ${kg(s.imHaus, 0)} im Haus · Erwartung ${y === null ? '—' : `${y.toFixed(1)} %`} verdunstet${s.naechste?.verdunstung_14_kg != null ? ` · in 14 Tagen +${kg(s.naechste.verdunstung_14_kg, 0)}` : ''}` }
    }).filter(p => kurveVon(staende.find(s => s.alter === p.x)?.charge.sorte ?? '') !== null),
  }
  const xEnde = Math.max(heute.xBis ?? 0, Math.ceil((gemessenBis + 30) / 30) * 30, 60)
  const linien = (() => {
    const gruppen = new Map<string, { k: SortenK; sorten: string[]; farbe: string }>()
    kandidaten.forEach(s => {
      const k = rate(s)
      if (k?.mittel == null) return
      const key = k.mittel.toFixed(6)
      const g = gruppen.get(key)
      if (g) g.sorten.push(s); else gruppen.set(key, { k, sorten: [s], farbe: farbeVon(s) })
    })
    const schritte = 32
    const ts = Array.from({ length: schritte + 1 }, (_, i) => (xEnde * i) / schritte)
    return [...gruppen.values()].map(g => {
      const f = verdunstungKurve(g.k)!
      return {
        name: g.sorten.length > 1 ? `Erwartung: ${g.sorten.length} Sorten mit dem Gesamtwert` : `${g.sorten[0]} — Erwartung`,
        farbe: g.sorten.length > 1 ? 'var(--text-leise)' : g.farbe, linie: true, marker: false, prognoseAb: gemessenBis > 0 ? gemessenBis : 0,
        punkte: ts.map(t => ({ x: t, y: f(t).mittel * 100 })),
        band: g.k.unten != null && g.k.oben != null ? ts.map(t => ({ x: t, unten: f(t).unten * 100, oben: f(t).oben * 100 })) : undefined,
      } as Reihe
    })
  })()
  const eigene = (k: SortenK) => k.basis?.includes('dieser Sorte')
  const tabelle = daten.sorten.verdunstung.filter(k => k.n > 0 && (!sorte || k.sorte === sorte)).sort((a, b) => (a.mittel ?? 0) - (b.mittel ?? 0))
  const reihen = [...linien, ...punktReihen, ...(heuteReihe.punkte.length ? [heuteReihe] : [])]
  const erwartungBei = (t: number) => { const f = kurveVon(staende[0]?.charge.sorte ?? sorte); return f ? f(t).mittel : null }
  return (
    <Karte titel="Verdunstung" unter="Wie viel Wasser die Ware mit der Lagerdauer verliert — je Sorte ihre Erwartung, die Rauten zeigen die Chargen heute.">
      <Zahlen zeilen={[
        Stromzahl({ v: strom, eingang, titel: 'Verdunstet bis heute' }),
        { titel: 'Vermutet vom aktuellen Lager', wert: strom?.bekannt && strom.projiziert !== null ? <>{kg(strom.projiziert, 0)} <Herkunft art="gerechnet" /></> : '—',
          unter: strom?.bekannt && strom.projiziert !== null ? `${prozent(lager > 0 && strom.projiziert !== null ? strom.projiziert / lager : null)} von dem, was ohne Verdunstung läge` : 'nicht gemessen' },
        ...(strom?.bekannt ? [{ titel: 'An der ausgelieferten Ware', wert: kg(strom.beobachtet, 0), unter: 'bis zum jeweiligen Liefertag' }] : []),
        Prognose14({ staende, feld: 'verdunstung_14_kg', titel: 'Prognose: zwei Wochen länger liegen' }),
      ]} />
      <Linien reihen={reihen}
              xFormat={x => `${Math.round(x)}`} yFormat={y => `${y.toFixed(1)} %`} xTitel="Lagertage" yTitel="Gewicht verloren"
              xEinheit="tage" yEinheit="prozent" yVon={0} xBis={reihen.length ? xEnde : undefined}
              heute={heute.heute} zonen={heute.zonen}
              senkrechte={gemessenBis > 0 ? [{ x: gemessenBis, text: 'bis hier gemessen', farbe: 'var(--text-leise)' }] : []}
              ausgeschlossenText={x => `${Math.round(x)} Lagertage`}
              leer="noch keine Palette gewogen" />
      {ohneVerlust > 0 && (
        <p className="fussnote">
          {ohneVerlust === 1 ? '1 Wägung zeigt keinen Verlust' : `${ohneVerlust} Wägungen zeigen keinen Verlust`} (Palette gleich schwer oder schwerer als beim Eingang) — nicht im Bild; sie stehen unter <Link to="/messungen">Messungen</Link>.
        </p>
      )}
      {filter.gruppe === 'charge' && (
        <Lagerstandtabelle staende={staende} modellAnteil={erwartungBei} feld="verdunstung_14_kg" titel="Diese Charge heute" />
      )}
      {tabelle.length > 0 && filter.gruppe !== 'charge' && (
        <Aufklapp titel={<><span>Je Sorte: die Rate</span> <span className="leise">{tabelle.length} Sorten, nach Rate sortiert — oben hält am besten</span></>}>
          <div className="rollbar"><table className="dicht">
            <thead><tr><th>Sorte</th><th className="zahl">je Tag</th><th className="zahl">nach 100 Tagen</th><th className="zahl">Bereich je Tag</th><th className="zahl">gewogene Paletten</th></tr></thead>
            <tbody>{tabelle.map(k => (
              <tr key={k.sorte} className={eigene(k) ? '' : 'leise'}>
                <td>{k.sorte}{!eigene(k) && <span className="leise"> · Gesamtwert</span>}</td>
                <td className="zahl">{k.mittel == null ? '—' : `${(k.mittel * 100).toFixed(3)} %`}</td>
                <td className="zahl"><strong>{k.mittel == null ? '—' : prozent(1 - Math.pow(1 - k.mittel, 100))}</strong></td>
                <td className="zahl">{k.unten != null && k.oben != null ? `${(k.unten * 100).toFixed(3)}–${(k.oben * 100).toFixed(3)} %` : '—'}</td>
                <td className="zahl">{k.n}</td>
              </tr>
            ))}</tbody>
          </table></div>
          <p className="fussnote">Grau: zu wenige eigene Messungen, es gilt der Gesamtwert aller Sorten.</p>
        </Aufklapp>
      )}
      <Erklaerung>
        Jede gewogene Palette: wie viel Prozent ihres Eingangsgewichts sie bis zum Wiegen verloren hat, über der Lagerdauer. Die Linie ist die Erwartung der Sorte, der Streifen ihr Bereich — liegen die Punkte darin, trägt die Rate; liegen sie systematisch darüber oder darunter, stimmt sie nicht.
        Rechts von „bis hier gemessen" ist die Linie Hochrechnung. Paletten mit sichtbar Faulem zählen nicht, sonst würde Fäulnis als Wasser verbucht.
        Die Rauten sind die Chargen mit Ware im Haus beim Alter ihrer liegenden Paletten, auf der Erwartungslinie ihrer Sorte.
      </Erklaerung>
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
  const maxAnteil = Math.max(0.001, ...sortenImFilter.map(s => Math.max(kleinS(s)?.mittel ?? 0, grossS(s)?.mittel ?? 0)))
  return (
    <Karte titel="Sortierung: zu klein, zu gross" unter="Kein echter Verlust — die Ware verlässt den Betrieb, nur nicht zum besten Preis.">
      <Zahlen zeilen={[
        Stromzahl({ v: klein, eingang, titel: 'Zu klein — an die Tiere' }),
        Stromzahl({ v: gross, eingang, titel: 'Zu gross — Nebenkanal' }),
        ...(s1 ? [{ titel: `Durchschnitt ${s1}`, wert: <>{ks?.mittel == null ? '—' : prozent(ks.mittel)} <span className="leise">zu klein</span> · {gs?.mittel == null ? '—' : prozent(gs.mittel)} <span className="leise">zu gross</span></>,
                      unter: eigene(ks) || eigene(gs) ? `${Math.max(ks?.n ?? 0, gs?.n ?? 0)} Sortierläufe dieser Sorte` : 'zu wenige eigene Messungen — der Gesamtwert aller Sorten' }] : []),
      ]} />

      {filter.gruppe !== 'charge' && sortenImFilter.length > 1 && (
        <>
          <h3 className="oben-0">Je Sorte <span className="leise">Anteil der Sortier-CSV, jeder Kürbis gewogen</span></h3>
          <div className="rollbar"><table className="dicht">
            <thead><tr><th>Sorte</th><th className="zahl">zu klein</th><th style={{ width: '22%' }}></th><th className="zahl">zu gross</th><th style={{ width: '22%' }}></th><th className="zahl">Sortierläufe</th></tr></thead>
            <tbody>{sortenImFilter.map(s => { const k = kleinS(s), g = grossS(s); return (
              <tr key={s} className={eigene(k) || eigene(g) ? '' : 'leise'}>
                <td><Link to={`/ursachen?sorte=${encodeURIComponent(s)}`}>{s}</Link></td>
                <td className="zahl"><strong>{k?.mittel == null ? '—' : prozent(k.mittel)}</strong>{k?.unten != null && k.oben != null && <div className="leise" style={{ fontSize: '.72rem' }}>{prozent(k.unten)}–{prozent(k.oben)}</div>}</td>
                <td><div className="balken-spur" style={{ height: 8 }}><div className="balken-fuellung waechst" style={{ width: `${((k?.mittel ?? 0) / maxAnteil) * 100}%`, background: 'var(--strom-ausschuss)' }} /></div></td>
                <td className="zahl"><strong>{g?.mittel == null ? '—' : prozent(g.mittel)}</strong>{g?.unten != null && g.oben != null && <div className="leise" style={{ fontSize: '.72rem' }}>{prozent(g.unten)}–{prozent(g.oben)}</div>}</td>
                <td><div className="balken-spur" style={{ height: 8 }}><div className="balken-fuellung waechst" style={{ width: `${((g?.mittel ?? 0) / maxAnteil) * 100}%`, background: 'var(--strom-nebenkanal)' }} /></div></td>
                <td className="zahl">{Math.max(k?.n ?? 0, g?.n ?? 0)}</td>
              </tr>
            ) })}</tbody>
          </table></div>
        </>
      )}

      {jeCharge.length > 0 && (
        <Aufklapp titel={<><span>{filter.gruppe === 'charge' ? 'Die Charge gegen ihre Sorte' : 'Je Charge'}</span> <span className="leise">{filter.gruppe === 'gesamt' && jeCharge.length > 15 ? `die 15 grössten von ${jeCharge.length}` : `${jeCharge.length} Chargen`}</span></>} offen={filter.gruppe === 'charge'}>
          <div className="rollbar"><table className="dicht">
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
          {filter.gruppe === 'gesamt' && jeCharge.length > 15 && <p className="fussnote">Eine Sorte wählen zeigt alle ihre Chargen.</p>}
        </Aufklapp>
      )}

      <Gewichtsverteilung daten={daten} filter={filter} sorte={sorte} />
      <Erklaerung>
        Gemessen an der Sortier-CSV (jeder Kürbis gewogen) — der Anteil der Sorte gilt für ihre ganze Ware, an der Waschstrasse wird nichts mehr gewogen.
        Zu klein geht an die Tiere, zu gross in den Nebenkanal: Die Ware ist nicht weg, nur nicht Hauptware. Darum steht sie nicht im Verlust bis heute.
      </Erklaerung>
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
  const { stufen, grenzen, gesamt, mittel, klassenfarbe, schema } = glockeVorbereiten(gewichte, daten.schemata, sorteAktiv, breite)
  return (
    <Aufklapp titel={<><span>Die Glocke: wie schwer sind die Kürbisse?</span> <span className="leise">{aktiv}{nach === 'charge' ? ` · ${sorteAktiv}` : ''} · {zahl(gesamt)} gewogen{mittel !== null ? ` · Schwerpunkt ${Math.round(mittel)} g` : ''}</span></>}>
      <div className="filterleiste">
        {werte.length > 1 && (
          <>
            <label htmlFor="gv-wahl">Sorte</label>
            <select id="gv-wahl" value={aktiv} onChange={e => setWahl(e.target.value)}>{werte.map(w => <option key={w}>{w}</option>)}</select>
          </>
        )}
        <label htmlFor="gv-breite">Stufe</label>
        <select id="gv-breite" value={breite} onChange={e => setBreite(Number(e.target.value))}>
          <option value={25}>25 g</option><option value={50}>50 g</option><option value={100}>100 g</option>
        </select>
        {schema && <span>Grenzen: Fassung vom {datum(schema.gilt_ab)}</span>}
      </div>
      <Glocke stufen={stufen} breite={breite} grenzen={grenzen} xFormat={x => `${x}`} klassenfarbe={klassenfarbe} mittel={mittel} hoehe={200} />
      {gruppe && (
        <div className="rollbar"><table className="kurz"><tbody>
          <tr><th>Kaliber</th>{gruppe.klassen.map(k => <th key={k.name}>{k.name}</th>)}</tr>
          <tr><td>Anteil der Stück</td>{gruppe.klassen.map(k => <td key={k.name}><strong>{prozent(gruppe.n > 0 ? k.n / gruppe.n : null, 0)}</strong></td>)}</tr>
          <tr><td>Gewogene Masse</td>{gruppe.klassen.map(k => <td key={k.name}>{kg(k.kg, 0)}</td>)}</tr>
        </tbody></table></div>
      )}
      <p className="fussnote">Glockenförmig oder zweigipflig, und wo liegt der Schwerpunkt zu den Kalibergrenzen? Eine Aussage über den Anbau, nicht über das Lager.</p>
    </Aufklapp>
  )
}

/* ---------- Fax: Faules beim Abpacken — eine Zahl --------------------------- */

function Fax({ daten, strom, eingang, chargen }: { daten: Auswertung; strom?: StromSumme; eingang: number; chargen: Set<number> }) {
  // Nur Arbeiten, bei denen das Faule wirklich gewogen wurde. Leer ist nicht null.
  const fax = daten.fax.filter(f => f.status === 'abgeschlossen' && f.plausibel
                                    && f.masse_kg != null && f.faul_erfasst && chargen.has(f.charge_nr))
  const masse = fax.reduce((s, f) => s + (f.masse_kg ?? 0) + f.faul_kg, 0)
  const faul = fax.reduce((s, f) => s + f.faul_kg, 0)
  const ohne = daten.fax.filter(f => f.status === 'abgeschlossen' && !f.faul_erfasst && chargen.has(f.charge_nr)).length
  return (
    <Karte titel="Faules beim Abpacken (Fax)" unter="Was nach dem Waschen beim Abpacken noch aussortiert wird — gerechnet an der abgepackten Ware.">
      <Zahlen zeilen={[
        Stromzahl({ v: strom, eingang, titel: 'Faules beim Abpacken bis heute' }),
        { titel: 'Gemessen an', wert: fax.length > 0 ? <>{fax.length} Fax-Arbeiten <Herkunft art="gemessen" /></> : <Marke art="warnung">keine Wägung</Marke>,
          unter: fax.length > 0 ? `${kg(faul, 0)} Faules von ${tonnen(masse)} abgepackter Ware, also ${prozent(masse > 0 ? faul / masse : null)}${ohne > 0 ? ` · ${ohne} weitere Fax-Arbeiten haben nichts gewogen` : ''}` : 'solange ist der Anteil unbekannt, nicht null' },
        ...(strom?.bekannt && strom.erwartet !== null && strom.erwartet > 0
          ? [{ titel: 'Erwartung für die Ware im Haus', wert: <>{kg(strom.erwartet, 0)} <Herkunft art="prognose" /></>, unter: 'was beim Abpacken noch dazukäme — steckt nicht im Verlust bis heute' }] : []),
      ]} />
      <Erklaerung>
        Nach dem Waschen steht die Ware ein bis drei Tage in Kisten, bis sie abgepackt wird; dabei wird nochmals aussortiert, was faul ist. Das kommt vom Waschen und vom Stehen danach, nicht von der Lagerdauer — darum eine eigene Ursache.
        Die Zahl beruht auf Fax-Arbeiten mit gewogenem Faulem <Herkunft art="gemessen" />; „nichts Faules" ist dabei eine Messung mit 0 kg.
      </Erklaerung>
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
  const kisten = alleKisten.filter(u => u.n_lieferungen > 0), kistenOhne = alleKisten.filter(u => u.n_lieferungen === 0)
  const stueck = alleStueck.filter(u => u.n_lieferungen > 0), stueckOhne = alleStueck.filter(u => u.n_lieferungen === 0)
  const unbekannt = zeilen.filter(u => u.kistensystem === 'unbekannt' && u.n_lieferungen > 0)
  const marge = daten.marge.find(m => m.posten.startsWith('Überfüllung'))
  const gerechnet = kisten.filter(u => u.verschenkt_kg != null)
  const verschenkt = gerechnet.reduce((s, u) => s + (u.verschenkt_kg ?? 0), 0)
  const verkauftOhne = kisten.filter(u => u.n_wiegungen === 0).reduce((s, u) => s + (u.kisten_verkauft ?? 0), 0)
  const datei = daten.ueberfuellung.some(u => u.n_lieferungen > 0)
  const band = (u: Ueberfuellung) => u.band_von_g != null && u.band_bis_g != null ? `${u.band_von_g}–${u.band_bis_g} g` : u.kaliber_idx != null ? `K${u.kaliber_idx + 1}` : '—'
  return (
    <Karte titel="Überfüllung: verschenkte Marge" unter="Was die Kiste über dem Soll hat, ist geschenkt — mal die verkauften Kisten.">
      <Zahlen zeilen={[
        { titel: 'Verschenkt bis heute', wert: gerechnet.length ? <>{kg(verschenkt, 0)} <Herkunft art="gerechnet" /></> : '—',
          unter: gerechnet.length ? `aus ${zahl(gerechnet.reduce((s, u) => s + (u.kisten_verkauft ?? 0), 0))} verkauften Kisten „ab x kg" mit gewogenem Gegenstück` : !datei ? 'keine Verkaufsdatei eingelesen — die verkauften Kisten sind unbekannt' : 'keine gewogene Palette dieses Systems' },
        { titel: 'Gewogene Paletten', wert: zahl(alleKisten.reduce((s, u) => s + u.n_wiegungen, 0)), unter: `${zahl(alleKisten.reduce((s, u) => s + (u.kisten_gewogen ?? 0), 0))} Kisten „ab x kg" auf der Waage` },
        ...(verkauftOhne > 0 ? [{ titel: 'Nicht gerechnet', wert: `${zahl(verkauftOhne)} Kisten`, unter: 'verkauft, aber kein gewogenes Gegenstück (Sorte oder Soll ohne Wägung)' }] : []),
      ]} />

      {kisten.length > 0 && (
        <>
          <h3 className="oben-0">Kiste ab x kg</h3>
          <div className="rollbar"><table className="dicht">
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
        <Aufklapp titel={<><span>Stück je Kiste</span> <span className="leise">{stueck.length} Sorten — kein Soll, keine verschenkte Marge, aber die Waage sagt, wo im Band die Ware liegt</span></>}>
          <div className="rollbar"><table className="dicht">
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
          <p className="fussnote">Liegt das gewogene Stück tief im Band, liesse sich ein engeres Band liefern — eine Beobachtung, kein Verlust.</p>
        </Aufklapp>
      )}
      {(kistenOhne.length > 0 || stueckOhne.length > 0) && (
        <Aufklapp titel={<><span>Gewogen, aber nicht verkauft</span> <span className="leise">{kistenOhne.length + stueckOhne.length} Kistensysteme — Wägungen ohne Gegenstück in der Verkaufsdatei</span></>}>
          <div className="rollbar"><table className="dicht">
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
        <p className="fussnote">Dazu {tonnen(unbekannt.reduce((s, u) => s + (u.kg_verkauft ?? 0), 0))} verkauft, deren Kistensystem die Datei nicht nennt (Einheit kg ohne Gebindeinhalt) — nichts gerechnet.</p>
      )}
      {kisten.length === 0 && stueck.length === 0 && <p className="leise unten-0">{datei ? 'Für diesen Filter nichts verkauft und nichts gewogen.' : 'Verkaufte Kisten kennt die App erst mit einer eingelesenen Verkaufsdatei — Betrieb → Warenausgang.'}</p>}
      <Erklaerung>
        Zwei Kistensysteme, zwei Rechnungen. <strong>Kiste ab x kg:</strong> Was die gewogene Kiste über dem Soll hat, ist geschenkt — mal die verkauften Kisten aus der Verkaufsdatei <Herkunft art="gemessen" />, nicht hochgerechnet; wo keine Wägung zum verkauften System passt, steht nichts.
        {' '}<strong>Stück je Kiste:</strong> kein Soll, keine verschenkte Marge — aber die Waage sagt, wie schwer die Stücke wirklich sind, und die Datei, was als Nenngewicht verkauft wurde.
        {marge && !marge.gemessen && <> {marge.erlaeuterung}</>}
      </Erklaerung>
    </Karte>
  )
}
