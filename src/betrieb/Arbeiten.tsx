import { Fragment, useCallback, useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import Sicherung from '../components/Sicherung'
import { TaetZeichen, ZAuswahl, ZHaken, ZKreuz, ZMikrofon, ZNeu, ZPapierkorb, ZSprechblase } from '../components/Zeichen'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import type { Durchsatz } from '../auswertung/daten'
import { WOERTERBUCH } from '../lib/i18n'
import { datum, kg, tagVon, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Lade, Leer, Marke, Segmente } from '../components/Bausteine'
import type { Auftrag, Charge, Rueckmeldung } from '../lib/typen'

/*
 * Runde AO (12. Oktober): Die Arbeiten stehen unter Messungen, als erster
 * Reiter — „mega wichtig, dass man einen Überblick hat". Bis Runde AN
 * standen sie unter Betrieb, mit der Karte „Arbeit und Tempo" darüber; die
 * ist weg („nicht wichtig, komplett weglassen").
 */

const TAGE_ZUERST = 14

/** Runde AQ: die Dauer lesbar — „0.0 h" stand bei jeder Arbeit, die in Minuten erfasst war. */
export function dauerText(h: number): string {
  const min = Math.round(h * 60)
  if (min < 1) return '< 1 min'
  if (min < 60) return `${min} min`
  return h < 10 ? `${h.toFixed(1)} h` : `${Math.round(h)} h`
}

/**
 * Die Arbeiten — nach Tag gruppiert, die neuesten oben. Zuerst die letzten
 * zwei Wochen; „ältere zeigen" holt die nächsten. Kein Bildschirm mit
 * dreihundert Zeilen mehr.
 */
export default function Arbeiten() {
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
   *  behält jede gelöschte Zeile. Neu gerechnet wird nicht (0107): heute
   *  Nacht oder auf „Neu rechnen" — nie mehr die volle Rechnung aus dem Browser. */
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
    setLoescht(false)
    setGeloescht(`${n === 1 ? '1 Arbeit' : `${n} Arbeiten`} endgültig gelöscht — das Journal behält eine Spur. Die Ergebnisse zählen sie ab der nächsten Rechnung nicht mehr: heute Nacht oder mit „Neu rechnen" auf dem Dashboard.`)
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
    {/* Runde AQ: die Arbeiten zuoberst — „mega wichtig, dass man einen Überblick hat"; die Sicherung steht darunter. */}
    <Karte titel="Arbeiten" unter={`${gezeigt.length} Arbeiten an ${alleTage.length} Tagen`}
           aktion={loeschmodus
             ? <button type="button" id="arbeiten-loeschen-aus" className="symbolknopf an" aria-label="Auswahl beenden" title="Auswahl beenden" onClick={loeschmodusAus}><ZKreuz size={18} /></button>
             : <>
                 {/* Runde AD: ein Symbol statt „x Löschen" — der Modus heisst Auswählen, das Löschen kommt erst mit der Rückfrage. */}
                 <button type="button" id="arbeiten-loeschen" className="symbolknopf" aria-label="Arbeiten auswählen" title="Arbeiten auswählen — zum Löschen" onClick={() => { setLoeschmodus(true); setGeloescht(null) }}><ZAuswahl size={20} /></button>
                 <Link to="/neu" className="knopf haupt klein"><ZNeu size={15} />Neue Arbeit starten</Link>
               </>}>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {geloescht && <Hinweis art="info">{geloescht}</Hinweis>}
      {loeschmodus && (
        <div className="loesch-leiste" role="status">
          <span>Antippen, was gelöscht werden soll —</span>
          <strong>{gewaehlt.size === 1 ? '1 ausgewählt' : `${gewaehlt.size} ausgewählt`}</strong>
          <button type="button" id="arbeiten-loeschen-weiter" className="knopf klein gefahr" disabled={gewaehlt.size === 0} onClick={() => setFrage(true)}><ZPapierkorb size={16} />Löschen …</button>
        </div>
      )}
      {frage && createPortal(
        /* Runde AF: als Portal an <body> — die Seite kommt mit einer Eintritts-Bewegung
           (transform), und ein bewegter Vorfahr macht aus „fixed" ein „absolute": der
           Dialog rutschte ans Ende der Seite, man musste scrollen. */
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
                <ZPapierkorb size={16} />{loescht ? 'Löscht …' : gewaehlt.size === 1 ? 'Ja, endgültig löschen' : `Ja, ${gewaehlt.size} Arbeiten endgültig löschen`}
              </button>
              <button type="button" className="knopf" disabled={loescht} onClick={() => setFrage(false)}>Abbrechen</button>
            </div>
          </div>
        </div>
      , document.body)}
      <div className="filterleiste">
        <Segmente wahl={filter} setzen={setFilter} teile={[['alle', 'alle'], ['offen', 'läuft'], ['fertig', 'fertig'], ['abgebrochen', 'abgebrochen']]} />
      </div>
      {gezeigt.length === 0 ? <Leer titel="Nichts hier">Für diesen Filter gibt es keine Arbeit.</Leer> : (
        <>
          {sichtbareTage.map(tag => (
            <div key={tag}>
              <div className="tag-trenner">{tagName(tag)} <span className="leise">· {gruppen.get(tag)!.length} Arbeiten</span></div>
              {/* Runde AQ: feste Spaltenbreiten — die Tabellen der Tage stehen genau untereinander. Ohne kg/h: „Arbeit und Tempo … komplett weglassen". */}
              <div className="rollbar"><table className="dicht arbeiten-tabelle">
                <colgroup>{loeschmodus && <col className="sp-wahl" />}<col className="sp-start" /><col className="sp-arbeit" /><col /><col className="sp-status" /><col className="sp-zahl" /><col className="sp-masse" /><col className="sp-zahl" /><col className="sp-leute" /><col className="sp-rueck" /><col className="sp-oeffnen" /></colgroup>
                <thead><tr>{loeschmodus && <th></th>}<th>Start</th><th>Arbeit</th><th>Charge</th><th>Status</th><th className="zahl">Paletten</th><th className="zahl">Bewegte Masse</th><th className="zahl">Dauer</th><th className="zahl">Leute</th><th>Rückmeldung</th><th></th></tr></thead>
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
                      <td className="zahl">{d && d.n_paletten > 0 ? zahl(d.n_paletten) : <span className="leise">—</span>}</td>
                      <td className="zahl">{d?.masse_kg != null ? kg(d.masse_kg, 0) : ''}</td>
                      <td className="zahl">{d ? dauerText(d.dauer_h) : ''}</td>
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
                        <td colSpan={loeschmodus ? 11 : 10}>
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
    <Sicherung />
    </>
  )
}
