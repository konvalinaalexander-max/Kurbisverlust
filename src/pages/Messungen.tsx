import { useState } from 'react'
import { Link } from 'react-router-dom'
import { datum, kg, prozent, zahl } from '../lib/format'
import { Aufklapp, Erklaerung, Herkunft, Hinweis, Karte, Marke } from '../components/Bausteine'
import { Linien } from '../components/Diagramm'
import { achsenBereich } from '../lib/achse'
import { hochrechnungLaden, useAuswertung, type Datenqualitaet } from '../auswertung/daten'
import { Auffaelligkeiten, Bilanz, Kurvenherkunft, Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { Kontrollkorrektur } from '../arbeit/Korrektur'
import { STATION_NAME } from '../lib/format'
import { ZHerunterladen, ZWarnung } from '../components/Zeichen'

const TAG = 86400000

/**
 * Messungen: Was weiss die Auswertung — und was nicht? Wie vollständig wird
 * erfasst, wo fehlen Messungen, welche sehen nicht richtig aus, worauf
 * beruhen die Koeffizienten, und was das Modell nicht weiss.
 */
export default function Messungen() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  // Vor jedem vorzeitigen Rückgeben: React zählt die Hooks je Render.
  const [exportLaeuft, setExportLaeuft] = useState(false)
  const [exportFehler, setExportFehler] = useState<string | null>(null)
  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const m = daten.modell
  const taraLuecken = daten.lage.filter(l => l.n_paletten > 0 && l.n_paletten_mit_netto < l.n_paletten)
  // Ein einzelner Ausreisser (ein vergiftetes Chargenalter aus einem Zettel in
  // der Zukunft) würde die Achse verziehen. achsenBereich() findet ihn; die
  // betroffenen Arbeiten bleiben aus dem Bild und stehen als Hinweis.
  const alterRoh = daten.verarbeitung.filter(v => v.differenz !== null)
  const drausx = new Set(achsenBereich(alterRoh.map(v => v.differenz ?? 0), 'frei').ausgeschlossen)
  const alter = alterRoh.filter(v => !drausx.has(v.differenz ?? 0))
  const alterAusreisser = alterRoh.length - alter.length
  const stationen = [...new Set(daten.durchsatz.map(d => d.station))]

  // Die volle Hochrechnung wird erst hier geholt, beim Klick — sie ist einige Megabyte gross.
  async function exportieren() {
    if (exportLaeuft) return
    setExportLaeuft(true); setExportFehler(null)
    try {
      const hochrechnung = await hochrechnungLaden()
      const kopf = ['charge_nr', 'sorte', 'schlag', 'portion', 'alter_tage', 'strom', 'buch', 'kg', 'basis_kg', 'koeffizient', 'koeff_n', 'koeff_basis', 'f_extrapoliert', 'formel']
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
      <Reiterkopf titel="Messungen" zweck="Was weiss die Auswertung — und was nicht? Auffälligkeiten zum Korrigieren, Vollständigkeit, Lücken, Koeffizienten, Modell."
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt} />
      <Probleme liste={daten.probleme} />

      <Auffaelligkeiten befunde={daten.befunde} />
      {daten.qualitaet && <Qualitaet q={daten.qualitaet} />}

      {taraLuecken.length > 0 && (
        <Hinweis art="warnung"><strong>Fehlende Tara verzerrt alles darüber.</strong> Bei {taraLuecken.length} Chargen fehlt für einen Teil der Paletten das Leergewicht des Gebindes; diese Paletten zählen nicht in die Eingangsmasse. Unter <Link to="/betrieb/stammdaten">Betrieb → Stammdaten → Gebinde</Link> nachtragen.</Hinweis>
      )}

      <Karte titel="Wo fehlen Messungen?" unter="Nach Eingangsmasse sortiert: die grössten Chargen ohne Stichprobe kosten am meisten Genauigkeit.">
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

      <Karte titel="Wird das Älteste zuerst verarbeitet?" unter="Je Arbeit: das Alter der gezählten Paletten gegen das mittlere Alter der Charge an dem Tag. Über null heisst: älter als der Durchschnitt.">
        <Linien reihen={[{ name: 'Arbeit', farbe: 'var(--strom-schimmel)',
                             punkte: alter.map(v => ({ x: Date.parse(v.tag) / TAG, y: v.differenz ?? 0, text: `Charge ${v.charge_nr} · ${STATION_NAME[v.station] ?? v.station} · ${v.n_paletten} Paletten` })) }]}
                  xFormat={d => datum(new Date(d * TAG)).slice(0, 5)} yFormat={y => `${y > 0 ? '+' : ''}${Math.round(y)} d`} xTitel="Tag" yTitel="Tage gegenüber dem Durchschnitt"
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

      {daten.durchsatz.length > 0 && (
        <Karte titel="Durchsatz je Arbeit" unter="Aus Start, Ende und Masse. Ohne bekannte Masse gibt es keine Rate — die Zeile bleibt stehen, damit man sieht, warum.">
          <div className="zahlenzeile">
            {stationen.map(s => {
              const eigene = daten.durchsatz.filter(d => d.station === s && d.kg_pro_h !== null)
              const mittel = eigene.length ? eigene.reduce((a, d) => a + (d.kg_pro_h ?? 0), 0) / eigene.length : null
              return <div key={s}><div className="titel">Tempo {STATION_NAME[s] ?? s}</div><div className="wert">{mittel === null ? '—' : `${zahl(Math.round(mittel))} kg/h`}</div><div className="unter">{eigene.length} Arbeiten mit Masse</div></div>
            })}
          </div>
          <Aufklapp titel={<><span>Die letzten Arbeiten</span> <span className="leise">{Math.min(daten.durchsatz.length, 40)} von {daten.durchsatz.length}</span></>}>
          <div className="rollbar"><table className="dicht">
            <thead><tr><th>Start</th><th>Arbeit</th><th>Charge</th><th className="zahl">Dauer</th><th className="zahl">Bewegte Masse</th><th className="zahl">kg/h</th><th className="zahl">Leute</th></tr></thead>
            <tbody>{daten.durchsatz.slice(0, 40).map(d => (
              <tr key={d.auftrag_id}><td>{datum(d.start_ts)}</td><td>{STATION_NAME[d.station] ?? d.station}{d.ist_fax ? ' (Fax)' : ''}</td><td>{d.charge_nr} · {d.sorte}</td>
                <td className="zahl">{d.dauer_h.toFixed(1)} h</td><td className="zahl">{d.masse_kg != null ? kg(d.masse_kg, 0) : <span className="leise">unbekannt</span>}</td>
                <td className="zahl">{d.kg_pro_h != null ? zahl(d.kg_pro_h) : '—'}</td><td className="zahl">{d.n_teilnehmer}</td></tr>
            ))}</tbody>
          </table></div>
          </Aufklapp>
        </Karte>
      )}

      <Karte titel="Die vier Koeffizienten" unter="Das Innenleben der Hochrechnung: Jede Zahl entsteht als Koeffizient × bekannte Grösse.">
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

      {m && (
        <Karte titel="Das Verderbsmodell — und was es nicht weiss" unter="Die Kurve, mit der für alle Ware im Lager gerechnet wird.">
          {!m.brauchbar ? (
            <Hinweis art="warnung">Für eine Kurve reicht es noch nicht — nötig sind Schimmelmessungen aus mindestens drei Chargen über deutlich verschiedene Lagerdauern. Solange gilt der zuletzt gemessene Wert.</Hinweis>
          ) : (
            <div className="rollbar"><table className="dicht"><tbody>
              <tr><td>Form der Kurve (k)</td><td className="zahl"><strong>{m.k?.toFixed(2)}</strong></td><td className="leise">über 1 heisst: die Verderbrate steigt mit der Lagerdauer</td></tr>
              <tr><td>Gemessener Bereich</td><td className="zahl"><strong>{Math.round(m.t_min)}–{Math.round(m.t_max)} Tage</strong></td><td className="leise">darüber hinaus wird gerechnet, nicht gemessen</td></tr>
              <tr><td>Messungen</td><td className="zahl"><strong>{m.n}</strong></td><td className="leise">aus {m.c_chargen} Chargen — die Chargen zählen, nicht die Messungen</td></tr>
              <tr><td>Rückrechnung (Smearing)</td><td className="zahl"><strong>×{m.smearing?.toFixed(3)}</strong></td><td className="leise">gleicht aus, dass die Anpassung im Logarithmus rechnet</td></tr>
              <tr><td>Sockel a₀</td><td className="zahl"><strong>{m.sockel != null ? prozent(m.sockel) : '—'}</strong></td><td className="leise">Nachweis ×{m.sockel_nachweis?.toFixed(3) ?? '—'} bei Schwelle ×{m.sockel_schwelle?.toFixed(3) ?? '—'}</td></tr>
            </tbody></table></div>
          )}
          {daten.selektion && (
            <Hinweis art={(daten.selektion.n_lager ?? 0) < 5 ? 'warnung' : 'info'}>
              <strong>Auswahl der gemessenen Paletten:</strong> {daten.selektion.befund}
              {(daten.selektion.n_lager ?? 0) < 5 && <> Dagegen hilft nur eine Handvoll zufällig gegriffener Lagerpaletten je Saison — „Palette kontrollieren" auf dem Startbildschirm der Arbeiter. Zwölf je Saison genügen.</>}
            </Hinweis>
          )}
        </Karte>
      )}
      <Kurvenherkunft punkte={daten.punkte} />

      <Karte titel="Massenbilanz je Charge" unter="Die Probe aufs Exempel: das Modell sagt voraus, wie viel Masse am Sortierband ankommen müsste; die CSV hat sie gewogen."
             aktion={<button type="button" className="klein" onClick={() => void exportieren()} disabled={exportLaeuft}><ZHerunterladen size={15} />{exportLaeuft ? 'holt die Hochrechnung …' : 'CSV exportieren'}</button>}>
        {exportFehler && <Hinweis art="warnung">{exportFehler}</Hinweis>}
        <Aufklapp titel={<><span>Je Charge</span> <span className="leise">{daten.bilanz.filter(b => b.eingang_kg !== null).length} Chargen · Modell<Herkunft art="gerechnet" />, CSV<Herkunft art="gemessen" /></span></>}>
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Charge</th><th className="zahl">Eingang</th><th className="zahl">Ausgelagert</th><th className="zahl">Noch im Lager</th><th className="zahl">Modell am Band</th><th className="zahl">CSV gewogen</th><th className="zahl">Abweichung Modell ↔ CSV</th></tr></thead>
          <tbody>{daten.bilanz.filter(b => b.eingang_kg !== null).map(b => (
            <tr key={b.charge_nr}><td>{b.charge_nr} · {b.sorte}</td><td className="zahl">{kg(b.eingang_kg)}</td><td className="zahl">{kg(b.ausgelagert_kg)}</td><td className="zahl">{kg(b.lager_kg)}</td>
              <td className="zahl">{kg(b.modell_am_band_kg)}</td><td className="zahl">{kg(b.csv_gemessen_kg)}</td>
              <td className="zahl">{b.abweichung_anteil === null ? '—' : <Marke art={Math.abs(b.abweichung_anteil) < 0.1 ? 'fertig' : 'warnung'}>{prozent(b.abweichung_anteil)}</Marke>}</td></tr>
          ))}</tbody>
        </table></div>
        </Aufklapp>
        <Erklaerung>
          <strong>Eingang</strong> <Herkunft art="gemessen" /> und <strong>CSV gewogen</strong> <Herkunft art="gemessen" /> stehen so in den Listen;
          {' '}<strong>Ausgelagert</strong>, <strong>Noch im Lager</strong> und <strong>Modell am Band</strong> <Herkunft art="gerechnet" /> kommen aus der Kaskade.
          Die Ware im Lager ist bis heute, <strong>{datum(daten.heute)}</strong>, gealtert — nicht bis zum Saisonende. Die Prognose bis dahin steht nur im Verlauf des Überblicks.
        </Erklaerung>
      </Karte>

      {daten.wiegungen.length > 0 && (
        <Karte titel={`Gewogene Paletten (${daten.wiegungen.length})`} unter="Netto damals minus Netto jetzt, beide auf der Waage — entwichenes Wasser, keine Hochrechnung.">
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
            <Kontrollkorrektur geaendert={neuRechnen} />
          </Aufklapp>
        </Karte>
      )}
    </>
  )
}

/** Wie vollständig wird erfasst? Ein Balken je Absprache. */
function Qualitaet({ q }: { q: Datenqualitaet }) {
  const zeilen: { name: string; ab: string; ist: number; von: number; hinweis: string }[] = [
    { name: 'Datum vom Zettel bei gezählten Paletten', ab: 'AB-11', ist: q.paletten_mit_datum, von: q.paletten_gezaehlt, hinweis: 'ohne Datum kein Alter der Ware' },
    { name: 'Palox abgelesen (mindestens einmal)', ab: 'AB-02', ist: q.arbeiten_mit_ablesung, von: q.arbeiten_fertig, hinweis: 'sonst landet der Schimmel auf der nächsten Arbeit' },
    { name: 'Palox zu Beginn und am Ende abgelesen', ab: 'AB-02', ist: q.arbeiten_mit_zwei_ablesungen, von: q.arbeiten_fertig, hinweis: 'zwei Ablesungen trennen die Arbeiten sauber' },
    { name: 'Abschlussfrage „alles aus einer Charge?" beantwortet', ab: 'AB-04', ist: q.arbeiten_mit_antwort, von: q.arbeiten_fertig, hinweis: 'ohne Antwort ist das Alter geraten' },
    { name: 'Sortier-CSV einer Arbeit zugeordnet', ab: '—', ist: q.sortierlaeufe_zugeordnet, von: q.sortierlaeufe, hinweis: 'unzugeordnet: Betrieb → Warteschlange' },
    { name: 'Kisten am Sortieren gezählt', ab: 'AB-12', ist: q.sortier_arbeiten_mit_kisten, von: q.sortier_arbeiten, hinweis: 'daraus entsteht das Kistengewicht' },
    { name: 'Waschen: Paletten gezählt (Kisten und Sortierdatum, mit Kaliber)', ab: 'AB-31', ist: q.wasch_arbeiten_mit_kisten, von: q.wasch_arbeiten, hinweis: 'sonst hat das Faule am Waschbecken keinen Nenner' },
    { name: 'Fax: Paletten oder Kisten gezählt', ab: 'AB-24', ist: q.fax_arbeiten_mit_kisten, von: q.fax_arbeiten, hinweis: 'ohne Palettenzahl hat das Faule beim Abpacken keinen Nenner' },
    { name: 'Fax: Faules gewogen (auch „nichts Faules")', ab: '0051', ist: q.fax_arbeiten_mit_faulem, von: q.fax_arbeiten, hinweis: 'sonst bleibt der Fax-Strom unbekannt' },
    { name: 'Waschen + Sortieren: Gewicht vom Zettel bei gezählten Paletten', ab: 'AB-25', ist: q.ws_paletten_mit_zettelgewicht, von: q.ws_paletten_gezaehlt, hinweis: 'ohne Zettelgewicht hat der Palox keinen Nenner' },
    { name: 'Kistensystem nach dem Waschen beantwortet', ab: 'AB-26', ist: q.arbeiten_mit_kistensystem, von: q.arbeiten_nach_waschen, hinweis: 'sonst weiss die Auswertung nicht, ob eine Kiste rechenbar ist' },
    { name: 'Waschen: Sortierdatum je gezählter Palette', ab: 'AB-31', ist: q.wasch_kisten_mit_sortierdatum, von: q.wasch_kisten_gezaehlt, hinweis: 'das Datum auf dem Zettel sagt, wie lange die Ware nach dem Sortieren stand' },
  ]
  const unbekannt = q.arbeiten_mit_palox_unbekannt
  const gesamtAnteil = zeilen.filter(z => z.von > 0)
  const erfuellt = gesamtAnteil.filter(z => z.ist / z.von >= 0.95).length
  return (
    <Karte titel="Wie vollständig wird erfasst?" unter={`Je Zeile eine Absprache aus der Halle (docs/ABMACHUNGEN.md) und wie oft sie eingehalten wurde — ${erfuellt} von ${gesamtAnteil.length} zu über 95 %.`}>
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
        {unbekannt > 0 && <> Bei <strong>{unbekannt}</strong> Arbeiten fiel der Palox-Stand zwischendurch (geleert ohne Ablesung) — ihr Faules ist unbekannt und fehlt in der Kurve; die Arbeiten stehen unter Auffälligkeiten.</>}
      </p>
    </Karte>
  )
}
