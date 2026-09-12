import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import DemoDaten from '../components/DemoDaten'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Aufklapp, Erklaerung, Herkunft, Hinweis, Karte, Kennzahl, Segmente } from '../components/Bausteine'
import { Anteilsbalken, Glocke, Linien, tonnenAchse, type Anteilszeile, type Reihe } from '../components/Diagramm'
import { STROMFARBE, STROMKURZ, alterSpanne, glockeVorbereiten, gruppenSchluessel, kaliberJe, stroemeVon, useAuswertung,
         type Auswertung, type Bestand, type Gruppe } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { summeBekannt } from '../lib/masse'
import { useZaehler } from '../design/bewegung'
import { ZWarnung } from '../components/Zeichen'

const TAG = 86400000
const GRUPPEN: [Gruppe, string][] = [['gesamt', 'Gesamt'], ['sorte', 'je Sorte'], ['schlag', 'je Schlag'], ['charge', 'je Charge']]
/** Die Ursachen im Anteilsbalken, in dieser Reihenfolge: erst der echte Verlust, dann der andere Kanal. */
const URSACHEN = ['Verdunstung', 'Schimmel/Fäulnis', 'Nicht lagerbedingt', 'Faul beim Abpacken (Fax)', 'Zu klein (Tierfutter)', 'Nebenkanal zu gross']
const KANAL = new Set(['Zu klein (Tierfutter)', 'Nebenkanal zu gross'])

/** Eine Tonnenzahl, die beim Erscheinen zu ihrem Wert läuft. */
function Tonnen({ kg }: { kg: number | null | undefined }) {
  const w = useZaehler(kg)
  return <>{tonnen(w)}</>
}

/**
 * Überblick — das Dashboard des Betriebsleiters. Vier Zahlen bis heute (zwei
 * gemessen, zwei gerechnet), der Verlauf, die Ursachen, dann Bestand und
 * Kaliber. Wenig Text: Wie die Zahlen entstehen, steht in den Erklärungen
 * unter jeder Karte — zu, bis man sie will. Nichts hier ist Prognose ausser
 * der gestrichelten Linie im Verlauf und der Zeile „14 Tage länger liegen".
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
  // 0064: Paletten ohne Netto (fehlende Tara, fehlende Kistenzahl) gehen mit dem
  // Mittel der übrigen in den Eingang ein. Solange das vorkommt, ist der Eingang
  // nicht durchweg gemessen — und die Marke darf das nicht behaupten.
  const ohneNetto = daten.bestand.reduce((a, b) => a + (b.n_paletten - b.n_paletten_mit_netto), 0)
  const zeilen = anteilszeilen(daten, gruppe)
  const faules = summeBekannt([s.schimmel_heute_kg, s.sockel_heute_kg])
  const verlustTeile = [
    { name: 'Verdunstung', kg: s.verdunstung_heute_kg, farbe: STROMFARBE['Verdunstung'] },
    { name: 'Faules im Lager', kg: faules, farbe: STROMFARBE['Schimmel/Fäulnis'] },
    { name: 'Faules beim Abpacken', kg: s.fax_heute_kg, farbe: STROMFARBE['Faul beim Abpacken (Fax)'] },
  ]
  const verlustSumme = verlustTeile.reduce((a, t) => a + (t.kg ?? 0), 0)
  const chargenImHaus = daten.bestand.filter(b => b.im_haus_heute_kg > 0).length
  const prognose14 = summeBekannt(daten.naechste.map(n => n.prognose_verlust_14_kg))

  return (
    <>
      <Reiterkopf titel="Überblick" zweck="Was kam herein, was ging hinaus, was ist bis heute verloren — und was liegt noch im Haus."
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

      {/* 1. Vier Zahlen bis heute: zwei gemessen, zwei gerechnet */}
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
        <Kennzahl titel={`Verlust bis ${datum(daten.heute).slice(0, 6)}`} ton="rot"
                  wert={<><Tonnen kg={s.verlust_heute_kg} /><Herkunft art="gerechnet" /></>}
                  unter={<>
                    <strong>{prozent(s.verlust_heute_kg !== null && s.eingang_kg > 0 ? s.verlust_heute_kg / s.eingang_kg : null)} des Eingangs</strong>
                    {s.verlust_unten_kg != null && s.verlust_oben_kg != null && <> · Bereich {tonnen(s.verlust_unten_kg)}–{tonnen(s.verlust_oben_kg)}</>}
                    <span className="mini-anteile" aria-hidden="true">
                      {verlustTeile.filter(t => (t.kg ?? 0) > 0).map(t => <span key={t.name} style={{ width: `${((t.kg ?? 0) / Math.max(verlustSumme, 1)) * 100}%`, background: t.farbe }} />)}
                    </span>
                    {verlustTeile.map(t => t.kg === null ? `${t.name} —` : `${t.name} ${tonnen(t.kg)}`).join(' · ')}
                  </>} />
        <Kennzahl titel="Noch im Haus" ton="gruen"
                  wert={<>{s.verlust_bekannt ? '' : 'höchstens '}<Tonnen kg={s.im_haus_heute_kg} /><Herkunft art="gerechnet" /></>}
                  unter={!s.verlust_bekannt
                    ? <>so viel Eingangsware ist nicht ausgeliefert — wie viel davon verdunstet oder verdorben ist, ist nicht gemessen</>
                    : s.n_lieferungen > 0
                    ? <>in {chargenImHaus} Chargen · davon verkaufsfähig <strong>{tonnen(s.verkaufsfaehig_heute_kg)}</strong> · zu klein oder zu gross {tonnen(s.kanal_im_haus_kg)}</>
                    : 'ohne Warenausgang: rechnerisch alles — abzüglich des Verlusts bis heute'} />
      </div>
      {unbekannt.length > 0 && (
        <Hinweis art="warnung"><strong>Nicht gemessen: {unbekannt.join(', ')}.</strong> Diese Ursache ist unbekannt — nicht null — und fehlt in allen Summen. Unter <Link to="/messungen">Messungen</Link> steht, welche Messung sie liefert.</Hinweis>
      )}

      <div className="zwei-spalten">
        {/* 2. Der Verlauf: gemessen bis heute, dann Prognose */}
        <Verlauf daten={daten} />

        {/* 3. Woran fehlt es — die Ursachen bis heute, mit dem Blick 14 Tage voraus */}
        <Karte titel="Woran fehlt es" unter="Der echte Verlust bis heute nach Ursache, gerechnet aus den Messungen.">
          <div className="rollbar"><table className="dicht">
            <thead><tr><th>Ursache</th><th className="zahl">Verlust bis heute</th><th className="zahl">Anteil am Eingang</th></tr></thead>
            <tbody>
              {verlustTeile.map(t => (
                <tr key={t.name}>
                  <td><span className="chip" style={{ background: t.farbe, marginRight: '.5rem' }} />{t.name}</td>
                  <td className="zahl"><strong>{t.kg === null ? '—' : tonnen(t.kg)}</strong></td>
                  <td className="zahl">{t.kg === null ? <span className="leise">nicht gemessen</span> : prozent(s.eingang_kg > 0 ? t.kg / s.eingang_kg : null)}</td>
                </tr>
              ))}
              <tr>
                <td><strong>Zusammen</strong><Herkunft art="gerechnet" /></td>
                <td className="zahl"><strong>{tonnen(s.verlust_heute_kg)}</strong></td>
                <td className="zahl"><strong>{prozent(s.verlust_heute_kg !== null && s.eingang_kg > 0 ? s.verlust_heute_kg / s.eingang_kg : null)}</strong></td>
              </tr>
            </tbody>
          </table></div>
          <div className="rollbar" style={{ marginTop: '.75rem' }}><table className="dicht">
            <thead><tr><th>Nicht Hauptware</th><th className="zahl">Anderer Kanal</th><th className="zahl">Anteil am Eingang</th></tr></thead>
            <tbody>
              {(['Zu klein (Tierfutter)', 'Nebenkanal zu gross'] as const).map(name => {
                const v = gesamt.find(x => x.strom === name)
                return (
                  <tr key={name}>
                    <td><span className="chip" style={{ background: STROMFARBE[name], marginRight: '.5rem' }} />{STROMKURZ[name]} — {name === 'Zu klein (Tierfutter)' ? 'an die Tiere' : 'in den Nebenkanal'}</td>
                    <td className="zahl">{v?.bekannt ? tonnen(v.mittel) : <span className="leise">nicht gemessen</span>}</td>
                    <td className="zahl">{v?.bekannt ? prozent(s.eingang_kg > 0 ? v.mittel / s.eingang_kg : null) : '—'}</td>
                  </tr>
                )
              })}
            </tbody>
          </table></div>
          {prognose14 !== null && prognose14 > 0 && (
            <div className="rollbar" style={{ marginTop: '.75rem' }}><table className="dicht">
              <tbody>
                <tr>
                  <td>Prognose: zwei Wochen länger liegen<Herkunft art="prognose" /></td>
                  <td className="zahl"><strong>+{tonnen(prognose14)}</strong></td>
                  <td className="zahl"><Link to="/chargen">je Charge</Link></td>
                </tr>
              </tbody>
            </table></div>
          )}
          <Erklaerung>
            <p><Herkunft art="gemessen" /> heisst: aus einer vollständigen Liste — jede Palette im Erntejournal, jede Lieferung auf einem Lieferschein.{' '}
            <Herkunft art="gerechnet" /> heisst: bis heute, dem {datum(daten.heute)}, aus gemessenen Raten hochgerechnet — die Ware im Haus ist genau so lange gealtert, wie sie liegt.</p>
            <p><strong>Verlust</strong> ist, was wirklich weg ist: verdunstetes Wasser und Faules (im Lager, vom Feld, beim Abpacken).
            Zu klein und zu gross sind kein Verlust: Die Ware ist nicht weg, nur nicht in der richtigen Grösse — sie geht an die Tiere oder in den Nebenkanal.
            An der Ware, die noch unsortiert liegt, kommen dazu {tonnen(s.kanal_im_haus_kg)} erwartet; die sind noch nicht passiert und stehen nirgends als Zahl.</p>
            <p><strong>Noch im Haus</strong> ist der Eingang minus die Eingangsware hinter den Lieferungen minus den Verlust der liegenden Ware bis heute.
            <strong> Zwei Wochen länger liegen</strong> ist die einzige Prognose in diesen Zahlen: was 14 weitere Tage Liegen die ganze Ware im Haus kosten würden.</p>
          </Erklaerung>
        </Karte>
      </div>

      {/* 4. Was vom Eingang bis heute fehlt — je Gruppe, alle Balken gleich lang */}
      <Karte titel="Wem fehlt anteilig am meisten?" unter="Jeder Balken ist der Eingang seiner Zeile (100 %); die farbigen Teile sind, was davon bis heute fehlt."
             aktion={<Segmente wahl={gruppe} setzen={setGruppe} teile={GRUPPEN} />}>
        <Anteilsbalken zeilen={zeilen} oeffnen={gruppe === 'gesamt' ? undefined : z => z.ziel && navigate(z.ziel)} />
        <Erklaerung>
          Links der echte Verlust (Verdunstung, Faules), rechts davon der andere Kanal (zu klein, zu gross — nicht weg, nur nicht Hauptware).
          Rechts steht der Anteil zusammen. So sieht man, wem anteilig am meisten fehlt — nicht, wer am grössten ist.
          Zeigen auf einen Teil nennt Prozent und Tonnen{gruppe !== 'gesamt' ? '; ein Klick öffnet die Ursachen der Zeile' : ''}.
        </Erklaerung>
      </Karte>

      {/* 5. Noch im Haus — aufklappbar, nach derselben Wahl */}
      <ImHaus daten={daten} gruppe={gruppe} />

      {/* 6. Kaliber: die Glocke je Sorte oder Charge */}
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
  // Die Achse endet immer beim letzten Punkt — sonst fehlte ein Stück Prognose.
  // Gepolstert wird links, vor dem ersten Eingang: dort ist ohnehin nichts.
  const xBis = xLetzte
  const xVon = Math.min(xErste, 2 * heute - xLetzte)
  const reihen: Reihe[] = [
    { name: 'Eingang kumuliert', farbe: 'var(--strom-verdunstung)', linie: true, marker: false, flaeche: true,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: w.eingang_kum_kg })) },
    { name: 'Ausgeliefert kumuliert', farbe: 'var(--strom-rest)', linie: true, marker: false, flaeche: true,
      punkte: bisHeute.map(w => ({ x: x(w.bis), y: w.ausgang_kum_kg })) },
    { name: 'Verlust — bis heute, dann Prognose', farbe: 'var(--strom-schimmel)', linie: true, marker: false, prognoseAb: heute, dick: true,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.verlust_kum_kg,
        text: `Verdunstung ${tonnen(w.verdunstung_kum_kg)} · Faules im Lager ${tonnen(w.schimmel_kum_kg)} · nicht lagerbedingt ${tonnen(w.sockel_kum_kg)} · Faules beim Abpacken ${tonnen(w.fax_kum_kg)}` })) },
    { name: 'Noch im Haus — bis heute, dann Prognose', farbe: 'var(--text-leise)', linie: true, marker: false, prognoseAb: heute, ausgeblendet: true,
      punkte: wochen.map(w => ({ x: x(w.bis), y: w.im_haus_kg })) },
  ]
  return (
    <Karte titel="Die Saison im Verlauf" unter="Kumuliert je Woche: was hereinkam, was hinausging, was verloren ist — und wie es weiterginge.">
      <Linien reihen={reihen} heute={{ x: heute, text: `heute, ${datum(daten.heute).slice(0, 6)}` }}
              xVon={xVon} xBis={xBis} hoehe={300}
              xFormat={d => datum(new Date(d * TAG)).slice(0, 5)} yFormat={tonnenAchse} xTitel="Woche" yTitel="Tonnen, kumuliert" />
      <Erklaerung>
        Eingang (Erntejournal) und Ausgeliefert (Lieferscheine) sind <Herkunft art="gemessen" /> und enden heute.
        Der Verlust ist <Herkunft art="gerechnet" /> bis heute und läuft danach als <Herkunft art="prognose" /> gestrichelt weiter:
        die Ware im Haus altert bis zum Saisonende, nichts Neues kommt herein, nichts geht hinaus — das weiss niemand.
        Zeigen auf eine Woche nennt alle Linien; die Legende blendet Linien aus; ein gezogener Rahmen vergrössert.
      </Erklaerung>
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
    const untertitel = gruppe === 'charge' ? `${c?.sorte ?? ''} · ${c?.schlag ?? ''} · ${tonnen(eingang)} Eingang` : `${nChargen} Chargen · ${tonnen(eingang)} Eingang`
    const ziel = gruppe === 'gesamt' ? undefined : gruppe === 'charge' ? `/ursachen?charge=${k}` : `/ursachen?${gruppe}=${encodeURIComponent(k)}`
    return { name, untertitel, bezug: eingang, bezugName: 'am Eingang', teile, ziel }
  })
  const anteil = (z: Anteilszeile) => z.bezug > 0 ? z.teile.reduce((a, t) => a + t.kg, 0) / z.bezug : 0
  return zeilen.sort((a, b) => anteil(b) - anteil(a))
}

/* ---------- Noch im Haus --------------------------------------------------- */

interface Gruppenbild {
  name: string; sorte: string; schlag: string; nChargen: number
  eingang: number; geliefert: number; verlust: number | null; imHaus: number; verkaufsfaehig: number | null
  alterVon: number | null; alterBis: number | null
}

function gruppenbild(chargen: Bestand[], nach: 'sorte' | 'schlag' | 'charge'): Gruppenbild[] {
  const map = new Map<string, Gruppenbild>()
  for (const c of chargen) {
    const name = nach === 'charge' ? String(c.charge_nr) : nach === 'sorte' ? c.sorte : c.schlag
    let g = map.get(name)
    if (!g) { g = { name, sorte: c.sorte, schlag: c.schlag, nChargen: 0, eingang: 0, geliefert: 0, verlust: 0, imHaus: 0, verkaufsfaehig: 0, alterVon: null, alterBis: null }; map.set(name, g) }
    // 0064: ein unbekannter Verlust bleibt unbekannt — auch in einer Gruppe.
    g.nChargen++; g.eingang += c.eingang_kg; g.geliefert += c.geliefert_kg
    g.verlust = summeBekannt([g.verlust, c.verlust_heute_kg])
    g.imHaus += c.im_haus_heute_kg
    // 0066: dasselbe für „davon verkaufsfähig".
    g.verkaufsfaehig = summeBekannt([g.verkaufsfaehig, c.verkaufsfaehig_lager_kg])
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
      <Aufklapp titel={<><span>Was ist noch im Haus?</span> <span className="leise">{tonnen(s.im_haus_heute_kg)} in {daten.bestand.filter(b => b.im_haus_heute_kg > 0).length} Chargen · davon verkaufsfähig {tonnen(s.verkaufsfaehig_heute_kg)} · {nach === 'sorte' ? 'je Sorte' : nach === 'schlag' ? 'je Schlag' : 'je Charge'}</span><Herkunft art="gerechnet" /></>}>
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
                <td>{nach === 'charge' ? <Link to={`/chargen?charge=${g.name}`}>{g.name}</Link> : <strong>{g.name}</strong>}{nach === 'charge' && <span className="leise"> · {g.sorte} · {g.schlag}</span>}{nach !== 'charge' && <span className="leise"> · {g.nChargen} Chargen</span>}</td>
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
        {s.ueberzaehlung_kg > 0 && (
          <p className="fussnote">Bei einigen Chargen steckt hinter den Lieferungen mehr Ware, als je eingelagert wurde ({tonnen(s.ueberzaehlung_kg)}) — dort fehlt meist Wareneingang. Sie stehen mit 0 im Haus.</p>
        )}
        <Erklaerung>
          Je Charge: Eingang <Herkunft art="gemessen" /> minus die Eingangsware hinter den Lieferungen <Herkunft art="gemessen" />, minus Verdunstung und Faules der liegenden Ware bis heute <Herkunft art="gerechnet" />.
          „Verkaufsfähig" zieht davon noch ab, was zu klein oder zu gross ist. „Liegt seit" ist eine Spanne über die Eingangstage — es gibt kein Zuerst-rein-zuerst-raus, und die App weiss nicht, welche Palette gegangen ist.
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
