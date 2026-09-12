import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { datum, kg, prozent, tonnen, vorZeit, zeitpunkt } from '../lib/format'
import { Erklaerung, Herkunft, Hinweis, Karte, Marke } from '../components/Bausteine'
import { ZAktualisieren, ZHaken } from '../components/Zeichen'
import { Bilanzzeile } from '../components/Kaskadenbild'
import { SCHRITTE, type Befund, type Fortschritt, type Problem, type Saisonbilanz, type Schimmelpunkt, type StromSumme } from './daten'
import { summeBekannt } from '../lib/masse'

/**
 * Kopfzeile eines Reiters: Name, der eine Satz, wozu er da ist; rechts der
 * Stand der Rechnung als Chip („vor 12 min") und „Neu rechnen".
 */
export function Reiterkopf({ titel, zweck, stand, heute, neuRechnen, rechts, laeuft }: {
  titel: string; zweck?: string; stand: string | null; heute?: string; neuRechnen?: () => void; rechts?: ReactNode; laeuft?: boolean
}) {
  return (
    <div className="seitenkopf">
      <div>
        <h1>{titel}</h1>
        {zweck && <p className="zweck">{zweck}</p>}
      </div>
      <div className="rechts">
        {stand && (
          <span className="stand-chip" title={`Gerechnet ${zeitpunkt(stand)}${heute ? ` — Zahlen bis heute, ${datum(heute)}` : ''}`}>
            Stand {vorZeit(stand)}{heute ? ` · bis ${datum(heute).slice(0, 6)}` : ''}
          </span>
        )}
        {neuRechnen && <button type="button" className="klein" onClick={neuRechnen} disabled={laeuft}><ZAktualisieren size={15} />Neu rechnen</button>}
        {rechts}
      </div>
    </div>
  )
}

/** Der Ladebildschirm: wo die Neuberechnung steht — fünf Schritte, der laufende hervorgehoben. */
export function Rechnet({ fortschritt }: { fortschritt: Fortschritt | null }) {
  return (
    <div className="rechnen">
      <div className="drehen" aria-hidden="true" />
      <div className="rechnen-kopf">
        {fortschritt ? <>Auswertung wird gerechnet — Schritt {fortschritt.schritt} von {fortschritt.schritte}</> : 'Auswertung wird geladen …'}
      </div>
      {fortschritt && (
        <ol>
          {SCHRITTE.map((name, i) => {
            const nr = i + 1
            const zustand = nr < fortschritt.schritt ? 'fertig' : nr === fortschritt.schritt ? 'laeuft' : ''
            return <li key={name} className={zustand}><span className="nr">{zustand === 'fertig' ? <ZHaken size={12} /> : nr}</span>{name}</li>
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
    // 0066: Die vier Teilbeträge sind null, solange der Strom nicht gemessen
    // ist — und sonst Zahlen, auch wenn ihre Portion leer ist.
    ['Davon an ausgelieferter Ware', v.beobachtet === null
      ? 'nicht gemessen' : `${kg(v.beobachtet, 0)} — beim Alter am Liefertag`],
    ['Davon an der Ware im Haus', v.projiziert === null
      ? 'nicht gemessen' : `${kg(v.projiziert, 0)} — beim Alter heute`],
    ['Davon jenseits der Messungen', v.extrapoliert === null
      ? 'nicht gemessen'
      : v.extrapoliert > 0
        ? `${kg(v.extrapoliert, 0)} — liegt länger als die längste gemessene Lagerdauer, der Verlauf ist dorthin verlängert`
        : 'nichts — alle Lagerdauern sind durch Messungen abgedeckt'],
    ...(v.erwartet !== null && v.erwartet > 0 ? [['Erwartung, nicht Verlust', `${kg(v.erwartet, 0)} — was beim Abpacken der Ware im Haus noch anfallen dürfte; steht nicht in der Zahl`] as [string, ReactNode]] : []),
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
    <Karte titel="Woher die Schimmelkurve kommt" unter="Welche Messungen die Kurve tragen — und welche nicht.">
      <div className="rollbar"><table className="dicht">
        <thead><tr><th>Herkunft</th><th className="zahl">Punkte</th><th className="zahl">Lagertage</th></tr></thead>
        <tbody>{klassen.map(k => {
          const eigene = brauchbar.filter(p => p.quelle === k.quelle)
          const tage = eigene.map(p => p.lagertage)
          return (
            <tr key={k.quelle}>
              <td>{k.name}<div className="leise-satz" style={{ margin: '.1rem 0 0' }}>{k.erklaerung}</div></td>
              <td className="zahl">{eigene.length || <span className="leise">keine</span>}</td>
              <td className="zahl">{eigene.length ? `${Math.round(Math.min(...tage))}–${Math.round(Math.max(...tage))}` : '—'}</td>
            </tr>
          )
        })}</tbody>
      </table></div>
      {verworfen > 0 && (
        <p className="fussnote">{verworfen} Messungen sind nicht eingeflossen, weil der daraus folgende Anteil unplausibel war — meist ein Zahlendreher. Sie stehen unter Auffälligkeiten.</p>
      )}
    </Karte>
  )
}

/**
 * Die Gegenprobe: Eingang = verkauft + Verlust bis heute + anderer Kanal +
 * noch im Haus. Zwei Zahlen sind gemessen (Eingang, verkauft), der Rest ist
 * gerechnet — und die Lücke ist die Überzählung.
 */
export function Bilanz({ bilanz }: { bilanz: Saisonbilanz }) {
  const kanalAusgelagert = bilanz.kanal_ausgelagert_kg
  return (
    <Karte titel="Geht die Rechnung auf?" unter={`Eingang + Überzählung = ausgeliefert + Verlust bis heute + anderer Kanal + noch im Haus — bis ${datum(bilanz.heute)}.`}>
      <Bilanzzeile titel="Wareneingang" herkunft="gemessen" kg={bilanz.eingang_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-nebenkanal)" erklaerung="Netto ab Zettel, Tara abgezogen" />
      <Bilanzzeile titel="Ausgeliefert" herkunft="gemessen" kg={bilanz.geliefert_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-rest)"
                   erklaerung={bilanz.n_lieferungen === 0 ? 'noch keine Lieferung erfasst' : `${bilanz.n_lieferungen} Lieferungen${bilanz.vorlauf_kg > 0 ? `, dazu ${tonnen(bilanz.vorlauf_kg)} vor dem Erfassungsbeginn` : ''}`} />
      <Bilanzzeile titel="Verlust bis heute" herkunft="gerechnet" kg={bilanz.verlust_heute_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-schimmel)"
                   erklaerung={`Verdunstung ${tonnen(bilanz.verdunstung_heute_kg)} · Faules im Lager ${tonnen(summeBekannt([bilanz.schimmel_heute_kg, bilanz.sockel_heute_kg]))} · Faules beim Abpacken ${tonnen(bilanz.fax_heute_kg)}`} />
      <Bilanzzeile titel="Anderer Kanal am Ausgelagerten" herkunft="gerechnet" kg={kanalAusgelagert} eingang={bilanz.eingang_kg} farbe="var(--strom-ausschuss)"
                   erklaerung={`zu klein und zu gross hinter den Lieferungen — kein echter Verlust${bilanz.marge_kg > 0 ? `; laut Lieferscheinen ${tonnen(bilanz.marge_kg)} dorthin geliefert` : ''}`} />
      <Bilanzzeile titel="Noch im Haus" herkunft="gerechnet" kg={bilanz.im_haus_heute_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-verdunstung)"
                   erklaerung={`davon verkaufsfähig ${tonnen(bilanz.verkaufsfaehig_heute_kg)}, zu klein oder zu gross ${tonnen(bilanz.kanal_im_haus_kg)}`} />
      {bilanz.ueberzaehlung_kg > 0 && (
        <Bilanzzeile titel="Überzählung" herkunft="gemessen" kg={bilanz.ueberzaehlung_kg} eingang={bilanz.eingang_kg} farbe="var(--rot)" erklaerung="hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — meist fehlt Wareneingang" />
      )}
      <Hinweis art={bilanz.n_lieferungen === 0 ? 'warnung' : bilanz.ueberzaehlung_kg > 0.05 * bilanz.eingang_kg ? 'warnung' : 'gut'}>{bilanz.befund}</Hinweis>
      <Erklaerung titel="Warum die Rechnung von selbst aufgeht">
        Sie geht von selbst auf, weil das Ausgelagerte aus den Lieferungen zurückgerechnet ist — bis auf Rundung, und genau darum taugt sie als Probe:
        Solange in der Kaskade ein Kilo doppelt oder zu früh zählte, blieb ein Rest stehen. Geprüft wird an den Rändern: mehr geliefert als hereingekommen
        (Überzählung — ein Datenfehler, kein Verlust), an die Tiere Geliefertes gegen den gerechneten Kanal, Entsorgtes gegen den gerechneten Schimmel.
      </Erklaerung>
    </Karte>
  )
}

/** Die Farbkante einer Auffälligkeit: rot (Messfehler), gelb (Datum), blau (nur ein Hinweis). */
function befundTon(art: string): '' | 'gelb' | 'blau' {
  const a = art.toLowerCase()
  if (a.includes('datum') || a.includes('zukunft')) return 'gelb'
  if (a.includes('hinweis') || a.includes('fehlt')) return 'blau'
  return ''
}

/**
 * Auffälligkeiten — Messungen, die nicht richtig aussehen, mit Rat und dem
 * Weg zur Korrektur: Jede zeigt auf ihre Arbeit, wo der Betriebsleiter den
 * Wert ändern kann. Sie stehen nur hier, nicht bei den Chargen.
 */
export function Auffaelligkeiten({ befunde, kurz = false }: { befunde: Befund[]; kurz?: boolean }) {
  if (befunde.length === 0) return kurz ? null : (
    <Karte titel="Auffälligkeiten" unter="Messungen, die nicht zu ihrem Nenner passen.">
      <div className="hinweis gut" style={{ margin: 0 }}><span className="hinweis-zeichen"><ZHaken size={18} /></span><div className="hinweis-text">Keine — jede Messung passt zu ihrem Nenner.</div></div>
    </Karte>
  )
  const liste = kurz ? befunde.slice(0, 3) : befunde
  return (
    <Karte titel={`Auffälligkeiten (${befunde.length})`}
           unter="Diese Werte fliessen nicht in die Rechnung ein — fast immer ist ein Tippfehler zu korrigieren oder etwas nachzutragen."
           aktion={kurz && befunde.length > 3 ? <Link to="/messungen" className="knopf klein">alle {befunde.length} ansehen</Link> : undefined}>
      <div className="befunde">
        {liste.map((b, i) => (
          <div key={i} className={`befund ${befundTon(b.art)}`}>
            <div className="befund-kopf"><Marke art="warnung" punkt={false}>{b.art}</Marke> Charge {b.charge_nr} · {b.sorte}</div>
            <div className="befund-text">{b.befund}</div>
            <div className="befund-rat">{b.rat}</div>
            {b.auftrag_id && <Link className="knopf klein befund-aktion" to={`/arbeit/${b.auftrag_id}?korrigieren=1`}>korrigieren</Link>}
          </div>
        ))}
      </div>
    </Karte>
  )
}

export { Herkunft }
