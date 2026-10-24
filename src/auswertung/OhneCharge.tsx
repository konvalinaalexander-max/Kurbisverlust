/**
 * Lieferscheine ohne Charge, einzeln (0125). Der Betrieb, 24. Oktober: „bitte
 * weis mir in der App auch Lieferscheine ohne Charge aus — dass du mir das
 * auch anzeigst, ich kann draufklicken, und du zeigst mir die Zeile vom
 * Perigon."
 *
 * Oben je Grund, wie viele und wie viel, und was zu tun ist — die Wege sind
 * verschieden: eine unbekannte Nummer trägt man in den Stammdaten ein, eine
 * fehlende Menge in Perigon, eine inzwischen bekannte Nummer erledigt das
 * nächste Rechnen. Darunter jeder Lieferschein mit Datum, Artikel, Kunde,
 * Masse und dem Satz, warum er keine Charge hat; ein Klick öffnet das Fenster
 * mit der ganzen Perigon-Zeile, die Zellen, die nicht stimmen, rot umrandet.
 */
import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg, tonnen } from '../lib/format'
import { Hinweis, Lade } from '../components/Bausteine'
import { LieferungFenster } from '../betrieb/LieferungFenster'
import type { LieferungOhneCharge } from './daten'
import { OHNE_CHARGE_GRUND, ohneChargeUebersicht } from './ungereimt'

/** Nummern, die beim Grund etwas sagen (welche Nummer unbekannt ist, welche Charge ohne Menge). */
const MIT_NUMMER = new Set(['unbekannt', 'mehrdeutig', 'nachholen', 'menge_null', 'rest'])

export function OhneChargeListe({ sorte }: { sorte?: string | null }) {
  const [liste, setListe] = useState<LieferungOhneCharge[] | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const [offen, setOffen] = useState<number | null>(null)

  useEffect(() => {
    let lebt = true
    void (async () => {
      let q = supabase.from('v_lieferung_ohne_charge')
        .select('id, datum, sorte, kunde, kg, quelle, pos_id, artikel, nummer, grund, satz, tun')
        .order('datum', { ascending: false })
      if (sorte) q = q.eq('sorte', sorte)
      const r = await q
      if (!lebt) return
      if (r.error) { setFehler(fehlerText(r.error)); setListe([]) }
      else setListe((r.data ?? []) as LieferungOhneCharge[])
    })()
    return () => { lebt = false }
  }, [sorte])

  if (liste === null) return <Lade zeilen={2} />
  if (fehler) return <Hinweis art="warnung">Die Lieferscheine ohne Charge liessen sich nicht laden: {fehler}</Hinweis>
  if (liste.length === 0) return <p className="leise">Keine Lieferscheine ohne Charge{sorte ? ` bei ${sorte}` : ''}.</p>

  const gruppen = ohneChargeUebersicht(liste)
  const tunVon = new Map(liste.map(l => [l.grund, l.tun]))
  const mehrereSorten = new Set(liste.map(l => l.sorte)).size > 1
  return (
    <div className="ohne-charge">
      <ul className="ohne-charge-gruende">
        {gruppen.map(g => (
          <li key={g.grund}>
            <strong>{g.n} × {g.name}</strong>
            {MIT_NUMMER.has(g.grund) && g.nummern.length > 0 && <span> ({g.nummern.slice(0, 4).join(', ')}{g.nummern.length > 4 ? ' …' : ''})</span>}
            <span className="leise"> · {tonnen(g.kg)}</span>
            <span className="ohne-charge-tun"> — {tunVon.get(g.grund)}</span>
          </li>
        ))}
      </ul>
      <div className="rollbar">
        <table className="dicht umbruch ohne-charge-tabelle">
          <thead>
            <tr><th>Geliefert</th><th>Artikel</th><th>Kunde</th><th className="zahl">Masse</th><th>Warum ohne Charge</th></tr>
          </thead>
          <tbody>
            {liste.map(l => (
                <tr key={l.id} className="klickbar" onClick={() => setOffen(l.id)}
                    title={l.quelle ? 'die ganze Zeile der Perigon-Datei zeigen' : 'von Hand erfasst — die Lieferung zeigen'}>
                  <td className="nowrap">{datum(l.datum)}</td>
                  <td>{l.artikel ?? <span className="leise">{l.quelle ? 'Perigon' : 'von Hand'}</span>}
                    {(mehrereSorten || !l.artikel) && l.sorte && <span className="zelle-unter">{l.sorte}</span>}</td>
                  <td>{l.kunde ?? <span className="leise">—</span>}</td>
                  <td className="zahl">{kg(l.kg, 0)}</td>
                  <td><strong>{OHNE_CHARGE_GRUND[l.grund] ?? l.grund}</strong><span className="zelle-unter ohne-charge-satz">{l.satz}</span></td>
                </tr>
            ))}
          </tbody>
        </table>
      </div>
      {offen !== null && <LieferungFenster lieferungId={offen} schliessen={() => setOffen(null)} />}
    </div>
  )
}
