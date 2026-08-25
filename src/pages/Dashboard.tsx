import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, kg, prozent, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Balken, Hinweis, Karte, Kennzahl, Lade, Marke, Rechenweg } from '../components/Bausteine'
import type { Datenlage, Hochrechnung, Massenbilanz, Ranking } from '../lib/typen'

type Ebene = 1 | 2 | 3

/** v_schimmel_modell — das angepasste Verderbsmodell F(t) = 1 − exp(−λ·t^k). */
interface Modell {
  n: number; c_chargen: number; t_min: number; t_max: number
  k: number | null; lambda: number | null; smearing: number | null
  brauchbar: boolean
}

/** v_selektionsverdacht — sagen zufällig gegriffene und nach Aussehen
 *  ausgewählte Paletten dasselbe? */
interface Selektion {
  n_verarbeitung: number | null; n_lager: number | null
  unterschied: number | null; befund: string
}

interface StromSumme {
  strom: string
  buch: string
  mittel: number; unten: number; oben: number
  beobachtet: number; projiziert: number; extrapoliert: number
  basis: number
  koeffN: number | null
  koeffBasis: string | null
  formel: string
  /** false, solange die Datenbank für diesen Filter noch keinen Bereich
   *  geliefert hat. Ein Bereich aus summierten Zeilen wäre falsch. */
  bereichBekannt: boolean
}

export default function Dashboard() {
  const [zeilen, setZeilen] = useState<Hochrechnung[]>([])
  const [ranking, setRanking] = useState<Ranking[]>([])
  const [bilanz, setBilanz] = useState<Massenbilanz[]>([])
  const [lage, setLage] = useState<Datenlage[]>([])
  const [befunde, setBefunde] = useState<{ art: string; charge_nr: number; sorte: string
    befund: string; rat: string }[]>([])
  const [kaliber, setKaliber] = useState<{ charge_nr: number; sorte: string; klasse: string
    band_von: number | null; band_bis: number | null; n_kuerbis: number; masse_kg: number }[]>([])
  const [kurve, setKurve] = useState<{ altersklasse: string; messungen: number
    gemessen: number | null; verwendet: number | null; erlaeuterung: string }[]>([])
  const [koeff, setKoeff] = useState<{ was: string; wert: string; n: number; basis: string }[]>([])
  const [modell, setModell] = useState<Modell | null>(null)
  const [selektion, setSelektion] = useState<Selektion | null>(null)
  const [wiegungen, setWiegungen] = useState<{ id: number; charge_nr: number; sorte: string
    lagertage: number; netto_damals_kg: number | null; netto_jetzt_kg: number | null
    kg_pro_kiste: number | null; kg_pro_kuerbis: number | null; verlust_kg: number | null
    sichtbar_schimmel: boolean }[]>([])
  const [marge, setMarge] = useState<{ posten: string; kg: number | null; kg_unten: number | null
    kg_oben: number | null; erlaeuterung: string }[]>([])
  const [laedt, setLaedt] = useState(true)
  const [rechnet, setRechnet] = useState(false)
  const [stand, setStand] = useState<string | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)

  const [ebene, setEbene] = useState<Ebene>(1)
  const [sorte, setSorte] = useState('')
  const [schlag, setSchlag] = useState('')
  const [minLagertage, setMinLagertage] = useState('')

  /**
   * Die Auswertung liegt gespeichert vor (Migration 0016) statt bei jedem
   * Hinschauen neu gerechnet zu werden — sonst bricht Supabase ab, sobald
   * genug Daten da sind. Wurde seit der letzten Rechnung etwas erfasst, wird
   * hier einmal nachgerechnet; das dauert unter einer Sekunde.
   */
  const laden = useCallback(async (erzwingen = false) => {
    setLaedt(true)
    try {
      const { data: st } = await supabase.from('auswertung_stand')
        .select('berechnet_ts, geaendert_ts').maybeSingle()
      const veraltet = !st?.berechnet_ts
        || new Date(st.geaendert_ts) > new Date(st.berechnet_ts)
      if (veraltet || erzwingen) {
        setRechnet(true)
        const { error } = await supabase.rpc('auswertung_aktualisieren')
        setRechnet(false)
        if (error) throw error
      }
      const { data: st2 } = await supabase.from('auswertung_stand')
        .select('berechnet_ts').maybeSingle()
      setStand(st2?.berechnet_ts ?? null)
      await datenLaden()
    } catch (f) {
      setFehler(fehlerText(f))
    } finally { setLaedt(false) }
  }, [])

  useEffect(() => { void laden() }, [laden])

  /** Der Bereich je Strom kommt aus der Datenbank, weil er sich nicht aus
   *  gefilterten Zeilen summieren lässt (Fehlerfortpflanzung, nicht Addition).
   *  Deshalb bei jeder Filteränderung neu holen — es sind ein paar Dutzend
   *  Zeilen, die Rechnung läuft auf gespeicherten Ansichten. */
  useEffect(() => {
    let verworfen = false
    void (async () => {
      const { data, error } = await supabase.rpc('verlust_ranking', {
        p_sorte: sorte || null,
        p_schlag: schlag || null,
        p_min_lagertage: minLagertage ? Number(minLagertage) : null,
      })
      if (!verworfen && !error) setRanking((data ?? []) as Ranking[])
    })()
    return () => { verworfen = true }
  }, [sorte, schlag, minLagertage, stand])

  const datenLaden = async () => {
    void (async () => {
      try {
        const [h, b, d, m, pl, wk, kv, sk, kfv, kfa, kfn, kfu, mo, sel] = await Promise.all([
          supabase.from('v_hochrechnung').select('*'),
          supabase.from('v_massenbilanz').select('*'),
          supabase.from('v_datenlage').select('*'),
          supabase.from('v_marge_buch').select('*'),
          supabase.from('v_plausibilitaet').select('*'),
          supabase.from('v_wiegung_kennzahl').select('*').order('wiege_ts', { ascending: false }),
          supabase.from('v_kaliber_verteilung').select('*'),
          supabase.from('v_schimmel_kurve_anzeige').select('*'),
          supabase.from('v_koeff_verdunstung').select('*'),
          supabase.from('v_koeff_ausschuss').select('*'),
          supabase.from('v_koeff_nebenkanal').select('*'),
          supabase.from('v_koeff_ueberfuellung').select('*'),
          supabase.from('v_schimmel_modell').select('*').maybeSingle(),
          supabase.from('v_selektionsverdacht').select('*').maybeSingle(),
        ])
        if (h.error) throw h.error
        setZeilen((h.data ?? []) as Hochrechnung[])
        setBilanz((b.data ?? []) as Massenbilanz[])
        setLage((d.data ?? []) as Datenlage[])
        setMarge((m.data ?? []) as typeof marge)
        setBefunde((pl.data ?? []) as typeof befunde)
        setWiegungen((wk.data ?? []) as typeof wiegungen)
        setKaliber((kv.data ?? []) as typeof kaliber)
        setKurve((sk.data ?? []) as typeof kurve)
        setModell((mo.data ?? null) as Modell | null)
        setSelektion((sel.data ?? null) as Selektion | null)

        // Die vier Koeffizienten in einer Tabelle: das Innenleben der Rechnung.
        type K = { sorte?: string; mittel?: number | null; n: number; basis?: string
                   kg_pro_kiste?: number | null }
        const mittelwert = (rohe: K[]) => {
          const gute = rohe.filter(r => r.mittel !== null && r.mittel !== undefined)
          if (!gute.length) return null
          return gute.reduce((a, r) => a + (r.mittel ?? 0), 0) / gute.length
        }
        const bestBasis = (rohe: K[]) =>
          rohe.find(r => r.basis?.includes('dieser Sorte'))?.basis
          ?? rohe.find(r => r.basis && !r.basis.startsWith('keine'))?.basis ?? '—'
        const maxN = (rohe: K[]) => rohe.reduce((a, r) => Math.max(a, r.n ?? 0), 0)

        const kv2 = (kfv.data ?? []) as K[], ka = (kfa.data ?? []) as K[]
        const kn = (kfn.data ?? []) as K[], ku = ((kfu.data ?? []) as K[])[0]
        setKoeff([
          { was: 'Verdunstung je Tag', n: maxN(kv2), basis: bestBasis(kv2),
            wert: mittelwert(kv2) === null ? '—' : `${(mittelwert(kv2)! * 100).toFixed(4)} %` },
          { was: 'Ausschuss zu klein', n: maxN(ka), basis: bestBasis(ka),
            wert: mittelwert(ka) === null ? '—' : `${(mittelwert(ka)! * 100).toFixed(2)} %` },
          { was: 'Nebenkanal zu gross', n: maxN(kn), basis: bestBasis(kn),
            wert: mittelwert(kn) === null ? '—' : `${(mittelwert(kn)! * 100).toFixed(2)} %` },
          { was: 'Überfüllung je Kiste', n: ku?.n ?? 0, basis: 'gewogene Ausgangspaletten',
            wert: ku?.kg_pro_kiste == null ? '—' : `${ku.kg_pro_kiste.toFixed(3)} kg` },
        ])
      } catch (f) {
        setFehler(fehlerText(f))
      }
    })()
  }

  const sorten = useMemo(() => [...new Set(zeilen.map(z => z.sorte))].sort(), [zeilen])
  const schlaege = useMemo(() => [...new Set(zeilen.map(z => z.schlag))].sort(), [zeilen])

  const gefiltert = useMemo(() => zeilen.filter(z =>
    (!sorte || z.sorte === sorte)
    && (!schlag || z.schlag === schlag)
    && (!minLagertage || z.alter_tage >= Number(minLagertage))), [zeilen, sorte, schlag, minLagertage])

  /** Summiert die Langform je Strom auf. Die Kilos lassen sich addieren, der
      Bereich nicht: Fehler setzen sich je nach Korrelation quadratisch oder
      linear zusammen, nie durch Summieren. Den Bereich rechnet deshalb
      verlust_ranking() in der Datenbank — mit denselben Filtern. */
  const stroeme = useMemo<StromSumme[]>(() => {
    const map = new Map<string, StromSumme>()
    for (const z of gefiltert) {
      if (z.kg === null) continue
      let s = map.get(z.strom)
      if (!s) {
        s = { strom: z.strom, buch: z.buch, mittel: 0, unten: 0, oben: 0,
              beobachtet: 0, projiziert: 0, extrapoliert: 0, basis: 0,
              koeffN: z.koeff_n, koeffBasis: z.koeff_basis, formel: z.formel,
              bereichBekannt: false }
        map.set(z.strom, s)
      }
      s.mittel += z.kg
      s.basis += z.basis_kg ?? 0
      if (z.portion === 'ausgelagert') s.beobachtet += z.kg; else s.projiziert += z.kg
      if (z.f_extrapoliert) s.extrapoliert += z.kg
      // Die kleinste Stichprobe bestimmt, wie belastbar die Zahl ist.
      if (z.koeff_n !== null) s.koeffN = s.koeffN === null ? z.koeff_n : Math.min(s.koeffN, z.koeff_n)
    }
    for (const r of ranking) {
      const s = map.get(r.strom)
      if (!s || r.kg_unten === null || r.kg_oben === null) continue
      s.unten = r.kg_unten
      s.oben = r.kg_oben
      s.bereichBekannt = true
    }
    return [...map.values()]
  }, [gefiltert, ranking])

  const verluste = stroeme.filter(s => s.buch === 'verlust').sort((a, b) => b.mittel - a.mittel)
  const eingang = useMemo(() => {
    // je Charge nur einmal zählen, egal über wie viele Zeilen sie verteilt ist
    const proCharge = new Map<number, number>()
    for (const z of gefiltert) proCharge.set(z.charge_nr, z.eingang_kg)
    return [...proCharge.values()].reduce((a, b) => a + b, 0)
  }, [gefiltert])

  const verlustGesamt = verluste.reduce((s, v) => s + v.mittel, 0)
  const maximum = Math.max(...verluste.map(v => Math.max(v.mittel, v.oben)), 1)

  if (laedt) return <Lade text={rechnet ? 'Auswertung wird gerechnet …' : 'Lädt …'} />
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
      <p className="leise" style={{ marginTop: '1rem', marginBottom: '.5rem' }}>
        Stand: {stand ? zeitpunkt(stand) : '—'}
        {' · '}
        <button style={{ minHeight: 28, padding: '.1rem .5rem' }}
                onClick={() => void laden(true)}>neu rechnen</button>
      </p>

      <div className="reihe">
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
        <Rohdaten zeilen={gefiltert} bilanz={bilanz} lage={lage} wiegungen={wiegungen}
                  kaliber={kaliber} kurve={kurve} koeff={koeff}
                  modell={modell} selektion={selektion} />
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
    ['Bereich', v.bereichBekannt
      ? `${kg(v.unten, 0)} – ${kg(v.oben, 0)} (95 %, aus den Messfehlern fortgepflanzt)`
      : 'wird gerechnet …'],
    ['Davon beobachtet', kg(v.beobachtet, 0)],
    ['Davon projiziert', `${kg(v.projiziert, 0)} — Ware, die noch im Lager liegt`],
    ['Davon hochgerechnet', v.extrapoliert > 0
      ? `${kg(v.extrapoliert, 0)} — liegt länger als die längste gemessene Lagerdauer, `
        + 'der Verlauf ist dorthin verlängert'
      : 'nichts — alle Lagerdauern sind durch Messungen abgedeckt'],
  ]
}

function Ueberblick({ verluste, eingang, verlustGesamt, maximum }: {
  verluste: StromSumme[]; eingang: number; verlustGesamt: number; maximum: number
}) {
  const haupt = verluste[0]
  const duenn = verluste.filter(v => (v.koeffN ?? 0) < 3)

  // Zwei Ströme, deren Bereiche sich überschneiden, lassen sich mit dieser
  // Datengrundlage nicht auseinanderhalten. In der Simulation gab es keinen
  // Fall, in dem die Rangfolge kippte, ohne dass die Bereiche es anzeigten —
  // deshalb steht es hier, statt es der Balkenlänge zu überlassen.
  const ununterscheidbar = verluste
    .slice(0, -1)
    .map((v, i) => [v, verluste[i + 1]] as const)
    .filter(([a, b]) => a.bereichBekannt && b.bereichBekannt && a.unten <= b.oben)
    .map(([a, b]) => `${a.strom} und ${b.strom}`)

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
        {ununterscheidbar.length > 0 && (
          <Hinweis art="info">
            Nicht auseinanderzuhalten: {ununterscheidbar.join(', ')}. Die Bereiche
            überschneiden sich — welcher davon größer ist, geben die Messungen
            nicht her. Die Reihenfolge der Balken ist dort Zufall.
          </Hinweis>
        )}
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

function Rohdaten({ zeilen, bilanz, lage, wiegungen, kaliber, kurve, koeff,
                   modell, selektion }: {
  zeilen: Hochrechnung[]; bilanz: Massenbilanz[]; lage: Datenlage[]
  wiegungen: { id: number; charge_nr: number; sorte: string; lagertage: number
    netto_damals_kg: number | null; netto_jetzt_kg: number | null
    kg_pro_kiste: number | null; kg_pro_kuerbis: number | null
    verlust_kg: number | null; sichtbar_schimmel: boolean }[]
  kaliber: { charge_nr: number; sorte: string; klasse: string; band_von: number | null
    band_bis: number | null; n_kuerbis: number; masse_kg: number }[]
  kurve: { altersklasse: string; messungen: number; gemessen: number | null
    verwendet: number | null; erlaeuterung: string }[]
  koeff: { was: string; wert: string; n: number; basis: string }[]
  modell: Modell | null; selektion: Selektion | null
}) {
  // Seit 0019 gibt es je Charge und Portion nur noch eine Zeile je Strom —
  // die drei Szenarien sind durch die Fehlerfortpflanzung ersetzt.
  const mittel = zeilen.filter(z => z.buch !== 'bilanz')
  const taraLuecken = lage.filter(l => l.n_paletten > 0 && l.n_paletten_mit_netto < l.n_paletten)

  function exportieren() {
    const kopf = ['charge_nr', 'sorte', 'schlag', 'portion', 'alter_tage', 'strom', 'buch',
                  'kg', 'basis_kg', 'koeffizient', 'koeff_n', 'koeff_basis',
                  'f_extrapoliert', 'formel']
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

      <Karte titel="Die vier Koeffizienten">
        <p className="leise">
          Das Innenleben der Hochrechnung. Jede Zahl im Dashboard entsteht als
          <em> Koeffizient × bekannte Größe</em>. Stimmt ein Koeffizient nicht,
          stimmt alles darüber nicht — hier steht, worauf er beruht.
        </p>
        <div className="rollbar">
          <table>
            <thead><tr><th>Koeffizient</th><th className="zahl">Wert</th>
              <th className="zahl">Messungen</th><th>Herkunft</th></tr></thead>
            <tbody>
              {koeff.map(k => (
                <tr key={k.was}>
                  <td>{k.was}</td>
                  <td className="zahl"><strong>{k.wert}</strong></td>
                  <td className="zahl">
                    {k.n > 0 ? k.n : <Marke art="warnung">keine</Marke>}
                  </td>
                  <td className="leise">{k.basis}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Karte>

      {modell && (
        <Karte titel="Das Verderbsmodell — und was es nicht weiß">
          <p className="leise">
            Der Schimmelverlauf wird nicht Altersklasse für Altersklasse
            abgelesen, sondern als Kurve an alle Messungen angepasst:
            F(t) = 1 − exp(−λ·t<sup>k</sup>). Nur so lässt sich sagen, was mit
            Ware passiert, die länger liegt als alles bisher Verarbeitete — und
            das ist mitten in der Saison die halbe Ernte.
          </p>
          {!modell.brauchbar ? (
            <Hinweis art="warnung">
              Für eine Kurve reicht es noch nicht — nötig sind Schimmelmessungen
              aus mindestens drei Chargen über deutlich verschiedene Lagerdauern.
              Solange gilt der zuletzt gemessene Wert. Ware, die länger liegt als
              die längste Messung, wird damit zu günstig gerechnet.
            </Hinweis>
          ) : (
            <div className="rollbar">
              <table>
                <tbody>
                  <tr><td>Form der Kurve (k)</td>
                      <td className="zahl"><strong>{modell.k?.toFixed(2)}</strong></td>
                      <td className="leise">über 1 heißt: die Verderbrate steigt mit
                          der Lagerdauer</td></tr>
                  <tr><td>Gemessener Bereich</td>
                      <td className="zahl"><strong>{Math.round(modell.t_min)}–
                          {Math.round(modell.t_max)} Tage</strong></td>
                      <td className="leise">darüber hinaus wird gerechnet, nicht
                          gemessen — der Bereich wird dort von selbst breiter</td></tr>
                  <tr><td>Messungen</td>
                      <td className="zahl"><strong>{modell.n}</strong></td>
                      <td className="leise">aus {modell.c_chargen} Chargen — und die
                          Chargen zählen, nicht die Messungen: was aus derselben
                          Charge kommt, ist sich ähnlich</td></tr>
                  <tr><td>Rückrechnung (Smearing)</td>
                      <td className="zahl"><strong>×{modell.smearing?.toFixed(3)}</strong></td>
                      <td className="leise">gleicht aus, dass die Anpassung im
                          Logarithmus rechnet und sonst systematisch zu tief landet</td></tr>
                </tbody>
              </table>
            </div>
          )}
          {selektion && (
            <Hinweis art={(selektion.n_lager ?? 0) < 5 ? 'warnung' : 'info'}>
              <strong>Auswahl der gemessenen Paletten:</strong> {selektion.befund}
              {(selektion.n_lager ?? 0) < 5 && (
                <> Wer schlecht aussieht, kommt zuerst dran — dadurch wird der
                  Verlauf flacher gemessen, als er ist. Dagegen hilft nur eine
                  Handvoll zufällig gegriffener Lagerpaletten je Saison: beim
                  Wiegen „Faules sichtbar" ankreuzen und die Kilo eintragen.
                  Zwei Paletten im Monat genügen.</>
              )}
            </Hinweis>
          )}
        </Karte>
      )}

      {kurve.length > 0 && (
        <Karte titel="Schimmelkurve">
          <p className="leise">
            Wie viel Masse bis zu einer bestimmten Lagerdauer verdorben ist —
            kumulativ. „Verwendet" kann über „Gemessen" liegen: Verdorbene Ware
            wird nicht wieder gesund, deshalb darf die Kurve nicht fallen.
          </p>
          <div className="rollbar">
            <table>
              <thead><tr><th>Lagerdauer</th><th className="zahl">Messungen</th>
                <th className="zahl">Gemessen</th><th className="zahl">Verwendet</th>
                <th>Warum</th></tr></thead>
              <tbody>
                {kurve.map(k => (
                  <tr key={k.altersklasse}>
                    <td>{k.altersklasse}</td>
                    <td className="zahl">{k.messungen || '—'}</td>
                    <td className="zahl">{prozent(k.gemessen, 2)}</td>
                    <td className="zahl"><strong>{prozent(k.verwendet, 2)}</strong></td>
                    <td className="leise" style={{ fontSize: '.8rem' }}>{k.erlaeuterung}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Karte>
      )}

      {kaliber.length > 0 && <Kaliber zeilen={kaliber} />}

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

/**
 * Die Kaliber-Verteilung aus den Sortier-CSVs. Auf der Maschinen-Linie wird je
 * Stück innerhalb eines Kalibers bezahlt, das Gewicht ist egal — wer weiß, wie
 * sich eine Sorte über die Bänder verteilt, kann ein engeres Band liefern
 * (Spec §3). Das ist die einzige Auswertung hier, die nicht von Verlusten
 * handelt, sondern vom Erlös.
 */
function Kaliber({ zeilen }: {
  zeilen: { charge_nr: number; sorte: string; klasse: string; band_von: number | null
    band_bis: number | null; n_kuerbis: number; masse_kg: number }[]
}) {
  const [sorte, setSorte] = useState('')
  const sorten = [...new Set(zeilen.map(z => z.sorte))].sort()
  const gezeigt = sorte ? sorten.filter(s => s === sorte) : sorten

  return (
    <Karte titel="Kaliber-Verteilung"
           aktion={
             <select value={sorte} onChange={e => setSorte(e.target.value)}
                     style={{ width: 'auto', minHeight: 36 }}>
               <option value="">alle Sorten</option>
               {sorten.map(s => <option key={s}>{s}</option>)}
             </select>
           }>
      <p className="leise">
        Wie sich die sortierten Kürbisse über die Kaliber verteilen. Bezahlt wird
        je Stück innerhalb eines Kalibers — wer weiß, wo eine Sorte liegt, kann
        ein engeres Band liefern.
      </p>
      {gezeigt.map(s => {
        const eigene = zeilen.filter(z => z.sorte === s)
        const gesamt = eigene.reduce((a, z) => a + z.n_kuerbis, 0)
        const maximum = Math.max(...eigene.map(z => z.n_kuerbis), 1)
        const sortiert = [...eigene].sort((a, b) => (a.band_von ?? -1) - (b.band_von ?? -1))
        return (
          <div key={s} style={{ marginBottom: '1.5rem' }}>
            <div className="reihe">
              <strong>{s}</strong>
              <span className="leise" style={{ marginLeft: 'auto' }}>
                {zahl(gesamt)} Kürbisse
              </span>
            </div>
            {sortiert.map((z, i) => {
              const name = z.klasse === 'verlust_klein' ? 'zu klein (Verlust)'
                : z.klasse === 'nebenkanal' ? 'ab 2000 g (anderer Kanal)'
                : `${z.band_von}–${z.band_bis} g`
              const farbe = z.klasse === 'verlust_klein' ? 'var(--rot)'
                : z.klasse === 'nebenkanal' ? 'var(--blau)' : 'var(--kuerbis)'
              return (
                <div key={i} style={{ marginTop: '.4rem' }}>
                  <div className="reihe" style={{ fontSize: '.85rem' }}>
                    <span>{name}</span>
                    <span className="leise" style={{ marginLeft: 'auto' }}>
                      {zahl(z.n_kuerbis)} · {prozent(gesamt > 0 ? z.n_kuerbis / gesamt : null)}
                    </span>
                  </div>
                  <div className="balken-spur" style={{ height: 18 }}>
                    <div className="balken-fuellung"
                         style={{ width: `${(z.n_kuerbis / maximum) * 100}%`, background: farbe }} />
                  </div>
                </div>
              )
            })}
          </div>
        )
      })}
    </Karte>
  )
}
