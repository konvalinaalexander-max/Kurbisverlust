import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { einstellung, fehlerText } from '../lib/db'
import { Hinweis, Karte } from './Bausteine'
import { datum as datumText, tagVon } from '../lib/format'
import { tageZwischen } from '../lib/kontrollpalette'

/** Ab wie vielen Tagen ohne Sicherung die Zeile in Warnfarbe steht. */
const MAHNEN_AB_TAGEN = 30

/**
 * Die Erinnerung an die Sicherung (0072).
 *
 * Zwei Netze halten die Erfassung: das `erfassung_journal` hält jede
 * Änderung fest, auch ein Löschen, und `keine_zerstoerung.sh` sorgt dafür,
 * dass keine Migration Daten wegnimmt. Beides hilft nicht, wenn die
 * Datenbank als Ganzes verschwindet.
 *
 * Dafür gibt es keinen automatischen Mechanismus — und es soll auch keiner
 * vorgetäuscht werden. Der Betriebsleiter zieht die Sicherung selbst (der
 * Weg steht in docs/DATENERHEBUNG.md) und vermerkt hier, wann. Eine Zahl,
 * die von Hand gepflegt wird und das auch sagt, ist ehrlicher als ein
 * Häkchen, das etwas verspricht.
 */
export default function Sicherung() {
  const [wann, setWann] = useState<string | null>(null)
  const [scharf, setScharf] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void einstellung<string | null>('letzte_sicherung', null).then(w => setWann(w ?? null))
    void einstellung<boolean>('erfassung_scharf', false).then(s => setScharf(Boolean(s)))
  }, [])

  async function vermerken() {
    setLaeuft(true); setFehler(null)
    const heute = tagVon(new Date())
    const { error } = await supabase.from('einstellung')
      .update({ wert: heute }).eq('schluessel', 'letzte_sicherung')
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    setWann(heute)
  }

  const tage = wann ? tageZwischen(wann, new Date()) : null
  const mahnen = tage === null || tage >= MAHNEN_AB_TAGEN

  return (
    <Karte titel="Sicherung" unter="Das Journal hält jede Änderung fest — aber nicht, wenn die Datenbank selbst verschwindet. Der Weg steht in docs/DATENERHEBUNG.md, Abschnitt 3.">
      <p style={{ margin: '0 0 .6rem' }}>
        Letzte vermerkte Sicherung:{' '}
        <strong style={mahnen ? { color: 'var(--gelb)' } : undefined}>
          {wann ? `${datumText(wann)} · vor ${tage} Tagen` : 'noch keine vermerkt'}
        </strong>
      </p>
      {scharf && (
        <Hinweis>Auf dieser Datenbank stehen echte Erfassungsdaten. Vor jedem Einspielen von setup.sql eine Sicherung ziehen.</Hinweis>
      )}
      {mahnen && wann && (
        <Hinweis art="warnung">Die letzte Sicherung ist über {MAHNEN_AB_TAGEN} Tage her.</Hinweis>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <button type="button" id="sicherung-vermerken" disabled={laeuft}
              onClick={() => void vermerken()}>Heute gesichert — vermerken</button>
    </Karte>
  )
}
