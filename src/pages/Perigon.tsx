/**
 * Reiter Perigon (0126) — wo Perigon etwas anderes sagt als Erntejournal und
 * Halle, Fall für Fall nachvollziehbar und mitverfolgt.
 *
 * Der Betrieb, 24. Oktober: „mach einen neuen Reiter und behandle dort die
 * Ungereimtheiten mit viel Detail, mit viel Rückverfolgbarkeit, so dass man
 * es nachvollziehen kann — was sind die Fehler —, dass man sie anklicken und
 * dann auch mitverfolgen kann."
 *
 * Runde BD: „überfordert gerade noch" — eine Liste, ein Fenster je Fall.
 * Runde BF, am selben Tag: „Es ist irgendwie Information Overload. Mach es
 * angenehmer … damit ich Fall für Fall angenehm abarbeiten kann. Den Fall
 * verstehe, sehe, was passiert ist." Jetzt:
 *  Fälle   — links die Liste (ein Fall ist eine Frage an den Chef: alles zu
 *            einer Charge, alle Perigon-Zeilen einer Art, eine Sache im
 *            Register), jeder mit seiner Nummer; rechts der Fall: was passiert
 *            ist, das Bild, die Belege, Stand und Notiz; ‹ › oder die
 *            Pfeiltasten von Fall zu Fall. Auf dem Handy erst die Liste, dann
 *            der Fall. „Je Sorte" ist im Fall aufgegangen (was die App
 *            vermutet), „Wo zu tun" in der Erklärung jeder Art.
 *  Verlauf — was vermerkt ist, was nicht mehr in den Daten steht.
 *  So prüft die App — die Dateien, die Spalten, jede Prüfung.
 */
import { Fragment, useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { datum, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Herkunft, Hinweis, Karte, Kennzahl, Segmente } from '../components/Bausteine'
import { useAuswertung, type Auswertung, type PerigonStand, type PerigonVerlauf, type VermerkStand } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { ART_NAME, ungereimtheiten } from '../auswertung/ungereimt'
import { ART_FOLGE, PERIGON_ART, STAND_NAME, WO_NAME, jeSorte, schnappschussText, spaltenZeichen, type SorteFall } from '../auswertung/perigon'
import { FALL_FILTER_LEER, THEMA_FOLGE, THEMA_NAME, faelleBilden, faelleFiltern, fallOffen, fallStand, type Fall, type FallFilter } from '../auswertung/faelle'
import { FallAnsicht } from '../auswertung/FallAnsicht'
import { StandMarke, VerlaufKontext, useVerlauf } from '../auswertung/Verfolgen'

type Teil = 'faelle' | 'verlauf' | 'pruefung'
const TEILE: [Teil, string][] = [
  ['faelle', 'Fälle'],
  ['verlauf', 'Verlauf'],
  ['pruefung', 'So prüft die App'],
]
/** Bis Runde BD hiessen die Fälle „Übersicht" und „Perigon-Zeilen", bis Runde BE gab es „Je Sorte" — Verweise von dort führen in die Fälle. */
const ALT: Record<string, Teil> = { uebersicht: 'faelle', zeilen: 'faelle', sorten: 'faelle' }

interface ChargeKurz { nr: number; sorte: string; schlag: string; perigon_nr: number | null }

export default function Perigon() {
  const { teil } = useParams()
  const navigate = useNavigate()
  const [such] = useSearchParams()
  const aktiv: Teil = TEILE.find(([t]) => t === teil)?.[0] ?? ALT[teil ?? ''] ?? 'faelle'
  const a = useAuswertung()
  const { daten, laedt, fehler, fortschritt } = a
  const wissen = useVerlauf()
  const [stand, setStand] = useState<PerigonStand[] | null>(null)
  const [chargen, setChargen] = useState<ChargeKurz[]>([])

  useEffect(() => {
    let lebt = true
    void (async () => {
      const [s, c] = await Promise.all([
        supabase.from('v_perigon_stand').select('*').order('quelle'),
        supabase.from('charge').select('nr, sorte, schlag, perigon_nr').order('nr'),
      ])
      if (!lebt) return
      setStand(s.error ? [] : ((s.data ?? []) as PerigonStand[]))
      setChargen(c.error ? [] : ((c.data ?? []) as ChargeKurz[]))
    })()
    return () => { lebt = false }
  }, [])
  // „Je Sorte" gibt es nicht mehr: die Sorte wird ein Filter der Fälle
  useEffect(() => {
    if (teil === 'sorten') navigate(`/perigon/faelle${such.get('sorte') ? `?sorte=${encodeURIComponent(such.get('sorte')!)}&stand=alle` : ''}`, { replace: true })
  }, [teil, such, navigate])

  const kopf = daten
    ? <Reiterkopf titel="Perigon" stand={daten.stand} heute={daten.heute} neuRechnen={() => void a.neuRechnen()} laeuft={laedt}
                  zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
    : <div className="seitenkopf"><div><h1>Perigon</h1></div></div>
  if (laedt && !daten) return <>{kopf}<Rechnet fortschritt={fortschritt} /></>
  if (fehler) return <>{kopf}<Hinweis art="warnung">{fehler}</Hinweis></>
  if (!daten) return kopf
  if (!daten.vollstaendig) return <>{kopf}<Rechnet fortschritt={fortschritt} /></>

  return (
    <VerlaufKontext.Provider value={wissen}>
      {kopf}
      <Probleme liste={daten.probleme} />
      {wissen.fehler && <Hinweis art="warnung">Der Stand der Fälle liess sich nicht laden: {wissen.fehler}</Hinweis>}
      <Inhalt daten={daten} stand={stand} chargen={chargen} aktiv={aktiv} verlauf={wissen.verlauf}
              gehe={(t, q) => navigate(`/perigon/${t}${q ? `?${q}` : ''}`)} />
    </VerlaufKontext.Provider>
  )
}

/**
 * Runde BF: die Nummern der Fälle (0127) — vergeben in der Folge der Liste,
 * danach fest. Fehlt die Funktion (Datenbank vor 0127), stehen die Fälle ohne
 * Nummer da; sonst ändert sich nichts.
 */
function useFallNummern(faelle: Fall[]): Map<string, number> {
  const [nummern, setNummern] = useState<Map<string, number>>(new Map())
  const kennung = faelle.map(f => f.id).join('|')
  useEffect(() => {
    if (!kennung) return
    let lebt = true
    void (async () => {
      const r = await supabase.rpc('perigon_fall_nummern', { p_faelle: kennung.split('|') })
      if (!lebt || r.error) return
      setNummern(new Map(((r.data ?? []) as { fall: string; nr: number }[]).map(x => [x.fall, Number(x.nr)])))
    })()
    return () => { lebt = false }
  }, [kennung])
  return nummern
}

function Inhalt({ daten, stand, chargen, aktiv, verlauf, gehe }: {
  daten: Auswertung; stand: PerigonStand[] | null; chargen: ChargeKurz[]; aktiv: Teil
  verlauf: Map<string, PerigonVerlauf>; gehe: (t: Teil, q?: string) => void
}) {
  // Die Sachen je Charge (v_ungereimtheit) — ohne die Perigon-Zeilen: die stehen je Position.
  const sachen = useMemo(() => ungereimtheiten(daten.ungereimt), [daten.ungereimt])
  const faelle = useMemo(() => faelleBilden(daten.perigon, sachen, daten.spur), [daten.perigon, sachen, daten.spur])
  const nummern = useFallNummern(faelle)
  const sorten = useMemo(() => new Map(jeSorte(daten.spur, sachen, daten.perigon, chargen).map(s => [s.sorte, s])), [daten.spur, sachen, daten.perigon, chargen])
  const zahlen = useMemo(() => {
    const offen = faelle.filter(f => fallOffen(f, verlauf))
    return {
      offen: offen.length, rot: offen.filter(f => f.schwere === 'rot').length,
      abklaerung: faelle.filter(f => fallStand(f, verlauf) === 'in_abklaerung').length,
      erledigt: faelle.filter(f => f.teile.length > 0 && ['erledigt', 'kein_fehler'].includes(fallStand(f, verlauf))).length,
      behoben: [...verlauf.values()].filter(v => v.weg_seit != null).length,
    }
  }, [faelle, verlauf])
  const bis = stand?.reduce<string | null>((m, s) => (s.bis && (!m || s.bis > m) ? s.bis : m), null) ?? null
  const alleZu = zahlen.offen + zahlen.erledigt
  return (
    <>
      {/* Runde BA: die Frage des Reiters, die Antwort zuoberst. Runde BF: gezählt werden Fälle — Fragen an den Chef —, nicht Zeilen. */}
      <section className="antwort perigon-antwort" id="perigon-antwort">
        <p className="perigon-frage">Was stimmt in Perigon nicht — und was ist davon schon geklärt?</p>
        <div className="spalten">
          <Kennzahl titel="Offen" wert={`${zahl(zahlen.offen)} ${zahlen.offen === 1 ? 'Fall' : 'Fälle'}`} ton={zahlen.rot > 0 ? 'rot' : undefined}
                    unter={zahlen.offen > 0
                      ? (zahlen.rot > 0
                        ? <>{zahl(zahlen.rot)} davon gross (ab 500 kg)<Herkunft art="gerechnet" text="je Fall die Masse, um die es geht — aus Datei und Lieferscheinen gemessen, „mehr verkauft als möglich“ mit dem gerechneten Verlust" /></>
                        : 'alle klein')
                      : 'nichts offen'} />
          <Kennzahl titel="In Abklärung" wert={zahl(zahlen.abklaerung)} unter="gemeldet, Antwort ausstehend" />
          <Kennzahl titel="Erledigt" wert={zahl(zahlen.erledigt)}
                    unter={zahlen.behoben > 0 ? `${zahl(zahlen.behoben)} ${zahlen.behoben === 1 ? 'Zeile' : 'Zeilen'} nicht mehr in den Daten` : 'erledigt oder „kein Fehler" vermerkt'} />
        </div>
        {alleZu > 0 && (
          <div className="perigon-fortschritt" role="img" aria-label={`${zahlen.erledigt} von ${alleZu} Fällen erledigt`}>
            <span style={{ width: `${(100 * zahlen.erledigt) / alleZu}%` }} />
          </div>
        )}
        <p className="leise perigon-dateien-zeile">
          {stand === null ? '' : stand.length === 0 ? 'Noch keine Perigon-Datei eingelesen.'
            : <>Perigon-Lieferscheine bis {bis ? datum(bis) : '—'} · {stand.length} {stand.length === 1 ? 'Datei' : 'Dateien'} eingelesen ·{' '}
                <button type="button" className="link" onClick={() => gehe('pruefung')}>die Dateien</button></>}
        </p>
      </section>
      <nav className="navleiste unter" aria-label="Perigon">
        {TEILE.map(([t, name]) => (
          <a key={t} href={`/perigon/${t}`} className={aktiv === t ? 'aktiv' : ''} id={`perigon-teil-${t}`}
             onClick={e => { e.preventDefault(); gehe(t) }}>
            {name}
            {t === 'faelle' && zahlen.offen > 0 && <span className="reiter-zahl">{zahlen.offen}</span>}
          </a>
        ))}
      </nav>
      <div className="wechsel" key={aktiv}>
        {aktiv === 'faelle' && <Arbeitsliste faelle={faelle} nummern={nummern} verlauf={verlauf} daten={daten} sorten={sorten} />}
        {aktiv === 'verlauf' && <Verlauf faelle={faelle} nummern={nummern} verlauf={verlauf} />}
        {aktiv === 'pruefung' && <SoPrueft stand={stand} />}
      </div>
    </>
  )
}

/* ---------- Fälle: die Liste und der Fall ------------------------------- */

/** Breit genug für Liste und Fall nebeneinander? Sonst erst die Liste, dann der Fall. */
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

/** Die Kennung eines Falls in der Adresse: seine Nummer, sonst die Kennung der App. */
const inAdresse = (f: Fall, nummern: Map<string, number>) => String(nummern.get(f.id) ?? f.id)

function Arbeitsliste({ faelle, nummern, verlauf, daten, sorten }: {
  faelle: Fall[]; nummern: Map<string, number>; verlauf: Map<string, PerigonVerlauf>; daten: Auswertung; sorten: Map<string, SorteFall>
}) {
  const [such, setSuch] = useSearchParams()
  const breit = useBreit()
  const filter: FallFilter = {
    ...FALL_FILTER_LEER,
    art: such.get('art') ?? '', sorte: such.get('sorte') ?? '', suche: such.get('suche') ?? '',
    stand: (['offen', 'abklaerung', 'erledigt', 'alle'].includes(such.get('stand') ?? '') ? such.get('stand') : 'offen') as FallFilter['stand'],
    charge: such.get('charge') ? Number(such.get('charge')) : null,
  }
  const setze = (k: string, v: string) => {
    const neu = new URLSearchParams(such)
    if (v) neu.set(k, v); else neu.delete(k)
    setSuch(neu, { replace: true })
  }
  const schluessel = [filter.art, filter.sorte, filter.suche, filter.stand, filter.charge].join('|')
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const liste = useMemo(() => faelleFiltern(faelle, verlauf, filter), [faelle, verlauf, schluessel])
  const spur = useMemo(() => new Map(daten.spur.map(s => [s.charge_nr, s])), [daten.spur])
  const gefragt = such.get('fall')
  const gewaehlt = (gefragt ? faelle.find(f => inAdresse(f, nummern) === gefragt || f.id === gefragt) : undefined)
    ?? (liste.length === 1 || (breit && liste.length > 0) ? liste[0] : undefined)
  const i = gewaehlt ? liste.findIndex(f => f.id === gewaehlt.id) : -1
  const waehlen = useCallback((f: Fall | undefined) => {
    const neu = new URLSearchParams(such)
    if (f) neu.set('fall', inAdresse(f, nummern)); else neu.delete('fall')
    setSuch(neu, { replace: !!f && !!such.get('fall') })
    window.requestAnimationFrame(() => {
      const el = document.getElementById(f ? 'fall-ansicht' : 'fall-liste')
      if (el && (el.getBoundingClientRect().top < 0 || el.getBoundingClientRect().top > window.innerHeight * 0.6)) el.scrollIntoView({ block: 'start', behavior: 'smooth' })
    })
  }, [such, setSuch, nummern])
  const vorher = i > 0 ? () => waehlen(liste[i - 1]) : null
  const nachher = i >= 0 && i < liste.length - 1 ? () => waehlen(liste[i + 1]) : null
  // Von Fall zu Fall mit den Pfeiltasten — nicht, während man schreibt
  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null
      if (t && (t.closest('input, textarea, select, [contenteditable="true"]') || t.closest('[role="dialog"]'))) return
      if (e.key === 'ArrowRight' && nachher) { e.preventDefault(); nachher() }
      if (e.key === 'ArrowLeft' && vorher) { e.preventDefault(); vorher() }
    }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [vorher, nachher])

  const chips: [string, string][] = [
    ...(filter.art ? [['art', `Art: ${ART_NAME[filter.art] ?? filter.art}`] as [string, string]] : []),
    ...(filter.sorte ? [['sorte', `Sorte: ${filter.sorte}`] as [string, string]] : []),
    ...(filter.charge != null ? [['charge', `Charge ${filter.charge}`] as [string, string]] : []),
  ]
  const zeigeFall = !!gewaehlt && (breit || !!gefragt || liste.length === 1)
  return (
    <>
      <div className="perigon-filter" id="perigon-filter">
        <Segmente<FallFilter['stand']> wahl={filter.stand} setzen={v => setze('stand', v === 'offen' ? '' : v)} id="perigon-stand"
                                       teile={[['offen', 'offen', 'filter-offen'], ['abklaerung', 'in Abklärung', 'filter-abklaerung'], ['erledigt', 'erledigt', 'filter-erledigt'], ['alle', 'alle', 'filter-alle']]} />
        <input type="search" aria-label="Suchen" placeholder="Suchen: Charge, Kunde, Artikel, Position …" value={filter.suche} onChange={e => setze('suche', e.target.value)} />
        {chips.map(([k, text]) => <button key={k} type="button" className="klein filter-chip" onClick={() => setze(k, '')} aria-label={`${text} — Filter weg`}>{text} ✕</button>)}
      </div>
      <div className={`postfach${zeigeFall ? ' mit-fall' : ''}`}>
        <div className="postfach-liste" id="fall-liste">
          {liste.length === 0
            ? <Karte><p className="leise">Keine Fälle{filter.stand === 'offen' ? ' offen' : ''} mit dieser Wahl.{filter.stand === 'offen' ? ' „alle" zeigt auch, was erledigt ist.' : ''}</p></Karte>
            : THEMA_FOLGE.filter(t => liste.some(f => f.thema === t)).map(t => {
              const hier = liste.filter(f => f.thema === t)
              return (
                <section key={t} className="fall-gruppe" id={`thema-${t}`} aria-label={THEMA_NAME[t]}>
                  <h2 className="fall-gruppe-titel">{THEMA_NAME[t]} <span className="leise">{hier.length}</span></h2>
                  <ul className="fall-liste">
                    {hier.map(f => <FallZeile key={f.id} f={f} nr={nummern.get(f.id) ?? null} aktiv={gewaehlt?.id === f.id && zeigeFall}
                                             stand={fallStand(f, verlauf)} waehlen={() => waehlen(f)} />)}
                  </ul>
                </section>
              )
            })}
        </div>
        <div className="postfach-fall">
          {gewaehlt && zeigeFall
            ? <FallAnsicht key={gewaehlt.id} fall={gewaehlt} nr={nummern.get(gewaehlt.id) ?? null} stelle={{ i: Math.max(i, 0), n: liste.length }}
                           vorher={vorher} nachher={nachher} zurListe={() => waehlen(undefined)} spur={spur}
                           sorte={gewaehlt.sorte ? sorten.get(gewaehlt.sorte) ?? null : null} />
            : liste.length > 0 && <p className="leise postfach-leer">Links einen Fall wählen.</p>}
        </div>
      </div>
    </>
  )
}

/** Ein Fall in der Liste: Nummer, wer, in wenigen Worten was nicht aufgeht, wie viel, der Stand. */
function FallZeile({ f, nr, aktiv, stand, waehlen }: { f: Fall; nr: number | null; aktiv: boolean; stand: VermerkStand; waehlen: () => void }) {
  return (
    <li>
      <button type="button" className={`fall-zeile s-${f.schwere}${aktiv ? ' aktiv' : ''}`} aria-current={aktiv ? 'true' : undefined} onClick={waehlen}
              id={`fall-${f.id.replace(/[^a-z0-9]+/gi, '-')}`}>
        <span className="fall-zeile-nr" aria-label={nr != null ? `Fall ${nr}` : 'Fall ohne Nummer'}>{nr ?? '·'}</span>
        <span className="fall-zeile-text">
          <strong>{f.titel}</strong>
          <span className="fall-zeile-unter">{f.unter}</span>
        </span>
        <span className="fall-zeile-rechts">
          {f.kg != null && f.kg > 0 && <span className="fall-zeile-kg">{tonnen(f.kg)}</span>}
          {stand !== 'offen' && <StandMarke stand={stand} />}
        </span>
      </button>
    </li>
  )
}

/* ---------- Die Dateien -------------------------------------------------- */

function DateienKarte({ stand }: { stand: PerigonStand[] | null }) {
  if (stand === null) return null
  const ohneRoh = stand.reduce((a, s) => a + s.ohne_roh, 0)
  return (
    <Karte titel="Die Perigon-Dateien" id="perigon-dateien">
      {stand.length === 0 ? <p className="leise">Noch keine Perigon-Datei eingelesen — unter <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link>.</p> : (
        <div className="rollbar">
          <table className="dicht">
            <thead><tr><th>Firma</th><th className="zahl">Zeilen</th><th className="zahl">Positionen</th><th>Lieferscheine</th><th>zuletzt eingelesen</th>
              <th className="zahl">ohne Charge</th><th className="zahl">Fälle offen</th></tr></thead>
            <tbody>{stand.map(s => (
              <tr key={s.quelle}>
                <td>{s.name}</td><td className="zahl">{zahl(s.zeilen)}</td><td className="zahl">{zahl(s.positionen)}</td>
                <td className="nowrap">{s.von ? `${datum(s.von)} – ${datum(s.bis)}` : '—'}</td>
                <td>{s.zuletzt_geladen ? zeitpunkt(s.zuletzt_geladen) : '—'}{s.letzte_datei && <span className="zelle-unter leise">{s.letzte_datei}{s.letzte_bis ? `, bis ${datum(s.letzte_bis)}` : ''}</span>}</td>
                <td className="zahl">{tonnen(s.kg_ohne_charge ?? 0)}</td>
                <td className="zahl">{zahl(s.faelle)}</td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      )}
      {ohneRoh > 0 && (
        <Hinweis art="info">{zahl(ohneRoh)} {ohneRoh === 1 ? 'Position hat' : 'Positionen haben'} ihre ganze Zeile noch nicht in der App. Die Datei
          unter <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link> neu einlesen, dann zeigt jedes Fenster die Zeile wie im Excel.</Hinweis>
      )}
    </Karte>
  )
}

/* ---------- Verlauf ------------------------------------------------------ */

interface VermerkZeile { id: number; schluessel: string; stand: VermerkStand; notiz: string | null; ts: string; schnappschuss: Record<string, unknown> | null; profil?: { name: string } | null }

function Verlauf({ faelle, nummern, verlauf }: { faelle: Fall[]; nummern: Map<string, number>; verlauf: Map<string, PerigonVerlauf> }) {
  const navigate = useNavigate()
  const [roh, setRoh] = useState<VermerkZeile[] | null>(null)
  useEffect(() => {
    let lebt = true
    void (async () => {
      const r = await supabase.from('perigon_vermerk').select('id, schluessel, stand, notiz, ts, schnappschuss, profil(name)')
        .order('ts', { ascending: false }).order('id', { ascending: false }).limit(2000)
      if (lebt) setRoh(r.error ? [] : ((r.data ?? []) as unknown as VermerkZeile[]))
    })()
    return () => { lebt = false }
  }, [verlauf])
  const fallVonTeil = new Map(faelle.flatMap(f => f.teile.map(t => [t, f] as const)))
  const oeffnen = (f: Fall) => navigate(`/perigon/faelle?fall=${encodeURIComponent(inAdresse(f, nummern))}&stand=alle`)
  const fallKnopf = (f: Fall) => (
    <button type="button" className="link" onClick={() => oeffnen(f)}>{nummern.has(f.id) ? `Fall ${nummern.get(f.id)} · ` : ''}{f.titel}</button>)
  const titel = (schluessel: string, s: Record<string, unknown> | null): ReactNode => {
    const f = fallVonTeil.get(schluessel)
    if (f) return fallKnopf(f)
    return <span>{schnappschussText(s ?? verlauf.get(schluessel)?.schnappschuss)} <span className="leise">(nicht mehr in den Daten)</span></span>
  }
  // Runde BF: was in einem Zug für alle Teile eines Falls vermerkt wurde, steht einmal da
  const vermerke = roh === null ? null : (() => {
    const m = new Map<string, VermerkZeile & { teile: number }>()
    for (const v of roh) {
      const k = `${v.ts}|${v.stand}|${v.notiz ?? ''}|${v.profil?.name ?? ''}|${fallVonTeil.get(v.schluessel)?.id ?? v.schluessel}`
      const da = m.get(k)
      if (da) da.teile += 1; else m.set(k, { ...v, teile: 1 })
    }
    return [...m.values()]
  })()
  const weg = [...verlauf.values()].filter(v => v.weg_seit != null).sort((a, b) => (b.weg_seit ?? '').localeCompare(a.weg_seit ?? ''))
  const wartet = faelle.filter(f => f.teile.length > 0 && fallStand(f, verlauf) === 'erledigt')
  return (
    <>
      <Karte titel="Was vermerkt ist" id="perigon-vermerke">
        {vermerke === null ? null : vermerke.length === 0
          ? <p className="leise">Noch nichts vermerkt. Unter jedem Fall hält der Betriebsleiter fest, wie es steht — offen, in Abklärung, erledigt
              oder kein Fehler —, mit einer Notiz. Hier steht dann alles in der Folge, in der es geschah.</p>
          : (
            <div className="rollbar">
              <table className="dicht umbruch">
                <thead><tr><th>Wann</th><th>Wer</th><th>Stand</th><th>Notiz</th><th>Fall</th></tr></thead>
                <tbody>{vermerke.map(v => (
                  <tr key={v.id}>
                    <td className="nowrap">{zeitpunkt(v.ts)}</td><td>{v.profil?.name ?? '—'}</td><td><StandMarke stand={v.stand} /></td>
                    <td>{v.notiz ?? <span className="leise">—</span>}</td>
                    <td>{titel(v.schluessel, v.schnappschuss)}{v.teile > 1 && <span className="zelle-unter leise">für {v.teile} Teile</span>}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}
      </Karte>
      {wartet.length > 0 && (
        <Karte titel="Erledigt vermerkt, aber noch in den Daten" id="perigon-wartet">
          <p className="leise oben-0">In Perigon berichtigt — die App sieht es erst, wenn die Datei neu eingelesen und neu gerechnet ist.</p>
          <ul>{wartet.map(f => <li key={f.id}>{fallKnopf(f)}</li>)}</ul>
        </Karte>
      )}
      <Karte titel="Nicht mehr in den Daten" id="perigon-weg">
        {weg.length === 0
          ? <p className="leise">Noch kein Fall verschwunden. Nach jedem Rechnen merkt sich die App, welche Fälle sie sieht; was danach nicht mehr da ist —
              weil Perigon berichtigt und die Datei neu eingelesen wurde —, steht hier, mit dem Tag, an dem sie es zuletzt sah.</p>
          : (
            <div className="rollbar">
              <table className="dicht umbruch">
                <thead><tr><th>Fall</th><th>zuerst gesehen</th><th>nicht mehr seit</th><th>Stand</th></tr></thead>
                <tbody>{weg.map(v => (
                  <tr key={v.schluessel}>
                    <td>{schnappschussText(v.schnappschuss)}{typeof v.schnappschuss?.satz === 'string' && <span className="zelle-unter leise">{v.schnappschuss.satz}</span>}</td>
                    <td className="nowrap">{v.erst_gesehen ? datum(v.erst_gesehen) : '—'}</td>
                    <td className="nowrap">{v.weg_seit ? zeitpunkt(v.weg_seit) : '—'}</td>
                    <td><StandMarke stand={v.stand} />{v.notiz && <span className="zelle-unter leise">{v.notiz}</span>}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}
      </Karte>
    </>
  )
}

/* ---------- So prüft die App --------------------------------------------- */

const SPALTEN_ERKLAERT: [string, string][] = [
  ['AuftragsLieferDatum', 'das Lieferdatum — gegen das Eingangsdatum der Charge im Erntejournal'],
  ['AuftragsLieferant', 'der Kunde'],
  ['AuftragsArtikel', 'der Artikel — daraus Artikelgruppe, Grösse und (ohne Preisgruppe) das Label'],
  ['AuftragsPrsGrpBez', 'die Preisgruppe: D… Demeter, K… und CH-K Knospe'],
  ['AuftragsArtikelMenge', 'die Menge der ganzen Position — auf jeder ihrer Zeilen dieselbe'],
  ['AufPosBatchQuantity Charge', 'die Menge, die diese Zeile ihrer Charge zuteilt'],
  ['AuftragsArtikelEinheit', 'die Einheit: kg oder Stück'],
  ['AuftragsChargeManuell', 'die Chargennummer — unsere vierstellige oder die sechsstellige Perigon-Nummer der Firma'],
  ['LiefProdAdrName', 'der Produzent — über ihn findet die App eine Charge, wenn die Nummer unbekannt ist'],
  ['LiefPrsGrpName', 'das Lieferlabel der Charge (D, K, CH-K)'],
  ['AufPosId', 'die Position — die Kennung, mit der man die Zeile in der Datei findet'],
  ['GewichtProArtikel', 'das Gewicht je Artikel; bei kg-Artikeln mit 0 ist die Menge das Kilo, bei Stück ohne Gewicht bleibt die Masse unbekannt'],
]

const SACHEN_ERKLAERT: [string, string][] = [
  ['ohne_eingang', 'Eine Charge hat Lieferscheine, aber im Erntejournal keine einzige Palette. Die App nennt die Chargen, von denen die Ware wohl kam (derselbe Artikel, noch Paletten da, höchstens die Hälfte verkauft).'],
  ['ueberzaehlung', 'Was unter einer Nummer hinausging, braucht mit dem gerechneten Verlust mehr Eingangsware, als hereinkam (ab 100 kg und 3 %). Auch hier: die Chargen, von denen es wohl kam, und was zu zählen ist.'],
  ['vor_eingang', 'Lieferscheine einer Charge, die älter sind als ihre erste Palette im Journal.'],
  ['ohne_charge', 'Lieferscheine ohne Charge, je Sorte: wie viel, und auf welche Chargen die App sie nach Menge verteilt.'],
  ['vorschlag', 'Die Zettel einer Arbeit passen aufs Kilo zu Paletten einer anderen Charge, aber der Beleg reicht nicht (weniger als 2 Zettel, unter 80 %, oder es geht um die Sorte): ein Vorschlag, nichts gebucht.'],
  ['umgebucht', 'Der Beleg reicht (mindestens 2 Zettel, 80 %, aufs Kilo, ±3 Tage): die Paletten zählen bei der Charge der Arbeit, mit Grund, zurücknehmbar; im Journal bleibt die alte Charge stehen.'],
  ['nachgeordnet', 'Eine unbekannte Nummer, über den Produzenten (Spalte X) eindeutig einer Charge zugeordnet — bei jedem Rechnen neu, bis die Nummer im Register steht.'],
  ['stammdaten', 'Was im Chargenregister selbst nicht stimmt: eine Perigon-Nummer an zwei Chargen, eine Charge ohne Perigon-Nummer, ein Schlag unter zwei Namen.'],
]

function SoPrueft({ stand }: { stand: PerigonStand[] | null }) {
  return (
    <>
      <DateienKarte stand={stand} />
      <Karte titel="Woher die Zahlen kommen" id="perigon-woher">
        <div className="weg-der-ware-schema">
          <div><strong>Herein · Erntejournal</strong><span>jede Palette mit Datum, Brutto, Kisten, Gebinde und Chargennummer</span></div>
          <div aria-hidden="true">→</div>
          <div><strong>In der Halle · App</strong><span>Arbeiten auf einer Charge, mit Zetteln je Palette; Wägungen, Palox</span></div>
          <div aria-hidden="true">→</div>
          <div><strong>Hinaus · Perigon</strong><span>Lieferschein, Artikel, Menge; die Chargennummer und die Menge je Charge</span></div>
        </div>
        <p>Die App sieht nicht in die Halle. Sie rechnet je Charge, was dort stehen müsste: herein laut Erntejournal, hinaus laut Perigon, dazwischen
        die Arbeiten und die Messungen. Die drei Listen hängen nur über die Chargennummer zusammen. Steht in Perigon die falsche Nummer — oder gar
        keine —, stimmt das Lager an zwei Stellen nicht: bei der einen Charge zieht die App Ware ab, die nie von dort kam; bei der anderen bleibt
        Ware auf dem Papier stehen, die längst verkauft ist.</p>
        <p>Jede Firma schickt ihre Perigon-Datei („Abgleich Rückverfolgbarkeit"). In der Chargenspalte steht entweder unsere vierstellige Nummer oder die
        sechsstellige Perigon-Nummer der Firma; die App übersetzt mit dem Chargenregister (Betrieb → Stammdaten → Chargen, Spalte Perigon-Nr.). Eine
        Position steht je Charge einmal da — dreimal, wenn drei Chargen —, mit der Menge der Position auf jeder Zeile und der Menge je Charge daneben.</p>
      </Karte>

      <Karte titel="Die Spalten, auf die es ankommt" id="perigon-spalten">
        <div className="rollbar">
          <table className="dicht umbruch">
            <thead><tr><th>Spalte</th><th>in der Datei</th><th>was die App daraus nimmt</th></tr></thead>
            <tbody>{SPALTEN_ERKLAERT.map(([name, was]) => (
              <tr key={name}><td className="nowrap"><strong>{spaltenZeichen(name) ?? '—'}</strong></td><td className="nowrap">{name}</td><td>{was}</td></tr>
            ))}</tbody>
          </table>
        </div>
        <p className="leise">Eine Zeile in der Datei finden: Excel öffnen, Ctrl+F, die Position (AufPosId) eingeben. Im Fenster jedes Falls steht sie.</p>
      </Karte>

      <Karte titel="Jede Prüfung einer Perigon-Zeile" id="perigon-pruefungen">
        {ART_FOLGE.map(a => {
          const i = PERIGON_ART[a]
          return (
            <section key={a} className="perigon-pruefung-art" id={`pruefung-${a}`}>
              <h3>{i.name} <span className="wo-marke">{WO_NAME[i.wo].kurz}</span></h3>
              <dl className="perigon-art-erklaerung">
                <dt>Was das heisst</dt><dd>{i.heisst}</dd>
                <dt>In der Datei</dt><dd>{i.datei}</dd>
                <dt>Was die App daraus macht</dt><dd>{i.app}</dd>
                <dt>Was tun</dt><dd>{i.tun}</dd>
              </dl>
            </section>
          )
        })}
      </Karte>

      <Karte titel="Jede Prüfung je Charge" id="perigon-pruefungen-charge">
        <dl className="perigon-art-erklaerung">
          {SACHEN_ERKLAERT.map(([art, was]) => <Fragment key={art}><dt>{ART_NAME[art] ?? art}</dt><dd>{was}</dd></Fragment>)}
        </dl>
      </Karte>

      <Karte titel="Was die App bewusst nicht tut" id="perigon-nicht">
        <ul>
          <li><strong>Nicht raten.</strong> Eine Überzählung wird nicht der Schwester-Charge abgezogen; ohne Zettel ist „wohl von dort" eine Vermutung, und so steht sie da.</li>
          <li><strong>Nicht löschen.</strong> Die Charge des Journals bleibt an jeder Palette; eine Umbuchung lässt sich zurücknehmen; ein Vermerk bleibt stehen.</li>
          <li><strong>Einen Vorschlag nicht buchen.</strong> Was die Sorte betrifft, entscheidet, wer zählt.</li>
          <li><strong>Perigon nicht korrigieren.</strong> Die App schreibt nie in Perigon. Was dort falsch steht, bleibt falsch, bis es dort jemand ändert — die App sagt nur, wo.</li>
          <li><strong>Keine Kilo erfinden.</strong> Stück ohne Gewicht sind unbekannt, nie 0; eine Position ohne Menge zählt nirgends.</li>
        </ul>
      </Karte>

      <Karte titel="Wie das Mitverfolgen geht" id="perigon-mitverfolgen">
        <p>Jeder Fall hat einen Schlüssel, der von Rechnen zu Rechnen gleich bleibt: die Art, die Firma, die Position und — bei einer Chargenzeile — die
        Nummer. An ihm hängen zwei Spuren:</p>
        <ul>
          <li><strong>Was der Betriebsleiter festhält</strong> — {(['offen', 'in_abklaerung', 'erledigt', 'kein_fehler'] as VermerkStand[]).map(s => STAND_NAME[s]).join(', ')} —,
            mit einer Notiz, wer und wann. Nur anhängen, nie ändern: der Verlauf ist die Spur.</li>
          <li><strong>Was die App von selbst weiss</strong> — nach jedem fertigen Rechnen, welche Fälle sie sieht: seit wann, und seit wann nicht mehr. Ist ein Fall nach
            dem Neu-Einlesen weg, steht er unter Verlauf → „Nicht mehr in den Daten", mit dem, was er war.</li>
        </ul>
        <p className="leise">„Erledigt" heisst: in Perigon berichtigt. Bis die Datei neu eingelesen ist, steht der Fall noch in den Daten — unter Verlauf als „wartet aufs Einlesen".
          „Kein Fehler" heisst: stimmt so (etwa ein Mix, der wirklich aus einer Charge ist); der Fall zählt dann nicht mehr als offen.</p>
      </Karte>
    </>
  )
}
