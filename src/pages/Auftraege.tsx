import { useEffect, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { STATION_NAME, WEG_NAME, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import type { Auftrag, Charge, Station, Weg } from '../lib/typen'

/** Welche Stationen es auf welchem Weg gibt (Spec §3). */
const STATIONEN: Record<Weg, Station[]> = {
  maschine: ['sortieren', 'waschen'],
  hand: ['waschen_sortieren'],
}

export default function Auftraege() {
  const [auftraege, setAuftraege] = useState<Auftrag[]>([])
  const [chargen, setChargen] = useState<Charge[]>([])
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  const [neuOffen, setNeuOffen] = useState(false)

  async function laden() {
    setLaedt(true)
    try {
      const [{ chargen }, { data, error }] = await Promise.all([
        stammdaten(),
        supabase.from('auftrag').select('*').order('start_ts', { ascending: false }).limit(40),
      ])
      if (error) throw error
      setChargen(chargen)
      setAuftraege((data ?? []) as Auftrag[])
      setFehler(null)
    } catch (f) {
      setFehler(fehlerText(f))
    } finally {
      setLaedt(false)
    }
  }
  useEffect(() => { void laden() }, [])

  const offen = auftraege.filter(a => a.status === 'offen')
  const fertig = auftraege.filter(a => a.status === 'abgeschlossen')
  const charge = (nr: number) => chargen.find(c => c.nr === nr)

  if (laedt) return <Lade />

  return (
    <>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      {!neuOffen && (
        <button className="haupt gross" style={{ width: '100%', marginTop: '1rem' }}
                onClick={() => setNeuOffen(true)}>
          + Neuen Auftrag eröffnen
        </button>
      )}
      {neuOffen && (
        <NeuerAuftrag chargen={chargen}
                      fertig={() => { setNeuOffen(false); void laden() }}
                      abbrechen={() => setNeuOffen(false)} />
      )}

      <Karte titel={`Laufende Aufträge (${offen.length})`}>
        {offen.length === 0
          ? <p className="leise">Gerade läuft kein Auftrag.</p>
          : offen.map(a => <AuftragZeile key={a.id} auftrag={a} charge={charge(a.charge_nr)} />)}
      </Karte>

      {fertig.length > 0 && (
        <Karte titel="Zuletzt abgeschlossen">
          {fertig.slice(0, 12).map(a => <AuftragZeile key={a.id} auftrag={a} charge={charge(a.charge_nr)} />)}
        </Karte>
      )}
    </>
  )
}

function AuftragZeile({ auftrag, charge }: { auftrag: Auftrag; charge?: Charge }) {
  return (
    <Link to={`/auftraege/${auftrag.id}`}
          style={{ display: 'block', textDecoration: 'none', color: 'inherit',
                   padding: '.7rem 0', borderBottom: '1px solid var(--rand)' }}>
      <div className="reihe">
        <strong>{chargeText(charge)}</strong>
        <Marke art={auftrag.status === 'offen' ? 'offen' : 'fertig'}>
          {auftrag.status === 'offen' ? 'läuft' : 'fertig'}
        </Marke>
      </div>
      <div className="leise">
        {WEG_NAME[auftrag.weg]} · {STATION_NAME[auftrag.station]} · seit {zeitpunkt(auftrag.start_ts)}
      </div>
    </Link>
  )
}

function NeuerAuftrag({ chargen, fertig, abbrechen }: {
  chargen: Charge[]; fertig: () => void; abbrechen: () => void
}) {
  const [weg, setWeg] = useState<Weg>('hand')
  const [station, setStation] = useState<Station>('waschen_sortieren')
  const [chargeNr, setChargeNr] = useState<number | ''>('')
  const [paletten, setPaletten] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  function wegWechseln(neu: Weg) {
    setWeg(neu)
    setStation(STATIONEN[neu][0])
  }

  async function anlegen(e: FormEvent) {
    e.preventDefault()
    if (chargeNr === '') return
    setLaeuft(true); setFehler(null)
    // Die Startzeit setzt die Datenbank (Spec §10): das Handy des Arbeiters
    // ist keine verlässliche Uhr, und an ihr hängt die CSV-Zuordnung.
    const { error } = await supabase.from('auftrag').insert({
      weg, station, charge_nr: chargeNr,
      geplante_paletten: paletten === '' ? null : Number(paletten),
    })
    setLaeuft(false)
    if (error) setFehler(fehlerText(error)); else fertig()
  }

  return (
    <Karte titel="Neuen Auftrag eröffnen">
      <form onSubmit={anlegen}>
        <div className="feld">
          <label>Weg</label>
          <div className="reihe">
            {(['hand', 'maschine'] as Weg[]).map(w => (
              <button key={w} type="button" className={weg === w ? 'haupt' : ''}
                      style={{ flex: 1 }} onClick={() => wegWechseln(w)}>
                {WEG_NAME[w]}
              </button>
            ))}
          </div>
        </div>

        <div className="feld">
          <label htmlFor="station">Station</label>
          <select id="station" value={station} onChange={e => setStation(e.target.value as Station)}>
            {STATIONEN[weg].map(s => <option key={s} value={s}>{STATION_NAME[s]}</option>)}
          </select>
        </div>

        <div className="feld">
          <label htmlFor="charge">Charge</label>
          <select id="charge" value={chargeNr} required
                  onChange={e => setChargeNr(e.target.value === '' ? '' : Number(e.target.value))}>
            <option value="">— wählen —</option>
            {chargen.map(c => <option key={c.nr} value={c.nr}>{chargeText(c)}</option>)}
          </select>
        </div>

        <div className="feld">
          <label htmlFor="gepl">Geplante Paletten (optional)</label>
          <input id="gepl" type="number" inputMode="numeric" min={0} value={paletten}
                 onChange={e => setPaletten(e.target.value)} />
        </div>

        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <div className="reihe" style={{ marginTop: '.5rem' }}>
          <button className="haupt" style={{ flex: 1 }} disabled={laeuft || chargeNr === ''}>
            Auftrag eröffnen
          </button>
          <button type="button" onClick={abbrechen}>Abbrechen</button>
        </div>
      </form>
    </Karte>
  )
}
