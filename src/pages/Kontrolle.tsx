import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { fehlerText, stammdaten } from '../lib/db'
import { Hinweis, Karte } from '../components/Bausteine'
import { ZStift, ZZurueck } from '../components/Zeichen'
import { Wahl } from '../components/Schritte'
import { ChargeFeld } from '../components/ChargeFeld'
import type { Charge, Gebinde, Kontrollpalette, KontrollpaletteWiegung } from '../lib/typen'
import { nettoKg, taraFehlt } from '../lib/masse'
import { einstellung } from '../lib/db'
import { ABSTAND_VORGABE, faelligkeit, type Abstand } from '../lib/kontrollpalette'
import { datum as datumText } from '../lib/format'

interface KpVorschlag { charge_nr: number; sorte: string; schlag: string; eingang_netto_kg: number; rang: number; hat_schon: boolean }

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

  // ---- Der zweite Weg: die Kontrollpalette (0072/0073) -----------------
  // Sie hängt an keiner Arbeit und an keiner Charge-Auswahl des Lagerwegs:
  // eine markierte Palette, die stehen bleibt und nur gewogen wird.
  const [weg, setWeg] = useState<'lager' | 'kontrollpalette'>('lager')
  const [kpListe, setKpListe] = useState<Kontrollpalette[]>([])
  const [kpWiegungen, setKpWiegungen] = useState<KontrollpaletteWiegung[]>([])
  const [kpVorschlaege, setKpVorschlaege] = useState<KpVorschlag[]>([])
  const [abstand, setAbstand] = useState<Abstand>(ABSTAND_VORGABE)
  const [kpWahl, setKpWahl] = useState<number | null>(null)
  const [kpNeu, setKpNeu] = useState(false)
  const [kpCharge, setKpCharge] = useState<number | ''>('')
  const [kpKennzeichen, setKpKennzeichen] = useState('')
  const [kpStandort, setKpStandort] = useState('')
  const [kpSchimmel, setKpSchimmel] = useState(false)

  useEffect(() => {
    void stammdaten().then(s => {
      setChargen(s.chargen)
      setGebinde(s.gebinde)
      setArt(a => a || s.gebinde[0]?.art || '')
    })
    void supabase.from('v_kontrolle_vorschlag').select('*')
      .then(({ data }) => setVorschlaege((data ?? []) as Vorschlag[]))
    void kpLaden()
    void Promise.all([
      einstellung<number>('kontrollpalette_tage_anfang', ABSTAND_VORGABE.anfang),
      einstellung<number>('kontrollpalette_tage_spaeter', ABSTAND_VORGABE.spaeter),
    ]).then(([a, b]) => setAbstand({ anfang: Number(a) || ABSTAND_VORGABE.anfang, spaeter: Number(b) || ABSTAND_VORGABE.spaeter }))
  }, [])

  async function kpLaden() {
    const [kp, wg, vs] = await Promise.all([
      supabase.from('kontrollpalette').select('*').is('beendet_ts', null).order('angelegt_ts'),
      supabase.from('kontrollpalette_wiegung').select('*').order('wiege_ts'),
      supabase.from('v_kontrollpalette_vorschlag').select('*').eq('hat_schon', false).order('rang').limit(5),
    ])
    setKpListe((kp.data ?? []) as Kontrollpalette[])
    setKpWiegungen((wg.data ?? []) as KontrollpaletteWiegung[])
    setKpVorschlaege((vs.data ?? []) as KpVorschlag[])
  }

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

  // ---- Kontrollpalette: anlegen und wiegen ----------------------------
  const kpLetzte = (id: number) => {
    const meine = kpWiegungen.filter(w => w.kontrollpalette_id === id)
    return meine.length ? meine[meine.length - 1] : null
  }
  const kpStand = (k: Kontrollpalette) =>
    faelligkeit(k.angelegt_ts, kpLetzte(k.id)?.wiege_ts ?? null, abstand)
  const kpGewaehlt = kpListe.find(k => k.id === kpWahl) ?? null
  const kpVollstaendig = kpWahl !== null && jetzt !== '' && kisten !== '' && art !== ''
  const kpNeuBereit = kpCharge !== '' && kpKennzeichen.trim() !== ''

  async function kpAnlegen() {
    if (!kpNeuBereit || laeuft) return
    setLaeuft(true); setFehler(null)
    const { data, error } = await supabase.from('kontrollpalette').insert({
      charge_nr: kpCharge, kennzeichen: kpKennzeichen.trim(),
      standort: kpStandort.trim() === '' ? null : kpStandort.trim(),
    }).select('id').single()
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    setKpNeu(false); setKpKennzeichen(''); setKpStandort(''); setKpCharge('')
    await kpLaden()
    setKpWahl((data as { id: number }).id)
  }

  async function kpWiegen() {
    if (!kpVollstaendig || laeuft) return
    const e = { jetzt, kisten, netto }
    setLaeuft(true); setFehler(null)
    setJetzt(''); setKisten('')
    const { error } = await supabase.from('kontrollpalette_wiegung').insert({
      kontrollpalette_id: kpWahl, brutto_kg: Number(e.jetzt),
      kisten: Number(e.kisten), gebindeart: art, sichtbar_schimmel: kpSchimmel,
    })
    setLaeuft(false)
    if (error) {
      setFehler(fehlerText(error))
      setJetzt(x => x || e.jetzt); setKisten(x => x || e.kisten)
      return
    }
    setKpSchimmel(false)
    await kpLaden()
    setGespeichert(g => [...g, { charge: kpGewaehlt?.charge_nr ?? 0, netto: e.netto }])
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

      {/* Zwei Wege, ein Bildschirm: die gegriffene Palette aus dem Lager —
          und die Kontrollpalette, die stehen bleibt (0072). */}
      <div className="wahl" style={{ marginBottom: '.9rem' }}>
        <Wahl id="weg-lager" name={t('kpLagerWeg')} gewaehlt={weg === 'lager'}
              onClick={() => setWeg('lager')} />
        <Wahl id="weg-kp" name={t('kpWeg')} gewaehlt={weg === 'kontrollpalette'}
              onClick={() => setWeg('kontrollpalette')} />
      </div>

      {weg === 'kontrollpalette' && (
        <Karte>
          <p className="leise oben-0">{t('kpWarum')}</p>

          {kpListe.length === 0 && !kpNeu && <Hinweis>{t('kpKeine')}</Hinweis>}
          {kpListe.length > 0 && (
            <>
              <p className="leise">{t('kpWaehlen')}</p>
              <div className="wahl">
                {kpListe.map(k => {
                  const st = kpStand(k)
                  const l = kpLetzte(k.id)
                  return (
                    <Wahl key={k.id} id={`kp-${k.id}`}
                          name={`${k.kennzeichen} · ${k.charge_nr}`}
                          erkl={[
                            st.nieGewogen ? t('kpNieGewogen')
                              : `${t('kpZuletzt')}: ${datumText(l!.wiege_ts)} · ${t('kpSeitTagen').replace('{n}', String(st.tageSeit))}`,
                            t('kpAlleAbstand').replace('{n}', String(st.sollAbstand)),
                            st.ueberfaellig ? t('kpUeberfaellig') : '',
                          ].filter(Boolean).join(' · ')}
                          gewaehlt={kpWahl === k.id}
                          onClick={() => { setKpWahl(k.id); setKpNeu(false) }} />
                  )
                })}
              </div>
            </>
          )}

          <button type="button" id="kp-neu" className="voll" style={{ marginTop: '.6rem', minHeight: 48 }}
                  onClick={() => { setKpNeu(x => !x); setKpWahl(null) }}>{t('kpNeu')}</button>

          {kpNeu && (
            <div style={{ marginTop: '.8rem' }}>
              {kpVorschlaege.length > 0 && (
                <>
                  <p className="leise">{t('kpVorschlag')}</p>
                  <div className="wahl">
                    {kpVorschlaege.map(v => (
                      <Wahl key={v.charge_nr} id={`kp-vor-${v.charge_nr}`}
                            name={`${v.charge_nr} · ${v.sorte}`}
                            erkl={`${tonnen(v.eingang_netto_kg)} ${t('imLager')}`}
                            gewaehlt={kpCharge === v.charge_nr}
                            onClick={() => setKpCharge(v.charge_nr)} />
                    ))}
                  </div>
                </>
              )}
              <ChargeFeld id="kp-charge" chargen={chargen} wert={kpCharge} setzen={setKpCharge} />
              <div className="feld">
                <label htmlFor="kp-kennzeichen">{t('kpKennzeichen')}</label>
                <input id="kp-kennzeichen" type="text" value={kpKennzeichen}
                       onChange={e => setKpKennzeichen(e.target.value)} />
                <p className="hilfe">{t('kpKennzeichenErkl')}</p>
              </div>
              <div className="feld">
                <label htmlFor="kp-standort">{t('kpStandort')}</label>
                <input id="kp-standort" type="text" value={kpStandort}
                       onChange={e => setKpStandort(e.target.value)} />
              </div>
              <button type="button" id="kp-anlegen" className="haupt voll" style={{ minHeight: 50 }}
                      disabled={laeuft || !kpNeuBereit} onClick={() => void kpAnlegen()}>{t('kpAnlegen')}</button>
            </div>
          )}

          {kpGewaehlt && (
            <>
              <div className="feld">
                <label htmlFor="kp-jetzt">{t('gewichtJetzt')}</label>
                <input id="kp-jetzt" type="number" inputMode="decimal" step="0.1" min={0}
                       value={jetzt} onChange={e => setJetzt(e.target.value)} style={{ fontSize: '1.2rem' }} />
              </div>
              <div className="spalten">
                <div className="feld">
                  <label htmlFor="kp-kisten">{t('anzahlKisten')}</label>
                  <input id="kp-kisten" type="number" inputMode="numeric" min={1}
                         value={kisten} onChange={e => setKisten(e.target.value)} />
                </div>
                <div className="feld">
                  <label htmlFor="kp-art">{t('kistenart')}</label>
                  <select id="kp-art" value={art} onChange={e => setArt(e.target.value)}>
                    {gebinde.map(g => <option key={g.art} value={g.art}>{g.art}</option>)}
                  </select>
                </div>
              </div>
              <label className="ankreuzen" style={{ display: 'flex', alignItems: 'center', gap: '.6rem', minHeight: 44 }}>
                <input id="kp-schimmel" type="checkbox" checked={kpSchimmel}
                       onChange={e => setKpSchimmel(e.target.checked)} />
                {t('kpSchimmel')}
              </label>
              {netto !== null && netto > 0 && (
                <p style={{ margin: '.4rem 0 .6rem' }}><strong>{netto.toFixed(1)} kg</strong> {t('netto')}</p>
              )}
              {fehlt && <Hinweis art="warnung">{fehlt}</Hinweis>}
              {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
              <button type="button" id="kp-eintragen" className="haupt voll" style={{ minHeight: 54 }}
                      disabled={laeuft || !kpVollstaendig} onClick={() => void kpWiegen()}>{t('eintragen')}</button>
            </>
          )}
        </Karte>
      )}

      {weg === 'lager' && (
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
      )}
    </>
  )
}
