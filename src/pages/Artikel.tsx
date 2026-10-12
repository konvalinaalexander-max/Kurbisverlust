import { Fragment, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { fehlerText } from '../lib/db'
import { Erklaerung, Herkunft, Hinweis, Karte, Kennzahl, Leer, Marke } from '../components/Bausteine'
import { Linien, tonnenAchse, type Reihe } from '../components/Diagramm'
import { artikelGrundlagen, artikelLagerBei, useAuswertung, useStichtag,
         type ArtikelKaliber, type ArtikelLager, type Bestand, type ChargeLabel, type KundeTag, type SorteGruppe } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { WochenFeld } from '../components/WochenFeld'
import { ZChevron } from '../components/Zeichen'

const TAG = 86400000

/**
 * Lagermanagement nach Artikel — der zweite Lagerreiter (Runde AO, 12. Oktober).
 *
 *   „Die Chargen sind wichtig — agronomisch. Aber im Verkauf denken wir nach
 *    Artikeln. Coop will nicht wissen, ob es ein Hokkaido in diesem Kaliber
 *    ist, sondern: gross oder klein. Und dann Demeter oder Knospe. … Wie
 *    stehen wir im Verhältnis zum letzten Jahr?"
 *
 * Zwei Fragen, zwei Karten:
 *   1. Was ist noch da, je Artikel? Die Chargen zusammengezählt nach
 *      Artikelgruppe (aus der Sorte) und Label (Demeter/Knospe); das
 *      Verkaufsfähige am Stichtag nach den Kalibern des Artikels geteilt
 *      (artikel_lager, 0112) — mit Stück und Kisten.
 *   2. Wie steht jeder Kunde gegen die Vorjahre? Kumuliert über die Saison
 *      (1. Juli bis 30. Juni), diese Saison bis heute, die Vorjahre
 *      gestrichelt über die ganze Saison — „die vergangene Zukunft".
 *
 * Nichts davon ist eine zweite Rechnung: Eingang, ausgeliefert, Lager und
 * verkaufsfähig sind die Zahlen der Chargen, nur anders zusammengezählt.
 */

const GRUPPEN_FOLGE = ['Knirps', 'Butternut', 'Butterkin/Muskat', 'Kabocha', 'Mandarin']
const gruppeName = (g: string | null) =>
  g === null ? 'Artikelgruppe unbekannt' : g === 'Knirps' ? 'Knirps (Hokkaido)' : g
const labelName = (l: string | null) => l === 'D' ? 'Demeter' : l === 'K' ? 'Knospe' : 'Label unbekannt'
const rang = (g: string | null) => { const i = g === null ? -1 : GRUPPEN_FOLGE.indexOf(g); return i < 0 ? 99 : i }

interface Grundlagen { labels: ChargeLabel[]; gruppen: SorteGruppe[]; kaliber: ArtikelKaliber[]; kunden: KundeTag[] }

export default function Artikel() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const [wochen, setWochen] = useState(0)
  const lager = useStichtag(artikelLagerBei, 7 * wochen)
  const [grund, setGrund] = useState<Grundlagen | null>(null)
  const [grundFehler, setGrundFehler] = useState<string | null>(null)
  useEffect(() => {
    let gilt = true
    artikelGrundlagen()
      .then(g => { if (gilt) setGrund(g) })
      .catch((f: unknown) => { if (gilt) setGrundFehler(fehlerText(f)) })
    return () => { gilt = false }
  }, [])

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
          <ArtikelBestand bestand={daten.bestand} grund={grund} lager={lager.zeilen} laedt={lager.laedt}
                          lagerFehler={lager.fehler} wochen={wochen} setzeWochen={setWochen} />
          <Kunden kunden={grund.kunden} heute={daten.heute} gruppen={[...new Set(grund.gruppen.map(g => g.artikelgruppe).filter(Boolean))] as string[]} />
        </>
      )}
      {!grund && !grundFehler && <Rechnet fortschritt={null} />}
    </>
  )
}

/* ---------- 1. Was ist noch da, je Artikel? -------------------------------- */

interface Artikelzeile {
  schluessel: string; gruppe: string | null; label: 'D' | 'K' | null
  chargen: Bestand[]
  eingang: number; geliefert: number; lager: number
  /** Die Teile des Verkaufsfähigen am Stichtag, nach Grösse. */
  teile: Map<string, ArtikelLager>
  verkaufsfaehig: number
}

function ArtikelBestand({ bestand, grund, lager, laedt, lagerFehler, wochen, setzeWochen }: {
  bestand: Bestand[]; grund: Grundlagen; lager: ArtikelLager[]; laedt: boolean; lagerFehler: string | null
  wochen: number; setzeWochen: (n: number) => void
}) {
  const [auf, setAuf] = useState<Set<string>>(new Set())
  const gruppeVon = useMemo(() => new Map(grund.gruppen.map(g => [g.sorte, g])), [grund.gruppen])
  const labelVon = useMemo(() => new Map(grund.labels.map(l => [l.charge_nr, l])), [grund.labels])
  const zeilen = useMemo(() => {
    const m = new Map<string, Artikelzeile>()
    const zeile = (gruppe: string | null, label: 'D' | 'K' | null) => {
      const k = `${gruppe ?? ''}|${label ?? ''}`
      let z = m.get(k)
      if (!z) { z = { schluessel: k, gruppe, label, chargen: [], eingang: 0, geliefert: 0, lager: 0, teile: new Map(), verkaufsfaehig: 0 }; m.set(k, z) }
      return z
    }
    for (const b of bestand) {
      const z = zeile(gruppeVon.get(b.sorte)?.artikelgruppe ?? null, labelVon.get(b.charge_nr)?.label ?? null)
      z.chargen.push(b); z.eingang += b.eingang_kg; z.geliefert += b.geliefert_kg; z.lager += b.lager_kg
    }
    for (const a of lager) {
      const z = zeile(a.artikelgruppe, a.label)
      z.teile.set(a.groesse, a); z.verkaufsfaehig += a.kg
    }
    return [...m.values()].sort((a, b) => rang(a.gruppe) - rang(b.gruppe) || (a.gruppe ?? '').localeCompare(b.gruppe ?? '')
                                          || (a.label ?? 'Z').localeCompare(b.label ?? 'Z'))
  }, [bestand, lager, gruppeVon, labelVon])
  const stichtag = lager[0]?.datum ?? null
  const spaeter = wochen > 0
  const summe = (f: (z: Artikelzeile) => number) => zeilen.reduce((a, z) => a + f(z), 0)
  const gesamt = summe(z => z.verkaufsfaehig)
  const jeLabel = (l: 'D' | 'K' | null) => zeilen.filter(z => z.label === l).reduce((a, z) => a + z.verkaufsfaehig, 0)
  const ohneLabel = bestand.filter(b => b.lager_kg > 0 && !labelVon.get(b.charge_nr)?.label)
  const ohneGruppe = [...new Set(bestand.filter(b => b.lager_kg > 0 && !gruppeVon.get(b.sorte)?.artikelgruppe).map(b => b.sorte))]
  const umschalten = (k: string) => setAuf(a => { const n = new Set(a); if (n.has(k)) n.delete(k); else n.add(k); return n })
  const herkunft = spaeter ? 'prognose' : 'gerechnet'

  return (
    <>
      <div className="kennzahl-reihe">
        <Kennzahl titel={<>Verkaufsfähig {spaeter ? `in ${wochen} Wochen` : 'im Lager'} <Herkunft art={herkunft} /></>} ton="gruen" id="kz-artikel-gesamt"
                  wert={tonnen(gesamt)} unter={<>{zeilen.filter(z => z.verkaufsfaehig > 0).length} Artikel · {spaeter && stichtag ? `am ${datum(stichtag).slice(0, 6)}` : 'heute'}</>} />
        <Kennzahl titel={<>davon Demeter <Herkunft art={herkunft} /></>} id="kz-artikel-d" wert={tonnen(jeLabel('D'))}
                  unter={<>{gesamt > 0 ? prozent(jeLabel('D') / gesamt, 0) : '—'} des Verkaufsfähigen</>} />
        <Kennzahl titel={<>davon Knospe <Herkunft art={herkunft} /></>} id="kz-artikel-k" wert={tonnen(jeLabel('K'))}
                  unter={<>{gesamt > 0 ? prozent(jeLabel('K') / gesamt, 0) : '—'} · Demeter darf als Knospe gehen, nicht umgekehrt</>} />
        {jeLabel(null) > 0.5 && (
          <Kennzahl titel={<>Label unbekannt <Herkunft art={herkunft} /></>} id="kz-artikel-unbekannt" wert={tonnen(jeLabel(null))}
                    unter={<>{ohneLabel.length} Chargen ohne Demeter/Knospe</>} />
        )}
      </div>

      {(ohneLabel.length > 0 || ohneGruppe.length > 0) && (
        <Hinweis art="info">
          {ohneLabel.length > 0 && <>Bei {ohneLabel.length} Chargen mit Ware ist Demeter/Knospe nicht bekannt ({ohneLabel.slice(0, 8).map(b => b.charge_nr).join(', ')}{ohneLabel.length > 8 ? ' …' : ''}).
            Es kommt aus der Perigon-Datei — einmal neu einlesen unter <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link> —
            oder aus den <Link to="/betrieb/stammdaten">Stammdaten → Chargen</Link>. </>}
          {ohneGruppe.length > 0 && <>Ohne Artikelgruppe: {ohneGruppe.join(', ')} — in den <Link to="/betrieb/stammdaten">Stammdaten → Sorten</Link> zuordnen.</>}
        </Hinweis>
      )}

      <Karte id="artikel-bestand" titel="Was ist noch da — je Artikel"
             aktion={<WochenFeld id="artikel-wochen" wochen={wochen} setzen={setzeWochen} datum={spaeter ? stichtag : null} />}>
        {lagerFehler && <Hinweis art="warnung">Das Lager je Artikel liess sich nicht laden: {lagerFehler}</Hinweis>}
        {zeilen.length === 0
          ? <Leer titel="Noch keine Charge">Sobald Ware eingelagert ist, steht hier, welcher Artikel daraus wird.</Leer>
          : (
          <div className="rollbar">
            <table className={`dicht umbruch lagertabelle artikeltabelle${laedt ? ' laedt' : ''}`}>
              <thead>
                <tr>
                  <th rowSpan={2} className="haftend">Artikel</th>
                  <th rowSpan={2} className="zahl">Eingang<Herkunft art="gemessen" /></th>
                  <th rowSpan={2} className="zahl">ausgeliefert<Herkunft art="gemessen" /></th>
                  <th rowSpan={2} className="zahl">im Lager<Herkunft art="gerechnet" /></th>
                  <th colSpan={5} className="gruppe">
                    verkaufsfähig {spaeter ? `in ${wochen} Wochen` : 'heute'}
                    {spaeter && stichtag ? <span className="leise"> · {datum(stichtag).slice(0, 6)}</span> : null}
                    <Herkunft art={herkunft} />
                  </th>
                </tr>
                <tr>
                  <th className="zahl">klein</th><th className="zahl">gross</th>
                  <th className="zahl" title="in keinem Kaliber des Artikels — lose verkäuflich">ausserhalb</th>
                  <th className="zahl" title="keine Sortier-CSV für diese Sorte: die Grösse ist unbekannt, nicht null">ohne Grösse</th>
                  <th className="zahl">gesamt</th>
                </tr>
              </thead>
              <tbody>
                {zeilen.map(z => {
                  const klein = z.teile.get('klein') ?? z.teile.get('stueck')
                  const gross = z.teile.get('gross')
                  const ausserhalb = ['darunter', 'darueber', 'dazwischen', 'lose'].reduce((a, g) => a + (z.teile.get(g)?.kg ?? 0), 0)
                  const ohne = z.teile.get('ohne Verteilung')?.kg ?? 0
                  const offen = auf.has(z.schluessel)
                  return (
                    <Fragment key={z.schluessel}>
                      <tr className={`klickbar${offen ? ' offen' : ''}`} onClick={() => umschalten(z.schluessel)} aria-expanded={offen}>
                        <th scope="row" className="haftend">
                          <span className="chevron" aria-hidden="true"><ZChevron size={14} /></span>
                          <span className="zeilenname">{gruppeName(z.gruppe)}</span>
                          <span className={`zeilenunter label-${z.label ?? 'x'}`}>{labelName(z.label)} · {z.chargen.length} {z.chargen.length === 1 ? 'Charge' : 'Chargen'}</span>
                        </th>
                        <td className="zahl">{masse(z.eingang)}</td>
                        <td className="zahl">{masse(z.geliefert)}</td>
                        <td className="zahl">{masse(z.lager)}</td>
                        <Teilzelle t={klein} />
                        <Teilzelle t={gross} />
                        <td className="zahl leise">{ausserhalb > 0.5 ? masse(ausserhalb) : '—'}</td>
                        <td className="zahl leise">{ohne > 0.5 ? masse(ohne) : '—'}</td>
                        <td className="zahl summe"><strong>{masse(z.verkaufsfaehig)}</strong>
                          <Anteilbalken teile={[klein?.kg ?? 0, gross?.kg ?? 0, ausserhalb, ohne]} />
                        </td>
                      </tr>
                      {offen && (
                        <tr className="artikel-chargen"><td colSpan={9}>
                          <table className="dicht">
                            <thead><tr><th>Charge</th><th>Sorte</th><th>Feld</th><th>Label</th><th className="zahl">Eingang</th><th className="zahl">im Lager</th><th className="zahl">verkaufsfähig heute</th></tr></thead>
                            <tbody>{[...z.chargen].sort((a, b) => b.lager_kg - a.lager_kg).map(c => {
                              const l = labelVon.get(c.charge_nr)
                              return (
                                <tr key={c.charge_nr}>
                                  <td><Link to={`/chargen?charge=${c.charge_nr}`}>{c.charge_nr}</Link></td>
                                  <td>{c.sorte}{gruppeVon.get(c.sorte)?.quelle === 'verkauft als' && <span className="leise"> · Gruppe aus den Verkäufen</span>}</td>
                                  <td>{c.schlag}</td>
                                  <td>{labelName(l?.label ?? null)}{l?.quelle && <span className="leise"> · {l.quelle}</span>}{l?.gemischt && <> <Marke art="warnung">D und K geliefert</Marke></>}</td>
                                  <td className="zahl">{kg(c.eingang_kg, 0)}</td>
                                  <td className="zahl">{c.lager_kg > 0 ? kg(c.lager_kg, 0) : '—'}</td>
                                  <td className="zahl">{c.verkaufsfaehig_lager_kg != null && c.lager_kg > 0 ? kg(c.verkaufsfaehig_lager_kg, 0) : '—'}</td>
                                </tr>
                              )
                            })}</tbody>
                          </table>
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
                    <td className="zahl"><strong>{masse(summe(z => z.eingang))}</strong></td>
                    <td className="zahl"><strong>{masse(summe(z => z.geliefert))}</strong></td>
                    <td className="zahl"><strong>{masse(summe(z => z.lager))}</strong></td>
                    <td className="zahl">{masse(summe(z => (z.teile.get('klein') ?? z.teile.get('stueck'))?.kg ?? 0))}</td>
                    <td className="zahl">{masse(summe(z => z.teile.get('gross')?.kg ?? 0))}</td>
                    <td className="zahl leise">{masse(summe(z => ['darunter', 'darueber', 'dazwischen', 'lose'].reduce((a, g) => a + (z.teile.get(g)?.kg ?? 0), 0)))}</td>
                    <td className="zahl leise">{masse(summe(z => z.teile.get('ohne Verteilung')?.kg ?? 0))}</td>
                    <td className="zahl summe"><strong>{masse(gesamt)}</strong></td>
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        )}
        <p className="hilfe">
          Klein und gross nach den Kalibern des Artikels (Coop 2026: {grund.kaliber.filter(k => k.groesse !== 'stueck').slice(0, 2).map(k => `${k.gruppe} ${k.groesse} ${zahl(k.von_g)}–${zahl(k.bis_g)} g`).join(', ')} …); Kisten zu {[...new Set(grund.kaliber.map(k => k.stueck_je_kiste).filter(Boolean))].sort().join(' bzw. ')} Stück.
        </p>
        <Erklaerung>
          <p><strong>Artikel</strong> heisst hier: Artikelgruppe × Label. Die Gruppe kommt aus der Sorte (Kaori Kuri, Amoro, … gehen als
          Knirps, Tiana und Mieluna als Butternut — so wurden sie 2026 verkauft; änderbar in den Stammdaten), das Label aus der Charge:
          Demeter oder Knospe, wie Perigon die Charge geliefert hat, oder wie es in den Stammdaten steht.</p>
          <p><strong>Eingang, ausgeliefert, im Lager</strong> sind die Zahlen der Chargen, zusammengezählt <Herkunft art="gemessen" />/<Herkunft art="gerechnet" />.
          <strong> Verkaufsfähig</strong> ist dieselbe Zahl wie im Lagermanagement nach Charge: je Charge, was nach Verdunstung, Palox und zu klein/zu gross
          bleibt. Geteilt wird es nach der Sortier-CSV der Charge (oder ihrer Sorte), jeder Kürbis um die gemessene Verdunstung bis zum
          Stichtag geschrumpft: Wiegt er so viel wie ein kleiner Artikel, zählt er klein, wie ein grosser, gross; dazwischen gibt es
          nichts, darunter oder darüber heisst <em>ausserhalb</em> — lose verkäuflich, nicht als Stück-Artikel. Stück = Kilo ÷ mittleres
          Gewicht der Klasse, Kisten = Stück ÷ Stück je Kiste.</p>
        </Erklaerung>
      </Karte>
    </>
  )
}

const masse = (v: number | null | undefined) =>
  v === null || v === undefined ? '—' : Math.abs(v) >= 1000 ? tonnen(v) : kg(v, 0)

function Teilzelle({ t }: { t: ArtikelLager | undefined }) {
  if (!t || t.kg < 0.5) return <td className="zahl leise">—</td>
  return (
    <td className="zahl" title={`${zahl(t.von_g)}–${zahl(t.bis_g)} g · im Mittel ${zahl(t.g_mittel)} g je Kürbis`}>
      {masse(t.kg)}
      {t.kisten != null && t.stueck_je_kiste != null
        ? <span className="zelle-unter">≈ {zahl(t.kisten)} Kisten à {t.stueck_je_kiste}</span>
        : t.stueck != null ? <span className="zelle-unter">≈ {zahl(t.stueck)} Stück</span> : null}
    </td>
  )
}

/** Ein dünner Balken unter der Summe: klein · gross · ausserhalb · ohne Grösse. */
function Anteilbalken({ teile }: { teile: number[] }) {
  const summe = teile.reduce((a, b) => a + b, 0)
  if (summe <= 0) return null
  const farben = ['var(--reihe-2)', 'var(--reihe-1)', 'var(--text-leise)', 'var(--flaeche-3, var(--rand))']
  return (
    <span className="mini-anteile artikel-balken" aria-hidden="true">
      {teile.map((t, i) => t > 0 ? <span key={i} style={{ width: `${(t / summe) * 100}%`, background: farben[i] }} /> : null)}
    </span>
  )
}

/* ---------- 2. Wie steht jeder Kunde gegen die Vorjahre? -------------------- */

/** Die Saison läuft vom 1. Juli bis zum 30. Juni (wie saison_von, 0112). */
const saisonVon = (d: string) => { const j = Number(d.slice(0, 4)), m = Number(d.slice(5, 7)); return m >= 7 ? j : j - 1 }
const saisonTag = (d: string, saison: number) => Math.round((Date.parse(d) - Date.UTC(saison, 6, 1)) / TAG)
const saisonText = (s: number) => `${s}/${String(s + 1).slice(2)}`
const tagText = (saison: number) => (t: number) => {
  const d = new Date(Date.UTC(saison, 6, 1) + t * TAG)
  return `${d.getUTCDate()}.${d.getUTCMonth() + 1}.`
}

interface Kundenkurve {
  kunde: string
  /** je Saison die kumulierte Menge über den Saisontagen. */
  saisons: Map<number, { tag: number; kum: number }[]>
  summe: Map<number, number>
  bisHeute: Map<number, number>
}

function Kunden({ kunden, heute, gruppen }: { kunden: KundeTag[]; heute: string; gruppen: string[] }) {
  const [gruppe, setGruppe] = useState('')
  const [label, setLabel] = useState('')
  const [alle, setAlle] = useState(false)
  const saison = saisonVon(heute)
  const tagHeute = saisonTag(heute, saison)
  const kurven = useMemo(() => {
    const m = new Map<string, Map<number, Map<number, number>>>()
    for (const k of kunden) {
      if (gruppe && k.gruppe !== gruppe) continue
      if (label && k.label !== label) continue
      if (k.saison < saison - 2 || k.saison > saison) continue
      const jeSaison = m.get(k.kunde) ?? new Map<number, Map<number, number>>()
      const tage = jeSaison.get(k.saison) ?? new Map<number, number>()
      const t = saisonTag(k.datum, k.saison)
      tage.set(t, (tage.get(t) ?? 0) + Number(k.kg))
      jeSaison.set(k.saison, tage); m.set(k.kunde, jeSaison)
    }
    const aus: Kundenkurve[] = []
    for (const [kunde, jeSaison] of m) {
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
      aus.push({ kunde, saisons, summe, bisHeute })
    }
    return aus.sort((a, b) => Math.max(b.summe.get(saison - 1) ?? 0, b.summe.get(saison) ?? 0)
                            - Math.max(a.summe.get(saison - 1) ?? 0, a.summe.get(saison) ?? 0))
  }, [kunden, gruppe, label, saison, tagHeute])
  const mitVorjahr = kunden.some(k => k.saison < saison)
  const gezeigt = alle ? kurven : kurven.slice(0, 6)

  return (
    <Karte id="artikel-kunden" titel="Kunden: diese Saison gegen die Vorjahre"
           aktion={<span className="reihe filter-klein">
             <select value={gruppe} onChange={e => setGruppe(e.target.value)} aria-label="Artikelgruppe">
               <option value="">alle Artikel</option>
               {gruppen.sort((a, b) => rang(a) - rang(b)).map(g => <option key={g} value={g}>{gruppeName(g)}</option>)}
             </select>
             <select value={label} onChange={e => setLabel(e.target.value)} aria-label="Label">
               <option value="">Demeter und Knospe</option><option value="D">nur Demeter</option><option value="K">nur Knospe</option>
             </select>
           </span>}>
      {kurven.length === 0
        ? <Leer titel="Noch kein Warenausgang">Sobald die Perigon-Dateien eingelesen sind, steht hier je Kunde die Saison.</Leer>
        : (
        <>
          {!mitVorjahr && (
            <Hinweis art="info">Die Vorjahre fehlen noch: Sie kommen aus denselben Perigon-Dateien — einmal neu einlesen unter{' '}
              <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link>, dann stehen 2024/25 und 2025/26 gestrichelt daneben.</Hinweis>
          )}
          <div className="rollbar">
            <table className="dicht kundentabelle">
              <thead><tr>
                <th>Kunde</th>
                <th className="zahl">geliefert {saisonText(saison)} bis heute<Herkunft art="gemessen" /></th>
                <th className="zahl">geliefert {saisonText(saison - 1)} bis {datum(heute).slice(0, 6)}<Herkunft art="gemessen" /></th>
                <th className="zahl">geliefert {saisonText(saison - 1)} ganze Saison<Herkunft art="gemessen" /></th>
                <th>schon erreicht</th>
              </tr></thead>
              <tbody>{kurven.map(k => {
                const jetzt = k.bisHeute.get(saison) ?? 0
                const vorjahrBis = k.bisHeute.get(saison - 1) ?? 0
                const vorjahrGanz = k.summe.get(saison - 1) ?? 0
                const erreicht = vorjahrGanz > 0 ? jetzt / vorjahrGanz : null
                return (
                  <tr key={k.kunde}>
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
          <div className="kunden-gitter">
            {gezeigt.map(k => (
              <div key={k.kunde} className="kunde-bild">
                <h3>{k.kunde}</h3>
                <Linien reihen={kundenReihen(k, saison)} hoehe={190} kompakt zoom={false}
                        xVon={0} xBis={364} yVon={0}
                        xFormat={tagText(saison)} yFormat={tonnenAchse} xTitel="Saisontag" yTitel="geliefert, kumuliert" yEinheit="kg"
                        heute={{ x: tagHeute, text: 'heute', rechts: '' }} leer="keine Lieferung" />
              </div>
            ))}
          </div>
          {kurven.length > 6 && (
            <button type="button" className="werkzeug-knopf" onClick={() => setAlle(a => !a)}>
              {alle ? 'nur die sechs grössten zeigen' : `alle ${kurven.length} Kunden zeigen`}
            </button>
          )}
        </>
      )}
      <Erklaerung>
        <p>Je Kunde die Kürbis-Lieferungen der Perigon-Dateien <Herkunft art="gemessen" />, kumuliert über die Saison vom 1. Juli bis zum
        30. Juni. Die laufende Saison endet heute; die Vorjahre laufen gestrichelt bis zum Saisonende weiter — so sieht man, was im
        Vorjahr nach heute noch kam. „Schon erreicht" ist diese Saison bis heute geteilt durch die ganze Vorjahressaison: Wer bei 100 %
        steht, hat schon so viel wie im ganzen letzten Jahr.</p>
        <p>Kunden sind die Lieferadressen der Datei — zwei Adressen derselben Kette stehen getrennt. Interne Umbuchungen (Journal L)
        zählen nicht. Mit den Filtern oben nur eine Artikelgruppe oder nur Demeter bzw. Knospe — so, wie der Artikel verkauft wurde.</p>
      </Erklaerung>
    </Karte>
  )
}

function kundenReihen(k: Kundenkurve, saison: number): Reihe[] {
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
