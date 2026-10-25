/**
 * Runde BG: die Auffälligkeiten, Fall für Fall — wie der Reiter Perigon. Der
 * Betrieb, 25. Oktober: „bitte ordne die chronologisch. Also die obersten
 * sollen die neuesten sein … wenn ich dann eine Auffälligkeit öffne … damit
 * ich besser nachvollziehen kann, was eigentlich genau Sache ist. Also das
 * Problem und dann mir Lösungsvorschläge anbieten, die ich dann auch
 * akzeptieren kann oder nicht akzeptieren … spezifische Fallnummer, damit
 * ich dir auch im Chat sagen kann, wie ich mit diesen Fallnummern umgehen
 * möchte."
 *
 * Links die Liste, nach dem Tag der Arbeit, die neuesten zuoberst, jede mit
 * ihrer Nummer (0128, fest). Rechts der Fall, für jede Art gleich:
 *  1. Was ist passiert — der Befund, und bei Zetteln die Daten: die Zettel
 *     der Arbeit gegen den Wareneingang der Charge an den Tagen, um die es
 *     geht, wer welche Palette schon gezählt hat.
 *  2. Wie kommt es dazu — wo im Ablauf das entsteht, das Muster, das die App
 *     in den Daten sieht, und was es für die Zahlen heisst.
 *  3. Der Vorschlag — ein Klick, wo die Daten einen Wert nennen
 *     (auffaelligkeit_korrigieren, danach neu rechnen); „so lassen", wo es so
 *     stimmt; sonst der Weg dorthin, wo es zu ändern wäre. Annehmen oder
 *     nicht — beides wird vermerkt.
 *  4. Stand und Notiz — was entschieden ist, wer, wann.
 */
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { kg, lesbar, zeitpunkt } from '../lib/format'
import { useAuth } from '../auth/AuthProvider'
import { Hinweis, Kennzahl, Segmente } from '../components/Bausteine'
import { ZChevron, ZZurueck } from '../components/Zeichen'
import { taetigkeitVon } from '../lib/taetigkeit'
import { WOERTERBUCH } from '../lib/i18n'
import { ArbeitFenster } from '../betrieb/ArbeitFenster'
import { ChargeFenster } from '../betrieb/ChargeFenster'
import type { Befund } from './daten'
import {
  AUFF_STAND_NAME, MUSTER_NAME, artInfo, artVorschlag, belegtVon, betroffeneZettel, chatZeile, fallKennung, istZettelFall,
  nachTag, neuZuerst, nichtMehrDa, nummernFolge, passtStand, standVon, tagIn, tagText, vermerkeJeFall, zettelDeutung,
  type AuffStand, type AuffVermerk, type Deutung, type StandFilter, type Vorschlag, type WarePalette, type Zettel, type ZettelLage,
} from './auffaellig'

/** Was die Liste über eine Arbeit sagt, ohne sie zu öffnen. */
interface ArbeitKurz { id: number; weg: string; station: string; ist_fax: boolean; start_ts: string; status: string; abgebrochen_ts: string | null }

const t = (id: keyof typeof WOERTERBUCH.de) => WOERTERBUCH.de[id]
const taetigkeit = (a: ArbeitKurz | undefined) => {
  if (!a) return null
  const ta = taetigkeitVon(a.weg as never, a.station as never, a.ist_fax)
  return ta ? t(ta.text) : 'Arbeit'
}

/** Die Farbkante: rot, wo eine Zahl der Rechnung fraglich ist; gelb, wo ein Datum; blau, wo nur etwas fehlt. */
function ton(art: string): 'rot' | 'gelb' | 'info' {
  if (/datum|zukunft/i.test(art)) return 'gelb'
  if (/kistengewicht|ohne nenner|fehlt|palox geleert/i.test(art)) return 'info'
  return 'rot'
}

export function AuffStandMarke({ stand }: { stand: AuffStand }) {
  return <span className={`stand-marke st-${stand}`}>{AUFF_STAND_NAME[stand]}</span>
}

/* ---------- Daten: Nummern und Vermerke ---------------------------------- */

/** Die Nummern (0128): vergeben in der Folge alt → neu, danach fest. Ohne Funktion (vor 0128) ohne Nummer. */
function useNummern(befunde: Befund[]): Map<string, number> {
  const [nummern, setNummern] = useState<Map<string, number>>(new Map())
  const folge = useMemo(() => nummernFolge(befunde), [befunde])
  const kennung = folge.join('\n')
  useEffect(() => {
    if (!kennung) return
    let lebt = true
    void (async () => {
      const r = await supabase.rpc('auffaelligkeit_nummern', { p_faelle: kennung.split('\n') })
      if (!lebt || r.error) return
      setNummern(new Map(((r.data ?? []) as { fall: string; nr: number }[]).map(x => [x.fall, Number(x.nr)])))
    })()
    return () => { lebt = false }
  }, [kennung])
  return nummern
}

export interface VermerkWissen { vermerke: Map<string, AuffVermerk[]>; fehler: string | null; neuLaden: () => Promise<void> }

/** Der Stand aller Auffälligkeiten (auffaelligkeit_vermerk) — einmal je Seite geladen, nach jedem Vermerk wieder. */
export function useVermerke(): VermerkWissen {
  const [alle, setAlle] = useState<AuffVermerk[]>([])
  const [fehler, setFehler] = useState<string | null>(null)
  const neuLaden = useCallback(async () => {
    const r = await supabase.from('auffaelligkeit_vermerk').select('id, fall, stand, notiz, schnappschuss, wer, ts, profil(name)')
      .order('ts', { ascending: false }).order('id', { ascending: false })
    if (r.error) { setFehler(fehlerText(r.error)); return }
    setFehler(null)
    setAlle((r.data ?? []) as unknown as AuffVermerk[])
  }, [])
  useEffect(() => { void neuLaden() }, [neuLaden])
  const vermerke = useMemo(() => vermerkeJeFall(alle), [alle])
  return { vermerke, fehler, neuLaden }
}

/** Breit genug für Liste und Fall nebeneinander? */
function useBreit(): boolean {
  const abfrage = '(min-width: 900px)'
  const [breit, setBreit] = useState(() => typeof window === 'undefined' || window.matchMedia(abfrage).matches)
  useEffect(() => {
    const m = window.matchMedia(abfrage)
    const h = () => setBreit(m.matches)
    m.addEventListener('change', h)
    return () => m.removeEventListener('change', h)
  }, [])
  return breit
}

const STAND_FILTER: [StandFilter, string, string][] = [
  ['offen', 'offen', 'auff-filter-offen'], ['in_abklaerung', 'in Abklärung', 'auff-filter-abklaerung'],
  ['erledigt', 'erledigt', 'auff-filter-erledigt'], ['alle', 'alle', 'auff-filter-alle'],
]

/* ---------- Die Seite ---------------------------------------------------- */

/** Wie viele Auffälligkeiten offen sind — für die Zahl am Reiter. */
export function offeneZahl(befunde: Befund[], vermerke: Map<string, AuffVermerk[]>): number {
  return befunde.filter(b => standVon(fallKennung(b), vermerke) === 'offen').length
}

export function AuffaelligkeitFaelle({ befunde, neuRechnen, wissen }: { befunde: Befund[]; neuRechnen: () => void; wissen: VermerkWissen }) {
  const [such, setSuch] = useSearchParams()
  const breit = useBreit()
  const nummern = useNummern(befunde)
  const { vermerke, fehler: vermerkFehler, neuLaden } = wissen
  const [arbeiten, setArbeiten] = useState<Map<number, ArbeitKurz>>(new Map())
  const ids = useMemo(() => [...new Set(befunde.map(b => b.auftrag_id).filter((x): x is number => x !== null))].join(','), [befunde])
  useEffect(() => {
    if (!ids) { setArbeiten(new Map()); return }
    let lebt = true
    void supabase.from('auftrag').select('id, weg, station, ist_fax, start_ts, status, abgebrochen_ts').in('id', ids.split(',').map(Number))
      .then(({ data }) => { if (lebt) setArbeiten(new Map(((data ?? []) as ArbeitKurz[]).map(a => [a.id, a]))) })
    return () => { lebt = false }
  }, [ids])

  const stand: StandFilter = (STAND_FILTER.map(s => s[0]) as string[]).includes(such.get('stand') ?? '') ? such.get('stand') as StandFilter : 'offen'
  const art = such.get('art') ?? ''
  const suche = (such.get('suche') ?? '').trim().toLowerCase()
  const setze = (k: string, v: string) => {
    const neu = new URLSearchParams(such)
    if (v) neu.set(k, v); else neu.delete(k)
    setSuch(neu, { replace: true })
  }

  const geordnet = useMemo(() => neuZuerst(befunde), [befunde])
  const standDer = useCallback((b: Befund) => standVon(fallKennung(b), vermerke), [vermerke])
  const liste = useMemo(() => geordnet.filter(b => passtStand(standDer(b), stand) && (!art || b.art === art) && (!suche || [
    String(nummern.get(fallKennung(b)) ?? ''), String(b.charge_nr), String(b.auftrag_id ?? ''), b.sorte, b.art, lesbar(b.befund),
  ].some(x => x.toLowerCase().includes(suche)))), [geordnet, standDer, stand, art, suche, nummern])
  const arten = useMemo(() => [...geordnet.filter(b => passtStand(standDer(b), stand))
    .reduce((m, b) => m.set(b.art, (m.get(b.art) ?? 0) + 1), new Map<string, number>()).entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'de')), [geordnet, standDer, stand])
  const jetzt = useMemo(() => new Set(befunde.map(fallKennung)), [befunde])
  const weg = useMemo(() => nichtMehrDa(vermerke, jetzt), [vermerke, jetzt])
  const zahlen = useMemo(() => {
    const s = geordnet.map(standDer)
    return {
      offen: s.filter(x => x === 'offen').length,
      abklaerung: s.filter(x => x === 'in_abklaerung').length,
      erledigt: s.filter(x => x === 'so_lassen' || x === 'korrigiert').length,
      behoben: weg.length,
    }
  }, [geordnet, standDer, weg])

  const gefragt = such.get('fall')
  const gewaehlt = (gefragt ? geordnet.find(b => String(nummern.get(fallKennung(b)) ?? '') === gefragt || fallKennung(b) === gefragt) : undefined)
    ?? (liste.length === 1 || (breit && liste.length > 0) ? liste[0] : undefined)
  const i = gewaehlt ? liste.findIndex(b => fallKennung(b) === fallKennung(gewaehlt)) : -1
  // Die Nachbarn nach der Zeit — auch für einen Fall, der nach einem Vermerk nicht mehr in der gewählten Liste steht.
  const ort = useMemo(() => new Map(geordnet.map((b, k) => [fallKennung(b), k])), [geordnet])
  const hier = gewaehlt ? ort.get(fallKennung(gewaehlt)) ?? -1 : -1
  const neuerer = gewaehlt ? [...liste].reverse().find(b => (ort.get(fallKennung(b)) ?? -1) < hier) : undefined
  const aelterer = gewaehlt ? liste.find(b => (ort.get(fallKennung(b)) ?? -1) > hier) : undefined
  const waehlen = useCallback((b: Befund | undefined) => {
    const neu = new URLSearchParams(such)
    if (b) neu.set('fall', String(nummern.get(fallKennung(b)) ?? fallKennung(b))); else neu.delete('fall')
    setSuch(neu, { replace: !!b && !!such.get('fall') })
    window.requestAnimationFrame(() => {
      const el = document.getElementById(b ? 'auff-ansicht' : 'auff-liste')
      if (el && (el.getBoundingClientRect().top < 0 || el.getBoundingClientRect().top > window.innerHeight * 0.6)) el.scrollIntoView({ block: 'start', behavior: 'smooth' })
    })
  }, [such, setSuch, nummern])
  const vorher = neuerer ? () => waehlen(neuerer) : null
  const nachher = aelterer ? () => waehlen(aelterer) : null
  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      const z = e.target as HTMLElement | null
      if (z && (z.closest('input, textarea, select, [contenteditable="true"]') || z.closest('[role="dialog"]'))) return
      if (e.key === 'ArrowDown' && nachher) { e.preventDefault(); nachher() }
      if (e.key === 'ArrowUp' && vorher) { e.preventDefault(); vorher() }
    }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [vorher, nachher])

  const zeigeFall = !!gewaehlt && (breit || !!gefragt || liste.length === 1)
  const alleZu = zahlen.offen + zahlen.abklaerung + zahlen.erledigt
  return (
    <>
      <section className="antwort perigon-antwort" id="auff-antwort">
        <p className="perigon-frage">Welche Messungen passen nicht — und was ist davon schon geklärt?</p>
        <div className="spalten">
          <Kennzahl titel="Offen" wert={`${zahlen.offen} ${zahlen.offen === 1 ? 'Fall' : 'Fälle'}`} ton={zahlen.offen > 0 ? 'kuerbis' : undefined}
                    unter={zahlen.offen > 0 ? 'die neuesten zuoberst' : 'nichts offen'} />
          <Kennzahl titel="In Abklärung" wert={String(zahlen.abklaerung)} unter="in der Halle gefragt" />
          <Kennzahl titel="Erledigt" wert={String(zahlen.erledigt + zahlen.behoben)}
                    unter={zahlen.behoben > 0 ? `${zahlen.behoben} davon korrigiert und nicht mehr in den Daten` : '„so lassen" oder korrigiert'} />
        </div>
        {alleZu > 0 && (
          <div className="perigon-fortschritt" role="img" aria-label={`${zahlen.erledigt + zahlen.behoben} von ${alleZu + zahlen.behoben} erledigt`}>
            <span style={{ width: `${(100 * (zahlen.erledigt + zahlen.behoben)) / (alleZu + zahlen.behoben)}%` }} />
          </div>
        )}
        <p className="leise auff-nummern-zeile">Jeder Fall hat eine Nummer, die bleibt — so lässt er sich im Gespräch nennen: „Auffälligkeit 12".</p>
      </section>
      {vermerkFehler && <Hinweis art="warnung">Der Stand der Fälle liess sich nicht laden: {vermerkFehler}</Hinweis>}
      <div className="perigon-filter" id="auff-filter">
        <Segmente<StandFilter> wahl={stand} setzen={v => setze('stand', v === 'offen' ? '' : v)} id="auff-stand"
                               teile={STAND_FILTER.map(([s, n, id]) => [s, n, id] as const)} />
        <input type="search" aria-label="Suchen" placeholder="Suchen: Nummer, Charge, Arbeit, Sorte …" value={such.get('suche') ?? ''} onChange={e => setze('suche', e.target.value)} />
      </div>
      {arten.length > 1 && (
        <div className="befund-arten" role="group" aria-label="nach Art zeigen" id="auff-arten">
          <button type="button" className={`befund-art${art === '' ? ' an' : ''}`} aria-pressed={art === ''} onClick={() => setze('art', '')}>
            alle <span className="leise">{arten.reduce((s, [, n]) => s + n, 0)}</span></button>
          {arten.map(([a, n]) => (
            <button key={a} type="button" className={`befund-art${art === a ? ' an' : ''}`} aria-pressed={art === a} onClick={() => setze('art', art === a ? '' : a)}>
              {a} <span className="leise">{n}</span>
            </button>
          ))}
        </div>
      )}
      <div className={`postfach${zeigeFall ? ' mit-fall' : ''}`}>
        <div className="postfach-liste" id="auff-liste">
          {liste.length === 0 && (
            <div className="postfach-leer leise">Keine Auffälligkeit{stand === 'offen' ? ' offen' : ''} mit dieser Wahl.{stand === 'offen' ? ' „alle" zeigt auch, was erledigt ist.' : ''}</div>
          )}
          {nachTag(liste).map(g => (
            <section key={g.tag ?? 'ohne'} className="fall-gruppe" aria-label={g.tag ? tagLang(g.tag) : 'ohne Tag'}>
              <h2 className="fall-gruppe-titel"><span>{g.tag ? tagLang(g.tag) : 'ohne Tag'}</span><span className="leise">{g.befunde.length}</span></h2>
              <ul className="fall-liste">
                {g.befunde.map(b => {
                  const k = fallKennung(b)
                  const a = b.auftrag_id ? arbeiten.get(b.auftrag_id) : undefined
                  const s = standDer(b)
                  const aktiv = zeigeFall && gewaehlt != null && fallKennung(gewaehlt) === k
                  return (
                    <li key={k}>
                      <button type="button" className={`fall-zeile s-${ton(b.art)}${aktiv ? ' aktiv' : ''}`} aria-current={aktiv ? 'true' : undefined}
                              onClick={() => waehlen(b)} id={`auff-${nummern.get(k) ?? k.replace(/[^a-z0-9]+/gi, '-')}`}>
                        <span className="fall-zeile-nr" aria-label={nummern.has(k) ? `Auffälligkeit ${nummern.get(k)}` : 'ohne Nummer'}>{nummern.get(k) ?? '·'}</span>
                        <span className="fall-zeile-text">
                          <strong>{artInfo(b.art).titel}</strong>
                          <span className="fall-zeile-unter">Charge {b.charge_nr} · {b.sorte}{b.auftrag_id ? ` · ${taetigkeit(a) ?? 'Arbeit'} ${b.auftrag_id}` : ''}</span>
                        </span>
                        <span className="fall-zeile-rechts">{s !== 'offen' && <AuffStandMarke stand={s} />}</span>
                      </button>
                    </li>
                  )
                })}
              </ul>
            </section>
          ))}
          {stand === 'erledigt' && weg.length > 0 && (
            <section className="fall-gruppe" id="auff-behoben" aria-label="nicht mehr in den Daten">
              <h2 className="fall-gruppe-titel"><span>Nicht mehr in den Daten</span><span className="leise">{weg.length}</span></h2>
              <ul className="fall-liste auff-behoben">
                {weg.map(v => (
                  <li key={v.id} className="auff-behoben-zeile">
                    <span className="fall-zeile-nr">{nummern.get(v.fall) ?? '·'}</span>
                    <span><strong>{String(v.fall.split('|')[0])}</strong> <AuffStandMarke stand={v.stand} />
                      <span className="fall-zeile-unter">{zeitpunkt(v.ts)}{v.profil?.name ? ` · ${v.profil.name}` : ''}{schnappschussText(v)}</span></span>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </div>
        <div className="postfach-fall">
          {gewaehlt && zeigeFall
            ? <AuffAnsicht key={fallKennung(gewaehlt)} b={gewaehlt} nr={nummern.get(fallKennung(gewaehlt)) ?? null}
                           stelle={{ i, n: liste.length }} vorher={vorher} nachher={nachher} zurListe={() => waehlen(undefined)}
                           festhalten={() => { if (!gefragt) waehlen(gewaehlt) }}
                           arbeit={gewaehlt.auftrag_id ? arbeiten.get(gewaehlt.auftrag_id) : undefined}
                           vermerke={vermerke.get(fallKennung(gewaehlt)) ?? []} neuLaden={neuLaden} neuRechnen={neuRechnen}
                           verwandte={befunde.filter(x => x.auftrag_id !== null && x.auftrag_id === gewaehlt.auftrag_id && fallKennung(x) !== fallKennung(gewaehlt))}
                           nummern={nummern} gehe={waehlen} />
            : liste.length > 0 && <p className="leise postfach-leer">Links einen Fall wählen.</p>}
        </div>
      </div>
    </>
  )
}

/** „Mittwoch, 21.10.2026" — der Wochentag hilft, die Arbeit wiederzufinden. */
function tagLang(tag: string): string {
  const d = new Date(`${tag}T12:00:00`)
  return Number.isNaN(d.getTime()) ? tag : d.toLocaleDateString('de-CH', { weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric' })
}

/** Was korrigiert wurde, aus dem Schnappschuss: „Zetteldatum 22.09.2026 → 23.09.2026". */
function schnappschussText(v: AuffVermerk): string {
  const s = v.schnappschuss ?? {}
  const was = typeof s.was === 'string' ? s.was : null
  if (!was || s.vorher == null || s.nachher == null) return v.notiz ? ` · ${v.notiz}` : ''
  const wert = (x: unknown) => was === 'zetteldatum' ? tagText(String(x)) : was === 'zettelgewicht' ? `${x} kg` : x === 'true' ? 'ja' : x === 'false' ? 'nein' : String(x)
  const name = was === 'zetteldatum' ? 'Zetteldatum' : was === 'zettelgewicht' ? 'Zettelgewicht' : '„mit Palette"'
  return ` · ${name} ${wert(s.vorher)} → ${wert(s.nachher)}`
}

/* ---------- Ein Fall ----------------------------------------------------- */

function AuffAnsicht({ b, nr, stelle, vorher, nachher, zurListe, festhalten, arbeit, vermerke, neuLaden, neuRechnen, verwandte, nummern, gehe }: {
  b: Befund; nr: number | null; stelle: { i: number; n: number }
  vorher: (() => void) | null; nachher: (() => void) | null; zurListe: () => void
  /** vor einem Vermerk: den Fall in der Adresse festhalten, damit er nicht wegspringt, wenn er die Liste verlässt */
  festhalten: () => void
  arbeit: ArbeitKurz | undefined; vermerke: AuffVermerk[]
  neuLaden: () => Promise<void>; neuRechnen: () => void
  verwandte: Befund[]; nummern: Map<string, number>; gehe: (b: Befund) => void
}) {
  const info = artInfo(b.art)
  const stand = vermerke[0]?.stand ?? 'offen'
  const [fenster, setFenster] = useState<'arbeit' | 'charge' | null>(null)
  const zettel = useZettelLage(istZettelFall(b) ? b : null)
  const deutung = useMemo(() => zettel.lage ? zettelDeutung(b, zettel.lage) : null, [b, zettel.lage])
  const vorschlag: Vorschlag | null = istZettelFall(b) ? deutung?.vorschlag ?? null : artVorschlag(b)
  const tag = tagIn(b.start_ts)
  const [kopiert, setKopiert] = useState(false)
  return (
    <article className={`fall-ansicht s-${ton(b.art)}`} id="auff-ansicht" aria-labelledby="auff-titel">
      <nav className="fall-nav" aria-label="Von Fall zu Fall">
        <button type="button" className="klein nur-handy" onClick={zurListe} id="auff-zur-liste"><ZZurueck size={14} /> Alle Fälle</button>
        <span className="fall-stelle leise">{stelle.i >= 0 ? `${stelle.i + 1} von ${stelle.n}` : 'nicht mehr in dieser Liste'}</span>
        <span className="fall-nav-knoepfe">
          <button type="button" className="klein" onClick={() => vorher?.()} disabled={!vorher} id="auff-vorher" title="neuerer Fall (Taste ↑)">
            <ZZurueck size={14} /> neuerer</button>
          <button type="button" className="klein" onClick={() => nachher?.()} disabled={!nachher} id="auff-nachher" title="älterer Fall (Taste ↓)">
            älterer <ZChevron size={14} /></button>
        </span>
      </nav>
      <header className="fall-titel">
        <p className="fall-nummer">
          {nr != null ? `Auffälligkeit ${nr}` : 'Auffälligkeit'}
          <button type="button" className="link klein auff-kopieren" id="auff-kopieren" title="die Zeile für den Chat kopieren"
                  onClick={() => { void navigator.clipboard?.writeText(chatZeile(b, nr)).then(() => setKopiert(true), () => setKopiert(false)) }}>
            {kopiert ? 'kopiert' : 'für den Chat kopieren'}</button>
        </p>
        <h2 id="auff-titel"><span className={`punkt s-${ton(b.art)}`} aria-hidden="true" />{info.titel}</h2>
        <p className="fall-unter">
          Charge {b.charge_nr} · {b.sorte}
          {b.auftrag_id ? <> · {taetigkeit(arbeit) ?? 'Arbeit'} {b.auftrag_id}{tag ? ` vom ${tagText(tag)}` : ''}</> : tag ? <> · seit {tagText(tag)}</> : null}
          {' '}<AuffStandMarke stand={stand} />
        </p>
      </header>

      <section className="fall-block" id="auff-passiert">
        <h3>Was ist passiert</h3>
        <p className="auff-befund">{lesbar(b.befund)}</p>
      </section>

      {istZettelFall(b) && <ZettelBild b={b} zettel={zettel} deutung={deutung} />}

      <section className="fall-block" id="auff-wie">
        <h3>Wie kommt es dazu</h3>
        {deutung?.muster && <p className="auff-muster"><span className="muster-marke">{MUSTER_NAME[deutung.muster]}</span></p>}
        <p className="auff-wie">{info.wie}</p>
        <p className="fall-folge"><strong>Für die Zahlen der App:</strong> {info.folge}</p>
      </section>

      <VorschlagBlock b={b} nr={nr} vorschlag={vorschlag} laedt={istZettelFall(b) && !zettel.lage && !zettel.fehler} stand={stand}
                      neuLaden={neuLaden} neuRechnen={neuRechnen} festhalten={festhalten} />

      <StandUndNotiz b={b} nr={nr} vermerke={vermerke} stand={stand} neuLaden={neuLaden} festhalten={festhalten} />

      {verwandte.length > 0 && (
        <section className="fall-block" id="auff-verwandte">
          <h3>Dieselbe Arbeit</h3>
          <ul className="auff-verwandte">
            {verwandte.map(v => (
              <li key={fallKennung(v)}>
                <button type="button" className="link" onClick={() => gehe(v)}>
                  {nummern.has(fallKennung(v)) ? `Auffälligkeit ${nummern.get(fallKennung(v))}` : 'Auffälligkeit'} — {artInfo(v.art).titel}
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      <div className="knopf-reihe auff-wege" style={{ display: 'flex' }}>
        {b.auftrag_id && <button type="button" className="knopf klein" onClick={() => setFenster('arbeit')} id="auff-arbeit">Arbeit ansehen</button>}
        {b.auftrag_id && <Link className="knopf klein" to={`/arbeit/${b.auftrag_id}?korrigieren=1`} id="auff-korrektur">Korrektur der Arbeit</Link>}
        <button type="button" className="knopf klein" onClick={() => setFenster('charge')}>Charge {b.charge_nr}</button>
      </div>
      {fenster === 'arbeit' && b.auftrag_id && <ArbeitFenster auftragId={b.auftrag_id} schliessen={() => setFenster(null)} />}
      {fenster === 'charge' && <ChargeFenster chargeNr={b.charge_nr} schliessen={() => setFenster(null)} />}
    </article>
  )
}

/* ---------- Zettel und Wareneingang ------------------------------------- */

interface ZettelWissen { lage: ZettelLage | null; fehler: string | null }

/** Die Zettel der Arbeit, die Paletten der Charge, die anderen Chargen an den Tagen der Zettel, die Zettel der anderen Arbeiten. */
function useZettelLage(b: Befund | null): ZettelWissen {
  const [w, setW] = useState<ZettelWissen>({ lage: null, fehler: null })
  const a = b?.auftrag_id ?? null
  const c = b?.charge_nr ?? null
  const tag = b ? tagIn(b.start_ts) : null
  useEffect(() => {
    if (a === null || c === null) { setW({ lage: null, fehler: null }); return }
    let lebt = true
    setW({ lage: null, fehler: null })
    void (async () => {
      const spalten = 'id, auftrag_id, eingangsdatum, brutto_zettel_kg, kisten, gebindeart'
      const [z, e, au] = await Promise.all([
        supabase.from('auftrag_palette').select(spalten).eq('auftrag_id', a),
        supabase.from('palette').select('charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart').eq('charge_nr', c),
        supabase.from('auftrag').select('id').eq('charge_nr', c),
      ])
      const fehler = z.error ?? e.error ?? au.error
      if (fehler) { if (lebt) setW({ lage: null, fehler: fehlerText(fehler) }); return }
      const zettel = ((z.data ?? []) as Zettel[]).map(x => ({ ...x, brutto_zettel_kg: x.brutto_zettel_kg === null ? null : Number(x.brutto_zettel_kg) }))
      const tage = [...new Set(zettel.map(x => x.eingangsdatum).filter((x): x is string => !!x))]
      const andereIds = ((au.data ?? []) as { id: number }[]).map(x => x.id).filter(x => x !== a)
      const [f, an] = await Promise.all([
        tage.length ? supabase.from('palette').select('charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart').in('eingangsdatum', tage) : Promise.resolve({ data: [], error: null }),
        andereIds.length ? supabase.from('auftrag_palette').select(spalten).in('auftrag_id', andereIds) : Promise.resolve({ data: [], error: null }),
      ])
      if (!lebt) return
      const zahl = (p: WarePalette) => ({ ...p, brutto_kg: p.brutto_kg === null ? null : Number(p.brutto_kg) })
      setW({
        fehler: null,
        lage: {
          zettel,
          eigen: ((e.data ?? []) as WarePalette[]).map(zahl),
          fremd: ((f.data ?? []) as WarePalette[]).filter(p => p.charge_nr !== c).map(zahl),
          andere: ((an.data ?? []) as Zettel[]).map(x => ({ ...x, brutto_zettel_kg: x.brutto_zettel_kg === null ? null : Number(x.brutto_zettel_kg) })),
          arbeitTag: tag,
        },
      })
    })()
    return () => { lebt = false }
  }, [a, c, tag])
  return w
}

const kgZahl = (x: number | null) => x === null ? '—' : (Number.isInteger(x) ? String(x) : x.toFixed(1))

/**
 * Das Bild: links die Zettel der Arbeit an den Tagen, um die es geht — der
 * Fall hervorgehoben; rechts, was im Wareneingang der Charge an diesen Tagen
 * (und am vorgeschlagenen) steht, gleich schwere Paletten hervorgehoben, und
 * wer sie schon gezählt hat.
 */
function ZettelBild({ b, zettel, deutung }: { b: Befund; zettel: ZettelWissen; deutung: Deutung | null }) {
  if (zettel.fehler) return <Hinweis art="warnung">Die Zettel liessen sich nicht laden: {zettel.fehler}</Hinweis>
  const lage = zettel.lage
  if (!lage || !deutung) return <section className="fall-block" id="auff-daten"><h3>Zettel und Wareneingang</h3><p className="leise">Lädt …</p></section>
  const betroffen = new Set(betroffeneZettel(b, lage.zettel).map(z => z.id))
  const vorschlagIds = new Set(deutung.vorschlag?.ids ?? [])
  const tageZettel = [...new Set(lage.zettel.filter(z => betroffen.has(z.id) || vorschlagIds.has(z.id)).map(z => z.eingangsdatum!).filter(Boolean))].sort()
  const zeilen = lage.zettel.filter(z => z.eingangsdatum && tageZettel.includes(z.eingangsdatum))
    .sort((x, y) => (x.eingangsdatum ?? '').localeCompare(y.eingangsdatum ?? '') || (x.brutto_zettel_kg ?? 0) - (y.brutto_zettel_kg ?? 0))
  const uebrige = lage.zettel.length - zeilen.length
  const gewichte = [...new Set(zeilen.filter(z => betroffen.has(z.id) || vorschlagIds.has(z.id)).map(z => z.brutto_zettel_kg).filter((x): x is number => x !== null))]
  const kandidaten = [...new Set([...betroffen].flatMap(id => deutung.treffer.get(id)?.tage ?? []))]
  const tage = [...new Set([...tageZettel, ...(deutung.vorschlag?.was === 'zetteldatum' && deutung.vorschlag.nachher ? [deutung.vorschlag.nachher] : []), ...kandidaten])].sort().slice(0, 5)
  const fremdeCharge = deutung.muster === 'fremde_charge' ? Number((deutung.vorschlag?.titel.match(/Charge (\d+)/) ?? [])[1]) : null
  const imEingang = (z: Zettel): ReactNode => {
    const tr = deutung.treffer.get(z.id)
    if (!tr) return '—'
    if (tr.genau) return <span className="auff-ja">genau so da</span>
    const teile: string[] = []
    if (tr.tage.length) teile.push(`am ${tr.tage.map(tagText).join(', ')}`)
    if (tr.fremd.length) teile.push(`bei Charge ${tr.fremd.join(', ')}`)
    if (tr.nahe.length) teile.push(`fast: ${[...new Set(tr.nahe.map(p => kgZahl(p.brutto_kg)))].join(', ')} kg`)
    return teile.length ? teile.join(' · ') : <span className="auff-nein">nirgends</span>
  }
  return (
    <section className="fall-block" id="auff-daten">
      <h3>Zettel und Wareneingang</h3>
      <p className="zt-begriff">Oben, was die Halle vom Palettenzettel getippt hat; darunter, was im Wareneingang (Erntejournal) der Charge {b.charge_nr} steht.
        Hervorgehoben: der Fall, und die Paletten, die genau so schwer sind.</p>
      <div className="auff-daten-spalten">
        <div className="rollbar">
          <table className="dicht auff-zettel">
            <caption>Zettel der Arbeit {b.auftrag_id}</caption>
            <thead><tr><th>Zetteldatum</th><th className="zahl">Brutto laut Zettel</th><th className="zahl">Kisten</th><th>im Wareneingang</th></tr></thead>
            <tbody>
              {zeilen.map(z => (
                <tr key={z.id} className={betroffen.has(z.id) ? 'auff-betroffen' : vorschlagIds.has(z.id) ? 'auff-mit' : ''}>
                  <td className="nowrap">{tagText(z.eingangsdatum)}</td>
                  <td className="zahl">{kg(z.brutto_zettel_kg, Number.isInteger(z.brutto_zettel_kg ?? 0) ? 0 : 1)}</td>
                  <td className="zahl">{z.kisten ?? '—'}</td>
                  <td>{imEingang(z)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {uebrige > 0 && <p className="leise auff-mehr">und {uebrige} {uebrige === 1 ? 'Zettel' : 'Zettel'} an anderen Tagen</p>}
        </div>
        <div className="rollbar">
          <table className="dicht auff-eingang">
            <caption>Wareneingang der Charge {b.charge_nr}</caption>
            <thead><tr><th>Eingangstag</th><th className="zahl">Brutto im Wareneingang</th><th className="zahl">Kisten</th><th>schon gezählt</th></tr></thead>
            {tage.map(tag => {
              const amTag = lage.eigen.filter(p => p.eingangsdatum === tag)
              const nah = amTag.filter(p => p.brutto_kg !== null && gewichte.some(w => Math.abs(p.brutto_kg! - w) <= 6))
                .sort((x, y) => (x.brutto_kg ?? 0) - (y.brutto_kg ?? 0))
              return (
                <tbody key={tag} className={tag === deutung.vorschlag?.nachher ? 'auff-tag-vorschlag' : tageZettel.includes(tag) ? 'auff-tag-zettel' : ''}>
                  <tr className="auff-tag-kopf"><th colSpan={4} scope="rowgroup">
                    {tagText(tag)}{tageZettel.includes(tag) ? ' — der Tag auf dem Zettel' : tag === deutung.vorschlag?.nachher ? ' — der vorgeschlagene Tag' : ''}
                    <span className="leise"> · {amTag.length === 0 ? 'keine Palette dieser Charge' : `${amTag.length} ${amTag.length === 1 ? 'Palette' : 'Paletten'}`}</span>
                  </th></tr>
                  {nah.map((p, k) => {
                    const genau = gewichte.some(w => Math.abs((p.brutto_kg ?? -1) - w) < 0.005)
                    const wer = belegtVon(p, lage).filter(z => !(z.auftrag_id === b.auftrag_id && z.eingangsdatum !== tag))
                    return (
                      <tr key={k} className={genau ? 'auff-treffer' : ''}>
                        <td />
                        <td className="zahl">{kg(p.brutto_kg, Number.isInteger(p.brutto_kg ?? 0) ? 0 : 1)}</td>
                        <td className="zahl">{p.kisten ?? '—'}</td>
                        <td>{wer.length ? [...new Set(wer.map(z => `Arbeit ${z.auftrag_id}`))].join(', ') : <span className="leise">frei</span>}</td>
                      </tr>
                    )
                  })}
                  {amTag.length > 0 && nah.length < amTag.length && (
                    <tr className="auff-tag-rest"><td /><td colSpan={3} className="leise">{amTag.length - nah.length} weitere, deutlich anders schwer</td></tr>
                  )}
                </tbody>
              )
            })}
          </table>
        </div>
      </div>
      {fremdeCharge && (
        <p className="auff-fremd">Bei Charge {fremdeCharge} am {tageZettel.map(tagText).join(', ')} genau so schwer: {
          [...new Set(lage.fremd.filter(p => p.charge_nr === fremdeCharge && tageZettel.includes(p.eingangsdatum) && gewichte.some(w => Math.abs((p.brutto_kg ?? -1) - w) < 0.005))
            .map(p => kgZahl(p.brutto_kg)))].join(', ')} kg.</p>
      )}
    </section>
  )
}

/* ---------- Der Vorschlag ---------------------------------------------- */

function VorschlagBlock({ b, nr, vorschlag, laedt, stand, neuLaden, neuRechnen, festhalten }: {
  b: Befund; nr: number | null; vorschlag: Vorschlag | null; laedt: boolean; stand: AuffStand
  neuLaden: () => Promise<void>; neuRechnen: () => void; festhalten: () => void
}) {
  const { istAdmin } = useAuth()
  const [frage, setFrage] = useState(false)
  const [laeuft, setLaeuft] = useState(false)
  const [meldung, setMeldung] = useState<{ art: 'gut' | 'warnung'; text: string } | null>(null)
  const fall = fallKennung(b)
  const schnappschuss = { art: b.art, bezug: b.bezug, charge_nr: b.charge_nr, auftrag_id: b.auftrag_id, sorte: b.sorte, start_ts: b.start_ts, befund: b.befund, nr }

  const uebernehmen = async () => {
    if (!vorschlag?.was || !vorschlag.ids || vorschlag.vorher === undefined || vorschlag.nachher === undefined) return
    festhalten()
    setLaeuft(true); setMeldung(null)
    const r = await supabase.rpc('auffaelligkeit_korrigieren', {
      p_fall: fall, p_was: vorschlag.was, p_ids: vorschlag.ids, p_vorher: vorschlag.vorher, p_nachher: vorschlag.nachher,
      p_notiz: vorschlag.titel, p_schnappschuss: schnappschuss,
    })
    setLaeuft(false); setFrage(false)
    if (r.error) { setMeldung({ art: 'warnung', text: fehlerText(r.error) }); return }
    setMeldung({ art: 'gut', text: 'Übernommen. Die App rechnet neu — stimmt es jetzt, verschwindet die Auffälligkeit aus der Liste (unter „erledigt" bleibt sie stehen).' })
    await neuLaden()
    neuRechnen()
  }
  const vermerken = async (s: 'so_lassen' | 'in_abklaerung', notiz: string) => {
    festhalten()
    setLaeuft(true); setMeldung(null)
    const r = await supabase.from('auffaelligkeit_vermerk').insert({ fall, stand: s, notiz, schnappschuss })
    setLaeuft(false)
    if (r.error) { setMeldung({ art: 'warnung', text: fehlerText(r.error) }); return }
    setMeldung({ art: 'gut', text: `Vermerkt: ${AUFF_STAND_NAME[s]}.` })
    await neuLaden()
  }

  if (laedt) return <section className="fall-block auff-vorschlag" id="auff-vorschlag"><h3>Vorschlag</h3><p className="leise">Die App sieht sich die Zettel an …</p></section>
  return (
    <section className={`fall-block auff-vorschlag v-${vorschlag?.art ?? 'keiner'}`} id="auff-vorschlag">
      <h3>Vorschlag</h3>
      {!vorschlag ? <p className="leise">Die App hat keinen{b.auftrag_id ? ' — in der Korrektur der Arbeit prüfen, oder' : ';'} vermerken, wie es steht.</p> : (
        <>
          <p className="auff-vorschlag-titel">
            <strong>{vorschlag.titel}</strong>
            {vorschlag.sicher && <span className={`sicher-marke s-${vorschlag.sicher}`}>{vorschlag.sicher}</span>}
          </p>
          <ul className="auff-warum">{vorschlag.warum.map((w, k) => <li key={k}>{w}</li>)}</ul>
          {!istZettelFall(b) && b.rat && <p className="auff-rat"><strong>Rat der Prüfung:</strong> {lesbar(b.rat)}</p>}
          {vorschlag.danach && <p className="leise auff-danach">{vorschlag.danach}</p>}
          {stand === 'korrigiert' ? (!meldung && <p className="leise">Übernommen — die App rechnet neu.</p>) : !istAdmin ? <p className="leise">Übernehmen kann der Betriebsleiter.</p> : (
            <div className="knopf-reihe auff-entscheid" style={{ display: 'flex' }}>
              {vorschlag.art === 'korrigieren' && !frage && (
                <button type="button" className="knopf haupt klein" id="auff-uebernehmen" disabled={laeuft} onClick={() => setFrage(true)}>Übernehmen …</button>
              )}
              {vorschlag.art === 'korrigieren' && frage && (
                <span className="auff-frage" role="group" aria-label="Wirklich übernehmen?">
                  <span>{vorschlag.titel}?</span>
                  <button type="button" className="knopf haupt klein" id="auff-ja" disabled={laeuft} onClick={() => void uebernehmen()}>{laeuft ? 'Übernimmt …' : 'Ja, übernehmen und neu rechnen'}</button>
                  <button type="button" className="knopf klein" disabled={laeuft} onClick={() => setFrage(false)}>Abbrechen</button>
                </span>
              )}
              {vorschlag.art === 'so_lassen' && stand !== 'so_lassen' && (
                <button type="button" className="knopf haupt klein" id="auff-so-lassen" disabled={laeuft} onClick={() => void vermerken('so_lassen', vorschlag.titel)}>So lassen</button>
              )}
              {vorschlag.art === 'von_hand' && vorschlag.wo === 'arbeit' && b.auftrag_id && (
                <Link className="knopf klein" to={`/arbeit/${b.auftrag_id}?korrigieren=1`}>Korrektur der Arbeit öffnen</Link>
              )}
              {vorschlag.art === 'von_hand' && vorschlag.wo === 'perigon' && (
                <Link className="knopf klein" to={`/perigon/faelle?charge=${b.charge_nr}&stand=alle`}>Im Reiter Perigon</Link>
              )}
              {stand !== 'in_abklaerung' && (
                <button type="button" className="knopf klein" id="auff-abklaeren" disabled={laeuft}
                        onClick={() => void vermerken('in_abklaerung', vorschlag.art === 'korrigieren' ? `Nicht übernommen: ${vorschlag.titel}` : 'in der Halle nachfragen')}>
                  {vorschlag.art === 'korrigieren' ? 'Nicht übernehmen — in Abklärung' : 'In Abklärung'}</button>
              )}
            </div>
          )}
        </>
      )}
      {meldung && <Hinweis art={meldung.art}>{meldung.text}</Hinweis>}
    </section>
  )
}

/* ---------- Stand und Notiz -------------------------------------------- */

const STAND_WAHL: [AuffStand, string, string][] = [
  ['in_abklaerung', 'in Abklärung', 'auff-stand-abklaerung'], ['so_lassen', 'so lassen', 'auff-stand-so-lassen'], ['offen', 'wieder offen', 'auff-stand-offen'],
]

function StandUndNotiz({ b, nr, vermerke, stand, neuLaden, festhalten }: {
  b: Befund; nr: number | null; vermerke: AuffVermerk[]; stand: AuffStand; neuLaden: () => Promise<void>; festhalten: () => void
}) {
  const { istAdmin } = useAuth()
  const [auf, setAuf] = useState(false)
  const [wahl, setWahl] = useState<AuffStand>(stand === 'in_abklaerung' ? 'so_lassen' : 'in_abklaerung')
  const [notiz, setNotiz] = useState('')
  const [laeuft, setLaeuft] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const vermerken = async () => {
    festhalten()
    setLaeuft(true); setFehler(null)
    const r = await supabase.from('auffaelligkeit_vermerk').insert({
      fall: fallKennung(b), stand: wahl, notiz: notiz.trim() || null,
      schnappschuss: { art: b.art, bezug: b.bezug, charge_nr: b.charge_nr, auftrag_id: b.auftrag_id, sorte: b.sorte, start_ts: b.start_ts, befund: b.befund, nr },
    })
    setLaeuft(false)
    if (r.error) { setFehler(fehlerText(r.error)); return }
    setNotiz(''); setAuf(false)
    await neuLaden()
  }
  return (
    <section className="verfolgen" id="auff-verfolgen" aria-label="Stand und Notiz">
      <h3>Stand und Notiz</h3>
      {vermerke.length === 0 ? <p className="leise verfolgen-leer">Noch nichts vermerkt.</p> : (
        <ol className="verfolgen-liste">
          {vermerke.map(v => (
            <li key={v.id}>
              <span className="nowrap leise">{zeitpunkt(v.ts)}</span>
              {v.profil?.name && <span className="leise"> · {v.profil.name}</span>}
              {' '}<AuffStandMarke stand={v.stand} />
              <span className="verfolgen-notiz">{schnappschussText({ ...v, notiz: v.notiz })}</span>
            </li>
          ))}
        </ol>
      )}
      {istAdmin && !auf && <button type="button" className="klein" id="auff-vermerken-auf" onClick={() => setAuf(true)}>Vermerken …</button>}
      {istAdmin && auf && (
        <form className="verfolgen-form" onSubmit={e => { e.preventDefault(); void vermerken() }}>
          <Segmente<AuffStand> wahl={wahl} setzen={setWahl} id="auff-stand-wahl" teile={STAND_WAHL.map(([s, n, id]) => [s, n, id] as const)} />
          <textarea value={notiz} onChange={e => setNotiz(e.target.value)} maxLength={2000} rows={2} aria-label="Notiz zum Fall"
                    placeholder="Was ist besprochen? Wen gefragt? Warum so lassen …" />
          <button type="submit" className="knopf haupt klein" id="auff-vermerken" disabled={laeuft}>{laeuft ? 'Vermerkt …' : 'Vermerken'}</button>
        </form>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </section>
  )
}
