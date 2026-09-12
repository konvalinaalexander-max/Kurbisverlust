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
 * Liegt der Stand unter dem letzten (der Palox wurde zwischendurch geleert),
 * wird nichts gefragt und nichts Negatives gezeigt: der Stand wird genommen,
 * die Menge dieser Arbeit ist für die Auswertung unbekannt (0060). Die
 * Waschstrasse hat einen Palox — Waschen und Waschen + Sortieren teilen ihn.
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
  const gefallen = n !== null && vorher !== null && n < vorher
  const menge = n === null ? null : vorher === null ? Math.max(n - tara, 0) : gefallen ? null : n - vorher
  const jePalette = menge !== null && d.paletten.length > 0 ? menge / d.paletten.length : null
  const verdaechtig = jePalette !== null && jePalette > 120

  async function speichern(unveraendert = false) {
    setLaeuft(true); setFehler(null)
    const zeile = unveraendert
      ? { auftrag_id: d.auftrag.id, kg: 0, palox_stand_kg: vorher, palox_geleert: false }
      : { auftrag_id: d.auftrag.id, kg: Math.round(Math.max(menge ?? 0, 0)), palox_stand_kg: n, palox_geleert: false }
    const { error } = await supabase.from('schimmel_messung').insert(zeile)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    setStand('')
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
        <p className="hilfe">{t('waageAblesenHinweis')}</p>
      </div>
      {menge !== null && (
        <p className="netto-zeile">
          <strong>{Math.round(Math.max(menge, 0))} kg</strong>
          {vorher !== null && <span className="leise"> ({n} − {vorher})</span>}
          {vorher === null && tara > 0 && <span className="leise"> ({n} − {tara})</span>}
          {jePalette !== null && <span className="leise"> · {Math.round(jePalette)} {t('kgJePalette')}</span>}
        </p>
      )}
      {verdaechtig && <Hinweis art="warnung">{t('vielJePalette')}</Hinweis>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <button type="button" id="palox-eintragen" className="haupt gross voll"
              onClick={() => void speichern()} disabled={gesperrt || laeuft || n === null || n < 0}>
        {t('eintragen')}
      </button>
      {unveraendertErlaubt && letzte && (
        <button type="button" id="palox-unveraendert" className="voll" style={{ marginTop: '.6rem', minHeight: 48 }}
                onClick={() => void speichern(true)} disabled={gesperrt || laeuft}>
          {t('standUnveraendert')}
        </button>
      )}
      {d.ablesungen.length > 0 && (
        <p className="leise abstand-oben unten-0">
          {t('zuletztAbgelesen')} {uhrzeit(letzte.ts, gebietsschema)} · {t('bisher')}: {summe} kg
          {' '}({d.ablesungen.length} {t('ablesungen')})
        </p>
      )}
    </div>
  )
}
