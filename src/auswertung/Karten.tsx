import { type ReactNode } from 'react'
import { datum, lesbar, tonnen, vorZeit, zeitpunkt } from '../lib/format'
import { Erklaerung, Hinweis, Karte } from '../components/Bausteine'
import { ZAktualisieren, ZHaken } from '../components/Zeichen'
import { Bilanzzeile } from '../components/Kaskadenbild'
import { SCHRITTE, type Fortschritt, type Problem, type Saisonbilanz, type Schimmelpunkt, type Zeitplan } from './daten'
import { summeBekannt } from '../lib/masse'
import { anforderungOffen, rechnetGerade } from '../lib/zeitplan'

/**
 * Kopfzeile eines Reiters: Name, der eine Satz, wozu er da ist; rechts der
 * Stand der Rechnung als Chip („vor 12 min") und „Neu rechnen".
 */
export function Reiterkopf({ titel, zweck, stand, heute, neuRechnen, rechts, laeuft, zeitplan, veraltet, aktuell }: {
  titel: string; zweck?: string; stand: string | null; heute?: string; neuRechnen?: () => void; rechts?: ReactNode; laeuft?: boolean
  /** 0095: läuft ein Zeitplan (wirklich — zustand), und ist dieser Stand veraltet, weil die App ihm das Rechnen überlässt? */
  zeitplan?: Zeitplan; veraltet?: boolean
  /** Seit dieser Rechnung nichts Neues erfasst? Dann sagt der Chip „aktuell", auch wenn sie eine Stunde her ist. */
  aktuell?: boolean
}) {
  const zustand = zeitplan?.zustand ?? 'fehlt'
  const uhr = (d: Date) => d.toLocaleTimeString('de-CH', { hour: '2-digit', minute: '2-digit' })
  const letzterLauf = zeitplan?.letzterStart
    ? `letzter Lauf ${zeitpunkt(zeitplan.letzterStart)}${zeitplan.letzterStatus === 'failed' ? ', fehlgeschlagen' : zeitplan.letzterStatus ? `, ${zeitplan.letzterStatus}` : ''}${zeitplan.letzteMeldung && zeitplan.letzterStatus === 'failed' ? ` (${zeitplan.letzteMeldung})` : ''}`
    : 'noch nie gelaufen'
  const zeitplanText = zustand === 'laeuft'
    ? `Zeitplan läuft (${zeitplan!.takt ?? 'in der Datenbank'}) · ${letzterLauf}`
    : zustand === 'rechnet_nicht'
      ? `Zeitplan eingetragen, rechnet aber nicht — ${letzterLauf}. „Neu rechnen" fordert einen Lauf an; bleibt er aus, unter Betrieb nachsehen.`
      : 'Kein Zeitplan in der Datenbank — „Neu rechnen" rechnet dann in der App, Schritt für Schritt (pg_cron einschalten, siehe README)'
  // Runde AG: eine offene Anforderung („Neu rechnen") steht im Chip, bis der Stand steht.
  const angefordert = anforderungOffen(zeitplan?.angefordertTs, stand)
  return (
    <div className="seitenkopf">
      <div>
        <h1>{titel}</h1>
        {zweck && <p className="zweck">{zweck}</p>}
      </div>
      <div className="rechts">
        {stand && (
          <span className="stand-chip" data-zeitplan={zustand} data-veraltet={veraltet ? 'ja' : 'nein'} data-aktuell={aktuell ? 'ja' : 'nein'}
                title={`Gerechnet ${zeitpunkt(stand)}${heute ? ` — Zahlen bis heute, ${datum(heute)}` : ''}${aktuell ? ' · seither nichts Neues erfasst, die Zahlen sind aktuell' : ''} · ${zeitplanText}`}>
            Stand {vorZeit(stand)}{heute ? ` · bis ${datum(heute).slice(0, 6)}` : ''}
            {aktuell && <span className="leise"> · aktuell</span>}
            {/* 0100: „wird gerade erneuert" gilt für jeden, der rechnet — Zeitplan
                oder ein anderes Fenster —, nicht nur für den laufenden Zeitplan. */}
            {angefordert && <span className="leise"> · Neu rechnen angefordert {uhr(new Date(zeitplan!.angefordertTs!))}, wird gerechnet</span>}
            {!angefordert && veraltet && rechnetGerade(zeitplan?.rechnetSeit) && <span className="leise"> · wird gerade erneuert</span>}
            {/* 0107: Die Halle löst keine Rechnung mehr aus — gerechnet wird nachts
                und auf „Neu rechnen". Das sagt der Chip, statt „rechnet nach" zu versprechen. */}
            {!angefordert && veraltet && zustand === 'laeuft' && !rechnetGerade(zeitplan!.rechnetSeit)
              && <span className="leise"> · Neues erfasst, rechnet heute Nacht</span>}
            {zeitplan && zustand === 'fehlt' && <span className="leise"> · kein Zeitplan</span>}
            {zustand === 'rechnet_nicht' && <span className="leise"> · Zeitplan rechnet nicht</span>}
          </span>
        )}
        {/* Runde AG (0102): Der Knopf rechnet nicht im Browser, er fordert an —
            der Zeitplan rechnet im Hintergrund unter seiner Zeitgrenze (15 min),
            und der Chip sagt „angefordert", bis der Stand steht. Darum gibt es
            ihn immer; ohne Zeitplan rechnet die App Schritt für Schritt. */}
        {neuRechnen && <button type="button" className="klein" onClick={neuRechnen} disabled={laeuft || angefordert}
                               title="Fordert einen neuen Stand an — der Zeitplan rechnet ihn im Hintergrund (etwa zwei Minuten); die Seite lädt dann von selbst nach"><ZAktualisieren size={15} />Neu rechnen</button>}
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
        {!fortschritt ? 'Auswertung wird geladen …'
          : fortschritt.titel === 'angefordert' ? <>Neu rechnen angefordert — der Zeitplan rechnet im Hintergrund, etwa zwei Minuten. Diese Seite lädt dann von selbst nach.</>
          : fortschritt.schritt === 0 ? <>Auswertung wird gerade an anderer Stelle gerechnet — dieses Fenster wartet und lädt dann nach</>
          : <>Auswertung wird gerechnet — Schritt {fortschritt.schritt} von {fortschritt.schritte}</>}
      </div>
      {fortschritt && fortschritt.schritt > 0 && (
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

/** Woher die Palox-Anteile kommen — die Punkte mit ihrer Herkunft (seit 0106 die Stationswerte statt der Kurve). */
export function Kurvenherkunft({ punkte }: { punkte: Schimmelpunkt[] }) {
  if (punkte.length === 0) return null
  const brauchbar = punkte.filter(p => p.plausibel && p.anteil !== null && p.anteil > 0)
  const verworfen = punkte.filter(p => !p.plausibel).length
  const klassen = [
    { name: 'aus der Verarbeitung', quelle: 'verarbeitung',
      erklaerung: 'Der Palox am Band oder am Waschbecken. Welche Palette wann drankommt, hängt oft davon ab, wie sie aussieht — diese Punkte sind nicht zufällig ausgewählt.' },
    { name: 'aus Lagerkontrollen', quelle: 'lager',
      erklaerung: 'Beim Wiegen aufgemacht und nachgesehen — nur bei älteren Kontrollen, die noch „davon faul" erfasst haben; heute misst die Lagerkontrolle nur die Verdunstung.' },
    { name: 'aus gemischten Chargen', quelle: 'verarbeitung_gemischt',
      erklaerung: 'Beim Abschluss wurde „nicht alles aus einer Charge" gesagt. Das Alter der Ware ist dann geraten — der Stationswert braucht keines, darum zählt die Messung mit.' },
  ]
  return (
    <Karte titel="Woher die Palox-Anteile kommen">
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
 * Die Gegenprobe: Eingang = ausgeliefert + Verlust bis heute + noch im Haus.
 * Zwei Zahlen sind gemessen (Eingang, ausgeliefert), der Rest ist gerechnet —
 * und die Lücke ist die Überzählung. Runde AF (0101): Ausgang ist nur, was
 * auf einem Lieferschein steht; zu klein und zu gross, das beim Sortieren
 * herausfällt, steht im Haus, bis ein Lieferschein es holt — der Betrieb:
 * „die stehen dann schon noch im Lager".
 */
export function Bilanz({ bilanz }: { bilanz: Saisonbilanz }) {
  const kanalImHaus = summeBekannt([bilanz.kanal_ausgelagert_kg, bilanz.kanal_im_haus_kg])
  return (
    <Karte titel="Geht die Rechnung auf?">
      <Bilanzzeile titel="Wareneingang" herkunft="gemessen" kg={bilanz.eingang_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-nebenkanal)" erklaerung="Netto ab Zettel, Tara abgezogen" />
      <Bilanzzeile titel="Ausgeliefert" herkunft="gemessen" kg={bilanz.geliefert_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-verkauft)"
                   erklaerung={bilanz.n_lieferungen === 0 ? 'noch keine Lieferung erfasst' : `${bilanz.n_lieferungen} Lieferungen ab Lieferschein${bilanz.marge_kg > 0 ? `, davon ${tonnen(bilanz.marge_kg)} an die Tiere oder in den Nebenkanal` : ''}${bilanz.vorlauf_kg > 0 ? `, dazu ${tonnen(bilanz.vorlauf_kg)} vor dem Erfassungsbeginn` : ''}`} />
      {/* 0106: Die Datenbank summiert nur die Chargen mit Wert; ist eine ohne
          (eine Station ohne Stationswert, ein Koeffizient ohne Messung), sagt
          verlust_bekannt es — und die Karte zeigt keine Teilsumme als Ganzes. */}
      <Bilanzzeile titel="Verlust bis heute" herkunft="gerechnet" kg={bilanz.verlust_bekannt ? bilanz.verlust_heute_kg : null} eingang={bilanz.eingang_kg} farbe="var(--strom-schimmel)"
                   erklaerung={bilanz.verlust_bekannt
                     ? `Verdunstung ${tonnen(bilanz.verdunstung_heute_kg)} · Palox ${tonnen(bilanz.schimmel_heute_kg)} · Faules beim Abpacken ${tonnen(bilanz.fax_heute_kg)}`
                     : `nicht für jede Charge bekannt — ein Koeffizient ohne Messung (welche Charge: Reiter Chargen; was zu messen ist: Messungen ausstehend). Nur die Chargen mit Wert: Verdunstung ${tonnen(bilanz.verdunstung_heute_kg)} · Palox ${tonnen(bilanz.schimmel_heute_kg)} · Faules beim Abpacken ${tonnen(bilanz.fax_heute_kg)}`} />
      <Bilanzzeile titel="Noch im Haus" herkunft="gerechnet" kg={bilanz.im_haus_heute_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-verdunstung)"
                   erklaerung={`davon verkaufsfähig ${tonnen(bilanz.verkaufsfaehig_heute_kg)} · zu klein oder zu gross ${tonnen(kanalImHaus)}${kanalImHaus !== null ? ` (${tonnen(bilanz.kanal_ausgelagert_kg)} beim Sortieren hinter den Lieferungen aussortiert, ${tonnen(bilanz.kanal_im_haus_kg)} im Liegenden erwartet) — steht im Haus, bis ein Lieferschein es holt` : ''}`} />
      {bilanz.ueberzaehlung_kg > 0 && (
        <Bilanzzeile titel="Überzählung" herkunft="gemessen" kg={bilanz.ueberzaehlung_kg} eingang={bilanz.eingang_kg} farbe="var(--rot)" erklaerung="hinter den Lieferungen steckt mehr Ware, als je eingelagert wurde — meist fehlt Wareneingang" />
      )}
      <Hinweis art={bilanz.n_lieferungen === 0 ? 'warnung' : bilanz.ueberzaehlung_kg > 0.05 * bilanz.eingang_kg ? 'warnung' : 'gut'}>{lesbar(bilanz.befund)}</Hinweis>
      <Erklaerung titel="Warum die Rechnung von selbst aufgeht">
        Eingang + Überzählung = ausgeliefert + Verlust bis heute + noch im Haus, bis {datum(bilanz.heute)}. Ausgeliefert ist nur, was auf einem Lieferschein
        steht. Sie geht von selbst auf, weil das Ausgelagerte aus den Lieferscheinen zurückgerechnet ist — bis auf Rundung, und genau darum taugt sie als Probe:
        Solange in der Kaskade ein Kilo doppelt oder zu früh zählte, blieb ein Rest stehen. Zu klein und zu gross, das beim Sortieren herausfällt, ist kein
        Ausgang: es steht im Haus, nicht verkaufsfähig, bis ein Lieferschein es holt. Geprüft wird an den Rändern: mehr geliefert als hereingekommen
        (Überzählung — ein Datenfehler, kein Verlust), an die Tiere Geliefertes gegen das gerechnet Aussortierte, Entsorgtes gegen den gerechneten Schimmel.
      </Erklaerung>
    </Karte>
  )
}

/*
 * Die Auffälligkeiten stehen seit Runde BG Fall für Fall in
 * AuffaelligkeitFaelle.tsx — mit Nummer, Daten, Erklärung, Vorschlag und Stand.
 */
