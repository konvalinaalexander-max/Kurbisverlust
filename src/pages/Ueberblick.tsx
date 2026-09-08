import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import DemoDaten from '../components/DemoDaten'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Balken, Hinweis, Karte, Kennzahl, Lade } from '../components/Bausteine'
import { Diagramm } from '../components/Diagramm'
import { Stapelbalken, Stapellegende, type Stapelzeile } from '../components/Stapelbalken'
import { STROMFARBE, alterSpanne, kaliberJeSorte, stroemeSummieren, useAuswertung, useRanking, type Auswertung, type Bestand, type LieferungKurz } from '../auswertung/daten'
import { Probleme, Reiterkopf } from '../auswertung/Karten'
import type { Hochrechnung } from '../lib/typen'

const TAG = 86400000
type Gruppe = 'gesamt' | 'sorte' | 'schlag' | 'charge'
const GRUPPEN: [Gruppe, string][] = [['gesamt', 'Gesamt'], ['sorte', 'je Sorte'], ['schlag', 'je Schlag'], ['charge', 'je Charge']]
/** Die Ursachen in fester Reihenfolge — dieselbe Farbe wie überall (index.css). */
const URSACHEN = ['Schimmel/Fäulnis', 'Verdunstung', 'Faul beim Abpacken (Fax)', 'Nicht lagerbedingt', 'Zu klein (Tierfutter)', 'Nebenkanal zu gross']
const PHYSISCH = new Set(['verlust', 'feld'])

/**
 * Überblick: vier Dinge, die der Betriebsleiter sicher wissen kann, und wie
 * er sie sehen will. Zwei Zahlen sind gemessen (Eingang ab Erntejournal,
 * Ausgang ab Lieferschein), zwei sind Modell (Verlust, Bestand) — und das
 * steht an jeder Zahl. Keine Vorhersagen, keine Ratschläge: was nicht
 * gewusst werden kann, steht hier nicht.
 */
export default function Ueberblick() {
  const { daten, laedt, fehler, neuRechnen } = useAuswertung()
  const ranking = useRanking('', '', '', daten?.stand ?? null)
  const stroeme = useMemo(() => daten ? stroemeSummieren(daten.hochrechnung, ranking) : [], [daten, ranking])
  const [gruppe, setGruppe] = useState<Gruppe>('gesamt')
  const [masstab, setMasstab] = useState<'kg' | 'prozent'>('kg')
  const navigate = useNavigate()

  const bild = useMemo(() => daten ? chargenbild(daten) : null, [daten])

  if (laedt && !daten) return <Lade text="Auswertung wird gerechnet …" />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten || !bild) return null
  if (daten.hochrechnung.length === 0) {
    return (
      <>
        <Reiterkopf titel="Überblick" zweck="Was kam herein, was ging hinaus, was ist verloren — und woran." stand={daten.stand} />
      <Probleme liste={daten.probleme} />
        <Hinweis>Noch keine auswertbaren Daten. Dafür braucht es mindestens Eingangspaletten mit hinterlegter Tara — siehe Betrieb → Stammdaten.</Hinweis>
        <DemoDaten kompakt nachAenderung={() => void neuRechnen()} />
      </>
    )
  }

  const { chargen, ohneCharge } = bild
  const eingang = chargen.reduce((s, c) => s + c.eingang, 0)
  const paletten = chargen.reduce((s, c) => s + c.paletten, 0)
  const verkauf = chargen.reduce((s, c) => s + c.verkauf, 0) + ohneCharge.reduce((s, l) => s + l.kg, 0)
  const nLieferungen = daten.lieferungen.filter(l => l.buch === 'verkauf').length
  const physisch = chargen.reduce((s, c) => s + c.physisch, 0)
  const kanal = chargen.reduce((s, c) => s + c.kanal, 0)
  const unbekannt = stroeme.filter(s => !s.bekannt && (PHYSISCH.has(s.buch) || s.buch === 'marge')).map(s => s.strom)
  const imHaus = nLieferungen > 0 ? Math.max(eingang - verkauf - physisch - kanal, 0) : null
  const haupt = [...stroeme].filter(s => s.bekannt && PHYSISCH.has(s.buch)).sort((a, b) => b.mittel - a.mittel)[0]
  const kaliber = kaliberJeSorte(daten.kaliber)
  const verlauf = daten.saisonverlauf

  const zeilen: Stapelzeile[] = gruppe === 'gesamt' ? [] : gruppenbild(chargen, gruppe).map(g => ({
    name: g.name, bezug: g.eingang,
    untertitel: gruppe === 'charge' ? `${g.sorte} · ${g.schlag}` : `${g.nChargen} Chargen · ${tonnen(g.eingang)} Eingang`,
    teile: URSACHEN.map(u => ({ name: u, kg: g.weg.get(u) ?? 0, farbe: STROMFARBE[u] ?? 'var(--text-leise)' })),
    ziel: gruppe === 'charge' ? `/chargen?charge=${g.name}` : `/ursachen?${gruppe}=${encodeURIComponent(g.name)}`,
  }))
  const bestand = gruppe === 'gesamt' ? [] : gruppenbild(chargen, gruppe)
  const maximumGesamt = Math.max(...stroeme.filter(s => s.bekannt).map(s => Math.max(s.mittel, s.oben)), 1)

  return (
    <>
      <Reiterkopf titel="Überblick" zweck="Was kam herein, was ging hinaus, was ist verloren — und woran."
                  stand={daten.stand} neuRechnen={() => void neuRechnen()} />

      {/* 1. Vier Zahlen: zwei gemessen, zwei Modell */}
      <Karte>
        <div className="spalten">
          <Kennzahl titel="Eingang" wert={tonnen(eingang)} unter={`${zahl(paletten)} Paletten ab Erntejournal · gemessen`} />
          <Kennzahl titel="Ausgeliefert" wert={nLieferungen > 0 ? tonnen(verkauf) : '—'}
                    unter={nLieferungen > 0
                      ? `${zahl(nLieferungen)} Lieferungen ab Lieferschein · gemessen`
                      : <>noch kein Warenausgang eingelesen — <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link></>} />
          <Kennzahl titel="Physisch verloren" wert={tonnen(physisch)}
                    unter={<>{prozent(eingang > 0 ? physisch / eingang : null)} des Eingangs · Modell{haupt ? `, vor allem ${haupt.strom}` : ''}</>} />
          <Kennzahl titel="Noch im Haus" wert={imHaus === null ? '—' : tonnen(imHaus)}
                    unter={imHaus === null ? 'braucht den Warenausgang' : 'Eingang − Ausgeliefert − Verlust − anderer Kanal · Modell'} />
        </div>
        <p className="leise" style={{ margin: '.6rem 0 0' }}>
          <strong>Gemessen</strong> heisst: aus vollständigen Listen — jede Palette im Erntejournal, jede Lieferung auf einem Lieferschein.{' '}
          <strong>Modell</strong> heisst: aus Stichproben hochgerechnet — mit welcher Rate, steht unter <Link to="/ursachen">Ursachen</Link>.
          {' '}Dazu {tonnen(kanal)} in einen anderen Kanal (zu klein an die Tiere, zu gross in den Nebenkanal) — kein Verlust, aber nicht mehr im Haus.
        </p>
        {unbekannt.length > 0 && (
          <Hinweis art="warnung"><strong>Nicht gemessen: {unbekannt.join(', ')}.</strong> Diese Ursache ist unbekannt — nicht null — und fehlt in allen Summen. Unter <Link to="/messungen">Messungen</Link> steht, welche Messung sie liefert.</Hinweis>
        )}
      </Karte>

      {/* 2. Hauptursachen, gruppiert nach Wahl */}
      <Karte titel="Woran geht die Ware verloren?">
        <div className="reihe" style={{ gap: '.4rem', flexWrap: 'wrap', marginBottom: '.6rem' }}>
               <div className="umschalter" role="tablist" style={{ margin: 0 }}>
                 {GRUPPEN.map(([g, name]) => (
                   <button key={g} role="tab" aria-selected={gruppe === g} className={gruppe === g ? 'aktiv' : ''} onClick={() => setGruppe(g)}>{name}</button>
                 ))}
               </div>
               {gruppe !== 'gesamt' && (
                 <div className="umschalter" role="tablist" style={{ margin: 0 }}>
                   <button role="tab" aria-selected={masstab === 'kg'} className={masstab === 'kg' ? 'aktiv' : ''} onClick={() => setMasstab('kg')}>Tonnen</button>
                   <button role="tab" aria-selected={masstab === 'prozent'} className={masstab === 'prozent' ? 'aktiv' : ''} onClick={() => setMasstab('prozent')}>Anteil</button>
                 </div>
               )}
        </div>
        {gruppe === 'gesamt' ? (
          <>
            <p className="leise">Jede Ursache mit ihrem Bereich (Strich): so weit trägt die Messung. Voll ist beobachtet, schraffiert für die Ware im Lager gerechnet.</p>
            {URSACHEN.map(u => stroeme.find(s => s.strom === u)).filter((s): s is NonNullable<typeof s> => !!s).map(v => (
              <div key={v.strom} className="balken-zeile">
                <div className="reihe">
                  <span aria-hidden="true" style={{ width: 10, height: 10, borderRadius: 2, background: STROMFARBE[v.strom], display: 'inline-block' }} />
                  <strong>{v.strom}</strong>
                  <span className="leise">{v.buch === 'marge' ? 'anderer Kanal' : v.buch === 'feld' ? 'vom Feld' : 'Lagerverlust'}</span>
                  <span style={{ marginLeft: 'auto' }}>{v.bekannt ? <>{tonnen(v.mittel)} <span className="leise">· {prozent(eingang > 0 ? v.mittel / eingang : null)}</span></> : <span className="leise">nicht gemessen</span>}</span>
                </div>
                <Balken wert={v.bekannt ? v.mittel : null} unten={v.unten} oben={v.oben} maximum={maximumGesamt} beobachtet={v.beobachtet} />
              </div>
            ))}
          </>
        ) : (
          <>
            <p className="leise">
              {masstab === 'kg' ? 'Balkenlänge: Tonnen, die diese Gruppe verliert oder abzweigt.' : 'Balkenlänge: Anteil am Eingang der Gruppe — so sieht man, wer anteilig am meisten verliert, nicht wer am grössten ist.'}
              {' '}Ein Klick öffnet die Gruppe.
            </p>
            <Stapelbalken zeilen={zeilen} masstab={masstab} oeffnen={z => z.ziel && navigate(z.ziel)} />
            <Stapellegende teile={URSACHEN.map(u => ({ name: u, farbe: STROMFARBE[u] ?? '' }))} />
          </>
        )}
      </Karte>

      {/* 3. Noch im Haus, gruppiert nach derselben Wahl */}
      <Karte titel="Was ist noch im Haus?">
        <p className="leise">
          Rechnung je Charge: Eingang (gemessen) minus Ausgeliefert (gemessen) minus Verlust und anderer Kanal (Modell).
          Ausgeliefert ist nur, was auf einem Lieferschein steht — ob die Ware davor gewaschen oder sortiert war, weiss die Auswertung nicht, und behauptet es nicht.
          „Liegt seit" ist eine Spanne über die Eingangstage; es gibt kein Zuerst-rein-zuerst-raus.
        </p>
        {nLieferungen === 0 && <Hinweis art="info">Ohne eingelesenen Warenausgang lässt sich der Bestand nicht beziffern — nur der Eingang und der gerechnete Verlust.</Hinweis>}
        <div className="rollbar"><table>
          <thead><tr>
            <th>{gruppe === 'gesamt' ? 'Sorte' : gruppe === 'sorte' ? 'Sorte' : gruppe === 'schlag' ? 'Schlag' : 'Charge'}</th>
            <th className="zahl">Eingang</th><th className="zahl">Ausgeliefert</th>
            <th className="zahl">Verlust (Modell)</th><th className="zahl">Anderer Kanal (Modell)</th>
            <th className="zahl">Noch im Haus</th><th className="zahl">Liegt seit</th>
          </tr></thead>
          <tbody>
            {(gruppe === 'gesamt' ? gruppenbild(chargen, 'sorte') : bestand)
              .map(g => ({ ...g, rest: nLieferungen > 0 ? Math.max(g.eingang - g.verkauf - g.physisch - g.kanal, 0) : null }))
              .sort((a, b) => (b.rest ?? b.eingang) - (a.rest ?? a.eingang))
              .map(g => (
                <tr key={g.name}>
                  <td>{gruppe === 'charge' ? <Link to={`/chargen?charge=${g.name}`}>{g.name}</Link> : g.name}{gruppe === 'charge' && <span className="leise"> · {g.sorte}</span>}</td>
                  <td className="zahl">{kg(g.eingang, 0)}</td>
                  <td className="zahl">{nLieferungen > 0 ? kg(g.verkauf, 0) : <span className="leise">—</span>}</td>
                  <td className="zahl">{kg(g.physisch, 0)}</td>
                  <td className="zahl">{kg(g.kanal, 0)}</td>
                  <td className="zahl"><strong>{g.rest === null ? '—' : kg(g.rest, 0)}</strong></td>
                  <td className="zahl">{g.alterVon !== null && g.alterBis !== null ? alterSpanne(g.alterVon, g.alterBis, null) : <span className="leise">—</span>}</td>
                </tr>
              ))}
            {ohneCharge.length > 0 && gruppe !== 'sorte' && gruppe !== 'gesamt' && (
              <tr><td className="leise">ohne Chargenbezug</td><td className="zahl">—</td><td className="zahl">{kg(ohneCharge.reduce((s, l) => s + l.kg, 0), 0)}</td><td className="zahl">—</td><td className="zahl">—</td><td className="zahl">—</td><td className="zahl">—</td></tr>
            )}
          </tbody>
        </table></div>
        {ohneCharge.length > 0 && (
          <p className="leise" style={{ margin: '.4rem 0 0' }}>
            {tonnen(ohneCharge.reduce((s, l) => s + l.kg, 0))} Lieferungen nennen keine Charge, nur die Sorte — sie zählen bei der Sorte, nicht bei einer Charge.
          </p>
        )}
      </Karte>

      {/* 4. Kaliber je Sorte — aus der Sortier-CSV, jeder Kürbis gewogen */}
      {kaliber.length > 0 && (
        <Karte titel="Wie gross sind die Kürbisse?" aktion={<Link to="/ursachen">Gewichtsverteilung</Link>}>
          <p className="leise">
            Aus der Sortier-CSV: jeder Kürbis gewogen, in die Kaliber der Sorte eingeteilt. Bezahlt wird je Stück innerhalb eines Kalibers —
            wer weiss, wo eine Sorte liegt, kann ein engeres Band liefern. Zu klein geht an die Tiere, zu gross in den Nebenkanal.
          </p>
          {kaliber.map(s => (
            <div key={`${s.sorte}|${s.baender}`} style={{ marginBottom: '.8rem' }}>
              <div className="reihe" style={{ fontSize: '.88rem' }}>
                <strong>{s.sorte}</strong>
                {s.mehrere && <span className="leise">Bänder {s.baender}</span>}
                <span className="leise" style={{ marginLeft: 'auto' }}>{zahl(s.n)} Kürbisse · {tonnen(s.kg)}</span>
              </div>
              <div className="kaliber-spur">
                {s.klassen.map((k, i) => (
                  <div key={k.name} className="stapel-teil" title={`${k.name}: ${zahl(k.n)} Kürbisse (${prozent(s.n > 0 ? k.n / s.n : null)})`}
                       style={{ flex: k.n, background: k.klasse === 'verlust_klein' ? 'var(--strom-ausschuss)' : k.klasse === 'nebenkanal' ? 'var(--strom-nebenkanal)' : 'var(--kuerbis)',
                                opacity: k.klasse === 'kaliber' ? 0.55 + 0.45 * ((i) / Math.max(s.klassen.length - 1, 1)) : 1 }} />
                ))}
              </div>
              <div className="reihe" style={{ fontSize: '.78rem', gap: '.7rem', marginTop: '.2rem' }}>
                {s.klassen.map(k => <span key={k.name} className={k.klasse === 'kaliber' ? '' : 'leise'}>{k.name} {prozent(s.n > 0 ? k.n / s.n : null, 0)}</span>)}
              </div>
            </div>
          ))}
        </Karte>
      )}

      {/* 5. Die Saison im Verlauf — zwei gemessene Kurven */}
      {verlauf.length > 1 && (
        <Karte titel="Die Saison im Verlauf">
          <p className="leise">Was kumuliert hereinkam (Erntejournal) und was hinausging (Lieferscheine). Der Abstand ist, was im Haus ist oder verloren ging — der Verlust steht oben.</p>
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
    </>
  )
}

/* ---------- Die Rechnung je Charge ---------------------------------------- */

interface ChargeBild {
  charge_nr: number; sorte: string; schlag: string
  eingang: number; paletten: number; verkauf: number
  /** Modell: physisch weg (Verdunstung, Schimmel, Fax, Feld) und anderer Kanal (Buch B). */
  physisch: number; kanal: number
  weg: Map<string, number>
  alterVon: number | null; alterBis: number | null
}
interface Gruppenbild {
  name: string; sorte: string; schlag: string; nChargen: number
  eingang: number; verkauf: number; physisch: number; kanal: number
  weg: Map<string, number>; alterVon: number | null; alterBis: number | null
}

/** Je Charge: Eingang und Ausgang gemessen, die Ströme aus der Hochrechnung, das Alter aus der Basis. */
function chargenbild(daten: Auswertung): { chargen: ChargeBild[]; ohneCharge: { sorte: string | null; kg: number }[] } {
  const karte = new Map<number, ChargeBild>()
  const basis = new Map<number, Bestand>(daten.bestand.map(b => [b.charge_nr, b]))
  for (const z of daten.hochrechnung as Hochrechnung[]) {
    let c = karte.get(z.charge_nr)
    if (!c) {
      const b = basis.get(z.charge_nr)
      c = { charge_nr: z.charge_nr, sorte: z.sorte, schlag: z.schlag, eingang: z.eingang_kg, paletten: b?.n_paletten ?? 0,
            verkauf: 0, physisch: 0, kanal: 0, weg: new Map(),
            alterVon: b?.alter_lager_von ?? null, alterBis: b?.alter_lager_bis ?? null }
      karte.set(z.charge_nr, c)
    }
    if (z.kg === null || z.koeff_bekannt === false) continue
    if (PHYSISCH.has(z.buch)) c.physisch += z.kg
    else if (z.buch === 'marge') c.kanal += z.kg
    else continue
    c.weg.set(z.strom, (c.weg.get(z.strom) ?? 0) + z.kg)
  }
  const ohneCharge: { sorte: string | null; kg: number }[] = []
  for (const l of daten.lieferungen as LieferungKurz[]) {
    if (l.buch !== 'verkauf' || l.masse_kg === null) continue
    const c = l.charge_nr === null ? undefined : karte.get(l.charge_nr)
    if (c) c.verkauf += l.masse_kg
    else ohneCharge.push({ sorte: l.sorte, kg: l.masse_kg })
  }
  return { chargen: [...karte.values()], ohneCharge }
}

/** Die Chargen zu Gruppen zusammenfassen — Sorte, Schlag oder die Charge selbst. */
function gruppenbild(chargen: ChargeBild[], nach: 'sorte' | 'schlag' | 'charge'): Gruppenbild[] {
  const map = new Map<string, Gruppenbild>()
  for (const c of chargen) {
    const name = nach === 'charge' ? String(c.charge_nr) : nach === 'sorte' ? c.sorte : c.schlag
    let g = map.get(name)
    if (!g) { g = { name, sorte: c.sorte, schlag: c.schlag, nChargen: 0, eingang: 0, verkauf: 0, physisch: 0, kanal: 0, weg: new Map(), alterVon: null, alterBis: null }; map.set(name, g) }
    g.nChargen++; g.eingang += c.eingang; g.verkauf += c.verkauf; g.physisch += c.physisch; g.kanal += c.kanal
    for (const [k, v] of c.weg) g.weg.set(k, (g.weg.get(k) ?? 0) + v)
    if (c.alterVon !== null) g.alterVon = g.alterVon === null ? c.alterVon : Math.min(g.alterVon, c.alterVon)
    if (c.alterBis !== null) g.alterBis = g.alterBis === null ? c.alterBis : Math.max(g.alterBis, c.alterBis)
  }
  return [...map.values()].sort((a, b) => (b.physisch + b.kanal) - (a.physisch + a.kanal))
}
