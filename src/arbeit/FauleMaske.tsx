import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { ZKreuz } from '../components/Zeichen'
import { uhrzeit, type ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'
import { nettoKg, taraFehlt } from '../lib/masse'

/**
 * Faules wiegen (Fax, 0051): kistenweise auf die Waage — Brutto, Kistenzahl,
 * Kistenart, und ob eine Palette drunter stand. Das Netto rechnet die
 * Datenbank (Auslöser), genau wie beim Ausschuss. „Nichts Faules" ist eine
 * Messung mit 0 kg, kein Auslassen.
 */
export function FauleMaske({ d, gesperrt, melden, neuLaden }: {
  d: ArbeitDaten; gesperrt: boolean; melden: (text: string) => void; neuLaden: () => Promise<void>
}) {
  const { t, gebietsschema } = useSprache()
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [brutto, setBrutto] = useState('')
  const [kisten, setKisten] = useState('1')
  const [gart, setGart] = useState('')
  const [mitPalette, setMitPalette] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void stammdaten().then(s => { setGebinde(s.gebinde); setGart(a => a || s.gebinde[0]?.art || '') })
  }, [])

  const tara = gebinde.find(g => g.art === gart)
  const n = Number(kisten); const b = Number(brutto)
  const roh = b > 0 && n > 0 ? nettoKg(b, n, tara, mitPalette) : null
  const netto = roh === null ? null : Math.max(Math.round(roh), 0)
  const fehlt = b > 0 && n > 0 ? taraFehlt(tara, mitPalette) : null

  async function speichern() {
    if (netto === null || laeuft) return
    setLaeuft(true); setFehler(null)
    // kg ist ein Pflichtfeld; der Auslöser ersetzt es durch das Netto aus Brutto und Tara.
    const { error } = await supabase.from('schimmel_messung').insert({
      auftrag_id: d.auftrag.id, kg: netto, brutto_kg: b, kisten: n, gebindeart: gart, mit_palette: mitPalette,
    })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    setBrutto(''); setKisten('1'); setMitPalette(false)
    melden(t('gespeichert')); await neuLaden()
  }

  async function nichtsFaules() {
    if (laeuft) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from('schimmel_messung').insert({
      auftrag_id: d.auftrag.id, kg: 0, bemerkung: t('nichtsFaules'),
    })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    melden(t('gespeichert')); await neuLaden()
  }

  const summe = d.ablesungen.reduce((s, z) => s + z.kg, 0)

  return (
    <div className="karte">
      <p className="leise oben-0">{t('faulesWiegenWarum')}</p>
      <div className="feld">
        <label htmlFor="faul-brutto">{t('gewicht')}</label>
        <input id="faul-brutto" className="gross" type="number" inputMode="decimal" step="0.1" min={0}
               value={brutto} disabled={gesperrt} onChange={e => setBrutto(e.target.value)} autoFocus />
      </div>
      <div className="spalten">
        <div className="feld">
          <label htmlFor="faul-kisten">{t('anzahlKisten')}</label>
          <input id="faul-kisten" type="number" inputMode="numeric" min={1} value={kisten}
                 disabled={gesperrt} onChange={e => setKisten(e.target.value)} style={{ fontSize: '1.2rem' }} />
        </div>
        <div className="feld">
          <label htmlFor="faul-art">{t('kistenart')}</label>
          <select id="faul-art" value={gart} disabled={gesperrt} onChange={e => setGart(e.target.value)}>
            {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
          </select>
        </div>
      </div>
      <label className="ankreuzen">
        <input id="faul-palette" type="checkbox" checked={mitPalette} disabled={gesperrt}
               onChange={e => setMitPalette(e.target.checked)} />
        {t('aufPaletteGewogen')}
      </label>
      {netto !== null && (
        <p className="netto-zeile">
          <strong>{netto} kg</strong> {t('netto')}
        </p>
      )}
      <button type="button" id="faul-eintragen" className="haupt gross voll"
              onClick={() => void speichern()} disabled={gesperrt || laeuft || netto === null}>
        {t('eintragen')}
      </button>
      {d.ablesungen.length === 0 && (
        <button type="button" id="faul-nichts" className="voll" style={{ marginTop: '.6rem', minHeight: 48 }}
                onClick={() => void nichtsFaules()} disabled={gesperrt || laeuft}>
          {t('nichtsFaules')}
        </button>
      )}
      {d.ablesungen.length === 0 && <p className="hilfe">{t('nichtsFaulesErkl')}</p>}
      {fehlt && <Hinweis art="warnung">{fehlt} Ohne sie lässt sich das Nettogewicht nicht ausrechnen — die Angabe gehört in die Stammdaten.</Hinweis>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {d.ablesungen.length > 0 && (
        <>
          <p className="abstand-oben"><strong>{t('bisher')}: {summe} kg</strong></p>
          <table className="dicht"><tbody>
            {d.ablesungen.map(z => (
              <tr key={z.id}>
                <td>{uhrzeit(z.ts, gebietsschema)}</td>
                <td className="zahl">{z.kg} kg</td>
                <td className="leise">{z.brutto_kg !== null ? `${z.kisten ?? 1} × ${z.gebindeart ?? ''} · ${z.brutto_kg} kg` : (z.bemerkung ?? '')}</td>
                <td className="rechts-buendig">
                  <button type="button" className="gefahr klein" disabled={gesperrt} aria-label={t('loeschen')}
                          onClick={async () => {
                            const { error } = await supabase.from('schimmel_messung').delete().eq('id', z.id)
                            if (error) setFehler(fehlerText(error)); else await neuLaden()
                          }}><ZKreuz size={14} /></button>
                </td>
              </tr>
            ))}
          </tbody></table>
        </>
      )}
    </div>
  )
}
