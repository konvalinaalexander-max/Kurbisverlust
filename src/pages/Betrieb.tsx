import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { WOERTERBUCH } from '../lib/i18n'
import { kg, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import Lieferungen from './Lieferungen'
import CsvUpload from './CsvUpload'
import Warteschlange from './Warteschlange'
import Stammdaten from './Stammdaten'
import Zugang from './Zugang'
import type { Auftrag, Charge } from '../lib/typen'

type Teil = 'arbeiten' | 'lieferungen' | 'csv' | 'warteschlange' | 'stammdaten' | 'zugang'
const TEILE: [Teil, string, string][] = [
  ['arbeiten', 'Arbeiten', 'Was heute läuft und was fertig ist — jede Arbeit lässt sich öffnen.'],
  ['lieferungen', 'Warenausgang', 'Was den Betrieb verlässt — die Gegenprobe zur Hochrechnung.'],
  ['csv', 'Sortier-CSV', 'Die Dateien der Sortiermaschine einlesen.'],
  ['warteschlange', 'Warteschlange', 'Sortier-CSVs, die noch keiner Arbeit zugeordnet sind.'],
  ['stammdaten', 'Stammdaten', 'Gebinde und Tara, Chargen, Sortierschemata, Benutzer, Einstellungen.'],
  ['zugang', 'Zugang', 'Der QR-Code für die Halle.'],
]

/** Betrieb: Was ist heute los, und wie pflege ich die Grundlagen? */
export default function Betrieb() {
  const { teil } = useParams()
  const navigate = useNavigate()
  const aktiv = (TEILE.find(([t]) => t === teil)?.[0] ?? 'arbeiten') as Teil
  const zweck = TEILE.find(([t]) => t === aktiv)?.[2]
  return (
    <>
      <div style={{ marginTop: '1.25rem' }}>
        <h1 style={{ margin: 0 }}>Betrieb</h1>
        <p className="leise" style={{ margin: '.25rem 0 0' }}>{zweck}</p>
      </div>
      <nav className="navleiste unter">
        {TEILE.map(([t, name]) => (
          <a key={t} href="#" className={aktiv === t ? 'aktiv' : ''}
             onClick={e => { e.preventDefault(); navigate(`/betrieb/${t}`) }}>{name}</a>
        ))}
      </nav>
      {aktiv === 'arbeiten' && <Arbeiten />}
      {aktiv === 'lieferungen' && <Lieferungen />}
      {aktiv === 'csv' && <CsvUpload />}
      {aktiv === 'warteschlange' && <Warteschlange />}
      {aktiv === 'stammdaten' && <Stammdaten />}
      {aktiv === 'zugang' && <Zugang />}
    </>
  )
}

interface Durchsatz { auftrag_id: number; dauer_h: number; masse_kg: number | null; kg_pro_h: number | null; n_teilnehmer: number; n_paletten: number }

function Arbeiten() {
  const [auftraege, setAuftraege] = useState<Auftrag[]>([])
  const [chargen, setChargen] = useState<Charge[]>([])
  const [durchsatz, setDurchsatz] = useState<Map<number, Durchsatz>>(new Map())
  const [filter, setFilter] = useState<'alle' | 'offen' | 'fertig' | 'abgebrochen'>('alle')
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  useEffect(() => {
    void (async () => {
      try {
        const [{ chargen }, a, d] = await Promise.all([
          stammdaten(),
          supabase.from('auftrag').select('*').order('start_ts', { ascending: false }).limit(200),
          supabase.from('v_durchsatz').select('auftrag_id, dauer_h, masse_kg, kg_pro_h, n_teilnehmer, n_paletten'),
        ])
        if (a.error) throw a.error
        setChargen(chargen); setAuftraege((a.data ?? []) as Auftrag[])
        setDurchsatz(new Map(((d.data ?? []) as Durchsatz[]).map(x => [x.auftrag_id, x])))
      } catch (f) { setFehler(fehlerText(f)) } finally { setLaedt(false) }
    })()
  }, [])
  const t = (id: keyof typeof WOERTERBUCH.de) => WOERTERBUCH.de[id]
  const gezeigt = auftraege.filter(a => filter === 'alle' ? true
    : filter === 'abgebrochen' ? a.abgebrochen_ts !== null
    : a.abgebrochen_ts === null && a.status === (filter === 'offen' ? 'offen' : 'abgeschlossen'))
  if (laedt) return <Lade />
  return (
    <Karte>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <div className="reihe" style={{ marginBottom: '.5rem' }}>
        <div className="umschalter" style={{ margin: 0, minWidth: 320 }} role="tablist">
          {(['alle', 'offen', 'fertig', 'abgebrochen'] as const).map(f => (
            <button key={f} role="tab" aria-selected={filter === f} className={filter === f ? 'aktiv' : ''} onClick={() => setFilter(f)}>
              {{ alle: 'alle', offen: 'läuft', fertig: 'fertig', abgebrochen: 'abgebrochen' }[f]}
            </button>
          ))}
        </div>
        <Link to="/neu" className="knopf haupt" style={{ marginLeft: 'auto' }}>Neue Arbeit starten</Link>
      </div>
      {gezeigt.length === 0 ? <p className="leise" style={{ margin: 0 }}>nichts</p> : (
        <div className="rollbar"><table>
          <thead><tr><th>Start</th><th>Arbeit</th><th>Charge</th><th>Status</th><th className="zahl">Paletten</th><th className="zahl">Masse</th><th className="zahl">Dauer</th><th className="zahl">kg/h</th><th className="zahl">Leute</th><th></th></tr></thead>
          <tbody>{gezeigt.map(a => {
            const ta = taetigkeitVon(a.weg, a.station, a.ist_fax); const d = durchsatz.get(a.id)
            return (
              <tr key={a.id}>
                <td>{zeitpunkt(a.start_ts)}</td>
                <td>{ta?.zeichen} {ta ? t(ta.text) : ''}{a.kaeufer && <span className="leise"> · {a.kaeufer}</span>}</td>
                <td>{chargeText(chargen.find(c => c.nr === a.charge_nr))}</td>
                <td>{a.abgebrochen_ts ? <Marke art="warnung">abgebrochen</Marke> : a.status === 'offen' ? <Marke art="offen">läuft</Marke> : <Marke art="fertig">fertig</Marke>}</td>
                <td className="zahl">{d ? zahl(d.n_paletten) : ''}</td>
                <td className="zahl">{d?.masse_kg != null ? kg(d.masse_kg, 0) : ''}</td>
                <td className="zahl">{d ? `${d.dauer_h.toFixed(1)} h` : ''}</td>
                <td className="zahl">{d?.kg_pro_h != null ? zahl(d.kg_pro_h) : ''}</td>
                <td className="zahl">{d ? d.n_teilnehmer : ''}</td>
                <td><Link to={`/arbeit/${a.id}`}>öffnen</Link></td>
              </tr>
            )
          })}</tbody>
        </table></div>
      )}
    </Karte>
  )
}
