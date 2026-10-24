import { useEffect, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg } from '../lib/format'
import { excelAnsicht, lieferungDeutung, schluessel, type ChargenzeileKurz, type RohZeile } from '../lib/warenausgang'
import { FALSCHE_SPALTEN, OHNE_CHARGE_GRUND, OHNE_CHARGE_SPALTEN } from '../auswertung/ungereimt'
import type { LieferungOhneCharge, PerigonBefund } from '../auswertung/daten'
import { PERIGON_ART, WO_NAME, gegenueber, nachrechnen, schnappschuss, spaltenZeichen, type Nachrechnung } from '../auswertung/perigon'
import { FallVerfolgen } from '../auswertung/Verfolgen'
import { Hinweis, Lade } from '../components/Bausteine'
import { ZChevron, ZKreuz } from '../components/Zeichen'

interface PositionZeile {
  quelle: string; pos_id: number; datum: string; kunde: string | null; artikel_id: string; artikel: string
  preisgruppe: string | null; einheit: string | null; menge: number | null; gewicht_je_artikel: number | null; kg: number | null
  roh: RohZeile[] | null
}
interface ZeileDerDatei extends ChargenzeileKurz {
  datum: string; kunde: string; artikel: string; einheit: string; menge: number; gewicht_je_artikel: number; kg_position: number | null
  preisgruppe: string | null; lauf_nr: number
}
interface LieferungZeile { id: number; datum: string; charge_nr: number | null; sorte: string | null; kg: number; kunde: string | null; bemerkung: string | null }
interface Einordnung { gruppe: string | null; groesse: string; label: string | null }

/** Eine Spaltenbreite in Excel-Zeichen als Bildpunkte (Arial 10: 7 Punkte je Zeichen und 5 Rand, wie Excel). */
function excelPx(zeichen: number): number {
  return Math.round(zeichen * 7 + 5)
}

/** Wo die Lieferung herkommt: Firma und Position aus der Kennung „Firma:Position:…". */
function positionAus(externId: string | null | undefined): { quelle: string; posId: number } | null {
  const m = /^([^:]+):(\d+):/.exec(externId ?? '')
  return m ? { quelle: m[1], posId: Number(m[2]) } : null
}

/**
 * Eine Lieferung, nachvollziehbar (Runde AS). Der Betrieb: „dass ich jede
 * Lieferung anklicken kann, und dann kommt ein Pop-up, wo du mir die ganze
 * Perigon-Zeile zeigst — eine Replika der Excel-Zeile, alle Spalten — und
 * darunter eine kurze Interpretation, wie du daraus die Kilos berechnest."
 *
 * Zu öffnen mit der Lieferung (aus einer Charge) oder mit Firma und Position
 * (aus der Liste eines Kunden). Die ganze Zeile steht in ausgang_position.roh,
 * sobald die Datei nach 0116 einmal neu eingelesen ist; bis dahin sagt das
 * Fenster das, statt etwas zu zeigen, das nicht in der Datei stand.
 */
export function LieferungFenster({ lieferungId, quelle, posId, fall, schliessen }: {
  lieferungId?: number; quelle?: string; posId?: number
  /** 0126: aus dem Reiter Perigon — der Fall, um den es geht: oben mit seiner Rechnung, unten zum Mitverfolgen */
  fall?: PerigonBefund
  schliessen: () => void
}) {
  const [lieferung, setLieferung] = useState<LieferungZeile | null>(null)
  const [position, setPosition] = useState<PositionZeile | null>(null)
  const [zeilen, setZeilen] = useState<ZeileDerDatei[]>([])
  const [lieferungen, setLieferungen] = useState<LieferungZeile[]>([])
  const [einordnung, setEinordnung] = useState<Einordnung | null>(null)
  // 0121: was an dieser Zeile nicht stimmt — die Zellen dazu stehen rot umrandet. Seit 0126 aus v_perigon_befund.
  const [falsch, setFalsch] = useState<Pick<PerigonBefund, 'schluessel' | 'art' | 'schwere' | 'satz' | 'tun' | 'wo'>[]>([])
  // 0125: warum ein Lieferschein keine Charge hat (v_lieferung_ohne_charge) — mit dem Satz, was zu tun ist.
  const [ohneGrund, setOhneGrund] = useState<LieferungOhneCharge[]>([])
  const [ziel, setZiel] = useState<{ quelle: string; posId: number } | null>(quelle && posId != null ? { quelle, posId } : null)
  const [geladen, setGeladen] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)

  useEffect(() => {
    let lebt = true
    // Vor Stand 125 gibt es die Sicht nicht — dann bleibt der allgemeine Satz (kein Fehler im Fenster).
    const ohneGrundLaden = async (ids: number[]) => {
      if (ids.length === 0) return
      const r = await supabase.from('v_lieferung_ohne_charge').select('id, datum, sorte, kunde, kg, quelle, pos_id, artikel, nummer, grund, satz, tun').in('id', ids)
      if (lebt && !r.error) setOhneGrund((r.data ?? []) as LieferungOhneCharge[])
    }
    void (async () => {
      try {
        let wo = quelle && posId != null ? { quelle, posId } : null
        if (lieferungId != null) {
          const [l, i] = await Promise.all([
            supabase.from('lieferung').select('id, datum, charge_nr, sorte, kg, kunde, bemerkung').eq('id', lieferungId),
            supabase.from('lieferung_import').select('quelle, extern_id').eq('lieferung_id', lieferungId),
          ])
          for (const x of [l, i]) if (x.error) throw x.error
          if (!lebt) return
          const eine = ((l.data ?? []) as LieferungZeile[])[0] ?? null
          setLieferung(eine)
          wo = positionAus(((i.data ?? []) as { extern_id: string }[])[0]?.extern_id)
          if (!wo && eine?.charge_nr == null) await ohneGrundLaden([lieferungId])
        }
        setZiel(wo)
        if (wo) {
          const [p, z, imp, e] = await Promise.all([
            supabase.from('ausgang_position').select('quelle, pos_id, datum, kunde, artikel_id, artikel, preisgruppe, einheit, menge, gewicht_je_artikel, kg, roh')
              .eq('quelle', wo.quelle).eq('pos_id', wo.posId),
            supabase.from('ausgang_zeile').select('datum, kunde, artikel, einheit, menge, gewicht_je_artikel, kg_position, charge_extern, batch_menge, kg_charge, liefer_label, preisgruppe, lauf_nr')
              .eq('quelle', wo.quelle).eq('pos_id', wo.posId).order('charge_extern').order('lauf_nr'),
            supabase.from('lieferung_import').select('lieferung_id').eq('quelle', wo.quelle).like('extern_id', `${wo.quelle}:${wo.posId}:%`),
            supabase.from('v_kunde_position').select('gruppe, groesse, label').eq('quelle', wo.quelle).eq('pos_id', wo.posId),
          ])
          for (const x of [p, z, imp, e]) if (x.error) throw x.error
          const pr = await supabase.from('v_perigon_befund').select('schluessel, art, schwere, satz, tun, wo').eq('quelle', wo.quelle).eq('pos_id', wo.posId)
          if (lebt && !pr.error) setFalsch((pr.data ?? []) as typeof falsch)
          const ids = ((imp.data ?? []) as { lieferung_id: number }[]).map(x => x.lieferung_id)
          const li = ids.length > 0
            ? await supabase.from('lieferung').select('id, datum, charge_nr, sorte, kg, kunde, bemerkung').in('id', ids).order('charge_nr')
            : { data: [], error: null }
          if (li.error) throw li.error
          await ohneGrundLaden(((li.data ?? []) as LieferungZeile[]).filter(x => x.charge_nr == null).map(x => x.id))
          if (!lebt) return
          setPosition(((p.data ?? []) as PositionZeile[])[0] ?? null)
          setZeilen((z.data ?? []) as ZeileDerDatei[])
          setLieferungen((li.data ?? []) as LieferungZeile[])
          setEinordnung(((e.data ?? []) as Einordnung[])[0] ?? null)
        }
        if (lebt) setGeladen(true)
      } catch (f) { if (lebt) setFehler(fehlerText(f)) }
    })()
    return () => { lebt = false }
  }, [lieferungId, quelle, posId])

  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape') schliessen() }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [schliessen])

  // Die Angaben der Position: aus ausgang_position, sonst aus der ersten Zeile der laufenden Saison.
  const z0 = zeilen[0]
  const kopf = position ?? (z0 ? { datum: z0.datum, kunde: z0.kunde, artikel: z0.artikel, artikel_id: '', einheit: z0.einheit, menge: z0.menge,
                                   gewicht_je_artikel: z0.gewicht_je_artikel, kg: z0.kg_position, preisgruppe: z0.preisgruppe, roh: null } : null)
  const deutung = kopf ? lieferungDeutung(kopf, zeilen) : []
  const roh = position?.roh ?? null
  // Die Datenbank (jsonb) merkt sich die Folge der Spalten nicht: excelAnsicht stellt sie in die Folge der
  // Datei (A bis AF) und zeigt jeden Wert im Format seiner Spalte.
  const ansicht = roh && roh.length > 0 ? excelAnsicht(roh) : null
  // Eine Lieferung ohne Charge, deren Zeile auch keine nennt: die Chargenspalte ist leer.
  const ohneCharge = lieferungen.some(l => l.charge_nr == null) && zeilen.length > 0 && zeilen.every(x => !x.charge_extern?.trim())
  // 0126: Was an der Position nicht stimmt, sagt v_perigon_befund (S = 0, Rest, keine Nummer, unbekannte Nummer …);
  // der Grund je Lieferschein (0125) nur noch dort, wo die Zeile selbst nichts sagt — die Zeile fehlt, oder von Hand.
  const meldungen: { art: string; befund: string; schluessel?: string }[] = [
    ...falsch.map(f => ({ art: f.art, befund: `${f.satz} ${f.tun}`, schluessel: f.schluessel })),
    ...ohneGrund.filter(g => falsch.length === 0 || g.grund === 'ohne_zeile' || g.grund === 'von_hand')
      .map(g => ({ art: `ohne_charge:${g.grund}`, befund: `${g.satz} ${g.tun}` })),
    ...(ohneCharge && !falsch.length && !ohneGrund.length ? [{ art: 'ohne_charge', befund: 'Auf dem Lieferschein steht keine Chargennummer. Die App verteilt die Menge darum nach Eingang auf alle Chargen derselben Sorte — für die einzelne Charge stimmt das nicht.' }] : []),
  ]
  const roteSpalten = new Set([...meldungen.flatMap(m => FALSCHE_SPALTEN[m.art] ?? []), ...ohneGrund.flatMap(g => OHNE_CHARGE_SPALTEN[g.grund] ?? []),
                                ...(fall ? FALSCHE_SPALTEN[fall.art] ?? [] : [])].map(schluessel))
  // 0126: Der Fall, um den es geht, steht oben — in der Liste nur, was an der Zeile sonst noch nicht stimmt.
  const zeigen = fall ? meldungen.filter(m => m.schluessel !== fall.schluessel) : meldungen

  return createPortal(
    <div className="dialog-hinter" onClick={schliessen}>
      <div className="dialog breit" role="dialog" aria-modal="true" aria-label="Lieferung" id="lieferung-fenster" onClick={e => e.stopPropagation()}>
        {fall ? (
          // Runde BD: im Fall zuerst, was nicht stimmt — die Lieferung ist nur, wo es steht.
          <div className="fenster-kopf">
            <div>
              <h2><span className={`punkt s-${fall.schwere}`} aria-hidden="true" />{PERIGON_ART[fall.art]?.name ?? fall.art}</h2>
              <p className="leise fall-wo">
                {datum(fall.datum)} · {fall.kunde ?? 'Kunde unbekannt'} · {fall.artikel} · Position {fall.pos_id}
                {einordnung ? ` · eingeordnet als ${einordnung.gruppe ?? 'unbekannte Gruppe'} ${einordnung.groesse}${einordnung.label ? ` · ${einordnung.label === 'D' ? 'Demeter' : 'Knospe'}` : ''}` : ''}
              </p>
            </div>
            <button type="button" className="klein schliessen" onClick={schliessen} aria-label="schliessen"><ZKreuz size={16} /></button>
          </div>
        ) : (
          <div className="fenster-kopf">
            <div>
              <h2>{kopf ? <>Lieferung an {kopf.kunde || 'unbekannt'} <span className="leise">· {datum(kopf.datum)}</span></>
                        : lieferung ? <>Lieferung vom {datum(lieferung.datum)}</> : 'Lieferung'}</h2>
              <p className="leise" style={{ margin: '.2rem 0 0' }}>
                {kopf?.artikel ?? lieferung?.sorte ?? ''}
                {ziel ? ` · ${ziel.quelle}, Position ${ziel.posId}` : ''}
                {einordnung ? ` · eingeordnet als ${einordnung.gruppe ?? 'unbekannte Gruppe'} ${einordnung.groesse}${einordnung.label ? ` · ${einordnung.label === 'D' ? 'Demeter' : 'Knospe'}` : ''}` : ''}
              </p>
            </div>
            <button type="button" className="klein schliessen" onClick={schliessen} aria-label="schliessen"><ZKreuz size={16} /></button>
          </div>
        )}
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {!fall && !geladen && !fehler && <Lade />}
        {!fall && geladen && !ziel && lieferung && (
          <p>Diese Lieferung kommt aus keiner Perigon-Datei — sie ist von Hand erfasst: {kg(lieferung.kg, 0)}
            {lieferung.charge_nr != null ? ` aus Charge ${lieferung.charge_nr}` : ''}{lieferung.kunde ? ` an ${lieferung.kunde}` : ''}
            {lieferung.bemerkung ? ` (${lieferung.bemerkung})` : ''}.</p>
        )}
        {!fall && geladen && !ziel && ohneGrund.map(g => (
          <div key={g.id} className="lieferung-falsch" id="lieferung-falsch">
            <strong>Warum ohne Charge: {OHNE_CHARGE_GRUND[g.grund] ?? g.grund}</strong>
            <ul><li>{g.satz} {g.tun}</li></ul>
          </div>
        ))}
        {fall && (geladen || fehler) && (
          <FallInhalt fall={fall} zeilen={zeilen} lieferungen={lieferungen} sonst={zeigen.map(m => m.befund)} schliessen={schliessen}
                      excel={ansicht ? <ExcelZeilen ansicht={ansicht} rot={roteSpalten} /> : null} />
        )}
        {fall && !(geladen || fehler) && <Lade />}
        {!fall && geladen && ziel && (
          <>
            {/* Runde AT: „wirklich gleich dargestellt wie in der Excel — erste Zeile die Spaltennamen, zweite einfach
                die Einträge." Spalten in der Folge der Datei, Breiten, Formate und Ausrichtung aus der Datei, grauer
                Kopf mit Umbruch; seitlich rollbar; je Charge der Position eine Zeile. */}
            <section id="lieferung-zeile">
              <h3 className="oben-0">Die Zeile in der Perigon-Datei</h3>
              {zeigen.length > 0 && (
                <div className="lieferung-falsch" id="lieferung-falsch">
                  <strong>Was an dieser Zeile nicht stimmt</strong>{ansicht && roteSpalten.size > 0 ? <span className="leise"> — die Zellen dazu sind rot umrandet</span> : null}
                  <ul>{zeigen.map((m, i) => <li key={i}>{m.befund}</li>)}</ul>
                  {falsch.some(f => f.schwere !== 'info') && ziel && (
                    <p className="unten-0"><Link to={`/perigon/faelle?suche=${ziel.posId}&stand=alle`} onClick={schliessen}>Im Reiter Perigon ansehen und mitverfolgen →</Link></p>
                  )}
                </div>
              )}
              {ansicht ? <ExcelZeilen ansicht={ansicht} rot={roteSpalten} /> : (
                <Hinweis art="info">Die ganze Zeile steht hier, sobald die Perigon-Datei einmal neu eingelesen ist
                  (<Link to="/betrieb/lieferungen" onClick={schliessen}>Betrieb → Warenausgang</Link>) — bis Runde AS speicherte die App
                  nur die Spalten, mit denen sie rechnet.</Hinweis>
              )}
            </section>
            <section id="lieferung-deutung" className="lieferung-deutung">
              <h3>So wird daraus die Masse</h3>
              {deutung.length > 0 ? <ul>{deutung.map((d, i) => <li key={i}>{d}</li>)}</ul>
                : <p className="leise">Die Position steht in keiner eingelesenen Datei mehr.</p>}
              {lieferungen.length > 0 && (
                <p className="leise">In der Rechnung: {lieferungen.map(l => `${kg(l.kg, 1)}${l.charge_nr != null ? ` aus Charge ${l.charge_nr}` : ' ohne Charge'}`).join(' · ')}.</p>
              )}
            </section>
          </>
        )}
      </div>
    </div>,
    document.body,
  )
}

/** Die Zeilen der Datei wie im Excel: Spalten in der Folge der Datei, Breiten, Formate; was nicht stimmt, rot umrandet. */
function ExcelZeilen({ ansicht, rot }: { ansicht: NonNullable<ReturnType<typeof excelAnsicht>>; rot: Set<string> }) {
  return (
    <div className="rollbar excel-rahmen">
      <table className="excel lieferung-zeile" style={{ width: ansicht.spalten.reduce((a, sp) => a + excelPx(sp.breite), 0) }}>
        <colgroup>{ansicht.spalten.map(sp => <col key={sp.name} style={{ width: excelPx(sp.breite) }} />)}</colgroup>
        <thead><tr>{ansicht.spalten.map(sp => (
          <th key={sp.name} data-spalte={sp.buchstabe ?? undefined} className={rot.has(schluessel(sp.name)) ? 'falsch' : undefined}
              title={sp.buchstabe ? `Spalte ${sp.buchstabe} in der Datei` : undefined}>{sp.name}</th>
        ))}</tr></thead>
        <tbody>{ansicht.zeilen.map((z, i) => (
          <tr key={i}>{z.map((w, j) => <td key={j} className={[ansicht.spalten[j].rechts ? 'rechts' : '', rot.has(schluessel(ansicht.spalten[j].name)) ? 'falsch' : ''].filter(Boolean).join(' ') || undefined}>{w}</td>)}</tr>
        ))}</tbody>
      </table>
    </div>
  )
}

/** Zu, bis man es will — mit einem Pfeil, der sich dreht (wie der Rechenweg). */
function Aufklapp({ titel, id, children }: { titel: ReactNode; id?: string; children: ReactNode }) {
  return (
    <details className="rechenweg fall-mehr" id={id}>
      <summary><ZChevron size={14} />{titel}</summary>
      <div className="fall-mehr-inhalt">{children}</div>
    </details>
  )
}

const zahlText = (x: number | null) => (x == null ? '—' : Number(x).toLocaleString('de-CH', { maximumFractionDigits: 3 }))

/**
 * Runde BD: der Fall im Fenster, in der Folge, in der man ihn versteht —
 * was nicht stimmt (ein Satz), nachgerechnet (die Zeilen der Datei, die
 * Summe, die Position, der Unterschied), was zu tun ist, das Mitverfolgen.
 * Die Zeilen wie im Excel und die Erklärung der Art stehen darunter, zu, bis
 * man sie will. Der Betrieb, 24. Oktober: „das versteh ich nicht — wie kommst
 * du auf 768?" — es waren drei gleiche Zeilen à 256 kg, und das Fenster
 * zeigte eine.
 */
function FallInhalt({ fall, zeilen, lieferungen, sonst, excel, schliessen }: {
  fall: PerigonBefund; zeilen: ZeileDerDatei[]; lieferungen: LieferungZeile[]; sonst: string[]; excel: ReactNode; schliessen: () => void
}) {
  const info = PERIGON_ART[fall.art]
  const r = nachrechnen(fall, zeilen)
  const angaben = r ? null : gegenueber(fall)
  const n = zeilen.length
  return (
    <>
      <section className={`fall-kopf s-${fall.schwere}`} id="fall-kopf">
        <p className="fall-satz">{r?.satz ?? fall.satz}</p>
      </section>
      {r && <Nachgerechnet r={r} lieferungen={lieferungen} />}
      {angaben && (
        <section className="fall-block" id="fall-angaben">
          <h3>Was die Datei sagt</h3>
          <table className="dicht fall-angaben ohne-haftkopf">
            <thead><tr><th>Angabe</th><th>Spalte</th><th>in der Datei</th><th>heisst</th></tr></thead>
            <tbody>{angaben.map(a => (
              <tr key={a.was}><th scope="row">{a.was}</th><td>{a.spalte ?? '—'}</td><td>{a.wert}</td><td>{a.heisst ?? <span className="leise">—</span>}</td></tr>
            ))}</tbody>
          </table>
        </section>
      )}
      <section className="fall-block fall-tun" id="fall-tun">
        <h3>Was tun <span className="wo-marke">{WO_NAME[fall.wo]?.kurz ?? fall.wo}</span></h3>
        <p className="oben-0">{fall.tun}</p>
        <p className="leise unten-0">Die Zeile finden: die Datei der Firma öffnen, Ctrl+F, <strong>{fall.pos_id}</strong> suchen
          (Spalte {spaltenZeichen('AufPosId') ?? 'AD'}, die Position){fall.nummer ? <> — die Zeile mit Charge {fall.nummer}</> : null}.</p>
        {sonst.length > 0 && (
          <div className="lieferung-falsch" id="lieferung-falsch">
            <strong>An dieser Position stimmt noch etwas nicht</strong>
            <ul>{sonst.map((m, i) => <li key={i}>{m}</li>)}</ul>
          </div>
        )}
      </section>
      <FallVerfolgen schluessel={fall.schluessel} schnappschuss={schnappschuss(fall)} />
      <Aufklapp id="fall-excel" titel={n > 0 ? `${n === 1 ? 'Die Zeile' : `Die ${n} Zeilen`} der Perigon-Datei, wie im Excel` : 'Die Zeile der Perigon-Datei, wie im Excel'}>
        {excel ? <>{excel}<p className="leise unten-0">Die Zellen, um die es geht, sind rot umrandet.</p></>
          : <Hinweis art="info">Die ganze Zeile steht hier, sobald die Perigon-Datei einmal neu eingelesen ist
              (<Link to="/betrieb/lieferungen" onClick={schliessen}>Betrieb → Warenausgang</Link>) — bis Runde AS speicherte die App nur die Spalten, mit denen sie rechnet.</Hinweis>}
      </Aufklapp>
      {info && (
        <Aufklapp id="fall-erklaert" titel="Was das heisst und was die App daraus macht">
          <dl className="fall-dl">
            <dt>Was das heisst</dt><dd>{info.heisst}</dd>
            <dt>Woran man es sieht</dt><dd>{info.datei}</dd>
            <dt>Was die App daraus macht</dt><dd>{info.app}</dd>
          </dl>
        </Aufklapp>
      )}
    </>
  )
}

/**
 * Nachgerechnet: jede Zeile der Position mit ihrer Charge (Spalte W) und
 * ihrer Menge (Spalte S) — eine Zeile, die schon dastand, sagt es —, darunter
 * die Summe, die Position (Spalte Q) und was nicht aufgeht.
 */
function Nachgerechnet({ r, lieferungen }: { r: Nachrechnung; lieferungen: LieferungZeile[] }) {
  const W = spaltenZeichen('AuftragsChargeManuell') ?? 'W'
  const S = spaltenZeichen('AufPosBatchQuantity Charge') ?? 'S'
  const Q = spaltenZeichen('AuftragsArtikelMenge') ?? 'Q'
  const AE = spaltenZeichen('GewichtProArtikel') ?? 'AE'
  const kgSpalte = !r.istKg
  return (
    <section className="fall-block" id="fall-nachgerechnet">
      <h3>Nachgerechnet</h3>
      <table className="dicht fall-rechnung ohne-haftkopf">
        <thead><tr>
          <th>Zeile</th><th>Charge <span className="leise">(Spalte {W})</span></th>
          <th className="zahl">Menge je Charge <span className="leise">(Spalte {S})</span></th>
          {kgSpalte && <th className="zahl">in kg <span className="leise">(× {AE})</span></th>}
        </tr></thead>
        <tbody>
          {r.zeilen.length === 0 && (
            <tr><td colSpan={kgSpalte ? 4 : 3} className="leise">Die Zeilen der Position stehen in keiner eingelesenen Datei mehr — die Summen unten sind die beim letzten Einlesen.</td></tr>
          )}
          {r.zeilen.map(z => (
            <tr key={z.nr} className={z.gleichWie ? 'doppelt' : undefined}>
              <td>{z.nr}</td>
              <td>{z.charge ?? <span className="leise">leer</span>}{z.gleichWie && <span className="fall-gleich"> gleich wie Zeile {z.gleichWie}</span>}</td>
              <td className="zahl">{z.s == null ? '—' : `${zahlText(z.s)} ${r.einheit}`}</td>
              {kgSpalte && <td className="zahl">{z.kg == null ? 'unbekannt' : kg(z.kg, 1)}</td>}
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr><th scope="row" colSpan={kgSpalte ? 3 : 2}>den Chargen zugeteilt, zusammen <span className="leise">(Spalte {S})</span></th>
            <td className="zahl">{r.zugeteiltKg == null ? 'unbekannt' : kg(r.zugeteiltKg, 0)}</td></tr>
          <tr><th scope="row" colSpan={kgSpalte ? 3 : 2}>die Position <span className="leise">(Spalte {Q}{kgSpalte ? ` × ${AE}` : ''})</span></th>
            <td className="zahl">{r.positionKg == null ? 'unbekannt' : kg(r.positionKg, 0)}</td></tr>
          {r.unterschied && (
            <tr className="fall-unterschied"><th scope="row" colSpan={kgSpalte ? 3 : 2}>{r.unterschied.wort}</th>
              <td className="zahl">{r.unterschied.kg == null ? 'unbekannt' : kg(Math.abs(r.unterschied.kg), 0)}</td></tr>
          )}
        </tfoot>
      </table>
      {lieferungen.length > 0 && (
        <p className="leise unten-0">In der Rechnung der App: {lieferungen.map(l => `${kg(l.kg, 0)} ${l.charge_nr != null ? `auf Charge ${l.charge_nr}` : 'ohne Charge'}`).join(' · ')}.</p>
      )}
    </section>
  )
}
