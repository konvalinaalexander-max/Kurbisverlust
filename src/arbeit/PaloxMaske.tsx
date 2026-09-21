import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { uhrzeit, type ArbeitDaten } from './daten'

/**
 * Den Palox ablesen (AB-02, AB-10, 0073).
 *
 * Die Regel des Betriebs: „arbeitsschritte werden nie über nacht pausiert …
 * deswegen soll nie von der letzten arbeit der palox wert irgendwie
 * übernommen werden." Jede Arbeit liest **ihren eigenen** Anfang und ihr
 * eigenes Ende ab; die Menge ist die Differenz dazwischen.
 *
 *   erste Ablesung dieser Arbeit  →  Startstand, keine Menge
 *   jede weitere                  →  Stand − vorheriger Stand
 *
 * Das Leergewicht der Box kürzt sich in der Differenz von selbst heraus und
 * wird nirgends abgezogen — und seit Runde T auch nirgends mehr erwähnt.
 *
 * Fällt der Stand, wurde der Palox zwischendurch geleert. Dann ist die Menge
 * dieser Arbeit **unbekannt**, nicht null (Regel „leer ist nicht null"). Vor
 * 0073 wurde in diesem Fall gar nichts angezeigt und stillschweigend
 * `kg: 0` gespeichert — aus unbekannt wurde eine behauptete Null. Jetzt
 * fragt die Maske, und die Antwort setzt `auftrag.palox_unbekannt`.
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
  const [stand, setStand] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    // Nur noch innerhalb DIESER Arbeit — nie über die Arbeitsgrenze hinweg.
    // Runde T: das Leergewicht der Box wird nicht mehr angezeigt — es kürzt
    // sich in der Differenz heraus, und der Satz dazu verwirrte mehr, als er
    // half („rechnet es minus 445?"). Der Arbeiter tippt ab, was die Waage zeigt.
    void supabase.rpc('palox_stand_dieser_arbeit', { p_auftrag_id: d.auftrag.id })
      .then(v => setVorher(typeof v.data === 'number' ? v.data : null))
  }, [d.auftrag.id, d.ablesungen.length])

  const n = stand === '' ? null : Number(stand)
  const erste = vorher === null
  const gefallen = n !== null && vorher !== null && n < vorher
  // Startstand: keine Menge. Sonst die Differenz — und bei gefallenem Stand
  // gar nichts, bis der Arbeiter gesagt hat, was los war.
  const menge = n === null || erste ? null : gefallen ? null : n - vorher
  const jePalette = menge !== null && d.paletten.length > 0 ? menge / d.paletten.length : null
  const verdaechtig = jePalette !== null && jePalette > 120

  const ersetzen = (text: string, werte: Record<string, number>) =>
    Object.entries(werte).reduce((s, [k, v]) => s.replace(`{${k}}`, String(v)), text)

  async function speichern(art: 'normal' | 'unveraendert' | 'geleert') {
    setLaeuft(true); setFehler(null)
    // Der Stand ist da, die Menge nicht: `palox_geleert` heisst für die
    // Auswertung „Differenz unbekannt" — nicht „null Kilo" (0064/0073).
    const zeile: {
      auftrag_id: number; kg: number; palox_stand_kg: number | null
      palox_geleert: boolean; gemessen?: boolean
    } =
      art === 'unveraendert'
        ? { auftrag_id: d.auftrag.id, kg: 0, palox_stand_kg: vorher, palox_geleert: false }
        : art === 'geleert'
          ? { auftrag_id: d.auftrag.id, kg: 0, palox_stand_kg: n, palox_geleert: true }
          : { auftrag_id: d.auftrag.id, kg: Math.round(Math.max(menge ?? 0, 0)), palox_stand_kg: n, palox_geleert: false }
    const { error } = await supabase.from('schimmel_messung').insert(zeile)
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    if (art === 'geleert') {
      // Die ganze Arbeit ist damit ohne bekannte Faul-Menge.
      const { error: e2 } = await supabase.from('auftrag')
        .update({ palox_unbekannt: true }).eq('id', d.auftrag.id)
      if (e2) { setLaeuft(false); setFehler(fehlerText(e2)); return }
    }
    setLaeuft(false)
    setStand('')
    await gespeichert()
  }

  const letzte = d.ablesungen[d.ablesungen.length - 1]
  const summe = d.ablesungen.reduce((s, z) => s + z.kg, 0)

  return (
    <div className="karte">
      {!erste && (
        <p className="leise unten-0">{t('paloxBeiBeginn')}: <strong>{vorher} kg</strong></p>
      )}
      <div className="feld">
        <label htmlFor="palox">{t('waageZeigt')}</label>
        <input id="palox" className="gross" type="number" inputMode="decimal" min={0} step="0.5"
               value={stand} disabled={gesperrt} onChange={e => setStand(e.target.value)} autoFocus />
      </div>

      {/* Startstand: die App zeigt ausdrücklich, dass das noch keine Menge ist. */}
      {erste && n !== null && (
        <p className="netto-zeile"><strong>{t('paloxStartstand')}</strong></p>
      )}

      {menge !== null && (
        <p className="netto-zeile">
          <strong>{Math.round(Math.max(menge, 0))} kg</strong>
          <span className="leise"> ({n} − {vorher})</span>
          {jePalette !== null && <span className="leise"> · {Math.round(jePalette)} {t('kgJePalette')}</span>}
        </p>
      )}

      {/* Der gefallene Stand: fragen statt schweigen. Vor 0073 stand hier
          nichts und „Eintragen" schrieb eine Null. */}
      {gefallen && (
        <Hinweis art="warnung">
          {ersetzen(t('paloxGefallen'), { vorher: vorher!, jetzt: n! })}
          {' '}{t('paloxGeleertFrage')}
        </Hinweis>
      )}
      {verdaechtig && <Hinweis art="warnung">{t('vielJePalette')}</Hinweis>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      {gefallen ? (
        <>
          <button type="button" id="palox-geleert" className="haupt gross voll"
                  onClick={() => void speichern('geleert')} disabled={gesperrt || laeuft}>
            {t('paloxGeleertJa')}
          </button>
          <p className="hilfe">{t('paloxGeleertFolge')}</p>
          <button type="button" id="palox-vertippt" className="voll" style={{ marginTop: '.6rem', minHeight: 48 }}
                  onClick={() => setStand('')} disabled={gesperrt || laeuft}>
            {t('paloxVertippt')}
          </button>
        </>
      ) : (
        <button type="button" id="palox-eintragen" className="haupt gross voll"
                onClick={() => void speichern('normal')} disabled={gesperrt || laeuft || n === null || n < 0}>
          {t('eintragen')}
        </button>
      )}

      {unveraendertErlaubt && letzte && !gefallen && (
        <button type="button" id="palox-unveraendert" className="voll" style={{ marginTop: '.6rem', minHeight: 48 }}
                onClick={() => void speichern('unveraendert')} disabled={gesperrt || laeuft}>
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
