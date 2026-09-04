import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { einstellung, fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import type { ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'

/**
 * Fertige Palette nach dem Waschen: wie viel Kürbis liegt wirklich in einer
 * Kiste? Gespeichert werden Brutto, Kisten und Gebinde; x rechnet die Datenbank.
 */
export function FertigePaletteMaske({ d, gesperrt, melden, neuLaden }: {
  d: ArbeitDaten; gesperrt: boolean; melden: (text: string) => void; neuLaden: () => Promise<void>
}) {
  const { t } = useSprache()
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [soll, setSoll] = useState(8)
  const [brutto, setBrutto] = useState('')
  const [kisten, setKisten] = useState('')
  const [art, setArt] = useState('')
  const [proKiste, setProKiste] = useState('')
  const [zeilen, setZeilen] = useState<{ id: number; kg_pro_kiste: number | null
    ueberfuellung_je_kiste: number | null; kisten: number }[]>([])
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const [s, k] = await Promise.all([
      stammdaten(),
      supabase.from('v_ausgang_kennzahl').select('id, kg_pro_kiste, ueberfuellung_je_kiste, kisten')
        .eq('auftrag_id', d.auftrag.id).order('ts'),
    ])
    setGebinde(s.gebinde); setArt(a => a || s.gebinde[0]?.art || '')
    setZeilen((k.data ?? []) as typeof zeilen)
    setSoll(await einstellung<number>('soll_kg_pro_kiste', 8))
  }, [d.auftrag.id])
  useEffect(() => { void laden() }, [laden])

  const tara = gebinde.find(g => g.art === art)
  const n = Number(kisten); const b = Number(brutto)
  const netto = n > 0 && b > 0 && tara?.tara_kg_pro_kiste != null
    ? b - n * tara.tara_kg_pro_kiste - (tara.tara_kg_palette ?? 0) : null
  const x = netto !== null && netto > 0 ? netto / n : null

  async function speichern() {
    if (!(n > 0 && b > 0 && art)) return
    const { error } = await supabase.from('ausgang_wiegung').insert({
      auftrag_id: d.auftrag.id, charge_nr: d.auftrag.charge_nr,
      brutto_kg: b, kisten: n, gebindeart: art,
      kuerbisse_pro_kiste: proKiste === '' ? null : Number(proKiste),
    })
    if (error) { setFehler(fehlerText(error)); return }
    setBrutto(''); setKisten(''); setProKiste(''); setFehler(null)
    melden(t('gespeichert')); await laden(); await neuLaden()
  }

  return (
    <div className="karte">
      <div className="feld">
        <label htmlFor="a-brutto">{t('gewicht')}</label>
        <input id="a-brutto" className="gross" type="number" inputMode="decimal" step="0.1" min={0}
               value={brutto} disabled={gesperrt} onChange={e => setBrutto(e.target.value)} />
      </div>
      <div className="reihe">
        <div className="feld" style={{ flex: 1 }}>
          <label htmlFor="a-kisten">{t('anzahlKisten')}</label>
          <input id="a-kisten" type="number" inputMode="numeric" min={1} value={kisten} disabled={gesperrt}
                 onChange={e => setKisten(e.target.value)} style={{ fontSize: '1.2rem' }} />
        </div>
        <div className="feld" style={{ flex: 1 }}>
          <label htmlFor="a-art">{t('kistenart')}</label>
          <select id="a-art" value={art} disabled={gesperrt} onChange={e => setArt(e.target.value)}>
            {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
          </select>
        </div>
      </div>
      <div className="feld">
        <label htmlFor="a-pro">{t('kuerbisseProKiste')} ({t('freiwillig')})</label>
        <input id="a-pro" type="number" inputMode="numeric" min={1} value={proKiste} disabled={gesperrt}
               onChange={e => setProKiste(e.target.value)} />
      </div>
      {x !== null && (
        <p style={{ fontSize: '1.15rem', margin: '0 0 .75rem' }}>
          <strong>{x.toFixed(2)} kg</strong> {t('jeKiste')}
          {x > soll && <span style={{ color: 'var(--rot)' }}> · +{(x - soll).toFixed(2)} kg {t('zuViel')}</span>}
        </p>
      )}
      <button className="haupt" style={{ width: '100%', minHeight: 60 }} onClick={() => void speichern()}
              disabled={gesperrt || x === null}>{t('eintragen')}</button>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {zeilen.length > 0 && (
        <>
          <p style={{ marginTop: '1rem' }}><strong>{t('bisher')}: {zeilen.length}</strong></p>
          <table><tbody>
            {zeilen.map(z => (
              <tr key={z.id}>
                <td>{z.kisten} {t('kisten')}</td>
                <td className="zahl">{z.kg_pro_kiste?.toFixed(2) ?? '—'} kg</td>
                <td className="zahl" style={{ color: 'var(--rot)' }}>
                  {z.ueberfuellung_je_kiste != null && z.ueberfuellung_je_kiste > 0 ? `+${z.ueberfuellung_je_kiste.toFixed(2)}` : ''}
                </td>
              </tr>
            ))}
          </tbody></table>
        </>
      )}
    </div>
  )
}
