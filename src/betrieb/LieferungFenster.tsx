import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg } from '../lib/format'
import { excelAnsicht, lieferungDeutung, schluessel, type ChargenzeileKurz, type RohZeile } from '../lib/warenausgang'
import { FALSCHE_SPALTEN, OHNE_CHARGE_GRUND, OHNE_CHARGE_SPALTEN } from '../auswertung/ungereimt'
import type { LieferungOhneCharge, PerigonBefund } from '../auswertung/daten'
import { PERIGON_ART, WO_NAME, betroffen, schnappschuss, spaltenZeichen } from '../auswertung/perigon'
import { FallVerfolgen } from '../auswertung/Verfolgen'
import { Hinweis, Lade } from '../components/Bausteine'
import { ZKreuz } from '../components/Zeichen'

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
        {fall && <FallKopf fall={fall} />}
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {!geladen && !fehler && <Lade />}
        {geladen && !ziel && lieferung && (
          <p>Diese Lieferung kommt aus keiner Perigon-Datei — sie ist von Hand erfasst: {kg(lieferung.kg, 0)}
            {lieferung.charge_nr != null ? ` aus Charge ${lieferung.charge_nr}` : ''}{lieferung.kunde ? ` an ${lieferung.kunde}` : ''}
            {lieferung.bemerkung ? ` (${lieferung.bemerkung})` : ''}.</p>
        )}
        {geladen && !ziel && ohneGrund.map(g => (
          <div key={g.id} className="lieferung-falsch" id="lieferung-falsch">
            <strong>Warum ohne Charge: {OHNE_CHARGE_GRUND[g.grund] ?? g.grund}</strong>
            <ul><li>{g.satz} {g.tun}</li></ul>
          </div>
        ))}
        {geladen && ziel && (
          <>
            {/* Runde AT: „wirklich gleich dargestellt wie in der Excel — erste Zeile die Spaltennamen, zweite einfach
                die Einträge." Spalten in der Folge der Datei, Breiten, Formate und Ausrichtung aus der Datei, grauer
                Kopf mit Umbruch; seitlich rollbar; je Charge der Position eine Zeile. */}
            <section id="lieferung-zeile">
              <h3 className="oben-0">Die Zeile in der Perigon-Datei</h3>
              {fall && zeigen.length === 0 && ansicht && roteSpalten.size > 0 && <p className="leise oben-0">Die Zellen, um die es geht, sind rot umrandet.</p>}
              {zeigen.length > 0 && (
                <div className="lieferung-falsch" id="lieferung-falsch">
                  <strong>{fall ? 'Was an dieser Zeile sonst nicht stimmt' : 'Was an dieser Zeile nicht stimmt'}</strong>{ansicht && roteSpalten.size > 0 ? <span className="leise"> — die Zellen dazu sind rot umrandet</span> : null}
                  <ul>{zeigen.map((m, i) => <li key={i}>{m.befund}</li>)}</ul>
                  {!fall && falsch.some(f => f.schwere !== 'info') && ziel && (
                    <p className="unten-0"><Link to={`/perigon/zeilen?suche=${ziel.posId}&stand=alle`} onClick={schliessen}>Im Reiter Perigon ansehen und mitverfolgen →</Link></p>
                  )}
                </div>
              )}
              {ansicht ? (
                <div className="rollbar excel-rahmen">
                  <table className="excel lieferung-zeile" style={{ width: ansicht.spalten.reduce((a, sp) => a + excelPx(sp.breite), 0) }}>
                    <colgroup>{ansicht.spalten.map(sp => <col key={sp.name} style={{ width: excelPx(sp.breite) }} />)}</colgroup>
                    <thead><tr>{ansicht.spalten.map(sp => (
                      <th key={sp.name} data-spalte={sp.buchstabe ?? undefined} className={roteSpalten.has(schluessel(sp.name)) ? 'falsch' : undefined}
                          title={sp.buchstabe ? `Spalte ${sp.buchstabe} in der Datei` : undefined}>{sp.name}</th>
                    ))}</tr></thead>
                    <tbody>{ansicht.zeilen.map((z, i) => (
                      <tr key={i}>{z.map((w, j) => <td key={j} className={[ansicht.spalten[j].rechts ? 'rechts' : '', roteSpalten.has(schluessel(ansicht.spalten[j].name)) ? 'falsch' : ''].filter(Boolean).join(' ') || undefined}>{w}</td>)}</tr>
                    ))}</tbody>
                  </table>
                </div>
              ) : (
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
        {fall && <FallVerfolgen schluessel={fall.schluessel} schnappschuss={schnappschuss(fall)} />}
      </div>
    </div>,
    document.body,
  )
}

/**
 * 0126: Der Fall, um den es geht, ganz oben — was nicht stimmt, die Rechnung
 * aus den Spalten der Datei, was die App daraus macht, was zu tun ist und wo
 * man die Zeile in der Datei findet.
 */
function FallKopf({ fall }: { fall: PerigonBefund }) {
  const info = PERIGON_ART[fall.art]
  const zahlText = (x: number | null) => (x == null ? '—' : Number(x).toLocaleString('de-CH', { maximumFractionDigits: 3 }))
  const b = betroffen(fall)
  return (
    <section className={`fall-kopf s-${fall.schwere}`} id="fall-kopf">
      <h3 className="oben-0"><span className={`punkt s-${fall.schwere}`} aria-hidden="true" />{info?.name ?? fall.art}
        {b != null && <span className="leise"> · {kg(b, 0)}</span>}</h3>
      <p className="fall-satz">{fall.satz}</p>
      <div className="rollbar">
        <table className="dicht fall-rechnung ohne-haftkopf">
          <tbody>
            <tr><th scope="row">Menge der Position <span className="leise">(Spalte {spaltenZeichen('AuftragsArtikelMenge') ?? 'Q'})</span></th>
              <td className="zahl">{zahlText(fall.menge)} {fall.einheit ?? ''}</td></tr>
            <tr><th scope="row">Gewicht je Artikel <span className="leise">(Spalte {spaltenZeichen('GewichtProArtikel') ?? 'AE'})</span></th>
              <td className="zahl">{fall.gewicht_je_artikel == null ? 'leer'
                : Number(fall.gewicht_je_artikel) === 0 && /^kg/i.test(fall.einheit ?? '') ? <>0 <span className="leise">— bei kg ist die Menge das Kilo</span></>
                : zahlText(fall.gewicht_je_artikel)}</td></tr>
            <tr><th scope="row">Masse der Position</th><td className="zahl">{fall.kg_position == null ? 'unbekannt' : kg(fall.kg_position, 1)}</td></tr>
            <tr><th scope="row">den Chargen zugeteilt <span className="leise">(Spalte {spaltenZeichen('AufPosBatchQuantity Charge') ?? 'S'})</span></th>
              <td className="zahl">{kg(fall.kg_zugeteilt, 1)}{fall.nummern ? <span className="leise"> · {fall.nummern}</span> : null}</td></tr>
            <tr><th scope="row">in der Rechnung der App</th>
              <td className="zahl">{fall.kg_rechnung == null ? 'keine Lieferung' : kg(fall.kg_rechnung, 1)}
                {fall.kg_ohne_charge != null && fall.kg_ohne_charge > 0 && <span className="leise"> · davon {kg(fall.kg_ohne_charge, 1)} ohne Charge</span>}</td></tr>
          </tbody>
        </table>
      </div>
      <dl className="fall-dl">
        {info && <><dt>Was das heisst</dt><dd>{info.heisst}</dd>
          <dt>Was die App daraus macht</dt><dd>{info.app}</dd></>}
        <dt>Was tun</dt><dd>{fall.tun} <span className="wo-marke">{WO_NAME[fall.wo]?.kurz ?? fall.wo}</span></dd>
        <dt>In der Datei finden</dt><dd>Die Datei der Firma öffnen, Ctrl+F, die Position <strong>{fall.pos_id}</strong> suchen
          (Spalte {spaltenZeichen('AufPosId') ?? 'AD'}, AufPosId){fall.nummer ? <> — die Chargenzeile mit {fall.nummer}</> : null}.</dd>
      </dl>
    </section>
  )
}
