import { useEffect, useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useBetriebsmodus } from '../lib/betriebsmodus'
import { imDemoModus } from '../lib/supabase'
import DemoDaten from '../components/DemoDaten'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Erklaerung, Herkunft, Hinweis, Karte, Kennzahl, Leer, Marke, Segmente } from '../components/Bausteine'
import { Glocke, Linien, tonnenAchse, type Reihe } from '../components/Diagramm'
import { kaliberGlockeBei, lagerKaliberBei, prognoseBei, useAuswertung, useStichtag, wohinVon,
         type Auswertung, type Bestand, type KaliberGlocke, type LagerKaliber } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { JournalAbgleich } from '../betrieb/JournalAbgleich'
import { useZaehler } from '../design/bewegung'
import { ZWarnung } from '../components/Zeichen'

const TAG = 86400000
/** Wie weit der Betriebsleiter vorausschauen darf: eine Saison. */
const WOCHEN_MAX = 28
const STUFE_G = 50

/** Der Filter dieser Seite: alles, eine Sorte oder eine Charge — kein Schlag. */
interface Filter { gruppe: 'gesamt' | 'sorte' | 'charge'; schluessel: string }

/** Eine Tonnenzahl, die beim Erscheinen zu ihrem Wert läuft. */
function Tonnen({ kg }: { kg: number | null | undefined }) {
  const w = useZaehler(kg)
  return <>{tonnen(w)}</>
}

/**
 * Lagermanagement — der erste Reiter des Betriebsleiters. Er fragt im
 * Tagesgeschäft dasselbe wie am Saisonende, nur anders herum:
 *
 *   „wieviel kürbis ist gerade im lager - aber halt genau - von welcher
 *    sorte von welcher charge … von dem kaliber von der charge ist noch so
 *    viel da - aber mit dem aktuellen verdampfung ist dann nur noch so viel
 *    von dem kaliber übrig weil gewisse in eine andere kalibergrösse fallen"
 *
 * Vier Zahlen, der Verlauf, die Tabelle mit den Kalibern — heute und in X
 * Wochen —, die Glocke. Jede Zahl über die Zukunft ist dieselbe Kaskade,
 * nur an einem späteren Tag ausgewertet: `lager_kaliber(h)` teilt die
 * verkaufsfähige Masse auf die Bänder auf, sonst nichts.
 */
export default function Lagermanagement() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const modus = useBetriebsmodus()
  const [params, setParams] = useSearchParams()

  const filter: Filter = params.get('charge') ? { gruppe: 'charge', schluessel: params.get('charge')! }
    : params.get('sorte') ? { gruppe: 'sorte', schluessel: params.get('sorte')! }
    : { gruppe: 'gesamt', schluessel: '' }
  const wochen = Math.min(WOCHEN_MAX, Math.max(1, Number(params.get('wochen')) || 4))

  const setzen = (wert: string) => {
    const [g, k] = wert.split('|')
    const neu = new URLSearchParams(params)
    neu.delete('sorte'); neu.delete('charge')
    if (g && k) neu.set(g, k)
    setParams(neu, { replace: true })
  }
  const setzeWochen = (n: number) => {
    const neu = new URLSearchParams(params)
    neu.set('wochen', String(n))
    setParams(neu, { replace: true })
  }

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const s = daten.saison
  if (!s || daten.bestand.length === 0) {
    return (
      <>
        <Reiterkopf titel="Lagermanagement" zweck={ZWECK} stand={daten.stand} />
        <Probleme liste={daten.probleme} />
        <Hinweis>Noch keine auswertbaren Daten. Dafür braucht es mindestens Eingangspaletten mit hinterlegter Tara — siehe Betrieb → Stammdaten.</Hinweis>
        {/* 0081: Auch im Demo-Modus — dort erklärt die Karte, was der
            Demo-Datenbank noch fehlt, statt zu verschwinden. */}
        {(modus === 'beispiel' || imDemoModus)
          && <DemoDaten kompakt nachAenderung={() => void neuRechnen()} />}
      </>
    )
  }

  return (
    <>
      <Reiterkopf titel="Lagermanagement" zweck={ZWECK}
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt} />
      <JournalAbgleich neuGerechnet={() => void neuRechnen()} />
      <Probleme liste={daten.probleme} />
      {daten.befunde.length > 0 && (
        <div className="hinweis warnung" role="status">
          <span className="hinweis-zeichen"><ZWarnung size={18} /></span>
          <div className="hinweis-text">
            <strong>{daten.befunde.length} Auffälligkeiten</strong> — Messungen, die nicht in die Rechnung eingehen, meist ein Tippfehler.{' '}
            <Link to="/messungen">Ansehen und korrigieren</Link>
          </div>
        </div>
      )}

      <Filterleiste daten={daten} filter={filter} setzen={setzen} />
      <Kennzahlen daten={daten} filter={filter} />
      <Verlauf daten={daten} filter={filter} />
      <ImHaus daten={daten} filter={filter} wochen={wochen} setzeWochen={setzeWochen} />
      <Glockenkarte daten={daten} filter={filter} wochen={wochen} setzeWochen={setzeWochen} />
    </>
  )
}

const ZWECK = 'Was liegt, wovon, in welchem Kaliber — heute und in ein paar Wochen.'

/* ---------- Der Filter: alle, eine Sorte, eine Charge ---------------------- */

function Filterleiste({ daten, filter, setzen }: { daten: Auswertung; filter: Filter; setzen: (w: string) => void }) {
  const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort((a, b) => a.localeCompare(b, 'de'))
  const chargen = [...daten.bestand].sort((a, b) => a.charge_nr - b.charge_nr)
  const imFilter = chargenIm(daten.bestand, filter)
  const name = filter.gruppe === 'gesamt' ? '' : filter.gruppe === 'charge'
    ? `Charge ${filter.schluessel}` : filter.schluessel
  return (
    <div className="filterleiste haftend">
      <label htmlFor="lager-filter">Ansicht</label>
      <select id="lager-filter" value={filter.gruppe === 'gesamt' ? '' : `${filter.gruppe}|${filter.schluessel}`}
              onChange={e => setzen(e.target.value)}>
        <option value="">alle Chargen</option>
        <optgroup label="Sorte">{sorten.map(x => <option key={x} value={`sorte|${x}`}>{x}</option>)}</optgroup>
        <optgroup label="Charge">{chargen.map(c => <option key={c.charge_nr} value={`charge|${c.charge_nr}`}>{c.charge_nr} · {c.sorte}</option>)}</optgroup>
      </select>
      {filter.gruppe !== 'gesamt' && <span className="aktiv-filter">{name}</span>}
      <span>{imFilter.length} {imFilter.length === 1 ? 'Charge' : 'Chargen'} · {imFilter.filter(b => b.lager_kg > 0).length} mit Ware im Haus</span>
      {filter.gruppe !== 'gesamt' && <button type="button" className="werkzeug-knopf" onClick={() => setzen('')}>alle zeigen</button>}
    </div>
  )
}

function chargenIm(bestand: Bestand[], f: Filter): Bestand[] {
  if (f.gruppe === 'charge') return bestand.filter(b => String(b.charge_nr) === f.schluessel)
  if (f.gruppe === 'sorte') return bestand.filter(b => b.sorte === f.schluessel)
  return bestand
}

/* ---------- L1: Vier Zahlen ------------------------------------------------ */

function Kennzahlen({ daten, filter }: { daten: Auswertung; filter: Filter }) {
  const w = wohinVon(daten.wohin, filter.gruppe, filter.schluessel)
  const p0 = prognoseBei(daten.prognose, filter.gruppe, filter.schluessel, 0)
  const chargen = chargenIm(daten.bestand, filter)
  const paletten = chargen.reduce((a, b) => a + b.n_paletten, 0)
  const ohneNetto = chargen.reduce((a, b) => a + (b.n_paletten - b.n_paletten_mit_netto), 0)
  const lieferungen = chargen.reduce((a, b) => a + b.n_lieferungen, 0)
  const anteil = p0?.verkaufsfaehig_anteil ?? null
  // Die liegende Ware, zerlegt: derselbe Balken, den die Kaskade rechnet.
  const teile = p0 ? [
    { name: 'verkaufsfähig', kg: p0.verkaufsfaehig_kg, farbe: 'var(--strom-rest)' },
    { name: 'zu klein / zu gross', kg: p0.kanal_kg, farbe: 'var(--strom-ausschuss)' },
    { name: 'faul', kg: p0.faul_kg + p0.sockel_kg, farbe: 'var(--strom-schimmel)' },
    { name: 'verdunstet', kg: p0.verdunstet_kg, farbe: 'var(--strom-verdunstung)' },
  ] : []
  const summe = teile.reduce((a, t) => a + t.kg, 0)

  return (
    <div className="kennzahl-reihe">
      <Kennzahl titel="Eingang" id="kz-eingang"
                wert={<><Tonnen kg={w?.eingang_kg} />{ohneNetto === 0
                  ? <Herkunft art="gemessen" />
                  : <Herkunft art="gerechnet" text={`${ohneNetto} Paletten ohne Nettogewicht — für sie rechnet der Eingang mit dem Mittel der übrigen`} />}</>}
                unter={<>{zahl(paletten)} Paletten · {w?.n_chargen ?? chargen.length} Chargen · ab Erntejournal</>} />
      <Kennzahl titel="Ausgang" id="kz-ausgang"
                wert={(w?.geliefert_kg ?? 0) > 0 ? <><Tonnen kg={w?.geliefert_kg} /><Herkunft art="gemessen" /></> : '—'}
                unter={(w?.geliefert_kg ?? 0) > 0
                  ? <>{zahl(lieferungen)} Lieferungen ab Lieferschein{(w?.kanal_ausgelagert_kg ?? 0) > 0
                      ? <> · + {tonnen(w?.kanal_ausgelagert_kg)} anderer Kanal (zu klein / zu gross)</> : ''}</>
                  : <>noch kein Warenausgang eingelesen — <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link></>} />
      <Kennzahl titel="Im Lager" ton="kuerbis" id="kz-lager"
                wert={<><Tonnen kg={p0?.lager_kg} /><Herkunft art="gerechnet" /></>}
                unter={<>Eingangsware, die nicht ausgeliefert ist · {chargen.filter(b => b.lager_kg > 0).length} Chargen</>} />
      <Kennzahl titel="Davon verkaufsfähig" ton="gruen" id="kz-verkaufsfaehig"
                wert={<>
                  {anteil === null && <span className="mini-wort">höchstens </span>}
                  <Tonnen kg={p0?.verkaufsfaehig_kg} />
                  {anteil !== null && <span className="neben-zahl"> · {prozent(anteil, 0)}</span>}
                  <Herkunft art="gerechnet" /></>}
                unter={<>
                  <span className="mini-anteile" aria-hidden="true">
                    {teile.filter(t => t.kg > 0).map(t => (
                      <span key={t.name} style={{ width: `${(t.kg / Math.max(summe, 1)) * 100}%`, background: t.farbe }} />
                    ))}
                  </span>
                  {anteil === null
                    ? <>der Anteil ist unbekannt, solange eine Rate nicht gemessen ist</>
                    : <>von dem, was im Lager liegt</>}
                </>} />
    </div>
  )
}

/* ---------- L2: Die Saison im Verlauf --------------------------------------- */

function Verlauf({ daten, filter }: { daten: Auswertung; filter: Filter }) {
  const k = filter.gruppe === 'gesamt' ? '' : filter.schluessel
  const wochen = daten.verlauf.filter(w => w.gruppe === filter.gruppe && w.schluessel === k)
    .sort((a, b) => a.bis.localeCompare(b.bis))
  if (wochen.length < 2) return null
  const x = (d: string) => Date.parse(d) / TAG
  const heute = x(daten.heute)
  const bisHeute = wochen.filter(w => !w.prognose)
  const xErste = x(wochen[0].woche), xLetzte = x(wochen[wochen.length - 1].bis)
  const xVon = Math.min(xErste, 2 * heute - xLetzte)
  const anteil = (w: typeof wochen[number]) => w.lager_kg > 0 ? w.verkaufsfaehig_kg / w.lager_kg : null
  const reihen: Reihe[] = [
    { name: 'Eingang kumuliert', farbe: 'var(--text-leise)', linie: true, marker: false, flaeche: true, ausgeblendet: true,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: w.eingang_kum_kg })) },
    // Runde V: Orange gegen Blau statt Orange gegen Grün — das Paar, das
    // auch bei Rot-Grün-Schwäche zwei Linien bleibt. Der Ausgang ist
    // Umgebung, kein Vergleich, und steht darum in Grau.
    { name: 'Ausgang kumuliert', farbe: 'var(--text-leise)', linie: true, marker: false,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: w.ausgang_kum_kg })) },
    { name: 'Im Lager', farbe: 'var(--kuerbis)', linie: true, marker: false, dick: true, prognoseAb: heute,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.lager_kg })) },
    { name: 'Davon verkaufsfähig', farbe: 'var(--blau)', linie: true, marker: false, dick: true, prognoseAb: heute,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.verkaufsfaehig_kg,
        text: `${prozent(anteil(w), 0)} der liegenden Ware · zu klein/zu gross ${tonnen(w.kanal_kg)}` })) },
  ]
  const name = filter.gruppe === 'gesamt' ? 'alle Chargen' : filter.gruppe === 'charge' ? `Charge ${filter.schluessel}` : filter.schluessel
  return (
    <Karte id="lager-verlauf" titel="Die Saison im Verlauf"
           unter={`Je Woche für ${name}: was hereinkam, was hinausging, was noch liegt — und wie viel davon verkaufsfähig ist.`}>
      <Linien reihen={reihen} heute={{ x: heute, text: `heute, ${datum(daten.heute).slice(0, 6)}`, rechts: 'so ginge es weiter' }}
              xVon={xVon} xBis={xLetzte} hoehe={300}
              xFormat={d => datum(new Date(d * TAG)).slice(0, 5)} yFormat={tonnenAchse}
              xTitel="Woche" yTitel="Tonnen" yEinheit="kg"
              fuss={<span className="leise">ab heute gestrichelt: wenn die liegende Ware liegen bleibt</span>} />
      <Erklaerung>
        <p>Eingang und Ausgang sind <Herkunft art="gemessen" /> und enden heute.
        <strong> Im Lager</strong> ist die Eingangsware, die an diesem Stichtag noch nicht ausgeliefert war — sie fällt, wenn geliefert wird, und steht danach still.
        <strong> Davon verkaufsfähig</strong> ist <Herkunft art="gerechnet" /> und fällt auch dann weiter, wenn nichts geliefert wird: Die liegende Ware altert.</p>
      </Erklaerung>
    </Karte>
  )
}

/* ---------- Die Bänder einer Gruppe ----------------------------------------- */

interface Bandzeile {
  schluessel: string; name: string; unter: string; sorte: string
  lager: number; verkaufsfaehig: number; anteil: number | null
  basis: string; nKuerbis: number | null
  /** Kilo je Kaliber-Index; −1 ist „unter Kaliber". */
  kg: Map<number, number>
  band: Map<number, string>
}

/** Aus den Zeilen von `lager_kaliber(h)` die Zeilen der Tabelle. */
function bandzeilen(zeilen: LagerKaliber[], filter: Filter, bestand: Bestand[]): Bandzeile[] {
  const gruppe = filter.gruppe === 'gesamt' ? 'sorte' : 'charge'
  const chargen = new Map(bestand.map(b => [String(b.charge_nr), b]))
  const map = new Map<string, Bandzeile>()
  for (const z of zeilen) {
    if (z.gruppe !== gruppe) continue
    if (filter.gruppe === 'sorte' && z.sorte !== filter.schluessel) continue
    if (filter.gruppe === 'charge' && z.schluessel !== filter.schluessel) continue
    if (!(z.lager_kg > 0)) continue
    let e = map.get(z.schluessel)
    if (!e) {
      const c = gruppe === 'charge' ? chargen.get(z.schluessel) : undefined
      e = {
        schluessel: z.schluessel,
        name: gruppe === 'charge' ? `Charge ${z.schluessel}` : z.schluessel,
        unter: gruppe === 'charge' ? `${z.sorte}${c ? ` · ${c.schlag}` : ''}` : `${z.n_chargen} ${z.n_chargen === 1 ? 'Charge' : 'Chargen'}`,
        sorte: z.sorte, lager: z.lager_kg, verkaufsfaehig: z.verkaufsfaehig_kg, anteil: z.anteil,
        basis: z.basis, nKuerbis: z.n_kuerbis, kg: new Map(), band: new Map(),
      }
      map.set(z.schluessel, e)
    }
    if (z.kaliber_idx !== null) {
      e.kg.set(z.kaliber_idx, (e.kg.get(z.kaliber_idx) ?? 0) + (z.kg ?? 0))
      if (z.band_von !== null && z.band_bis !== null) e.band.set(z.kaliber_idx, `${z.band_von}–${z.band_bis} g`)
    }
    // Der Anteil am Lager gehört der Zeile, nicht dem Band.
    e.anteil = e.lager > 0 ? e.verkaufsfaehig / e.lager : null
  }
  return [...map.values()].sort((a, b) => b.lager - a.lager)
}

/** Welche Spalten die Tabelle hat: die Bänder, die irgendeine Zeile trägt. */
function bandspalten(zeilen: Bandzeile[]): { idx: number; kopf: string; unter: string }[] {
  const idxe = [...new Set(zeilen.flatMap(z => [...z.kg.keys()]))].sort((a, b) => a - b)
  const mitBand = idxe.filter(i => i >= 0)
  const spalten = mitBand.map(i => {
    const baender = [...new Set(zeilen.map(z => z.band.get(i)).filter(Boolean))] as string[]
    return { idx: i, kopf: baender.length === 1 ? baender[0] : `Kaliber ${i + 1}`, unter: baender.length === 1 ? '' : 'je Sorte eigene Grenzen' }
  })
  // „unter Kaliber" nur, wenn dort etwas steht — sonst eine Spalte aus Nullen.
  if (idxe.includes(-1) && zeilen.some(z => (z.kg.get(-1) ?? 0) > 0.5)) {
    spalten.push({ idx: -1, kopf: 'unter Kaliber', unter: 'geschrumpft' })
  }
  return spalten
}

/* ---------- L3: Was ist noch im Haus? --------------------------------------- */

function ImHaus({ daten, filter, wochen, setzeWochen }: {
  daten: Auswertung; filter: Filter; wochen: number; setzeWochen: (n: number) => void
}) {
  const heute = useStichtag(lagerKaliberBei, 0)
  const spaeter = useStichtag(lagerKaliberBei, 7 * wochen)
  const zeilenHeute = useMemo(() => bandzeilen(heute.zeilen, filter, daten.bestand), [heute.zeilen, filter, daten.bestand])
  const zeilenSpaeter = useMemo(() => bandzeilen(spaeter.zeilen, filter, daten.bestand), [spaeter.zeilen, filter, daten.bestand])
  const spalten = bandspalten([...zeilenHeute, ...zeilenSpaeter])
  const spaeterJe = new Map(zeilenSpaeter.map(z => [z.schluessel, z]))
  const stichtag = spaeter.zeilen[0]?.datum ?? null

  const summe = (f: (z: Bandzeile) => number) => zeilenHeute.reduce((a, z) => a + f(z), 0)

  return (
    <Karte id="lager-tabelle" titel="Was ist noch im Haus?"
           unter={`Je ${filter.gruppe === 'gesamt' ? 'Sorte' : 'Charge'}: was liegt, und wie viel davon in welchem Kaliber verkaufsfähig ist — heute und in ${wochen} Wochen.`}
           aktion={<WochenFeld id="lager-wochen" wochen={wochen} setzen={setzeWochen} datum={stichtag} />}>
      {heute.fehler && <Hinweis art="warnung">Die Kaliber von heute konnten nicht geladen werden: {heute.fehler}</Hinweis>}
      {spaeter.fehler && <Hinweis art="warnung">Die Spalten „in {wochen} Wochen" konnten nicht geladen werden: {spaeter.fehler}</Hinweis>}
      {zeilenHeute.length === 0 && !heute.laedt
        ? <Leer titel="Nichts im Lager">Sobald wieder Ware liegt, steht hier, in welchem Kaliber sie liegt.</Leer>
        : (
        <div className="rollbar">
          <table className="dicht umbruch lagertabelle">
            <thead>
              <tr>
                {/* Die Herkunftsmarke steht im Kopf, nicht nur in der Erklärung:
                    Eine Zahl in dieser Tabelle liest man über ihre Spalte, und
                    die Spalten sind verschiedener Herkunft — links gerechnet bis
                    heute, rechts über heute hinaus. */}
                <th rowSpan={2} className="haftend">{filter.gruppe === 'gesamt' ? 'Sorte' : 'Charge'}</th>
                <th rowSpan={2} className="zahl">im Lager<Herkunft art="gerechnet" /></th>
                <th colSpan={spalten.length + 1} className="gruppe">verkaufsfähig heute<Herkunft art="gerechnet" /></th>
                <th colSpan={spalten.length + 1} className="gruppe spaeter">verkaufsfähig in {wochen} Wochen{stichtag ? <span className="leise"> · {datum(stichtag).slice(0, 6)}</span> : null}<Herkunft art="prognose" /></th>
              </tr>
              <tr>
                {spalten.map(sp => <th key={`h${sp.idx}`} className="zahl">{sp.kopf}</th>)}
                <th className="zahl">gesamt</th>
                {spalten.map(sp => <th key={`s${sp.idx}`} className="zahl spaeter">{sp.kopf}</th>)}
                <th className="zahl spaeter">gesamt</th>
              </tr>
            </thead>
            <tbody>
              {zeilenHeute.map(z => {
                const sp = spaeterJe.get(z.schluessel)
                return (
                  <tr key={z.schluessel}>
                    <th scope="row" className="haftend">
                      <span className="zeilenname">{z.name}</span>
                      <span className="leise"> {z.unter}</span>
                      {z.basis === 'sorte' && <Marke art="neutral" punkt={false}>aus der Sorte</Marke>}
                    </th>
                    <td className="zahl"><strong>{masse(z.lager)}</strong></td>
                    {spalten.map(s => <Bandzelle key={`h${s.idx}`} zeile={z} idx={s.idx} filter={filter} />)}
                    <td className="zahl summe"><strong>{masse(z.verkaufsfaehig)}</strong>
                      {z.anteil !== null && <span className="leise"> {prozent(z.anteil, 0)}</span>}</td>
                    {spalten.map(s => <Bandzelle key={`s${s.idx}`} zeile={sp} idx={s.idx} filter={filter} laedt={spaeter.laedt} spaeter />)}
                    <td className={`zahl summe spaeter${spaeter.laedt ? ' laedt' : ''}`}>
                      {sp ? <><strong>{masse(sp.verkaufsfaehig)}</strong>{sp.anteil !== null && <span className="leise"> {prozent(sp.anteil, 0)}</span>}</> : '—'}
                    </td>
                  </tr>
                )
              })}
            </tbody>
            {zeilenHeute.length > 1 && (
              <tfoot>
                <tr>
                  <th scope="row" className="haftend">Summe</th>
                  <td className="zahl"><strong>{masse(summe(z => z.lager))}</strong></td>
                  {spalten.map(s => <td key={`fh${s.idx}`} className="zahl"><strong>{masse(summe(z => z.kg.get(s.idx) ?? 0))}</strong></td>)}
                  <td className="zahl summe"><strong>{masse(summe(z => z.verkaufsfaehig))}</strong></td>
                  {spalten.map(s => <td key={`fs${s.idx}`} className="zahl spaeter"><strong>{masse(zeilenSpaeter.reduce((a, z) => a + (z.kg.get(s.idx) ?? 0), 0))}</strong></td>)}
                  <td className="zahl summe spaeter"><strong>{masse(zeilenSpaeter.reduce((a, z) => a + z.verkaufsfaehig, 0))}</strong></td>
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      )}
      <p className="hilfe">
        Die Summe der Bänder ist die verkaufsfähige Masse der Rechnung; die Bänder kommen aus der Sortier-CSV,
        jeder Kürbis um die gemessene Verdunstung geschrumpft — fällt einer unter das kleinste Band, steht er in „unter Kaliber".
      </p>
      <Erklaerung>
        <p><strong>Im Lager</strong> ist Eingangsware, die nicht ausgeliefert ist <Herkunft art="gerechnet" />.
        <strong> Verkaufsfähig</strong> zieht davon ab, was bis heute verdunstet oder verdorben ist und was zu klein oder zu gross war.</p>
        <p>Die Aufteilung auf die Kaliber ist keine zweite Rechnung: Jeder Kürbis der Sortier-CSV wird um die
        gemessene Verdunstung seiner Charge geschrumpft und neu in sein Band gelegt; die Massenanteile der Bänder
        mal der verkaufsfähigen Masse ergeben die Kilo. Über alle Bänder summiert steht wieder genau diese Masse.</p>
        <p>„aus der Sorte" heisst: Diese Charge hat keine eigene Sortier-CSV — sie bekommt die Verteilung aller
        sortierten Kürbisse ihrer Sorte. Fehlt auch die, bleiben die Bänder leer: unbekannt, nicht null.</p>
      </Erklaerung>
    </Karte>
  )
}

/** Masse kurz: Tonnen ab einer Tonne, darunter Kilo. */
const masse = (v: number | null | undefined) =>
  v === null || v === undefined ? '—' : v >= 1000 ? tonnen(v) : kg(v, 0)

function Bandzelle({ zeile, idx, filter, laedt = false, spaeter = false }: {
  zeile: Bandzeile | undefined; idx: number; filter: Filter; laedt?: boolean; spaeter?: boolean
}) {
  const klasse = `zahl${spaeter ? ' spaeter' : ''}${laedt ? ' laedt' : ''}${idx === -1 ? ' unter-kaliber' : ''}`
  if (!zeile) return <td className={klasse}>—</td>
  if (zeile.basis === 'keine') {
    return <td className={klasse} title="keine Sortier-CSV für diese Sorte — die Verteilung ist unbekannt, nicht null">—</td>
  }
  const wert = zeile.kg.get(idx)
  if (wert === undefined) return <td className={klasse} />
  const band = zeile.band.get(idx)
  return (
    <td className={klasse} title={idx === -1
      ? 'laut Rechnung noch verkaufsfähig, aber unter das kleinste Band geschrumpft'
      : `${band ?? ''} · ${zeile.sorte}`}>
      {masse(wert)}
      {band && filter.gruppe === 'gesamt' && <span className="band-unter">{band}</span>}
    </td>
  )
}

/** Das Feld „in X Wochen" — ein Zustand, zwei Felder (Tabelle und Glocke). */
function WochenFeld({ id, wochen, setzen, datum: stichtag }: {
  id: string; wochen: number; setzen: (n: number) => void; datum?: string | null
}) {
  const [text, setText] = useState(String(wochen))
  useEffect(() => { setText(String(wochen)) }, [wochen])
  // Erst nach einer kurzen Pause übernehmen: Wer „12" tippt, soll nicht bei
  // „1" einen Aufruf auslösen.
  useEffect(() => {
    const n = Number(text)
    if (!Number.isFinite(n) || n < 1 || n > WOCHEN_MAX || n === wochen) return
    const uhr = setTimeout(() => setzen(Math.round(n)), 300)
    return () => clearTimeout(uhr)
  }, [text, wochen, setzen])
  const gueltig = Number(text) >= 1 && Number(text) <= WOCHEN_MAX
  return (
    <span className="wochenfeld">
      <label htmlFor={id}>in</label>
      <input id={id} type="number" inputMode="numeric" min={1} max={WOCHEN_MAX} step={1}
             value={text} aria-invalid={!gueltig} onChange={e => setText(e.target.value)} />
      <span>Wochen{stichtag ? <span className="leise"> · {datum(stichtag).slice(0, 6)}</span> : null}</span>
    </span>
  )
}

/* ---------- L4: Wie schwer sind die Kürbisse? -------------------------------- */

function Glockenkarte({ daten, filter, wochen, setzeWochen }: {
  daten: Auswertung; filter: Filter; wochen: number; setzeWochen: (n: number) => void
}) {
  const [wann, setWann] = useState<'heute' | 'spaeter'>('heute')
  const h = wann === 'heute' ? 0 : 7 * wochen
  const glocke = useStichtag(kaliberGlockeBei, h)
  const kaliber = useStichtag(lagerKaliberBei, h)
  const [sorte, setSorte] = useState('')

  // Eine Glocke zeigt eine Sorte: die Bänder sind je Sorte andere, und eine
  // Kurve über alle Sorten wäre eine Zahl, die es nicht gibt.
  const gruppe = filter.gruppe === 'charge' ? 'charge' : 'sorte'
  const schluessel = filter.gruppe === 'charge' ? filter.schluessel
    : filter.gruppe === 'sorte' ? filter.schluessel
    : (sorte || groessteSorte(glocke.zeilen, daten.bestand))
  const zeilen = glocke.zeilen.filter(z => z.gruppe === gruppe && z.schluessel === schluessel)
  const sorten = [...new Set(daten.bestand.filter(b => b.lager_kg > 0).map(b => b.sorte))].sort((a, b) => a.localeCompare(b, 'de'))

  const stufen = zeilen.map(z => ({ x: z.stufe_g, n: z.n_kuerbis ?? 0 })).sort((a, b) => a.x - b.x)
  const gesamt = stufen.reduce((a, s) => a + s.n, 0)
  const mittel = gesamt > 0 ? stufen.reduce((a, s) => a + (s.x + STUFE_G / 2) * s.n, 0) / gesamt : null
  const basis = zeilen[0]?.basis ?? 'keine'
  const stichtag = zeilen[0]?.datum ?? null

  // Die Grenzen und die Anteile kommen aus derselben Rechnung wie die Tabelle.
  const bandzeilenH = kaliber.zeilen.filter(z => z.gruppe === gruppe && z.schluessel === schluessel)
  const grenzen = [...new Map(bandzeilenH.filter(z => z.band_von !== null)
    .map(z => [z.band_von!, { x: z.band_von!, text: `K${(z.kaliber_idx ?? 0) + 1}` }])).values()].sort((a, b) => a.x - b.x)
  const unterstes = grenzen[0]?.x ?? null
  const anteile = bandzeilenH.filter(z => z.kaliber_idx !== null && (z.anteil ?? 0) > 0.001)
    .sort((a, b) => (a.kaliber_idx ?? 0) - (b.kaliber_idx ?? 0))

  return (
    <Karte id="lager-glocke" titel="Wie schwer sind die Kürbisse?"
           unter={`Die Gewichte der sortierten Kürbisse${gruppe === 'charge' ? ` der Charge ${schluessel}` : ` der Sorte ${schluessel || '—'}`}, mit den Kalibergrenzen.`}
           aktion={<span className="reihe">
             <Segmente wahl={wann} setzen={setWann} id="glocke-umschalter"
                       teile={[['heute', 'heute', 'glocke-heute'], ['spaeter', `in ${wochen} Wochen`, 'glocke-spaeter']]} />
             <WochenFeld id="glocke-wochen" wochen={wochen} setzen={setzeWochen} datum={wann === 'spaeter' ? stichtag : null} />
           </span>}>
      {filter.gruppe === 'gesamt' && sorten.length > 1 && (
        <div className="filterleiste">
          <label htmlFor="glocke-sorte">Sorte</label>
          <select id="glocke-sorte" value={schluessel} onChange={e => setSorte(e.target.value)}>
            {sorten.map(x => <option key={x} value={x}>{x}</option>)}
          </select>
        </div>
      )}
      {glocke.fehler && <Hinweis art="warnung">Die Glocke konnte nicht geladen werden: {glocke.fehler}</Hinweis>}
      {stufen.length === 0
        ? <Leer titel="Keine Sortier-CSV">Sobald ein Sortierlauf eingelesen ist, steht hier die Glocke.</Leer>
        : (
        <>
          <Glocke stufen={stufen} breite={STUFE_G} grenzen={grenzen} hoehe={200}
                  xFormat={x => `${x}`} mittel={mittel}
                  klassenfarbe={x => unterstes !== null && x + STUFE_G <= unterstes ? 'var(--gelb)' : 'var(--kuerbis)'} />
          <p className="leise">
            {zahl(gesamt)} gewogen{wann === 'heute'
              ? <Herkunft art="gemessen" text="die Gewichte aus der Sortier-CSV" />
              : <Herkunft art="gerechnet" text="dieselben Kürbisse, um die Verdunstung bis zum Stichtag leichter" />}
            {' · '}{basis === 'charge' ? 'eigene Messung' : basis === 'sorte' ? 'aus der Sorte' : 'gemischt'}
            {mittel !== null && <> · Schwerpunkt {Math.round(mittel)} g</>}
            {anteile.map(z => <span key={z.kaliber_idx}> · {z.kaliber_idx === -1 ? 'unter Kaliber' : `K${(z.kaliber_idx ?? 0) + 1}`} {prozent(z.anteil, 0)}</span>)}
          </p>
        </>
      )}
      <Erklaerung titel="Was die Glocke sagt">
        Dieselben Kürbisse wie in der Tabelle darüber, nur in 50-Gramm-Stufen statt in Bändern — und am selben Stichtag.
        Bezahlt wird je Stück innerhalb eines Kalibers: Wer weiss, wo eine Sorte liegt, kann ein engeres Band liefern.
        Mit der Lagerdauer wandert die Glocke nach links; was unter das kleinste Band fällt, steht in der Tabelle als „unter Kaliber".
      </Erklaerung>
    </Karte>
  )
}

/** Ohne Wahl: die Sorte mit der meisten liegenden Ware. */
function groessteSorte(zeilen: KaliberGlocke[], bestand: Bestand[]): string {
  const je = new Map<string, number>()
  for (const b of bestand) if (b.lager_kg > 0) je.set(b.sorte, (je.get(b.sorte) ?? 0) + b.lager_kg)
  const sortiert = [...je.entries()].sort((a, b) => b[1] - a[1])
  for (const [s] of sortiert) if (zeilen.some(z => z.gruppe === 'sorte' && z.schluessel === s)) return s
  return sortiert[0]?.[0] ?? ''
}
