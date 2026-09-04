import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { stationsProfil, type ArbeitDaten } from './daten'

const ZETTEL = (id: number) => `zettel_${id}`

/**
 * Der Zähler — das Einzige, was ein Zähler sieht.
 *
 * Paletten: Datum vom Zettel oben (Pflicht, AB-11), und es bleibt für die
 * nächste Palette stehen — die kommen zu Dutzenden mit demselben Datum. „+"
 * zählt sofort, „Rückgängig" nimmt die letzte zurück. Keine Nachfrage.
 *
 * Kisten: je Kaliberband ein Zähler (Sortieren: gefüllte, Waschen: geleerte).
 */
export function Zaehler({ d, gesperrt, neuLaden, melden, zumWiegen }: {
  d: ArbeitDaten; gesperrt: boolean
  neuLaden: () => Promise<void>; melden: (text: string) => void; zumWiegen: () => void
}) {
  const { t } = useSprache()
  const p = stationsProfil(d.auftrag)
  const [teil, setTeil] = useState<'paletten' | 'kisten'>(p.hatPaletten ? 'paletten' : 'kisten')
  const [zettel, setZettel] = useState(() => {
    try { return localStorage.getItem(ZETTEL(d.auftrag.id)) ?? '' } catch { return '' }
  })
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  function zettelSetzen(w: string) {
    setZettel(w)
    try { localStorage.setItem(ZETTEL(d.auftrag.id), w) } catch { /* privater Modus */ }
  }

  async function paletteZaehlen() {
    if (zettel === '' || laeuft) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from('auftrag_palette')
      .insert({ auftrag_id: d.auftrag.id, eingangsdatum: zettel })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    melden(t('paletteGezaehlt')); await neuLaden()
  }

  async function paletteZurueck() {
    const letzte = d.paletten[d.paletten.length - 1]
    if (!letzte || laeuft) return
    setLaeuft(true)
    if (letzte.wiegung_id) await supabase.from('verdunstung_wiegung').delete().eq('id', letzte.wiegung_id)
    const { error } = await supabase.from('auftrag_palette').delete().eq('id', letzte.id)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    melden(t('rueckgaengig')); await neuLaden()
  }

  async function kistenSetzen(idx: number, wert: number) {
    if (wert < 0 || laeuft) return
    setLaeuft(true)
    const { error } = await supabase.from('auftrag_gebinde')
      .upsert({ auftrag_id: d.auftrag.id, kaliber_idx: idx, anzahl: wert }, { onConflict: 'auftrag_id,kaliber_idx' })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    melden(t('gespeichert')); await neuLaden()
  }

  const anzahlVon = (idx: number) => d.gebinde.find(z => z.kaliber_idx === idx)?.anzahl ?? 0
  const indizes = d.auftrag.station === 'waschen'
    ? (d.auftrag.kaliber_idx === null ? [] : [d.auftrag.kaliber_idx])
    : d.baender.map((_, i) => i)
  const gewogen = d.paletten.filter(z => z.wiegung_id !== null).length

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
          </div>
          <div className="zaehler-gross">
            <div className="stand">{d.paletten.length}</div>
            <div className="einheit">{t('paletten')}{gewogen > 0 && ` · ${gewogen} ${t('gewogen')}`}</div>
          </div>
          <button id="zaehlen-plus" className="haupt zaehler-plus" disabled={gesperrt || laeuft || zettel === ''}
                  onClick={() => void paletteZaehlen()}>
            + 1 {t('paletteHingestellt')}
          </button>
          <button id="zaehlen-minus" className="zaehler-minus" disabled={gesperrt || laeuft || d.paletten.length === 0}
                  onClick={() => void paletteZurueck()}>
            ↶ {t('rueckgaengig')}
          </button>
          {p.mitWiegen && (
            <button id="zum-wiegen" style={{ width: '100%', marginTop: '.6rem', minHeight: 48 }}
                    disabled={gesperrt || zettel === ''} onClick={zumWiegen}>
              ⚖️ {t('paletteWiegen')}
            </button>
          )}
        </div>
      )}

      {teil === 'kisten' && p.hatKisten && (
        <div className="karte">
          <p className="leise" style={{ marginTop: 0 }}>
            {d.auftrag.station === 'waschen' ? t('kistenWaschenWarum') : t('kistenSortierenWarum')}
          </p>
          {d.auftrag.station === 'waschen' && d.auftrag.kaliber_idx === null && (
            <Hinweis art="warnung">{t('kistenOhneKaliber')}</Hinweis>
          )}
          {indizes.map(i => (
            <div key={i} style={{ marginBottom: '1rem' }}>
              <label>{t('kaliber')} {i + 1}{d.baender[i] && <span className="leise"> · {d.baender[i][0]}–{d.baender[i][1]} g</span>}</label>
              <div className="zaehler">
                <button onClick={() => void kistenSetzen(i, anzahlVon(i) - 1)} aria-label="−"
                        disabled={gesperrt || laeuft || anzahlVon(i) === 0}>−</button>
                <span className="stand">{anzahlVon(i)}</span>
                <button className="haupt" aria-label="+" id={`kiste-plus-${i}`} disabled={gesperrt || laeuft}
                        onClick={() => void kistenSetzen(i, anzahlVon(i) + 1)}>+</button>
              </div>
            </div>
          ))}
          {indizes.length === 0 && d.auftrag.kaliber_idx !== null && <Hinweis>{t('kistenKeineBaender')}</Hinweis>}
        </div>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </>
  )
}
