import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { chargeText, fehlerText } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { WOERTERBUCH } from '../lib/i18n'
import { datum, zeitpunkt } from '../lib/format'
import { Hinweis, Lade, Marke } from '../components/Bausteine'
import { TaetZeichen, ZKreuz } from '../components/Zeichen'
import { arbeitLaden, uhrzeit, type ArbeitDaten } from '../arbeit/daten'
import type { Rueckmeldung } from '../lib/typen'

interface Wiegung {
  id: number; wiege_ts: string; eingangsdatum: string; brutto_damals_kg: number; brutto_jetzt_kg: number
  kisten: number | null; gebindeart: string | null; sichtbar_schimmel: boolean; gemessen: boolean; kuerbisse_pro_kiste: number | null
}
interface Ausgang {
  id: number; ts: string; brutto_kg: number; kisten: number; gebindeart: string | null
  kuerbisse_pro_kiste: number | null; kaliber_idx: number | null; voll: boolean
}

/**
 * Die Arbeit hinter einer Zahl — als Fenster über der Seite (Runde W).
 *
 * Der Betrieb: „wenn ich den Punkt selber anklicke … dass dann die Arbeit
 * geöffnet wird, als Pop-up. Ich bleibe noch auf der Seite … und ich kann
 * alle Zahlen nachschauen dort drin." Also alles, was die Arbeit erfasst
 * hat, zum Lesen; berichtigt wird auf der Arbeitsseite (Korrektur).
 */
export function ArbeitFenster({ auftragId, schliessen }: { auftragId: number; schliessen: () => void }) {
  const [d, setD] = useState<ArbeitDaten | null>(null)
  const [wiegungen, setWiegungen] = useState<Wiegung[]>([])
  const [ausgang, setAusgang] = useState<Ausgang[]>([])
  const [rueck, setRueck] = useState<Rueckmeldung[]>([])
  const [fehler, setFehler] = useState<string | null>(null)
  const t = (id: keyof typeof WOERTERBUCH.de) => WOERTERBUCH.de[id]

  useEffect(() => {
    let lebt = true
    void (async () => {
      try {
        const [a, w, g, r] = await Promise.all([
          arbeitLaden(auftragId),
          supabase.from('verdunstung_wiegung').select('id, wiege_ts, eingangsdatum, brutto_damals_kg, brutto_jetzt_kg, kisten, gebindeart, sichtbar_schimmel, gemessen, kuerbisse_pro_kiste')
            .eq('auftrag_id', auftragId).order('wiege_ts'),
          supabase.from('ausgang_wiegung').select('id, ts, brutto_kg, kisten, gebindeart, kuerbisse_pro_kiste, kaliber_idx, voll')
            .eq('auftrag_id', auftragId).order('ts'),
          supabase.from('auftrag_rueckmeldung').select('*').eq('auftrag_id', auftragId).order('ts'),
        ])
        if (!lebt) return
        if (!a) { setFehler('Diese Arbeit gibt es nicht mehr.'); return }
        if (w.error) throw w.error
        if (g.error) throw g.error
        setD(a); setWiegungen((w.data ?? []) as Wiegung[]); setAusgang((g.data ?? []) as Ausgang[]); setRueck((r.data ?? []) as Rueckmeldung[])
      } catch (f) { if (lebt) setFehler(fehlerText(f)) }
    })()
    return () => { lebt = false }
  }, [auftragId])

  // Escape schliesst; der Hintergrund auch.
  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape') schliessen() }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [schliessen])

  const a = d?.auftrag
  const ta = a ? taetigkeitVon(a.weg, a.station, a.ist_fax) : null
  const gebietsschema = 'de-CH'

  return (
    <div className="dialog-hinter" onClick={schliessen}>
      <div className="dialog breit" role="dialog" aria-modal="true" aria-label="Arbeit" id="arbeit-fenster" onClick={e => e.stopPropagation()}>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {!d && !fehler && <Lade />}
        {d && a && (
          <>
            <div className="fenster-kopf">
              <TaetZeichen id={ta?.id} />
              <div>
                <h2>{ta ? t(ta.text) : 'Arbeit'} <span className="leise">· {chargeText(d.charge)}</span></h2>
                <p className="leise" style={{ margin: '.2rem 0 0' }}>
                  {zeitpunkt(a.start_ts)}{a.ende_ts ? ` – ${uhrzeit(a.ende_ts, gebietsschema)}` : ''}
                  {' · '}{a.abgebrochen_ts ? <Marke art="warnung">abgebrochen</Marke> : a.status === 'offen' ? <Marke art="offen">läuft</Marke> : <Marke art="fertig">fertig</Marke>}
                  {' · '}{d.teilnehmer.length ? d.teilnehmer.map(x => x.name).join(', ') : 'niemand eingetragen'}
                </p>
              </div>
              <button type="button" className="klein schliessen" onClick={schliessen} aria-label="schliessen"><ZKreuz size={16} /></button>
            </div>

            {d.ablesungen.length > 0 && (
              <section className="fenster-abschnitt">
                <h3>Palox</h3>
                <table className="dicht">
                  <thead><tr><th>Zeit</th><th className="zahl">Stand (kg brutto)</th><th className="zahl">Faules (kg)</th><th></th></tr></thead>
                  <tbody>{d.ablesungen.map(z => (
                    <tr key={z.id}>
                      <td>{uhrzeit(z.ts, gebietsschema)}</td>
                      <td className="zahl">{z.palox_stand_kg ?? (z.brutto_kg != null ? `${z.brutto_kg} (${z.kisten} × ${z.gebindeart})` : '—')}</td>
                      <td className="zahl">{z.kg}</td>
                      <td className="leise">{z.palox_nach_leeren ? 'nach dem Leeren — neuer Anfang' : z.bemerkung ?? ''}</td>
                    </tr>
                  ))}</tbody>
                </table>
              </section>
            )}

            {d.paletten.length > 0 && (
              <section className="fenster-abschnitt">
                <h3>Gezählte Paletten · {d.paletten.length}</h3>
                <table className="dicht">
                  <thead><tr><th>Eingangsdatum</th><th className="zahl">Zettel (kg brutto)</th><th>Sortierdatum</th><th className="zahl">Kisten</th><th>Gebinde</th><th>Gewogen</th></tr></thead>
                  <tbody>{d.paletten.map(p => (
                    <tr key={p.id}>
                      <td>{p.eingangsdatum ? datum(p.eingangsdatum) : '—'}</td>
                      <td className="zahl">{p.brutto_zettel_kg ?? '—'}</td>
                      <td>{p.sortierdatum ? datum(p.sortierdatum) : '—'}</td>
                      <td className="zahl">{p.kisten ?? '—'}</td>
                      <td>{p.gebindeart ?? ''}</td>
                      <td>{p.wiegung_id != null ? 'ja' : ''}</td>
                    </tr>
                  ))}</tbody>
                </table>
              </section>
            )}

            {wiegungen.length > 0 && (
              <section className="fenster-abschnitt">
                <h3>Wägungen · {wiegungen.length}</h3>
                <table className="dicht">
                  <thead><tr><th>Wiegetag</th><th>Eingang</th><th className="zahl">Damals (kg brutto)</th><th className="zahl">Jetzt (kg brutto)</th><th className="zahl">Kisten</th><th>Gebinde</th><th></th></tr></thead>
                  <tbody>{wiegungen.map(w => (
                    <tr key={w.id}>
                      <td>{datum(w.wiege_ts)}</td>
                      <td>{datum(w.eingangsdatum)}</td>
                      <td className="zahl">{w.brutto_damals_kg}</td>
                      <td className="zahl">{w.brutto_jetzt_kg}</td>
                      <td className="zahl">{w.kisten ?? '—'}</td>
                      <td>{w.gebindeart ?? ''}</td>
                      <td className="leise">{w.sichtbar_schimmel ? 'Schimmel sichtbar' : ''}{!w.gemessen ? 'nicht gemessen' : ''}</td>
                    </tr>
                  ))}</tbody>
                </table>
              </section>
            )}

            {d.ausschuss.length > 0 && (
              <section className="fenster-abschnitt">
                <h3>Zu klein / zu gross</h3>
                <table className="dicht">
                  <thead><tr><th>Zeit</th><th>Art</th><th className="zahl">Netto (kg)</th><th className="zahl">Brutto (kg)</th><th className="zahl">Kisten</th><th></th></tr></thead>
                  <tbody>{d.ausschuss.map(z => (
                    <tr key={z.id}>
                      <td>{uhrzeit(z.ts, gebietsschema)}</td>
                      <td>{z.art === 'zu_klein' ? 'zu klein' : 'zu gross'}</td>
                      <td className="zahl">{z.kg}</td>
                      <td className="zahl">{z.brutto_kg ?? '—'}</td>
                      <td className="zahl">{z.kisten ?? '—'}{z.gebindeart ? ` ${z.gebindeart}` : ''}</td>
                      <td className="leise">{z.mit_palette ? 'mit Palette · ' : ''}{z.bemerkung ?? ''}</td>
                    </tr>
                  ))}</tbody>
                </table>
              </section>
            )}

            {ausgang.length > 0 && (
              <section className="fenster-abschnitt">
                <h3>Fertige Paletten gewogen · {ausgang.length}</h3>
                <table className="dicht">
                  <thead><tr><th>Zeit</th><th className="zahl">Brutto (kg)</th><th className="zahl">Kisten</th><th>Gebinde</th><th className="zahl">Stück je Kiste</th><th>Kaliber</th><th></th></tr></thead>
                  <tbody>{ausgang.map(g => (
                    <tr key={g.id}>
                      <td>{uhrzeit(g.ts, gebietsschema)}</td>
                      <td className="zahl">{g.brutto_kg}</td>
                      <td className="zahl">{g.kisten}</td>
                      <td>{g.gebindeart ?? ''}</td>
                      <td className="zahl">{g.kuerbisse_pro_kiste ?? '—'}</td>
                      <td>{g.kaliber_idx != null ? `K${g.kaliber_idx + 1}` : '—'}</td>
                      <td className="leise">{g.voll ? '' : 'halbe Palette — zählt nicht in der Marge'}</td>
                    </tr>
                  ))}</tbody>
                </table>
              </section>
            )}

            {(Object.keys(d.angaben).length > 0 || a.paletten_gesamt != null || a.fertige_paletten_gesamt != null || a.palox_unbekannt) && (
              <section className="fenster-abschnitt">
                <h3>Angaben</h3>
                <dl className="zusammenfassung">
                  {a.fertige_paletten_gesamt != null && <><dt>Fertige Paletten insgesamt</dt><dd>{a.fertige_paletten_gesamt}</dd></>}
                  {a.paletten_gesamt != null && <><dt>Paletten gesamt</dt><dd>{a.paletten_gesamt}</dd></>}
                  {a.palox_unbekannt && <><dt>Palox</dt><dd>Menge unbekannt — zwischendurch geleert</dd></>}
                  {Object.entries(d.angaben).map(([k, v]) => <div key={k} style={{ display: 'contents' }}><dt>{k.replace(/_/g, ' ')}</dt><dd>{v}</dd></div>)}
                </dl>
              </section>
            )}

            {rueck.length > 0 && (
              <section className="fenster-abschnitt">
                <h3>Rückmeldung</h3>
                {rueck.map(r => (
                  <p key={r.id} className="rueckmeldung-text">{r.text ?? ''}{r.audio_ref ? <span className="leise"> · Aufnahme{r.audio_sekunden != null ? ` (${Math.floor(r.audio_sekunden / 60)}:${String(r.audio_sekunden % 60).padStart(2, '0')})` : ''} — unter Betrieb → Arbeiten anhören</span> : ''}</p>
                ))}
              </section>
            )}

            <div className="knopf-reihe" style={{ marginTop: 'var(--a-4)' }}>
              <Link to={`/arbeit/${a.id}?korrigieren=1`} className="knopf haupt">Messungen berichtigen</Link>
              <Link to={`/arbeit/${a.id}`} className="knopf">Arbeit öffnen</Link>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
