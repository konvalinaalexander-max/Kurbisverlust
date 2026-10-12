import { Fragment, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { fehlerText } from '../lib/db'
import { Erklaerung, Herkunft, Hinweis, Karte, Kennzahl, Leer, Marke, Segmente } from '../components/Bausteine'
import { Linien, tonnenAchse, type Reihe } from '../components/Diagramm'
import { artikelGrundlagen, artikelLagerChargeBei, useAuswertung, useStichtag,
         type ArtikelKaliber, type ArtikelLagerCharge, type Bestand, type ChargeLabel, type KundeTag, type SorteGruppe } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { WochenFeld } from '../components/WochenFeld'
import { ZChevron } from '../components/Zeichen'
import { KLASSEN, OFFEN, klasseVon, passtGruppe, passtKlasse, passtLabel, rang, uebersichtszeilen,
         type Klasse, type Uebersichtszeile, type Wahl } from '../auswertung/artikel'

const TAG = 86400000

/**
 * Lagermanagement nach Artikel — der zweite Lagerreiter (Runde AO, neu
 * gebaut in Runde AP, 12. Oktober).
 *
 *   „Wie viel haben wir Knirps klein noch da, das wir als Demeter verkaufen
 *    können? … Und dann kann ich darauf klicken, und dann sagst du mir im
 *    Dropdown die Chargen an, wie sich die Zahl zusammensetzt. … Knirps
 *    klein, Knirps gross, das sind zwei unterschiedliche Sachen." — und:
 *   „zehn Grafiken, aber alle so mega klein … dann machst du doch lieber, dass
 *    man aussuchen muss, welcher Artikel und welches Label, und dann zeigst
 *    du mir an, wie das bisher gegangen ist."
 *
 * Ein Artikel ist Artikelgruppe × Grösse × Label, wie Perigon ihn führt
 * („Bio Kürbis Knirps Dem klein"). Oben wählt man ihn — Artikel, klein oder
 * gross oder beide, Demeter oder Knospe oder beide —, und alles darunter
 * folgt der Wahl:
 *   1. Wie viel ist von welchem Artikel noch da (Runde AQ): je Artikel ein
 *      Balken — so lang wie sein Eingang, grau, was ausgeliefert ist, orange,
 *      was noch im Lager liegt, blau darin das Verkaufsfähige nach Grösse —,
 *      und dieselben Zahlen als Tabelle. „Mit einer Grafik, nach Artikeln
 *      sortiert, noch im Lager, also Eingang, Ausgang, noch im Lager. Und dann
 *      vielleicht schon auch noch mit Tabelle."
 *   2. Noch da je Artikel und Grösse, in Kisten; ein Klick zeigt die Chargen
 *      dahinter (artikel_lager_charge, 0113).
 *   3. Wie es gegangen ist: EIN grosses Diagramm, kumuliert über die Saison,
 *      diese gegen die Vorjahre — alle Kunden zusammen oder einer (v_kunde_tag).
 *
 * Nichts davon ist eine zweite Rechnung: das Verkaufsfähige ist das der
 * Chargen, nach den Kalibern des Artikels geteilt; die Lieferungen sind die
 * der Perigon-Dateien.
 */

const gruppeName = (g: string | null) =>
  g === null ? 'Artikelgruppe unbekannt' : g === 'Knirps' ? 'Knirps (Hokkaido)' : g
const labelName = (l: string | null) => l === 'D' ? 'Demeter' : l === 'K' ? 'Knospe' : 'Label unbekannt'


const klasseName = (k: Klasse) =>
  k === 'stueck' ? 'je Stück' : k === 'ausserhalb' ? 'ausserhalb der Kaliber' : k === 'ohne' ? 'ohne Grösse' : k

/** Verkauft: KundeTag.groesse ist gross, klein oder lose — lose zählt nur bei „beide". */
const passtVerkauf = (w: Wahl, g: string) => w.groesse === 'beide' || g === w.groesse

const wahlName = (w: Wahl) =>
  `${w.gruppe ? (w.gruppe === 'Knirps' ? 'Knirps' : w.gruppe) : 'alle Artikel'}${w.groesse === 'beide' ? '' : ` ${w.groesse}`}`
  + `${w.label === 'beide' ? '' : ` · ${labelName(w.label)}`}`

const WAHL_SCHLUESSEL = 'artikel.wahl'
function wahlLesen(): Wahl {
  try {
    const w = JSON.parse(localStorage.getItem(WAHL_SCHLUESSEL) ?? 'null') as Partial<Wahl> | null
    if (w && typeof w.gruppe === 'string' && ['beide', 'klein', 'gross'].includes(String(w.groesse))
        && ['beide', 'D', 'K'].includes(String(w.label))) return w as Wahl
  } catch { /* privates Fenster */ }
  return OFFEN
}

interface Grundlagen { labels: ChargeLabel[]; gruppen: SorteGruppe[]; kaliber: ArtikelKaliber[]; kunden: KundeTag[] }

export default function Artikel() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const [wochen, setWochen] = useState(0)
  const lager = useStichtag(artikelLagerChargeBei, 7 * wochen)
  // Die Übersicht zeigt immer heute: Eingang und ausgeliefert gibt es nur bis heute.
  const lagerHeute = useStichtag(artikelLagerChargeBei, 0)
  const [grund, setGrund] = useState<Grundlagen | null>(null)
  const [grundFehler, setGrundFehler] = useState<string | null>(null)
  const [wahl, setWahlRoh] = useState<Wahl>(wahlLesen)
  const setWahl = (w: Wahl) => {
    setWahlRoh(w)
    try { localStorage.setItem(WAHL_SCHLUESSEL, JSON.stringify(w)) } catch { /* privates Fenster */ }
  }
  useEffect(() => {
    let gilt = true
    artikelGrundlagen()
      .then(g => { if (gilt) setGrund(g) })
      .catch((f: unknown) => { if (gilt) setGrundFehler(fehlerText(f)) })
    return () => { gilt = false }
  }, [])

  const gruppen = useMemo(() => {
    const s = new Set<string>()
    for (const g of grund?.gruppen ?? []) if (g.artikelgruppe) s.add(g.artikelgruppe)
    for (const k of grund?.kunden ?? []) if (k.gruppe) s.add(k.gruppe)
    for (const t of lager.zeilen) if (t.artikelgruppe) s.add(t.artikelgruppe)
    return [...s].sort((a, b) => rang(a) - rang(b) || a.localeCompare(b, 'de'))
  }, [grund, lager.zeilen])

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null

  return (
    <>
      <Reiterkopf titel="Lagermanagement nach Artikel"
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt}
                  zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
      <Probleme liste={daten.probleme} />
      {grundFehler && <Hinweis art="warnung">Die Zuordnung zu Artikeln liess sich nicht laden: {grundFehler}</Hinweis>}
      {grund && (
        <>
          <Wahlleiste wahl={wahl} setzen={setWahl} gruppen={gruppen} />
          <NochDa bestand={daten.bestand} grund={grund} teile={lager.zeilen} laedt={lager.laedt} lagerFehler={lager.fehler}
                  wochen={wochen} setzeWochen={setWochen} wahl={wahl} heute={daten.heute}
                  uebersicht={<Uebersicht bestand={daten.bestand} grund={grund} teile={lagerHeute.zeilen} wahl={wahl} />} />
          <Verlauf kunden={grund.kunden} heute={daten.heute} wahl={wahl} />
        </>
      )}
      {!grund && !grundFehler && <Rechnet fortschritt={null} />}
    </>
  )
}

/* ---------- Die Wahl oben: Artikel, Grösse, Label ---------------------------- */

function Wahlleiste({ wahl, setzen, gruppen }: { wahl: Wahl; setzen: (w: Wahl) => void; gruppen: string[] }) {
  const eingeschraenkt = wahl.gruppe !== '' || wahl.groesse !== 'beide' || wahl.label !== 'beide'
  return (
    <div className="filterleiste haftend artikel-wahl" id="artikel-wahl">
      <label htmlFor="artikel-gruppe">Artikel</label>
      <select id="artikel-gruppe" value={wahl.gruppe} onChange={e => setzen({ ...wahl, gruppe: e.target.value })}>
        <option value="">alle Artikel</option>
        {gruppen.map(g => <option key={g} value={g}>{gruppeName(g)}</option>)}
      </select>
      <span className="wahl-teil">
        <span>Grösse</span>
        <Segmente id="artikel-groesse" wahl={wahl.groesse} setzen={g => setzen({ ...wahl, groesse: g })}
                  teile={[['beide', 'beide', 'artikel-groesse-beide'], ['klein', 'klein', 'artikel-groesse-klein'], ['gross', 'gross', 'artikel-groesse-gross']]} />
      </span>
      <span className="wahl-teil">
        <span>Label</span>
        <Segmente id="artikel-label" wahl={wahl.label} setzen={l => setzen({ ...wahl, label: l })}
                  teile={[['beide', 'beide', 'artikel-label-beide'], ['D', 'Demeter', 'artikel-label-d'], ['K', 'Knospe', 'artikel-label-k']]} />
      </span>
      {eingeschraenkt && <button type="button" className="werkzeug-knopf" onClick={() => setzen(OFFEN)}>alle zeigen</button>}
    </div>
  )
}

/* ---------- 1. Was ist noch da? --------------------------------------------- */

/** Je Charge, was sie zu einer Auswahl beiträgt. */
interface Chargenteil { charge_nr: number; sorte: string; label: 'D' | 'K' | null; kg: number; stueck: number | null; klassen: Set<Klasse> }

interface Artikelzeile {
  schluessel: string; gruppe: string | null; klasse: Klasse; label: 'D' | 'K' | null
  kg: number; stueck: number | null; kisten: number | null; stueckJeKiste: number | null
  vonG: number | null; bisG: number | null
  teile: ArtikelLagerCharge[]
}

function artikelzeilen(teile: ArtikelLagerCharge[], wahl: Wahl): Artikelzeile[] {
  const m = new Map<string, Artikelzeile>()
  for (const t of teile) {
    const klasse = klasseVon(t.groesse)
    if (!(Number(t.kg) > 0) || !passtGruppe(wahl, t.artikelgruppe) || !passtLabel(wahl, t.label) || !passtKlasse(wahl, klasse)) continue
    const k = `${t.artikelgruppe ?? ''}|${klasse}|${t.label ?? ''}`
    let z = m.get(k)
    if (!z) {
      z = { schluessel: k, gruppe: t.artikelgruppe, klasse, label: t.label, kg: 0, stueck: null, kisten: null,
            stueckJeKiste: klasse === 'klein' || klasse === 'gross' ? t.stueck_je_kiste : null,
            vonG: t.von_g, bisG: t.bis_g, teile: [] }
      m.set(k, z)
    }
    z.kg += Number(t.kg)
    if (t.stueck != null) z.stueck = (z.stueck ?? 0) + Number(t.stueck)
    z.teile.push(t)
  }
  for (const z of m.values()) z.kisten = z.stueck != null && z.stueckJeKiste ? z.stueck / z.stueckJeKiste : null
  return [...m.values()].sort((a, b) => rang(a.gruppe) - rang(b.gruppe) || (a.gruppe ?? '').localeCompare(b.gruppe ?? '')
                                        || KLASSEN.indexOf(a.klasse) - KLASSEN.indexOf(b.klasse)
                                        || (a.label ?? 'Z').localeCompare(b.label ?? 'Z'))
}

/** Die Teile je Charge zusammengezählt — woraus eine Zahl besteht. */
function jeCharge(teile: ArtikelLagerCharge[]): Chargenteil[] {
  const m = new Map<number, Chargenteil>()
  for (const t of teile) {
    let c = m.get(t.charge_nr)
    if (!c) { c = { charge_nr: t.charge_nr, sorte: t.sorte, label: t.label, kg: 0, stueck: null, klassen: new Set() }; m.set(t.charge_nr, c) }
    c.kg += Number(t.kg)
    if (t.stueck != null) c.stueck = (c.stueck ?? 0) + Number(t.stueck)
    c.klassen.add(klasseVon(t.groesse))
  }
  return [...m.values()].sort((a, b) => b.kg - a.kg)
}

function NochDa({ bestand, grund, teile, laedt, lagerFehler, wochen, setzeWochen, wahl, heute, uebersicht }: {
  bestand: Bestand[]; grund: Grundlagen; teile: ArtikelLagerCharge[]; laedt: boolean; lagerFehler: string | null
  wochen: number; setzeWochen: (n: number) => void; wahl: Wahl; heute: string; uebersicht: ReactNode
}) {
  const [auf, setAuf] = useState<Set<string>>(new Set())
  const [zeigeChargen, setZeigeChargen] = useState(false)
  const labelVon = useMemo(() => new Map(grund.labels.map(l => [l.charge_nr, l])), [grund.labels])
  const gruppeVon = useMemo(() => new Map(grund.gruppen.map(g => [g.sorte, g])), [grund.gruppen])
  const chargeVon = useMemo(() => new Map(bestand.map(b => [b.charge_nr, b])), [bestand])
  const zeilen = useMemo(() => artikelzeilen(teile, wahl), [teile, wahl])
  const ausgewaehlt = useMemo(() => zeilen.flatMap(z => z.teile), [zeilen])
  const chargen = useMemo(() => jeCharge(ausgewaehlt), [ausgewaehlt])
  const stichtag = teile[0]?.datum ?? null
  const spaeter = wochen > 0
  const herkunft = spaeter ? 'prognose' : 'gerechnet'
  const gesamt = zeilen.reduce((a, z) => a + z.kg, 0)
  const jeLabel = (l: 'D' | 'K') => zeilen.filter(z => z.label === l).reduce((a, z) => a + z.kg, 0)
  // Kisten nur, wenn jede Zeile der Auswahl in Kisten geht (klein, gross).
  const kisten = zeilen.length > 0 && zeilen.every(z => z.kisten != null) ? zeilen.reduce((a, z) => a + (z.kisten ?? 0), 0) : null
  const umschalten = (k: string) => setAuf(a => { const n = new Set(a); if (n.has(k)) n.delete(k); else n.add(k); return n })

  // Die Chargen dahinter, über alle Grössen: Eingang, ausgeliefert, im Lager.
  const dahinter = bestand.filter(b => passtGruppe(wahl, gruppeVon.get(b.sorte)?.artikelgruppe ?? null)
                                    && passtLabel(wahl, labelVon.get(b.charge_nr)?.label ?? null))
  const quellen = new Map<string, number>()
  for (const b of dahinter) if (b.lager_kg > 0) {
    const q = labelVon.get(b.charge_nr)?.quelle ?? 'unbekannt'
    quellen.set(q, (quellen.get(q) ?? 0) + 1)
  }
  const widerspruch = dahinter.filter(b => (labelVon.get(b.charge_nr)?.n_widerspruch ?? 0) > 0)
  const ohneGruppe = [...new Set(bestand.filter(b => b.lager_kg > 0 && !gruppeVon.get(b.sorte)?.artikelgruppe).map(b => b.sorte))]

  return (
    <>
      <div className="kennzahl-reihe">
        <Kennzahl ton="gruen" id="kz-artikel-gesamt"
                  titel={<>{wahlName(wahl)}: verkaufsfähig {spaeter ? `in ${wochen} Wochen` : 'heute'} <Herkunft art={herkunft} /></>}
                  wert={tonnen(gesamt)}
                  unter={<>
                    noch da{kisten != null ? <>, ≈ {zahl(Math.round(kisten))} Kisten</> : null}
                    {spaeter && stichtag ? <> · am {datum(stichtag).slice(0, 6)}</> : null}
                    {chargen.length > 0 && (
                      <button type="button" className="werkzeug-knopf kennzahl-knopf" id="artikel-chargen-knopf"
                              aria-expanded={zeigeChargen} onClick={() => setZeigeChargen(z => !z)}>
                        aus {chargen.length} {chargen.length === 1 ? 'Charge' : 'Chargen'} <ZChevron size={12} />
                      </button>
                    )}
                  </>} />
        {wahl.label === 'beide' && <>
          <Kennzahl titel={<>davon Demeter <Herkunft art={herkunft} /></>} id="kz-artikel-d" wert={tonnen(jeLabel('D'))}
                    unter={<>{gesamt > 0 ? prozent(jeLabel('D') / gesamt, 0) : '—'} des Verkaufsfähigen</>} />
          <Kennzahl titel={<>davon Knospe <Herkunft art={herkunft} /></>} id="kz-artikel-k" wert={tonnen(jeLabel('K'))}
                    unter={<>{gesamt > 0 ? prozent(jeLabel('K') / gesamt, 0) : '—'} · Demeter darf als Knospe gehen, nicht umgekehrt</>} />
        </>}
        <VerkauftKennzahl kunden={grund.kunden} heute={heute} wahl={wahl} />
      </div>

      {zeigeChargen && chargen.length > 0 && (
        <Karte id="artikel-chargen-wahl" titel={<>Woraus {tonnen(gesamt)} {wahlName(wahl)} bestehen</>}
               aktion={<button type="button" className="werkzeug-knopf" onClick={() => setZeigeChargen(false)}>schliessen</button>}>
          <Chargenliste chargen={chargen} labelVon={labelVon} chargeVon={chargeVon} mitGroesse={wahl.groesse === 'beide'} />
        </Karte>
      )}

      {widerspruch.length > 0 && (
        <Hinweis art="info">
          {widerspruch.length === 1 ? 'Eine Charge wurde' : `${widerspruch.length} Chargen wurden`} als Demeter verkauft, aber als Knospe
          geliefert ({widerspruch.map(b => b.charge_nr).join(', ')}) — {widerspruch.length === 1 ? 'sie zählt' : 'sie zählen'} als Knospe.
          Stimmt das nicht, unter <Link to="/betrieb/stammdaten">Stammdaten → Chargen</Link> Demeter eintragen.
        </Hinweis>
      )}
      {ohneGruppe.length > 0 && (
        <Hinweis art="info">Ohne Artikelgruppe: {ohneGruppe.join(', ')} — in den <Link to="/betrieb/stammdaten">Stammdaten → Sorten</Link> zuordnen.</Hinweis>
      )}

      {uebersicht}

      <Karte id="artikel-bestand" titel="Je Artikel und Grösse — in Kisten"
             aktion={<WochenFeld id="artikel-wochen" wochen={wochen} setzen={setzeWochen} datum={spaeter ? stichtag : null} />}>
        {lagerFehler && <Hinweis art="warnung">Das Lager je Artikel liess sich nicht laden: {lagerFehler}</Hinweis>}
        {zeilen.length === 0
          ? <Leer titel={teile.length === 0 ? 'Nichts im Lager' : `Kein ${wahlName(wahl)} im Lager`}>
              {teile.length === 0 ? 'Sobald Ware eingelagert ist, steht hier, welcher Artikel daraus wird.' : 'Oben einen anderen Artikel, eine andere Grösse oder ein anderes Label wählen.'}
            </Leer>
          : (
          <div className="rollbar">
            <table className={`dicht umbruch lagertabelle artikeltabelle${laedt ? ' laedt' : ''}`}>
              <thead>
                <tr>
                  <th className="haftend">Artikel</th>
                  <th className="zahl">verkaufsfähig {spaeter ? `in ${wochen} Wochen` : 'heute'}<Herkunft art={herkunft} /></th>
                  <th className="zahl">≈ Kisten / Stück</th>
                </tr>
              </thead>
              <tbody>
                {zeilen.map(z => {
                  const offen = auf.has(z.schluessel)
                  const zc = jeCharge(z.teile)
                  return (
                    <Fragment key={z.schluessel}>
                      <tr className={`klickbar${offen ? ' offen' : ''}`} onClick={() => umschalten(z.schluessel)} aria-expanded={offen}>
                        <th scope="row" className="haftend">
                          <span className="chevron" aria-hidden="true"><ZChevron size={14} /></span>
                          <span className="zeilenname">{z.gruppe === 'Knirps' ? 'Knirps' : gruppeName(z.gruppe)} {klasseName(z.klasse)}</span>
                          <span className={`zeilenunter label-${z.label ?? 'x'}`}>{labelName(z.label)}
                            {z.vonG != null && z.bisG != null && (z.klasse === 'klein' || z.klasse === 'gross') && <span className="leise"> · {zahl(z.vonG)}–{zahl(z.bisG)} g</span>}
                            {z.klasse === 'ausserhalb' && <span className="leise"> · lose verkäuflich</span>}
                            {z.klasse === 'ohne' && <span className="leise"> · keine Sortier-CSV</span>}
                            <span className="leise"> · {zc.length} {zc.length === 1 ? 'Charge' : 'Chargen'}</span>
                          </span>
                        </th>
                        <td className="zahl"><strong>{masse(z.kg)}</strong></td>
                        <td className="zahl">{z.kisten != null
                          ? <>≈ {zahl(Math.round(z.kisten))} Kisten<span className="zelle-unter">à {z.stueckJeKiste} Stück</span></>
                          : z.stueck != null && z.klasse !== 'ohne' ? <>≈ {zahl(Math.round(z.stueck))} Stück</> : <span className="leise">—</span>}</td>
                      </tr>
                      {offen && (
                        <tr className="artikel-chargen"><td colSpan={3}>
                          <Chargenliste chargen={zc} labelVon={labelVon} chargeVon={chargeVon} mitGroesse={false} />
                        </td></tr>
                      )}
                    </Fragment>
                  )
                })}
              </tbody>
              {zeilen.length > 1 && (
                <tfoot>
                  <tr>
                    <th scope="row" className="haftend">Summe</th>
                    <td className="zahl"><strong>{masse(gesamt)}</strong></td>
                    <td className="zahl">{kisten != null ? <>≈ {zahl(Math.round(kisten))} Kisten</> : ''}
                      <span className="zelle-unter">{chargen.length} {chargen.length === 1 ? 'Charge' : 'Chargen'}</span></td>
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        )}
        {/* Runde AQ: Eingang, ausgeliefert und im Lager der Chargen dahinter stehen jetzt in der Übersicht oben. */}
        {quellen.size > 0 && (
          <p className="hilfe" id="artikel-dahinter">
            Demeter oder Knospe der Chargen mit Ware: {[...quellen.entries()].map(([q, n]) => `${n} ${quelleText(q)}`).join(', ')}.
          </p>
        )}
        <Erklaerung>
          <p><strong>Artikel</strong> heisst hier, was Perigon verkauft: Artikelgruppe × Grösse × Label — „Knirps klein · Demeter" ist ein
          anderer Artikel als „Knirps gross · Demeter". Die Gruppe kommt aus der Sorte (Kaori Kuri, Amoro, … gehen als Knirps; änderbar in den
          Stammdaten), das Label aus der Charge.</p>
          <p><strong>Demeter oder Knospe</strong> je Charge: Hat Perigon die Charge auch nur einmal als Demeter geliefert, ist sie Demeter —
          ein Demeter-Feld, auch wenn ein Teil als Knospe verkauft wird. Sonst ist sie Knospe („Knospe ist alles, was nicht Demeter ist").
          Eine Charge, die noch nie verkauft wurde, nimmt das Label der anderen Chargen ihres Produzenten; kennt Perigon den Produzenten
          nicht, gilt Knospe, angenommen. Die Stammdaten gehen allem vor.</p>
          <p><strong>Verkaufsfähig</strong> ist dieselbe Zahl wie im Lagermanagement nach Charge: je Charge, was nach Verdunstung, Palox und
          zu klein/zu gross bleibt <Herkunft art={herkunft} />. Geteilt wird es nach der Sortier-CSV der Charge (oder ihrer Sorte), jeder
          Kürbis um die gemessene Verdunstung bis zum Stichtag geschrumpft: Wiegt er so viel wie ein kleiner Artikel, zählt er klein, wie ein
          grosser, gross; dazwischen, darunter oder darüber heisst <em>ausserhalb der Kaliber</em> — lose verkäuflich. Kaliber und Kisten
          (Coop 2026): {grund.kaliber.filter(k => k.groesse !== 'stueck').slice(0, 2).map(k => `${k.gruppe} ${k.groesse} ${zahl(k.von_g)}–${zahl(k.bis_g)} g`).join(', ')} …;
          Kisten zu {[...new Set(grund.kaliber.map(k => k.stueck_je_kiste).filter(Boolean))].sort().join(' bzw. ')} Stück.
          Stück = Kilo ÷ mittleres Gewicht der Klasse, Kisten = Stück ÷ Stück je Kiste.</p>
        </Erklaerung>
      </Karte>
    </>
  )
}

/* ---------- 1. Wie viel ist von welchem Artikel noch da? -------------------- */

/** „klein 7.4 t · gross 3.4 t · lose 0.6 t" — das Verkaufsfähige nach Grösse, in einer Zeile. */
function groessenText(kl: Map<Klasse, number>): string {
  const lose = (kl.get('ausserhalb') ?? 0) + (kl.get('ohne') ?? 0)
  return [['klein', kl.get('klein') ?? 0], ['gross', kl.get('gross') ?? 0], ['je Stück', kl.get('stueck') ?? 0], ['lose', lose]]
    .filter(([, v]) => Number(v) > 0).map(([n, v]) => `${n} ${masse(Number(v))}`).join(' · ')
}

/** Die Farben der Grössen im Verkaufsfähigen — eine Familie, vom kräftigen Blau zum hellen. */
const KLASSE_FARBE: Record<Klasse, string> = {
  klein: 'var(--blau)', gross: 'color-mix(in srgb, var(--blau) 62%, var(--flaeche))', stueck: 'var(--blau)',
  ausserhalb: 'color-mix(in srgb, var(--blau) 35%, var(--flaeche))', ohne: 'color-mix(in srgb, var(--blau) 35%, var(--flaeche))',
}

function Uebersicht({ bestand, grund, teile, wahl }: { bestand: Bestand[]; grund: Grundlagen; teile: ArtikelLagerCharge[]; wahl: Wahl }) {
  const labelVon = useMemo(() => new Map(grund.labels.map(l => [l.charge_nr, l])), [grund.labels])
  const gruppeVon = useMemo(() => new Map(grund.gruppen.map(g => [g.sorte, g])), [grund.gruppen])
  const zeilen = useMemo(() => uebersichtszeilen(bestand, labelVon, gruppeVon, teile, wahl), [bestand, labelVon, gruppeVon, teile, wahl])
  if (zeilen.length === 0) return null
  const max = Math.max(...zeilen.map(z => z.ausgelagert + z.lager), 1)
  const gewaehlt = (kl: Klasse) => passtKlasse(wahl, kl)
  const vfGewaehlt = (z: Uebersichtszeile) => wahl.groesse === 'beide' ? z.vf
    : [...z.klassen.entries()].filter(([kl]) => gewaehlt(kl)).reduce((a, [, v]) => a + v, 0)
  const summe = (f: (z: Uebersichtszeile) => number) => zeilen.reduce((a, z) => a + f(z), 0)
  const klassenDa = KLASSEN.filter(kl => zeilen.some(z => (z.klassen.get(kl) ?? 0) > 0))
  const name = (z: Uebersichtszeile) => `${z.gruppe === 'Knirps' ? 'Knirps' : gruppeName(z.gruppe)} · ${labelName(z.label)}`
  const summeKlassen = new Map<Klasse, number>()
  for (const z of zeilen) for (const [kl, v] of z.klassen) summeKlassen.set(kl, (summeKlassen.get(kl) ?? 0) + v)
  const groesseText = wahl.groesse === 'beide' ? '' : ` ${wahl.groesse}`

  return (
    <Karte id="artikel-uebersicht" titel="Wie viel ist von welchem Artikel noch da?">
      <div className="uebersicht" role="list">
        {zeilen.map(z => {
          const ganz = z.ausgelagert + z.lager
          const anteil = (v: number, von: number) => `${von > 0 ? Math.max(Math.min((v / von) * 100, 100), 0) : 0}%`
          const vfKlassen = KLASSEN.map(kl => [kl, z.klassen.get(kl) ?? 0] as const).filter(([, v]) => v > 0)
          const rest = Math.max(z.lager - vfKlassen.reduce((a, [, v]) => a + v, 0), 0)
          return (
            <div key={z.schluessel} className="uebersicht-zeile" role="listitem">
              <div className="uebersicht-name">
                <strong>{name(z)}</strong>
                <span className="leise">{z.n} {z.n === 1 ? 'Charge' : 'Chargen'} · Eingang {masse(z.eingang)}</span>
              </div>
              <div className="uebersicht-bahn">
                <div className="uebersicht-spur" style={{ width: anteil(ganz, max) }}
                     aria-label={`Eingang ${masse(z.eingang)}, ausgeliefert ${masse(z.geliefert)}, im Lager ${masse(z.lager)}, verkaufsfähig ${masse(z.vf)}`}>
                  <span className="uebersicht-teil ausgeliefert" style={{ width: anteil(z.ausgelagert, ganz) }}
                        title={`ausgeliefert ${masse(z.geliefert)} — dafür gingen ${masse(z.ausgelagert)} Eingangsware aus dem Lager`}>
                    {z.ausgelagert / max >= 0.09 && <em>{masse(z.geliefert)}</em>}
                  </span>
                  <span className="uebersicht-lager" style={{ width: anteil(z.lager, ganz) }}
                        title={`im Lager ${masse(z.lager)} Eingangsware — davon verkaufsfähig ${masse(z.vf)}, der Rest ist verdunstet, im Palox oder zu klein / zu gross`}>
                    {vfKlassen.map(([kl, v]) => (
                      <span key={kl} className={`uebersicht-teil${gewaehlt(kl) ? '' : ' gedimmt'}`}
                            style={{ width: anteil(v, z.lager), background: KLASSE_FARBE[kl] }}
                            title={`verkaufsfähig ${klasseName(kl)}: ${masse(v)}`} />
                    ))}
                    {rest > 0 && <span className="uebersicht-teil rest" style={{ width: anteil(rest, z.lager) }} />}
                  </span>
                </div>
                {z.lager > 0 && <span className="uebersicht-lagertext">im Lager {masse(z.lager)}</span>}
              </div>
              <div className="uebersicht-wert">
                <strong>{masse(vfGewaehlt(z))}</strong>
                <span className="leise">verkaufsfähig{groesseText}{z.luecke > 0 ? ` · ${z.luecke} ohne Zahl` : ''}</span>
              </div>
            </div>
          )
        })}
      </div>
      <div className="legende uebersicht-legende">
        <span><span className="chip" style={{ background: 'var(--text-leise)' }} />ausgeliefert</span>
        {klassenDa.filter(kl => kl === 'klein' || kl === 'gross' || kl === 'stueck').map(kl => (
          <span key={kl}><span className="chip" style={{ background: KLASSE_FARBE[kl] }} />verkaufsfähig {klasseName(kl)}</span>
        ))}
        {klassenDa.some(kl => kl === 'ausserhalb' || kl === 'ohne') && (
          <span><span className="chip" style={{ background: KLASSE_FARBE.ohne }} />verkaufsfähig, lose (ausserhalb der Kaliber oder ohne Sortier-CSV)</span>
        )}
        <span><span className="chip uebersicht-chip-rest" />im Lager, nicht mehr verkaufsfähig</span>
        <span className="leise">· jeder Balken ist so lang wie der Eingang des Artikels</span>
      </div>

      <div className="rollbar">
        <table className="dicht uebersicht-tabelle" id="artikel-uebersicht-tabelle">
          <thead><tr>
            <th>Artikel</th>
            <th className="zahl">Eingang<Herkunft art="gemessen" /></th>
            <th className="zahl">ausgeliefert<Herkunft art="gemessen" /></th>
            <th className="zahl">im Lager<Herkunft art="gerechnet" /></th>
            <th className="zahl">verkaufsfähig<Herkunft art="gerechnet" /></th>
          </tr></thead>
          <tbody>{zeilen.map(z => (
            <tr key={z.schluessel}>
              <td><strong>{name(z)}</strong><span className="zelle-unter">{z.n} {z.n === 1 ? 'Charge' : 'Chargen'}</span></td>
              <td className="zahl">{masse(z.eingang)}</td>
              <td className="zahl">{z.geliefert > 0 ? masse(z.geliefert) : <span className="leise">—</span>}</td>
              <td className="zahl">{z.lager > 0 ? masse(z.lager) : <span className="leise">—</span>}</td>
              <td className="zahl"><strong>{z.lager > 0 ? masse(z.vf) : '—'}</strong>
                {groessenText(z.klassen) && <span className="zelle-unter">{groessenText(z.klassen)}</span>}
                {z.luecke > 0 && <span className="zelle-unter">{z.luecke} {z.luecke === 1 ? 'Charge' : 'Chargen'} ohne Zahl</span>}</td>
            </tr>
          ))}</tbody>
          {zeilen.length > 1 && (
            <tfoot><tr>
              <th scope="row">Summe</th>
              <td className="zahl">{masse(summe(z => z.eingang))}</td>
              <td className="zahl">{masse(summe(z => z.geliefert))}</td>
              <td className="zahl">{masse(summe(z => z.lager))}</td>
              <td className="zahl"><strong>{masse(summe(z => z.vf))}</strong>
                {groessenText(summeKlassen) && <span className="zelle-unter">{groessenText(summeKlassen)}</span>}</td>
            </tr></tfoot>
          )}
        </table>
      </div>
      <Erklaerung titel="Wie diese Zahlen entstehen">
        <p>Ein Artikel ist hier die Artikelgruppe mit dem Label der Charge — „Knirps · Demeter" sind alle Demeter-Chargen, deren Sorte als
        Knirps verkauft wird. <strong>Eingang</strong> und <strong>ausgeliefert</strong> sind gewogen bzw. vom Lieferschein <Herkunft art="gemessen" />,
        <strong> im Lager</strong> ist die Eingangsware, die noch nicht ausgeliefert ist, und <strong>verkaufsfähig</strong> das, was davon nach
        Verdunstung, Palox und zu klein/zu gross bleibt <Herkunft art="gerechnet" /> — dieselben Zahlen wie im Lagermanagement nach Charge.</p>
        <p>Der graue Teil eines Balkens ist die Eingangsware hinter den Lieferungen: etwas mehr als geliefert, weil unterwegs verdunstet, im Palox
        gelandet oder aussortiert. Das Blaue ist nach der Sortier-CSV der Chargen auf klein und gross geteilt (Kaliber der Coop-Artikeldaten);
        Eingang und ausgeliefert gibt es nur je Artikelgruppe, nicht je Grösse — beim Eingang ist noch nichts sortiert.</p>
      </Erklaerung>
    </Karte>
  )
}

const quelleText = (q: string) =>
  q === 'Perigon' ? 'aus Perigon' : q === 'Produzent' ? 'vom Produzenten' : q === 'angenommen' ? 'angenommen (Knospe)'
    : q === 'Stammdaten' ? 'aus den Stammdaten' : 'unbekannt'

/** Die Chargen hinter einer Zahl — der „Dropdown", den der Betrieb wollte. */
function Chargenliste({ chargen, labelVon, chargeVon, mitGroesse }: {
  chargen: Chargenteil[]; labelVon: Map<number, ChargeLabel>; chargeVon: Map<number, Bestand>; mitGroesse: boolean
}) {
  return (
    <div className="rollbar">
      {/* Vier Spalten — auf dem Handy bleibt so das Kilo im Bild: Sorte und
          Feld stehen unter der Nummer, die Herkunft des Labels darunter. */}
      <table className="dicht chargenliste">
        <thead><tr>
          <th>Charge</th><th>Label</th>
          <th className="zahl">verkaufsfähig<Herkunft art="gerechnet" /></th>
          <th className="zahl">≈ Stück</th>
        </tr></thead>
        <tbody>{chargen.map(c => {
          const l = labelVon.get(c.charge_nr)
          const feld = chargeVon.get(c.charge_nr)?.schlag
          return (
            <tr key={c.charge_nr}>
              <td><Link to={`/chargen?charge=${c.charge_nr}`}>{c.charge_nr}</Link>
                <span className="zelle-unter">{c.sorte}{feld ? ` · ${feld}` : ''}</span></td>
              <td>{labelName(c.label)}
                {l?.quelle && <span className="zelle-unter">{quelleText(l.quelle)}</span>}
                {(l?.n_widerspruch ?? 0) > 0 && <Marke art="warnung">als Demeter verkauft, als Knospe geliefert</Marke>}</td>
              <td className="zahl">{kg(c.kg, 0)}
                {mitGroesse && <span className="zelle-unter">{KLASSEN.filter(k => c.klassen.has(k)).map(klasseName).join(', ')}</span>}</td>
              <td className="zahl">{c.stueck != null ? zahl(Math.round(c.stueck)) : '—'}</td>
            </tr>
          )
        })}</tbody>
      </table>
    </div>
  )
}

const masse = (v: number | null | undefined) =>
  v === null || v === undefined ? '—' : Math.abs(v) >= 1000 ? tonnen(v) : kg(v, 0)

/* ---------- 2. Wie ist es gegangen? ------------------------------------------ */

/** Die Saison läuft vom 1. Juli bis zum 30. Juni (wie saison_von, 0112). */
const saisonVon = (d: string) => { const j = Number(d.slice(0, 4)), m = Number(d.slice(5, 7)); return m >= 7 ? j : j - 1 }
const saisonTag = (d: string, saison: number) => Math.round((Date.parse(d) - Date.UTC(saison, 6, 1)) / TAG)
const saisonText = (s: number) => `${s}/${String(s + 1).slice(2)}`
const tagText = (saison: number) => (t: number) => {
  const d = new Date(Date.UTC(saison, 6, 1) + t * TAG)
  return `${d.getUTCDate()}.${d.getUTCMonth() + 1}.`
}

interface Kurve {
  kunde: string
  /** je Saison die kumulierte Menge über den Saisontagen. */
  saisons: Map<number, { tag: number; kum: number }[]>
  summe: Map<number, number>
  bisHeute: Map<number, number>
}

/** Aus Lieferungen (schon gefiltert) die kumulierte Kurve je Saison. */
function kurveAus(kunde: string, zeilen: KundeTag[], saison: number, tagHeute: number): Kurve {
  const jeSaison = new Map<number, Map<number, number>>()
  for (const k of zeilen) {
    const tage = jeSaison.get(k.saison) ?? new Map<number, number>()
    const t = saisonTag(k.datum, k.saison)
    tage.set(t, (tage.get(t) ?? 0) + Number(k.kg))
    jeSaison.set(k.saison, tage)
  }
  const saisons = new Map<number, { tag: number; kum: number }[]>()
  const summe = new Map<number, number>(), bisHeute = new Map<number, number>()
  for (const [s, tage] of jeSaison) {
    let kum = 0, kumHeute = 0
    const punkte = [{ tag: 0, kum: 0 }]
    for (const [t, kgTag] of [...tage.entries()].sort((a, b) => a[0] - b[0])) {
      kum += kgTag; punkte.push({ tag: t, kum })
      if (t <= tagHeute) kumHeute = kum
    }
    // Die Vorjahre laufen bis zum Saisonende weiter — „die vergangene Zukunft".
    if (s < saison) punkte.push({ tag: 364, kum })
    saisons.set(s, punkte); summe.set(s, kum); bisHeute.set(s, kumHeute)
  }
  return { kunde, saisons, summe, bisHeute }
}

function useVerkauf(kunden: KundeTag[], heute: string, wahl: Wahl) {
  const saison = saisonVon(heute)
  const tagHeute = saisonTag(heute, saison)
  const passend = useMemo(() => kunden.filter(k => k.saison >= saison - 2 && k.saison <= saison
    && passtGruppe(wahl, k.gruppe) && passtLabel(wahl, k.label) && passtVerkauf(wahl, k.groesse)), [kunden, wahl, saison])
  const alle = useMemo(() => kurveAus('alle Kunden', passend, saison, tagHeute), [passend, saison, tagHeute])
  const jeKunde = useMemo(() => {
    const m = new Map<string, KundeTag[]>()
    for (const k of passend) m.set(k.kunde, [...(m.get(k.kunde) ?? []), k])
    return [...m.entries()].map(([kunde, z]) => kurveAus(kunde, z, saison, tagHeute))
      .sort((a, b) => Math.max(b.summe.get(saison - 1) ?? 0, b.summe.get(saison) ?? 0)
                    - Math.max(a.summe.get(saison - 1) ?? 0, a.summe.get(saison) ?? 0))
  }, [passend, saison, tagHeute])
  return { saison, tagHeute, alle, jeKunde, mitVorjahr: kunden.some(k => k.saison < saison) }
}

function VerkauftKennzahl({ kunden, heute, wahl }: { kunden: KundeTag[]; heute: string; wahl: Wahl }) {
  const { saison, alle } = useVerkauf(kunden, heute, wahl)
  const jetzt = alle.bisHeute.get(saison) ?? 0
  const vorjahr = alle.bisHeute.get(saison - 1) ?? 0
  return (
    <Kennzahl titel={<>ausgeliefert {saisonText(saison)} bis heute <Herkunft art="gemessen" /></>} id="kz-artikel-verkauft"
              wert={tonnen(jetzt)}
              unter={vorjahr > 0
                ? <>Vorjahr bis heute {tonnen(vorjahr)} · {jetzt >= vorjahr ? '+' : '−'}{prozent(Math.abs(jetzt / vorjahr - 1), 0)}</>
                : <>kein Vorjahr zum Vergleich</>} />
  )
}

function Verlauf({ kunden, heute, wahl }: { kunden: KundeTag[]; heute: string; wahl: Wahl }) {
  const [kunde, setKunde] = useState('')
  const { saison, tagHeute, alle, jeKunde, mitVorjahr } = useVerkauf(kunden, heute, wahl)
  const gewaehlt = kunde ? jeKunde.find(k => k.kunde === kunde) : alle
  const leer = jeKunde.length === 0

  return (
    <Karte id="artikel-verlauf" titel={<>Wie ist es gegangen? {wahlName(wahl)}</>}
           aktion={<span className="reihe filter-klein">
             <select id="artikel-kunde" value={kunde} onChange={e => setKunde(e.target.value)} aria-label="Kunde">
               <option value="">alle Kunden</option>
               {jeKunde.map(k => <option key={k.kunde} value={k.kunde}>{k.kunde}</option>)}
               {kunde && !jeKunde.some(k => k.kunde === kunde) && <option value={kunde}>{kunde}</option>}
             </select>
           </span>}>
      {leer
        ? <Leer titel={kunden.length === 0 ? 'Noch kein Warenausgang' : `Keine Lieferung: ${wahlName(wahl)}`}>
            {kunden.length === 0 ? 'Sobald die Perigon-Dateien eingelesen sind, steht hier je Kunde die Saison.' : 'Oben einen anderen Artikel, eine andere Grösse oder ein anderes Label wählen.'}
          </Leer>
        : (
        <>
          {!mitVorjahr && (
            <Hinweis art="info">Die Vorjahre fehlen noch: Sie kommen aus denselben Perigon-Dateien — einmal neu einlesen unter{' '}
              <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link>, dann stehen die zwei Saisons davor gestrichelt daneben.</Hinweis>
          )}
          {gewaehlt
            ? <Linien reihen={kurvenReihen(gewaehlt, saison)} hoehe={440} zoom={false}
                      xVon={0} xBis={364} yVon={0} xKalender={Date.UTC(saison, 6, 1)}
                      xFormat={tagText(saison)} yFormat={tonnenAchse} xTitel={`Saison ${saisonText(saison)}`}
                      yTitel={`geliefert, kumuliert — ${kunde || 'alle Kunden'}`} yEinheit="kg"
                      heute={{ x: tagHeute, text: 'heute', rechts: '' }} leer="keine Lieferung"
                      fuss={<span className="leise">Ausgezogen diese Saison bis heute, gestrichelt die Vorjahre bis zum Saisonende — was nach heute noch kam.</span>} />
            : <Leer titel={`${kunde}: keine Lieferung`}>{kunde} hat {wahlName(wahl)} in den letzten drei Saisons nicht bekommen.</Leer>}
          <div className="rollbar">
            <table className="dicht kundentabelle">
              <thead><tr>
                <th>Kunde</th>
                {/* Zweizeilig: einzeilig lief die Tabelle schon am Bildschirm im Büro über den Rand. */}
                <th className="zahl">geliefert{' '}<br />{saisonText(saison)} bis heute<Herkunft art="gemessen" /></th>
                <th className="zahl">geliefert{' '}<br />{saisonText(saison - 1)} bis {datum(heute).slice(0, 6)}<Herkunft art="gemessen" /></th>
                <th className="zahl">geliefert{' '}<br />{saisonText(saison - 1)} ganze Saison<Herkunft art="gemessen" /></th>
                <th>schon erreicht</th>
              </tr></thead>
              <tbody>{jeKunde.map(k => {
                const jetzt = k.bisHeute.get(saison) ?? 0
                const vorjahrBis = k.bisHeute.get(saison - 1) ?? 0
                const vorjahrGanz = k.summe.get(saison - 1) ?? 0
                const erreicht = vorjahrGanz > 0 ? jetzt / vorjahrGanz : null
                const aktiv = k.kunde === kunde
                return (
                  <tr key={k.kunde} className={`klickbar${aktiv ? ' aktiv' : ''}`} aria-selected={aktiv}
                      onClick={() => setKunde(aktiv ? '' : k.kunde)} title={aktiv ? 'wieder alle Kunden zeigen' : 'im Diagramm zeigen'}>
                    <td>{k.kunde}</td>
                    <td className="zahl"><strong>{masse(jetzt)}</strong></td>
                    <td className="zahl">{vorjahrBis > 0 ? masse(vorjahrBis) : '—'}
                      {vorjahrBis > 0 && jetzt > 0 && <span className="leise"> · {jetzt >= vorjahrBis ? '+' : '−'}{prozent(Math.abs(jetzt / vorjahrBis - 1), 0)}</span>}</td>
                    <td className="zahl">{vorjahrGanz > 0 ? masse(vorjahrGanz) : '—'}</td>
                    <td className="erreicht">{erreicht === null ? <span className="leise">kein Vorjahr</span> : (
                      <span className="erreicht-balken" title={`${prozent(erreicht, 0)} der ganzen Vorjahressaison`}>
                        <span style={{ width: `${Math.min(erreicht, 1) * 100}%` }} className={erreicht >= 1 ? 'voll' : erreicht >= 0.8 ? 'fast' : ''} />
                        <em>{prozent(erreicht, 0)}</em>
                      </span>)}</td>
                  </tr>
                )
              })}</tbody>
            </table>
          </div>
        </>
      )}
      <Erklaerung>
        <p>Die Kürbis-Lieferungen der Perigon-Dateien <Herkunft art="gemessen" />, kumuliert über die Saison vom 1. Juli bis zum
        30. Juni — für den Artikel, die Grösse und das Label oben, so wie der Artikel verkauft wurde (lose verkaufte Ware zählt nur
        bei „beide Grössen"). Die laufende Saison endet heute; die Vorjahre laufen gestrichelt bis zum Saisonende weiter — so sieht
        man, was im Vorjahr nach heute noch kam.</p>
        <p>Ein Klick auf einen Kunden zeigt nur ihn im Diagramm, ein zweiter wieder alle. „Schon erreicht" ist diese Saison bis heute
        geteilt durch die ganze Vorjahressaison: Wer bei 100 % steht, hat schon so viel wie im ganzen letzten Jahr. Kunden sind die
        Lieferadressen der Datei — zwei Adressen derselben Kette stehen getrennt. Interne Umbuchungen (Journal L) zählen nicht.</p>
      </Erklaerung>
    </Karte>
  )
}

function kurvenReihen(k: Kurve, saison: number): Reihe[] {
  const r: Reihe[] = []
  const farben: Record<number, [string, boolean]> = {
    [saison]: ['var(--blau)', false], [saison - 1]: ['var(--text-2)', true], [saison - 2]: ['var(--text-leise)', true],
  }
  for (const s of [saison, saison - 1, saison - 2]) {
    const p = k.saisons.get(s)
    if (!p || p.length < 2) continue
    r.push({ name: saisonText(s), farbe: farben[s][0], linie: true, marker: false, gestrichelt: farben[s][1], dick: s === saison,
             punkte: p.map(x => ({ x: x.tag, y: x.kum })) })
  }
  return r
}
