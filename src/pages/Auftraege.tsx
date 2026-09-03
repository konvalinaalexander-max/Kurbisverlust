import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { TAETIGKEITEN, taetigkeitVon } from '../lib/taetigkeit'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import type { Auftrag, Charge, Kaeufer, Sortierschema } from '../lib/typen'

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
  const [kaeufer, setKaeufer] = useState<Kaeufer[]>([])
  const [kaeuferCode, setKaeuferCode] = useState('')
  const [neuerKaeufer, setNeuerKaeufer] = useState('')
  const [schemata, setSchemata] = useState<Sortierschema[]>([])
  const [kaliberIdx, setKaliberIdx] = useState<number | ''>('')
  const [art, setArt] = useState<'kaliber' | 'kiste' | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void supabase.from('kaeufer').select('*').eq('aktiv', true).order('name')
      .then(({ data }) => setKaeufer((data ?? []) as Kaeufer[]))
    void supabase.from('sortierschema').select('*').order('gilt_ab', { ascending: false })
      .then(({ data }) => setSchemata((data ?? []) as Sortierschema[]))
  }, [])

  const gewaehlt = TAETIGKEITEN.find(a => a.id === taetigkeit)
  // Der Käufer bestimmt das Sortierschema (Coop will es anders als Migros).
  // Beim Sortieren und auf der Hand-Linie ist er die eine Angabe, die das
  // Modell braucht, um die CSV nach den Regeln zu klassieren, die an diesem
  // Tag galten. Beim Waschen ist längst sortiert — dort fragt die Maske nicht.
  const fragtKaeufer = gewaehlt?.station !== 'waschen'

  // Beim Waschen liegt die Ware in Kaliber-Kisten, nicht auf Paletten. Damit
  // die verarbeitete Menge überhaupt bestimmbar wird, muss feststehen, welches
  // Kaliber gewaschen wird — das trägt ein, wer die Arbeit eröffnet. Die Bänder
  // stammen aus der zuletzt gültigen Fassung der Sorte; nach welcher Fassung
  // wirklich sortiert wurde, hält die Datenbank beim Anlegen fest.
  const fragtKaliber = gewaehlt?.station === 'waschen'
  const sorte = chargen.find(c => c.nr === chargeNr)?.sorte

  // Wie sortiert wird, entscheidet die Arbeit, nicht die Stammdaten: Auf der
  // Hand-Linie kommt die Ware aus der Trommel aufs Band, und die Arbeiter
  // sortieren nach der Regel, die hier festgelegt wird. An der Sortiermaschine
  // gilt die hinterlegte Fassung — bestätigt wird sie trotzdem, damit niemand
  // eine Woche lang nach Regeln erfasst, die an dem Tag nicht galten.
  const fragtArt = gewaehlt?.station === 'sortieren'
                || gewaehlt?.station === 'waschen_sortieren'

  // Die Fassung, die für Sorte, Käufer und Art heute gilt: die des Käufers,
  // sonst der Standard. Dieselbe Reihenfolge wie sortierschema_fuer() in der
  // Datenbank — hier nur, damit der Arbeiter sieht, was er bestätigt.
  const heute = new Date().toISOString().slice(0, 10)
  function fassung(fuerArt: 'kaliber' | 'kiste'): Sortierschema | undefined {
    const passend = schemata.filter(x => x.sorte === sorte && x.art === fuerArt
                                         && x.gilt_ab <= heute)
    return passend.find(x => x.kaeufer === (kaeuferCode || null))
        ?? passend.find(x => x.kaeufer === null)
        ?? schemata.find(x => x.sorte === sorte && x.art === fuerArt)
  }
  const fassungKaliber = fassung('kaliber')
  const fassungKiste = fassung('kiste')
  const gewaehlteFassung = art === null ? undefined
                         : art === 'kiste' ? fassungKiste : fassungKaliber

  const baender = fassungKaliber?.kaliber_baender ?? []

  async function anlegen() {
    if (!gewaehlt || chargeNr === '') return
    setLaeuft(true); setFehler(null)
    let code: string | null = kaeuferCode || null
    if (kaeuferCode === '__neu__') {
      const name = neuerKaeufer.trim()
      if (!name) { setLaeuft(false); setFehler(t('kaeuferName')); return }
      // Ein Käufer, den es noch nicht gibt, wird angelegt — Teil der Erfassung,
      // kein Stammdaten-Pflegefall. Der Code ist der Name, klein und ohne Leerzeichen.
      code = name.toLowerCase().replace(/[^a-z0-9äöü]+/g, '-').replace(/(^-|-$)/g, '')
      const { error } = await supabase.from('kaeufer')
        .upsert({ code, name }, { onConflict: 'code', ignoreDuplicates: true })
      if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    }
    // Startzeit setzt der Server (Spec §10) — das Handy ist keine verlässliche
    // Uhr, und an der Startzeit hängt die Zuordnung der Sortier-CSVs. Das
    // Sortierschema hält die Datenbank beim Anlegen fest (Auslöser).
    const { data, error } = await supabase.from('auftrag')
      .insert({ weg: gewaehlt.weg, station: gewaehlt.station, charge_nr: chargeNr,
                kaeufer: fragtKaeufer ? code : null,
                kaliber_idx: fragtKaliber && kaliberIdx !== '' ? kaliberIdx : null,
                // Die Fassung wird gewählt, nicht geraten. Ist keine da, setzt
                // sie der Auslöser in der Datenbank wie bisher.
                sortierschema_id: fragtArt ? (gewaehlteFassung?.id ?? null) : null })
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

      {taetigkeit && chargeNr !== '' && fragtKaeufer && (
        <div className="feld">
          <label htmlFor="kaeufer">{t('kaeufer')}</label>
          <select id="kaeufer" value={kaeuferCode} style={{ fontSize: '1.05rem' }}
                  onChange={e => { setKaeuferCode(e.target.value); setArt(null) }}>
            <option value="">— {t('ohneKaeufer')} —</option>
            {kaeufer.map(k => <option key={k.code} value={k.code}>{k.name}</option>)}
            <option value="__neu__">{t('kaeuferNeu')}</option>
          </select>
          {kaeuferCode === '__neu__' && (
            <input style={{ marginTop: '.5rem' }} placeholder={t('kaeuferName')}
                   value={neuerKaeufer} onChange={e => setNeuerKaeufer(e.target.value)} />
          )}
        </div>
      )}

      {taetigkeit && chargeNr !== '' && fragtArt && (
        <div className="feld">
          <label>{t('wieSortiert')}</label>
          <div style={{ display: 'grid', gap: '.5rem' }}>
            <button type="button" className={art === 'kiste' ? 'haupt' : ''}
                    style={{ minHeight: 58, justifyContent: 'flex-start', textAlign: 'left' }}
                    onClick={() => setArt('kiste')}>
              {t('artKiste')}
              {fassungKiste?.soll_kg_pro_kiste != null &&
                <span className="leise"> · {fassungKiste.soll_kg_pro_kiste} kg {t('jeKiste')}</span>}
            </button>
            <button type="button" className={art === 'kaliber' ? 'haupt' : ''}
                    style={{ minHeight: 58, justifyContent: 'flex-start', textAlign: 'left' }}
                    onClick={() => setArt('kaliber')}>
              {t('artKaliber')}
              {baender.length > 0 &&
                <span className="leise"> · {baender.length} {t('baender')}</span>}
            </button>
          </div>
          {gewaehlteFassung && (
            <p className="leise" style={{ marginTop: '.4rem', marginBottom: 0 }}>
              {t('fassungVom')} {gewaehlteFassung.gilt_ab}
              {gewaehlteFassung.kaeufer === null && ` (${t('standard')})`}
            </p>
          )}
          {art !== null && !gewaehlteFassung && (
            <Hinweis art="warnung">{t('keineFassung')}</Hinweis>
          )}
        </div>
      )}

      {taetigkeit && chargeNr !== '' && fragtKaliber && (
        <div className="feld">
          <label htmlFor="kaliber">{t('welchesKaliber')}</label>
          <select id="kaliber" value={kaliberIdx} style={{ fontSize: '1.05rem' }}
                  onChange={e => setKaliberIdx(e.target.value === '' ? '' : Number(e.target.value))}>
            <option value="">— {t('waehlen')} —</option>
            {baender.map(([von, bis], i) => (
              <option key={i} value={i}>{t('kaliber')} {i + 1} ({von}–{bis} g)</option>
            ))}
          </select>
          <p className="leise" style={{ marginTop: '.4rem', marginBottom: 0 }}>
            {t('welchesKaliberWarum')}
          </p>
        </div>
      )}

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <div className="reihe" style={{ marginTop: '.5rem' }}>
        <button className="haupt" style={{ flex: 1, minHeight: 54 }}
                onClick={anlegen}
                disabled={laeuft || !taetigkeit || chargeNr === ''
                          || (fragtArt && art === null)}>
          {t('starten')}
        </button>
        <button type="button" onClick={abbrechen}>{t('abbrechen')}</button>
      </div>
    </Karte>
  )
}
