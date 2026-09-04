import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { kg, prozent, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Balken, Hinweis, Karte, Kennzahl, Marke } from '../components/Bausteine'
import { Bilanzzeile } from '../components/Kaskadenbild'
import type { Befund, Bestand, NaechsteCharge, Saisonbilanz, Schimmelpunkt, SortenK, StromSumme } from './daten'

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

/** Die Ströme als Balken mit Bereich — beobachtet voll, projiziert schraffiert. */
export function Stromliste({ verluste, maximum }: { verluste: StromSumme[]; maximum: number }) {
  return (
    <>
      {verluste.map(v => (
        <div key={v.strom} className="balken-zeile">
          <div className="reihe">
            <strong>{v.strom}</strong>
            {!v.bekannt && <Marke art="warnung">nicht gemessen</Marke>}
            {v.bekannt && (v.koeffN ?? 0) < 3 && <Marke art="warnung">dünne Datenlage</Marke>}
            <span style={{ marginLeft: 'auto' }}>{v.bekannt ? tonnen(v.mittel) : '—'}</span>
          </div>
          <Balken wert={v.bekannt ? v.mittel : null} unten={v.unten} oben={v.oben} maximum={maximum} beobachtet={v.beobachtet} />
        </div>
      ))}
    </>
  )
}

/** Welche Charge als nächstes? Was zwei Wochen Warten kosten. */
export function NaechsteChargen({ zeilen, alle = false }: { zeilen: NaechsteCharge[]; alle?: boolean }) {
  const mitVerlust = zeilen.filter(z => (z.verlust_14_kg ?? 0) > 0).slice(0, alle ? undefined : 5)
  if (mitVerlust.length === 0) return null
  const summe = zeilen.reduce((a, z) => a + (z.verlust_14_kg ?? 0), 0)
  return (
    <Karte titel="Was kostet Warten?">
      <p className="leise">
        Voraussichtlicher Verlust, wenn die Charge zwei weitere Wochen liegen bleibt — Verdunstung
        nach der Sortenrate, Verderb nach dem Verlaufsmodell. Oben steht, was zuerst ans Band gehört.
      </p>
      <div className="rollbar">
        <table>
          <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">liegt seit</th>
            <th className="zahl">Bestand</th><th className="zahl">Verlust in 14 Tagen</th></tr></thead>
          <tbody>
            {mitVerlust.map(z => (
              <tr key={z.charge_nr}>
                <td><Link to={`/chargen?charge=${z.charge_nr}`}>{z.charge_nr}</Link></td>
                <td>{z.sorte}</td>
                <td className="zahl">{z.alter_tage} Tagen</td>
                <td className="zahl">{kg(z.masse_jetzt_kg, 0)}</td>
                <td className="zahl"><strong>{kg(z.verlust_14_kg ?? 0, 0)}</strong>{z.hochgerechnet && <span className="leise"> ~</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="leise" style={{ marginBottom: 0 }}>
        Alle liegenden Chargen zusammen: <strong>{kg(summe, 0)}</strong> in zwei Wochen.
        {mitVerlust.some(z => z.hochgerechnet) && ' ~ heisst: älter als die längste gemessene Lagerdauer, der Verderb ist hochgerechnet.'}
        {!mitVerlust[0]?.modell_gilt && ' Das Verderbsmodell trägt noch nicht — die Zahlen zeigen nur die Verdunstung.'}
      </p>
    </Karte>
  )
}

export function Sortenvergleich({ koeff }: { koeff: { verdunstung: SortenK[]; ausschuss: SortenK[] } }) {
  const eigene = (k: SortenK) => k.basis?.includes('dieser Sorte')
  const zeilen = koeff.verdunstung.filter(k => k.n > 0)
    .map(k => ({ sorte: k.sorte, v: k, a: koeff.ausschuss.find(x => x.sorte === k.sorte) }))
    .sort((x, y) => (x.v.mittel ?? 0) - (y.v.mittel ?? 0))
  if (zeilen.length < 2) return null
  return (
    <Karte titel="Sorten im Vergleich">
      <p className="leise">Nach Verdunstungsrate sortiert — oben hält am besten. Grau: zu wenige eigene Messungen, es gilt der Gesamtwert.</p>
      <div className="rollbar">
        <table>
          <thead><tr><th>Sorte</th><th className="zahl">Verdunstung je Tag</th><th className="zahl">Zu klein</th><th className="zahl">Messungen</th></tr></thead>
          <tbody>
            {zeilen.map(z => (
              <tr key={z.sorte} className={eigene(z.v) ? '' : 'leise'}>
                <td>{z.sorte}</td>
                <td className="zahl">
                  {z.v.mittel == null ? '—' : `${(z.v.mittel * 100).toFixed(3)} %`}
                  {z.v.unten != null && z.v.oben != null && z.v.oben > z.v.unten && (
                    <span className="leise"> ({(z.v.unten * 100).toFixed(3)}–{(z.v.oben * 100).toFixed(3)})</span>)}
                </td>
                <td className="zahl">{z.a?.mittel == null ? '—' : `${(z.a.mittel * 100).toFixed(1)} %`}</td>
                <td className="zahl">{z.v.n}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Karte>
  )
}

export function WartetAufsWaschen({ bestand }: { bestand: Bestand[] }) {
  const wartend = bestand.filter(b => b.wartet_kg > 0).sort((a, b) => b.wartet_kg - a.wartet_kg)
  const summe = wartend.reduce((s, b) => s + b.wartet_kg, 0)
  if (wartend.length === 0) return null
  return (
    <Karte titel="Sortiert — wartet aufs Waschen">
      <p className="leise">Durchs Sortierband, aber noch in Kaliber-Kisten in der Halle. Sie altert weiter. Oben steht, was am längsten wartet.</p>
      <div className="spalten"><Kennzahl titel="Wartet insgesamt" wert={tonnen(summe)} unter={`${wartend.length} Chargen`} /></div>
      <div className="rollbar">
        <table>
          <thead><tr><th>Charge</th><th>Sorte</th><th className="zahl">sortiert</th><th className="zahl">gewaschen</th><th className="zahl">wartet</th><th className="zahl">Liegt seit</th></tr></thead>
          <tbody>
            {wartend.slice(0, 15).map(b => (
              <tr key={b.charge_nr}>
                <td><Link to={`/chargen?charge=${b.charge_nr}`}>{b.charge_nr}</Link></td><td>{b.sorte}</td>
                <td className="zahl">{kg(b.sortiert_kg, 0)}</td><td className="zahl">{kg(b.gewaschen_kg, 0)}</td>
                <td className="zahl"><strong>{kg(b.wartet_kg, 0)}</strong></td><td className="zahl">{Math.round(b.alter_lager_heute)} Tagen</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Karte>
  )
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

/** Die Gegenprobe: Eingang = Verlust + Ausgang + Restbestand. */
export function Bilanz({ bilanz }: { bilanz: Saisonbilanz }) {
  return (
    <Karte titel="Geht die Rechnung auf?">
      <p className="leise">Die einzige Gegenprobe, die es gibt: Was eingelagert wurde, muss als Verlust, als Ausgang oder als Bestand wieder auftauchen. Was übrig bleibt, ist das, was das Modell nicht sieht.</p>
      <Bilanzzeile titel="Wareneingang" kg={bilanz.eingang_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-nebenkanal)" erklaerung="Netto ab Zettel, Tara abgezogen" />
      <Bilanzzeile titel="Physisch weg (Modell)" kg={bilanz.verlust_modell_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-schimmel)" erklaerung="Verdunstung und Schimmel, dazu die Grundaussortierung vom Feld" />
      <Bilanzzeile titel="Ausgeliefert" kg={bilanz.ausgang_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-rest)"
                   erklaerung={bilanz.n_lieferungen === 0 ? 'noch keine Lieferung erfasst' : `${bilanz.n_lieferungen} Lieferungen erfasst${bilanz.vorlauf_kg > 0 ? `, dazu ${tonnen(bilanz.vorlauf_kg)} vor dem Erfassungsbeginn` : ''}`} />
      <Bilanzzeile titel="Noch im Haus (Modell)" kg={bilanz.restbestand_modell_kg} eingang={bilanz.eingang_kg} farbe="var(--strom-verdunstung)"
                   erklaerung={`davon ${tonnen(bilanz.wartet_kg)} sortiert und wartet aufs Waschen`} />
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
