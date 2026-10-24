/**
 * Reiter Perigon (0126) — wo Perigon etwas anderes sagt als Erntejournal und
 * Halle, Fall für Fall nachvollziehbar und mitverfolgt.
 *
 * Der Betrieb, 24. Oktober: „mach einen neuen Reiter und behandle dort die
 * Ungereimtheiten mit viel Detail, mit viel Rückverfolgbarkeit, so dass man
 * es nachvollziehen kann — was sind die Fehler —, dass man sie anklicken und
 * dann auch mitverfolgen kann … nicht nur die gerade genannten, sondern alle
 * Perigon-Auffälligkeiten, die bisher bei Artikel oben waren." Und: „alles,
 * was du im PDF hast, dort in den Reiter — das mit 1719 etc."
 *
 * Runde BD, am selben Tag: „an sich in die richtige Richtung — aber er
 * überfordert gerade noch; nutze gutes UI für bessere Verständlichkeit."
 * Dieselben Fälle standen dreimal da (nach Ort, nach Art, nach Charge), jede
 * Zeile mit ihrem ganzen Satz, Je Sorte war zehn Bildschirme lang. Jetzt:
 *  Fälle         — eine Arbeitsliste: je Art des Fehlers eine Zeile, die
 *                  aufklappt; je Fall eine kurze Zeile; ein Klick öffnet den
 *                  Fall im Fenster (nachgerechnet, was tun, mitverfolgen).
 *                  Oben: wo es behoben wird, als Filter.
 *  Je Sorte      — die Sorten als Liste, eine aufgeklappt: das Bild über die
 *                  Sorte, der Weg der Ware je Charge, die Fälle der Sorte.
 *  Verlauf       — was vermerkt ist, was nicht mehr in den Daten steht.
 *  So prüft die App — die Dateien, die Spalten, jede Prüfung, was die App
 *                  bewusst nicht tut.
 * Erklärungen stehen dort, wo man sie sucht (im Fenster, unter „So prüft die
 * App"), nicht in jeder Zeile.
 */
import { Fragment, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { datum, kg, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Herkunft, Hinweis, Karte, Kennzahl, Segmente } from '../components/Bausteine'
import { ZChevron, ZWarnung } from '../components/Zeichen'
import { useAuswertung, type Auswertung, type PerigonBefund, type PerigonStand, type PerigonVerlauf, type VermerkStand } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { ART_NAME, spurText, ungereimtheiten, type Schwere, type Ungereimtheit } from '../auswertung/ungereimt'
import {
  ART_FOLGE, FILTER_LEER, PERIGON_ART, SACHE_HEISST, STAND_NAME, WO_FOLGE, WO_NAME, aufgaben, betroffen, fallKurz, fallTitel, filtern, istOffen, jeSorte,
  lageInZahlen, nachArt, sachenFiltern, sachenNachArt, schnappschussText, spaltenZeichen, standVon, type Filter, type SorteFall, type StandFilter, type Wo,
} from '../auswertung/perigon'
import { SacheFenster } from '../auswertung/Ungereimtheiten'
import { OhneChargeListe } from '../auswertung/OhneCharge'
import { StandMarke, VerlaufKontext, useVerlauf } from '../auswertung/Verfolgen'
import { LieferungFenster } from '../betrieb/LieferungFenster'

type Teil = 'faelle' | 'sorten' | 'verlauf' | 'pruefung'
const TEILE: [Teil, string][] = [
  ['faelle', 'Fälle'],
  ['sorten', 'Je Sorte'],
  ['verlauf', 'Verlauf'],
  ['pruefung', 'So prüft die App'],
]
/** Bis Runde BD hiessen die Fälle „Übersicht" und „Perigon-Zeilen" — Verweise von dort führen in die Fälle. */
const ALT: Record<string, Teil> = { uebersicht: 'faelle', zeilen: 'faelle' }

interface ChargeKurz { nr: number; sorte: string; schlag: string; perigon_nr: number | null }

export default function Perigon() {
  const { teil } = useParams()
  const navigate = useNavigate()
  const aktiv: Teil = TEILE.find(([t]) => t === teil)?.[0] ?? ALT[teil ?? ''] ?? 'faelle'
  const a = useAuswertung()
  const { daten, laedt, fehler, fortschritt } = a
  const wissen = useVerlauf()
  const [stand, setStand] = useState<PerigonStand[] | null>(null)
  const [chargen, setChargen] = useState<ChargeKurz[]>([])
  const [offen, setOffen] = useState<PerigonBefund | null>(null)
  const [sache, setSache] = useState<Ungereimtheit | null>(null)

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

  const spur = useMemo(() => new Map((daten?.spur ?? []).map(s => [s.charge_nr, s])), [daten?.spur])
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
              gehe={(t, q) => navigate(`/perigon/${t}${q ? `?${q}` : ''}`)} oeffnen={setOffen} sacheOeffnen={setSache} />
      {offen && <LieferungFenster quelle={offen.quelle} posId={offen.pos_id} fall={offen} schliessen={() => setOffen(null)} />}
      {sache && <SacheFenster u={sache} spur={spur} schliessen={() => setSache(null)} />}
    </VerlaufKontext.Provider>
  )
}

interface Oeffner { oeffnen: (f: PerigonBefund) => void; sacheOeffnen: (u: Ungereimtheit) => void }

function Inhalt({ daten, stand, chargen, aktiv, verlauf, gehe, oeffnen, sacheOeffnen }: {
  daten: Auswertung; stand: PerigonStand[] | null; chargen: ChargeKurz[]; aktiv: Teil
  verlauf: Map<string, PerigonVerlauf>; gehe: (t: Teil, q?: string) => void
} & Oeffner) {
  // Die Sachen je Charge (v_ungereimtheit) — ohne die Perigon-Zeilen: die stehen je Position.
  const sachen = useMemo(() => ungereimtheiten(daten.ungereimt), [daten.ungereimt])
  const faelle = daten.perigon
  const sorten = useMemo(() => jeSorte(daten.spur, sachen, faelle, chargen), [daten.spur, sachen, faelle, chargen])
  const zahlen = useMemo(() => {
    const st = (s: string) => standVon(verlauf, s)
    const alle = [...faelle.map(f => ({ s: f.schluessel, schwere: f.schwere, kg: betroffen(f) })),
                  ...sachen.map(u => ({ s: u.schluessel, schwere: u.schwere, kg: u.kg }))]
    const offenAlle = alle.filter(x => istOffen(x.schwere, st(x.s)))
    return {
      offen: offenAlle.length, offenKg: offenAlle.reduce((a, x) => a + (x.kg ?? 0), 0), rot: offenAlle.filter(x => x.schwere === 'rot').length,
      abklaerung: alle.filter(x => st(x.s) === 'in_abklaerung').length,
      wartet: alle.filter(x => st(x.s) === 'erledigt').length,
      behoben: [...verlauf.values()].filter(v => v.weg_seit != null).length,
    }
  }, [faelle, sachen, verlauf])
  const bis = stand?.reduce<string | null>((m, s) => (s.bis && (!m || s.bis > m) ? s.bis : m), null) ?? null
  const offenFaelle = faelle.filter(f => istOffen(f.schwere, standVon(verlauf, f.schluessel))).length
    + sachen.filter(u => istOffen(u.schwere, standVon(verlauf, u.schluessel))).length

  return (
    <>
      {/* Runde BA: die Frage des Reiters, die Antwort zuoberst — Runde BD: drei Zahlen, nicht fünf. */}
      <section className="antwort perigon-antwort" id="perigon-antwort">
        <p className="perigon-frage">Was stimmt in Perigon nicht — und was ist davon schon geklärt?</p>
        <div className="spalten">
          <Kennzahl titel="Offen" wert={zahl(zahlen.offen)} ton={zahlen.rot > 0 ? 'rot' : undefined}
                    unter={zahlen.offen > 0
                      ? <>betrifft {tonnen(zahlen.offenKg)}<Herkunft art="gerechnet" text="aus Datei und Lieferscheinen gemessen, „mehr verkauft als möglich“ mit dem gerechneten Verlust" />{zahlen.rot > 0 ? ` · ${zahlen.rot} davon gross (ab 500 kg)` : ''}</>
                      : 'nichts offen'} />
          <Kennzahl titel="In Abklärung" wert={zahl(zahlen.abklaerung)} unter="gemeldet, Antwort ausstehend" />
          <Kennzahl titel="Erledigt" wert={zahl(zahlen.wartet + zahlen.behoben)}
                    unter={`${zahl(zahlen.behoben)} nicht mehr in den Daten · ${zahl(zahlen.wartet)} ${zahlen.wartet === 1 ? 'wartet' : 'warten'} aufs Einlesen`} />
        </div>
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
            {t === 'faelle' && offenFaelle > 0 && <span className="reiter-zahl">{offenFaelle}</span>}
            {t === 'sorten' && sorten.length > 0 && <span className="reiter-zahl">{sorten.length}</span>}
          </a>
        ))}
      </nav>
      <div className="wechsel" key={aktiv}>
        {aktiv === 'faelle' && <Faelle faelle={faelle} sachen={sachen} stand={stand} verlauf={verlauf} oeffnen={oeffnen} sacheOeffnen={sacheOeffnen} />}
        {aktiv === 'sorten' && <JeSorte sorten={sorten} daten={daten} sachen={sachen} verlauf={verlauf} oeffnen={oeffnen} sacheOeffnen={sacheOeffnen} />}
        {aktiv === 'verlauf' && <Verlauf faelle={faelle} sachen={sachen} verlauf={verlauf} oeffnen={oeffnen} sacheOeffnen={sacheOeffnen} />}
        {aktiv === 'pruefung' && <SoPrueft stand={stand} />}
      </div>
    </>
  )
}

const RANG: Record<Schwere, number> = { rot: 0, gelb: 1, info: 2 }
const Punkt = ({ s }: { s: Schwere }) => <span className={`punkt s-${s}`} aria-hidden="true" />
const faelleWort = (n: number) => `${zahl(n)} ${n === 1 ? 'Fall' : 'Fälle'}`

/* ---------- Bausteine der Listen ---------------------------------------- */

/**
 * Eine Art von Fehler als Zeile, die aufklappt: der Name, was er heisst (ein
 * Satz), wie viele Fälle, wie viel es betrifft, wo es behoben wird. Offen:
 * was zu tun ist (einmal für alle Fälle der Art) und die Fälle.
 */
function Gruppe({ id, schwere, name, heisst, n, kgSumme, wo, auf, umschalten, children }: {
  id: string; schwere: Schwere; name: string; heisst: string | null; n: number; kgSumme: number | null; wo: Wo
  auf: boolean; umschalten: () => void; children: ReactNode
}) {
  return (
    <section className={`perigon-art s-${schwere}${auf ? ' auf' : ''}`} id={id}>
      <button type="button" className="perigon-art-kopf" aria-expanded={auf} onClick={umschalten}>
        <span className="chevron" aria-hidden="true"><ZChevron size={16} /></span>
        <span className="perigon-art-name">
          <span><Punkt s={schwere} /><strong>{name}</strong></span>
          {heisst && <span className="perigon-art-heisst">{heisst}</span>}
        </span>
        <span className="perigon-art-zahlen">
          <span>{faelleWort(n)}</span>
          {kgSumme != null && kgSumme > 0 && <span className="leise">betrifft {tonnen(kgSumme)}</span>}
        </span>
        <span className="wo-marke">{WO_NAME[wo].kurz}</span>
      </button>
      {auf && <div className="perigon-art-inhalt">{children}</div>}
    </section>
  )
}

/** Eine Zeile, die ein Fenster öffnet — mit der Maus, mit Enter oder der Leertaste. */
const klick = (tun: () => void) => ({
  className: 'klickbar', tabIndex: 0, onClick: tun,
  onKeyDown: (e: React.KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); tun() } },
})

/** Die Fälle einer Art: je Fall eine Zeile — wann, was, welche Charge, das Eine, das nicht passt, wie viel, der Stand. */
function FallTabelle({ faelle, verlauf, stand, oeffnen, mitArt = false }: {
  faelle: PerigonBefund[]; verlauf: Map<string, PerigonVerlauf>; stand: PerigonStand[] | null; oeffnen: (f: PerigonBefund) => void
  /** in Je Sorte: die Art steht nicht darüber, also in der Zeile */
  mitArt?: boolean
}) {
  const quelleName = (q: string) => (stand && stand.length > 1 ? stand.find(s => s.quelle === q)?.name ?? q : null)
  return (
    <div className="rollbar">
      <table className="dicht fall-tabelle ohne-haftkopf">
        <thead><tr><th>Geliefert</th><th>Artikel</th><th>Charge</th><th>Was nicht passt</th><th className="zahl">betrifft</th><th>Stand</th><th aria-label="öffnen" /></tr></thead>
        <tbody>{faelle.map(f => {
          const v = verlauf.get(f.schluessel)
          const q = quelleName(f.quelle)
          return (
            <tr key={f.schluessel} {...klick(() => oeffnen(f))} title="den Fall öffnen: nachgerechnet, was tun, mitverfolgen">
              <td className="nowrap" data-titel="Geliefert">{datum(f.datum)}</td>
              <td data-titel="Artikel">{mitArt ? <><strong>{PERIGON_ART[f.art].name}</strong><span className="zelle-unter">{f.artikel}</span></> : f.artikel}
                <span className="zelle-unter leise">{f.kunde ?? 'Kunde unbekannt'} · Position {f.pos_id}{q ? ` · ${q}` : ''}</span></td>
              <td data-titel="Charge">{f.nummer ?? f.nummern ?? <span className="leise">keine</span>}
                {f.charge_nr != null && String(f.charge_nr) !== (f.nummer ?? f.nummern) && <span className="leise"> → {f.charge_nr}</span>}</td>
              <td className="fall-kurz" data-titel="Was nicht passt">{fallKurz(f)}</td>
              <td className="zahl" data-titel="betrifft">{f.kg == null ? 'unbekannt' : kg(betroffen(f), 0)}</td>
              <td data-titel="Stand"><StandMarke stand={v?.stand ?? 'offen'} /></td>
              <td className="zeile-pfeil" aria-hidden="true"><ZChevron size={14} /></td>
            </tr>
          )
        })}</tbody>
      </table>
    </div>
  )
}

/** Die Sachen je Charge: je Sache eine Zeile — was nicht passt, wie viel, der Stand. */
function SachTabelle({ sachen, verlauf, sacheOeffnen, mitArt = false }: {
  sachen: Ungereimtheit[]; verlauf: Map<string, PerigonVerlauf>; sacheOeffnen: (u: Ungereimtheit) => void; mitArt?: boolean
}) {
  return (
    <div className="rollbar">
      <table className="dicht fall-tabelle sach-tabelle ohne-haftkopf">
        <thead><tr><th>Was nicht passt</th><th className="zahl">betrifft</th><th>Stand</th><th aria-label="öffnen" /></tr></thead>
        <tbody>{sachen.map(u => {
          const v = verlauf.get(u.schluessel)
          return (
            <tr key={u.schluessel} {...klick(() => sacheOeffnen(u))} title="öffnen: der Weg der Ware, was tun, mitverfolgen">
              <td data-titel="Was nicht passt">{mitArt && <strong className="zelle-oben">{ART_NAME[u.art] ?? u.art}</strong>}{u.titel}</td>
              <td className="zahl" data-titel="betrifft">{u.kg == null ? '—' : kg(u.kg, 0)}</td>
              <td data-titel="Stand">{u.schwere === 'info' ? <span className="leise">Auskunft</span> : <StandMarke stand={v?.stand ?? 'offen'} />}</td>
              <td className="zeile-pfeil" aria-hidden="true"><ZChevron size={14} /></td>
            </tr>
          )
        })}</tbody>
      </table>
    </div>
  )
}

/* ---------- Fälle: die Arbeitsliste -------------------------------------- */

function Faelle({ faelle, sachen, stand, verlauf, oeffnen, sacheOeffnen }: {
  faelle: PerigonBefund[]; sachen: Ungereimtheit[]; stand: PerigonStand[] | null; verlauf: Map<string, PerigonVerlauf>
} & Oeffner) {
  const [such, setSuch] = useSearchParams()
  const filter: Filter = {
    ...FILTER_LEER,
    art: such.get('art') ?? '', quelle: such.get('quelle') ?? '', sorte: such.get('sorte') ?? '', suche: such.get('suche') ?? '', wo: such.get('wo') ?? '',
    stand: (['offen', 'abklaerung', 'erledigt', 'alle'].includes(such.get('stand') ?? '') ? such.get('stand') : 'offen') as StandFilter,
    charge: such.get('charge') ? Number(such.get('charge')) : null,
  }
  const setze = (k: string, v: string) => {
    const neu = new URLSearchParams(such)
    if (v) neu.set(k, v); else neu.delete(k)
    setSuch(neu, { replace: true })
  }
  const schluessel = [filter.art, filter.quelle, filter.sorte, filter.suche, filter.stand, filter.charge, filter.wo].join('|')
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const zeilen = useMemo(() => nachArt(filtern(faelle, verlauf, filter), verlauf), [faelle, verlauf, schluessel])
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const proCharge = useMemo(() => sachenNachArt(sachenFiltern(sachen, verlauf, filter), verlauf), [sachen, verlauf, schluessel])
  // Wo es behoben wird — über alles Offene, unabhängig vom Filter, damit die Zahlen stehen bleiben.
  const tun = useMemo(() => aufgaben(faelle, sachen, verlauf), [faelle, sachen, verlauf])
  const alleGruppen = zeilen.length + proCharge.length
  const [auf, setAuf] = useState<Set<string>>(() => new Set(filter.art ? [`art-${filter.art}`, `charge-art-${filter.art}`] : []))
  const offenGruppe = (id: string) => auf.has(id) || alleGruppen <= 2 || !!filter.suche || filter.charge != null
  const umschalten = (id: string) => setAuf(a => { const n = new Set(a); if (n.has(id)) n.delete(id); else n.add(id); return n })
  const chips: [string, string][] = [
    ...(filter.art ? [['art', `Art: ${(PERIGON_ART as Record<string, { name: string } | undefined>)[filter.art]?.name ?? ART_NAME[filter.art] ?? filter.art}`] as [string, string]] : []),
    ...(filter.sorte ? [['sorte', `Sorte: ${filter.sorte}`] as [string, string]] : []),
    ...(filter.charge != null ? [['charge', `Charge ${filter.charge}`] as [string, string]] : []),
    ...(filter.quelle ? [['quelle', `Firma: ${stand?.find(s => s.quelle === filter.quelle)?.name ?? filter.quelle}`] as [string, string]] : []),
  ]
  return (
    <>
      <div className="perigon-filter" id="perigon-filter">
        <Segmente<StandFilter> wahl={filter.stand} setzen={v => setze('stand', v === 'offen' ? '' : v)} id="perigon-stand"
                               teile={[['offen', 'offen', 'filter-offen'], ['abklaerung', 'in Abklärung', 'filter-abklaerung'], ['erledigt', 'erledigt', 'filter-erledigt'], ['alle', 'alle', 'filter-alle']]} />
        <input type="search" aria-label="Suchen" placeholder="Suchen: Charge, Kunde, Artikel, Position …" value={filter.suche} onChange={e => setze('suche', e.target.value)} />
        {chips.map(([k, text]) => <button key={k} type="button" className="klein filter-chip" onClick={() => setze(k, '')} aria-label={`${text} — Filter weg`}>{text} ✕</button>)}
      </div>
      {tun.length > 0 && (
        <div className="perigon-wo" role="group" aria-label="Wo es behoben wird" id="perigon-wo">
          <span className="leise">Wo zu tun:</span>
          {WO_FOLGE.filter(w => tun.some(t => t.wo === w)).map(w => {
            const t = tun.find(x => x.wo === w)!
            const an = filter.wo === w
            return (
              <button key={w} type="button" className={`wo-knopf${an ? ' an' : ''}`} aria-pressed={an} id={`wo-${w}`}
                      onClick={() => setze('wo', an ? '' : w)} title={WO_NAME[w].lang}>
                {WO_NAME[w].kurz} <span className="wo-zahl">{t.eintraege.length}</span>
              </button>
            )
          })}
        </div>
      )}
      {alleGruppen === 0 && (
        <Karte><p className="leise">Keine Fälle{filter.stand === 'offen' ? ' offen' : ''} mit dieser Wahl.{filter.stand === 'offen' ? ' „alle" zeigt auch, was erledigt ist.' : ''}</p></Karte>
      )}
      {zeilen.length > 0 && (
        <section className="perigon-abschnitt" id="perigon-zeilen">
          <h2>In einer Perigon-Zeile <span className="leise">— je Lieferschein-Position</span></h2>
          {zeilen.map(g => {
            const id = `art-${g.art}`
            return (
              <Gruppe key={id} id={id} schwere={g.schwere} name={g.info.name} heisst={g.info.heisst} n={g.faelle.length} kgSumme={g.kg}
                      wo={g.info.wo} auf={offenGruppe(id)} umschalten={() => umschalten(id)}>
                <p className="perigon-art-tun"><strong>Was tun:</strong> {g.info.tun}</p>
                <FallTabelle faelle={g.faelle} verlauf={verlauf} stand={stand} oeffnen={oeffnen} />
              </Gruppe>
            )
          })}
        </section>
      )}
      {proCharge.length > 0 && (
        <section className="perigon-abschnitt" id="perigon-je-charge">
          <h2>Zwischen Perigon und Lager <span className="leise">— je Charge</span></h2>
          {proCharge.map(g => {
            const id = `charge-art-${g.art}`
            return (
              <Gruppe key={id} id={id} schwere={g.schwere} name={ART_NAME[g.art] ?? g.art} heisst={SACHE_HEISST[g.art] ?? null} n={g.faelle.length}
                      kgSumme={g.kg} wo={g.wo} auf={offenGruppe(id)} umschalten={() => umschalten(id)}>
                <p className="perigon-art-tun"><strong>Was tun:</strong> {WO_NAME[g.wo].lang} — je Fall steht im Fenster, was genau.</p>
                <SachTabelle sachen={g.faelle} verlauf={verlauf} sacheOeffnen={sacheOeffnen} />
              </Gruppe>
            )
          })}
        </section>
      )}
    </>
  )
}

/* ---------- Je Sorte: Fall für Fall ------------------------------------- */

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-')

function JeSorte({ sorten, daten, sachen, verlauf, oeffnen, sacheOeffnen }: {
  sorten: SorteFall[]; daten: Auswertung; sachen: Ungereimtheit[]; verlauf: Map<string, PerigonVerlauf>
} & Oeffner) {
  const [such] = useSearchParams()
  const ziel = such.get('sorte')
  const lage = useMemo(() => lageInZahlen(daten.spur, sachen), [daten.spur, sachen])
  const [auf, setAuf] = useState<Set<string>>(() => new Set(ziel ? [ziel] : []))
  useEffect(() => {
    if (!ziel) return
    const t = window.setTimeout(() => document.getElementById(`sorte-${slug(ziel)}`)?.scrollIntoView({ block: 'start', behavior: 'smooth' }), 80)
    return () => window.clearTimeout(t)
  }, [ziel])
  if (sorten.length === 0) return <Karte><p className="leise">In keiner Sorte passt etwas nicht — Perigon und Lager gehen auf.</p></Karte>
  return (
    <>
      <p className="perigon-einleitung" id="perigon-lage">
        Über alle Chargen: <strong>{tonnen(lage.hereinKg)}</strong> herein laut Erntejournal<Herkunft art="gemessen" />,{' '}
        <strong>{tonnen(lage.hinausKg)}</strong> hinaus laut Perigon<Herkunft art="gemessen" />, davon {tonnen(lage.ohneChargeKg ?? 0)} ohne Charge;
        laut App noch {lage.nochPaletten == null ? 'unbekannt' : `≈ ${zahl(lage.nochPaletten)} Paletten`}<Herkunft art="gerechnet" />.
        <span className="leise"> Je Sorte, in der etwas nicht passt: erst das Bild über alle ihre Chargen, dann die Fälle.</span>
      </p>
      {sorten.map(s => (
        <SorteZeile key={s.sorte} s={s} verlauf={verlauf} auf={auf.has(s.sorte)} oeffnen={oeffnen} sacheOeffnen={sacheOeffnen}
                    umschalten={() => setAuf(a => { const n = new Set(a); if (n.has(s.sorte)) n.delete(s.sorte); else n.add(s.sorte); return n })} />
      ))}
    </>
  )
}

function SorteZeile({ s, verlauf, auf, umschalten, oeffnen, sacheOeffnen }: {
  s: SorteFall; verlauf: Map<string, PerigonVerlauf>; auf: boolean; umschalten: () => void
} & Oeffner) {
  const [ohneAuf, setOhneAuf] = useState(false)
  const marken = (nr: number) => {
    const m: { text: string; s: Schwere }[] = []
    for (const u of s.sachen) {
      if (u.charge_nr !== nr && u.von_charge_nr !== nr) continue
      const name = u.art === 'ueberzaehlung' ? `${tonnen(u.kg)} zu viel` : u.art === 'vor_eingang' ? `vor dem Eingang ${tonnen(u.kg)}`
        : u.art === 'umgebucht' ? (u.charge_nr === nr ? 'Paletten hierher umgebucht' : 'Paletten weg umgebucht')
        : u.art === 'vorschlag' ? (u.charge_nr === nr ? 'Paletten wohl hierher' : 'Paletten wohl anderswo') : ART_NAME[u.art] ?? u.art
      m.push({ text: name, s: u.schwere })
    }
    if (s.nieGeliefert.includes(nr)) m.push({ text: 'nie ein Lieferschein', s: 'gelb' })
    const z = s.zeilen.filter(f => f.charge_nr === nr && f.schwere !== 'info')
    if (z.length) m.push({ text: `${z.length} Perigon-${z.length === 1 ? 'Zeile' : 'Zeilen'}`, s: schwerste(z) })
    return m
  }
  const ohne = s.sachen.find(u => u.art === 'ohne_charge')
  const ernst = [...s.sachen, ...s.zeilen].filter(x => x.schwere !== 'info')
  const offen = ernst.filter(x => istOffen(x.schwere, standVon(verlauf, x.schluessel))).length
  const sachen = [...s.sachen].sort((a, b) => RANG[a.schwere] - RANG[b.schwere] || (b.kg ?? 0) - (a.kg ?? 0))
  return (
    <section id={`sorte-${slug(s.sorte)}`} className={`perigon-art sorte-fall s-${s.schwere}${auf ? ' auf' : ''}`}>
      <button type="button" className="perigon-art-kopf" aria-expanded={auf} onClick={umschalten}>
        <span className="chevron" aria-hidden="true"><ZChevron size={16} /></span>
        <span className="perigon-art-name">
          <span><Punkt s={s.schwere} /><strong>{s.sorte}</strong></span>
          <span className="perigon-art-heisst immer">{s.chargen.length} {s.chargen.length === 1 ? 'Charge' : 'Chargen'} · {faelleWort(ernst.length)}{offen < ernst.length ? `, ${zahl(offen)} offen` : ''}</span>
        </span>
        <span className="perigon-art-zahlen">{s.kg > 0 && <span className="leise">betrifft {tonnen(s.kg)}</span>}</span>
      </button>
      {auf && (
        <div className="perigon-art-inhalt">
          {s.bild.length > 0 && <ul className="sorte-bild">{s.bild.map((b, i) => <li key={i}>{b}</li>)}</ul>}
          {s.aehnlich.map((h, i) => <p key={i} className="hinweis-zeile"><ZWarnung size={14} /> {h}</p>)}
          <div className="rollbar">
            <table className="spur-tabelle sorte-tabelle ohne-haftkopf">
              <caption>Der Weg der Ware, alle Chargen {s.sorte} — herein und hinaus gemessen, „noch da" gerechnet</caption>
              <thead><tr><th scope="col">Charge</th><th scope="col">Herein · Erntejournal</th>
                <th scope="col">Hinaus · Perigon</th><th scope="col">Laut App noch da</th><th scope="col">Was nicht passt</th></tr></thead>
              <tbody>{s.chargen.map(c => {
                const t = spurText(c)
                const m = marken(c.charge_nr)
                const zelle = (titel: string, x: string[], leer = false) => (
                  <td className={leer ? 'spur-leer' : undefined} data-titel={titel}><div>{x.map((y, i) => <div key={i} className={i === 0 ? undefined : 'leise'}>{y}</div>)}</div></td>)
                return (
                  <tr key={c.charge_nr} className={m.length ? `mit-befund s-${schwerste(m.map(x => ({ schwere: x.s })))}` : undefined}>
                    <th scope="row"><Link to={`/chargen?charge=${c.charge_nr}`} title="die Charge unter Chargen öffnen">{c.charge_nr}</Link>
                      <span className="zelle-unter leise">{c.schlag}</span></th>
                    {zelle('Herein', t.herein, t.ohneEingang)}{zelle('Hinaus', t.hinaus)}{zelle('Noch da', [t.noch])}
                    <td data-titel="Was nicht passt">{m.length ? m.map((x, i) => <span key={i} className={`sorte-marke s-${x.s}`}>{x.text}</span>) : <span className="leise">—</span>}</td>
                  </tr>
                )
              })}</tbody>
            </table>
          </div>
          {(sachen.length > 0 || s.zeilen.length > 0) && <h3 className="sorte-faelle-titel">Die Fälle {s.sorte} <span className="leise">— ein Klick zeigt, was zu tun ist</span></h3>}
          {sachen.length > 0 && <SachTabelle sachen={sachen} verlauf={verlauf} sacheOeffnen={sacheOeffnen} mitArt />}
          {s.zeilen.length > 0 && <FallTabelle faelle={[...s.zeilen].sort((a, b) => RANG[a.schwere] - RANG[b.schwere] || (betroffen(b) ?? 0) - (betroffen(a) ?? 0))}
                                               verlauf={verlauf} stand={null} oeffnen={oeffnen} mitArt />}
          {ohne && (
            <div className="ungereimt-aktion">
              <button type="button" className="klein" aria-expanded={ohneAuf} onClick={() => setOhneAuf(x => !x)}>
                {ohneAuf ? 'Lieferscheine ohne Charge zu' : `${ohne.zeilen.length || ''} Lieferscheine ohne Charge zeigen`.replace(/^ /, '')}</button>
            </div>
          )}
          {ohneAuf && <OhneChargeListe sorte={s.sorte} />}
        </div>
      )}
    </section>
  )
}

const schwerste = (l: { schwere: Schwere }[]): Schwere => (l.some(x => x.schwere === 'rot') ? 'rot' : l.some(x => x.schwere === 'gelb') ? 'gelb' : 'info')

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

function Verlauf({ faelle, sachen, verlauf, oeffnen, sacheOeffnen }: {
  faelle: PerigonBefund[]; sachen: Ungereimtheit[]; verlauf: Map<string, PerigonVerlauf>
} & Oeffner) {
  const [vermerke, setVermerke] = useState<VermerkZeile[] | null>(null)
  useEffect(() => {
    let lebt = true
    void (async () => {
      const r = await supabase.from('perigon_vermerk').select('id, schluessel, stand, notiz, ts, schnappschuss, profil(name)')
        .order('ts', { ascending: false }).order('id', { ascending: false }).limit(500)
      if (lebt) setVermerke(r.error ? [] : ((r.data ?? []) as unknown as VermerkZeile[]))
    })()
    return () => { lebt = false }
  }, [verlauf])
  const fallVon = new Map(faelle.map(f => [f.schluessel, f]))
  const sacheVon = new Map(sachen.map(u => [u.schluessel, u]))
  const titel = (schluessel: string, s: Record<string, unknown> | null): ReactNode => {
    const f = fallVon.get(schluessel)
    if (f) return <button type="button" className="link" onClick={() => oeffnen(f)}>{fallTitel(f)}</button>
    const u = sacheVon.get(schluessel)
    if (u) return <button type="button" className="link" onClick={() => sacheOeffnen(u)}>{u.titel}</button>
    return <span>{schnappschussText(s ?? verlauf.get(schluessel)?.schnappschuss)} <span className="leise">(nicht mehr in den Daten)</span></span>
  }
  const weg = [...verlauf.values()].filter(v => v.weg_seit != null).sort((a, b) => (b.weg_seit ?? '').localeCompare(a.weg_seit ?? ''))
  const wartet = [...verlauf.values()].filter(v => v.stand === 'erledigt' && v.weg_seit == null && (fallVon.has(v.schluessel) || sacheVon.has(v.schluessel)))
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
                    <td>{v.notiz ?? <span className="leise">—</span>}</td><td>{titel(v.schluessel, v.schnappschuss)}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}
      </Karte>
      {wartet.length > 0 && (
        <Karte titel="Erledigt vermerkt, aber noch in den Daten" id="perigon-wartet">
          <p className="leise oben-0">In Perigon berichtigt — die App sieht es erst, wenn die Datei neu eingelesen und neu gerechnet ist.</p>
          <ul>{wartet.map(v => <li key={v.schluessel}>{titel(v.schluessel, v.schnappschuss)}{v.vermerk_ts && <span className="leise"> · vermerkt {zeitpunkt(v.vermerk_ts)}</span>}</li>)}</ul>
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
