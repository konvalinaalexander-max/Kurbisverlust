/**
 * Ungereimtheiten zwischen Perigon und Lager — gut sichtbar oben auf jeder
 * Lagerseite, und je Charge in der aufgeklappten Zeile (0121). Zu: eine
 * Leiste mit der Zahl und den Kilo; auf: je Sache, was komisch ist, warum es
 * das Lager verfälscht und was zu tun ist — mit den Perigon-Zeilen dazu, die
 * im Fenster ihre falschen Zellen rot zeigen.
 */
import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg, tonnen } from '../lib/format'
import { useAuth } from '../auth/AuthProvider'
import { ZChevron, ZWarnung } from '../components/Zeichen'
import { LieferungFenster } from '../betrieb/LieferungFenster'
import type { Auswertung, ChargeSpur } from './daten'
import { ART_NAME, spurText, ungereimtheiten, vonCharge, type Ungereimtheit } from './ungereimt'
import { OhneChargeListe } from './OhneCharge'

export function Ungereimtheiten({ daten, charge, startOffen = false }: { daten: Auswertung; charge?: number; startOffen?: boolean }) {
  const alle = useMemo(() => ungereimtheiten(daten.ungereimt, daten.perigon), [daten.ungereimt, daten.perigon])
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
        </div>
      )}
    </section>
  )
}

/**
 * 0122: Der Weg der Ware je beteiligter Charge — herein laut Erntejournal,
 * bearbeitet in der Halle, hinaus laut Perigon, und was laut App noch da ist.
 */
function WegDerWare({ nrn, spur }: { nrn: number[]; spur: Map<number, ChargeSpur> }) {
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

function Sache({ u, inCharge, spur }: { u: Ungereimtheit; inCharge?: number; spur: Map<number, ChargeSpur> }) {
  const { istAdmin } = useAuth()
  const [zeilenAuf, setZeilenAuf] = useState(false)
  const [fenster, setFenster] = useState<{ quelle?: string; posId?: number; lieferungId?: number } | null>(null)
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
    <article className={`ungereimt-sache s-${u.schwere}`}>
      <h4><span className={`punkt s-${u.schwere}`} aria-hidden="true" />{u.titel}{u.kg != null && u.kg > 0 && <span className="leise"> · {kg(u.kg, 0)}</span>}</h4>
      <dl>
        <dt>Was</dt><dd>{u.was}</dd>
        {u.warum && <><dt>Warum es zählt</dt><dd>{u.warum}</dd></>}
        {u.stand && <><dt>Stand</dt><dd>{u.stand}</dd></>}
        {u.vorschlag && <><dt>Vorschlag</dt><dd>{u.vorschlag}</dd></>}
        {u.tun && <><dt>Was tun</dt><dd>{u.tun}</dd></>}
      </dl>
      <WegDerWare nrn={u.beteiligt} spur={spur} />
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
          {u.zeilen.map(z => (
            <li key={`${z.quelle}:${z.pos_id}:${z.art}`}>
              <button type="button" className="link" onClick={() => setFenster({ quelle: z.quelle, posId: z.pos_id })} title="die Zeile der Perigon-Datei zeigen — was nicht stimmt, ist rot umrandet">
                {datum(z.datum)} · {z.artikel}{z.kg != null ? ` · ${kg(z.kg, 0)}` : ''}{z.kunde ? ` · ${z.kunde}` : ''}</button>
              <span className="leise"> — {z.befund}</span>
            </li>
          ))}
        </ul>
      )}
      {/* 0125: jeder Lieferschein mit dem Grund, warum er keine Charge hat; ein Klick zeigt die Perigon-Zeile. */}
      {zeilenAuf && u.art === 'ohne_charge' && <OhneChargeListe sorte={u.sorte} />}
      {fenster && <LieferungFenster {...fenster} schliessen={() => setFenster(null)} />}
    </article>
  )
}
