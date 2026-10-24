/**
 * Runde BE: die Belege einer Sache je Charge in Perigon. Der Betrieb, 24.
 * Oktober: „du zeigst mir genau an, wie die Excel-Zeile aussieht und wie ich
 * sie im Excel wiederfinde … damit ich mit dieser Zeile zu meinem Chef gehen
 * kann — das musst du dir für all diese Fälle überlegen."
 *
 * Bei einem Perigon-Fall ist der Beleg eine Position. Bei einer Sache je Charge
 * („mehr verkauft als möglich", „verkauft, nie eingegangen", „vor dem
 * Eingang") sind es die Lieferscheine, die Perigon unter dieser Nummer führt:
 * je Lieferschein Datum, Kunde, Artikel, Kilo, die Position (AufPosId, blau wie
 * im Fenster) und, wo bekannt, die Excel-Zeile. Ein Klick zeigt die Zeile wie im Excel.
 *
 * Runde BF: geladen wird einmal (useBelege) — der Fall braucht dieselben
 * Lieferscheine für die Zeitleiste und für die Tabelle; eine lange Liste zeigt
 * zuerst die ersten zehn.
 */
import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg } from '../lib/format'
import { excelZeileVon, type RohZeile } from '../lib/warenausgang'
import { Hinweis, Lade } from '../components/Bausteine'
import { ZChevron } from '../components/Zeichen'
import { LieferungFenster } from '../betrieb/LieferungFenster'

export interface Beleg {
  id: number; datum: string; charge_nr: number | null; kg: number; kunde: string | null
  quelle: string | null; pos_id: number | null; excel: number | null; artikel: string | null; datei: string | null
  /** die Nummer in Spalte W, wie Perigon sie schreibt */
  nummer: string | null
}

/** Firma, Position, Charge und Lauf aus der Kennung einer Lieferung („Firma:Position:Charge:Lauf"). */
function kennungAus(externId: string | null | undefined) {
  const m = /^([^:]+):(\d+)(?::([^:]*):(\d+))?/.exec(externId ?? '')
  return m ? { quelle: m[1], posId: Number(m[2]), charge: m[3] ?? null, lauf: m[4] ? Number(m[4]) : 1 } : null
}

/** Die Lieferscheine unter diesen Chargen — oder mit diesen Nummern in Spalte W, auch die ohne Charge. */
export function useBelege(chargen: number[] = [], nummern: string[] = []): { belege: Beleg[] | null; fehler: string | null } {
  const [belege, setBelege] = useState<Beleg[] | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const schluessel = `${chargen.join(',')}|${nummern.join(',')}`
  const nachNummer = nummern.length > 0

  useEffect(() => {
    let lebt = true
    setBelege(null); setFehler(null)
    void (async () => {
      try {
        type L = { id: number; datum: string; charge_nr: number | null; kg: number; kunde: string | null }
        type I = { lieferung_id: number; extern_id: string }
        let liste: L[]
        let importe: I[]
        if (nachNummer) {
          // die Kennung einer Lieferung trägt die Nummer, wie Perigon sie schreibt: Firma:Position:Nummer:Lauf
          const je = await Promise.all(nummern.map(nr => supabase.from('lieferung_import').select('lieferung_id, extern_id').like('extern_id', `%:${nr}:%`)))
          for (const x of je) if (x.error) throw x.error
          importe = je.flatMap(x => (x.data ?? []) as I[]).filter(x => nummern.includes(kennungAus(x.extern_id)?.charge ?? ''))
          const ids = [...new Set(importe.map(x => x.lieferung_id))]
          const l = ids.length ? await supabase.from('lieferung').select('id, datum, charge_nr, kg, kunde').in('id', ids).order('datum') : { data: [], error: null }
          if (l.error) throw l.error
          liste = (l.data ?? []) as L[]
        } else {
          const l = chargen.length ? await supabase.from('lieferung').select('id, datum, charge_nr, kg, kunde').in('charge_nr', chargen).order('datum') : { data: [], error: null }
          if (l.error) throw l.error
          liste = (l.data ?? []) as L[]
          const ids = liste.map(x => x.id)
          const imp = ids.length ? await supabase.from('lieferung_import').select('lieferung_id, extern_id').in('lieferung_id', ids) : { data: [], error: null }
          if (imp.error) throw imp.error
          importe = (imp.data ?? []) as I[]
        }
        const kennung = new Map(importe.map(x => [x.lieferung_id, kennungAus(x.extern_id)]))
        const posIds = [...new Set([...kennung.values()].map(k => k?.posId).filter((x): x is number => x != null))]
        const pos = posIds.length
          ? await supabase.from('ausgang_position').select('quelle, pos_id, artikel, roh').in('pos_id', posIds)
          : { data: [], error: null }
        if (pos.error) throw pos.error
        const posVon = new Map(((pos.data ?? []) as { quelle: string; pos_id: number; artikel: string; roh: RohZeile[] | null }[])
          .map(p => [`${p.quelle}:${p.pos_id}`, p]))
        if (!lebt) return
        setBelege(liste.map(x => {
          const k = kennung.get(x.id) ?? null
          const p = k ? posVon.get(`${k.quelle}:${k.posId}`) : undefined
          const datei = p?.roh?.map(r => r['#datei']).find((d): d is string => typeof d === 'string') ?? null
          return { ...x, quelle: k?.quelle ?? null, pos_id: k?.posId ?? null, artikel: p?.artikel ?? null, datei, nummer: k?.charge ?? null,
                   excel: k ? excelZeileVon(p?.roh, k.charge, k.lauf) : null }
        }))
      } catch (f) { if (lebt) { setFehler(fehlerText(f)); setBelege([]) } }
    })()
    return () => { lebt = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [schluessel])
  return { belege, fehler }
}

export function PerigonBelege({ chargen = [], nummern = [], vorEingang }: {
  /** die Lieferscheine dieser Chargen */
  chargen?: number[]
  /** oder: die Lieferscheine, auf denen Perigon diese Nummern schreibt (Spalte W) — auch die ohne Charge */
  nummern?: string[]
  /** bei „vor dem Eingang": der Tag der ersten Palette — früher Geliefertes ist markiert */
  vorEingang?: string | null
}) {
  const { belege, fehler } = useBelege(chargen, nummern)
  return <BelegeTabelle belege={belege} fehler={fehler} unter={(nummern.length ? nummern : chargen).join(', ')} nachNummer={nummern.length > 0} vorEingang={vorEingang} />
}

/** Wie viele Lieferscheine zuerst stehen — der Rest auf Knopfdruck. */
const ZUERST = 10

export function BelegeTabelle({ belege, fehler, unter, nachNummer = false, vorEingang, titel }: {
  belege: Beleg[] | null; fehler: string | null
  /** die Chargen oder Nummern, um die es geht — für den Titel */
  unter: string
  nachNummer?: boolean
  vorEingang?: string | null
  /** Runde BF: im Fall heisst der Block anders */
  titel?: string
}) {
  const [offen, setOffen] = useState<number | null>(null)
  const [alle, setAlle] = useState(false)
  if (belege === null) return <Lade zeilen={2} />
  if (fehler) return <Hinweis art="warnung">Die Lieferscheine liessen sich nicht laden: {fehler}</Hinweis>
  if (belege.length === 0) return <p className="leise">Perigon führt unter {unter} keinen Lieferschein.</p>
  const summe = belege.reduce((a, b) => a + Number(b.kg), 0)
  const mitExcel = belege.some(b => b.excel != null)
  const dateien = [...new Set(belege.map(b => b.datei).filter(Boolean))]
  // „vor dem Eingang": die frühen zuerst sichtbar, sie sind der Fall
  const reihe = vorEingang ? [...belege].sort((a, b) => Number(b.datum < vorEingang) - Number(a.datum < vorEingang) || a.datum.localeCompare(b.datum)) : belege
  const sichtbar = alle ? reihe : reihe.slice(0, ZUERST)
  return (
    <section className="fall-block belege" id="sache-belege">
      <h3>{titel ?? 'Die Belege in Perigon'} <span className="leise">— {belege.length} {belege.length === 1 ? 'Lieferschein' : 'Lieferscheine'} {nachNummer ? 'mit der Nummer' : 'unter'} {unter}, zusammen {kg(summe, 0)}</span></h3>
      <p className="leise oben-0">So findest du jeden im Excel{dateien.length === 1 ? <> (<strong>{dateien[0]}</strong>)</> : null}: <kbd>Ctrl</kbd>+<kbd>F</kbd> und die
        Position (AufPosId, Spalte AD){mitExcel ? ', oder direkt die Excel-Zeile' : ''}. Ein Klick zeigt die Zeile wie im Excel.</p>
      <div className="rollbar">
        <table className="dicht fall-tabelle beleg-tabelle ohne-haftkopf">
          <thead><tr><th>Geliefert</th><th>Kunde</th><th>Artikel</th>{nachNummer && <th>Nummer</th>}<th className="zahl">Masse <span className="zelle-unter">der Lieferung</span></th><th>Position</th>{mitExcel && <th>Excel-Zeile</th>}<th aria-label="öffnen" /></tr></thead>
          <tbody>{sichtbar.map(b => {
            const vor = vorEingang != null && b.datum < vorEingang
            return (
              <tr key={b.id} className={`klickbar${vor ? ' beleg-vor' : ''}`} tabIndex={0} onClick={() => setOffen(b.id)}
                  onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setOffen(b.id) } }} title="die Zeile wie im Excel zeigen">
                <td className="nowrap" data-titel="Geliefert">{datum(b.datum)}{vor && <span className="zelle-unter beleg-vor-marke">vor dem Eingang</span>}</td>
                <td data-titel="Kunde">{b.kunde ?? <span className="leise">—</span>}</td>
                <td data-titel="Artikel">{b.artikel ?? <span className="leise">—</span>}</td>
                {nachNummer && <td data-titel="Nummer">{b.nummer}{b.charge_nr != null ? <span className="zelle-unter leise">die App zählt sie bei {b.charge_nr}</span> : <span className="zelle-unter leise">bei keiner Charge</span>}</td>}
                <td className="zahl" data-titel="Masse der Lieferung">{kg(b.kg, 0)}</td>
                <td data-titel="Position">{b.pos_id != null ? <code className="kennung-wert">{b.pos_id}</code> : <span className="leise">von Hand</span>}</td>
                {mitExcel && <td data-titel="Excel-Zeile">{b.excel ?? <span className="leise">—</span>}</td>}
                <td className="zeile-pfeil" aria-hidden="true"><ZChevron size={14} /></td>
              </tr>
            )
          })}</tbody>
        </table>
      </div>
      {reihe.length > ZUERST && (
        <button type="button" className="klein belege-alle" onClick={() => setAlle(a => !a)} aria-expanded={alle}>
          {alle ? `nur die ersten ${ZUERST}` : `alle ${belege.length} Lieferscheine zeigen`}</button>
      )}
      {offen !== null && <LieferungFenster lieferungId={offen} schliessen={() => setOffen(null)} />}
    </section>
  )
}
