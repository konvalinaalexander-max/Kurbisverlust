import { useEffect, useState } from 'react'
import { einstellung } from './db'

/**
 * Echt oder Beispiel — und warum das in der DATENBANK steht.
 *
 * Der Betrieb will zwei Webseiten: eine mit den echten Daten, eine mit den
 * Beispieldaten. Das sind zwei Builds, weil VITE_SUPABASE_URL zur Bauzeit
 * eingesetzt wird. Ein Build kann sich aber irren — jemand baut mit der
 * falschen .env-Datei und die Beispiel-Webseite zeigt plötzlich den Betrieb.
 *
 * Deshalb entscheidet nicht der Build, sondern die Datenbank: die
 * Einstellung `betriebsmodus`. Eine Datenbank weiss immer, was sie ist, und
 * kann nicht behaupten, die andere zu sein. Im Echtmodus verweigern
 * ausserdem die Beispieldaten den Dienst (Auslöser in 0072) — die App ist
 * hier nur das Schild, nicht das Schloss.
 */
export type Betriebsmodus = 'echt' | 'beispiel'

let gemerkt: Betriebsmodus | null = null

export async function betriebsmodusHolen(): Promise<Betriebsmodus> {
  if (gemerkt) return gemerkt
  const wert = await einstellung<string>('betriebsmodus', 'echt')
  gemerkt = wert === 'beispiel' ? 'beispiel' : 'echt'
  return gemerkt
}

/** Für Prüfstände: den gemerkten Wert vergessen. */
export function betriebsmodusVergessen() { gemerkt = null }

/**
 * Solange die App nicht weiss, was sie ist, gilt sie als echt. Lieber ein
 * fehlendes Band als ein falsches „nur Beispieldaten" über echten Zahlen.
 */
export function useBetriebsmodus(): Betriebsmodus {
  const [modus, setModus] = useState<Betriebsmodus>(gemerkt ?? 'echt')
  useEffect(() => {
    let weg = false
    void betriebsmodusHolen().then(m => { if (!weg) setModus(m) })
    return () => { weg = true }
  }, [])
  return modus
}
