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

type SchrittId = 'was' | 'charge' | 'kaeufer' | 'art' | 'baender' | 'soll' | 'kaliber' | 'kisten' | 'pruefen'
type Band = [number, number]

const ERKL: Record<string, TextId> = {
  sortieren: 'sortierenErkl', waschen: 'waschenErkl',
  waschen_sortieren: 'waschenSortierenErkl', fax: 'faxErkl',
}

/** Bänder ↔ Grenzen: [500,800],[800,1300] ⇔ 500 | 800 | 1300. Lückenlos per Bauart. */
const grenzenVon = (b: Band[]): number[] => (b.length ? [b[0][0], ...b.map(x => x[1])] : [])
const baenderVon = (g: number[]): Band[] => g.slice(1).map((bis, i) => [g[i], bis] as Band)
const aufsteigend = (g: number[]) => g.length >= 2 && g.every((x, i) => Number.isFinite(x) && x >= 0 && (i === 0 || x > g[i - 1]))
const gleicheBaender = (a: Band[], b: Band[]) => a.length === b.length && a.every((x, i) => x[0] === b[i][0] && x[1] === b[i][1])

/**
 * Eine Arbeit eröffnen — der Assistent des Vorarbeiters. Je Bildschirm eine
 * Frage; Fragen, die für die Tätigkeit nicht gelten, gibt es nicht.
 *
 *  Sortieren:            Charge · Käufer · welche Kaliber (die Maschine kennt
 *                        nur Bänder — gefragt wird, wie sie heute steht)
 *  Waschen:              Charge · welches Kaliber wird gewaschen
 *  Waschen + Sortieren:  Charge · Käufer · Kiste oder Kaliber · Sollgewicht
 *                        bzw. Bänder
 *  Fax:                  Charge · Käufer · Kaliber-Kisten oder Kisten nach
 *                        Sollgewicht
 *
 * Bänder und Sollgewicht kommen als Vorschlag „wie zuletzt"; wer sie ändert,
 * legt damit eine neue, datierte Fassung an (sortierschema_festlegen, 0051).
 */
export default function NeueArbeit() {
  const { t } = useSprache()
  const navigate = useNavigate()
  const [chargen, setChargen] = useState<Charge[]>([])
  const [kaeufer, setKaeufer] = useState<Kaeufer[]>([])
  const [schemata, setSchemata] = useState<Sortierschema[]>([])
  const [laufSchema, setLaufSchema] = useState<{ charge: number; id: number | null } | null>(null)

  const [taetigkeit, setTaetigkeit] = useState<string | null>(null)
  const [chargeNr, setChargeNr] = useState<number | ''>('')
  const [kaeuferCode, setKaeuferCode] = useState<string | null>(null)   // null = noch nicht gewählt
  const [neuerKaeufer, setNeuerKaeufer] = useState('')
  const [art, setArt] = useState<'kaliber' | 'kiste' | null>(null)
  const [kaliberIdx, setKaliberIdx] = useState<number | null>(null)
  // 0054: ein eigenes Kaliber, wenn das Etikett keines der Bänder nennt
  const [eigenes, setEigenes] = useState<{ von: string; bis: string } | null>(null)
  const [grenzen, setGrenzen] = useState<number[] | null>(null)          // null = noch „wie zuletzt"
  const [soll, setSoll] = useState<string | null>(null)                   // null = noch „wie zuletzt"
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
  const station = gewaehlt?.station
  const istFax = gewaehlt?.fax ?? false
  const fragtKaeufer = gewaehlt ? (station !== 'waschen' || istFax) : true
  const fragtArt = station === 'waschen_sortieren'
  const fragtBaender = station === 'sortieren' || (station === 'waschen_sortieren' && art === 'kaliber')
  const fragtSoll = station === 'waschen_sortieren' && art === 'kiste'
  const fragtKaliber = station === 'waschen' && !istFax
  const fragtKisten = istFax

  const schritte = useMemo<SchrittId[]>(() => [
    'was', 'charge',
    ...(fragtKaeufer ? ['kaeufer' as const] : []),
    ...(fragtArt ? ['art' as const] : []),
    ...(fragtBaender ? ['baender' as const] : []),
    ...(fragtSoll ? ['soll' as const] : []),
    ...(fragtKaliber ? ['kaliber' as const] : []),
    ...(fragtKisten ? ['kisten' as const] : []),
    'pruefen',
  ], [fragtKaeufer, fragtArt, fragtBaender, fragtSoll, fragtKaliber, fragtKisten])
  const aktuell = schritte[Math.min(pos, schritte.length - 1)]
  const weiter = () => setPos(p => Math.min(p + 1, schritte.length - 1))
  const zurueck = () => (pos === 0 ? navigate('/') : setPos(p => p - 1))

  const charge = chargen.find(c => c.nr === chargeNr)
  const sorte = charge?.sorte
  const chargeBekannt = chargeNr !== '' && !!charge

  // Beim Waschen gelten die Bänder, mit denen die Charge sortiert wurde — die
  // Fassung des letzten Sortierlaufs. Dieselbe Regel wie der Auslöser in der
  // Datenbank; so zeigt die Maske dieselben Bänder, die später gerechnet werden.
  useEffect(() => {
    if (chargeNr === '' || !chargeBekannt) return
    let weg = false
    void supabase.from('sortier_lauf').select('sortierschema_id, datei_zeit, gelesen_ts')
      .eq('charge_nr', chargeNr).not('sortierschema_id', 'is', null)
      .order('gelesen_ts', { ascending: false }).limit(1)
      .then(({ data }) => {
        if (weg) return
        const z = (data ?? [])[0] as { sortierschema_id: number } | undefined
        setLaufSchema({ charge: chargeNr, id: z?.sortierschema_id ?? null })
      })
    return () => { weg = true }
  }, [chargeNr, chargeBekannt])

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
  const fassungLauf = laufSchema?.charge === chargeNr && laufSchema.id !== null
    ? schemata.find(x => x.id === laufSchema.id) : undefined
  const zuletztBaender: Band[] = (fragtKaliber || istFax ? fassungLauf?.kaliber_baender : undefined)
    ?? fassungKaliber?.kaliber_baender ?? []
  const zuletztSoll = fassungKiste?.soll_kg_pro_kiste ?? null
  const grenzenJetzt = grenzen ?? grenzenVon(zuletztBaender)
  const baenderJetzt = baenderVon(grenzenJetzt)
  const baenderGeaendert = grenzen !== null && !gleicheBaender(baenderJetzt, zuletztBaender)
  const baenderOk = aufsteigend(grenzenJetzt)
  const sollJetzt = soll ?? (zuletztSoll === null ? '' : String(zuletztSoll))
  const sollGeaendert = soll !== null && Number(soll) !== zuletztSoll
  const sollOk = Number(sollJetzt) > 0

  function grenzeSetzen(i: number, wert: string) {
    const g = [...grenzenJetzt]; g[i] = wert === '' ? Number.NaN : Number(wert); setGrenzen(g)
  }

  async function starten() {
    if (!gewaehlt || chargeNr === '' || !chargeBekannt || !sorte) return
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

    // Die Fassung: bestätigt oder geändert — die Datenbank entscheidet, ob es
    // eine neue wird (sortierschema_festlegen). Beim Waschen und beim Fax mit
    // Kaliber-Kisten erbt die Arbeit die Fassung des Sortierlaufs (Auslöser).
    let schemaId: number | null = null
    if (fragtBaender || fragtSoll) {
      const fuerArt = fragtSoll ? 'kiste' : 'kaliber'
      const { data, error } = await supabase.rpc('sortierschema_festlegen', {
        p_sorte: sorte, p_kaeufer: fragtKaeufer ? code : null, p_art: fuerArt,
        p_baender: fuerArt === 'kaliber' ? baenderJetzt : null,
        p_soll: fuerArt === 'kiste' ? Number(sollJetzt) : null,
        p_bemerkung: (baenderGeaendert || sollGeaendert) ? 'Beim Eröffnen der Arbeit geändert' : null,
      })
      if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
      schemaId = typeof data === 'number' ? data : null
    } else if (istFax && art === 'kiste') {
      schemaId = fassungKiste?.id ?? null
    }

    // Startzeit setzt der Server; die Fassung wird gewählt, nicht geraten.
    const { data, error } = await supabase.from('auftrag')
      .insert({ weg: gewaehlt.weg, station: gewaehlt.station, charge_nr: chargeNr,
                ist_fax: istFax,
                kaeufer: fragtKaeufer ? code : null,
                kaliber_idx: fragtKaliber && eigenes === null ? kaliberIdx : null,
                kaliber_von_g: fragtKaliber && eigenes !== null ? Number(eigenes.von) : null,
                kaliber_bis_g: fragtKaliber && eigenes !== null ? Number(eigenes.bis) : null,
                sortierschema_id: schemaId })
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
                  onClick={() => { setTaetigkeit(a.id); setArt(null); setKaliberIdx(null); setGrenzen(null); setSoll(null); setPos(1) }} />
          ))}
        </div>
      </Schritt>
    )
  }

  if (aktuell === 'charge') {
    return (
      <Schritt nummer={n} von={von} frage={t('welcheCharge')} warum={t('chargeWarum')}
               zurueck={zurueck} weiter={weiter} weiterMoeglich={chargeBekannt}>
        <ChargeFeld id="charge" chargen={chargen} wert={chargeNr} setzen={c => { setChargeNr(c); setGrenzen(null); setSoll(null) }} ohneLabel />
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
                  onClick={() => { setKaeuferCode(k.code); setGrenzen(null); setSoll(null); weiter() }} />
          ))}
          <Wahl id="kaeufer-keiner" name={t('ohneKaeufer')} gewaehlt={kaeuferCode === ''}
                onClick={() => { setKaeuferCode(''); setGrenzen(null); setSoll(null); weiter() }} />
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
    const kisteErkl = zuletztSoll != null ? `${t('artKisteErkl')} · ${zuletztSoll} kg` : t('artKisteErkl')
    const kaliberErkl = zuletztBaender.length > 0
      ? `${t('artKaliberErkl')} · ${zuletztBaender.length} ${t('baender')}` : t('artKaliberErkl')
    return (
      <Schritt nummer={n} von={von} frage={t('wieSortiert')} warum={t('wieSortiertWarum')} zurueck={zurueck}>
        <div className="wahl">
          <Wahl id="art-kiste" bild="📦" name={t('artKiste')} erkl={kisteErkl} gewaehlt={art === 'kiste'}
                onClick={() => { setArt('kiste'); weiter() }} />
          <Wahl id="art-kaliber" bild="📏" name={t('artKaliber')} erkl={kaliberErkl} gewaehlt={art === 'kaliber'}
                onClick={() => { setArt('kaliber'); weiter() }} />
        </div>
      </Schritt>
    )
  }

  if (aktuell === 'baender') {
    // Die Grenzen als Zahlen: zu klein unter der ersten, zu gross ab der
    // letzten, dazwischen die Bänder. Lückenlos per Bauart — nur die
    // Reihenfolge kann falsch sein, und das sagt die Maske.
    const g = grenzenJetzt
    return (
      <Schritt nummer={n} von={von} frage={t('welcheKaliber')} warum={t('kaliberWarum')} zurueck={zurueck}
               weiter={weiter} weiterMoeglich={baenderOk}>
        {zuletztBaender.length > 0 && (
          <div className="reihe" style={{ marginBottom: '.75rem' }}>
            <button id="baender-uebernehmen" className={grenzen === null ? 'haupt' : ''} style={{ flex: 1, minHeight: 50 }}
                    onClick={() => setGrenzen(null)}>{t('wieZuletzt')} · {t('uebernehmen')}</button>
            <button id="baender-anpassen" className={grenzen !== null ? 'haupt' : ''} style={{ flex: 1, minHeight: 50 }}
                    onClick={() => setGrenzen([...grenzenVon(zuletztBaender)])}>{t('anpassen')}</button>
          </div>
        )}
        <div className="karte">
          {g.length === 0 && (
            <>
              <Hinweis art="warnung">{t('kistenKeineBaender')}</Hinweis>
              <button id="baender-anlegen" style={{ width: '100%', minHeight: 50 }} onClick={() => setGrenzen([500, 1000, 1500, 2000])}>{t('bandDazu')}</button>
            </>
          )}
          {g.length > 0 && (
            <>
              <div className="feld">
                <label htmlFor="grenze-0">{t('zuKleinUnter')} ({t('gramm')})</label>
                <input id="grenze-0" type="number" inputMode="numeric" min={0} step={10} value={Number.isNaN(g[0]) ? '' : g[0]}
                       disabled={grenzen === null} onChange={e => grenzeSetzen(0, e.target.value)} style={{ fontSize: '1.15rem' }} />
              </div>
              {baenderJetzt.map((b, i) => (
                <div key={i} className="reihe" style={{ alignItems: 'end', marginBottom: '.5rem' }}>
                  <div style={{ flex: 1 }}><strong>{t('kaliber')} {i + 1}</strong><div className="leise">{Number.isNaN(b[0]) || Number.isNaN(b[1]) ? '—' : `${b[0]}–${b[1]} ${t('gramm')}`}</div></div>
                  <div className="feld" style={{ flex: 1, margin: 0 }}>
                    <label htmlFor={`grenze-${i + 1}`}>{i === baenderJetzt.length - 1 ? t('zuGrossAb') : t('bis')} ({t('gramm')})</label>
                    <input id={`grenze-${i + 1}`} type="number" inputMode="numeric" min={0} step={10} value={Number.isNaN(g[i + 1]) ? '' : g[i + 1]}
                           disabled={grenzen === null} onChange={e => grenzeSetzen(i + 1, e.target.value)} style={{ fontSize: '1.15rem' }} />
                  </div>
                </div>
              ))}
              {grenzen !== null && (
                <div className="reihe">
                  <button id="band-dazu" style={{ flex: 1 }} onClick={() => setGrenzen([...g, (g[g.length - 1] || 0) + 300])}>{t('bandDazu')}</button>
                  <button id="band-weg" style={{ flex: 1 }} disabled={g.length <= 2} onClick={() => setGrenzen(g.slice(0, -1))}>{t('bandWeg')}</button>
                </div>
              )}
              {!baenderOk && <Hinweis art="warnung">{t('baenderLueckenhaft')}</Hinweis>}
              {baenderGeaendert && baenderOk && <p className="leise">{t('geaendertGiltHeute')}</p>}
            </>
          )}
        </div>
      </Schritt>
    )
  }

  if (aktuell === 'soll') {
    return (
      <Schritt nummer={n} von={von} frage={t('sollKgFrage')} warum={t('sollKgWarum')} zurueck={zurueck}
               weiter={weiter} weiterMoeglich={sollOk}>
        {zuletztSoll !== null && (
          <div className="reihe" style={{ marginBottom: '.75rem' }}>
            <button id="soll-uebernehmen" className={soll === null ? 'haupt' : ''} style={{ flex: 1, minHeight: 50 }}
                    onClick={() => setSoll(null)}>{t('wieZuletzt')} · {zuletztSoll} kg</button>
            <button id="soll-anpassen" className={soll !== null ? 'haupt' : ''} style={{ flex: 1, minHeight: 50 }}
                    onClick={() => setSoll(String(zuletztSoll))}>{t('anpassen')}</button>
          </div>
        )}
        <div className="karte">
          <div className="feld">
            <label htmlFor="soll">{t('kgProKiste')}</label>
            <input id="soll" className="gross" type="number" inputMode="decimal" step="0.1" min={0} value={sollJetzt}
                   disabled={soll === null && zuletztSoll !== null} onChange={e => setSoll(e.target.value)} />
          </div>
          {sollGeaendert && sollOk && <p className="leise">{t('geaendertGiltHeute')}</p>}
        </div>
      </Schritt>
    )
  }

  if (aktuell === 'kaliber') {
    const eigenOk = eigenes !== null && eigenes.von !== '' && eigenes.bis !== ''
      && Number(eigenes.von) >= 0 && Number(eigenes.bis) > Number(eigenes.von)
    return (
      <Schritt nummer={n} von={von} frage={t('welchesKaliber')} warum={t('welchesKaliberWarum')} zurueck={zurueck}
               weiter={eigenes !== null ? weiter : undefined} weiterMoeglich={eigenOk}>
        {zuletztBaender.length > 0 && (
          <p className="leise" style={{ margin: '0 0 .5rem' }}>
            {fassungLauf ? t('kaliberQuelleLauf') : `${t('kaliberQuelleSorte')} · ${sorte ?? ''}`}
          </p>
        )}
        <div className="wahl">
          {zuletztBaender.map(([a, b], i) => (
            <Wahl key={i} id={`kaliber-${i}`} name={`${t('kaliber')} ${i + 1}`} erkl={`${a}–${b} g`}
                  gewaehlt={eigenes === null && kaliberIdx === i}
                  onClick={() => { setEigenes(null); setKaliberIdx(i); weiter() }} />
          ))}
          <Wahl id="kaliber-eigen" bild="✏️" name={t('anderesKaliber')} erkl={t('anderesKaliberErkl')}
                gewaehlt={eigenes !== null}
                onClick={() => { setKaliberIdx(null); setEigenes(e => e ?? { von: '', bis: '' }) }} />
        </div>
        {eigenes !== null && (
          <div className="karte">
            <div className="reihe" style={{ alignItems: 'end' }}>
              <div className="feld" style={{ flex: 1, margin: 0 }}>
                <label htmlFor="kaliber-von">{t('kaliberVon')}</label>
                <input id="kaliber-von" type="number" inputMode="numeric" min={0} step={10} value={eigenes.von}
                       onChange={e => setEigenes({ ...eigenes, von: e.target.value })} style={{ fontSize: '1.15rem' }} />
              </div>
              <div className="feld" style={{ flex: 1, margin: 0 }}>
                <label htmlFor="kaliber-bis">{t('kaliberBis')}</label>
                <input id="kaliber-bis" type="number" inputMode="numeric" min={0} step={10} value={eigenes.bis}
                       onChange={e => setEigenes({ ...eigenes, bis: e.target.value })} style={{ fontSize: '1.15rem' }} />
              </div>
            </div>
            <p className="leise" style={{ margin: '.5rem 0 0' }}>{t('kaliberEigenHinweis')}</p>
          </div>
        )}
        {zuletztBaender.length === 0 && eigenes === null && <Hinweis art="warnung">{t('kistenKeineBaender')}</Hinweis>}
      </Schritt>
    )
  }

  if (aktuell === 'kisten') {
    return (
      <Schritt nummer={n} von={von} frage={t('wasFuerKisten')} zurueck={zurueck}>
        <div className="wahl">
          <Wahl id="kisten-kaliber" bild="📏" name={t('artKaliber')} erkl={t('kistenKaliberErkl')} gewaehlt={art === 'kaliber'}
                onClick={() => { setArt('kaliber'); weiter() }} />
          <Wahl id="kisten-soll" bild="📦" name={t('artKiste')} erkl={`${t('kistenSollErkl')}${zuletztSoll != null ? ` · ${zuletztSoll} kg` : ''}`} gewaehlt={art === 'kiste'}
                onClick={() => { setArt('kiste'); weiter() }} />
        </div>
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
          {(fragtArt || fragtKisten) && <><dt>{t('sortierart')}</dt><dd>{art === 'kiste' ? t('artKiste') : t('artKaliber')}</dd></>}
          {fragtBaender && (
            <><dt>{t('kaliber')}</dt>
              <dd>{baenderJetzt.map(b => `${b[0]}–${b[1]}`).join(' · ')} g
                {baenderGeaendert ? <span className="leise"> · {t('geaendertGiltHeute')}</span>
                  : fassungKaliber && <span className="leise"> · {t('fassungVom')} {fassungKaliber.gilt_ab}{fassungKaliber.kaeufer === null && ` (${t('standard')})`}</span>}
              </dd></>
          )}
          {fragtSoll && (
            <><dt>{t('kgProKiste')}</dt>
              <dd>{sollJetzt} kg{sollGeaendert && <span className="leise"> · {t('geaendertGiltHeute')}</span>}</dd></>
          )}
          {fragtKaliber && (
            <><dt>{t('kaliber')}</dt>
              <dd>{eigenes !== null ? `${eigenes.von}–${eigenes.bis} g · ${t('anderesKaliber')}`
                : kaliberIdx === null ? '—' : `${kaliberIdx + 1} (${zuletztBaender[kaliberIdx]?.[0]}–${zuletztBaender[kaliberIdx]?.[1]} g)`}</dd></>
          )}
        </dl>
      </div>
      <p className="leise">{istFax ? t('dannFax') : t('dannPalox')}</p>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </Schritt>
  )
}
