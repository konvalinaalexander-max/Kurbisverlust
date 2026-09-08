import { useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { Schritt, Wahl } from '../components/Schritte'
import { PaloxMaske } from './PaloxMaske'
import { FauleMaske } from './FauleMaske'
import { FertigePaletteMaske } from './FertigePaletteMaske'
import { stationsProfil, uhrzeit, type ArbeitDaten } from './daten'

type SchrittId = 'palox' | 'faule' | 'paletten' | 'kisten' | 'ausgang' | 'charge' | 'pruefen'

/**
 * Der geführte Abschluss (AB-02, AB-04, AB-05): Was man vergessen kann, wird
 * hier der Reihe nach gefragt — zuerst die Palox-Ablesung (beim Fax: das
 * Faule wiegen), dann die Fragen, dann die Zusammenfassung. Der Knopf „Ja,
 * fertig" kommt erst, wenn nichts mehr fehlt; was fehlt, steht als Satz dabei.
 *
 * 0060: Zu klein / zu gross wird nicht mehr gefragt (der Anteil kommt aus der
 * Sortier-CSV). Neu: die fertige Palette, wo das Kistensystem rechenbar ist;
 * beim Fax die Palettenzahl als Gesamtzahl und die Tage seit dem Waschen;
 * beim Waschen ist der Palox freiwillig.
 */
export function Abschluss({ d, neuLaden, zurueck, fertig }: {
  d: ArbeitDaten; neuLaden: () => Promise<void>; zurueck: () => void; fertig: () => void
}) {
  const { t, gebietsschema } = useSprache()
  const p = stationsProfil(d.auftrag)
  const [pos, setPos] = useState(0)
  const [eineCharge, setEineCharge] = useState<boolean | null>(null)
  const [gleicheSorte, setGleicheSorte] = useState<boolean | null>(null)
  const [paletten, setPaletten] = useState(String(d.auftrag.paletten_gesamt ?? ''))
  const [tage, setTage] = useState(String(d.auftrag.tage_seit_waschen ?? ''))
  const [sicher, setSicher] = useState(false)
  const [abbruch, setAbbruch] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  const kistenGezaehlt = d.gebinde.reduce((s, g) => s + g.anzahl, 0)
  const palettenOk = Number(paletten) > 0
  const schritte = useMemo<SchrittId[]>(() => [
    ...(p.hatPalox ? ['palox' as const] : []),
    ...(p.hatFaule ? ['faule' as const] : []),
    ...(p.hatFaxPaletten ? ['paletten' as const] : []),
    ...(p.kistenPflicht ? ['kisten' as const] : []),
    ...(p.hatAusgang ? ['ausgang' as const] : []),
    'charge',
    'pruefen',
  ], [p.hatPalox, p.hatFaule, p.hatFaxPaletten, p.kistenPflicht, p.hatAusgang])
  const aktuell = schritte[Math.min(pos, schritte.length - 1)]
  const n = pos + 1, von = schritte.length
  const weiter = () => setPos(x => Math.min(x + 1, schritte.length - 1))
  const zurueckSchritt = () => (pos === 0 ? zurueck() : setPos(x => x - 1))

  // Was noch fehlt — als Sätze, nicht als gesperrter Knopf ohne Grund.
  const fehlt: string[] = []
  if (p.paloxPflicht && d.ablesungen.length === 0) fehlt.push(t('paloxVorAbschluss'))
  if (p.hatFaule && d.ablesungen.length === 0) fehlt.push(t('faulesFehlt'))
  if (p.hatFaxPaletten && !palettenOk) fehlt.push(t('palettenGesamt'))
  if (p.kistenPflicht && kistenGezaehlt === 0) fehlt.push(t('kistenFehlen'))
  if (eineCharge === null || (eineCharge === false && gleicheSorte === null)) fehlt.push(t('eineChargeFrage'))
  const fertigMoeglich = fehlt.length === 0

  async function palettenSpeichern() {
    if (!palettenOk || laeuft) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from('auftrag')
      .update({ paletten_gesamt: Number(paletten), tage_seit_waschen: tage === '' ? null : Number(tage) })
      .eq('id', d.auftrag.id)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    await neuLaden(); weiter()
  }

  async function abschliessen() {
    setLaeuft(true); setFehler(null)
    const angaben: { schluessel: string; wert: string }[] = []
    if (eineCharge !== null) angaben.push({ schluessel: 'eine_charge', wert: String(eineCharge) })
    if (eineCharge === false && gleicheSorte !== null) angaben.push({ schluessel: 'gleiche_sorte', wert: String(gleicheSorte) })
    if (angaben.length) {
      const { error } = await supabase.from('auftrag_angabe')
        .insert(angaben.map(a => ({ auftrag_id: d.auftrag.id, ...a })))
      if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    }
    // Das Ende setzt der Server (Auslöser in 0039).
    const { error } = await supabase.from('auftrag').update({ status: 'abgeschlossen' }).eq('id', d.auftrag.id)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    await neuLaden(); fertig()
  }

  async function abbrechen() {
    setLaeuft(true)
    const { error } = await supabase.rpc('auftrag_abbrechen', { p_auftrag_id: d.auftrag.id, p_grund: null })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    await neuLaden(); fertig()
  }

  if (aktuell === 'palox') {
    const letzte = d.ablesungen[d.ablesungen.length - 1]
    return (
      <Schritt nummer={n} von={von} frage={p.paloxPflicht ? t('paloxJetzt') : t('paloxFreiwillig')}
               warum={letzte ? `${t('zuletztAbgelesen')} ${uhrzeit(letzte.ts, gebietsschema)}. ${t('paloxEndeWarum')}` : p.paloxPflicht ? t('paloxEndeWarum') : t('paloxWaschenWarum')}
               zurueck={zurueckSchritt}>
        <PaloxMaske d={d} gesperrt={false} unveraendertErlaubt={d.ablesungen.length > 0}
                    gespeichert={async () => { await neuLaden(); weiter() }} />
        {!p.paloxPflicht && (
          <button id="palox-ohne" style={{ width: '100%', marginTop: '.6rem', minHeight: 48 }} onClick={weiter}>{t('ohneAblesungWeiter')}</button>
        )}
      </Schritt>
    )
  }

  if (aktuell === 'faule') {
    return (
      <Schritt nummer={n} von={von} frage={t('faulesWiegen')} zurueck={zurueckSchritt}
               weiter={d.ablesungen.length > 0 ? weiter : undefined}>
        <FauleMaske d={d} gesperrt={false} melden={() => undefined} neuLaden={neuLaden} />
      </Schritt>
    )
  }

  if (aktuell === 'paletten') {
    // Fax (0060): die Palettenzahl als Gesamtzahl, dazu freiwillig die Tage seit dem Waschen
    return (
      <Schritt nummer={n} von={von} frage={t('palettenGesamt')} warum={t('palettenGesamtWarum')} zurueck={zurueckSchritt}
               weiter={() => void palettenSpeichern()} weiterMoeglich={palettenOk && !laeuft}>
        <div className="karte">
          <div className="feld">
            <label htmlFor="ab-paletten">{t('palettenGesamt')}</label>
            <input id="ab-paletten" className="gross" type="number" inputMode="numeric" min={0} value={paletten}
                   onChange={e => setPaletten(e.target.value)} autoFocus />
          </div>
          <div className="feld">
            <label htmlFor="ab-tage">{t('tageSeitWaschen')} ({t('freiwillig')})</label>
            <input id="ab-tage" type="number" inputMode="numeric" min={0} value={tage} onChange={e => setTage(e.target.value)} />
            <p className="leise" style={{ margin: '.35rem 0 0' }}>{t('tageSeitWaschenErkl')}</p>
          </div>
          {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        </div>
      </Schritt>
    )
  }

  if (aktuell === 'kisten') {
    // Die Menge kommt aus den gezählten Kisten — hier wird nur nachgesehen,
    // ob sie da sind, und mit welchem Sortierdatum.
    const daten = [...new Set(d.gebinde.filter(g => g.anzahl > 0).map(g => g.datum_fehlt ? t('keinDatumKiste') : (g.sortierdatum ?? '—')))]
    return (
      <Schritt nummer={n} von={von} frage={t('kaliberKisten')} warum={t('sortierdatumErkl')} zurueck={zurueckSchritt}
               weiter={kistenGezaehlt > 0 ? weiter : undefined}>
        {kistenGezaehlt > 0
          ? <Hinweis art="gut">{kistenGezaehlt} {t('kistenGezaehltGut')}{daten.length > 0 && <> · {t('sortierdatumKiste')}: {daten.join(', ')}</>}</Hinweis>
          : <Hinweis art="warnung">{t('kistenFehlen')}</Hinweis>}
      </Schritt>
    )
  }

  if (aktuell === 'ausgang') {
    // Fertige Palette (0060): gefragt, wo das Kistensystem rechenbar ist; freiwillig.
    return (
      <Schritt nummer={n} von={von} frage={t('fertigePaletteSchritt')} warum={t('fertigePaletteWarum')} zurueck={zurueckSchritt}
               weiter={weiter} weiterText={d.nAusgang > 0 ? t('weiter') : t('keineGewogen')}>
        {d.nAusgang > 0 && <Hinweis art="gut">{d.nAusgang} {t('palettenGewogen')}</Hinweis>}
        <FertigePaletteMaske d={d} gesperrt={false} melden={() => undefined} neuLaden={neuLaden} />
      </Schritt>
    )
  }

  if (aktuell === 'charge') {
    const ok = eineCharge === true || (eineCharge === false && gleicheSorte !== null)
    return (
      <Schritt nummer={n} von={von} frage={t('eineChargeFrage')} warum={t('eineChargeWarum')} zurueck={zurueckSchritt}
               weiter={ok ? weiter : undefined}>
        <div className="wahl">
          <Wahl id="charge-ja" name={t('eineChargeJa')} gewaehlt={eineCharge === true}
                onClick={() => { setEineCharge(true); setGleicheSorte(null) }} />
          <Wahl id="charge-nein" name={t('eineChargeNein')} gewaehlt={eineCharge === false} onClick={() => setEineCharge(false)} />
        </div>
        {eineCharge === false && (
          <>
            <h2 className="frage" style={{ fontSize: '1.1rem' }}>{t('gleicheSorteFrage')}</h2>
            <div className="wahl">
              <Wahl id="sorte-ja" name={t('gleicheSorteJa')} gewaehlt={gleicheSorte === true} onClick={() => setGleicheSorte(true)} />
              <Wahl id="sorte-nein" name={t('gleicheSorteNein')} gewaehlt={gleicheSorte === false} onClick={() => setGleicheSorte(false)} />
            </div>
          </>
        )}
      </Schritt>
    )
  }

  // pruefen
  return (
    <Schritt nummer={n} von={von} frage={t('allesRichtig')} zurueck={zurueckSchritt}>
      <div className="karte">
        <dl className="zusammenfassung">
          {p.hatPaletten && <><dt>{t('paletten')}</dt><dd>{d.paletten.length}</dd></>}
          {p.hatFaxPaletten && <><dt>{t('palettenGesamt')}</dt><dd>{paletten || '—'}{tage !== '' && <span className="leise"> · {tage} {t('tageSeitWaschen')}</span>}</dd></>}
          {p.hatKisten && kistenGezaehlt > 0 && <><dt>{t('kaliberKisten')}</dt><dd>{kistenGezaehlt}</dd></>}
          <dt>{t('faule')}</dt><dd>{d.ablesungen.reduce((s, z) => s + z.kg, 0)} kg · {d.ablesungen.length} {p.istFax ? t('kisten') : t('ablesungen')}</dd>
          {p.hatAusgang && <><dt>{t('fertigePalette')}</dt><dd>{d.nAusgang > 0 ? d.nAusgang : t('keineGewogen')}</dd></>}
          <dt>{t('eineChargeFrage')}</dt>
          <dd>{eineCharge === null ? '—' : eineCharge ? t('ja') : `${t('nein')}${gleicheSorte === null ? '' : gleicheSorte ? ` · ${t('gleicheSorteJa')}` : ` · ${t('gleicheSorteNein')}`}`}</dd>
        </dl>
      </div>
      {d.auftrag.station === 'sortieren' && <Hinweis art="info">{t('sortierdatumSchreiben')}</Hinweis>}
      {fehlt.length > 0 && (
        <Hinweis art="warnung">
          <strong>{t('fehltNoch')}:</strong>
          <ul style={{ margin: '.3rem 0 0', paddingLeft: '1.2rem' }}>{fehlt.map(f => <li key={f}>{f}</li>)}</ul>
        </Hinweis>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {!sicher ? (
        <button id="arbeit-fertig" className="haupt gross" style={{ width: '100%' }} onClick={() => setSicher(true)}
                disabled={!fertigMoeglich || laeuft}>{t('arbeitFertig')}</button>
      ) : (
        <div className="reihe">
          <button id="ja-fertig" className="haupt" style={{ flex: 1, minHeight: 60 }} onClick={() => void abschliessen()}
                  disabled={laeuft}>{t('jaFertig')}</button>
          <button onClick={() => setSicher(false)}>{t('abbrechen')}</button>
        </div>
      )}
      <div style={{ marginTop: '2.5rem', borderTop: '1px solid var(--rand)', paddingTop: '1rem' }}>
        {!abbruch ? (
          <button className="gefahr" style={{ width: '100%' }} onClick={() => setAbbruch(true)}>{t('arbeitAbbrechen')}</button>
        ) : (
          <>
            <p className="leise">{t('wirklichAbbrechen')}</p>
            <div className="reihe">
              <button className="gefahr" style={{ flex: 1, minHeight: 54 }} onClick={() => void abbrechen()} disabled={laeuft}>{t('jaAbbrechen')}</button>
              <button onClick={() => setAbbruch(false)}>{t('abbrechen')}</button>
            </div>
          </>
        )}
      </div>
    </Schritt>
  )
}
