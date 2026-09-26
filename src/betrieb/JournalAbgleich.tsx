import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { einstellung, fehlerText, stammdaten } from '../lib/db'
import { importErkennen } from '../lib/import'
import { Hinweis } from '../components/Bausteine'

/** Nicht öfter als alle zehn Minuten je Gerät — das Sheet ist geduldig, aber nicht unendlich. */
const ABSTAND_MS = 10 * 60 * 1000
const MERKZETTEL = 'journal_abgleich_zuletzt'

/**
 * Das Erntejournal von selbst nachziehen (Runde X).
 *
 * Der Betrieb: „Wird das jedes Mal neu runtergezogen? … Wenn möglich, schau,
 * dass es automatisiert ist, dass da immer die neuesten Daten drin sind."
 * Also: Steht die veröffentlichte CSV-Adresse in den Einstellungen, holt das
 * Dashboard beim Öffnen die Datei und übernimmt, was neu ist. NUR was neu ist:
 * Eine Palette, die schon da ist (gleiche extern_id), wird nicht angefasst —
 * was der Betriebsleiter berichtigt hat, bleibt berichtigt. Der volle Abgleich
 * mit Vorschau bleibt unter Betrieb → Stammdaten.
 *
 * Scheitert der Abruf, sagt die Karte es leise und die Seite läuft weiter.
 */
export function JournalAbgleich({ neuGerechnet }: { neuGerechnet?: () => void }) {
  const [meldung, setMeldung] = useState<{ art: 'gut' | 'warnung' | 'info'; text: string } | null>(null)

  useEffect(() => {
    let lebt = true
    void (async () => {
      try {
        const url = (await einstellung<string>('journal_csv_url', '')).trim()
        if (!url) return
        let zuletzt = 0
        try { zuletzt = Number(localStorage.getItem(MERKZETTEL) ?? 0) } catch { /* privates Fenster */ }
        if (Date.now() - zuletzt < ABSTAND_MS) return
        const antwort = await fetch(url, { redirect: 'follow' })
        if (!antwort.ok) throw new Error(`Das Erntejournal antwortete mit ${antwort.status}.`)
        const csv = await antwort.text()
        if (/^\s*</.test(csv)) throw new Error('Die Journal-Adresse liefert eine Webseite statt CSV.')
        const { chargen } = await stammdaten()
        const b = importErkennen(csv, chargen)
        try { localStorage.setItem(MERKZETTEL, String(Date.now())) } catch { /* dann eben jedes Mal */ }
        if (!lebt) return
        if (b.paletten.length === 0) { setMeldung({ art: 'warnung', text: 'Erntejournal geholt, aber keine Palette erkannt — bitte unter Stammdaten nachsehen.' }); return }
        // Nur, was es noch nicht gibt: erst nachsehen, dann anlegen — der
        // Upsert mit ignoreDuplicates täte dasselbe, sagt aber nicht, wie viele.
        const ids = b.paletten.map(z => z.extern_id)
        const bekannt = new Set<string>()
        for (let i = 0; i < ids.length; i += 500) {
          const { data, error } = await supabase.from('palette').select('extern_id').in('extern_id', ids.slice(i, i + 500))
          if (error) throw error
          for (const z of (data ?? []) as { extern_id: string }[]) bekannt.add(z.extern_id)
        }
        const neue = b.paletten.filter(z => !bekannt.has(z.extern_id))
        if (neue.length === 0) return
        const arten = [...new Set(neue.map(z => z.gebindeart).filter(Boolean))] as string[]
        if (arten.length) {
          const { error } = await supabase.from('gebinde').upsert(arten.map(art => ({ art })), { onConflict: 'art', ignoreDuplicates: true })
          if (error) throw error
        }
        const ohneLeere = neue.map(z => { const r: Record<string, unknown> = {}; for (const [k, v] of Object.entries(z)) if (v !== null) r[k] = v; return r })
        for (let i = 0; i < ohneLeere.length; i += 500) {
          const { error } = await supabase.from('palette').upsert(ohneLeere.slice(i, i + 500), { onConflict: 'extern_id', ignoreDuplicates: true })
          if (error) throw error
        }
        void stammdaten(true)
        if (!lebt) return
        setMeldung({ art: 'gut', text: `${neue.length === 1 ? '1 neue Palette' : `${neue.length} neue Paletten`} aus dem Erntejournal übernommen${b.probleme.length ? ` · ${b.probleme.length} Zeilen nicht erkannt (unter Stammdaten nachsehen)` : ''}. Die Ergebnisse rechnen neu.` })
        const { error: e2 } = await supabase.rpc('auswertung_aktualisieren')
        if (!e2) neuGerechnet?.()
      } catch (f) {
        if (lebt) setMeldung({ art: 'warnung', text: `Erntejournal nicht abgeglichen: ${fehlerText(f)}` })
      }
    })()
    return () => { lebt = false }
  }, [neuGerechnet])

  if (!meldung) return null
  return (
    <Hinweis art={meldung.art}>
      {meldung.text} <Link to="/betrieb/stammdaten">Stammdaten</Link>
    </Hinweis>
  )
}
