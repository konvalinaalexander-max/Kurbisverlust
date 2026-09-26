import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { WOERTERBUCH } from '../lib/i18n'
import { datum, kg, prozent, zeitpunkt } from '../lib/format'
import { Hinweis, Lade, Marke } from '../components/Bausteine'
import { TaetZeichen, ZKreuz } from '../components/Zeichen'
import type { Bestand, Wohin } from '../auswertung/daten'
import { ArbeitFenster } from './ArbeitFenster'

interface ChargeZeile { nr: number; schlag: string; sorte: string; saison: number; ernte_abgeschlossen_ts: string | null }
interface ArbeitKurz { id: number; weg: string; station: string; ist_fax: boolean; start_ts: string; ende_ts: string | null; status: string; abgebrochen_ts: string | null }
interface LieferungKurz { id: number; datum: string; masse_kg: number | null; ziel_name: string | null; buch: string | null }
interface BefundKurz { art: string; befund: string; auftrag_id: number | null }
interface KommentarKurz { auftrag_id: number; text: string; roh: string | null; ts: string }

/** Die Summe, die „nicht gemessen" bleibt, solange kein Teil gemessen ist (Leer ist nicht null). */
function summe(...teile: (number | null | undefined)[]): number | null {
  const da = teile.filter((x): x is number => x != null)
  return da.length ? da.reduce((a, b) => a + b, 0) : null
}

/**
 * Die Charge hinter einer Zahl — als Fenster über der Seite (Runde Z).
 *
 * Der Betrieb: „wenn ich eine Charge anklicke, dann vielleicht ein Pop-up mit
 * den Chargen-Infos." Also das Wesentliche auf einen Blick: Eingang, was
 * heute liegt, wohin der Rest ging, die Arbeiten, die Lieferungen, die
 * Auffälligkeiten, die gekürzten Kommentare — und von hier aus die Arbeit
 * als Fenster oder die Seiten, die mehr zeigen.
 */
export function ChargeFenster({ chargeNr, schliessen }: { chargeNr: number; schliessen: () => void }) {
  const [charge, setCharge] = useState<ChargeZeile | null>(null)
  const [bestand, setBestand] = useState<Bestand | null>(null)
  const [wohin, setWohin] = useState<Wohin | null>(null)
  const [arbeiten, setArbeiten] = useState<ArbeitKurz[]>([])
  const [lieferungen, setLieferungen] = useState<LieferungKurz[]>([])
  const [befunde, setBefunde] = useState<BefundKurz[]>([])
  const [kommentare, setKommentare] = useState<KommentarKurz[]>([])
  const [geladen, setGeladen] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const [arbeit, setArbeit] = useState<number | null>(null)
  const kindOffen = useRef(false)
  kindOffen.current = arbeit !== null
  const t = (id: keyof typeof WOERTERBUCH.de) => WOERTERBUCH.de[id]

  useEffect(() => {
    let lebt = true
    void (async () => {
      try {
        const [c, b, w, a, l, p, k] = await Promise.all([
          supabase.from('charge').select('nr, schlag, sorte, saison, ernte_abgeschlossen_ts').eq('nr', chargeNr),
          supabase.from('erg_charge').select('*').eq('charge_nr', chargeNr),
          supabase.from('erg_wohin').select('*').eq('gruppe', 'charge').eq('schluessel', String(chargeNr)),
          supabase.from('auftrag').select('id, weg, station, ist_fax, start_ts, ende_ts, status, abgebrochen_ts').eq('charge_nr', chargeNr).order('start_ts', { ascending: false }),
          supabase.from('erg_lieferung').select('id, datum, masse_kg, ziel_name, buch').eq('charge_nr', chargeNr).order('datum', { ascending: false }),
          supabase.from('erg_plausibilitaet').select('art, befund, auftrag_id').eq('charge_nr', chargeNr),
          supabase.from('v_arbeit_kommentar').select('auftrag_id, text, roh, ts').eq('charge_nr', chargeNr).order('ts', { ascending: false }),
        ])
        if (!lebt) return
        for (const x of [c, b, w, a, l, p, k]) if (x.error) throw x.error
        setCharge(((c.data ?? []) as ChargeZeile[])[0] ?? null)
        setBestand(((b.data ?? []) as Bestand[])[0] ?? null)
        setWohin(((w.data ?? []) as Wohin[])[0] ?? null)
        setArbeiten((a.data ?? []) as ArbeitKurz[])
        setLieferungen((l.data ?? []) as LieferungKurz[])
        setBefunde((p.data ?? []) as BefundKurz[])
        setKommentare((k.data ?? []) as KommentarKurz[])
        setGeladen(true)
      } catch (f) { if (lebt) setFehler(fehlerText(f)) }
    })()
    return () => { lebt = false }
  }, [chargeNr])

  // Escape schliesst — aber nur dieses Fenster, nicht das darunter mit.
  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape' && !kindOffen.current) schliessen() }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [schliessen])

  const eingang = bestand?.eingang_kg ?? wohin?.eingang_kg ?? null
  const anteil = (x: number | null) => (x != null && eingang ? prozent(x / eingang) : '—')
  const teile: { name: string; kg: number | null }[] = wohin ? [
    { name: 'noch im Lager, verkaufsfähig', kg: wohin.lager_verkaufsfaehig_kg },
    { name: 'verkauft (auf Lieferscheinen)', kg: wohin.geliefert_kg },
    { name: 'verdunstet bis heute', kg: summe(wohin.verdunstet_ausgelagert_kg, wohin.lager_verdunstet_kg) },
    { name: 'Faules bis heute', kg: summe(wohin.faul_ausgelagert_kg, wohin.lager_faul_kg, wohin.sockel_ausgelagert_kg, wohin.lager_sockel_kg, wohin.fax_kg, wohin.lager_fax_kg) },
    { name: 'zu klein', kg: summe(wohin.klein_ausgelagert_kg, wohin.lager_klein_kg) },
    { name: 'zu gross', kg: summe(wohin.gross_ausgelagert_kg, wohin.lager_gross_kg) },
    { name: 'Rest der Zählung', kg: summe(wohin.rest_kg, wohin.lager_rest_kg) },
  ] : []
  const jeTaetigkeit = new Map<string, number>()
  for (const a of arbeiten) {
    const ta = taetigkeitVon(a.weg as never, a.station as never, a.ist_fax)
    const n = ta ? t(ta.text) : 'Arbeit'
    jeTaetigkeit.set(n, (jeTaetigkeit.get(n) ?? 0) + 1)
  }
  const jeArt = new Map<string, number>()
  for (const b of befunde) jeArt.set(b.art, (jeArt.get(b.art) ?? 0) + 1)
  const geliefert = summe(...lieferungen.map(l => l.masse_kg))

  return (
    <div className="dialog-hinter" onClick={schliessen}>
      <div className="dialog breit" role="dialog" aria-modal="true" aria-label="Charge" id="charge-fenster" onClick={e => e.stopPropagation()}>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {!geladen && !fehler && <Lade />}
        {geladen && (
          <>
            <div className="fenster-kopf">
              <div>
                <h2>Charge {chargeNr} <span className="leise">· {charge?.sorte ?? bestand?.sorte ?? ''}{charge?.schlag ? ` · ${charge.schlag}` : ''}</span></h2>
                <p className="leise" style={{ margin: '.2rem 0 0' }}>
                  {charge ? `Saison ${charge.saison}` : 'nicht in den Stammdaten'}
                  {' · '}{charge?.ernte_abgeschlossen_ts ? `Ernte abgeschlossen am ${datum(charge.ernte_abgeschlossen_ts)}` : 'Ernte läuft noch'}
                  {bestand?.eingang_von ? ` · Eingang ${datum(bestand.eingang_von)}${bestand.eingang_bis && bestand.eingang_bis !== bestand.eingang_von ? ` – ${datum(bestand.eingang_bis)}` : ''}` : ''}
                </p>
              </div>
              <button type="button" className="klein schliessen" onClick={schliessen} aria-label="schliessen"><ZKreuz size={16} /></button>
            </div>

            <section className="fenster-abschnitt">
              <h3>Eingang und heute</h3>
              {bestand ? (
                <dl className="zusammenfassung">
                  <dt>Eingang</dt><dd>{kg(bestand.eingang_kg, 0)} netto · {bestand.n_paletten} Paletten{bestand.ueberzaehlung_kg > 0 ? ` · ${kg(bestand.ueberzaehlung_kg, 0)} mehr geliefert als eingelagert` : ''}</dd>
                  <dt>Im Haus heute</dt><dd>{kg(bestand.im_haus_heute_kg, 0)}{bestand.verkaufsfaehig_lager_kg != null ? ` · davon verkaufsfähig ${kg(bestand.verkaufsfaehig_lager_kg, 0)}` : ' · verkaufsfähig: nicht gemessen'}</dd>
                  <dt>Verarbeitet</dt><dd>{kg(bestand.ausgelagert_kg, 0)} ausgelagert · {kg(bestand.sortiert_kg, 0)} sortiert · {kg(bestand.gewaschen_kg, 0)} gewaschen</dd>
                  <dt>Geliefert</dt><dd>{kg(bestand.geliefert_kg, 0)} · {bestand.n_lieferungen} {bestand.n_lieferungen === 1 ? 'Lieferung' : 'Lieferungen'}</dd>
                  <dt>Lagerdauer</dt><dd>{Math.round(bestand.alter_lager_heute)} Tage im Mittel{bestand.alter_lager_von != null && bestand.alter_lager_bis != null ? ` (${Math.round(bestand.alter_lager_von)}–${Math.round(bestand.alter_lager_bis)})` : ''}</dd>
                </dl>
              ) : <p className="leise">Die Auswertung kennt diese Charge noch nicht — „Neu rechnen" auf dem Dashboard.</p>}
            </section>

            {wohin && (
              <section className="fenster-abschnitt">
                <h3>Wohin ging der Kürbis · {kg(eingang, 0)} Eingang</h3>
                <table className="dicht">
                  <thead><tr><th>Teil</th><th className="zahl">kg</th><th className="zahl">Anteil</th></tr></thead>
                  <tbody>{teile.filter(x => x.kg == null || Math.abs(x.kg) > 0.5).map(x => (
                    <tr key={x.name}><td>{x.name}</td><td className="zahl">{x.kg == null ? 'nicht gemessen' : kg(x.kg, 0)}</td><td className="zahl">{anteil(x.kg)}</td></tr>
                  ))}</tbody>
                </table>
              </section>
            )}

            <section className="fenster-abschnitt">
              <h3>Arbeiten · {arbeiten.length}</h3>
              {arbeiten.length === 0 ? <p className="leise">noch keine</p> : (
                <>
                  <p className="leise" style={{ margin: '0 0 .4rem' }}>{[...jeTaetigkeit.entries()].map(([n, z]) => `${z}× ${n}`).join(' · ')}</p>
                  <table className="dicht">
                    <thead><tr><th>Start</th><th>Arbeit</th><th>Stand</th><th></th></tr></thead>
                    <tbody>{arbeiten.slice(0, 8).map(a => {
                      const ta = taetigkeitVon(a.weg as never, a.station as never, a.ist_fax)
                      return (
                        <tr key={a.id}>
                          <td className="nowrap">{zeitpunkt(a.start_ts)}</td>
                          <td className="nowrap"><TaetZeichen id={ta?.id} /> {ta ? t(ta.text) : 'Arbeit'}</td>
                          <td>{a.abgebrochen_ts ? <Marke art="warnung">abgebrochen</Marke> : a.status === 'offen' ? <Marke art="offen">läuft</Marke> : <Marke art="fertig">fertig</Marke>}</td>
                          <td className="rechts-buendig"><button type="button" className="werkzeug-knopf" onClick={() => setArbeit(a.id)}>ansehen</button></td>
                        </tr>
                      )
                    })}</tbody>
                  </table>
                  {arbeiten.length > 8 && <p className="leise" style={{ margin: '.3rem 0 0' }}>… und {arbeiten.length - 8} weitere unter Betrieb → Arbeiten</p>}
                </>
              )}
            </section>

            <section className="fenster-abschnitt">
              <h3>Lieferungen · {lieferungen.length}{geliefert != null ? ` · ${kg(geliefert, 0)}` : ''}</h3>
              {lieferungen.length === 0 ? <p className="leise">noch keine</p> : (
                <table className="dicht">
                  <thead><tr><th>Datum</th><th className="zahl">kg</th><th>Ziel</th><th>Buch</th></tr></thead>
                  <tbody>{lieferungen.slice(0, 6).map(l => (
                    <tr key={l.id}><td>{datum(l.datum)}</td><td className="zahl">{l.masse_kg != null ? kg(l.masse_kg, 0) : '—'}</td><td>{l.ziel_name ?? ''}</td><td className="leise">{l.buch ?? ''}</td></tr>
                  ))}</tbody>
                </table>
              )}
            </section>

            {befunde.length > 0 && (
              <section className="fenster-abschnitt">
                <h3>Auffälligkeiten · {befunde.length}</h3>
                <p className="leise" style={{ margin: '0 0 .4rem' }}>{[...jeArt.entries()].map(([a, z]) => `${z}× ${a}`).join(' · ')}</p>
                <ul className="liste-schlicht">{befunde.slice(0, 6).map((b, i) => (
                  <li key={i}><strong>{b.art}:</strong> {b.befund}{b.auftrag_id != null && <> <button type="button" className="werkzeug-knopf" onClick={() => setArbeit(b.auftrag_id!)}>Arbeit</button></>}</li>
                ))}</ul>
              </section>
            )}

            {kommentare.length > 0 && (
              <section className="fenster-abschnitt">
                <h3>Kommentare zur Ware · {kommentare.length}</h3>
                {kommentare.map(k => (
                  <p key={`${k.auftrag_id}${k.ts}`} className="rueckmeldung-text">
                    <strong>{k.text}</strong>{k.roh && <span className="leise"> — „{k.roh}"</span>}
                    {' '}<button type="button" className="werkzeug-knopf" onClick={() => setArbeit(k.auftrag_id)}>Arbeit</button>
                  </p>
                ))}
              </section>
            )}

            <div className="knopf-reihe" style={{ marginTop: 'var(--a-4)' }}>
              <Link to={`/ursachen?charge=${chargeNr}`} className="knopf haupt">Ursachen dieser Charge</Link>
              <Link to={`/dashboard?charge=${chargeNr}`} className="knopf">Im Lagermanagement</Link>
            </div>
          </>
        )}
      </div>
      {arbeit !== null && <div onClick={e => e.stopPropagation()}><ArbeitFenster auftragId={arbeit} schliessen={() => setArbeit(null)} /></div>}
    </div>
  )
}
