import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import type { TextId } from '../lib/i18n'
import type { Auftrag, Charge } from '../lib/typen'

type Reiter = 'paletten' | 'faule' | 'ausschuss' | 'wiegen' | 'marge' | 'abschluss'

export default function AuftragDetail() {
  const { id } = useParams()
  const auftragId = Number(id)
  const navigate = useNavigate()
  const { session } = useAuth()
  const { t, gebietsschema } = useSprache()

  const [auftrag, setAuftrag] = useState<Auftrag | null>(null)
  const [charge, setCharge] = useState<Charge | undefined>()
  const [teilnehmer, setTeilnehmer] = useState<{ profil_id: string; name: string }[]>([])
  const [reiter, setReiter] = useState<Reiter>('paletten')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laedt, setLaedt] = useState(true)

  const laden = useCallback(async () => {
    try {
      const [{ chargen }, a, tn] = await Promise.all([
        stammdaten(),
        supabase.from('auftrag').select('*').eq('id', auftragId).maybeSingle(),
        supabase.from('auftrag_teilnehmer').select('profil_id, profil(name)')
          .eq('auftrag_id', auftragId).is('verlassen_ts', null),
      ])
      if (a.error) throw a.error
      const auf = a.data as Auftrag | null
      setAuftrag(auf)
      setCharge(chargen.find(c => c.nr === auf?.charge_nr))
      type Eintrag = { profil_id: string; profil: { name: string } | { name: string }[] | null }
      setTeilnehmer(((tn.data ?? []) as unknown as Eintrag[]).map(r => ({
        profil_id: r.profil_id,
        name: (Array.isArray(r.profil) ? r.profil[0]?.name : r.profil?.name) ?? '?',
      })))
      setFehler(null)
    } catch (f) { setFehler(fehlerText(f)) } finally { setLaedt(false) }
  }, [auftragId])

  useEffect(() => { void laden() }, [laden])

  if (laedt) return <Lade />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!auftrag) return <Hinweis art="warnung">{t('fehler')}</Hinweis>

  const istWeg2 = auftrag.weg === 'hand'
  const binDabei = teilnehmer.some(t => t.profil_id === session?.user.id)
  const gesperrt = auftrag.status === 'abgeschlossen'
  const taet = taetigkeitVon(auftrag.weg, auftrag.station)

  const reiterListe: [Reiter, TextId][] = [
    ['paletten', 'paletten'],
    ['faule', 'faule'],
    ...(istWeg2 ? [['ausschuss', 'kleinGross'] as [Reiter, TextId]] : []),
    ['wiegen', 'wiegen'],
    ...(istWeg2 ? [['marge', 'kisten'] as [Reiter, TextId]] : []),
    ['abschluss', 'abschluss'],
  ]

  return (
    <>
      <Karte>
        <div className="reihe">
          <h1 style={{ margin: 0, fontSize: '1.25rem' }}>
            {taet?.zeichen} {taet ? t(taet.text) : ''}
          </h1>
          <Marke art={gesperrt ? 'fertig' : 'offen'}>{gesperrt ? t('fertig') : t('laeuft')}</Marke>
        </div>
        <p className="leise" style={{ margin: '.3rem 0 0' }}>
          {chargeText(charge)} · {t('seit')}{' '}
          {new Date(auftrag.start_ts).toLocaleString(gebietsschema,
            { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}
        </p>
        <p className="leise" style={{ margin: '.2rem 0 0' }}>
          {t('dabei')}: {teilnehmer.length ? teilnehmer.map(x => x.name).join(', ') : t('niemand')}
        </p>
        {!binDabei && !gesperrt && (
          <button className="haupt" style={{ width: '100%', marginTop: '.75rem' }}
                  onClick={async () => {
                    const { error } = await supabase.from('auftrag_teilnehmer')
                      .insert({ auftrag_id: auftragId })
                    if (error) setFehler(fehlerText(error)); else void laden()
                  }}>
            {t('mitmachen')}
          </button>
        )}
      </Karte>

      <nav className="navleiste" style={{ position: 'static', borderRadius: 'var(--radius)',
                                          border: '1px solid var(--rand)' }}>
        {reiterListe.map(([r, id]) => (
          <a key={r} href="#" className={reiter === r ? 'aktiv' : ''}
             onClick={e => { e.preventDefault(); setReiter(r) }}>{t(id)}</a>
        ))}
      </nav>

      {gesperrt && <Hinweis>{t('gesperrt')}</Hinweis>}

      {reiter === 'paletten' && <Paletten auftrag={auftrag} gesperrt={gesperrt} />}
      {reiter === 'faule' && (
        <Mengen auftrag={auftrag} gesperrt={gesperrt} tabelle="schimmel_messung"
                titel={t('faule')} mitTeilgewicht />
      )}
      {reiter === 'ausschuss' && <Ausschuss auftrag={auftrag} gesperrt={gesperrt} />}
      {reiter === 'wiegen' && <Wiegen auftrag={auftrag} gesperrt={gesperrt} />}
      {reiter === 'marge' && <Ueberfuellung auftrag={auftrag} gesperrt={gesperrt} />}
      {reiter === 'abschluss' && (
        <Abschluss auftrag={auftrag} neuLaden={laden} zurueck={() => navigate('/auftraege')} />
      )}
    </>
  )
}

/* ---------- Paletten zählen ---------- */
function Paletten({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const { t } = useSprache()
  const [zeilen, setZeilen] = useState<{ id: number; eingangsdatum: string | null }[]>([])
  const [zettelDatum, setZettelDatum] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  const laden = useCallback(async () => {
    const { data, error } = await supabase.from('auftrag_palette')
      .select('id, eingangsdatum').eq('auftrag_id', auftrag.id).order('ts')
    if (error) setFehler(fehlerText(error)); else setZeilen(data as typeof zeilen)
  }, [auftrag.id])
  useEffect(() => { void laden() }, [laden])

  async function hinzu() {
    setLaeuft(true)
    const { error } = await supabase.from('auftrag_palette')
      .insert({ auftrag_id: auftrag.id, eingangsdatum: zettelDatum || null })
    setLaeuft(false)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  async function zurueck() {
    const letzte = zeilen[zeilen.length - 1]
    if (!letzte) return
    const { error } = await supabase.from('auftrag_palette').delete().eq('id', letzte.id)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  return (
    <Karte titel={t('paletten')}>
      <div className="zaehler">
        <button onClick={zurueck} disabled={gesperrt || zeilen.length === 0} aria-label="−">−</button>
        <span className="stand">{zeilen.length}</span>
        <button className="haupt" onClick={hinzu} disabled={gesperrt || laeuft} aria-label="+">+</button>
      </div>
      <div className="feld" style={{ marginBottom: 0 }}>
        <label htmlFor="zettel">{t('datumZettel')}</label>
        <input id="zettel" type="date" value={zettelDatum} disabled={gesperrt}
               onChange={e => setZettelDatum(e.target.value)} />
      </div>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </Karte>
  )
}

/* ---------- Kilo-Erfassung (Faule, zu klein, zu gross) ---------- */
function Mengen({ auftrag, gesperrt, tabelle, titel, zusatz, filter, mitTeilgewicht }: {
  auftrag: Auftrag; gesperrt: boolean; tabelle: string; titel: string
  zusatz?: Record<string, unknown>; filter?: Record<string, string>; mitTeilgewicht?: boolean
}) {
  const { t, gebietsschema } = useSprache()
  const [zeilen, setZeilen] = useState<{ id: number; kg: number; ts: string; teilgewicht?: boolean }[]>([])
  const [wert, setWert] = useState('')
  const [teil, setTeil] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const filterSchluessel = JSON.stringify(filter ?? {})

  const laden = useCallback(async () => {
    let abfrage = supabase.from(tabelle).select('*').eq('auftrag_id', auftrag.id).order('ts')
    for (const [k, v] of Object.entries(JSON.parse(filterSchluessel) as Record<string, string>)) {
      abfrage = abfrage.eq(k, v)
    }
    const { data, error } = await abfrage
    if (error) setFehler(fehlerText(error)); else setZeilen(data as typeof zeilen)
  }, [auftrag.id, tabelle, filterSchluessel])
  useEffect(() => { void laden() }, [laden])

  async function speichern() {
    const n = Number(wert)
    if (!Number.isInteger(n) || n < 0) { setFehler(t('ganzeZahl')); return }
    const { error } = await supabase.from(tabelle).insert({
      auftrag_id: auftrag.id, kg: n, ...(zusatz ?? {}),
      ...(mitTeilgewicht ? { teilgewicht: teil } : {}),
    })
    if (error) { setFehler(fehlerText(error)); return }
    setWert(''); setTeil(false); setFehler(null); void laden()
  }

  const summe = zeilen.reduce((s, z) => s + z.kg, 0)

  return (
    <Karte titel={titel}>
      <div className="reihe" style={{ alignItems: 'flex-end' }}>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor={`kg-${tabelle}`}>{t('kilo')}</label>
          <input id={`kg-${tabelle}`} type="number" inputMode="numeric" min={0} step={1}
                 value={wert} disabled={gesperrt} onChange={e => setWert(e.target.value)}
                 style={{ fontSize: '1.2rem' }} />
        </div>
        <button className="haupt" style={{ minHeight: 54 }}
                onClick={speichern} disabled={gesperrt || wert === ''}>{t('eintragen')}</button>
      </div>
      {mitTeilgewicht && (
        <label style={{ display: 'flex', gap: '.5rem', alignItems: 'center', marginTop: '.6rem' }}>
          <input type="checkbox" checked={teil} disabled={gesperrt}
                 onChange={e => setTeil(e.target.checked)} style={{ width: 22, height: 22, minHeight: 0 }} />
          {t('boxWarVoll')}
        </label>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      {zeilen.length > 0 && (
        <>
          <p style={{ marginTop: '1rem' }}><strong>{t('bisher')}: {summe} kg</strong></p>
          <table>
            <tbody>
              {zeilen.map(z => (
                <tr key={z.id}>
                  <td>{new Date(z.ts).toLocaleTimeString(gebietsschema,
                        { hour: '2-digit', minute: '2-digit' })}</td>
                  <td className="zahl">{z.kg} kg</td>
                  <td style={{ textAlign: 'right' }}>
                    <button className="gefahr" style={{ minHeight: 32, padding: '.2rem .5rem' }}
                            disabled={gesperrt}
                            onClick={async () => {
                              const { error } = await supabase.from(tabelle).delete().eq('id', z.id)
                              if (error) setFehler(fehlerText(error)); else void laden()
                            }}>✕</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </Karte>
  )
}

function Ausschuss({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const { t } = useSprache()
  const [art, setArt] = useState<'zu_klein' | 'zu_gross'>('zu_klein')
  return (
    <>
      <div className="reihe" style={{ marginTop: '1rem' }}>
        <button className={art === 'zu_klein' ? 'haupt' : ''} style={{ flex: 1, minHeight: 54 }}
                onClick={() => setArt('zu_klein')}>{t('zuKlein')}</button>
        <button className={art === 'zu_gross' ? 'haupt' : ''} style={{ flex: 1, minHeight: 54 }}
                onClick={() => setArt('zu_gross')}>{t('zuGross')}</button>
      </div>
      <Mengen key={art} auftrag={auftrag} gesperrt={gesperrt} tabelle="ausschuss_messung"
              titel={art === 'zu_klein' ? t('zuKlein') : t('zuGross')}
              zusatz={{ art }} filter={{ art }} />
    </>
  )
}

/* ---------- Palette wiegen ---------- */
interface PaletteZeile {
  id: number; eingangsdatum: string; brutto_kg: number
  kisten: number | null; gebindeart: string | null
}

function Wiegen({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const { t, gebietsschema } = useSprache()
  const [paletten, setPaletten] = useState<PaletteZeile[]>([])
  const [palettenId, setPalettenId] = useState<number | ''>('')
  const [jetzt, setJetzt] = useState('')
  const [schimmel, setSchimmel] = useState(false)
  const [anzahl, setAnzahl] = useState(0)
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const [p, w] = await Promise.all([
      supabase.from('palette').select('id, eingangsdatum, brutto_kg, kisten, gebindeart')
        .eq('charge_nr', auftrag.charge_nr).order('eingangsdatum'),
      supabase.from('verdunstung_wiegung').select('id').eq('auftrag_id', auftrag.id),
    ])
    setPaletten((p.data ?? []) as PaletteZeile[])
    setAnzahl((w.data ?? []).length)
  }, [auftrag.id, auftrag.charge_nr])
  useEffect(() => { void laden() }, [laden])

  const gewaehlt = paletten.find(p => p.id === palettenId)

  async function speichern() {
    if (!gewaehlt || jetzt === '') return
    const { error } = await supabase.from('verdunstung_wiegung').insert({
      auftrag_id: auftrag.id, charge_nr: auftrag.charge_nr, palette_id: gewaehlt.id,
      eingangsdatum: gewaehlt.eingangsdatum, brutto_damals_kg: gewaehlt.brutto_kg,
      brutto_jetzt_kg: Number(jetzt), kisten: gewaehlt.kisten,
      gebindeart: gewaehlt.gebindeart, sichtbar_schimmel: schimmel,
    })
    if (error) { setFehler(fehlerText(error)); return }
    setJetzt(''); setPalettenId(''); setSchimmel(false); setFehler(null)
    void laden()
  }

  if (paletten.length === 0) {
    return <Karte titel={t('wiegen')}><p className="leise">{t('keinePaletten')}</p></Karte>
  }

  return (
    <Karte titel={t('wiegen')}>
      <div className="feld">
        <label htmlFor="pal">{t('welchePalette')}</label>
        <select id="pal" value={palettenId} disabled={gesperrt}
                onChange={e => setPalettenId(e.target.value === '' ? '' : Number(e.target.value))}>
          <option value="">— {t('waehlen')} —</option>
          {paletten.map(p => (
            <option key={p.id} value={p.id}>
              {new Date(p.eingangsdatum).toLocaleDateString(gebietsschema)} · {p.brutto_kg} kg
            </option>
          ))}
        </select>
      </div>

      <div className="reihe" style={{ alignItems: 'flex-end' }}>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor="jetzt">{t('gewichtJetzt')}</label>
          <input id="jetzt" type="number" inputMode="decimal" step="0.1" min={0}
                 value={jetzt} disabled={gesperrt || !gewaehlt}
                 onChange={e => setJetzt(e.target.value)} style={{ fontSize: '1.2rem' }} />
        </div>
        <button className="haupt" style={{ minHeight: 54 }} onClick={speichern}
                disabled={gesperrt || !gewaehlt || jetzt === ''}>{t('eintragen')}</button>
      </div>

      <label style={{ display: 'flex', gap: '.5rem', alignItems: 'center', marginTop: '.6rem' }}>
        <input type="checkbox" checked={schimmel} disabled={gesperrt}
               onChange={e => setSchimmel(e.target.checked)} style={{ width: 22, height: 22, minHeight: 0 }} />
        {t('faulesSichtbar')}
      </label>

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {anzahl > 0 && <p style={{ marginTop: '1rem' }}><strong>{t('bisher')}: {anzahl}</strong></p>}
    </Karte>
  )
}

/* ---------- Kisten wiegen (Überfüllung) ---------- */
function Ueberfuellung({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const { t } = useSprache()
  const [kisten, setKisten] = useState('')
  const [gewicht, setGewicht] = useState('')
  const [zeilen, setZeilen] = useState<{ id: number; wert: number; n_kisten: number | null }[]>([])
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const { data } = await supabase.from('marge_messung').select('id, wert, n_kisten')
      .eq('auftrag_id', auftrag.id).eq('art', 'ueberfuellung').order('ts')
    setZeilen((data ?? []) as typeof zeilen)
  }, [auftrag.id])
  useEffect(() => { void laden() }, [laden])

  const n = Number(kisten)
  const g = Number(gewicht)
  // Bezahlt wird ein Fixpreis ab 8 kg je Kiste; alles darüber ist verschenkt.
  const ueberschuss = n > 0 && g > 0 ? g - n * 8 : null

  async function speichern() {
    if (ueberschuss === null) return
    const { error } = await supabase.from('marge_messung').insert({
      auftrag_id: auftrag.id, art: 'ueberfuellung', wert: ueberschuss, n_kisten: n,
    })
    if (error) { setFehler(fehlerText(error)); return }
    setKisten(''); setGewicht(''); setFehler(null); void laden()
  }

  const summe = zeilen.reduce((s, z) => s + z.wert, 0)
  const kistenGesamt = zeilen.reduce((s, z) => s + (z.n_kisten ?? 0), 0)

  return (
    <Karte titel={t('kisten')}>
      <div className="reihe" style={{ alignItems: 'flex-end' }}>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor="nk">{t('anzahlKisten')}</label>
          <input id="nk" type="number" inputMode="numeric" min={1} value={kisten}
                 disabled={gesperrt} onChange={e => setKisten(e.target.value)} />
        </div>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor="gw">{t('gewichtZusammen')}</label>
          <input id="gw" type="number" inputMode="decimal" step="0.1" min={0} value={gewicht}
                 disabled={gesperrt} onChange={e => setGewicht(e.target.value)} />
        </div>
      </div>
      {ueberschuss !== null && n > 0 && (
        <p style={{ marginTop: '.6rem', fontSize: '1.1rem' }}>
          <strong>{(g / n).toFixed(2)} kg</strong> {t('jeKiste')}
        </p>
      )}
      <button className="haupt" style={{ width: '100%', marginTop: '.5rem', minHeight: 54 }}
              onClick={speichern} disabled={gesperrt || ueberschuss === null}>{t('eintragen')}</button>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {kistenGesamt > 0 && (
        <p style={{ marginTop: '1rem' }}>
          <strong>{t('bisher')}: {kistenGesamt} {t('kisten').toLowerCase()}</strong>
          {' · '}{(summe / kistenGesamt).toFixed(2)} kg {t('jeKiste')}
        </p>
      )}
    </Karte>
  )
}

/* ---------- Abschluss ---------- */
function Abschluss({ auftrag, neuLaden, zurueck }: {
  auftrag: Auftrag; neuLaden: () => Promise<void>; zurueck: () => void
}) {
  const { t, gebietsschema } = useSprache()
  const [sicher, setSicher] = useState(false)
  const [durchsatz, setDurchsatz] = useState(auftrag.durchsatz_kg?.toString() ?? '')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  // Beim Waschen auf der Maschinen-Linie sind die Original-Paletten längst in
  // Kaliber-Kisten aufgelöst; ohne Mengenangabe hätte der dort ausgelesene
  // Schimmel keinen Nenner.
  const brauchtDurchsatz = auftrag.weg === 'maschine' && auftrag.station === 'waschen'

  async function abschliessen() {
    setLaeuft(true)
    const { error } = await supabase.from('auftrag').update({
      durchsatz_kg: durchsatz === '' ? null : Number(durchsatz),
      status: 'abgeschlossen', ende_ts: new Date().toISOString(),
    }).eq('id', auftrag.id)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    await neuLaden()
    zurueck()
  }

  if (auftrag.status === 'abgeschlossen') {
    return (
      <Karte>
        <p style={{ margin: 0 }}>
          {t('abgeschlossenAm')}{' '}
          {new Date(auftrag.ende_ts!).toLocaleString(gebietsschema,
            { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}
        </p>
      </Karte>
    )
  }

  return (
    <Karte>
      {brauchtDurchsatz && (
        <div className="feld">
          <label htmlFor="ds">{t('mengeVerarbeitet')}</label>
          <input id="ds" type="number" inputMode="decimal" step="1" min={0} value={durchsatz}
                 onChange={e => setDurchsatz(e.target.value)} style={{ fontSize: '1.2rem' }} />
        </div>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {!sicher ? (
        <button className="haupt gross" style={{ width: '100%' }} onClick={() => setSicher(true)}>
          {t('arbeitFertig')}
        </button>
      ) : (
        <div className="reihe">
          <button className="haupt" style={{ flex: 1, minHeight: 58 }}
                  onClick={abschliessen} disabled={laeuft}>{t('jaFertig')}</button>
          <button onClick={() => setSicher(false)}>{t('abbrechen')}</button>
        </div>
      )}
    </Karte>
  )
}
