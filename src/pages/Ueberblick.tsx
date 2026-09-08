import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import DemoDaten from '../components/DemoDaten'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Aufklapp, Herkunft, Hinweis, Karte, Kennzahl } from '../components/Bausteine'
import { Anteilsbalken, Glocke, Linien, tonnenAchse, type Anteilszeile, type Reihe } from '../components/Diagramm'
import { STROMFARBE, STROMKURZ, alterSpanne, gruppenSchluessel, kaliberJe, stroemeVon, useAuswertung,
         type Auswertung, type Bestand, type Gruppe, type StromSumme } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'

const TAG = 86400000
const GRUPPEN: [Gruppe, string][] = [['gesamt', 'Gesamt'], ['sorte', 'je Sorte'], ['schlag', 'je Schlag'], ['charge', 'je Charge']]
/** Die Ursachen im Anteilsbalken, in dieser Reihenfolge: erst der echte Verlust, dann der andere Kanal. */
const URSACHEN = ['Verdunstung', 'Schimmel/Fäulnis', 'Nicht lagerbedingt', 'Faul beim Abpacken (Fax)', 'Zu klein (Tierfutter)', 'Nebenkanal zu gross']
const KANAL = new Set(['Zu klein (Tierfutter)', 'Nebenkanal zu gross'])

/**
 * Überblick: was der Betriebsleiter heute sicher wissen kann. Zwei Zahlen
 * sind gemessen (Eingang ab Erntejournal, ausgeliefert ab Lieferschein), zwei
 * sind bis heute gerechnet (Verlust, noch im Haus) — und das steht an jeder
 * Zahl. Nichts hier ist Prognose; die steht als gestrichelte Linie im
 * Verlauf, und nur dort.
 */
export default function Ueberblick() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const [gruppe, setGruppe] = useState<Gruppe>('gesamt')
  const navigate = useNavigate()

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const s = daten.saison
  if (!s || daten.bestand.length === 0) {
    return (
      <>
        <Reiterkopf titel="Überblick" zweck="Was kam herein, was ging hinaus, was ist bis heute verloren — und was liegt noch im Haus." stand={daten.stand} />
        <Probleme liste={daten.probleme} />
        <Hinweis>Noch keine auswertbaren Daten. Dafür braucht es mindestens Eingangspaletten mit hinterlegter Tara — siehe Betrieb → Stammdaten.</Hinweis>
        <DemoDaten kompakt nachAenderung={() => void neuRechnen()} />
      </>
    )
  }

  const gesamt = stroemeVon(daten.verlust, 'gesamt')
  const unbekannt = gesamt.filter(x => !x.bekannt && x.buch !== 'bilanz').map(x => STROMKURZ[x.strom] ?? x.strom)
  const paletten = daten.bestand.reduce((a, b) => a + b.n_paletten, 0)
  const kanalAusgelagert = s.kanal_heute_kg - s.kanal_im_haus_kg
  const zeilen = anteilszeilen(daten, gruppe)

  return (
    <>
      <Reiterkopf titel="Überblick" zweck="Was kam herein, was ging hinaus, was ist bis heute verloren — und was liegt noch im Haus."
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} />
      <Probleme liste={daten.probleme} />

      {/* 1. Vier Zahlen bis heute: zwei gemessen, zwei gerechnet */}
      <Karte>
        <div className="spalten">
          <Kennzahl titel="Eingang" wert={<>{tonnen(s.eingang_kg)} <Herkunft art="gemessen" /></>}
                    unter={`${zahl(paletten)} Paletten in ${s.n_chargen} Chargen, ab Erntejournal`} />
          <Kennzahl titel="Ausgeliefert" wert={s.n_lieferungen > 0 || s.vorlauf_kg > 0 ? <>{tonnen(s.ausgang_kg)} <Herkunft art="gemessen" /></> : '—'}
                    unter={s.n_lieferungen > 0 || s.vorlauf_kg > 0
                      ? <>{zahl(s.n_lieferungen)} Lieferungen ab Lieferschein{s.marge_kg > 0 ? `, davon ${tonnen(s.marge_kg)} an Tiere und Nebenkanal` : ''}{s.vorlauf_kg > 0 ? `, ${tonnen(s.vorlauf_kg)} vor dem Erfassungsbeginn` : ''}</>
                      : <>noch kein Warenausgang eingelesen — <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link></>} />
          <Kennzahl titel={`Verlust bis ${datum(daten.heute).slice(0, 6)}`} wert={<>{tonnen(s.verlust_heute_kg)} <Herkunft art="gerechnet" /></>}
                    unter={<>{prozent(s.eingang_kg > 0 ? s.verlust_heute_kg / s.eingang_kg : null)} des Eingangs
                      {s.verlust_unten_kg != null && s.verlust_oben_kg != null && <> · Bereich {tonnen(s.verlust_unten_kg)}–{tonnen(s.verlust_oben_kg)}</>}
                      <br />Verdunstung {tonnen(s.verdunstung_heute_kg)} · Faules {tonnen(s.schimmel_heute_kg + s.sockel_heute_kg)} · beim Abpacken {tonnen(s.fax_heute_kg)}</>} />
          <Kennzahl titel="Noch im Haus" wert={<>{tonnen(s.im_haus_heute_kg)} <Herkunft art="gerechnet" /></>}
                    unter={s.n_lieferungen > 0
                      ? <>davon verkaufsfähig {tonnen(s.verkaufsfaehig_heute_kg)}, zu klein oder zu gross {tonnen(s.kanal_im_haus_kg)}</>
                      : 'ohne Warenausgang: rechnerisch alles — abzüglich des Verlusts bis heute'} />
        </div>
        <p className="leise" style={{ margin: '.7rem 0 0' }}>
          <Herkunft art="gemessen" /> heisst: aus einer vollständigen Liste — jede Palette im Erntejournal, jede Lieferung auf einem Lieferschein.{' '}
          <Herkunft art="gerechnet" /> heisst: bis heute, dem {datum(daten.heute)}, aus gemessenen Raten hochgerechnet — die Ware im Haus ist genau so lange gealtert, wie sie liegt, keinen Tag länger.{' '}
          <strong>Verlust</strong> ist, was wirklich weg ist: verdunstetes Wasser und Faules (im Lager, vom Feld, beim Abpacken).
          Dazu gehen {tonnen(s.kanal_heute_kg)} als zu klein oder zu gross in einen anderen Kanal — die Ware ist da, nur nicht in der richtigen Grösse; {tonnen(kanalAusgelagert)} davon stecken hinter den Lieferungen, der Rest liegt noch im Haus.{' '}
          <strong>Noch im Haus</strong> ist der Eingang minus die Eingangsware hinter den Lieferungen (verkauft, dazu ihr Verlust und ihr Kanal) minus den Verlust der liegenden Ware bis heute.
          Was die Ware bis zum Saisonende noch verliert, steht unten als Prognose — nirgends sonst.
        </p>
        {unbekannt.length > 0 && (
          <Hinweis art="warnung"><strong>Nicht gemessen: {unbekannt.join(', ')}.</strong> Diese Ursache ist unbekannt — nicht null — und fehlt in allen Summen. Unter <Link to="/messungen">Messungen</Link> steht, welche Messung sie liefert.</Hinweis>
        )}
      </Karte>

      {/* 2. Der Verlauf: gemessen bis heute, dann Prognose */}
      <Verlauf daten={daten} />

      {/* 3. Was vom Eingang bis heute fehlt — je Gruppe, alle Balken gleich lang */}
      <Karte titel="Was vom Eingang bis heute fehlt — und woran">
        <div className="reihe" style={{ gap: '.4rem', flexWrap: 'wrap', marginBottom: '.6rem' }}>
          <div className="umschalter" role="tablist" style={{ margin: 0 }}>
            {GRUPPEN.map(([g, name]) => (
              <button key={g} role="tab" aria-selected={gruppe === g} className={gruppe === g ? 'aktiv' : ''} onClick={() => setGruppe(g)}>{name}</button>
            ))}
          </div>
        </div>
        <p className="leise">
          Jeder Balken ist der Eingang seiner Zeile (100 %). Die farbigen Teile sind, was davon bis heute fehlt: links der echte Verlust (Verdunstung, Faules), rechts davon der andere Kanal (zu klein, zu gross — nicht weg, nur nicht Hauptware).
          Rechts steht der Anteil zusammen. So sieht man, wem anteilig am meisten fehlt — nicht, wer am grössten ist. Zeigen auf einen Teil nennt Prozent und Tonnen{gruppe !== 'gesamt' ? ', ein Klick öffnet die Ursachen der Zeile' : ''}.
        </p>
        <Anteilsbalken zeilen={zeilen} oeffnen={gruppe === 'gesamt' ? undefined : z => z.ziel && navigate(z.ziel)} />
      </Karte>

      {/* 4. Noch im Haus — aufklappbar, nach derselben Wahl */}
      <ImHaus daten={daten} gruppe={gruppe} />

      {/* 5. Kaliber: die Glocke je Sorte oder Charge */}
      <Kaliber daten={daten} />
    </>
  )
}

/* ---------- Der Verlauf --------------------------------------------------- */

function Verlauf({ daten }: { daten: Auswertung }) {
  const wochen = daten.verlauf.filter(w => w.sorte === null)
  if (wochen.length < 2) return null
  const x = (d: string) => Date.parse(d) / TAG
  const heute = x(daten.heute)
  const bisHeute = wochen.filter(w => !w.prognose)
  const xErste = x(wochen[0].woche), xLetzte = x(wochen[wochen.length - 1].bis)
  // Heute in der Mitte der Achse — mindestens bis zum Ende der Prognose.
  const xBis = Math.max(xLetzte, 2 * heute - xErste)
  const reihen: Reihe[] = [
    { name: 'Eingang', farbe: 'var(--strom-verdunstung)', linie: true, marker: false,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: w.eingang_kum_kg })) },
    { name: 'Ausgang', farbe: 'var(--strom-rest)', linie: true, marker: false,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: w.ausgang_kum_kg })) },
    { name: 'Verlust', farbe: 'var(--strom-schimmel)', linie: true, marker: false, prognoseAb: heute,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.verlust_kum_kg,
        text: `Verdunstung ${tonnen(w.verdunstung_kum_kg)} · Faules ${tonnen(w.faul_kum_kg)} · beim Abpacken ${tonnen(w.fax_kum_kg)}` })) },
    { name: 'Noch im Haus', farbe: 'var(--text-leise)', linie: true, marker: false, prognoseAb: heute, ausgeblendet: true,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.im_haus_kg })) },
  ]
  return (
    <Karte titel="Die Saison im Verlauf">
      <p className="leise">
        Kumuliert je Woche: was hereinkam (Erntejournal) und hinausging (Lieferscheine) — <Herkunft art="gemessen" />, beide enden heute.
        Der Verlust ist <Herkunft art="gerechnet" /> bis heute und läuft danach als <Herkunft art="prognose" /> gestrichelt weiter: die Ware im Haus altert bis zum Saisonende, nichts Neues kommt herein, nichts geht hinaus — das weiss niemand.
        Zeigen auf eine Woche nennt alle Linien; die Legende blendet Linien aus; ein gezogener Rahmen vergrössert.
      </p>
      <Linien reihen={reihen} heute={{ x: heute, text: `heute, ${datum(daten.heute).slice(0, 6)}` }}
              xVon={xErste} xBis={xBis} hoehe={300}
              xFormat={d => datum(new Date(d * TAG)).slice(0, 5)} yFormat={tonnenAchse} xTitel="Woche" yTitel="Tonnen, kumuliert" />
    </Karte>
  )
}

/* ---------- Die Anteile je Gruppe ------------------------------------------ */

function anteilszeilen(daten: Auswertung, gruppe: Gruppe): Anteilszeile[] {
  const schluessel = gruppe === 'gesamt' ? [''] : gruppenSchluessel(daten.verlust, gruppe)
  const chargen = new Map(daten.bestand.map(b => [String(b.charge_nr), b]))
  const zeilen = schluessel.map(k => {
    const stroeme = stroemeVon(daten.verlust, gruppe, k)
    const eingang = stroeme[0]?.eingang ?? 0
    const nChargen = stroeme[0]?.nChargen ?? 0
    const teil = (name: string) => stroeme.find(x => x.strom === name)
    const teile = URSACHEN.map(u => {
      const v = teil(u)
      return { name: STROMKURZ[u] ?? u, kg: v?.bekannt ? v.mittel : 0, farbe: STROMFARBE[u] ?? 'var(--text-leise)',
               hinweis: !v?.bekannt ? 'nicht gemessen — unbekannt, nicht null' : KANAL.has(u) ? 'kein echter Verlust: die Ware geht in einen anderen Kanal' : v.bereichBekannt ? `Bereich ${tonnen(v.unten)}–${tonnen(v.oben)}` : undefined }
    })
    const c = gruppe === 'charge' ? chargen.get(k) : undefined
    const name = gruppe === 'gesamt' ? 'Alle Chargen' : gruppe === 'charge' ? `Charge ${k}` : k
    const untertitel = gruppe === 'charge' ? `${c?.sorte ?? ''} · ${c?.schlag ?? ''} · ${tonnen(eingang)}` : `${nChargen} Chargen · ${tonnen(eingang)} Eingang`
    const ziel = gruppe === 'gesamt' ? undefined : gruppe === 'charge' ? `/ursachen?charge=${k}` : `/ursachen?${gruppe}=${encodeURIComponent(k)}`
    return { name, untertitel, bezug: eingang, teile, ziel }
  })
  const anteil = (z: Anteilszeile) => z.bezug > 0 ? z.teile.reduce((a, t) => a + t.kg, 0) / z.bezug : 0
  return zeilen.sort((a, b) => anteil(b) - anteil(a))
}

/* ---------- Noch im Haus --------------------------------------------------- */

interface Gruppenbild {
  name: string; sorte: string; schlag: string; nChargen: number
  eingang: number; geliefert: number; verlust: number; imHaus: number; verkaufsfaehig: number
  alterVon: number | null; alterBis: number | null
}

function gruppenbild(chargen: Bestand[], nach: 'sorte' | 'schlag' | 'charge'): Gruppenbild[] {
  const map = new Map<string, Gruppenbild>()
  for (const c of chargen) {
    const name = nach === 'charge' ? String(c.charge_nr) : nach === 'sorte' ? c.sorte : c.schlag
    let g = map.get(name)
    if (!g) { g = { name, sorte: c.sorte, schlag: c.schlag, nChargen: 0, eingang: 0, geliefert: 0, verlust: 0, imHaus: 0, verkaufsfaehig: 0, alterVon: null, alterBis: null }; map.set(name, g) }
    g.nChargen++; g.eingang += c.eingang_kg; g.geliefert += c.geliefert_kg; g.verlust += c.verlust_heute_kg
    g.imHaus += c.im_haus_heute_kg; g.verkaufsfaehig += c.verkaufsfaehig_lager_kg ?? 0
    if (c.im_haus_heute_kg > 0 && c.alter_lager_von !== null) g.alterVon = g.alterVon === null ? c.alter_lager_von : Math.min(g.alterVon, c.alter_lager_von)
    if (c.im_haus_heute_kg > 0 && c.alter_lager_bis !== null) g.alterBis = g.alterBis === null ? c.alter_lager_bis : Math.max(g.alterBis, c.alter_lager_bis)
  }
  return [...map.values()].sort((a, b) => b.imHaus - a.imHaus)
}

function ImHaus({ daten, gruppe }: { daten: Auswertung; gruppe: Gruppe }) {
  const s = daten.saison!
  const nach = gruppe === 'gesamt' ? 'sorte' : gruppe
  const gruppen = gruppenbild(daten.bestand, nach)
  const mitBestand = gruppen.filter(g => g.imHaus > 0)
  return (
    <Karte>
      <Aufklapp titel={<>Was ist noch im Haus? <span className="leise">{tonnen(s.im_haus_heute_kg)} in {daten.bestand.filter(b => b.im_haus_heute_kg > 0).length} Chargen, davon verkaufsfähig {tonnen(s.verkaufsfaehig_heute_kg)} — {nach === 'sorte' ? 'je Sorte' : nach === 'schlag' ? 'je Schlag' : 'je Charge'}</span></>}>
        <p className="leise" style={{ marginTop: '.4rem' }}>
          Je Charge: Eingang <Herkunft art="gemessen" /> minus die Eingangsware hinter den Lieferungen <Herkunft art="gemessen" />, minus Verdunstung und Faules der liegenden Ware bis heute <Herkunft art="gerechnet" />.
          „Verkaufsfähig" zieht davon noch ab, was zu klein oder zu gross ist. „Liegt seit" ist eine Spanne über die Eingangstage — es gibt kein Zuerst-rein-zuerst-raus, und die App weiss nicht, welche Palette gegangen ist.
        </p>
        {s.n_lieferungen === 0 && <Hinweis art="info">Ohne eingelesenen Warenausgang liegt rechnerisch noch alles im Haus.</Hinweis>}
        <div className="rollbar"><table>
          <thead><tr>
            <th>{nach === 'sorte' ? 'Sorte' : nach === 'schlag' ? 'Schlag' : 'Charge'}</th>
            <th className="zahl">Eingang</th><th className="zahl">Ausgeliefert</th>
            <th className="zahl">Verlust bis heute</th>
            <th className="zahl">Noch im Haus</th><th className="zahl">davon verkaufsfähig</th><th className="zahl">Liegt seit</th>
          </tr></thead>
          <tbody>
            {mitBestand.map(g => (
              <tr key={g.name}>
                <td>{nach === 'charge' ? <Link to={`/chargen?charge=${g.name}`}>{g.name}</Link> : g.name}{nach === 'charge' && <span className="leise"> · {g.sorte} · {g.schlag}</span>}{nach !== 'charge' && <span className="leise"> · {g.nChargen} Chargen</span>}</td>
                <td className="zahl">{kg(g.eingang, 0)}</td>
                <td className="zahl">{s.n_lieferungen > 0 ? kg(g.geliefert, 0) : <span className="leise">—</span>}</td>
                <td className="zahl">{kg(g.verlust, 0)}</td>
                <td className="zahl"><strong>{kg(g.imHaus, 0)}</strong></td>
                <td className="zahl">{kg(g.verkaufsfaehig, 0)}</td>
                <td className="zahl">{g.alterVon !== null && g.alterBis !== null ? alterSpanne(g.alterVon, g.alterBis, null) : <span className="leise">—</span>}</td>
              </tr>
            ))}
            {gruppen.length > mitBestand.length && (
              <tr><td colSpan={7} className="leise">{gruppen.length - mitBestand.length} {nach === 'sorte' ? 'Sorten' : nach === 'schlag' ? 'Schläge' : 'Chargen'} ohne Bestand — alles ausgeliefert.</td></tr>
            )}
          </tbody>
        </table></div>
        {(s.ueberzaehlung_kg ?? 0) > 0 && (
          <p className="leise" style={{ margin: '.4rem 0 0' }}>
            Bei einigen Chargen steckt hinter den Lieferungen mehr Ware, als je eingelagert wurde ({tonnen(s.ueberzaehlung_kg)}) — dort fehlt meist Wareneingang. Sie stehen mit 0 im Haus.
          </p>
        )}
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
  const stufenMap = new Map<number, number>()
  for (const g of gewichte) { const x = Math.floor(g.stufe_g / breite) * breite; stufenMap.set(x, (stufenMap.get(x) ?? 0) + g.n) }
  const stufen = [...stufenMap.entries()].map(([x, n]) => ({ x, n })).sort((a, b) => a.x - b.x)
  const schema = daten.schemata.find(s => s.sorte === sorte && s.art === 'kaliber' && s.kaeufer === null)
    ?? daten.schemata.find(s => s.sorte === sorte && s.art === 'kaliber')
  const grenzen: { x: number; text: string }[] = []
  if (schema?.verlust_unter != null) grenzen.push({ x: schema.verlust_unter, text: 'zu klein <' })
  ;(schema?.kaliber_baender ?? []).forEach(([a], i) => { if (i > 0) grenzen.push({ x: a, text: `K${i + 1}` }) })
  if (schema?.kanal_ab != null) grenzen.push({ x: schema.kanal_ab, text: 'zu gross ≥' })
  const gesamt = gewichte.reduce((a, g) => a + g.n, 0)
  const mittel = gesamt > 0 ? gewichte.reduce((a, g) => a + (g.stufe_g + 12.5) * g.n, 0) / gesamt : null
  const klassenfarbe = (x: number) => schema?.verlust_unter != null && x + breite <= schema.verlust_unter ? 'var(--strom-ausschuss)'
    : schema?.kanal_ab != null && x >= schema.kanal_ab ? 'var(--strom-nebenkanal)' : 'var(--kuerbis)'
  return (
    <Karte titel="Wie gross sind die Kürbisse?">
      <div className="filterleiste">
        <div className="umschalter" role="tablist" style={{ margin: 0, minWidth: 180 }}>
          <button role="tab" aria-selected={nach === 'sorte'} className={nach === 'sorte' ? 'aktiv' : ''} onClick={() => { setNach('sorte'); setWahl('') }}>je Sorte</button>
          <button role="tab" aria-selected={nach === 'charge'} className={nach === 'charge' ? 'aktiv' : ''} onClick={() => { setNach('charge'); setWahl('') }}>je Charge</button>
        </div>
        <label htmlFor="kal-wahl" style={{ margin: 0 }}>{nach === 'sorte' ? 'Sorte' : 'Charge'}</label>
        <select id="kal-wahl" value={aktiv} onChange={e => setWahl(e.target.value)}>
          {werte.map(w => <option key={w} value={w}>{nach === 'charge' ? `${w} · ${gruppen.find(g => g.schluessel === w)?.sorte ?? ''}` : w}</option>)}
        </select>
        <span>{zahl(gesamt)} Kürbisse aus der Sortier-CSV, jeder gewogen{mittel !== null ? ` · Schwerpunkt ${Math.round(mittel)} g` : ''}{schema ? ` · Grenzen: Fassung vom ${datum(schema.gilt_ab)}` : ''}</span>
      </div>
      <Glocke stufen={stufen} breite={breite} grenzen={grenzen} xFormat={x => `${x}`} klassenfarbe={klassenfarbe} mittel={mittel} hoehe={200} />
      {gruppe && (
        <div className="rollbar">
          <table className="kurz">
            <tbody>
              <tr><th>Kaliber</th>{gruppe.klassen.map(k => <th key={k.name} style={{ color: k.klasse === 'kaliber' ? undefined : 'var(--text-leise)' }}>{k.klasse === 'kaliber' ? k.name : k.name}</th>)}</tr>
              <tr><td>Anteil</td>{gruppe.klassen.map(k => <td key={k.name}><strong>{prozent(gruppe.n > 0 ? k.n / gruppe.n : null, 0)}</strong></td>)}</tr>
              <tr><td>Masse</td>{gruppe.klassen.map(k => <td key={k.name}>{kg(k.kg, 0)}</td>)}</tr>
              <tr><td>Stück</td>{gruppe.klassen.map(k => <td key={k.name} className="leise">{zahl(k.n)}</td>)}</tr>
            </tbody>
          </table>
        </div>
      )}
      <p className="leise" style={{ margin: '.5rem 0 0' }}>
        Bezahlt wird je Stück innerhalb eines Kalibers — wer weiss, wo eine Sorte liegt, kann ein engeres Band liefern. Zu klein geht an die Tiere, zu gross in den Nebenkanal. Eine Aussage über den Anbau, nicht über das Lager.
      </p>
    </Karte>
  )
}

// Für Erweiterungen erreichbar; im Überblick selbst nicht mehr gebraucht.
void ((x: StromSumme) => x)
