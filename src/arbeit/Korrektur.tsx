import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import type { ArbeitDaten } from './daten'

type Wert = string | number | boolean | null
type Zeile = Record<string, Wert> & { id: number }
interface Feld { name: string; label: string; typ: 'zahl' | 'ganz' | 'datum' | 'text' | 'ja_nein' | 'zeit'; nurLesen?: boolean }
interface Tabelle { tabelle: string; titel: string; erklaerung: string; felder: Feld[] }

/**
 * Die Korrektur (Runde H): Der Betriebsleiter kommt von einer Auffälligkeit
 * („korrigieren" auf der Messungen-Seite) hierher und sieht jede Messung dieser
 * Arbeit als Zeile — ändern, speichern, löschen. Was gemessen wurde, bleibt
 * gemessen: Abgeleitetes (Netto, Palox-Menge) rechnet die Datenbank nach dem
 * Speichern neu, hier wird nur die Beobachtung berichtigt.
 *
 * Nur für den Betriebsleiter (RLS: ist_admin()), darum deutsch wie die
 * Auswertung — der Arbeiter sieht diese Ansicht nicht.
 */
const TABELLEN: Tabelle[] = [
  { tabelle: 'schimmel_messung', titel: 'Palox-Ablesungen und Faules',
    erklaerung: 'Palox: die Zahl auf der Waage; Fax: Brutto, Kisten, Kistenart. Das Netto rechnet die Datenbank.',
    felder: [
      { name: 'ts', label: 'Zeit', typ: 'zeit', nurLesen: true },
      { name: 'palox_stand_kg', label: 'Waage (kg)', typ: 'zahl' },
      { name: 'brutto_kg', label: 'Brutto (kg)', typ: 'zahl' },
      { name: 'kisten', label: 'Kisten', typ: 'ganz' },
      { name: 'gebindeart', label: 'Kistenart', typ: 'text' },
      { name: 'mit_palette', label: 'mit Palette', typ: 'ja_nein' },
      { name: 'kg', label: 'Netto (kg)', typ: 'zahl', nurLesen: true },
      { name: 'bemerkung', label: 'Bemerkung', typ: 'text' },
    ] },
  { tabelle: 'verdunstung_wiegung', titel: 'Gewogene Eingangspaletten',
    erklaerung: 'Zettel-Datum und -Gewicht gegen das Gewicht jetzt — die Verdunstungsmessung.',
    felder: [
      { name: 'eingangsdatum', label: 'Eingangsdatum', typ: 'datum' },
      { name: 'brutto_damals_kg', label: 'Zettel (kg)', typ: 'zahl' },
      { name: 'brutto_jetzt_kg', label: 'jetzt (kg)', typ: 'zahl' },
      { name: 'kisten', label: 'Kisten', typ: 'ganz' },
      { name: 'gebindeart', label: 'Kistenart', typ: 'text' },
      { name: 'kuerbisse_pro_kiste', label: 'Stück je Kiste', typ: 'ganz' },
      { name: 'gemessen', label: 'gemessen', typ: 'ja_nein' },
    ] },
  { tabelle: 'ausschuss_messung', titel: 'Zu klein / zu gross',
    erklaerung: 'Je Palette gewogen (Waschen + Sortieren). Das Netto rechnet die Datenbank aus Brutto und Tara.',
    felder: [
      { name: 'art', label: 'Art', typ: 'text', nurLesen: true },
      { name: 'brutto_kg', label: 'Brutto (kg)', typ: 'zahl' },
      { name: 'kisten', label: 'Kisten', typ: 'ganz' },
      { name: 'gebindeart', label: 'Kistenart', typ: 'text' },
      { name: 'kg', label: 'Netto (kg)', typ: 'zahl', nurLesen: true },
      { name: 'bemerkung', label: 'Bemerkung', typ: 'text' },
    ] },
  { tabelle: 'ausgang_wiegung', titel: 'Fertige Paletten',
    erklaerung: 'Brutto, Kisten, Kistenart — daraus das Kistengewicht und die Überfüllung.',
    felder: [
      { name: 'brutto_kg', label: 'Brutto (kg)', typ: 'zahl' },
      { name: 'kisten', label: 'Kisten', typ: 'ganz' },
      { name: 'gebindeart', label: 'Kistenart', typ: 'text' },
      { name: 'kuerbisse_pro_kiste', label: 'Stück je Kiste', typ: 'ganz' },
      { name: 'kaliber_idx', label: 'Kaliber-Index', typ: 'ganz' },
    ] },
  { tabelle: 'auftrag_palette', titel: 'Gezählte Paletten',
    erklaerung: 'Eingangspaletten (Datum, Zettelgewicht) oder Kaliber-Paletten beim Waschen (Sortierdatum, Kisten).',
    felder: [
      { name: 'eingangsdatum', label: 'Eingangsdatum', typ: 'datum' },
      { name: 'brutto_zettel_kg', label: 'Zettel (kg)', typ: 'zahl' },
      { name: 'sortierdatum', label: 'Sortierdatum', typ: 'datum' },
      { name: 'kisten', label: 'Kisten', typ: 'ganz' },
      { name: 'wiegung_id', label: 'Wägung', typ: 'ganz', nurLesen: true },
    ] },
  { tabelle: 'auftrag_gebinde', titel: 'Kisten je Kaliber (Sortieren)',
    erklaerung: 'Die gefüllten Kisten je Band.',
    felder: [
      { name: 'kaliber_idx', label: 'Kaliber-Index', typ: 'ganz', nurLesen: true },
      { name: 'anzahl', label: 'Kisten', typ: 'ganz' },
    ] },
]

const AUFTRAG_FELDER: Feld[] = [
  { name: 'kistensystem', label: 'Kistensystem (kiste_ab / stueck / anderes)', typ: 'text' },
  { name: 'soll_kg_pro_kiste', label: 'Soll kg je Kiste', typ: 'zahl' },
  { name: 'stueck_je_kiste', label: 'Stück je Kiste', typ: 'ganz' },
  { name: 'kaliber_idx', label: 'Kaliber-Index (Waschen)', typ: 'ganz' },
  { name: 'kaliber_von_g', label: 'eigenes Kaliber von (g)', typ: 'ganz' },
  { name: 'kaliber_bis_g', label: 'eigenes Kaliber bis (g)', typ: 'ganz' },
  { name: 'paletten_gesamt', label: 'Paletten gesamt (Fax)', typ: 'ganz' },
  { name: 'tage_seit_waschen', label: 'Tage seit dem Waschen (Fax)', typ: 'ganz' },
]

const zuText = (w: Wert, f: Feld): string => {
  if (w === null || w === undefined) return ''
  if (f.typ === 'zeit') return new Date(String(w)).toLocaleString('de-CH', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
  return String(w)
}
const zuWert = (s: string, f: Feld): Wert => {
  if (s === '') return null
  if (f.typ === 'zahl') return Number(s)
  if (f.typ === 'ganz') return Math.round(Number(s))
  return s
}

/**
 * Welche Zeilen der Block zeigt. Meist die einer Arbeit; die Lagerkontrolle
 * gehört zu keiner Arbeit (der Betriebsleiter wiegt zwischendurch eine
 * Palette), darum kann auch auf „Spalte ist leer" gefiltert werden — sonst
 * wäre eine Kontrollwägung sichtbar, aber nicht zu berichtigen.
 */
interface Filter { spalte: string; wert: number | null }

function Tabellenblock({ t, wo, gesperrt, geaendert }: { t: Tabelle; wo: Filter; gesperrt: boolean; geaendert: () => Promise<void> }) {
  const [zeilen, setZeilen] = useState<Zeile[]>([])
  const [entwurf, setEntwurf] = useState<Record<number, Record<string, string>>>({})
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  const laden = useCallback(async () => {
    const frage = supabase.from(t.tabelle).select('*')
    const { data, error } = await (wo.wert === null ? frage.is(wo.spalte, null) : frage.eq(wo.spalte, wo.wert)).order('id')
    if (error) { setFehler(fehlerText(error)); return }
    setZeilen((data ?? []) as Zeile[]); setEntwurf({})
  }, [t.tabelle, wo.spalte, wo.wert])
  useEffect(() => { void laden() }, [laden])

  const wertVon = (z: Zeile, f: Feld) => entwurf[z.id]?.[f.name] ?? zuText(z[f.name], f)
  const istGeaendert = (z: Zeile) => Object.keys(entwurf[z.id] ?? {}).length > 0

  async function speichern(z: Zeile) {
    const e = entwurf[z.id]; if (!e || laeuft) return
    setLaeuft(true); setFehler(null)
    const setzt: Record<string, Wert> = {}
    for (const f of t.felder) if (f.name in e) setzt[f.name] = f.typ === 'ja_nein' ? e[f.name] === 'true' : zuWert(e[f.name], f)
    const { error } = await supabase.from(t.tabelle).update(setzt).eq('id', z.id)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    await laden(); await geaendert()
  }
  async function loeschen(z: Zeile) {
    if (laeuft || !window.confirm(`Diese Zeile aus „${t.titel}" löschen? Das ist eine Messung — nur, wenn sie wirklich falsch ist.`)) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from(t.tabelle).delete().eq('id', z.id)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    await laden(); await geaendert()
  }

  if (zeilen.length === 0 && !fehler) return null
  return (
    <div className="karte">
      <h2 style={{ margin: '0 0 .2rem', fontSize: '1.05rem' }}>{t.titel} <span className="leise">({zeilen.length})</span></h2>
      <p className="leise" style={{ margin: '0 0 .6rem' }}>{t.erklaerung}</p>
      <div style={{ overflowX: 'auto' }}>
        <table className="korrektur">
          <thead><tr>{t.felder.map(f => <th key={f.name}>{f.label}</th>)}<th /></tr></thead>
          <tbody>
            {zeilen.map(z => (
              <tr key={z.id}>
                {t.felder.map(f => (
                  <td key={f.name}>
                    {f.nurLesen ? <span className={f.typ === 'zeit' ? 'leise' : ''}>{zuText(z[f.name], f) || '—'}</span>
                     : f.typ === 'ja_nein'
                       ? <select value={wertVon(z, f) === 'true' ? 'true' : 'false'} disabled={gesperrt}
                                 onChange={e => setEntwurf(x => ({ ...x, [z.id]: { ...x[z.id], [f.name]: e.target.value } }))}>
                           <option value="true">ja</option><option value="false">nein</option>
                         </select>
                       : <input type={f.typ === 'datum' ? 'date' : f.typ === 'text' ? 'text' : 'number'}
                                step={f.typ === 'zahl' ? '0.01' : f.typ === 'ganz' ? '1' : undefined}
                                value={wertVon(z, f)} disabled={gesperrt} style={{ minWidth: f.typ === 'text' ? '8rem' : '5.5rem' }}
                                onChange={e => setEntwurf(x => ({ ...x, [z.id]: { ...x[z.id], [f.name]: e.target.value } }))} />}
                  </td>
                ))}
                <td style={{ whiteSpace: 'nowrap' }}>
                  <button className="haupt klein" disabled={gesperrt || laeuft || !istGeaendert(z)} onClick={() => void speichern(z)}>Speichern</button>
                  {' '}
                  <button className="gefahr klein" disabled={gesperrt || laeuft} aria-label="Löschen" onClick={() => void loeschen(z)}>✕</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </div>
  )
}

export function Korrektur({ d, neuLaden, zurueck }: { d: ArbeitDaten; neuLaden: () => Promise<void>; zurueck: () => void }) {
  const a = d.auftrag
  const [entwurf, setEntwurf] = useState<Record<string, string>>({})
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)
  const [gespeichert, setGespeichert] = useState(false)
  const auftragZeile = a as unknown as Zeile

  async function auftragSpeichern() {
    if (laeuft || Object.keys(entwurf).length === 0) return
    setLaeuft(true); setFehler(null)
    const setzt: Record<string, Wert> = {}
    for (const f of AUFTRAG_FELDER) if (f.name in entwurf) setzt[f.name] = zuWert(entwurf[f.name], f)
    const { error } = await supabase.from('auftrag').update(setzt).eq('id', a.id)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    setEntwurf({}); setGespeichert(true); await neuLaden()
  }

  return (
    <>
      <div className="schritt-kopf">
        <button type="button" className="zurueck" onClick={zurueck}>‹ Zurück</button>
        <span className="stand">Arbeit {a.id} · Charge {a.charge_nr}</span>
      </div>
      <h1 className="frage">Messungen korrigieren</h1>
      <p className="leise frage-warum">
        Jede Messung dieser Arbeit als Zeile. Berichtigt wird die Beobachtung (Waagenstand, Datum, Kisten);
        das Abgeleitete rechnet die Datenbank neu. Löschen nur, was wirklich nicht gemessen wurde.
        {a.status === 'abgeschlossen' && ' Die Arbeit ist abgeschlossen — Änderungen fliessen beim nächsten Rechnen ein.'}
      </p>
      {gespeichert && <Hinweis art="gut">Gespeichert — die Auswertung rechnet beim nächsten Aufruf neu.</Hinweis>}

      <div className="karte">
        <h2 style={{ margin: '0 0 .2rem', fontSize: '1.05rem' }}>Die Arbeit</h2>
        <p className="leise" style={{ margin: '0 0 .6rem' }}>Was beim Eröffnen festgelegt wurde — Kistensystem, Soll, Kaliber; beim Fax Paletten und Tage.</p>
        {AUFTRAG_FELDER.map(f => (
          <div className="feld" key={f.name}>
            <label htmlFor={`ko-${f.name}`}>{f.label}</label>
            <input id={`ko-${f.name}`} type={f.typ === 'text' ? 'text' : 'number'} step={f.typ === 'zahl' ? '0.01' : '1'}
                   value={entwurf[f.name] ?? zuText(auftragZeile[f.name], f)}
                   onChange={e => setEntwurf(x => ({ ...x, [f.name]: e.target.value }))} />
          </div>
        ))}
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <button className="haupt" style={{ width: '100%' }} disabled={laeuft || Object.keys(entwurf).length === 0} onClick={() => void auftragSpeichern()}>Arbeit speichern</button>
      </div>

      {TABELLEN.map(t => <Tabellenblock key={t.tabelle} t={t} wo={{ spalte: 'auftrag_id', wert: a.id }} gesperrt={false} geaendert={neuLaden} />)}
    </>
  )
}

/**
 * Die Lagerkontrollen berichtigen. Eine Kontrollwägung entsteht ohne Arbeit —
 * der Betriebsleiter wiegt zwischendurch eine Palette nach (Seite „Kontrolle").
 * Sie stand darum in der Auswertung, war aber über keine Arbeit erreichbar und
 * damit nicht zu korrigieren. Dieser Block zeigt genau diese Zeilen.
 *
 * Die Chargennummer ist hier änderbar: bei einer Kontrolle ist sie von Hand
 * getippt, und eine Wägung an der falschen Charge verschiebt deren
 * Verdunstungsrate. Alles andere bleibt wie bei den Arbeiten — geändert wird
 * die Beobachtung, das Abgeleitete rechnet die Datenbank nach.
 */
const KONTROLLE: Tabelle = {
  tabelle: 'verdunstung_wiegung',
  titel: 'Lagerkontrollen (ohne Arbeit gewogen)',
  erklaerung: 'Zwischendurch nachgewogene Paletten: Zettel-Datum und -Gewicht gegen das Gewicht jetzt. '
    + 'Sie gehören zu keiner Arbeit, darum stehen sie hier statt bei einer.',
  felder: [
    { name: 'wiege_ts', label: 'Gewogen', typ: 'zeit', nurLesen: true },
    { name: 'charge_nr', label: 'Charge', typ: 'ganz' },
    { name: 'eingangsdatum', label: 'Eingangsdatum', typ: 'datum' },
    { name: 'brutto_damals_kg', label: 'Zettel (kg)', typ: 'zahl' },
    { name: 'brutto_jetzt_kg', label: 'jetzt (kg)', typ: 'zahl' },
    { name: 'kisten', label: 'Kisten', typ: 'ganz' },
    { name: 'gebindeart', label: 'Kistenart', typ: 'text' },
    { name: 'sichtbar_schimmel', label: 'Faules sichtbar', typ: 'ja_nein' },
    { name: 'bemerkung', label: 'Bemerkung', typ: 'text' },
  ],
}

export function Kontrollkorrektur({ geaendert }: { geaendert: () => Promise<void> }) {
  return <Tabellenblock t={KONTROLLE} wo={{ spalte: 'auftrag_id', wert: null }} gesperrt={false} geaendert={geaendert} />
}
