import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, einstellung, fehlerText, stammdaten } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import type { TextId } from '../lib/i18n'
import type { Auftrag, AuftragGebinde, Charge, Gebinde } from '../lib/typen'

type Reiter = 'paletten' | 'kisten' | 'faule' | 'ausschuss' | 'ausgang' | 'abschluss'

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
  // AB-02: Der Palox wird zu Beginn und beim Abschluss abgelesen. Ohne
  // Ablesung landet der Schimmel zweier Arbeiten auf einer. Wir zählen die
  // Ablesungen dieser Arbeit, um zu Beginn hinzuführen und den Abschluss zu
  // sperren, solange keine da ist.
  const [nPalox, setNPalox] = useState<number | null>(null)
  // AB-05: Angaben zu den Ausschuss-Paletten (leer zu Beginn? alles von dieser
  // Arbeit?). Beides sind Messwerte über die Verlässlichkeit des Ausschusses.
  const [angaben, setAngaben] = useState<Record<string, string>>({})

  const laden = useCallback(async () => {
    try {
      const [{ chargen }, a, tn, sm, an] = await Promise.all([
        stammdaten(),
        supabase.from('auftrag').select('*').eq('id', auftragId).maybeSingle(),
        supabase.from('auftrag_teilnehmer').select('profil_id, profil(name)')
          .eq('auftrag_id', auftragId).is('verlassen_ts', null),
        supabase.from('schimmel_messung').select('id', { count: 'exact', head: false })
          .eq('auftrag_id', auftragId),
        supabase.from('v_auftrag_angabe').select('schluessel, wert').eq('auftrag_id', auftragId),
      ])
      if (a.error) throw a.error
      setNPalox(((sm.data ?? []) as unknown[]).length)
      const av = (an.data ?? []) as { schluessel: string; wert: string }[]
      setAngaben(Object.fromEntries(av.map(x => [x.schluessel, x.wert])))
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

  const taet = taetigkeitVon(auftrag.weg, auftrag.station, auftrag.ist_fax)
  const binDabei = teilnehmer.some(x => x.profil_id === session?.user.id)
  const gesperrt = auftrag.status === 'abgeschlossen'
  async function angabeSetzen(schluessel: string, wert: string) {
    const { error } = await supabase.from('auftrag_angabe')
      .insert({ auftrag_id: auftragId, schluessel, wert })
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  // Was an dieser Station überhaupt anfällt:
  //  · Beim Sortieren an der Maschine werden Paletten gezählt, aber nie gewogen.
  //  · Beim Waschen gibt es keine Paletten mehr — die Ware liegt längst in
  //    Kaliber-Kisten. Dort wird nur der ausgelesene Schimmel erfasst.
  //  · Auf der Hand-Linie wird gezählt und, wenn es sich ergibt, gewogen;
  //    dort fällt auch der Ausschuss nach Augenmaß an.
  const hatPaletten = auftrag.station !== 'waschen'
  // Kisten: Beim Waschen sind sie die einzige Mengenangabe, die es dort gibt.
  // Beim Sortieren werden sie gezählt, damit überhaupt bekannt wird, was eine
  // Kiste wiegt — die Masse je Kaliber steht in der CSV, die Kistenzahl nicht.
  // Auf der Hand-Linie gibt es keine Kaliber-Kisten; dort geht die Ware direkt raus.
  const hatKisten = auftrag.station !== 'waschen_sortieren'
  const mitWiegen = auftrag.station === 'waschen_sortieren'
  const hatAusschuss = auftrag.weg === 'hand'
  // Gewaschen wird in neue Paletten gepackt — dort lässt sich nachwiegen,
  // wie viel Kürbis wirklich je Kiste ausgeliefert wird.
  const hatAusgang = auftrag.station === 'waschen' || auftrag.station === 'waschen_sortieren'

  const reiterListe: [Reiter, TextId][] = [
    ...(hatPaletten ? [['paletten', 'paletten'] as [Reiter, TextId]] : []),
    ...(hatKisten ? [['kisten', 'kaliberKisten'] as [Reiter, TextId]] : []),
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
        <nav className="navleiste unter">
          {reiterListe.map(([r, id]) => (
            <a key={r} href="#" className={aktiverReiter === r ? 'aktiv' : ''}
               onClick={e => { e.preventDefault(); setReiter(r) }}>{t(id)}</a>
          ))}
        </nav>
      )}

      {gesperrt && <Hinweis>{t('gesperrt')}</Hinweis>}

      {!gesperrt && nPalox === 0 && aktiverReiter !== 'faule' && (
        <Hinweis art="warnung">
          {t('paloxZuBeginn')}{' '}
          <a href="#" onClick={e => { e.preventDefault(); setReiter('faule') }}>{t('jetztAblesen')}</a>
        </Hinweis>
      )}

      {!gesperrt && hatAusschuss && angaben['ausschuss_leer'] === undefined && (
        <Karte titel={t('ausschussLeerFrage')}>
          <p className="leise" style={{ marginTop: 0 }}>{t('ausschussLeerWarum')}</p>
          <div className="reihe">
            <button className="haupt" style={{ flex: 1, minHeight: 50 }}
                    onClick={() => void angabeSetzen('ausschuss_leer', 'true')}>{t('ja')}</button>
            <button style={{ flex: 1, minHeight: 50 }}
                    onClick={() => void angabeSetzen('ausschuss_leer', 'false')}>{t('nein')}</button>
          </div>
        </Karte>
      )}

      {aktiverReiter === 'paletten' && (
        <Paletten auftrag={auftrag} gesperrt={gesperrt} mitWiegen={mitWiegen} />
      )}
      {aktiverReiter === 'kisten' && <Kisten auftrag={auftrag} gesperrt={gesperrt} />}
      {aktiverReiter === 'faule' && (
        <Palox auftrag={auftrag} gesperrt={gesperrt} neuLaden={laden} />
      )}
      {aktiverReiter === 'ausschuss' && <Ausschuss auftrag={auftrag} gesperrt={gesperrt} />}
      {aktiverReiter === 'ausgang' && <FertigePalette auftrag={auftrag} gesperrt={gesperrt} />}
      {aktiverReiter === 'abschluss' && (
        <Abschluss auftrag={auftrag} neuLaden={laden} zurueck={() => navigate('/auftraege')}
                   paloxGelesen={(nPalox ?? 0) > 0} zumPalox={() => setReiter('faule')}
                   hatAusschuss={hatAusschuss} angaben={angaben} />
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
      .insert({ auftrag_id: auftrag.id, eingangsdatum: zettelDatum })
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
          <button className="haupt" aria-label="+" disabled={gesperrt || laeuft || zettelDatum === ''}
                  onClick={() => (mitWiegen ? setFrageOffen(true) : void nurZaehlen())}>+</button>
        </div>
        <div className="feld" style={{ marginBottom: 0 }}>
          <label htmlFor="zettel">{t('datumZettel')}</label>
          <input id="zettel" type="date" value={zettelDatum} disabled={gesperrt}
                 onChange={e => setZettelDatum(e.target.value)} />
          {zettelDatum === '' && !gesperrt && (
            <p className="leise" style={{ marginTop: '.4rem', marginBottom: 0 }}>
              {t('datumZettelPflicht')}
            </p>
          )}
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

            <label className="ankreuzen" style={{ marginBottom: '.5rem' }}>
              <input type="checkbox" checked={schimmel} onChange={e => setSchimmel(e.target.checked)} />
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

/**
 * Faules wiegen. Der Palox steht auf einer Waage und läuft über mehrere
 * Arbeiten weiter — der Arbeiter soll ablesen, was draufsteht, und nicht im
 * Kopf die Differenz zum letzten Mal bilden. Die Software zieht ab und zeigt
 * ihm das Ergebnis, bevor er speichert.
 */
/** Kisten zählen. Beim Waschen für das eine Kaliber, das die Arbeit wäscht;
 *  beim Sortieren je Kaliberband, denn dort entsteht die Messung, aus der das
 *  Kistengewicht überhaupt bekannt wird. Gespeichert wird die Zahl — was eine
 *  Kiste wiegt, rechnet die Datenbank aus CSV-Masse und Zählung. */
function Kisten({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const { t } = useSprache()
  const [zeilen, setZeilen] = useState<AuftragGebinde[]>([])
  const [baender, setBaender] = useState<[number, number][]>([])
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  const laden = useCallback(async () => {
    const { data, error } = await supabase.from('auftrag_gebinde')
      .select('*').eq('auftrag_id', auftrag.id).order('kaliber_idx')
    if (error) setFehler(fehlerText(error)); else setZeilen((data ?? []) as AuftragGebinde[])
  }, [auftrag.id])

  useEffect(() => { void laden() }, [laden])
  useEffect(() => {
    if (auftrag.sortierschema_id === null) return
    void supabase.from('sortierschema').select('kaliber_baender')
      .eq('id', auftrag.sortierschema_id).single()
      .then(({ data }) => setBaender(((data as { kaliber_baender: [number, number][] } | null)
                                      ?.kaliber_baender) ?? []))
  }, [auftrag.sortierschema_id])

  async function setzen(idx: number, wert: number) {
    if (wert < 0) return
    setLaeuft(true)
    const { error } = await supabase.from('auftrag_gebinde')
      .upsert({ auftrag_id: auftrag.id, kaliber_idx: idx, anzahl: wert },
              { onConflict: 'auftrag_id,kaliber_idx' })
    setLaeuft(false)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  const anzahlVon = (idx: number) => zeilen.find(z => z.kaliber_idx === idx)?.anzahl ?? 0
  // Beim Waschen zählt nur das Kaliber der Arbeit; beim Sortieren alle Bänder.
  const indizes = auftrag.station === 'waschen'
    ? (auftrag.kaliber_idx === null ? [] : [auftrag.kaliber_idx])
    : baender.map((_, i) => i)

  return (
    <Karte titel={t('kaliberKisten')}>
      <p className="leise" style={{ marginTop: 0 }}>
        {auftrag.station === 'waschen' ? t('kistenWaschenWarum') : t('kistenSortierenWarum')}
      </p>

      {auftrag.station === 'waschen' && auftrag.kaliber_idx === null && (
        <Hinweis art="warnung">{t('kistenOhneKaliber')}</Hinweis>
      )}

      {indizes.map(i => (
        <div key={i} style={{ marginBottom: '.9rem' }}>
          <label>
            {t('kaliber')} {i + 1}
            {baender[i] && <span className="leise"> ({baender[i][0]}–{baender[i][1]} g)</span>}
          </label>
          <div className="zaehler">
            <button onClick={() => void setzen(i, anzahlVon(i) - 1)}
                    disabled={gesperrt || laeuft || anzahlVon(i) === 0} aria-label="−">−</button>
            <span className="stand">{anzahlVon(i)}</span>
            <button className="haupt" aria-label="+" disabled={gesperrt || laeuft}
                    onClick={() => void setzen(i, anzahlVon(i) + 1)}>+</button>
          </div>
        </div>
      ))}

      {indizes.length === 0 && auftrag.kaliber_idx !== null && (
        <Hinweis>{t('kistenKeineBaender')}</Hinweis>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </Karte>
  )
}


function Palox({ auftrag, gesperrt, neuLaden }: { auftrag: Auftrag; gesperrt: boolean; neuLaden?: () => Promise<void> }) {
  const { t, gebietsschema } = useSprache()
  const [zeilen, setZeilen] = useState<{ id: number; kg: number; ts: string }[]>([])
  const [vorher, setVorher] = useState<number | null>(null)
  const [nPaletten, setNPaletten] = useState(0)
  const [stand, setStand] = useState('')
  const [leerGemeldet, setLeerGemeldet] = useState(false)
  const [tara, setTara] = useState(0)
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const [z, v, ap, t] = await Promise.all([
      supabase.from('schimmel_messung').select('*').eq('auftrag_id', auftrag.id).order('ts'),
      // Der Stand gilt je Station: Sortierband, Waschbecken und Hand-Linie
      // haben je einen eigenen Palox auf eigener Waage.
      supabase.rpc('palox_letzter_stand', { p_station: auftrag.station }),
      supabase.from('auftrag_palette').select('id', { count: 'exact', head: true })
        .eq('auftrag_id', auftrag.id),
      // Die Waage zeigt brutto: Behälter plus Inhalt. Bei der Differenz
      // zweier Stände kürzt sich der Behälter weg; ist der Stand selbst die
      // Menge (erste Ablesung, geleert), muss er heraus.
      einstellung<number>('palox_tara_kg', 0),
    ])
    if (z.error) setFehler(fehlerText(z.error)); else setZeilen(z.data as typeof zeilen)
    setVorher(typeof v.data === 'number' ? v.data : null)
    setNPaletten(ap.count ?? 0)
    setTara(Number(t) || 0)
  }, [auftrag.id, auftrag.station])
  useEffect(() => { void laden() }, [laden])

  const n = stand === '' ? null : Number(stand)
  // Fällt der Stand, wurde der Palox zwischendurch geleert — dann ist der
  // neue Stand (ohne Behälter) selbst die Menge. Wurde er geleert und danach
  // ÜBER den alten Stand befüllt, sieht die Zahlenreihe harmlos aus: dafür
  // ist das Häkchen. Dieselbe Rechnung wie v_palox_stand in der Datenbank —
  // hier nur, damit der Arbeiter sieht, was er gleich speichert.
  const geleert = leerGemeldet || (n !== null && vorher !== null && n < vorher)
  const menge = n === null ? null
    : vorher === null || geleert ? n - tara : n - vorher

  // Die Prüfgrösse des Betriebs: kg Faules je gezählter Palette. Deutlich zu
  // viel heisst meist, dass eine Ablesung vergessen ging und die Menge zweier
  // Arbeiten auf dieser landet. Warnen, nicht sperren.
  const jePalette = menge !== null && nPaletten > 0 ? menge / nPaletten : null
  const verdaechtig = jePalette !== null && jePalette > 120

  async function speichern() {
    if (menge === null || menge < 0) return
    const { error } = await supabase.from('schimmel_messung').insert({
      auftrag_id: auftrag.id, kg: Math.round(menge), palox_stand_kg: n,
      palox_geleert: leerGemeldet,
    })
    if (error) { setFehler(fehlerText(error)); return }
    setStand(''); setLeerGemeldet(false); setFehler(null); void laden(); void neuLaden?.()
  }

  const summe = zeilen.reduce((s, z) => s + z.kg, 0)

  return (
    <Karte titel={t('faule')}>
      <div className="reihe" style={{ alignItems: 'flex-end' }}>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor="palox">{t('waageZeigt')}</label>
          <input id="palox" type="number" inputMode="decimal" min={0} step="0.5"
                 value={stand} disabled={gesperrt} onChange={e => setStand(e.target.value)}
                 style={{ fontSize: '1.4rem' }} />
          <p className="leise" style={{ margin: '.3rem 0 0' }}>{t('waageAblesenHinweis')}</p>
        </div>
        <button className="haupt" style={{ minHeight: 54 }}
                onClick={speichern} disabled={gesperrt || menge === null || menge < 0}>
          {t('eintragen')}
        </button>
      </div>

      <label className="ankreuzen">
        <input type="checkbox" checked={leerGemeldet} disabled={gesperrt}
               onChange={e => setLeerGemeldet(e.target.checked)} />
        {t('paloxWarLeer')}
      </label>

      {menge !== null && (
        <p style={{ margin: '.6rem 0 0', fontSize: '1.1rem' }}>
          <strong>{Math.round(Math.max(menge, 0))} kg</strong>
          {vorher !== null && !geleert && <> ({n} − {vorher})</>}
          {(vorher === null || geleert) && tara > 0 && <> ({n} − {tara})</>}
          {geleert && !leerGemeldet && <> — {t('paloxGeleert')}</>}
          {jePalette !== null && (
            <span className="leise"> · {Math.round(jePalette)} {t('kgJePalette')}</span>
          )}
        </p>
      )}
      {verdaechtig && <Hinweis art="warnung">{t('vielJePalette')}</Hinweis>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      {zeilen.length > 0 && (
        <>
          <p style={{ marginTop: '1rem' }}><strong>{t('bisher')}: {summe} kg</strong></p>
          <table>
            <tbody>
              {zeilen.map(z => (
                <tr key={z.id}>
                  <td>{z.kg} kg</td>
                  <td className="leise">
                    {new Date(z.ts).toLocaleTimeString(gebietsschema,
                      { hour: '2-digit', minute: '2-digit' })}
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
  const { t, gebietsschema } = useSprache()
  const [art, setArt] = useState<'zu_klein' | 'zu_gross'>('zu_klein')
  const [modus, setModus] = useState<'wiegen' | 'schaetzen'>('wiegen')
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [brutto, setBrutto] = useState('')
  const [kisten, setKisten] = useState('')
  const [gart, setGart] = useState('')
  const [schaetzung, setSchaetzung] = useState('')
  const [zeilen, setZeilen] = useState<{ id: number; kg: number; ts: string
    gemessen: boolean; brutto_kg: number | null; kisten: number | null }[]>([])
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const [s, r] = await Promise.all([
      stammdaten(),
      supabase.from('ausschuss_messung')
        .select('id, kg, ts, gemessen, brutto_kg, kisten')
        .eq('auftrag_id', auftrag.id).eq('art', art).order('ts'),
    ])
    setGebinde(s.gebinde)
    setGart(a => a || s.gebinde[0]?.art || '')
    setZeilen((r.data ?? []) as typeof zeilen)
  }, [auftrag.id, art])
  useEffect(() => { void laden() }, [laden])

  const tara = gebinde.find(g => g.art === gart)
  const n = Number(kisten); const b = Number(brutto)
  // Dieselbe Rechnung wie der Auslöser ausschuss_netto_setzen — hier nur zur
  // Vorschau. Gespeichert werden Brutto und Kisten, gerechnet wird das Netto.
  const netto = b > 0 && tara?.tara_kg_pro_kiste != null
    ? Math.max(Math.round(b - n * tara.tara_kg_pro_kiste - (tara.tara_kg_palette ?? 0)), 0)
    : null

  async function speichern() {
    let zeile: Record<string, unknown>
    if (modus === 'wiegen') {
      if (!(b > 0 && n > 0 && gart)) return
      zeile = { auftrag_id: auftrag.id, art, brutto_kg: b, kisten: n, gebindeart: gart }
    } else {
      const k = Number(schaetzung)
      if (!Number.isInteger(k) || k < 0) { setFehler(t('ganzeZahl')); return }
      zeile = { auftrag_id: auftrag.id, art, kg: k }
    }
    const { error } = await supabase.from('ausschuss_messung').insert(zeile)
    if (error) { setFehler(fehlerText(error)); return }
    setBrutto(''); setKisten(''); setSchaetzung(''); setFehler(null); void laden()
  }

  const summe = zeilen.reduce((s, z) => s + z.kg, 0)

  return (
    <>
      <div className="reihe" style={{ marginTop: '1rem' }}>
        <button className={art === 'zu_klein' ? 'haupt' : ''} style={{ flex: 1, minHeight: 54 }}
                onClick={() => setArt('zu_klein')}>{t('zuKlein')}</button>
        <button className={art === 'zu_gross' ? 'haupt' : ''} style={{ flex: 1, minHeight: 54 }}
                onClick={() => setArt('zu_gross')}>{t('zuGross')}</button>
      </div>
      <Karte titel={art === 'zu_klein' ? t('zuKlein') : t('zuGross')}>
        <div className="reihe" style={{ marginBottom: '.75rem' }}>
          <button className={modus === 'wiegen' ? 'haupt' : ''} style={{ flex: 1 }}
                  onClick={() => setModus('wiegen')}>{t('ausschussWiegen')}</button>
          <button className={modus === 'schaetzen' ? 'haupt' : ''} style={{ flex: 1 }}
                  onClick={() => setModus('schaetzen')}>{t('ausschussSchaetzen')}</button>
        </div>

        {modus === 'wiegen' ? (
          <>
            <div className="feld">
              <label htmlFor="aus-brutto">{t('gewicht')}</label>
              <input id="aus-brutto" type="number" inputMode="decimal" step="0.1" min={0}
                     value={brutto} disabled={gesperrt} onChange={e => setBrutto(e.target.value)}
                     style={{ fontSize: '1.2rem' }} />
            </div>
            <div className="reihe">
              <div className="feld" style={{ flex: 1 }}>
                <label htmlFor="aus-kisten">{t('anzahlKisten')}</label>
                <input id="aus-kisten" type="number" inputMode="numeric" min={1} value={kisten}
                       disabled={gesperrt} onChange={e => setKisten(e.target.value)} />
              </div>
              <div className="feld" style={{ flex: 1 }}>
                <label htmlFor="aus-art">{t('kistenart')}</label>
                <select id="aus-art" value={gart} disabled={gesperrt}
                        onChange={e => setGart(e.target.value)}>
                  {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
                </select>
              </div>
            </div>
            {netto !== null && (
              <p style={{ fontSize: '1.15rem', margin: '0 0 .75rem' }}>
                <strong>{netto} kg</strong> {t('netto')}
              </p>
            )}
            <button className="haupt" style={{ width: '100%', minHeight: 54 }}
                    onClick={speichern} disabled={gesperrt || netto === null || n < 1}>
              {t('eintragen')}
            </button>
          </>
        ) : (
          <>
            <div className="reihe" style={{ alignItems: 'flex-end' }}>
              <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
                <label htmlFor="aus-schaetz">{t('kilo')}</label>
                <input id="aus-schaetz" type="number" inputMode="numeric" min={0} step={1}
                       value={schaetzung} disabled={gesperrt}
                       onChange={e => setSchaetzung(e.target.value)} style={{ fontSize: '1.2rem' }} />
              </div>
              <button className="haupt" style={{ minHeight: 54 }} onClick={speichern}
                      disabled={gesperrt || schaetzung === ''}>{t('eintragen')}</button>
            </div>
            <p className="leise" style={{ marginTop: '.4rem' }}>{t('ausschussSchaetzenHinweis')}</p>
          </>
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
                    <td>{z.brutto_kg === null ? t('geschaetzt') : t('gewogen')}</td>
                    <td style={{ textAlign: 'right' }}>
                      <button className="gefahr klein" disabled={gesperrt}
                              onClick={async () => {
                                const { error } = await supabase.from('ausschuss_messung')
                                  .delete().eq('id', z.id)
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
                  <td>{z.kisten} {t('kisten')}</td>
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
function Abschluss({ auftrag, neuLaden, zurueck, paloxGelesen, zumPalox, hatAusschuss, angaben }: {
  auftrag: Auftrag; neuLaden: () => Promise<void>; zurueck: () => void
  paloxGelesen: boolean; zumPalox: () => void
  hatAusschuss: boolean; angaben: Record<string, string>
}) {
  const { t, gebietsschema } = useSprache()
  const [sicher, setSicher] = useState(false)
  const [abbruchSicher, setAbbruchSicher] = useState(false)
  const [durchsatz, setDurchsatz] = useState(auftrag.durchsatz_kg?.toString() ?? '')
  const [eineCharge, setEineCharge] = useState<boolean | null>(null)
  const [gleicheSorte, setGleicheSorte] = useState<boolean | null>(null)
  const [sortierdatum, setSortierdatum] = useState('')
  const [ausschussVonAuftrag, setAusschussVonAuftrag] = useState<boolean | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  // Beim Waschen sind die Original-Paletten längst in Kaliber-Kisten aufgelöst;
  // ohne Mengenangabe hätte der dort ausgelesene Schimmel keinen Nenner.
  const brauchtDurchsatz = auftrag.station === 'waschen'

  // Antworten sind Messwerte (docs/Datenarchitektur, Regel 2): „War alles aus
  // einer Charge?" sagt, ob das Alter der Ware im Palox bekannt ist. Bei Nein
  // bleibt die Messung dem Verderbsmodell fern und zählt nur in der Bilanz.
  // Beantwortet werden muss es — eine leere Antwort wäre „nicht gefragt".
  const fragen: { schluessel: string; wert: string }[] = []
  if (eineCharge !== null) fragen.push({ schluessel: 'eine_charge', wert: String(eineCharge) })
  if (eineCharge === false && gleicheSorte !== null) {
    fragen.push({ schluessel: 'gleiche_sorte', wert: String(gleicheSorte) })
  }
  if (auftrag.station === 'waschen' && sortierdatum !== '') {
    fragen.push({ schluessel: 'sortierdatum', wert: sortierdatum })
  }
  // AB-05: Beim Ausschuss die zweite Frage — gehört alles zu dieser Arbeit?
  if (hatAusschuss && ausschussVonAuftrag !== null) {
    fragen.push({ schluessel: 'ausschuss_von_auftrag', wert: String(ausschussVonAuftrag) })
  }
  const beantwortet = eineCharge !== null && (eineCharge || gleicheSorte !== null)
  // AB-02: Ohne Palox-Ablesung (Beginn/Abschluss) kein Abschluss.
  // Für Hand-Arbeiten müssen beide Ausschuss-Fragen beantwortet sein: zu
  // Beginn „leer?" (in der Startkarte), am Ende „alles von dieser Arbeit?".
  const ausschussKlar = !hatAusschuss
    || (angaben['ausschuss_leer'] !== undefined && ausschussVonAuftrag !== null)
  const fertigMoeglich = beantwortet && paloxGelesen && ausschussKlar

  async function abschliessen() {
    setLaeuft(true)
    if (fragen.length) {
      const { error: f0 } = await supabase.from('auftrag_angabe')
        .insert(fragen.map(f => ({ auftrag_id: auftrag.id, ...f })))
      if (f0) { setLaeuft(false); setFehler(fehlerText(f0)); return }
    }
    // Das Ende setzt der Server (Auslöser in 0039): Die Uhr des Handys ist
    // keine verlässliche Zeit, und stand sie hinter der Startzeit, liess sich
    // die Arbeit nicht abschliessen.
    const { error } = await supabase.from('auftrag').update({
      durchsatz_kg: durchsatz === '' ? null : Number(durchsatz),
      status: 'abgeschlossen',
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
      <div className="feld">
        <label>{t('eineChargeFrage')}</label>
        <div className="reihe">
          <button type="button" className={eineCharge === true ? 'haupt' : ''}
                  style={{ flex: 1, minHeight: 50 }}
                  onClick={() => setEineCharge(true)}>{t('eineChargeJa')}</button>
          <button type="button" className={eineCharge === false ? 'haupt' : ''}
                  style={{ flex: 1, minHeight: 50 }}
                  onClick={() => setEineCharge(false)}>{t('eineChargeNein')}</button>
        </div>
      </div>
      {eineCharge === false && (
        <div className="feld">
          <label>{t('gleicheSorteFrage')}</label>
          <div className="reihe">
            <button type="button" className={gleicheSorte === true ? 'haupt' : ''}
                    style={{ flex: 1, minHeight: 50 }}
                    onClick={() => setGleicheSorte(true)}>{t('gleicheSorteJa')}</button>
            <button type="button" className={gleicheSorte === false ? 'haupt' : ''}
                    style={{ flex: 1, minHeight: 50 }}
                    onClick={() => setGleicheSorte(false)}>{t('gleicheSorteNein')}</button>
          </div>
        </div>
      )}
      {auftrag.station === 'waschen' && (
        <div className="feld">
          <label htmlFor="sd">{t('sortierdatumKiste')} ({t('freiwillig')})</label>
          <input id="sd" type="date" value={sortierdatum}
                 onChange={e => setSortierdatum(e.target.value)} />
        </div>
      )}
      {hatAusschuss && (
        <div className="feld">
          <label>{t('ausschussVonAuftragFrage')}</label>
          <div className="reihe">
            <button type="button" className={ausschussVonAuftrag === true ? 'haupt' : ''}
                    style={{ flex: 1, minHeight: 50 }}
                    onClick={() => setAusschussVonAuftrag(true)}>{t('ja')}</button>
            <button type="button" className={ausschussVonAuftrag === false ? 'haupt' : ''}
                    style={{ flex: 1, minHeight: 50 }}
                    onClick={() => setAusschussVonAuftrag(false)}>{t('nein')}</button>
          </div>
        </div>
      )}
      {hatAusschuss && angaben['ausschuss_leer'] === undefined && (
        <Hinweis art="warnung">{t('ausschussLeerOffen')}</Hinweis>
      )}
      {!paloxGelesen && (
        <Hinweis art="warnung">
          {t('paloxVorAbschluss')}{' '}
          <a href="#" onClick={e => { e.preventDefault(); zumPalox() }}>{t('jetztAblesen')}</a>
        </Hinweis>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {!sicher ? (
        <button className="haupt gross" style={{ width: '100%' }} onClick={() => setSicher(true)}
                disabled={!fertigMoeglich}>
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
