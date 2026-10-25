import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg, zeitpunkt } from '../lib/format'
import { excelAnsicht, excelZeileVon, lieferungDeutung, schluessel, type ChargenzeileKurz, type ExcelAnsicht, type RohZeile } from '../lib/warenausgang'
import { FALSCHE_SPALTEN, OHNE_CHARGE_GRUND, OHNE_CHARGE_SPALTEN } from '../auswertung/ungereimt'
import type { LieferungOhneCharge, PerigonBefund } from '../auswertung/daten'
import { PERIGON_ART, WO_NAME, gegenueber, nachrechnen, schnappschuss, spaltenZeichen, zuteilung, type Nachrechnung } from '../auswertung/perigon'
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
  /** Runde BE: aus welcher Datei die Zeile zuletzt eingelesen wurde */
  datei_id: number | null
}
interface DateiKurz { id: number; dateiname: string; ts: string }
interface LieferungZeile { id: number; datum: string; charge_nr: number | null; sorte: string | null; kg: number; kunde: string | null; bemerkung: string | null }
interface Einordnung { gruppe: string | null; groesse: string; label: string | null }

/** Eine Spaltenbreite in Excel-Zeichen als Bildpunkte (Arial 10: 7 Punkte je Zeichen und 5 Rand, wie Excel). */
function excelPx(zeichen: number): number {
  return Math.round(zeichen * 7 + 5)
}

/**
 * Runde BE: die Excel-Zeile zu jeder Zeile der App. Die App zählt gleiche
 * Chargen einer Position durch (lauf_nr, in der Folge der Datei); die k-te
 * Zeile mit Charge C in der Datei ist die Zeile der App mit Charge C und
 * lauf_nr k. Leer, wo die Datei seit Runde BE nicht neu eingelesen ist.
 */
function excelNrJe(zeilen: { charge_extern: string | null; lauf_nr: number }[], roh: RohZeile[] | null): (number | null)[] {
  return zeilen.map(z => excelZeileVon(roh, z.charge_extern, z.lauf_nr))
}

/** Wo die Lieferung herkommt: Firma und Position aus der Kennung „Firma:Position:…". */
function positionAus(externId: string | null | undefined): { quelle: string; posId: number } | null {
  const m = /^([^:]+):(\d+):/.exec(externId ?? '')
  return m ? { quelle: m[1], posId: Number(m[2]) } : null
}

/** Was zu einer Position oder Lieferung geladen wird — im Fenster und, seit Runde BF, im Fall selbst. */
interface PositionDaten {
  lieferung: LieferungZeile | null; position: PositionZeile | null; zeilen: ZeileDerDatei[]; lieferungen: LieferungZeile[]
  einordnung: Einordnung | null
  /** 0121: was an dieser Zeile nicht stimmt — die Zellen dazu stehen rot umrandet. Seit 0126 aus v_perigon_befund. */
  falsch: Pick<PerigonBefund, 'schluessel' | 'art' | 'schwere' | 'satz' | 'tun' | 'wo'>[]
  /** 0125: warum ein Lieferschein keine Charge hat (v_lieferung_ohne_charge) — mit dem Satz, was zu tun ist. */
  ohneGrund: LieferungOhneCharge[]
  /** Runde BE: die Datei, aus der die Zeilen zuletzt kamen — fürs Wiederfinden im Excel */
  datei: DateiKurz | null
  ziel: { quelle: string; posId: number } | null
  geladen: boolean; fehler: string | null
}

/** Die Position (Firma und Position) oder die Lieferung laden: die Zeilen der Datei, die Lieferungen, was nicht stimmt. */
function usePosition(lieferungId: number | undefined, quelle: string | undefined, posId: number | undefined): PositionDaten {
  const [lieferung, setLieferung] = useState<LieferungZeile | null>(null)
  const [position, setPosition] = useState<PositionZeile | null>(null)
  const [zeilen, setZeilen] = useState<ZeileDerDatei[]>([])
  const [lieferungen, setLieferungen] = useState<LieferungZeile[]>([])
  const [einordnung, setEinordnung] = useState<Einordnung | null>(null)
  const [falsch, setFalsch] = useState<PositionDaten['falsch']>([])
  const [ohneGrund, setOhneGrund] = useState<LieferungOhneCharge[]>([])
  const [datei, setDatei] = useState<DateiKurz | null>(null)
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
            supabase.from('ausgang_zeile').select('datum, kunde, artikel, einheit, menge, gewicht_je_artikel, kg_position, charge_extern, batch_menge, kg_charge, liefer_label, preisgruppe, lauf_nr, datei_id')
              .eq('quelle', wo.quelle).eq('pos_id', wo.posId).order('charge_extern').order('lauf_nr'),
            supabase.from('lieferung_import').select('lieferung_id').eq('quelle', wo.quelle).like('extern_id', `${wo.quelle}:${wo.posId}:%`),
            supabase.from('v_kunde_position').select('gruppe, groesse, label').eq('quelle', wo.quelle).eq('pos_id', wo.posId),
          ])
          for (const x of [p, z, imp, e]) if (x.error) throw x.error
          const pr = await supabase.from('v_perigon_befund').select('schluessel, art, schwere, satz, tun, wo').eq('quelle', wo.quelle).eq('pos_id', wo.posId)
          if (lebt && !pr.error) setFalsch((pr.data ?? []) as PositionDaten['falsch'])
          const ids = ((imp.data ?? []) as { lieferung_id: number }[]).map(x => x.lieferung_id)
          const li = ids.length > 0
            ? await supabase.from('lieferung').select('id, datum, charge_nr, sorte, kg, kunde, bemerkung').in('id', ids).order('charge_nr')
            : { data: [], error: null }
          if (li.error) throw li.error
          await ohneGrundLaden(((li.data ?? []) as LieferungZeile[]).filter(x => x.charge_nr == null).map(x => x.id))
          const dateiIds = [...new Set(((z.data ?? []) as ZeileDerDatei[]).map(x => x.datei_id).filter((x): x is number => x != null))]
          if (dateiIds.length > 0) {
            const d = await supabase.from('ausgang_datei').select('id, dateiname, ts').in('id', dateiIds).order('ts', { ascending: false })
            if (lebt && !d.error) setDatei(((d.data ?? []) as DateiKurz[])[0] ?? null)
          }
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
  return { lieferung, position, zeilen, lieferungen, einordnung, falsch, ohneGrund, datei, ziel, geladen, fehler }
}

/** Was aus den geladenen Zeilen folgt: die Zeile wie im Excel, was rot steht, was sonst nicht stimmt. */
function auswerten(d: PositionDaten, fall?: PerigonBefund) {
  // Die Angaben der Position: aus ausgang_position, sonst aus der ersten Zeile der laufenden Saison.
  const z0 = d.zeilen[0]
  const kopf = d.position ?? (z0 ? { datum: z0.datum, kunde: z0.kunde, artikel: z0.artikel, artikel_id: '', einheit: z0.einheit, menge: z0.menge,
                                     gewicht_je_artikel: z0.gewicht_je_artikel, kg: z0.kg_position, preisgruppe: z0.preisgruppe, roh: null } : null)
  const roh = d.position?.roh ?? null
  // Die Datenbank (jsonb) merkt sich die Folge der Spalten nicht: excelAnsicht stellt sie in die Folge der
  // Datei (A bis AF) und zeigt jeden Wert im Format seiner Spalte.
  const ansicht = roh && roh.length > 0 ? excelAnsicht(roh) : null
  // Eine Lieferung ohne Charge, deren Zeile auch keine nennt: die Chargenspalte ist leer.
  const ohneCharge = d.lieferungen.some(l => l.charge_nr == null) && d.zeilen.length > 0 && d.zeilen.every(x => !x.charge_extern?.trim())
  // 0126: Was an der Position nicht stimmt, sagt v_perigon_befund (S = 0, Rest, keine Nummer, unbekannte Nummer …);
  // der Grund je Lieferschein (0125) nur noch dort, wo die Zeile selbst nichts sagt — die Zeile fehlt, oder von Hand.
  const meldungen: { art: string; befund: string; schluessel?: string }[] = [
    ...d.falsch.map(f => ({ art: f.art, befund: `${f.satz} ${f.tun}`, schluessel: f.schluessel })),
    ...d.ohneGrund.filter(g => d.falsch.length === 0 || g.grund === 'ohne_zeile' || g.grund === 'von_hand')
      .map(g => ({ art: `ohne_charge:${g.grund}`, befund: `${g.satz} ${g.tun}` })),
    ...(ohneCharge && !d.falsch.length && !d.ohneGrund.length ? [{ art: 'ohne_charge', befund: 'Auf dem Lieferschein steht keine Chargennummer. Die App verteilt die Menge darum nach Eingang auf alle Chargen derselben Sorte — für die einzelne Charge stimmt das nicht.' }] : []),
  ]
  const roteSpalten = new Set([...meldungen.flatMap(m => FALSCHE_SPALTEN[m.art] ?? []), ...d.ohneGrund.flatMap(g => OHNE_CHARGE_SPALTEN[g.grund] ?? []),
                                ...(fall ? FALSCHE_SPALTEN[fall.art] ?? [] : [])].map(schluessel))
  // 0126: Der Fall, um den es geht, steht oben — in der Liste nur, was an der Zeile sonst noch nicht stimmt.
  const zeigen = fall ? meldungen.filter(m => m.schluessel !== fall.schluessel) : meldungen
  return { kopf, roh, ansicht, roteSpalten, zeigen }
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
  const d = usePosition(lieferungId, quelle, posId)
  const { lieferung, zeilen, lieferungen, einordnung, ohneGrund, datei, ziel, geladen, fehler } = d
  const { kopf, roh, ansicht, roteSpalten, zeigen } = auswerten(d, fall)
  const deutung = kopf ? lieferungDeutung(kopf, zeilen) : []

  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape') schliessen() }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [schliessen])

  return createPortal(
    <div className="dialog-hinter" onClick={schliessen}>
      <div className="dialog breit sehr-breit" role="dialog" aria-modal="true" aria-label="Lieferung" id="lieferung-fenster" onClick={e => e.stopPropagation()}>
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
          <FallInhalt fall={fall} zeilen={zeilen} lieferungen={lieferungen} sonst={zeigen.map(m => m.befund)} excelNr={excelNrJe(zeilen, roh)} roh={roh}
                      beleg={<ZeileImExcel ansicht={ansicht} rot={roteSpalten} posId={fall.pos_id} quelle={fall.quelle} datei={datei}
                                           gemeint={fall.nummer} anzahl={zeilen.length} schliessen={schliessen} />} />
        )}
        {fall && !(geladen || fehler) && <Lade />}
        {!fall && geladen && ziel && (
          <>
            {/* Runde AT: „wirklich gleich dargestellt wie in der Excel — erste Zeile die Spaltennamen, zweite einfach
                die Einträge." Spalten in der Folge der Datei, Breiten, Formate und Ausrichtung aus der Datei, grauer
                Kopf mit Umbruch; seitlich rollbar; je Charge der Position eine Zeile. */}
            <section id="lieferung-zeile">
              {zeigen.length > 0 && (
                <div className="lieferung-falsch" id="lieferung-falsch">
                  <strong>Was an dieser Zeile nicht stimmt</strong>{ansicht && roteSpalten.size > 0 ? <span className="leise"> — die Zellen dazu sind rot umrandet</span> : null}
                  <ul>{zeigen.map((m, i) => <li key={i}>{m.befund}</li>)}</ul>
                  {d.falsch.some(f => f.schwere !== 'info') && ziel && (
                    <p className="unten-0"><Link to={`/perigon/faelle?suche=${ziel.posId}&stand=alle`} onClick={schliessen}>Im Reiter Perigon ansehen und mitverfolgen →</Link></p>
                  )}
                </div>
              )}
              <ZeileImExcel ansicht={ansicht} rot={roteSpalten} posId={ziel.posId} quelle={ziel.quelle} datei={datei}
                            gemeint={null} anzahl={zeilen.length} schliessen={schliessen} />
            </section>
            <section id="lieferung-deutung" className="lieferung-deutung">
              <h3>So wird daraus die Masse</h3>
              {deutung.length > 0 ? <ul>{deutung.map((x, i) => <li key={i}>{x}</li>)}</ul>
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

/**
 * Runde BF: eine Position im Fall selbst, ohne Fenster — wenn ein Fall genau
 * eine Position hat. Was passiert ist (ein Satz, nachgerechnet), die Zeile wie
 * im Excel, die Rechnung. Stand und Notiz stehen beim Fall, nicht hier.
 */
export function PositionImFall({ fall }: { fall: PerigonBefund }) {
  const d = usePosition(undefined, fall.quelle, fall.pos_id)
  const { roh, ansicht, roteSpalten, zeigen } = auswerten(d, fall)
  if (d.fehler) return <Hinweis art="warnung">{d.fehler}</Hinweis>
  if (!d.geladen) return <Lade />
  return (
    <FallInhalt fall={fall} zeilen={d.zeilen} lieferungen={d.lieferungen} sonst={zeigen.map(m => m.befund)} excelNr={excelNrJe(d.zeilen, roh)} roh={roh} imFall
                beleg={<ZeileImExcel ansicht={ansicht} rot={roteSpalten} posId={fall.pos_id} quelle={fall.quelle} datei={d.datei}
                                     gemeint={fall.nummer} anzahl={d.zeilen.length} schliessen={() => {}} />} />
  )
}

/** Die Kennung einer Perigon-Zeile: die Position (AufPosId). Die Chargenspalte unterscheidet die Zeilen einer Position. */
const KENNUNG = schluessel('AufPosId')
const CHARGE = schluessel('AuftragsChargeManuell')

/**
 * Runde BE: die Zeile, wie sie in der Perigon-Datei steht — sichtbar, nicht
 * hinter einem Klick, und so, dass man sie im Excel wiederfindet. Der Betrieb,
 * 24. Oktober: „du zeigst mir genau an, wie die Excel-Zeile aussieht und wie
 * ich sie im Excel wiederfinde … was identifiziert diese Zeile spezifisch,
 * irgendwie blau umrandet … damit ich mit dieser Zeile zu meinem Chef gehen
 * kann." Oben, wo sie steht (Datei, Blatt, Excel-Zeile, die Position zum
 * Suchen und Kopieren); darunter die Zeilen wie im Excel — Spaltenbuchstaben
 * oben, Zeilennummern links, die Kennung blau, was nicht stimmt rot.
 */
function ZeileImExcel({ ansicht, rot, posId, quelle, datei, gemeint, anzahl, schliessen }: {
  ansicht: ExcelAnsicht | null; rot: Set<string>; posId: number; quelle: string; datei: DateiKurz | null
  /** die Charge (Spalte W) der einen Zeile, um die es geht — sonst gelten alle Zeilen der Position */
  gemeint: string | null
  anzahl: number; schliessen: () => void
}) {
  const n = ansicht?.zeilen.length ?? anzahl
  const nr = (ansicht?.nr ?? []).filter((x): x is number => x != null)
  const dateiname = ansicht?.datei ?? datei?.dateiname ?? null
  const [kopiert, setKopiert] = useState(false)
  const kopieren = async () => {
    try { await navigator.clipboard.writeText(String(posId)); setKopiert(true); window.setTimeout(() => setKopiert(false), 1800) } catch { /* ohne Zwischenablage: die Zahl steht da */ }
  }
  const sp = (name: string, ersatz: string) => spaltenZeichen(name) ?? ersatz
  return (
    <section className="fall-block beleg" id="fall-beleg">
      <h3>{n > 1 ? `Die ${n} ganzen Zeilen` : 'Die ganze Zeile'} im Excel <span className="leise">— alle Spalten, und wie man sie findet</span></h3>
      <div className="finden" id="zeile-finden">
        <div className="finden-zeile">
          <span className="finden-was">Datei</span>
          <span>{dateiname ? <strong>{dateiname}</strong> : <span className="leise">die Perigon-Datei der Firma {quelle}</span>}
            {ansicht?.blatt && <span className="leise"> · Blatt „{ansicht.blatt}"</span>}
            {!ansicht?.datei && datei && <span className="leise"> · zuletzt eingelesen {zeitpunkt(datei.ts)}</span>}</span>
        </div>
        <div className="finden-zeile">
          <span className="finden-was">Excel-Zeile</span>
          <span>{nr.length > 0 ? <strong>{nr.join(', ')}</strong>
            : <span className="leise">kennt die App, sobald die Datei einmal neu eingelesen ist (<Link to="/betrieb/lieferungen" onClick={schliessen}>Betrieb → Warenausgang</Link>)</span>}</span>
        </div>
        <div className="finden-zeile">
          <span className="finden-was">Suchen</span>
          <span><kbd>Ctrl</kbd>+<kbd>F</kbd> <span className="leise">(Mac: <kbd>⌘</kbd>+<kbd>F</kbd>)</span>, dann{' '}
            <code className="kennung-wert" id="zeile-kennung">{posId}</code>
            <button type="button" className="klein" onClick={() => void kopieren()} id="kennung-kopieren">{kopiert ? 'kopiert' : 'kopieren'}</button>
            <span className="finden-erklaert">die Position (AufPosId, Spalte {sp('AufPosId', 'AD')}) — in jeder Perigon-Datei dieselbe; Excel findet {n === 1 ? 'eine Zeile' : `${n} Zeilen`}
              {gemeint ? <>, gemeint ist die mit Charge <strong>{gemeint}</strong> in Spalte {sp('AuftragsChargeManuell', 'W')}</> : null}.</span></span>
        </div>
      </div>
      {ansicht ? (
        <>
          <ExcelZeilen ansicht={ansicht} rot={rot} gemeint={gemeint} />
          <p className="excel-legende leise">
            <span className="legende-kennung" aria-hidden="true" /> woran man die Zeile findet ·{' '}
            <span className="legende-falsch" aria-hidden="true" /> was nicht stimmt · links die Zeilennummer, oben die Spalte wie im Excel; seitlich rollen zeigt alle Spalten.
          </p>
        </>
      ) : (
        <Hinweis art="info">Die ganze Zeile steht hier, sobald die Perigon-Datei einmal neu eingelesen ist
          (<Link to="/betrieb/lieferungen" onClick={schliessen}>Betrieb → Warenausgang</Link>) — bis Runde AS speicherte die App nur die Spalten, mit denen sie rechnet.</Hinweis>
      )}
    </section>
  )
}

/**
 * Die Zeilen der Datei wie im Excel: Spaltenbuchstaben oben, Zeilennummern
 * links (bleiben beim Rollen stehen), Spalten in der Folge der Datei mit ihren
 * Breiten und Formaten. Die Kennung (AufPosId) blau, was nicht stimmt rot; die
 * Zeile, um die es geht, links markiert. Gerollt wird gleich zur ersten roten
 * Zelle — die Datei ist über 3'800 Punkte breit.
 */
function ExcelZeilen({ ansicht, rot, gemeint }: { ansicht: ExcelAnsicht; rot: Set<string>; gemeint: string | null }) {
  const rahmen = useRef<HTMLDivElement>(null)
  const chargeSpalte = ansicht.spalten.findIndex(sp => schluessel(sp.name) === CHARGE)
  const istGemeint = (z: string[]) => gemeint != null && chargeSpalte >= 0 && z[chargeSpalte]?.trim() === gemeint
  const klasse = (name: string, rechts = false) => [rechts ? 'rechts' : '', rot.has(schluessel(name)) ? 'falsch' : '',
                                                    schluessel(name) === KENNUNG ? 'kennung' : ''].filter(Boolean).join(' ') || undefined
  useLayoutEffect(() => {
    const r = rahmen.current
    const ziel = r?.querySelector<HTMLElement>('tbody td.falsch') ?? r?.querySelector<HTMLElement>('tbody td.kennung')
    const nrBreite = r?.querySelector<HTMLElement>('tbody th')?.offsetWidth ?? 0
    if (r && ziel) r.scrollLeft = Math.max(0, ziel.offsetLeft - nrBreite - 24)
  }, [ansicht])
  return (
    <div className="rollbar excel-rahmen" ref={rahmen}>
      <table className="excel lieferung-zeile" style={{ width: ansicht.spalten.reduce((a, sp) => a + excelPx(sp.breite), 0) + 44 }}>
        <colgroup><col style={{ width: 44 }} />{ansicht.spalten.map(sp => <col key={sp.name} style={{ width: excelPx(sp.breite) }} />)}</colgroup>
        <thead>
          <tr className="excel-buchstaben">
            <th className="excel-nr" aria-label="Zeile" />
            {ansicht.spalten.map(sp => <th key={sp.name} className={klasse(sp.name)}>{sp.buchstabe ?? ''}</th>)}
          </tr>
          <tr>
            <th className="excel-nr" aria-label="Kopfzeile" />
            {ansicht.spalten.map(sp => (
              <th key={sp.name} data-spalte={sp.buchstabe ?? undefined} className={klasse(sp.name)}
                  title={sp.buchstabe ? `Spalte ${sp.buchstabe} in der Datei` : undefined}>{sp.name}</th>
            ))}
          </tr>
        </thead>
        <tbody>{ansicht.zeilen.map((z, i) => (
          <tr key={i} className={istGemeint(z) ? 'gemeint' : undefined}>
            <th scope="row" className="excel-nr">{ansicht.nr[i] ?? '·'}</th>
            {z.map((w, j) => <td key={j} className={klasse(ansicht.spalten[j].name, ansicht.spalten[j].rechts)}>{w}</td>)}
          </tr>
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

/**
 * Runde BG: die Gebinde der Position und ihrer Chargenzeile — nur, wenn die
 * Position genau eine Zeile hat. Gleich viele Gebinde bei mehr Kilo heisst:
 * wohl wurde nur das Gewicht der Position geändert. Leer heisst unbekannt.
 */
function gebindeAus(roh: RohZeile[] | null): { position: number | null; zeile: number | null } | null {
  if (!roh || roh.length !== 1) return null
  const wert = (name: string) => {
    const k = Object.keys(roh[0]).find(x => schluessel(x) === schluessel(name))
    const v = k == null ? null : roh[0][k]
    const n = v == null || v === '' ? null : Number(v)
    return n != null && Number.isFinite(n) ? n : null
  }
  return { position: wert('AuftragsGebindemenge'), zeile: wert('AufPosBatchPackageQuantity Charge') }
}

const zahlText = (x: number | null) => (x == null ? '—' : Number(x).toLocaleString('de-CH', { maximumFractionDigits: 3 }))

/**
 * Runde BD: der Fall im Fenster, in der Folge, in der man ihn versteht —
 * was nicht stimmt (ein Satz), nachgerechnet (die Zeilen der Datei, die
 * Summe, die Position, der Unterschied), was zu tun ist, das Mitverfolgen.
 * Der Betrieb, 24. Oktober: „das versteh ich nicht — wie kommst du auf
 * 768?" — es waren drei gleiche Zeilen à 256 kg, und das Fenster zeigte eine.
 * Runde BE: die Zeilen der Datei stehen gleich nach dem Satz, sichtbar —
 * „das ist ja wichtig, ist Nachvollziehbarkeit"; nur die Erklärung der Art
 * bleibt hinter einem Klick.
 */
function FallInhalt({ fall, zeilen, lieferungen, sonst, beleg, excelNr, roh, imFall = false }: {
  fall: PerigonBefund; zeilen: ZeileDerDatei[]; lieferungen: LieferungZeile[]; sonst: string[]
  /** Runde BG: die Zeilen der Datei, wie eingelesen — für die Gebinde, wenn die Position nur eine Zeile hat */
  roh: RohZeile[] | null
  /** Runde BE: die Zeile(n) der Datei, sichtbar — gleich nach dem Satz */
  beleg: ReactNode
  /** Runde BE: die Excel-Zeile je Zeile der App, in derselben Folge wie zeilen */
  excelNr: (number | null)[]
  /** Runde BF: im Fall selbst — Stand, Notiz und die Erklärung der Art stehen dort einmal für den ganzen Fall */
  imFall?: boolean
}) {
  const info = PERIGON_ART[fall.art]
  const r = nachrechnen(fall, zeilen)
  const angaben = r ? null : gegenueber(fall)
  return (
    <>
      <section className={`fall-kopf s-${fall.schwere}`} id="fall-kopf">
        <p className="fall-satz">{r?.satz ?? fall.satz}</p>
      </section>
      {/* Runde BH: erst der Ausschnitt aus dem Excel (alle Zeilen der Position, nur Q, S, W, AD) mit der Rechnung,
          dann die ganzen Zeilen mit allen Spalten als Beleg — „arbeite mehr mit Excel" */}
      {r && <ImExcel r={r} fall={fall} lieferungen={lieferungen} excelNr={excelNr} gebinde={gebindeAus(roh)} />}
      {beleg}
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
      {sonst.length > 0 && (
        <div className="lieferung-falsch" id="lieferung-falsch">
          <strong>An dieser Position stimmt noch etwas nicht</strong>
          <ul>{sonst.map((m, i) => <li key={i}>{m}</li>)}</ul>
        </div>
      )}
      {/* Runde BF: der Betrieb will verstehen, was passiert ist — „du musst uns nicht 1000 Lösungsvorschläge vorschlagen".
          Was zu tun wäre, steht darum zu, unter der Erklärung; Stand und Notiz bleiben offen sichtbar. */}
      {!imFall && <FallVerfolgen schluessel={fall.schluessel} schnappschuss={schnappschuss(fall)} />}
      {!imFall && info && (
        <Aufklapp id="fall-erklaert" titel="Wie die App damit rechnet — und was man tun könnte">
          <dl className="fall-dl">
            <dt>Was das heisst</dt><dd>{info.heisst}</dd>
            <dt>Woran man es sieht</dt><dd>{info.datei}</dd>
            <dt>Was die App daraus macht</dt><dd>{info.app}</dd>
            <dt>Was man tun könnte</dt><dd id="fall-tun">{fall.tun} <span className="wo-marke">{WO_NAME[fall.wo]?.kurz ?? fall.wo}</span></dd>
          </dl>
        </Aufklapp>
      )}
    </>
  )
}

/** Runde BH: wie die Zeile des Unterschieds unter dem Excel-Ausschnitt heisst — ein ganzer Begriff, nicht ein Wortstück */
const UNTERSCHIED_NAME: Record<string, string> = {
  'zu viel': 'Zu viel zugeteilt', 'ohne Charge': 'Ohne Charge', 'zurück': 'Zurückgenommen',
  'in der App mehr': 'In der Rechnung der App mehr', 'in der App weniger': 'In der Rechnung der App weniger',
}

/**
 * Runde BH — der Betrieb: „sorry aber ich check das noch immer nicht …
 * also sind 3 Zeilen ident? … zeig mir besser, klarer, verständlicher was
 * Sache ist, arbeite mehr mit Excel, falls es mehrere Zeilen sind, zeig mir
 * alle Zeilen, die es betrifft, übereinander." Darum zuerst das Excel selbst:
 * nur die Spalten, um die es geht (Q geliefert, S aus der Charge, W die
 * Charge, AD die Position — AE, wo in Stück verkauft wird), alle Zeilen der
 * Position untereinander mit ihrer Zeilennummer. Rechts daneben, ausserhalb
 * des Excels: Spalte S bis hier zusammen, und ob die Zeile eine davor
 * wiederholt. Darunter die Rechnung in drei Zeilen: Q einmal, S zusammen, der
 * Unterschied. Die Balken und die Erklärung „was ist eine Chargenzeile"
 * (Runde BG) sind weg — sie halfen nicht.
 */
function ImExcel({ r, fall, lieferungen, excelNr, gebinde }: {
  r: Nachrechnung; fall: PerigonBefund; lieferungen: LieferungZeile[]; excelNr: (number | null)[]
  gebinde: { position: number | null; zeile: number | null } | null
}) {
  const mitExcel = r.zeilen.length > 0 && r.zeilen.every((_, i) => excelNr[i] != null)
  const nrVon = (i: number) => (mitExcel ? String(excelNr[i]) : `${i + 1}.`)
  const Q = spaltenZeichen('AuftragsArtikelMenge') ?? 'Q'
  const S = spaltenZeichen('AufPosBatchQuantity Charge') ?? 'S'
  const W = spaltenZeichen('AuftragsChargeManuell') ?? 'W'
  const AD = spaltenZeichen('AufPosId') ?? 'AD'
  const AE = spaltenZeichen('GewichtProArtikel') ?? 'AE'
  const b = zuteilung(r, fall.art, gebinde)
  const pos = r.positionKg
  const q = fall.menge == null ? null : Number(fall.menge)
  const ae = fall.gewicht_je_artikel == null ? null : Number(fall.gewicht_je_artikel)
  const mitAE = !r.istKg
  // Was in der Zeile nicht stimmt, je Art — rot wie im ganzen Excel darunter
  const falschS = (z: (typeof b.zeilen)[number]) => (fall.art === 'zu_viel' && (z.drueber ?? 0) > 0) || (fall.art === 'menge_null' && z.s === 0)
  const falschW = (z: (typeof b.zeilen)[number]) => fall.art === 'keine_nummer' && !z.charge
  const falschQ = fall.art === 'ruecknahme'
  const falschAE = fall.art === 'ohne_gewicht'
  const gebucht = lieferungen.map(l => `${kg(l.kg, 0)} ${l.charge_nr != null ? `auf Charge ${l.charge_nr}` : 'ohne Charge'}`).join(' · ')
  const mehr = r.unterschied?.wort === 'zu viel' && (r.unterschied.kg ?? 0) > 0
  const nummern = b.zeilen.map((_, i) => nrVon(i))
  const einheitQ = r.istKg ? 'kg' : r.einheit
  return (
    <section className="fall-block" id="fall-excel">
      <h3>So steht es im Excel
        <span className="leise"> — {mitExcel ? (nummern.length === 1 ? `Zeile ${nummern[0]}` : `Zeilen ${nummern.join(', ')}`) : `${b.zeilen.length} ${b.zeilen.length === 1 ? 'Zeile' : 'Zeilen'}`}, nur die Spalten, um die es geht</span></h3>
      {b.zeilen.length === 0 ? (
        <p className="leise">Die Zeilen der Position stehen in keiner eingelesenen Datei mehr — die Summen unten sind die beim letzten Einlesen.</p>
      ) : (
        <div className="rollbar excel-rahmen excel-auszug-rahmen">
          <table className="excel excel-auszug">
            <thead>
              <tr className="excel-buchstaben">
                <th className="excel-nr" aria-label="Zeile" />
                <th>{Q}</th><th>{S}</th><th>{W}</th><th>{AD}</th>{mitAE && <th>{AE}</th>}
                <th className="excel-neben" aria-label="nicht im Excel" />
              </tr>
              <tr>
                <th className="excel-nr" aria-label="Kopfzeile" />
                <th>Auftrags<wbr />Artikel<wbr />Menge<span className="excel-heisst">geliefert, in {einheitQ}</span></th>
                <th>AufPos<wbr />Batch<wbr />Quantity Charge<span className="excel-heisst">davon aus der Charge, in {einheitQ}</span></th>
                <th>Auftrags<wbr />Charge<wbr />Manuell<span className="excel-heisst">die Charge</span></th>
                <th className="kennung">AufPosId<span className="excel-heisst">die Position</span></th>
                {mitAE && <th>Gewicht<wbr />Pro<wbr />Artikel<span className="excel-heisst">kg je {r.einheit}</span></th>}
                <th className="excel-neben">nicht im Excel<span className="excel-heisst">Spalte {S}{mitAE ? ` × ${AE}` : ''} bis hier zusammen</span></th>
              </tr>
            </thead>
            <tbody>{b.zeilen.map((z, i) => (
              <tr key={z.nr} className={z.gleichWie ? 'excel-gleich' : undefined}>
                <th scope="row" className="excel-nr">{nummern[i]}</th>
                <td className={`rechts${falschQ ? ' falsch' : ''}`}>{zahlText(q)}</td>
                <td className={`rechts${falschS(z) ? ' falsch' : ''}`}>{zahlText(z.s)}</td>
                <td className={falschW(z) ? 'falsch' : undefined}>{z.charge ?? ''}</td>
                <td className="rechts kennung">{fall.pos_id}</td>
                {mitAE && <td className={`rechts${falschAE ? ' falsch' : ''}`}>{zahlText(ae)}</td>}
                <td className="excel-neben">
                  <span className={`excel-bis${pos != null && z.bis != null && z.bis > pos + 0.0005 ? ' drueber' : ''}`}>{z.bis == null ? 'unbekannt' : kg(z.bis, 0)}</span>
                  {z.gleichWie != null && <span className="fall-gleich"> gleich wie Zeile {nummern[z.gleichWie - 1]}</span>}
                  {fall.art === 'zu_viel' && (z.drueber ?? 0) > 0 && (
                    <span className="excel-zuviel"> · {(z.innen ?? 0) > 0 ? `davon ${kg(z.drueber, 0)} zu viel` : 'ganz zu viel'}</span>
                  )}
                </td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      )}
      {/* die Rechnung Q gegen S; was zu einer Zahl zu wissen ist, steht rechts in einer eigenen Spalte, nicht in der Beschriftung */}
      <table className="dicht excel-rechnung ohne-haftkopf" id="fall-rechnung-excel">
        <tbody>
          <tr><th scope="row">Geliefert — Spalte {Q}{mitAE ? ` × ${AE}` : ''}</th>
            <td className="zahl">{pos == null ? 'unbekannt' : kg(pos, 0)}</td>
            <td className="leise">{b.zeilen.length > 1 ? 'steht auf jeder Zeile gleich und zählt einmal' : 'was auf dem Lieferschein steht'}</td></tr>
          <tr><th scope="row">Der Charge zugeteilt — Spalte {S}{mitAE ? ` × ${AE}` : ''}</th>
            <td className="zahl">{r.zugeteiltKg == null ? 'unbekannt' : kg(r.zugeteiltKg, 0)}</td>
            <td className="leise">{b.zeilen.length > 1 ? `alle ${b.zeilen.length} Zeilen zusammen` : b.zeilen.length === 1 ? `Charge ${b.zeilen[0].charge ?? '— Spalte ' + W + ' leer'}` : 'laut Datei'}</td></tr>
          {fall.art === 'masse_abweichung' && (
            <tr><th scope="row">In der Rechnung der App</th>
              <td className="zahl">{r.rechnungKg == null ? 'unbekannt' : kg(r.rechnungKg, 0)}</td>
              <td className="leise">beim letzten Einlesen</td></tr>
          )}
          {r.unterschied && (
            <tr className="fall-unterschied"><th scope="row">{UNTERSCHIED_NAME[r.unterschied.wort] ?? r.unterschied.wort}</th>
              <td className="zahl">{r.unterschied.kg == null ? 'unbekannt' : kg(Math.abs(r.unterschied.kg), 0)}</td><td /></tr>
          )}
        </tbody>
      </table>
      {b.woran && <p className="zt-woran"><strong>Woran es wohl liegt:</strong> {b.woran}</p>}
      {lieferungen.length > 0 && (
        <p className="leise unten-0">In der Rechnung der App: {gebucht}.{mehr ? ' So viel, wie geliefert wurde — eure Lagerzahlen stimmen; zu gross ist nur die Zuteilung in Perigon.' : ''}</p>
      )}
    </section>
  )
}
