import { useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { Schritt, Wahl } from '../components/Schritte'
import { PaloxMaske } from './PaloxMaske'
import { FauleMaske } from './FauleMaske'
import { AusschussMaske } from './AusschussMaske'
import { FertigePaletteMaske } from './FertigePaletteMaske'
import { fertigeSoll, stationsProfil, uhrzeit, type ArbeitDaten } from './daten'

type SchrittId = 'palox' | 'faule' | 'wiegen' | 'ausschuss' | 'paletten' | 'wasch_paletten' | 'ausgang' | 'charge' | 'pruefen'

/**
 * Der geführte Abschluss (AB-02, AB-04, AB-05): Was man vergessen kann, wird
 * hier der Reihe nach gefragt — zuerst die Palox-Ablesung (beim Fax: das
 * Faule wiegen), dann die Fragen, dann die Zusammenfassung. Der Knopf „Ja,
 * fertig" kommt erst, wenn nichts mehr fehlt; was fehlt, steht als Satz dabei.
 *
 * Runde H (0061), je Station:
 *  Waschen + Sortieren  Erinnerung, wenn weniger als drei Eingangspaletten
 *                       gewogen sind (abschliessen geht trotzdem); dann zu
 *                       klein / zu gross Palette für Palette (Pflicht — oder
 *                       „nichts"); fertige Paletten, mindestens drei erinnert
 *  Waschen              die gezählten Kaliber-Paletten nachsehen (Pflicht);
 *                       fertige Paletten: drei verlangt, oder so viele, wie die
 *                       Arbeit hergibt
 *  Fax                  Palettenzahl als Gesamtzahl, Tage seit dem Waschen
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
  const waschKisten = d.paletten.reduce((s, x) => s + (x.kisten ?? 0), 0)
  const gewogen = d.paletten.filter(x => x.wiegung_id != null).length
  const palettenOk = Number(paletten) > 0
  const soll = fertigeSoll(d)
  const wiegenErinnern = p.wiegenSoll > 0 && gewogen < p.wiegenSoll
  const schritte = useMemo<SchrittId[]>(() => [
    ...(p.hatPalox ? ['palox' as const] : []),
    ...(p.hatFaule ? ['faule' as const] : []),
    ...(wiegenErinnern ? ['wiegen' as const] : []),
    ...(p.hatAusschuss ? ['ausschuss' as const] : []),
    ...(p.hatFaxPaletten ? ['paletten' as const] : []),
    ...(p.hatWaschPaletten ? ['wasch_paletten' as const] : []),
    ...(p.hatAusgang ? ['ausgang' as const] : []),
    'charge',
    'pruefen',
  ], [p.hatPalox, p.hatFaule, wiegenErinnern, p.hatAusschuss, p.hatFaxPaletten, p.hatWaschPaletten, p.hatAusgang])
  const aktuell = schritte[Math.min(pos, schritte.length - 1)]
  const n = pos + 1, von = schritte.length
  const weiter = () => setPos(x => Math.min(x + 1, schritte.length - 1))
  const zurueckSchritt = () => (pos === 0 ? zurueck() : setPos(x => x - 1))
  const ersetzen = (text: string, werte: Record<string, number>) =>
    Object.entries(werte).reduce((s, [k, v]) => s.replace(`{${k}}`, String(v)), text)

  // Was noch fehlt — als Sätze, nicht als gesperrter Knopf ohne Grund.
  const fehlt: string[] = []
  if (p.paloxPflicht && d.ablesungen.length === 0) fehlt.push(t('paloxVorAbschluss'))
  if (p.hatFaule && d.ablesungen.length === 0) fehlt.push(t('faulesFehlt'))
  if (p.hatFaxPaletten && !palettenOk) fehlt.push(t('palettenGesamt'))
  if (p.hatWaschPaletten && waschKisten === 0) fehlt.push(t('palettenFehlen'))
  if (p.hatAusschuss && d.ausschuss.length === 0) fehlt.push(t('ausschussFehlt'))
  if (p.ausgangPflicht && d.nAusgang < soll) fehlt.push(ersetzen(t('fertigeFehlen'), { n: d.nAusgang, soll }))
  if (eineCharge === null || (eineCharge === false && gleicheSorte === null)) fehlt.push(t('eineChargeFrage'))
  const fertigMoeglich = fehlt.length === 0
  // Erinnerungen: nicht Pflicht, aber gesagt (Runde H).
  const erinnert: string[] = []
  if (wiegenErinnern) erinnert.push(`${t('dreiWiegen')} ${ersetzen(t('nurGewogen'), { n: gewogen, soll: p.wiegenSoll })}`)
  if (p.hatAusgang && !p.ausgangPflicht && d.nAusgang < soll) erinnert.push(`${t('dreiFertige')} ${ersetzen(t('nurGewogen'), { n: d.nAusgang, soll })}`)

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

  if (aktuell === 'wiegen') {
    // Waschen + Sortieren (Runde H): weniger als drei Eingangspaletten gewogen —
    // gesagt, nicht erzwungen. Wiegen geht nur am Zähler, bevor die Palette in
    // die Maschine kommt; hier bleibt nur die Erinnerung.
    return (
      <Schritt nummer={n} von={von} frage={t('dreiWiegen')} warum={t('dreiWiegenWarum')} zurueck={zurueckSchritt}
               weiter={weiter} weiterText={t('trotzdemWeiter')}>
        <Hinweis art="warnung">{ersetzen(t('nurGewogen'), { n: gewogen, soll: p.wiegenSoll })}</Hinweis>
      </Schritt>
    )
  }

  if (aktuell === 'ausschuss') {
    return (
      <Schritt nummer={n} von={von} frage={t('ausschussWiegenSchritt')} zurueck={zurueckSchritt}
               weiter={d.ausschuss.length > 0 ? weiter : undefined}>
        <AusschussMaske d={d} gesperrt={false} melden={() => undefined} neuLaden={neuLaden} />
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

  if (aktuell === 'wasch_paletten') {
    // Waschen (0061): die Menge sind die gezählten Kaliber-Paletten — hier wird
    // nur nachgesehen, ob sie da sind, mit welchen Sortierdaten.
    const daten = [...new Set(d.paletten.filter(x => x.kisten != null).map(x => x.sortierdatum ?? t('keinSortierdatum')))]
    return (
      <Schritt nummer={n} von={von} frage={t('paletten')} warum={t('waschPalettenWarum')} zurueck={zurueckSchritt}
               weiter={waschKisten > 0 ? weiter : undefined}>
        {waschKisten > 0
          ? <Hinweis art="gut">{ersetzen(t('palettenGezaehltGut'), { n: d.paletten.length, kisten: waschKisten })}{daten.length > 0 && <> · {t('sortierdatumZettel')}: {daten.join(', ')}</>}</Hinweis>
          : <Hinweis art="warnung">{t('palettenFehlen')}</Hinweis>}
      </Schritt>
    )
  }

  if (aktuell === 'ausgang') {
    // Fertige Paletten (0060/0061): beim Waschen verlangt (drei, oder so viele,
    // wie die Arbeit hergibt); beim Waschen + Sortieren erinnert.
    const genug = d.nAusgang >= soll
    return (
      <Schritt nummer={n} von={von} frage={t('fertigePaletteSchritt')} warum={t('fertigePaletteWarum')} zurueck={zurueckSchritt}
               weiter={p.ausgangPflicht && !genug ? undefined : weiter}
               weiterText={genug ? t('weiter') : d.nAusgang > 0 ? t('trotzdemWeiter') : t('keineGewogen')}>
        {genug
          ? <Hinweis art="gut">{d.nAusgang} {t('palettenGewogen')}</Hinweis>
          : <Hinweis art={p.ausgangPflicht ? 'warnung' : 'info'}>{t('dreiFertige')} {ersetzen(t('nurGewogen'), { n: d.nAusgang, soll })}</Hinweis>}
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
  const ausschussSumme = (a: 'zu_klein' | 'zu_gross') => d.ausschuss.filter(z => z.art === a).reduce((s, z) => s + z.kg, 0)
  return (
    <Schritt nummer={n} von={von} frage={t('allesRichtig')} zurueck={zurueckSchritt}>
      <div className="karte">
        <dl className="zusammenfassung">
          {p.hatPaletten && <><dt>{t('paletten')}</dt><dd>{d.paletten.length}{gewogen > 0 && <span className="leise"> · {gewogen} {t('gewogen')}</span>}</dd></>}
          {p.hatWaschPaletten && <><dt>{t('paletten')}</dt><dd>{d.paletten.length} · {waschKisten} {t('kisten')}</dd></>}
          {p.hatFaxPaletten && <><dt>{t('palettenGesamt')}</dt><dd>{paletten || '—'}{tage !== '' && <span className="leise"> · {tage} {t('tageSeitWaschen')}</span>}</dd></>}
          {p.hatKisten && kistenGezaehlt > 0 && <><dt>{t('kaliberKisten')}</dt><dd>{kistenGezaehlt}</dd></>}
          <dt>{t('faule')}</dt><dd>{d.ablesungen.reduce((s, z) => s + z.kg, 0)} kg · {d.ablesungen.length} {p.istFax ? t('kisten') : t('ablesungen')}</dd>
          {p.hatAusschuss && <><dt>{t('ausschussWiegenSchritt')}</dt><dd>{d.ausschuss.length > 0 ? `${t('zuKlein')} ${ausschussSumme('zu_klein')} kg · ${t('zuGross')} ${ausschussSumme('zu_gross')} kg` : '—'}</dd></>}
          {p.hatAusgang && <><dt>{t('fertigePalette')}</dt><dd>{d.nAusgang > 0 ? d.nAusgang : t('keineGewogen')}</dd></>}
          <dt>{t('eineChargeFrage')}</dt>
          <dd>{eineCharge === null ? '—' : eineCharge ? t('ja') : `${t('nein')}${gleicheSorte === null ? '' : gleicheSorte ? ` · ${t('gleicheSorteJa')}` : ` · ${t('gleicheSorteNein')}`}`}</dd>
        </dl>
      </div>
      {d.auftrag.station === 'sortieren' && <Hinweis art="info">{t('sortierdatumSchreiben')}</Hinweis>}
      {erinnert.map(e => <Hinweis key={e} art="info">{e}</Hinweis>)}
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
