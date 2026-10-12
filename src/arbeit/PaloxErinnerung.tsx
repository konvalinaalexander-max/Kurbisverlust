import { useState } from 'react'
import { useSprache } from '../sprache/SprachProvider'
import { ZKiste } from '../components/Zeichen'
import { PALOX_HINWEIS_MAL, gesehenLesen, paloxHinweisGesehen, paloxHinweisSchluessel, paloxHinweisZeigen } from './erinnerung'

/**
 * Der gelbe Kasten oben in der Arbeit: Palox voll? Zuerst in der App
 * (Runde AO, erinnerung.ts). Er zeigt auf den Knopf „Palox leeren", statt
 * selbst einer zu sein — wer ihn liest, soll nicht aus Versehen ein Leeren
 * anfangen, das gar nicht ansteht.
 */
export function PaloxErinnerung({ profilId, auftragId }: { profilId: string | undefined; auftragId: number }) {
  const { t } = useSprache()
  const [gesehen, setGesehen] = useState<number[]>(() => {
    if (!profilId) return []
    try { return gesehenLesen(localStorage.getItem(paloxHinweisSchluessel(profilId))) } catch { return [] }
  })
  if (!profilId || !paloxHinweisZeigen(gesehen, auftragId)) return null
  function verstanden() {
    const neu = paloxHinweisGesehen(gesehen, auftragId)
    try { localStorage.setItem(paloxHinweisSchluessel(profilId!), JSON.stringify(neu)) } catch { /* privater Modus: dann kommt er wieder */ }
    setGesehen(neu)
  }
  return (
    <div className="palox-erinnerung eintritt" id="palox-erinnerung" role="note">
      <div className="palox-erinnerung-kopf"><ZKiste size={22} /> <strong>{t('paloxHinweisTitel')}</strong></div>
      <p>{t('paloxHinweisText')}</p>
      <button type="button" id="palox-erinnerung-ok" onClick={verstanden}>
        {t('paloxHinweisOk')} <span className="leise">{gesehen.length + 1}/{PALOX_HINWEIS_MAL}</span>
      </button>
    </div>
  )
}
