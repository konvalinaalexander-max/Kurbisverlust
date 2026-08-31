import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { TAETIGKEITEN, taetigkeitVon } from '../lib/taetigkeit'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import type { Auftrag, Charge } from '../lib/typen'

export default function Auftraege() {
  const { t, gebietsschema } = useSprache()
  const navigate = useNavigate()
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
    } catch (f) { setFehler(fehlerText(f)) } finally { setLaedt(false) }
  }
  useEffect(() => { void laden() }, [])

  // Abgebrochene Arbeiten sind Fehlgriffe — sie gehören nicht in die Liste
  // des Arbeiters. Für den Betriebsleiter bleiben sie in der Datenbank.
  const gueltig = auftraege.filter(a => a.abgebrochen_ts === null)
  const offen = gueltig.filter(a => a.status === 'offen')
  const fertig = gueltig.filter(a => a.status === 'abgeschlossen')
  const charge = (nr: number) => chargen.find(c => c.nr === nr)

  if (laedt) return <Lade />

  function Zeile({ auftrag }: { auftrag: Auftrag }) {
    const taet = taetigkeitVon(auftrag.weg, auftrag.station)
    const zeit = new Date(auftrag.start_ts)
      .toLocaleString(gebietsschema, { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
    return (
      <Link to={`/auftraege/${auftrag.id}`}
            style={{ display: 'flex', alignItems: 'center', gap: '.6rem',
                     textDecoration: 'none', color: 'inherit',
                     padding: '.85rem 0', borderBottom: '1px solid var(--rand-leise)' }}>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div className="reihe">
            <strong style={{ fontSize: '1.02rem' }}>{taet ? t(taet.text) : ''}</strong>
            <Marke art={auftrag.status === 'offen' ? 'offen' : 'fertig'}>
              {auftrag.status === 'offen' ? t('laeuft') : t('fertig')}
            </Marke>
          </div>
          <div className="leise">{chargeText(charge(auftrag.charge_nr))} · {zeit}</div>
        </div>
        <span aria-hidden="true" style={{ color: 'var(--text-leise)', fontSize: '1.2rem' }}>›</span>
      </Link>
    )
  }

  return (
    <>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      {!neuOffen && (
        <>
          <button className="haupt gross" style={{ width: '100%', marginTop: '1rem' }}
                  onClick={() => setNeuOffen(true)}>
            + {t('neuerAuftrag')}
          </button>
          {/* Lagerkontrolle: ohne Arbeit eine zufällig gegriffene Palette
              wiegen und nachsehen. Bewusst direkt auf dem Startbildschirm —
              eine Messung, die einen Umweg braucht, findet nicht statt. */}
          <button className="gross" style={{ width: '100%', marginTop: '.6rem' }}
                  onClick={() => navigate('/kontrolle')}>
            🔍 {t('kontrolle')}
          </button>
        </>
      )}
      {neuOffen && (
        <NeuerAuftrag chargen={chargen}
                      fertig={() => { setNeuOffen(false); void laden() }}
                      abbrechen={() => setNeuOffen(false)} />
      )}

      <Karte>
        {offen.length === 0
          ? <p className="leise" style={{ margin: 0 }}>{t('keinAuftrag')}</p>
          : offen.map(a => <Zeile key={a.id} auftrag={a} />)}
      </Karte>

      {fertig.length > 0 && (
        <Karte titel={t('zuletztFertig')}>
          {fertig.slice(0, 8).map(a => <Zeile key={a.id} auftrag={a} />)}
        </Karte>
      )}
    </>
  )
}

function NeuerAuftrag({ chargen, fertig, abbrechen }: {
  chargen: Charge[]; fertig: () => void; abbrechen: () => void
}) {
  const { t } = useSprache()
  const [taetigkeit, setTaetigkeit] = useState<string | null>(null)
  const [chargeNr, setChargeNr] = useState<number | ''>('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  const gewaehlt = TAETIGKEITEN.find(a => a.id === taetigkeit)

  async function anlegen() {
    if (!gewaehlt || chargeNr === '') return
    setLaeuft(true); setFehler(null)
    // Startzeit setzt der Server (Spec §10) — das Handy ist keine verlässliche
    // Uhr, und an der Startzeit hängt die Zuordnung der Sortier-CSVs.
    const { data, error } = await supabase.from('auftrag')
      .insert({ weg: gewaehlt.weg, station: gewaehlt.station, charge_nr: chargeNr })
      .select('id').single()
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }

    // Wer die Arbeit eröffnet, ist selbstverständlich dabei — sonst stünde beim
    // eigenen Auftrag „noch niemand" und ein Knopf zum Mitmachen.
    await supabase.from('auftrag_teilnehmer').insert({ auftrag_id: (data as { id: number }).id })
    setLaeuft(false)
    fertig()
  }

  return (
    <Karte>
      <div className="feld">
        <label>{t('wasMachstDu')}</label>
        <div style={{ display: 'grid', gap: '.5rem' }}>
          {TAETIGKEITEN.map(a => (
            <button key={a.id} type="button"
                    className={taetigkeit === a.id ? 'haupt' : ''}
                    style={{ minHeight: 58, fontSize: '1.05rem', justifyContent: 'flex-start' }}
                    onClick={() => setTaetigkeit(a.id)}>
              <span style={{ fontSize: '1.4rem', marginRight: '.6rem' }}>{a.zeichen}</span>
              {t(a.text)}
            </button>
          ))}
        </div>
      </div>

      {taetigkeit && (
        <div className="feld">
          <label htmlFor="charge">{t('charge')}</label>
          <select id="charge" value={chargeNr} style={{ fontSize: '1.05rem' }}
                  onChange={e => setChargeNr(e.target.value === '' ? '' : Number(e.target.value))}>
            <option value="">— {t('waehlen')} —</option>
            {chargen.map(c => <option key={c.nr} value={c.nr}>{chargeText(c)}</option>)}
          </select>
        </div>
      )}

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <div className="reihe" style={{ marginTop: '.5rem' }}>
        <button className="haupt" style={{ flex: 1, minHeight: 54 }}
                onClick={anlegen} disabled={laeuft || !taetigkeit || chargeNr === ''}>
          {t('starten')}
        </button>
        <button type="button" onClick={abbrechen}>{t('abbrechen')}</button>
      </div>
    </Karte>
  )
}
