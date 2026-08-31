import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { einstellung, fehlerText, stammdaten } from '../lib/db'
import { REINIGUNG_STANDARD, csvReinigen, masseKg, pruefsumme, trichter,
         type ReinigungsParameter, type Reinigungsergebnis } from '../lib/csv'
import { dateinamenLesen } from '../lib/dateiname'
import { kg, lokalFuerInput, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Marke } from '../components/Bausteine'
import type { Charge } from '../lib/typen'

interface Vorbereitet {
  datei: File
  ergebnis: Reinigungsergebnis
  chargeNr: number | null
  zeit: Date | null
  quelle: 'dateiname' | 'lastModified' | null
  hinweis: string | null
  puffer: ArrayBuffer
  summe: string
  status: 'bereit' | 'laeuft' | 'fertig' | 'fehler'
  meldung?: string
}

export default function CsvUpload() {
  const [chargen, setChargen] = useState<Charge[]>([])
  const [saison, setSaison] = useState(new Date().getFullYear())
  const [parameter, setParameter] = useState<ReinigungsParameter>(REINIGUNG_STANDARD)
  const [dateien, setDateien] = useState<Vorbereitet[]>([])
  const [fehler, setFehler] = useState<string | null>(null)

  useEffect(() => {
    void (async () => {
      const s = await stammdaten()
      setChargen(s.chargen)
      setSaison(await einstellung('saison_aktuell', new Date().getFullYear()))
      const gespeichert = await einstellung<ReinigungsParameter>('reinigung_standard', REINIGUNG_STANDARD)
      setParameter(gespeichert)
    })()
  }, [])

  async function dateienWaehlen(liste: FileList | null) {
    if (!liste) return
    if (chargen.length === 0) {
      setFehler('Die Chargenliste ist noch nicht geladen — einen Moment warten.')
      return
    }
    setFehler(null)
    const nummern = chargen.map(c => c.nr)
    const neu: Vorbereitet[] = []
    try {
    for (const datei of Array.from(liste)) {
      const puffer = await datei.arrayBuffer()
      const text = new TextDecoder('utf-8').decode(puffer)
      const ergebnis = csvReinigen(text, parameter)
      const gelesen = dateinamenLesen(datei.name, nummern, saison, datei.lastModified)
      neu.push({
        datei, ergebnis, puffer,
        chargeNr: gelesen.chargeNr, zeit: gelesen.zeit, quelle: gelesen.quelle,
        hinweis: gelesen.hinweis, summe: await pruefsumme(puffer), status: 'bereit',
      })
    }
    } catch (f) {
      setFehler(`Datei konnte nicht gelesen werden: ${fehlerText(f)}`)
      return
    }
    setDateien(d => [...d, ...neu])
  }

  /** Reinigung neu rechnen, wenn der Betriebsleiter an den Regeln dreht. */
  function parameterAendern(neu: ReinigungsParameter) {
    setParameter(neu)
    setDateien(ds => ds.map(d => d.status === 'bereit'
      ? { ...d, ergebnis: csvReinigen(new TextDecoder('utf-8').decode(d.puffer), neu) }
      : d))
  }

  function aendern(i: number, teil: Partial<Vorbereitet>) {
    setDateien(ds => ds.map((d, j) => (j === i ? { ...d, ...teil } : d)))
  }

  async function hochladen(i: number) {
    const d = dateien[i]
    if (!d.chargeNr) { aendern(i, { status: 'fehler', meldung: 'Ohne Charge geht es nicht.' }); return }
    aendern(i, { status: 'laeuft', meldung: undefined })
    try {
      // 1. Rohdatei unverändert ablegen — sie ist die eigentliche Quelle.
      const pfad = `${saison}/${d.chargeNr}/${d.summe.slice(0, 12)}-${d.datei.name}`
      const { error: sf } = await supabase.storage.from('rohdaten')
        .upload(pfad, d.datei, { upsert: false, contentType: 'text/plain' })
      // Liegt die Datei schon, ist das kein Fehler — die Prüfsumme entscheidet.
      if (sf && !`${sf.message}`.toLowerCase().includes('exists')) throw sf

      // 2. Gereinigtes Histogramm eintragen; klassiert und zugeordnet wird in der DB.
      const { data, error } = await supabase.rpc('csv_lauf_speichern', {
        p_charge_nr: d.chargeNr,
        p_datei_name: d.datei.name,
        p_roh_datei_ref: pfad,
        p_roh_pruefsumme: d.summe,
        p_datei_zeit: d.zeit?.toISOString() ?? null,
        p_datei_zeit_quelle: d.quelle,
        p_reinigung: d.ergebnis.parameter,
        p_n_roh: d.ergebnis.n_roh,
        p_n_overflow: d.ergebnis.n_overflow,
        p_n_klein: d.ergebnis.n_klein,
        p_n_dubletten: d.ergebnis.n_dubletten,
        p_histogramm: d.ergebnis.histogramm,
      })
      if (error) throw error

      const { data: lauf } = await supabase.from('sortier_lauf')
        .select('zuordnung, auftrag_id').eq('id', data as number).maybeSingle()
      aendern(i, {
        status: 'fertig',
        meldung: lauf?.zuordnung === 'auto'
          ? `Automatisch Auftrag ${lauf.auftrag_id} zugeordnet.`
          : 'Kein eindeutiger Auftrag — liegt jetzt in der Warteschlange.',
      })
    } catch (f) {
      const text = fehlerText(f)
      aendern(i, {
        status: 'fehler',
        meldung: text.includes('bereits') || `${text}`.includes('roh_pruefsumme')
          ? 'Diese Datei wurde schon einmal hochgeladen.'
          : text,
      })
    }
  }

  return (
    <>
      <h1>Sortier-CSV einlesen</h1>
      <p className="leise">
        Eine Zahl je Zeile, Gewicht in Gramm. Die Rohdatei wird unverändert
        gespeichert; gereinigt wird in einer eigenen Schicht, die hier sichtbar
        und umstellbar ist.
      </p>

      <Karte titel="Reinigungsregeln">
        <div className="spalten">
          <div className="feld">
            <label htmlFor="ov">Overflow ab (g)</label>
            <input id="ov" type="number" value={parameter.overflow_ab}
                   onChange={e => parameterAendern({ ...parameter, overflow_ab: Number(e.target.value) })} />
          </div>
          <div className="feld">
            <label htmlFor="mg">Mindestgewicht (g)</label>
            <input id="mg" type="number" value={parameter.min_gramm}
                   onChange={e => parameterAendern({ ...parameter, min_gramm: Number(e.target.value) })} />
          </div>
        </div>
        <label className="ankreuzen">
          <input type="checkbox" checked={parameter.dubletten_zusammenfassen}
                 onChange={e => parameterAendern({ ...parameter, dubletten_zusammenfassen: e.target.checked })} />
          Direkte Dubletten zusammenfassen (Doppel-Trigger der Maschine)
        </label>
      </Karte>

      <Karte titel="Dateien">
        <input type="file" accept=".csv,text/csv,text/plain" multiple
               onChange={e => { void dateienWaehlen(e.target.files); e.target.value = '' }} />
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      </Karte>

      {dateien.map((d, i) => (
        <Karte key={`${d.summe}-${i}`} titel={d.datei.name}
               aktion={<Marke art={d.status === 'fertig' ? 'fertig' : d.status === 'fehler' ? 'warnung' : 'offen'}>
                 {{ bereit: 'bereit', laeuft: 'lädt …', fertig: 'eingelesen', fehler: 'Fehler' }[d.status]}
               </Marke>}>
          <p className="trichter">{trichter(d.ergebnis)}</p>
          <p className="leise">
            {kg(masseKg(d.ergebnis.histogramm), 1)} gesamt ·
            {' '}{zahl(d.ergebnis.histogramm.length)} verschiedene Gewichte
            {d.ergebnis.n_unlesbar > 0 && ` · ⚠ ${d.ergebnis.n_unlesbar} Zeilen unlesbar`}
          </p>

          {d.hinweis && <Hinweis art="warnung">{d.hinweis}</Hinweis>}

          <div className="spalten">
            <div className="feld">
              <label>Charge</label>
              <select value={d.chargeNr ?? ''} disabled={d.status !== 'bereit'}
                      onChange={e => aendern(i, { chargeNr: e.target.value === '' ? null : Number(e.target.value) })}>
                <option value="">— wählen —</option>
                {chargen.map(c => (
                  <option key={c.nr} value={c.nr}>{c.nr} — {c.schlag} · {c.sorte}</option>
                ))}
              </select>
            </div>
            <div className="feld">
              <label>Zeitpunkt des Laufs</label>
              <input type="datetime-local" disabled={d.status !== 'bereit'}
                     value={d.zeit ? lokalFuerInput(d.zeit) : ''}
                     onChange={e => aendern(i, {
                       zeit: e.target.value ? new Date(e.target.value) : null,
                       quelle: 'manuell' as never,
                     })} />
            </div>
          </div>
          <p className="leise">
            Quelle des Zeitpunkts: {d.quelle === 'dateiname' ? 'Dateiname'
              : d.quelle === 'lastModified' ? 'Zeitstempel der Datei' : 'von Hand gesetzt'}
          </p>

          {d.meldung && (
            <Hinweis art={d.status === 'fehler' ? 'warnung' : 'gut'}>{d.meldung}</Hinweis>
          )}

          {d.status === 'bereit' && (
            <button className="haupt" style={{ width: '100%' }}
                    onClick={() => hochladen(i)} disabled={!d.chargeNr}>
              Einlesen
            </button>
          )}
        </Karte>
      ))}

      <Letzte />
    </>
  )
}

function Letzte() {
  const [zeilen, setZeilen] = useState<{ id: number; datei_name: string; charge_nr: number
    n_gueltig: number; zuordnung: string; gelesen_ts: string }[]>([])
  useEffect(() => {
    void supabase.from('sortier_lauf')
      .select('id, datei_name, charge_nr, n_gueltig, zuordnung, gelesen_ts')
      .order('gelesen_ts', { ascending: false }).limit(15)
      .then(({ data }) => setZeilen((data ?? []) as typeof zeilen))
  }, [])
  if (zeilen.length === 0) return null
  return (
    <Karte titel="Zuletzt eingelesen">
      <div className="rollbar">
        <table>
          <thead><tr><th>Datei</th><th>Charge</th><th className="zahl">Kürbisse</th>
            <th>Zuordnung</th><th>Eingelesen</th></tr></thead>
          <tbody>
            {zeilen.map(z => (
              <tr key={z.id}>
                <td>{z.datei_name}</td>
                <td>{z.charge_nr}</td>
                <td className="zahl">{zahl(z.n_gueltig)}</td>
                <td>{z.zuordnung}</td>
                <td>{zeitpunkt(z.gelesen_ts)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Karte>
  )
}
