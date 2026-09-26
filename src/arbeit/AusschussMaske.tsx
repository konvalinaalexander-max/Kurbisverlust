import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { ZKreuz } from '../components/Zeichen'
import { Wahl } from '../components/Schritte'
import { uhrzeit, type ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'
import { nettoKg, taraFehlt } from '../lib/masse'

type Art = 'zu_klein' | 'zu_gross'

/**
 * Zu klein / zu gross beim Waschen + Sortieren (0061): Am Band gibt es keine
 * Sortier-CSV — was von Hand aussortiert wurde, wird am Ende gewogen: Art,
 * Brutto, Kisten, Kistenart. Das Netto rechnet die Datenbank (Auslöser aus
 * 0044). „Nichts zu klein oder zu gross" ist eine Messung mit 0 kg für beide
 * Arten, kein Auslassen.
 *
 * Seit 0083 fragt die Maske, ob eine Palette drunter steht — und sie fragt
 * es, statt es anzunehmen. Vorher zog sie immer 25 kg Palette ab, auch von
 * der einen Kiste, die jemand direkt auf die Waage stellte: 12 − 1.5 − 25
 * ist negativ, und das wurde still zu null. Der Betrieb: „man kanns zwar
 * eingeben - aber es gibt trotzdem immer nur 0 ein". Jetzt gibt es ohne
 * die Antwort keinen Eintrag, und ein Brutto unter der Tara wird gesagt
 * statt verschluckt.
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
  // Keine Vorgabe: Die Maske kann nicht wissen, ob eine Palette drunter
  // steht, und beide Annahmen gehen daneben — die eine still (null Kilo),
  // die andere um 25 kg. Also wird gefragt. Die Antwort bleibt für die
  // nächste Wägung stehen, denn die steht meist gleich auf der Waage.
  const [mitPalette, setMitPalette] = useState<boolean | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  useEffect(() => {
    void stammdaten().then(s => { setGebinde(s.gebinde); setGart(a => a || s.gebinde[0]?.art || '') })
  }, [])

  const tara = gebinde.find(g => g.art === gart)
  const n = Number(kisten); const b = Number(brutto)
  const eingegeben = b > 0 && n > 0
  const roh = eingegeben && mitPalette !== null ? nettoKg(b, n, tara, mitPalette) : null
  // Kein Math.max(…, 0): ein negatives Netto ist ein Widerspruch, den der
  // Arbeiter sehen muss — nicht eine leere Wägung.
  const netto = roh === null ? null : Math.round(roh)
  const fehlt = eingegeben && mitPalette !== null ? taraFehlt(tara, mitPalette) : null
  const unterTara = netto !== null && netto < 0
  const grund = !eingegeben ? null
    : mitPalette === null ? t('paletteZuerst')
    : unterTara ? (mitPalette ? t('bruttoUnterTara') : t('bruttoUnterKisten'))
    : null
  const kannSpeichern = netto !== null && netto >= 0 && !fehlt

  async function speichern() {
    if (!kannSpeichern || mitPalette === null || laeuft) return
    setLaeuft(true); setFehler(null)
    // kg ist ein Pflichtfeld; der Auslöser ersetzt es durch das Netto aus Brutto und Tara.
    const { error } = await supabase.from('ausschuss_messung').insert({
      auftrag_id: d.auftrag.id, art, kg: netto, brutto_kg: b, kisten: n, gebindeart: gart, mit_palette: mitPalette,
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
      <div className="wahl" style={{ marginBottom: '.75rem' }}>
        <Wahl id="aus-zu_klein" name={t('zuKlein')} gewaehlt={art === 'zu_klein'} onClick={() => setArt('zu_klein')} />
        <Wahl id="aus-zu_gross" name={t('zuGross')} gewaehlt={art === 'zu_gross'} onClick={() => setArt('zu_gross')} />
      </div>
      <div className="feld">
        <label htmlFor="aus-brutto">{t('gewicht')}</label>
        <input id="aus-brutto" className="gross" type="number" inputMode="decimal" step="0.1" min={0}
               value={brutto} disabled={gesperrt} onChange={e => setBrutto(e.target.value)} />
      </div>
      <div className="spalten">
        <div className="feld">
          <label htmlFor="aus-kisten">{t('anzahlKisten')}</label>
          <input id="aus-kisten" type="number" inputMode="numeric" min={1} value={kisten}
                 disabled={gesperrt} onChange={e => setKisten(e.target.value)} style={{ fontSize: '1.2rem' }} />
        </div>
        <div className="feld">
          <label htmlFor="aus-art">{t('kistenart')}</label>
          <select id="aus-art" value={gart} disabled={gesperrt} onChange={e => setGart(e.target.value)}>
            {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
          </select>
        </div>
      </div>
      <div className="feld">
        <label>{t('paletteFrage')}</label>
        <div className="wahl">
          <Wahl id="aus-ohne-palette" name={t('ohnePaletteGewogen')} gewaehlt={mitPalette === false}
                onClick={() => !gesperrt && setMitPalette(false)} />
          <Wahl id="aus-mit-palette" name={t('aufPaletteGewogen')} gewaehlt={mitPalette === true}
                onClick={() => !gesperrt && setMitPalette(true)} />
        </div>
      </div>
      {netto !== null && tara?.tara_kg_pro_kiste != null && (
        <p className="netto-zeile">
          <strong>{netto} kg</strong> {t('netto')} · {artText(art)}
          <span className="leise">
            {' '}· {b} − {n} × {tara.tara_kg_pro_kiste}
            {mitPalette && tara.tara_kg_palette != null ? ` − ${tara.tara_kg_palette} ${t('paletteWort')}` : ''}
          </span>
        </p>
      )}
      {grund && <p className="grund" role="status">{grund}</p>}
      <button type="button" id="aus-eintragen" className="haupt gross voll"
              onClick={() => void speichern()} disabled={gesperrt || laeuft || !kannSpeichern}>
        {t('eintragen')}
      </button>
      {d.ausschuss.length === 0 && (
        <>
          <button type="button" id="aus-nichts" className="voll" style={{ marginTop: '.6rem', minHeight: 48 }}
                  onClick={() => void nichts()} disabled={gesperrt || laeuft}>
            {t('ausschussNichts')}
          </button>
        </>
      )}
      {fehlt && <Hinweis art="warnung">{fehlt}</Hinweis>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {d.ausschuss.length > 0 && (
        <>
          <p className="abstand-oben">
            <strong>{t('bisher')}: {t('zuKlein')} {summe('zu_klein')} kg · {t('zuGross')} {summe('zu_gross')} kg</strong>
          </p>
          <table className="dicht"><tbody>
            {d.ausschuss.map(z => (
              <tr key={z.id}>
                <td>{uhrzeit(z.ts, gebietsschema)}</td>
                <td>{artText(z.art)}</td>
                <td className="zahl">{z.kg} kg</td>
                <td className="leise">
                  {z.brutto_kg !== null
                    ? `${z.kisten ?? 1} × ${z.gebindeart ?? ''} · ${z.brutto_kg} kg${z.mit_palette ? ` · ${t('paletteWort')}` : ''}`
                    : (z.bemerkung ?? '')}
                </td>
                <td className="rechts-buendig">
                  <button type="button" className="gefahr klein" disabled={gesperrt} aria-label={t('loeschen')}
                          onClick={async () => {
                            const { error } = await supabase.from('ausschuss_messung').delete().eq('id', z.id)
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
