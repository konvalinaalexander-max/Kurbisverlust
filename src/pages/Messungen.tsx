import { useState, type ReactNode } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { datum, kg, prozent, zahl } from '../lib/format'
import { Aufklapp, Erklaerung, Herkunft, Hinweis, Karte, Marke } from '../components/Bausteine'
import { Linien } from '../components/Diagramm'
import { achsenBereich } from '../lib/achse'
import { hochrechnungLaden, useAuswertung, type Auswertung, type Datenqualitaet } from '../auswertung/daten'
import { Bilanz, Kurvenherkunft, Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { AuffaelligkeitFaelle, offeneZahl, useVermerke } from '../auswertung/AuffaelligkeitFaelle'
import { Kontrollkorrektur } from '../arbeit/Korrektur'
import { STATION_NAME } from '../lib/format'
import { ZHerunterladen, ZWarnung } from '../components/Zeichen'
import Arbeiten from '../betrieb/Arbeiten'
import { AusstehendInhalt } from './Ausstehend'

const TAG = 86400000

/*
 * Messungen — seit Runde AO (12. Oktober) mit vier Reitern: Arbeiten (bis
 * dahin unter Betrieb), Auffälligkeiten, Messwerte (alles, was bisher unter
 * den Auffälligkeiten stand) und Ausstehend (bis dahin ein eigener Reiter
 * rechts vom Betrieb). Der Betrieb: „innerhalb von Messungen erster Reiter
 * Arbeiten, zweiter Reiter Auffälligkeiten, dritter Reiter dort die ganzen
 * Informationen, die du dort noch hast". Keine Untertitel.
 */
type Teil = 'arbeiten' | 'auffaelligkeiten' | 'messwerte' | 'ausstehend'
const TEILE: [Teil, string][] = [
  ['arbeiten', 'Arbeiten'],
  ['auffaelligkeiten', 'Auffälligkeiten'],
  ['messwerte', 'Messwerte'],
  ['ausstehend', 'Ausstehend'],
]

export default function Messungen() {
  const { teil } = useParams()
  const navigate = useNavigate()
  const aktiv = (TEILE.find(([t]) => t === teil)?.[0] ?? 'arbeiten') as Teil
  const a = useAuswertung()
  const { daten } = a
  // Runde BG: die Zahl am Reiter sind die offenen Auffälligkeiten — was „so lassen" oder korrigiert ist, zählt nicht mehr.
  const auff = useVermerke()
  const offen = daten?.vollstaendig ? offeneZahl(daten.befunde, auff.vermerke) : 0
  return (
    <>
      {daten
        ? <Reiterkopf titel="Messungen" stand={daten.stand} heute={daten.heute} neuRechnen={() => void a.neuRechnen()} laeuft={a.laedt}
                      zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
        : <div className="seitenkopf"><div><h1>Messungen</h1></div></div>}
      <nav className="navleiste unter" aria-label="Messungen">
        {TEILE.map(([t, name]) => (
          <a key={t} href={`/messungen/${t}`} className={aktiv === t ? 'aktiv' : ''}
             onClick={e => { e.preventDefault(); navigate(`/messungen/${t}`) }}>
            {name}{t === 'auffaelligkeiten' && offen > 0 && <span className="reiter-zahl">{offen}</span>}
          </a>
        ))}
      </nav>
      <div className="wechsel" key={aktiv}>
        {aktiv === 'arbeiten' && <Arbeiten />}
        {aktiv === 'auffaelligkeiten' && <MitAuswertung a={a}>{d => <AuffaelligkeitFaelle befunde={d.befunde} neuRechnen={() => void a.neuRechnen()} wissen={auff} />}</MitAuswertung>}
        {aktiv === 'messwerte' && <MitAuswertung a={a}>{d => <Messwerte daten={d} />}</MitAuswertung>}
        {aktiv === 'ausstehend' && <MitAuswertung a={a}>{d => <AusstehendInhalt daten={d} />}</MitAuswertung>}
      </div>
    </>
  )
}

/** Die Reiter, die die Ergebnisse brauchen: warten, bis die zweite Welle da ist. */
function MitAuswertung({ a, children }: { a: ReturnType<typeof useAuswertung>; children: (d: Auswertung) => ReactNode }) {
  const { daten, laedt, fehler, fortschritt } = a
  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  // Runde AJ: die zweite Welle der Ergebnisse (diese Reiter brauchen sie) kommt nach dem Lagermanagement.
  if (daten && !daten.vollstaendig) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  return <><Probleme liste={daten.probleme} />{children(daten)}</>
}

/** Alles, was bis Runde AN unter den Auffälligkeiten stand. */
function Messwerte({ daten }: { daten: Auswertung }) {
  const [exportLaeuft, setExportLaeuft] = useState(false)
  const [exportFehler, setExportFehler] = useState<string | null>(null)
  const taraLuecken = daten.lage.filter(l => l.n_paletten > 0 && l.n_paletten_mit_netto < l.n_paletten)
  // Ein einzelner Ausreisser (ein vergiftetes Chargenalter aus einem Zettel in
  // der Zukunft) würde die Achse verziehen. achsenBereich() findet ihn; die
  // betroffenen Arbeiten bleiben aus dem Bild und stehen als Hinweis.
  const alterRoh = daten.verarbeitung.filter(v => v.differenz !== null)
  const drausx = new Set(achsenBereich(alterRoh.map(v => v.differenz ?? 0), 'frei').ausgeschlossen)
  const alter = alterRoh.filter(v => !drausx.has(v.differenz ?? 0))
  const alterAusreisser = alterRoh.length - alter.length

  // Die volle Hochrechnung wird erst hier geholt, beim Klick — sie ist einige Megabyte gross.
  async function exportieren() {
    if (exportLaeuft) return
    setExportLaeuft(true); setExportFehler(null)
    try {
      const hochrechnung = await hochrechnungLaden()
      const kopf = ['charge_nr', 'sorte', 'schlag', 'portion', 'alter_tage', 'strom', 'buch', 'kg', 'basis_kg', 'koeffizient', 'koeff_n', 'koeff_basis', 'f_geliehen', 'formel']
      const zeilen = hochrechnung.filter(z => z.buch !== 'bilanz').map(z => kopf.map(k => {
        const w = (z as unknown as Record<string, unknown>)[k]; const s = w == null ? '' : String(w)
        return /[";\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
      }).join(';'))
      const blob = new Blob(['﻿' + [kopf.join(';'), ...zeilen].join('\n')], { type: 'text/csv;charset=utf-8' })
      const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'kuerbis-hochrechnung.csv'; a.click(); URL.revokeObjectURL(a.href)
    } catch (f) {
      setExportFehler(f instanceof Error ? f.message : 'Die Hochrechnung liess sich nicht holen.')
    } finally {
      setExportLaeuft(false)
    }
  }

  return (
    <>
      {daten.qualitaet && <Qualitaet q={daten.qualitaet} />}

      {taraLuecken.length > 0 && (
        <Hinweis art="warnung"><strong>Fehlende Tara verzerrt alles darüber.</strong> Bei {taraLuecken.length === 1 ? 'einer Charge' : `${taraLuecken.length} Chargen`} fehlt für einen Teil der Paletten das Leergewicht des Gebindes; diese Paletten zählen nicht in die Eingangsmasse. Unter <Link to="/betrieb/stammdaten">Betrieb → Stammdaten → Gebinde</Link> nachtragen.</Hinweis>
      )}

      <Karte titel="Wo fehlen Messungen?">
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Charge</th><th className="zahl">Eingang</th><th className="zahl">Paletten</th><th className="zahl">Wiegungen</th><th className="zahl">Schimmel</th><th className="zahl">CSV-Läufe</th></tr></thead>
          <tbody>{[...daten.lage].sort((a, b) => (b.eingang_kg ?? 0) - (a.eingang_kg ?? 0)).slice(0, 20).map(l => (
            <tr key={l.charge_nr}><td><strong>{l.charge_nr}</strong> <span className="leise">{l.sorte} · {l.schlag}</span></td><td className="zahl">{kg(l.eingang_kg)}</td>
              <td className="zahl">{zahl(l.n_paletten)}{l.n_paletten_mit_netto < l.n_paletten && <span className="leise"> ({l.n_paletten_mit_netto} m. Netto)</span>}</td>
              <td className="zahl">{l.n_wiegungen || <Marke art="warnung">keine</Marke>}</td><td className="zahl">{l.n_schimmel || <Marke art="warnung">keine</Marke>}</td><td className="zahl">{l.n_sortierlaeufe || '—'}</td></tr>
          ))}</tbody>
        </table></div>
      </Karte>

      {daten.saison && <Bilanz bilanz={daten.saison} />}

      <Karte titel="Wird das Älteste zuerst verarbeitet?">
        <Linien reihen={[{ name: 'Arbeit', farbe: 'var(--strom-schimmel)',
                             punkte: alter.map(v => ({ x: Date.parse(v.tag) / TAG, y: v.differenz ?? 0, text: `Charge ${v.charge_nr} · ${STATION_NAME[v.station] ?? v.station} · ${v.n_paletten} Paletten` })) }]}
                  xFormat={d => datum(new Date(d * TAG)).slice(0, 6)} xKalender={0} yFormat={y => `${y > 0 ? '+' : ''}${Math.round(y)} d`} yTitel="Tage gegenüber dem Durchschnitt"
                  waagrechte={[{ y: 0, text: 'Durchschnitt der Charge' }]}
                  leer="noch keine Arbeit mit datierten Paletten" />
        {alter.length > 2 && (
          <p className="leise-satz">
            Im Mittel {(() => { const d = alter.reduce((a, v) => a + (v.differenz ?? 0), 0) / alter.length; return `${d > 0 ? '+' : ''}${d.toFixed(1)} Tage` })()} gegenüber dem Durchschnitt der Charge, über {alter.length} Arbeiten.
          </p>
        )}
        {alterAusreisser > 0 && (
          <p className="fussnote">
            {alterAusreisser === 1 ? '1 Arbeit weicht' : `${alterAusreisser} Arbeiten weichen`} über ein Jahr vom Chargenschnitt ab — das ist ein Datenfehler (ein Zetteldatum in der Zukunft), kein Reihenfolge-Effekt. Er steht oben unter den Auffälligkeiten.
          </p>
        )}
        <Erklaerung>
          Wer nach Aussehen auswählt, misst den Verderb zu flach — das ist die Fehlerquelle, die keine Rechnung wegbekommt. Ein Punkt über null: Diese Arbeit hat Ware genommen, die älter war als der Durchschnitt der Charge an dem Tag.
        </Erklaerung>
      </Karte>

      {/* Runde AQ: „Durchsatz je Arbeit" (Tempo, kg/h) ist weg — „Arbeit und Tempo … nicht wichtig, komplett weglassen". */}

      <Karte titel="Die vier Koeffizienten">
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Koeffizient</th><th className="zahl">Gemessener Wert</th><th className="zahl">Messungen</th><th>Herkunft</th></tr></thead>
          <tbody>{daten.koeff.map(k => (
            <tr key={k.was}><td>{k.was}</td><td className="zahl"><strong>{k.wert}</strong></td><td className="zahl">{k.n > 0 ? k.n : <Marke art="warnung">keine</Marke>}</td><td className="leise">{k.basis}</td></tr>
          ))}</tbody>
        </table></div>
        {daten.gebinde.length > 0 && (
          <Aufklapp titel={<><span>Kistengewicht je Kaliber</span> <span className="leise">gemessen am Sortieren · {daten.gebinde.length} Zeilen</span></>}>
            <div className="rollbar"><table className="dicht">
              <thead><tr><th>Sorte</th><th className="zahl">Kaliber</th><th className="zahl">kg je Kiste</th><th className="zahl">Bereich</th><th className="zahl">Messungen</th></tr></thead>
              <tbody>{daten.gebinde.map(g => (
                <tr key={`${g.sorte}${g.kaliber_idx}`}><td>{g.sorte}</td><td className="zahl">{g.kaliber_idx + 1}</td><td className="zahl"><strong>{g.kg_je_gebinde.toFixed(1)}</strong></td>
                  <td className="zahl">{g.unten != null && g.oben != null ? `${g.unten.toFixed(1)}–${g.oben.toFixed(1)}` : '—'}</td><td className="zahl">{g.n}</td></tr>
              ))}</tbody>
            </table></div>
          </Aufklapp>
        )}
      </Karte>

      <Karte titel="Der Palox-Ausschuss je Sorte und Station">
        {daten.erwartung.length === 0
          ? <Hinweis art="warnung">Noch keine plausible Ablesung am Palox — bis dahin ist der Palox-Ausschuss unbekannt, nicht 0.</Hinweis>
          : <div className="rollbar"><table className="dicht">
              <thead><tr><th>Sorte</th><th>Station</th><th className="zahl">Grundausschuss</th><th className="zahl">Bereich</th>
                <th className="zahl">gemessen Ø</th><th className="zahl">bei Ø Lagerdauer</th><th className="zahl">Anstieg je Woche</th>
                <th className="zahl">Arbeiten</th><th>Woher</th></tr></thead>
              <tbody>{daten.erwartung.map(e => (
                <tr key={`${e.sorte}|${e.station}`}><td>{e.sorte}</td><td>{STATION_NAME[e.station] ?? e.station}</td>
                  <td className="zahl"><strong>{prozent(e.anteil)}</strong></td>
                  <td className="zahl">{e.n_arbeiten >= 2 ? `${prozent(e.unten)}–${prozent(e.oben)}` : '—'}</td>
                  <td className="zahl">{prozent(e.mittel)}</td>
                  <td className="zahl">{e.lager_mittel != null ? `${Math.round(e.lager_mittel)} d` : '—'}</td>
                  <td className="zahl">{e.anstieg_je_woche != null && e.anstieg_je_woche > 0
                    ? `+${(e.anstieg_je_woche * 100).toFixed(1)} % je Woche`
                    : <span className="leise">{e.anstieg_je_woche === 0 ? 'keiner sicher' : 'keiner messbar'}</span>}</td>
                  <td className="zahl">{e.n_arbeiten}</td>
                  <td>{e.geliehen && <Marke art="warnung">geliehen</Marke>} <span className="leise">{e.quelle}</span></td></tr>
              ))}</tbody>
            </table></div>}
        <Erklaerung>
          <p>Der Palox ist vor allem Aussortieren: Hagelschaden, falsch geschnittene Stiele, andere Mängel — ein <strong>Grundausschuss</strong>, den
          die Ware vom Feld mitbringt. Dazu kommt mit der Lagerdauer das Faule: der <strong>Anstieg</strong> je Woche, gemessen je Station über alle Sorten
          (innerhalb jeder Sorte: die länger gelagerten Arbeiten gegen die kürzer gelagerten). Er gilt erst, wenn er sicher ist — der Bereich,
          in dem er mit 95 % Sicherheit liegt, ganz über null; sonst „keiner sicher", und es wird ohne Anstieg gerechnet.</p>
          <p>Grundausschuss = das nach Masse gewichtete Mittel der Ablesungen der Sorte (ab drei Arbeiten, sonst aller Sorten — „geliehen"), um einen
          sicheren Anstieg auf null Lagertage zurückgelegt <Herkunft art="gerechnet" />; ohne sicheren Anstieg ist er das Mittel selbst. Für Ware mit t Lagertagen rechnet die Kaskade
          Grundausschuss + Anstieg × t / 7; was eine Charge auf ihrem Weg verliert, ist die Zusammensetzung der Stationen, durch die sie geht.
          Der Anstieg und seine Messung stehen unter <Link to="/ursachen">Ursachen</Link>.</p>
        </Erklaerung>
      </Karte>
      <Kurvenherkunft punkte={daten.punkte} />

      <Karte titel="Massenbilanz je Charge"
             aktion={<button type="button" className="klein" onClick={() => void exportieren()} disabled={exportLaeuft}><ZHerunterladen size={15} />{exportLaeuft ? 'holt die Hochrechnung …' : 'CSV exportieren'}</button>}>
        {exportFehler && <Hinweis art="warnung">{exportFehler}</Hinweis>}
        <Aufklapp titel={<><span>Je Charge</span> <span className="leise">{daten.bilanz.filter(b => b.eingang_kg !== null).length} Chargen · Kaskade<Herkunft art="gerechnet" />, CSV<Herkunft art="gemessen" /></span></>}>
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Charge</th><th className="zahl">Eingang</th><th className="zahl">Ausgelagert</th><th className="zahl" title="Eingang − ausgelagert, in Eingangskilo — vor Verdunstung und Faulem: der Nenner der Kaskade. Im Lagermanagement heisst dieselbe Eingangsmasse der Paletten, die noch dastehen, „Im Lager“; was davon verkaufsfähig ist, steht dort daneben.">Liegend (Eingangskilo)</th><th className="zahl">Kaskade am Band</th><th className="zahl">CSV gewogen</th><th className="zahl">Abweichung Kaskade ↔ CSV</th></tr></thead>
          <tbody>{daten.bilanz.filter(b => b.eingang_kg !== null).map(b => (
            <tr key={b.charge_nr}><td>{b.charge_nr} · {b.sorte}</td><td className="zahl">{kg(b.eingang_kg)}</td><td className="zahl">{kg(b.ausgelagert_kg)}</td><td className="zahl">{kg(b.lager_kg)}</td>
              <td className="zahl">{kg(b.modell_am_band_kg)}</td><td className="zahl">{kg(b.csv_gemessen_kg)}</td>
              <td className="zahl">{b.abweichung_anteil === null ? '—' : <Marke art={Math.abs(b.abweichung_anteil) < 0.1 ? 'fertig' : 'warnung'}>{prozent(b.abweichung_anteil)}</Marke>}</td></tr>
          ))}</tbody>
        </table></div>
        </Aufklapp>
        <Erklaerung>
          <strong>Eingang</strong> <Herkunft art="gemessen" /> und <strong>CSV gewogen</strong> <Herkunft art="gemessen" /> stehen so in den Listen;
          {' '}<strong>Ausgelagert</strong>, <strong>Liegend</strong> und <strong>Kaskade am Band</strong> <Herkunft art="gerechnet" /> kommen aus der Kaskade.
          Liegend ist die Eingangsmasse, die nicht ausgeliefert ist, vor Verdunstung und Faulem — im Lagermanagement steht sie als „Im Lager"; verkaufsfähig ist davon weniger.
          Die Ware im Lager ist bis heute, <strong>{datum(daten.heute)}</strong>, gealtert — nicht bis zum Saisonende. Die Prognose bis dahin steht nur im Verlauf des Überblicks.
        </Erklaerung>
      </Karte>

      {daten.wiegungen.length > 0 && (
        <Karte titel={`Gewogene Paletten (${daten.wiegungen.length})`}>
          <Aufklapp titel={<><span>Die letzten Wägungen</span> <span className="leise">{Math.min(daten.wiegungen.length, 40)} von {daten.wiegungen.length} · Verdunstet<Herkunft art="gemessen" /></span></>}>
          <div className="rollbar"><table className="dicht">
            <thead><tr><th>Charge</th><th className="zahl">Lagertage</th><th className="zahl">Netto damals</th><th className="zahl">Netto jetzt</th><th className="zahl">Verdunstet</th><th className="zahl">kg/Kiste</th><th className="zahl">kg/Kürbis</th></tr></thead>
            <tbody>{daten.wiegungen.slice(0, 40).map(w => (
              <tr key={w.id}><td>{w.charge_nr} · {w.sorte}{w.sichtbar_schimmel && <span className="gelb" title="sichtbar Faules auf der Palette — zählt nicht in die Verdunstungsrate"> <ZWarnung size={14} /></span>}</td><td className="zahl">{zahl(w.lagertage)}</td><td className="zahl">{kg(w.netto_damals_kg, 1)}</td>
                <td className="zahl">{kg(w.netto_jetzt_kg, 1)}</td><td className="zahl">{kg(w.verdunstung_kg, 1)}</td><td className="zahl">{w.kg_pro_kiste?.toFixed(2) ?? '—'}</td><td className="zahl">{w.kg_pro_kuerbis?.toFixed(2) ?? '—'}</td></tr>
            ))}</tbody>
          </table></div>
          </Aufklapp>
          <Erklaerung>
            <strong>Verdunstet</strong> <Herkunft art="gemessen" /> ist hier keine Hochrechnung, sondern der Unterschied zwischen beiden Wägungen dieser einen Palette.
            Es wird kein Kürbis entnommen, also ist der Unterschied entwichenes Wasser. Das Warnzeichen heisst: Es lag sichtbar Faules auf der Palette; dann zählt die Wägung nicht in die Verdunstungsrate, weil Faules schneller Wasser verliert.
          </Erklaerung>
          <Aufklapp titel="Lagerkontrollen berichtigen">
            <Kontrollkorrektur />
          </Aufklapp>
        </Karte>
      )}
    </>
  )
}

/** Wie vollständig wird erfasst? Ein Balken je Absprache. */
function Qualitaet({ q }: { q: Datenqualitaet }) {
  const zeilen: { name: string; ab: string; ist: number; von: number; hinweis: string }[] = [
    // Runde AO: Nenner sind die Eingangspaletten (Sortieren, Waschen +
    // Sortieren) — die Paletten aus dem Zwischenlager tragen nie ein
    // Eingangsdatum und drückten die Zeile bisher grundlos nach unten.
    { name: 'Datum vom Zettel bei gezählten Eingangspaletten', ab: 'AB-11', ist: q.paletten_mit_datum, von: q.eingangspaletten, hinweis: 'ohne Datum kein Alter der Ware' },
    { name: 'Palox abgelesen (mindestens einmal)', ab: 'AB-02', ist: q.arbeiten_mit_ablesung, von: q.arbeiten_fertig, hinweis: 'sonst landet der Schimmel auf der nächsten Arbeit' },
    { name: 'Palox zu Beginn und am Ende abgelesen', ab: 'AB-02', ist: q.arbeiten_mit_zwei_ablesungen, von: q.arbeiten_fertig, hinweis: 'zwei Ablesungen trennen die Arbeiten sauber' },
    { name: 'Abschlussfrage „alles aus einer Charge?" beantwortet', ab: 'AB-04', ist: q.arbeiten_mit_antwort, von: q.arbeiten_fertig, hinweis: 'ohne Antwort ist das Alter geraten' },
    { name: 'Sortier-CSV einer Arbeit zugeordnet', ab: '—', ist: q.sortierlaeufe_zugeordnet, von: q.sortierlaeufe, hinweis: 'unzugeordnet: Betrieb → Warteschlange' },
    { name: 'Kisten am Sortieren gezählt', ab: 'AB-12', ist: q.sortier_arbeiten_mit_kisten, von: q.sortier_arbeiten, hinweis: 'daraus entsteht das Kistengewicht' },
    { name: 'Waschen: Paletten gezählt (Kisten, mit Kaliber)', ab: 'AB-33', ist: q.wasch_arbeiten_mit_kisten, von: q.wasch_arbeiten, hinweis: 'sonst hat das Faule am Waschbecken keinen Nenner' },
    // Fax (AB-24, 0051): seit Runde R eingefroren — die zwei Zeilen dazu sind
    // weg, die Zähler in v_datenqualitaet bleiben.
    { name: 'Waschen + Sortieren: Gewicht vom Zettel bei gezählten Paletten', ab: 'AB-25', ist: q.ws_paletten_mit_zettelgewicht, von: q.ws_paletten_gezaehlt, hinweis: 'ohne Zettelgewicht hat der Palox keinen Nenner' },
    { name: 'Kistensystem nach dem Waschen beantwortet', ab: 'AB-26', ist: q.arbeiten_mit_kistensystem, von: q.arbeiten_nach_waschen, hinweis: 'sonst weiss die Auswertung nicht, ob eine Kiste rechenbar ist' },
    // Runde AO: „Waschen: Sortierdatum je gezählter Palette" ist weg — das
    // Datum ist freiwillig, seit die Waage am Anfang der Strasse die Menge
    // misst (0104). Eine Absprache, die es nicht mehr gibt, misst man nicht.
    // Der Zähler wasch_kisten_mit_sortierdatum bleibt in v_datenqualitaet.
    // Runde Q: die Kistenzahl auf der Eingangspalette. Ohne sie hat die
    // Palette kein Netto (die Tara hängt am Gebinde) — und ohne Netto keine
    // Masse. Die Zeile sagt, wie oft dieser Weg wirklich trägt.
    { name: 'Eingangspalette: Kistenzahl getippt', ab: 'AB-49', ist: q.eingangspaletten_mit_kisten, von: q.eingangspaletten, hinweis: 'ohne Kistenzahl kein Leergewicht und damit keine Masse für diese Palette' },
    // Runde Q, Q21: eine geschätzte Zahl darf nicht aussehen wie eine
    // gemessene. Diese Zeile sagt, auf wie vielen ABGELESENEN Altersangaben
    // die Verderbskurve ruht — beim Waschen ist das Alter geschätzt.
    { name: 'Alter der Ware vom Zettel abgelesen', ab: 'AB-50', ist: q.arbeiten_alter_gemessen, von: q.arbeiten_fertig, hinweis: 'beim Waschen kommt die Palette aus dem Zwischenlager und trägt kein Eingangsdatum mehr — dort ist das Alter geschätzt' },
  ]
  const unbekannt = q.arbeiten_mit_palox_unbekannt
  const gesamtAnteil = zeilen.filter(z => z.von > 0)
  const erfuellt = gesamtAnteil.filter(z => z.ist / z.von >= 0.95).length
  return (
    <Karte titel="Wie vollständig wird erfasst?" unter={`${erfuellt} von ${gesamtAnteil.length} Absprachen mit der Halle zu über 95 % eingehalten`}>
      <div className="gitter" style={{ gap: '.5rem 1.5rem', gridTemplateColumns: 'repeat(auto-fit, minmax(340px, 1fr))' }}>
        {zeilen.map(z => {
          const anteil = z.von > 0 ? z.ist / z.von : null
          return (
            <div key={z.name} style={{ padding: '.25rem 0' }}>
              <div className="reihe" style={{ fontSize: '.88rem', gap: '.4rem', flexWrap: 'nowrap', alignItems: 'baseline' }}>
                <span style={{ minWidth: 0, flex: 1 }}>{z.name} <span className="leise">{z.ab}</span></span>
                <span className="nowrap tabular">{z.von === 0 ? <span className="leise">noch nichts</span> : <><strong>{z.ist}</strong> <span className="leise">von {z.von} ·</span> <strong>{prozent(anteil, 0)}</strong></>}</span>
              </div>
              <div className="balken-spur" style={{ height: 8, marginTop: '.3rem' }}>
                <div className="balken-fuellung waechst" style={{ width: `${(anteil ?? 0) * 100}%`, background: anteil !== null && anteil < 0.8 ? 'var(--rot)' : anteil !== null && anteil < 0.95 ? 'var(--gelb)' : 'var(--gruen)' }} />
              </div>
              {anteil !== null && anteil < 0.95 && <div className="fussnote" style={{ marginTop: '.2rem' }}>{z.hinweis}</div>}
            </div>
          )
        })}
      </div>
      <p className="leise-satz">
        Lagerkontrollen: <strong>{q.lagerkontrollen}</strong> gewogene Paletten — jede ist ein Punkt in der Verdunstungskurve; die App schlägt vor, wo eine Wägung am meisten bringt.
        {unbekannt > 0 && <> Bei <strong>{unbekannt === 1 ? 'einer Arbeit' : `${unbekannt} Arbeiten`}</strong> fiel der Palox-Stand zwischendurch (geleert ohne Ablesung) — {unbekannt === 1 ? 'ihr' : 'deren'} Faules ist unbekannt und fehlt in der Kurve; {unbekannt === 1 ? 'sie steht' : 'sie stehen'} unter Auffälligkeiten.</>}
      </p>
    </Karte>
  )
}
