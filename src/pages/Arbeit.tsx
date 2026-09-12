import { useCallback, useEffect, useState } from 'react'
import { TaetKachel, TaetZeichen, ZChevron, ZHaken, ZStift, ZZurueck } from '../components/Zeichen'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, fehlerText } from '../lib/db'
import { taetigkeitVon } from '../lib/taetigkeit'
import { fuehrungSetzen, istVorarbeiter } from '../lib/rolle'
import { Hinweis, Lade, Marke } from '../components/Bausteine'
import { Bestaetigt } from '../components/Schritte'
import { arbeitLaden, fertigeSoll, stationsProfil, uhrzeit, type ArbeitDaten } from '../arbeit/daten'
import { Zaehler } from '../arbeit/Zaehler'
import { PaloxMaske } from '../arbeit/PaloxMaske'
import { FauleMaske } from '../arbeit/FauleMaske'
import { WiegenMaske } from '../arbeit/WiegenMaske'
import { AusschussMaske } from '../arbeit/AusschussMaske'
import { FertigePaletteMaske } from '../arbeit/FertigePaletteMaske'
import { Abschluss } from '../arbeit/Abschluss'
import { Korrektur } from '../arbeit/Korrektur'

type Ansicht = 'liste' | 'zaehler' | 'palox' | 'faule' | 'wiegen' | 'ausschuss' | 'ausgang' | 'abschluss' | 'korrektur'

/**
 * Eine Arbeit, aus zwei Blickwinkeln:
 *  · der Zähler sieht den Zähler — sonst nichts;
 *  · der Vorarbeiter sieht die Checkliste, aus der jede Maske erreichbar ist,
 *    und weiss jederzeit, was erledigt ist und was noch fehlt.
 * Beide können wechseln; die Rolle hängt an der Arbeit (docs/UI-KONZEPT.md).
 * Welche Punkte die Checkliste hat, sagt das Stationsprofil — beim Fax gibt
 * es keinen Palox, dafür „Faules wiegen" und die Palettenzahl (0051, 0060);
 * beim Waschen + Sortieren am Ende zu klein / zu gross je Palette (0061).
 *
 * Der Betriebsleiter kommt mit „?korrigieren=1" von einer Auffälligkeit her
 * und sieht die Messungen dieser Arbeit zum Berichtigen (Runde H).
 */
export default function Arbeit() {
  const { id } = useParams()
  const auftragId = Number(id)
  const [suche] = useSearchParams()
  const navigate = useNavigate()
  const { session, istAdmin } = useAuth()
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
        const p = stationsProfil(daten.auftrag)
        if (istAdmin && suche.get('korrigieren') === '1') setAnsicht('korrektur')
        // Frisch eröffnet: als erstes der Palox (AB-02) — wo er Pflicht ist.
        else setAnsicht(f ? (suche.get('neu') === '1' && p.paloxPflicht && daten.ablesungen.length === 0 ? 'palox' : 'liste') : 'zaehler')
      }
    } catch (f) { setFehler(fehlerText(f)) } finally { setLaedt(false) }
  }, [auftragId, session?.user.id, fuehrt, suche, istAdmin])
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
    <div className="karte arbeit-kopf eintritt">
      <div className="kopfzeile">
        <TaetKachel id={taet?.id} size={44} />
        <div className="flex-1" style={{ minWidth: 0 }}>
          <h1>{taet ? t(taet.text) : ''}</h1>
          <div className="charge">{chargeText(d.charge)}</div>
        </div>
        <Marke art={gesperrt ? 'fertig' : 'offen'}>{gesperrt ? t('fertig') : t('laeuft')}</Marke>
      </div>
      <p className="leise unter">
        {t('seit')} {uhrzeit(a.start_ts, gebietsschema)} · {t('dabei')}: {d.teilnehmer.length ? d.teilnehmer.map(x => x.name).join(', ') : t('niemand')}
        {fuehrt && !gesperrt && <> · <Marke>{t('vorarbeiter')}</Marke></>}
      </p>
      {!binDabei && !gesperrt && (
        <button type="button" className="haupt gross voll" onClick={() => void mitmachen()}>
          {t('mitmachen')}
        </button>
      )}
    </div>
  )

  const kistenGezaehlt = d.gebinde.reduce((s, g) => s + g.anzahl, 0)
  const waschKisten = d.paletten.reduce((s, x) => s + (x.kisten ?? 0), 0)
  const gewogen = d.paletten.filter(x => x.wiegung_id != null).length
  const faulSumme = d.ablesungen.reduce((s, z) => s + z.kg, 0)
  const ausschussSumme = d.ausschuss.reduce((s, z) => s + z.kg, 0)
  const soll = fertigeSoll(d)
  const ersetzen = (text: string, werte: Record<string, number>) =>
    Object.entries(werte).reduce((s, [k, v]) => s.replace(`{${k}}`, String(v)), text)

  // Der Betriebsleiter berichtigt Messungen — auch an einer fertigen Arbeit.
  if (ansicht === 'korrektur' && istAdmin) {
    return <Korrektur d={d} neuLaden={laden} zurueck={() => (gesperrt ? navigate('/messungen') : setAnsicht(heim))} />
  }

  // Fertige Arbeit: nur noch lesen.
  if (gesperrt) {
    return (
      <>
        {kopf}
        <div className="karte">
          <dl className="zusammenfassung">
            <dt>{t('abgeschlossenAm')}</dt>
            <dd>{a.ende_ts ? new Date(a.ende_ts).toLocaleString(gebietsschema, { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'}</dd>
            {p.hatPaletten && <><dt>{t('paletten')}</dt><dd>{d.paletten.length}{gewogen > 0 && <span className="leise"> · {gewogen} {t('gewogen')}</span>}</dd></>}
            {p.hatWaschPaletten && <><dt>{t('paletten')}</dt><dd>{d.paletten.length} · {waschKisten} {t('kisten')}</dd></>}
            {p.hatFaxPaletten && <><dt>{t('palettenGesamt')}</dt><dd>{a.paletten_gesamt ?? '—'}</dd></>}
            {p.hatKisten && kistenGezaehlt > 0 && <><dt>{t('kaliberKisten')}</dt><dd>{kistenGezaehlt}</dd></>}
            <dt>{t('faule')}</dt><dd>{faulSumme} kg</dd>
            {p.hatAusschuss && <><dt>{t('ausschussWiegenSchritt')}</dt><dd>{d.ausschuss.length > 0 ? `${ausschussSumme} kg` : '—'}</dd></>}
            {p.hatAusgang && <><dt>{t('fertigePalette')}</dt><dd>{d.nAusgang > 0 ? `${d.nAusgang} ${t('gewogen')}` : t('keineGewogen')}</dd></>}
          </dl>
        </div>
        <div className="knopf-reihe">
          {istAdmin && (
            <button type="button" id="zur-korrektur" className="voll" onClick={() => setAnsicht('korrektur')}><ZStift size={18} />{t('messungenKorrigieren')}</button>
          )}
          <button type="button" className="voll" onClick={() => navigate('/')}><ZZurueck size={18} />{t('uebersicht')}</button>
        </div>
      </>
    )
  }

  // Eine Maske: Kopfzeile mit Zurück, dann die Maske.
  const maske = (titel: string, inhalt: React.ReactNode, zurueckZu: Ansicht = heim) => (
    <>
      <div className="schritt-kopf">
        <button type="button" className="zurueck" onClick={() => setAnsicht(zurueckZu)}><ZZurueck size={18} />{t('zurueck')}</button>
        <span className="stand"><TaetZeichen id={taet?.id} /> {chargeText(d.charge)}</span>
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
              <button type="button" id="palox-spaeter" className="voll abstand-oben" onClick={() => setAnsicht(heim)}>{t('spaeter')}</button>
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
  if (ansicht === 'ausschuss') {
    return <>{maske(t('ausschussWiegenSchritt'), <AusschussMaske d={d} gesperrt={false} melden={melden} neuLaden={laden} />)}<Bestaetigt text={meldung} /></>
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
            <button type="button" className="zurueck" onClick={() => setAnsicht('liste')}><ZZurueck size={18} />{t('wasZuTun')}</button>
            <span className="stand"><TaetZeichen id={taet?.id} /> {chargeText(d.charge)}</span>
          </div>
        ) : kopf}
        <Zaehler d={d} gesperrt={false} neuLaden={laden} melden={melden} zumWiegen={b => { setZettelBrutto(b); setAnsicht('wiegen') }} />
        {!fuehrt && (
          <p className="rolle-wechsel">
            <button type="button" className="leise-knopf" onClick={() => rolleWechseln(true)}>{t('ichFuehre')}</button>
          </p>
        )}
        <Bestaetigt text={meldung} />
      </>
    )
  }

  // liste — die Checkliste des Vorarbeiters
  const erste = d.ablesungen[0]
  const zaehlStand = [
    p.hatPaletten ? `${d.paletten.length} ${t('paletten')}${gewogen > 0 ? ` · ${gewogen} ${t('gewogen')}` : ''}` : '',
    p.hatWaschPaletten ? `${d.paletten.length} ${t('paletten')} · ${waschKisten} ${t('kisten')}` : '',
    p.hatKisten ? `${kistenGezaehlt} ${t('kaliberKisten')}` : '',
    p.hatFaxPaletten ? `${a.paletten_gesamt ?? 0} ${t('paletten')}` : '',
  ].filter(Boolean).join(' · ')
  const gezaehlt = d.paletten.length + kistenGezaehlt + (a.paletten_gesamt ?? 0) > 0
  const wiegenErinnert = p.wiegenSoll > 0 && gewogen < p.wiegenSoll
  const Zustand = ({ art }: { art: 'getan' | 'offen' | 'frei' }) => (
    <span className={`zustand ${art}`} aria-hidden="true">{art === 'getan' ? <ZHaken size={18} /> : art === 'offen' ? '!' : <span className="punkt-klein" />}</span>
  )

  return (
    <>
      {kopf}
      <div className="abschnitt-titel">{t('wasZuTun')}</div>
      <div className="check eintritt">
        {p.hatPalox && (
          <button type="button" id="check-palox" onClick={() => setAnsicht('palox')}>
            <Zustand art={d.ablesungen.length > 0 ? 'getan' : p.paloxPflicht ? 'offen' : 'frei'} />
            <span className="text">
              <span className="name">{p.paloxPflicht ? t('paloxBeginn') : t('paloxFreiwillig')}</span>
              <span className="unter">{erste ? `${t('abgelesenUm')} ${uhrzeit(erste.ts, gebietsschema)}` : p.paloxPflicht ? t('paloxZuBeginnKurz') : t('paloxWaschenWarum')}</span>
            </span>
            <span className="pfeil"><ZChevron size={20} /></span>
          </button>
        )}

        <button type="button" id="check-zaehlen" onClick={() => setAnsicht('zaehler')}>
          <Zustand art={gezaehlt ? (wiegenErinnert ? 'frei' : 'getan') : 'offen'} />
          <span className="text">
            <span className="name">{t('zaehlen')}</span>
            <span className="unter">{zaehlStand}{wiegenErinnert && gezaehlt ? ` — ${t('dreiWiegen')}` : ''}</span>
          </span>
          <span className="pfeil"><ZChevron size={20} /></span>
        </button>

        {p.hatFaule && (
          <button type="button" id="check-faule" onClick={() => setAnsicht('faule')}>
            <Zustand art={d.ablesungen.length > 0 ? 'getan' : 'offen'} />
            <span className="text">
              <span className="name">{t('faulesWiegen')}</span>
              <span className="unter">{d.ablesungen.length > 0 ? `${faulSumme} kg · ${d.ablesungen.length} ${t('kisten')}` : t('faulesWiegenWarum')}</span>
            </span>
            <span className="pfeil"><ZChevron size={20} /></span>
          </button>
        )}

        {p.hatAusschuss && (
          <button type="button" id="check-ausschuss" onClick={() => setAnsicht('ausschuss')}>
            <Zustand art={d.ausschuss.length > 0 ? 'getan' : 'frei'} />
            <span className="text">
              <span className="name">{t('ausschussWiegenSchritt')}</span>
              <span className="unter">{d.ausschuss.length > 0 ? `${ausschussSumme} kg · ${d.ausschuss.length} ${t('paletten')}` : t('ausschussAmEnde')}</span>
            </span>
            <span className="pfeil"><ZChevron size={20} /></span>
          </button>
        )}

        {p.hatAusgang && (
          <button type="button" id="check-ausgang" onClick={() => setAnsicht('ausgang')}>
            <Zustand art={d.nAusgang >= soll ? 'getan' : p.ausgangPflicht ? 'offen' : d.nAusgang > 0 ? 'getan' : 'frei'} />
            <span className="text">
              <span className="name">{t('fertigePaletteSchritt')}</span>
              <span className="unter">{d.nAusgang >= soll ? `${d.nAusgang} ${t('gewogen')}` : `${t('dreiFertige')} ${ersetzen(t('nurGewogen'), { n: d.nAusgang, soll })}`}</span>
            </span>
            <span className="pfeil"><ZChevron size={20} /></span>
          </button>
        )}

        <button type="button" id="check-abschluss" className="haupt" onClick={() => setAnsicht('abschluss')}>
          <span className="zustand" aria-hidden="true"><ZChevron size={18} /></span>
          <span className="text">
            <span className="name">{t('abschliessen')}</span>
            <span className="unter">{p.istFax ? t('dannFax') : p.hatAusschuss ? t('abschlussErklWS') : t('abschlussErkl')}</span>
          </span>
        </button>
      </div>

      <p className="rolle-wechsel">
        <button type="button" className="leise-knopf" onClick={() => rolleWechseln(false)}>{t('nurZaehlenAnsicht')}</button>
        {istAdmin && <> · <button type="button" className="leise-knopf" onClick={() => setAnsicht('korrektur')}>{t('messungenKorrigieren')}</button></>}
      </p>
      <Bestaetigt text={meldung} />
    </>
  )
}
