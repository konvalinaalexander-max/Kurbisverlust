import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zeitpunkt } from '../lib/format'
import { Herkunft, Hinweis, Karte, Marke } from '../components/Bausteine'
import { Bilanzzeile } from '../components/Kaskadenbild'
import { SCHRITTE, type Befund, type Fortschritt, type Problem, type Saisonbilanz, type Schimmelpunkt, type StromSumme } from './daten'

/** Kopfzeile eines Reiters: Name, der eine Satz, wozu er da ist, Stand, bis wann gerechnet, Neu rechnen. */
export function Reiterkopf({ titel, zweck, stand, heute, neuRechnen, rechts }: {
  titel: string; zweck: string; stand: string | null; heute?: string; neuRechnen?: () => void; rechts?: ReactNode
}) {
  return (
    <div style={{ marginTop: '1.25rem' }}>
      <div className="reihe">
        <h1 style={{ margin: 0 }}>{titel}</h1>
        <span className="leise" style={{ marginLeft: 'auto' }}>
          {heute && <>bis heute, {datum(heute)} · </>}Stand {stand ? zeitpunkt(stand) : '—'}
        </span>
        {neuRechnen && <button className="klein" onClick={neuRechnen}>Neu rechnen</button>}
        {rechts}
      </div>
      <p className="leise" style={{ margin: '.25rem 0 .75rem' }}>{zweck}</p>
    </div>
  )
}

/** Der Ladebildschirm: wo die Neuberechnung steht — fünf Schritte, der laufende hervorgehoben. */
export function Rechnet({ fortschritt }: { fortschritt: Fortschritt | null }) {
  return (
    <div className="rechnen">
      <div className="lade" style={{ padding: '1rem 0 0' }}>
        {fortschritt ? <>Auswertung wird gerechnet — Schritt {fortschritt.schritt} von {fortschritt.schritte}</> : 'Auswertung wird geladen …'}
      </div>
      {fortschritt && (
        <ol>
          {SCHRITTE.map((name, i) => {
            const nr = i + 1
            const zustand = nr < fortschritt.schritt ? 'fertig' : nr === fortschritt.schritt ? 'laeuft' : ''
            return <li key={name} className={zustand}><span className="nr">{zustand === 'fertig' ? '✓' : nr}</span>{name}</li>
          })}
        </ol>
      )}
    </div>
  )
}

/**
 * Sichten, die sich nicht lesen liessen, und Schritte, die nicht rechneten.
 * Früher riss eine davon den ganzen Bildschirm mit; jetzt fehlen nur ihre
 * Zahlen, und hier steht, welche.
 */
export function Probleme({ liste }: { liste: Problem[] }) {
  if (liste.length === 0) return null
  const rechnen = liste.filter(p => p.sicht.startsWith('Neu rechnen'))
  return (
    <Hinweis art="warnung">
      <strong>{rechnen.length ? 'Die Auswertung konnte nicht vollständig neu gerechnet werden.' : 'Ein Teil der Auswertung konnte nicht gelesen werden.'}</strong>{' '}
      {rechnen.length ? 'Gezeigt wird der letzte gespeicherte Stand.' : 'Alles Übrige auf dieser Seite stimmt; die betroffenen Zahlen stehen als „—".'}
      <ul style={{ margin: '.4rem 0 .3rem', paddingLeft: '1.2rem' }}>
        {liste.map((p, i) => <li key={i}><code>{p.sicht}</code> — {p.meldung}</li>)}
      </ul>
      <span className="leise">Was dahintersteckt, sagt <code>supabase/diagnose.sql</code> im
      SQL-Editor. Meist steht die Ursache auch unter Messungen → Auffälligkeiten.</span>
    </Hinweis>
  )
}

/** Der Rechenweg zu einem Strom — jede Zahl sagt, woher sie kommt. */
export function rechenweg(v: StromSumme, eingang: number): [string, ReactNode][] {
  return [
    ['Formel', v.formel],
    ['Bezugsmasse', kg(v.basis, 0)],
    ['Koeffizient', v.koeffBasis ? `${v.koeffBasis}${v.koeffN !== null ? ` · ${v.koeffN} Messungen` : ''}` : '—'],
    ['Ergebnis bis heute', v.bekannt
      ? `${kg(v.mittel, 0)} (${prozent(eingang > 0 ? v.mittel / eingang : null)} der Eingangsmasse)`
      : 'nicht gemessen — der Koeffizient hat keine einzige Messung'],
    ['Bereich', v.bereichBekannt
      ? `${kg(v.unten, 0)} – ${kg(v.oben, 0)} (95 %, aus den Messfehlern fortgepflanzt)` : '—'],
    ['Davon an ausgelieferter Ware', `${kg(v.beobachtet, 0)} — beim Alter am Liefertag`],
    ['Davon an der Ware im Haus', `${kg(v.projiziert, 0)} — beim Alter heute`],
    ['Davon jenseits der Messungen', v.extrapoliert > 0
      ? `${kg(v.extrapoliert, 0)} — liegt länger als die längste gemessene Lagerdauer, der Verlauf ist dorthin verlängert`
      : 'nichts — alle Lagerdauern sind durch Messungen abgedeckt'],
    ...(v.erwartet > 0 ? [['Erwartung, nicht Verlust', `${kg(v.erwartet, 0)} — was beim Abpacken der Ware im Haus noch anfallen dürfte; steht nicht in der Zahl`] as [string, ReactNode]] : []),
  ]
}

/** Woher die Schimmelkurve kommt — die Punkte mit ihrer Herkunft. */
export function Kurvenherkunft({ punkte }: { punkte: Schimmelpunkt[] }) {
  if (punkte.length === 0) return null
  const brauchbar = punkte.filter(p => p.plausibel && p.anteil !== null && p.anteil > 0)
  const verworfen = punkte.filter(p => !p.plausibel).length
  const klassen = [
    { name: 'aus der Verarbeitung', quelle: 'verarbeitung',
      erklaerung: 'Der Palox am Band oder am Waschbecken. Welche Palette wann drankommt, hängt oft davon ab, wie sie aussieht — diese Punkte sind nicht zufällig ausgewählt.' },
    { name: 'aus Lagerkontrollen', quelle: 'lager',
      erklaerung: 'Beim Wiegen aufgemacht und nachgesehen — nur bei älteren Kontrollen, die noch „davon faul" erfasst haben. Die Lagerkontrolle ist seit Runde H eine reine Verdunstungsmessung.' },
    { name: 'aus gemischten Chargen — nicht in der Kurve', quelle: 'verarbeitung_gemischt',
      erklaerung: 'Beim Abschluss wurde „nicht alles aus einer Charge" gesagt. Das Alter der Ware ist dann geraten; die Menge zählt in der Bilanz, aber nicht im Verlauf.' },
  ]
  return (
    <Karte titel="Woher die Schimmelkurve kommt">
      {klassen.map(k => {
        const eigene = brauchbar.filter(p => p.quelle === k.quelle)
        if (eigene.length === 0) return <p key={k.quelle} className="leise" style={{ marginBottom: '.8rem' }}><strong>{k.name}:</strong> keine. {k.erklaerung}</p>
        const tage = eigene.map(p => p.lagertage)
        return (
          <div key={k.quelle} style={{ marginBottom: '1rem' }}>
            <div className="reihe"><strong>{k.name}</strong>
              <span style={{ marginLeft: 'auto' }}>{eigene.length} Punkte · {Math.round(Math.min(...tage))}–{Math.round(Math.max(...tage))} Lagertage</span></div>
            <p className="leise" style={{ margin: '.2rem 0 0', fontSize: '.82rem' }}>{k.erklaerung}</p>
          </div>
        )
      })}
      {verworfen > 0 && (
        <Hinweis art="info">{verworfen} Messungen sind nicht eingeflossen, weil der daraus folgende Anteil unplausibel war — meist ein Zahlendreher. Sie stehen unter Messungen → Auffälligkeiten.</Hinweis>
      )}
    </Karte>
  )
}

/**
 * Die Gegenprobe: Eingang = verkauft + Verlust bis heute + anderer Kanal +
 * noch im Haus. Zwei Zahlen sind gemessen (Eingang, verkauft), der Rest ist
 * gerechnet — und die Lücke ist die Überzählung. Steht unter Messungen, weil
 * sie das Modell prüft, nicht den Betrieb.
 */
export function Bilanz({ bilanz }: { bilanz: Saisonbilanz }) {
  const kanalAusgelagert = bilanz.kanal_heute_kg - bilanz.kanal_im_haus_kg
  return (
    <Karte titel={<>Geht die Rechnung auf? <span className="leise" style={{ fontWeight: 480 }}>bis {datum(bilanz.heute)}</span></>}>
      <p className="leise">Eingang = verkauft + Verlust bis heute + anderer Kanal + noch im Haus. Sie geht von selbst auf, weil das Ausgelagerte aus den Lieferungen zurückgerechnet ist — geprüft wird an den Rändern: mehr geliefert als hereingekommen (Überzählung), an die Tiere Geliefertes gegen den gerechneten Kanal, Entsorgtes gegen den gerechneten Schimmel.</p>
      <Bilanzzeile titel="Wareneingang" herkunft="gemessen" kg={bilanz.eingang_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-nebenkanal)" erklaerung="Netto ab Zettel, Tara abgezogen" />
      <Bilanzzeile titel="Verkauft" herkunft="gemessen" kg={bilanz.geliefert_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-rest)"
                   erklaerung={bilanz.n_lieferungen === 0 ? 'noch keine Lieferung erfasst' : `${bilanz.n_lieferungen} Lieferungen${bilanz.vorlauf_kg > 0 ? `, dazu ${tonnen(bilanz.vorlauf_kg)} vor dem Erfassungsbeginn` : ''}`} />
      <Bilanzzeile titel="Verlust bis heute" herkunft="gerechnet" kg={bilanz.verlust_heute_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-schimmel)"
                   erklaerung={`Verdunstung ${tonnen(bilanz.verdunstung_heute_kg)} · Faules im Lager ${tonnen(bilanz.schimmel_heute_kg + bilanz.sockel_heute_kg)} · Faules beim Abpacken ${tonnen(bilanz.fax_heute_kg)}`} />
      <Bilanzzeile titel="Anderer Kanal am Ausgelagerten" herkunft="gerechnet" kg={kanalAusgelagert} eingang={bilanz.eingang_kg} farbe="var(--strom-ausschuss)"
                   erklaerung={`zu klein und zu gross hinter den Lieferungen — kein echter Verlust${bilanz.marge_kg > 0 ? `; laut Lieferscheinen ${tonnen(bilanz.marge_kg)} dorthin geliefert` : ''}`} />
      <Bilanzzeile titel="Noch im Haus" herkunft="gerechnet" kg={bilanz.im_haus_heute_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-verdunstung)"
                   erklaerung={`davon verkaufsfähig ${tonnen(bilanz.verkaufsfaehig_heute_kg)}, zu klein oder zu gross ${tonnen(bilanz.kanal_im_haus_kg)}`} />
      {(bilanz.ueberzaehlung_kg ?? 0) > 0 && (
        <Bilanzzeile titel="Überzählung" herkunft="gemessen" kg={bilanz.ueberzaehlung_kg ?? 0} eingang={bilanz.eingang_kg} farbe="var(--rot)" erklaerung="hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — meist fehlt Wareneingang" />
      )}
      <Hinweis art={bilanz.n_lieferungen === 0 ? 'warnung' : (bilanz.ueberzaehlung_kg ?? 0) > 0.05 * bilanz.eingang_kg ? 'warnung' : 'gut'}>{bilanz.befund}</Hinweis>
    </Karte>
  )
}

/**
 * Auffälligkeiten — Messungen, die nicht richtig aussehen, mit Rat und dem
 * Weg zur Korrektur: Jede zeigt auf ihre Arbeit, wo der Betriebsleiter den
 * Wert ändern kann (Runde H). Sie stehen nur hier, nicht bei den Chargen.
 */
export function Auffaelligkeiten({ befunde, kurz = false }: { befunde: Befund[]; kurz?: boolean }) {
  if (befunde.length === 0) return kurz ? null : <Karte titel="Auffälligkeiten"><p className="leise" style={{ margin: 0 }}>Keine — jede Messung passt zu ihrem Nenner.</p></Karte>
  const liste = kurz ? befunde.slice(0, 3) : befunde
  return (
    <Karte titel={`Auffälligkeiten (${befunde.length})`}
           aktion={kurz && befunde.length > 3 ? <Link to="/messungen">alle ansehen</Link> : undefined}>
      <p className="leise">Diese Werte fliessen bewusst <em>nicht</em> in die Rechnung ein — sie würden sie verfälschen. Fast immer ist ein Tippfehler zu korrigieren oder etwas nachzutragen; „korrigieren" öffnet die Arbeit mit ihren Messungen.</p>
      <ul style={{ margin: 0, paddingLeft: '1.2rem' }}>
        {liste.map((b, i) => (
          <li key={i} style={{ marginBottom: '.45rem' }}>
            <Marke art="warnung">{b.art}</Marke> <strong>Charge {b.charge_nr} · {b.sorte}</strong> — {b.befund}
            <br /><span className="leise">{b.rat}</span>
            {b.auftrag_id && <> · <Link to={`/arbeit/${b.auftrag_id}?korrigieren=1`}>korrigieren</Link></>}
          </li>
        ))}
      </ul>
    </Karte>
  )
}

export { Herkunft }
