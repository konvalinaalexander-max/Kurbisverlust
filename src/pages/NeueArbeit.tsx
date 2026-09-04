import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { TAETIGKEITEN } from '../lib/taetigkeit'
import { Hinweis } from '../components/Bausteine'
import { Schritt, Wahl } from '../components/Schritte'
import { ChargeFeld } from '../components/ChargeFeld'
import { fuehrungSetzen } from '../lib/rolle'
import type { TextId } from '../lib/i18n'
import type { Charge, Kaeufer, Sortierschema } from '../lib/typen'

type SchrittId = 'was' | 'charge' | 'kaeufer' | 'art' | 'kaliber' | 'pruefen'

const ERKL: Record<string, TextId> = {
  sortieren: 'sortierenErkl', waschen: 'waschenErkl',
  waschen_sortieren: 'waschenSortierenErkl', fax: 'faxErkl',
}

/**
 * Eine Arbeit eröffnen — der Assistent des Vorarbeiters. Je Bildschirm eine
 * Frage; Fragen, die für die Tätigkeit nicht gelten, gibt es nicht. Am Ende
 * eine Zusammenfassung, dann „Starten" — und direkt danach die erste Pflicht:
 * den Palox ablesen (AB-02).
 */
export default function NeueArbeit() {
  const { t } = useSprache()
  const navigate = useNavigate()
  const [chargen, setChargen] = useState<Charge[]>([])
  const [kaeufer, setKaeufer] = useState<Kaeufer[]>([])
  const [schemata, setSchemata] = useState<Sortierschema[]>([])

  const [taetigkeit, setTaetigkeit] = useState<string | null>(null)
  const [chargeNr, setChargeNr] = useState<number | ''>('')
  const [kaeuferCode, setKaeuferCode] = useState<string | null>(null)   // null = noch nicht gewählt
  const [neuerKaeufer, setNeuerKaeufer] = useState('')
  const [art, setArt] = useState<'kaliber' | 'kiste' | null>(null)
  const [kaliberIdx, setKaliberIdx] = useState<number | null>(null)
  const [pos, setPos] = useState(0)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void stammdaten().then(s => setChargen(s.chargen))
    void supabase.from('kaeufer').select('*').eq('aktiv', true).order('name')
      .then(({ data }) => setKaeufer((data ?? []) as Kaeufer[]))
    void supabase.from('sortierschema').select('*').order('gilt_ab', { ascending: false })
      .then(({ data }) => setSchemata((data ?? []) as Sortierschema[]))
  }, [])

  const gewaehlt = TAETIGKEITEN.find(a => a.id === taetigkeit)
  const fragtKaeufer = gewaehlt ? gewaehlt.station !== 'waschen' : true
  const fragtArt = gewaehlt ? (gewaehlt.station === 'sortieren' || gewaehlt.station === 'waschen_sortieren') : true
  const fragtKaliber = gewaehlt ? gewaehlt.station === 'waschen' : false

  const schritte = useMemo<SchrittId[]>(() => [
    'was', 'charge',
    ...(fragtKaeufer ? ['kaeufer' as const] : []),
    ...(fragtArt ? ['art' as const] : []),
    ...(fragtKaliber ? ['kaliber' as const] : []),
    'pruefen',
  ], [fragtKaeufer, fragtArt, fragtKaliber])
  const aktuell = schritte[Math.min(pos, schritte.length - 1)]
  const weiter = () => setPos(p => Math.min(p + 1, schritte.length - 1))
  const zurueck = () => (pos === 0 ? navigate('/') : setPos(p => p - 1))

  const charge = chargen.find(c => c.nr === chargeNr)
  const sorte = charge?.sorte
  const chargeBekannt = chargeNr !== '' && !!charge

  // Die Fassung, die für Sorte, Käufer und Art heute gilt — dieselbe
  // Reihenfolge wie sortierschema_fuer() in der Datenbank.
  const heute = new Date().toISOString().slice(0, 10)
  function fassung(fuerArt: 'kaliber' | 'kiste'): Sortierschema | undefined {
    const passend = schemata.filter(x => x.sorte === sorte && x.art === fuerArt && x.gilt_ab <= heute)
    return passend.find(x => x.kaeufer === (kaeuferCode || null))
        ?? passend.find(x => x.kaeufer === null)
        ?? schemata.find(x => x.sorte === sorte && x.art === fuerArt)
  }
  const fassungKaliber = fassung('kaliber')
  const fassungKiste = fassung('kiste')
  const gewaehlteFassung = art === null ? undefined : art === 'kiste' ? fassungKiste : fassungKaliber
  const baender = fassungKaliber?.kaliber_baender ?? []

  async function starten() {
    if (!gewaehlt || chargeNr === '' || !chargeBekannt) return
    setLaeuft(true); setFehler(null)
    let code: string | null = kaeuferCode || null
    if (kaeuferCode === '__neu__') {
      const name = neuerKaeufer.trim()
      if (!name) { setLaeuft(false); setFehler(t('kaeuferName')); return }
      code = name.toLowerCase().replace(/[^a-z0-9äöü]+/g, '-').replace(/(^-|-$)/g, '')
      const { error } = await supabase.from('kaeufer')
        .upsert({ code, name }, { onConflict: 'code', ignoreDuplicates: true })
      if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    }
    // Startzeit setzt der Server; die Fassung wird gewählt, nicht geraten.
    const { data, error } = await supabase.from('auftrag')
      .insert({ weg: gewaehlt.weg, station: gewaehlt.station, charge_nr: chargeNr,
                ist_fax: gewaehlt.fax ?? false,
                kaeufer: fragtKaeufer ? code : null,
                kaliber_idx: fragtKaliber ? kaliberIdx : null,
                sortierschema_id: fragtArt ? (gewaehlteFassung?.id ?? null) : null })
      .select('id').single()
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    const id = (data as { id: number }).id
    // Wer eröffnet, ist dabei — und führt.
    await supabase.from('auftrag_teilnehmer').insert({ auftrag_id: id })
    fuehrungSetzen(id, true)
    setLaeuft(false)
    navigate(`/arbeit/${id}?neu=1`, { replace: true })
  }

  const n = pos + 1, von = schritte.length
  const kaeuferName = kaeuferCode === '__neu__' ? neuerKaeufer
    : kaeuferCode ? (kaeufer.find(k => k.code === kaeuferCode)?.name ?? kaeuferCode) : t('ohneKaeufer')

  if (aktuell === 'was') {
    return (
      <Schritt nummer={n} von={von} frage={t('wasMachtIhr')} zurueck={zurueck}>
        <div className="wahl">
          {TAETIGKEITEN.map(a => (
            <Wahl key={a.id} id={`taet-${a.id}`} bild={a.zeichen} name={t(a.text)} erkl={t(ERKL[a.id])}
                  gewaehlt={taetigkeit === a.id}
                  onClick={() => { setTaetigkeit(a.id); setArt(null); setKaliberIdx(null); setPos(1) }} />
          ))}
        </div>
      </Schritt>
    )
  }

  if (aktuell === 'charge') {
    return (
      <Schritt nummer={n} von={von} frage={t('welcheCharge')} warum={t('chargeWarum')}
               zurueck={zurueck} weiter={weiter} weiterMoeglich={chargeBekannt}>
        <ChargeFeld id="charge" chargen={chargen} wert={chargeNr} setzen={setChargeNr} ohneLabel />
      </Schritt>
    )
  }

  if (aktuell === 'kaeufer') {
    return (
      <Schritt nummer={n} von={von} frage={t('fuerWen')} warum={t('kaeuferWarum')} zurueck={zurueck}
               weiter={kaeuferCode === '__neu__' ? weiter : undefined}
               weiterMoeglich={neuerKaeufer.trim() !== ''}>
        <div className="wahl">
          {kaeufer.map(k => (
            <Wahl key={k.code} id={`kaeufer-${k.code}`} name={k.name} gewaehlt={kaeuferCode === k.code}
                  onClick={() => { setKaeuferCode(k.code); setArt(null); weiter() }} />
          ))}
          <Wahl id="kaeufer-keiner" name={t('ohneKaeufer')} gewaehlt={kaeuferCode === ''}
                onClick={() => { setKaeuferCode(''); setArt(null); weiter() }} />
          <Wahl id="kaeufer-neu" name={t('kaeuferNeu')} gewaehlt={kaeuferCode === '__neu__'}
                onClick={() => setKaeuferCode('__neu__')} />
        </div>
        {kaeuferCode === '__neu__' && (
          <div className="feld">
            <label htmlFor="kaeufer-name">{t('kaeuferName')}</label>
            <input id="kaeufer-name" value={neuerKaeufer} autoFocus style={{ fontSize: '1.1rem' }}
                   onChange={e => setNeuerKaeufer(e.target.value)} />
          </div>
        )}
      </Schritt>
    )
  }

  if (aktuell === 'art') {
    const kisteErkl = fassungKiste?.soll_kg_pro_kiste != null
      ? `${t('artKisteErkl')} · ${fassungKiste.soll_kg_pro_kiste} kg` : t('artKisteErkl')
    const kaliberErkl = baender.length > 0
      ? `${t('artKaliberErkl')} · ${baender.length} ${t('baender')}` : t('artKaliberErkl')
    return (
      <Schritt nummer={n} von={von} frage={t('wieSortiert')} warum={t('wieSortiertWarum')} zurueck={zurueck}>
        <div className="wahl">
          <Wahl id="art-kiste" bild="📦" name={t('artKiste')} erkl={kisteErkl} gewaehlt={art === 'kiste'}
                onClick={() => { setArt('kiste'); weiter() }} />
          <Wahl id="art-kaliber" bild="📏" name={t('artKaliber')} erkl={kaliberErkl} gewaehlt={art === 'kaliber'}
                onClick={() => { setArt('kaliber'); weiter() }} />
        </div>
        {sorte && !fassungKiste && !fassungKaliber && <Hinweis art="warnung">{t('keineFassung')}</Hinweis>}
      </Schritt>
    )
  }

  if (aktuell === 'kaliber') {
    return (
      <Schritt nummer={n} von={von} frage={t('welchesKaliber')} warum={t('welchesKaliberWarum')} zurueck={zurueck}>
        <div className="wahl">
          {baender.map(([a, b], i) => (
            <Wahl key={i} id={`kaliber-${i}`} name={`${t('kaliber')} ${i + 1}`} erkl={`${a}–${b} g`}
                  gewaehlt={kaliberIdx === i} onClick={() => { setKaliberIdx(i); weiter() }} />
          ))}
        </div>
        {baender.length === 0 && <Hinweis art="warnung">{t('kistenKeineBaender')}</Hinweis>}
      </Schritt>
    )
  }

  // pruefen
  return (
    <Schritt nummer={n} von={von} frage={t('allesRichtig')} zurueck={zurueck}
             weiter={() => void starten()} weiterText={t('starten')} weiterMoeglich={!laeuft && chargeBekannt}>
      <div className="karte">
        <dl className="zusammenfassung">
          <dt>{t('taetigkeit')}</dt><dd>{gewaehlt?.zeichen} {gewaehlt ? t(gewaehlt.text) : ''}</dd>
          <dt>{t('charge')}</dt><dd>{chargeText(charge)}</dd>
          {fragtKaeufer && <><dt>{t('kaeuferKurz')}</dt><dd>{kaeuferName}</dd></>}
          {fragtArt && (
            <><dt>{t('sortierart')}</dt>
              <dd>{art === 'kiste' ? t('artKiste') : t('artKaliber')}
                {gewaehlteFassung && <span className="leise"> · {t('fassungVom')} {gewaehlteFassung.gilt_ab}
                  {gewaehlteFassung.kaeufer === null && ` (${t('standard')})`}</span>}
              </dd></>
          )}
          {fragtKaliber && (
            <><dt>{t('kaliber')}</dt>
              <dd>{kaliberIdx === null ? '—' : `${kaliberIdx + 1} (${baender[kaliberIdx]?.[0]}–${baender[kaliberIdx]?.[1]} g)`}</dd></>
          )}
        </dl>
      </div>
      {fragtArt && art !== null && !gewaehlteFassung && <Hinweis art="warnung">{t('keineFassung')}</Hinweis>}
      <p className="leise">{t('dannPalox')}</p>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </Schritt>
  )
}
