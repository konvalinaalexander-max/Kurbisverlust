import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, einstellung, fehlerText, stammdaten } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import type { TextId } from '../lib/i18n'
import type { Auftrag, Charge, Gebinde } from '../lib/typen'

type Reiter = 'paletten' | 'faule' | 'ausschuss' | 'ausgang' | 'abschluss'

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

  const taet = taetigkeitVon(auftrag.weg, auftrag.station)
  const binDabei = teilnehmer.some(x => x.profil_id === session?.user.id)
  const gesperrt = auftrag.status === 'abgeschlossen'

  // Was an dieser Station überhaupt anfällt:
  //  · Beim Sortieren an der Maschine werden Paletten gezählt, aber nie gewogen.
  //  · Beim Waschen gibt es keine Paletten mehr — die Ware liegt längst in
  //    Kaliber-Kisten. Dort wird nur der ausgelesene Schimmel erfasst.
  //  · Auf der Hand-Linie wird gezählt und, wenn es sich ergibt, gewogen;
  //    dort fällt auch der Ausschuss nach Augenmaß an.
  const hatPaletten = auftrag.station !== 'waschen'
  const mitWiegen = auftrag.station === 'waschen_sortieren'
  const hatAusschuss = auftrag.weg === 'hand'
  // Gewaschen wird in neue Paletten gepackt — dort lässt sich nachwiegen,
  // wie viel Kürbis wirklich je Kiste ausgeliefert wird.
  const hatAusgang = auftrag.station === 'waschen' || auftrag.station === 'waschen_sortieren'

  const reiterListe: [Reiter, TextId][] = [
    ...(hatPaletten ? [['paletten', 'paletten'] as [Reiter, TextId]] : []),
    ['faule', 'faule'],
    ...(hatAusschuss ? [['ausschuss', 'kleinGross'] as [Reiter, TextId]] : []),
    ...(hatAusgang ? [['ausgang', 'fertigePalette'] as [Reiter, TextId]] : []),
    ['abschluss', 'abschluss'],
  ]
  const aktiverReiter = reiterListe.some(([r]) => r === reiter) ? reiter : reiterListe[0][0]

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

      {reiterListe.length > 1 && (
        <nav className="navleiste" style={{ position: 'static', borderRadius: 'var(--radius)',
                                            border: '1px solid var(--rand)' }}>
          {reiterListe.map(([r, id]) => (
            <a key={r} href="#" className={aktiverReiter === r ? 'aktiv' : ''}
               onClick={e => { e.preventDefault(); setReiter(r) }}>{t(id)}</a>
          ))}
        </nav>
      )}

      {gesperrt && <Hinweis>{t('gesperrt')}</Hinweis>}

      {aktiverReiter === 'paletten' && (
        <Paletten auftrag={auftrag} gesperrt={gesperrt} mitWiegen={mitWiegen} />
      )}
      {aktiverReiter === 'faule' && (
        <Mengen auftrag={auftrag} gesperrt={gesperrt} tabelle="schimmel_messung"
                titel={t('faule')} mitTeilgewicht />
      )}
      {aktiverReiter === 'ausschuss' && <Ausschuss auftrag={auftrag} gesperrt={gesperrt} />}
      {aktiverReiter === 'ausgang' && <FertigePalette auftrag={auftrag} gesperrt={gesperrt} />}
      {aktiverReiter === 'abschluss' && (
        <Abschluss auftrag={auftrag} neuLaden={laden} zurueck={() => navigate('/auftraege')} />
      )}
    </>
  )
}

/* ------------------------------------------------------------------ */
/* Paletten zählen — und dabei gleich fragen, ob gewogen wurde         */
/* ------------------------------------------------------------------ */
function Paletten({ auftrag, gesperrt, mitWiegen }: {
  auftrag: Auftrag; gesperrt: boolean; mitWiegen: boolean
}) {
  const { t } = useSprache()
  const [zeilen, setZeilen] = useState<{ id: number; wiegung_id: number | null }[]>([])
  const [zettelDatum, setZettelDatum] = useState('')
  const [frageOffen, setFrageOffen] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  const laden = useCallback(async () => {
    const { data, error } = await supabase.from('auftrag_palette')
      .select('id, wiegung_id').eq('auftrag_id', auftrag.id).order('ts')
    if (error) setFehler(fehlerText(error)); else setZeilen(data as typeof zeilen)
  }, [auftrag.id])
  useEffect(() => { void laden() }, [laden])

  async function nurZaehlen() {
    setLaeuft(true); setFrageOffen(false)
    const { error } = await supabase.from('auftrag_palette')
      .insert({ auftrag_id: auftrag.id, eingangsdatum: zettelDatum || null })
    setLaeuft(false)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  async function zurueck() {
    const letzte = zeilen[zeilen.length - 1]
    if (!letzte) return
    // Die Wägung hängt an der Palette und muss mit verschwinden, sonst bliebe
    // eine Messung ohne die Palette zurück, zu der sie gehört.
    if (letzte.wiegung_id) {
      await supabase.from('verdunstung_wiegung').delete().eq('id', letzte.wiegung_id)
    }
    const { error } = await supabase.from('auftrag_palette').delete().eq('id', letzte.id)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  const gewogen = zeilen.filter(z => z.wiegung_id !== null).length

  return (
    <>
      <Karte titel={t('paletten')}>
        <div className="zaehler">
          <button onClick={zurueck} disabled={gesperrt || zeilen.length === 0} aria-label="−">−</button>
          <span className="stand">{zeilen.length}</span>
          <button className="haupt" aria-label="+" disabled={gesperrt || laeuft}
                  onClick={() => (mitWiegen ? setFrageOffen(true) : void nurZaehlen())}>+</button>
        </div>
        <div className="feld" style={{ marginBottom: 0 }}>
          <label htmlFor="zettel">{t('datumZettel')}</label>
          <input id="zettel" type="date" value={zettelDatum} disabled={gesperrt}
                 onChange={e => setZettelDatum(e.target.value)} />
        </div>
        {gewogen > 0 && (
          <p className="leise" style={{ marginTop: '.6rem', marginBottom: 0 }}>
            {gewogen} × {t('gewogen')}
          </p>
        )}
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      </Karte>

      {frageOffen && (
        <WiegeDialog auftrag={auftrag} zettelDatum={zettelDatum}
                     nurZaehlen={nurZaehlen}
                     abbrechen={() => setFrageOffen(false)}
                     fertig={() => { setFrageOffen(false); void laden() }} />
      )}
    </>
  )
}

/**
 * Die Frage beim Zählen. Zuerst nur die Entscheidung — wer nicht wiegt, ist
 * mit einem Tipp fertig. Erst danach die Felder.
 *
 * Die Palette wird nicht aus einer Liste gesucht: Bei hunderten Paletten, von
 * denen viele gleich schwer sind, wäre das nicht bedienbar. Der Arbeiter tippt
 * ab, was auf dem Zettel steht.
 */
function WiegeDialog({ auftrag, zettelDatum, nurZaehlen, abbrechen, fertig }: {
  auftrag: Auftrag; zettelDatum: string
  nurZaehlen: () => Promise<void>; abbrechen: () => void; fertig: () => void
}) {
  const { t } = useSprache()
  const [wiegen, setWiegen] = useState(false)
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [datum, setDatum] = useState(zettelDatum)
  const [damals, setDamals] = useState('')
  const [jetzt, setJetzt] = useState('')
  const [kisten, setKisten] = useState('')
  const [art, setArt] = useState('')
  const [proKiste, setProKiste] = useState('')
  const [schimmel, setSchimmel] = useState(false)
  const [faul, setFaul] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void stammdaten().then(s => {
      setGebinde(s.gebinde)
      setArt(a => a || s.gebinde[0]?.art || '')
    })
  }, [])

  const vollstaendig = datum !== '' && damals !== '' && jetzt !== '' && kisten !== '' && art !== ''

  async function speichern() {
    if (!vollstaendig) return
    setLaeuft(true); setFehler(null)
    // Erst die Wägung, dann die Palette mit dem Verweis darauf — so gibt es
    // nie eine gezählte Palette, die auf eine Wägung zeigt, die es nicht gibt.
    const { data, error } = await supabase.from('verdunstung_wiegung').insert({
      auftrag_id: auftrag.id, charge_nr: auftrag.charge_nr,
      eingangsdatum: datum,
      brutto_damals_kg: Number(damals),
      brutto_jetzt_kg: Number(jetzt),
      kisten: Number(kisten),
      gebindeart: art,
      kuerbisse_pro_kiste: proKiste === '' ? null : Number(proKiste),
      sichtbar_schimmel: schimmel,
      // Der einzige Schimmelwert, dessen Palette nicht danach ausgewählt
      // wurde, wie sie aussieht — und damit der einzige, der die Kurve
      // gegen die Verarbeitungsreihenfolge absichert.
      faul_kg: schimmel && faul !== '' ? Number(faul) : null,
    }).select('id').single()
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }

    const { error: f2 } = await supabase.from('auftrag_palette').insert({
      auftrag_id: auftrag.id, eingangsdatum: datum,
      wiegung_id: (data as { id: number }).id,
    })
    setLaeuft(false)
    if (f2) { setFehler(fehlerText(f2)); return }
    fertig()
  }

  const tara = gebinde.find(g => g.art === art)
  const netto = kisten !== '' && jetzt !== '' && tara?.tara_kg_pro_kiste != null
    ? Number(jetzt) - Number(kisten) * tara.tara_kg_pro_kiste - (tara.tara_kg_palette ?? 0)
    : null

  return (
    <div className="dialog-hinter" onClick={abbrechen}>
      <div className="dialog" onClick={e => e.stopPropagation()}>
        {!wiegen ? (
          <>
            <h2 style={{ marginTop: 0, textAlign: 'center' }}>{t('palettenWiegenFrage')}</h2>
            <div style={{ display: 'grid', gap: '.6rem' }}>
              <button className="haupt gross" onClick={() => setWiegen(true)}>{t('jaWiegen')}</button>
              <button className="gross" onClick={() => void nurZaehlen()}>{t('nurZaehlen')}</button>
            </div>
          </>
        ) : (
          <>
            <div className="feld">
              <label htmlFor="w-datum">{t('eingangsdatum')}</label>
              <input id="w-datum" type="date" value={datum} onChange={e => setDatum(e.target.value)} />
            </div>
            <div className="feld">
              <label htmlFor="w-damals">{t('eingangsgewicht')}</label>
              <input id="w-damals" type="number" inputMode="decimal" step="0.1" min={0}
                     value={damals} onChange={e => setDamals(e.target.value)}
                     style={{ fontSize: '1.2rem' }} />
            </div>
            <div className="feld">
              <label htmlFor="w-jetzt">{t('gewichtJetzt')}</label>
              <input id="w-jetzt" type="number" inputMode="decimal" step="0.1" min={0}
                     value={jetzt} onChange={e => setJetzt(e.target.value)}
                     style={{ fontSize: '1.2rem' }} />
            </div>
            <div className="reihe">
              <div className="feld" style={{ flex: 1 }}>
                <label htmlFor="w-kisten">{t('anzahlKisten')}</label>
                <input id="w-kisten" type="number" inputMode="numeric" min={1}
                       value={kisten} onChange={e => setKisten(e.target.value)} />
              </div>
              <div className="feld" style={{ flex: 1 }}>
                <label htmlFor="w-art">{t('kistenart')}</label>
                <select id="w-art" value={art} onChange={e => setArt(e.target.value)}>
                  {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
                </select>
              </div>
            </div>
            <div className="feld">
              <label htmlFor="w-pro">{t('kuerbisseProKiste')} ({t('freiwillig')})</label>
              <input id="w-pro" type="number" inputMode="numeric" min={1}
                     value={proKiste} onChange={e => setProKiste(e.target.value)} />
            </div>

            {netto !== null && netto > 0 && (
              <p style={{ margin: '0 0 .6rem' }}>
                <strong>{(netto / Number(kisten)).toFixed(2)} kg</strong> {t('jeKiste')}
                {proKiste !== '' && Number(proKiste) > 0 && (
                  <> · <strong>{(netto / (Number(kisten) * Number(proKiste))).toFixed(2)} kg</strong>
                    {' '}{t('proKuerbis')}</>
                )}
              </p>
            )}

            <label style={{ display: 'flex', gap: '.5rem', alignItems: 'center', marginBottom: '.75rem' }}>
              <input type="checkbox" checked={schimmel} onChange={e => setSchimmel(e.target.checked)}
                     style={{ width: 22, height: 22, minHeight: 0 }} />
              {t('faulesSichtbar')}
            </label>

            {schimmel && (
              <div className="feld">
                <label htmlFor="w-faul">{t('wievielFaul')} ({t('freiwillig')})</label>
                <input id="w-faul" type="number" inputMode="decimal" step="0.5" min={0}
                       value={faul} onChange={e => setFaul(e.target.value)} />
              </div>
            )}

            {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
            <div className="reihe">
              <button className="haupt" style={{ flex: 1, minHeight: 54 }}
                      onClick={speichern} disabled={laeuft || !vollstaendig}>{t('eintragen')}</button>
              <button onClick={abbrechen}>{t('abbrechen')}</button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

/* ------------------------------------------------------------------ */
/* Kilo-Erfassung (Faule, zu klein, zu gross)                          */
/* ------------------------------------------------------------------ */
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

/* ------------------------------------------------------------------ */
/* Fertige Palette nach dem Waschen                                    */
/* ------------------------------------------------------------------ */
/**
 * Nach dem Waschen wird in neue Paletten gepackt. Die eine Zahl, die zählt:
 * wie viel Kürbis liegt wirklich in einer Kiste?
 *
 *   x = (Brutto − Palettentara − Kisten × Kistentara) / Kisten
 *
 * Bezahlt wird ein Fixpreis ab 8 kg je Kiste. Alles darüber ist verschenkte
 * Ware — kein Verlust, sondern Marge.
 */
function FertigePalette({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const { t } = useSprache()
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [soll, setSoll] = useState(8)
  const [brutto, setBrutto] = useState('')
  const [kisten, setKisten] = useState('')
  const [art, setArt] = useState('')
  const [proKiste, setProKiste] = useState('')
  const [zeilen, setZeilen] = useState<{ id: number; kg_pro_kiste: number | null
    ueberfuellung_je_kiste: number | null; kisten: number }[]>([])
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const [s, k] = await Promise.all([
      stammdaten(),
      supabase.from('v_ausgang_kennzahl')
        .select('id, kg_pro_kiste, ueberfuellung_je_kiste, kisten')
        .eq('auftrag_id', auftrag.id).order('ts'),
    ])
    setGebinde(s.gebinde)
    setArt(a => a || s.gebinde[0]?.art || '')
    setZeilen((k.data ?? []) as typeof zeilen)
    setSoll(await einstellung<number>('soll_kg_pro_kiste', 8))
  }, [auftrag.id])
  useEffect(() => { void laden() }, [laden])

  const tara = gebinde.find(g => g.art === art)
  const n = Number(kisten)
  const b = Number(brutto)
  // Dieselbe Rechnung wie in v_ausgang_kennzahl — hier nur, damit der Arbeiter
  // das Ergebnis sofort sieht. Gespeichert werden die Rohwerte, gerechnet wird
  // in der Datenbank.
  const netto = n > 0 && b > 0 && tara?.tara_kg_pro_kiste != null
    ? b - n * tara.tara_kg_pro_kiste - (tara.tara_kg_palette ?? 0)
    : null
  const x = netto !== null && netto > 0 ? netto / n : null

  async function speichern() {
    if (!(n > 0 && b > 0 && art)) return
    const { error } = await supabase.from('ausgang_wiegung').insert({
      auftrag_id: auftrag.id, charge_nr: auftrag.charge_nr,
      brutto_kg: b, kisten: n, gebindeart: art,
      kuerbisse_pro_kiste: proKiste === '' ? null : Number(proKiste),
    })
    if (error) { setFehler(fehlerText(error)); return }
    setBrutto(''); setKisten(''); setProKiste(''); setFehler(null)
    void laden()
  }

  return (
    <Karte titel={t('fertigePalette')}>
      <div className="feld">
        <label htmlFor="a-brutto">{t('gewicht')}</label>
        <input id="a-brutto" type="number" inputMode="decimal" step="0.1" min={0}
               value={brutto} disabled={gesperrt} onChange={e => setBrutto(e.target.value)}
               style={{ fontSize: '1.2rem' }} />
      </div>
      <div className="reihe">
        <div className="feld" style={{ flex: 1 }}>
          <label htmlFor="a-kisten">{t('anzahlKisten')}</label>
          <input id="a-kisten" type="number" inputMode="numeric" min={1}
                 value={kisten} disabled={gesperrt} onChange={e => setKisten(e.target.value)} />
        </div>
        <div className="feld" style={{ flex: 1 }}>
          <label htmlFor="a-art">{t('kistenart')}</label>
          <select id="a-art" value={art} disabled={gesperrt}
                  onChange={e => setArt(e.target.value)}>
            {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
          </select>
        </div>
      </div>
      <div className="feld">
        <label htmlFor="a-pro">{t('kuerbisseProKiste')} ({t('freiwillig')})</label>
        <input id="a-pro" type="number" inputMode="numeric" min={1}
               value={proKiste} disabled={gesperrt} onChange={e => setProKiste(e.target.value)} />
      </div>

      {x !== null && (
        <p style={{ fontSize: '1.15rem', margin: '0 0 .75rem' }}>
          <strong>{x.toFixed(2)} kg</strong> {t('jeKiste')}
          {x > soll && (
            <span style={{ color: 'var(--rot)' }}> · +{(x - soll).toFixed(2)} kg {t('zuViel')}</span>
          )}
          {proKiste !== '' && Number(proKiste) > 0 && netto !== null && (
            <> · <strong>{(netto / (n * Number(proKiste))).toFixed(2)} kg</strong> {t('proKuerbis')}</>
          )}
        </p>
      )}

      <button className="haupt" style={{ width: '100%', minHeight: 54 }}
              onClick={speichern} disabled={gesperrt || x === null}>{t('eintragen')}</button>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      {zeilen.length > 0 && (
        <>
          <p style={{ marginTop: '1rem' }}>
            <strong>{t('bisher')}: {zeilen.length}</strong>
          </p>
          <table>
            <tbody>
              {zeilen.map(z => (
                <tr key={z.id}>
                  <td>{z.kisten} × {t('kistenart').toLowerCase()}</td>
                  <td className="zahl">{z.kg_pro_kiste?.toFixed(2) ?? '—'} kg</td>
                  <td className="zahl" style={{ color: 'var(--rot)' }}>
                    {z.ueberfuellung_je_kiste != null && z.ueberfuellung_je_kiste > 0
                      ? `+${z.ueberfuellung_je_kiste.toFixed(2)}` : ''}
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

/* ------------------------------------------------------------------ */
function Abschluss({ auftrag, neuLaden, zurueck }: {
  auftrag: Auftrag; neuLaden: () => Promise<void>; zurueck: () => void
}) {
  const { t, gebietsschema } = useSprache()
  const [sicher, setSicher] = useState(false)
  const [abbruchSicher, setAbbruchSicher] = useState(false)
  const [durchsatz, setDurchsatz] = useState(auftrag.durchsatz_kg?.toString() ?? '')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  // Beim Waschen sind die Original-Paletten längst in Kaliber-Kisten aufgelöst;
  // ohne Mengenangabe hätte der dort ausgelesene Schimmel keinen Nenner.
  const brauchtDurchsatz = auftrag.station === 'waschen'

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

  // Abbrechen löscht nicht: Die erfassten Zeilen bleiben als Spur stehen,
  // zählen aber in keiner Auswertung mehr mit. Endgültig löschen kann später
  // der Betriebsleiter.
  async function abbrechen() {
    setLaeuft(true)
    const { error } = await supabase.rpc('auftrag_abbrechen',
      { p_auftrag_id: auftrag.id, p_grund: null })
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

      <div style={{ marginTop: '2rem', borderTop: '1px solid var(--rand)', paddingTop: '1rem' }}>
        {!abbruchSicher ? (
          <button className="gefahr" style={{ width: '100%' }}
                  onClick={() => setAbbruchSicher(true)}>{t('arbeitAbbrechen')}</button>
        ) : (
          <>
            <p className="leise">{t('wirklichAbbrechen')}</p>
            <div className="reihe">
              <button className="gefahr" style={{ flex: 1, minHeight: 54 }}
                      onClick={abbrechen} disabled={laeuft}>{t('jaAbbrechen')}</button>
              <button onClick={() => setAbbruchSicher(false)}>{t('abbrechen')}</button>
            </div>
          </>
        )}
      </div>
    </Karte>
  )
}
