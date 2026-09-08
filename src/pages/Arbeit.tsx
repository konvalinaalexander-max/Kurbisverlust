import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, fehlerText } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { fuehrungSetzen, istVorarbeiter } from '../lib/rolle'
import { Hinweis, Lade, Marke } from '../components/Bausteine'
import { Bestaetigt } from '../components/Schritte'
import { arbeitLaden, stationsProfil, uhrzeit, type ArbeitDaten } from '../arbeit/daten'
import { Zaehler } from '../arbeit/Zaehler'
import { PaloxMaske } from '../arbeit/PaloxMaske'
import { FauleMaske } from '../arbeit/FauleMaske'
import { WiegenMaske } from '../arbeit/WiegenMaske'
import { FertigePaletteMaske } from '../arbeit/FertigePaletteMaske'
import { Abschluss } from '../arbeit/Abschluss'

type Ansicht = 'liste' | 'zaehler' | 'palox' | 'faule' | 'wiegen' | 'ausgang' | 'abschluss'

/**
 * Eine Arbeit, aus zwei Blickwinkeln:
 *  · der Zähler sieht den Zähler — sonst nichts;
 *  · der Vorarbeiter sieht die Checkliste, aus der jede Maske erreichbar ist,
 *    und weiss jederzeit, was erledigt ist und was noch fehlt.
 * Beide können wechseln; die Rolle hängt an der Arbeit (docs/UI-KONZEPT.md).
 * Welche Punkte die Checkliste hat, sagt das Stationsprofil — beim Fax gibt
 * es keinen Palox, dafür „Faules wiegen" und die Palettenzahl (0051, 0060).
 * Zu klein / zu gross gibt es seit 0060 nirgends mehr.
 */
export default function Arbeit() {
  const { id } = useParams()
  const auftragId = Number(id)
  const [suche] = useSearchParams()
  const navigate = useNavigate()
  const { session } = useAuth()
  const { t, gebietsschema } = useSprache()

  const [d, setD] = useState<ArbeitDaten | null>(null)
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  const [fuehrt, setFuehrt] = useState<boolean | null>(null)
  const [ansicht, setAnsicht] = useState<Ansicht | null>(null)
  const [meldung, setMeldung] = useState<string | null>(null)
  // 0060: das Gewicht vom Zettel wandert vom Zähler in die Wägung
  const [zettelBrutto, setZettelBrutto] = useState('')

  const laden = useCallback(async () => {
    try {
      const daten = await arbeitLaden(auftragId)
      setD(daten); setFehler(null)
      if (daten && fuehrt === null) {
        const f = istVorarbeiter(auftragId, daten.auftrag.eroeffnet_von, session?.user.id)
        setFuehrt(f)
        // Frisch eröffnet: als erstes der Palox (AB-02) — wo er Pflicht ist.
        const p = stationsProfil(daten.auftrag)
        setAnsicht(f ? (suche.get('neu') === '1' && p.paloxPflicht && daten.ablesungen.length === 0 ? 'palox' : 'liste') : 'zaehler')
      }
    } catch (f) { setFehler(fehlerText(f)) } finally { setLaedt(false) }
  }, [auftragId, session?.user.id, fuehrt, suche])
  useEffect(() => { void laden() }, [laden])

  function melden(text: string) {
    setMeldung(text)
    window.setTimeout(() => setMeldung(null), 1400)
  }

  if (laedt) return <Lade />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!d || fuehrt === null || ansicht === null) return <Hinweis art="warnung">{t('keineArbeit')}</Hinweis>

  const a = d.auftrag
  const taet = taetigkeitVon(a.weg, a.station, a.ist_fax)
  const p = stationsProfil(a)
  const gesperrt = a.status === 'abgeschlossen'
  const binDabei = d.teilnehmer.some(x => x.profil_id === session?.user.id)
  const heim = fuehrt ? 'liste' : 'zaehler'

  async function mitmachen() {
    const { error } = await supabase.from('auftrag_teilnehmer').insert({ auftrag_id: auftragId })
    if (error) setFehler(fehlerText(error)); else await laden()
  }
  function rolleWechseln(neu: boolean) {
    fuehrungSetzen(auftragId, neu); setFuehrt(neu); setAnsicht(neu ? 'liste' : 'zaehler')
  }
  const kopf = (
    <div className="karte" style={{ marginTop: '1rem' }}>
      <div className="reihe">
        <h1 style={{ margin: 0, fontSize: '1.25rem' }}>{taet?.zeichen} {taet ? t(taet.text) : ''}</h1>
        <Marke art={gesperrt ? 'fertig' : 'offen'}>{gesperrt ? t('fertig') : t('laeuft')}</Marke>
        {fuehrt && !gesperrt && <Marke>{t('vorarbeiter')}</Marke>}
      </div>
      <p style={{ margin: '.3rem 0 0', fontSize: '1rem' }}>{chargeText(d.charge)}</p>
      <p className="leise" style={{ margin: '.2rem 0 0' }}>
        {t('seit')} {uhrzeit(a.start_ts, gebietsschema)} · {t('dabei')}: {d.teilnehmer.length ? d.teilnehmer.map(x => x.name).join(', ') : t('niemand')}
      </p>
      {!binDabei && !gesperrt && (
        <button className="haupt" style={{ width: '100%', marginTop: '.75rem', minHeight: 54 }} onClick={() => void mitmachen()}>
          {t('mitmachen')}
        </button>
      )}
    </div>
  )

  const kistenGezaehlt = d.gebinde.reduce((s, g) => s + g.anzahl, 0)
  const faulSumme = d.ablesungen.reduce((s, z) => s + z.kg, 0)

  // Fertige Arbeit: nur noch lesen.
  if (gesperrt) {
    return (
      <>
        {kopf}
        <div className="karte">
          <dl className="zusammenfassung">
            <dt>{t('abgeschlossenAm')}</dt>
            <dd>{a.ende_ts ? new Date(a.ende_ts).toLocaleString(gebietsschema, { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'}</dd>
            {p.hatPaletten && <><dt>{t('paletten')}</dt><dd>{d.paletten.length}</dd></>}
            {p.hatFaxPaletten && <><dt>{t('palettenGesamt')}</dt><dd>{a.paletten_gesamt ?? '—'}</dd></>}
            {p.hatKisten && kistenGezaehlt > 0 && <><dt>{t('kaliberKisten')}</dt><dd>{kistenGezaehlt}</dd></>}
            <dt>{t('faule')}</dt><dd>{faulSumme} kg</dd>
          </dl>
        </div>
        <button style={{ width: '100%' }} onClick={() => navigate('/')}>‹ {t('uebersicht')}</button>
      </>
    )
  }

  // Eine Maske: Kopfzeile mit Zurück, dann die Maske.
  const maske = (titel: string, inhalt: React.ReactNode, zurueckZu: Ansicht = heim) => (
    <>
      <div className="schritt-kopf">
        <button type="button" className="zurueck" onClick={() => setAnsicht(zurueckZu)}>‹ {t('zurueck')}</button>
        <span className="stand">{taet?.zeichen} {chargeText(d.charge)}</span>
      </div>
      <h1 className="frage">{titel}</h1>
      {inhalt}
    </>
  )

  if (ansicht === 'palox') {
    return (
      <>
        {maske(t('paloxBeginn'), (
          <>
            <p className="leise frage-warum">{t('paloxZuBeginn')}</p>
            <PaloxMaske d={d} gesperrt={false} gespeichert={async () => { melden(t('gespeichert')); await laden(); setAnsicht(heim) }} />
            {d.ablesungen.length === 0 && (
              <button id="palox-spaeter" style={{ width: '100%', marginTop: '.5rem' }} onClick={() => setAnsicht(heim)}>{t('spaeter')}</button>
            )}
          </>
        ))}
        <Bestaetigt text={meldung} />
      </>
    )
  }
  if (ansicht === 'faule') {
    return <>{maske(t('faulesWiegen'), <FauleMaske d={d} gesperrt={false} melden={melden} neuLaden={laden} />)}<Bestaetigt text={meldung} /></>
  }
  if (ansicht === 'ausgang') {
    return <>{maske(t('fertigePalette'), <FertigePaletteMaske d={d} gesperrt={false} melden={melden} neuLaden={laden} />)}<Bestaetigt text={meldung} /></>
  }
  if (ansicht === 'wiegen') {
    let zettel = ''
    try { zettel = localStorage.getItem(`zettel_${auftragId}`) ?? '' } catch { /* egal */ }
    return maske(t('paletteWiegen'), (
      <WiegenMaske d={d} zettelDatum={zettel} zettelBrutto={zettelBrutto}
                   fertig={async () => { melden(t('paletteGezaehlt')); await laden(); setAnsicht('zaehler') }} />
    ), 'zaehler')
  }
  if (ansicht === 'abschluss') {
    return <Abschluss d={d} neuLaden={laden} zurueck={() => setAnsicht('liste')} fertig={() => navigate('/')} />
  }

  if (ansicht === 'zaehler') {
    return (
      <>
        {fuehrt ? (
          <div className="schritt-kopf">
            <button type="button" className="zurueck" onClick={() => setAnsicht('liste')}>‹ {t('wasZuTun')}</button>
            <span className="stand">{taet?.zeichen} {chargeText(d.charge)}</span>
          </div>
        ) : kopf}
        <Zaehler d={d} gesperrt={false} neuLaden={laden} melden={melden} zumWiegen={b => { setZettelBrutto(b); setAnsicht('wiegen') }} />
        {!fuehrt && (
          <p className="rolle-wechsel">
            <button className="blank" style={{ color: 'var(--text-leise)' }} onClick={() => rolleWechseln(true)}>{t('ichFuehre')}</button>
          </p>
        )}
        <Bestaetigt text={meldung} />
      </>
    )
  }

  // liste — die Checkliste des Vorarbeiters
  const erste = d.ablesungen[0]
  const zaehlStand = [
    p.hatPaletten ? `${d.paletten.length} ${t('paletten')}` : '',
    p.hatKisten ? `${kistenGezaehlt} ${t('kaliberKisten')}` : '',
    p.hatFaxPaletten ? `${a.paletten_gesamt ?? 0} ${t('paletten')}` : '',
  ].filter(Boolean).join(' · ')
  const Zustand = ({ art }: { art: 'getan' | 'offen' | 'frei' }) => (
    <span className={`zustand ${art}`} aria-hidden="true">{art === 'getan' ? '✓' : art === 'offen' ? '!' : '·'}</span>
  )

  return (
    <>
      {kopf}
      <div className="abschnitt-titel">{t('wasZuTun')}</div>
      <div className="check">
        {p.hatPalox && (
          <button id="check-palox" onClick={() => setAnsicht('palox')}>
            <Zustand art={d.ablesungen.length > 0 ? 'getan' : p.paloxPflicht ? 'offen' : 'frei'} />
            <span className="text">
              <span className="name">{p.paloxPflicht ? t('paloxBeginn') : t('paloxFreiwillig')}</span>
              <span className="unter">{erste ? `${t('abgelesenUm')} ${uhrzeit(erste.ts, gebietsschema)}` : p.paloxPflicht ? t('paloxZuBeginnKurz') : t('paloxWaschenWarum')}</span>
            </span>
            <span className="pfeil">›</span>
          </button>
        )}

        <button id="check-zaehlen" onClick={() => setAnsicht('zaehler')}>
          <Zustand art={d.paletten.length + kistenGezaehlt + (a.paletten_gesamt ?? 0) > 0 ? 'getan' : 'offen'} />
          <span className="text">
            <span className="name">{t('zaehlen')}</span>
            <span className="unter">{zaehlStand}</span>
          </span>
          <span className="pfeil">›</span>
        </button>

        {p.hatFaule && (
          <button id="check-faule" onClick={() => setAnsicht('faule')}>
            <Zustand art={d.ablesungen.length > 0 ? 'getan' : 'offen'} />
            <span className="text">
              <span className="name">{t('faulesWiegen')}</span>
              <span className="unter">{d.ablesungen.length > 0 ? `${faulSumme} kg · ${d.ablesungen.length} ${t('kisten')}` : t('faulesWiegenWarum')}</span>
            </span>
            <span className="pfeil">›</span>
          </button>
        )}

        {p.hatAusgang && (
          <button id="check-ausgang" onClick={() => setAnsicht('ausgang')}>
            <Zustand art={d.nAusgang > 0 ? 'getan' : 'frei'} />
            <span className="text">
              <span className="name">{t('fertigePaletteSchritt')}</span>
              <span className="unter">{d.nAusgang > 0 ? `${d.nAusgang} ${t('gewogen')}` : t('fertigePaletteWarum')}</span>
            </span>
            <span className="pfeil">›</span>
          </button>
        )}

        <button id="check-abschluss" className="haupt" style={{ borderColor: 'var(--kuerbis)' }} onClick={() => setAnsicht('abschluss')}>
          <span className="zustand" style={{ borderColor: 'rgb(255 255 255 / 60%)', color: '#fff' }} aria-hidden="true">›</span>
          <span className="text">
            <span className="name">{t('abschliessen')}</span>
            <span className="unter" style={{ color: 'rgb(255 255 255 / 85%)' }}>{p.istFax ? t('dannFax') : t('abschlussErkl')}</span>
          </span>
        </button>
      </div>

      <p className="rolle-wechsel">
        <button className="blank" style={{ color: 'var(--text-leise)' }} onClick={() => rolleWechseln(false)}>{t('nurZaehlenAnsicht')}</button>
      </p>
      <Bestaetigt text={meldung} />
    </>
  )
}
