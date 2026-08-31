import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { STATION_NAME, WEG_NAME, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import type { Auftrag, Charge, SortierLauf } from '../lib/typen'

/**
 * Nicht zugeordnete CSVs (Spec §5). Automatisch zugeordnet wird nur, was
 * eindeutig ist — alles andere landet hier und wird von Hand entschieden.
 */
export default function Warteschlange() {
  const [laeufe, setLaeufe] = useState<SortierLauf[]>([])
  const [auftraege, setAuftraege] = useState<Auftrag[]>([])
  const [chargen, setChargen] = useState<Charge[]>([])
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    setLaedt(true)
    try {
      const [s, l, a] = await Promise.all([
        stammdaten(),
        supabase.from('sortier_lauf').select('*')
          .in('zuordnung', ['offen', 'mehrdeutig']).order('datei_zeit', { ascending: false }),
        supabase.from('auftrag').select('*')
          .eq('weg', 'maschine').order('start_ts', { ascending: false }).limit(200),
      ])
      if (l.error) throw l.error
      setChargen(s.chargen)
      setLaeufe((l.data ?? []) as SortierLauf[])
      setAuftraege((a.data ?? []) as Auftrag[])
      setFehler(null)
    } catch (f) {
      setFehler(fehlerText(f))
    } finally { setLaedt(false) }
  }, [])
  useEffect(() => { void laden() }, [laden])

  async function zuordnen(laufId: number, auftragId: number | null) {
    const { error } = await supabase.rpc('auftrag_manuell_zuordnen',
      { p_lauf_id: laufId, p_auftrag_id: auftragId })
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  async function nochmalSuchen(laufId: number) {
    const { error } = await supabase.rpc('auftrag_zuordnen', { p_lauf_id: laufId })
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  if (laedt) return <Lade />

  return (
    <>
      <h1>Nicht zugeordnete CSVs</h1>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      {laeufe.length === 0 && (
        <Hinweis art="gut">Alles zugeordnet — hier liegt nichts.</Hinweis>
      )}

      {laeufe.map(l => {
        const passende = auftraege.filter(a => a.charge_nr === l.charge_nr && a.station === 'sortieren')
        const abstand = (a: Auftrag) => l.datei_zeit
          ? Math.abs(new Date(a.start_ts).getTime() - new Date(l.datei_zeit).getTime()) / 3600000
          : null
        return (
          <Karte key={l.id} titel={l.datei_name}
                 aktion={<Marke art="warnung">{l.zuordnung === 'mehrdeutig' ? 'mehrdeutig' : 'kein Treffer'}</Marke>}>
            <p className="leise">
              {chargeText(chargen.find(c => c.nr === l.charge_nr))} ·
              {' '}{zahl(l.n_gueltig)} Kürbisse · Dateizeit {zeitpunkt(l.datei_zeit)}
              {l.datei_zeit_quelle && ` (${l.datei_zeit_quelle})`}
            </p>

            {passende.length === 0 ? (
              <Hinweis art="warnung">
                Für diese Charge gibt es keinen Sortier-Auftrag. Entweder wurde er nie
                eröffnet, oder die Charge im Dateinamen stimmt nicht.
              </Hinweis>
            ) : (
              <div className="rollbar">
                <table>
                  <thead><tr><th>Auftrag</th><th>Start</th><th className="zahl">Abstand</th><th /></tr></thead>
                  <tbody>
                    {passende.slice(0, 8).map(a => (
                      <tr key={a.id}>
                        <td>#{a.id} · {WEG_NAME[a.weg]} · {STATION_NAME[a.station]}</td>
                        <td>{zeitpunkt(a.start_ts)}</td>
                        <td className="zahl">
                          {abstand(a) === null ? '—' : `${abstand(a)!.toFixed(1)} h`}
                        </td>
                        <td style={{ textAlign: 'right' }}>
                          <button className="klein" onClick={() => zuordnen(l.id, a.id)}>
                            zuordnen
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            <div className="reihe" style={{ marginTop: '.75rem' }}>
              <button onClick={() => nochmalSuchen(l.id)}>Automatik nochmal laufen lassen</button>
            </div>
          </Karte>
        )
      })}
    </>
  )
}
