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
import { useEffect, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { Link } from 'react-router-dom'
import { FallVerfolgen } from './Verfolgen'
import { betroffen, istOffen, sacheSchnappschuss } from './perigon'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg, tonnen } from '../lib/format'
import { useAuth } from '../auth/AuthProvider'
import { ZChevron, ZKreuz, ZWarnung } from '../components/Zeichen'
import { LieferungFenster } from '../betrieb/LieferungFenster'
import type { Auswertung, ChargeSpur, PerigonBefund } from './daten'
import { ART_NAME, spurText, ungereimtheiten, vonCharge, type Ungereimtheit } from './ungereimt'
import { OhneChargeListe } from './OhneCharge'

/**
 * 0126: Oben auf Lager nach Charge, nach Artikel und Chargen — eine Zeile:
 * wie viele Stellen offen sind und wie viel es betrifft, und der Weg in den
 * Reiter Perigon. Was der Betriebsleiter als erledigt oder „kein Fehler"
 * vermerkt hat, zählt nicht mehr.
 */
export function PerigonVerweis({ daten }: { daten: Auswertung }) {
  const stand = useMemo(() => new Map(daten.faelleStand.map(v => [v.schluessel, v.stand])), [daten.faelleStand])
  const sachen = useMemo(() => ungereimtheiten(daten.ungereimt), [daten.ungereimt])
  const offenSachen = sachen.filter(u => istOffen(u.schwere, stand.get(u.schluessel) ?? 'offen'))
  const offenZeilen = daten.perigon.filter(f => istOffen(f.schwere, stand.get(f.schluessel) ?? 'offen'))
  const n = offenSachen.length + offenZeilen.length
  if (n === 0) return null
  const kgSumme = [...offenSachen.map(u => u.kg ?? 0), ...offenZeilen.map(f => betroffen(f) ?? 0)].reduce((a, x) => a + x, 0)
  const rot = offenSachen.some(u => u.schwere === 'rot') || offenZeilen.some(f => f.schwere === 'rot')
  return (
    <Link to="/perigon" className={`perigon-verweis ${rot ? 'u-rot' : 'u-gelb'}`} id="ungereimt">
      <span className="ungereimt-zeichen" aria-hidden="true"><ZWarnung size={16} /></span>
      <span><strong>Perigon und Lager passen an {n} {n === 1 ? 'Stelle' : 'Stellen'} nicht zusammen</strong>
        {kgSumme > 0 && <span> · betrifft {tonnen(kgSumme)}</span>}</span>
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

/**
 * Runde BD: eine Sache je Charge im eigenen Fenster — aus der Liste der Fälle
 * und aus Je Sorte, wie ein Perigon-Fall. Oben die Art und die Sache in einem
 * Satz, darunter was nicht passt, der Weg der Ware, was zu tun ist und das
 * Mitverfolgen; die Seite dahinter bleibt, wo sie war.
 */
export function SacheFenster({ u, spur, schliessen }: { u: Ungereimtheit; spur: Map<number, ChargeSpur>; schliessen: () => void }) {
  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape') schliessen() }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [schliessen])
  return createPortal(
    <div className="dialog-hinter" onClick={schliessen}>
      <div className="dialog breit" role="dialog" aria-modal="true" aria-label={ART_NAME[u.art] ?? u.art} id="sache-fenster" onClick={e => e.stopPropagation()}>
        <div className="fenster-kopf">
          <div>
            <h2><span className={`punkt s-${u.schwere}`} aria-hidden="true" />{ART_NAME[u.art] ?? u.art}</h2>
            <p className="leise fall-wo">{u.titel}{u.kg != null && u.kg > 0 ? ` · betrifft ${kg(u.kg, 0)}` : ''}</p>
          </div>
          <button type="button" className="klein schliessen" onClick={schliessen} aria-label="schliessen"><ZKreuz size={16} /></button>
        </div>
        <Sache u={u} spur={spur} verfolgen imFenster />
      </div>
    </div>,
    document.body,
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
  const { istAdmin } = useAuth()
  const [zeilenAuf, setZeilenAuf] = useState(false)
  const [fenster, setFenster] = useState<{ quelle?: string; posId?: number; lieferungId?: number; fall?: PerigonBefund } | null>(null)
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
        {anzahl !== null && anzahl > 0 && (
          <button type="button" className="klein" onClick={() => setZeilenAuf(a => !a)} aria-expanded={zeilenAuf}>
            {zeilenAuf ? 'Perigon-Zeilen zu' : `${anzahl} ${anzahl === 1 ? 'Perigon-Zeile' : 'Perigon-Zeilen'} zeigen`}</button>
        )}
        {u.art === 'ohne_charge' && <button type="button" className="klein" onClick={() => setZeilenAuf(a => !a)} aria-expanded={zeilenAuf}>
          {zeilenAuf ? 'Lieferscheine zu' : 'Lieferscheine zeigen'}</button>}
        {istAdmin && u.art === 'umgebucht' && <button type="button" className="klein" disabled={laeuft} onClick={() => void setzen('zurueckgenommen')}>Umbuchung zurücknehmen</button>}
        {istAdmin && u.art === 'vorschlag' && <button type="button" className="klein" disabled={laeuft} onClick={() => void setzen('angewandt')}>Umbuchen</button>}
        {istAdmin && u.perigonSetzen && <button type="button" className="klein" disabled={laeuft} onClick={() => void nummerEintragen()}>
          Bei {u.perigonSetzen.charge_nr} Perigon-Nr. {u.perigonSetzen.perigon_nr} eintragen</button>}
      </div>
      {meldung && <p className="hilfe unten-0">{meldung}</p>}
      {zeilenAuf && u.art !== 'ohne_charge' && (
        <ul className="ungereimt-zeilen">
          {u.zeilen.map((z, i) => (
            <li key={'schluessel' in z ? String(z.schluessel) : `${z.quelle}:${z.pos_id}:${z.art}:${i}`}>
              <button type="button" className="link" title="die Zeile der Perigon-Datei zeigen — was nicht stimmt, ist rot umrandet"
                      onClick={() => setFenster({ quelle: z.quelle, posId: z.pos_id, fall: 'schluessel' in z ? (z as PerigonBefund) : undefined })}>
                {datum(z.datum)} · {z.artikel}{z.kg != null ? ` · ${kg(z.kg, 0)}` : ''}{z.kunde ? ` · ${z.kunde}` : ''}</button>
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
