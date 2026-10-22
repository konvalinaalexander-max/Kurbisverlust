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
import type { Auswertung } from './daten'
import { ART_NAME, ungereimtheiten, vonCharge, type Ungereimtheit } from './ungereimt'

export function Ungereimtheiten({ daten, charge, startOffen = false }: { daten: Auswertung; charge?: number; startOffen?: boolean }) {
  const alle = useMemo(() => ungereimtheiten(daten.ungereimt, daten.perigon), [daten.ungereimt, daten.perigon])
  const liste = charge != null ? vonCharge(alle, charge) : alle
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
            Das Schwerste zuerst.</p>}
          {liste.map(u => <Sache key={u.schluessel} u={u} inCharge={charge} />)}
        </div>
      )}
    </section>
  )
}

function Sache({ u, inCharge }: { u: Ungereimtheit; inCharge?: number }) {
  const { istAdmin } = useAuth()
  const [zeilenAuf, setZeilenAuf] = useState(false)
  const [fenster, setFenster] = useState<{ quelle?: string; posId?: number; lieferungId?: number } | null>(null)
  type L = { id: number; datum: string; kunde: string | null; masse_kg: number | null }
  const [lieferungen, setLieferungen] = useState<L[] | null>(null)
  const [meldung, setMeldung] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  // Lieferscheine ohne Charge: die Liste kommt erst beim Aufklappen (erg_lieferung).
  const ohneChargeLaden = async () => {
    setZeilenAuf(a => !a)
    if (lieferungen !== null || u.art !== 'ohne_charge') return
    const r = await supabase.from('erg_lieferung').select('id, datum, kunde, masse_kg').is('charge_nr', null).eq('sorte', u.sorte ?? '').order('datum', { ascending: false })
    setLieferungen(r.error ? [] : (r.data ?? []) as L[])
    if (r.error) setMeldung(fehlerText(r.error))
  }
  const setzen = async (stand: 'angewandt' | 'zurueckgenommen') => {
    if (!u.paletten?.length) return
    setLaeuft(true); setMeldung(null)
    const r = await supabase.rpc('palette_zuordnung_setzen', { p_palette_ids: u.paletten, p_stand: stand })
    setLaeuft(false)
    setMeldung(r.error ? fehlerText(r.error) : stand === 'angewandt'
      ? 'Umgebucht. Die Zahlen ändern sich mit dem nächsten Rechnen („Neu rechnen" oben).'
      : 'Zurückgenommen. Die Zahlen ändern sich mit dem nächsten Rechnen („Neu rechnen" oben).')
  }
  const anzahl = u.art === 'ohne_charge' ? null : u.zeilen.length
  return (
    <article className={`ungereimt-sache s-${u.schwere}`}>
      <h4><span className={`punkt s-${u.schwere}`} aria-hidden="true" />{u.titel}{u.kg != null && u.kg > 0 && <span className="leise"> · {kg(u.kg, 0)}</span>}</h4>
      <dl>
        <dt>Was</dt><dd>{u.was}</dd>
        {u.warum && <><dt>Warum es zählt</dt><dd>{u.warum}</dd></>}
        {u.tun && <><dt>Was tun</dt><dd>{u.tun}</dd></>}
      </dl>
      <div className="ungereimt-aktion">
        {u.charge_nr != null && u.charge_nr !== inCharge && <Link to={`/chargen?charge=${u.charge_nr}`}>Charge {u.charge_nr} öffnen</Link>}
        {u.von_charge_nr != null && u.von_charge_nr !== inCharge && <Link to={`/chargen?charge=${u.von_charge_nr}`}>Charge {u.von_charge_nr} öffnen</Link>}
        {anzahl !== null && anzahl > 0 && (
          <button type="button" className="klein" onClick={() => setZeilenAuf(a => !a)} aria-expanded={zeilenAuf}>
            {zeilenAuf ? 'Perigon-Zeilen zu' : `${anzahl} ${anzahl === 1 ? 'Perigon-Zeile' : 'Perigon-Zeilen'} zeigen`}</button>
        )}
        {u.art === 'ohne_charge' && <button type="button" className="klein" onClick={() => void ohneChargeLaden()} aria-expanded={zeilenAuf}>
          {zeilenAuf ? 'Lieferscheine zu' : 'Lieferscheine zeigen'}</button>}
        {istAdmin && u.art === 'umgebucht' && <button type="button" className="klein" disabled={laeuft} onClick={() => void setzen('zurueckgenommen')}>Umbuchung zurücknehmen</button>}
        {istAdmin && u.art === 'vorschlag' && <button type="button" className="klein" disabled={laeuft} onClick={() => void setzen('angewandt')}>Umbuchen</button>}
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
      {zeilenAuf && u.art === 'ohne_charge' && (
        lieferungen === null ? <p className="leise">lädt …</p> : (
          <ul className="ungereimt-zeilen">
            {lieferungen.map(l => (
              <li key={l.id}><button type="button" className="link" onClick={() => setFenster({ lieferungId: l.id })} title="die Zeile der Perigon-Datei zeigen">
                {datum(l.datum)} · {kg(l.masse_kg, 0)}{l.kunde ? ` · ${l.kunde}` : ''}</button></li>
            ))}
          </ul>
        )
      )}
      {fenster && <LieferungFenster {...fenster} schliessen={() => setFenster(null)} />}
    </article>
  )
}
