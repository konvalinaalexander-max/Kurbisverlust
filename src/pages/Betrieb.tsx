import { useEffect, useState } from 'react'
import { TaetZeichen, ZNeu } from '../components/Zeichen'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { tempoJeTaetigkeit } from '../auswertung/tempo'
import type { Durchsatz } from '../auswertung/daten'
import { WOERTERBUCH } from '../lib/i18n'
import { datum, kg, tagVon, zahl } from '../lib/format'
import { Hinweis, Karte, Lade, Leer, Marke, Segmente } from '../components/Bausteine'
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
      <div className="seitenkopf">
        <div><h1>Betrieb</h1><p className="zweck">{zweck}</p></div>
      </div>
      <nav className="navleiste unter" aria-label="Betrieb">
        {TEILE.map(([t, name]) => (
          <a key={t} href={`/betrieb/${t}`} className={aktiv === t ? 'aktiv' : ''}
             onClick={e => { e.preventDefault(); navigate(`/betrieb/${t}`) }}>{name}</a>
        ))}
      </nav>
      <div className="wechsel" key={aktiv}>
        {aktiv === 'arbeiten' && <Arbeiten />}
        {aktiv === 'lieferungen' && <Lieferungen />}
        {aktiv === 'csv' && <CsvUpload />}
        {aktiv === 'warteschlange' && <Warteschlange />}
        {aktiv === 'stammdaten' && <Stammdaten />}
        {aktiv === 'zugang' && <Zugang />}
      </div>
    </>
  )
}

const TAGE_ZUERST = 14

/**
 * Die Arbeiten — nach Tag gruppiert, die neuesten oben. Zuerst die letzten
 * zwei Wochen; „ältere zeigen" holt die nächsten. Kein Bildschirm mit
 * dreihundert Zeilen mehr.
 */
function Arbeiten() {
  const [auftraege, setAuftraege] = useState<Auftrag[]>([])
  const [chargen, setChargen] = useState<Charge[]>([])
  const [durchsatz, setDurchsatz] = useState<Map<number, Durchsatz>>(new Map())
  const [filter, setFilter] = useState<'alle' | 'offen' | 'fertig' | 'abgebrochen'>('alle')
  const [tage, setTage] = useState(TAGE_ZUERST)
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  useEffect(() => {
    void (async () => {
      try {
        const [{ chargen }, a, d] = await Promise.all([
          stammdaten(),
          supabase.from('auftrag').select('*').order('start_ts', { ascending: false }).limit(400),
          supabase.from('erg_durchsatz').select('*'),
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
  const tempo = tempoJeTaetigkeit([...durchsatz.values()])
  if (laedt) return <Lade />

  // Nach Tag gruppieren; die ältesten Tage bleiben zu, bis man sie will.
  const gruppen = new Map<string, Auftrag[]>()
  for (const a of gezeigt) { const tag = tagVon(new Date(a.start_ts)); gruppen.set(tag, [...(gruppen.get(tag) ?? []), a]) }
  const alleTage = [...gruppen.keys()].sort().reverse()
  const sichtbareTage = alleTage.slice(0, tage)
  const heute = tagVon(new Date())
  const gestern = tagVon(new Date(Date.now() - 86400000))
  const tagName = (tag: string) => tag === heute ? 'Heute' : tag === gestern ? 'Gestern' : new Date(tag + 'T00:00:00').toLocaleDateString('de-CH', { weekday: 'long', day: '2-digit', month: '2-digit' })

  return (
    <>
    {tempo.length > 0 && (
      <Karte titel="Arbeit und Tempo" unter="Je Tätigkeit: wie viele Arbeiten, wie lange sie dauerten, wie viel Masse je Stunde durchging.">
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Tätigkeit</th><th className="zahl">Arbeiten</th><th className="zahl">Stunden</th><th className="zahl">Dauer (Median)</th><th className="zahl">Bewegte Masse</th><th className="zahl">kg je Stunde</th><th className="zahl">kg je Person und Stunde</th></tr></thead>
          <tbody>{tempo.map(z => (
            <tr key={z.name}>
              <td><TaetZeichen id={z.id} /> {z.name}</td>
              <td className="zahl">{z.n}</td>
              <td className="zahl">{z.stunden.toFixed(1)} h</td>
              <td className="zahl">{z.median.toFixed(1)} h</td>
              <td className="zahl">{z.masse > 0 ? kg(z.masse, 0) : <span className="leise">—</span>}</td>
              <td className="zahl">{z.kgProH !== null ? <strong>{zahl(z.kgProH)}</strong> : <span className="leise">—</span>}</td>
              <td className="zahl">{z.kgProPersonH !== null ? zahl(z.kgProPersonH) : <span className="leise">—</span>}</td>
            </tr>
          ))}</tbody>
        </table></div>
        <p className="fussnote">Aus Start und Ende jeder abgeschlossenen Arbeit und der Masse, die sie bewegt hat. Arbeiten ohne bekannte Masse zählen bei der Dauer, nicht beim Tempo.</p>
      </Karte>
    )}
    <Karte titel="Arbeiten" unter={`${gezeigt.length} Arbeiten an ${alleTage.length} Tagen — die neuesten zuerst.`}
           aktion={<Link to="/neu" className="knopf haupt klein"><ZNeu size={15} />Neue Arbeit starten</Link>}>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <div className="filterleiste">
        <Segmente wahl={filter} setzen={setFilter} teile={[['alle', 'alle'], ['offen', 'läuft'], ['fertig', 'fertig'], ['abgebrochen', 'abgebrochen']]} />
      </div>
      {gezeigt.length === 0 ? <Leer titel="Nichts hier">Für diesen Filter gibt es keine Arbeit.</Leer> : (
        <>
          {sichtbareTage.map(tag => (
            <div key={tag}>
              <div className="tag-trenner">{tagName(tag)} <span className="leise">· {gruppen.get(tag)!.length} Arbeiten</span></div>
              <div className="rollbar"><table className="dicht">
                <thead><tr><th>Start</th><th>Arbeit</th><th>Charge</th><th>Status</th><th className="zahl">Paletten</th><th className="zahl">Bewegte Masse</th><th className="zahl">Dauer</th><th className="zahl">kg/h</th><th className="zahl">Leute</th><th></th></tr></thead>
                <tbody>{gruppen.get(tag)!.map(a => {
                  const ta = taetigkeitVon(a.weg, a.station, a.ist_fax); const d = durchsatz.get(a.id)
                  return (
                    <tr key={a.id}>
                      <td className="nowrap">{new Date(a.start_ts).toLocaleTimeString('de-CH', { hour: '2-digit', minute: '2-digit' })}</td>
                      <td className="nowrap"><TaetZeichen id={ta?.id} /> {ta ? t(ta.text) : ''}</td>
                      <td>{chargeText(chargen.find(c => c.nr === a.charge_nr))}</td>
                      <td>{a.abgebrochen_ts ? <Marke art="warnung">abgebrochen</Marke> : a.status === 'offen' ? <Marke art="offen">läuft</Marke> : <Marke art="fertig">fertig</Marke>}</td>
                      <td className="zahl">{d ? zahl(d.n_paletten) : ''}</td>
                      <td className="zahl">{d?.masse_kg != null ? kg(d.masse_kg, 0) : ''}</td>
                      <td className="zahl">{d ? `${d.dauer_h.toFixed(1)} h` : ''}</td>
                      <td className="zahl">{d?.kg_pro_h != null ? zahl(d.kg_pro_h) : ''}</td>
                      <td className="zahl">{d ? d.n_teilnehmer : ''}</td>
                      <td className="rechts-buendig"><Link to={`/arbeit/${a.id}`}>öffnen</Link></td>
                    </tr>
                  )
                })}</tbody>
              </table></div>
            </div>
          ))}
          {alleTage.length > sichtbareTage.length && (
            <div className="mitte" style={{ marginTop: '1rem' }}>
              <button type="button" onClick={() => setTage(n => n + TAGE_ZUERST)}>Ältere zeigen <span className="leise">· {alleTage.length - sichtbareTage.length} Tage, bis {datum(alleTage[alleTage.length - 1])}</span></button>
            </div>
          )}
        </>
      )}
    </Karte>
    </>
  )
}
