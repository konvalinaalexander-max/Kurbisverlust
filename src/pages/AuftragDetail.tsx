import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'
import { chargeText, fehlerText, stammdaten } from '../lib/db'
import { STATION_NAME, WEG_NAME, datum, kg, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
import type { Auftrag, Charge, Gebinde } from '../lib/typen'

type Reiter = 'paletten' | 'faule' | 'ausschuss' | 'wiegen' | 'marge' | 'abschluss'

export default function AuftragDetail() {
  const { id } = useParams()
  const auftragId = Number(id)
  const navigate = useNavigate()
  const { session } = useAuth()

  const [auftrag, setAuftrag] = useState<Auftrag | null>(null)
  const [charge, setCharge] = useState<Charge | undefined>()
  const [teilnehmer, setTeilnehmer] = useState<{ profil_id: string; name: string }[]>([])
  const [reiter, setReiter] = useState<Reiter>('paletten')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laedt, setLaedt] = useState(true)

  const laden = useCallback(async () => {
    try {
      const [{ chargen }, a, t] = await Promise.all([
        stammdaten(),
        supabase.from('auftrag').select('*').eq('id', auftragId).maybeSingle(),
        supabase.from('auftrag_teilnehmer').select('profil_id, profil(name)')
          .eq('auftrag_id', auftragId).is('verlassen_ts', null),
      ])
      if (a.error) throw a.error
      const auf = a.data as Auftrag | null
      setAuftrag(auf)
      setCharge(chargen.find(c => c.nr === auf?.charge_nr))
      // Supabase typisiert eingebettete Relationen als Array, liefert bei
      // einer 1:1-Beziehung aber ein Objekt — beides abfangen.
      type Eintrag = { profil_id: string; profil: { name: string } | { name: string }[] | null }
      setTeilnehmer(((t.data ?? []) as unknown as Eintrag[]).map(r => ({
        profil_id: r.profil_id,
        name: (Array.isArray(r.profil) ? r.profil[0]?.name : r.profil?.name) ?? '?',
      })))
      setFehler(null)
    } catch (f) {
      setFehler(fehlerText(f))
    } finally {
      setLaedt(false)
    }
  }, [auftragId])

  useEffect(() => { void laden() }, [laden])

  if (laedt) return <Lade />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!auftrag) return <Hinweis art="warnung">Diesen Auftrag gibt es nicht.</Hinweis>

  const istWeg2 = auftrag.weg === 'hand'
  const binDabei = teilnehmer.some(t => t.profil_id === session?.user.id)
  const abgeschlossen = auftrag.status === 'abgeschlossen'

  const reiterListe: [Reiter, string][] = [
    ['paletten', 'Paletten'],
    ['faule', 'Faule'],
    ...(istWeg2 ? [['ausschuss', 'Gross / klein'] as [Reiter, string]] : []),
    ['wiegen', 'Palette wiegen'],
    ...(istWeg2 ? [['marge', 'Überfüllung'] as [Reiter, string]] : []),
    ['abschluss', 'Abschluss'],
  ]

  return (
    <>
      <Karte>
        <div className="reihe">
          <h1 style={{ margin: 0 }}>{chargeText(charge)}</h1>
          <Marke art={abgeschlossen ? 'fertig' : 'offen'}>{abgeschlossen ? 'fertig' : 'läuft'}</Marke>
        </div>
        <p className="leise" style={{ marginBottom: '.5rem' }}>
          {WEG_NAME[auftrag.weg]} · {STATION_NAME[auftrag.station]} · seit {zeitpunkt(auftrag.start_ts)}
          {auftrag.geplante_paletten !== null && ` · geplant: ${auftrag.geplante_paletten} Paletten`}
        </p>
        <p className="leise" style={{ marginBottom: 0 }}>
          Dabei: {teilnehmer.length ? teilnehmer.map(t => t.name).join(', ') : 'noch niemand'}
        </p>
        {!binDabei && !abgeschlossen && (
          <button className="haupt" style={{ width: '100%', marginTop: '.75rem' }}
                  onClick={async () => {
                    const { error } = await supabase.from('auftrag_teilnehmer')
                      .insert({ auftrag_id: auftragId })
                    if (error) setFehler(fehlerText(error)); else void laden()
                  }}>
            Diesem Auftrag beitreten
          </button>
        )}
      </Karte>

      <nav className="navleiste" style={{ position: 'static', borderRadius: 'var(--radius)',
                                          border: '1px solid var(--rand)' }}>
        {reiterListe.map(([r, name]) => (
          <a key={r} href="#" className={reiter === r ? 'aktiv' : ''}
             onClick={e => { e.preventDefault(); setReiter(r) }}>{name}</a>
        ))}
      </nav>

      {abgeschlossen && <Hinweis>Dieser Auftrag ist abgeschlossen. Neue Erfassungen sind gesperrt.</Hinweis>}

      {reiter === 'paletten' && <Paletten auftrag={auftrag} gesperrt={abgeschlossen} />}
      {reiter === 'faule' && <Faule auftrag={auftrag} gesperrt={abgeschlossen} />}
      {reiter === 'ausschuss' && <Ausschuss auftrag={auftrag} gesperrt={abgeschlossen} />}
      {reiter === 'wiegen' && <Wiegen auftrag={auftrag} gesperrt={abgeschlossen} />}
      {reiter === 'marge' && <Ueberfuellung auftrag={auftrag} gesperrt={abgeschlossen} />}
      {reiter === 'abschluss' && (
        <Abschluss auftrag={auftrag} neuLaden={laden} zurueck={() => navigate('/auftraege')} />
      )}
    </>
  )
}

/* ------------------------------------------------------------------ */
/* Paletten zählen — das einzige Pflichtfeld (Spec §10)               */
/* ------------------------------------------------------------------ */
function Paletten({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const [zeilen, setZeilen] = useState<{ id: number; eingangsdatum: string | null; ts: string }[]>([])
  const [zettelDatum, setZettelDatum] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  const laden = useCallback(async () => {
    const { data, error } = await supabase.from('auftrag_palette')
      .select('id, eingangsdatum, ts').eq('auftrag_id', auftrag.id).order('ts')
    if (error) setFehler(fehlerText(error))
    else setZeilen(data as typeof zeilen)
  }, [auftrag.id])
  useEffect(() => { void laden() }, [laden])

  async function hinzu() {
    setLaeuft(true)
    const { error } = await supabase.from('auftrag_palette').insert({
      auftrag_id: auftrag.id, eingangsdatum: zettelDatum || null,
    })
    setLaeuft(false)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  async function zurueck() {
    const letzte = zeilen[zeilen.length - 1]
    if (!letzte) return
    const { error } = await supabase.from('auftrag_palette').delete().eq('id', letzte.id)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  const ohneDatum = zeilen.filter(z => !z.eingangsdatum).length

  return (
    <Karte titel="Paletten zählen">
      <p className="leise">
        Jede Palette einmal antippen. Das Eingangsdatum vom Zettel ist freiwillig —
        mit Datum wird die Lagerdauer genau, ohne Datum rechnet die Auswertung mit
        dem Durchschnitt der Charge.
      </p>

      <div className="zaehler">
        <button onClick={zurueck} disabled={gesperrt || zeilen.length === 0} aria-label="Eine zurück">−</button>
        <span className="stand">{zeilen.length}</span>
        <button className="haupt" onClick={hinzu} disabled={gesperrt || laeuft} aria-label="Palette dazu">+</button>
      </div>

      <div className="feld">
        <label htmlFor="zettel">Eingangsdatum vom Zettel (gilt für die nächste Palette)</label>
        <input id="zettel" type="date" value={zettelDatum} disabled={gesperrt}
               onChange={e => setZettelDatum(e.target.value)} />
      </div>

      {auftrag.geplante_paletten !== null && (
        <p className="leise">Geplant waren {auftrag.geplante_paletten} Paletten.</p>
      )}
      {ohneDatum > 0 && (
        <p className="leise">{ohneDatum} von {zeilen.length} ohne Eingangsdatum erfasst.</p>
      )}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
    </Karte>
  )
}

/* ------------------------------------------------------------------ */
/* Schimmel — klein genug, um direkt gewogen zu werden                */
/* ------------------------------------------------------------------ */
function Faule({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  return (
    <MengenErfassung
      auftrag={auftrag} gesperrt={gesperrt}
      tabelle="schimmel_messung" titel="Faule Kürbisse (Palox wiegen)"
      erklaerung="Am Ende des Auftrags den vollen Palox wiegen und die Kilo eintragen.
                  Ist die Box zwischendurch voll, ein Teilgewicht erfassen und weitermachen."
      zusatz={{}} mitTeilgewicht
    />
  )
}

function Ausschuss({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const [art, setArt] = useState<'zu_klein' | 'zu_gross'>('zu_klein')
  return (
    <>
      <div className="reihe" style={{ marginTop: '1rem' }}>
        <button className={art === 'zu_klein' ? 'haupt' : ''} style={{ flex: 1 }}
                onClick={() => setArt('zu_klein')}>Zu klein (Verlust)</button>
        <button className={art === 'zu_gross' ? 'haupt' : ''} style={{ flex: 1 }}
                onClick={() => setArt('zu_gross')}>Zu gross (anderer Kanal)</button>
      </div>
      <MengenErfassung
        key={art}
        auftrag={auftrag} gesperrt={gesperrt}
        tabelle="ausschuss_messung"
        titel={art === 'zu_klein' ? 'Zu klein — weggeworfen' : 'Zu gross — Nebenkanal'}
        erklaerung={art === 'zu_klein'
          ? 'Unter der Sortengrenze und damit echter Verlust. Kiste oder Palox wiegen.'
          : 'Über 2000 g: geht in einen anderen Verkaufskanal und ist kein Verlust — '
            + 'wird getrennt im Marge-Buch geführt.'}
        zusatz={{ art }} filter={{ art }}
      />
    </>
  )
}

/** Gemeinsame Maske für alle kg-Messungen an einem Auftrag. */
function MengenErfassung({ auftrag, gesperrt, tabelle, titel, erklaerung, zusatz, filter, mitTeilgewicht }: {
  auftrag: Auftrag; gesperrt: boolean; tabelle: string; titel: string; erklaerung: ReactNode
  zusatz: Record<string, unknown>; filter?: Record<string, string>; mitTeilgewicht?: boolean
}) {
  const [zeilen, setZeilen] = useState<{ id: number; kg: number; ts: string; teilgewicht?: boolean }[]>([])
  const [wert, setWert] = useState('')
  const [teil, setTeil] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    let abfrage = supabase.from(tabelle).select('*').eq('auftrag_id', auftrag.id).order('ts')
    for (const [k, v] of Object.entries(filter ?? {})) abfrage = abfrage.eq(k, v)
    const { data, error } = await abfrage
    if (error) setFehler(fehlerText(error)); else setZeilen(data as typeof zeilen)
  }, [auftrag.id, tabelle, JSON.stringify(filter)])
  useEffect(() => { void laden() }, [laden])

  async function speichern() {
    const n = Number(wert)
    if (!Number.isInteger(n) || n < 0) { setFehler('Bitte ganze Kilogramm eintragen.'); return }
    const { error } = await supabase.from(tabelle).insert({
      auftrag_id: auftrag.id, kg: n, ...zusatz, ...(mitTeilgewicht ? { teilgewicht: teil } : {}),
    })
    if (error) { setFehler(fehlerText(error)); return }
    setWert(''); setTeil(false); setFehler(null); void laden()
  }

  const summe = zeilen.reduce((s, z) => s + z.kg, 0)

  return (
    <Karte titel={titel}>
      <p className="leise">{erklaerung}</p>
      <div className="reihe" style={{ alignItems: 'flex-end' }}>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor={`kg-${tabelle}`}>Kilogramm (ganze Zahl)</label>
          <input id={`kg-${tabelle}`} type="number" inputMode="numeric" min={0} step={1}
                 value={wert} disabled={gesperrt} onChange={e => setWert(e.target.value)} />
        </div>
        <button className="haupt" onClick={speichern} disabled={gesperrt || wert === ''}>Erfassen</button>
      </div>
      {mitTeilgewicht && (
        <label style={{ display: 'flex', gap: '.5rem', alignItems: 'center', marginTop: '.6rem' }}>
          <input type="checkbox" checked={teil} disabled={gesperrt}
                 onChange={e => setTeil(e.target.checked)} style={{ width: 22, height: 22, minHeight: 0 }} />
          Teilgewicht — die Box war voll, es geht weiter
        </label>
      )}

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      {zeilen.length > 0 && (
        <>
          <p style={{ marginTop: '1rem' }}><strong>Bisher: {kg(summe)}</strong> aus {zeilen.length} Wägungen</p>
          <div className="rollbar">
            <table>
              <thead><tr><th>Zeit</th><th className="zahl">kg</th><th /></tr></thead>
              <tbody>
                {zeilen.map(z => (
                  <tr key={z.id}>
                    <td>{zeitpunkt(z.ts)}{z.teilgewicht ? ' · Teilgewicht' : ''}</td>
                    <td className="zahl">{zahl(z.kg)}</td>
                    <td style={{ textAlign: 'right' }}>
                      <button className="gefahr" style={{ minHeight: 32, padding: '.2rem .5rem' }}
                              disabled={gesperrt}
                              onClick={async () => {
                                const { error } = await supabase.from(tabelle).delete().eq('id', z.id)
                                if (error) setFehler(fehlerText(error)); else void laden()
                              }}>
                        löschen
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </Karte>
  )
}

/* ------------------------------------------------------------------ */
/* Verdunstung — der beste Messpunkt ist Weg 2 vor dem Wasserbecken   */
/* ------------------------------------------------------------------ */
interface PaletteZeile {
  id: number; eingangsdatum: string; brutto_kg: number
  kisten: number | null; gebindeart: string | null
}

function Wiegen({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const [paletten, setPaletten] = useState<PaletteZeile[]>([])
  const [gebinde, setGebinde] = useState<Gebinde[]>([])
  const [palettenId, setPalettenId] = useState<number | ''>('')
  const [jetzt, setJetzt] = useState('')
  const [schimmel, setSchimmel] = useState(false)
  const [zeilen, setZeilen] = useState<{ id: number; brutto_damals_kg: number; brutto_jetzt_kg: number
    eingangsdatum: string; wiege_ts: string; sichtbar_schimmel: boolean }[]>([])
  const [fehler, setFehler] = useState<string | null>(null)
  const [meldung, setMeldung] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const [p, w, s] = await Promise.all([
      supabase.from('palette').select('id, eingangsdatum, brutto_kg, kisten, gebindeart')
        .eq('charge_nr', auftrag.charge_nr).order('eingangsdatum'),
      supabase.from('verdunstung_wiegung').select('*').eq('auftrag_id', auftrag.id).order('wiege_ts'),
      stammdaten(),
    ])
    setPaletten((p.data ?? []) as PaletteZeile[])
    setZeilen((w.data ?? []) as typeof zeilen)
    setGebinde(s.gebinde)
  }, [auftrag.id, auftrag.charge_nr])
  useEffect(() => { void laden() }, [laden])

  const gewaehlt = paletten.find(p => p.id === palettenId)
  const taraFehlt = gewaehlt
    && !gebinde.find(g => g.art === gewaehlt.gebindeart)?.tara_kg_pro_kiste

  async function speichern() {
    if (!gewaehlt || jetzt === '') return
    const { error } = await supabase.from('verdunstung_wiegung').insert({
      auftrag_id: auftrag.id,
      charge_nr: auftrag.charge_nr,
      palette_id: gewaehlt.id,
      eingangsdatum: gewaehlt.eingangsdatum,
      brutto_damals_kg: gewaehlt.brutto_kg,
      brutto_jetzt_kg: Number(jetzt),
      kisten: gewaehlt.kisten,
      gebindeart: gewaehlt.gebindeart,
      sichtbar_schimmel: schimmel,
    })
    if (error) { setFehler(fehlerText(error)); return }
    setJetzt(''); setPalettenId(''); setSchimmel(false); setFehler(null)
    setMeldung('Wägung erfasst.')
    void laden()
  }

  if (paletten.length === 0) {
    return (
      <Karte titel="Palette wiegen">
        <Hinweis art="warnung">
          Für diese Charge sind noch keine Eingangspaletten importiert. Ohne das
          Eingangsgewicht lässt sich keine Verdunstung berechnen — der Import aus
          dem Erntejournal fehlt noch.
        </Hinweis>
      </Karte>
    )
  }

  return (
    <Karte titel="Palette wiegen (Verdunstung)">
      <p className="leise">
        Freiwillig, aber die wertvollste Messung überhaupt: dieselbe Palette einmal
        beim Eingang und einmal jetzt. Am besten beim Herausholen aus dem Lager,
        vor dem Wasserbecken.
      </p>

      <div className="feld">
        <label htmlFor="pal">Welche Palette?</label>
        <select id="pal" value={palettenId} disabled={gesperrt}
                onChange={e => setPalettenId(e.target.value === '' ? '' : Number(e.target.value))}>
          <option value="">— wählen —</option>
          {paletten.map(p => (
            <option key={p.id} value={p.id}>
              {datum(p.eingangsdatum)} · {kg(p.brutto_kg, 1)} brutto
              {p.kisten !== null && ` · ${p.kisten} Kisten`}
            </option>
          ))}
        </select>
      </div>

      {gewaehlt && (
        <p className="leise">
          Eingang {datum(gewaehlt.eingangsdatum)} mit {kg(gewaehlt.brutto_kg, 1)} brutto
          {' '}({Math.round((Date.now() - new Date(gewaehlt.eingangsdatum).getTime()) / 86400000)} Tage her).
        </p>
      )}
      {taraFehlt && (
        <Hinweis art="warnung">
          Für die Gebindeart „{gewaehlt?.gebindeart ?? '—'}" ist keine Tara hinterlegt.
          Die Wägung wird gespeichert, fließt aber erst in die Auswertung ein, wenn
          der Betriebsleiter unter Stammdaten das Leergewicht einträgt.
        </Hinweis>
      )}

      <div className="reihe" style={{ alignItems: 'flex-end' }}>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor="jetzt">Bruttogewicht jetzt (kg)</label>
          <input id="jetzt" type="number" inputMode="decimal" step="0.1" min={0}
                 value={jetzt} disabled={gesperrt || !gewaehlt}
                 onChange={e => setJetzt(e.target.value)} />
        </div>
        <button className="haupt" onClick={speichern} disabled={gesperrt || !gewaehlt || jetzt === ''}>
          Erfassen
        </button>
      </div>

      <label style={{ display: 'flex', gap: '.5rem', alignItems: 'center', marginTop: '.6rem' }}>
        <input type="checkbox" checked={schimmel} disabled={gesperrt}
               onChange={e => setSchimmel(e.target.checked)} style={{ width: 22, height: 22, minHeight: 0 }} />
        Sichtbar Faules auf der Palette
      </label>
      <p className="leise" style={{ marginTop: '.3rem' }}>
        Angekreuzt zählt die Wägung nicht in die Verdunstungsrate — sonst würde
        Fäulnis als Wasserverlust verbucht.
      </p>

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {meldung && <Hinweis art="gut">{meldung}</Hinweis>}

      {zeilen.length > 0 && (
        <div className="rollbar" style={{ marginTop: '1rem' }}>
          <table>
            <thead><tr><th>Eingang</th><th className="zahl">damals</th>
              <th className="zahl">jetzt</th><th className="zahl">Verlust</th></tr></thead>
            <tbody>
              {zeilen.map(z => (
                <tr key={z.id}>
                  <td>{datum(z.eingangsdatum)}{z.sichtbar_schimmel ? ' ⚠' : ''}</td>
                  <td className="zahl">{kg(z.brutto_damals_kg, 1)}</td>
                  <td className="zahl">{kg(z.brutto_jetzt_kg, 1)}</td>
                  <td className="zahl">{kg(z.brutto_damals_kg - z.brutto_jetzt_kg, 1)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Karte>
  )
}

/* ------------------------------------------------------------------ */
/* Überfüllung — Buch B, kein Verlust                                 */
/* ------------------------------------------------------------------ */
function Ueberfuellung({ auftrag, gesperrt }: { auftrag: Auftrag; gesperrt: boolean }) {
  const [kisten, setKisten] = useState('')
  const [gewicht, setGewicht] = useState('')
  const [zeilen, setZeilen] = useState<{ id: number; wert: number; n_kisten: number | null; ts: string }[]>([])
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const { data } = await supabase.from('marge_messung').select('*')
      .eq('auftrag_id', auftrag.id).eq('art', 'ueberfuellung').order('ts')
    setZeilen((data ?? []) as typeof zeilen)
  }, [auftrag.id])
  useEffect(() => { void laden() }, [laden])

  const n = Number(kisten)
  const g = Number(gewicht)
  // Der Arbeiter wiegt n volle Kisten. Verschenkt ist alles über n · 8 kg.
  const ueberschuss = n > 0 && g > 0 ? g - n * 8 : null

  async function speichern() {
    if (ueberschuss === null) return
    const { error } = await supabase.from('marge_messung').insert({
      auftrag_id: auftrag.id, art: 'ueberfuellung', wert: ueberschuss, n_kisten: n,
    })
    if (error) { setFehler(fehlerText(error)); return }
    setKisten(''); setGewicht(''); setFehler(null); void laden()
  }

  const summe = zeilen.reduce((s, z) => s + z.wert, 0)
  const kistenGesamt = zeilen.reduce((s, z) => s + (z.n_kisten ?? 0), 0)

  return (
    <Karte titel="Überfüllung der 8-kg-Kisten">
      <p className="leise">
        Bezahlt wird ein Fixpreis je Kiste ab 8 kg — alles darüber ist verschenkte Ware.
        Ein paar fertige Kisten zusammen wiegen und beides eintragen.
      </p>
      <div className="reihe" style={{ alignItems: 'flex-end' }}>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor="nk">Anzahl Kisten</label>
          <input id="nk" type="number" inputMode="numeric" min={1} value={kisten}
                 disabled={gesperrt} onChange={e => setKisten(e.target.value)} />
        </div>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor="gw">Gewicht zusammen (kg)</label>
          <input id="gw" type="number" inputMode="decimal" step="0.1" min={0} value={gewicht}
                 disabled={gesperrt} onChange={e => setGewicht(e.target.value)} />
        </div>
      </div>
      {ueberschuss !== null && (
        <p style={{ marginTop: '.6rem' }}>
          Das sind <strong>{kg(g / n, 2)} je Kiste</strong> — {kg(ueberschuss, 2)} über dem Soll
          {ueberschuss < 0 && ' (unter 8 kg!)'}
        </p>
      )}
      <button className="haupt" style={{ width: '100%', marginTop: '.5rem' }}
              onClick={speichern} disabled={gesperrt || ueberschuss === null}>
        Erfassen
      </button>

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {zeilen.length > 0 && (
        <p style={{ marginTop: '1rem' }}>
          Bisher {kg(summe, 1)} Überschuss auf {kistenGesamt} Kisten
          {kistenGesamt > 0 && ` — im Schnitt ${kg(summe / kistenGesamt, 2)} je Kiste`}.
        </p>
      )}
    </Karte>
  )
}

/* ------------------------------------------------------------------ */
/* Abschluss                                                          */
/* ------------------------------------------------------------------ */
function Abschluss({ auftrag, neuLaden, zurueck }: {
  auftrag: Auftrag; neuLaden: () => Promise<void>; zurueck: () => void
}) {
  const [sicher, setSicher] = useState(false)
  const [durchsatz, setDurchsatz] = useState(auftrag.durchsatz_kg?.toString() ?? '')
  const [bemerkung, setBemerkung] = useState(auftrag.bemerkung ?? '')
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  // Beim Waschen auf Weg 1 sind die Original-Paletten längst aufgelöst; ohne
  // eine Mengenangabe hätte der hier gemessene Schimmel keinen Nenner.
  const brauchtDurchsatz = auftrag.weg === 'maschine' && auftrag.station === 'waschen'

  async function speichern(abschliessen: boolean) {
    setLaeuft(true)
    const { error } = await supabase.from('auftrag').update({
      durchsatz_kg: durchsatz === '' ? null : Number(durchsatz),
      bemerkung: bemerkung || null,
      ...(abschliessen ? { status: 'abgeschlossen', ende_ts: new Date().toISOString() } : {}),
    }).eq('id', auftrag.id)
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    await neuLaden()
    if (abschliessen) zurueck()
  }

  if (auftrag.status === 'abgeschlossen') {
    return (
      <Karte titel="Abschluss">
        <p>Abgeschlossen am {zeitpunkt(auftrag.ende_ts)}.</p>
        {auftrag.bemerkung && <p className="leise">{auftrag.bemerkung}</p>}
      </Karte>
    )
  }

  return (
    <Karte titel="Auftrag abschließen">
      {brauchtDurchsatz && (
        <div className="feld">
          <label htmlFor="ds">Verarbeitete Menge (kg)</label>
          <input id="ds" type="number" inputMode="decimal" step="1" min={0} value={durchsatz}
                 onChange={e => setDurchsatz(e.target.value)} />
          <p className="leise" style={{ marginTop: '.3rem' }}>
            Beim Waschen gibt es keine Paletten mehr zu zählen. Ohne diese Angabe
            lässt sich der hier ausgelesene Schimmel nicht ins Verhältnis setzen.
          </p>
        </div>
      )}

      <div className="feld">
        <label htmlFor="bem">Bemerkung (optional)</label>
        <textarea id="bem" rows={3} value={bemerkung} onChange={e => setBemerkung(e.target.value)} />
      </div>

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}

      <button style={{ width: '100%' }} onClick={() => speichern(false)} disabled={laeuft}>
        Zwischenstand speichern
      </button>

      {!sicher ? (
        <button className="haupt" style={{ width: '100%', marginTop: '.5rem' }}
                onClick={() => setSicher(true)}>
          Auftrag abschließen?
        </button>
      ) : (
        <div className="reihe" style={{ marginTop: '.5rem' }}>
          <button className="haupt" style={{ flex: 1 }} onClick={() => speichern(true)} disabled={laeuft}>
            Sicher? Ja, abschließen
          </button>
          <button onClick={() => setSicher(false)}>Doch nicht</button>
        </div>
      )}
    </Karte>
  )
}
