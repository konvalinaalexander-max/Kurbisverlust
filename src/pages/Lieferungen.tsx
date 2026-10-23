import { useCallback, useEffect, useState } from 'react'
import { ZKreuz } from '../components/Zeichen'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum as datumText, heute as heuteOrtszeit, kg as kgText, tonnen, zahl } from '../lib/format'
import { Hinweis, Karte, Kennzahl, Lade } from '../components/Bausteine'
import AusgangImport from '../betrieb/AusgangImport'

/**
 * Warenausgang erfassen. Spec §9 sieht die Gegenprobe „Eingang = Verlust +
 * Ausgang + Restbestand" ausdrücklich vor; ohne diese Maske gab es sie nicht.
 *
 * Bewusst genügsam: Datum, Sorte und *entweder* Kilo oder Kistenzahl. Mehr
 * steht auf einem Lieferschein nicht drauf, und Palettengewichte kennt der
 * Betrieb gar nicht. Kisten werden über das gemessene Kilo je Kiste
 * umgerechnet — mit ausgewiesener Unsicherheit, statt sie zu verschweigen.
 */
interface Zeile {
  id: number; datum: string; charge_nr: number | null; sorte: string | null
  kg: number | null; kisten: number | null; ziel: string; ziel_name: string
  kunde: string | null; masse_kg: number | null; masse_quelle: string
  masse_fehler_kg: number | null
}
interface Ziel { code: string; name: string; buch: string; reihenfolge: number }

const heute = heuteOrtszeit

/** So viele Lieferungen stehen zuerst in der Liste; die Zahlen darüber zählen alle. */
const ZUERST = 200
const SEITE = 1000

export default function Lieferungen() {
  const [alle, setAlle] = useState<Zeile[]>([])
  const [zeigeAlle, setZeigeAlle] = useState(false)
  const [ziele, setZiele] = useState<Ziel[]>([])
  const [sorten, setSorten] = useState<string[]>([])
  const [chargen, setChargen] = useState<{ nr: number; sorte: string; schlag: string }[]>([])
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)

  const [datum, setDatum] = useState(heute())
  const [sorte, setSorte] = useState('')
  const [charge, setCharge] = useState('')
  const [einheit, setEinheit] = useState<'kg' | 'kisten'>('kg')
  const [menge, setMenge] = useState('')
  const [ziel, setZiel] = useState('verkauf')
  const [kunde, setKunde] = useState('')

  const laden = useCallback(async () => {
    // Runde AQ: alle Lieferungen, seitenweise — bis hier nur die neuesten 200,
    // und „Masse aller Lieferungen" zählte nur diese (27.7 t statt 209.7 t).
    const holeAlle = async () => {
      const da: Zeile[] = []
      for (let von = 0; ; von += SEITE) {
        const r = await supabase.from('v_lieferung_masse').select('*')
          .order('datum', { ascending: false }).order('id', { ascending: false }).range(von, von + SEITE - 1)
        if (r.error) { setFehler(fehlerText(r.error)); return da }
        const teil = (r.data ?? []) as Zeile[]
        da.push(...teil)
        if (teil.length < SEITE) return da
      }
    }
    const [l, z, s, c] = await Promise.all([
      holeAlle(),
      supabase.from('ausgang_ziel').select('*').order('reihenfolge'),
      supabase.from('sorte_kaliber').select('sorte').order('sorte'),
      supabase.from('charge').select('nr, sorte, schlag').order('nr'),
    ])
    setAlle(l)
    for (const r of [z, s, c]) if (r.error) setFehler(fehlerText(r.error))
    setZiele((z.data ?? []) as Ziel[])
    setSorten(((s.data ?? []) as { sorte: string }[]).map(x => x.sorte))
    setChargen((c.data ?? []) as typeof chargen)
    setLaedt(false)
  }, [])
  useEffect(() => { void laden() }, [laden])

  // Charge gewählt → Sorte folgt daraus, das spart eine Eingabe.
  const gewaehlteCharge = chargen.find(c => String(c.nr) === charge)
  const wirkSorte = gewaehlteCharge?.sorte ?? sorte

  async function speichern() {
    const n = Number(menge)
    if (!(n > 0)) { setFehler('Menge fehlt'); return }
    if (!wirkSorte && !charge) { setFehler('Sorte oder Charge angeben'); return }
    const { error } = await supabase.from('lieferung').insert({
      datum,
      charge_nr: charge === '' ? null : Number(charge),
      sorte: wirkSorte || null,
      kg: einheit === 'kg' ? n : null,
      kisten: einheit === 'kisten' ? Math.round(n) : null,
      ziel,
      kunde: kunde.trim() || null,
    })
    if (error) { setFehler(fehlerText(error)); return }
    setMenge(''); setKunde(''); setFehler(null); void laden()
  }

  async function entfernen(id: number) {
    const { error } = await supabase.from('lieferung').delete().eq('id', id)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  if (laedt) return <Lade />

  // Leer ist nicht null: Zeilen ohne Masse (das Kistengewicht ist noch
  // unbekannt) gehen nicht als 0 kg in die Summe, sondern zählen nicht mit —
  // wie viele es sind, steht unter der Kennzahl und im Hinweis darunter.
  const massen = alle.flatMap(z => z.masse_kg !== null ? [z.masse_kg] : [])
  const summe = massen.reduce((s, m) => s + m, 0)
  const ohneMasse = alle.length - massen.length
  const ohneKistengewicht = alle.some(z => z.masse_quelle === 'Kistengewicht unbekannt')
  const zeilen = zeigeAlle ? alle : alle.slice(0, ZUERST)

  return (
    <>
      <h1>Warenausgang</h1>

      <AusgangImport nachUebernahme={() => void laden()} />

      <Karte titel="Lieferung von Hand eintragen">
        <div className="spalten">
          <div className="feld">
            <label htmlFor="l-datum">Datum</label>
            <input id="l-datum" type="date" value={datum}
                   onChange={e => setDatum(e.target.value)} />
          </div>
          <div className="feld">
            <label htmlFor="l-charge">Charge <span className="leise">(wenn bekannt)</span></label>
            <select id="l-charge" value={charge} onChange={e => setCharge(e.target.value)}>
              <option value="">— keine —</option>
              {chargen.map(c => (
                <option key={c.nr} value={c.nr}>{c.nr} · {c.sorte} · {c.schlag}</option>
              ))}
            </select>
          </div>
          <div className="feld">
            <label htmlFor="l-sorte">Sorte</label>
            <select id="l-sorte" value={wirkSorte} disabled={!!gewaehlteCharge}
                    onChange={e => setSorte(e.target.value)}>
              <option value="">— wählen —</option>
              {sorten.map(s => <option key={s}>{s}</option>)}
            </select>
          </div>
        </div>

        <div className="spalten">
          <div className="feld">
            <label htmlFor="l-einheit">Einheit</label>
            <select id="l-einheit" value={einheit}
                    onChange={e => setEinheit(e.target.value as 'kg' | 'kisten')}>
              <option value="kg">Kilo</option>
              <option value="kisten">Kisten</option>
            </select>
          </div>
          <div className="feld">
            <label htmlFor="l-menge">{einheit === 'kg' ? 'Kilo' : 'Anzahl Kisten'}</label>
            <input id="l-menge" type="number" inputMode="decimal" min={0}
                   step={einheit === 'kg' ? '0.1' : '1'}
                   value={menge} onChange={e => setMenge(e.target.value)} />
          </div>
          <div className="feld">
            <label htmlFor="l-ziel">Wohin</label>
            <select id="l-ziel" value={ziel} onChange={e => setZiel(e.target.value)}>
              {ziele.map(z => <option key={z.code} value={z.code}>{z.name}</option>)}
            </select>
          </div>
          <div className="feld">
            <label htmlFor="l-kunde">Kunde <span className="leise">(freiwillig)</span></label>
            <input id="l-kunde" value={kunde} onChange={e => setKunde(e.target.value)} />
          </div>
        </div>

        {einheit === 'kisten' && (
          <Hinweis art="info">
            Kisten werden über das gemessene Kilo je Kiste in Masse umgerechnet.
            Wie sicher das ist, hängt daran, wie viele fertige Paletten gewogen
            wurden — die Spalte „Masse" sagt es je Zeile.
          </Hinweis>
        )}
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <button className="haupt" onClick={speichern} disabled={menge === ''}>
          Eintragen
        </button>
      </Karte>

      <Karte titel="Erfasst">
        <div className="spalten">
          <Kennzahl titel="Lieferungen" wert={zahl(alle.length)} />
          <Kennzahl titel="Masse aller Lieferungen" wert={tonnen(summe)}
                    unter={ohneMasse > 0 ? `${ohneMasse} ohne Masse — nicht mitgezählt` : undefined} />
        </div>
        {ohneKistengewicht && (
          <Hinweis art="warnung">
            Für manche Zeilen ist die Kistenzahl angegeben, aber es wurde noch
            keine fertige Palette gewogen — ohne die lässt sich nicht sagen, wie
            viel eine Kiste wiegt. Diese Zeilen zählen noch nicht mit.
          </Hinweis>
        )}
        {alle.length === 0 ? (
          <p className="leise">Noch nichts erfasst.</p>
        ) : (
          <div className="rollbar">
            {alle.length > ZUERST && (
              <p className="leise">
                {zeigeAlle ? `Alle ${zahl(alle.length)} Lieferungen, die neuesten zuerst.` : `Die neuesten ${ZUERST} von ${zahl(alle.length)}.`}{' '}
                <button type="button" className="werkzeug-knopf" onClick={() => setZeigeAlle(a => !a)}>
                  {zeigeAlle ? `nur die neuesten ${ZUERST}` : 'alle zeigen'}
                </button>
              </p>
            )}
            <table>
              <thead>
                <tr><th>Datum</th><th>Sorte</th><th>Charge</th><th className="zahl">Angabe auf dem Lieferschein</th>
                  <th className="zahl">Masse der Lieferung</th><th>Wohin</th><th>Kunde</th><th /></tr>
              </thead>
              <tbody>
                {zeilen.map(z => (
                  <tr key={z.id}>
                    <td>{datumText(z.datum)}</td>
                    <td>{z.sorte ?? '—'}</td>
                    <td>{z.charge_nr ?? '—'}</td>
                    <td className="zahl">
                      {z.kg !== null ? kgText(z.kg, 0) : `${zahl(z.kisten)} Kisten`}
                    </td>
                    <td className="zahl">
                      {z.masse_kg === null ? '—' : kgText(z.masse_kg, 0)}
                      {z.masse_fehler_kg ? (
                        <span className="leise"> ± {kgText(z.masse_fehler_kg, 0)}</span>
                      ) : null}
                      <div className="leise" style={{ fontSize: '.75rem' }}>{z.masse_quelle}</div>
                    </td>
                    <td>{z.ziel_name}</td>
                    <td>{z.kunde ?? ''}</td>
                    <td className="rechts-buendig">
                      <button type="button" className="gefahr klein" aria-label="Lieferung entfernen"
                              onClick={() => entfernen(z.id)}><ZKreuz size={16} /></button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Karte>
    </>
  )
}
