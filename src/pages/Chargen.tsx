import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { TaetZeichen, ZChevron } from '../components/Zeichen'
import { Link, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { taetigkeitVon } from '../lib/taetigkeit'
import { WOERTERBUCH } from '../lib/i18n'
import { datum, kg, prozent, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Erklaerung, Herkunft, Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import { alterSpanne, anteilBei, useAuswertung, type Auswertung } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import type { Auftrag } from '../lib/typen'
import { herkunftText, summeBekannt } from '../lib/masse'

/** Wonach die Tabelle sortiert ist — der Betriebsleiter wählt es mit einem Klick auf den Kopf. */
type Sortierung = 'lager' | 'verkaufsfaehig' | 'in4wochen' | 'alter'

/**
 * Chargen: Wo steht welche Charge? Eine Zeile je Charge mit Eingang und
 * ausgeliefert (gemessen), Im Lager, verkaufsfähig heute und in vier Wochen
 * (gerechnet und prognostiziert), Alter und Verlust bis heute — und
 * aufgeklappt, in der Reihenfolge des Weges der Ware: Eingang (die
 * Eingangstage), Ausgang (die Lieferungen), Arbeiten. Auffälligkeiten stehen
 * nicht hier, sondern unter Messungen — dort, wo man sie korrigiert.
 *
 * Die Reihenfolge ist die Aussage: Wer nach „in 4 Wochen" sortiert, sieht
 * oben die Charge, die am meisten verliert, wenn sie liegen bleibt — und
 * damit die, die zuerst raus sollte.
 */
export default function Chargen() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const [suche, setSuche] = useSearchParams()
  const [sorte, setSorte] = useState('')
  const [nurBestand, setNurBestand] = useState(false)
  const [nach, setNach] = useState<Sortierung>('lager')
  const offen = Number(suche.get('charge') ?? 0) || null

  const zeilen = useMemo(() => {
    if (!daten) return []
    const anteil = (nr: number, h: number) => anteilBei(daten.prognose, 'charge', String(nr), h)
    const liste = daten.bestand.map(b => ({
      b,
      n: daten.naechste.find(x => x.charge_nr === b.charge_nr),
      l: daten.lage.find(x => x.charge_nr === b.charge_nr),
      m: daten.bilanz.find(x => x.charge_nr === b.charge_nr),
      heute: anteil(b.charge_nr, 0),
      in4: anteil(b.charge_nr, 28),
    })).filter(z => (!sorte || z.b.sorte === sorte) && (!nurBestand || z.b.lager_kg > 0))
    // Bei den Anteilen steht der **schlechteste** oben: Das ist die Charge, die
    // zuerst raus sollte. Eine Charge ohne Zahl steht in jedem Fall hinten —
    // „unbekannt" ist weder gut noch schlecht.
    const hinten = (x: number | null) => x === null ? Infinity : x
    return liste.sort((a, c) => {
      if (nach === 'verkaufsfaehig') return hinten(a.heute) - hinten(c.heute)
      if (nach === 'in4wochen') return hinten(a.in4) - hinten(c.in4)
      if (nach === 'alter') return (c.b.alter_lager_bis ?? -1) - (a.b.alter_lager_bis ?? -1)
      return c.b.lager_kg - a.b.lager_kg
    })
  }, [daten, sorte, nurBestand, nach])

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort()
  const summeLager = zeilen.reduce((a, z) => a + z.b.lager_kg, 0)
  const summeVerkaufsfaehig = summeBekannt(zeilen.map(z => z.b.verkaufsfaehig_lager_kg))
  const summeGeliefert = zeilen.reduce((a, z) => a + z.b.geliefert_kg, 0)
  const summePrognose = summeBekannt(zeilen.map(z => z.n?.prognose_verlust_14_kg ?? null))
  /**
   * Ein Spaltenkopf, der sortiert. Der Pfeil zeigt, wohin: Bei Masse und
   * Alter steht das Grösste oben (↓), bei den Anteilen das Kleinste (↑) —
   * denn dort ist klein das Dringende.
   */
  const Kopf = ({ id, children }: { id: Sortierung; children: ReactNode }) => {
    const auf = id === 'verkaufsfaehig' || id === 'in4wochen'
    return (
      <th className="zahl">
        <button type="button" onClick={() => setNach(id)} aria-pressed={nach === id}
                style={{ font: 'inherit', color: 'inherit', background: 'none', border: 0, padding: 0, cursor: 'pointer' }}>
          {children}{nach === id && <span aria-hidden="true"> {auf ? '↑' : '↓'}</span>}
        </button>
      </th>
    )
  }

  return (
    <>
      <Reiterkopf titel="Chargen" zweck="Wo steht welche Charge — wie viel liegt noch, wie alt ist es, was droht?"
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt} />
      <Probleme liste={daten.probleme} />
      <Karte>
        <div className="filterleiste">
          <select value={sorte} onChange={e => setSorte(e.target.value)} aria-label="Sorte">
            <option value="">alle Sorten</option>{sorten.map(s => <option key={s}>{s}</option>)}
          </select>
          <label className="ankreuzen" style={{ minHeight: 36 }}>
            <input type="checkbox" checked={nurBestand} onChange={e => setNurBestand(e.target.checked)} /> nur mit Bestand
          </label>
          <span className="nach-rechts">
            {zeilen.length} Chargen · ausgeliefert <strong>{tonnen(summeGeliefert)}</strong> · im Lager <strong>{tonnen(summeLager)}</strong> · davon verkaufsfähig <strong>{tonnen(summeVerkaufsfaehig)}</strong>
            {summePrognose !== null && summePrognose > 0 && <> · zwei Wochen länger liegen: <strong>+{tonnen(summePrognose)}</strong></>}
          </span>
          <span className="herkunft-legende">Eingang, Ausgeliefert<Herkunft art="gemessen" /> · Im Lager, verkaufsfähig, Verlust<Herkunft art="gerechnet" /> · in 4 Wochen, zwei Wochen<Herkunft art="prognose" /></span>
        </div>
        <div className="rollbar">
          <table className="umbruch">
            <thead>
              <tr>
                <th style={{ width: 28 }} aria-label="aufklappen" />
                <th>Charge</th><th>Sorte</th><th className="zahl">Eingang</th><th className="zahl">Ausgeliefert</th>
                <Kopf id="lager">Im Lager</Kopf>
                <Kopf id="verkaufsfaehig">Verkaufsfähig heute</Kopf>
                <Kopf id="in4wochen">In 4 Wochen</Kopf>
                <Kopf id="alter">Liegt seit</Kopf>
                <th className="zahl">Verlust bis heute</th>
                <th className="zahl">Zwei Wochen länger</th><th className="zahl">Messungen</th>
              </tr>
            </thead>
            <tbody>
              {zeilen.map(z => (
                <ChargenZeile key={z.b.charge_nr} z={z} offen={offen === z.b.charge_nr} daten={daten}
                              oeffnen={() => setSuche(offen === z.b.charge_nr ? {} : { charge: String(z.b.charge_nr) })} />
              ))}
            </tbody>
          </table>
        </div>
        <Erklaerung>
          <p>Eingang und Ausgeliefert sind <Herkunft art="gemessen" />. <strong>Im Lager</strong> ist Eingangsware, die nicht ausgeliefert ist; sie ändert sich nur durch Liefern.
          <strong> Verkaufsfähig heute</strong> zieht davon ab, was bis heute verdunstet oder verdorben ist und was zu klein oder zu gross ist <Herkunft art="gerechnet" />; der Prozentsatz daneben ist der Anteil an der liegenden Eingangsware.
          <strong> In 4 Wochen</strong> ist dieselbe Rechnung 28 Tage später <Herkunft art="prognose" />, <em>wenn die Ware bis dahin liegen bleibt</em>.</p>
          <p>Ein Klick auf einen Spaltenkopf sortiert danach. Nach „In 4 Wochen" sortiert steht oben, was am wenigsten übersteht — und damit die Charge, die zuerst raus sollte.
          „Liegt seit" ist die Spanne der Eingangstage; es gibt kein Zuerst-rein-zuerst-raus.
          Messungen: Palettenwägungen · Faules · CSV-Läufe. Eine Zeile antippen zeigt Eingang, Ausgang und Arbeiten der Charge.</p>
        </Erklaerung>
      </Karte>
    </>
  )
}

type Zeile = { b: Auswertung['bestand'][number]; n?: Auswertung['naechste'][number]; l?: Auswertung['lage'][number]
               m?: Auswertung['bilanz'][number]; heute: number | null; in4: number | null }

function ChargenZeile({ z, offen, oeffnen, daten }: { z: Zeile; offen: boolean; oeffnen: () => void; daten: Auswertung }) {
  const { b, n, l } = z
  const liegt = b.lager_kg > 0
  return (
    <>
      <tr onClick={oeffnen} className={`klickbar${offen ? ' offen' : ''}`} aria-expanded={offen}>
        <td><span className="chevron" style={{ display: 'inline-flex', color: 'var(--text-leise)', transition: 'transform var(--d-mittel)', transform: offen ? 'rotate(90deg)' : undefined }}><ZChevron size={16} /></span></td>
        <td><strong>{b.charge_nr}</strong> <span className="leise nowrap">{b.schlag}</span></td>
        <td>{b.sorte}</td>
        <td className="zahl">{kg(b.eingang_kg, 0)}</td>
        <td className="zahl">{b.n_lieferungen > 0 ? kg(b.geliefert_kg, 0) : <span className="leise">—</span>}</td>
        <td className="zahl">{liegt ? <strong>{kg(b.lager_kg, 0)}</strong> : <span className="leise">—</span>}</td>
        <td className="zahl">{liegt && b.verkaufsfaehig_lager_kg !== null
          ? <>{kg(b.verkaufsfaehig_lager_kg, 0)}{z.heute !== null && <span className="leise"> · {prozent(z.heute, 0)}</span>}</>
          : <span className="leise">—</span>}</td>
        <td className="zahl">{liegt && z.in4 !== null ? prozent(z.in4, 0) : <span className="leise">—</span>}</td>
        <td className="zahl">{liegt ? alterSpanne(b.alter_lager_von, b.alter_lager_bis, b.alter_lager_heute).replace(' Tagen', ' d') : ''}</td>
        <td className="zahl">{kg(b.verlust_heute_kg, 0)}</td>
        <td className="zahl">{n?.prognose_verlust_14_kg != null && n.prognose_verlust_14_kg > 0 ? `−${kg(n.prognose_verlust_14_kg, 0)}` : <span className="leise">—</span>}</td>
        <td className="zahl leise">{l ? `${l.n_wiegungen} · ${l.n_schimmel} · ${l.n_sortierlaeufe}` : '—'}</td>
      </tr>
      {offen && (
        <tr><td colSpan={11} className="detail"><ChargeDetail nr={b.charge_nr} z={z} daten={daten} /></td></tr>
      )}
    </>
  )
}

function ChargeDetail({ nr, z, daten }: { nr: number; z: Zeile; daten: Auswertung }) {
  const [arbeiten, setArbeiten] = useState<(Auftrag & { masse_kg: number | null; masse_quelle: string | null })[]>([])
  const [lieferungen, setLieferungen] = useState<{ id: number; datum: string; ziel_name: string; kunde: string | null; masse_kg: number | null; masse_quelle: string }[]>([])
  const [laedt, setLaedt] = useState(true)
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
  return (
    <div className="wechsel">
      <div className="zahlenzeile" style={{ marginBottom: '1rem' }}>
        <div><div className="titel">Paletten</div><div className="wert" style={{ fontSize: '1.2rem' }}>{zahl(b.n_paletten)}</div>{b.im_haus_heute_kg > 0 && (b.n_rest_paletten ?? 0) > 0 && <div className="unter">etwa {b.n_rest_paletten} noch im Haus (gerechnet)</div>}</div>
        <div><div className="titel">Eingang</div><div className="wert" style={{ fontSize: '1.2rem' }}>{b.eingang_von && b.eingang_bis && b.eingang_von !== b.eingang_bis ? `${datum(b.eingang_von)} – ${datum(b.eingang_bis)}` : datum(b.eingang_von ?? b.eingangsdatum_mittel)}</div>{(b.n_eingangstage ?? 0) > 1 && <div className="unter">{b.n_eingangstage} Eingangstage</div>}</div>
        <div><div className="titel">Ausgeliefert / dahinter an Eingang</div><div className="wert" style={{ fontSize: '1.2rem' }}>{kg(b.geliefert_kg, 0)} / {kg(b.ausgelagert_kg, 0)}</div>{b.ueberzaehlung_kg > 0 && <div className="unter">mehr geliefert als hereingekommen: {kg(b.ueberzaehlung_kg, 0)}</div>}</div>
        <div><div className="titel">Verlust bis heute</div><div className="wert" style={{ fontSize: '1.2rem' }}>{kg(b.verlust_heute_kg, 0)}</div><div className="unter">Verdunstung {kg(b.verdunstung_heute_kg, 0)} · Faules {kg(summeBekannt([b.schimmel_heute_kg, b.sockel_heute_kg]), 0)} · Abpacken {kg(b.fax_heute_kg, 0)}</div></div>
        {z.m?.csv_gemessen_kg != null && <div><div className="titel">Modell am Band / CSV gewogen</div><div className="wert" style={{ fontSize: '1.2rem' }}>{kg(z.m.modell_am_band_kg, 0)} / {kg(z.m.csv_gemessen_kg, 0)}</div></div>}
      </div>
      <p className="leise-satz" style={{ margin: '0 0 1rem' }}>
        Eingang und Ausgeliefert <Herkunft art="gemessen" />, alles Übrige <Herkunft art="gerechnet" /> bis heute. Auffälligkeiten dieser Charge stehen unter <Link to="/messungen">Messungen</Link>.
      </p>

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
                  <td className="zahl">{k.n_verarbeitet}{k.n_verarbeitet > k.n_paletten && <> <Marke art="warnung">mehr gezählt als gekommen</Marke></>}</td>
                </tr>
              ))}</tbody>
            </table></div>
          )}
        </div>

        <div>
          <h3 className="oben-0">2 · Ausgang <span className="leise">· {lieferungen.length} Lieferungen</span></h3>
          {lieferungen.length === 0 ? <p className="leise">noch keine dieser Charge zugeordnet</p> : (
            <div className="rollbar"><table className="dicht">
              <thead><tr><th>Datum</th><th>Ziel</th><th>Kunde</th><th className="zahl">Masse der Lieferung</th></tr></thead>
              <tbody>{lieferungen.map(l => (
                <tr key={l.id}><td>{datum(l.datum)}</td><td>{l.ziel_name}</td><td>{l.kunde ?? ''}</td>
                  <td className="zahl">{kg(l.masse_kg, 0)}{l.masse_quelle !== 'gewogen' && <span className="leise"> ({herkunftText(l.masse_quelle)})</span>}</td></tr>
              ))}</tbody>
            </table></div>
          )}
        </div>
      </div>

      <h3>3 · Arbeiten <span className="leise">· {arbeiten.length}</span></h3>
      {arbeiten.length === 0 ? <p className="leise">noch keine</p> : (
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Start</th><th>Arbeit</th><th>Status</th><th className="zahl">Bewegte Masse</th><th className="zahl">Alter verarbeitet</th><th></th></tr></thead>
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
                  <td className="zahl">{va ? `${Math.round(va.alter_verarbeitet)} d${va.differenz != null ? ` (${va.differenz > 0 ? '+' : ''}${Math.round(va.differenz)})` : ''}` : ''}</td>
                  <td className="rechts-buendig"><Link to={`/arbeit/${a.id}`}>öffnen</Link></td>
                </tr>
              )
            })}
          </tbody>
        </table></div>
      )}
    </div>
  )
}
