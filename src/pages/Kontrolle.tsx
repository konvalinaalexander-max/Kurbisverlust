import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis, Karte } from '../components/Bausteine'
import { Wahl } from '../components/Schritte'
import { ChargeFeld } from '../components/ChargeFeld'
import type { Charge, Gebinde } from '../lib/typen'

interface Vorschlag {
  charge_nr: number; sorte: string; schlag: string; lager_kg: number
  alter_lager_von: number | null; alter_lager_bis: number | null; n_kontrollen: number; zuletzt: string | null
}

/**
 * Lagerkontrolle: eine zufällig gegriffene Palette wiegen und nachsehen, wie
 * viel faul ist — ohne laufende Arbeit, direkt aus der Halle.
 *
 * Das ist die statistisch wertvollste Messung im ganzen System: die einzige,
 * deren Palette nicht danach ausgewählt wurde, wie sie aussieht. Nur sie kann
 * aufdecken, ob die Verarbeitungsreihenfolge die Schimmelkurve verzerrt
 * (docs/STATISTIK_BEFUND.md).
 *
 * 0060: Die App schlägt drei Chargen vor — die mit dem meisten Bestand und
 * den wenigsten Kontrollen —, der Arbeiter darf jede andere greifen. Gefragt
 * werden Eingangsdatum und Eingangsgewicht vom Zettel (ohne sie sagt die
 * Wägung nichts über die Verdunstung). Die Maske bleibt nach dem Speichern
 * für die nächste Palette stehen.
 *
 * „Davon faul" ist Pflicht, und 0 ist eine echte Antwort: Ein leeres Feld
 * dagegen wäre „nicht nachgesehen" — Leer ≠ 0.
 */
export default function Kontrolle() {
  const { t } = useSprache()
  const navigate = useNavigate()
  const [chargen, setChargen] = useState<Charge[]>([])
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [vorschlaege, setVorschlaege] = useState<Vorschlag[]>([])

  const [chargeNr, setChargeNr] = useState<number | ''>('')
  const [andere, setAndere] = useState(false)
  const [datum, setDatum] = useState('')
  const [damals, setDamals] = useState('')
  const [jetzt, setJetzt] = useState('')
  const [kisten, setKisten] = useState('')
  const [art, setArt] = useState('')
  const [faul, setFaul] = useState('')
  const [auswahl, setAuswahl] = useState('erreichbar_zufaellig')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)
  const [gespeichert, setGespeichert] = useState<{ charge: number; netto: number | null; faul: number }[]>([])

  useEffect(() => {
    void stammdaten().then(s => {
      setChargen(s.chargen)
      setGebinde(s.gebinde)
      setArt(a => a || s.gebinde[0]?.art || '')
    })
    void supabase.from('v_kontrolle_vorschlag').select('*')
      .then(({ data }) => setVorschlaege((data ?? []) as Vorschlag[]))
  }, [])

  const chargeBekannt = chargeNr !== '' && chargen.some(c => c.nr === chargeNr)
  const vollstaendig = chargeBekannt && datum !== '' && damals !== ''
    && jetzt !== '' && kisten !== '' && art !== '' && faul !== ''

  async function speichern() {
    if (!vollstaendig || laeuft) return
    // Die Charge und die Kistenart bleiben stehen — die nächste Palette ist oft
    // dieselbe Charge; nur, was je Palette anders ist, wird geleert. Und zwar
    // sofort, nicht erst nach der Antwort: wer schon die nächste Palette tippt,
    // während die erste noch unterwegs ist, verliert sie sonst an das späte Leeren.
    const e = { datum, damals, jetzt, kisten, faul, auswahl, netto }
    setLaeuft(true); setFehler(null)
    setDatum(''); setDamals(''); setJetzt(''); setKisten(''); setFaul('')
    setAuswahl('erreichbar_zufaellig')
    const { error } = await supabase.from('verdunstung_wiegung').insert({
      charge_nr: chargeNr,
      eingangsdatum: e.datum,
      brutto_damals_kg: Number(e.damals),
      brutto_jetzt_kg: Number(e.jetzt),
      kisten: Number(e.kisten),
      gebindeart: art,
      faul_kg: Number(e.faul),
      sichtbar_schimmel: Number(e.faul) > 0,
      auswahl: e.auswahl,
    })
    setLaeuft(false)
    if (error) {
      setFehler(fehlerText(error))
      // nichts verloren: die Eingabe steht wieder da, soweit nichts Neues getippt wurde
      setDatum(x => x || e.datum); setDamals(x => x || e.damals); setJetzt(x => x || e.jetzt)
      setKisten(x => x || e.kisten); setFaul(x => x || e.faul); setAuswahl(e.auswahl)
      return
    }
    setGespeichert(g => [...g, { charge: chargeNr as number, netto: e.netto, faul: Number(e.faul) }])
  }

  const tara = gebinde.find(g => g.art === art)
  const netto = kisten !== '' && jetzt !== '' && tara?.tara_kg_pro_kiste != null
    ? Number(jetzt) - Number(kisten) * tara.tara_kg_pro_kiste - (tara.tara_kg_palette ?? 0)
    : null
  const alter = (v: Vorschlag) => v.alter_lager_von != null && v.alter_lager_bis != null
    ? (v.alter_lager_von === v.alter_lager_bis ? `${v.alter_lager_von}` : `${v.alter_lager_von}–${v.alter_lager_bis}`) + ` ${t('tage')}` : ''

  return (
    <>
      <div className="schritt-kopf">
        <button type="button" className="zurueck" onClick={() => navigate('/')}>‹ {t('zurueck')}</button>
      </div>
      <h1 className="frage">{t('kontrolle')}</h1>
      <p className="leise frage-warum">{t('kontrolleWarum')}</p>
      {gespeichert.length > 0 && (
        <Hinweis art="gut">✓ {gespeichert.length} {t('gespeichert')} · {gespeichert.map(g => `${g.charge}: ${g.netto !== null ? `${g.netto.toFixed(0)} kg` : '—'}, ${g.faul} kg ${t('faule').toLowerCase()}`).join(' · ')}</Hinweis>
      )}

      <Karte>
        {vorschlaege.length > 0 && (
          <>
            <p className="leise" style={{ marginTop: 0 }}>{t('kontrolleVorschlag')}</p>
            <div className="wahl">
              {vorschlaege.map(v => (
                <Wahl key={v.charge_nr} id={`vorschlag-${v.charge_nr}`} name={`${v.charge_nr} · ${v.sorte}`}
                      erkl={`${Math.round(v.lager_kg / 1000 * 10) / 10} t ${t('imLager')}${alter(v) ? ` · ${t('liegtSeit')} ${alter(v)}` : ''} · ${v.n_kontrollen > 0 ? `${v.n_kontrollen} ${t('kontrollen')}` : t('nochKeineKontrolle')}`}
                      gewaehlt={!andere && chargeNr === v.charge_nr}
                      onClick={() => { setAndere(false); setChargeNr(v.charge_nr) }} />
              ))}
              <Wahl id="vorschlag-andere" bild="✏️" name={t('kontrolleAndere')} gewaehlt={andere}
                    onClick={() => { setAndere(true); setChargeNr('') }} />
            </div>
          </>
        )}
        {(andere || vorschlaege.length === 0) && (
          <ChargeFeld id="k-charge" chargen={chargen} wert={chargeNr} setzen={setChargeNr} />
        )}
        <div className="feld">
          <label htmlFor="k-datum">{t('eingangsdatum')}</label>
          <input id="k-datum" type="date" value={datum} onChange={e => setDatum(e.target.value)} />
        </div>
        <div className="feld">
          <label htmlFor="k-damals">{t('eingangsgewicht')}</label>
          <input id="k-damals" type="number" inputMode="decimal" step="0.1" min={0}
                 value={damals} onChange={e => setDamals(e.target.value)}
                 style={{ fontSize: '1.2rem' }} />
          <p className="leise" style={{ margin: '.35rem 0 0' }}>{t('kontrolleEingangWarum')}</p>
        </div>
        <div className="feld">
          <label htmlFor="k-jetzt">{t('gewichtJetzt')}</label>
          <input id="k-jetzt" type="number" inputMode="decimal" step="0.1" min={0}
                 value={jetzt} onChange={e => setJetzt(e.target.value)}
                 style={{ fontSize: '1.2rem' }} />
        </div>
        <div className="reihe">
          <div className="feld" style={{ flex: 1 }}>
            <label htmlFor="k-kisten">{t('anzahlKisten')}</label>
            <input id="k-kisten" type="number" inputMode="numeric" min={1}
                   value={kisten} onChange={e => setKisten(e.target.value)} />
          </div>
          <div className="feld" style={{ flex: 1 }}>
            <label htmlFor="k-art">{t('kistenart')}</label>
            <select id="k-art" value={art} onChange={e => setArt(e.target.value)}>
              {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
            </select>
          </div>
        </div>
        <div className="feld">
          <label htmlFor="k-faul">{t('wievielFaul')}</label>
          <input id="k-faul" type="number" inputMode="decimal" step="0.5" min={0}
                 value={faul} onChange={e => setFaul(e.target.value)}
                 style={{ fontSize: '1.2rem' }} />
        </div>
        <div className="feld">
          <label htmlFor="k-auswahl">{t('wieGegriffen')}</label>
          <select id="k-auswahl" value={auswahl} onChange={e => setAuswahl(e.target.value)}>
            <option value="erreichbar_zufaellig">{t('auswahlErreichbar')}</option>
            <option value="mitte_unten">{t('auswahlMitteUnten')}</option>
            <option value="gezielt">{t('auswahlGezielt')}</option>
          </select>
        </div>

        {netto !== null && netto > 0 && (
          <p style={{ margin: '0 0 .6rem' }}><strong>{netto.toFixed(1)} kg</strong></p>
        )}

        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <div className="reihe">
          <button id="k-eintragen" className="haupt" style={{ flex: 1, minHeight: 54 }}
                  onClick={speichern} disabled={laeuft || !vollstaendig}>{gespeichert.length > 0 ? t('kontrolleWeitere') : t('eintragen')}</button>
          <button onClick={() => navigate('/')}>{t('uebersicht')}</button>
        </div>
      </Karte>
    </>
  )
}
