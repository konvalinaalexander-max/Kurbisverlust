import { Navigate, useNavigate, useParams } from 'react-router-dom'
import Lieferungen from './Lieferungen'
import CsvUpload from './CsvUpload'
import Warteschlange from './Warteschlange'
import Stammdaten from './Stammdaten'
import Zugang from './Zugang'

type Teil = 'lieferungen' | 'csv' | 'warteschlange' | 'stammdaten' | 'zugang'
// Runde AO: die Arbeiten stehen seit dem 12. Oktober unter Messungen (erster Reiter).
const TEILE: [Teil, string, string][] = [
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
  const aktiv = (TEILE.find(([t]) => t === teil)?.[0] ?? 'lieferungen') as Teil
  // Alte Adressen und Lesezeichen: /betrieb/arbeiten heisst jetzt /messungen/arbeiten.
  if (teil === 'arbeiten') return <Navigate to="/messungen/arbeiten" replace />
  return (
    <>
      <div className="seitenkopf">
        {/* Runde AF: kein Untertitel mehr — der Betrieb will die Überschriften ohne Erklärsatz. */}
        <div><h1>Betrieb</h1></div>
      </div>
      <nav className="navleiste unter" aria-label="Betrieb">
        {TEILE.map(([t, name]) => (
          <a key={t} href={`/betrieb/${t}`} className={aktiv === t ? 'aktiv' : ''}
             onClick={e => { e.preventDefault(); navigate(`/betrieb/${t}`) }}>{name}</a>
        ))}
      </nav>
      <div className="wechsel" key={aktiv}>
        {aktiv === 'lieferungen' && <Lieferungen />}
        {aktiv === 'csv' && <CsvUpload />}
        {aktiv === 'warteschlange' && <Warteschlange />}
        {aktiv === 'stammdaten' && <Stammdaten />}
        {aktiv === 'zugang' && <Zugang />}
      </div>
    </>
  )
}
