import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { Hinweis, Lade } from '../components/Bausteine'
import type { Auftrag, Charge } from '../lib/typen'

/**
 * Die Startseite des Arbeiters: Was läuft gerade — und zwei Knöpfe.
 *
 * Wer beitritt, tippt eine Karte an und ist drin. Wer eine Arbeit eröffnet,
 * geht durch den Assistenten. Mehr gibt es hier nicht: keine Liste fertiger
 * Arbeiten, keine Zahlen, nichts, was man verstehen müsste.
 */
export default function Start() {
  const { t, gebietsschema } = useSprache()
  const { profil, session } = useAuth()
  const navigate = useNavigate()
  const [offen, setOffen] = useState<Auftrag[]>([])
  const [heuteFertig, setHeuteFertig] = useState(0)
  const [chargen, setChargen] = useState<Charge[]>([])
  const [dabei, setDabei] = useState<Record<number, { profil_id: string; name: string }[]>>({})
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = setFehlerState()

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
  }, [setFehler])
  useEffect(() => { void laden() }, [laden])

  async function mitmachen(a: Auftrag) {
    const ich = session?.user.id
    if (ich && !(dabei[a.id] ?? []).some(x => x.profil_id === ich)) {
      const { error } = await supabase.from('auftrag_teilnehmer').insert({ auftrag_id: a.id })
      if (error) { setFehler(fehlerText(error)); return }
    }
    navigate(`/arbeit/${a.id}`)
  }

  if (laedt) return <Lade />

  return (
    <>
      <h1 style={{ marginBottom: '.25rem' }}>{t('hallo')} {profil?.name ?? ''}</h1>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      <div className="abschnitt-titel">{t('laeuftGerade')}</div>
      {offen.length === 0 && <p className="leise" style={{ margin: '.25rem 0 .5rem' }}>{t('nichtsLaeuft')}</p>}
      {offen.map(a => {
        const taet = taetigkeitVon(a.weg, a.station, a.ist_fax)
        const leute = dabei[a.id] ?? []
        const binDabei = !!session && leute.some(x => x.profil_id === session.user.id)
        return (
          <div key={a.id} className="arbeit-karte">
            <div className="titel">
              <span className="bild" aria-hidden="true">{taet?.zeichen}</span>
              {taet ? t(taet.text) : ''}
            </div>
            <div className="charge">{chargeText(chargen.find(c => c.nr === a.charge_nr))}</div>
            <div className="leise unter">
              {t('seit')} {new Date(a.start_ts).toLocaleTimeString(gebietsschema, { hour: '2-digit', minute: '2-digit' })}
              {' · '}{t('dabei')}: {leute.length ? leute.map(x => x.name).join(', ') : t('niemand')}
            </div>
            <button className={binDabei ? '' : 'haupt'} style={{ width: '100%', marginTop: '.7rem', minHeight: 54 }}
                    onClick={() => void mitmachen(a)}>
              {binDabei ? t('weiter') + ' ›' : t('mitmachen')}
            </button>
          </div>
        )
      })}

      <div className="start-knoepfe">
        <button className={offen.length === 0 ? 'haupt' : ''} onClick={() => navigate('/neu')}>
          <span className="bild" aria-hidden="true">➕</span>{t('neueArbeitStarten')}
        </button>
        <button onClick={() => navigate('/kontrolle')}>
          <span className="bild" aria-hidden="true">🔍</span>{t('kontrolle')}
        </button>
      </div>

      {heuteFertig > 0 && (
        <p className="leise" style={{ textAlign: 'center' }}>{t('heuteFertig')}: {heuteFertig}</p>
      )}
    </>
  )
}

function setFehlerState() {
  return useState<string | null>(null)
}
