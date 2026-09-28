import { useCallback, useEffect, useState } from 'react'
import { TaetKachel, ZAuswahl, ZChevron, ZHaken, ZKreuz, ZLupe, ZNeu, ZStopp } from '../components/Zeichen'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { Avatar, Hinweis, Lade, Marke } from '../components/Bausteine'
import { staffel } from '../design/bewegung'
import { useFrischhalten } from '../lib/frischhalten'
import type { Auftrag, Charge } from '../lib/typen'

/**
 * Die Startseite des Arbeiters: Was läuft gerade — und zwei Knöpfe.
 *
 * Wer beitritt, tippt eine Karte an und ist drin. Wer eine Arbeit eröffnet,
 * geht durch den Assistenten. Mehr gibt es hier nicht: keine Liste fertiger
 * Arbeiten, keine Zahlen, nichts, was man verstehen müsste.
 *
 * Runde AD: laufende Arbeiten abbrechen — auch fremde — darf der
 * Betriebsleiter und wer die Erlaubnis hat (profil.darf_abbrechen, 0097).
 * Der Weg ist immer derselbe: erst der Auswahlmodus, dann ein Kreis an
 * jeder Karte, dann der Knopf, dann die Rückfrage mit der Liste der
 * gewählten Arbeiten. Es gibt keinen Knopf, der „alle" nimmt; ohne Auswahl
 * ist der Knopf grau. Die Datenbank prüft die Erlaubnis noch einmal selbst.
 */
export default function Start() {
  const { t, gebietsschema } = useSprache()
  const { profil, session, istAdmin } = useAuth()
  const navigate = useNavigate()
  const [offen, setOffen] = useState<Auftrag[]>([])
  const [heuteFertig, setHeuteFertig] = useState(0)
  const [chargen, setChargen] = useState<Charge[]>([])
  const [dabei, setDabei] = useState<Record<number, { profil_id: string; name: string }[]>>({})
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  /** Runde AD: der Auswahlmodus zum Abbrechen. */
  const darfAbbrechen = istAdmin || !!profil?.darf_abbrechen
  const [wahl, setWahl] = useState(false)
  const [gewaehlt, setGewaehlt] = useState<Set<number>>(new Set())
  const [frage, setFrage] = useState(false)
  const [bricht, setBricht] = useState(false)
  const [abgebrochen, setAbgebrochen] = useState<string | null>(null)

  const laden = useCallback(async () => {
    try {
      const heute = new Date(); heute.setHours(0, 0, 0, 0)
      const [{ chargen }, a, f] = await Promise.all([
        stammdaten(),
        supabase.from('auftrag').select('*').eq('status', 'offen').is('abgebrochen_ts', null)
          .order('start_ts', { ascending: false }),
        supabase.from('auftrag').select('id', { count: 'exact', head: true })
          .eq('status', 'abgeschlossen').gte('ende_ts', heute.toISOString()),
      ])
      if (a.error) throw a.error
      const liste = (a.data ?? []) as Auftrag[]
      setChargen(chargen); setOffen(liste); setHeuteFertig(f.count ?? 0)
      if (liste.length) {
        const { data } = await supabase.from('auftrag_teilnehmer').select('auftrag_id, profil_id, profil(name)')
          .in('auftrag_id', liste.map(x => x.id)).is('verlassen_ts', null)
        type Z = { auftrag_id: number; profil_id: string; profil: { name: string } | { name: string }[] | null }
        const map: typeof dabei = {}
        for (const z of ((data ?? []) as unknown as Z[])) {
          const name = (Array.isArray(z.profil) ? z.profil[0]?.name : z.profil?.name) ?? '?'
          ;(map[z.auftrag_id] ??= []).push({ profil_id: z.profil_id, name })
        }
        setDabei(map)
      }
      setFehler(null)
    } catch (f) { setFehler(fehlerText(f)) } finally { setLaedt(false) }
  }, [])
  useEffect(() => { void laden() }, [laden])
  // Q22: die Liste altert nicht mehr still vor sich hin — sie holt sich neu,
  // sobald jemand wieder hinschaut. Genau das braucht der Schichtwechsel.
  useFrischhalten(laden)

  async function mitmachen(a: Auftrag) {
    const ich = session?.user.id
    if (ich && !(dabei[a.id] ?? []).some(x => x.profil_id === ich)) {
      const { error } = await supabase.from('auftrag_teilnehmer').insert({ auftrag_id: a.id })
      // 23505: Der Eintrag steht schon — der eindeutige Schlüssel über
      // (Arbeit, Person) lässt keinen zweiten zu. Das passiert genau dann,
      // wenn diese Liste älter ist als die Wirklichkeit: der Mann hat auf
      // einem anderen Handy schon mitgemacht. Früher stand dann eine rote
      // Datenbankmeldung da und er kam nicht hinein. Jetzt ist er einfach
      // drin — dabei ist dabei (Q22).
      if (error && (error as { code?: string }).code !== '23505') {
        setFehler(fehlerText(error)); return
      }
    }
    navigate(`/arbeit/${a.id}`)
  }

  function wahlAus() { setWahl(false); setGewaehlt(new Set()); setFrage(false) }
  function umschalten(id: number) {
    setGewaehlt(g => { const n = new Set(g); if (n.has(id)) n.delete(id); else n.add(id); return n })
  }
  const mitZahl = (text: string, n: number) => text.replace('{n}', String(n))

  /** Genau die angetippten Arbeiten, eine nach der anderen — die Liste kommt
   *  aus den Kreisen, nirgends sonst her. Die Funktion in der Datenbank
   *  (0097) prüft die Erlaubnis selbst und bricht nur Laufendes ab. */
  async function abbrechen() {
    if (bricht || gewaehlt.size === 0) return
    setBricht(true); setFehler(null)
    const fehlgeschlagen: string[] = []
    for (const id of gewaehlt) {
      const { error } = await supabase.rpc('auftrag_abbrechen', { p_auftrag_id: id, p_grund: `Startseite · ${profil?.name ?? ''}` })
      if (error) fehlgeschlagen.push(fehlerText(error))
    }
    const n = gewaehlt.size - fehlgeschlagen.length
    setAbgebrochen(n === 0 ? null : n === 1 ? t('abgebrochen1') : mitZahl(t('abgebrochenN'), n))
    if (fehlgeschlagen.length) setFehler(fehlgeschlagen.join(' · '))
    setBricht(false); wahlAus()
    await laden()
  }

  if (laedt) return <Lade />

  return (
    <>
      <div className="halle-gruss">
        <h1>{t('hallo')} {profil?.name ?? ''}</h1>
        {heuteFertig > 0 && <span className="leise">{t('heuteFertig')}: {heuteFertig}</span>}
      </div>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {abgebrochen && <Hinweis art="gut">{abgebrochen}</Hinweis>}

      <div className="abschnitt-kopf">
        <div className="abschnitt-titel">{t('laeuftGerade')}</div>
        {darfAbbrechen && offen.length > 0 && (wahl
          ? <button type="button" id="auswahl-aus" className="symbolknopf an" aria-label={t('auswahlBeenden')} title={t('auswahlBeenden')} onClick={wahlAus}><ZKreuz size={18} /></button>
          : <button type="button" id="auswahl-an" className="symbolknopf" aria-label={t('auswaehlen')} title={t('auswaehlen')} onClick={() => { setWahl(true); setAbgebrochen(null) }}><ZAuswahl size={20} /></button>)}
      </div>
      {wahl && (
        <div className="loesch-leiste" role="status">
          <span>{t('auswahlHinweis')}</span>
          <strong>{mitZahl(t('nAusgewaehlt'), gewaehlt.size)}</strong>
          <button type="button" id="auswahl-abbrechen" className="knopf klein gefahr" disabled={gewaehlt.size === 0} onClick={() => setFrage(true)}>
            <ZStopp size={16} />{t('gewaehlteAbbrechen')}
          </button>
        </div>
      )}
      {frage && (
        <div className="dialog-hinter" onClick={() => setFrage(false)}>
          <div className="dialog" role="dialog" aria-modal="true" aria-label={t('gewaehlteAbbrechen')} onClick={e => e.stopPropagation()}>
            <h2 style={{ marginTop: 0 }}>{gewaehlt.size === 1 ? t('abbrechenFrage1') : mitZahl(t('abbrechenFrageN'), gewaehlt.size)}</h2>
            <ul className="liste-schlicht">
              {offen.filter(a => gewaehlt.has(a.id)).map(a => {
                const ta = taetigkeitVon(a.weg, a.station, a.ist_fax)
                const leute = dabei[a.id] ?? []
                return (
                  <li key={a.id}>
                    {ta ? t(ta.text) : ''} · {chargeText(chargen.find(c => c.nr === a.charge_nr))} · {t('seit')} {new Date(a.start_ts).toLocaleTimeString(gebietsschema, { hour: '2-digit', minute: '2-digit' })}
                    {' · '}{leute.length ? leute.map(x => x.name).join(', ') : t('niemand')}
                  </li>
                )
              })}
            </ul>
            <Hinweis art="warnung">{t('abbrechenFolge')}</Hinweis>
            <div className="knopf-reihe" style={{ marginTop: 'var(--a-3)' }}>
              <button type="button" id="auswahl-abbrechen-ja" className="knopf gefahr" disabled={bricht} onClick={() => void abbrechen()}>
                <ZStopp size={16} />{bricht ? '…' : gewaehlt.size === 1 ? t('wahlJaAbbrechen') : mitZahl(t('jaNAbbrechen'), gewaehlt.size)}
              </button>
              <button type="button" id="auswahl-abbrechen-nein" className="knopf" disabled={bricht} onClick={() => setFrage(false)}>{t('nein')}</button>
            </div>
          </div>
        </div>
      )}
      {offen.length === 0 && <p className="leise" style={{ margin: '.25rem 0 .75rem' }}>{t('nichtsLaeuft')}</p>}
      {offen.map((a, i) => {
        const taet = taetigkeitVon(a.weg, a.station, a.ist_fax)
        const leute = dabei[a.id] ?? []
        const binDabei = !!session && leute.some(x => x.profil_id === session.user.id)
        const dran = wahl && gewaehlt.has(a.id)
        return (
          <div key={a.id} data-id={a.id} className={`arbeit-karte eintritt${wahl ? ' waehlbar' : ''}${dran ? ' gewaehlt' : ''}`} style={staffel(i)}
               onClick={wahl ? () => umschalten(a.id) : undefined}>
            <div className="kopfzeile">
              {wahl && (
                <button type="button" role="checkbox" aria-checked={dran} aria-label={`${taet ? t(taet.text) : ''} ${chargeText(chargen.find(c => c.nr === a.charge_nr))}`}
                        className={`wahlkreis${dran ? ' an' : ''}`} onClick={e => { e.stopPropagation(); umschalten(a.id) }}>
                  {dran && <ZHaken size={14} />}
                </button>
              )}
              <TaetKachel id={taet?.id} size={44} />
              <div style={{ minWidth: 0, flex: 1 }}>
                <div className="titel">{taet ? t(taet.text) : ''}</div>
                <div className="charge">{chargeText(chargen.find(c => c.nr === a.charge_nr))}</div>
              </div>
              <Marke art="offen">{t('laeuft')}</Marke>
            </div>
            <div className="unter">
              <span>{t('seit')} {new Date(a.start_ts).toLocaleTimeString(gebietsschema, { hour: '2-digit', minute: '2-digit' })}</span>
              <span>·</span>
              <span>{t('dabei')}:</span>
              {leute.length
                ? <><span className="avatare">{leute.slice(0, 4).map(x => <Avatar key={x.profil_id} name={x.name} klein />)}</span><span>{leute.map(x => x.name).join(', ')}</span></>
                : <span>{t('niemand')}</span>}
            </div>
            {!wahl && (
              <button type="button" className={binDabei ? '' : 'haupt'} onClick={() => void mitmachen(a)}>
                {binDabei ? <>{t('weiter')} <ZChevron size={18} /></> : t('mitmachen')}
              </button>
            )}
          </div>
        )
      })}

      <div className="start-knoepfe">
        <button type="button" className={offen.length === 0 ? 'haupt' : ''} onClick={() => navigate('/neu')}>
          <span className="kachel" aria-hidden="true" style={{ width: 38, height: 38 }}><ZNeu size={22} /></span>{t('neueArbeitStarten')}
        </button>
        <button type="button" onClick={() => navigate('/kontrolle')}>
          <span className="kachel" aria-hidden="true" style={{ width: 38, height: 38 }}><ZLupe size={22} /></span>{t('kontrolle')}
        </button>
      </div>
    </>
  )
}
