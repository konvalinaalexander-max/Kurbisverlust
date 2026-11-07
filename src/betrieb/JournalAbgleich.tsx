import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { chargenAnlegen, einstellung, fehlerText, stammdaten } from '../lib/db'
import { abgleichMeldung, importErkennen, journalAbgleichen, verdachtSatz, type BekanntePalette } from '../lib/import'
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
 * Dashboard beim Öffnen die Datei und übernimmt, was neu ist. Runde BJ: dazu,
 * was eine Journalzeile mit ID an einer bekannten Palette berichtigt hat
 * (Charge, Tag, Gewicht, Kisten, Gebinde — journalAbgleichen). Eine Zeile ohne
 * ID, die wohl eine berichtigte ist, legt keine zweite Palette an; die Meldung
 * sagt es. Der volle Abgleich mit Vorschau bleibt unter Betrieb → Stammdaten.
 *
 * Scheitert der Abruf, sagt die Karte es leise und die Seite läuft weiter.
 *
 * 0107: Danach wird NICHT neu gerechnet. Bis 0107 startete der Abgleich die
 * volle Rechnung aus dem Browser — einer der drei Wege, die die Datenbank am
 * 29. September lahmlegten. Die neuen Paletten zählen ab der nächsten
 * Rechnung: heute Nacht oder auf „Neu rechnen".
 */
export function JournalAbgleich() {
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
        const { chargen, aliase } = await stammdaten()
        const b = importErkennen(csv, chargen, aliase)
        try { localStorage.setItem(MERKZETTEL, String(Date.now())) } catch { /* dann eben jedes Mal */ }
        if (!lebt) return
        // 22. Oktober: Stehen nur Zeilen ohne Charge da, sagt das die Meldung unten mit dem Grund.
        if (b.paletten.length === 0 && b.probleme.length === 0) { setMeldung({ art: 'warnung', text: 'Erntejournal geholt, aber keine Palette erkannt — bitte unter Stammdaten nachsehen.' }); return }
        // Nur, was es noch nicht gibt: erst nachsehen, dann anlegen — der
        // Upsert mit ignoreDuplicates täte dasselbe, sagt aber nicht, wie viele.
        // Runde AD: nicht mehr 500 Kennungen in einer Adresszeile (17 KB, am
        // 28. September „Bad Request"), sondern alle Kennungen des Journals
        // aus der Datenbank geblättert — 1000 je Anfrage, kurze Adresse.
        const bekannt: BekanntePalette[] = []
        for (let von = 0; ; von += 1000) {
          const { data, error } = await supabase.from('palette')
            .select('id, extern_id, charge_nr, charge_nr_journal, eingangsdatum, brutto_kg, kisten, gebindeart')
            .eq('quelle', 'journal-import').order('id').range(von, von + 999)
          if (error) throw error
          bekannt.push(...((data ?? []) as BekanntePalette[]).map(p => ({ ...p, brutto_kg: p.brutto_kg === null ? null : Number(p.brutto_kg) })))
          if ((data ?? []).length < 1000) break
        }
        const { neu: neue, korrekturen, verdacht } = journalAbgleichen(b.paletten, bekannt)
        // Runde BJ: Berichtigungen an bekannten Paletten (Zeilen mit ID) übernehmen — Feld für Feld, was anders ist.
        for (const k of korrekturen) {
          const { error } = await supabase.from('palette').update(k.felder).eq('id', k.id)
          if (error) throw error
        }
        const dazu = [korrekturen.length ? `${korrekturen.length === 1 ? 'Eine Berichtigung' : `${korrekturen.length} Berichtigungen`} aus dem Journal übernommen (${korrekturen[0].was}${korrekturen.length > 1 ? ' …' : ''}).` : null,
                      verdachtSatz(verdacht)].filter(Boolean).join(' ')
        // 22. Oktober: nichts Neues heisst nicht nichts zu sagen — Zeilen ohne Charge kommen sonst nie an.
        if (neue.length === 0) {
          const m = abgleichMeldung(0, [], b.probleme)
          if (lebt) setMeldung(dazu ? { art: verdacht.length ? 'warnung' : 'gut', text: `${m ? `${m.text} ` : ''}${dazu}` } : m)
          return
        }
        // Runde AS: eine Charge, die das Journal neu nennt, zuerst anlegen.
        const nrNeu = new Set(neue.map(z => z.charge_nr))
        const angelegt = await chargenAnlegen(b.neueChargen.filter(c => nrNeu.has(c.nr)))
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
        const m = abgleichMeldung(neue.length, angelegt ? b.neueChargen.filter(c => nrNeu.has(c.nr)).map(c => c.nr) : [], b.probleme)
        setMeldung(dazu && m ? { art: verdacht.length ? 'warnung' : m.art, text: `${m.text} ${dazu}` } : m)
      } catch (f) {
        // Was genau scheiterte, steht dabei — „Bad Request" allein half niemandem.
        const e = f as { status?: number; code?: string; details?: string } | null
        const dazu = [e?.status ? `HTTP ${e.status}` : '', e?.code ?? '', e?.details ?? ''].filter(Boolean).join(' · ')
        if (lebt) setMeldung({ art: 'warnung', text: `Erntejournal nicht abgeglichen: ${fehlerText(f)}${dazu ? ` (${dazu})` : ''}` })
      }
    })()
    return () => { lebt = false }
  }, [])

  if (!meldung) return null
  return (
    <Hinweis art={meldung.art}>
      {meldung.text} <Link to="/betrieb/stammdaten">Stammdaten</Link>
    </Hinweis>
  )
}
