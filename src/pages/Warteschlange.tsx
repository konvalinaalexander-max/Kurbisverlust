import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { STATION_NAME, WEG_NAME, sortiertagText, tagAnfang, tagEnde, zahl,
         zeitpunkt } from '../lib/format'
import { Aufklapp, Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import type { Auftrag, Charge, SortierLauf } from '../lib/typen'

/**
 * Sortier-Lesungen, die keiner Arbeit zugeordnet werden konnten (Spec §5).
 *
 * Hier liegen nur **Lauf-Dateien** — eine Sammeldatei gehört zu keiner
 * einzelnen Arbeit und wird deshalb gar nicht erst danach gefragt (0082).
 *
 * Es gibt zwei Gründe, warum eine Datei hier landet, und sie verlangen
 * Verschiedenes:
 *
 *  · Die Datei ist wirklich ein Sortierlauf, aber die passende Arbeit ist
 *    nicht eindeutig — dann wird sie unten von Hand zugeordnet.
 *
 *  · Die Datei ist in Wahrheit eine **Sammeldatei** und wurde nur als Lauf
 *    eingelesen, weil das vor 0082 die einzige Art war. Dann stimmt ihr
 *    Zeitpunkt nicht: Er stammt vom Zeitstempel der Datei, also vom letzten
 *    Anhängen, und ist kein Sortierdatum. Statt sie zu löschen und neu
 *    hochzuladen, wird sie umgedeutet — die Masse bleibt, die Deutung ändert
 *    sich. Der Zeitstempel geht dabei nicht verloren, er wird zur oberen
 *    Schranke des Zeitfensters.
 *
 * Woran man den zweiten Fall erkennt, steht in der Lesung selbst: Wenn der
 * Zeitpunkt nicht aus dem Dateinamen kam, hat ihn niemand gemessen.
 */
export default function Warteschlange() {
  const [laeufe, setLaeufe] = useState<SortierLauf[]>([])
  const [auftraege, setAuftraege] = useState<Auftrag[]>([])
  const [chargen, setChargen] = useState<Charge[]>([])
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  /** Was beim Umdeuten herauskam — die Karte selbst verschwindet dabei. */
  const [befunde, setBefunde] = useState<{ art: 'gut' | 'warnung'; text: string }[]>([])
  /** Das Zeitfenster je Lesung, solange es nur im Formular steht. */
  const [fenster, setFenster] = useState<Record<number, { von: string; bis: string }>>({})
  const [laeuft, setLaeuft] = useState<number | null>(null)

  const laden = useCallback(async () => {
    setLaedt(true)
    try {
      const [s, l, a] = await Promise.all([
        stammdaten(),
        supabase.from('sortier_lauf').select('*')
          .in('zuordnung', ['offen', 'mehrdeutig']).eq('art', 'lauf')
          .order('datei_zeit', { ascending: false }),
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

  /**
   * Aus einer als Lauf eingelesenen Datei eine Sammel-Lesung machen. Die
   * Datenbank zieht dabei ab, was frühere Sammel-Lesungen derselben Charge
   * schon tragen, und weist die Lesung zurück, wenn sie keine Fortsetzung
   * sein kann — eine Datei, der Gewichtsstufen fehlen, ist nicht dieselbe,
   * gewachsene Datei.
   */
  async function alsSammel(l: SortierLauf) {
    // Dieselbe Vorbelegung wie im Formular. Stünde hier ein anderer
    // Rückfallwert, schickte der Knopf etwas anderes ab, als im Feld steht.
    const f = fenster[l.id] ?? vorbelegt(l)
    setLaeuft(l.id)
    try {
      const { data, error } = await supabase.rpc('lesung_als_sammel', {
        p_lauf_id: l.id,
        p_von: tagAnfang(f.von)?.toISOString() ?? null,
        p_bis: tagEnde(f.bis)?.toISOString() ?? null,
      })
      if (error) throw error
      const a = (data ?? {}) as Record<string, unknown>
      if (a.fehler) {
        const stufen = Array.isArray(a.negativ) ? (a.negativ as [number, number][]) : []
        setBefunde(b => [{
          art: 'warnung',
          text: `${l.datei_name}: ${String(a.meldung ?? a.fehler)}`
              + (stufen.length
                 ? ` Es fehlen ${stufen.length} Gewichtsstufe(n), z. B. `
                   + stufen.slice(0, 3).map(([g, n]) => `${n}× ${g} g`).join(', ')
                   + '. Das ist keine gewachsene Datei — bitte die Herkunft prüfen.'
                 : ''),
        }, ...b])
        return
      }
      setBefunde(b => [{
        art: 'gut',
        text: `${l.datei_name} gilt jetzt als Sammeldatei: ${zahl(Number(a.n_gueltig))} Kürbisse`
            + ` · Sortiertag ${a.sortiertag ?? 'unbekannt'}`
            + ` — ${sortiertagText(a.sortiertag_quelle as string | null)}`
            + ` · Zeitraum ${kurz(a.von)} bis ${kurz(a.bis)}`,
      }, ...b])
      await laden()
    } catch (f2) {
      setFehler(fehlerText(f2))
    } finally { setLaeuft(null) }
  }

  if (laedt) return <Lade />

  return (
    <>
      <h1>Nicht zugeordnete CSVs</h1>
      <p className="leise">
        Automatisch zugeordnet wird nur, was eindeutig ist. Was hier liegt,
        gehört entweder zu einer Arbeit, die sich nicht von selbst finden
        liess — oder es ist gar kein einzelner Lauf, sondern die Sammeldatei
        einer Charge.
      </p>

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {befunde.map((b, i) => <Hinweis key={i} art={b.art}>{b.text}</Hinweis>)}

      {laeufe.length === 0 && (
        <Hinweis art="gut">Alles zugeordnet — hier liegt nichts.</Hinweis>
      )}

      {laeufe.map(l => {
        const passende = auftraege.filter(a => a.charge_nr === l.charge_nr && a.station === 'sortieren')
        const abstand = (a: Auftrag) => l.datei_zeit
          ? Math.abs(new Date(a.start_ts).getTime() - new Date(l.datei_zeit).getTime()) / 3600000
          : null
        // Kam der Zeitpunkt nicht aus dem Dateinamen, hat ihn niemand
        // gemessen — dann ist der Verdacht „Sammeldatei" nicht abwegig.
        const geraten = l.datei_zeit_quelle !== 'dateiname'
        const f = fenster[l.id] ?? vorbelegt(l)
        const setzen = (teil: Partial<{ von: string; bis: string }>) =>
          setFenster(s => ({ ...s, [l.id]: { ...f, ...teil } }))
        return (
          <Karte key={l.id} titel={l.datei_name}
                 aktion={<Marke art="warnung">{l.zuordnung === 'mehrdeutig' ? 'mehrdeutig' : 'kein Treffer'}</Marke>}>
            <p className="leise">
              {chargeText(chargen.find(c => c.nr === l.charge_nr))} ·
              {' '}{zahl(l.n_gueltig)} Kürbisse · Dateizeit {zeitpunkt(l.datei_zeit)}
              {l.datei_zeit_quelle && ` (${l.datei_zeit_quelle})`}
            </p>

            {geraten && (
              <Hinweis art="warnung">
                Der Zeitpunkt steht nicht im Dateinamen — er stammt vom
                Zeitstempel der Datei. Das ist der Moment des letzten
                Speicherns, nicht der des Sortierens. Heisst die Datei nur
                nach ihrer Charge, ist sie eine Sammeldatei; dann unten
                umdeuten statt zuordnen.
              </Hinweis>
            )}

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

            <Aufklapp titel="Das ist gar kein einzelner Lauf — das ist die Sammeldatei der Charge"
                      offen={geraten}>
              <p className="hilfe">
                Die Maschine hängt bei jedem Sortieren unten an dieselbe Datei
                an. Eine solche Datei trägt kein Sortierdatum, dafür alles
                bisher Sortierte dieser Charge. Umgedeutet behält sie ihre
                Kürbisse — sie bekommt statt eines erfundenen Zeitpunkts einen
                Zeitraum, und daraus wird der Sortiertag abgeleitet. Lädst Du
                die gewachsene Datei später nochmals hoch, zählt nur, was
                dazugekommen ist.
              </p>
              <div className="spalten">
                <div className="feld">
                  <label htmlFor={`von-${l.id}`}>Sortiert frühestens am</label>
                  <input id={`von-${l.id}`} type="date" value={f.von}
                         onChange={e => setzen({ von: e.target.value })} />
                </div>
                <div className="feld">
                  <label htmlFor={`bis-${l.id}`}>… spätestens am</label>
                  <input id={`bis-${l.id}`} type="date" value={f.bis}
                         onChange={e => setzen({ bis: e.target.value })} />
                </div>
              </div>
              <p className="hilfe">
                Leer gelassen, nimmt die App den Zeitraum vom Eingang der
                Charge (oder von der vorigen Sammel-Lesung) bis zum Zeitstempel
                der Datei. Wer enger weiss, wann sortiert wurde, trägt es ein —
                dann ruht die Verdunstungsrechnung auf einer Angabe statt auf
                einer Schätzung.
              </p>
              <button onClick={() => void alsSammel(l)} disabled={laeuft === l.id}>
                {laeuft === l.id ? 'wird umgedeutet …' : 'Als Sammeldatei umdeuten'}
              </button>
            </Aufklapp>

            <div className="reihe" style={{ marginTop: '.75rem' }}>
              <button onClick={() => nochmalSuchen(l.id)}>Automatik nochmal laufen lassen</button>
            </div>
          </Karte>
        )
      })}
    </>
  )
}

/** Ein Zeitstempel aus der Datenbank als blosses Datum — im Befund genügt der Tag. */
function kurz(wert: unknown): string {
  if (typeof wert !== 'string' || !wert) return 'unbekannt'
  return zeitpunkt(wert).slice(0, 10)
}

/**
 * Das Zeitfenster, solange niemand es angefasst hat: offen nach unten (die
 * Datenbank nimmt dann die vorige Lesung oder den Eingang der Charge), nach
 * oben der Zeitstempel der Datei — später kann nichts sortiert worden sein.
 */
const vorbelegt = (l: SortierLauf) => ({ von: '', bis: alsFeld(l.datei_zeit) })

/** Ein Zeitstempel als Vorbelegung für ein <input type="date">. */
function alsFeld(wert: string | null): string {
  if (!wert) return ''
  const d = new Date(wert)
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}
