import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useBetriebsmodus } from '../lib/betriebsmodus'
import DemoDaten from '../components/DemoDaten'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Aufklapp, Erklaerung, Herkunft, Hinweis, Karte, Kennzahl, Segmente } from '../components/Bausteine'
import { Anteilsbalken, Glocke, Linien, tonnenAchse, type Anteilszeile, type Reihe } from '../components/Diagramm'
import { STROMFARBE, STROMKURZ, alterSpanne, anteilBei, glockeVorbereiten, gruppenSchluessel, kaliberJe,
         prognoseBei, prognoseEnde, stroemeVon, useAuswertung, wohinVon,
         type Auswertung, type Bestand, type Gruppe } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { summeBekannt } from '../lib/masse'
import { useZaehler } from '../design/bewegung'
import { ZWarnung } from '../components/Zeichen'

const TAG = 86400000
const GRUPPEN: [Gruppe, string][] = [['gesamt', 'Gesamt'], ['sorte', 'je Sorte'], ['schlag', 'je Schlag'], ['charge', 'je Charge']]

/** Heller Zwilling einer Stromfarbe — dieselbe Ursache, aber noch im Lager. */
const hell = (farbe: string) => `color-mix(in srgb, ${farbe} 42%, var(--flaeche))`

/**
 * Die zehn Teile, in die der Eingang zerfällt (erg_wohin). Die ersten fünf
 * sind passiert, die letzten fünf liegen noch — dieselben Ursachen, dieselben
 * Farben, nur heller. Zusammen ergeben sie den ganzen Eingang.
 */
const WOHIN_TEILE: { name: string; feld: string; farbe: string; hinweis?: string }[] = [
  { name: 'Ausgeliefert', feld: 'geliefert_kg', farbe: 'var(--strom-rest)',
    hinweis: 'verkauft — auf einem Lieferschein' },
  { name: 'Anderer Kanal (ausgeliefert)', feld: 'kanal_ausgelagert_kg', farbe: STROMFARBE['Zu klein (Tierfutter)'],
    hinweis: 'zu klein oder zu gross: nicht weg, nur nicht Hauptware' },
  { name: 'Verdunstet (ausgeliefert)', feld: 'verdunstet_ausgelagert_kg', farbe: STROMFARBE['Verdunstung'] },
  { name: 'Faul (ausgeliefert)', feld: 'faul_ausgelagert_kg', farbe: STROMFARBE['Schimmel/Fäulnis'],
    hinweis: 'Faules im Lager und vom Feld, an der Ware, die schon draussen ist' },
  { name: 'Faules beim Abpacken', feld: 'fax_kg', farbe: STROMFARBE['Faul beim Abpacken (Fax)'] },
  { name: 'Im Lager: verkaufsfähig', feld: 'lager_verkaufsfaehig_kg', farbe: hell('var(--strom-rest)'),
    hinweis: 'liegt und ist heute verkaufsfähig' },
  { name: 'Im Lager: zu klein / zu gross', feld: 'lager_kanal_kg', farbe: hell(STROMFARBE['Zu klein (Tierfutter)']),
    hinweis: 'war es vom Feld an — wächst nicht mit der Lagerdauer' },
  { name: 'Im Lager: Fax erwartet', feld: 'lager_fax_kg', farbe: hell(STROMFARBE['Faul beim Abpacken (Fax)']),
    hinweis: 'fällt erst beim Abpacken an' },
  { name: 'Im Lager: faul', feld: 'lager_faul_kg', farbe: hell(STROMFARBE['Schimmel/Fäulnis']) },
  { name: 'Im Lager: verdunstet', feld: 'lager_verdunstet_kg', farbe: hell(STROMFARBE['Verdunstung']) },
]
/** Was davon echter Verlust ist — danach wird sortiert. */
const VERLUSTTEILE = new Set(['Verdunstet (ausgeliefert)', 'Faul (ausgeliefert)', 'Faules beim Abpacken',
                              'Im Lager: faul', 'Im Lager: verdunstet'])

/** Eine Tonnenzahl, die beim Erscheinen zu ihrem Wert läuft. */
function Tonnen({ kg }: { kg: number | null | undefined }) {
  const w = useZaehler(kg)
  return <>{tonnen(w)}</>
}

/**
 * Überblick — das Dashboard des Betriebsleiters. Er fragt zwei Dinge, und in
 * dieser Reihenfolge stehen sie hier:
 *
 *   1. Wie viel kam herein, wie viel ging hinaus, wie viel liegt noch — und
 *      wie viel davon ist verkaufsfähig? Vier Kopfzahlen, dann der Verlauf.
 *   2. Wo geht der Kürbis hin? Eine Karte, in der der ganze Eingang in seine
 *      zehn Teile zerfällt, mit der Rangfolge darunter.
 *
 * Der Verlust ist keine Kopfzahl mehr. Er ist der Abstand zwischen „Im Lager"
 * und „Verkaufsfähig" — und in „Wohin geht der Kürbis?" steht er ausgebreitet.
 */
export default function Ueberblick() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const modus = useBetriebsmodus()
  const [gruppe, setGruppe] = useState<Gruppe>('gesamt')
  const [wahl, setWahl] = useState('')
  const navigate = useNavigate()

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const s = daten.saison
  if (!s || daten.bestand.length === 0) {
    return (
      <>
        <Reiterkopf titel="Überblick" zweck="Was kam herein, was ging hinaus — und wie viel von dem, was noch liegt, ist verkaufsfähig." stand={daten.stand} />
        <Probleme liste={daten.probleme} />
        <Hinweis>Noch keine auswertbaren Daten. Dafür braucht es mindestens Eingangspaletten mit hinterlegter Tara — siehe Betrieb → Stammdaten.</Hinweis>
        {modus === 'beispiel' && <DemoDaten kompakt nachAenderung={() => void neuRechnen()} />}
      </>
    )
  }

  const gesamt = stroemeVon(daten.verlust, 'gesamt')
  const unbekannt = gesamt.filter(x => !x.bekannt && x.buch !== 'bilanz').map(x => STROMKURZ[x.strom] ?? x.strom)
  const paletten = daten.bestand.reduce((a, b) => a + b.n_paletten, 0)
  // 0064: Paletten ohne Netto (fehlende Tara, fehlende Kistenzahl) gehen mit dem
  // Mittel der übrigen in den Eingang ein. Solange das vorkommt, ist der Eingang
  // nicht durchweg gemessen — und die Marke darf das nicht behaupten.
  const ohneNetto = daten.bestand.reduce((a, b) => a + (b.n_paletten - b.n_paletten_mit_netto), 0)
  const chargenImHaus = daten.bestand.filter(b => b.im_haus_heute_kg > 0).length

  // Die Prognose der ganzen Saison: heute, in vier Wochen, am Saisonende.
  const p0 = prognoseBei(daten.prognose, 'gesamt', '', 0)
  const p28 = prognoseBei(daten.prognose, 'gesamt', '', 28)
  const pEnde = prognoseEnde(daten.prognose, 'gesamt')
  const anteilHeute = p0?.verkaufsfaehig_anteil ?? null

  // Die Teile der liegenden Ware — der Mini-Balken unter „davon verkaufsfähig".
  const wohinGesamt = wohinVon(daten.wohin, 'gesamt')
  const lagerTeile = WOHIN_TEILE.filter(t => t.feld.startsWith('lager_')).map(t => ({
    name: t.name.replace('Im Lager: ', ''), farbe: t.farbe,
    kg: (wohinGesamt?.[t.feld as keyof typeof wohinGesamt] as number | null) ?? 0,
  }))
  const lagerSumme = lagerTeile.reduce((a, t) => a + t.kg, 0)

  // Die gewählte Gruppe: ein Schlüssel, wenn nicht „Gesamt".
  const schluessel = gruppenSchluessel(daten.verlust, gruppe)
  const aktiv = gruppe === 'gesamt' ? '' : (wahl && schluessel.includes(wahl) ? wahl : schluessel[0] ?? '')

  return (
    <>
      <Reiterkopf titel="Überblick" zweck="Was kam herein, was ging hinaus — und wie viel von dem, was noch liegt, ist verkaufsfähig."
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt} />
      <Probleme liste={daten.probleme} />
      {daten.befunde.length > 0 && (
        <div className="hinweis warnung" role="status">
          <span className="hinweis-zeichen"><ZWarnung size={18} /></span>
          <div className="hinweis-text">
            <strong>{daten.befunde.length} Auffälligkeiten</strong> — Messungen, die nicht in die Rechnung eingehen, meist ein Tippfehler.{' '}
            <Link to="/messungen">Ansehen und korrigieren</Link>
          </div>
        </div>
      )}

      {/* 1. Vier Zahlen: zwei gemessen, zwei gerechnet */}
      <div className="kennzahl-reihe">
        <Kennzahl titel="Eingang"
                  wert={<><Tonnen kg={s.eingang_kg} />{ohneNetto === 0
                    ? <Herkunft art="gemessen" />
                    : <Herkunft art="gerechnet" text={`${ohneNetto} Paletten ohne Nettogewicht — für sie rechnet der Eingang mit dem Mittel der übrigen`} />}</>}
                  unter={<>{zahl(paletten)} Paletten · {s.n_chargen} Chargen · ab Erntejournal
                    {ohneNetto > 0 && <>, {zahl(ohneNetto)} ohne Nettogewicht (<Link to="/messungen">welche</Link>)</>}</>} />
        <Kennzahl titel="Ausgeliefert"
                  wert={s.n_lieferungen > 0 || s.vorlauf_kg > 0
                    ? <><Tonnen kg={s.ausgang_kg} />{s.vorlauf_kg > 0
                        ? <Herkunft art="gerechnet" text="enthält die Angabe des Betriebs über die Zeit vor dem Erfassungsbeginn — dafür gibt es keinen Lieferschein" />
                        : <Herkunft art="gemessen" />}</>
                    : '—'}
                  unter={s.n_lieferungen > 0 || s.vorlauf_kg > 0
                    ? <>{zahl(s.n_lieferungen)} Lieferungen ab Lieferschein{s.marge_kg > 0 ? ` · ${tonnen(s.marge_kg)} an Tiere und Nebenkanal` : ''}{s.vorlauf_kg > 0 ? ` · ${tonnen(s.vorlauf_kg)} vor dem Erfassungsbeginn` : ''}</>
                    : <>noch kein Warenausgang eingelesen — <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link></>} />
        <Kennzahl titel="Im Lager" ton="kuerbis"
                  wert={<><Tonnen kg={s.lager_kg} /><Herkunft art="gerechnet" /></>}
                  unter={<>Eingangsware, die nicht ausgeliefert ist · {chargenImHaus} Chargen
                    · im Haus gesamt <strong>{tonnen(s.im_haus_heute_kg)}</strong>{s.verlust_bekannt ? '' : ' (höchstens)'}</>} />
        <Kennzahl titel="Davon verkaufsfähig" ton="gruen"
                  wert={<>{/* Fehlt ein Koeffizient, ist die Masse eine obere Schranke (0064) — dann
                             sagt die Kopfzahl das, so wie „Im Lager" es für „im Haus gesamt" tut.
                             Drehbuch 03 spielt genau diesen Fall. */}
                    {anteilHeute === null && <span style={{ fontSize: '.45em', whiteSpace: 'nowrap' }}>höchstens </span>}
                    <Tonnen kg={s.verkaufsfaehig_heute_kg} />{anteilHeute !== null && <span style={{ fontSize: '.55em', whiteSpace: 'nowrap' }}> · {prozent(anteilHeute, 0)}</span>}<Herkunft art="gerechnet" /></>}
                  unter={<>
                    <span className="mini-anteile" aria-hidden="true">
                      {lagerTeile.filter(t => t.kg > 0).map(t => <span key={t.name} style={{ width: `${(t.kg / Math.max(lagerSumme, 1)) * 100}%`, background: t.farbe }} />)}
                    </span>
                    {anteilHeute === null
                      ? <>der Anteil an der liegenden Eingangsware ist unbekannt, solange ein Koeffizient nicht gemessen ist</>
                      : <>
                          {p28?.verkaufsfaehig_anteil != null && <span style={{ whiteSpace: 'nowrap' }}>in 4 Wochen {prozent(p28.verkaufsfaehig_anteil, 0)}</span>}
                          {p28?.verkaufsfaehig_anteil != null && ' · '}
                          {pEnde && pEnde.h > 28 && pEnde.verkaufsfaehig_anteil != null
                            ? <><span style={{ whiteSpace: 'nowrap' }}>am {datum(pEnde.datum).slice(0, 6)} <strong>{prozent(pEnde.verkaufsfaehig_anteil, 0)}</strong></span><Herkunft art="prognose" text="wenn die heute liegende Ware bis dahin liegen bleibt" /></>
                            : <span className="leise">Anteil an der liegenden Eingangsware</span>}
                        </>}
                  </>} />
      </div>
      {unbekannt.length > 0 && (
        <Hinweis art="warnung"><strong>Nicht gemessen: {unbekannt.join(', ')}.</strong> Diese Ursache ist unbekannt — nicht null — und fehlt in allen Summen. Unter <Link to="/messungen">Messungen</Link> steht, welche Messung sie liefert.</Hinweis>
      )}

      {/* Die Wahl gilt für den Verlauf, „Wohin geht der Kürbis?" und „Was ist noch im Haus?" */}
      <div className="filterleiste">
        <Segmente wahl={gruppe} setzen={g => { setGruppe(g); setWahl('') }} teile={GRUPPEN} />
        {gruppe !== 'gesamt' && schluessel.length > 0 && (
          <>
            <label htmlFor="ueb-wahl">{gruppe === 'sorte' ? 'Sorte' : gruppe === 'schlag' ? 'Schlag' : 'Charge'}</label>
            <select id="ueb-wahl" value={aktiv} onChange={e => setWahl(e.target.value)}>
              {schluessel.map(k => <option key={k} value={k}>{gruppe === 'charge' ? `Charge ${k}` : k}</option>)}
            </select>
          </>
        )}
      </div>

      {/* 2. Der Verlauf: im Lager und verkaufsfähig, bis heute gemessen, dann Prognose */}
      <Verlauf daten={daten} gruppe={gruppe} schluessel={aktiv} />

      {/* 3. Wohin geht der Kürbis — der ganze Eingang, aufgeteilt */}
      <Wohin daten={daten} gruppe={gruppe} schluessel={aktiv} oeffnen={z => z.ziel && navigate(z.ziel)} />

      {/* 4. Noch im Haus — nach derselben Wahl */}
      <ImHaus daten={daten} gruppe={gruppe} />

      {/* 5. Kaliber: die Glocke je Sorte oder Charge */}
      <Kaliber daten={daten} />
    </>
  )
}

/* ---------- Der Verlauf --------------------------------------------------- */

function Verlauf({ daten, gruppe, schluessel }: { daten: Auswertung; gruppe: Gruppe; schluessel: string }) {
  const k = gruppe === 'gesamt' ? '' : schluessel
  const wochen = daten.verlauf.filter(w => w.gruppe === gruppe && w.schluessel === k)
    .sort((a, b) => a.bis.localeCompare(b.bis))
  if (wochen.length < 2) return null
  const x = (d: string) => Date.parse(d) / TAG
  const heute = x(daten.heute)
  const bisHeute = wochen.filter(w => !w.prognose)
  const xErste = x(wochen[0].woche), xLetzte = x(wochen[wochen.length - 1].bis)
  // Die Achse endet immer beim letzten Punkt — sonst fehlte ein Stück Prognose.
  // Gepolstert wird links, vor dem ersten Eingang: dort ist ohnehin nichts.
  const xBis = xLetzte
  const xVon = Math.min(xErste, 2 * heute - xLetzte)
  const anteil = (w: typeof wochen[number]) => w.lager_kg > 0 ? w.verkaufsfaehig_kg / w.lager_kg : null
  const reihen: Reihe[] = [
    { name: 'Eingang kumuliert', farbe: 'var(--text-leise)', linie: true, marker: false, flaeche: true, ausgeblendet: true,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: w.eingang_kum_kg })) },
    { name: 'Ausgeliefert kumuliert', farbe: 'var(--text-2)', linie: true, marker: false, flaeche: true,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: w.ausgang_kum_kg })) },
    { name: 'Im Lager — Eingangsware, die noch liegt', farbe: 'var(--kuerbis)', linie: true, marker: false, dick: true, prognoseAb: heute,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.lager_kg })) },
    { name: 'Davon verkaufsfähig', farbe: 'var(--strom-rest)', linie: true, marker: false, dick: true, prognoseAb: heute,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.verkaufsfaehig_kg,
        text: `${prozent(anteil(w), 0)} der liegenden Ware · zu klein/zu gross ${tonnen(w.kanal_kg)} · Fax erwartet ${tonnen(w.fax_lager_kg)}` })) },
    { name: 'Gute Ware (nach Verdunstung und Faulem)', farbe: 'var(--text-leise)', linie: true, marker: false, prognoseAb: heute, ausgeblendet: true,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.im_haus_kg })) },
  ]
  const name = gruppe === 'gesamt' ? 'alle Chargen' : gruppe === 'charge' ? `Charge ${schluessel}` : schluessel
  return (
    <Karte titel="Die Saison im Verlauf" unter={`Je Woche für ${name}: was hereinkam, was hinausging, was noch liegt — und wie viel davon verkaufsfähig ist.`}>
      <Linien reihen={reihen} heute={{ x: heute, text: `heute, ${datum(daten.heute).slice(0, 6)}` }}
              xVon={xVon} xBis={xBis} hoehe={300}
              xFormat={d => datum(new Date(d * TAG)).slice(0, 5)} yFormat={tonnenAchse} xTitel="Woche" yTitel="Tonnen, kumuliert" />
      <Erklaerung>
        <p>Eingang und Ausgeliefert sind <Herkunft art="gemessen" /> und enden heute.
        <strong> Im Lager</strong> ist die Eingangsware, die an diesem Stichtag noch nicht ausgeliefert war — sie fällt, wenn geliefert wird, und steht danach still.
        <strong> Davon verkaufsfähig</strong> ist <Herkunft art="gerechnet" /> und fällt auch dann weiter, wenn nichts geliefert wird: Die liegende Ware altert.</p>
        <p>Der Abstand zwischen den beiden dicken Linien <em>ist</em> der Verlust plus das, was zu klein, zu gross oder Fax-Ausschuss ist — deshalb gibt es dafür keine eigene Linie mehr.
        Ab heute läuft beides gestrichelt weiter als <Herkunft art="prognose" />: <em>wenn nichts mehr verkauft wird und nichts Neues hereinkommt.</em>
        Zeigen auf eine Woche nennt alle Linien und den Anteil; die Legende blendet Linien aus; ein gezogener Rahmen vergrössert.</p>
      </Erklaerung>
    </Karte>
  )
}

/* ---------- Wohin geht der Kürbis? ----------------------------------------- */

function wohinZeilen(daten: Auswertung, gruppe: Gruppe, schluessel: string): Anteilszeile[] {
  const keys = gruppe === 'gesamt' ? [''] : gruppenSchluessel(daten.verlust, gruppe)
  const chargen = new Map(daten.bestand.map(b => [String(b.charge_nr), b]))
  const zeilen = keys.map(k => {
    const w = wohinVon(daten.wohin, gruppe, k)
    const teile = WOHIN_TEILE.map(t => ({
      name: t.name, farbe: t.farbe,
      kg: (w?.[t.feld as keyof typeof w] as number | null) ?? 0,
      hinweis: t.hinweis,
    }))
    const eingang = w?.eingang_kg ?? 0
    const verlust = teile.filter(t => VERLUSTTEILE.has(t.name)).reduce((a, t) => a + t.kg, 0)
    const c = gruppe === 'charge' ? chargen.get(k) : undefined
    const name = gruppe === 'gesamt' ? 'Alle Chargen' : gruppe === 'charge' ? `Charge ${k}` : k
    const untertitel = gruppe === 'charge'
      ? `${c?.sorte ?? ''} · ${c?.schlag ?? ''} · ${tonnen(eingang)} Eingang`
      : `${w?.n_chargen ?? 0} Chargen · ${tonnen(eingang)} Eingang`
    const ziel = gruppe === 'gesamt' ? undefined : gruppe === 'charge' ? `/ursachen?charge=${k}` : `/ursachen?${gruppe}=${encodeURIComponent(k)}`
    return { name, untertitel, bezug: eingang, bezugName: 'am Eingang', teile, ziel,
             rechts: prozent(eingang > 0 ? verlust / eingang : null), verlust: eingang > 0 ? verlust / eingang : 0,
             hervor: gruppe !== 'gesamt' && k === schluessel }
  })
  return zeilen.sort((a, b) => b.verlust - a.verlust)
}

function Wohin({ daten, gruppe, schluessel, oeffnen }: {
  daten: Auswertung; gruppe: Gruppe; schluessel: string; oeffnen: (z: Anteilszeile) => void
}) {
  const zeilen = wohinZeilen(daten, gruppe, schluessel)
  const k = gruppe === 'gesamt' ? '' : schluessel
  const stroeme = stroemeVon(daten.verlust, gruppe, k)
  const eingang = stroeme[0]?.eingang ?? 0
  const echt = ['Schimmel/Fäulnis', 'Verdunstung', 'Faul beim Abpacken (Fax)', 'Nicht lagerbedingt']
  const kanal = ['Zu klein (Tierfutter)', 'Nebenkanal zu gross']
  const rang = echt.map(name => stroeme.find(x => x.strom === name)).filter(Boolean)
    .sort((a, b) => (b!.bekannt ? b!.mittel : -1) - (a!.bekannt ? a!.mittel : -1))
  const groesster = rang.find(x => x!.bekannt)?.strom
  const p0 = prognoseBei(daten.prognose, gruppe, k, 0)
  const name = gruppe === 'gesamt' ? 'alle Chargen' : gruppe === 'charge' ? `Charge ${schluessel}` : schluessel

  const zeile = (x: NonNullable<typeof rang[number]>) => (
    <tr key={x.strom}>
      <td><span className="chip" style={{ background: STROMFARBE[x.strom], marginRight: '.5rem' }} />{STROMKURZ[x.strom] ?? x.strom}
        {x.strom === groesster && <span className="leise"> · grösster Posten</span>}</td>
      <td className="zahl">{x.bekannt ? <strong>{tonnen(x.mittel)}</strong> : <span className="leise">nicht gemessen</span>}</td>
      <td className="zahl">{x.bekannt ? prozent(eingang > 0 ? x.mittel / eingang : null) : '—'}</td>
      <td className="zahl">{x.bekannt && x.bereichBekannt ? <span className="leise">{tonnen(x.unten)}–{tonnen(x.oben)}</span> : <span className="leise">—</span>}</td>
    </tr>
  )

  return (
    <Karte titel="Wohin geht der Kürbis?"
           unter={<>Der ganze Eingang von {name}, in die zehn Teile zerlegt, in die er zerfällt — was draussen ist, und was noch liegt.
             Jede Masse hier ist bis heute <Herkunft art="gerechnet" />, ausser wo eine Prognose danebensteht.</>}>
      <Anteilsbalken zeilen={zeilen} oeffnen={gruppe === 'gesamt' ? undefined : oeffnen} />

      <div className="rollbar" style={{ marginTop: '1rem' }}><table className="dicht">
        <thead><tr><th>Echter Verlust bis heute<Herkunft art="gerechnet" /></th><th className="zahl">Masse</th><th className="zahl">Anteil am Eingang</th><th className="zahl">Bereich</th></tr></thead>
        <tbody>{rang.map(x => zeile(x!))}</tbody>
      </table></div>

      <div className="rollbar" style={{ marginTop: '.75rem' }}><table className="dicht">
        <thead><tr><th>Nicht weg, nur nicht Hauptware<Herkunft art="gerechnet" /></th><th className="zahl">Masse</th><th className="zahl">Anteil am Eingang</th><th className="zahl">Bereich</th></tr></thead>
        <tbody>{kanal.map(n => stroeme.find(x => x.strom === n)).filter(Boolean).map(x => zeile(x!))}</tbody>
      </table></div>

      {p0 && p0.verkaufsfaehig_je_tag_kg !== null && p0.verkaufsfaehig_je_tag_kg > 0 && (
        <p className="fussnote" style={{ marginTop: '.75rem' }}>
          <strong>So geht es weiter:</strong> An der liegenden Ware gehen zurzeit rund <strong>{kg(p0.verkaufsfaehig_je_tag_kg, 0)} je Tag</strong> verkaufsfähige Ware verloren
          {p0.verdunstet_je_tag_kg !== null && p0.faul_je_tag_kg !== null && <> — Verdunstung {kg(p0.verdunstet_je_tag_kg, 0)}, Faules {kg(p0.faul_je_tag_kg, 0)}</>}.
          <Herkunft art="prognose" /> <Link to="/chargen">je Charge ansehen</Link>
        </p>
      )}

      <Erklaerung>
        <p>Der Balken ist der ganze Eingang (100 %). Die kräftigen Farben sind Ware, die den Betrieb verlassen hat; die hellen sind dieselben Ursachen an der Ware, die noch liegt.
        Rechts steht der Anteil <strong>echter Verlust</strong> — verdunstetes Wasser und Faules, draussen wie drinnen. Danach sind die Zeilen sortiert.</p>
        <p><strong>Zu klein und zu gross sind kein Verlust.</strong> Die Ware ist nicht weg, nur nicht in der richtigen Grösse: Sie geht an die Tiere oder in den Nebenkanal.
        Und sie war es vom Feld an — sie wächst nicht mit der Lagerdauer und steht deshalb in der Prognose als flacher Streifen, nicht als steigende Kurve.</p>
        <p><Herkunft art="gemessen" /> heisst: aus einer vollständigen Liste — jede Palette im Erntejournal, jede Lieferung auf einem Lieferschein.{' '}
        <Herkunft art="gerechnet" /> heisst: bis heute, dem {datum(daten.heute)}, aus gemessenen Raten hochgerechnet.</p>
      </Erklaerung>
    </Karte>
  )
}

/* ---------- Noch im Haus --------------------------------------------------- */

interface Gruppenbild {
  name: string; sorte: string; schlag: string; nChargen: number
  eingang: number; geliefert: number; verlust: number | null; lager: number; imHaus: number; verkaufsfaehig: number | null
  alterVon: number | null; alterBis: number | null
}

function gruppenbild(chargen: Bestand[], nach: 'sorte' | 'schlag' | 'charge'): Gruppenbild[] {
  const map = new Map<string, Gruppenbild>()
  for (const c of chargen) {
    const name = nach === 'charge' ? String(c.charge_nr) : nach === 'sorte' ? c.sorte : c.schlag
    let g = map.get(name)
    if (!g) { g = { name, sorte: c.sorte, schlag: c.schlag, nChargen: 0, eingang: 0, geliefert: 0, verlust: 0, lager: 0, imHaus: 0, verkaufsfaehig: 0, alterVon: null, alterBis: null }; map.set(name, g) }
    // 0064: ein unbekannter Verlust bleibt unbekannt — auch in einer Gruppe.
    g.nChargen++; g.eingang += c.eingang_kg; g.geliefert += c.geliefert_kg
    g.verlust = summeBekannt([g.verlust, c.verlust_heute_kg])
    g.lager += c.lager_kg
    g.imHaus += c.im_haus_heute_kg
    // 0066: dasselbe für „davon verkaufsfähig".
    g.verkaufsfaehig = summeBekannt([g.verkaufsfaehig, c.verkaufsfaehig_lager_kg])
    if (c.im_haus_heute_kg > 0 && c.alter_lager_von !== null) g.alterVon = g.alterVon === null ? c.alter_lager_von : Math.min(g.alterVon, c.alter_lager_von)
    if (c.im_haus_heute_kg > 0 && c.alter_lager_bis !== null) g.alterBis = g.alterBis === null ? c.alter_lager_bis : Math.max(g.alterBis, c.alter_lager_bis)
  }
  // Älteste zuerst: Wer am längsten liegt, verliert als nächstes am meisten.
  return [...map.values()].sort((a, b) => (b.alterBis ?? -1) - (a.alterBis ?? -1) || b.lager - a.lager)
}

function ImHaus({ daten, gruppe }: { daten: Auswertung; gruppe: Gruppe }) {
  const s = daten.saison!
  const nach = gruppe === 'gesamt' ? 'sorte' : gruppe
  const gruppen = gruppenbild(daten.bestand, nach)
  const mitBestand = gruppen.filter(g => g.lager > 0)
  return (
    <Karte>
      <Aufklapp titel={<><span>Was ist noch im Haus?</span> <span className="leise">{tonnen(s.lager_kg)} im Lager in {daten.bestand.filter(b => b.lager_kg > 0).length} Chargen · davon verkaufsfähig {tonnen(s.verkaufsfaehig_heute_kg)} · {nach === 'sorte' ? 'je Sorte' : nach === 'schlag' ? 'je Schlag' : 'je Charge'}</span><Herkunft art="gerechnet" /></>}>
        {s.n_lieferungen === 0 && <Hinweis art="info">Ohne eingelesenen Warenausgang liegt rechnerisch noch alles im Haus.</Hinweis>}
        <div className="rollbar"><table>
          <thead><tr>
            <th>{nach === 'sorte' ? 'Sorte' : nach === 'schlag' ? 'Schlag' : 'Charge'}</th>
            <th className="zahl">Im Lager</th><th className="zahl">Verkaufsfähig heute</th>
            <th className="zahl">In 4 Wochen</th><th className="zahl">Liegt seit</th>
            <th className="zahl">Gute Ware</th>
          </tr></thead>
          <tbody>
            {mitBestand.map(g => {
              const heute = anteilBei(daten.prognose, nach, g.name, 0)
              const spaeter = anteilBei(daten.prognose, nach, g.name, 28)
              return (
                <tr key={g.name}>
                  <td>{nach === 'charge' ? <Link to={`/chargen?charge=${g.name}`}>{g.name}</Link> : <strong>{g.name}</strong>}{nach === 'charge' && <span className="leise"> · {g.sorte} · {g.schlag}</span>}{nach !== 'charge' && <span className="leise"> · {g.nChargen} Chargen</span>}</td>
                  <td className="zahl"><strong>{kg(g.lager, 0)}</strong></td>
                  <td className="zahl">{kg(g.verkaufsfaehig, 0)}{heute !== null && <span className="leise"> · {prozent(heute, 0)}</span>}</td>
                  <td className="zahl">{spaeter !== null ? prozent(spaeter, 0) : <span className="leise">—</span>}</td>
                  <td className="zahl">{g.alterVon !== null && g.alterBis !== null ? alterSpanne(g.alterVon, g.alterBis, null) : <span className="leise">—</span>}</td>
                  <td className="zahl"><span className="leise">{kg(g.imHaus, 0)}</span></td>
                </tr>
              )
            })}
            {gruppen.length > mitBestand.length && (
              <tr><td colSpan={6} className="leise">{gruppen.length - mitBestand.length} {nach === 'sorte' ? 'Sorten' : nach === 'schlag' ? 'Schläge' : 'Chargen'} ohne Bestand — alles ausgeliefert.</td></tr>
            )}
          </tbody>
        </table></div>
        {s.ueberzaehlung_kg > 0 && (
          <p className="fussnote">Bei einigen Chargen steckt hinter den Lieferungen mehr Ware, als je eingelagert wurde ({tonnen(s.ueberzaehlung_kg)}) — dort fehlt meist Wareneingang. Sie stehen mit 0 im Lager.</p>
        )}
        <Erklaerung>
          <strong>Im Lager</strong> ist Eingangsware: Eingang <Herkunft art="gemessen" /> minus die Eingangsware hinter den Lieferungen. Sie ändert sich nur durch Liefern.
          <strong> Verkaufsfähig</strong> zieht davon ab, was bis heute verdunstet oder verdorben ist und was zu klein oder zu gross ist <Herkunft art="gerechnet" />;
          <strong> in 4 Wochen</strong> ist dieselbe Rechnung 28 Tage später <Herkunft art="prognose" />.
          <strong> Gute Ware</strong> ist, was nach Verdunstung und Faulem übrig ist — mehr als verkaufsfähig, weil zu klein und zu gross noch drinstecken.
          Sortiert ist nach der ältesten Ware: Wer am längsten liegt, verliert als nächstes am meisten. „Liegt seit" ist eine Spanne über die Eingangstage — es gibt kein Zuerst-rein-zuerst-raus.
        </Erklaerung>
      </Aufklapp>
    </Karte>
  )
}

/* ---------- Die Kaliber-Glocke ----------------------------------------------- */

function Kaliber({ daten }: { daten: Auswertung }) {
  const [nach, setNach] = useState<'sorte' | 'charge'>('sorte')
  const [wahl, setWahl] = useState('')
  const gruppen = useMemo(() => kaliberJe(daten.kaliber, nach), [daten.kaliber, nach])
  if (daten.kaliber.length === 0 || daten.gewichte.length === 0) return null
  const werte = [...new Set(gruppen.map(g => g.schluessel))]
  const aktiv = wahl && werte.includes(wahl) ? wahl : werte[0] ?? ''
  const gruppe = gruppen.find(g => g.schluessel === aktiv)
  const sorte = gruppe?.sorte ?? ''
  const gewichte = daten.gewichte.filter(g => nach === 'sorte' ? g.sorte === aktiv : String(g.charge_nr) === aktiv)
  const breite = 50
  const { stufen, grenzen, gesamt, mittel, klassenfarbe, schema } = glockeVorbereiten(gewichte, daten.schemata, sorte, breite)
  return (
    <Karte titel="Wie gross sind die Kürbisse?" unter={`${zahl(gesamt)} Kürbisse aus der Sortier-CSV, jeder gewogen${mittel !== null ? ` · Schwerpunkt ${Math.round(mittel)} g` : ''}${schema ? ` · Grenzen: Fassung vom ${datum(schema.gilt_ab)}` : ''}`}>
      <div className="filterleiste">
        <Segmente wahl={nach} setzen={n => { setNach(n); setWahl('') }} teile={[['sorte', 'je Sorte'], ['charge', 'je Charge']]} />
        <label htmlFor="kal-wahl">{nach === 'sorte' ? 'Sorte' : 'Charge'}</label>
        <select id="kal-wahl" value={aktiv} onChange={e => setWahl(e.target.value)}>
          {werte.map(w => <option key={w} value={w}>{nach === 'charge' ? `${w} · ${gruppen.find(g => g.schluessel === w)?.sorte ?? ''}` : w}</option>)}
        </select>
      </div>
      <Glocke stufen={stufen} breite={breite} grenzen={grenzen} xFormat={x => `${x}`} klassenfarbe={klassenfarbe} mittel={mittel} hoehe={200} />
      {gruppe && (
        <div className="rollbar">
          <table className="kurz">
            <tbody>
              <tr><th>Kaliber</th>{gruppe.klassen.map(k => <th key={k.name} style={{ color: k.klasse === 'kaliber' ? undefined : 'var(--text-leise)' }}>{k.name}</th>)}</tr>
              <tr><td>Anteil der Stück</td>{gruppe.klassen.map(k => <td key={k.name}><strong>{prozent(gruppe.n > 0 ? k.n / gruppe.n : null, 0)}</strong></td>)}</tr>
              <tr><td>Gewogene Masse</td>{gruppe.klassen.map(k => <td key={k.name}>{kg(k.kg, 0)}</td>)}</tr>
              <tr><td>Stück</td>{gruppe.klassen.map(k => <td key={k.name} className="leise">{zahl(k.n)}</td>)}</tr>
            </tbody>
          </table>
        </div>
      )}
      <Erklaerung titel="Was die Glocke sagt">
        Bezahlt wird je Stück innerhalb eines Kalibers — wer weiss, wo eine Sorte liegt, kann ein engeres Band liefern. Zu klein geht an die Tiere, zu gross in den Nebenkanal. Eine Aussage über den Anbau, nicht über das Lager.
      </Erklaerung>
    </Karte>
  )
}
