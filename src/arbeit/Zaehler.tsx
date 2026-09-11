import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { stationsProfil, type ArbeitDaten } from './daten'
import { heute } from '../lib/format'

const ZETTEL = (id: number) => `zettel_${id}`
const SORTIERDATUM = (id: number) => `sortierdatum_${id}`
const KISTEN_PALETTE = (id: number) => `kisten_palette_${id}`

/**
 * Der Zähler — das Einzige, was ein Zähler sieht.
 *
 * Eingangspaletten (Sortieren, Waschen + Sortieren): Datum vom Zettel (Pflicht,
 * AB-11) bleibt für die nächste Palette stehen — die kommen zu Dutzenden mit
 * demselben Datum; der Knopf sagt, welches Datum er speichert. Beim Waschen +
 * Sortieren dazu das Gewicht vom Zettel (0060), je Palette neu. „Wägst du
 * diese Palette?" führt zur Wägung, sonst zählt „+" sofort.
 *
 * Kaliber-Paletten (Waschen, 0061): Was gewaschen wird, steht auf Paletten aus
 * dem Zwischenlager — auf dem Zettel das Sortierdatum, darauf die Kisten. Gezählt
 * wird die Palette mit beidem; Datum und Kistenzahl bleiben stehen, „kein Datum
 * auf dem Zettel" ist eine Antwort.
 *
 * Kisten je Kaliber (Sortieren): je Band ein Zähler der gefüllten Kisten —
 * erst daraus kennt die Auswertung das Kistengewicht des Kalibers.
 *
 * Fax: die Palettenzahl als Gesamtzahl (0060) — eine Zahl, nicht Klicks.
 */
export function Zaehler({ d, gesperrt, neuLaden, melden, zumWiegen }: {
  d: ArbeitDaten; gesperrt: boolean
  neuLaden: () => Promise<void>; melden: (text: string) => void; zumWiegen: (brutto: string) => void
}) {
  const { t, gebietsschema } = useSprache()
  const p = stationsProfil(d.auftrag)
  const lesen = (schluessel: string, sonst = '') => {
    try { return localStorage.getItem(schluessel) ?? sonst } catch { return sonst }
  }
  const merken = (schluessel: string, wert: string) => {
    try { localStorage.setItem(schluessel, wert) } catch { /* privater Modus */ }
  }
  const [teil, setTeil] = useState<'paletten' | 'kisten'>(p.hatPaletten ? 'paletten' : 'kisten')
  const [zettel, setZettel] = useState(() => lesen(ZETTEL(d.auftrag.id)))
  const [brutto, setBrutto] = useState('')
  const [sortierdatum, setSortierdatum] = useState(() => lesen(SORTIERDATUM(d.auftrag.id)))
  const [ohneDatum, setOhneDatum] = useState(false)
  const [kistenPalette, setKistenPalette] = useState(() => lesen(KISTEN_PALETTE(d.auftrag.id), String(d.kistenProPalette)))
  const [paletten, setPaletten] = useState(String(d.auftrag.paletten_gesamt ?? ''))
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  function zettelSetzen(w: string) { setZettel(w); merken(ZETTEL(d.auftrag.id), w) }
  function sortierdatumSetzen(w: string) {
    setSortierdatum(w); if (w) setOhneDatum(false)
    merken(SORTIERDATUM(d.auftrag.id), w)
  }
  function kistenPaletteSetzen(w: string) { setKistenPalette(w); merken(KISTEN_PALETTE(d.auftrag.id), w) }

  const bruttoOk = !p.zettelGewichtPflicht || Number(brutto) > 0
  const datumText = (iso: string) => iso ? new Date(iso + 'T00:00:00').toLocaleDateString(gebietsschema, { day: '2-digit', month: '2-digit' }) : ''

  /** Nach dem Schreiben gesperrt bleiben, bis der neue Stand da ist — sonst
   *  zählt ein schneller zweiter Tipp vom alten Stand weiter. */
  async function nachladen(text: string) {
    melden(text)
    try { await neuLaden() } finally { setLaeuft(false) }
  }

  async function paletteZaehlen() {
    if (zettel === '' || !bruttoOk || laeuft) return
    // Das Gewicht sofort leeren, nicht erst nach der Antwort: wer schon die
    // nächste Zahl tippt, während die erste noch unterwegs ist, verliert sie
    // sonst an das späte Leeren.
    const bruttoWert = brutto
    setLaeuft(true); setFehler(null); setBrutto('')
    const { error } = await supabase.from('auftrag_palette')
      .insert({ auftrag_id: d.auftrag.id, eingangsdatum: zettel,
                brutto_zettel_kg: p.zettelGewichtPflicht ? Number(bruttoWert) : null })
    if (error) {
      setLaeuft(false); setFehler(fehlerText(error))
      setBrutto(b => (b === '' ? bruttoWert : b))   // nichts verloren: der Wert steht wieder da
      return
    }
    await nachladen(t('paletteGezaehlt'))
  }

  // Waschen (0061): eine Kaliber-Palette aus dem Zwischenlager — Sortierdatum
  // vom Zettel (oder ausdrücklich keines) und die Kisten darauf.
  const kistenZahl = Number(kistenPalette)
  const waschBereit = (ohneDatum || sortierdatum !== '') && Number.isInteger(kistenZahl) && kistenZahl > 0
  async function waschPaletteZaehlen() {
    if (!waschBereit || laeuft) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from('auftrag_palette')
      .insert({ auftrag_id: d.auftrag.id, sortierdatum: ohneDatum ? null : sortierdatum, kisten: kistenZahl })
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

  // Sortieren: die gefüllten Kisten je Kaliberband, ohne Datum — das
  // Sortierdatum ist heute, es kommt auf den Zettel der Palette.
  const zeile = (idx: number) => d.gebinde.find(z => z.kaliber_idx === idx)
  async function kistenSetzen(idx: number, wert: number) {
    if (wert < 0 || laeuft) return
    setLaeuft(true)
    const { error } = await supabase.from('auftrag_gebinde')
      .upsert({ auftrag_id: d.auftrag.id, kaliber_idx: idx, anzahl: wert, sortierdatum: null, datum_fehlt: false },
              { onConflict: 'auftrag_id,kaliber_idx,sortierdatum' })
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    await nachladen(t('gespeichert'))
  }

  async function palettenSetzen(wert: number) {
    if (wert < 0 || laeuft) return
    setLaeuft(true); setFehler(null)
    setPaletten(String(wert))
    const { error } = await supabase.from('auftrag').update({ paletten_gesamt: wert }).eq('id', d.auftrag.id)
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    await nachladen(t('gespeichert'))
  }

  const anzahlVon = (idx: number) => zeile(idx)?.anzahl ?? 0
  const gewogen = d.paletten.filter(z => z.wiegung_id != null).length
  const kistenGesamt = d.paletten.reduce((s, x) => s + (x.kisten ?? 0), 0)
  const kaliberFehlt = p.hatWaschPaletten && d.auftrag.kaliber_idx === null && d.auftrag.kaliber_von_g === null

  if (p.hatFaxPaletten) {
    // Fax: die Palettenzahl als eine Zahl — mit Tasten, damit niemand tippen muss
    const n = Number(paletten) || 0
    return (
      <div className="karte">
        <p className="leise" style={{ marginTop: 0 }}>{t('palettenGesamtWarum')}</p>
        <label htmlFor="paletten-gesamt">{t('palettenGesamt')}</label>
        <div className="zaehler">
          <button onClick={() => void palettenSetzen(n - 1)} aria-label="−" disabled={gesperrt || laeuft || n === 0}>−</button>
          <input id="paletten-gesamt" type="number" inputMode="numeric" min={0} value={paletten} disabled={gesperrt}
                 className="stand" style={{ width: '5rem', textAlign: 'center', fontSize: '1.6rem' }}
                 onChange={e => setPaletten(e.target.value)}
                 onBlur={() => { if (paletten !== '' && Number(paletten) !== (d.auftrag.paletten_gesamt ?? 0)) void palettenSetzen(Number(paletten)) }} />
          <button className="haupt" aria-label="+" id="paletten-plus" disabled={gesperrt || laeuft} onClick={() => void palettenSetzen(n + 1)}>+</button>
        </div>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      </div>
    )
  }

  if (p.hatWaschPaletten) {
    return (
      <div className="karte">
        <p className="leise" style={{ marginTop: 0 }}>{t('waschPalettenWarum')}</p>
        {kaliberFehlt && <Hinweis art="warnung">{t('kistenOhneKaliber')}</Hinweis>}
        <div className="feld">
          <label htmlFor="sortierdatum">{t('sortierdatumZettel')}</label>
          <input id="sortierdatum" type="date" value={ohneDatum ? '' : sortierdatum} disabled={gesperrt || ohneDatum}
                 onChange={e => sortierdatumSetzen(e.target.value)} style={{ fontSize: '1.15rem' }} />
          <label className="ankreuzen" style={{ marginTop: '.4rem' }}>
            <input id="kein-sortierdatum" type="checkbox" checked={ohneDatum} disabled={gesperrt} onChange={e => setOhneDatum(e.target.checked)} />
            {t('keinSortierdatum')}
          </label>
          <p className="leise" style={{ margin: '.35rem 0 0' }}>
            {ohneDatum || sortierdatum === '' ? t('sortierdatumErkl') : `${t('sortierdatumErkl')} ${t('datumBleibt')}`}
          </p>
        </div>
        <div className="feld">
          <label htmlFor="kisten-palette">{t('kistenAufPalette')}</label>
          <div className="zaehler">
            <button aria-label="−" disabled={gesperrt || laeuft || kistenZahl <= 1}
                    onClick={() => kistenPaletteSetzen(String(Math.max(1, kistenZahl - 1)))}>−</button>
            <input id="kisten-palette" type="number" inputMode="numeric" min={1} step={1} value={kistenPalette} disabled={gesperrt}
                   className="stand" style={{ width: '5rem', textAlign: 'center', fontSize: '1.6rem' }}
                   onChange={e => kistenPaletteSetzen(e.target.value)} />
            <button aria-label="+" disabled={gesperrt || laeuft}
                    onClick={() => kistenPaletteSetzen(String((Number.isFinite(kistenZahl) ? kistenZahl : 0) + 1))}>+</button>
          </div>
          <p className="leise" style={{ margin: '.35rem 0 0' }}>{t('kistenAufPaletteErkl')}</p>
        </div>
        <div className="zaehler-gross">
          <div className="stand">{d.paletten.length}</div>
          <div className="einheit">{t('paletten')} · {kistenGesamt} {t('kisten')}</div>
        </div>
        <button id="wasch-plus" className="haupt zaehler-plus" disabled={gesperrt || laeuft || !waschBereit}
                onClick={() => void waschPaletteZaehlen()}>
          + 1 {t('paletteHingestellt')}
          {waschBereit && <span style={{ fontWeight: 400, opacity: .85 }}> · {ohneDatum ? t('keinSortierdatum') : datumText(sortierdatum)} · {kistenZahl} {t('kisten')}</span>}
        </button>
        <button id="wasch-minus" className="zaehler-minus" disabled={gesperrt || laeuft || d.paletten.length === 0}
                onClick={() => void paletteZurueck()}>
          ↶ {t('rueckgaengig')}
        </button>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      </div>
    )
  }

  return (
    <>
      {p.hatPaletten && p.hatKisten && (
        <div className="umschalter gross" role="tablist">
          <button role="tab" aria-selected={teil === 'paletten'} className={teil === 'paletten' ? 'aktiv' : ''}
                  onClick={() => setTeil('paletten')}>{t('paletten')}</button>
          <button role="tab" aria-selected={teil === 'kisten'} className={teil === 'kisten' ? 'aktiv' : ''}
                  onClick={() => setTeil('kisten')}>{t('kaliberKisten')}</button>
        </div>
      )}

      {teil === 'paletten' && p.hatPaletten && (
        <div className="karte">
          <div className="feld">
            <label htmlFor="zettel">{t('datumZettel')}</label>
            <input id="zettel" type="date" value={zettel} disabled={gesperrt}
                   onChange={e => zettelSetzen(e.target.value)} style={{ fontSize: '1.15rem' }} />
            <p className="leise" style={{ margin: '.35rem 0 0' }}>
              {zettel === '' ? t('datumZettelPflicht') : t('datumBleibt')}
            </p>
            {zettel !== '' && zettel > heute() && (
              <p style={{ margin: '.35rem 0 0', color: 'var(--gelb)', fontWeight: 500 }}>{t('datumZukunft')}</p>
            )}
          </div>
          {p.zettelGewichtPflicht && (
            <div className="feld">
              <label htmlFor="zettel-brutto">{t('gewichtZettel')}</label>
              <input id="zettel-brutto" type="number" inputMode="decimal" step="0.5" min={0} value={brutto} disabled={gesperrt}
                     onChange={e => setBrutto(e.target.value)} style={{ fontSize: '1.15rem' }} />
              <p className="leise" style={{ margin: '.35rem 0 0' }}>{brutto === '' ? t('gewichtZettelPflicht') : t('gewichtZettelWarum')}</p>
            </div>
          )}
          <div className="zaehler-gross">
            <div className="stand">{d.paletten.length}</div>
            <div className="einheit">{t('paletten')}{gewogen > 0 && ` · ${gewogen} ${t('gewogen')}`}</div>
          </div>
          {p.wiegenSoll > 0 && gewogen < p.wiegenSoll && (
            <p className="leise" style={{ margin: '0 0 .6rem', textAlign: 'center' }}>
              {t('dreiWiegen')} {t('nurGewogen').replace('{n}', String(gewogen)).replace('{soll}', String(p.wiegenSoll))}
            </p>
          )}
          <button id="zaehlen-plus" className="haupt zaehler-plus" disabled={gesperrt || laeuft || zettel === '' || !bruttoOk}
                  onClick={() => void paletteZaehlen()}>
            + 1 {t('paletteHingestellt')}{zettel !== '' && <span style={{ fontWeight: 400, opacity: .85 }}> · {datumText(zettel)}{p.zettelGewichtPflicht && brutto !== '' ? ` · ${brutto} kg` : ''}</span>}
          </button>
          <button id="zaehlen-minus" className="zaehler-minus" disabled={gesperrt || laeuft || d.paletten.length === 0}
                  onClick={() => void paletteZurueck()}>
            ↶ {t('rueckgaengig')}
          </button>
          {p.mitWiegen && (
            <button id="zum-wiegen" style={{ width: '100%', marginTop: '.6rem', minHeight: 48 }}
                    disabled={gesperrt || zettel === ''} onClick={() => zumWiegen(brutto)}>
              ⚖️ {t('paletteWiegenFrage')}
            </button>
          )}
        </div>
      )}

      {teil === 'kisten' && p.hatKisten && (
        <div className="karte">
          <p className="leise" style={{ marginTop: 0 }}>{t('kistenSortierenWarum')}</p>
          {d.baender.map((band, i) => (
            <div key={i} style={{ marginBottom: '1rem' }}>
              <label>{t('kaliber')} {i + 1}<span className="leise"> · {band[0]}–{band[1]} g</span></label>
              <div className="zaehler">
                <button onClick={() => void kistenSetzen(i, anzahlVon(i) - 1)} aria-label="−"
                        disabled={gesperrt || laeuft || anzahlVon(i) === 0}>−</button>
                <span className="stand">{anzahlVon(i)}</span>
                <button className="haupt" aria-label="+" id={`kiste-plus-${i}`} disabled={gesperrt || laeuft}
                        onClick={() => void kistenSetzen(i, anzahlVon(i) + 1)}>+</button>
              </div>
            </div>
          ))}
          {d.baender.length === 0 && <Hinweis>{t('kistenKeineBaender')}</Hinweis>}
        </div>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </>
  )
}
