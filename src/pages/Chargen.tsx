import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { TaetZeichen, ZChevron } from '../components/Zeichen'
import { Link, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { taetigkeitVon } from '../lib/taetigkeit'
import { WOERTERBUCH } from '../lib/i18n'
import { datum, kg, prozent, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Erklaerung, Herkunft, Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import { lieferungenVon, useAuswertung, type Auswertung } from '../auswertung/daten'
import { IM_LAGER_TEXT, imLagerCharge, palettenText } from '../auswertung/lager'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { Ungereimtheiten } from '../auswertung/Ungereimtheiten'
import { ungereimtheiten, vonCharge, type Ungereimtheit } from '../auswertung/ungereimt'
import { ausweisVon, summiere } from '../auswertung/ausweis'
import { LagerLeiste, LagerRechnung } from '../auswertung/LagerKette'
import { ZWarnung } from '../components/Zeichen'
import type { Auftrag } from '../lib/typen'
import { herkunftText, summeBekannt } from '../lib/masse'
import { LieferungFenster } from '../betrieb/LieferungFenster'
import { useAuth } from '../auth/AuthProvider'
import { fehlerText } from '../lib/db'

/** Wonach die Tabelle sortiert ist — der Betriebsleiter wählt es mit einem Klick auf den Kopf. */
type Sortierung = 'nr' | 'lager' | 'verkaufsfaehig' | 'eingang'

/**
 * Chargen: eine Zeile je Charge — Eingang (Kilo, Paletten, von–bis),
 * ausgeliefert (und wie viel Eingangsware dafür aus dem Lager ging), im
 * Lager (≈ Paletten), davon verkaufsfähig, Verlust bis heute. Aufgeklappt
 * wird dieselbe Zeile grösser: ein paar Sätze, die die Zahlen der Zeile
 * erklären, dann Eingang, Ausgang und Arbeiten der Charge.
 *
 * Runde AO (12. Oktober): „lieber nur die eine Tabelle … wenn ich eine
 * Charge aufklappe, wird einfach diese Zeile grösser". Weg sind „in vier
 * Wochen", „zwei Wochen länger", „liegt seit", die Messungszähler und die
 * zweite Zahlenzeile im Aufgeklappten („Kaskade am Band / CSV gewogen").
 */
export default function Chargen() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const [suche, setSuche] = useSearchParams()
  const [sorte, setSorte] = useState('')
  const [nurBestand, setNurBestand] = useState(false)
  // 22. Oktober, der Betrieb: „why the hell sind die nicht nach Nummer geordnet — das ist so ein Pain,
  // dort eine Charge zu finden." Zuerst nach Nummer; die Masse sortiert ein Klick auf ihren Kopf.
  const [nach, setNach] = useState<Sortierung>('nr')
  const [finden, setFinden] = useState('')
  const offen = Number(suche.get('charge') ?? 0) || null
  // Runde AS (0116): der Hagelschaden je Charge, vom Betriebsleiter gesetzt
  const { istAdmin } = useAuth()
  const [hagel, setHagel] = useState<Map<number, number>>(new Map())
  const hagelLaden = () => void supabase.from('charge').select('nr, hagel_anteil').not('hagel_anteil', 'is', null).then(r => {
    if (!r.error) setHagel(new Map(((r.data ?? []) as { nr: number; hagel_anteil: number }[]).map(c => [c.nr, Number(c.hagel_anteil)])))
  })
  useEffect(hagelLaden, [])

  const zeilen = useMemo(() => {
    if (!daten) return []
    // 23. Oktober: Im Lager sind die Paletten vom Eingang, die noch stehen, mit
    // dem Gewicht beim Eingang (src/auswertung/lager.ts); verkaufsfähig ist,
    // was davon als Artikel verkauft werden kann (v_lager_ausweis.verkaufbar_kg,
    // 0123), der Anteil der an dieser Zahl. Ist eine Rate nicht gemessen oder
    // fehlt der Ausweis, bleibt es leer — nie der Wert der Sortiermaschine.
    const liste = daten.bestand.map(b => {
      const lager = b.lager_kg > 0 ? imLagerCharge(b) : 0
      const aw = ausweisVon(daten.ausweis, b.charge_nr)
      const vf = aw?.verkaufbar_kg != null ? Number(aw.verkaufbar_kg) : null
      return {
        b, lager, vf, offen: aw?.verkaufbar_offen ?? null,
        l: daten.lage.find(x => x.charge_nr === b.charge_nr),
        heute: vf === null || !(lager > 0) ? null : Math.min(vf / lager, 1),
      }
    }).filter(z => (!sorte || z.b.sorte === sorte) && (!nurBestand || z.b.lager_kg > 0) && passt(z.b, finden))
    // Beim Anteil steht der **schlechteste** oben: Das ist die Charge, die
    // zuerst raus sollte. Eine Charge ohne Zahl steht in jedem Fall hinten —
    // „unbekannt" ist weder gut noch schlecht.
    const hinten = (x: number | null) => x === null ? Infinity : x
    return liste.sort((a, c) => {
      if (nach === 'nr') return a.b.charge_nr - c.b.charge_nr
      if (nach === 'verkaufsfaehig') return hinten(a.heute) - hinten(c.heute)
      if (nach === 'eingang') return (a.b.eingang_von ?? '9999').localeCompare(c.b.eingang_von ?? '9999')
      return c.lager - a.lager
    })
  }, [daten, sorte, nurBestand, nach, finden])

  // 0121: was zwischen Perigon und Lager nicht passt — je Charge ein Zeichen in der Zeile, und
  // Chargen, die verkauft haben, ohne je eine Palette zu bekommen, stehen als eigene Zeile da.
  const ungereimt = useMemo(() => daten ? ungereimtheiten(daten.ungereimt, daten.perigon) : [], [daten])
  const ohneEingang = useMemo(() => (daten?.ungereimt ?? [])
    .filter(u => u.art === 'ohne_eingang' && u.charge_nr != null && !daten?.bestand.some(b => b.charge_nr === u.charge_nr))
    .filter(u => (!sorte || u.sorte === sorte) && !nurBestand && passt({ charge_nr: u.charge_nr!, schlag: u.schlag, sorte: u.sorte ?? '' }, finden)),
  [daten, sorte, nurBestand, finden])

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  // Runde AJ: die zweite Welle der Ergebnisse (dieser Reiter braucht sie) kommt nach dem Lagermanagement.
  if (daten && !daten.vollstaendig) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort()
  const summeLager = zeilen.reduce((a, z) => a + z.lager, 0)
  // Die Summe nur über Chargen mit Ware: eine ausgelieferte Charge hat keinen Ausweis, aber auch nichts zu verkaufen.
  const summeVerkaufsfaehig = summeBekannt(zeilen.filter(z => z.lager > 0).map(z => z.vf))
  const summeHoechstens = zeilen.some(z => z.lager > 0 && z.offen)
  const summeGeliefert = zeilen.reduce((a, z) => a + z.b.geliefert_kg, 0)
  /**
   * Ein Spaltenkopf, der sortiert. Der Pfeil zeigt, wohin: Bei der Masse
   * steht das Grösste oben (↓), beim Anteil das Kleinste (↑) — dort ist klein
   * das Dringende —, beim Eingang das Älteste.
   */
  const Kopf = ({ id, children, zahlspalte = true }: { id: Sortierung; children: ReactNode; zahlspalte?: boolean }) => {
    const auf = id === 'nr' || id === 'verkaufsfaehig' || id === 'eingang'
    return (
      <th className={zahlspalte ? 'zahl' : undefined}>
        <button type="button" onClick={() => setNach(id)} aria-pressed={nach === id}
                style={{ font: 'inherit', color: 'inherit', textTransform: 'inherit', letterSpacing: 'inherit', textAlign: 'inherit', background: 'none', border: 0, padding: 0, cursor: 'pointer' }}>
          {children}{nach === id && <span aria-hidden="true"> {auf ? '↑' : '↓'}</span>}
        </button>
      </th>
    )
  }

  return (
    <>
      <Reiterkopf titel="Chargen"
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt}
                  zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
      <Probleme liste={daten.probleme} />
      <Ungereimtheiten daten={daten} />
      <Karte>
        <div className="filterleiste">
          <input type="search" value={finden} onChange={e => setFinden(e.target.value)} aria-label="Charge finden"
                 placeholder="Nr. oder Schlag" style={{ width: '11rem', minHeight: 36 }} />
          <select value={sorte} onChange={e => setSorte(e.target.value)} aria-label="Sorte">
            <option value="">alle Sorten</option>{sorten.map(s => <option key={s}>{s}</option>)}
          </select>
          <label className="ankreuzen" style={{ minHeight: 36 }}>
            <input type="checkbox" checked={nurBestand} onChange={e => setNurBestand(e.target.checked)} /> nur mit Bestand
          </label>
          <span className="nach-rechts">
            {zeilen.length} Chargen · ausgeliefert <strong>{tonnen(summeGeliefert)}</strong> · im Lager <strong>{tonnen(summeLager)}</strong> · davon verkaufsfähig <strong>{summeHoechstens && summeVerkaufsfaehig !== null ? 'höchstens ' : ''}{tonnen(summeVerkaufsfaehig)}</strong>
          </span>
          <span className="herkunft-legende">Eingang, ausgeliefert<Herkunft art="gemessen" /> · im Lager, verkaufsfähig, Verlust<Herkunft art="gerechnet" /></span>
        </div>
        <div className="rollbar">
          <table className="umbruch chargentabelle">
            <thead>
              <tr>
                <th style={{ width: 28 }} aria-label="aufklappen" />
                <Kopf id="nr" zahlspalte={false}>Charge</Kopf><th>Sorte</th>
                <th className="zahl">Eingang</th><th className="zahl">Paletten</th>
                <Kopf id="eingang" zahlspalte={false}>Eingang am</Kopf>
                <th className="zahl">Ausgeliefert</th>
                <Kopf id="lager"><span title={`Im Lager ist ${IM_LAGER_TEXT}`}>Im Lager</span></Kopf>
                <Kopf id="verkaufsfaehig">Davon verkaufsfähig</Kopf>
                <th className="zahl">Verlust bis heute</th>
                <th className="zahl" title="Hagelschaden der Charge in Prozent des Eingangs — kommt beim Waschen und Sortieren in den Palox">Hagel</th>
              </tr>
            </thead>
            <tbody>
              {mischen(zeilen, ohneEingang, nach === 'nr').map(e => e.z ? (
                <ChargenZeile key={e.z.b.charge_nr} z={e.z} offen={offen === e.z.b.charge_nr} daten={daten}
                              ungereimt={vonCharge(ungereimt, e.z.b.charge_nr)}
                              oeffnen={() => setSuche(offen === e.z!.b.charge_nr ? {} : { charge: String(e.z!.b.charge_nr) })}
                              hagel={<HagelZelle nr={e.z.b.charge_nr} anteil={hagel.get(e.z.b.charge_nr) ?? null} darf={istAdmin} neu={hagelLaden} />} />
              ) : (
                <OhneEingangZeile key={`ohne-${e.u!.charge_nr}`} u={e.u!} offen={offen === e.u!.charge_nr} daten={daten}
                                  oeffnen={() => setSuche(offen === e.u!.charge_nr ? {} : { charge: String(e.u!.charge_nr) })} />
              ))}
            </tbody>
          </table>
        </div>
        <Erklaerung>
          <p>Eingang und ausgeliefert sind <Herkunft art="gemessen" />. <strong>Ausgeliefert</strong> ist die Masse der Lieferscheine; darunter steht,
          wie viel Eingangsware dafür aus dem Lager ging — mehr, weil unterwegs Wasser verdunstet, Faules in den Palox geht und zu Kleines oder zu Grosses aussortiert wird.</p>
          <p><strong>Im Lager</strong> sind die Paletten vom Eingang, die noch dastehen — so viele triffst du im Lager etwa an —, darunter ihr
          Gewicht beim Eingang <Herkunft art="gerechnet" />, vor Verdunstung, Palox und Arbeit.
          <strong> Davon verkaufsfähig</strong> ist, was davon als Artikel verkauft werden kann: ohne Verdunstetes, Faules, zu klein und zu gross,
          ohne was in kein Artikelgewicht passt und ohne Überfüllung in den Kisten; Unique (Hagel, als Knospe verkauft) zählt mit. „höchstens":
          die Überfüllung ist nicht gewogen oder die Sortier-CSV fehlt. Die Leiste darunter zeigt den Weg von der Ware, wie sie einging, zum
          Verkaufsfähigen. Aufgeklappt steht er Schritt für Schritt.
          Ein Klick auf einen Spaltenkopf sortiert danach — nach „davon verkaufsfähig" steht oben, was am wenigsten übersteht.</p>
        </Erklaerung>
      </Karte>
    </>
  )
}

/**
 * Hagelschaden je Charge (Runde AS, 0116). Der Betrieb: „ein Kästchen, und
 * wenn ich das Kreuz mache, ein Feld, wo ich die Prozent eingebe … wenn 20 %
 * Hagelschaden, dann ist 20 % vom Wareneingang nicht mehr verfügbar." Der
 * Hagel kommt beim Waschen und Sortieren in den Palox; die Rechnung zählt ihn
 * dort, wo noch keine Messung der Charge ihn schon enthält — ab der nächsten
 * Rechnung.
 */
function HagelZelle({ nr, anteil, darf, neu }: { nr: number; anteil: number | null; darf: boolean; neu: () => void }) {
  const [offen, setOffen] = useState(false)
  const [wert, setWert] = useState(anteil != null ? String(Math.round(anteil * 1000) / 10) : '')
  const [fehler, setFehler] = useState<string | null>(null)
  const prozentWert = Number(wert.replace(',', '.'))
  const gueltig = wert.trim() !== '' && Number.isFinite(prozentWert) && prozentWert > 0 && prozentWert <= 100
  async function speichern(neuerAnteil: number | null) {
    setFehler(null)
    const r = await supabase.from('charge').update({ hagel_anteil: neuerAnteil, hagel_ts: new Date().toISOString() }).eq('nr', nr)
    if (r.error) { setFehler(fehlerText(r.error)); return }
    setOffen(false); neu()
  }
  return (
    <td className="zahl hagel-zelle" onClick={e => e.stopPropagation()}>
      {darf && (
        <input type="checkbox" aria-label={`Hagelschaden an Charge ${nr}`} checked={anteil != null || offen}
               onChange={e => { if (e.target.checked) setOffen(true); else if (anteil != null) void speichern(null); else setOffen(false) }} />
      )}
      {!offen && anteil != null && (
        <button type="button" className="werkzeug-knopf" disabled={!darf} onClick={() => setOffen(true)} title="Hagelschaden ändern">{prozent(anteil, 0)}</button>
      )}
      {!offen && anteil == null && !darf && <span className="leise">—</span>}
      {offen && (
        <form className="hagel-feld" onSubmit={e => { e.preventDefault(); if (gueltig) void speichern(prozentWert / 100) }}>
          <input type="text" inputMode="decimal" autoFocus value={wert} onChange={e => setWert(e.target.value)} aria-label="Hagelschaden in Prozent"
                 onKeyDown={e => { if (e.key === 'Escape') setOffen(false) }} />
          <span className="leise">%</span>
          <button type="submit" className="werkzeug-knopf" disabled={!gueltig}>speichern</button>
        </form>
      )}
      {fehler && <span className="zelle-unter fehler-text">{fehler}</span>}
    </td>
  )
}

/** Runde AD: „—" beim Verlust sagt, WELCHER Strom noch keine Messung hat —
 *  der Betrieb fragte „warum?". Vier Ströme, jeder mit Koeffizient; fehlt
 *  einer, ist die Summe unbekannt, nicht die Summe der übrigen (0064). */
function verlustTitel(b: Auswertung['bestand'][number]): string {
  if (b.verlust_heute_kg !== null) return 'Verdunstung + Faules im Palox (Faules und Mängel im Lager) + Faules beim Abpacken, gerechnet bis heute'
  const fehlt = [
    !b.verdunstung_bekannt && 'Verdunstung (keine Wägung einer Palette nach Lagerung)',
    !b.schimmel_bekannt && 'Faules im Palox (keine Ablesung mit Nenner)',
    !b.fax_bekannt && 'Faules beim Abpacken',
    !b.kanal_bekannt && 'zu klein / zu gross',
  ].filter(Boolean)
  return `unbekannt, solange nicht gemessen: ${fehlt.join(' · ') || 'ein Koeffizient ohne Messung'}`
}

type Zeile = { b: Auswertung['bestand'][number]; lager: number; vf: number | null; offen: string | null; l?: Auswertung['lage'][number]; heute: number | null }

/** Das Suchfeld: eine Zahl sucht im Anfang der Nummer („16" → 1601 … 1699), sonst im Schlag und in der Sorte. */
function passt(b: { charge_nr: number; schlag: string | null; sorte: string }, finden: string): boolean {
  const f = finden.trim().toLowerCase()
  if (!f) return true
  if (/^\d+$/.test(f)) return String(b.charge_nr).startsWith(f)
  return (b.schlag ?? '').toLowerCase().includes(f) || b.sorte.toLowerCase().includes(f)
}

/** Der Eingang als Spanne: „2.9. – 18.9." oder ein Tag. */
function eingangSpanne(b: Auswertung['bestand'][number]): string {
  const von = b.eingang_von ?? b.eingangsdatum_mittel
  if (!von) return '—'
  const kurz = (d: string) => datum(d).slice(0, 6)
  return b.eingang_bis && b.eingang_bis !== von ? `${kurz(von)} – ${kurz(b.eingang_bis)}` : kurz(von)
}

/** Die Zeilen der Tabelle: Chargen mit Eingang und solche ohne — nach Nummer gemischt, sonst die ohne Eingang zuerst (sie sind ein Fehler). */
function mischen(zeilen: Zeile[], ohne: Auswertung['ungereimt'], nachNummer: boolean): { z?: Zeile; u?: Auswertung['ungereimt'][number] }[] {
  const a = zeilen.map(z => ({ nr: z.b.charge_nr, z })), o = ohne.map(u => ({ nr: u.charge_nr ?? 0, u }))
  return nachNummer ? [...a, ...o].sort((x, y) => x.nr - y.nr) : [...o, ...a]
}

/** Das Zeichen hinter der Nummer, wenn Perigon und Lager bei dieser Charge nicht zusammenpassen. */
function UngereimtMal({ liste }: { liste: Ungereimtheit[] }) {
  const ernst = liste.filter(u => u.schwere !== 'info')
  if (ernst.length === 0) return null
  return <span className={`ungereimt-mal${ernst.some(u => u.schwere === 'rot') ? '' : ' gelb'}`} title={ernst.map(u => u.titel).join('\n')}
               aria-label="Perigon und Lager passen nicht zusammen"><ZWarnung size={14} /></span>
}

/** Eine Charge, die verkauft hat, aber im Erntejournal nie eine Palette bekam (wie 1627 vor der Umbuchung). */
function OhneEingangZeile({ u, offen, oeffnen, daten }: { u: Auswertung['ungereimt'][number]; offen: boolean; oeffnen: () => void; daten: Auswertung }) {
  return (
    <>
      <tr onClick={oeffnen} className={`klickbar ohne-eingang${offen ? ' offen' : ''}`} aria-expanded={offen}>
        <td><span className="chevron" style={{ display: 'inline-flex', color: 'var(--text-leise)', transform: offen ? 'rotate(90deg)' : undefined }}><ZChevron size={16} /></span></td>
        <td><strong>{u.charge_nr}</strong><span className="ungereimt-mal" aria-label="verkauft, nie eingegangen"><ZWarnung size={14} /></span> <span className="leise nowrap">{u.schlag}</span></td>
        <td>{u.sorte}</td>
        <td className="zahl" colSpan={3}><Marke art="warnung">kein Eingang im Erntejournal</Marke></td>
        <td className="zahl">{kg(u.kg, 0)}</td>
        <td className="zahl" colSpan={4}><span className="leise">verkauft, aber nie eingegangen</span></td>
      </tr>
      {offen && <tr className="aufgeklappt"><td colSpan={11} className="detail"><Ungereimtheiten daten={daten} charge={u.charge_nr ?? undefined} /></td></tr>}
    </>
  )
}

function ChargenZeile({ z, offen, oeffnen, daten, hagel, ungereimt }: { z: Zeile; offen: boolean; oeffnen: () => void; daten: Auswertung; hagel: ReactNode; ungereimt: Ungereimtheit[] }) {
  const { b } = z
  const liegt = b.lager_kg > 0
  const ausweis = ausweisVon(daten.ausweis, b.charge_nr)
  const kette = ausweis ? summiere([ausweis]) : null
  return (
    <>
      <tr onClick={oeffnen} className={`klickbar${offen ? ' offen' : ''}`} aria-expanded={offen}>
        <td><span className="chevron" style={{ display: 'inline-flex', color: 'var(--text-leise)', transition: 'transform var(--d-mittel)', transform: offen ? 'rotate(90deg)' : undefined }}><ZChevron size={16} /></span></td>
        <td><strong>{b.charge_nr}</strong><UngereimtMal liste={ungereimt} /> <span className="leise nowrap">{b.schlag}</span></td>
        <td>{b.sorte}</td>
        <td className="zahl">{kg(b.eingang_kg, 0)}</td>
        <td className="zahl">{zahl(b.n_paletten)}</td>
        <td className="nowrap">{eingangSpanne(b)}</td>
        <td className="zahl">{b.n_lieferungen > 0
          ? <>{kg(b.geliefert_kg, 0)}{b.ausgelagert_kg > 0 && <span className="zelle-unter" title="So viel Eingangsware ging für diese Lieferungen aus dem Lager — mehr als geliefert, weil unterwegs verdunstet, im Palox gelandet oder aussortiert">aus {kg(b.ausgelagert_kg, 0)} Eingang</span>}</>
          : <span className="leise">—</span>}</td>
        {/* 0121: zuerst die Paletten — „so viele wirst du im Lager wohl antreffen" —, darunter die Kilo darauf. */}
        <td className="zahl">{liegt
          ? <>{b.n_rest_paletten != null
                ? <strong title="die Eingangspaletten, die noch da sind: Eingangsmasse, die nicht ausgeliefert ist, durch die mittlere Eingangspalette der Charge">{palettenText(b.n_rest_paletten)}</strong>
                : <strong>{kg(z.lager, 0)}</strong>}
              {b.n_rest_paletten != null && <span className="zelle-unter" title={`Im Lager ist ${IM_LAGER_TEXT}`}>{kg(z.lager, 0)}</span>}</>
          : <span className="leise">—</span>}</td>
        <td className="zahl">{liegt && z.vf !== null
          ? <>{z.offen && <span className="mini-wort zelle-oben" title={`noch offen: ${z.offen}`}>höchstens</span>}{kg(z.vf, 0)}{z.heute !== null && <span className="leise"> · {prozent(z.heute, 0)}</span>}
              {kette && <span className="zelle-leiste"><LagerLeiste s={kette} /></span>}</>
          : <span className="leise">—</span>}</td>
        <td className="zahl" title={verlustTitel(b)}>{kg(b.verlust_heute_kg, 0)}</td>
        {hagel}
      </tr>
      {offen && (
        <tr className="aufgeklappt"><td colSpan={11} className="detail">
          {ungereimt.length > 0 && <Ungereimtheiten daten={daten} charge={b.charge_nr} />}
          <ChargeDetail nr={b.charge_nr} z={z} daten={daten} />
        </td></tr>
      )}
    </>
  )
}

function ChargeDetail({ nr, z, daten }: { nr: number; z: Zeile; daten: Auswertung }) {
  const [arbeiten, setArbeiten] = useState<(Auftrag & { masse_kg: number | null; masse_quelle: string | null })[]>([])
  const [lieferungen, setLieferungen] = useState<{ id: number; datum: string; ziel_name: string; kunde: string | null; masse_kg: number | null; masse_quelle: string }[]>([])
  const [laedt, setLaedt] = useState(true)
  // Runde AS: die Lieferung als Fenster — die ganze Perigon-Zeile und die Rechnung der Masse
  const [lieferung, setLieferung] = useState<number | null>(null)
  useEffect(() => {
    let weg = false
    void (async () => {
      const [a, m, li] = await Promise.all([
        supabase.from('auftrag').select('*').eq('charge_nr', nr).order('start_ts', { ascending: false }),
        supabase.from('v_auftrag_masse').select('auftrag_id, eingang_netto_kg, masse_quelle').eq('charge_nr', nr),
        supabase.from('erg_lieferung').select('id, datum, ziel_name, kunde, masse_kg, masse_quelle').eq('charge_nr', nr).order('datum', { ascending: false }),
      ])
      if (weg) return
      type M = { auftrag_id: number; eingang_netto_kg: number | null; masse_quelle: string | null }
      const massen = new Map(((m.data ?? []) as M[]).map(x => [x.auftrag_id, x]))
      setArbeiten(((a.data ?? []) as Auftrag[]).map(x => ({ ...x, masse_kg: massen.get(x.id)?.eingang_netto_kg ?? null, masse_quelle: massen.get(x.id)?.masse_quelle ?? null })))
      setLieferungen((li.data ?? []) as typeof lieferungen)
      setLaedt(false)
    })()
    return () => { weg = true }
  }, [nr])
  const alter = daten.verarbeitung.filter(x => x.charge_nr === nr)
  const kohorten = daten.kohorten.filter(x => x.charge_nr === nr)
  const t = (id: keyof typeof WOERTERBUCH.de) => WOERTERBUCH.de[id]
  if (laedt) return <Lade zeilen={2} />
  const b = z.b
  // 0114: Lieferscheine ohne Chargennummer nehmen anteilig von jeder Charge
  // ihrer Sorte — sie zählen hier mit, stehen aber nicht in der Liste unten.
  const ohneNummer = lieferungenVon(daten.lieferungGruppe, 'charge', String(nr))?.n_ohne_charge ?? 0
  const einZiel = lieferungen.every(l => l.ziel_name === lieferungen[0]?.ziel_name)
  const mz = (n: number, ein: string, mehr: string) => `${zahl(n)} ${n === 1 ? ein : mehr}`
  // 0121: der Weg von der Ware, wie sie einging, zum Verkaufsfähigen — Schritt für Schritt.
  const aw = ausweisVon(daten.ausweis, nr)
  const hagelBisHeute = aw?.hagel_bis_heute_kg != null ? Number(aw.hagel_bis_heute_kg) : 0
  return (
    <div className="wechsel">
      {aw && Number(aw.eingang_kg) > 0 && (
        <section className="detail-kette">
          <h3 className="oben-0">Was im Lager steht — und was davon verkaufsfähig ist</h3>
          <LagerRechnung s={summiere([aw])}
                         fuss={aw.marge_anteil != null && Number(aw.ueberfuellung_kg) > 0.5 ? <p className="leise unten-0">Überfüllung: {aw.marge_quelle}.</p> : undefined} />
        </section>
      )}
      {/* Runde AO: keine zweite Zahlenreihe mehr — die Zahlen stehen in der
          Zeile darüber. Runde AS: und auch keine Sätze mehr („16 davon ohne
          Chargennummer … verteilt — What?"): drei Zeilen, nur was die Zeile
          nicht schon sagt; die Erklärung steht im Hinweis unter der Maus. */}
      <ul className="erklaer-liste">
        {b.n_lieferungen > 0 && (
          <li><strong>Ausgeliefert {kg(b.geliefert_kg, 0)}</strong> in {mz(b.n_lieferungen, 'Lieferung', 'Lieferungen')}
            {ohneNummer > 0 && <span className="leise" title="Lieferscheine ohne Chargennummer nehmen anteilig von jeder Charge ihrer Sorte, die schon da war. Sie zählen hier mit, stehen aber nicht in der Liste unten. Unter Betrieb → Warenausgang lässt sich die Charge nachtragen."> (davon {zahl(ohneNummer)} ohne Chargennummer, anteilig)</span>}
            {' '}· <span title="So viel Eingangsware ging dafür aus dem Lager — mehr als geliefert, weil unterwegs verdunstet, im Palox gelandet oder als zu klein / zu gross aussortiert">aus {kg(b.ausgelagert_kg, 0)} Eingangsware</span> <Herkunft art="gerechnet" /></li>
        )}
        {b.ueberzaehlung_kg > 0 && <li><Marke art="warnung">{kg(b.ueberzaehlung_kg, 0)} mehr geliefert als gekommen</Marke> — ein Zettel oder eine Zuordnung stimmt nicht.</li>}
        <li><strong>Verlust bis heute {kg(b.verlust_heute_kg, 0)}</strong>
          {b.verlust_heute_kg !== null
            ? <> = Verdunstung {kg(b.verdunstung_heute_kg, 0)} + Faules im Palox <span title={b.faul_anteil != null ? `rechnet mit ${prozent(b.faul_anteil)} im Palox — ${b.faul_quelle ?? 'Quelle unbekannt'}` : undefined}>{kg(b.schimmel_heute_kg, 0)}</span> + Faules beim Abpacken {kg(b.fax_heute_kg, 0)}
                {hagelBisHeute > 0.5 && <span className="leise"> · im Palox stecken {kg(hagelBisHeute, 0)} Hagel — Unique, wird als Knospe verkauft, kein Verlust</span>}</>
            : <> — {verlustTitel(b)}</>}</li>
        {z.l && <li className="leise">Gemessen: {mz(z.l.n_wiegungen, 'Palettenwägung', 'Palettenwägungen')} · {mz(z.l.n_schimmel, 'Palox-Ablesung', 'Palox-Ablesungen')} · {mz(z.l.n_sortierlaeufe, 'Sortierlauf', 'Sortierläufe')}</li>}
      </ul>

      <div className="gitter">
        <div>
          <h3 className="oben-0">1 · Eingang{kohorten.length > 0 && <span className="leise"> · {kohorten.length} Eingangstage</span>}</h3>
          {kohorten.length === 0 ? <p className="leise">keine Eingangstage bekannt</p> : (
            <div className="rollbar"><table className="dicht">
              <thead><tr><th>Eingangstag</th><th className="zahl">Alter heute</th><th className="zahl">Paletten</th><th className="zahl">Eingang</th><th className="zahl">in der App gezählt</th></tr></thead>
              <tbody>{kohorten.map(k => (
                <tr key={k.eingangsdatum}>
                  <td>{datum(k.eingangsdatum)}</td><td className="zahl">{k.alter_heute} d</td>
                  <td className="zahl">{k.n_paletten}</td><td className="zahl">{k.eingang_kg != null ? kg(k.eingang_kg, 0) : <span className="leise">—</span>}</td>
                  <td className="zahl">{k.n_verarbeitet}{k.n_verarbeitet > k.n_paletten && <span className="zelle-unter"><Marke art="warnung">mehr gezählt als gekommen</Marke></span>}</td>
                </tr>
              ))}</tbody>
            </table></div>
          )}
        </div>

        <div>
          {/* Runde AQ: die Spalte „Ziel" nur, wenn nicht alles derselbe Weg ist — sonst stand 40-mal „Verkauf (Lieferschein)" da. */}
          <h3 className="oben-0">2 · Ausgang <span className="leise">· {lieferungen.length} {lieferungen.length === 1 ? 'Lieferung' : 'Lieferungen'}{einZiel && lieferungen.length > 0 ? ` · ${lieferungen[0].ziel_name}` : ''}</span></h3>
          {lieferungen.length === 0 ? <p className="leise">noch keine dieser Charge zugeordnet</p> : (
            <div className="rollbar"><table className="dicht">
              <thead><tr><th>Datum</th>{!einZiel && <th>Ziel</th>}<th>Kunde</th><th className="zahl">Masse der Lieferung</th></tr></thead>
              <tbody>{lieferungen.map(l => (
                <tr key={l.id} className="klickbar" onClick={() => setLieferung(l.id)} title="die ganze Zeile der Perigon-Datei zeigen"><td>{datum(l.datum)}</td>{!einZiel && <td>{l.ziel_name}</td>}<td>{l.kunde ?? ''}</td>
                  <td className="zahl">{kg(l.masse_kg, 0)}{l.masse_quelle !== 'gewogen' && <span className="leise"> ({herkunftText(l.masse_quelle)})</span>}</td></tr>
              ))}</tbody>
            </table></div>
          )}
        </div>
      </div>

      <h3>3 · Arbeiten <span className="leise">· {arbeiten.length}</span></h3>
      {arbeiten.length === 0 ? <p className="leise">noch keine</p> : (
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Start</th><th>Arbeit</th><th>Status</th><th className="zahl">Bewegte Masse</th><th className="zahl" title="Wie alt die verarbeitete Ware war — in Klammern: Tage älter (+) oder jünger (−) als der Durchschnitt der Charge an dem Tag">Alter der Ware</th><th></th></tr></thead>
          <tbody>
            {arbeiten.map(a => {
              const ta = taetigkeitVon(a.weg, a.station, a.ist_fax)
              const va = alter.find(x => x.auftrag_id === a.id)
              return (
                <tr key={a.id}>
                  <td>{zeitpunkt(a.start_ts)}</td>
                  <td><TaetZeichen id={ta?.id} /> {ta ? t(ta.text) : ''}</td>
                  <td>{a.abgebrochen_ts ? <Marke art="warnung">abgebrochen</Marke> : a.status === 'offen' ? <Marke art="offen">läuft</Marke> : <Marke art="fertig">fertig</Marke>}</td>
                  <td className="zahl">{a.masse_kg != null ? kg(a.masse_kg, 0) : <span className="leise">unbekannt</span>}{a.masse_quelle && a.masse_quelle !== 'fehlt' && <span className="leise"> ({herkunftText(a.masse_quelle)})</span>}</td>
                  <td className="zahl" title={va?.differenz != null ? `${Math.abs(Math.round(va.differenz))} Tage ${va.differenz >= 0 ? 'älter' : 'jünger'} als der Durchschnitt der Charge an dem Tag` : undefined}>{va ? `${Math.round(va.alter_verarbeitet)} d${va.differenz != null ? ` (${va.differenz > 0 ? '+' : ''}${Math.round(va.differenz)})` : ''}` : ''}</td>
                  <td className="rechts-buendig"><Link to={`/arbeit/${a.id}`}>öffnen</Link></td>
                </tr>
              )
            })}
          </tbody>
        </table></div>
      )}
      {lieferung !== null && <LieferungFenster lieferungId={lieferung} schliessen={() => setLieferung(null)} />}
    </div>
  )
}
