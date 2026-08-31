import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum as datumText, kg as kgText, zahl } from '../lib/format'
import { Hinweis, Karte, Kennzahl, Lade } from '../components/Bausteine'

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

const heute = () => new Date().toISOString().slice(0, 10)

export default function Lieferungen() {
  const [zeilen, setZeilen] = useState<Zeile[]>([])
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
    const [l, z, s, c] = await Promise.all([
      supabase.from('v_lieferung_masse').select('*').order('datum', { ascending: false }).limit(200),
      supabase.from('ausgang_ziel').select('*').order('reihenfolge'),
      supabase.from('sorte_kaliber').select('sorte').order('sorte'),
      supabase.from('charge').select('nr, sorte, schlag').order('nr'),
    ])
    if (l.error) setFehler(fehlerText(l.error))
    setZeilen((l.data ?? []) as Zeile[])
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

  const summe = zeilen.reduce((s, z) => s + (z.masse_kg ?? 0), 0)
  const ohneKistengewicht = zeilen.some(z => z.masse_quelle === 'Kistengewicht unbekannt')

  return (
    <>
      <h1>Warenausgang</h1>
      <p className="leise">
        Was den Betrieb verlassen hat. Erst damit lässt sich prüfen, ob die
        Verlustrechnung aufgeht — vorher ist der Restbestand nur eine
        Hochrechnung. Es genügt, was auf dem Lieferschein steht.
      </p>

      <Karte titel="Lieferung eintragen">
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
          <Kennzahl titel="Lieferungen" wert={String(zeilen.length)} />
          <Kennzahl titel="Masse gesamt" wert={`${(summe / 1000).toFixed(1)} t`} />
        </div>
        {ohneKistengewicht && (
          <Hinweis art="warnung">
            Für manche Zeilen ist die Kistenzahl angegeben, aber es wurde noch
            keine fertige Palette gewogen — ohne die lässt sich nicht sagen, wie
            viel eine Kiste wiegt. Diese Zeilen zählen noch nicht mit.
          </Hinweis>
        )}
        {zeilen.length === 0 ? (
          <p className="leise">Noch nichts erfasst.</p>
        ) : (
          <div className="rollbar">
            <table>
              <thead>
                <tr><th>Datum</th><th>Sorte</th><th>Charge</th><th className="zahl">Angabe</th>
                  <th className="zahl">Masse</th><th>Wohin</th><th>Kunde</th><th /></tr>
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
                      {z.masse_kg === null ? '—' : `${Math.round(z.masse_kg)} kg`}
                      {z.masse_fehler_kg ? (
                        <span className="leise"> ±{Math.round(z.masse_fehler_kg)}</span>
                      ) : null}
                      <div className="leise" style={{ fontSize: '.75rem' }}>{z.masse_quelle}</div>
                    </td>
                    <td>{z.ziel_name}</td>
                    <td>{z.kunde ?? ''}</td>
                    <td style={{ textAlign: 'right' }}>
                      <button className="gefahr klein" aria-label="Lieferung entfernen"
                              onClick={() => entfernen(z.id)}>✕</button>
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
