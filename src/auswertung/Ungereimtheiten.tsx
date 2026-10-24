/**
 * Ungereimtheiten zwischen Perigon und Lager (0121) — je Charge in der
 * aufgeklappten Zeile, und seit 0126 ganz im Reiter Perigon. Je Sache, was
 * komisch ist, warum es das Lager verfälscht und was zu tun ist — mit den
 * Perigon-Zeilen dazu, die im Fenster ihre falschen Zellen rot zeigen.
 *
 * 0126: Oben auf den Lagerseiten steht statt der grossen Leiste ein schmaler
 * Verweis (PerigonVerweis) — der Betrieb: „nicht oberhalb von Artikel etc.,
 * sondern mach einen neuen Reiter".
 */
import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { FallVerfolgen } from './Verfolgen'
import { sacheSchnappschuss } from './perigon'
import { faelleBilden, fallOffen } from './faelle'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg, tonnen } from '../lib/format'
import { useAuth } from '../auth/AuthProvider'
import { ZChevron, ZWarnung } from '../components/Zeichen'
import { LieferungFenster } from '../betrieb/LieferungFenster'
import type { Auswertung, ChargeSpur, PerigonBefund, PerigonVerlauf } from './daten'
import { ART_NAME, spurText, ungereimtheiten, vonCharge, type Ungereimtheit } from './ungereimt'
import { OhneChargeListe } from './OhneCharge'
import { PerigonBelege } from './Belege'

/**
 * 0126: Oben auf Lager nach Charge, nach Artikel und Chargen — eine Zeile:
 * wie viele Stellen offen sind und wie viel es betrifft, und der Weg in den
 * Reiter Perigon. Was der Betriebsleiter als erledigt oder „kein Fehler"
 * vermerkt hat, zählt nicht mehr. Runde BF: gezählt werden Fälle wie im
 * Reiter (alles zu einer Charge ist einer), nicht Zeilen.
 */
export function PerigonVerweis({ daten }: { daten: Auswertung }) {
  const stand = useMemo(() => new Map(daten.faelleStand.map(v => [v.schluessel, { schluessel: v.schluessel, stand: v.stand } as PerigonVerlauf])), [daten.faelleStand])
  const faelle = useMemo(() => faelleBilden(daten.perigon, ungereimtheiten(daten.ungereimt), daten.spur), [daten.perigon, daten.ungereimt, daten.spur])
  const offen = faelle.filter(f => fallOffen(f, stand))
  const n = offen.length
  if (n === 0) return null
  const rot = offen.some(f => f.schwere === 'rot')
  const gross = offen.filter(f => f.schwere === 'rot').length
  return (
    <Link to="/perigon" className={`perigon-verweis ${rot ? 'u-rot' : 'u-gelb'}`} id="ungereimt">
      <span className="ungereimt-zeichen" aria-hidden="true"><ZWarnung size={16} /></span>
      <span><strong>Perigon und Lager: {n} {n === 1 ? 'Fall' : 'Fälle'} offen</strong>
        {gross > 0 && <span> · {gross} davon gross</span>}</span>
      <span className="perigon-verweis-weg">im Reiter Perigon ansehen →</span>
    </Link>
  )
}

export function Ungereimtheiten({ daten, charge, startOffen = false }: { daten: Auswertung; charge?: number; startOffen?: boolean }) {
  // 0126: je Charge nur ihre eigenen Perigon-Zeilen — sonst stünden in der Sache die Zeilen aller Chargen derselben Art
  const alle = useMemo(() => ungereimtheiten(daten.ungereimt, charge != null ? daten.perigon.filter(p => p.charge_nr === charge) : daten.perigon),
    [daten.ungereimt, daten.perigon, charge])
  const liste = charge != null ? vonCharge(alle, charge) : alle
  const spur = useMemo(() => new Map(daten.spur.map(s => [s.charge_nr, s])), [daten.spur])
  const [offen, setOffen] = useState(startOffen || charge != null)
  if (liste.length === 0) return null
  const ernst = liste.filter(u => u.schwere !== 'info')
  const kgErnst = ernst.reduce((a, u) => a + (u.kg ?? 0), 0)
  const arten = new Map<string, number>()
  for (const u of liste) arten.set(u.art, (arten.get(u.art) ?? 0) + 1)
  const titel = charge != null
    ? `Bei Charge ${charge} passen Perigon und Lager nicht zusammen`
    : ernst.length > 0
      ? `Perigon und Lager passen an ${ernst.length} ${ernst.length === 1 ? 'Stelle' : 'Stellen'} nicht zusammen`
      : 'Die App hat Paletten mit Beleg umgebucht'
  return (
    <section className={`ungereimt ${ernst.some(u => u.schwere === 'rot') ? 'u-rot' : ernst.length ? 'u-gelb' : 'u-info'}`} id={charge != null ? undefined : 'ungereimt'}>
      <button type="button" className="ungereimt-kopf" onClick={() => setOffen(o => !o)} aria-expanded={offen}>
        <span className="ungereimt-zeichen" aria-hidden="true"><ZWarnung size={18} /></span>
        <span className="ungereimt-titel">
          <strong>{titel}</strong>
          {kgErnst > 0 && <span> · betrifft {tonnen(kgErnst)}</span>}
          {charge == null && (
            <span className="ungereimt-chips">
              {[...arten.entries()].map(([art, n]) => <span key={art} className="ungereimt-chip">{n} × {ART_NAME[art] ?? art}</span>)}
            </span>
          )}
        </span>
        <span className="chevron" aria-hidden="true" style={{ transform: offen ? 'rotate(90deg)' : undefined }}><ZChevron size={16} /></span>
      </button>
      {offen && (
        <div className="ungereimt-liste">
          {charge == null && <p className="leise oben-0">Die App rechnet je Charge: was laut Erntejournal kam, minus was laut Perigon-Lieferschein
            mit dieser Nummer hinausging. Wo Nummer oder Sorte nicht stimmen, steht Ware im Lager, die verkauft ist — oder es fehlt welche.
            Unter jeder Sache steht der Weg der Ware: herein, bearbeitet, hinaus. Das Schwerste zuerst.</p>}
          {liste.map(u => <Sache key={u.schluessel} u={u} inCharge={charge} spur={spur} />)}
          {charge != null && <p className="unten-0"><Link to={`/perigon/faelle?charge=${charge}&stand=alle`}>Alle Perigon-Fälle von Charge {charge} im Reiter Perigon →</Link></p>}
        </div>
      )}
    </section>
  )
}

/**
 * 0122: Der Weg der Ware je beteiligter Charge — herein laut Erntejournal,
 * bearbeitet in der Halle, hinaus laut Perigon, und was laut App noch da ist.
 */
export function WegDerWare({ nrn, spur }: { nrn: number[]; spur: Map<number, ChargeSpur> }) {
  const zeilen = [...new Set(nrn)].map(nr => spur.get(nr)).filter((z): z is ChargeSpur => z !== undefined).map(spurText)
  if (zeilen.length === 0) return null
  // data-titel: auf dem Handy steht jede Zeile als Block, die Station davor (index.css)
  const zelle = (titel: string, t: string[], leer = false) => (
    <td className={leer ? 'spur-leer' : undefined} data-titel={titel}>
      <div>{t.map((x, i) => <div key={i} className={i === 0 ? undefined : 'leise'}>{x}</div>)}</div>
    </td>)
  return (
    <div className="spur">
      <table className="spur-tabelle ohne-haftkopf">
        <caption>Der Weg der Ware</caption>
        <thead><tr><th scope="col">Charge</th><th scope="col">Herein · Erntejournal</th><th scope="col">Bearbeitet · Halle</th><th scope="col">Hinaus · Perigon</th><th scope="col">Laut App noch da</th></tr></thead>
        <tbody>
          {zeilen.map(z => (
            <tr key={z.charge}>
              <th scope="row">{z.charge}</th>
              {zelle('Herein', z.herein, z.ohneEingang)}{zelle('Bearbeitet', z.bearbeitet)}{zelle('Hinaus', z.hinaus)}{zelle('Noch da', [z.noch])}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

/** Die Kennung einer Sache im Reiter Perigon (Sprungziel aus der Übersicht). */
export const sacheAnker = (schluessel: string) => `sache-${schluessel.replace(/[^a-z0-9]+/gi, '-')}`

export function Sache({ u, inCharge, spur, verfolgen = false, ohneWeg = false, imFenster = false }: {
  u: Ungereimtheit; inCharge?: number; spur: Map<number, ChargeSpur>
  /** 0126: im Reiter Perigon — Stand, Vermerke und das Feld zum Vermerken unter der Sache */
  verfolgen?: boolean
  /** 0126: der Weg der Ware steht schon darüber (je Sorte) */
  ohneWeg?: boolean
  /** Runde BD: im eigenen Fenster — der Titel steht schon im Kopf */
  imFenster?: boolean
}) {
  // Runde BE: im eigenen Fenster stehen die Belege gleich da — „das ist ja wichtig, ist Nachvollziehbarkeit"
  const [zeilenAuf, setZeilenAuf] = useState(imFenster)
  // Wo die Ware nach Perigon unter einer Nummer hinausging, sind deren Lieferscheine die Belege
  const belegeDerCharge = imFenster && u.charge_nr != null && ['ueberzaehlung', 'ohne_eingang', 'vor_eingang'].includes(u.art)
  // … und wo sie keiner Charge gehören (eine Nummer an zwei Chargen, über den Produzenten zugeordnet): die mit der Nummer
  const belegeDerNummer = imFenster && !belegeDerCharge && (u.nummern?.length ?? 0) > 0
  const [fenster, setFenster] = useState<{ quelle?: string; posId?: number; lieferungId?: number; fall?: PerigonBefund } | null>(null)
  const anzahl = u.art === 'ohne_charge' ? null : u.zeilen.length
  return (
    <article className={`ungereimt-sache s-${u.schwere}`} id={verfolgen ? sacheAnker(u.schluessel) : undefined}>
      {!imFenster && <h4><span className={`punkt s-${u.schwere}`} aria-hidden="true" />{u.titel}{u.kg != null && u.kg > 0 && <span className="leise"> · {kg(u.kg, 0)}</span>}</h4>}
      <dl>
        <dt>Was nicht passt</dt><dd>{u.was}</dd>
        {u.warum && <><dt>Warum es zählt</dt><dd>{u.warum}</dd></>}
        {u.stand && <><dt>Stand</dt><dd>{u.stand}</dd></>}
        {u.vorschlag && <><dt>Vorschlag</dt><dd>{u.vorschlag}</dd></>}
        {u.tun && <><dt>Was tun</dt><dd>{u.tun}</dd></>}
      </dl>
      {!ohneWeg && <WegDerWare nrn={u.beteiligt} spur={spur} />}
      <div className="ungereimt-aktion">
        {u.charge_nr != null && u.charge_nr !== inCharge && <Link to={`/chargen?charge=${u.charge_nr}`}>Charge {u.charge_nr} öffnen</Link>}
        {u.von_charge_nr != null && u.von_charge_nr !== inCharge && <Link to={`/chargen?charge=${u.von_charge_nr}`}>Charge {u.von_charge_nr} öffnen</Link>}
        {anzahl !== null && anzahl > 0 && !imFenster && (
          <button type="button" className="klein" onClick={() => setZeilenAuf(a => !a)} aria-expanded={zeilenAuf}>
            {zeilenAuf ? 'Perigon-Zeilen zu' : `${anzahl} ${anzahl === 1 ? 'Perigon-Zeile' : 'Perigon-Zeilen'} zeigen`}</button>
        )}
        {u.art === 'ohne_charge' && !imFenster && <button type="button" className="klein" onClick={() => setZeilenAuf(a => !a)} aria-expanded={zeilenAuf}>
          {zeilenAuf ? 'Lieferscheine zu' : 'Lieferscheine zeigen'}</button>}
        <SacheKnoepfe u={u} />
      </div>
      {belegeDerCharge && <PerigonBelege chargen={[u.charge_nr!]} vorEingang={u.art === 'vor_eingang' ? spur.get(u.charge_nr!)?.journal_von ?? null : null} />}
      {belegeDerNummer && <PerigonBelege nummern={u.nummern} />}
      {imFenster && zeilenAuf && u.zeilen.length > 0 && u.art !== 'ohne_charge' && <h3 className="belege-titel">Die Perigon-Zeilen dazu <span className="leise">— ein Klick zeigt die Zeile wie im Excel</span></h3>}
      {zeilenAuf && u.art !== 'ohne_charge' && (
        <ul className="ungereimt-zeilen">
          {u.zeilen.map((z, i) => (
            <li key={'schluessel' in z ? String(z.schluessel) : `${z.quelle}:${z.pos_id}:${z.art}:${i}`}>
              <button type="button" className="link" title="die Zeile der Perigon-Datei zeigen — was nicht stimmt, ist rot umrandet"
                      onClick={() => setFenster({ quelle: z.quelle, posId: z.pos_id, fall: 'schluessel' in z ? (z as PerigonBefund) : undefined })}>
                {datum(z.datum)} · {z.artikel}{z.kg != null ? ` · ${kg(z.kg, 0)}` : ''}{z.kunde ? ` · ${z.kunde}` : ''}</button>
              {' '}<code className="kennung-wert" title="die Position (AufPosId, Spalte AD) — so findet man die Zeile im Excel">{z.pos_id}</code>
              <span className="leise"> — {z.satz ?? z.befund}</span>
            </li>
          ))}
        </ul>
      )}
      {/* 0125: jeder Lieferschein mit dem Grund, warum er keine Charge hat; ein Klick zeigt die Perigon-Zeile. */}
      {zeilenAuf && u.art === 'ohne_charge' && <OhneChargeListe sorte={u.sorte} />}
      {verfolgen && <FallVerfolgen schluessel={u.schluessel} schnappschuss={sacheSchnappschuss(u)} kompakt />}
      {fenster && <LieferungFenster {...fenster} schliessen={() => setFenster(null)} />}
    </article>
  )
}

/**
 * Was der Betriebsleiter an einer Sache mit einem Klick tun kann: eine
 * Umbuchung zurücknehmen, einen Vorschlag umbuchen, eine Perigon-Nummer ins
 * Register übernehmen. Runde BF: im Fall stehen die Knöpfe unter „Was die App
 * vermutet" — nicht oben, denn entscheiden tut der Betrieb.
 */
export function SacheKnoepfe({ u }: { u: Ungereimtheit }) {
  const { istAdmin } = useAuth()
  const [meldung, setMeldung] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)
  const setzen = async (stand: 'angewandt' | 'zurueckgenommen') => {
    if (!u.paletten?.length) return
    setLaeuft(true); setMeldung(null)
    const r = await supabase.rpc('palette_zuordnung_setzen', { p_palette_ids: u.paletten, p_stand: stand })
    setLaeuft(false)
    setMeldung(r.error ? fehlerText(r.error) : stand === 'angewandt'
      ? 'Umgebucht. Die Zahlen ändern sich mit dem nächsten Rechnen („Neu rechnen" oben).'
      : 'Zurückgenommen. Die Zahlen ändern sich mit dem nächsten Rechnen („Neu rechnen" oben).')
  }
  // 0122: den Vorschlag fürs Chargenregister übernehmen — dasselbe wie unter Stammdaten → Chargen, nur ohne Suchen.
  const nummerEintragen = async () => {
    const p = u.perigonSetzen
    if (!p) return
    setLaeuft(true); setMeldung(null)
    const r = await supabase.from('charge').update({ perigon_nr: p.perigon_nr }).eq('nr', p.charge_nr)
    setLaeuft(false)
    setMeldung(r.error ? fehlerText(r.error)
      : `Bei ${p.charge_nr} steht jetzt die Perigon-Nr. ${p.perigon_nr}. Die Zahlen ändern sich mit dem nächsten Rechnen („Neu rechnen" oben); zurück geht es unter Stammdaten → Chargen.`)
  }
  if (!istAdmin || !(u.art === 'umgebucht' || u.art === 'vorschlag' || u.perigonSetzen)) return null
  return (
    <>
      {u.art === 'umgebucht' && <button type="button" className="klein" disabled={laeuft} onClick={() => void setzen('zurueckgenommen')}>Umbuchung zurücknehmen</button>}
      {u.art === 'vorschlag' && <button type="button" className="klein" disabled={laeuft} onClick={() => void setzen('angewandt')}>Umbuchen</button>}
      {u.perigonSetzen && <button type="button" className="klein" disabled={laeuft} onClick={() => void nummerEintragen()}>
        Bei {u.perigonSetzen.charge_nr} Perigon-Nr. {u.perigonSetzen.perigon_nr} eintragen</button>}
      {meldung && <p className="hilfe unten-0 knopf-meldung">{meldung}</p>}
    </>
  )
}
