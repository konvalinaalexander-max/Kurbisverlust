import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { Hinweis, Karte } from '../components/Bausteine'
import type { Charge, Gebinde } from '../lib/typen'

/**
 * Lagerkontrolle: eine zufällig gegriffene Palette wiegen und nachsehen, wie
 * viel faul ist — ohne laufende Arbeit, direkt aus der Halle.
 *
 * Das ist die statistisch wertvollste Messung im ganzen System: die einzige,
 * deren Palette nicht danach ausgewählt wurde, wie sie aussieht. Nur sie kann
 * aufdecken, ob die Verarbeitungsreihenfolge die Schimmelkurve verzerrt
 * (docs/STATISTIK_BEFUND.md). Bisher konnte die Datenbank sie speichern, aber
 * kein Bildschirm sie erfassen — Wiegen ging nur innerhalb einer Arbeit.
 *
 * „Davon faul" ist hier Pflicht, und 0 ist eine echte Antwort: Eine zufällig
 * gegriffene Palette ohne Faules ist genauso eine Messung wie eine mit. Ein
 * leeres Feld dagegen wäre „nicht nachgesehen" — Leer ≠ 0.
 */
export default function Kontrolle() {
  const { t } = useSprache()
  const navigate = useNavigate()
  const [chargen, setChargen] = useState<Charge[]>([])
  const [gebinde, setGebinde] = useState<Gebinde[]>([])

  const [chargeNr, setChargeNr] = useState<number | ''>('')
  const [datum, setDatum] = useState('')
  const [damals, setDamals] = useState('')
  const [jetzt, setJetzt] = useState('')
  const [kisten, setKisten] = useState('')
  const [art, setArt] = useState('')
  const [faul, setFaul] = useState('')
  const [auswahl, setAuswahl] = useState('erreichbar_zufaellig')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)
  const [gespeichert, setGespeichert] = useState(0)

  useEffect(() => {
    void stammdaten().then(s => {
      setChargen(s.chargen)
      setGebinde(s.gebinde)
      setArt(a => a || s.gebinde[0]?.art || '')
    })
  }, [])

  const vollstaendig = chargeNr !== '' && datum !== '' && damals !== ''
    && jetzt !== '' && kisten !== '' && art !== '' && faul !== ''

  async function speichern() {
    if (!vollstaendig) return
    setLaeuft(true); setFehler(null)
    const { error } = await supabase.from('verdunstung_wiegung').insert({
      charge_nr: chargeNr,
      eingangsdatum: datum,
      brutto_damals_kg: Number(damals),
      brutto_jetzt_kg: Number(jetzt),
      kisten: Number(kisten),
      gebindeart: art,
      faul_kg: Number(faul),
      sichtbar_schimmel: Number(faul) > 0,
      auswahl,
    })
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    // Maske leeren für die nächste Palette; die Zählung zeigt, dass es ankam.
    setChargeNr(''); setDatum(''); setDamals(''); setJetzt(''); setKisten(''); setFaul('')
    setAuswahl('erreichbar_zufaellig')
    setGespeichert(g => g + 1)
  }

  const tara = gebinde.find(g => g.art === art)
  const netto = kisten !== '' && jetzt !== '' && tara?.tara_kg_pro_kiste != null
    ? Number(jetzt) - Number(kisten) * tara.tara_kg_pro_kiste - (tara.tara_kg_palette ?? 0)
    : null

  return (
    <>
      <h1>{t('kontrolle')}</h1>
      {gespeichert > 0 && <Hinweis art="gut">✓ {gespeichert} {t('gespeichert')}</Hinweis>}

      <Karte>
        <div className="feld">
          <label htmlFor="k-charge">{t('charge')}</label>
          <select id="k-charge" value={chargeNr}
                  onChange={e => setChargeNr(e.target.value === '' ? '' : Number(e.target.value))}>
            <option value="">{t('waehlen')}</option>
            {chargen.map(c => <option key={c.nr} value={c.nr}>{chargeText(c)}</option>)}
          </select>
        </div>
        <div className="feld">
          <label htmlFor="k-datum">{t('datumZettel')}</label>
          <input id="k-datum" type="date" value={datum} onChange={e => setDatum(e.target.value)} />
        </div>
        <div className="feld">
          <label htmlFor="k-damals">{t('eingangsgewicht')}</label>
          <input id="k-damals" type="number" inputMode="decimal" step="0.1" min={0}
                 value={damals} onChange={e => setDamals(e.target.value)}
                 style={{ fontSize: '1.2rem' }} />
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
          <button className="haupt" style={{ flex: 1, minHeight: 54 }}
                  onClick={speichern} disabled={laeuft || !vollstaendig}>{t('eintragen')}</button>
          <button onClick={() => navigate('/auftraege')}>{t('fertig')}</button>
        </div>
      </Karte>
    </>
  )
}
