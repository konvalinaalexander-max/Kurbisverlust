import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { einstellung, fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import type { ArbeitDaten } from './daten'

/**
 * Den Palox mitten in der Arbeit leeren — ohne dass die Menge verloren geht
 * (0084).
 *
 * Zwei Ablesungen, in dieser Reihenfolge:
 *
 *   1. vor dem Leeren    — eine normale Ablesung: Stand − voriger Stand
 *   2. nach dem Leeren   — die leere Box auf der Waage: keine Menge,
 *                          sondern der neue Anfang für alles Weitere
 *
 * Der Betrieb: „im dashboard sagt man - palox leeren - man wird gefragt
 * wie viel es war". Die zweite Ablesung ist die, die den Unterschied macht:
 * Ohne sie wüsste die App nicht, von wo aus sie am Ende weiterrechnet.
 * Vorbelegt ist sie mit dem Leergewicht aus den Einstellungen — und sagt
 * das, damit die Zahl nicht wie gemessen aussieht (AB-50). Wer die Waage
 * abliest, überschreibt sie.
 */
export function PaloxLeerenMaske({ d, fertig }: { d: ArbeitDaten; fertig: () => Promise<void> }) {
  const { t } = useSprache()
  const [vorher, setVorher] = useState<number | null>(null)
  const [leergewicht, setLeergewicht] = useState<number | null>(null)
  const [schritt, setSchritt] = useState<'vor' | 'nach'>('vor')
  const [stand, setStand] = useState('')
  const [vorbelegt, setVorbelegt] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void supabase.rpc('palox_stand_dieser_arbeit', { p_auftrag_id: d.auftrag.id })
      .then(v => setVorher(typeof v.data === 'number' ? v.data : null))
    void einstellung<number | null>('palox_tara_kg', null)
      .then(v => setLeergewicht(typeof v === 'number' && v > 0 ? v : null))
  }, [d.auftrag.id])

  const n = stand === '' ? null : Number(stand)
  const ersetzen = (text: string, werte: Record<string, number>) =>
    Object.entries(werte).reduce((s, [k, v]) => s.replace(`{${k}}`, String(v)), text)

  // Schritt 1: Die Menge bis jetzt. Ein Stand unter dem vorigen kann nicht
  // „vor dem Leeren" sein — dann ist schon geleert worden, und das gehört
  // in die normale Ablesemaske, die es als unbekannt festhält.
  const menge = n !== null && vorher !== null ? n - vorher : null
  const niedriger = menge !== null && menge < 0

  async function vorSpeichern() {
    if (n === null || vorher === null || niedriger || laeuft) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from('schimmel_messung').insert({
      auftrag_id: d.auftrag.id, kg: Math.round(menge ?? 0), palox_stand_kg: n, palox_geleert: false,
    })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    setVorher(n)
    setStand(leergewicht !== null ? String(leergewicht) : '')
    setVorbelegt(leergewicht !== null)
    setSchritt('nach')
  }

  // Schritt 2: der neue Anfang. Keine Menge — kg ist 0, der Stand zählt.
  async function nachSpeichern() {
    if (n === null || n < 0 || laeuft) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from('schimmel_messung').insert({
      auftrag_id: d.auftrag.id, kg: 0, palox_stand_kg: n, palox_geleert: false, palox_nach_leeren: true,
    })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    await fertig()
  }

  if (vorher === null) {
    return <div className="karte"><Hinweis art="info">{t('paloxVorAbschluss')}</Hinweis></div>
  }

  if (schritt === 'vor') {
    return (
      <div className="karte">
        <p className="leise unten-0">{t('zuletztAbgelesen')}: <strong>{vorher} kg</strong></p>
        <div className="feld">
          <label htmlFor="palox-vor">{t('paloxVorLeeren')}</label>
          <input id="palox-vor" className="gross" type="number" inputMode="decimal" min={0} step="0.5"
                 value={stand} onChange={e => setStand(e.target.value)} autoFocus />
        </div>
        {menge !== null && !niedriger && (
          <p className="netto-zeile">
            <strong>{Math.round(menge)} kg</strong>
            <span className="leise"> ({n} − {vorher})</span>
          </p>
        )}
        {niedriger && <p className="grund" role="status">{ersetzen(t('paloxVorLeerenNiedriger'), { vorher })}</p>}
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <button type="button" id="palox-vor-eintragen" className="haupt gross voll"
                onClick={() => void vorSpeichern()} disabled={laeuft || n === null || niedriger}>
          {t('eintragen')}
        </button>
      </div>
    )
  }

  return (
    <div className="karte">
      <Hinweis art="info">{t('paloxJetztLeeren')}</Hinweis>
      <div className="feld">
        <label htmlFor="palox-nach">{t('paloxNachLeeren')}</label>
        <input id="palox-nach" className="gross" type="number" inputMode="decimal" min={0} step="0.5"
               value={stand} onChange={e => { setStand(e.target.value); setVorbelegt(false) }} autoFocus />
        {vorbelegt && <p className="hilfe">{t('paloxLeerGewichtVorbelegt')}</p>}
      </div>
      {n !== null && <p className="netto-zeile"><strong>{t('paloxNeuerAnfang')}</strong></p>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <button type="button" id="palox-nach-eintragen" className="haupt gross voll"
              onClick={() => void nachSpeichern()} disabled={laeuft || n === null || n < 0}>
        {t('eintragen')}
      </button>
    </div>
  )
}
