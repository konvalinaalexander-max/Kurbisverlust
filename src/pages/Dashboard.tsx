import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Balken, Hinweis, Karte, Kennzahl, Lade, Marke, Rechenweg } from '../components/Bausteine'
import type { Datenlage, Hochrechnung, Massenbilanz } from '../lib/typen'

type Ebene = 1 | 2 | 3

interface StromSumme {
  strom: string
  buch: string
  mittel: number; unten: number; oben: number
  beobachtet: number; projiziert: number
  basis: number
  koeffN: number | null
  koeffBasis: string | null
  formel: string
}

export default function Dashboard() {
  const [zeilen, setZeilen] = useState<Hochrechnung[]>([])
  const [bilanz, setBilanz] = useState<Massenbilanz[]>([])
  const [lage, setLage] = useState<Datenlage[]>([])
  const [befunde, setBefunde] = useState<{ art: string; charge_nr: number; sorte: string
    befund: string; rat: string }[]>([])
  const [wiegungen, setWiegungen] = useState<{ id: number; charge_nr: number; sorte: string
    lagertage: number; netto_damals_kg: number | null; netto_jetzt_kg: number | null
    kg_pro_kiste: number | null; kg_pro_kuerbis: number | null; verlust_kg: number | null
    sichtbar_schimmel: boolean }[]>([])
  const [marge, setMarge] = useState<{ posten: string; kg: number | null; kg_unten: number | null
    kg_oben: number | null; erlaeuterung: string }[]>([])
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)

  const [ebene, setEbene] = useState<Ebene>(1)
  const [sorte, setSorte] = useState('')
  const [schlag, setSchlag] = useState('')
  const [minLagertage, setMinLagertage] = useState('')

  useEffect(() => {
    void (async () => {
      try {
        const [h, b, d, m, pl, wk] = await Promise.all([
          supabase.from('v_hochrechnung').select('*'),
          supabase.from('v_massenbilanz').select('*'),
          supabase.from('v_datenlage').select('*'),
          supabase.from('v_marge_buch').select('*'),
          supabase.from('v_plausibilitaet').select('*'),
          supabase.from('v_wiegung_kennzahl').select('*').order('wiege_ts', { ascending: false }),
        ])
        if (h.error) throw h.error
        setZeilen((h.data ?? []) as Hochrechnung[])
        setBilanz((b.data ?? []) as Massenbilanz[])
        setLage((d.data ?? []) as Datenlage[])
        setMarge((m.data ?? []) as typeof marge)
        setBefunde((pl.data ?? []) as typeof befunde)
        setWiegungen((wk.data ?? []) as typeof wiegungen)
      } catch (f) {
        setFehler(fehlerText(f))
      } finally { setLaedt(false) }
    })()
  }, [])

  const sorten = useMemo(() => [...new Set(zeilen.map(z => z.sorte))].sort(), [zeilen])
  const schlaege = useMemo(() => [...new Set(zeilen.map(z => z.schlag))].sort(), [zeilen])

  const gefiltert = useMemo(() => zeilen.filter(z =>
    (!sorte || z.sorte === sorte)
    && (!schlag || z.schlag === schlag)
    && (!minLagertage || z.alter_tage >= Number(minLagertage))), [zeilen, sorte, schlag, minLagertage])

  /** Summiert die Langform je Strom auf — dieselbe Rechnung wie v_verlust_ranking,
      nur mit den hier gesetzten Filtern. */
  const stroeme = useMemo<StromSumme[]>(() => {
    const map = new Map<string, StromSumme>()
    for (const z of gefiltert) {
      if (z.kg === null) continue
      let s = map.get(z.strom)
      if (!s) {
        s = { strom: z.strom, buch: z.buch, mittel: 0, unten: 0, oben: 0,
              beobachtet: 0, projiziert: 0, basis: 0,
              koeffN: z.koeff_n, koeffBasis: z.koeff_basis, formel: z.formel }
        map.set(z.strom, s)
      }
      if (z.szenario === 'mittel') {
        s.mittel += z.kg
        s.basis += z.basis_kg ?? 0
        if (z.portion === 'ausgelagert') s.beobachtet += z.kg; else s.projiziert += z.kg
        // Die kleinste Stichprobe bestimmt, wie belastbar die Zahl ist.
        if (z.koeff_n !== null) s.koeffN = s.koeffN === null ? z.koeff_n : Math.min(s.koeffN, z.koeff_n)
      } else if (z.szenario === 'unten') s.unten += z.kg
      else s.oben += z.kg
    }
    return [...map.values()]
  }, [gefiltert])

  const verluste = stroeme.filter(s => s.buch === 'verlust').sort((a, b) => b.mittel - a.mittel)
  const eingang = useMemo(() => {
    // je Charge nur einmal zählen, egal über wie viele Zeilen sie verteilt ist
    const proCharge = new Map<number, number>()
    for (const z of gefiltert) proCharge.set(z.charge_nr, z.eingang_kg)
    return [...proCharge.values()].reduce((a, b) => a + b, 0)
  }, [gefiltert])

  const verlustGesamt = verluste.reduce((s, v) => s + v.mittel, 0)
  const maximum = Math.max(...verluste.map(v => Math.max(v.mittel, v.oben)), 1)

  if (laedt) return <Lade text="Auswertung wird gerechnet …" />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (zeilen.length === 0) {
    return (
      <Hinweis>
        Noch keine auswertbaren Daten. Dafür braucht es mindestens Eingangspaletten
        mit hinterlegter Tara — siehe Stammdaten.
      </Hinweis>
    )
  }

  return (
    <>
      <div className="reihe" style={{ marginTop: '1rem' }}>
        {([1, 2, 3] as Ebene[]).map(e => (
          <button key={e} className={ebene === e ? 'haupt' : ''} style={{ flex: 1 }}
                  onClick={() => setEbene(e)}>
            {['Überblick', 'Aufschlüsselung', 'Rohdaten'][e - 1]}
          </button>
        ))}
      </div>

      {(sorte || schlag || minLagertage) && (
        <p className="leise" style={{ marginTop: '.5rem' }}>
          Gefiltert: {[sorte, schlag, minLagertage && `ab ${minLagertage} Lagertagen`]
            .filter(Boolean).join(' · ')}
          {' '}<button style={{ minHeight: 28, padding: '.1rem .5rem' }}
                       onClick={() => { setSorte(''); setSchlag(''); setMinLagertage('') }}>
            zurücksetzen
          </button>
        </p>
      )}

      {befunde.length > 0 && (
        <Hinweis art="warnung">
          <strong>{befunde.length} Messung{befunde.length === 1 ? '' : 'en'} sieht nicht richtig aus</strong>
          <p style={{ margin: '.4rem 0' }}>
            Diese Werte fließen bewusst <em>nicht</em> in die Rechnung ein — sie würden sie
            verfälschen. Fast immer ist es ein Tippfehler, der sich korrigieren lässt.
          </p>
          <ul style={{ margin: 0, paddingLeft: '1.2rem' }}>
            {befunde.slice(0, 8).map((b, i) => (
              <li key={i} style={{ marginBottom: '.3rem' }}>
                <strong>Charge {b.charge_nr} · {b.sorte}</strong> — {b.befund}
                <br /><span className="leise">{b.rat}</span>
              </li>
            ))}
          </ul>
        </Hinweis>
      )}

      {ebene === 1 && (
        <Ueberblick verluste={verluste} eingang={eingang} verlustGesamt={verlustGesamt}
                    maximum={maximum} />
      )}

      {ebene === 2 && (
        <>
          <Karte titel="Filter">
            <div className="spalten">
              <div className="feld">
                <label htmlFor="fs">Sorte</label>
                <select id="fs" value={sorte} onChange={e => setSorte(e.target.value)}>
                  <option value="">alle</option>
                  {sorten.map(s => <option key={s}>{s}</option>)}
                </select>
              </div>
              <div className="feld">
                <label htmlFor="fl">Schlag</label>
                <select id="fl" value={schlag} onChange={e => setSchlag(e.target.value)}>
                  <option value="">alle</option>
                  {schlaege.map(s => <option key={s}>{s}</option>)}
                </select>
              </div>
              <div className="feld">
                <label htmlFor="ft">Ab Lagerdauer (Tage)</label>
                <input id="ft" type="number" min={0} value={minLagertage}
                       onChange={e => setMinLagertage(e.target.value)} />
              </div>
            </div>
          </Karte>

          <Karte titel="Buch A — physischer Verlust">
            {verluste.map(v => (
              <div key={v.strom} style={{ marginBottom: '1.25rem' }}>
                <div className="reihe">
                  <strong>{v.strom}</strong>
                  <span style={{ marginLeft: 'auto' }}>{tonnen(v.mittel)}</span>
                </div>
                <Balken wert={v.mittel} unten={v.unten} oben={v.oben}
                        maximum={maximum} beobachtet={v.beobachtet} />
                <p className="leise" style={{ margin: '.25rem 0 0' }}>
                  {tonnen(v.beobachtet)} beobachtet · {tonnen(v.projiziert)} projiziert ·
                  {' '}Bereich {tonnen(v.unten)} – {tonnen(v.oben)}
                </p>
                <Rechenweg zeilen={rechenweg(v, eingang)} />
              </div>
            ))}
          </Karte>

          <Karte titel="Buch B — verschenkte Marge">
            <p className="leise">
              Kein Verlust: die Ware ist verkauft oder verkäuflich, nur nicht zum
              besten Preis. Wird nie mit Buch A vermischt.
            </p>
            {marge.length === 0
              ? <p className="leise">Noch nichts gemessen.</p>
              : marge.map(m => (
                  <div key={m.posten} style={{ marginBottom: '1rem' }}>
                    <div className="reihe">
                      <strong>{m.posten}</strong>
                      <span style={{ marginLeft: 'auto' }}>{tonnen(m.kg)}</span>
                    </div>
                    <p className="leise" style={{ margin: 0 }}>{m.erlaeuterung}</p>
                  </div>
                ))}
          </Karte>
        </>
      )}

      {ebene === 3 && (
        <Rohdaten zeilen={gefiltert} bilanz={bilanz} lage={lage} wiegungen={wiegungen} />
      )}
    </>
  )
}

function rechenweg(v: StromSumme, eingang: number): [string, React.ReactNode][] {
  return [
    ['Formel', v.formel],
    ['Bezugsmasse', kg(v.basis, 0)],
    ['Koeffizient', v.koeffBasis
      ? `${v.koeffBasis}${v.koeffN !== null ? ` · ${v.koeffN} Messungen` : ''}`
      : '—'],
    ['Ergebnis', `${kg(v.mittel, 0)} (${prozent(eingang > 0 ? v.mittel / eingang : null)} der Eingangsmasse)`],
    ['Bereich', `${kg(v.unten, 0)} – ${kg(v.oben, 0)}`],
    ['Davon beobachtet', kg(v.beobachtet, 0)],
    ['Davon projiziert', `${kg(v.projiziert, 0)} — Ware, die noch im Lager liegt`],
  ]
}

function Ueberblick({ verluste, eingang, verlustGesamt, maximum }: {
  verluste: StromSumme[]; eingang: number; verlustGesamt: number; maximum: number
}) {
  const haupt = verluste[0]
  const duenn = verluste.filter(v => (v.koeffN ?? 0) < 3)

  return (
    <>
      <Karte>
        <div className="spalten">
          <Kennzahl titel="Eingang" wert={tonnen(eingang)} unter="Netto ab Wareneingang" />
          <Kennzahl titel="Verlust gesamt" wert={tonnen(verlustGesamt)}
                    unter={prozent(eingang > 0 ? verlustGesamt / eingang : null)} />
          <Kennzahl titel="Hauptursache" wert={haupt?.strom ?? '—'}
                    unter={haupt ? `${prozent(verlustGesamt > 0 ? haupt.mittel / verlustGesamt : null)} des Verlusts` : ''} />
        </div>
      </Karte>

      <Karte titel="Ursachen, rangiert">
        <p className="leise">
          Voller Balken = beobachtet, schraffiert = hochgerechnet für Ware, die noch
          im Lager liegt. Der Strich darüber ist der Unsicherheitsbereich.
        </p>
        {verluste.map(v => (
          <div key={v.strom} className="balken-zeile">
            <div className="reihe">
              <strong>{v.strom}</strong>
              {(v.koeffN ?? 0) < 3 && <Marke art="warnung">dünne Datenlage</Marke>}
              <span style={{ marginLeft: 'auto' }}>{tonnen(v.mittel)}</span>
            </div>
            <Balken wert={v.mittel} unten={v.unten} oben={v.oben}
                    maximum={maximum} beobachtet={v.beobachtet} />
          </div>
        ))}
      </Karte>

      {duenn.length > 0 && (
        <Hinweis art="warnung">
          <strong>Diese Zahlen tragen noch nicht.</strong>
          <p style={{ margin: '.4rem 0 0' }}>
            {duenn.map(v => v.strom).join(', ')} {duenn.length === 1 ? 'beruht' : 'beruhen'} auf
            weniger als drei Stichproben. Die Rangfolge kann sich mit jeder weiteren
            Messung noch drehen — unter „Rohdaten" steht, wo eine Messung am meisten bringt.
          </p>
        </Hinweis>
      )}
    </>
  )
}

function Rohdaten({ zeilen, bilanz, lage, wiegungen }: {
  zeilen: Hochrechnung[]; bilanz: Massenbilanz[]; lage: Datenlage[]
  wiegungen: { id: number; charge_nr: number; sorte: string; lagertage: number
    netto_damals_kg: number | null; netto_jetzt_kg: number | null
    kg_pro_kiste: number | null; kg_pro_kuerbis: number | null
    verlust_kg: number | null; sichtbar_schimmel: boolean }[]
}) {
  const mittel = zeilen.filter(z => z.szenario === 'mittel' && z.buch !== 'bilanz')
  const taraLuecken = lage.filter(l => l.n_paletten > 0 && l.n_paletten_mit_netto < l.n_paletten)

  function exportieren() {
    const kopf = ['charge_nr', 'sorte', 'schlag', 'portion', 'alter_tage', 'strom', 'buch',
                  'kg', 'basis_kg', 'koeffizient', 'koeff_n', 'koeff_basis', 'formel']
    const zeilenText = mittel.map(z => kopf.map(k => {
      const w = (z as unknown as Record<string, unknown>)[k]
      const s = w === null || w === undefined ? '' : String(w)
      return /[";\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
    }).join(';'))
    const blob = new Blob(['﻿' + [kopf.join(';'), ...zeilenText].join('\n')],
                          { type: 'text/csv;charset=utf-8' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = 'kuerbis-hochrechnung.csv'
    a.click()
    URL.revokeObjectURL(a.href)
  }

  return (
    <>
      {taraLuecken.length > 0 && (
        <Hinweis art="warnung">
          <strong>Fehlende Tara verzerrt alles darüber.</strong>
          <p style={{ margin: '.4rem 0 0' }}>
            Bei {taraLuecken.length} Chargen fehlt für einen Teil der Paletten das
            Leergewicht des Gebindes. Diese Paletten zählen nicht in die Eingangsmasse,
            die Auswertung unterschätzt sie also. Unter Stammdaten → Gebinde nachtragen.
          </p>
        </Hinweis>
      )}

      <Karte titel="Massenbilanz" aktion={<button onClick={exportieren}>CSV exportieren</button>}>
        <p className="leise">
          Die Probe aufs Exempel: das Modell sagt voraus, wie viel Masse am Sortierband
          ankommen müsste; die CSV hat sie gewogen. Liegen beide nah beieinander,
          stimmen die Koeffizienten.
        </p>
        <div className="rollbar">
          <table>
            <thead>
              <tr>
                <th>Charge</th><th className="zahl">Eingang</th><th className="zahl">ausgelagert</th>
                <th className="zahl">im Lager</th><th className="zahl">Modell</th>
                <th className="zahl">gewogen</th><th className="zahl">Abweichung</th>
              </tr>
            </thead>
            <tbody>
              {bilanz.filter(b => b.eingang_kg !== null).map(b => (
                <tr key={b.charge_nr}>
                  <td>{b.charge_nr} · {b.sorte}</td>
                  <td className="zahl">{kg(b.eingang_kg)}</td>
                  <td className="zahl">{kg(b.ausgelagert_kg)}</td>
                  <td className="zahl">{kg(b.lager_kg)}</td>
                  <td className="zahl">{kg(b.modell_am_band_kg)}</td>
                  <td className="zahl">{kg(b.csv_gemessen_kg)}</td>
                  <td className="zahl">
                    {b.abweichung_anteil === null ? '—' : (
                      <Marke art={Math.abs(b.abweichung_anteil) < 0.1 ? 'fertig' : 'warnung'}>
                        {prozent(b.abweichung_anteil)}
                      </Marke>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Karte>

      {wiegungen.length > 0 && (
        <Karte titel={`Gewogene Paletten (${wiegungen.length})`}>
          <p className="leise">
            Beim Zählen mitgewogen. „kg je Kiste" und — wo die Kürbisse je Kiste
            erfasst wurden — das Durchschnittsgewicht eines einzelnen Kürbisses.
            Auf der Hand-Linie gibt es dafür sonst keine Quelle, weil es dort
            keine Sortier-CSV gibt.
          </p>
          <div className="rollbar">
            <table>
              <thead>
                <tr>
                  <th>Charge</th><th className="zahl">Lagertage</th>
                  <th className="zahl">Netto damals</th><th className="zahl">Netto jetzt</th>
                  <th className="zahl">Verlust</th><th className="zahl">kg/Kiste</th>
                  <th className="zahl">kg/Kürbis</th>
                </tr>
              </thead>
              <tbody>
                {wiegungen.slice(0, 40).map(w => (
                  <tr key={w.id}>
                    <td>{w.charge_nr} · {w.sorte}{w.sichtbar_schimmel ? ' ⚠' : ''}</td>
                    <td className="zahl">{zahl(w.lagertage)}</td>
                    <td className="zahl">{kg(w.netto_damals_kg, 1)}</td>
                    <td className="zahl">{kg(w.netto_jetzt_kg, 1)}</td>
                    <td className="zahl">{kg(w.verlust_kg, 1)}</td>
                    <td className="zahl">{w.kg_pro_kiste?.toFixed(2) ?? '—'}</td>
                    <td className="zahl">{w.kg_pro_kuerbis?.toFixed(2) ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="leise" style={{ marginTop: '.5rem' }}>
            ⚠ = sichtbar Faules auf der Palette. Diese Wägungen zählen bewusst
            nicht in die Verdunstungsrate, sonst würde Fäulnis als Wasserverlust
            verbucht.
          </p>
        </Karte>
      )}

      <Karte titel="Wo fehlen Messungen?">
        <p className="leise">
          Nach Eingangsmasse sortiert: die größten Chargen ohne Stichprobe kosten
          am meisten Genauigkeit.
        </p>
        <div className="rollbar">
          <table>
            <thead>
              <tr>
                <th>Charge</th><th className="zahl">Eingang</th><th className="zahl">Paletten</th>
                <th className="zahl">Wiegungen</th><th className="zahl">Schimmel</th>
                <th className="zahl">CSV-Läufe</th>
              </tr>
            </thead>
            <tbody>
              {[...lage].sort((a, b) => (b.eingang_kg ?? 0) - (a.eingang_kg ?? 0))
                .slice(0, 20).map(l => (
                <tr key={l.charge_nr}>
                  <td>{l.charge_nr} · {l.sorte} · {l.schlag}</td>
                  <td className="zahl">{kg(l.eingang_kg)}</td>
                  <td className="zahl">
                    {zahl(l.n_paletten)}
                    {l.n_paletten_mit_netto < l.n_paletten && ` (${l.n_paletten_mit_netto} m. Netto)`}
                  </td>
                  <td className="zahl">{l.n_wiegungen || '—'}</td>
                  <td className="zahl">{l.n_schimmel || '—'}</td>
                  <td className="zahl">{l.n_sortierlaeufe || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Karte>

      <Karte titel={`Hochrechnung je Charge (${mittel.length} Zeilen)`}>
        <div className="rollbar">
          <table>
            <thead>
              <tr>
                <th>Charge</th><th>Portion</th><th className="zahl">Alter</th>
                <th>Strom</th><th className="zahl">kg</th><th className="zahl">Basis</th>
                <th className="zahl">Koeffizient</th><th>Herkunft</th>
              </tr>
            </thead>
            <tbody>
              {mittel.slice(0, 300).map((z, i) => (
                <tr key={i}>
                  <td>{z.charge_nr} · {z.sorte}</td>
                  <td>{z.portion === 'lager' ? 'im Lager' : 'ausgelagert'}</td>
                  <td className="zahl">{zahl(z.alter_tage)} d</td>
                  <td>{z.strom}</td>
                  <td className="zahl">{kg(z.kg)}</td>
                  <td className="zahl">{kg(z.basis_kg)}</td>
                  <td className="zahl">
                    {z.koeffizient === null ? '—' : prozent(z.koeffizient, 3)}
                  </td>
                  <td className="leise">{z.koeff_basis ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {mittel.length > 300 && (
          <p className="leise">Nur die ersten 300 Zeilen angezeigt — der Export enthält alle.</p>
        )}
      </Karte>

      <Karte titel="Stichtag">
        <p className="leise">
          Ware, die noch im Lager liegt, wird bis zum Stichtag projiziert:
          {' '}<strong>{datum(bilanz[0]?.stichtag)}</strong>. Zu ändern unter
          Stammdaten → Einstellungen.
        </p>
      </Karte>
    </>
  )
}
