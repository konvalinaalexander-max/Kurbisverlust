import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { ZMinus, ZPlus, ZRueckgaengig, ZWaage } from '../components/Zeichen'
import { stationsProfil, type ArbeitDaten } from './daten'
import type { Gebinde } from '../lib/typen'
import { heute } from '../lib/format'

const ZETTEL = (id: number) => `zettel_${id}`
const SORTIERDATUM = (id: number) => `sortierdatum_${id}`
const KISTEN_PALETTE = (id: number) => `kisten_palette_${id}`
const GEBINDE = (id: number) => `gebinde_palette_${id}`

/**
 * Der Zähler — das Einzige, was ein Zähler sieht.
 *
 * Eingangspaletten (Sortieren, Waschen + Sortieren): Datum vom Zettel (Pflicht,
 * AB-11) bleibt für die nächste Palette stehen — die kommen zu Dutzenden mit
 * demselben Datum; der Knopf sagt, welches Datum er speichert. Beim Waschen +
 * Sortieren dazu das Gewicht vom Zettel (0060), je Palette neu. „Wägst du
 * diese Palette?" führt zur Wägung, sonst zählt „+" sofort.
 *
 * Kaliber-Paletten (Waschen, 0061): Sortierdatum vom Zettel (oder ausdrücklich
 * keines) und die Kisten darauf; beides bleibt für die nächste stehen.
 *
 * Kisten je Kaliber gibt es seit Runde Q nicht mehr: „niemand wird händisch
 * die kisten zählen und in der app eintragen". Die Masse je Kaliberband
 * kommt stattdessen aus Zettelgewicht × Kistenzahl der Eingangspaletten und
 * der Sortier-CSV — beides fällt ohnehin an.
 * Fax: die Palettenzahl als Gesamtzahl (0060) — eine Zahl, nicht Klicks.
 */
export function Zaehler({ d, gesperrt, neuLaden, melden, zumWiegen }: {
  d: ArbeitDaten; gesperrt: boolean
  neuLaden: () => Promise<void>; melden: (text: string) => void
  /** Zur Wägung — mit allem, was der Zähler schon weiss (Runde T): das
   *  Gewicht vom Zettel, die Kisten und das Gebinde. Vorher fing die
   *  Wägung mit leeren Kisten und dem ersten Gebinde der Liste an — und
   *  wer beim Zählen G2 gewählt hatte, wog plötzlich in IFCO. */
  zumWiegen: (brutto: string, kisten: string, gebinde: string) => void
}) {
  const { t, gebietsschema } = useSprache()
  const p = stationsProfil(d.auftrag)
  const lesen = (schluessel: string, sonst = '') => {
    try { return localStorage.getItem(schluessel) ?? sonst } catch { return sonst }
  }
  const merken = (schluessel: string, wert: string) => {
    try { localStorage.setItem(schluessel, wert) } catch { /* privater Modus */ }
  }
  const [zettel, setZettel] = useState(() => lesen(ZETTEL(d.auftrag.id)))
  const [brutto, setBrutto] = useState('')
  const [sortierdatum, setSortierdatum] = useState(() => lesen(SORTIERDATUM(d.auftrag.id)))
  const [ohneDatum, setOhneDatum] = useState(false)
  const [kistenPalette, setKistenPalette] = useState(() => lesen(KISTEN_PALETTE(d.auftrag.id), String(d.kistenProPalette)))
  // Das Gebinde klebt wie Datum und Kistenzahl: es kommen Dutzende Paletten
  // im selben. Vorbelegt aus der letzten Palette dieser Arbeit, sonst aus
  // der Einstellung (0072).
  const [gebinde, setGebinde] = useState(() =>
    d.paletten[d.paletten.length - 1]?.gebindeart
    || lesen(GEBINDE(d.auftrag.id))
    || d.gebindeLager)
  const [arten, setArten] = useState<Gebinde[]>([])
  const [paletten, setPaletten] = useState(String(d.auftrag.paletten_gesamt ?? ''))
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  function zettelSetzen(w: string) { setZettel(w); merken(ZETTEL(d.auftrag.id), w) }
  function sortierdatumSetzen(w: string) {
    setSortierdatum(w); if (w) setOhneDatum(false)
    merken(SORTIERDATUM(d.auftrag.id), w)
  }
  function kistenPaletteSetzen(w: string) { setKistenPalette(w); merken(KISTEN_PALETTE(d.auftrag.id), w) }
  function gebindeSetzen(w: string) { setGebinde(w); merken(GEBINDE(d.auftrag.id), w) }
  useEffect(() => { void stammdaten().then(s => setArten(s.gebinde)) }, [])

  const bruttoOk = !p.zettelGewichtPflicht || Number(brutto) > 0
  const datumText = (iso: string) => iso ? new Date(iso + 'T00:00:00').toLocaleDateString(gebietsschema, { day: '2-digit', month: '2-digit' }) : ''

  /** Nach dem Schreiben gesperrt bleiben, bis der neue Stand da ist — sonst
   *  zählt ein schneller zweiter Tipp vom alten Stand weiter. */
  async function nachladen(text: string) {
    melden(text)
    try { await neuLaden() } finally { setLaeuft(false) }
  }

  async function paletteZaehlen() {
    if (zettel === '' || !bruttoOk || !kistenOk || laeuft) return
    // Das Gewicht sofort leeren, nicht erst nach der Antwort: wer schon die
    // nächste Zahl tippt, während die erste noch unterwegs ist, verliert sie
    // sonst an das späte Leeren.
    const bruttoWert = brutto
    setLaeuft(true); setFehler(null); setBrutto('')
    const { error } = await supabase.from('auftrag_palette')
      // Kistenzahl und Gebinde gehen mit: aus Zettel-Brutto minus Tara
      // ergibt sich das Netto, und daraus mit der Sortier-CSV die Masse je
      // Kaliberband (Runde Q). Ein leeres Feld sperrt den Knopf — es wird
      // nie als 0 geschrieben.
      .insert({ auftrag_id: d.auftrag.id, eingangsdatum: zettel,
                brutto_zettel_kg: p.zettelGewichtPflicht ? Number(bruttoWert) : null,
                kisten: p.hatPaletten ? kistenZahl : null,
                gebindeart: p.hatPaletten ? gebinde : null })
    if (error) {
      setLaeuft(false); setFehler(fehlerText(error))
      setBrutto(b => (b === '' ? bruttoWert : b))   // nichts verloren: der Wert steht wieder da
      return
    }
    await nachladen(t('paletteGezaehlt'))
  }

  // Waschen (0061): eine Kaliber-Palette aus dem Zwischenlager.
  const kistenZahl = Number(kistenPalette)
  const kistenOk = Number.isInteger(kistenZahl) && kistenZahl > 0
  const waschBereit = (ohneDatum || sortierdatum !== '') && kistenOk && gebinde !== ''
  async function waschPaletteZaehlen() {
    if (!waschBereit || laeuft) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from('auftrag_palette')
      .insert({ auftrag_id: d.auftrag.id, sortierdatum: ohneDatum ? null : sortierdatum,
                kisten: kistenZahl, gebindeart: gebinde })
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    await nachladen(t('paletteGezaehlt'))
  }

  async function paletteZurueck() {
    const letzte = d.paletten[d.paletten.length - 1]
    if (!letzte || laeuft) return
    setLaeuft(true)
    if (letzte.wiegung_id) await supabase.from('verdunstung_wiegung').delete().eq('id', letzte.wiegung_id)
    const { error } = await supabase.from('auftrag_palette').delete().eq('id', letzte.id)
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    await nachladen(t('rueckgaengig'))
  }

  async function palettenSetzen(wert: number) {
    if (wert < 0 || laeuft) return
    setLaeuft(true); setFehler(null)
    setPaletten(String(wert))
    const { error } = await supabase.from('auftrag').update({ paletten_gesamt: wert }).eq('id', d.auftrag.id)
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    await nachladen(t('gespeichert'))
  }

  const gewogen = d.paletten.filter(z => z.wiegung_id != null).length
  const kistenGesamt = d.paletten.reduce((s, x) => s + (x.kisten ?? 0), 0)
  const kaliberFehlt = p.hatWaschPaletten && d.auftrag.kaliber_idx === null && d.auftrag.kaliber_von_g === null

  if (p.hatFaxPaletten) {
    // Fax: die Palettenzahl als eine Zahl — mit Tasten, damit niemand tippen muss
    const n = Number(paletten) || 0
    return (
      <div className="karte">
        <label htmlFor="paletten-gesamt">{t('palettenGesamt')}</label>
        <div className="zaehler">
          <button type="button" onClick={() => void palettenSetzen(n - 1)} aria-label="−" disabled={gesperrt || laeuft || n === 0}><ZMinus size={24} /></button>
          <input id="paletten-gesamt" type="number" inputMode="numeric" min={0} value={paletten} disabled={gesperrt}
                 className="stand" onChange={e => setPaletten(e.target.value)}
                 onBlur={() => { if (paletten !== '' && Number(paletten) !== (d.auftrag.paletten_gesamt ?? 0)) void palettenSetzen(Number(paletten)) }} />
          <button type="button" className="haupt" aria-label="+" id="paletten-plus" disabled={gesperrt || laeuft} onClick={() => void palettenSetzen(n + 1)}><ZPlus size={26} /></button>
        </div>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      </div>
    )
  }

  if (p.hatWaschPaletten) {
    return (
      <div className="karte">
        {kaliberFehlt && <Hinweis art="warnung">{t('kistenOhneKaliber')}</Hinweis>}
        <div className="feld">
          <label htmlFor="sortierdatum">{t('sortierdatumZettel')}</label>
          <input id="sortierdatum" type="date" value={ohneDatum ? '' : sortierdatum} disabled={gesperrt || ohneDatum}
                 onChange={e => sortierdatumSetzen(e.target.value)} style={{ fontSize: '1.15rem' }} />
          <label className="ankreuzen" style={{ marginTop: '.4rem' }}>
            <input id="kein-sortierdatum" type="checkbox" checked={ohneDatum} disabled={gesperrt} onChange={e => setOhneDatum(e.target.checked)} />
            {t('keinSortierdatum')}
          </label>
        </div>
        <div className="feld">
          <label htmlFor="gebinde-palette">{t('gebindeFrage')}</label>
          <select id="gebinde-palette" value={gebinde} disabled={gesperrt}
                  onChange={e => gebindeSetzen(e.target.value)} style={{ fontSize: '1.1rem' }}>
            {arten.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
          </select>
        </div>
        <div className="feld">
          <label htmlFor="kisten-palette">{t('kistenAufPalette')}</label>
          <div className="zaehler">
            <button type="button" aria-label="−" disabled={gesperrt || laeuft || kistenZahl <= 1}
                    onClick={() => kistenPaletteSetzen(String(Math.max(1, kistenZahl - 1)))}><ZMinus size={24} /></button>
            <input id="kisten-palette" type="number" inputMode="numeric" min={1} step={1} value={kistenPalette} disabled={gesperrt}
                   className="stand" onChange={e => kistenPaletteSetzen(e.target.value)} />
            <button type="button" aria-label="+" disabled={gesperrt || laeuft}
                    onClick={() => kistenPaletteSetzen(String((Number.isFinite(kistenZahl) ? kistenZahl : 0) + 1))}><ZPlus size={24} /></button>
          </div>
        </div>
        <div className="zaehler-gross">
          <div className="stand neu" key={d.paletten.length}>{d.paletten.length}</div>
          <div className="einheit">{t('paletten')} · {kistenGesamt} {t('kisten')}</div>
        </div>
        <button type="button" id="wasch-plus" className="haupt zaehler-plus" disabled={gesperrt || laeuft || !waschBereit}
                onClick={() => void waschPaletteZaehlen()}>
          <span><ZPlus size={22} /> 1 {t('paletteHingestellt')}</span>
          {waschBereit && <span className="klein-text">{ohneDatum ? t('keinSortierdatum') : datumText(sortierdatum)} · {kistenZahl} {gebinde}</span>}
        </button>
        {/* Runde T: statt Erklärtexten unter jedem Feld ein Satz am grauen
            Knopf, der sagt, was ihm gerade fehlt. */}
        {!waschBereit && !gesperrt && (
          <p className="zaehler-grund" role="status">
            {!(ohneDatum || sortierdatum !== '') ? t('grundSortierdatumFehlt') : !kistenOk ? t('grundKistenFehlen') : t('gebindeFrage')}
          </p>
        )}
        <button type="button" id="wasch-minus" className="zaehler-minus" disabled={gesperrt || laeuft || d.paletten.length === 0}
                onClick={() => void paletteZurueck()}>
          <ZRueckgaengig size={18} /> {t('rueckgaengig')}
        </button>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      </div>
    )
  }

  return (
    <>
      {p.hatPaletten && (
        <div className="karte">
          <div className="feld">
            <label htmlFor="zettel">{t('datumZettel')}</label>
            <input id="zettel" type="date" value={zettel} disabled={gesperrt}
                   onChange={e => zettelSetzen(e.target.value)} style={{ fontSize: '1.15rem' }} />
            {zettel !== '' && zettel > heute() && (
              <p className="hilfe gelb" style={{ fontWeight: 560 }}>{t('datumZukunft')}</p>
            )}
          </div>
          {p.zettelGewichtPflicht && (
            <div className="feld">
              <label htmlFor="zettel-brutto">{t('gewichtZettel')}</label>
              <input id="zettel-brutto" type="number" inputMode="decimal" step="0.5" min={0} value={brutto} disabled={gesperrt}
                     onChange={e => setBrutto(e.target.value)} style={{ fontSize: '1.15rem' }} />
            </div>
          )}
          {/* Kisten je Eingangspalette (Runde Q): vorbelegt mit 36, immer
              änderbar — der Betrieb sagt „teilweise sinds 32 und teilweise
              36". Zusammen mit dem Zettelgewicht ergibt das die Masse, die
              in die Maschine ging. */}
          <div className="feld">
            <label htmlFor="kisten-palette">{t('kistenAufPalette')}</label>
            <div className="zaehler">
              <button type="button" aria-label="−" disabled={gesperrt || laeuft || kistenZahl <= 1}
                      onClick={() => kistenPaletteSetzen(String(Math.max(1, kistenZahl - 1)))}><ZMinus size={24} /></button>
              <input id="kisten-palette" type="number" inputMode="numeric" min={1} step={1} value={kistenPalette} disabled={gesperrt}
                     className="stand" onChange={e => kistenPaletteSetzen(e.target.value)} />
              <button type="button" aria-label="+" disabled={gesperrt || laeuft}
                      onClick={() => kistenPaletteSetzen(String((Number.isFinite(kistenZahl) ? kistenZahl : 0) + 1))}><ZPlus size={24} /></button>
            </div>
          </div>
          <div className="feld">
            <label htmlFor="gebinde-eingang">{t('gebindeFrage')}</label>
            <select id="gebinde-eingang" value={gebinde} disabled={gesperrt}
                    onChange={e => gebindeSetzen(e.target.value)} style={{ fontSize: '1.1rem' }}>
              {arten.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
            </select>
          </div>
          <div className="zaehler-gross">
            <div className="stand neu" key={d.paletten.length}>{d.paletten.length}</div>
            <div className="einheit">{t('paletten')}{gewogen > 0 && ` · ${gewogen} ${t('gewogen')}`}</div>
          </div>
          {p.wiegenSoll > 0 && gewogen < p.wiegenSoll && (
            <p className="leise mitte" style={{ margin: '0 0 .6rem' }}>
              {t('dreiWiegen')} {t('nurGewogen').replace('{n}', String(gewogen)).replace('{soll}', String(p.wiegenSoll))}
            </p>
          )}
          <button type="button" id="zaehlen-plus" className="haupt zaehler-plus" disabled={gesperrt || laeuft || zettel === '' || !bruttoOk || !kistenOk}
                  onClick={() => void paletteZaehlen()}>
            <span><ZPlus size={22} /> 1 {t('paletteHingestellt')}</span>
            {zettel !== '' && <span className="klein-text">{datumText(zettel)}{p.zettelGewichtPflicht && brutto !== '' ? ` · ${brutto} kg` : ''}{kistenOk ? ` · ${kistenZahl} ${gebinde}` : ''}</span>}
          </button>
          {/* Runde T: der Grund am grauen Knopf statt eines Absatzes unter
              jedem Feld — genau das eine, was gerade fehlt. */}
          {(zettel === '' || !bruttoOk || !kistenOk) && !gesperrt && (
            <p className="zaehler-grund" role="status">
              {zettel === '' ? t('grundDatumFehlt') : !bruttoOk ? t('grundGewichtFehlt') : t('grundKistenFehlen')}
            </p>
          )}
          <button type="button" id="zaehlen-minus" className="zaehler-minus" disabled={gesperrt || laeuft || d.paletten.length === 0}
                  onClick={() => void paletteZurueck()}>
            <ZRueckgaengig size={18} /> {t('rueckgaengig')}
          </button>
          {p.mitWiegen && (
            <button type="button" id="zum-wiegen" className="voll" style={{ marginTop: '.6rem', minHeight: 48 }}
                    disabled={gesperrt || zettel === '' || !bruttoOk || !kistenOk} onClick={() => zumWiegen(brutto, kistenPalette, gebinde)}>
              <ZWaage size={18} /> {t('paletteWiegenFrage')}
            </button>
          )}
        </div>
      )}

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </>
  )
}
