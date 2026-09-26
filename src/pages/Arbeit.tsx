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
import { PaloxLeerenMaske } from '../arbeit/PaloxLeerenMaske'
import { FertigePaletteMaske } from '../arbeit/FertigePaletteMaske'
import { Abschluss } from '../arbeit/Abschluss'
import { Korrektur } from '../arbeit/Korrektur'

type Ansicht = 'liste' | 'zaehler' | 'palox' | 'palox_leeren' | 'faule' | 'wiegen' | 'ausschuss' | 'ausgang' | 'abschluss' | 'korrektur'

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
/**
 * Muss der Vorarbeiter zuerst den Palox ablesen, bevor er irgendetwas
 * anderes sieht? (Runde T)
 *
 * Vorher gab es „Später": Die Ablesung liess sich überspringen, und die
 * Checkliste zeigte dafür ein „!". Der Haken daran kam erst am Ende: Mit nur
 * einer Ablesung (der am Schluss) hat die Arbeit keine Faul-Menge, der
 * Abschluss verlangt die zweite — und die Ware ist längst durch. Der
 * Betrieb: „warum überhaupt dann weiter kommen ohne anklicken?" Also nicht.
 * Wer wirklich nicht ablesen kann, sagt das ausdrücklich — dann ist das
 * Faule dieser Arbeit unbekannt, nicht null, und die Sperre fällt.
 */
function paloxSperre(d: ArbeitDaten): boolean {
  const p = stationsProfil(d.auftrag)
  return p.paloxPflicht && d.auftrag.status !== 'abgeschlossen'
    && !d.auftrag.palox_unbekannt
    && d.ablesungen.filter(x => x.palox_stand_kg !== null).length === 0
}

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
  // 0060: das Gewicht vom Zettel wandert vom Zähler in die Wägung — und seit
  // Runde T auch Kisten und Gebinde, damit die Wägung nicht mit leeren
  // Feldern und dem falschen Gebinde anfängt.
  const [wiegenStart, setWiegenStart] = useState({ brutto: '', kisten: '', gebinde: '' })
  // Runde T: „Palox kann nicht abgelesen werden" fragt einmal nach — die
  // Folge (Faules dieser Arbeit unbekannt) soll niemand aus Versehen wählen.
  const [fragtOhnePalox, setFragtOhnePalox] = useState(false)
  // Q22: „Ich bin nicht mehr dabei" fragt einmal nach — ein Fehlgriff in der
  // Halle soll niemanden aus der Arbeit werfen.
  const [fragtVerlassen, setFragtVerlassen] = useState(false)

  const laden = useCallback(async () => {
    try {
      const daten = await arbeitLaden(auftragId)
      setD(daten); setFehler(null)
      if (daten && fuehrt === null) {
        const f = istVorarbeiter(auftragId, daten.auftrag.eroeffnet_von, session?.user.id)
        setFuehrt(f)
        if (istAdmin && suche.get('korrigieren') === '1') setAnsicht('korrektur')
        // Als erstes der Palox (AB-02), wo er Pflicht ist — und zwar nicht
        // nur beim ersten Öffnen: Solange die Startablesung fehlt, kommt der
        // Vorarbeiter an der Frage nicht vorbei (Runde T, siehe paloxSperre).
        else setAnsicht(f ? (paloxSperre(daten) ? 'palox' : 'liste') : 'zaehler')
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
    // 23505 heisst „steht schon" — er ist auf einem anderen Handy schon
    // dabei, oder diese Seite ist älter als die Wirklichkeit. Kein Fehler,
    // den ein Arbeiter lesen müsste: neu laden, fertig (Q22).
    if (error && (error as { code?: string }).code !== '23505') { setFehler(fehlerText(error)); return }
    await laden()
  }
  // Q22, Schichtwechsel: Wer geht, trägt sich aus. Ohne das stand am Abend
  // die halbe Belegschaft unter „Dabei" — auch die, die um zwei nach Hause
  // gegangen sind, weil `verlassen_ts` bis Runde Q nirgends gesetzt wurde.
  // Die Messungen bleiben unberührt; ausgetragen wird nur die Anwesenheit.
  async function verlassen() {
    const ich = session?.user.id
    if (!ich) return
    const { error } = await supabase.from('auftrag_teilnehmer')
      .update({ verlassen_ts: new Date().toISOString() })
      .eq('auftrag_id', auftragId).eq('profil_id', ich).is('verlassen_ts', null)
    if (error) { setFehler(fehlerText(error)); return }
    navigate('/')
  }
  function rolleWechseln(neu: boolean) {
    fuehrungSetzen(auftragId, session?.user.id, neu); setFuehrt(neu)
    setAnsicht(neu ? (d && paloxSperre(d) ? 'palox' : 'liste') : 'zaehler')
  }
  /** Der ausdrückliche Verzicht: die Arbeit bleibt ohne bekannte Faul-Menge. */
  async function ohnePalox() {
    const { error } = await supabase.from('auftrag').update({ palox_unbekannt: true }).eq('id', auftragId)
    if (error) { setFehler(fehlerText(error)); return }
    setFragtOhnePalox(false)
    await laden(); setAnsicht(heim)
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
      {binDabei && !gesperrt && (
        <p className="rolle-wechsel" style={{ margin: '.5rem 0 0' }}>
          {fragtVerlassen
            ? <>
                <span className="leise">{t('nichtMehrDabeiFrage')}</span>{' '}
                <button type="button" id="verlassen-ja" className="leise-knopf" onClick={() => void verlassen()}>{t('jaGehe')}</button>
                {' · '}
                <button type="button" className="leise-knopf" onClick={() => setFragtVerlassen(false)}>{t('abbrechen')}</button>
              </>
            : <button type="button" id="verlassen" className="leise-knopf" onClick={() => setFragtVerlassen(true)}>{t('nichtMehrDabei')}</button>}
        </p>
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
            {/* Ohne p.hatKisten: seit Runde Q wird nichts mehr gezählt, aber was
                einmal gezählt WURDE, bleibt sichtbar. Nicht mehr erheben ist
                etwas anderes als verschweigen. */}
            {kistenGezaehlt > 0 && <><dt>{t('kaliberKisten')}</dt><dd>{kistenGezaehlt}</dd></>}
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
    const sperre = paloxSperre(d)
    return (
      <>
        <div className="schritt-kopf">
          {/* Solange die Startablesung Pflicht ist und fehlt, führt „Zurück"
              nicht zur Checkliste, sondern aus der Arbeit hinaus — an der
              Frage vorbei kommt niemand (Runde T). */}
          <button type="button" className="zurueck" onClick={() => (sperre ? navigate('/') : setAnsicht(heim))}><ZZurueck size={18} />{sperre ? t('uebersicht') : t('zurueck')}</button>
          <span className="stand"><TaetZeichen id={taet?.id} /> {chargeText(d.charge)}</span>
        </div>
        <h1 className="frage">{p.paloxPflicht ? t('paloxBeginn') : t('paloxFreiwillig')}</h1>
        <PaloxMaske d={d} gesperrt={false} gespeichert={async () => { melden(t('gespeichert')); await laden(); setAnsicht(heim) }} />
        {d.ablesungen.length === 0 && !p.paloxPflicht && (
          <button type="button" id="palox-spaeter" className="voll abstand-oben" onClick={() => setAnsicht(heim)}>{t('ohneAblesungWeiter')}</button>
        )}
        {sperre && !fragtOhnePalox && (
          <p className="rolle-wechsel">
            <button type="button" id="palox-unbekannt" className="leise-knopf" onClick={() => setFragtOhnePalox(true)}>{t('paloxNichtMoeglich')}</button>
          </p>
        )}
        {sperre && fragtOhnePalox && (
          <div className="karte abstand-oben">
            <p className="oben-0">{t('paloxNichtMoeglichFolge')}</p>
            <div className="knopf-reihe">
              <button type="button" id="palox-unbekannt-ja" className="gefahr" style={{ flex: 2, minHeight: 48 }} onClick={() => void ohnePalox()}>{t('paloxUnbekanntLassen')}</button>
              <button type="button" onClick={() => setFragtOhnePalox(false)}>{t('abbrechen')}</button>
            </div>
          </div>
        )}
        <Bestaetigt text={meldung} />
      </>
    )
  }
  if (ansicht === 'faule') {
    return <>{maske(t('faulesWiegen'), <FauleMaske d={d} gesperrt={false} melden={melden} neuLaden={laden} />)}<Bestaetigt text={meldung} /></>
  }
  if (ansicht === 'palox_leeren') {
    // 0084: vor dem Leeren ablesen, leeren, die leere Box ablesen — die
    // Menge bleibt bekannt. Zurück in die Checkliste, wenn beides steht.
    return <>{maske(t('paloxLeeren'), <PaloxLeerenMaske d={d} fertig={async () => { await laden(); melden(t('gespeichert')); setAnsicht('liste') }} />)}<Bestaetigt text={meldung} /></>
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
      <WiegenMaske d={d} zettelDatum={zettel} zettelBrutto={wiegenStart.brutto}
                   kistenVorbelegt={wiegenStart.kisten} gebindeVorbelegt={wiegenStart.gebinde}
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
        <Zaehler d={d} gesperrt={false} neuLaden={laden} melden={melden}
                 zumWiegen={(brutto, kisten, gebinde) => { setWiegenStart({ brutto, kisten, gebinde }); setAnsicht('wiegen') }} />
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
  const geleerte = d.ablesungen.filter(x => x.palox_nach_leeren)
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

  // Runde T: dieselben drei Blöcke wie im Plan vor der Arbeit — vor,
  // während, nach. Was der Plan angekündigt hat, steht hier an derselben
  // Stelle wieder; nichts taucht erst am Ende auf.
  return (
    <>
      {kopf}
      {p.hatPalox && <div className="abschnitt-titel">{t('vorDerArbeit')}</div>}
      {p.hatPalox && (
        <div className="check eintritt">
          <button type="button" id="check-palox" onClick={() => setAnsicht('palox')}>
            <Zustand art={d.ablesungen.length > 0 ? 'getan' : a.palox_unbekannt ? 'frei' : p.paloxPflicht ? 'offen' : 'frei'} />
            <span className="text">
              <span className="name">{p.paloxPflicht ? t('paloxBeginn') : t('paloxFreiwillig')}</span>
              <span className="unter">{erste ? `${t('abgelesenUm')} ${uhrzeit(erste.ts, gebietsschema)}` : a.palox_unbekannt ? t('faulesUnbekannt') : p.paloxPflicht ? t('paloxZuBeginnKurz') : t('freiwillig')}</span>
            </span>
            <span className="pfeil"><ZChevron size={20} /></span>
          </button>
        </div>
      )}

      <div className="abschnitt-titel">{t('waehrendDerArbeit')}</div>
      <div className="check eintritt">
        <button type="button" id="check-zaehlen" onClick={() => setAnsicht('zaehler')}>
          <Zustand art={gezaehlt ? (wiegenErinnert ? 'frei' : 'getan') : 'offen'} />
          <span className="text">
            <span className="name">{t('zaehlen')}</span>
            <span className="unter">{zaehlStand}{wiegenErinnert && gezaehlt ? ` — ${t('dreiWiegen')}` : ''}</span>
          </span>
          <span className="pfeil"><ZChevron size={20} /></span>
        </button>

        {/* 0084: Der Palox wird mittendrin geleert — mit Ablesung davor und
            danach bleibt die Menge bekannt. Erst sinnvoll, wenn ein Anfang
            abgelesen ist; sinnlos, wenn die Menge ohnehin unbekannt ist. */}
        {p.hatPalox && d.ablesungen.some(x => x.palox_stand_kg !== null) && !a.palox_unbekannt && (
          <button type="button" id="check-palox-leeren" onClick={() => setAnsicht('palox_leeren')}>
            <Zustand art="frei" />
            <span className="text">
              <span className="name">{t('paloxLeeren')}</span>
              <span className="unter">{geleerte.length > 0
                ? `${geleerte.length}× ${t('paloxGeleertUm')} ${geleerte.map(g => uhrzeit(g.ts, gebietsschema)).join(', ')}`
                : t('paloxLeerenKurz')}</span>
            </span>
            <span className="pfeil"><ZChevron size={20} /></span>
          </button>
        )}

        {p.hatFaule && (
          <button type="button" id="check-faule" onClick={() => setAnsicht('faule')}>
            <Zustand art={d.ablesungen.length > 0 ? 'getan' : 'offen'} />
            <span className="text">
              <span className="name">{t('faulesWiegen')}</span>
              {d.ablesungen.length > 0 && <span className="unter">{faulSumme} kg · {d.ablesungen.length} {t('kisten')}</span>}
            </span>
            <span className="pfeil"><ZChevron size={20} /></span>
          </button>
        )}
      </div>

      <div className="abschnitt-titel">{t('nachDerArbeit')}</div>
      <div className="check eintritt">
        {p.hatAusschuss && (
          <button type="button" id="check-ausschuss" onClick={() => setAnsicht('ausschuss')}>
            <Zustand art={d.ausschuss.length > 0 ? 'getan' : 'frei'} />
            <span className="text">
              <span className="name">{t('ausschussWiegenSchritt')}</span>
              <span className="unter">{d.ausschuss.length > 0 ? `${ausschussSumme} kg · ${d.ausschuss.reduce((n, z) => n + (z.brutto_kg !== null ? (z.kisten ?? 1) : 0), 0)} ${t('kisten')}` : t('ausschussAmEnde')}</span>
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
