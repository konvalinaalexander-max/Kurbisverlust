import { datum, kg, prozent, zahl } from '../lib/format'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import { Diagramm } from '../components/Diagramm'
import { useAuswertung, type Datenqualitaet } from '../auswertung/daten'
import { Auffaelligkeiten, Herkunft, Reiterkopf } from '../auswertung/Karten'
import { STATION_NAME } from '../lib/format'

const TAG = 86400000

/**
 * Messungen: Was weiss die Auswertung — und was nicht? Wie vollständig wird
 * erfasst, wo fehlen Messungen, welche sehen nicht richtig aus, worauf
 * beruhen die Koeffizienten, und was das Modell nicht weiss.
 */
export default function Messungen() {
  const { daten, laedt, fehler, neuRechnen } = useAuswertung()
  if (laedt && !daten) return <Lade text="Auswertung wird gerechnet …" />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null
  const m = daten.modell
  const taraLuecken = daten.lage.filter(l => l.n_paletten > 0 && l.n_paletten_mit_netto < l.n_paletten)
  const alter = daten.verarbeitung.filter(v => v.differenz !== null)
  const stationen = [...new Set(daten.durchsatz.map(d => d.station))]

  function exportieren() {
    const kopf = ['charge_nr', 'sorte', 'schlag', 'portion', 'alter_tage', 'strom', 'buch', 'kg', 'basis_kg', 'koeffizient', 'koeff_n', 'koeff_basis', 'f_extrapoliert', 'formel']
    const zeilen = daten!.hochrechnung.filter(z => z.buch !== 'bilanz').map(z => kopf.map(k => {
      const w = (z as unknown as Record<string, unknown>)[k]; const s = w == null ? '' : String(w)
      return /[";\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
    }).join(';'))
    const blob = new Blob(['﻿' + [kopf.join(';'), ...zeilen].join('\n')], { type: 'text/csv;charset=utf-8' })
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'kuerbis-hochrechnung.csv'; a.click(); URL.revokeObjectURL(a.href)
  }

  return (
    <>
      <Reiterkopf titel="Messungen" zweck="Was weiss die Auswertung — und was nicht? Vollständigkeit, Lücken, Auffälligkeiten, Koeffizienten, Modell."
                  stand={daten.stand} neuRechnen={() => void neuRechnen()} />

      {daten.qualitaet && <Qualitaet q={daten.qualitaet} />}
      <Auffaelligkeiten befunde={daten.befunde} />

      {taraLuecken.length > 0 && (
        <Hinweis art="warnung"><strong>Fehlende Tara verzerrt alles darüber.</strong> Bei {taraLuecken.length} Chargen fehlt für einen Teil der Paletten das Leergewicht des Gebindes; diese Paletten zählen nicht in die Eingangsmasse. Unter Betrieb → Stammdaten → Gebinde nachtragen.</Hinweis>
      )}

      <Karte titel="Wo fehlen Messungen?">
        <p className="leise">Nach Eingangsmasse sortiert: die grössten Chargen ohne Stichprobe kosten am meisten Genauigkeit.</p>
        <div className="rollbar"><table>
          <thead><tr><th>Charge</th><th className="zahl">Eingang</th><th className="zahl">Paletten</th><th className="zahl">Wiegungen</th><th className="zahl">Schimmel</th><th className="zahl">CSV-Läufe</th></tr></thead>
          <tbody>{[...daten.lage].sort((a, b) => (b.eingang_kg ?? 0) - (a.eingang_kg ?? 0)).slice(0, 20).map(l => (
            <tr key={l.charge_nr}><td>{l.charge_nr} · {l.sorte} · {l.schlag}</td><td className="zahl">{kg(l.eingang_kg)}</td>
              <td className="zahl">{zahl(l.n_paletten)}{l.n_paletten_mit_netto < l.n_paletten && ` (${l.n_paletten_mit_netto} m. Netto)`}</td>
              <td className="zahl">{l.n_wiegungen || <Marke art="warnung">keine</Marke>}</td><td className="zahl">{l.n_schimmel || <Marke art="warnung">keine</Marke>}</td><td className="zahl">{l.n_sortierlaeufe || '—'}</td></tr>
          ))}</tbody>
        </table></div>
      </Karte>

      <Karte titel="Wird das Älteste zuerst verarbeitet?">
        <p className="leise">Je Arbeit: das Alter der gezählten Paletten gegen das mittlere Alter der Charge an dem Tag. Über null heisst: älter als der Durchschnitt verarbeitet. Wer nach Aussehen auswählt, misst den Verderb zu flach — das ist die Fehlerquelle, die keine Rechnung wegbekommt.</p>
        <Diagramm reihen={[{ name: 'Arbeit', farbe: 'var(--strom-schimmel)',
                             punkte: alter.map(v => ({ x: Date.parse(v.tag) / TAG, y: v.differenz ?? 0, text: `Charge ${v.charge_nr} · ${STATION_NAME[v.station] ?? v.station} · ${v.n_paletten} Paletten` })) }]}
                  xFormat={d => datum(new Date(d * TAG)).slice(0, 5)} yFormat={y => `${y > 0 ? '+' : ''}${Math.round(y)} d`} xTitel="Tag" yTitel="Tage gegenüber dem Durchschnitt"
                  leer="noch keine Arbeit mit datierten Paletten" />
        {alter.length > 2 && (
          <p className="leise" style={{ margin: '.5rem 0 0' }}>
            Im Mittel {(() => { const d = alter.reduce((a, v) => a + (v.differenz ?? 0), 0) / alter.length; return `${d > 0 ? '+' : ''}${d.toFixed(1)} Tage` })()} gegenüber dem Durchschnitt der Charge, über {alter.length} Arbeiten.
          </p>
        )}
      </Karte>

      {daten.durchsatz.length > 0 && (
        <Karte titel="Durchsatz je Arbeit">
          <p className="leise">Aus Start, Ende und Masse. Ohne bekannte Masse gibt es keine Rate — die Zeile bleibt stehen, damit man sieht, warum.</p>
          <div className="spalten" style={{ marginBottom: '.75rem' }}>
            {stationen.map(s => {
              const eigene = daten.durchsatz.filter(d => d.station === s && d.kg_pro_h !== null)
              const mittel = eigene.length ? eigene.reduce((a, d) => a + (d.kg_pro_h ?? 0), 0) / eigene.length : null
              return <div key={s}><div className="leise">{STATION_NAME[s] ?? s}</div><strong>{mittel === null ? '—' : `${Math.round(mittel)} kg/h`}</strong><div className="leise">{eigene.length} Arbeiten mit Masse</div></div>
            })}
          </div>
          <div className="rollbar"><table>
            <thead><tr><th>Start</th><th>Arbeit</th><th>Charge</th><th className="zahl">Dauer</th><th className="zahl">Masse</th><th className="zahl">kg/h</th><th className="zahl">Leute</th></tr></thead>
            <tbody>{daten.durchsatz.slice(0, 40).map(d => (
              <tr key={d.auftrag_id}><td>{datum(d.start_ts)}</td><td>{STATION_NAME[d.station] ?? d.station}{d.ist_fax ? ' (Fax)' : ''}</td><td>{d.charge_nr} · {d.sorte}</td>
                <td className="zahl">{d.dauer_h.toFixed(1)} h</td><td className="zahl">{d.masse_kg != null ? kg(d.masse_kg, 0) : <span className="leise">unbekannt</span>}</td>
                <td className="zahl">{d.kg_pro_h != null ? zahl(d.kg_pro_h) : '—'}</td><td className="zahl">{d.n_teilnehmer}</td></tr>
            ))}</tbody>
          </table></div>
        </Karte>
      )}

      <Karte titel="Die vier Koeffizienten">
        <p className="leise">Das Innenleben der Hochrechnung: Jede Zahl entsteht als <em>Koeffizient × bekannte Grösse</em>. Hier steht, worauf jeder beruht.</p>
        <div className="rollbar"><table>
          <thead><tr><th>Koeffizient</th><th className="zahl">Wert</th><th className="zahl">Messungen</th><th>Herkunft</th></tr></thead>
          <tbody>{daten.koeff.map(k => (
            <tr key={k.was}><td>{k.was}</td><td className="zahl"><strong>{k.wert}</strong></td><td className="zahl">{k.n > 0 ? k.n : <Marke art="warnung">keine</Marke>}</td><td className="leise">{k.basis}</td></tr>
          ))}</tbody>
        </table></div>
        {daten.gebinde.length > 0 && (
          <>
            <h3 style={{ marginTop: '1rem' }}>Kistengewicht je Kaliber (gemessen am Sortieren)</h3>
            <div className="rollbar"><table>
              <thead><tr><th>Sorte</th><th className="zahl">Kaliber</th><th className="zahl">kg je Kiste</th><th className="zahl">Bereich</th><th className="zahl">Messungen</th></tr></thead>
              <tbody>{daten.gebinde.map(g => (
                <tr key={`${g.sorte}${g.kaliber_idx}`}><td>{g.sorte}</td><td className="zahl">{g.kaliber_idx + 1}</td><td className="zahl"><strong>{g.kg_je_gebinde.toFixed(1)}</strong></td>
                  <td className="zahl">{g.unten != null && g.oben != null ? `${g.unten.toFixed(1)}–${g.oben.toFixed(1)}` : '—'}</td><td className="zahl">{g.n}</td></tr>
              ))}</tbody>
            </table></div>
          </>
        )}
      </Karte>

      {m && (
        <Karte titel="Das Verderbsmodell — und was es nicht weiss">
          {!m.brauchbar ? (
            <Hinweis art="warnung">Für eine Kurve reicht es noch nicht — nötig sind Schimmelmessungen aus mindestens drei Chargen über deutlich verschiedene Lagerdauern. Solange gilt der zuletzt gemessene Wert.</Hinweis>
          ) : (
            <div className="rollbar"><table><tbody>
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
      <Herkunft punkte={daten.punkte} />

      <Karte titel="Massenbilanz je Charge" aktion={<button onClick={exportieren}>CSV exportieren</button>}>
        <p className="leise">Die Probe aufs Exempel: das Modell sagt voraus, wie viel Masse am Sortierband ankommen müsste; die CSV hat sie gewogen.</p>
        <div className="rollbar"><table>
          <thead><tr><th>Charge</th><th className="zahl">Eingang</th><th className="zahl">ausgelagert</th><th className="zahl">im Lager</th><th className="zahl">Modell</th><th className="zahl">gewogen</th><th className="zahl">Abweichung</th></tr></thead>
          <tbody>{daten.bilanz.filter(b => b.eingang_kg !== null).map(b => (
            <tr key={b.charge_nr}><td>{b.charge_nr} · {b.sorte}</td><td className="zahl">{kg(b.eingang_kg)}</td><td className="zahl">{kg(b.ausgelagert_kg)}</td><td className="zahl">{kg(b.lager_kg)}</td>
              <td className="zahl">{kg(b.modell_am_band_kg)}</td><td className="zahl">{kg(b.csv_gemessen_kg)}</td>
              <td className="zahl">{b.abweichung_anteil === null ? '—' : <Marke art={Math.abs(b.abweichung_anteil) < 0.1 ? 'fertig' : 'warnung'}>{prozent(b.abweichung_anteil)}</Marke>}</td></tr>
          ))}</tbody>
        </table></div>
        <p className="leise" style={{ margin: '.5rem 0 0' }}>Ware im Lager wird bis zum Stichtag <strong>{datum(daten.bilanz[0]?.stichtag)}</strong> projiziert (Betrieb → Stammdaten → Einstellungen).</p>
      </Karte>

      {daten.wiegungen.length > 0 && (
        <Karte titel={`Gewogene Paletten (${daten.wiegungen.length})`}>
          <div className="rollbar"><table>
            <thead><tr><th>Charge</th><th className="zahl">Lagertage</th><th className="zahl">Netto damals</th><th className="zahl">Netto jetzt</th><th className="zahl">Verlust</th><th className="zahl">kg/Kiste</th><th className="zahl">kg/Kürbis</th></tr></thead>
            <tbody>{daten.wiegungen.slice(0, 40).map(w => (
              <tr key={w.id}><td>{w.charge_nr} · {w.sorte}{w.sichtbar_schimmel ? ' ⚠' : ''}</td><td className="zahl">{zahl(w.lagertage)}</td><td className="zahl">{kg(w.netto_damals_kg, 1)}</td>
                <td className="zahl">{kg(w.netto_jetzt_kg, 1)}</td><td className="zahl">{kg(w.verlust_kg, 1)}</td><td className="zahl">{w.kg_pro_kiste?.toFixed(2) ?? '—'}</td><td className="zahl">{w.kg_pro_kuerbis?.toFixed(2) ?? '—'}</td></tr>
            ))}</tbody>
          </table></div>
          <p className="leise" style={{ marginTop: '.5rem' }}>⚠ = sichtbar Faules auf der Palette; zählt nicht in die Verdunstungsrate.</p>
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
    { name: 'Ausschuss gewogen statt geschätzt', ab: 'AB-03', ist: q.ausschuss_gewogen, von: q.ausschuss_messungen, hinweis: 'gewogen ist verlässlich, geschätzt nur Notweg' },
    { name: 'Sortier-CSV einer Arbeit zugeordnet', ab: '—', ist: q.sortierlaeufe_zugeordnet, von: q.sortierlaeufe, hinweis: 'unzugeordnet: Betrieb → Warteschlange' },
    { name: 'Kisten am Sortieren gezählt', ab: 'AB-12', ist: q.sortier_arbeiten_mit_kisten, von: q.sortier_arbeiten, hinweis: 'daraus entsteht das Kistengewicht' },
    { name: 'Kisten am Waschbecken gezählt (mit Kaliber)', ab: 'AB-12', ist: q.wasch_arbeiten_mit_kisten, von: q.wasch_arbeiten, hinweis: 'sonst hat der Schimmel am Waschbecken keinen Nenner' },
  ]
  return (
    <Karte titel="Wie vollständig wird erfasst?">
      <p className="leise">Je Zeile eine Absprache aus der Halle (docs/ABMACHUNGEN.md) und wie oft sie eingehalten wurde. Was hier fehlt, fehlt der Auswertung.</p>
      {zeilen.map(z => {
        const anteil = z.von > 0 ? z.ist / z.von : null
        return (
          <div key={z.name} style={{ marginBottom: '.7rem' }}>
            <div className="reihe" style={{ fontSize: '.9rem' }}>
              <span>{z.name} <span className="leise">{z.ab}</span></span>
              <span style={{ marginLeft: 'auto' }}>{z.von === 0 ? <span className="leise">noch nichts</span> : <><strong>{z.ist}</strong> von {z.von} · {prozent(anteil, 0)}</>}</span>
            </div>
            <div className="balken-spur" style={{ height: 10 }}>
              <div className="balken-fuellung" style={{ width: `${(anteil ?? 0) * 100}%`, background: anteil !== null && anteil < 0.8 ? 'var(--rot)' : 'var(--gruen)' }} />
            </div>
            {anteil !== null && anteil < 1 && <div className="leise" style={{ fontSize: '.8rem', marginTop: '.15rem' }}>{z.hinweis}</div>}
          </div>
        )
      })}
      <p className="leise" style={{ margin: '.5rem 0 0' }}>
        Lagerkontrollen: <strong>{q.lagerkontrollen}</strong>{q.lagerkontrollen > 0 && <>, davon {q.lagerkontrollen_zufaellig} zufällig unter den erreichbaren gegriffen (AB-09)</>}. Zwölf je Saison machen den Bereich des Sockels ehrlich.
      </p>
    </Karte>
  )
}
