import { useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { ZKiste, ZKreuz } from '../components/Zeichen'
import { Wahl } from '../components/Schritte'
import { uhrzeit, type ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'

type Art = 'zu_klein' | 'zu_gross'

/** Die Kistenart, in der der Ausschuss im Betrieb steht — vorbelegt, änderbar. */
const KISTE_VORGABE = 'G2'
/** Über diesem Brutto fragt die Maske nach — so viel wiegt eine volle Kiste selten. */
const VIEL_FUER_EINE_KISTE_KG = 30
/** Ab hier ist es keine einzelne Kiste mehr: gesperrt, mit Grund. */
const KEINE_EINZELNE_KISTE_AB_KG = 60

/** Die noch nicht eingetragenen Kisten überleben ein zugeklapptes Handy. */
const merkzettel = (auftragId: number) => `ausschuss_kisten_${auftragId}`

/**
 * Zu klein / zu gross beim Waschen + Sortieren (0061), seit 0088 **Kiste für
 * Kiste**. Der Betrieb: „die Kisten werden nacheinander auf eine Waage
 * gestellt … sie werden nie auf Paletten stehen, sondern nur einzelne
 * Kisten … mach im UI so, dass klar ist, sie muss jetzt eine einzelne Kiste
 * angeben."
 *
 * Also: eine Art wählen, die Kistenart ist vorbelegt (G2), und dann eine
 * Kiste nach der anderen — Brutto tippen, „Kiste dazu", die nächste. Die
 * Maske zieht die leere Kiste ab und zählt mit. Am Ende schreibt sie EINE
 * Zeile je Art: Kistenzahl, Summe der Bruttos, die einzelnen Gewichte in
 * der Bemerkung. Eine Zeile, nicht eine je Kiste, weil kg ganzzahlig ist
 * und die Datenbank je Zeile rundet: drei Kisten zu 10.5 kg wären als drei
 * Zeilen 33 kg, als eine 32.
 *
 * Eine Palette gibt es hier nicht mehr — die Frage aus 0083 ist mit dem
 * Betrieb beantwortet. Was zu schwer für eine Kiste ist, wird gesagt: ab
 * 30 kg als Rückfrage, ab 60 kg als Sperre.
 */
export function AusschussMaske({ d, gesperrt, melden, neuLaden }: {
  d: ArbeitDaten; gesperrt: boolean; melden: (text: string) => void; neuLaden: () => Promise<void>
}) {
  const { t, gebietsschema } = useSprache()
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [art, setArt] = useState<Art>('zu_klein')
  const [gart, setGart] = useState('')
  const [brutto, setBrutto] = useState('')
  const [kisten, setKisten] = useState<Record<Art, number[]>>(() => {
    try { return JSON.parse(localStorage.getItem(merkzettel(d.auftrag.id)) ?? '') as Record<Art, number[]> }
    catch { return { zu_klein: [], zu_gross: [] } }
  })
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)
  const feld = useRef<HTMLInputElement>(null)

  useEffect(() => {
    void stammdaten().then(s => {
      setGebinde(s.gebinde)
      setGart(a => a || (s.gebinde.some(g => g.art === KISTE_VORGABE) ? KISTE_VORGABE : s.gebinde[0]?.art ?? ''))
    })
  }, [])
  useEffect(() => {
    try { localStorage.setItem(merkzettel(d.auftrag.id), JSON.stringify(kisten)) } catch { /* privates Fenster: dann eben nicht */ }
  }, [kisten, d.auftrag.id])

  const tara = gebinde.find(g => g.art === gart)
  const taraKiste = tara?.tara_kg_pro_kiste ?? null
  const liste = kisten[art]
  const b = brutto === '' ? null : Number(brutto)
  const ersetzen = (text: string, werte: Record<string, number | string>) =>
    Object.entries(werte).reduce((s, [k, v]) => s.replace(`{${k}}`, String(v)), text)
  const artText = (a: Art) => (a === 'zu_klein' ? t('zuKlein') : t('zuGross'))

  // Die eine Kiste auf der Waage: was an ihr nicht stimmen kann, steht am Knopf.
  const grund = b === null || taraKiste === null ? null
    : b >= KEINE_EINZELNE_KISTE_AB_KG ? t('zuSchwerFuerKiste')
    : b <= taraKiste ? t('bruttoUnterKiste')
    : null
  const viel = b !== null && grund === null && b > VIEL_FUER_EINE_KISTE_KG
  const kannDazu = b !== null && b > 0 && taraKiste !== null && grund === null && !gesperrt

  function dazu() {
    if (!kannDazu || b === null) return
    setKisten(k => ({ ...k, [art]: [...k[art], b] }))
    setBrutto('')
    feld.current?.focus()
  }
  function entfernen(i: number) {
    setKisten(k => ({ ...k, [art]: k[art].filter((_, j) => j !== i) }))
  }

  const summeBrutto = Math.round(liste.reduce((s, x) => s + x, 0) * 100) / 100
  const roh = taraKiste !== null && liste.length > 0 ? summeBrutto - liste.length * taraKiste : null
  const netto = roh === null ? null : Math.round(roh)

  async function speichern() {
    if (netto === null || netto < 0 || laeuft || gesperrt) return
    setLaeuft(true); setFehler(null)
    // Eine Zeile je Art: Summe und Kistenzahl — der Auslöser rechnet das Netto
    // aus Brutto und Tara noch einmal selbst (0044/0083); die einzelnen
    // Gewichte bleiben lesbar in der Bemerkung.
    const { error } = await supabase.from('ausschuss_messung').insert({
      auftrag_id: d.auftrag.id, art, kg: netto, brutto_kg: summeBrutto, kisten: liste.length, gebindeart: gart,
      mit_palette: false,
      bemerkung: `${ersetzen(t('kistenEinzelnGewogen'), { n: liste.length })}: ${liste.join(' · ')} kg`,
    })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    setKisten(k => ({ ...k, [art]: [] }))
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
  const andere: Art = art === 'zu_klein' ? 'zu_gross' : 'zu_klein'

  return (
    <div className="karte">
      <div className="wahl" style={{ marginBottom: '.75rem' }}>
        <Wahl id="aus-zu_klein" name={t('zuKlein')} gewaehlt={art === 'zu_klein'} onClick={() => setArt('zu_klein')} />
        <Wahl id="aus-zu_gross" name={t('zuGross')} gewaehlt={art === 'zu_gross'} onClick={() => setArt('zu_gross')} />
      </div>

      {/* Die Regel, gross und vor dem Feld: eine Kiste, keine Palette. */}
      <p className="einzelkiste" id="aus-einzelkiste">
        <ZKiste size={28} />
        <span>{t('einzelneKiste')}</span>
      </p>

      <form onSubmit={e => { e.preventDefault(); dazu() }}>
        <div className="feld">
          <label htmlFor="aus-kiste">
            <strong>{ersetzen(t('kisteNr'), { n: liste.length + 1 })}</strong> · {t('waageZeigt')}
          </label>
          <input id="aus-kiste" ref={feld} className="gross" type="number" inputMode="decimal" step="0.1" min={0}
                 value={brutto} disabled={gesperrt} onChange={e => setBrutto(e.target.value)} autoFocus />
        </div>
        {b !== null && taraKiste !== null && grund === null && (
          <p className="netto-zeile">
            <strong>{Math.round((b - taraKiste) * 10) / 10} kg</strong> {t('netto')}
            <span className="leise"> · {b} − {taraKiste} {gart}</span>
          </p>
        )}
        {grund && <p className="grund" role="status">{grund}</p>}
        {viel && <Hinweis art="warnung">{t('vielFuerKiste')}</Hinweis>}
        <button type="submit" id="aus-kiste-dazu" className="haupt gross voll" disabled={!kannDazu || laeuft}>
          {t('kisteDazu')}
        </button>
      </form>

      <div className="feld abstand-oben">
        <label htmlFor="aus-art">{t('kistenart')}</label>
        <select id="aus-art" value={gart} disabled={gesperrt || liste.length > 0} onChange={e => setGart(e.target.value)}>
          {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}{g.tara_kg_pro_kiste != null ? ` · ${g.tara_kg_pro_kiste} kg` : ''}</option>)}
        </select>
      </div>

      {liste.length > 0 && (
        <>
          <ol className="kistenliste" aria-label={artText(art)}>
            {liste.map((x, i) => (
              <li key={i}>
                <span>{ersetzen(t('kisteNr'), { n: i + 1 })}</span>
                <span className="zahl">{x} kg{taraKiste !== null && <span className="leise"> → {Math.round((x - taraKiste) * 10) / 10} kg</span>}</span>
                <button type="button" className="gefahr klein" aria-label={t('kisteEntfernen')} disabled={gesperrt}
                        onClick={() => entfernen(i)}><ZKreuz size={14} /></button>
              </li>
            ))}
          </ol>
          {netto !== null && (
            <p className="netto-zeile">
              <strong>{netto} kg</strong> {t('netto')} · {artText(art)}
              <span className="leise"> · {summeBrutto} − {liste.length} × {taraKiste}</span>
            </p>
          )}
          <button type="button" id="aus-eintragen" className="haupt gross voll"
                  onClick={() => void speichern()} disabled={gesperrt || laeuft || netto === null || netto < 0}>
            {liste.length === 1 ? t('kisteEintragen') : ersetzen(t('kistenEintragen'), { n: liste.length })}
          </button>
        </>
      )}
      {kisten[andere].length > 0 && (
        <p className="hilfe">{ersetzen(t('kistenNochOffen'), { n: kisten[andere].length, art: artText(andere) })}</p>
      )}
      {d.ausschuss.length === 0 && liste.length === 0 && (
        <button type="button" id="aus-nichts" className="voll" style={{ marginTop: '.6rem', minHeight: 48 }}
                onClick={() => void nichts()} disabled={gesperrt || laeuft}>
          {t('ausschussNichts')}
        </button>
      )}
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
                    ? `${z.kisten ?? 1} × ${z.gebindeart ?? ''} · ${z.brutto_kg} kg${z.mit_palette ? ` · ${t('paletteWort')}` : ''}${z.bemerkung ? ` · ${z.bemerkung}` : ''}`
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
