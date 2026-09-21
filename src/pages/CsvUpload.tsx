import { useCallback, useEffect, useState } from 'react'
import { ZWarnung } from '../components/Zeichen'
import { supabase } from '../lib/supabase'
import { einstellung, fehlerText, stammdaten } from '../lib/db'
import { REINIGUNG_STANDARD, csvReinigen, deltaTrichter, histogrammAbziehen, masseKg,
         pruefsumme, trichter,
         type ReinigungsParameter, type Reinigungsergebnis } from '../lib/csv'
import { dateinamenLesen, type Dateiart } from '../lib/dateiname'
import { kg, lokalFuerInput, sortiertagText, tagAnfang, tagEnde, zahl,
         zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Marke } from '../components/Bausteine'
import { Wahl } from '../components/Schritte'
import type { Charge } from '../lib/typen'

/**
 * Sortier-CSV einlesen — zwei Arten, zwei Wege.
 *
 * **Lauf-Datei**: ein Sortierlauf, das Datum steht im Namen
 * (`1614_07_10_26`). Wie bisher: die Datei ist für sich genommen die ganze
 * Wahrheit über diesen einen Lauf.
 *
 * **Sammeldatei**: eine Datei je Charge, benannt nur nach der Charge
 * (`1614`), bei der die Maschine jedes Mal unten anhängt. Zwei Folgen, und
 * beide würden sonst still danebengehen:
 *  · Der zweite Upload enthält alles vom ersten noch einmal. Eingelesen
 *    wird deshalb nur das **Delta** — die Datenbank rechnet es (0082), hier
 *    steht die Vorschau, damit man vor dem Drücken sieht, was dazukommt.
 *  · Es gibt kein Sortierdatum. Also wird keines erfunden, sondern ein
 *    **Zeitraum** angegeben; woraus die App daraus den Sortiertag ableitet,
 *    sagt sie hinterher.
 *
 * Die Art schlägt der Dateiname vor. Überstimmen kann sie immer ein Mensch —
 * er weiss, woher die Datei kommt, der Name weiss es nur manchmal.
 */
interface Vorbereitet {
  datei: File
  ergebnis: Reinigungsergebnis
  chargeNr: number | null
  art: Dateiart
  /** Nur bei einer Lauf-Datei: der Zeitpunkt aus dem Namen. */
  zeit: Date | null
  ausDemNamen: boolean
  /** Nur bei einer Sammeldatei: der Zeitraum, als Datumsfelder. */
  von: string
  bis: string
  /** Wie viele Kürbisse dieser Charge schon als Sammeldatei eingelesen sind. */
  bekannt: number | null
  hinweis: string | null
  puffer: ArrayBuffer
  summe: string
  status: 'bereit' | 'laeuft' | 'fertig' | 'fehler'
  meldung?: string
  /** Was die Datenbank nach dem Einlesen gemeldet hat. */
  befund?: string
}

const alsFeld = (d: Date | null) => (d ? lokalFuerInput(d).slice(0, 10) : '')

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
      setParameter(await einstellung<ReinigungsParameter>('reinigung_standard', REINIGUNG_STANDARD))
    })()
  }, [])

  /**
   * Wie viele Kürbisse dieser Charge stehen schon aus Sammel-Lesungen in der
   * Datenbank? Gelesen wird die Summe, nicht das Histogramm: Für die
   * Vorschau genügt sie, und ein Histogramm mit tausend Stufen über die
   * Leitung zu ziehen, nur um eine Zahl zu zeigen, wäre Verschwendung. Die
   * massgebliche Rechnung macht ohnehin die Datenbank.
   */
  const bekanntHolen = useCallback(async (chargeNr: number): Promise<number | null> => {
    const { data, error } = await supabase.from('sortier_lauf')
      .select('n_gueltig').eq('charge_nr', chargeNr).eq('art', 'sammel')
    if (error) return null
    return (data ?? []).reduce((s, z) => s + ((z as { n_gueltig: number }).n_gueltig ?? 0), 0)
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
        const ergebnis = csvReinigen(new TextDecoder('utf-8').decode(puffer), parameter)
        const g = dateinamenLesen(datei.name, nummern, saison, datei.lastModified)
        neu.push({
          datei, ergebnis, puffer, chargeNr: g.chargeNr, art: g.art,
          zeit: g.zeit, ausDemNamen: g.quelle === 'dateiname',
          // Der Zeitstempel der Datei ist die obere Schranke: Später als da
          // kann nichts darin sortiert worden sein.
          von: '', bis: alsFeld(g.spaetestens),
          bekannt: g.art === 'sammel' && g.chargeNr ? await bekanntHolen(g.chargeNr) : null,
          hinweis: g.hinweis, summe: await pruefsumme(puffer), status: 'bereit',
        })
      }
    } catch (f) {
      setFehler(`Datei konnte nicht gelesen werden: ${fehlerText(f)}`)
      return
    }
    setDateien(d => [...d, ...neu])
  }

  function parameterAendern(neu: ReinigungsParameter) {
    setParameter(neu)
    setDateien(ds => ds.map(d => d.status === 'bereit'
      ? { ...d, ergebnis: csvReinigen(new TextDecoder('utf-8').decode(d.puffer), neu) }
      : d))
  }

  function aendern(i: number, teil: Partial<Vorbereitet>) {
    setDateien(ds => ds.map((d, j) => (j === i ? { ...d, ...teil } : d)))
  }

  /** Charge oder Art geändert: der bekannte Stand gilt je Charge. */
  async function chargeSetzen(i: number, chargeNr: number | null, art?: Dateiart) {
    const neueArt = art ?? dateien[i].art
    aendern(i, { chargeNr, art: neueArt, bekannt: null })
    if (chargeNr && neueArt === 'sammel') aendern(i, { bekannt: await bekanntHolen(chargeNr) })
  }

  async function hochladen(i: number) {
    const d = dateien[i]
    if (!d.chargeNr) { aendern(i, { status: 'fehler', meldung: 'Ohne Charge geht es nicht.' }); return }
    if (d.art === 'lauf' && !d.zeit) {
      aendern(i, { status: 'fehler', meldung: 'Eine Lauf-Datei braucht ihren Zeitpunkt — oder sie ist eine Sammeldatei.' })
      return
    }
    aendern(i, { status: 'laeuft', meldung: undefined, befund: undefined })
    try {
      // 1. Rohdatei unverändert ablegen — sie ist die eigentliche Quelle.
      const pfad = `${saison}/${d.chargeNr}/${d.summe.slice(0, 12)}-${d.datei.name}`
      const { error: sf } = await supabase.storage.from('rohdaten')
        .upload(pfad, d.datei, { upsert: false, contentType: 'text/plain' })
      if (sf && !`${sf.message}`.toLowerCase().includes('exists')) throw sf

      const gemeinsam = {
        p_charge_nr: d.chargeNr,
        p_datei_name: d.datei.name,
        p_roh_datei_ref: pfad,
        p_roh_pruefsumme: d.summe,
        p_reinigung: d.ergebnis.parameter,
        p_n_roh: d.ergebnis.n_roh,
        p_n_overflow: d.ergebnis.n_overflow,
        p_n_klein: d.ergebnis.n_klein,
        p_n_dubletten: d.ergebnis.n_dubletten,
        p_histogramm: d.ergebnis.histogramm,
      }

      if (d.art === 'sammel') {
        // Die Datenbank zieht ab, was sie schon hat, und weist die Datei ab,
        // wenn sie keine Erweiterung der vorigen Lesung ist.
        const { data, error } = await supabase.rpc('csv_sammel_speichern', {
          ...gemeinsam,
          p_von: tagAnfang(d.von)?.toISOString() ?? null,
          p_bis: tagEnde(d.bis)?.toISOString() ?? null,
        })
        if (error) throw error
        const a = data as Record<string, unknown>
        if (a.fehler) {
          aendern(i, { status: 'fehler', meldung: String(a.meldung ?? a.fehler) })
          return
        }
        aendern(i, {
          status: 'fertig',
          meldung: `${zahl(Number(a.n_neu))} Kürbisse neu eingelesen`
                 + (Number(a.n_bekannt) > 0 ? ` — ${zahl(Number(a.n_bekannt))} waren schon da.` : '.'),
          befund: `Sortiertag ${a.sortiertag ?? 'unbekannt'}`
                + ` — ${sortiertagText(a.sortiertag_quelle as string | null)}`
                + (Number(a.lauf_dateien) > 0
                   ? ` · Achtung: für diese Charge gibt es auch ${zahl(Number(a.lauf_dateien))} Lauf-Datei(en) — prüfe, ob sich Kürbisse überschneiden.`
                   : ''),
        })
        return
      }

      const { data, error } = await supabase.rpc('csv_lauf_speichern', {
        ...gemeinsam,
        p_datei_zeit: d.zeit?.toISOString() ?? null,
        p_datei_zeit_quelle: d.ausDemNamen ? 'dateiname' : 'manuell',
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
          ? 'Genau diese Datei wurde schon einmal hochgeladen.'
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
        {/* Der Browser-eigene Dateiknopf sieht in jedem Browser anders aus und
            passt in keinen. Ein Etikett im Knopf-Stil, das Feld selbst unsichtbar. */}
        <label className="knopf haupt">
          Dateien wählen …
          <input type="file" accept=".csv,text/csv,text/plain" multiple hidden
                 onChange={e => { void dateienWaehlen(e.target.files); e.target.value = '' }} />
        </label>
        <p className="leise" style={{ margin: '.6rem 0 0' }}>
          Mehrere Dateien auf einmal sind möglich; jede wird einzeln geprüft.
          Heisst eine Datei nur nach ihrer Charge (<code>1614</code>), gilt sie
          als Sammeldatei — dann wird nur eingelesen, was seit dem letzten Mal
          dazugekommen ist.
        </p>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      </Karte>

      {dateien.map((d, i) => {
        const bereit = d.status === 'bereit'
        // Vorschau des Deltas: Was in der Datei steht, abzüglich dessen, was
        // für diese Charge schon als Sammel-Lesung gespeichert ist.
        const vorschau = d.art === 'sammel' && d.bekannt !== null
          ? histogrammAbziehen(d.ergebnis.histogramm,
              // Nur die Summe ist bekannt, nicht das Histogramm — für die
              // Anzeige genügt eine einzige Stufe mit dieser Summe.
              d.bekannt > 0 ? [[0, d.bekannt]] : [])
          : null
        return (
          <Karte key={`${d.summe}-${i}`} titel={d.datei.name}
                 aktion={<Marke art={d.status === 'fertig' ? 'fertig' : d.status === 'fehler' ? 'warnung' : 'offen'}>
                   {{ bereit: 'bereit', laeuft: 'lädt …', fertig: 'eingelesen', fehler: 'Fehler' }[d.status]}
                 </Marke>}>
            <p className="trichter">{trichter(d.ergebnis)}</p>
            <p className="leise">
              {kg(masseKg(d.ergebnis.histogramm), 1)} gesamt ·
              {' '}{zahl(d.ergebnis.histogramm.length)} verschiedene Gewichte
              {d.ergebnis.n_unlesbar > 0 && <> · <span className="gelb"><ZWarnung size={14} /> {d.ergebnis.n_unlesbar} Zeilen unlesbar</span></>}
            </p>

            {d.hinweis && <Hinweis art="warnung">{d.hinweis}</Hinweis>}

            <div className="feld">
              <label>Was für eine Datei ist das?</label>
              <div className="wahl">
                <Wahl id={`art-lauf-${i}`} name="Ein Sortierlauf"
                      erkl="Das Datum steht im Namen — 1614_07_10_26"
                      gewaehlt={d.art === 'lauf'}
                      onClick={() => bereit && void chargeSetzen(i, d.chargeNr, 'lauf')} />
                <Wahl id={`art-sammel-${i}`} name="Sammeldatei der Charge"
                      erkl="Eine Datei je Charge, die Maschine hängt unten an — 1614"
                      gewaehlt={d.art === 'sammel'}
                      onClick={() => bereit && void chargeSetzen(i, d.chargeNr, 'sammel')} />
              </div>
            </div>

            <div className="feld">
              <label htmlFor={`charge-${i}`}>Charge</label>
              <select id={`charge-${i}`} value={d.chargeNr ?? ''} disabled={!bereit}
                      onChange={e => void chargeSetzen(i, e.target.value === '' ? null : Number(e.target.value))}>
                <option value="">— wählen —</option>
                {chargen.map(c => (
                  <option key={c.nr} value={c.nr}>{c.nr} — {c.schlag} · {c.sorte}</option>
                ))}
              </select>
            </div>

            {d.art === 'lauf' ? (
              <div className="feld">
                <label htmlFor={`zeit-${i}`}>Zeitpunkt des Laufs</label>
                <input id={`zeit-${i}`} type="datetime-local" disabled={!bereit}
                       value={d.zeit ? lokalFuerInput(d.zeit) : ''}
                       onChange={e => aendern(i, {
                         zeit: e.target.value ? new Date(e.target.value) : null,
                         ausDemNamen: false,
                       })} />
                <p className="hilfe">
                  {d.ausDemNamen ? 'Aus dem Dateinamen gelesen.'
                    : 'Steht nicht im Dateinamen — von Hand gesetzt.'}
                </p>
              </div>
            ) : (
              <>
                {vorschau && (
                  <Hinweis art={vorschau.n_neu > 0 ? 'gut' : 'warnung'}>
                    {deltaTrichter(vorschau)}
                    {vorschau.n_neu === 0 && ' — es gäbe nichts einzulesen.'}
                  </Hinweis>
                )}
                <div className="spalten">
                  <div className="feld">
                    <label htmlFor={`von-${i}`}>Sortiert frühestens am</label>
                    <input id={`von-${i}`} type="date" disabled={!bereit} value={d.von}
                           onChange={e => aendern(i, { von: e.target.value })} />
                  </div>
                  <div className="feld">
                    <label htmlFor={`bis-${i}`}>… spätestens am</label>
                    <input id={`bis-${i}`} type="date" disabled={!bereit} value={d.bis}
                           onChange={e => aendern(i, { bis: e.target.value })} />
                  </div>
                </div>
                <p className="hilfe">
                  Eine Sammeldatei trägt kein Datum. Leer gelassen, nimmt die App
                  den Zeitraum von der vorigen Lesung (sonst vom ersten Eingang
                  der Charge) bis zum Zeitstempel der Datei — und leitet den
                  Sortiertag daraus ab. Wer den Zeitraum enger kennt, trägt ihn
                  ein; dann ruht die Verdunstungsrechnung auf einer Angabe statt
                  auf einer Schätzung.
                </p>
              </>
            )}

            {d.meldung && (
              <Hinweis art={d.status === 'fehler' ? 'warnung' : 'gut'}>{d.meldung}</Hinweis>
            )}
            {d.befund && <p className="leise">{d.befund}</p>}

            {bereit && (
              <button className="haupt" style={{ width: '100%' }}
                      onClick={() => void hochladen(i)} disabled={!d.chargeNr}>
                Einlesen
              </button>
            )}
          </Karte>
        )
      })}

      <Letzte />
    </>
  )
}

function Letzte() {
  const [zeilen, setZeilen] = useState<{ id: number; datei_name: string; charge_nr: number
    art: string; n_gueltig: number; sortiertag: string | null; sortiertag_text: string
    zuordnung: string; gelesen_ts: string }[]>([])
  useEffect(() => {
    void supabase.from('v_sortier_lesung')
      .select('id, datei_name, charge_nr, art, n_gueltig, sortiertag, sortiertag_text, zuordnung, gelesen_ts')
      .order('gelesen_ts', { ascending: false }).limit(15)
      .then(({ data }) => setZeilen((data ?? []) as typeof zeilen))
  }, [])
  if (zeilen.length === 0) return null
  return (
    <Karte titel="Zuletzt eingelesen">
      <div className="rollbar">
        <table>
          <thead><tr><th>Datei</th><th>Charge</th><th>Art</th><th className="zahl">Kürbisse</th>
            <th>Sortiertag</th><th>Eingelesen</th></tr></thead>
          <tbody>
            {zeilen.map(z => (
              <tr key={z.id}>
                <td>{z.datei_name}</td>
                <td>{z.charge_nr}</td>
                <td>{z.art === 'sammel' ? 'Sammeldatei' : 'Lauf'}</td>
                <td className="zahl">{zahl(z.n_gueltig)}</td>
                <td>{z.sortiertag ?? '—'}<span className="leise"> · {z.sortiertag_text}</span></td>
                <td>{zeitpunkt(z.gelesen_ts)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="leise">
        Bei einer Sammeldatei ist „Kürbisse" das, was diese Lesung
        <strong> dazugebracht</strong> hat — nicht, was in der Datei steht.
      </p>
    </Karte>
  )
}
