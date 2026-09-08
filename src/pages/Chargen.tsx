import { useEffect, useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { taetigkeitVon } from '../lib/taetigkeit'
import { WOERTERBUCH } from '../lib/i18n'
import { datum, kg, prozent, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import { alterSpanne, useAuswertung, type Auswertung } from '../auswertung/daten'
import { Probleme, Reiterkopf } from '../auswertung/Karten'
import type { Auftrag } from '../lib/typen'

/**
 * Chargen: Wo steht welche Charge? Eine Zeile je Charge mit Eingang, Lager,
 * Wartendem, Verarbeitetem, Alter, drohendem Verlust und Messungen — und
 * aufgeklappt die Arbeiten und Lieferungen dahinter.
 */
export default function Chargen() {
  const { daten, laedt, fehler, neuRechnen } = useAuswertung()
  const [suche, setSuche] = useSearchParams()
  const [sorte, setSorte] = useState('')
  const [nurBestand, setNurBestand] = useState(false)
  const offen = Number(suche.get('charge') ?? 0) || null

  const zeilen = useMemo(() => {
    if (!daten) return []
    return daten.bestand.map(b => ({
      b,
      n: daten.naechste.find(x => x.charge_nr === b.charge_nr),
      l: daten.lage.find(x => x.charge_nr === b.charge_nr),
      m: daten.bilanz.find(x => x.charge_nr === b.charge_nr),
      befunde: daten.befunde.filter(x => x.charge_nr === b.charge_nr).length,
    })).filter(z => (!sorte || z.b.sorte === sorte) && (!nurBestand || z.b.lager_kg > 0 || z.b.wartet_kg > 0))
      .sort((a, c) => (c.b.lager_kg + c.b.wartet_kg) - (a.b.lager_kg + a.b.wartet_kg))
  }, [daten, sorte, nurBestand])

  if (laedt && !daten) return <Lade text="Auswertung wird gerechnet …" />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort()
  const summeLager = zeilen.reduce((a, z) => a + z.b.lager_kg, 0)
  const summeWartet = zeilen.reduce((a, z) => a + z.b.wartet_kg, 0)

  return (
    <>
      <Reiterkopf titel="Chargen" zweck="Wo steht welche Charge — wie viel liegt noch, wie alt ist es, was droht?"
                  stand={daten.stand} neuRechnen={() => void neuRechnen()} />
      <Probleme liste={daten.probleme} />
      <Karte>
        <div className="reihe">
          <select value={sorte} onChange={e => setSorte(e.target.value)} style={{ width: 'auto', minHeight: 36 }}>
            <option value="">alle Sorten</option>{sorten.map(s => <option key={s}>{s}</option>)}
          </select>
          <label className="ankreuzen" style={{ minHeight: 36 }}>
            <input type="checkbox" checked={nurBestand} onChange={e => setNurBestand(e.target.checked)} /> nur mit Bestand
          </label>
          <span className="leise" style={{ marginLeft: 'auto' }}>
            {zeilen.length} Chargen · im Lager {kg(summeLager, 0)} · wartet {kg(summeWartet, 0)}
          </span>
        </div>
        <div className="rollbar">
          <table>
            <thead>
              <tr>
                <th>Charge</th><th>Sorte</th><th className="zahl">Eingang</th><th className="zahl">Im Lager</th>
                <th className="zahl">liegt seit</th><th className="zahl">wartet</th><th className="zahl">verarbeitet</th>
                <th className="zahl">Verlust 14 T</th><th className="zahl">Messungen</th><th className="zahl">Modell ↔ CSV</th>
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
        <p className="leise" style={{ margin: '.5rem 0 0' }}>
          „Liegt seit" ist die Spanne der noch liegenden Paletten (jüngste bis älteste) — der Eingang einer Charge verteilt sich über Tage und Wochen, und verarbeitet wird, was erreichbar ist, nicht das Älteste. Messungen: Palettenwägungen · Schimmel · CSV-Läufe. Modell ↔ CSV: Abweichung zwischen der Masse, die das Modell am Band erwartet, und der gewogenen. Eine Zeile antippen zeigt Eingangstage, Arbeiten und Lieferungen der Charge.
        </p>
      </Karte>
    </>
  )
}

type Zeile = { b: Auswertung['bestand'][number]; n?: Auswertung['naechste'][number]; l?: Auswertung['lage'][number]; m?: Auswertung['bilanz'][number]; befunde: number }

function ChargenZeile({ z, offen, oeffnen, daten }: { z: Zeile; offen: boolean; oeffnen: () => void; daten: Auswertung }) {
  const { b, n, l, m } = z
  return (
    <>
      <tr onClick={oeffnen} style={{ cursor: 'pointer', background: offen ? 'var(--kuerbis-flaeche)' : undefined }}>
        <td><strong>{b.charge_nr}</strong> <span className="leise">{b.schlag}</span></td>
        <td>{b.sorte}</td>
        <td className="zahl">{kg(b.eingang_kg, 0)}</td>
        <td className="zahl">{b.lager_kg > 0 ? kg(b.lager_kg, 0) : <span className="leise">—</span>}</td>
        <td className="zahl">{b.lager_kg > 0 ? alterSpanne(b.alter_lager_von, b.alter_lager_bis, b.alter_lager_heute).replace(' Tagen', ' d') : ''}</td>
        <td className="zahl">{b.wartet_kg > 0 ? kg(b.wartet_kg, 0) : <span className="leise">—</span>}</td>
        <td className="zahl">{kg(b.ausgelagert_kg, 0)}</td>
        <td className="zahl">{n?.verlust_14_kg != null && n.verlust_14_kg > 0 ? <strong>{kg(n.verlust_14_kg, 0)}</strong> : <span className="leise">—</span>}</td>
        <td className="zahl">{l ? `${l.n_wiegungen} · ${l.n_schimmel} · ${l.n_sortierlaeufe}` : '—'}{z.befunde > 0 && <> <Marke art="warnung">{z.befunde}</Marke></>}</td>
        <td className="zahl">{m?.abweichung_anteil == null ? <span className="leise">—</span>
          : <Marke art={Math.abs(m.abweichung_anteil) < 0.1 ? 'fertig' : 'warnung'}>{prozent(m.abweichung_anteil)}</Marke>}</td>
      </tr>
      {offen && (
        <tr><td colSpan={10} style={{ background: 'var(--flaeche-2)' }}><ChargeDetail nr={b.charge_nr} z={z} daten={daten} /></td></tr>
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
        supabase.from('v_lieferung_masse').select('id, datum, ziel_name, kunde, masse_kg, masse_quelle').eq('charge_nr', nr).order('datum', { ascending: false }),
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
  const befunde = daten.befunde.filter(x => x.charge_nr === nr)
  const alter = daten.verarbeitung.filter(x => x.charge_nr === nr)
  const kohorten = daten.kohorten.filter(x => x.charge_nr === nr)
  const t = (id: keyof typeof WOERTERBUCH.de) => WOERTERBUCH.de[id]
  if (laedt) return <Lade />
  const b = z.b
  // Die Hand-Linie wäscht und sortiert in einem — in der Rückgrat-Sicht steht
  // sie als hand_kg getrennt von der Maschine; hier aus den Arbeiten summiert.
  const handKg = arbeiten.filter(a => a.station === 'waschen_sortieren' && !a.abgebrochen_ts)
    .reduce((s, a) => s + (a.masse_kg ?? 0), 0)
  return (
    <div style={{ padding: '.5rem 0' }}>
      <div className="spalten" style={{ marginBottom: '.75rem' }}>
        <div><div className="leise">Paletten</div><strong>{zahl(b.n_paletten)}</strong>{(b.n_rest_paletten ?? 0) > 0 && <div className="leise">davon {b.n_rest_paletten} noch im Lager</div>}</div>
        <div><div className="leise">Eingang</div><strong>{b.eingang_von && b.eingang_bis && b.eingang_von !== b.eingang_bis ? `${datum(b.eingang_von)} – ${datum(b.eingang_bis)}` : datum(b.eingang_von ?? b.eingangsdatum_mittel)}</strong>{(b.n_eingangstage ?? 0) > 1 && <div className="leise">{b.n_eingangstage} Eingangstage</div>}</div>
        {handKg > 0 && <div><div className="leise">Hand-Linie (gewaschen + sortiert)</div><strong>{kg(handKg, 0)}</strong></div>}
        {(b.sortiert_kg > 0 || handKg === 0) && <div><div className="leise">Maschine: sortiert / davon gewaschen</div><strong>{kg(b.sortiert_kg, 0)} / {kg(b.gewaschen_kg, 0)}</strong></div>}
        {z.m?.csv_gemessen_kg != null && <div><div className="leise">Modell am Band / CSV gewogen</div><strong>{kg(z.m.modell_am_band_kg, 0)} / {kg(z.m.csv_gemessen_kg, 0)}</strong></div>}
      </div>
      {kohorten.length > 0 && (
        <>
          <h3>Eingangstage ({kohorten.length})</h3>
          <p className="leise" style={{ margin: '0 0 .4rem' }}>Was an welchem Tag kam, was davon mit diesem Zetteldatum gezählt wurde und was noch liegt. Kein Zuerst-rein-zuerst-raus: die Rechnung nimmt für jeden Tag sein eigenes Alter.</p>
          <div className="rollbar"><table>
            <thead><tr><th>Eingangstag</th><th className="zahl">Alter</th><th className="zahl">gekommen</th><th className="zahl">verarbeitet</th><th className="zahl">noch da</th><th className="zahl">Bestand</th></tr></thead>
            <tbody>{kohorten.map(k => (
              <tr key={k.eingangsdatum} className={k.n_rest === 0 ? 'leise' : ''}>
                <td>{datum(k.eingangsdatum)}</td><td className="zahl">{k.alter_heute} d</td>
                <td className="zahl">{k.n_paletten}</td><td className="zahl">{k.n_verarbeitet}{k.n_verarbeitet > k.n_paletten && <> <Marke art="warnung">mehr gezählt als gekommen</Marke></>}</td>
                <td className="zahl"><strong>{k.n_rest}</strong></td><td className="zahl">{k.rest_kg != null && k.rest_kg > 0 ? kg(k.rest_kg, 0) : <span className="leise">—</span>}</td>
              </tr>
            ))}</tbody>
          </table></div>
        </>
      )}
      {befunde.length > 0 && (
        <Hinweis art="warnung">{befunde.map((b, i) => <div key={i}><strong>{b.art}:</strong> {b.befund} <span className="leise">— {b.rat}</span></div>)}</Hinweis>
      )}
      <h3 style={{ marginTop: '1rem' }}>Arbeiten ({arbeiten.length})</h3>
      {arbeiten.length === 0 ? <p className="leise">noch keine</p> : (
        <div className="rollbar"><table>
          <thead><tr><th>Start</th><th>Arbeit</th><th>Status</th><th className="zahl">Masse</th><th className="zahl">Alter verarbeitet</th><th></th></tr></thead>
          <tbody>
            {arbeiten.map(a => {
              const ta = taetigkeitVon(a.weg, a.station, a.ist_fax)
              const va = alter.find(x => x.auftrag_id === a.id)
              return (
                <tr key={a.id}>
                  <td>{zeitpunkt(a.start_ts)}</td>
                  <td>{ta?.zeichen} {ta ? t(ta.text) : ''}{a.kaeufer && <span className="leise"> · {a.kaeufer}</span>}</td>
                  <td>{a.abgebrochen_ts ? <Marke art="warnung">abgebrochen</Marke> : a.status === 'offen' ? <Marke art="offen">läuft</Marke> : <Marke art="fertig">fertig</Marke>}</td>
                  <td className="zahl">{a.masse_kg != null ? kg(a.masse_kg, 0) : <span className="leise">unbekannt</span>}{a.masse_quelle && a.masse_quelle !== 'fehlt' && <span className="leise"> ({a.masse_quelle})</span>}</td>
                  <td className="zahl">{va ? `${Math.round(va.alter_verarbeitet)} d${va.differenz != null ? ` (${va.differenz > 0 ? '+' : ''}${Math.round(va.differenz)})` : ''}` : ''}</td>
                  <td><Link to={`/arbeit/${a.id}`}>öffnen</Link></td>
                </tr>
              )
            })}
          </tbody>
        </table></div>
      )}
      <h3 style={{ marginTop: '1rem' }}>Lieferungen ({lieferungen.length})</h3>
      {lieferungen.length === 0 ? <p className="leise">noch keine dieser Charge zugeordnet</p> : (
        <div className="rollbar"><table>
          <thead><tr><th>Datum</th><th>Ziel</th><th>Kunde</th><th className="zahl">Masse</th></tr></thead>
          <tbody>{lieferungen.map(l => (
            <tr key={l.id}><td>{datum(l.datum)}</td><td>{l.ziel_name}</td><td>{l.kunde ?? ''}</td>
              <td className="zahl">{kg(l.masse_kg, 0)}{l.masse_quelle !== 'kg' && <span className="leise"> ({l.masse_quelle})</span>}</td></tr>
          ))}</tbody>
        </table></div>
      )}
    </div>
  )
}
