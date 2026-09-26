import { Fragment, useCallback, useEffect, useState } from 'react'
import Sicherung from '../components/Sicherung'
import { TaetZeichen, ZHaken, ZKreuz, ZMikrofon, ZNeu, ZSprechblase } from '../components/Zeichen'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { tempoJeTaetigkeit } from '../auswertung/tempo'
import type { Durchsatz } from '../auswertung/daten'
import { WOERTERBUCH } from '../lib/i18n'
import { datum, kg, tagVon, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Lade, Leer, Marke, Segmente } from '../components/Bausteine'
import Lieferungen from './Lieferungen'
import CsvUpload from './CsvUpload'
import Warteschlange from './Warteschlange'
import Stammdaten from './Stammdaten'
import Zugang from './Zugang'
import type { Auftrag, Charge, Rueckmeldung } from '../lib/typen'

type Teil = 'arbeiten' | 'lieferungen' | 'csv' | 'warteschlange' | 'stammdaten' | 'zugang'
const TEILE: [Teil, string, string][] = [
  ['arbeiten', 'Arbeiten', 'Was heute läuft und was fertig ist — jede Arbeit lässt sich öffnen.'],
  ['lieferungen', 'Warenausgang', 'Was den Betrieb verlässt — die Gegenprobe zur Hochrechnung.'],
  ['csv', 'Sortier-CSV', 'Die Dateien der Sortiermaschine einlesen.'],
  ['warteschlange', 'Warteschlange', 'Sortier-CSVs, die noch keiner Arbeit zugeordnet sind.'],
  ['stammdaten', 'Stammdaten', 'Gebinde und Tara, Chargen, Sortierschemata, Benutzer, Einstellungen.'],
  ['zugang', 'Zugang', 'Der QR-Code für die Halle.'],
]

/** Betrieb: Was ist heute los, und wie pflege ich die Grundlagen? */
export default function Betrieb() {
  const { teil } = useParams()
  const navigate = useNavigate()
  const aktiv = (TEILE.find(([t]) => t === teil)?.[0] ?? 'arbeiten') as Teil
  const zweck = TEILE.find(([t]) => t === aktiv)?.[2]
  return (
    <>
      <div className="seitenkopf">
        <div><h1>Betrieb</h1><p className="zweck">{zweck}</p></div>
      </div>
      <nav className="navleiste unter" aria-label="Betrieb">
        {TEILE.map(([t, name]) => (
          <a key={t} href={`/betrieb/${t}`} className={aktiv === t ? 'aktiv' : ''}
             onClick={e => { e.preventDefault(); navigate(`/betrieb/${t}`) }}>{name}</a>
        ))}
      </nav>
      <div className="wechsel" key={aktiv}>
        {aktiv === 'arbeiten' && <Arbeiten />}
        {aktiv === 'lieferungen' && <Lieferungen />}
        {aktiv === 'csv' && <CsvUpload />}
        {aktiv === 'warteschlange' && <Warteschlange />}
        {aktiv === 'stammdaten' && <Stammdaten />}
        {aktiv === 'zugang' && <Zugang />}
      </div>
    </>
  )
}

const TAGE_ZUERST = 14

/**
 * Die Arbeiten — nach Tag gruppiert, die neuesten oben. Zuerst die letzten
 * zwei Wochen; „ältere zeigen" holt die nächsten. Kein Bildschirm mit
 * dreihundert Zeilen mehr.
 */
function Arbeiten() {
  const [auftraege, setAuftraege] = useState<Auftrag[]>([])
  const [chargen, setChargen] = useState<Charge[]>([])
  const [durchsatz, setDurchsatz] = useState<Map<number, Durchsatz>>(new Map())
  const [filter, setFilter] = useState<'alle' | 'offen' | 'fertig' | 'abgebrochen'>('alle')
  const [tage, setTage] = useState(TAGE_ZUERST)
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  /** 0085: die Rückmeldungen je Arbeit, und wer sie gegeben hat. */
  const [rueckmeldungen, setRueckmeldungen] = useState<Map<number, Rueckmeldung[]>>(new Map())
  const [namen, setNamen] = useState<Map<string, string>>(new Map())
  const [offen, setOffen] = useState<Set<number>>(new Set())
  /** Signierte Adressen der Aufnahmen — der Bucket ist nicht öffentlich. */
  const [tonUrl, setTonUrl] = useState<Map<number, string>>(new Map())
  /** Runde Z (0094): die Kurzfassung, die der Betriebsleiter selbst macht —
   *  etwa nach dem Anhören einer Aufnahme. Erst damit steht der Kommentar
   *  im Dashboard. */
  const [kurzEntwurf, setKurzEntwurf] = useState<Map<number, string>>(new Map())
  const [kuerzt, setKuerzt] = useState<Set<number>>(new Set())
  /** Runde W: der Löschmodus — Kreise an den Zeilen, dann ein Knopf. */
  const [loeschmodus, setLoeschmodus] = useState(false)
  const [gewaehlt, setGewaehlt] = useState<Set<number>>(new Set())
  const [frage, setFrage] = useState(false)
  const [loescht, setLoescht] = useState(false)
  const [geloescht, setGeloescht] = useState<string | null>(null)
  const laden = useCallback(async () => {
    void (async () => {
      try {
        const [{ chargen }, a, d, r, pr] = await Promise.all([
          stammdaten(),
          supabase.from('auftrag').select('*').order('start_ts', { ascending: false }).limit(400),
          supabase.from('erg_durchsatz').select('*'),
          supabase.from('auftrag_rueckmeldung').select('*').order('ts', { ascending: false }).limit(1000),
          supabase.from('profil').select('id, name'),
        ])
        if (a.error) throw a.error
        setChargen(chargen); setAuftraege((a.data ?? []) as Auftrag[])
        setDurchsatz(new Map(((d.data ?? []) as Durchsatz[]).map(x => [x.auftrag_id, x])))
        const m = new Map<number, Rueckmeldung[]>()
        for (const x of (r.data ?? []) as Rueckmeldung[]) m.set(x.auftrag_id, [...(m.get(x.auftrag_id) ?? []), x])
        setRueckmeldungen(m)
        setNamen(new Map(((pr.data ?? []) as { id: string; name: string | null }[]).map(x => [x.id, x.name ?? ''])))
      } catch (f) { setFehler(fehlerText(f)) } finally { setLaedt(false) }
    })()
  }, [])
  useEffect(() => { void laden() }, [laden])

  function umschaltenWahl(id: number) {
    setGewaehlt(g => { const n = new Set(g); if (n.has(id)) n.delete(id); else n.add(id); return n })
  }
  function loeschmodusAus() { setLoeschmodus(false); setGewaehlt(new Set()); setFrage(false) }

  /** Endgültig löschen — je Arbeit die Funktion aus 0013, die auch die
   *  Wägungen mitnimmt, die sonst verwaist zurückblieben. Das Journal (0072)
   *  behält jede gelöschte Zeile. Danach rechnen die Ergebnisse neu. */
  async function loeschen() {
    if (loescht || gewaehlt.size === 0) return
    setLoescht(true); setFehler(null)
    const fehlgeschlagen: string[] = []
    for (const id of gewaehlt) {
      const { error } = await supabase.rpc('auftrag_endgueltig_loeschen', { p_auftrag_id: id })
      if (error) fehlgeschlagen.push(`Arbeit ${id}: ${fehlerText(error)}`)
    }
    const n = gewaehlt.size - fehlgeschlagen.length
    if (fehlgeschlagen.length) setFehler(fehlgeschlagen.join(' · '))
    loeschmodusAus()
    setLaedt(true); await laden()
    const { error: e2 } = await supabase.rpc('auswertung_aktualisieren')
    setLoescht(false)
    setGeloescht(`${n === 1 ? '1 Arbeit' : `${n} Arbeiten`} endgültig gelöscht — das Journal behält eine Spur.${e2 ? ' Die Ergebnisse konnten nicht neu gerechnet werden: auf dem Dashboard „Neu rechnen".' : ' Die Ergebnisse sind neu gerechnet.'}`)
  }

  /** Eine Rückmeldung auf- oder zuklappen; beim Öffnen die Aufnahme
   *  signieren lassen — eine Stunde reicht zum Anhören. */
  async function umschalten(auftragId: number) {
    const neu = new Set(offen)
    if (neu.has(auftragId)) { neu.delete(auftragId); setOffen(neu); return }
    neu.add(auftragId); setOffen(neu)
    for (const r of rueckmeldungen.get(auftragId) ?? []) {
      if (!r.audio_ref || tonUrl.has(r.id)) continue
      const { data } = await supabase.storage.from('rueckmeldungen').createSignedUrl(r.audio_ref, 3600)
      if (data?.signedUrl) setTonUrl(u => new Map(u).set(r.id, data.signedUrl))
    }
  }
  /** Kürzen oder zurücknehmen — die Zeilenregel lässt nur den Betriebsleiter. */
  async function kuerzen(r: Rueckmeldung, kurz: string | null) {
    if (kuerzt.has(r.id)) return
    setKuerzt(k => new Set(k).add(r.id)); setFehler(null)
    const neu = kurz === null
      ? { kurz: null, kurz_quelle: null, kurz_ts: null, kurz_charge_nr: null }
      : { kurz, kurz_quelle: 'betriebsleiter' as const, kurz_ts: new Date().toISOString() }
    const { error } = await supabase.from('auftrag_rueckmeldung').update(neu).eq('id', r.id)
    setKuerzt(k => { const n = new Set(k); n.delete(r.id); return n })
    if (error) { setFehler(fehlerText(error)); return }
    setRueckmeldungen(m => {
      const n = new Map(m)
      n.set(r.auftrag_id, (n.get(r.auftrag_id) ?? []).map(x => x.id === r.id ? { ...x, ...neu } : x))
      return n
    })
    setKurzEntwurf(e => { const n = new Map(e); n.delete(r.id); return n })
  }
  const t = (id: keyof typeof WOERTERBUCH.de) => WOERTERBUCH.de[id]
  const gezeigt = auftraege.filter(a => filter === 'alle' ? true
    : filter === 'abgebrochen' ? a.abgebrochen_ts !== null
    : a.abgebrochen_ts === null && a.status === (filter === 'offen' ? 'offen' : 'abgeschlossen'))
  const tempo = tempoJeTaetigkeit([...durchsatz.values()])
  if (laedt) return <Lade />

  // Nach Tag gruppieren; die ältesten Tage bleiben zu, bis man sie will.
  const gruppen = new Map<string, Auftrag[]>()
  for (const a of gezeigt) { const tag = tagVon(new Date(a.start_ts)); gruppen.set(tag, [...(gruppen.get(tag) ?? []), a]) }
  const alleTage = [...gruppen.keys()].sort().reverse()
  const sichtbareTage = alleTage.slice(0, tage)
  const heute = tagVon(new Date())
  const gestern = tagVon(new Date(Date.now() - 86400000))
  const tagName = (tag: string) => tag === heute ? 'Heute' : tag === gestern ? 'Gestern' : new Date(tag + 'T00:00:00').toLocaleDateString('de-CH', { weekday: 'long', day: '2-digit', month: '2-digit' })

  return (
    <>
    <Sicherung />
    {tempo.length > 0 && (
      <Karte titel="Arbeit und Tempo" unter="Je Tätigkeit: wie viele Arbeiten, wie lange sie dauerten, wie viel Masse je Stunde durchging.">
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Tätigkeit</th><th className="zahl">Arbeiten</th><th className="zahl">Stunden</th><th className="zahl">Dauer (Median)</th><th className="zahl">Bewegte Masse</th><th className="zahl">kg je Stunde</th><th className="zahl">kg je Person und Stunde</th></tr></thead>
          <tbody>{tempo.map(z => (
            <tr key={z.name}>
              <td><TaetZeichen id={z.id} /> {z.name}</td>
              <td className="zahl">{z.n}</td>
              <td className="zahl">{z.stunden.toFixed(1)} h</td>
              <td className="zahl">{z.median.toFixed(1)} h</td>
              <td className="zahl">{z.masse > 0 ? kg(z.masse, 0) : <span className="leise">—</span>}</td>
              <td className="zahl">{z.kgProH !== null ? <strong>{zahl(z.kgProH)}</strong> : <span className="leise">—</span>}</td>
              <td className="zahl">{z.kgProPersonH !== null ? zahl(z.kgProPersonH) : <span className="leise">—</span>}</td>
            </tr>
          ))}</tbody>
        </table></div>
        <p className="fussnote">Aus Start und Ende jeder abgeschlossenen Arbeit und der Masse, die sie bewegt hat. Arbeiten ohne bekannte Masse zählen bei der Dauer, nicht beim Tempo.</p>
      </Karte>
    )}
    <Karte titel="Arbeiten" unter={`${gezeigt.length} Arbeiten an ${alleTage.length} Tagen — die neuesten zuerst.`}
           aktion={loeschmodus
             ? <button type="button" className="werkzeug-knopf" onClick={loeschmodusAus}>Abbrechen</button>
             : <>
                 <button type="button" id="arbeiten-loeschen" className="werkzeug-knopf" onClick={() => { setLoeschmodus(true); setGeloescht(null) }}><ZKreuz size={14} />Löschen</button>
                 <Link to="/neu" className="knopf haupt klein"><ZNeu size={15} />Neue Arbeit starten</Link>
               </>}>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {geloescht && <Hinweis art="info">{geloescht}</Hinweis>}
      {loeschmodus && (
        <div className="loesch-leiste" role="status">
          <span>Arbeiten zum Löschen anklicken —</span>
          <strong>{gewaehlt.size === 1 ? '1 ausgewählt' : `${gewaehlt.size} ausgewählt`}</strong>
          <button type="button" id="arbeiten-loeschen-weiter" className="knopf klein gefahr" disabled={gewaehlt.size === 0} onClick={() => setFrage(true)}>Löschen …</button>
          <button type="button" className="werkzeug-knopf" onClick={loeschmodusAus}>Abbrechen</button>
        </div>
      )}
      {frage && (
        <div className="dialog-hinter" onClick={() => setFrage(false)}>
          <div className="dialog" role="dialog" aria-modal="true" aria-label="Arbeiten löschen" onClick={e => e.stopPropagation()}>
            <h2 style={{ marginTop: 0 }}>{gewaehlt.size === 1 ? 'Diese Arbeit endgültig löschen?' : `Diese ${gewaehlt.size} Arbeiten endgültig löschen?`}</h2>
            <ul className="liste-schlicht">
              {auftraege.filter(a => gewaehlt.has(a.id)).map(a => {
                const ta = taetigkeitVon(a.weg, a.station, a.ist_fax)
                return <li key={a.id}>{datum(a.start_ts)} · {ta ? t(ta.text) : ''} · {chargeText(chargen.find(c => c.nr === a.charge_nr))} · {a.abgebrochen_ts ? 'abgebrochen' : a.status === 'offen' ? 'läuft' : 'fertig'}</li>
              })}
            </ul>
            <Hinweis art="warnung">Mit der Arbeit gehen alle ihre Messungen: Palox-Ablesungen, zu klein / zu gross, gezählte Paletten, Wägungen, fertige Paletten, Angaben und Rückmeldungen. Zugeordnete Sortierdateien gehen zurück in die Warteschlange. Das Journal behält jede gelöschte Zeile.</Hinweis>
            <div className="knopf-reihe" style={{ marginTop: 'var(--a-3)' }}>
              <button type="button" id="arbeiten-loeschen-ja" className="knopf gefahr" disabled={loescht} onClick={() => void loeschen()}>
                {loescht ? 'Löscht …' : gewaehlt.size === 1 ? 'Ja, endgültig löschen' : `Ja, ${gewaehlt.size} Arbeiten endgültig löschen`}
              </button>
              <button type="button" className="knopf" disabled={loescht} onClick={() => setFrage(false)}>Abbrechen</button>
            </div>
          </div>
        </div>
      )}
      <div className="filterleiste">
        <Segmente wahl={filter} setzen={setFilter} teile={[['alle', 'alle'], ['offen', 'läuft'], ['fertig', 'fertig'], ['abgebrochen', 'abgebrochen']]} />
      </div>
      {gezeigt.length === 0 ? <Leer titel="Nichts hier">Für diesen Filter gibt es keine Arbeit.</Leer> : (
        <>
          {sichtbareTage.map(tag => (
            <div key={tag}>
              <div className="tag-trenner">{tagName(tag)} <span className="leise">· {gruppen.get(tag)!.length} Arbeiten</span></div>
              <div className="rollbar"><table className="dicht">
                <thead><tr>{loeschmodus && <th></th>}<th>Start</th><th>Arbeit</th><th>Charge</th><th>Status</th><th className="zahl">Paletten</th><th className="zahl">Bewegte Masse</th><th className="zahl">Dauer</th><th className="zahl">kg/h</th><th className="zahl">Leute</th><th>Rückmeldung</th><th></th></tr></thead>
                <tbody>{gruppen.get(tag)!.map(a => {
                  const ta = taetigkeitVon(a.weg, a.station, a.ist_fax); const d = durchsatz.get(a.id)
                  const rm = rueckmeldungen.get(a.id) ?? []
                  const hatText = rm.some(r => r.text), hatTon = rm.some(r => r.audio_ref)
                  return (
                    <Fragment key={a.id}>
                    <tr className={loeschmodus && gewaehlt.has(a.id) ? 'gewaehlt' : undefined}>
                      {loeschmodus && (
                        <td>
                          <button type="button" role="checkbox" aria-checked={gewaehlt.has(a.id)} aria-label={`Arbeit ${a.id} zum Löschen wählen`}
                                  className={`wahlkreis${gewaehlt.has(a.id) ? ' an' : ''}`} onClick={() => umschaltenWahl(a.id)}>
                            {gewaehlt.has(a.id) && <ZHaken size={14} />}
                          </button>
                        </td>
                      )}
                      <td className="nowrap">{new Date(a.start_ts).toLocaleTimeString('de-CH', { hour: '2-digit', minute: '2-digit' })}</td>
                      <td className="nowrap"><TaetZeichen id={ta?.id} /> {ta ? t(ta.text) : ''}</td>
                      <td>{chargeText(chargen.find(c => c.nr === a.charge_nr))}</td>
                      <td>{a.abgebrochen_ts ? <Marke art="warnung">abgebrochen</Marke> : a.status === 'offen' ? <Marke art="offen">läuft</Marke> : <Marke art="fertig">fertig</Marke>}</td>
                      <td className="zahl">{d ? zahl(d.n_paletten) : ''}</td>
                      <td className="zahl">{d?.masse_kg != null ? kg(d.masse_kg, 0) : ''}</td>
                      <td className="zahl">{d ? `${d.dauer_h.toFixed(1)} h` : ''}</td>
                      <td className="zahl">{d?.kg_pro_h != null ? zahl(d.kg_pro_h) : ''}</td>
                      <td className="zahl">{d ? d.n_teilnehmer : ''}</td>
                      <td className="nowrap">{rm.length > 0 && (
                        // 0085: Die Zeichen sagen, was da ist — Text, Ton oder beides.
                        <button type="button" className="klein" onClick={() => void umschalten(a.id)}
                                aria-expanded={offen.has(a.id)} aria-label={`Rückmeldung ${offen.has(a.id) ? 'schliessen' : 'öffnen'}`}>
                          {hatText && <ZSprechblase size={15} />}{hatTon && <ZMikrofon size={15} />}
                          {' '}{offen.has(a.id) ? 'schliessen' : rm.length > 1 ? `${rm.length} lesen` : hatTon && !hatText ? 'anhören' : 'lesen'}
                        </button>
                      )}</td>
                      <td className="rechts-buendig"><Link to={`/arbeit/${a.id}`}>öffnen</Link></td>
                    </tr>
                    {offen.has(a.id) && rm.map(r => (
                      <tr key={`r${r.id}`} className="rueckmeldung-zeile">
                        <td colSpan={loeschmodus ? 12 : 11}>
                          <div className="leise" style={{ marginBottom: '.3rem' }}>
                            {namen.get(r.erfasser) || 'jemand'} · {zeitpunkt(r.ts)}
                            {r.audio_sekunden != null && <> · {Math.floor(r.audio_sekunden / 60)}:{String(r.audio_sekunden % 60).padStart(2, '0')} Aufnahme</>}
                          </div>
                          <div className="leise" style={{ marginBottom: '.2rem' }}><strong>{r.art === 'ware' ? 'Zur Ware' : 'Zur App'}</strong></div>
                          {r.text && <p className="rueckmeldung-text">{r.text}</p>}
                          {r.transkript && <p className="rueckmeldung-text leise">mitgeschrieben{r.transkript_quelle === 'hand' ? ', geprüft' : ' (ungeprüft)'}: „{r.transkript}"</p>}
                          {r.audio_ref && (tonUrl.has(r.id)
                            ? <audio controls src={tonUrl.get(r.id)} style={{ width: '100%', maxWidth: 480 }} />
                            : <span className="leise">Aufnahme wird geholt …</span>)}
                          {r.art === 'ware' && (
                            // 0094: erst gelesen, dann gezeigt — die Kurzfassung ist, was das
                            // Dashboard an die Messungen hängt. Leer heisst: noch nirgends.
                            <div className="kurz-block" data-stand={r.kurz ? 'gekuerzt' : 'offen'}>
                              {r.kurz
                                ? <p className="rueckmeldung-kurz"><strong>Im Dashboard:</strong> {r.kurz} <span className="leise">· gekürzt {r.kurz_quelle === 'betriebsleiter' ? 'von dir' : 'von der Runde am Programm'}{r.kurz_ts ? `, ${datum(r.kurz_ts)}` : ''}{r.kurz_charge_nr != null ? ` · zugeordnet zu Charge ${r.kurz_charge_nr}` : ''}</span></p>
                                : <p className="rueckmeldung-kurz"><Marke art="warnung" punkt={false}>noch nicht gelesen</Marke> <span className="leise">Steht noch nicht im Dashboard. Auf das Wesentliche kürzen — „Hagelschaden" — dann steht es an den Messungen dieser Arbeit.</span></p>}
                              <form className="knopf-reihe" style={{ alignItems: 'center' }}
                                    onSubmit={e => { e.preventDefault(); const k = (kurzEntwurf.get(r.id) ?? '').trim(); if (k) void kuerzen(r, k) }}>
                                <input id={`kurz-${r.id}`} type="text" maxLength={120} placeholder={r.kurz ? 'anders kürzen' : 'Kurzfassung fürs Dashboard'}
                                       value={kurzEntwurf.get(r.id) ?? ''} onChange={e => setKurzEntwurf(m => new Map(m).set(r.id, e.target.value))}
                                       style={{ flex: '1 1 220px', minHeight: 36 }} aria-label="Kurzfassung fürs Dashboard" />
                                <button type="submit" id={`kurz-speichern-${r.id}`} className="klein haupt" disabled={kuerzt.has(r.id) || !(kurzEntwurf.get(r.id) ?? '').trim()}>
                                  {r.kurz ? 'ändern' : 'ins Dashboard'}
                                </button>
                                {r.kurz && <button type="button" id={`kurz-weg-${r.id}`} className="klein" disabled={kuerzt.has(r.id)} onClick={() => void kuerzen(r, null)}>zurücknehmen</button>}
                              </form>
                            </div>
                          )}
                        </td>
                      </tr>
                    ))}
                    </Fragment>
                  )
                })}</tbody>
              </table></div>
            </div>
          ))}
          {alleTage.length > sichtbareTage.length && (
            <div className="mitte" style={{ marginTop: '1rem' }}>
              <button type="button" onClick={() => setTage(n => n + TAGE_ZUERST)}>Ältere zeigen <span className="leise">· {alleTage.length - sichtbareTage.length} Tage, bis {datum(alleTage[alleTage.length - 1])}</span></button>
            </div>
          )}
        </>
      )}
    </Karte>
    </>
  )
}
