import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { Wahl } from '../components/Schritte'
import { uhrzeit, type ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'
import { nettoKg, taraFehlt } from '../lib/masse'

type Art = 'zu_klein' | 'zu_gross'

/**
 * Zu klein / zu gross beim Waschen + Sortieren (0061): Am Band gibt es keine
 * Sortier-CSV — was von Hand aussortiert wurde, steht am Ende auf Paletten.
 * Die werden Palette für Palette gewogen: Art, Brutto, Kisten, Kistenart; das
 * Netto rechnet die Datenbank (Auslöser aus 0044). „Nichts zu klein oder zu
 * gross" ist eine Messung mit 0 kg für beide Arten, kein Auslassen.
 */
export function AusschussMaske({ d, gesperrt, melden, neuLaden }: {
  d: ArbeitDaten; gesperrt: boolean; melden: (text: string) => void; neuLaden: () => Promise<void>
}) {
  const { t, gebietsschema } = useSprache()
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [art, setArt] = useState<Art>('zu_klein')
  const [brutto, setBrutto] = useState('')
  const [kisten, setKisten] = useState('')
  const [gart, setGart] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void stammdaten().then(s => { setGebinde(s.gebinde); setGart(a => a || s.gebinde[0]?.art || '') })
  }, [])

  const tara = gebinde.find(g => g.art === gart)
  const n = Number(kisten); const b = Number(brutto)
  const roh = b > 0 && n > 0 ? nettoKg(b, n, tara) : null
  const netto = roh === null ? null : Math.max(Math.round(roh), 0)
  const fehlt = b > 0 && n > 0 ? taraFehlt(tara) : null

  async function speichern() {
    if (netto === null || laeuft) return
    setLaeuft(true); setFehler(null)
    // kg ist ein Pflichtfeld; der Auslöser ersetzt es durch das Netto aus Brutto und Tara.
    const { error } = await supabase.from('ausschuss_messung').insert({
      auftrag_id: d.auftrag.id, art, kg: netto, brutto_kg: b, kisten: n, gebindeart: gart,
    })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    setBrutto(''); setKisten('')
    melden(t('gespeichert')); await neuLaden()
  }

  async function nichts() {
    if (laeuft) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from('ausschuss_messung').insert(
      (['zu_klein', 'zu_gross'] as Art[]).map(a => ({ auftrag_id: d.auftrag.id, art: a, kg: 0, bemerkung: t('ausschussNichts') })))
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    melden(t('gespeichert')); await neuLaden()
  }

  const summe = (a: Art) => d.ausschuss.filter(z => z.art === a).reduce((s, z) => s + z.kg, 0)
  const artText = (a: Art) => (a === 'zu_klein' ? t('zuKlein') : t('zuGross'))

  return (
    <div className="karte">
      <p className="leise" style={{ marginTop: 0 }}>{t('ausschussWarum')}</p>
      <div className="wahl" style={{ marginBottom: '.75rem' }}>
        <Wahl id="aus-zu_klein" name={t('zuKlein')} gewaehlt={art === 'zu_klein'} onClick={() => setArt('zu_klein')} />
        <Wahl id="aus-zu_gross" name={t('zuGross')} gewaehlt={art === 'zu_gross'} onClick={() => setArt('zu_gross')} />
      </div>
      <div className="feld">
        <label htmlFor="aus-brutto">{t('gewicht')}</label>
        <input id="aus-brutto" className="gross" type="number" inputMode="decimal" step="0.1" min={0}
               value={brutto} disabled={gesperrt} onChange={e => setBrutto(e.target.value)} />
      </div>
      <div className="reihe">
        <div className="feld" style={{ flex: 1 }}>
          <label htmlFor="aus-kisten">{t('anzahlKisten')}</label>
          <input id="aus-kisten" type="number" inputMode="numeric" min={1} value={kisten}
                 disabled={gesperrt} onChange={e => setKisten(e.target.value)} style={{ fontSize: '1.2rem' }} />
        </div>
        <div className="feld" style={{ flex: 1 }}>
          <label htmlFor="aus-art">{t('kistenart')}</label>
          <select id="aus-art" value={gart} disabled={gesperrt} onChange={e => setGart(e.target.value)}>
            {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
          </select>
        </div>
      </div>
      {netto !== null && (
        <p style={{ fontSize: '1.15rem', margin: '.6rem 0 .75rem' }}>
          <strong>{netto} kg</strong> {t('netto')} · {artText(art)}
        </p>
      )}
      <button id="aus-eintragen" className="haupt" style={{ width: '100%', minHeight: 60 }}
              onClick={() => void speichern()} disabled={gesperrt || laeuft || netto === null}>
        {t('eintragen')}
      </button>
      {d.ausschuss.length === 0 && (
        <>
          <button id="aus-nichts" style={{ width: '100%', marginTop: '.6rem', minHeight: 48 }}
                  onClick={() => void nichts()} disabled={gesperrt || laeuft}>
            {t('ausschussNichts')}
          </button>
          <p className="leise" style={{ margin: '.4rem 0 0' }}>{t('ausschussNichtsErkl')}</p>
        </>
      )}
      {fehlt && <Hinweis art="warnung">{fehlt} Ohne sie lässt sich das Nettogewicht nicht ausrechnen — die Angabe gehört in die Stammdaten.</Hinweis>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {d.ausschuss.length > 0 && (
        <>
          <p style={{ marginTop: '1rem' }}>
            <strong>{t('bisher')}: {t('zuKlein')} {summe('zu_klein')} kg · {t('zuGross')} {summe('zu_gross')} kg</strong>
          </p>
          <table><tbody>
            {d.ausschuss.map(z => (
              <tr key={z.id}>
                <td>{uhrzeit(z.ts, gebietsschema)}</td>
                <td>{artText(z.art)}</td>
                <td className="zahl">{z.kg} kg</td>
                <td className="leise">{z.brutto_kg !== null ? `${z.kisten ?? 1} × ${z.gebindeart ?? ''} · ${z.brutto_kg} kg` : (z.bemerkung ?? '')}</td>
                <td style={{ textAlign: 'right' }}>
                  <button className="gefahr klein" disabled={gesperrt} aria-label={t('loeschen')}
                          onClick={async () => {
                            const { error } = await supabase.from('ausschuss_messung').delete().eq('id', z.id)
                            if (error) setFehler(fehlerText(error)); else await neuLaden()
                          }}>✕</button>
                </td>
              </tr>
            ))}
          </tbody></table>
        </>
      )}
    </div>
  )
}
