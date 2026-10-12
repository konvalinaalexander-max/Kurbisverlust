import { useState, type ReactNode } from 'react'
import { useSprache } from '../sprache/SprachProvider'
import { ZKiste, ZInfo } from '../components/Zeichen'
import { PALOX_HINWEIS_MAL, SORTIERDATUM_HINWEIS_MAL, gesehenLesen, hinweisZeigen, paloxHinweisGesehen,
         paloxHinweisSchluessel, sortierdatumHinweisSchluessel } from './erinnerung'

/**
 * Ein gelber Kasten oben in der Arbeit, der je Person in einigen Arbeiten
 * steht, bis „Verstanden" ihn wegtippt (Runde AO, erinnerung.ts). Gemerkt
 * wird auf dem Gerät, je Profil.
 */
function Erinnerung({ profilId, auftragId, schluessel, mal, id, zeichen, titel, text, ok }: {
  profilId: string | undefined; auftragId: number; schluessel: (profilId: string) => string; mal: number
  id: string; zeichen: ReactNode; titel: string; text: string; ok: string
}) {
  const [gesehen, setGesehen] = useState<number[]>(() => {
    if (!profilId) return []
    try { return gesehenLesen(localStorage.getItem(schluessel(profilId))) } catch { return [] }
  })
  if (!profilId || !hinweisZeigen(gesehen, auftragId, mal)) return null
  function verstanden() {
    const neu = paloxHinweisGesehen(gesehen, auftragId)
    try { localStorage.setItem(schluessel(profilId!), JSON.stringify(neu)) } catch { /* privater Modus: dann kommt er wieder */ }
    setGesehen(neu)
  }
  return (
    <div className="palox-erinnerung eintritt" id={id} role="note">
      <div className="palox-erinnerung-kopf">{zeichen} <strong>{titel}</strong></div>
      <p>{text}</p>
      <button type="button" id={`${id}-ok`} onClick={verstanden}>
        {ok} <span className="leise">{gesehen.length + 1}/{mal}</span>
      </button>
    </div>
  )
}

/**
 * Palox voll? Zuerst in der App (Runde AO). Er zeigt auf den Knopf „Palox
 * leeren", statt selbst einer zu sein — wer ihn liest, soll nicht aus
 * Versehen ein Leeren anfangen, das gar nicht ansteht.
 */
export function PaloxErinnerung({ profilId, auftragId }: { profilId: string | undefined; auftragId: number }) {
  const { t } = useSprache()
  return <Erinnerung profilId={profilId} auftragId={auftragId} schluessel={paloxHinweisSchluessel} mal={PALOX_HINWEIS_MAL}
                     id="palox-erinnerung" zeichen={<ZKiste size={22} />}
                     titel={t('paloxHinweisTitel')} text={t('paloxHinweisText')} ok={t('paloxHinweisOk')} />
}

/** Das Sortierdatum muss nicht mehr auf den Zettel (Runde AP), fünfmal je Person. */
export function SortierdatumErinnerung({ profilId, auftragId }: { profilId: string | undefined; auftragId: number }) {
  const { t } = useSprache()
  return <Erinnerung profilId={profilId} auftragId={auftragId} schluessel={sortierdatumHinweisSchluessel} mal={SORTIERDATUM_HINWEIS_MAL}
                     id="sortierdatum-erinnerung" zeichen={<ZInfo size={22} />}
                     titel={t('sortierdatumHinweisTitel')} text={t('sortierdatumHinweisText')} ok={t('paloxHinweisOk')} />
}
