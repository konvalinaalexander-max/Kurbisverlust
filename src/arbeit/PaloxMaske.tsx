import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { einstellung, fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { uhrzeit, type ArbeitDaten } from './daten'

/**
 * Den Palox ablesen (AB-02, AB-10). Der Arbeiter tippt ab, was die Waage
 * zeigt — die Differenz zum letzten Stand rechnet die App und zeigt sie, bevor
 * gespeichert wird. Gespeichert wird der Stand, die Menge ist Ableitung.
 *
 * `unveraendertErlaubt`: im Abschluss darf gesagt werden „seit der letzten
 * Ablesung kam nichts dazu" — das ist eine Messung (0 kg), kein Auslassen.
 */
export function PaloxMaske({ d, gesperrt, gespeichert, unveraendertErlaubt = false }: {
  d: ArbeitDaten; gesperrt: boolean
  gespeichert: () => Promise<void>
  unveraendertErlaubt?: boolean
}) {
  const { t, gebietsschema } = useSprache()
  const [vorher, setVorher] = useState<number | null>(null)
  const [tara, setTara] = useState(0)
  const [stand, setStand] = useState('')
  const [leer, setLeer] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void Promise.all([
      supabase.rpc('palox_letzter_stand', { p_station: d.auftrag.station }),
      einstellung<number>('palox_tara_kg', 0),
    ]).then(([v, ta]) => {
      setVorher(typeof v.data === 'number' ? v.data : null)
      setTara(Number(ta) || 0)
    })
  }, [d.auftrag.station, d.ablesungen.length])

  const n = stand === '' ? null : Number(stand)
  const geleert = leer || (n !== null && vorher !== null && n < vorher)
  const menge = n === null ? null : vorher === null || geleert ? n - tara : n - vorher
  const jePalette = menge !== null && d.paletten.length > 0 ? menge / d.paletten.length : null
  const verdaechtig = jePalette !== null && jePalette > 120

  async function speichern(unveraendert = false) {
    setLaeuft(true); setFehler(null)
    const zeile = unveraendert
      ? { auftrag_id: d.auftrag.id, kg: 0, palox_stand_kg: vorher, palox_geleert: false }
      : { auftrag_id: d.auftrag.id, kg: Math.round(Math.max(menge ?? 0, 0)), palox_stand_kg: n, palox_geleert: leer }
    const { error } = await supabase.from('schimmel_messung').insert(zeile)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    setStand(''); setLeer(false)
    await gespeichert()
  }

  const letzte = d.ablesungen[d.ablesungen.length - 1]
  const summe = d.ablesungen.reduce((s, z) => s + z.kg, 0)

  return (
    <div className="karte">
      <div className="feld">
        <label htmlFor="palox">{t('waageZeigt')}</label>
        <input id="palox" className="gross" type="number" inputMode="decimal" min={0} step="0.5"
               value={stand} disabled={gesperrt} onChange={e => setStand(e.target.value)} autoFocus />
        <p className="leise" style={{ margin: '.4rem 0 0' }}>{t('waageAblesenHinweis')}</p>
      </div>
      <label className="ankreuzen">
        <input type="checkbox" checked={leer} disabled={gesperrt} onChange={e => setLeer(e.target.checked)} />
        {t('paloxWarLeer')}
      </label>
      {menge !== null && (
        <p style={{ margin: '.6rem 0', fontSize: '1.15rem' }}>
          <strong>{Math.round(Math.max(menge, 0))} kg</strong>
          {vorher !== null && !geleert && <span className="leise"> ({n} − {vorher})</span>}
          {(vorher === null || geleert) && tara > 0 && <span className="leise"> ({n} − {tara})</span>}
          {jePalette !== null && <span className="leise"> · {Math.round(jePalette)} {t('kgJePalette')}</span>}
        </p>
      )}
      {verdaechtig && <Hinweis art="warnung">{t('vielJePalette')}</Hinweis>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <button id="palox-eintragen" className="haupt" style={{ width: '100%', minHeight: 60, fontSize: '1.08rem' }}
              onClick={() => void speichern()} disabled={gesperrt || laeuft || menge === null || menge < 0}>
        {t('eintragen')}
      </button>
      {unveraendertErlaubt && letzte && (
        <button id="palox-unveraendert" style={{ width: '100%', marginTop: '.6rem', minHeight: 48 }}
                onClick={() => void speichern(true)} disabled={gesperrt || laeuft}>
          {t('standUnveraendert')}
        </button>
      )}
      {d.ablesungen.length > 0 && (
        <p className="leise" style={{ marginTop: '1rem', marginBottom: 0 }}>
          {t('zuletztAbgelesen')} {uhrzeit(letzte.ts, gebietsschema)} · {t('bisher')}: {summe} kg
          {' '}({d.ablesungen.length} {t('ablesungen')})
        </p>
      )}
    </div>
  )
}
