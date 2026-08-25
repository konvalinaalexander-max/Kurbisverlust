import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { GEBIETSSCHEMA, SPRACHEN, uebersetze, type Sprache, type TextId } from '../lib/i18n'

const SCHLUESSEL = 'sprache'
const TAG_SCHLUESSEL = 'sprache_tag'

interface SprachWert {
  sprache: Sprache
  gebietsschema: string
  t: (id: TextId) => string
  setSprache: (s: Sprache) => void
  abfrageOffen: boolean
  abfrageOeffnen: () => void
}

const Kontext = createContext<SprachWert>({
  sprache: 'de', gebietsschema: 'de-CH',
  t: id => uebersetze('de', id),
  setSprache: () => {}, abfrageOffen: false, abfrageOeffnen: () => {},
})

const heute = () => new Date().toISOString().slice(0, 10)

function lesen(schluessel: string): string | null {
  try { return localStorage.getItem(schluessel) } catch { return null }
}

export function SprachProvider({ children }: { children: ReactNode }) {
  const [sprache, setSpracheIntern] = useState<Sprache>(() => {
    const gemerkt = lesen(SCHLUESSEL) as Sprache | null
    return gemerkt && SPRACHEN.some(s => s.code === gemerkt) ? gemerkt : 'de'
  })

  // Beim ersten Öffnen an einem Tag nach der Sprache fragen. Die Handys werden
  // untereinander weitergereicht — was gestern eingestellt war, sagt nichts
  // darüber, wer das Gerät heute in der Hand hat.
  const [abfrageOffen, setAbfrageOffen] = useState(() => lesen(TAG_SCHLUESSEL) !== heute())

  const setSprache = useCallback((s: Sprache) => {
    setSpracheIntern(s)
    setAbfrageOffen(false)
    try {
      localStorage.setItem(SCHLUESSEL, s)
      localStorage.setItem(TAG_SCHLUESSEL, heute())
    } catch { /* privater Modus: gilt dann nur für diese Sitzung */ }
  }, [])

  useEffect(() => { document.documentElement.lang = sprache }, [sprache])

  const wert: SprachWert = {
    sprache,
    gebietsschema: GEBIETSSCHEMA[sprache],
    t: (id: TextId) => uebersetze(sprache, id),
    setSprache,
    abfrageOffen,
    abfrageOeffnen: () => setAbfrageOffen(true),
  }
  return <Kontext.Provider value={wert}>{children}</Kontext.Provider>
}

export const useSprache = () => useContext(Kontext)

/** Die Flaggen-Auswahl. Kein Text außer den Sprachnamen — die versteht jeder. */
export function SprachAuswahl() {
  const { setSprache } = useSprache()
  return (
    <div className="huelle" style={{ maxWidth: 460, paddingTop: '3rem' }}>
      <div style={{ textAlign: 'center', fontSize: '3rem', marginBottom: '.5rem' }}>🎃</div>
      <div className="flaggen">
        {SPRACHEN.map(s => (
          <button key={s.code} className="flagge" onClick={() => setSprache(s.code)}
                  lang={s.code} aria-label={s.name}>
            <span className="flagge-bild">{s.flagge}</span>
            <span className="flagge-name">{s.name}</span>
          </button>
        ))}
      </div>
    </div>
  )
}
