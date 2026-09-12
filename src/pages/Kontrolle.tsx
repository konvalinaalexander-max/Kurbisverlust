import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis, Karte } from '../components/Bausteine'
import { ZStift, ZZurueck } from '../components/Zeichen'
import { Wahl } from '../components/Schritte'
import { ChargeFeld } from '../components/ChargeFeld'
import type { Charge, Gebinde } from '../lib/typen'
import { nettoKg, taraFehlt } from '../lib/masse'

interface Vorschlag {
  charge_nr: number; sorte: string; schlag: string; im_haus_heute_kg: number
  alter_lager_von: number | null; alter_lager_bis: number | null
  n_kontrollen: number; zuletzt: string | null; tage_seit_wiegung: number | null
}

/**
 * Lagerkontrolle: eine Palette aus dem Lager wiegen — ohne laufende Arbeit,
 * direkt aus der Halle. Sie ist eine Verdunstungsmessung: Zettel-Datum und
 * Zettel-Gewicht gegen das Gewicht jetzt.
 *
 * Runde H (0061): Die App schlägt die drei Chargen vor, bei denen eine Wägung
 * am meisten bringt — viel Bestand, lange nicht gewogen —, der Arbeiter darf
 * jede andere greifen. Nicht mehr gefragt wird „davon faul" und „wie
 * gegriffen": Die Palette wird gewogen, nicht ausgepackt — was faul ist,
 * sieht dabei niemand, und die Auswahl kann niemand beurteilen. Was die App
 * nicht wissen kann, fragt sie nicht. Die Maske bleibt nach dem Speichern für
 * die nächste Palette stehen.
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
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)
  const [gespeichert, setGespeichert] = useState<{ charge: number; netto: number | null }[]>([])

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
  const vollstaendig = chargeBekannt && datum !== '' && damals !== '' && jetzt !== '' && kisten !== '' && art !== ''

  const tara = gebinde.find(g => g.art === art)
  const netto = kisten !== '' && jetzt !== '' ? nettoKg(Number(jetzt), Number(kisten), tara) : null
  const fehlt = kisten !== '' && jetzt !== '' ? taraFehlt(tara) : null

  async function speichern() {
    if (!vollstaendig || laeuft) return
    // Die Charge und die Kistenart bleiben stehen — die nächste Palette ist oft
    // dieselbe Charge; nur, was je Palette anders ist, wird geleert. Und zwar
    // sofort, nicht erst nach der Antwort: wer schon die nächste Palette tippt,
    // während die erste noch unterwegs ist, verliert sie sonst an das späte Leeren.
    const e = { datum, damals, jetzt, kisten, netto }
    setLaeuft(true); setFehler(null)
    setDatum(''); setDamals(''); setJetzt(''); setKisten('')
    const { error } = await supabase.from('verdunstung_wiegung').insert({
      charge_nr: chargeNr,
      eingangsdatum: e.datum,
      brutto_damals_kg: Number(e.damals),
      brutto_jetzt_kg: Number(e.jetzt),
      kisten: Number(e.kisten),
      gebindeart: art,
    })
    setLaeuft(false)
    if (error) {
      setFehler(fehlerText(error))
      // nichts verloren: die Eingabe steht wieder da, soweit nichts Neues getippt wurde
      setDatum(x => x || e.datum); setDamals(x => x || e.damals); setJetzt(x => x || e.jetzt)
      setKisten(x => x || e.kisten)
      return
    }
    setGespeichert(g => [...g, { charge: chargeNr as number, netto: e.netto }])
  }

  const tonnen = (kg: number) => `${(Math.round(kg / 100) / 10).toLocaleString()} t`
  const erklaerung = (v: Vorschlag) => [
    `${tonnen(v.im_haus_heute_kg)} ${t('imLager')}`,
    v.tage_seit_wiegung !== null
      ? (v.n_kontrollen > 0 || v.zuletzt
          ? t('nichtGewogenSeit').replace('{n}', String(v.tage_seit_wiegung))
          : t('nochNieGewogen').replace('{n}', String(v.tage_seit_wiegung)))
      : '',
    v.n_kontrollen > 0 ? `${v.n_kontrollen} ${t('kontrollen')}` : t('nochKeineKontrolle'),
  ].filter(Boolean).join(' · ')

  return (
    <>
      <div className="schritt-kopf">
        <button type="button" className="zurueck" onClick={() => navigate('/')}><ZZurueck size={20} />{t('zurueck')}</button>
      </div>
      <h1 className="frage">{t('kontrolle')}</h1>
      <p className="leise frage-warum">{t('kontrolleWarum')}</p>
      {gespeichert.length > 0 && (
        <Hinweis art="gut">{gespeichert.length} {t('gespeichert')} · {gespeichert.map(g => `${g.charge}: ${g.netto !== null ? `${g.netto.toFixed(0)} kg` : '—'}`).join(' · ')}</Hinweis>
      )}

      <Karte>
        {vorschlaege.length > 0 && (
          <>
            <p className="leise oben-0">{t('kontrolleVorschlag')}</p>
            <div className="wahl">
              {vorschlaege.map(v => (
                <Wahl key={v.charge_nr} id={`vorschlag-${v.charge_nr}`} name={`${v.charge_nr} · ${v.sorte}`}
                      erkl={erklaerung(v)}
                      gewaehlt={!andere && chargeNr === v.charge_nr}
                      onClick={() => { setAndere(false); setChargeNr(v.charge_nr) }} />
              ))}
              <Wahl id="vorschlag-andere" bild={<span className="kachel" style={{ width: 40, height: 40 }}><ZStift size={22} /></span>} name={t('kontrolleAndere')} gewaehlt={andere}
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
          <p className="hilfe">{t('kontrolleEingangWarum')}</p>
        </div>
        <div className="feld">
          <label htmlFor="k-jetzt">{t('gewichtJetzt')}</label>
          <input id="k-jetzt" type="number" inputMode="decimal" step="0.1" min={0}
                 value={jetzt} onChange={e => setJetzt(e.target.value)}
                 style={{ fontSize: '1.2rem' }} />
        </div>
        <div className="spalten">
          <div className="feld">
            <label htmlFor="k-kisten">{t('anzahlKisten')}</label>
            <input id="k-kisten" type="number" inputMode="numeric" min={1}
                   value={kisten} onChange={e => setKisten(e.target.value)} />
          </div>
          <div className="feld">
            <label htmlFor="k-art">{t('kistenart')}</label>
            <select id="k-art" value={art} onChange={e => setArt(e.target.value)}>
              {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
            </select>
          </div>
        </div>

        {netto !== null && netto > 0 && (
          <p style={{ margin: '0 0 .6rem' }}><strong>{netto.toFixed(1)} kg</strong> {t('netto')}</p>
        )}

        {fehlt && <Hinweis art="warnung">{fehlt} Ohne sie lässt sich das Nettogewicht nicht ausrechnen — die Angabe gehört in die Stammdaten.</Hinweis>}
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <div className="knopf-reihe">
          <button type="button" id="k-eintragen" className="haupt" style={{ minHeight: 54, flex: 2 }}
                  onClick={speichern} disabled={laeuft || !vollstaendig}>{gespeichert.length > 0 ? t('kontrolleWeitere') : t('eintragen')}</button>
          <button type="button" onClick={() => navigate('/')}>{t('uebersicht')}</button>
        </div>
      </Karte>
    </>
  )
}
