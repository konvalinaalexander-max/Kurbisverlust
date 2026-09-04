import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { uhrzeit, type ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'

/**
 * Zu klein / zu gross wiegen (AB-03): Brutto und Kisten eintippen, das Netto
 * rechnet die Datenbank. Schätzen bleibt als Notweg — sichtbar als solcher.
 */
export function AusschussMaske({ d, gesperrt, melden, neuLaden }: {
  d: ArbeitDaten; gesperrt: boolean; melden: (text: string) => void; neuLaden: () => Promise<void>
}) {
  const { t, gebietsschema } = useSprache()
  const [art, setArt] = useState<'zu_klein' | 'zu_gross'>('zu_klein')
  const [modus, setModus] = useState<'wiegen' | 'schaetzen'>('wiegen')
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [brutto, setBrutto] = useState('')
  const [kisten, setKisten] = useState('')
  const [gart, setGart] = useState('')
  const [schaetzung, setSchaetzung] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)

  useEffect(() => {
    void stammdaten().then(s => { setGebinde(s.gebinde); setGart(a => a || s.gebinde[0]?.art || '') })
  }, [])

  const tara = gebinde.find(g => g.art === gart)
  const n = Number(kisten); const b = Number(brutto)
  const netto = b > 0 && tara?.tara_kg_pro_kiste != null
    ? Math.max(Math.round(b - n * tara.tara_kg_pro_kiste - (tara.tara_kg_palette ?? 0)), 0) : null

  async function speichern() {
    let zeile: Record<string, unknown>
    if (modus === 'wiegen') {
      if (!(b > 0 && n > 0 && gart)) return
      zeile = { auftrag_id: d.auftrag.id, art, brutto_kg: b, kisten: n, gebindeart: gart }
    } else {
      const k = Number(schaetzung)
      if (!Number.isInteger(k) || k < 0) { setFehler(t('ganzeZahl')); return }
      zeile = { auftrag_id: d.auftrag.id, art, kg: k }
    }
    const { error } = await supabase.from('ausschuss_messung').insert(zeile)
    if (error) { setFehler(fehlerText(error)); return }
    setBrutto(''); setKisten(''); setSchaetzung(''); setFehler(null)
    melden(t('gespeichert')); await neuLaden()
  }

  const zeilen = d.ausschuss.filter(z => z.art === art)
  const summe = zeilen.reduce((s, z) => s + z.kg, 0)

  return (
    <>
      <div className="umschalter gross" role="tablist">
        <button role="tab" aria-selected={art === 'zu_klein'} className={art === 'zu_klein' ? 'aktiv' : ''}
                onClick={() => setArt('zu_klein')}>{t('zuKlein')}</button>
        <button role="tab" aria-selected={art === 'zu_gross'} className={art === 'zu_gross' ? 'aktiv' : ''}
                onClick={() => setArt('zu_gross')}>{t('zuGross')}</button>
      </div>
      <div className="karte">
        <div className="reihe" style={{ marginBottom: '.9rem' }}>
          <button className={modus === 'wiegen' ? 'haupt' : ''} style={{ flex: 1 }}
                  onClick={() => setModus('wiegen')}>⚖️ {t('ausschussWiegen')}</button>
          <button className={modus === 'schaetzen' ? 'haupt' : ''} style={{ flex: 1 }}
                  onClick={() => setModus('schaetzen')}>{t('ausschussSchaetzen')}</button>
        </div>
        {modus === 'wiegen' ? (
          <>
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
            {netto !== null && <p style={{ fontSize: '1.15rem', margin: '0 0 .75rem' }}><strong>{netto} kg</strong> {t('netto')}</p>}
            <button className="haupt" style={{ width: '100%', minHeight: 60 }} onClick={() => void speichern()}
                    disabled={gesperrt || netto === null || n < 1}>{t('eintragen')}</button>
          </>
        ) : (
          <>
            <div className="feld">
              <label htmlFor="aus-schaetz">{t('kilo')}</label>
              <input id="aus-schaetz" className="gross" type="number" inputMode="numeric" min={0} step={1}
                     value={schaetzung} disabled={gesperrt} onChange={e => setSchaetzung(e.target.value)} />
            </div>
            <p className="leise">{t('ausschussSchaetzenHinweis')}</p>
            <button className="haupt" style={{ width: '100%', minHeight: 60 }} onClick={() => void speichern()}
                    disabled={gesperrt || schaetzung === ''}>{t('eintragen')}</button>
          </>
        )}
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {zeilen.length > 0 && (
          <>
            <p style={{ marginTop: '1rem' }}><strong>{t('bisher')}: {summe} kg</strong></p>
            <table><tbody>
              {zeilen.map(z => (
                <tr key={z.id}>
                  <td>{uhrzeit(z.ts, gebietsschema)}</td>
                  <td className="zahl">{z.kg} kg</td>
                  <td>{z.brutto_kg === null ? t('geschaetzt') : t('gewogen')}</td>
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
    </>
  )
}
