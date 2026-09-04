import { useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText } from '../lib/db'
import { Hinweis } from '../components/Bausteine'
import { Schritt, Wahl } from '../components/Schritte'
import { PaloxMaske } from './PaloxMaske'
import { stationsProfil, uhrzeit, type ArbeitDaten } from './daten'

type SchrittId = 'palox' | 'ausschuss' | 'charge' | 'waschen' | 'pruefen'

/**
 * Der geführte Abschluss (AB-02, AB-04, AB-05): Was man vergessen kann, wird
 * hier der Reihe nach gefragt — zuerst die Palox-Ablesung, dann die Fragen,
 * dann die Zusammenfassung. Der Knopf „Ja, fertig" kommt erst, wenn nichts
 * mehr fehlt; was fehlt, steht als Satz dabei.
 */
export function Abschluss({ d, neuLaden, zurueck, fertig }: {
  d: ArbeitDaten; neuLaden: () => Promise<void>; zurueck: () => void; fertig: () => void
}) {
  const { t, gebietsschema } = useSprache()
  const p = stationsProfil(d.auftrag)
  const [pos, setPos] = useState(0)
  const [ausschussLeer, setAusschussLeer] = useState<boolean | null>(
    d.angaben['ausschuss_leer'] === undefined ? null : d.angaben['ausschuss_leer'] === 'true')
  const [ausschussVon, setAusschussVon] = useState<boolean | null>(null)
  const [eineCharge, setEineCharge] = useState<boolean | null>(null)
  const [gleicheSorte, setGleicheSorte] = useState<boolean | null>(null)
  const [durchsatz, setDurchsatz] = useState(d.auftrag.durchsatz_kg?.toString() ?? '')
  const [sortierdatum, setSortierdatum] = useState('')
  const [sicher, setSicher] = useState(false)
  const [abbruch, setAbbruch] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  const kistenGezaehlt = d.gebinde.reduce((s, g) => s + g.anzahl, 0)
  const schritte = useMemo<SchrittId[]>(() => [
    'palox',
    ...(p.hatAusschuss ? ['ausschuss' as const] : []),
    'charge',
    ...(d.auftrag.station === 'waschen' ? ['waschen' as const] : []),
    'pruefen',
  ], [p.hatAusschuss, d.auftrag.station])
  const aktuell = schritte[Math.min(pos, schritte.length - 1)]
  const n = pos + 1, von = schritte.length
  const weiter = () => setPos(x => Math.min(x + 1, schritte.length - 1))
  const zurueckSchritt = () => (pos === 0 ? zurueck() : setPos(x => x - 1))

  // Was noch fehlt — als Sätze, nicht als gesperrter Knopf ohne Grund.
  const fehlt: string[] = []
  if (d.ablesungen.length === 0) fehlt.push(t('paloxVorAbschluss'))
  if (p.hatAusschuss && ausschussLeer === null) fehlt.push(t('ausschussLeerFrage'))
  if (p.hatAusschuss && ausschussVon === null) fehlt.push(t('ausschussVonAuftragFrage'))
  if (eineCharge === null || (eineCharge === false && gleicheSorte === null)) fehlt.push(t('eineChargeFrage'))
  const fertigMoeglich = fehlt.length === 0

  async function abschliessen() {
    setLaeuft(true); setFehler(null)
    const angaben: { schluessel: string; wert: string }[] = []
    if (p.hatAusschuss && ausschussLeer !== null && d.angaben['ausschuss_leer'] === undefined) {
      angaben.push({ schluessel: 'ausschuss_leer', wert: String(ausschussLeer) })
    }
    if (p.hatAusschuss && ausschussVon !== null) angaben.push({ schluessel: 'ausschuss_von_auftrag', wert: String(ausschussVon) })
    if (eineCharge !== null) angaben.push({ schluessel: 'eine_charge', wert: String(eineCharge) })
    if (eineCharge === false && gleicheSorte !== null) angaben.push({ schluessel: 'gleiche_sorte', wert: String(gleicheSorte) })
    if (d.auftrag.station === 'waschen' && sortierdatum !== '') angaben.push({ schluessel: 'sortierdatum', wert: sortierdatum })
    if (angaben.length) {
      const { error } = await supabase.from('auftrag_angabe')
        .insert(angaben.map(a => ({ auftrag_id: d.auftrag.id, ...a })))
      if (error) { setLaeuft(false); setFehler(fehlerText(error)); return }
    }
    // Das Ende setzt der Server (Auslöser in 0039).
    const { error } = await supabase.from('auftrag').update({
      durchsatz_kg: durchsatz === '' ? null : Number(durchsatz), status: 'abgeschlossen',
    }).eq('id', d.auftrag.id)
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
      <Schritt nummer={n} von={von} frage={t('paloxJetzt')}
               warum={letzte ? `${t('zuletztAbgelesen')} ${uhrzeit(letzte.ts, gebietsschema)}. ${t('paloxEndeWarum')}` : t('paloxEndeWarum')}
               zurueck={zurueckSchritt}>
        <PaloxMaske d={d} gesperrt={false} unveraendertErlaubt={d.ablesungen.length > 0}
                    gespeichert={async () => { await neuLaden(); weiter() }} />
      </Schritt>
    )
  }

  if (aktuell === 'ausschuss') {
    const klein = d.ausschuss.filter(z => z.art === 'zu_klein').reduce((s, z) => s + z.kg, 0)
    const gross = d.ausschuss.filter(z => z.art === 'zu_gross').reduce((s, z) => s + z.kg, 0)
    const leerFehlt = d.angaben['ausschuss_leer'] === undefined
    return (
      <Schritt nummer={n} von={von} frage={t('ausschussVonAuftragFrage')}
               warum={`${t('zuKlein')} ${klein} kg · ${t('zuGross')} ${gross} kg`} zurueck={zurueckSchritt}
               weiter={ausschussVon !== null && (!leerFehlt || ausschussLeer !== null) ? weiter : undefined}>
        <div className="wahl">
          <Wahl id="ausschuss-von-ja" name={t('ja')} gewaehlt={ausschussVon === true} onClick={() => setAusschussVon(true)} />
          <Wahl id="ausschuss-von-nein" name={t('nein')} gewaehlt={ausschussVon === false} onClick={() => setAusschussVon(false)} />
        </div>
        {leerFehlt && (
          <>
            <h2 className="frage" style={{ fontSize: '1.1rem' }}>{t('ausschussLeerFrage')}</h2>
            <p className="leise frage-warum">{t('ausschussLeerNachgefragt')}</p>
            <div className="wahl">
              <Wahl id="ausschuss-leer-ja" name={t('ja')} gewaehlt={ausschussLeer === true} onClick={() => setAusschussLeer(true)} />
              <Wahl id="ausschuss-leer-nein" name={t('nein')} gewaehlt={ausschussLeer === false} onClick={() => setAusschussLeer(false)} />
            </div>
          </>
        )}
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

  if (aktuell === 'waschen') {
    return (
      <Schritt nummer={n} von={von} frage={t('mengeVerarbeitet')} warum={t('mengeWarum')} zurueck={zurueckSchritt} weiter={weiter}>
        {kistenGezaehlt > 0
          ? <Hinweis art="gut">{kistenGezaehlt} {t('kisten')} — {t('mengeAusKisten')}</Hinweis>
          : (
            <div className="feld">
              <label htmlFor="ds">{t('kilo')}</label>
              <input id="ds" className="gross" type="number" inputMode="decimal" step="1" min={0} value={durchsatz}
                     onChange={e => setDurchsatz(e.target.value)} />
            </div>
          )}
        <div className="feld">
          <label htmlFor="sd">{t('sortierdatumKiste')} ({t('freiwillig')})</label>
          <input id="sd" type="date" value={sortierdatum} onChange={e => setSortierdatum(e.target.value)} />
        </div>
      </Schritt>
    )
  }

  // pruefen
  const klein = d.ausschuss.filter(z => z.art === 'zu_klein').reduce((s, z) => s + z.kg, 0)
  const gross = d.ausschuss.filter(z => z.art === 'zu_gross').reduce((s, z) => s + z.kg, 0)
  return (
    <Schritt nummer={n} von={von} frage={t('allesRichtig')} zurueck={zurueckSchritt}>
      <div className="karte">
        <dl className="zusammenfassung">
          {p.hatPaletten && <><dt>{t('paletten')}</dt><dd>{d.paletten.length}</dd></>}
          {p.hatKisten && kistenGezaehlt > 0 && <><dt>{t('kaliberKisten')}</dt><dd>{kistenGezaehlt}</dd></>}
          <dt>{t('faule')}</dt><dd>{d.ablesungen.reduce((s, z) => s + z.kg, 0)} kg · {d.ablesungen.length} {t('ablesungen')}</dd>
          {p.hatAusschuss && <><dt>{t('kleinGross')}</dt><dd>{klein} kg / {gross} kg</dd></>}
          {p.hatAusgang && d.nAusgang > 0 && <><dt>{t('fertigePalette')}</dt><dd>{d.nAusgang}</dd></>}
          <dt>{t('eineChargeFrage')}</dt>
          <dd>{eineCharge === null ? '—' : eineCharge ? t('ja') : `${t('nein')}${gleicheSorte === null ? '' : gleicheSorte ? ` · ${t('gleicheSorteJa')}` : ` · ${t('gleicheSorteNein')}`}`}</dd>
        </dl>
      </div>
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
