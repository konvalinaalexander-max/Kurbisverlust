/**
 * Runde BF: ein Fall, wie man ihn versteht. Der Betrieb, 24. Oktober: „Den
 * Fall verstehe, sehe, was passiert ist … erkläre lieber, was Sache ist, sehr
 * verständlich, angenehm dargestellt. Denk an Visual Design … Und dann machen
 * wir uns unsere Meinung dazu."
 *
 * In dieser Folge, für jeden Fall gleich:
 *  1. Was ist passiert — herein, hinaus, was nicht aufgeht, in Sätzen mit
 *     Zahlen und Herkunft; was das für die Zahlen der App heisst.
 *  2. Das Bild — herein gegen das, was es für die Lieferscheine brauchte
 *     (Balken), die Rückrechnung Schritt für Schritt mit „wie sicher", die
 *     Lieferscheine auf einer Zeitachse gegen den Tag der ersten Palette.
 *  3. Die Belege — die Lieferscheine, die Zeilen wie im Excel.
 *  4. Stand und Notiz — was der Betrieb entschieden hat.
 *  5. Zu, ganz unten: was die App vermutet und was man tun könnte. Der
 *     Betrieb: „du musst uns nicht 1000 Lösungsvorschläge vorschlagen."
 */
import { Fragment, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { datum, kg, prozent, tonnen } from '../lib/format'
import { Herkunft, Hinweis } from '../components/Bausteine'
import { ZChevron, ZZurueck } from '../components/Zeichen'
import type { ChargeSpur, PerigonBefund } from './daten'
import { bilanz, fallStand, geschichte, rueckrechnung, spanne, wieSicher, zeitleiste, type Fall, type KaskadeZeile, type Rueckrechnung } from './faelle'
import { PERIGON_ART, WO_NAME, betroffen, fallKurz, sacheSchnappschuss, schnappschuss, type SorteFall } from './perigon'
import { useBelege, BelegeTabelle, PerigonBelege, type Beleg } from './Belege'
import { FallVerfolgen, StandMarke, VerlaufKontext } from './Verfolgen'
import { SacheKnoepfe, WegDerWare } from './Ungereimtheiten'
import { OhneChargeListe } from './OhneCharge'
import { LieferungFenster, PositionImFall } from '../betrieb/LieferungFenster'

export function FallAnsicht({ fall, nr, stelle, vorher, nachher, zurListe, spur, sorte }: {
  fall: Fall
  /** die Nummer des Falls (0127) — leer, solange sie nicht vergeben ist */
  nr: number | null
  /** der wievielte in der Liste, und wie viele es sind */
  stelle: { i: number; n: number }
  vorher: (() => void) | null
  nachher: (() => void) | null
  /** auf dem Handy: zurück zur Liste */
  zurListe: () => void
  spur: Map<number, ChargeSpur>
  /** Runde BF: das Bild der Sorte (Chargen ohne Lieferschein, verwechselbare Nummern) — für „was die App vermutet" */
  sorte: SorteFall | null
}) {
  const wissen = useContext(VerlaufKontext)
  const stand = fallStand(fall, wissen?.verlauf ?? new Map())
  const s = fall.charge_nr != null ? spur.get(fall.charge_nr) : undefined
  return (
    <article className={`fall-ansicht s-${fall.schwere}`} id="fall-ansicht" aria-labelledby="fall-titel">
      <nav className="fall-nav" aria-label="Von Fall zu Fall">
        <button type="button" className="klein nur-handy" onClick={zurListe} id="fall-zur-liste"><ZZurueck size={14} /> Alle Fälle</button>
        <span className="fall-stelle leise">{stelle.n > 0 ? `${stelle.i + 1} von ${stelle.n}` : ''}</span>
        <span className="fall-nav-knoepfe">
          <button type="button" className="klein" onClick={() => vorher?.()} disabled={!vorher} id="fall-vorher" aria-label="voriger Fall" title="voriger Fall (Taste ←)">
            <ZZurueck size={14} /> voriger</button>
          <button type="button" className="klein" onClick={() => nachher?.()} disabled={!nachher} id="fall-nachher" aria-label="nächster Fall" title="nächster Fall (Taste →)">
            nächster <ZChevron size={14} /></button>
        </span>
      </nav>
      <header className="fall-titel">
        <p className="fall-nummer">{nr != null ? `Fall ${nr}` : 'Fall'}</p>
        <h2 id="fall-titel"><span className={`punkt s-${fall.schwere}`} aria-hidden="true" />{fall.titel}</h2>
        <p className="fall-unter">
          {fall.typ === 'charge' && s?.schlag ? <>{s.schlag} · </> : null}{fall.unter}
          {' '}<StandMarke stand={stand} />
        </p>
      </header>
      {fall.typ === 'charge' && <ChargeFall fall={fall} spur={s} />}
      {fall.typ === 'art' && <ArtFall fall={fall} />}
      {(fall.typ === 'register' || fall.typ === 'auskunft') && <SacheFall fall={fall} spur={spur} />}
      {fall.teile.length > 0 && (
        <FallVerfolgen key={fall.id} titel="Stand und Notiz" schluessel={fall.teile}
                       schnappschuss={x => teilSchnappschuss(fall, x)} />
      )}
      <Vermutung fall={fall} spur={spur} sorte={sorte} />
    </article>
  )
}

/** Was ein Teil war, falls er später verschwindet — eine Sache oder eine Position. */
function teilSchnappschuss(f: Fall, schluessel: string): Record<string, unknown> {
  const u = f.sachen.find(x => x.schluessel === schluessel)
  if (u) return sacheSchnappschuss(u)
  const b = f.befunde.find(x => x.schluessel === schluessel)
  return b ? schnappschuss(b) : { fall: f.id }
}

/* ---------- 1. Was ist passiert ----------------------------------------- */

function Passiert({ fall, spur, extra }: { fall: Fall; spur: Map<number, ChargeSpur>; extra?: ReactNode }) {
  const g = geschichte(fall, spur)
  return (
    <section className="fall-block fall-passiert" id="fall-passiert">
      <h3>Was ist passiert</h3>
      {(g.herein || g.hinaus) && (
        <dl className="fall-wege">
          {g.herein && <><dt className="weg-herein">Herein</dt><dd>{g.herein.replace(/^Herein: /, '')}</dd></>}
          {g.hinaus && <><dt className="weg-hinaus">Hinaus</dt><dd>{g.hinaus.replace(/^Hinaus: /, '')}</dd></>}
        </dl>
      )}
      {g.punkte.length > 0 && (
        <ul className="fall-punkte">
          {g.punkte.map((p, i) => <li key={i} className={`s-${p.schwere}`}>{p.text}</li>)}
        </ul>
      )}
      {extra}
      {g.folge && <p className="fall-folge"><strong>{fall.typ === 'art' ? 'So rechnet die App damit:' : 'Für die Zahlen der App:'}</strong> {g.folge}</p>}
    </section>
  )
}

/* ---------- Ein Fall je Charge ------------------------------------------- */

function ChargeFall({ fall, spur }: { fall: Fall; spur: ChargeSpur | undefined }) {
  const nr = fall.charge_nr!
  const spurMap = useMemo(() => new Map(spur ? [[nr, spur]] : []), [nr, spur])
  const vor = fall.sachen.find(u => u.art === 'vor_eingang')
  const erst = vor ? (typeof vor.roh?.mehr?.erster_eingang === 'string' ? vor.roh.mehr.erster_eingang : spur?.journal_von ?? null) : null
  const zahlen = bilanz(fall)
  const { belege, fehler } = useBelege([nr])
  const kaskade = useKaskade(zahlen?.gebrauchtKg != null ? nr : null)
  const r = kaskade.zeilen ? rueckrechnung(kaskade.zeilen, zahlen?.eingangKg ?? null) : null
  return (
    <>
      <Passiert fall={fall} spur={spurMap} />
      {zahlen && <BilanzBild eingangKg={zahlen.eingangKg} geliefertKg={zahlen.geliefertKg} gebrauchtKg={zahlen.gebrauchtKg} r={r} />}
      {r && <RechnungTabelle r={r} nr={nr} />}
      {zahlen?.gebrauchtKg != null && kaskade.zeilen && !r && (
        <Hinweis art="info">Die Rechnung Schritt für Schritt steht hier, sobald die Auswertung einmal neu gerechnet ist.</Hinweis>
      )}
      {vor && erst && belege && <ZeitBild belege={belege} eingang={erst} />}
      <BelegeTabelle belege={belege} fehler={fehler} unter={String(nr)} vorEingang={erst} titel="Die Lieferscheine in Perigon" />
    </>
  )
}

/** Die Kaskade einer Charge (mv_kaskade, was auf die Lieferscheine ging) — erst, wenn der Fall sie braucht. */
function useKaskade(nr: number | null): { zeilen: KaskadeZeile[] | null } {
  const [zeilen, setZeilen] = useState<KaskadeZeile[] | null>(null)
  useEffect(() => {
    if (nr == null) { setZeilen(null); return }
    let lebt = true
    setZeilen(null)
    void (async () => {
      const r = await supabase.from('mv_kaskade')
        .select('m0, m1, m2, alter_tage, r, f, a_klein_n, a_gross_n, a_fax, hagel, verdunstung_kg, schimmel_kg, klein_kg, nebenkanal_kg, fax_kg, geliefert_kg, r_basis, f_quelle, klein_basis, gross_basis')
        .eq('charge_nr', nr).eq('portion', 'ausgelagert')
      if (lebt) setZeilen(r.error ? [] : ((r.data ?? []) as KaskadeZeile[]))
    })()
    return () => { lebt = false }
  }, [nr])
  return { zeilen }
}

const STROM_NAME: Record<string, string> = {
  verkauft: 'auf den Lieferscheinen', ausschuss: 'zu klein', nebenkanal: 'zu gross', fax: 'faul beim Abpacken', schimmel: 'Faules (Palox)', verdunstung: 'verdunstet',
}

/**
 * Das Bild herein gegen gebraucht: zwei Balken auf derselben Skala. Oben, was
 * laut Erntejournal hereinkam; unten, was es für die Lieferscheine brauchte —
 * aus Lieferscheinen, Aussortiertem, Faulem und Verdunstetem. Die Linie zeigt,
 * wo der Eingang endet; was rechts davon liegt, fehlt.
 */
function BilanzBild({ eingangKg, geliefertKg, gebrauchtKg, r }: {
  eingangKg: number | null; geliefertKg: number | null; gebrauchtKg: number | null; r: Rueckrechnung | null
}) {
  const ein = eingangKg ?? 0
  const gebraucht = r?.gebrauchtKg ?? gebrauchtKg ?? geliefertKg ?? 0
  const max = Math.max(ein, gebraucht, geliefertKg ?? 0, 1)
  const pct = (x: number) => `${(100 * x) / max}%`
  const teile: { strom: string; kg: number }[] = r
    ? [{ strom: 'verkauft', kg: r.geliefertKg }, ...r.schritte.map(x => ({ strom: x.strom, kg: x.kg }))]
    : gebrauchtKg != null ? [{ strom: 'verkauft', kg: geliefertKg ?? 0 }, { strom: 'verlust', kg: Math.max(0, gebrauchtKg - (geliefertKg ?? 0)) }]
      : [{ strom: 'verkauft', kg: geliefertKg ?? 0 }]
  const fehlt = gebraucht - ein
  const titelUnten = gebrauchtKg != null || r ? 'Dafür gebraucht' : 'Hinaus'
  return (
    <section className="fall-block" id="fall-bilanz">
      <h3>Herein gegen hinaus</h3>
      <div className="bilanz-bild" role="img"
           aria-label={`Herein ${kg(ein, 0)}, ${titelUnten.toLowerCase()} ${kg(gebraucht, 0)}${fehlt > 0 ? `, es fehlen ${kg(fehlt, 0)}` : ''}`}>
        <div className="bilanz-zeile">
          <span className="bilanz-name">Herein<span className="leise">Erntejournal</span></span>
          <div className="bilanz-spur">
            {ein > 0 ? <div className="bilanz-teil st-herein" style={{ width: pct(ein) }} title={`herein ${kg(ein, 0)}`} />
              : <span className="bilanz-leer">keine Palette</span>}
            {ein > 0 && fehlt > 0 && <div className="bilanz-grenze" style={{ left: pct(ein) }} aria-hidden="true" />}
          </div>
          <span className="bilanz-zahl">{kg(ein, 0)}</span>
        </div>
        <div className="bilanz-zeile">
          <span className="bilanz-name">{titelUnten}<span className="leise">{r || gebrauchtKg != null ? 'für die Lieferscheine' : 'Perigon'}</span></span>
          <div className="bilanz-spur">
            <div className="bilanz-stapel" style={{ width: pct(gebraucht) }}>
              {teile.filter(t => t.kg > 0).map(t => (
                <div key={t.strom} className={`bilanz-teil st-${t.strom}`} style={{ width: `${(100 * t.kg) / Math.max(gebraucht, 1)}%` }}
                     title={`${STROM_NAME[t.strom] ?? 'Verlust unterwegs'}: ${kg(t.kg, 0)}`} />
              ))}
            </div>
            {ein > 0 && fehlt > 0 && <div className="bilanz-grenze" style={{ left: pct(ein) }} aria-hidden="true" />}
            {fehlt > 0 && <div className="bilanz-fehlt" style={{ left: pct(ein), width: pct(fehlt) }}><span>fehlt {kg(fehlt, 0)}</span></div>}
          </div>
          <span className="bilanz-zahl">{kg(gebraucht, 0)}</span>
        </div>
      </div>
      {teile.length > 1 && (
        <ul className="bilanz-legende">
          {teile.filter(t => t.kg > 0).map(t => (
            <li key={t.strom}><span className={`bilanz-farbe st-${t.strom}`} aria-hidden="true" />{STROM_NAME[t.strom] ?? 'Verlust unterwegs'} <span className="leise">{kg(t.kg, 0)}</span></li>
          ))}
        </ul>
      )}
    </section>
  )
}

/** Die Rückrechnung Zeile für Zeile — was jede Zahl ist und woher sie kommt — und darunter, wie sicher der Unterschied ist. */
function RechnungTabelle({ r, nr }: { r: Rueckrechnung; nr: number }) {
  return (
    <section className="fall-block" id="fall-rechnung">
      <h3>Die Rechnung, rückwärts</h3>
      <p className="leise oben-0">Was auf den Lieferscheinen steht (gemessen), plus was unterwegs verloren ging (gerechnet), gibt den Eingang, den es dafür brauchte.</p>
      <div className="rollbar">
      <table className="dicht rueck-tabelle ohne-haftkopf">
        <tbody>
          <tr className="rueck-start">
            <th scope="row"><span className="bilanz-farbe st-verkauft" aria-hidden="true" />Auf den Lieferscheinen</th>
            <td className="zahl">{kg(r.geliefertKg, 0)}</td>
            <td className="leise">Perigon, unter der Nummer {nr}</td>
          </tr>
          {r.schritte.map(x => (
            <tr key={x.strom}>
              <th scope="row"><span className={`bilanz-farbe st-${x.strom}`} aria-hidden="true" />+ {x.was}</th>
              <td className="zahl">+ {kg(x.kg, 0)}</td>
              <td>{x.anteil != null ? <strong>{prozent(x.anteil)}</strong> : null}{x.anteil != null ? ' · ' : ''}{x.wie}
                {x.woher && <span className="zelle-unter leise">gemessen: {x.woher}</span>}</td>
            </tr>
          ))}
          {/* ein Körper, keine Fusszeile: die Summe ist eine Zeile der Rechnung wie die Schritte darüber */}
          <tr className="rueck-summe"><th scope="row">= so viel musste hereinkommen</th><td className="zahl">{kg(r.gebrauchtKg, 0)}</td><td /></tr>
          <tr><th scope="row">hereingekommen laut Erntejournal</th><td className="zahl">{r.eingangKg == null ? 'unbekannt' : kg(r.eingangKg, 0)}</td><td /></tr>
          {r.fehltKg != null && r.fehltKg > 0 && (
            <tr className="rueck-fehlt"><th scope="row">es fehlen</th><td className="zahl">{kg(r.fehltKg, 0)}</td><td /></tr>
          )}
        </tbody>
      </table>
      </div>
      <p className="leise rueck-fuss">Die Anteile gelten je vom Rest davor — so rechnet die App: Zuerst verdunstet die Ware im Lager, dann fällt beim Waschen und
        Sortieren Faules heraus, dann sortiert die Maschine nach Grösse. Die Werte stehen unter Ursachen und Messungen.</p>
      <p className={`rueck-sicher${r.ohneVerlustZuViel ? ' sicher' : ''}`} id="fall-wie-sicher"><strong>Wie sicher?</strong> {wieSicher(r)}</p>
    </section>
  )
}

/**
 * Die Lieferscheine einer Charge auf der Zeitachse: je Tag ein Strich, so hoch
 * wie die Kilo; links der Tag der ersten Palette grau hinterlegt — was dort
 * steht, ging hinaus, bevor die Charge da war.
 */
function ZeitBild({ belege, eingang }: { belege: Beleg[]; eingang: string }) {
  const z = zeitleiste(belege.map(b => ({ datum: b.datum, kg: Number(b.kg) })), eingang)
  if (!z) return null
  const t = (d: string) => new Date(`${d}T12:00:00`).getTime()
  const rand = 2 * 864e5
  const a = t(z.von) - rand, b = t(z.bis) + rand
  const pos = (d: string) => `${(100 * (t(d) - a)) / (b - a)}%`
  // je Tag zusammen
  const jeTag = new Map<string, { kg: number; vor: boolean; n: number }>()
  for (const p of z.punkte) {
    const x = jeTag.get(p.datum) ?? { kg: 0, vor: p.vor, n: 0 }
    x.kg += p.kg; x.n += 1
    jeTag.set(p.datum, x)
  }
  const maxKg = Math.max(...[...jeTag.values()].map(x => x.kg), 1)
  const monate: string[] = []
  for (let d = new Date(a); d.getTime() <= b; d.setDate(d.getDate() + 1)) {
    if (d.getDate() === 1) monate.push(d.toISOString().slice(0, 10))
  }
  const vorN = z.punkte.filter(p => p.vor).length
  return (
    <section className="fall-block" id="fall-zeit">
      <h3>Wann die Lieferscheine hinausgingen</h3>
      <div className="zeit-bild" role="img" aria-label={`${vorN} Lieferscheine mit ${tonnen(z.vorKg)} vor der ersten Palette am ${datum(eingang)}, ${z.punkte.length - vorN} danach`}>
        <div className="zeit-flaeche">
          <div className="zeit-vorher" style={{ width: pos(eingang) }} />
          <div className="zeit-eingang" style={{ left: pos(eingang) }}><span>erste Palette {spanne(eingang, null)}</span></div>
          {[...jeTag.entries()].map(([d, x]) => (
            <div key={d} className={`zeit-strich${x.vor ? ' vor' : ''}`} style={{ left: pos(d), height: `${Math.max(6, (100 * x.kg) / maxKg)}%` }}
                 title={`${datum(d)}: ${x.n === 1 ? '1 Lieferschein' : `${x.n} Lieferscheine`}, ${kg(x.kg, 0)}`} />
          ))}
        </div>
        <div className="zeit-achse" aria-hidden="true">
          <span style={{ left: '0%' }}>{spanne(z.von, null)}</span>
          {monate.map(m => <span key={m} style={{ left: pos(m) }} className="zeit-monat">{new Date(`${m}T12:00:00`).toLocaleDateString('de-CH', { month: 'short' })}</span>)}
          <span style={{ right: '0%' }} className="zeit-ende">{spanne(z.bis, null)}</span>
        </div>
      </div>
      <ul className="bilanz-legende">
        <li><span className="bilanz-farbe zeit-vor-farbe" aria-hidden="true" />vor dem Eingang <span className="leise">{vorN} {vorN === 1 ? 'Lieferschein' : 'Lieferscheine'}, {tonnen(z.vorKg)}</span></li>
        <li><span className="bilanz-farbe st-verkauft" aria-hidden="true" />danach <span className="leise">{z.punkte.length - vorN}, {tonnen(z.nachKg)}</span></li>
        <li><span className="bilanz-farbe zeit-vorher-farbe" aria-hidden="true" />die Charge war noch nicht da</li>
      </ul>
    </section>
  )
}

/* ---------- Ein Fall je Art der Perigon-Zeilen ---------------------------- */

const ZUERST = 12

function ArtFall({ fall }: { fall: Fall }) {
  const [offen, setOffen] = useState<PerigonBefund | null>(null)
  const [alle, setAlle] = useState(false)
  const wissen = useContext(VerlaufKontext)
  if (fall.befunde.length === 1) {
    const b = fall.befunde[0]
    const info = PERIGON_ART[b.art]
    return (
      <>
        <section className="fall-block fall-passiert" id="fall-passiert">
          <h3>Was ist passiert</h3>
          <PositionImFall key={b.schluessel} fall={b} />
          {info && <p className="fall-folge"><strong>So rechnet die App damit:</strong> {info.app}</p>}
        </section>
      </>
    )
  }
  const sichtbar = alle ? fall.befunde : fall.befunde.slice(0, ZUERST)
  return (
    <>
      <Passiert fall={fall} spur={new Map()} />
      <section className="fall-block" id="fall-positionen">
        <h3>Die Positionen <span className="leise">— ein Klick zeigt die Zeile wie im Excel und rechnet nach</span></h3>
        <div className="rollbar">
          <table className="dicht fall-tabelle ohne-haftkopf">
            <thead><tr><th>Geliefert</th><th>Artikel</th><th>Charge</th><th>Was nicht passt</th><th className="zahl">betrifft<Herkunft art="gemessen" text="so in der Perigon-Datei: Menge × Gewicht je Artikel (Q × AE, S × AE)" /></th><th>Stand</th><th aria-label="öffnen" /></tr></thead>
            <tbody>{sichtbar.map(b => (
              <tr key={b.schluessel} className="klickbar" tabIndex={0} onClick={() => setOffen(b)} title="die Position öffnen"
                  onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setOffen(b) } }}>
                <td className="nowrap" data-titel="Geliefert">{datum(b.datum)}</td>
                <td data-titel="Artikel">{b.artikel}<span className="zelle-unter leise">{b.kunde ?? 'Kunde unbekannt'} · Position <code className="kennung-wert">{b.pos_id}</code></span></td>
                <td data-titel="Charge">{b.nummer ?? b.nummern ?? <span className="leise">keine</span>}
                  {b.charge_nr != null && String(b.charge_nr) !== (b.nummer ?? b.nummern) && <span className="leise"> → {b.charge_nr}</span>}</td>
                <td className="fall-kurz" data-titel="Was nicht passt">{fallKurz(b)}</td>
                <td className="zahl" data-titel="betrifft">{b.kg == null ? 'unbekannt' : kg(betroffen(b), 0)}</td>
                <td data-titel="Stand"><StandMarke stand={wissen?.verlauf.get(b.schluessel)?.stand ?? 'offen'} /></td>
                <td className="zeile-pfeil" aria-hidden="true"><ZChevron size={14} /></td>
              </tr>
            ))}</tbody>
          </table>
        </div>
        {fall.befunde.length > ZUERST && (
          <button type="button" className="klein belege-alle" onClick={() => setAlle(a => !a)} aria-expanded={alle}>
            {alle ? `nur die ersten ${ZUERST}` : `alle ${fall.befunde.length} Positionen zeigen`}</button>
        )}
      </section>
      {offen && <LieferungFenster quelle={offen.quelle} posId={offen.pos_id} fall={offen} schliessen={() => setOffen(null)} />}
    </>
  )
}

/* ---------- Register und Auskunft ---------------------------------------- */

function SacheFall({ fall, spur }: { fall: Fall; spur: Map<number, ChargeSpur> }) {
  const u = fall.sachen[0]
  if (!u) return null
  return (
    <>
      <Passiert fall={fall} spur={spur} />
      {u.art === 'ohne_charge' && <section className="fall-block"><h3>Die Lieferscheine ohne Charge</h3><OhneChargeListe sorte={u.sorte} /></section>}
      {(u.nummern?.length ?? 0) > 0 && <PerigonBelege nummern={u.nummern} />}
    </>
  )
}

/* ---------- 5. Was die App vermutet — zu, ganz unten ---------------------- */

function Vermutung({ fall, spur, sorte }: { fall: Fall; spur: Map<number, ChargeSpur>; sorte: SorteFall | null }) {
  const info = fall.typ === 'art' && fall.art ? PERIGON_ART[fall.art as keyof typeof PERIGON_ART] : undefined
  // dieselbe Vermutung steht oft bei zwei Sachen einer Charge (vor dem Eingang, zu viel) — einmal genügt
  const vermutet = [...new Set(fall.sachen.map(u => u.vorschlag).filter(Boolean))]
  // was die App bei einer Umbuchung schon getan hat (oder nicht) — nur, wo es um Paletten geht
  const getan = [...new Set(fall.sachen.filter(u => ['vorschlag', 'umgebucht', 'nachgeordnet'].includes(u.art)).map(u => u.stand).filter(Boolean))]
  const tun = [...new Set([...fall.sachen.map(u => u.tun),
                           ...(fall.typ === 'art' ? [fall.befunde.length === 1 ? fall.befunde[0].tun : info?.tun] : [])].filter((x): x is string => !!x))]
  const beteiligt = [...new Set(fall.sachen.flatMap(u => u.beteiligt))]
  const nie = (sorte?.nieGeliefert ?? []).filter(nr => nr !== fall.charge_nr)
  const hinweise = fall.typ === 'charge' ? [...(nie.length ? [nie] : []), ...(sorte?.aehnlich ?? [])] : []
  const knoepfe = fall.sachen.some(u => u.art === 'umgebucht' || u.art === 'vorschlag' || u.perigonSetzen)
  if (!vermutet.length && !tun.length && !knoepfe && !getan.length) return null
  return (
    <details className="rechenweg fall-mehr fall-vermutung" id="fall-vermutung">
      <summary><ZChevron size={14} />{vermutet.length || getan.length || hinweise.length ? 'Was die App vermutet — und was man tun könnte' : 'Was man tun könnte'}</summary>
      <div className="fall-mehr-inhalt">
        <p className="leise oben-0">{vermutet.length || getan.length || hinweise.length ? 'Vermutungen, keine Befunde: entscheiden' : 'Entscheiden'} tut der Betrieb. Gebucht wird nichts, bevor jemand es sagt.</p>
        {vermutet.length > 0 && (
          <div className="vermutung-teil">
            <h4>Woher die Ware wohl kam</h4>
            <ul>{vermutet.map((v, i) => <li key={i}>{v}</li>)}</ul>
          </div>
        )}
        {getan.length > 0 && (
          <div className="vermutung-teil">
            <h4>Was die App schon getan hat</h4>
            <ul>{getan.map((v, i) => <li key={i}>{v}</li>)}</ul>
          </div>
        )}
        {hinweise.length > 0 && (
          <div className="vermutung-teil">
            <h4>In der Sorte {fall.sorte} fällt auf</h4>
            <ul>{hinweise.map((h, i) => <li key={i}>{Array.isArray(h)
              ? <>{h.length === 1 ? 'Diese Charge hat' : 'Diese Chargen haben'} Eingang, aber nie einen Lieferschein: {h.map((x, j) => <Fragment key={x}>{j ? ', ' : ''}<Link to={`/chargen?charge=${x}`}>{x}</Link></Fragment>)}.</>
              : h}</li>)}</ul>
          </div>
        )}
        {beteiligt.length > 1 && fall.typ === 'charge' && (
          <div className="vermutung-teil">
            <h4>Der Weg der Ware</h4>
            <div className="rollbar"><WegDerWare nrn={beteiligt} spur={spur} /></div>
          </div>
        )}
        {tun.length > 0 && (
          <div className="vermutung-teil">
            <h4>Was man tun könnte{info ? <> <span className="wo-marke">{WO_NAME[info.wo].kurz}</span></> : null}</h4>
            <ul>{tun.map((t, i) => <li key={i}>{t}</li>)}</ul>
          </div>
        )}
        {knoepfe && <div className="ungereimt-aktion">{fall.sachen.map(u => <SacheKnoepfe key={u.schluessel} u={u} />)}</div>}
        {fall.charge_nr != null && <p className="unten-0"><Link to={`/chargen?charge=${fall.charge_nr}`}>Charge {fall.charge_nr} unter Chargen öffnen</Link></p>}
      </div>
    </details>
  )
}
