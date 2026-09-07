import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import DemoDaten from '../components/DemoDaten'
import { datum, prozent, tonnen } from '../lib/format'
import { Hinweis, Karte, Kennzahl, Lade } from '../components/Bausteine'
import { Kaskadenbild, type Kaskadenstrom } from '../components/Kaskadenbild'
import { Diagramm } from '../components/Diagramm'
import { stroemeSummieren, useAuswertung, useRanking } from '../auswertung/daten'
import { Auffaelligkeiten, Bilanz, NaechsteChargen, Reiterkopf, Stromliste } from '../auswertung/Karten'
import { taetigkeitVon } from '../lib/taetigkeit'
import { WOERTERBUCH } from '../lib/i18n'
import { kg, zahl } from '../lib/format'
import type { Durchsatz } from '../auswertung/daten'

const TAG = 86400000

/**
 * Überblick: Wie viel verliere ich, woran — und was tue ich als nächstes?
 * Fünf Zahlen, ein Bild, eine Liste mit Handlungen. Alles Weitere steht
 * unter Ursachen, Chargen und Messungen.
 */
export default function Ueberblick() {
  const { daten, laedt, fehler, neuRechnen } = useAuswertung()
  const ranking = useRanking('', '', '', daten?.stand ?? null)
  const stroeme = useMemo(() => daten ? stroemeSummieren(daten.hochrechnung, ranking) : [], [daten, ranking])

  if (laedt && !daten) return <Lade text="Auswertung wird gerechnet …" />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  if (daten.hochrechnung.length === 0) {
    return (
      <>
        <Reiterkopf titel="Überblick" zweck="Wie viel verliere ich, woran — und was tue ich als nächstes?" stand={daten.stand} />
        <Hinweis>Noch keine auswertbaren Daten. Dafür braucht es mindestens Eingangspaletten mit hinterlegter Tara — siehe Betrieb → Stammdaten.</Hinweis>
        <DemoDaten kompakt nachAenderung={() => void neuRechnen()} />
      </>
    )
  }

  const verluste = stroeme.filter(s => s.buch === 'verlust').sort((a, b) => Number(b.bekannt) - Number(a.bekannt) || b.mittel - a.mittel)
  const proCharge = new Map<number, number>()
  for (const z of daten.hochrechnung) proCharge.set(z.charge_nr, z.eingang_kg)
  const eingang = [...proCharge.values()].reduce((a, b) => a + b, 0)
  const verlustGesamt = verluste.filter(v => v.bekannt).reduce((s, v) => s + v.mittel, 0)
  const maximum = Math.max(...verluste.map(v => Math.max(v.mittel, v.oben)), 1)
  const haupt = verluste.find(v => v.bekannt)
  const abzweigend = (b: string) => b === 'verlust' || b === 'marge' || b === 'feld'
  const unbekannt = stroeme.filter(s => !s.bekannt && abzweigend(s.buch))
  const feld = stroeme.find(s => s.buch === 'feld')
  const kaskade: Kaskadenstrom[] = stroeme.filter(s => s.bekannt && abzweigend(s.buch) && s.mittel > 0)
    .sort((a, b) => b.mittel - a.mittel)
    .map(s => ({ name: s.strom, kg: s.mittel, unten: s.unten, oben: s.oben, buch: s.buch as 'verlust' | 'feld' | 'marge',
                 bereichBekannt: s.bereichBekannt, extrapoliert: s.extrapoliert }))
  const verkaufsfaehig = Math.max(eingang - kaskade.reduce((a, s) => a + s.kg, 0), 0)
  const duenn = verluste.filter(v => v.bekannt && (v.koeffN ?? 0) < 3)
  const q = daten.qualitaet
  const luecken: string[] = []
  if (q) {
    if (q.arbeiten_fertig - q.arbeiten_mit_ablesung > 0) luecken.push(`${q.arbeiten_fertig - q.arbeiten_mit_ablesung} von ${q.arbeiten_fertig} Arbeiten ohne Palox-Ablesung`)
    if (q.paletten_gezaehlt - q.paletten_mit_datum > 0) luecken.push(`${q.paletten_gezaehlt - q.paletten_mit_datum} gezählte Paletten ohne Datum`)
    if (q.ausschuss_messungen - q.ausschuss_gewogen > 0) luecken.push(`${q.ausschuss_messungen - q.ausschuss_gewogen} von ${q.ausschuss_messungen} Ausschuss-Mengen geschätzt statt gewogen`)
    if (q.sortierlaeufe - q.sortierlaeufe_zugeordnet > 0) luecken.push(`${q.sortierlaeufe - q.sortierlaeufe_zugeordnet} Sortier-CSVs keiner Arbeit zugeordnet`)
  }
  const verlauf = daten.saisonverlauf
  const tempo = tempoJeTaetigkeit(daten.durchsatz)

  return (
    <>
      <Reiterkopf titel="Überblick" zweck="Wie viel verliere ich, woran — und was tue ich als nächstes?"
                  stand={daten.stand} neuRechnen={() => void neuRechnen()} />

      <Karte>
        <div className="spalten">
          <Kennzahl titel="Eingang" wert={tonnen(eingang)} unter="Netto ab Wareneingang" />
          <Kennzahl titel={unbekannt.length ? 'Lagerverlust mindestens' : 'Lagerverlust'} wert={tonnen(verlustGesamt)}
                    unter={prozent(eingang > 0 ? verlustGesamt / eingang : null)} />
          <Kennzahl titel="Hauptursache" wert={haupt?.strom ?? '—'}
                    unter={haupt ? `${prozent(verlustGesamt > 0 ? haupt.mittel / verlustGesamt : null)} des Verlusts` : ''} />
          {daten.saison && <Kennzahl titel="Noch im Haus" wert={tonnen(daten.saison.restbestand_modell_kg)}
                                     unter={`davon ${tonnen(daten.saison.wartet_kg)} wartet aufs Waschen`} />}
          {daten.saison && <Kennzahl titel="Ausgeliefert" wert={tonnen(daten.saison.ausgang_kg)}
                                     unter={daten.saison.n_lieferungen ? `${daten.saison.n_lieferungen} Lieferungen` : 'noch keine Lieferung erfasst'} />}
        </div>
        {feld?.bekannt && feld.mittel > 0 && (
          <p className="leise" style={{ margin: '.6rem 0 0' }}>
            Dazu <strong>{tonnen(feld.mittel)}</strong> nicht lagerbedingt — Erde, Hagelnarben, Schnittfehler vom Feld. Physisch weg, aber kein Lagerverlust.
          </p>
        )}
        {unbekannt.length > 0 && (
          <Hinweis art="warnung"><strong>Nicht gemessen: {unbekannt.map(s => s.strom).join(', ')}.</strong> Der Strom ist unbekannt — nicht null — und fehlt in „mindestens" und im Bild. Unter <Link to="/messungen">Messungen</Link> steht, welche Messung ihn liefert.</Hinweis>
        )}
      </Karte>

      <Karte titel="Wo bleibt die Masse?">
        <Kaskadenbild eingang={eingang} verkaufsfaehig={verkaufsfaehig} stroeme={kaskade} />
        <p className="leise" style={{ margin: '.5rem 0 0' }}>Jeder Strom mit seinem Bereich als hellem Streifen; schraffiert ist hochgerechnet. Die Rechenwege stehen unter <Link to="/ursachen">Ursachen</Link>.</p>
      </Karte>

      <Karte titel="Was jetzt zu tun ist">
        {luecken.length > 0 ? (
          <>
            <p className="leise">Erfassung, die der Auswertung fehlt — je Zeile eine Absprache aus der Halle:</p>
            <ul style={{ margin: '0 0 .5rem', paddingLeft: '1.2rem' }}>{luecken.map(l => <li key={l}>{l}</li>)}</ul>
            <p className="leise" style={{ margin: 0 }}>Einzelheiten unter <Link to="/messungen">Messungen</Link>.</p>
          </>
        ) : <p className="leise" style={{ margin: 0 }}>Die Erfassung ist vollständig — alle Absprachen werden eingehalten.</p>}
      </Karte>
      <NaechsteChargen zeilen={daten.naechste} />
      <Auffaelligkeiten befunde={daten.befunde} kurz />

      {tempo.length > 0 && (
        <Karte titel="Arbeit und Tempo" aktion={<Link to="/betrieb/arbeiten">jede Arbeit</Link>}>
          <p className="leise">Je Tätigkeit: wie viele Arbeiten, wie lange sie dauerten, wie viel Masse je Stunde und je Person und Stunde durchging — aus Start und Ende jeder abgeschlossenen Arbeit und der Masse, die sie bewegt hat. Arbeiten ohne bekannte Masse zählen bei der Dauer, nicht beim Tempo.</p>
          <div className="rollbar"><table>
            <thead><tr><th>Tätigkeit</th><th className="zahl">Arbeiten</th><th className="zahl">Stunden</th><th className="zahl">Dauer (Median)</th><th className="zahl">Masse</th><th className="zahl">kg je Stunde</th><th className="zahl">kg je Person und Stunde</th></tr></thead>
            <tbody>{tempo.map(z => (
              <tr key={z.name}>
                <td>{z.zeichen} {z.name}</td>
                <td className="zahl">{z.n}</td>
                <td className="zahl">{z.stunden.toFixed(1)} h</td>
                <td className="zahl">{z.median.toFixed(1)} h</td>
                <td className="zahl">{z.masse > 0 ? kg(z.masse, 0) : <span className="leise">—</span>}</td>
                <td className="zahl">{z.kgProH !== null ? <strong>{zahl(z.kgProH)}</strong> : <span className="leise">—</span>}</td>
                <td className="zahl">{z.kgProPersonH !== null ? zahl(z.kgProPersonH) : <span className="leise">—</span>}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </Karte>
      )}

      {verlauf.length > 1 && (
        <Karte titel="Die Saison im Verlauf">
          <p className="leise">Was kumuliert hereinkam und was hinausging. Der Abstand ist, was im Haus ist — vor Abzug des Verlusts, den das Modell darunter schätzt.</p>
          <Diagramm
            reihen={[
              { name: 'Eingang kumuliert', farbe: 'var(--strom-verdunstung)', linie: true,
                punkte: verlauf.map(w => ({ x: Date.parse(w.woche) / TAG, y: w.eingang_kumuliert_kg })) },
              { name: 'Ausgang kumuliert', farbe: 'var(--strom-rest)', linie: true,
                punkte: verlauf.map(w => ({ x: Date.parse(w.woche) / TAG, y: w.ausgang_kumuliert_kg,
                  text: w.vorlauf_kg > 0 ? `davon ${tonnen(w.vorlauf_kg)} vor dem Erfassungsbeginn` : undefined })) },
            ]}
            xFormat={d => datum(new Date(d * TAG)).slice(0, 5)} yFormat={y => tonnen(y)} xTitel="Woche" yTitel="Tonnen" />
        </Karte>
      )}

      {daten.saison && <Bilanz bilanz={daten.saison} />}

      <Karte titel="Ursachen, rangiert" aktion={<Link to="/ursachen">Rechenwege</Link>}>
        <p className="leise">Voller Balken = beobachtet, schraffiert = hochgerechnet für Ware im Lager. Der Strich ist der Unsicherheitsbereich.</p>
        <Stromliste verluste={verluste} maximum={maximum} />
        {duenn.length > 0 && (
          <Hinweis art="warnung"><strong>Diese Zahlen tragen noch nicht:</strong> {duenn.map(v => v.strom).join(', ')} — weniger als drei Stichproben. Die Rangfolge kann sich noch drehen.</Hinweis>
        )}
      </Karte>
    </>
  )
}

interface Tempo { name: string; zeichen: string; n: number; stunden: number; median: number; masse: number; kgProH: number | null; kgProPersonH: number | null }

/** Dauer und Durchsatz je Tätigkeit — Median statt Mittel, damit eine
 *  vergessene, über Nacht offen gebliebene Arbeit den Wert nicht verzerrt. */
function tempoJeTaetigkeit(zeilen: Durchsatz[]): Tempo[] {
  const gruppen = new Map<string, Durchsatz[]>()
  for (const d of zeilen) {
    const k = `${d.weg}|${d.station}|${d.ist_fax}`
    gruppen.set(k, [...(gruppen.get(k) ?? []), d])
  }
  const median = (xs: number[]) => { const s = [...xs].sort((a, b) => a - b); return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : 0 }
  return [...gruppen.entries()].map(([, ds]) => {
    const d0 = ds[0]
    const ta = taetigkeitVon(d0.weg as 'maschine' | 'hand', d0.station as 'sortieren' | 'waschen' | 'waschen_sortieren', d0.ist_fax)
    const mitMasse = ds.filter(d => d.masse_kg !== null && d.dauer_h >= 0.25)
    const stundenMitMasse = mitMasse.reduce((a, d) => a + d.dauer_h, 0)
    const personStunden = mitMasse.reduce((a, d) => a + d.dauer_h * Math.max(d.n_teilnehmer, 1), 0)
    const masse = mitMasse.reduce((a, d) => a + (d.masse_kg ?? 0), 0)
    return {
      name: ta ? WOERTERBUCH.de[ta.text] : d0.station, zeichen: ta?.zeichen ?? '',
      n: ds.length, stunden: ds.reduce((a, d) => a + d.dauer_h, 0), median: median(ds.map(d => d.dauer_h)),
      masse, kgProH: stundenMitMasse > 0 ? masse / stundenMitMasse : null,
      kgProPersonH: personStunden > 0 ? masse / personStunden : null,
    }
  }).sort((a, b) => b.n - a.n)
}
