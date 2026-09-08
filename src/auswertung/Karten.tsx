import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { kg, prozent, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Marke } from '../components/Bausteine'
import { Bilanzzeile } from '../components/Kaskadenbild'
import type { Befund, Problem, Saisonbilanz, Schimmelpunkt, StromSumme } from './daten'

/** Kopfzeile eines Reiters: Name, der eine Satz, wozu er da ist, Stand, Neu rechnen. */
export function Reiterkopf({ titel, zweck, stand, neuRechnen, rechts }: {
  titel: string; zweck: string; stand: string | null; neuRechnen?: () => void; rechts?: ReactNode
}) {
  return (
    <div style={{ marginTop: '1.25rem' }}>
      <div className="reihe">
        <h1 style={{ margin: 0 }}>{titel}</h1>
        <span className="leise" style={{ marginLeft: 'auto' }}>Stand {stand ? zeitpunkt(stand) : '—'}</span>
        {neuRechnen && <button className="klein" onClick={neuRechnen}>Neu rechnen</button>}
        {rechts}
      </div>
      <p className="leise" style={{ margin: '.25rem 0 .75rem' }}>{zweck}</p>
    </div>
  )
}

/**
 * Sichten, die sich nicht lesen liessen. Früher riss eine davon den ganzen
 * Bildschirm mit; jetzt fehlen nur ihre Zahlen, und hier steht, welche.
 */
export function Probleme({ liste }: { liste: Problem[] }) {
  if (liste.length === 0) return null
  return (
    <Hinweis art="warnung">
      <strong>Ein Teil der Auswertung konnte nicht gerechnet werden.</strong> Alles Übrige auf
      dieser Seite stimmt; die betroffenen Zahlen stehen als „—".
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
    ['Ergebnis', v.bekannt
      ? `${kg(v.mittel, 0)} (${prozent(eingang > 0 ? v.mittel / eingang : null)} der Eingangsmasse)`
      : 'nicht gemessen — der Koeffizient hat keine einzige Messung'],
    ['Bereich', v.bereichBekannt
      ? `${kg(v.unten, 0)} – ${kg(v.oben, 0)} (95 %, aus den Messfehlern fortgepflanzt)` : 'wird gerechnet …'],
    ['Davon beobachtet', kg(v.beobachtet, 0)],
    ['Davon projiziert', `${kg(v.projiziert, 0)} — Ware, die noch im Lager liegt`],
    ['Davon hochgerechnet', v.extrapoliert > 0
      ? `${kg(v.extrapoliert, 0)} — liegt länger als die längste gemessene Lagerdauer, der Verlauf ist dorthin verlängert`
      : 'nichts — alle Lagerdauern sind durch Messungen abgedeckt'],
  ]
}

/** Woher die Schimmelkurve kommt — die Punkte mit ihrer Herkunft. */
export function Herkunft({ punkte }: { punkte: Schimmelpunkt[] }) {
  if (punkte.length === 0) return null
  const brauchbar = punkte.filter(p => p.plausibel && p.anteil !== null && p.anteil > 0)
  const verworfen = punkte.filter(p => !p.plausibel).length
  const klassen = [
    { name: 'aus der Verarbeitung', quelle: 'verarbeitung',
      erklaerung: 'Der Palox am Band oder am Waschbecken. Welche Palette wann drankommt, hängt oft davon ab, wie sie aussieht — diese Punkte sind nicht zufällig ausgewählt.' },
    { name: 'zufällig gegriffene Lagerpaletten', quelle: 'lager',
      erklaerung: 'Beim Wiegen aufgemacht und nachgesehen. Die einzigen Punkte, deren Palette nicht nach ihrem Aussehen ausgewählt wurde.' },
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
 * Die Gegenprobe: Eingang = Verlust + Ausgang + Restbestand. Zwei Zahlen sind
 * gemessen (Eingang, Ausgang), der Rest ist Modell — und die Lücke ist, was
 * das Modell nicht sieht. Steht unter Messungen, weil sie das Modell prüft,
 * nicht den Betrieb.
 */
export function Bilanz({ bilanz }: { bilanz: Saisonbilanz }) {
  return (
    <Karte titel="Geht die Rechnung auf?">
      <p className="leise">Die einzige Gegenprobe, die es gibt: Was eingelagert wurde, muss als Verlust, als Ausgang oder als Bestand wieder auftauchen. Was übrig bleibt, ist das, was das Modell nicht sieht.</p>
      <Bilanzzeile titel="Wareneingang (gemessen)" kg={bilanz.eingang_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-nebenkanal)" erklaerung="Netto ab Zettel, Tara abgezogen" />
      <Bilanzzeile titel="Physisch weg (Modell)" kg={bilanz.verlust_modell_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-schimmel)" erklaerung="Verdunstung und Schimmel, dazu die Grundaussortierung vom Feld" />
      <Bilanzzeile titel="Ausgeliefert (gemessen)" kg={bilanz.ausgang_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-rest)"
                   erklaerung={bilanz.n_lieferungen === 0 ? 'noch keine Lieferung erfasst' : `${bilanz.n_lieferungen} Lieferungen erfasst${bilanz.vorlauf_kg > 0 ? `, dazu ${tonnen(bilanz.vorlauf_kg)} vor dem Erfassungsbeginn` : ''}`} />
      <Bilanzzeile titel="Noch im Haus (Modell)" kg={bilanz.restbestand_modell_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-verdunstung)"
                   erklaerung="was nach Verlust und Ausgang übrig bleibt" />
      <Bilanzzeile titel="Lücke" kg={Math.abs(bilanz.luecke_kg)} eingang={bilanz.eingang_kg} farbe="var(--rot)" erklaerung={`${prozent(bilanz.luecke_anteil)} des Eingangs`} />
      <Hinweis art={bilanz.n_lieferungen === 0 ? 'warnung' : Math.abs(bilanz.luecke_anteil ?? 1) < 0.05 ? 'gut' : 'info'}>{bilanz.befund}</Hinweis>
    </Karte>
  )
}

/** Auffälligkeiten — Messungen, die nicht richtig aussehen, mit Rat. */
export function Auffaelligkeiten({ befunde, kurz = false }: { befunde: Befund[]; kurz?: boolean }) {
  if (befunde.length === 0) return kurz ? null : <Karte titel="Auffälligkeiten"><p className="leise" style={{ margin: 0 }}>Keine — jede Messung passt zu ihrem Nenner.</p></Karte>
  const liste = kurz ? befunde.slice(0, 3) : befunde
  return (
    <Karte titel={`Auffälligkeiten (${befunde.length})`}
           aktion={kurz && befunde.length > 3 ? <Link to="/messungen">alle ansehen</Link> : undefined}>
      <p className="leise">Diese Werte fliessen bewusst <em>nicht</em> in die Rechnung ein — sie würden sie verfälschen. Fast immer ist etwas nachzutragen oder ein Tippfehler zu korrigieren.</p>
      <ul style={{ margin: 0, paddingLeft: '1.2rem' }}>
        {liste.map((b, i) => (
          <li key={i} style={{ marginBottom: '.4rem' }}>
            <Marke art="warnung">{b.art}</Marke> <strong>Charge {b.charge_nr} · {b.sorte}</strong> — {b.befund}
            <br /><span className="leise">{b.rat}</span>
            {b.auftrag_id && <> · <Link to={`/arbeit/${b.auftrag_id}`}>zur Arbeit</Link></>}
          </li>
        ))}
      </ul>
    </Karte>
  )
}

export const zahlKurz = (n: number | null | undefined) => zahl(n)
