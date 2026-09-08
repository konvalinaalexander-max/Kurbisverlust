import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import DemoDaten from '../components/DemoDaten'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Balken, Hinweis, Karte, Kennzahl, Lade } from '../components/Bausteine'
import { Diagramm } from '../components/Diagramm'
import { Stapelbalken, Stapellegende, type Stapelzeile } from '../components/Stapelbalken'
import { PALOX_STROEME, STROMFARBE, alterSpanne, kaliberJeSorte, stroemeSummieren, useAuswertung, useRanking, type Auswertung, type Bestand, type StromSumme } from '../auswertung/daten'
import { Probleme, Reiterkopf } from '../auswertung/Karten'
import type { Hochrechnung } from '../lib/typen'

const TAG = 86400000
type Gruppe = 'gesamt' | 'sorte' | 'schlag' | 'charge'
const GRUPPEN: [Gruppe, string][] = [['gesamt', 'Gesamt'], ['sorte', 'je Sorte'], ['schlag', 'je Schlag'], ['charge', 'je Charge']]
/** Die Ursachen im Überblick, verallgemeinert (0060): Palox fasst alles Faule zusammen. */
const URSACHEN = ['Palox (Faules)', 'Verdunstung', 'Zu klein (Tierfutter)', 'Nebenkanal zu gross']
const ECHT = new Set(['verlust', 'feld'])

/**
 * Überblick: was der Betriebsleiter sicher wissen kann, und wie er es sehen
 * will. Zwei Zahlen sind gemessen (Eingang ab Erntejournal, Ausgeliefert ab
 * Lieferschein), zwei sind Modell (Verlust, noch im Haus) — und das steht an
 * jeder Zahl. „Verlust" heisst hier alles, was nicht als Hauptware verkauft
 * wird: auch zu klein und zu gross. Ob es echter Verlust ist, klärt der
 * Reiter Ursachen — hier zählt, was fehlt.
 *
 * Keine Zahl stammt aus einer gezählten Arbeit: Die Erfassung in der Halle
 * ist punktuell, vollständig sind nur Eingang und Ausgang (0060).
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
        <Reiterkopf titel="Überblick" zweck="Was kam herein, was ging hinaus, was fehlt — und woran." stand={daten.stand} />
        <Probleme liste={daten.probleme} />
        <Hinweis>Noch keine auswertbaren Daten. Dafür braucht es mindestens Eingangspaletten mit hinterlegter Tara — siehe Betrieb → Stammdaten.</Hinweis>
        <DemoDaten kompakt nachAenderung={() => void neuRechnen()} />
      </>
    )
  }

  const chargen = bild
  const eingang = chargen.reduce((s, c) => s + c.eingang, 0)
  const paletten = chargen.reduce((s, c) => s + c.paletten, 0)
  const verkauf = daten.saison?.verkauf_kg ?? chargen.reduce((s, c) => s + c.verkauf, 0)
  const nLieferungen = daten.saison?.n_lieferungen ?? 0
  const echt = chargen.reduce((s, c) => s + c.echt, 0)
  const kanal = chargen.reduce((s, c) => s + c.kanal, 0)
  const verlust = echt + kanal
  const imHaus = chargen.reduce((s, c) => s + c.imHaus, 0)
  const verkaufsfaehig = chargen.reduce((s, c) => s + (c.verkaufsfaehig ?? 0), 0)
  const ueberfuellung = daten.marge.find(m => m.posten.startsWith('Überfüllung'))
  const unbekannt = stroeme.filter(s => !s.bekannt && (ECHT.has(s.buch) || s.buch === 'marge')).map(s => s.strom)
  const kaliber = kaliberJeSorte(daten.kaliber)
  const verlauf = daten.saisonverlauf
  const zusammen = ursachenZusammen(stroeme)
  const haupt = [...zusammen].filter(s => s.bekannt).sort((a, b) => b.mittel - a.mittel)[0]

  const gruppen = gruppe === 'gesamt' ? [] : gruppenbild(chargen, gruppe)
  const zeilen: Stapelzeile[] = gruppen.map(g => ({
    name: g.name, bezug: g.eingang,
    untertitel: gruppe === 'charge' ? `${g.sorte} · ${g.schlag}` : `${g.nChargen} Chargen · ${tonnen(g.eingang)} Eingang`,
    teile: URSACHEN.map(u => ({ name: u, kg: g.weg.get(u) ?? 0, farbe: STROMFARBE[u] ?? 'var(--text-leise)' })),
    ziel: gruppe === 'charge' ? `/ursachen?charge=${g.name}` : `/ursachen?${gruppe}=${encodeURIComponent(g.name)}`,
  }))
  const maximumGesamt = Math.max(...zusammen.filter(s => s.bekannt).map(s => Math.max(s.mittel, s.oben)), 1)

  return (
    <>
      <Reiterkopf titel="Überblick" zweck="Was kam herein, was ging hinaus, was fehlt — und woran."
                  stand={daten.stand} neuRechnen={() => void neuRechnen()} />
      <Probleme liste={daten.probleme} />

      {/* 1. Vier Zahlen: zwei gemessen, zwei Modell */}
      <Karte>
        <div className="spalten">
          <Kennzahl titel="Eingang" wert={tonnen(eingang)} unter={`${zahl(paletten)} Paletten ab Erntejournal · gemessen`} />
          <Kennzahl titel="Ausgeliefert" wert={nLieferungen > 0 ? tonnen(verkauf) : '—'}
                    unter={nLieferungen > 0
                      ? `${zahl(nLieferungen)} Lieferungen ab Lieferschein · gemessen`
                      : <>noch kein Warenausgang eingelesen — <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link></>} />
          <Kennzahl titel="Verlust" wert={tonnen(verlust)}
                    unter={<>{prozent(eingang > 0 ? verlust / eingang : null)} des Eingangs · Modell{haupt ? `, vor allem ${haupt.strom}` : ''}</>} />
          <Kennzahl titel="Noch im Haus" wert={tonnen(imHaus)}
                    unter={nLieferungen > 0 ? `davon heute verkaufsfähig etwa ${tonnen(verkaufsfaehig)} · Modell` : 'ohne Warenausgang: rechnerisch alles · Modell'} />
        </div>
        <p className="leise" style={{ margin: '.6rem 0 0' }}>
          <strong>Gemessen</strong> heisst: aus vollständigen Listen — jede Palette im Erntejournal, jede Lieferung auf einem Lieferschein.{' '}
          <strong>Modell</strong> heisst: aus Stichproben hochgerechnet — mit welcher Rate, steht unter <Link to="/ursachen">Ursachen</Link>.{' '}
          <strong>Verlust</strong> ist hier alles, was nicht als Hauptware verkauft wird: {tonnen(echt)} sind wirklich weg (Palox, Verdunstung),
          {' '}{tonnen(kanal)} gehen in einen anderen Kanal (zu klein an die Tiere, zu gross in den Nebenkanal) — die Ware ist da, nur nicht in der richtigen Grösse.
          {ueberfuellung?.kg != null && <> Dazu {tonnen(ueberfuellung.kg)} verschenkt, weil Kisten über dem Sollgewicht gefüllt wurden.</>}
          {' '}<strong>Noch im Haus</strong> ist der Eingang minus das, was hinter den Lieferungen steckt — nichts davon ist gezählt.
        </p>
        {unbekannt.length > 0 && (
          <Hinweis art="warnung"><strong>Nicht gemessen: {unbekannt.join(', ')}.</strong> Diese Ursache ist unbekannt — nicht null — und fehlt in allen Summen. Unter <Link to="/messungen">Messungen</Link> steht, welche Messung sie liefert.</Hinweis>
        )}
      </Karte>

      {/* 2. Woran, gruppiert nach Wahl */}
      <Karte titel="Woran fehlt die Ware?">
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
            <p className="leise">Jede Ursache mit ihrem Bereich (Strich): so weit trägt die Messung. Voll ist an ausgelieferter Ware gerechnet, schraffiert für die Ware im Haus. Was genau im Palox liegt und wann, steht unter <Link to="/ursachen">Ursachen</Link>.</p>
            {URSACHEN.map(u => zusammen.find(s => s.strom === u)).filter((s): s is StromSumme => !!s).map(v => (
              <div key={v.strom} className="balken-zeile">
                <div className="reihe">
                  <span aria-hidden="true" style={{ width: 10, height: 10, borderRadius: 2, background: STROMFARBE[v.strom], display: 'inline-block' }} />
                  <strong>{v.strom}</strong>
                  <span className="leise">{v.buch === 'marge' ? 'anderer Kanal — kein echter Verlust' : 'echter Verlust'}</span>
                  <span style={{ marginLeft: 'auto' }}>{v.bekannt ? <>{tonnen(v.mittel)} <span className="leise">· {prozent(eingang > 0 ? v.mittel / eingang : null)}</span></> : <span className="leise">nicht gemessen</span>}</span>
                </div>
                <Balken wert={v.bekannt ? v.mittel : null} unten={v.unten} oben={v.oben} maximum={maximumGesamt} beobachtet={v.beobachtet} />
              </div>
            ))}
            {ueberfuellung && (
              <div className="balken-zeile">
                <div className="reihe">
                  <span aria-hidden="true" style={{ width: 10, height: 10, borderRadius: 2, background: 'var(--strom-rest)', display: 'inline-block' }} />
                  <strong>Überfüllung der Kisten</strong>
                  <span className="leise">verschenkt — kein echter Verlust, in „Ausgeliefert" enthalten</span>
                  <span style={{ marginLeft: 'auto' }}>{ueberfuellung.kg != null ? <>{tonnen(ueberfuellung.kg)} <span className="leise">· {prozent(eingang > 0 ? ueberfuellung.kg / eingang : null)}</span></> : <span className="leise">nicht gemessen</span>}</span>
                </div>
                <Balken wert={ueberfuellung.kg} unten={ueberfuellung.kg_unten} oben={ueberfuellung.kg_oben} maximum={maximumGesamt} beobachtet={ueberfuellung.kg} />
              </div>
            )}
          </>
        ) : (
          <>
            <p className="leise">
              {masstab === 'kg' ? 'Balkenlänge: Tonnen, die dieser Gruppe fehlen.' : 'Balkenlänge: Anteil am Eingang der Gruppe — so sieht man, wem anteilig am meisten fehlt, nicht wer am grössten ist.'}
              {' '}Ein Klick öffnet die Ursachen der Gruppe.
            </p>
            <Stapelbalken zeilen={zeilen} masstab={masstab} oeffnen={z => z.ziel && navigate(z.ziel)} />
            <Stapellegende teile={URSACHEN.map(u => ({ name: u, farbe: STROMFARBE[u] ?? '' }))} />
          </>
        )}
      </Karte>

      {/* 3. Noch im Haus, gruppiert nach derselben Wahl */}
      <Karte titel="Was ist noch im Haus?">
        <p className="leise">
          Je Charge: Eingang (gemessen) minus die Eingangsmasse hinter den Lieferungen (gemessen, über den verkaufsfähigen Anteil zurückgerechnet).
          Das ist die Ware in Eingangskilo; „heute verkaufsfähig" zieht Verdunstung, Faules und Kanal für die Lagerdauer ab (Modell).
          „Liegt seit" ist eine Spanne über die Eingangstage; es gibt kein Zuerst-rein-zuerst-raus, und die App weiss nicht, welche Palette gegangen ist.
        </p>
        {nLieferungen === 0 && <Hinweis art="info">Ohne eingelesenen Warenausgang liegt rechnerisch noch alles im Haus — die Zahl ist dann nur der Eingang.</Hinweis>}
        <div className="rollbar"><table>
          <thead><tr>
            <th>{gruppe === 'gesamt' ? 'Sorte' : gruppe === 'sorte' ? 'Sorte' : gruppe === 'schlag' ? 'Schlag' : 'Charge'}</th>
            <th className="zahl">Eingang</th><th className="zahl">Ausgeliefert</th>
            <th className="zahl">Verlust (Modell)</th>
            <th className="zahl">Noch im Haus</th><th className="zahl">davon verkaufsfähig</th><th className="zahl">Liegt seit</th>
          </tr></thead>
          <tbody>
            {(gruppe === 'gesamt' ? gruppenbild(chargen, 'sorte') : gruppen)
              .slice().sort((a, b) => b.imHaus - a.imHaus)
              .map(g => (
                <tr key={g.name}>
                  <td>{gruppe === 'charge' ? <Link to={`/chargen?charge=${g.name}`}>{g.name}</Link> : g.name}{gruppe === 'charge' && <span className="leise"> · {g.sorte}</span>}</td>
                  <td className="zahl">{kg(g.eingang, 0)}</td>
                  <td className="zahl">{nLieferungen > 0 ? kg(g.verkauf, 0) : <span className="leise">—</span>}</td>
                  <td className="zahl">{kg(g.echt + g.kanal, 0)}</td>
                  <td className="zahl"><strong>{kg(g.imHaus, 0)}</strong></td>
                  <td className="zahl">{g.verkaufsfaehig !== null ? kg(g.verkaufsfaehig, 0) : <span className="leise">—</span>}</td>
                  <td className="zahl">{g.imHaus > 0 && g.alterVon !== null && g.alterBis !== null ? alterSpanne(g.alterVon, g.alterBis, null) : <span className="leise">—</span>}</td>
                </tr>
              ))}
          </tbody>
        </table></div>
        {(daten.saison?.ueberzaehlung_kg ?? 0) > 0 && (
          <p className="leise" style={{ margin: '.4rem 0 0' }}>
            Bei einigen Chargen steckt hinter den Lieferungen mehr Ware, als je eingelagert wurde ({tonnen(daten.saison?.ueberzaehlung_kg)}) — dort fehlt meist Wareneingang. Sie stehen mit 0 im Haus.
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

      {/* 5. Die Saison im Verlauf — zwei gemessene Kurven und ihr Abstand */}
      {verlauf.length > 1 && (
        <Karte titel="Die Saison im Verlauf">
          <p className="leise">Was kumuliert hereinkam (Erntejournal) und was hinausging (Lieferscheine). Der Abstand ist, was im Haus ist oder fehlt — der Verlust selbst ist modelliert, nicht datiert, und steht oben.</p>
          <Diagramm
            reihen={[
              { name: 'Eingang kumuliert', farbe: 'var(--strom-verdunstung)', linie: true,
                punkte: verlauf.map(w => ({ x: Date.parse(w.woche) / TAG, y: w.eingang_kumuliert_kg })) },
              { name: 'Ausgang kumuliert', farbe: 'var(--strom-rest)', linie: true,
                punkte: verlauf.map(w => ({ x: Date.parse(w.woche) / TAG, y: w.ausgang_kumuliert_kg,
                  text: w.vorlauf_kg > 0 ? `davon ${tonnen(w.vorlauf_kg)} vor dem Erfassungsbeginn` : undefined })) },
              { name: 'Im Haus oder fehlend (Abstand)', farbe: 'var(--strom-schimmel)', linie: true, marker: false, gestrichelt: true,
                punkte: verlauf.map(w => ({ x: Date.parse(w.woche) / TAG, y: Math.max(w.eingang_kumuliert_kg - w.ausgang_kumuliert_kg, 0) })) },
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
  eingang: number; paletten: number; verkauf: number; imHaus: number; verkaufsfaehig: number | null
  /** Modell: echt weg (Palox, Verdunstung) und anderer Kanal (zu klein, zu gross). */
  echt: number; kanal: number
  weg: Map<string, number>
  alterVon: number | null; alterBis: number | null
}
interface Gruppenbild {
  name: string; sorte: string; schlag: string; nChargen: number
  eingang: number; verkauf: number; echt: number; kanal: number; imHaus: number; verkaufsfaehig: number | null
  weg: Map<string, number>; alterVon: number | null; alterBis: number | null
}

/** Die Ströme zusammengefasst, wie der Überblick sie zeigt: alles Faule als „Palox". */
function ursachenZusammen(stroeme: StromSumme[]): StromSumme[] {
  const palox = stroeme.filter(s => PALOX_STROEME.includes(s.strom))
  const rest = stroeme.filter(s => !PALOX_STROEME.includes(s.strom))
  if (palox.length === 0) return rest
  const summe = (f: (s: StromSumme) => number) => palox.reduce((a, s) => a + f(s), 0)
  // Unbekannt ist der Palox nur, wenn der Hauptstrom (Schimmel im Lager) unbekannt ist —
  // ein noch nie gemessener Fax-Anteil macht das Faule im Lager nicht unbekannt.
  const bekannt = palox.filter(s => s.bekannt)
  const zusammen: StromSumme = {
    strom: 'Palox (Faules)', buch: 'verlust',
    mittel: bekannt.reduce((a, s) => a + s.mittel, 0), unten: bekannt.reduce((a, s) => a + s.unten, 0), oben: bekannt.reduce((a, s) => a + s.oben, 0),
    beobachtet: bekannt.reduce((a, s) => a + s.beobachtet, 0), projiziert: bekannt.reduce((a, s) => a + s.projiziert, 0),
    extrapoliert: bekannt.reduce((a, s) => a + s.extrapoliert, 0), basis: summe(s => s.basis),
    koeffN: bekannt.reduce<number | null>((a, s) => s.koeffN === null ? a : a === null ? s.koeffN : Math.min(a, s.koeffN), null),
    koeffBasis: bekannt[0]?.koeffBasis ?? null, formel: 'Schimmel im Lager + nicht Lagerbedingtes + Faules beim Abpacken',
    bereichBekannt: bekannt.every(s => s.bereichBekannt), bekannt: palox.some(s => s.strom === 'Schimmel/Fäulnis' && s.bekannt),
  }
  return [zusammen, ...rest]
}

/** Je Charge: Eingang, geliefert, im Haus aus der Basis (0060); die Ströme aus der Hochrechnung. */
function chargenbild(daten: Auswertung): ChargeBild[] {
  const karte = new Map<number, ChargeBild>()
  const basis = new Map<number, Bestand>(daten.bestand.map(b => [b.charge_nr, b]))
  for (const z of daten.hochrechnung as Hochrechnung[]) {
    let c = karte.get(z.charge_nr)
    if (!c) {
      const b = basis.get(z.charge_nr)
      c = { charge_nr: z.charge_nr, sorte: z.sorte, schlag: z.schlag, eingang: z.eingang_kg, paletten: b?.n_paletten ?? 0,
            verkauf: b?.geliefert_kg ?? 0, imHaus: b?.lager_kg ?? z.eingang_kg, verkaufsfaehig: b?.verkaufsfaehig_lager_kg ?? null,
            echt: 0, kanal: 0, weg: new Map(),
            alterVon: b?.alter_lager_von ?? null, alterBis: b?.alter_lager_bis ?? null }
      karte.set(z.charge_nr, c)
    }
    if (z.kg === null || z.koeff_bekannt === false) continue
    if (ECHT.has(z.buch)) c.echt += z.kg
    else if (z.buch === 'marge') c.kanal += z.kg
    else continue
    const name = PALOX_STROEME.includes(z.strom) ? 'Palox (Faules)' : z.strom
    c.weg.set(name, (c.weg.get(name) ?? 0) + z.kg)
  }
  return [...karte.values()]
}

/** Die Chargen zu Gruppen zusammenfassen — Sorte, Schlag oder die Charge selbst. */
function gruppenbild(chargen: ChargeBild[], nach: 'sorte' | 'schlag' | 'charge'): Gruppenbild[] {
  const map = new Map<string, Gruppenbild>()
  for (const c of chargen) {
    const name = nach === 'charge' ? String(c.charge_nr) : nach === 'sorte' ? c.sorte : c.schlag
    let g = map.get(name)
    if (!g) { g = { name, sorte: c.sorte, schlag: c.schlag, nChargen: 0, eingang: 0, verkauf: 0, echt: 0, kanal: 0, imHaus: 0, verkaufsfaehig: null, weg: new Map(), alterVon: null, alterBis: null }; map.set(name, g) }
    g.nChargen++; g.eingang += c.eingang; g.verkauf += c.verkauf; g.echt += c.echt; g.kanal += c.kanal; g.imHaus += c.imHaus
    if (c.verkaufsfaehig !== null) g.verkaufsfaehig = (g.verkaufsfaehig ?? 0) + c.verkaufsfaehig
    for (const [k, v] of c.weg) g.weg.set(k, (g.weg.get(k) ?? 0) + v)
    if (c.imHaus > 0 && c.alterVon !== null) g.alterVon = g.alterVon === null ? c.alterVon : Math.min(g.alterVon, c.alterVon)
    if (c.imHaus > 0 && c.alterBis !== null) g.alterBis = g.alterBis === null ? c.alterBis : Math.max(g.alterBis, c.alterBis)
  }
  return [...map.values()].sort((a, b) => (b.echt + b.kanal) - (a.echt + a.kanal))
}
