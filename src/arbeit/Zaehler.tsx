import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { stationsProfil, type ArbeitDaten } from './daten'

const ZETTEL = (id: number) => `zettel_${id}`
const KISTENDATUM = (id: number) => `kistendatum_${id}`

/**
 * Der Zähler — das Einzige, was ein Zähler sieht.
 *
 * Paletten (Sortieren, Waschen + Sortieren): Datum vom Zettel (Pflicht, AB-11)
 * bleibt für die nächste Palette stehen — die kommen zu Dutzenden mit
 * demselben Datum; der Knopf sagt, welches Datum er speichert. Beim Waschen +
 * Sortieren dazu das Gewicht vom Zettel (0060), je Palette neu. „Wägst du
 * diese Palette?" führt zur Wägung, sonst zählt „+" sofort.
 *
 * Kisten: je Kaliberband ein Zähler (Sortieren: gefüllte, Waschen: geleerte).
 * Beim Waschen steht das Sortierdatum auf der Kiste; es wird mitgezählt und
 * bleibt stehen, „kein Datum auf der Kiste" ist eine Antwort (0060).
 *
 * Fax: die Palettenzahl als Gesamtzahl (0060) — eine Zahl, nicht Klicks.
 */
export function Zaehler({ d, gesperrt, neuLaden, melden, zumWiegen }: {
  d: ArbeitDaten; gesperrt: boolean
  neuLaden: () => Promise<void>; melden: (text: string) => void; zumWiegen: (brutto: string) => void
}) {
  const { t, gebietsschema } = useSprache()
  const p = stationsProfil(d.auftrag)
  const [teil, setTeil] = useState<'paletten' | 'kisten'>(p.hatPaletten ? 'paletten' : 'kisten')
  const [zettel, setZettel] = useState(() => {
    try { return localStorage.getItem(ZETTEL(d.auftrag.id)) ?? '' } catch { return '' }
  })
  const [brutto, setBrutto] = useState('')
  const [kistendatum, setKistendatum] = useState(() => {
    try { return localStorage.getItem(KISTENDATUM(d.auftrag.id)) ?? '' } catch { return '' }
  })
  const [ohneDatum, setOhneDatum] = useState(false)
  const [paletten, setPaletten] = useState(String(d.auftrag.paletten_gesamt ?? ''))
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  function zettelSetzen(w: string) {
    setZettel(w)
    try { localStorage.setItem(ZETTEL(d.auftrag.id), w) } catch { /* privater Modus */ }
  }
  function kistendatumSetzen(w: string) {
    setKistendatum(w); if (w) setOhneDatum(false)
    try { localStorage.setItem(KISTENDATUM(d.auftrag.id), w) } catch { /* privater Modus */ }
  }

  const bruttoOk = !p.zettelGewichtPflicht || Number(brutto) > 0
  const datumText = (iso: string) => iso ? new Date(iso + 'T00:00:00').toLocaleDateString(gebietsschema, { day: '2-digit', month: '2-digit' }) : ''

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
    melden(t('paletteGezaehlt'))
    // Gesperrt bleiben, bis der neue Stand da ist — sonst zählt ein schneller
    // zweiter Tipp vom alten Stand weiter und ein Stück geht verloren.
    try { await neuLaden() } finally { setLaeuft(false) }
  }

  async function paletteZurueck() {
    const letzte = d.paletten[d.paletten.length - 1]
    if (!letzte || laeuft) return
    setLaeuft(true)
    if (letzte.wiegung_id) await supabase.from('verdunstung_wiegung').delete().eq('id', letzte.wiegung_id)
    const { error } = await supabase.from('auftrag_palette').delete().eq('id', letzte.id)
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    melden(t('rueckgaengig'))
    try { await neuLaden() } finally { setLaeuft(false) }
  }

  // Beim Waschen zählt jede Kiste zu ihrem Sortierdatum (oder ausdrücklich zu
  // „kein Datum"); beim Sortieren gibt es noch kein Datum.
  const datumJetzt = p.kistenMitDatum && !ohneDatum ? kistendatum : ''
  const datumFehlt = p.kistenMitDatum && ohneDatum
  const kistenBereit = !p.kistenMitDatum || ohneDatum || kistendatum !== ''
  const zeile = (idx: number) => d.gebinde.find(z => z.kaliber_idx === idx
    && (p.kistenMitDatum ? (z.sortierdatum ?? '') === datumJetzt && (z.datum_fehlt === datumFehlt || !datumFehlt && !z.datum_fehlt) : true))

  async function kistenSetzen(idx: number, wert: number) {
    if (wert < 0 || laeuft || !kistenBereit) return
    setLaeuft(true)
    const { error } = await supabase.from('auftrag_gebinde')
      .upsert({ auftrag_id: d.auftrag.id, kaliber_idx: idx, anzahl: wert,
                sortierdatum: datumJetzt || null, datum_fehlt: datumFehlt },
              { onConflict: 'auftrag_id,kaliber_idx,sortierdatum' })
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    melden(t('gespeichert'))
    try { await neuLaden() } finally { setLaeuft(false) }
  }

  async function palettenSetzen(wert: number) {
    if (wert < 0 || laeuft) return
    setLaeuft(true); setFehler(null)
    setPaletten(String(wert))
    const { error } = await supabase.from('auftrag').update({ paletten_gesamt: wert }).eq('id', d.auftrag.id)
    if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    melden(t('gespeichert'))
    try { await neuLaden() } finally { setLaeuft(false) }
  }

  const anzahlVon = (idx: number) => zeile(idx)?.anzahl ?? 0
  const gesamtVon = (idx: number) => d.gebinde.filter(z => z.kaliber_idx === idx).reduce((s, z) => s + z.anzahl, 0)
  // Welche Zähler es gibt: beim Waschen das eine Kaliber der Arbeit; beim
  // Sortieren alle Bänder.
  const indizes: number[] = d.auftrag.station === 'waschen'
    ? (d.auftrag.kaliber_idx !== null ? [d.auftrag.kaliber_idx]
       : d.auftrag.kaliber_von_g !== null ? [-2] : [])
    : d.baender.map((_, i) => i)
  const gewogen = d.paletten.filter(z => z.wiegung_id !== null).length
  const erklaerung = d.auftrag.station === 'waschen' ? t('kistenWaschenWarum') : t('kistenSortierenWarum')
  const bandName = (i: number) => i === -2
    ? `${t('kisteEigenesKaliber')} · ${d.auftrag.kaliber_von_g}–${d.auftrag.kaliber_bis_g} g`
    : i < 0 ? t('kisteOhneKaliber') : `${t('kaliber')} ${i + 1}`
  const idVon = (i: number) => i === -2 ? 'eigen' : i < 0 ? 'soll' : String(i)
  const datenGezaehlt = [...new Set(d.gebinde.map(z => z.datum_fehlt ? '' : (z.sortierdatum ?? '')))]

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
          <p className="leise" style={{ marginTop: 0 }}>{erklaerung}</p>
          {d.auftrag.station === 'waschen' && d.auftrag.kaliber_idx === null && d.auftrag.kaliber_von_g === null && (
            <Hinweis art="warnung">{t('kistenOhneKaliber')}</Hinweis>
          )}
          {p.kistenMitDatum && (
            <div className="feld">
              <label htmlFor="kistendatum">{t('sortierdatumKisteFrage')}</label>
              <input id="kistendatum" type="date" value={ohneDatum ? '' : kistendatum} disabled={gesperrt || ohneDatum}
                     onChange={e => kistendatumSetzen(e.target.value)} style={{ fontSize: '1.15rem' }} />
              <label className="ankreuzen" style={{ marginTop: '.4rem' }}>
                <input id="kein-datum" type="checkbox" checked={ohneDatum} disabled={gesperrt} onChange={e => setOhneDatum(e.target.checked)} />
                {t('keinDatumKiste')}
              </label>
              <p className="leise" style={{ margin: '.35rem 0 0' }}>
                {ohneDatum ? t('sortierdatumErkl') : kistendatum === '' ? t('sortierdatumErkl') : `${t('sortierdatumErkl')} ${t('datumBleibtKiste')}`}
              </p>
            </div>
          )}
          {indizes.map(i => (
            <div key={i} style={{ marginBottom: '1rem' }}>
              <label>{bandName(i)}{i >= 0 && d.baender[i] && <span className="leise"> · {d.baender[i][0]}–{d.baender[i][1]} g</span>}
                {p.kistenMitDatum && datenGezaehlt.length > 1 && <span className="leise"> · {gesamtVon(i)} {t('kisten')}</span>}</label>
              <div className="zaehler">
                <button onClick={() => void kistenSetzen(i, anzahlVon(i) - 1)} aria-label="−"
                        disabled={gesperrt || laeuft || anzahlVon(i) === 0 || !kistenBereit}>−</button>
                <span className="stand">{anzahlVon(i)}</span>
                <button className="haupt" aria-label="+" id={`kiste-plus-${idVon(i)}`} disabled={gesperrt || laeuft || !kistenBereit}
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
